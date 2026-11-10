# FROZEN_REPORT — RED TEAM CEGO EA · rifa / Hub / stock / convert / hitch / live_item · POS_DTDY

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 0

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_EA_RAFFLE_HUB_POS_DTDY_v1
FROZEN_AT: 2026-09-06T18:30:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [EA1, EA2, EA3, EA4, EA5, EA6, EA7]
probes_na_tabela: 16
classes_novas: 10
races: 3
stripe_test_pago: true
draw_real_com_bilhetes: true
VEREDICTO: PASS_CEGO_SATURADO
prefix: RTEA-20260906T1823
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `pi_3UCjr2H7FWYUN3jh1pcN7bxU` succeeded) · JWT B1/S1 + B2 · `service_role` só fixture / observação / restore / end_live. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

Draws reais com rifa **active**, join+bilhetes, close, sorteio. FOMO / welcome / Hub hide live accepted clássico **não** na tabela (anti-atrofia). A1 qty=1 Hub 0 + live_item sold = **1 linha reteste** residual do fecho DTDY.

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

Nenhum. `findings: []`.

Os dois P2 do DU (hitch `available` no instante do sorteio; live_only `available` sem SKU) **não** reproduzem: após `drawn` o cartão do directo fica `sold` + `is_active=false`; `batata_recompute_live_item_status` devolve `sealed`/`raffle_drawn` e **não** reabre `available`.

--------------------------------------------------
## TABELA DE PROVAS (16)
--------------------------------------------------

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Hub/CPI | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|------------|------------------|--------------|
| A1 | EA-A | draw qty=1 hitch + tickets | draw **200** drawn; insert **400** hold | Hub **0**; qty 1→0 sold; li **sold** inactivo | **HOLD** residual | não |
| A2 | EA-A | winner_count=2 stock=2 | draw **200** 2 winners; insert **400** hold | Hub **0**; qty 2→0; li **sold** | **HOLD** | **SIM** |
| A3 | EA-A | draw live_only sem product_id | draw **200** drawn | li **sold** inactivo; product_id null; Hub n/a | **HOLD** | **SIM** |
| A4 | EA-A | draw 2× | 2.º **400** `invalid_status` | nWin=**1** | **HOLD** residual | não |
| A5 | EA-A | JWT buyer draw | **400** `not_allowed` | nWin inalterado até seller draw | **HOLD** | não |
| B1 | EA-B | award + draw∥CPI qty=1 | draw **200**; CPI **400** marked sold | Hub 0 qty=0; li sold | **HOLD** | **SIM** race |
| B2 | EA-B | após drawn: insert/CPI | insert **400** hold; CPI n/a | Hub 0 qty=0 | **HOLD** | **SIM** |
| B3 | EA-B | leftover qty=3 winners=1 | draw **200** | qty **2**; Hub **1**; insert leftover OK; li **sold** | **HOLD** | **SIM** |
| B4 | EA-B | refund/cancel premio_rifa | prize_n=**0**; rf n/a | Hub **0** qty 0→0 (não restaurou) | **HOLD** | **SIM** |
| C1 | EA-C | convert pending ∥ accept | convert **403** function denied; accept **200** | r1 pending; r2 accepted; ≠converted | **HOLD** | não race |
| C2 | EA-C | accept hitch + rifa mesmo SKU | unlist **200**; acc **200**; nWin=**0** | Hub 0 listed=false; qty 1; double_claim=false | **HOLD** | **SIM** race |
| C3 | EA-C | partilhar sem rifa | **200** `raffle_not_found` ×2 | tickets=0 winners=0 | **HOLD** residual | não |
| C4 | EA-C | share com rifa + forge entry | join 1→ share **2**; POST entries **403** RLS; award JWT B2 deny | tAfter=2 | **HOLD** | **SIM** |
| D1 | EA-D | pago 4242 SKU não-prémio | e2e **200** `pi_3UCjr2…` succeeded | status `pago`; qty leftover **1**; Hub **1**; 590¢ | **HOLD** | não |
| D2 | EA-D | prize_orders[] vs seal.ok | draw prize_orders **[]**; seal **ok** winners=1 li sold | Hub **0** qty=0 | **HOLD** | **SIM** |
| D3 | EA-D | forçar recompute após draw | seller/svc **sealed** sold; buyer **not_allowed** | li sold→sold; PATCH seller reabre até recompute; buyer PATCH 0 rows | **HOLD** | **SIM** |

EA-A: 5 · EA-B: 4 · EA-C: 4 · EA-D: 3 · **total 16**.

`classe_nova=SIM`: A2, A3, B1, B2, B3, B4, C2, C4, D2, D3 → **10** (≥4).  
Races: B1 draw∥CPI, C1 convert∥accept, C2 award∥unlist → **3** (≥3).  
Residual clássico A1+A4+C3 = 3/16 = 19% ≪ 40%. **ATROFIA: NÃO.**

Efeito BD obrigatório: **sim** — draws reais com bilhetes (A1/A2/A3/B3…); D1 pago Stripe TEST 4242 leftover Hub.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| FOMO / welcome / Hub hide accepted clássico | **não corridos** (anti-atrofia) |
| A1 qty=1 Hub 0 + live_item sold | reteste 1 linha: qty 0 sold listed=false insert 400; li sold inactivo |
| A3 live_only | DU P2-2 **fechado**: sold + recompute sealed |
| D3 recompute | seller/svc sealed; buyer `not_allowed`; após PATCH seller `available`, recompute `raffle_drawn` volta `sold` |
| PATCH live_item JWT vendedor | dono do cartão consegue `available` via REST; comprador **0 rows** (RLS); recompute reseleia — não é caminho de terceiro |
| PATCH live_raffles JWT vendedor | **403** RLS |
| prize_orders vazio | selo **ainda** fecha Hub + live_item |
| A5 buyer draw | `not_allowed` |
| A4 2.º draw | `invalid_status` nWin=1 |
| A2 wc=2 | qty 0 Hub 0 insert 400 li sold |
| B1 race CPI | 400 marked sold; Hub 0 li sold |
| B2 insert pós-drawn | 400 hold |
| B3 leftover | qty 3→2 Hub lista resto; cartão directo sold (selo DTDY) |
| B4 sem premio_rifa | Hub não restaurou |
| C1 convert JWT | 403 function denied |
| C2 nWin=0 nesta corrida | Hub já 0 via unlist; accept hitch sem vencedor; sem double_claim |
| C3 sem rifa | `raffle_not_found` |
| C4 forge | RLS 42501; tickets B1=2 |
| D1 4242 | pago + leftover coerente |

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| EA1 draw | SIM A3/A4/A5 | não |
| EA2 Hub | SIM A1/B3 | não |
| EA3 hold | SIM B2/B4/C1 | não |
| EA4 live_item | SIM D3/B1/A3 | não |
| EA5 multi-winner | SIM A2 + C2 hitch | não |
| EA6 forge | SIM A5/C3/C4 | não |
| EA7 caixa | SIM D1/D2 | não |

Lentes **7/7**.

--------------------------------------------------
## INVARIANTES
--------------------------------------------------

Após `drawn` hitch qty=1: Hub 0, `is_sold`, hold bloqueia insert, CPI «marked sold», live_item `sold`+inactivo. `batata_recompute_live_item_status` **não** reabre `available` enquanto a rifa está `drawn` (mesmo depois do vendedor PATCH REST). Comprador JWT: draw `not_allowed`; recompute `not_allowed`; PATCH live_item 0 rows. live_only sem `product_id` também `sold`. Multi-winner stock=2 consome 2. Draw 2.º `invalid_status`. Partilhar sem rifa ≠ bilhetes; com rifa +1 ticket; forge entry RLS. Convert JWT autenticado 403. Leftover qty=3 winners=1 → qty=2 Hub lista resto; cartão directo sold. Pago 4242 leftover Hub 1. `prize_orders: []` **não** impede o selo.

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_ea_20260906T1823/pass1.dart` + `pass1.json`
- `tool/redteam_blind_ea_20260906T1823/confirm.dart` + `confirm.json` — buyer PATCH 0 rows; seller PATCH reabre até recompute `raffle_drawn`
- `tool/redteam_blind_ea_20260906T1823/_rtea.dart`

**NÃO CORRIGIR.**

```
AUDITOR: REDTEAM_BLIND_EA_RAFFLE_HUB_POS_DTDY_v1
probes_na_tabela: 16 · classes_novas: 10
VEREDICTO: PASS_CEGO_SATURADO
```

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
