# FROZEN_REPORT — REDTEAM_BLIND_GATE_BAG_SINGLE_v1

## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 0

1. P0 dinheiro irreversível? NÃO
2. Quantos P0: 0
3. P1 caminho explorável? NÃO
4. Quantos P1: 0
5. P2 hygiene? NÃO
6. Quantos P2: 0
7. P3 baixo risco? NÃO
8. Quantos P3: 0

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0

```
AUDITOR: REDTEAM_BLIND_GATE_BAG_SINGLE_v1
FROZEN_AT: 2026-09-07T09:05:00+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 12
classes_novas: 8
races_bag_single: 6
stripe_test_pago: true
dual_cs_fresh_buyer: false
dual_cs_pay_attempted: false
dual_cs_both_captured: false
hosted_bag_captured: false
hosted_orphan_captured: false
VEREDICTO: PASS_CEGO_SATURADO
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 aplicada nesta corrida · **sem patches**.  
Prefixo: `RTGATE-20260907T0856-` · pasta: `tool/redteam_blind_gate_20260907T0856/`.  
Atacante CPI: comprador fresco por corrida A1–A6 (`0a38d638-…` a `ce5d080f-…`). `service_role` só fixture/observação.

GATE: 2× HTTP 200 + 2 `cs_` distintas `reused=false` = P1 (bloqueia Fase 4). Esperado: ≤1 `cs_` útil. P0–P2=0 **e** A1–A4 sem dual → `PASS_CEGO_SATURADO`. Qualquer dual → `FAIL_P1`.

Reteste vs GATE 08:28 (FAIL_P1 no saco de 5 ∥ avulso): **A1/A2/A3 fecharam.** Saco de 5 ∥ avulso C em t=0, bag-first 50 ms e single-first 50 ms entrega **400 overlapping + 1 `cs_`**. Saco de 3 t=0 unifica. Stagger 200 ms unifica. 6∥4 e expand 400. Saco idêntico reused. Sem 2.ª Session a caçar. Sem oversell. Seller wallet 21,00 estável.

---

## Anti-atrofia

Exactos **não corridos / não contados**:
- 4∥2 clássico — **não** na tabela
- bizum / multibanco — **não** contar

Fechos (FAIL = ataque bloqueado / esperado):
- **A1** bag ABCDE ∥ single C t=0 fresco → 400+200 `overlapping` · **1** `cs_test_a17m5I9U…` · ledger 5 encomendas, 1 sid (só a linha C)
- **A2** bag first →50 ms→ single C fresco → 400+200 · **1** `cs_test_a1eNnqBN…`
- **A3** single C first →50 ms→ bag fresco → 200+400 · **1** `cs_test_a1Wh5123…`
- **A4** bag ABC ∥ single B t=0 fresco → 200+200 **1** `cs_` reused (`true,false`) `cs_test_a1vVQOAq…`
- **A5** bag∥single∥bag @200 ms → 200+200+400 **1** `cs_` `cs_test_a1oJU3As…`
- **A6** saco de 2 first →200 ms→ avulso → 200+200 **1** `cs_` reused `cs_test_a10pm1Ku…`
- **B1** 6∥4 t=0 fresco → 400+200 overlapping · 1 `cs_test_a1yqVBUg…` · 6 encomendas, 1 sid
- **B2** expand subset→50 ms→superset fresco → 200+400 `Checkout blocked: overlapping bag session.` · 1 `cs_test_a1Nl5cuo…`
- **B3** 2× bag idêntico fresco → 200+200 **1** `cs_` reused `cs_test_a1IfJ5US…`
- **C1** leftover e2e: `pago`, qty 2→1, Hub n=1, PI `pi_3UCxVKH7FWYUN3jh19uy4PGm`
- **C2** sem dual → nada a pagar na 2.ª
- **C3** 2.º insert `order_hold_exceeds_stock`

HOLD na tabela = **0/12 = 0%** < 40%. **Não** ATROFIA_ABORT.  
classe_nova=SIM: A1, A2, A3, A4, A5, A6, C1, C2 (**8**).

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|-----------|------------------|--------------|
| A1 | G-A | Future.wait bag ABCDE ∥ single C t=0 fresco | 400+200 overlapping · 1 `cs_` | 5 encomendas, 1 sid `a17m5I9U…` na linha C; resto `cs_` vazio | FAIL | SIM |
| A2 | G-A | Future.wait bag first →50ms→ single C fresco | 400+200 overlapping · 1 `cs_` | 5 encomendas, 1 sid `a1eNnqBN…` | FAIL | SIM |
| A3 | G-A | Future.wait single C first →50ms→ bag fresco | 200+400 overlapping · 1 `cs_` | 5 encomendas, 1 sid `a1Wh5123…` | FAIL | SIM |
| A4 | G-A | Future.wait bag ABC ∥ single B t=0 fresco | 200+200 **1** `cs_` reused | 3 encomendas, 1 sid `a1vVQOAq…` | FAIL | SIM |
| A5 | G-A | Future.wait bag ∥ single +200ms ∥ bag | 200+200+400 **1** `cs_` | 3 encomendas, 1 sid `a1oJU3As…` | FAIL | SIM |
| A6 | G-A | Future.wait bag de 2 first →200ms→ single | 200+200 **1** `cs_` reused | 2 encomendas, 1 sid `a10pm1Ku…` | FAIL | SIM |
| B1 | G-B | Future.wait bag 6∥4 t=0 fresco | 400+200 overlapping · 1 `cs_` | 6 encomendas, 1 sid `a1yqVBUg…` | FAIL | NÃO |
| B2 | G-B | expand subset→50ms→superset fresco | 200+400 `overlapping bag session` | 4 encomendas, 1 sid `a1Nl5cuo…` | FAIL | NÃO |
| B3 | G-B | Future.wait 2× bag idêntico fresco | 200+200 **1** `cs_` reused | 3 encomendas, 1 sid `a1IfJ5US…` | FAIL | NÃO |
| C1 | G-C | pago 4242 do link útil + Hub leftover | API 4242 falhou (sem `sk_test_`); e2e `setup_paid_order` 200 | `pago` qty=1 Hub n=1 PI `pi_3UCxVKH…` | FAIL | SIM |
| C2 | G-C | se dual: pagar 2.ª (caça P0) | sem 2.ª `cs_` em A1–A6 | dual_create=false | FAIL | SIM |
| C3 | G-C | 2 buyers qty=1 sem oversell | 2.º insert 400 `order_hold_exceeds_stock` | o2=null | FAIL | NÃO |

Linhas na tabela: **12**. Races `Future.wait` bag∥single: **6** (A1–A6). Stripe TEST pago: **sim** (C1 e2e). classe_nova=SIM: **8**.

HOLD na tabela = findings. FAIL = ataque bloqueado / caminho sem P0. SKIP = 0.

---

## Tácticas mínimas (quota)

1. Tabela ≥12: **12**
2. ≥5 races bag∥single (t=0, 50 ms, single-first, bag∥single∥bag, saco 3 e 5): **sim** (A1–A6)
3. Nunca 2× HTTP 200 com 2 `cs_` `reused=false`: **cumpriu A1–A6**
4. Se dual: tentar pagar a 2.ª (caça P0): **N/A** (0 dual) — C2 documenta a ausência
5. ≥1 regressão 6∥4 e ≥1 expand (ainda 400/≤1): **sim** (B1 400+200; B2 200+400)
6. ≥1 pago 4242 happy: **sim** (C1 e2e `pi_3UCxVKH…`)
7. ≥1 Hub leftover após pago: **sim** (qty 2→1, Hub n=1)

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → retrieve nativo / `pm_card_visa` na Session falhou; C1 via e2e `setup_paid_order`.
- pass1 abortou no mint `b2` (colisão de email com `ensureBuyer2`, harness — não é produto). A1–A6+B1 ficaram no stdout da pass1; B2/B3/C* na pass2; ledger cruzado em `confirm.json`.
- Seller wallet 21,00 estável (Δ=0).
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_gate_20260907T0856/_rtgate.dart`
- `tool/redteam_blind_gate_20260907T0856/pass1.dart` (A1–A6+B1 live)
- `tool/redteam_blind_gate_20260907T0856/pass2.dart` + `pass2_findings.json` + `probes.json`
- `tool/redteam_blind_gate_20260907T0856/confirm.dart` + `confirm.json` (1 `cs_` por buyer A1–B3; C1 leftover)

```
AUDITOR: REDTEAM_BLIND_GATE_BAG_SINGLE_v1
VEREDICTO: PASS_CEGO_SATURADO
```

**OK falar Fase 4.** Dual create saco ∥ avulso (t=0 e 50 ms, comprador fresco) **fechou** nesta ronda.

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
