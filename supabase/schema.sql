-- Caixa: esquema do banco (Supabase / PostgreSQL)
-- Rode este arquivo inteiro uma vez no SQL Editor do Supabase.
--
-- Segurança: as duas tabelas usam Row Level Security (RLS).
-- Cada linha guarda o dono em user_id, e as políticas abaixo só deixam
-- o usuário logado ler e gravar as próprias linhas. A chave pública
-- (anon key) que vai no front não dá acesso a nada sem login.

-- ---------------------------------------------------------------
-- Metas
-- ---------------------------------------------------------------
create table if not exists public.metas (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  nome       text not null check (char_length(nome) between 1 and 120),
  alvo       numeric(12, 2) not null default 0 check (alvo >= 0),
  inicial    numeric(12, 2) not null default 0 check (inicial >= 0),
  prazo      text check (prazo ~ '^\d{4}-\d{2}$'),          -- mês no formato AAAA-MM
  status     text not null default 'ativa' check (status in ('ativa', 'pausada', 'concluida')),
  ordem      integer not null default 0,
  nota       text check (char_length(nota) <= 500),
  sugestao   numeric(12, 2) check (sugestao > 0),           -- valor sugerido no atalho "Guardar"
  criado_em  timestamptz not null default now()
);

-- ---------------------------------------------------------------
-- Lançamentos
-- tipo:  entrada | gasto | guardado (vai para uma meta) | fatura (pagamento de fatura)
-- forma: 'conta' para Pix/débito, ou o id de um cartão definido no config.js
-- ---------------------------------------------------------------
create table if not exists public.lancamentos (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  tipo       text not null check (tipo in ('entrada', 'gasto', 'guardado', 'fatura')),
  valor      numeric(12, 2) not null check (valor > 0),
  data       date not null,
  descricao  text check (char_length(descricao) <= 200),
  categoria  text check (char_length(categoria) <= 60),
  forma      text check (char_length(forma) <= 40),
  cartao     text check (char_length(cartao) <= 40),
  meta_id    uuid references public.metas (id) on delete set null,
  grupo      text check (char_length(grupo) <= 40),         -- liga as parcelas de uma mesma compra
  parcela    integer check (parcela >= 1),
  parcelas   integer check (parcelas >= 1 and parcelas <= 48),
  base       text check (char_length(base) <= 200),         -- descrição sem o "(3/10)"
  criado_em  timestamptz not null default now()
);

create index if not exists lancamentos_user_data_idx on public.lancamentos (user_id, data);
create index if not exists metas_user_ordem_idx on public.metas (user_id, ordem);

-- ---------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------
alter table public.metas enable row level security;
alter table public.lancamentos enable row level security;

drop policy if exists "metas: dono le" on public.metas;
drop policy if exists "metas: dono cria" on public.metas;
drop policy if exists "metas: dono altera" on public.metas;
drop policy if exists "metas: dono apaga" on public.metas;

create policy "metas: dono le"     on public.metas for select to authenticated using ((select auth.uid()) = user_id);
create policy "metas: dono cria"   on public.metas for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "metas: dono altera" on public.metas for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "metas: dono apaga"  on public.metas for delete to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "lancamentos: dono le" on public.lancamentos;
drop policy if exists "lancamentos: dono cria" on public.lancamentos;
drop policy if exists "lancamentos: dono altera" on public.lancamentos;
drop policy if exists "lancamentos: dono apaga" on public.lancamentos;

create policy "lancamentos: dono le"     on public.lancamentos for select to authenticated using ((select auth.uid()) = user_id);
create policy "lancamentos: dono cria"   on public.lancamentos for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "lancamentos: dono altera" on public.lancamentos for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "lancamentos: dono apaga"  on public.lancamentos for delete to authenticated using ((select auth.uid()) = user_id);

-- Um lançamento só pode apontar para uma meta do mesmo dono.
create or replace function public.lancamento_meta_do_dono()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.meta_id is not null and not exists (
    select 1 from public.metas m where m.id = new.meta_id and m.user_id = new.user_id
  ) then
    raise exception 'meta_id não pertence a este usuário';
  end if;
  return new;
end;
$$;

drop trigger if exists lancamento_meta_do_dono on public.lancamentos;
create trigger lancamento_meta_do_dono
  before insert or update on public.lancamentos
  for each row execute function public.lancamento_meta_do_dono();

-- ---------------------------------------------------------------
-- Tempo real (o app atualiza sozinho no celular e no PC)
-- ---------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'lancamentos') then
    alter publication supabase_realtime add table public.lancamentos;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'metas') then
    alter publication supabase_realtime add table public.metas;
  end if;
end $$;
