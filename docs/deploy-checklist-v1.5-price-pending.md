# Deploy e testes — V1.5 (`logical_item_id`) + V1 (artigo sem preço)

Guia passo-a-passo: **o que fazer**, **onde clicar**, **o que deves ver** e **como saber se passou ou falhou**.

---

## Estado da bateria L1–L18 — **FECHADA** (Jun 2026)

**Script automático:** `dart run tool/live_logical_item_id_check.dart` → **12 PASS · 0 FAIL · 6 SKIP**  
Os 6 SKIP (UI/fluxo manual) foram confirmados em testes manuais na mesma sessão.

| Teste | Método | Resultado |
| ----- | ------ | --------- |
| L1–L6 | Automático | ✅ PASS |
| L7 / L8 | Manual (sheet: badges, foto, preço, scroll) | ✅ PASS |
| L9 | Manual (novo prep → sheet reaparece) | ✅ PASS |
| L10 / L11 | Automático | ✅ PASS |
| L12 | Manual (marketplace sem sheet) | ✅ PASS |
| L13 | Automático + manual (mesmo draft não reabre sheet) | ✅ PASS |
| L14 | Manual (checkout artigo novo) | ✅ PASS |
| L15 | Manual (chat directo + gravado) | ✅ PASS |
| L16–L18 | Automático (relevância L1/L2/L3) | ✅ PASS |

**Próximo foco:** bateria **P1–P15** (artigo live sem preço) — ver Parte C.  
Deploy mínimo P: **A2** + **A3** (`create-payment-intent`) + **A4** (rebuild vendedora + comprador).

### Roadmap L (pós-V1.5 — não bloqueia P)

| Versão | Âmbito previsto | Notas |
| ------ | --------------- | ----- |
| **V1.5** | ✅ Entregue | `logical_item_id`, sheet no prep, popup início directo por linhagem, backfill 1 UUID / `live_item` |
| **L-V1.6 (UX)** | Sheet com muitas linhagens | Filtro/pesquisa, expandir reservas/vendas por card (dados já vêm no RPC), paginação |
| **L-V2 (dados)** | Catálogo lógico da seller | Tabela `seller_catalog` / entidade persistente; `logical_item_id` com FK; menos dependência de heurísticas ref/título |
| **L-V2 (ops)** | Ferramentas seller | «Fundir linhagens» erradas, renomear linhagem, arquivar uso fantasma |
| **L-V2 (config)** | `usage_window_months` configurável | Hoje fixo 12 meses (ramo L3); possível por seller ou global |
| **L-V2 (realtime)** | Saco/catálogo comprador | Preço/qty sem depender só de reload 5 s (complementa fix A1/P14) |

Nada disto está planeado para implementar durante a bateria P — são evoluções **depois** de P fechada em staging.

---

## 0 — Mapa da app (lê isto primeiro)

### Vendedora (telemóvel)


| O quê                        | Como chegar                                               | Aspecto / pista visual                                                                      |
| ---------------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| **Preparar directo**         | Criar → Preparar directoc                                 | Grelha de chips numerados (#1, #2, #15…) na secção de refs **sem catálogo**                 |
| **Editar uma ref**           | Preparar directo → **pressionar longo** no chip do número | Abre sheet «Editar ref» (título, preço, qty)                                                |
| **Sheet de linhagem**        | Após Guardar numa ref com histórico                       | Sheet escuro: «A referência #X já foi usada antes» + cards + botões Continuar / Novo artigo |
| **Criar directo**            | Depois do prep → fluxo de iniciar live                    | Botão para ir LIVE                                                                          |
| **Popup reservas em aberto** | Criar directo → **Iniciar directo** (antes de LIVE)       | Sheet de aviso com lista de reservas/orders antigas que «herdam» por linhagem               |
| **Directo — catálogo**       | Durante a live, painel de baixo                           | Cards de artigos com contadores (disp./vendidos/reservas)                                   |
| **Directo — editar artigo**  | Catálogo → ícone **⋮** (menu) no card → **Editar rápido** | Sheet com preço, qty, título                                                                |
| **Card vermelho (stock)**    | Durante live, se pedido precisa confirmar qty             | Faixa vermelha «Confirmar quantidade» + botões Aceitar/Recusar; pode ter **Definir preço**  |


### Comprador (browser ou telemóvel)


| O quê                  | Como chegar                                                                          | Aspecto / pista visual                                                      |
| ---------------------- | ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| **Entrar no directo**  | Home → card LIVE → player                                                            | Vídeo + carrossel de artigos em baixo                                       |
| **Reservar**           | Toca num artigo no carrossel → modal → **Reservar no saco**                          | Msg no chat público «reservou…»                                             |
| **Saco da live**       | Barra lateral **direita** → ícone **saco** (shopping bag), pode ter badge com número | Sheet «Saco da live» com lista de reservas por artigo                       |
| **Chat público**       | Zona de mensagens à esquerda / em baixo no player                                    | Mensagens normais + mensagens **Sistema** (preço definido, reserva aceite…) |
| **Card verde (preço)** | Aparece sozinho no player, por cima do chat                                          | «Preço definido: [artigo] — 12,00 €» durante ~10 segundos                   |


### Supabase (verificações SQL)

Dashboard → **SQL Editor** → Nova query.  
Substitui sempre `SELLER_UUID` pelo UUID da conta vendedora de teste.

**Query A — artigos live_only da seller** (L2, L4, L5, L6, L13…)

```sql
select
  li.id as live_item_id,
  li.ref_code,
  li.title,
  li.logical_item_id,
  li.price,
  li.live_id,
  l.status as live_status,
  li.created_at
from public.live_items li
join public.lives l on l.id = li.live_id
where coalesce(l.seller_id, l.vendedor_id) = 'SELLER_UUID'
  and li.item_kind = 'live_only'
order by li.created_at desc
limit 30;
```

**Query B — reservas em aberto** (L4, L6, L18, P1, P13…)

```sql
select
  r.id as request_id,
  r.status,
  r.requested_qty,
  r.live_item_id,
  li.ref_code,
  li.title,
  li.logical_item_id,
  r.created_at
from public.live_reservation_requests r
join public.live_items li on li.id = r.live_item_id
join public.lives l on l.id = r.live_id
where coalesce(l.seller_id, l.vendedor_id) = 'SELLER_UUID'
  and r.status in ('pending', 'accepted')
  and coalesce(r.notes, '') not ilike '%bag_removed%'
order by r.created_at desc
limit 30;
```

**Query C — draft actual (live em preparação)** (L4, L5, L11, L13)

```sql
select li.id, li.title, li.ref_code, li.logical_item_id, li.price, l.id as live_id
from public.live_items li
join public.lives l on l.id = li.live_id
where coalesce(l.seller_id, l.vendedor_id) = 'SELLER_UUID'
  and l.status = 'draft'
order by li.updated_at desc;
```

---

## Parte A — Deploys (por ordem, antes de qualquer teste manual)

### A1 — Testes automáticos no PC *(opcional)*

```bash
flutter test
```


| Verificar      | Onde     | Esperado                            |
| -------------- | -------- | ----------------------------------- |
| Suite completa | Terminal | `All tests passed!` — **61** testes |


---

### A2 — SQL *(obrigatório)*

1. Supabase → **SQL Editor**
2. Abre `supabase/sql/live_ops_hotfix_batata.sql` no projeto
3. Copia **o ficheiro inteiro** → cola → **Run**


| Verificar | Onde            | Esperado                        |
| --------- | --------------- | ------------------------------- |
| Execução  | SQL Editor      | Sem erro vermelho               |
| Schema    | Final do script | `notify pgrst, 'reload schema'` |


Smoke opcional: `supabase/sql/live_ops_test_seed.sql`

---

### A3 — Edge `create-payment-intent` *(obrigatório para testes P)*

```bash
npx supabase functions deploy create-payment-intent
```


| Verificar | Onde     | Esperado          |
| --------- | -------- | ----------------- |
| Deploy    | Terminal | Sucesso, sem erro |


V1.5 (L) **não** precisa de edge. Price pending (P) **sim**.

---

### A4 — Rebuild apps *(obrigatório)*


| App       | Instalar em              | Porquê                                |
| --------- | ------------------------ | ------------------------------------- |
| Vendedora | Telemóvel seller         | Sheet linhagem, prep, «Definir preço» |
| Comprador | Browser ou 2.º telemóvel | Saco, bloqueio Pagar, card verde      |


---

## Parte B — Testes L1–L18 (V1.5 linhagem de referências) — ✅ concluída

**Conta:** vendedora (telemóvel com APK A4)  
**Deploy mínimo:** A2 + A4 vendedora  
**Estado:** bateria **fechada** — tabela no topo deste doc. Secções L1–L18 mantêm-se como referência de regressão.

### Dados de teste recomendados (para L3–L6, L10)

Se ainda não tens histórico, idealmente na tua seller de teste já existem (ou existiram):

- Live **antiga 1:** ref **#15**, título **«Puzzle Star»**
- Live **antiga 2:** ref **#15**, título **«Boneca Rosa»** (outro artigo, mesma ref visível)
- Opcional: 1 reserva `accepted` no Puzzle, 0 reservas na Boneca

Se não tens isto, L3/L4/L10 podem mostrar só 1 linhagem — não é bug, faltam dados.

---

### L1 — Referência nova (sem histórico)

**Objetivo:** Confirmar que uma ref que a seller **nunca usou** grava **sem** abrir o sheet de linhagem.

**Quem testa:** Vendedora (app)

**Pré-requisitos:** A2 + A4 vendedora. Escolhe um número alto que nunca usaste (ex. **#99**).

#### Passo a passo

1. Abre **Preparar directo**.
2. Na grelha, localiza o chip **99** (ou o número escolhido).
3. **Pressão longa** no chip → abre editor de ref.
4. Título: `Teste L1` → (preço opcional) → **Guardar**.

#### Onde verificar na APP


| O quê          | Onde              | Esperado ✅                                            |
| -------------- | ----------------- | ----------------------------------------------------- |
| Sheet linhagem | Ecrã após Guardar | **Não** aparece «A referência #99 já foi usada antes» |
| Confirmação    | Snackbar em baixo | «Referência #99 actualizada.» (ou número equivalente) |
| Chip           | Grelha prep       | Chip com indicador de preenchido (ex. «99 •»)         |


#### Onde verificar no SQL

Corre **Query A** e filtra `ref_code` com 99:


| Coluna            | Esperado ✅             |
| ----------------- | ---------------------- |
| `ref_code`        | Contém 99              |
| `title`           | Teste L1               |
| `live_status`     | `draft`                |
| `logical_item_id` | Preenchido (UUID novo) |


#### Falha ❌ se

- Aparece sheet de linhagem numa ref que nunca usaste → histórico fantasma ou ref já usada noutro teste; tenta #98 ou #97.

---

### L2 — Backfill SQL (cada artigo antigo com UUID próprio)

**Objetivo:** Confirmar que o deploy SQL (A2) preencheu `logical_item_id` nos artigos **antigos**, e que **duas utilizações da mesma ref** (Puzzle + Boneca) **não** partilham o mesmo UUID.

**Quem testa:** Tu no **Supabase SQL Editor** — **não abres a app** para este teste.

**Pré-requisitos:** A2 já corrido com sucesso.

#### Passo a passo

1. Supabase → SQL Editor.
2. Corre **Query A** (substitui `SELLER_UUID`).
3. Na tabela de resultados, procura **duas ou mais linhas** com a **mesma** `ref_code` (ex. duas linhas `#15` ou `15`).
4. Compara as colunas `live_item_id` e `logical_item_id` dessas linhas.

#### Onde verificar no SQL


| O quê                         | Esperado ✅                                                                |
| ----------------------------- | ------------------------------------------------------------------------- |
| Artigos antigos               | `logical_item_id` **não é NULL**                                          |
| Mesma ref, artigos diferentes | `logical_item_id` da linha A **≠** `logical_item_id` da linha B           |
| Regra backfill V1.5           | Cada linha: `logical_item_id` = `live_item_id` (o UUID do próprio artigo) |


**Exemplo visual do resultado correcto:**


| ref_code | title       | live_item_id | logical_item_id |
| -------- | ----------- | ------------ | --------------- |
| #15      | Puzzle Star | `aaa-111`    | `aaa-111`       |
| #15      | Boneca Rosa | `bbb-222`    | `bbb-222`       |


#### Falha ❌ se

- `logical_item_id` NULL em artigos antigos → A2 não correu ou falhou a meio.
- Duas linhas #15 com o **mesmo** `logical_item_id` → backfill errado (versão antiga do SQL).

---

### L3 — Sheet mostra linhagens separadas (não mistura Puzzle com Boneca)

**Objetivo:** Ao reutilizar #15, a app mostra **um card por linhagem** (Puzzle à parte, Boneca à parte), com contexto de cada uma.

**Quem testa:** Vendedora (app)

**Pré-requisitos:** A2 + A4. **Query A** deve mostrar ≥2 linhas `#15` com **títulos diferentes** (ver L2).

#### Passo a passo

1. **Preparar directo** (draft novo ou existente).
2. **Pressão longa** no chip **#15**.
3. Título qualquer (ex. `Teste L3`) → **Guardar**.
4. Espera o sheet de linhagem abrir.

#### Onde verificar na APP


| O quê             | Onde no sheet    | Esperado ✅                                                                         |
| ----------------- | ---------------- | ---------------------------------------------------------------------------------- |
| Título do sheet   | Topo             | «A referência #15 já foi usada antes» (ou #15 conforme formato)                    |
| Texto explicativo | Abaixo do título | Explica que reservas/compras antigas não mudam                                     |
| Cards de linhagem | Lista no meio    | **≥2 cards** se tens Puzzle + Boneca no histórico                                  |
| Card Puzzle       | Primeiro card    | Título «Puzzle…», stats (reservas abertas / vendas), «Última: Gravado» ou «Direto» |
| Card Boneca       | Segundo card     | Título «Boneca…», stats próprias                                                   |
| Botões Continuar  | Abaixo dos cards | Um botão teal **por linhagem**: «Continuar — Puzzle…», «Continuar — Boneca…»       |
| Novo artigo       | Botão outline    | «Usar #15 como novo artigo» + texto «não serão alteradas»                          |
| Cancelar          | Link em baixo    | Fecha sem gravar escolha                                                           |


#### Onde verificar no SQL

Nada neste momento — só abriste o preview, ainda não escolheste linhagem.

#### Falha ❌ se

- Só 1 card mas **Query A** mostra Puzzle **e** Boneca com #15 → SQL preview não agrupa bem; reporta.
- Sheet não abre mas tens reservas/vendas antigas em #15 → ver L16/L18 (critérios de relevância).

---

### L4 — «Continuar Puzzle» liga só às reservas do Puzzle

**Objetivo:** Quando escolhes **Continuar** numa linhagem, o draft fica «irmão» do Puzzle; ao **iniciar directo**, o popup só avisa reservas **dessa** linhagem, não da Boneca.

**Quem testa:** Vendedora (app) + confirmação SQL

**Pré-requisitos:** L3 funciona (2 linhagens). Puzzle #15 com ≥1 reserva `pending` ou `accepted` (ver **Query B**). Boneca sem reservas abertas (mais fácil de ver a diferença).

**Antes de começar:** Corre **Query B** e anota:

- `live_item_id` do **Puzzle** antigo
- `logical_item_id` do Puzzle (= `live_item_id` após L2)
- Quantas reservas abertas existem no Puzzle

#### Passo a passo

1. **Preparar directo** → **pressão longa** #15 → Guardar.
2. No sheet → toca **Continuar — [título do Puzzle]** (não «novo artigo»).
3. Vê snackbar de ref actualizada.
4. Segue fluxo normal: **Criar directo** (com catálogo sincronizado).
5. Toca **Iniciar directo** / ir LIVE.
6. **Antes de confirmar LIVE**, lê o popup de **reservas em aberto**.

#### Onde verificar na APP


| Momento           | Onde                           | Esperado ✅                                                                           |
| ----------------- | ------------------------------ | ------------------------------------------------------------------------------------ |
| Após Continuar    | Prep                           | Sheet fecha; snackbar OK                                                             |
| Popup início live | Sheet de aviso (amarelo/lista) | Lista **só** reservas ligadas ao **Puzzle**                                          |
| Popup início live | Lista                          | **Não** aparecem reservas da Boneca (se Boneca tinha zero, lista vazia ou só Puzzle) |
| Títulos no popup  | Itens da lista                 | Nome/ref do Puzzle, não da Boneca                                                    |


#### Onde verificar no SQL

Corre **Query C** (draft):


| Coluna            | Esperado ✅                                                             |
| ----------------- | ---------------------------------------------------------------------- |
| `ref_code`        | #15                                                                    |
| `logical_item_id` | **Igual** ao `logical_item_id` do Puzzle histórico (anotado no início) |
| `logical_item_id` | **Diferente** do Boneca histórico                                      |


#### Falha ❌ se

- Popup mostra reservas da Boneca quando escolheste Continuar Puzzle → linhagem errada no draft (ver Query C).
- `logical_item_id` do draft = Boneca → clicaste no botão errado ou bug no inherit.

---

### L5 — «Novo artigo» não herda reservas do Puzzle

**Objetivo:** «Usar #15 como novo artigo» cria **linhagem nova**; o popup ao iniciar directo **não** deve listar reservas antigas do Puzzle.

**Quem testa:** Vendedora (app) + SQL

**Pré-requisitos:** Puzzle #15 com reservas abertas (para contrastar com L4). Draft **novo** (novo prep ou apaga escolha anterior).

#### Passo a passo

1. **Preparar directo** (preferir draft limpo).
2. **Pressão longa** #15 → Guardar.
3. No sheet → **Usar #15 como novo artigo** (botão outline, não Continuar).
4. Título: `Boneca L5` → confirma gravação.
5. **Criar directo** → **Iniciar directo**.
6. Lê popup de reservas em aberto.

#### Onde verificar na APP


| O quê               | Onde        | Esperado ✅                                                   |
| ------------------- | ----------- | ------------------------------------------------------------ |
| Popup início        | Sheet aviso | **Sem** reservas do Puzzle (lista vazia ou «sem pendências») |
| Comportamento vs L4 | Comparação  | L4 mostrava Puzzle; L5 **não** mostra                        |


#### Onde verificar no SQL

**Query C** — item draft de #15:


| Coluna            | Esperado ✅                                                    |
| ----------------- | ------------------------------------------------------------- |
| `title`           | Boneca L5 (ou o que puseste)                                  |
| `logical_item_id` | UUID **novo**, diferente do Puzzle **e** do Boneca históricos |


#### Falha ❌ se

- Popup ainda lista reservas do Puzzle → escolheste «Continuar» em vez de «Novo artigo», ou draft não foi resetado.

---

### L6 — Reservas antigas do Puzzle não foram mexidas

**Objetivo:** Garantir que L4/L5 **não alteraram** reservas já existentes na base de dados.

**Quem testa:** SQL (podes comparar antes/depois se anotaste)

**Pré-requisitos:** Ter corrido L5 (ou L4). Ter anotado IDs de reservas do Puzzle antes (Query B).

#### Passo a passo

1. Corre **Query B**.
2. Filtra linhas onde `live_item_id` = UUID do **Puzzle antigo** (não o draft novo).
3. Compara com o que tinhas **antes** de L4/L5.

#### Onde verificar no SQL


| Coluna          | Esperado ✅                                                    |
| --------------- | ------------------------------------------------------------- |
| `request_id`    | Mesmos IDs de antes                                           |
| `status`        | Inalterado (`pending` / `accepted`)                           |
| `requested_qty` | Inalterado                                                    |
| `live_item_id`  | Continua a apontar para o **Puzzle antigo**, não para o draft |


#### Onde verificar na APP

Nada obrigatório — este teste é de integridade de dados.

#### Falha ❌ se

- Reservas do Puzzle mudaram de `live_item_id` ou desapareceram sem acção tua.

---

### L7 — Preview mostra vendas concluídas na linhagem certa

**Objetivo:** Linhagem com vendas passadas mostra essa informação no sheet (para a seller perceber qual Puzzle/Boneca vendeu).

**Quem testa:** Vendedora (app)

**Pré-requisitos:** Alguma ref com encomenda `pago`/`paid` ligada a um `live_item` histórico. Descobre com:

```sql
select o.id, o.status, o.live_item_id, li.ref_code, li.title, li.logical_item_id
from public.orders o
join public.live_items li on li.id = o.live_item_id
join public.lives l on l.id = li.live_id
where coalesce(l.seller_id, l.vendedor_id) = 'SELLER_UUID'
  and lower(o.status) in ('pago', 'paid')
order by o.created_at desc
limit 10;
```

#### Passo a passo

1. Identifica uma `ref_code` que tenha vendas (ex. #15 no Puzzle).
2. **Preparar directo** → **pressão longa** nessa ref → Guardar.
3. No sheet, olha para o **card** da linhagem que vendeu.

#### Onde verificar na APP


| O quê           | Onde no card / botão Continuar  | Esperado ✅                                                   |
| --------------- | ------------------------------- | ------------------------------------------------------------ |
| Vendas          | Card da linhagem                | Indicação de vendas concluídas / unidades vendidas           |
| Badge           | Abaixo do botão «Continuar — …» | Texto verde tipo vendas (se existirem vendas nessa linhagem) |
| Linhagem errada | Outro card                      | **Sem** badge de vendas se essa linhagem não vendeu          |


#### Falha ❌ se

- Vendas do Puzzle aparecem no card da Boneca → agrupamento errado.

---

### L8 — Card de linhagem com contexto visual completo

**Objetivo:** Cada linhagem no sheet mostra dados úteis para a seller distinguir artigos.

**Quem testa:** Vendedora (app)

**Pré-requisitos:** Igual L3 (histórico com título/foto/preço no passado, se existirem).

#### Passo a passo

1. Abre sheet de uma ref com histórico (L3).
2. Examina **cada card** da lista (não os botões).

#### Onde verificar na APP


| Campo  | Onde no card         | Esperado ✅                                            |
| ------ | -------------------- | ----------------------------------------------------- |
| Título | Texto principal      | Nome do artigo antigo (Puzzle, Boneca…)               |
| Foto   | Miniatura à esquerda | Aparece se o artigo antigo tinha `photo_url`          |
| Preço  | Texto no card        | Aparece se tinha preço definido                       |
| Origem | Linha pequena        | «Última: Gravado» ou «Última: Direto»                 |
| Stats  | Números no card      | Reservas abertas / unidades / vendas conforme existam |


#### Falha ❌ se

- Cards vazios ou todos iguais quando o histórico tem títulos diferentes.

---

### L9 — Sheet volta a aparecer em novo preparação

**Objetivo:** A app **não guarda para sempre** a escolha «novo artigo». Num **novo** draft, ao reutilizar #15, volta a perguntar.

**Quem testa:** Vendedora (app)

**Pré-requisitos:** Ref #15 com histórico relevante. Já correste L4 ou L5 num draft **anterior**.

#### Passo a passo

1. Termina ou abandona o prep/directo anterior.
2. Abre **Preparar directo** outra vez (novo ciclo — novo draft).
3. **Pressão longa** #15 → preenche → **Guardar**.

#### Onde verificar na APP


| O quê          | Esperado ✅                                                                                 |
| -------------- | ------------------------------------------------------------------------------------------ |
| Sheet linhagem | **Abre outra vez** (desde que o **novo** draft ainda não tenha `logical_item_id` definido) |


#### Onde verificar no SQL

**Query C** antes de escolher no sheet: draft sem item #15 com `logical_item_id` definido, ou item novo.

#### Falha ❌ se

- Sheet nunca mais aparece em drafts novos → possível bug; verifica se estás no mesmo draft antigo.

---

### L10 — Dois botões «Continuar» com nomes diferentes

**Objetivo:** Com 2 linhagens, há **2 CTAs separados** — não um botão genérico.

**Quem testa:** Vendedora (app)

**Pré-requisitos:** L3 (2 linhagens visíveis).

#### Passo a passo

1. Abre sheet #15 (L3).
2. Conta os botões teal **Continuar — …** abaixo dos cards.

#### Onde verificar na APP


| O quê      | Esperado ✅                                            |
| ---------- | ----------------------------------------------------- |
| Quantidade | **2** botões Continuar (se 2 linhagens)               |
| Texto      | Cada um com **título diferente** (Puzzle vs Boneca)   |
| Acção      | Tocar um fecha sheet e grava essa linhagem (snackbar) |


#### Falha ❌ se

- Só 1 botão Continuar mas 2 cards → bug de UI.

---

### L11 — Cancelar no sheet não grava no servidor

**Objetivo:** Se a seller **Cancelar**, nada é gravado no Supabase (nem linhagem nem upsert).

**Quem testa:** Vendedora (app) + SQL

**Pré-requisitos:** Ref com histórico (#15).

#### Passo a passo

1. Corre **Query C** e **anota** quantos itens existem no draft e os seus `logical_item_id`.
2. **Pressão longa** #15 → título `Cancelar L11` → Guardar.
3. Sheet abre → toca **Cancelar** (link em baixo).
4. Corre **Query C** outra vez.

#### Onde verificar na APP


| O quê         | Esperado ✅                                |
| ------------- | ----------------------------------------- |
| Após Cancelar | Voltas ao prep; sheet fechado             |
| Chip local    | Pode mostrar detalhe local do editor — OK |


#### Onde verificar no SQL


| O quê             | Esperado ✅                               |
| ----------------- | ---------------------------------------- |
| Query C           | **Mesmos** registos que antes do passo 2 |
| `title`           | **Não** aparece `Cancelar L11` no draft  |
| `logical_item_id` | Inalterado vs anotação inicial           |


#### Falha ❌ se

- Query C mostra item novo ou `logical_item_id` mudou após Cancelar.

---

### L12 — Marketplace (TYPE A) não abre sheet de linhagem

**Objetivo:** Sheet de ref reutilizada é **só para live_only por ref**. Artigos do marketplace ignoram este fluxo.

**Quem testa:** Vendedora (app)

**Pré-requisitos:** Ter um produto no marketplace (anúncio normal com `product_id`).

#### Passo a passo

1. **Preparar directo**.
2. Adiciona ao prep/catálogo um artigo **do marketplace** (não cries via chip #15 live_only).
3. Grava / sincroniza — qualquer fluxo que associe produto marketplace ao directo.

#### Onde verificar na APP


| O quê                | Esperado ✅                                                              |
| -------------------- | ----------------------------------------------------------------------- |
| Durante todo o fluxo | **Nunca** aparece «A referência #X já foi usada antes» para marketplace |


#### Falha ❌ se

- Sheet de linhagem abre ao mexer em produto marketplace.

---

### L13 — Segunda edição no mesmo draft não reabre sheet

**Objetivo:** Depois de escolheres linhagem **uma vez**, mudar preço/qty **não** deve voltar a perguntar.

**Quem testa:** Vendedora (app)

**Pré-requisitos:** #15 com histórico. Draft **mesmo** (não fechar prep).

#### Passo a passo

1. **Pressão longa** #15 → Guardar → no sheet escolhe **Continuar** ou **Novo artigo** → confirma snackbar.
2. **Outra vez** **pressão longa** #15.
3. Muda **só o preço** (ex. 10 → 15) → **Guardar**.

#### Onde verificar na APP


| O quê        | Esperado ✅                             |
| ------------ | -------------------------------------- |
| 2.ª gravação | Sheet **não** abre                     |
| Feedback     | Snackbar «Referência #15 actualizada.» |


#### Onde verificar no SQL

**Query C** — mesmo `logical_item_id` que após passo 1; só `price` pode ter mudado.

#### Falha ❌ se

- Sheet abre na 2.ª gravação no **mesmo** draft.

---

### L14 — Checkout funciona no artigo novo sem estragar Puzzle

**Objetivo:** Fluxo de compra normal no artigo «novo» (#15 Boneca L5); histórico Puzzle intacto.

**Quem testa:** Vendedora + **Comprador**

**Pré-requisitos:** L5 concluído. Directo **LIVE** com artigo novo. Comprador com conta de teste. Artigo com **preço** definido (senão checkout bloqueia — ver parte P).

#### Passo a passo

1. Após L5, inicia directo e fica LIVE.
2. **Comprador** entra no player → reserva artigo novo → vendedora aceita se necessário.
3. Comprador → saco → **Pagar** → Stripe → conclui pagamento.
4. Corre **Query B** para reservas do Puzzle antigo.

#### Onde verificar na APP (comprador)


| O quê         | Esperado ✅                                 |
| ------------- | ------------------------------------------ |
| Stripe        | Abre e pagamento conclui                   |
| Pós-pagamento | Artigo marcado comprado / saco actualizado |


#### Onde verificar no SQL


| O quê                     | Esperado ✅                                       |
| ------------------------- | ------------------------------------------------ |
| Reservas Puzzle (Query B) | Inalteradas vs antes do pagamento (L6)           |
| Nova order                | `live_item_id` do artigo **novo**, não do Puzzle |


#### Falha ❌ se

- Pagamento associa-se ao Puzzle antigo ou apaga reservas do Puzzle.

---

### L15 — Regressão: chat no directo e no gravado

**Objetivo:** Alterações de linhagem **não** estragaram chat público nem replay.

**Quem testa:** Comprador (app)

**Pré-requisitos:** Directo LIVE ou gravado disponível.

#### Passo a passo — directo

1. Comprador entra no directo.
2. Faz uma **reserva** ou envia mensagem no chat.
3. Faz **scroll para cima** no chat até ao início.

#### Passo a passo — gravado

1. Abre um **gravado** (VOD) da mesma seller.
2. Reproduz vídeo — observa se mensagens do chat aparecem sincronizadas.
3. Scroll no chat até à primeira mensagem.

#### Onde verificar na APP


| O quê               | Esperado ✅                                                        |
| ------------------- | ----------------------------------------------------------------- |
| Nome na reserva     | Nome real do comprador, **não** «Utilizador»                      |
| Scroll chat directo | Consegues chegar à **primeira** mensagem                          |
| Gravado             | Chat não fica permanentemente vazio no início (sync com playhead) |


#### Falha ❌ se

- «Utilizador» no chat de reservas; scroll bloqueado a meio do histórico.

---

### L16 — Venda há ~18 meses ainda mostra sheet

**Objetivo:** Vendas concluídas contam como histórico **relevante** — **sem limite de tempo**.

**Quem testa:** Vendedora (app)

**Pré-requisitos:** Uma ref com:

- ≥1 order `pago`/`paid` (mesmo que antiga)
- **0** reservas `pending`/`accepted`

Descobre candidata:

```sql
select li.ref_code, li.title, count(o.id) as vendas
from public.live_items li
join public.lives l on l.id = li.live_id
left join public.orders o on o.live_item_id = li.id and lower(o.status) in ('pago','paid')
where coalesce(l.seller_id, l.vendedor_id) = 'SELLER_UUID'
  and li.item_kind = 'live_only'
group by li.id, li.ref_code, li.title
having count(o.id) > 0;
```

#### Passo a passo

1. Escolhe essa ref (ex. #20).
2. **Preparar directo** → **pressão longa** → Guardar.

#### Onde verificar na APP


| O quê | Esperado ✅                              |
| ----- | --------------------------------------- |
| Sheet | **Abre** (mesmo sem reservas abertas)   |
| Card  | Mostra vendas concluídas nessa linhagem |


#### Falha ❌ se

- Grava directo sem sheet numa ref que sabes ter vendas pagas.

---

### L17 — Uso antigo sem vendas nem reservas → sem sheet

**Objetivo:** Só «usei a ref há muito tempo» **sem** dinheiro pendente **não** deve incomodar a seller (janela 12 meses).

**Quem testa:** Vendedora (app)

**Pré-requisitos:** Ref usada há **>12 meses**, com:

- **0** reservas abertas
- **0** vendas `pago`

(pode ser difícil de achar — se não tiveres, marca «N/A — sem dados» e segue.)

#### Passo a passo

1. Identifica ref candidata (Query A + Query B + orders — tudo zero/aberto).
2. **Preparar directo** → **pressão longa** → Guardar.

#### Onde verificar na APP


| O quê    | Esperado ✅                |
| -------- | ------------------------- |
| Sheet    | **Não** abre              |
| Gravação | Snackbar directo, como L1 |


#### Falha ❌ se

- Sheet abre só por uso antigo sem vendas/reservas.

---

### L18 — Reservas abertas há anos sempre mostram sheet

**Objetivo:** Reservas `pending`/`accepted` são sempre relevantes — **não** expiram aos 12 meses.

**Quem testa:** Vendedora (app)

**Pré-requisitos:** Ref com reserva aberta antiga (Query B com `created_at` há anos).

#### Passo a passo

1. Confirma em **Query B** que existe reserva `pending`/`accepted` antiga numa ref.
2. **Preparar directo** → **pressão longa** nessa ref → Guardar.

#### Onde verificar na APP


| O quê               | Esperado ✅                                               |
| ------------------- | -------------------------------------------------------- |
| Sheet               | **Abre**                                                 |
| Texto «Novo artigo» | «As reservas e compras antigas **não serão alteradas**.» |
| Cards               | Mostram reservas abertas dessa linhagem                  |


#### Falha ❌ se

- Reservas abertas existem na Query B mas sheet não abre.

---

## Parte C — Testes P1–P15 (artigo live sem preço)

**Contas:** vendedora + comprador  
**Deploy mínimo:** A2 + **A3** + A4 **ambos**  
**Dica:** Usa um artigo **live_only** dedicado (ex. ref #88) com **preço vazio** no prep/directo.

---

### P1 — Criar e reservar artigo sem preço

**Objetivo:** Artigo sem preço pode existir e receber reservas — não é bloqueado.

**Quem testa:** Vendedora cria → Comprador reserva

**Pré-requisitos:** A2, A3, A4. Directo LIVE com artigo sem preço.

#### Passo a passo — vendedora

1. No prep ou no **catálogo do directo**, artigo live_only ref ex. #88.
2. Campo **preço vazio** ou 0 → grava / mostra no catálogo.
3. Inicia directo se ainda não estiver LIVE.
4. Toca **Mostrar** no artigo para compradores verem.

#### Passo a passo — comprador

1. Entra no player do directo.
2. Toca no artigo no **carrossel** → modal abre.
3. Toca **Reservar no saco**.

#### Onde verificar na APP (comprador)


| O quê          | Onde             | Esperado ✅                          |
| -------------- | ---------------- | ----------------------------------- |
| Reserva        | Modal / feedback | Sucesso — pedido criado             |
| Chat           | Chat público     | Msg «reservou…» (sem erro de preço) |
| Preço no modal | Modal artigo     | Pode não mostrar preço — OK         |


#### Onde verificar no SQL

```sql
select r.id, r.status, r.live_item_id, li.price, li.ref_code
from public.live_reservation_requests r
join public.live_items li on li.id = r.live_item_id
where r.buyer_id = 'BUYER_UUID'
order by r.created_at desc
limit 5;
```


| Coluna     | Esperado ✅              |
| ---------- | ----------------------- |
| `status`   | `pending` ou `accepted` |
| `li.price` | NULL ou 0               |


#### Falha ❌ se

- App impede reserva por falta de preço.

---

### P2 — Saco mostra «Preço a definir» e esconde Pagar

**Objetivo:** Comprador vê estado claro; não pode pagar ainda.

**Quem testa:** Comprador (app)

**Pré-requisitos:** P1 feito — tens reserva no saco, artigo ainda sem preço.

#### Passo a passo

1. No player, barra lateral **direita** → ícone **saco** (shopping bag).
2. Abre sheet «Saco da live».
3. Localiza o cartão do artigo #88 (ou o que usaste).

#### Onde verificar na APP


| O quê       | Onde no cartão do saco             | Esperado ✅                                      |
| ----------- | ---------------------------------- | ----------------------------------------------- |
| Preço       | Texto abaixo do título             | **«Preço a definir pela vendedora»** (cinzento) |
| Botão Pagar | Linha de botões em baixo do cartão | **Ausente** — só «Gerir reservas» se aplicável  |
| Reserva     | Chips de estado                    | Reserva listada (pendente/aceite) — OK          |


#### Falha ❌ se

- Aparece «0,00 €» com botão **Pagar** activo.

---

### P3 — Impossível pagar sem preço

**Objetivo:** UI + backend bloqueiam pagamento a zero.

**Quem testa:** Comprador (app)

**Pré-requisitos:** P2 — sem botão Pagar.

#### Passo a passo

1. Confirma em P2 que **não há** botão Pagar.
2. *(Opcional)* Se no modal do artigo existir outro caminho «Comprar já» / checkout, tenta — deve falhar ou não aparecer total válido.

#### Onde verificar na APP


| O quê             | Esperado ✅                                                    |
| ----------------- | ------------------------------------------------------------- |
| Saco              | Sem Pagar                                                     |
| Qualquer checkout | Não abre Stripe; ou msg «Preço a definir…» / «Preço inválido» |


#### Falha ❌ se

- Stripe abre com total 0 € → falta A3 (edge) ou A4 comprador antigo.

---

### P4 — Vendedora define preço

**Objetivo:** Preço grava em `live_items` e sincroniza produto shadow para checkout futuro.

**Quem testa:** Vendedora (app) + SQL

**Pré-requisitos:** P1 — artigo sem preço no directo LIVE.

#### Passo a passo — opção A (catálogo)

1. No **directo**, painel catálogo em baixo.
2. No card do artigo → **⋮** menu → **Editar rápido**.
3. Preço: `12,00` → Guardar.

#### Passo a passo — opção B (card vermelho)

1. Se aparecer card vermelho «Confirmar quantidade» para esse artigo **sem preço**.
2. Toca **Definir preço** (botão com ícone €).
3. No editor → preço `12,00` → Guardar.

#### Onde verificar na APP (vendedora)


| O quê         | Onde           | Esperado ✅                        |
| ------------- | -------------- | --------------------------------- |
| Catálogo      | Card do artigo | **12,00 €** visível               |
| Card vermelho | Se existia     | Pode desaparecer ou mostrar preço |


#### Onde verificar no SQL

Substitui `LIVE_ITEM_UUID`:

```sql
select li.id, li.price, li.checkout_product_id, p.price as shadow_price
from public.live_items li
left join public.products p on p.id = li.checkout_product_id
where li.id = 'LIVE_ITEM_UUID';
```


| Coluna         | Esperado ✅                            |
| -------------- | ------------------------------------- |
| `li.price`     | 12                                    |
| `shadow_price` | 12 (se `checkout_product_id` existir) |


#### Falha ❌ se

- App mostra 12 € mas SQL `li.price` NULL → gravação falhou.

---

### P5 — Saco do comprador actualiza com preço e Pagar

**Objetivo:** Após P4, comprador pode pagar.

**Quem testa:** Comprador (app)

**Pré-requisitos:** P4 concluído. Reserva aceite ou pronta a pagar.

#### Passo a passo

1. Comprador no directo → ícone **saco**.
2. Abre saco (fecha e reabre se já estava aberto antes de P4).

#### Onde verificar na APP


| O quê | Onde no cartão  | Esperado ✅                                                         |
| ----- | --------------- | ------------------------------------------------------------------ |
| Preço | Texto preço     | **12,00 €** (verde/teal)                                           |
| Botão | Linha de acções | **Pagar** visível e clicável (se reserva aceite/aguarda pagamento) |


#### Falha ❌ se

- Continua «Preço a definir» após P4 → reabre saco; se persiste, falta realtime (ver P14).

---

### P6 — Mensagem de sistema no chat público

**Objetivo:** Todos no directo veem no chat que o preço foi definido.

**Quem testa:** Comprador (ou qualquer viewer)

**Pré-requisitos:** P4 acabou de correr.

#### Passo a passo

1. Olha para o **chat público** no player (zona de mensagens).
2. Procura mensagem recente do **Sistema**.

#### Onde verificar na APP


| O quê        | Onde                       | Esperado ✅                                    |
| ------------ | -------------------------- | --------------------------------------------- |
| Formato      | Chat público               | `💶 Preço definido · [nome artigo] · 12,00 €` |
| Visibilidade | Qualquer viewer no directo | Mensagem visível (não é privada)              |


#### Falha ❌ se

- Preço definido na vendedora mas chat sem mensagem → SQL broadcast falhou (A2).

---

### P7 — Card verde temporário no player

**Objetivo:** Destaque visual ~10 s para todos os viewers.

**Quem testa:** Comprador (app)

**Pré-requisitos:** P4 — acabado de definir preço.

#### Passo a passo

1. Mantém olho na zona **acima do chat** no player.
2. Espera até 10 segundos.

#### Onde verificar na APP


| O quê   | Onde                    | Esperado ✅                               |
| ------- | ----------------------- | ---------------------------------------- |
| Card    | Flutuante acima do chat | Borda verde, título **«Preço definido»** |
| Texto   | Corpo do card           | `[artigo] — 12,00 €`                     |
| Duração | Tempo                   | Desaparece só ~**10 s** depois           |


#### Falha ❌ se

- Chat tem msg (P6) mas card verde nunca aparece → APK comprador antigo (A4).

---

### P8 — Viewer sem reserva também vê aviso

**Objetivo:** Broadcast é **público** — não só quem reservou.

**Quem testa:** 2.º comprador ou conta sem reserva

**Pré-requisitos:** P4 — outro user **sem** reserva no artigo #88.

#### Passo a passo

1. Entra no **mesmo directo** com conta que **não** reservou.
2. Observa chat (P6) e card verde (P7) quando vendedora define preço (ou logo após).

#### Onde verificar na APP


| O quê        | Esperado ✅         |
| ------------ | ------------------ |
| Chat sistema | Vê a mesma msg P6  |
| Card verde   | Vê o mesmo card P7 |


#### Falha ❌ se

- Só o comprador com reserva vê — bug de broadcast.

---

### P9 — Pagamento Stripe com fees correctos

**Objetivo:** Checkout completo com preço > 0 e taxas Fleaber.

**Quem testa:** Comprador

**Pré-requisitos:** P5 — botão Pagar activo. A3 deployada.

#### Passo a passo

1. Saco → **Pagar** → escolhe linhas se pedido → confirma.
2. No sheet checkout, verifica breakdown (artigo + portes + seguro).
3. Completa **Stripe** no browser.
4. Volta à app.

#### Onde verificar na APP


| O quê          | Esperado ✅                                                                                         |
| -------------- | -------------------------------------------------------------------------------------------------- |
| Total checkout | Artigo 12 € + portes (3,50 € transportadora ou 0 € mão) + seguro (0,65 € + 5% sobre artigo+portes) |
| Stripe         | Cobrança ≈ esse total                                                                              |
| Pós-pagamento  | Saco/card «comprado»; vendedora vê vendido                                                         |


#### Onde verificar no SQL

```sql
select id, status, price_total, live_item_id
from public.orders
where buyer_id = 'BUYER_UUID'
order by created_at desc
limit 3;
```


| Coluna        | Esperado ✅                     |
| ------------- | ------------------------------ |
| `status`      | Evolui para pago               |
| `price_total` | Coerente com total do checkout |


#### Falha ❌ se

- Stripe com 0 € → edge A3 em falta.

---

### P10 — Mudar preço antes de pagar (ainda permitido)

**Objetivo:** Vendedora pode corrigir preço **antes** de qualquer pagamento nesse artigo.

**Quem testa:** Vendedora + Comprador

**Pré-requisitos:** P4 com 12 €. **Ninguém pagou ainda** (não correr P9 antes).

#### Passo a passo

1. Vendedora → **Editar rápido** → muda 12 → **15,00** → Guardar.
2. Comprador → reabre **saco**.

#### Onde verificar na APP


| O quê          | Esperado ✅                                                  |
| -------------- | ----------------------------------------------------------- |
| Saco comprador | **15,00 €**                                                 |
| Chat           | Nova msg «Preço definido · … · 15,00 €» (mudança relevante) |
| Card verde     | Pode aparecer outra vez com 15 €                            |


#### Falha ❌ se

- Snackbar «Preço bloqueado» **antes** de pagamento → bug de lock.

---

### P11 — Bloquear mudança de preço após venda

**Objetivo:** Com pagamento/converted, preço fica locked.

**Quem testa:** Vendedora (app)

**Pré-requisitos:** P9 concluído (order pago ou reserva `converted` nesse `live_item`).

#### Passo a passo

1. Vendedora → catálogo → **⋮** → **Editar rápido** no **mesmo** artigo.
2. Tenta mudar preço 12 → 20 → Guardar.

#### Onde verificar na APP


| O quê    | Esperado ✅                                     |
| -------- | ---------------------------------------------- |
| Snackbar | **«Preço bloqueado após venda neste artigo.»** |
| Catálogo | Preço **permanece** o anterior (12 €)          |


#### Onde verificar no SQL

`li.price` inalterado após tentativa.

#### Falha ❌ se

- Preço muda após venda → A2 SQL em falta ou incompleto.

---

### P12 — Marketplace (TYPE A) sem regressão

**Objetivo:** Artigo marketplace com preço no prep continua a funcionar normalmente.

**Quem testa:** Vendedora + Comprador

**Pré-requisitos:** Produto marketplace com preço já definido no anúncio.

#### Passo a passo

1. Adiciona produto **marketplace** ao directo (não live_only sem preço).
2. Comprador reserva → paga → Stripe.

#### Onde verificar na APP


| O quê          | Esperado ✅                                   |
| -------------- | -------------------------------------------- |
| Fluxo completo | Igual ao habitual — preço desde o início     |
| Saco           | Mostra preço; Pagar disponível quando aceite |
| Sheet linhagem | **Não** interfere (cruzado com L12)          |


#### Falha ❌ se

- Marketplace perde preço ou não paga.

---

### P13 — Aceitar reserva sem preço (vendedora)

**Objetivo:** Aceite de reserva é válido mesmo sem preço; comprador ainda não paga.

**Quem testa:** Vendedora aceita → Comprador vê saco

**Pré-requisitos:** P1 — reserva `pending` em artigo sem preço.

#### Passo a passo — vendedora

1. No directo, fila de **reservas** / card vermelho se aplicável.
2. Toca **Aceitar** na reserva do artigo sem preço.

#### Passo a passo — comprador

1. Abre **saco**.
2. Verifica estado da reserva aceite.

#### Onde verificar na APP (comprador)


| O quê   | Esperado ✅                              |
| ------- | --------------------------------------- |
| Reserva | Estado aceite / banner verde se existir |
| Preço   | Ainda «Preço a definir pela vendedora»  |
| Pagar   | **Ainda ausente** até P4                |


#### Falha ❌ se

- Aceitar falha por falta de preço.

---

### P14 — Actualização em tempo real (ou quase)

**Objetivo:** Comprador vê preço novo sem sair do directo.

**Quem testa:** Comprador + Vendedora em paralelo

**Pré-requisitos:** P1 + P13. Dois dispositivos.

#### Passo a passo

1. Comprador: abre **saco** e mantém-se no directo.
2. Vendedora: **P4** — define 12 €.
3. Comprador: observa saco, chat e card verde **sem** sair do player.

#### Onde verificar na APP (comprador)


| O quê             | Esperado ✅                                                    |
| ----------------- | ------------------------------------------------------------- |
| Chat / card verde | Actualizam em segundos (P6/P7)                                |
| Saco              | Mostra 12 € e Pagar — pode precisar **fechar e reabrir** saco |


#### Falha ❌ se

- Nada muda até relaunch da app — anota como limitação; reabrir saco deve funcionar sempre após P4.

---

### P15 — Sem spam de notificações (debounce)

**Objetivo:** Gravar o **mesmo** preço duas vezes não duplica msg chat.

**Quem testa:** Vendedora + observação chat

**Pré-requisitos:** Artigo com 12 € já definido.

#### Passo a passo

1. Vendedora → **Editar rápido** → preço `12,00` → Guardar.
2. **Imediatamente** outra vez → **Editar rápido** → mesmo `12,00` → Guardar.
3. Conta mensagens «Preço definido» no chat nos últimos 2 minutos.

#### Onde verificar na APP


| O quê  | Esperado ✅                                                |
| ------ | --------------------------------------------------------- |
| Chat   | **Uma** msg «… 12,00 €» — não duas seguidas iguais        |
| 15 min | Repetir mesmo preço dentro de 15 min → ainda sem duplicar |


#### Falha ❌ se

- Duas msgs idênticas «12,00 €» em sequência rápida.

---

## Ordem recomendada (resumo final)

```
A1  flutter test (PC, opcional)
A2  SQL live_ops_hotfix_batata.sql (completo)
A3  edge create-payment-intent
A4  rebuild vendedora + comprador

B   L1–L18  ✅ FECHADA (12 auto + 6 manual SKIP confirmados)
C   P1→P2→P3 → P4→P5→P6→P7→P8 → P9 → P10 | P11 → P12–P15  ← AGORA
```

**Nota:** P10 e P11 são mutuamente exclusivos no mesmo artigo — usa **dois** artigos ou repete P1–P4 noutra ref para P10 antes de P9.

---

## Problemas comuns


| Sintoma                              | O que verificar                                 |
| ------------------------------------ | ----------------------------------------------- |
| Sheet linhagem nunca abre            | A2 SQL? Ref tem histórico relevante? (L16/L18)  |
| `logical_item_id` NULL               | A2 incompleto — corre L2                        |
| Popup início mostra reservas erradas | Query C — `logical_item_id` do draft (L4 vs L5) |
| «Preço a definir» após definir preço | Fecha/reabre saco; A4 comprador                 |
| Botão Pagar sem preço                | APK comprador antigo                            |
| Stripe 0 €                           | Edge A3 não deployada                           |
| Preço bloqueado antes de pagar       | Correste P9 antes de P10 no mesmo artigo        |


---

*Última actualização: L1–L18 fechada · P em curso — Jun 2026*