# FROZEN_REPORT — REDTEAM_BLIND_ER_BAG_SINGLE_RETEST_v1

## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 1
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 1

1. P0 dinheiro irreversível? NÃO
2. Quantos P0: 0
3. P1 caminho explorável? SIM
4. Quantos P1: 1
5. P2 hygiene? NÃO
6. Quantos P2: 0
7. P3 baixo risco? NÃO
8. Quantos P3: 0

RESUMO_NUMERICO: P0=0 P1=1 P2=0 P3=0 TOTAL=1

```
AUDITOR: REDTEAM_BLIND_ER_BAG_SINGLE_RETEST_v1
FROZEN_AT: 2026-09-06T20:40:16+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 14
classes_novas: 5
races_bag_single: 6
stripe_test_pago: true
dual_cs_fresh_buyer: true
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTER-20260906T2031-` · pasta: `tool/redteam_blind_er_20260906T2031/`.  
Atacante CPI: buyer JWT fresco (`fd523d92-bdb6-4883-8b5f-a828628091cf`) + confirm buyer4 (`1dcf7c4f-d876-4d4d-b1ed-8938d912264c`). `service_role` só fixture/observação.

GATE: 2× HTTP 200 + 2 `cs_` distintas `reused=false` = P1 (bloqueia Fase 4). Esperado: ≤1 `cs_` útil (200+400 / 400+200 / reused mesmo sid). **Nunca** 2 creates.

Reteste vs EL/EM/EN: **6∥4 e expand continuam fechados**. Saco idêntico e shrink **≤1**. **bag∥single no primeiro checkout do comprador continua a entregar 2 `cs_test_`.** Depois do primeiro claim, as corridas seguintes no mesmo comprador passam a reuse (1 sid). **Não** pagámos as duas.

---

## P1-1 — Saco e artigo avulso ao mesmo tempo: dois links no primeiro checkout

**O que isto é:** o comprador pede o pagamento do saco e, no mesmo instante, o pagamento avulso de um artigo que está no meio do saco. O cadeado (já fechado em 6∥4 e no expand) tinha de entregar no máximo um link. Se o avulso respeitasse o claim do saco, o segundo pedido reutilizava a Session ou era recusado.

**Quem / onde:** comprador (JWT fresco, sem checkout prévio) no checkout do saco vs checkout avulso da mesma linha. Stripe TEST.

**O que fizemos:**
- A1: saco ABCDE ∥ avulso C, t=0, comprador recém-criado (buyer3).
- A2: saco primeiro → 50 ms → avulso C (mesmo comprador, ainda na primeira ronda).
- Confirm no mesmo buyer3: A1 e A2 **já não** dual (reuse).
- Burst 8× A1 no mesmo buyer3: 0/8 dual.
- Fresh buyer4: A1 t=0 **outra vez dual**.

**Esperado vs resultado**
- API A1 (buyer3 fresco): esperado ≤1 `cs_` · visto **2** `cs_test_` distintas, ambas HTTP 200, `reused=false` (`a1QdOiSx…` + `a1gGqNr9…`). Ledger das 5 linhas = saco; órfã do avulso. Settle **402** nas duas.
- API A2 (50 ms bag first): **2** `cs_test_` (`a1rycCkF…` + `a1fdFPF5…`), `reused=false`. Ledger = saco.
- API A3 (avulso primeiro → 50 ms → saco): **1** `cs_` (`a1nAi5Vr…`); saco `reused=true`.
- API A4–A6 (já com claim no comprador): **1** `cs_` reused.
- Confirm + burst no mesmo comprador: **1** `cs_`; saco `reused=true`, avulso cria.
- Fresh buyer4: **2** `cs_test_` (`a1LGgPFm…` + `a1z70B0Q…`), `reused=false`. Ledger 5/5 = saco.
- Stripe: sem `sk_test_` local. **Não pagámos as duas.**

**Conclusão:** **P1** — no primeiro checkout paralelo saco∥avulso de um comprador sem claim, o cliente recebe dois links. Depois do primeiro claim, o avulso (ou o saco) reutiliza. Não é P0: as duas capturas **não** aconteceram. 6∥4 / expand **fecharam**. Dual no comprador fresco **bloqueia Fase 4**.  
**Prova:** `probes.json` A1/A2 + `fresh_buyer_a1.json` + `burst_a1.json` (0/8 no mesmo comprador).

---

## Anti-atrofia

Exactos **não corridos / não contados**:
- 4∥2 clássico — **não** na tabela
- bizum — **não**
- multibanco — **não**
- settle unpaid 402 — GET 402 nas Sessions **não** é finding

Fechos documentados (FAIL = ataque bloqueado / esperado):
- **A3** avulso primeiro → 50 ms → saco → 1 `cs_` reused
- **A4** bag∥single@200ms∥bag → 1 `cs_`
- **A5** bag ABC ∥ avulso B t=0 (já com claim) → 1 `cs_`
- **A6** bag de 2 first → 200 ms → avulso → 1 `cs_`
- **B1** 6∥4 t=0 → 400 overlapping + 200 · 1 `cs_test_a1Q1JJFQ…`
- **B2** expand 50 ms → 200 + **400 overlapping** · 1 `cs_test_a1Pb3XcX…`
- **B3** 2× bag idêntico → 200 + 200 mesmo `cs_` (`reused=true`)
- **B4** shrink → 400 overlapping + 200 · 1 `cs_` (subset; nunca 2 creates)
- **C1** underpay → amount **2323** ¢ (catálogo)
- **C2** 2.º insert 400 `order_hold_exceeds_stock`
- **C3** pago 4242 coerente (`setup_paid_order`)
- **C4** 2 bags disjuntos → 2 `cs_` OK

HOLD na tabela = A1/A2 (um P1) = **2/14 = 14%** ≪ 40%. **Não** ATROFIA_ABORT.  
classe_nova=SIM: A2, A3, A4, A5, A6 (**5** ≥ 4).

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|-----------|------------------|--------------|
| A1 | ER-A | Future.wait bag ABCDE ∥ single C t=0 | 2× 200 duas `cs_` reused=false | ledger saco `a1QdOiSx…`; órfã `a1gGqNr9…`; fresh buyer4 dual | **HOLD** P1-1 | NÃO |
| A2 | ER-A | Future.wait bag first → 50ms → single C | 2× 200 duas `cs_` reused=false | ledger saco `a1rycCkF…`; órfã `a1fdFPF5…` | **HOLD** P1-1 | SIM |
| A3 | ER-A | Future.wait single C first → 50ms → bag | 200+200 **1** `cs_` reused | só linha C `a1nAi5Vr…` | FAIL | SIM |
| A4 | ER-A | Future.wait bag ∥ single +200ms ∥ bag | 3× 200 **1** `cs_` | `a1nSLzJ5…` reused | FAIL | SIM |
| A5 | ER-A | Future.wait bag ABC ∥ single B t=0 | 200+200 **1** `cs_` | `a1pbwHtx…` (já com claim) | FAIL | SIM |
| A6 | ER-A | Future.wait bag de 2 first → 200ms → single | 200+200 **1** `cs_` | `a1dELe4X…` | FAIL | SIM |
| B1 | ER-B | Future.wait bag 6∥4 t=0 | 400 overlapping + 200 | 1 `cs_test_a1Q1JJFQ…` | FAIL | NÃO |
| B2 | ER-B | Future.wait subset → 50ms → expand | 200 + **400 overlapping** | 1 `cs_test_a1Pb3XcX…` | FAIL | NÃO |
| B3 | ER-B | Future.wait 2× bag idêntico | 200+200 mesmo `cs_` reused | 1 `cs_test_a1pbXPqz…` | FAIL | NÃO |
| B4 | ER-B | Future.wait full → 50ms → shrink | 400 overlapping + 200 | 1 `cs_test_a1JuFTg8…` | FAIL | NÃO |
| C1 | ER-C | body total_eur=0 item_price=0.01 SKU 18€ | 200 **2323** ¢ | amount catálogo | FAIL | NÃO |
| C2 | ER-C | 2 buyers qty=1 | insert 2.º 400 stock | o2=null | FAIL | NÃO |
| C3 | ER-C | pago 4242 single/bag | e2e `setup_paid_order` 200 | `pago` PI `pi_3UClqqH7FWYUN3jh0WUH9Q1D` 590¢ qty 2→1 | FAIL | NÃO |
| C4 | ER-C | Future.wait 2 bags disjuntos | 200+200 duas `cs_` | A `a1zOGI9n…` B `a13MJse6…` | FAIL | NÃO |

Linhas na tabela: **14** (≥14). Races bag∥single: **6** (A1–A6; timings 0 / 50 / 200 ms; bag first; single first). Stripe TEST pago: **sim**. classe_nova=SIM: **5**.

HOLD na tabela = findings. FAIL = ataque bloqueado. SKIP = 0.

---

## Tácticas mínimas (quota)

1. Tabela ≥14: **14**
2. ≥5 races bag∥single (0 / 50 / 200 ms; single first; bag first): **6** (A1–A6)
3. Dual create 2×200 + 2 `cs_`: **sim** (A1, A2, fresh buyer4) → P1
4. ≥1 regressão 6∥4 e expand 400/≤1: **sim** (B1, B2)
5. ≥1 pago 4242 happy: **sim** (C3)
6. ≥4 classe_nova: **5** (A2–A6)

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → HTML Checkout tem `expired` no bundle JS (oráculo ingénuo inválido). Settle 402 nas úteis e nas órfãs.
- **Não pagámos as duas** Sessions — P1 (dois links), não P0.
- CPI 4242 directo (página Checkout) não liquidou; C3 usou `setup_paid_order` (Stripe TEST) — caixa coerente.
- Burst 8× no **mesmo** comprador após A1 **não** dual: o furo é o **primeiro** paralelo sem claim, não todas as corridas seguintes.
- Wallet seller 21,00→21,00 (e2e marcou `pago` + stock; saldo snapshot não moveu — não finding).
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_er_20260906T2031/_rter.dart`
- `tool/redteam_blind_er_20260906T2031/pass1.dart` + `pass1_findings.json` + `probes.json`
- `tool/redteam_blind_er_20260906T2031/confirm.dart` + `confirm.json`
- `tool/redteam_blind_er_20260906T2031/burst_a1.dart` + `burst_a1.json`
- `tool/redteam_blind_er_20260906T2031/fresh_a1.dart` + `fresh_buyer_a1.json`

```
AUDITOR: REDTEAM_BLIND_ER_BAG_SINGLE_RETEST_v1
VEREDICTO: FAIL_P1
```

RESUMO_NUMERICO: P0=0 P1=1 P2=0 P3=0 TOTAL=1
