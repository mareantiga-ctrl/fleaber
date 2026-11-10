# FROZEN_REPORT — RED TEAM CEGO EP · multi-buyer / Hub / live / stock · POS_OPEN_GATE

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
AUDITOR: REDTEAM_BLIND_EP_MULTI_BUYER_STRESS_POS_OPEN_v1
FROZEN_AT: 2026-09-06T20:05:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [EP-A, EP-B, EP-C, EP-D, EP-E]
probes_na_tabela: 24
classes_novas: 18
races: 11
stripe_test_pago: true
draw_real_com_bilhetes: true
actors: 3 buyers + 2 sellers
VEREDICTO: PASS_CEGO_SATURADO
prefix: RTEP-20260906T1952
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `pi_3UClIl…` leftover 3→2 Hub 1; `pi_3UClIo…` 2→1 Hub 1; `pi_3UClIy…` qty=1 Hub 0; `pi_3UClJa…` 2.º deny; `pi_3UClJe…` refund∥leftover; `pi_3UClJk…` chat 590¢; saco `setup_paid_bag` `pi_3UClJW…` 1115¢ leftover Hub 1+1) · JWT B1/S1 + B2 + B3 + S2 · `service_role` só fixture / observação / restore / end_live. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

Pass1 B4 `sellable=true` em SKU unlisted — **P2-B4-HUB-SELLABLE retractado**: RPC `batata_product_hub_sellable` = stock−held>0 (contrato SQL); Hub view exige ainda `listed && !sold`. Confirm Hub listed 1/1 · sold 0/0 · unlisted 0/0 (buyer=anon).

FOMO deny **não** na tabela. Hub hide sold clássico = **1 linha residual** (B1). Draw qty=1 selo = **1 residual** (C1). Dual bag create **não** reproduziu: D1 6∥4 fail-closed (`400 overlapping bag session` + 1 `cs_`).

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

Nenhum. `findings: []`.

P2-B4-HUB-SELLABLE (pass1) **retractado** — ver B4 + `confirm_b4.json`.

--------------------------------------------------
## TABELA DE PROVAS (24)
--------------------------------------------------

| probe_id | poço | payload/resumo | HTTP/RPC | stock/BD | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|----------|------------------|--------------|
| A1 | EP-A | 3 buyers insert qty=1 ∥ | B1 **201** · B2 **400** hold · B3 **400** hold | claims=**1** held=**1** | **HOLD** race | **SIM** |
| A2 | EP-A | 2 buyers CPI∥CPI qty=1 | B1 CPI **200** `cs_test_a12Z0l…` · B2 insert **400** hold | claims=1 cs=**1** | **HOLD** race | não |
| A3 | EP-A | bag B1 ∥ insert B2 ∥ insert B3 | bag **200** `cs_test_a1ZrHl…` · B2/B3 **400** hold | claims=**1** | **HOLD** race | **SIM** |
| A4 | EP-A | favorite+hold+2.º+3.º | fav **201** · B1 **201** · B2/B3 **400** | claims=1 fav_n=1 Hub 0 | **HOLD** race | **SIM** |
| A5 | EP-A | cancel → Hub restore → 2.º claim | ins **201** · cancel **200** · B2 **201** | Hub hold **0** → after **1**; 2.º ok | **HOLD** | **SIM** |
| A6 | EP-A | qty hostil 99 PATCH+CPI | PATCH **403** immutable · CPI **200** qty=1 | ord_qty=**1** prod_qty=**1** | **HOLD** | não |
| A7 | EP-A | cross-seller bag | **400** one seller | sem cs_ | **HOLD** | não |
| B1 | EP-B | sold+listed vs Hub vs insert | buyer **200 []** · anon **200 []** · insert **400** hold | qty=0 sold listed | **HOLD** residual | não |
| B2 | EP-B | leftover 3→2→1 cadeia pagos | e2e **200** PI `pi_3UClIl…` + `pi_3UClIo…` | qty **3→2** Hub **1**; **2→1** Hub **1** | **HOLD** | **SIM** |
| B3 | EP-B | unpublish mid-CPI + mid-tip | unpub **200** · CPI **200** `cs_test_a13FiT…` · tip sem cs | claims=**1** qty=2 restored published | **HOLD** race | **SIM** |
| B4 | EP-B | Hub anon vs buyer vs sellable RPC | listed Hub **1/1** · sold **0/0** · unlisted **0/0** | sellable true / false / true (stock-only) | **HOLD** | **SIM** |
| B5 | EP-B | Hub 0 após rifa + após pago | draw **200** drawn nWin=1 · PI `pi_3UClIy…` pago | Hub **0** qty=0 li **sold**; pago Hub **0** | **HOLD** | **SIM** |
| C1 | EP-C | draw qty=1 + live_item ≠ available | draw **200** drawn · insert **400** hold | Hub **0** qty=0 li **sold** nWin=1 | **HOLD** residual | não |
| C2 | EP-C | winner_count=2 stock=2 | draw **200** 2 winners · insert **400** hold | Hub **0** qty **2→0** li **sold** | **HOLD** | **SIM** |
| C3 | EP-C | draw∥CPI∥insert | draw **200** drawn · CPI sem cs_ · insert **400** | Hub **0** qty=0 li **sold** | **HOLD** race | **SIM** |
| C4 | EP-C | hitch accept ∥ bag outro SKU | acc **200** accepted · bag **200** `cs_test_a1yK00…` | hitch_claims=**0** bagDouble=**0** | **HOLD** race | **SIM** |
| C5 | EP-C | end_live∥bag∥Hub refresh | end **200** ended · bag **200** `cs_test_a1rMV8…` | claims=**1** Hub 0 | **HOLD** race | **SIM** |
| C6 | EP-C | partilhar sem/com rifa + forge | ghost **400** uuid · join+share t=**2** · POST **403** RLS | tickets fantasma=0 forged=false | **HOLD** | **SIM** |
| D1 | EP-D | 6∥4 fail-closed / ≤1 | 6 **400** overlapping · 4 **200** `cs_test_a125WS…` | dual=**false** doubleClaim=**0** | **HOLD** race | **SIM** |
| D2 | EP-D | expand (esperado 400) | sub **200** `cs_test_a1QNh7…` · super deny (sid null) | dual=**false** expandDenied=**true** | **HOLD** race | **SIM** |
| D3 | EP-D | bag pago + Hub leftover | e2e **200** PI `pi_3UClJW…` 1115¢ | qty **3→2** Hub **1+1** ambas `pago` | **HOLD** | **SIM** |
| E1 | EP-E | pago 4242 + 2.º deny | PI `pi_3UClJa…` · insert **400** hold | qty=0 sold Hub **0** | **HOLD** | não |
| E2 | EP-E | refund∥nova compra leftover | refund **200** · CPI **200** `cs_test_a1TRKF…` | claims=**1** qty **2** Hub **1** | **HOLD** race | **SIM** |
| E3 | EP-E | chat card vs order após pago | e2e **200** PI `pi_3UClJk…` 590¢ · card JWT falhou | status `pago` Hub **1** leftover **1** | **HOLD** | **SIM** |

EP-A: 7 · EP-B: 5 · EP-C: 6 · EP-D: 3 · EP-E: 3 · **total 24**.

`classe_nova=SIM`: A1, A3, A4, A5, B2, B3, B4, B5, C2, C3, C4, C5, C6, D1, D2, D3, E2, E3 → **18** (≥8).  
Races `Future.wait`: A1, A2, A3, A4, B3, C3, C4, C5, D1, D2, E2 → **11** (≥8).  
Residual clássico B1+C1 = 2/24 = 8% ≪ 50%. FOMO **0**. Dual bag **0**. **ATROFIA: NÃO.**

Efeito BD obrigatório: **sim** — inserts/holds reais 3 buyers; 6× Stripe TEST 4242 + 1× bag pago; draws reais (C1/C2/C3/B5) com bilhetes; Hub leftover coerente.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| FOMO deny | **não corrido** (anti-atrofia) |
| B1 Hub hide sold clássico | 1 linha residual: sold+listed Hub 0 buyer+anon; insert 400 |
| C1 draw qty=1 selo | 1 residual: li sold Hub 0 insert 400 |
| A1 3 insert qty=1 | 1× 201 + 2× 400 `order_hold_exceeds_stock`; held=1 |
| A2 2 CPI | 2.º nem chega a order; 1 `cs_` |
| A3 bag∥B2∥B3 | 2.º/3.º insert recusados; 1 claim no SKU |
| A4 favorite | fav ≠ stock extra; 2.º+3.º 400 |
| A5 cancel + 2.º | Hub 0 durante hold, 1 após cancel; B2 claim ok |
| A6 qty 99 | PATCH 403; ledger qty=1 |
| A7 cross-seller | 400 one seller |
| B2 4242 cadeia | qty 3→2 Hub 1; 2→1 Hub 1 |
| B3 unpublish∥CPI∥tip | claims=1; hub restored published; SKU em hold Hub 0 |
| B4 GET sellable unlisted true | **retractado**: contrato stock-only; Hub 0/0 unlisted |
| B5 rifa+pago | Hub 0 qty=0 li sold; pago Hub 0 |
| C2 wc=2 | qty 0 Hub 0 insert 400 li sold nWin=2 |
| C3 draw∥CPI∥insert | CPI sem cs; insert 400; Hub 0 |
| C4 hitch∥bag | accept isolado do bag noutro SKU; sem double claim |
| C5 end_live∥bag | 1 cs_ bag; 1 claim; live ended |
| C6 share+forge | ghost 400; tAfter=2; forge RLS |
| D1 6∥4 | **fail-closed**: overlapping 400 no de 6; 1 cs_ no de 4; 1 dono/SKU |
| D2 expand | 2.º deny (sid null); dual=false |
| D3 bag pago | 1115¢ leftover Hub 1+1 proporcional 335+780 |
| E1 pós-pago | 400 hold; Hub 0 sold |
| E2 refund∥leftover | claims=1 qty restaurou 2 Hub 1; sem 2 donos |
| E3 chat card JWT | post card falhou (RLS); order pago 590¢ Hub leftover coerente — não é mismatch de amount |

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| EP1 multi-buyer | SIM A1–A7 | não |
| EP2 Hub | SIM B1–B5 | não |
| EP3 rifa | SIM C1–C6 | não |
| EP4 bag | SIM D1–D3 | não |
| EP5 race | SIM A1/A2/A3/A4/B3/C3/C4/C5/D1/D2/E2 | não |
| EP6 caixa | SIM E1–E3 + B2 + D3 | não |

Lentes **6/6**.

--------------------------------------------------
## INVARIANTES
--------------------------------------------------

qty=1 → ≤1 hold/venda válida com 3 buyers (`order_hold_exceeds_stock`). Favorite ≠ stock extra. Cancel restaurou Hub e libertou o 2.º claim. Cross-seller bag deny. qty hostil 99 não altera ledger. Hub esconde sold e unlisted (buyer=anon). Leftover 3→2 e 2→1 Hub 1. Rifa drawn sela live_item `sold` + Hub 0; wc=2 consome qty=2. Draw∥CPI∥insert não deixa 2 donos. Hitch accept não interfere com bag noutro SKU. end_live∥bag ≤1 claim. Share sem rifa ≠ bilhetes; forge entry RLS. Overlap 6∥4 **fail-closed** (não dual create). Expand subset→superset deny. Bag pago leftover Hub coerente. Pago 4242 qty=1 + 2.º deny. Refund∥leftover sem oversell.

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_ep_20260906T1952/pass1.dart` + `pass1.json`
- `tool/redteam_blind_ep_20260906T1952/confirm_b4.dart` + `confirm_b4.json` — Hub listed 1/1 · sold 0/0 · unlisted 0/0; sellable unlisted=true por contrato stock
- `tool/redteam_blind_ep_20260906T1952/_rtep.dart`

**NÃO CORRIGIR.**

```
AUDITOR: REDTEAM_BLIND_EP_MULTI_BUYER_STRESS_POS_OPEN_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: 24 · classes_novas: 18 · races: 11
VEREDICTO: PASS_CEGO_SATURADO
```

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
