# appJPA — Jampac CRM (Saúde de Carteira)

App web interno da Jampac para gestão comercial / retenção de carteira. **Single-page app** num único arquivo `index.html` (HTML + CSS + JS inline, ~3350 linhas). Sem build, sem framework. Bibliotecas via CDN: **XLSX** (importação de planilhas) e **Lucide Icons** (ícones SVG).

> **Este README também serve de handoff entre sessões do Claude Code.** Se a janela de contexto estourar, uma nova sessão deve ler este arquivo inteiro para retomar o trabalho. A seção **"Correções pendentes"** é o checklist vivo do que falta.

---

## Arquitetura & Workflow

- **Arquivo único:** `index.html`. Bloco `<script>` começa na linha ~1099.
- **Persistência:** `localStorage` (imediato) + **Supabase** (REST, assíncrono).
- **Supabase:** projeto `ldmdfjnieohrjvyselnz`. URL e chave `anon` ficam hardcoded no topo do `<script>` (`SUPABASE_URL`, `SUPABASE_KEY`). Schema completo em **`supabase_setup.sql`** (rodar no SQL Editor do Supabase; é idempotente).
- **Login:** perfil **Gestor** (senha fallback `jampacg`) ou **Vendedor** (cadastrado em Administração → tabela `usuarios`). Vendedor vê só sua carteira.

### Git / Deploy
- **Branch de desenvolvimento:** `claude/blissful-wright-pb19fm`. Commitar e pushar nela.
- **Deploy = merge na `main`.** Sempre que terminar uma leva de mudanças: `git checkout main && git pull && git merge <branch> && git push origin main`, depois voltar pra branch. (O usuário pediu: "sempre faça deploy para a main quando terminar".)
- Mensagens de commit em PT-BR, terminando com a URL da sessão. **Não** incluir identificador de modelo em nada commitado.

---

## Modelo de Dados (em memória)

### `clientes[]` — fonte primária da UI
```
{ id, codigo, nome, vendedor,
  status,                       // status "display" (do mês atual ou TOTAL)
  statusHistorico: {mesKey: status},   // ex: {"jun/2026":"Retido","mai/2026":"Não Retido"}
  statusTotal,                  // coluna TOTAL da planilha de Histórico Anual
  ultimaCompra,                 // string dd/mm/aaaa (HOJE vem do Campo A, só mês atual — BUG)
  semana,
  entrepostos: { EN: { ultimaCompra, date, meses:{mesKey:count} } },  // EN ∈ {ITP,JPA,KRC,SUL}
  justificativa: {motivo,submotivo,obs,data},
  classificacao: {tipo,obs,justProcesso},
  tratativa: {desfecho,obs,data},
  capcobObs, historico }
```

### Estruturas brutas de importação (só em memória, no gestor que importou)
- **`baseRetencaoRaw`** (Campo A — "Base Retenção", planilha por linha de NF):
  - `clientData[code]` = só registros do **mês atual** → `{code,name,vendedor,entrepostos:{EN:{date,ultimaCompra,meses}}}`
  - `allClientData[code]` = **todos os meses** do ano → `{code,name,vendedor}`
  - `vendorClientMap['nome_lower']` = `Set<codigo>` (todos os meses)
  - Importação lê colunas: `CODIGO_CLIENTE, VENDEDOR_CLIENTE, NOME_CLIENTE, ENTREPOSTO, DATA_ENTREGA, MES, ANO`. **⚠️ Hoje usa `DATA_ENTREGA`; o cliente quer a `DATA_EMISSÃO da NF` para o cálculo de dias sem compra.** Confirmar nome exato da coluna na planilha.
- **`historicoAnualRaw`** (Campo B — "Histórico Anual por Vendedor"):
  - `clients[code]` = `{code,name,history:{mes:status},statusAtual,vendedorTitular,recencyScore}`
  - `months[]`, `colMesAtual`, `colMesAnterior`, `titularMap`
  - Mês atual é detectado por `new Date()` comparando com os cabeçalhos `mmm/aaaa` da planilha.
- **`positivacaoAtualCache`** = `{count, ts, vendorData:{vkey:{mes,ano}}}`. **⚠️ `count` guarda só o total do MÊS** (não do ano) — origem do bug de "Total de Atendimentos".

### Status & regras
- `STATUS_POSITIVOS = ['Capt./Cob.','Recuperado','Retido']`.
- `normalizeStatus()` normaliza variações. `calcDias(ultimaCompra)` → dias desde última compra (999 = sem data).
- `riscoDias(dias)`: 0–10 Baixo / 11–20 Médio / 21–30 Alto / 31–40 Gravíssimo / 40+ Perda.

---

## Mapa de funções (linhas aproximadas — podem deslocar após edições)
- `renderDash()` ~2238 — KPIs do dashboard (Positivação, Total Atendimentos, Retidos/Não Retidos/Capt-Cob/Recuperados, risco, gráficos).
- `kpi-total-acum` (Total de Atendimentos) calculado ~2310-2335; escrito ~2370.
- `crossReferenceAndBuild()` ~2021 — monta `clientes[]` a partir de Campo A + Campo B; chama `saveAll()`.
- `processarBaseRetencao()` ~1700 / `processarHistoricoAnual()` ~1810 — parsing das planilhas.
- `renderClientes()` ~2748 — tabela Carteira (entrepostos, últ. compra, risco, ações).
- `renderProcessoRetencao()` ~2898 / `renderObsCoord()` ~2917.
- `openClienteModal(id)` ~2953 — modal detalhe do cliente.
- `renderRanking()` ~3112 / `renderGestores()` (Por Vendedor).
- `atualizarBadgeEmProcesso()` — badges da sidebar (`emProcessoCount`, `emProcessoCountObs`).
- Helpers: `calcDias` 1516, `riscoDias` 1530, `riscoBadge` 1538, `getClientesFiltrados` 1544, `comprouNoMes` (~1265), `getMesAtualKey`/`getMesAnteriorKey`.
- Constantes a editar: `SUBMOTIVOS` (~1236, motivos de justificativa), opções de classificação no `<select>` (~1018-1026) e em `classBadgeHtml`/mapa de labels (~1505-1514).

---

## Correções pendentes (checklist) — pedido do cliente

### DASHBOARD
- [ ] **Total de Atendimentos**: mostrar acumulado do **ANO** (clientes únicos atendidos no ano), não do mês. Hoje mostra 178 (mês). Causa: `positivacaoAtualCache.count` guarda só o mês; persistir/usar contagem anual (`allClientData`).
- [ ] **Retidos** = clientes do total que **compraram no mês atual**.
- [ ] **Não Retidos** = clientes que compraram no **mês anterior** mas **ainda não** no mês atual.
- [ ] **Captação ou Cobertura** = clientes do Histórico Anual com status Captação/Cobertura **do mês atual**.
- [ ] **Recuperados** = clientes do Histórico Anual com status Recuperado **do mês atual**.
- [ ] **Pizza "Clientes por Entreposto — Mês Atual"** = dividir por entreposto da **Base Retenção** (mês atual).
- [ ] **Pizza "Mês Anterior"** = mesma lógica, mês anterior.
- [ ] **Risco por Dias Sem Compras** = pela **Base Retenção**: dias desde a última compra (qualquer entreposto), usando **DATA EMISSÃO da NF** como base.
- [ ] **Histórico de Positivações**: **janeiro não funciona** — investigar iteração/detecção de meses.

### CARTEIRA
- [ ] **Bug visual**: ao abrir a página ela desce ~200px em vez de abrir no topo (provável `scrollIntoView`/foco em input). Corrigir.
- [ ] **Sequência** (seq-bar): "1. Classificar → 2. Justificar não Recompra → 3. Concluir Tratativa".
- [ ] **Risco por Dias Sem Compras**: igual ao dashboard (Base Retenção / Data Emissão).
- [ ] **Coluna ENTREPOSTOS** (3 estados): comprou no **mês atual** naquele entreposto → **verde**; comprou no **ano** mas não naquele entreposto no mês atual → **amarelo**; **nunca** comprou naquele entreposto → mantém cor neutra.
- [ ] **ÚLT. COMPRA** não puxa data — corrigir (deve usar última compra do ano por Data Emissão, não só mês atual).
- [ ] **AÇÕES → Classificar**: remover "Cliente Oportunidade".
- [ ] **AÇÕES → Justificar**: nos motivos, **adicionar** "Financeiro"; **remover** os "Produção *" (JPA/ITP/SUL/KRC); **adicionar** "Não quis informar" e "Consumo Próprio".
- [ ] **Detalhe do cliente**: remover o campo/seção "Contatos".

### EM PROCESSO
- [ ] Bolha de notificação com **contador** de quantos clientes estão em Processo de Retenção (visualização rápida). [badge `emProcessoCount` já existe — garantir contador correto e visível.]
- [ ] No **detalhe do cliente**: trazer a **observação** dada na Justificativa do Processo de Retenção + a **classificação**.

### OBS. COORDENADOR
- [ ] Bolha de notificação com contador de quantas observações o Coordenador enviou para o Vendedor (**visão do vendedor**). Hoje o badge `emProcessoCountObs` usa contagem de processo — trocar para contar `obsCoord` destinadas ao vendedor logado.

### GESTÃO
- [ ] **Por Vendedor**: **REMOVER** a página/menu (`gestoresMenu`, page `gestores`, `renderGestores`).
- [ ] **Ranking**: remover colunas **Contatos** e **Pontos**.
- [ ] **Importar Excel**: remover o card de visualização **"Nova Lógica de Dados — v4"** (~linha 855).

---

## Convenções
- Ícones: usar helper `lc('nome', size)` (Lucide) em template literals JS, ou `<svg class="lc" ...>` inline no HTML estático. Indicadores coloridos de risco: `riskDot('#cor')`. **Não** reintroduzir emojis.
- Toda importação chama `saveAll()` → upsert nas tabelas Supabase + feedback "Sincronizado" via `mostrarSyncStatus()`.
- Após mudanças de lógica de dados, conferir sintaxe: extrair o `<script>` e rodar `node --check`.
