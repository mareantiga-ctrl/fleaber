# FROZEN_REPORT — REDTEAM_BLIND_FA_CHECKOUT_SMOKE_PRE_P4_v1

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
AUDITOR: REDTEAM_BLIND_FA_CHECKOUT_SMOKE_PRE_P4_v1
FROZEN_AT: 2026-09-07T09:36:00+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 10
classes_novas: 6
races_bag_single: 1
stripe_test_pago: true
dual_cs_fresh_buyer: false
dual_cs_pay_attempted: false
dual_cs_both_captured: false
hosted_bag_captured: false
VEREDICTO: PASS_CEGO_SATURADO
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 aplicada nesta corrida · **sem patches**.  
Prefixo: `RTFA-20260907T0924-` · pasta: `tool/redteam_blind_fa_20260907T0924/`.  
Atacante CPI: comprador fresco por corrida (`70a11270-…` a `1358a7fd-…`). `service_role` só fixture/observação.

GATE: 2× HTTP 200 + 2 `cs_` distintas `reused=false` = P1 (pack falha). Esperado: ≤1 `cs_` útil. P0–P2=0 **e** A1 sem dual → `PASS_CEGO_SATURADO`. Qualquer dual → `FAIL_P1`.

Smoke vs GATE 08:56 (`PASS_CEGO_SATURADO`): **A1 a frio fechou de novo** — saco ABCDE ∥ avulso C t=0 → 400 overlapping + 200 · **1** `cs_`. 6∥4, expand, saco idêntico e shrink ≤1 create. CPI saco feliz ignora `amount=1` e sela 3341 ¢ (20 % conjunto + protecção sobre 12+13+14 €). Underpay avulso 18 € → 1955 ¢. Pago e2e `pago` qty 2→1, Hub n=1. Seller wallet 21,00 estável.

---

## Anti-atrofia

Exactos **não corridos / não contados**:
- 4∥2 clássico — **não** na tabela
- bizum / multibanco — **não** contar

Fechos (FAIL = ataque bloqueado / esperado):
- **A1** bag ABCDE ∥ single C t=0 fresco → 400+200 `overlapping` · **1** `cs_test_a1EeK4lY…` · ledger 5 encomendas, 1 sid (só a linha C)
- **A2** 6∥4 t=0 fresco → 400+200 overlapping · **1** `cs_test_a1fyXdjy…`
- **A3** expand subset→50 ms→superset fresco → 200+400 `Checkout blocked: overlapping bag session.` · **1** `cs_test_a1Jmz0cU…`
- **A4** 2× bag idêntico fresco → 200+200 **1** `cs_` reused (`false,true`) `cs_test_a1pDlWrN…`
- **B1** CPI saco 3 linhas `amount=1` → 200 · `amount_total` **3341** ¢ (= 39,00 € × 0,80 + 0,65 € + 5 %) · cliente 1 ¢ **não** selou
- **B2** pago 4242 via e2e `setup_paid_order` (API 4242 sem `sk_test_`) → `pago` qty 2→1 · PI `pi_3UCxw3H7FWYUN3jh0aD4FQL6`
- **B3** shrink após open → 200+200 **1** `cs_` reused `cs_test_a1cgYswR…` (nunca 2 creates)
- **C1** underpay body → amount **1955** ¢ (catálogo 18 € + protecção)
- **C2** 2 bags disjuntos t=0 → 200+200 **1** `cs_` `cs_test_a1V3KHLB…` (mutex serializa; bag B no ledger, bag A sem sid) — não 2 creates
- **C3** Hub n=1 após B2 leftover qty=1

HOLD na tabela = **0/10 = 0%** < 40%. **Não** ATROFIA_ABORT.  
classe_nova=SIM: A1, B1, B2, C1, C2, C3 (**6**).

pass1 marcou P0-B1 (3341 < 3900). **Retratado em confirm:** `amount_total` 3341 ¢ é o selo servidor (desconto conjunto 20 % do vendedor + taxa de protecção), não underpay. Produtos 12+13+14 €; `price_total` nas encomendas redistribuído 10,28+11,14+11,99 = 33,41 €.

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|-----------|------------------|--------------|
| A1 | FA-A | Future.wait bag ABCDE ∥ single C t=0 fresco | 400+200 overlapping · 1 `cs_` | 5 encomendas, 1 sid `a1EeK4lY…` na linha C; resto `cs_` vazio | FAIL | SIM |
| A2 | FA-A | Future.wait bag 6∥4 t=0 fresco | 400+200 overlapping · 1 `cs_` | 6 encomendas, 1 sid `a1fyXdjy…` | FAIL | NÃO |
| A3 | FA-A | expand subset→50ms→superset fresco | 200+400 `overlapping bag session` | 4 encomendas, 1 sid `a1Jmz0cU…` | FAIL | NÃO |
| A4 | FA-A | Future.wait 2× bag idêntico fresco | 200+200 **1** `cs_` reused | 3 encomendas, 1 sid `a1pDlWrN…` | FAIL | NÃO |
| B1 | FA-B | CPI saco 3 linhas amount=1 (catálogo 39 €) | 200 · amount_total **3341** ¢ | 3 linhas no mesmo `cs_test_a1jFfHgc…`; 20 % conjunto + protecção | FAIL | SIM |
| B2 | FA-B | pago 4242 (e2e; API 4242 falhou sem `sk_test_`) | e2e `setup_paid_order` 200 | `pago` qty=1 Hub n=1 PI `pi_3UCxw3H…` | FAIL | SIM |
| B3 | FA-B | shrink após open: full →300ms→ subset 2 | 200+200 **1** `cs_` reused | 4 encomendas, 1 sid `a1cgYswR…` | FAIL | NÃO |
| C1 | FA-C | body total_eur=0 item_price=0.01 amount=0 (SKU 18 €) | 200 · amount **1955** ¢ | extras ignorados; catálogo+protecção | FAIL | SIM |
| C2 | FA-C | Future.wait 2 bags disjuntos mesmo buyer | 200+200 1 `cs_` (mutex serializa) | bag B sid `a1V3KHLB…`; bag A `cs_` vazio | FAIL | SIM |
| C3 | FA-C | Hub n após B2 (1 sítio) | Hub HTTP 200 | qty=1 leftover; Hub n=1; `pago` | FAIL | SIM |

Linhas na tabela: **10**. Races `Future.wait` bag∥avulso: **1** (A1). Stripe TEST pago: **sim** (B2 e2e). classe_nova=SIM: **6**.

HOLD na tabela = findings. FAIL = ataque bloqueado / caminho sem P0. SKIP = 0.

---

## Tácticas mínimas (quota)

1. Tabela ≥10: **10**
2. Exactamente 1 race bag ABCDE ∥ single C t=0 fresco: **sim** (A1)
3. Dual 2× HTTP 200 + 2 `cs_` `reused=false` = P1: **não observado** (A1 400+200 · 1 `cs_`)
4. ≥1 6∥4 · ≥1 expand · ≥1 2× bag idêntico: **sim** (A2, A3, A4)
5. ≥1 pago 4242 (saco ou avulso) coerente: **sim** (B2 e2e `pago` qty↓ Hub n=1)
6. ≥3 classe_nova: **6** (A1, B1, B2, C1, C2, C3)

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → retrieve nativo / `pm_card_visa` na Session falhou; B2 via e2e `setup_paid_order`.
- C2 em paralelo no mesmo comprador: mutex devolveu **1** `cs_` (bag B) em vez de 2 Sessions disjuntas; bag A ficou sem sid. Não é dual create (1 `cs_`, não 2 `reused=false`). Residual do fail-closed por comprador — **não** contado como finding (ER: mutex serializa).
- Seller wallet 21,00 estável (Δ=0). Wallet «buyer» 61,10→0 = troca de actor mint, não débito.
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_fa_20260907T0924/_rtfa.dart`
- `tool/redteam_blind_fa_20260907T0924/pass1.dart` + `pass1_findings.json` + `probes.json`
- `tool/redteam_blind_fa_20260907T0924/confirm.dart` + `confirm.json` (B1 fórmula; C2 ledger)

```
AUDITOR: REDTEAM_BLIND_FA_CHECKOUT_SMOKE_PRE_P4_v1
VEREDICTO: PASS_CEGO_SATURADO
```

Fail-closed do saco **não** partiu checkout feliz nem overlap. A1 a frio sem dual.

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
