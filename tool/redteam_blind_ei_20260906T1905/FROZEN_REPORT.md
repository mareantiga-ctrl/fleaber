# FROZEN_REPORT — RED TEAM CEGO EI · stock / Hub / hold · POS_OPEN_MVP

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
AUDITOR: REDTEAM_BLIND_EI_STOCK_HUB_POS_OPEN_v1
FROZEN_AT: 2026-09-06T19:20:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [EI-A, EI-B, EI-C, EI-D]
probes_na_tabela: 16
classes_novas: 11
races: 7
stripe_test_pago: true
VEREDICTO: PASS_CEGO_SATURADO
prefix: RTEI-20260906T1905
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `pi_3UCkZTH7FWYUN3jh0SUwGV0u` leftover qty 2→1 Hub 1; PI `pi_3UCkZXH7FWYUN3jh115prdlF` qty=1 sold Hub 0) · JWT B1/S1 + B2 + S2 · `service_role` só fixture / observação / restore / end_live. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

Pass1 D3 GET imediato Hub listed `[]` com `products.quantity=2` — **P2-D3-HUB-QTY retractado**: confirm `batata_product_hub_sellable=true`, Hub buyer+anon **1 / 0 / 0**.

FOMO deny **não** na tabela. Hub hide sold clássico = **1 linha residual** (B1).

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

Nenhum. `findings: []`.

P2-D3-HUB-QTY (pass1) **retractado** — ver D3 + `confirm_d3.json`.

--------------------------------------------------
## TABELA DE PROVAS (16)
--------------------------------------------------

| probe_id | poço | payload/resumo | HTTP/RPC | stock/BD | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|----------|------------------|--------------|
| A1 | EI-A | 2 buyers insert qty=1 ∥ | B1 **400** `order_hold_exceeds_stock` · B2 **201** | claims=**1** held=**1** | **HOLD** race | não |
| A2 | EI-A | 2 buyers CPI qty=1 ∥ | B1 CPI **200** `cs_test_a1SHV0…` · B2 insert **400** hold | claims=1 cs=**1** | **HOLD** race | **SIM** |
| A3 | EI-A | bag B1 ∥ single B2 mesmo SKU | bag **200** `cs_test_a1yCJX…` · B2 insert deny | claims=**1** held=1 | **HOLD** race bag∥Hub | **SIM** |
| A4 | EI-A | favorite + hold + 2.º | fav **201** · B1 **201** · B2 **400** hold | claims=1 fav_n=1 Hub 0 | **HOLD** | **SIM** |
| A5 | EI-A | cancel hold → Hub restore | ins **201** · cancel **200** | Hub hold **0** → after **1**; held 1→0 | **HOLD** | não |
| B1 | EI-B | sold+listed vs Hub | buyer **200 []** · anon **200 []** | qty=0 sold listed | **HOLD** residual | não |
| B2 | EI-B | leftover qty 2→1 após pago | e2e **200** PI `pi_3UCkZT…` succeeded | qty **2→1** Hub **1** applied=1 | **HOLD** | não |
| B3 | EI-B | rifa drawn ∥ CPI | draw **200** drawn · CPI **400** marked sold | Hub **0** qty=0 li **sold** nWin=1 | **HOLD** race | **SIM** |
| B4 | EI-B | unlist ∥ CPI | unlist **200** · CPI **400** not listed | listed=false Hub **0** claims=1 | **HOLD** race | **SIM** |
| B5 | EI-B | end_live ∥ bag hitch | end **200** ended · bag **200** `cs_test_a1KkUZ…` | claims=**1** Hub 0 (hold) | **HOLD** race | **SIM** |
| C1 | EI-C | bag 6∥4 overlap | 6 **400** contention · 4 **200** `cs_test_a1rxdz…` | doubleClaim=**0** held=1/SKU | **HOLD** race | **SIM** |
| C2 | EI-C | bag cross-seller | **400** one seller | sem cs_ | **HOLD** | **SIM** |
| C3 | EI-C | qty hostil 99 body | PATCH **403** immutable · CPI **200** qty efectiva 1 | ord_qty=**1** prod_qty=**1** | **HOLD** | **SIM** |
| D1 | EI-D | pago 4242 + Hub | e2e **200** `pago` 590¢ | qty leftover **1** Hub **1** | **HOLD** | não |
| D2 | EI-D | 2.º insert após pago qty=1 | PI `pi_3UCkZX…` · insert **400** hold | qty=0 sold Hub **0** | **HOLD** | **SIM** |
| D3 | EI-D | Hub public vs products qty | pass1 GET imediato listed `[]`; **confirm** Hub **1/0/0** | qty 2 / 0 / 3 · sellable true | **HOLD** | **SIM** |

EI-A: 5 · EI-B: 5 · EI-C: 3 · EI-D: 3 · **total 16**.

`classe_nova=SIM`: A2, A3, A4, B3, B4, B5, C1, C2, C3, D2, D3 → **11** (≥4).  
Races `Future.wait`: A1, A2, A3, B3, B4, B5, C1 → **7** (≥4: 2 buyers, bag∥Hub, unlist∥CPI, rifa∥CPI).  
Residual clássico B1 Hub hide sold = 1/16 = 6% ≪ 50%. FOMO **0**. **ATROFIA: NÃO.**

Efeito BD obrigatório: **sim** — inserts/holds reais; 2× Stripe TEST 4242; draw real com 5 bilhetes; Hub leftover coerente.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| FOMO deny | **não corrido** (anti-atrofia) |
| B1 Hub hide sold clássico | 1 linha residual: sold+listed Hub 0 buyer+anon |
| A1 2 insert qty=1 | 1× 201 + 1× 400 `order_hold_exceeds_stock`; held=1 |
| A2 2 CPI | 2.º nem chega a order; 1 `cs_` |
| A3 bag∥single | 2.º insert recusado antes do CPI; 1 claim no SKU |
| A4 favorite | fav ≠ stock extra; 2.º 400 |
| A5 cancel | Hub 0 durante hold, 1 após cancelado; held=0 |
| B2/D1 4242 leftover | qty 2→1 Hub 1 `pago` 590¢ |
| B3 draw∥CPI | CPI marked sold; Hub 0 li sold |
| B4 unlist∥CPI | CPI not listed; Hub 0 |
| B5 end_live∥bag | 1 cs_ bag; 1 claim; live ended |
| C1 6∥4 | contention no de 6; stock 1 dono/SKU (mutex órfão = EF/DZ, não oversell EI) |
| C2 cross-seller | 400 one seller |
| C3 qty 99 | PATCH 403; ledger qty=1 |
| D2 pós-pago | 400 hold; Hub 0 sold |
| D3 GET imediato [] | **retractado**: confirm Hub 1/0/0 sellable true |

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| EI-A hold 2 buyers | SIM A1–A5 | não |
| EI-B Hub / live | SIM B1–B5 | não |
| EI-C bag stock | SIM C1–C3 | não |
| EI-D caixa | SIM D1–D3 | não |

Lentes **4/4**.

--------------------------------------------------
## INVARIANTES
--------------------------------------------------

qty=1 → ≤1 hold/venda válida (`order_hold_exceeds_stock` / CPI marked sold / not listed). Hub esconde sold e SKU sem stock efectivo; restaura após cancel. Overlap 6∥4 não cria 2 claims no mesmo SKU. Cross-seller bag deny. qty hostil 99 não altera ledger. Pago 4242 leftover Hub coerente; 2.º insert após qty=1 pago recusado. Rifa drawn∥CPI não deixa o prémio comprável.

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_ei_20260906T1905/pass1.dart` + `pass1.json`
- `tool/redteam_blind_ei_20260906T1905/confirm_d3.dart` + `confirm_d3.json` — Hub listed 1 · sold 0 · unlisted 0
- `tool/redteam_blind_ei_20260906T1905/_rtei.dart`

**NÃO CORRIGIR.**

```
AUDITOR: REDTEAM_BLIND_EI_STOCK_HUB_POS_OPEN_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: 16 · classes_novas: 11 · races: 7
VEREDICTO: PASS_CEGO_SATURADO
```

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
