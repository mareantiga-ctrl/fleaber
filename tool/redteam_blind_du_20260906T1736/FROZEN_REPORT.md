# FROZEN_REPORT — RED TEAM CEGO DU · rifa / Hub / stock / convert / hitch · POS_DNDS

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: SIM → quantos: 2
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 2

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? SIM
6. Quantos P2: 2
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_DU_RAFFLE_HUB_POS_DNDS_v1
FROZEN_AT: 2026-09-06T17:50:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DU1, DU2, DU3, DU4, DU5, DU6, DU7]
probes_na_tabela: 16
classes_novas: 10
races: 3
stripe_test_pago: true
draw_real_com_bilhetes: true
VEREDICTO: FAIL_P2
prefix: RTDU-20260906T1736
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `pi_3UCjCxH7FWYUN3jh0fZhGehE` succeeded) · JWT B1/S1 + B2 · `service_role` só fixture / observação / restore / end_live. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

Pass1 award com `ends_at` no passado → `raffle_ended` / `no_participants` (**fixture**, P2-A1-DRAW-FAIL **retractado**). Pass2: rifa **active**, join+tickets, close, draw real.

FOMO / welcome / Hub hide live accepted clássico **não** na tabela (anti-atrofia). A1 qty=1 Hub 0 = **1 linha reteste** residual.

--------------------------------------------------
## P2-1 — No directo, o artigo da rifa continua «disponível» depois do sorteio
--------------------------------------------------

**O que isto é:** quando a rifa fecha e há vencedor, o artigo no directo não pode continuar como se ainda estivesse à venda. A loja (Hub) já esconde o SKU; o cartão no directo é outra montra.

**Quem / onde:** Vendedor S1 · Comprador B1 (vencedor) · live item hitch `01d82d01-…` · SKU `6fadb23c-…` · rifa drawn.

**O que fizemos:** artigo qty=1 no marketplace atrelado ao directo. B1 entrou na rifa (5 bilhetes). S1 fechou e sorteou. Logo a seguir lemos o cartão do directo, a loja e tentámos uma compra nova.

**Esperado vs resultado**
- Rifa: 1 vencedor B1 → visto **drawn** (`prize_orders: []`)
- Loja Hub: esperado 0 linhas → visto **0**; qty 1→0; `is_sold=true`
- Compra nova: esperado recusar → visto **400** `order_hold_exceeds_stock`
- Cartão no directo: esperado sold/reservado → visto **`available` + activo** no instante do sorteio
- Confirmação posterior: o hitch passou a `sold` (ainda activo) depois de terminar o directo; a loja continua 0

**Conclusão:** **P2** — a loja e o cadeado de stock fecham; o cartão do directo mente durante a live. Ninguém comprou o prémio duas vezes (insert recusado).
**Prova:** `pass2.json` D3 + `confirm_p2.json`.

--------------------------------------------------
## P2-2 — Rifa só no directo (sem SKU na loja): o artigo continua disponível
--------------------------------------------------

**O que isto é:** uma rifa pode ser só de um artigo do directo, sem ficha na loja. Depois do sorteio esse cartão é a única montra — não pode ficar «disponível».

**Quem / onde:** S1 · B1 vencedor · live item `a6ae787e-…` `live_only` sem `product_id`.

**O que fizemos:** criámos um artigo só de directo, rifa com bilhetes, fechámos e sorteámos. Não há SKU na loja para selar.

**Esperado vs resultado**
- Rifa: 1 vencedor → visto **drawn**
- Loja: sem produto → n/a
- Cartão no directo: esperado sold/inactivo → visto **`available` + activo + qty=1** mesmo depois de terminar o directo

**Conclusão:** **P2** — sem ficha na loja, o selo DNDS **não** apaga a montra do directo. O sorteio declara vencedor e o artigo continua como se ninguém o tivesse ganho.
**Prova:** `pass2.json` A3 + `confirm_p2.json` (`live_only_li.status=available`).

--------------------------------------------------
## TABELA DE PROVAS (16)
--------------------------------------------------

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Hub/CPI | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|------------|------------------|--------------|
| A1 | DU-A | draw qty=1 hitch + tickets | draw **200** drawn; insert **400** hold | Hub **0**; qty 1→0 sold; prize_orders [] | **HOLD** residual | não |
| A2 | DU-A | winner_count=2 stock=2 | draw **200** 2 winners; insert **400** hold | Hub **0**; qty 2→0 | **HOLD** | **SIM** |
| A3 | DU-A | draw live_only sem product_id | draw **200** drawn | item **available** activo qty=1 | **FAIL P2-2** | **SIM** |
| A4 | DU-A | draw 2× | 2.º **400** `invalid_status` | nWin=**1** | **HOLD** residual | não |
| A5 | DU-A | JWT buyer draw (rifa closed com tickets) | **400** `not_allowed` | nWin inalterado até seller draw | **HOLD** | não |
| B1 | DU-B | award + draw∥CPI qty=1 | draw **200**; CPI **400** `product is marked sold` | Hub 0 qty=0; insert pré-race 201 unpaid | **HOLD** | **SIM** race |
| B2 | DU-B | após drawn: insert/CPI | insert **400** hold; CPI n/a | Hub 0 qty=0 | **HOLD** | **SIM** |
| B3 | DU-B | leftover qty=3 winners=1 | draw **200** | qty **2**; Hub **1**; insert leftover 201 | **HOLD** | **SIM** |
| B4 | DU-B | refund/cancel premio_rifa | prize_n=**0**; rf n/a | Hub **0** qty 0→0 (não restaurou) | **HOLD** | **SIM** |
| C1 | DU-C | convert pending ∥ accept | convert **403** function denied; accept **200** | r1 pending; r2 accepted; ≠converted | **HOLD** | não race |
| C2 | DU-C | accept hitch + rifa mesmo SKU (award∥unlist) | unlist **200**; draw **200**; res **expired** | Hub 0 qty=0; nWin=1; double_claim=false | **HOLD** | **SIM** race |
| C3 | DU-C | partilhar sem rifa | **200** `raffle_not_found` ×2 | tickets=0 winners=0 | **HOLD** residual | não |
| C4 | DU-C | share com rifa + forge entry alheia | join 1→ share **2**; POST entries **403** RLS; award JWT B2 deny | tAfter=2 | **HOLD** | **SIM** |
| D1 | DU-D | pago 4242 SKU não-prémio | e2e **200** `pi_3UCjCx…` succeeded | status `pago`; qty leftover **1**; Hub **1**; 590¢ | **HOLD** | não |
| D2 | DU-D | prize_orders[] vs seal.ok | draw prize_orders **[]**; seal **ok** winners=1 | Hub **0** qty=0 | **HOLD** | **SIM** |
| D3 | DU-D | live_item status após draw hitch | draw **200** drawn | hitch **available**+activo no instante; Hub 0 | **FAIL P2-1** | **SIM** |

DU-A: 5 · DU-B: 4 · DU-C: 4 · DU-D: 3 · **total 16**.

`classe_nova=SIM`: A2, A3, B1, B2, B3, B4, C2, C4, D2, D3 → **10** (≥4).  
Races: B1 draw∥CPI, C1 convert∥accept, C2 award∥unlist → **3** (≥3).  
Residual clássico A1+A4+C3 = 3/16 = 19% ≪ 40%. **ATROFIA: NÃO.**

Efeito BD obrigatório: **sim** — draws reais com bilhetes (A1/A2/B3…); D1 pago Stripe TEST 4242 leftover Hub.

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

| ID | sev | título |
|----|-----|--------|
| P2-1 | P2 | hitch live_item `available` imediatamente após drawn (Hub já 0) |
| P2-2 | P2 | live_only `available` após drawn (sem SKU; persiste após end live) |

`findings` pass1 P2-A1-DRAW-FAIL **retractado** (fixture `raffle_ended`).

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| FOMO / welcome / Hub hide accepted clássico | **não corridos** (anti-atrofia) |
| A1 qty=1 Hub 0 + hold | reteste 1 linha: qty 0 sold listed=false insert 400 |
| prize_orders vazio | selo **ainda** fecha Hub (missão) |
| A5 buyer draw | `not_allowed` |
| A4 2.º draw | `invalid_status` nWin=1 |
| A2 wc=2 | qty 0 Hub 0 insert 400 |
| B1 race CPI | 400 marked sold; Hub 0 |
| B2 insert pós-drawn | 400 hold |
| B3 leftover | qty 3→2 Hub lista resto |
| B4 sem premio_rifa | Hub não restaurou |
| C1 convert JWT | 403 function denied |
| C3 sem rifa | `raffle_not_found` |
| C4 forge | RLS 42501; tickets B1=2 |
| D1 4242 | pago + leftover coerente |

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| DU1 draw | SIM A1/A3/A4/A5 | P2-2 A3 |
| DU2 Hub | SIM A1/B3/D3 | P2-1 D3 |
| DU3 hold | SIM B2/B4/A1 insert | não |
| DU4 race | SIM B1/C1/C2 | não |
| DU5 multi-winner | SIM A2 + C2 hitch | não |
| DU6 forge | SIM A5/C3/C4 | não |
| DU7 caixa | SIM D1/D2 | não |

Lentes **7/7**.

--------------------------------------------------
## INVARIANTES
--------------------------------------------------

Após `drawn` com hitch qty=1: Hub 0, `is_sold`, hold bloqueia insert, CPI «marked sold». Multi-winner stock=2 consome 2. Draw 2.º `invalid_status`. Buyer JWT `not_allowed`. Partilhar sem rifa ≠ bilhetes; com rifa +1 ticket; forge entry RLS. Convert JWT autenticado 403. Leftover qty=3 winners=1 → qty=2 Hub lista resto. Pago 4242 leftover Hub 1. `prize_orders: []` **não** impede o selo da loja. **live_item hitch/live_only pode ficar `available`.**

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_du_20260906T1736/pass1.dart` + `pass1.json` (C1/C3/C4/D1; draws fixture)
- `tool/redteam_blind_du_20260906T1736/pass2.dart` + `pass2.json` (draws reais)
- `tool/redteam_blind_du_20260906T1736/confirm_p2.json` — hitch agora `sold`; live_only ainda `available`
- `tool/redteam_blind_du_20260906T1736/cleanup.dart`

**NÃO CORRIGIR.**

```
AUDITOR: REDTEAM_BLIND_DU_RAFFLE_HUB_POS_DNDS_v1
probes_na_tabela: 16 · classes_novas: 10
VEREDICTO: FAIL_P2
```

RESUMO_NUMERICO: P0=0 P1=0 P2=2 P3=0 TOTAL=2
