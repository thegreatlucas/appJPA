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

> ⚠️ As correções de lógica de dados (entrepostos/última compra/risco/total anual) **só têm efeito após o gestor RE-IMPORTAR** a Base Retenção, pois passam a guardar dados do ano inteiro (antes era só o mês). E rode o `supabase_setup.sql` atualizado (coluna `count_ano`).

### DASHBOARD
- [x] **Total de Atendimentos** = acumulado do ANO. Agora persistido como `countAno`/`count_ano` (Supabase) e usado nos fallbacks de `renderDash`.
- [x] **Retidos / Não Retidos / Capt./Cob. / Recuperados** = contagem por status da coluna do mês (Campo B), via `_contaStatus(colAtual)`. "Não Retido" = status do mês (comprou mês anterior, não no atual).
- [x] **Pizzas por Entreposto (mês atual / anterior)**: `renderChartEntr` agora escreve nos IDs corretos (`chartEntr2`/`chartEntrAnt2`) e usa dados do ano (mês atual e anterior funcionam).
- [x] **Risco por Dias Sem Compras** = Base Retenção, última compra do ano por **Data de Emissão da NF** (coluna detectada por "EMISS"; fallback "ENTREGA").
- [ ] **Histórico de Positivações — janeiro**: HIPÓTESE = janeiro costuma ter status "Start Compra" (1ª compra do ano), que NÃO conta como positivado → barra fica baixa/zerada. **Confirmar com o cliente** se "Start Compra" deve contar como positivação no 1º mês. (sem mudança feita)

### CARTEIRA
- [x] **Bug visual de scroll**: `goPage` reseta `.main` scrollTop=0.
- [x] **Sequência**: adicionado "3. Concluir Tratativa".
- [x] **Risco**: agora idêntico ao dashboard (mesma `ultimaCompra` anual).
- [x] **Coluna ENTREPOSTOS (3 estados)**: verde (mês atual) / amarelo `.entr-ano` (comprou no ano, não no mês) / neutro (nunca comprou).
- [x] **ÚLT. COMPRA**: corrigido — usa última compra do ano (Data Emissão).
- [x] **Classificar**: removido "Cliente Oportunidade".
- [x] **Justificar**: adicionado Financeiro / Não quis informar / Consumo Próprio; removidos os "Produção *".
- [x] **Detalhe do cliente**: removida seção "Contatos".

### EM PROCESSO
- [x] Badge contador (`emProcessoCount`) — clientes em processo de retenção.
- [x] Detalhe do cliente mostra a **Justificativa do Processo** (`classificacao.justProcesso`) + observação + classificação.

### OBS. COORDENADOR
- [x] Badge `emProcessoCountObs` conta observações do coordenador (visão vendedor = só as destinadas a ele).

### GESTÃO
- [x] **Por Vendedor**: página/menu removidos.
- [x] **Ranking**: removidas colunas Contatos e Pontos (ordena por Positivados).
- [x] **Importar Excel**: removido card "Nova Lógica de Dados — v4".

### Aberto / a confirmar
- Histórico de Positivações (janeiro) — ver hipótese acima.
- Confirmar o **nome exato da coluna de Data de Emissão da NF** na planilha (detecção atual procura "EMISS" no cabeçalho; se a coluna tiver outro nome, ajustar `_emissCol`).

---

## Convenções
- Ícones: usar helper `lc('nome', size)` (Lucide) em template literals JS, ou `<svg class="lc" ...>` inline no HTML estático. Indicadores coloridos de risco: `riskDot('#cor')`. **Não** reintroduzir emojis.
- Toda importação chama `saveAll()` → upsert nas tabelas Supabase + feedback "Sincronizado" via `mostrarSyncStatus()`.
- Após mudanças de lógica de dados, conferir sintaxe: extrair o `<script>` e rodar `node --check`.
