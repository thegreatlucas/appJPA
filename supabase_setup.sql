-- =====================================================================
-- Jampac CRM — Setup do banco Supabase
-- Projeto: ldmdfjnieohrjvyselnz
-- Como usar: Supabase Dashboard -> SQL Editor -> New query -> cole tudo -> Run.
-- O script é IDEMPOTENTE: pode ser executado novamente sem quebrar nada.
--
-- Tabelas criadas (espelham exatamente o que o index.html lê/grava):
--   usuarios, clientes, contatos, justificativas, classificacoes,
--   tratativas, proc_retencao_hist, obs_coordenador, metas, positivacao_atual
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. USUÁRIOS  (login = chave; gestor/vendedor; senha em texto)
--    PK: login  -> usado no upsert merge-duplicates
-- ---------------------------------------------------------------------
create table if not exists public.usuarios (
  login      text primary key,
  senha      text,
  role       text not null default 'vendedor',   -- 'gestor' | 'vendedor'
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 2. CLIENTES (master da carteira)
--    PK: id  (id = codigo + '_' + vendedor, gerado pelo app)
-- ---------------------------------------------------------------------
create table if not exists public.clientes (
  id                text primary key,
  codigo            text,
  nome              text,
  vendedor          text default '',
  status            text,
  status_historico  jsonb default '{}'::jsonb,    -- { "jun/2026": "Retido", ... }
  status_total      text,
  ultima_compra     text,
  semana            text default '',
  entrepostos       jsonb default '{}'::jsonb,     -- { "JPA": { ultimaCompra, meses:{...} }, ... }
  atualizado_em     timestamptz not null default now()
);
create index if not exists idx_clientes_vendedor on public.clientes (vendedor);

-- ---------------------------------------------------------------------
-- 3. CONTATOS (registros de contato por cliente×vendedor)
--    PK: id
-- ---------------------------------------------------------------------
create table if not exists public.contatos (
  id          text primary key,
  cliente_id  text,
  vendedor    text default '',
  data        text,
  tipo        text,
  num         text,
  tentativas  text,
  status      text,
  motivo      text,
  dif         text,
  obs         text,
  criado_em   timestamptz not null default now()
);
create index if not exists idx_contatos_vendedor on public.contatos (vendedor);
create index if not exists idx_contatos_cliente  on public.contatos (cliente_id);

-- ---------------------------------------------------------------------
-- 4. JUSTIFICATIVAS (1 por cliente×vendedor)
--    PK composta: (cliente_id, vendedor) -> alvo do upsert merge-duplicates
-- ---------------------------------------------------------------------
create table if not exists public.justificativas (
  cliente_id     text not null,
  vendedor       text not null default '',
  motivo         text,
  submotivo      text,
  obs            text,
  data           text,
  atualizado_em  timestamptz not null default now(),
  primary key (cliente_id, vendedor)
);

-- ---------------------------------------------------------------------
-- 5. CLASSIFICACOES (1 por cliente×vendedor)
--    PK composta: (cliente_id, vendedor)
-- ---------------------------------------------------------------------
create table if not exists public.classificacoes (
  cliente_id     text not null,
  vendedor       text not null default '',
  tipo           text,
  obs            text,
  just_processo  text,
  atualizado_em  timestamptz not null default now(),
  primary key (cliente_id, vendedor)
);

-- ---------------------------------------------------------------------
-- 6. TRATATIVAS (1 por cliente×vendedor)
--    PK composta: (cliente_id, vendedor)
-- ---------------------------------------------------------------------
create table if not exists public.tratativas (
  cliente_id     text not null,
  vendedor       text not null default '',
  desfecho       text,
  obs            text,
  data           text,
  atualizado_em  timestamptz not null default now(),
  primary key (cliente_id, vendedor)
);

-- ---------------------------------------------------------------------
-- 7. PROC_RETENCAO_HIST (histórico de clientes recuperados)
--    PK: id
-- ---------------------------------------------------------------------
create table if not exists public.proc_retencao_hist (
  id                text primary key,
  cliente_id        text,
  nome              text,
  vendedor          text default '',
  data_recuperacao  text,
  criado_em         timestamptz not null default now()
);
create index if not exists idx_proc_ret_vendedor on public.proc_retencao_hist (vendedor);

-- ---------------------------------------------------------------------
-- 8. OBS_COORDENADOR (observações do gestor para o vendedor)
--    PK: id ; o app usa "data" e cai em "criado_em" como fallback
-- ---------------------------------------------------------------------
create table if not exists public.obs_coordenador (
  id             text primary key,
  de             text,
  vendedor_dest  text default '',
  cliente        text,
  texto          text,
  data           text,
  criado_em      timestamptz not null default now()
);
create index if not exists idx_obs_dest on public.obs_coordenador (vendedor_dest);

-- ---------------------------------------------------------------------
-- 9. METAS (meta de positivação por chave "vendedor_mes_ano")
--    PK: chave
-- ---------------------------------------------------------------------
create table if not exists public.metas (
  chave          text primary key,
  geral          integer default 0,
  jpa            integer default 0,
  sul            integer default 0,
  krc            integer default 0,
  itp            integer default 0,
  atualizado_em  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 10. POSITIVACAO_ATUAL (linha única, id = 'singleton')
--     Guarda contagem do mês atual, meses detectados e dados por vendedor.
--     PK: id   (upserts parciais atualizam só as colunas enviadas)
-- ---------------------------------------------------------------------
create table if not exists public.positivacao_atual (
  id               text primary key,
  count            integer default 0,    -- clientes distintos no MÊS atual (Base Retenção)
  count_ano        integer default 0,    -- clientes distintos no ANO (Total de Atendimentos)
  ts               text,                 -- ISO string gerada pelo app (versão dos dados)
  vendor_data      jsonb,                -- { "nome_vendedor": { mes, ano, mesAntEquiv }, ... }
  mes_atual        text,                 -- ex.: "jun/2026"
  mes_anterior     text,
  meses_historico  jsonb,                -- ["jan/2026", "fev/2026", ...]
  mes_ant_equiv    integer default 0,    -- positivação do mês anterior no mesmo dia útil
  label_equiv_ant  text,                 -- rótulo do comparativo equivalente (ex.: "até 6º dia útil")
  atualizado_em    timestamptz not null default now()
);
-- Migração p/ bancos já criados (adiciona colunas novas se faltarem)
alter table public.positivacao_atual add column if not exists count_ano       integer default 0;
alter table public.positivacao_atual add column if not exists mes_ant_equiv   integer default 0;
alter table public.positivacao_atual add column if not exists label_equiv_ant text;

-- =====================================================================
-- RLS + POLÍTICAS DE ACESSO
-- App interno: a chave publishable (role "anon") lê e grava direto do
-- navegador. Liberamos acesso total para anon/authenticated em todas as
-- tabelas. >>> Se um dia quiser restringir, troque o USING/WITH CHECK. <<<
-- =====================================================================
grant usage on schema public to anon, authenticated;

do $$
declare
  t text;
  tabelas text[] := array[
    'usuarios','clientes','contatos','justificativas','classificacoes',
    'tratativas','proc_retencao_hist','obs_coordenador','metas','positivacao_atual'
  ];
begin
  foreach t in array tabelas loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists "jampac_all_%1$s" on public.%1$I;', t);
    execute format(
      'create policy "jampac_all_%1$s" on public.%1$I for all to anon, authenticated using (true) with check (true);',
      t);
    execute format('grant all on public.%I to anon, authenticated, service_role;', t);
  end loop;
end $$;

-- Força o PostgREST a recarregar o schema (expõe as tabelas no REST na hora)
notify pgrst, 'reload schema';

-- =====================================================================
-- (OPCIONAL) SEED — credencial de gestor.
-- O app já aceita o gestor com a senha fixa 'jampacg' mesmo sem registro,
-- mas você pode criar/sobrescrever uma credencial de gestor aqui:
-- insert into public.usuarios (login, senha, role, ativo)
-- values ('Gestor', 'jampacg', 'gestor', true)
-- on conflict (login) do update set senha = excluded.senha, role = excluded.role, ativo = excluded.ativo;
--
-- Vendedores são cadastrados pelo próprio app em Administração.
-- =====================================================================

-- =====================================================================
-- (VERIFICAÇÃO) rode para conferir que tudo foi criado:
-- select table_name from information_schema.tables
--   where table_schema = 'public' order by table_name;
-- =====================================================================
