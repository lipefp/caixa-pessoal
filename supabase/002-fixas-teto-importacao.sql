-- Caixa: migração 002
-- Contas fixas (recorrentes), teto semanal (ajustes) e importação de extrato.
-- Rode este arquivo inteiro uma vez no SQL Editor, depois do schema.sql.

-- ---------------------------------------------------------------
-- Contas fixas
-- ---------------------------------------------------------------
create table if not exists public.recorrentes (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  nome       text not null check (char_length(nome) between 1 and 120),
  tipo       text not null default 'gasto' check (tipo in ('entrada', 'gasto', 'guardado')),
  valor      numeric(12, 2) not null check (valor > 0),
  dia        integer not null default 5 check (dia between 1 and 28),
  categoria  text check (char_length(categoria) <= 60),
  forma      text check (char_length(forma) <= 40),
  meta_id    uuid references public.metas (id) on delete set null,
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);
create index if not exists recorrentes_user_idx on public.recorrentes (user_id);

-- ---------------------------------------------------------------
-- Ajustes por usuário (teto semanal)
-- ---------------------------------------------------------------
create table if not exists public.ajustes (
  user_id       uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  teto_semanal  numeric(12, 2) check (teto_semanal >= 0),
  atualizado_em timestamptz not null default now()
);

-- ---------------------------------------------------------------
-- Novas colunas em lançamentos
-- ---------------------------------------------------------------
alter table public.lancamentos add column if not exists recorrente_id uuid;
alter table public.lancamentos add column if not exists import_ref text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'lancamentos_recorrente_fk') then
    alter table public.lancamentos
      add constraint lancamentos_recorrente_fk foreign key (recorrente_id) references public.recorrentes (id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'lancamentos_import_ref_len') then
    alter table public.lancamentos add constraint lancamentos_import_ref_len check (char_length(import_ref) <= 160);
  end if;
end $$;

-- ---------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------
alter table public.recorrentes enable row level security;
alter table public.ajustes enable row level security;

drop policy if exists "recorrentes: dono le" on public.recorrentes;
drop policy if exists "recorrentes: dono cria" on public.recorrentes;
drop policy if exists "recorrentes: dono altera" on public.recorrentes;
drop policy if exists "recorrentes: dono apaga" on public.recorrentes;
create policy "recorrentes: dono le"     on public.recorrentes for select to authenticated using ((select auth.uid()) = user_id);
create policy "recorrentes: dono cria"   on public.recorrentes for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "recorrentes: dono altera" on public.recorrentes for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "recorrentes: dono apaga"  on public.recorrentes for delete to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "ajustes: dono le" on public.ajustes;
drop policy if exists "ajustes: dono cria" on public.ajustes;
drop policy if exists "ajustes: dono altera" on public.ajustes;
create policy "ajustes: dono le"     on public.ajustes for select to authenticated using ((select auth.uid()) = user_id);
create policy "ajustes: dono cria"   on public.ajustes for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "ajustes: dono altera" on public.ajustes for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- A meta de uma conta fixa precisa ser do mesmo dono (reaproveita a função do schema.sql).
drop trigger if exists recorrente_meta_do_dono on public.recorrentes;
create trigger recorrente_meta_do_dono
  before insert or update on public.recorrentes
  for each row execute function public.lancamento_meta_do_dono();

-- Um lançamento só pode apontar para uma conta fixa do mesmo dono.
create or replace function public.lancamento_recorrente_do_dono()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.recorrente_id is not null and not exists (
    select 1 from public.recorrentes r where r.id = new.recorrente_id and r.user_id = new.user_id
  ) then
    raise exception 'recorrente_id não pertence a este usuário';
  end if;
  return new;
end;
$$;

drop trigger if exists lancamento_recorrente_do_dono on public.lancamentos;
create trigger lancamento_recorrente_do_dono
  before insert or update on public.lancamentos
  for each row execute function public.lancamento_recorrente_do_dono();

-- Tempo real
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'recorrentes') then
    alter publication supabase_realtime add table public.recorrentes;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'ajustes') then
    alter publication supabase_realtime add table public.ajustes;
  end if;
end $$;
