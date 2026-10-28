// Configuração do Caixa.
// A URL e a chave pública do Supabase ("publishable", sb_publishable_..., ou a antiga "anon")
// são públicas por natureza: quem protege os dados são as regras de Row Level Security
// do supabase/schema.sql. NUNCA coloque aqui a chave "secret" nem a "service_role".
window.CAIXA_CONFIG = {
  supabaseUrl: "https://kxsmnjwnbkqecewpdtev.supabase.co",
  supabaseAnonKey: "sb_publishable_8oXjesRNulu7ro5MM80ChA_L-Jzhorn",

  // Cartões de crédito. O "id" fica gravado nos lançamentos: escolha uma vez e não mude.
  cartoes: [
    { id: "santander", nome: "Cartão Santander" },
    { id: "nubank", nome: "Cartão Nubank" },
    { id: "emprestado", nome: "Cartão emprestado" }
  ],

  categorias: ["Alimentação", "Transporte", "Pessoal", "Lazer", "Compras", "Assinaturas", "Contas da casa", "Estudos", "Saúde", "Outros"],

  // Regras extras pra importar extrato: se a descrição contém o texto, usa a categoria.
  // Ex.: { contem: "ACADEMIA", categoria: "Saúde" }. Este arquivo é público: não coloque nomes de pessoas.
  regras: [],

  // Atalhos que aparecem acima do formulário. "v" (valor) e "c" (categoria) são opcionais.
  atalhos: {
    gasto: [
      { t: "iFood", d: "iFood", c: "Alimentação" },
      { t: "Mercado", d: "Mercado", c: "Alimentação" },
      { t: "Transporte", d: "Transporte", c: "Transporte" }
    ],
    entrada: [
      { t: "Salário", d: "Salário" },
      { t: "13º salário", d: "13º salário" }
    ]
  }
};
