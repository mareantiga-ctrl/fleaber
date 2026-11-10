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
FROZEN_AT: 2026-09-06T21:18:47+01:00
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
Prefixo: `RTER-20260906T2112-` · pasta: `tool/redteam_blind_er_20260906T2112/`.  
Atacante CPI: comprador fresco por corrida A1–A6 (`b9ea2400-…` a `13156647-…`) + confirm `2da6e34a-…` / `9f473768-…`. `service_role` só fixture/observação.

GATE: 2× HTTP 200 + 2 `cs_` distintas `reused=false` = P1 (bloqueia Fase 4). Esperado: ≤1 `cs_` útil (200+400 / 400+200 / reused mesmo sid). **Nunca** 2 creates.

Reteste vs EL/EM/EN: **6∥4 e expand continuam fechados**. Saco idêntico e shrink **≤1**. **Saco de 5 ∥ avulso da linha do meio (t=0 e t=50 ms, bag first e single first) continua a entregar 2 `cs_test_` em comprador fresco.** Saco de 2–3 linhas no mesmo instante unificou em 1 `cs_`. **Não** pagámos as duas.

---

## P1-1 — Saco e artigo avulso ao mesmo tempo: dois links

**O que isto é:** o comprador pede o pagamento do saco e, no mesmo instante (ou 50 ms depois), o pagamento avulso de um artigo que está no meio do saco. O cadeado (já fechado em 6∥4 e no expand) tinha de entregar no máximo um link. Se o avulso respeitasse o claim do saco — ou o saco reutilizasse a Session do avulso — o segundo pedido reutilizava a Session ou era recusado.

**Quem / onde:** comprador (JWT fresco, sem checkout prévio) no checkout do saco vs checkout avulso da mesma linha. Stripe TEST.

**O que fizemos:**
- A1: saco ABCDE ∥ avulso C, t=0, comprador recém-criado.
- A2: saco primeiro → 50 ms → avulso C (outro comprador fresco).
- A3: avulso C primeiro → 50 ms → saco ABCDE (outro comprador fresco).
- Confirm: A1 outra vez em comprador novo; repetir A1 no mesmo comprador com SKUs novos; A3 fresco.
- A4–A6 (saco de 2–3, t=0 / 200 ms) no respectivo comprador fresco.

**Esperado vs resultado**
- API A1: esperado ≤1 `cs_` · visto **2** `cs_test_` distintas, ambas HTTP 200, `reused=false` (`a15cBt8q…` + `a1fGHyOt…`). Ledger das 5 linhas = saco; órfã do avulso. Settle **402** nas duas.
- API A2 (50 ms bag first, fresco): **2** `cs_test_` (`a1v8uJMZ…` + `a1NnGV0M…`), `reused=false`. Ledger = saco.
- API A3 (avulso primeiro → 50 ms → saco, fresco): **2** `cs_test_` (`a1QbYTO9…` + `a1PbKTT7…`), `reused=false`. Ledger = saco (o saco ganhou a escrita).
- API A4–A6 (saco de 2–3, fresco): **1** `cs_` reused.
- Confirm A1 fresco: **2** `cs_test_` (`a10TJ1AS…` + `a1uREWKK…`), settle 402 nas duas.
- Confirm A1 no mesmo comprador (SKUs novos): **ainda dual** (`a1E2wsEW…` + `a1mU36AJ…`).
- Confirm A3 fresco: **2** `cs_test_` (`a13ggck9…` + `a1biEi5p…`).
- Stripe: sem `sk_test_` local. **Não pagámos as duas.**

**Conclusão:** **P1** — saco de 5 ∥ avulso da linha do meio a 0 / 50 ms (qualquer ordem) entrega dois links. Saco pequeno (2–3) no mesmo instante unifica. 6∥4 / expand **fecharam**. Dual **bloqueia Fase 4**. Não é P0: as duas capturas **não** aconteceram.  
**Prova:** `probes.json` A1/A2/A3 + `confirm.json`.

---

## Anti-atrofia

Exactos **não corridos / não contados**:
- 4∥2 clássico — **não** na tabela
- bizum — **não**
- multibanco — **não**
- settle unpaid 402 — GET 402 nas Sessions **não** é finding

Fechos documentados (FAIL = ataque bloqueado / esperado):
- **A4** bag∥single@200ms∥bag → 1 `cs_` reused
- **A5** bag ABC ∥ avulso B t=0 (fresco, 3 linhas) → 1 `cs_` (avulso criou; saco reused)
- **A6** bag de 2 first → 200 ms → avulso → 1 `cs_`
- **B1** 6∥4 t=0 → 400 overlapping + 200 · 1 `cs_test_a1rUCjjq…`
- **B2** expand 50 ms → 200 + **400 overlapping** · 1 `cs_test_a1k8ROsF…`
- **B3** 2× bag idêntico → 200 + 200 mesmo `cs_` (`reused=true`)
- **B4** shrink → 400 overlapping + 200 · 1 `cs_` (subset; nunca 2 creates)
- **C1** underpay → amount **2323** ¢ (catálogo)
- **C2** 2.º insert 400 `order_hold_exceeds_stock`
- **C3** pago 4242 coerente (`setup_paid_order` PI `pi_3UCmUpH7FWYUN3jh1jtINP9p` 590¢ qty 2→1)
- **C4** 2 bags disjuntos → 2 `cs_` OK

HOLD na tabela = A1/A2/A3 (um P1) = **3/14 ≈ 21%** ≪ 40%. **Não** ATROFIA_ABORT.  
classe_nova=SIM: A2, A3, A4, A5, A6 (**5** ≥ 4).

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|-----------|------------------|--------------|
| A1 | ER-A | Future.wait bag ABCDE ∥ single C t=0 | 2× 200 duas `cs_` reused=false | ledger saco `a15cBt8q…`; órfã `a1fGHyOt…`; confirm fresco dual | **HOLD** P1-1 | NÃO |
| A2 | ER-A | Future.wait bag first → 50ms → single C | 2× 200 duas `cs_` reused=false | ledger saco `a1v8uJMZ…`; órfã `a1NnGV0M…` | **HOLD** P1-1 | SIM |
| A3 | ER-A | Future.wait single C first → 50ms → bag | 2× 200 duas `cs_` reused=false | ledger saco `a1PbKTT7…`; órfã `a1QbYTO9…` | **HOLD** P1-1 | SIM |
| A4 | ER-A | Future.wait bag ∥ single +200ms ∥ bag | 3× 200 **1** `cs_` | `a1IAYbTG…` reused | FAIL | SIM |
| A5 | ER-A | Future.wait bag ABC ∥ single B t=0 | 200+200 **1** `cs_` | `a1ZWNTbQ…` (avulso criou; saco reused) | FAIL | SIM |
| A6 | ER-A | Future.wait bag de 2 first → 200ms → single | 200+200 **1** `cs_` | `a1R3pTHs…` | FAIL | SIM |
| B1 | ER-B | Future.wait bag 6∥4 t=0 | 400 overlapping + 200 | 1 `cs_test_a1rUCjjq…` | FAIL | NÃO |
| B2 | ER-B | Future.wait subset → 50ms → expand | 200 + **400 overlapping** | 1 `cs_test_a1k8ROsF…` | FAIL | NÃO |
| B3 | ER-B | Future.wait 2× bag idêntico | 200+200 mesmo `cs_` reused | 1 `cs_test_a1TgnDgi…` | FAIL | NÃO |
| B4 | ER-B | Future.wait full → 50ms → shrink | 400 overlapping + 200 | 1 `cs_test_a1zijCTs…` | FAIL | NÃO |
| C1 | ER-C | body total_eur=0 item_price=0.01 SKU 18€ | 200 **2323** ¢ | amount catálogo | FAIL | NÃO |
| C2 | ER-C | 2 buyers qty=1 | insert 2.º 400 stock | o2=null | FAIL | NÃO |
| C3 | ER-C | pago 4242 single/bag | e2e `setup_paid_order` 200 | `pago` PI `pi_3UCmUpH7FWYUN3jh1jtINP9p` 590¢ qty 2→1 | FAIL | NÃO |
| C4 | ER-C | Future.wait 2 bags disjuntos | 200+200 duas `cs_` | A `a1C1M81w…` B `a1u4IEDC…` | FAIL | NÃO |

Linhas na tabela: **14** (≥14). Races bag∥single: **6** (A1–A6; timings 0 / 50 / 200 ms; bag first; single first). Stripe TEST pago: **sim**. classe_nova=SIM: **5**.

HOLD na tabela = findings. FAIL = ataque bloqueado. SKIP = 0.

---

## Tácticas mínimas (quota)

1. Tabela ≥14: **14**
2. ≥5 races bag∥single (0 / 50 / 200 ms; single first; bag first): **6** (A1–A6)
3. Dual create 2×200 + 2 `cs_`: **sim** (A1, A2, A3, confirm fresco e 2.ª ronda) → P1
4. ≥1 regressão 6∥4 e expand 400/≤1: **sim** (B1, B2)
5. ≥1 pago 4242 happy: **sim** (C3)
6. ≥4 classe_nova: **5** (A2–A6)

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → HTML Checkout tem `expired` no bundle JS (oráculo ingénuo inválido). Settle 402 nas úteis e nas órfãs.
- **Não pagámos as duas** Sessions — P1 (dois links), não P0.
- CPI 4242 directo (página Checkout) não liquidou; C3 usou `setup_paid_order` (Stripe TEST) — caixa coerente.
- Wallet seller 21,00→21,00 (e2e marcou `pago` + stock; saldo snapshot não moveu — não finding).
- Confirm no mesmo comprador com SKUs **novos** ainda dual (A1×2) — o furo não é só «primeiro checkout da conta»; saco de 5 ∥ avulso a 0/50 ms continua a abrir 2 `cs_`.
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_er_20260906T2112/_rter.dart`
- `tool/redteam_blind_er_20260906T2112/pass1.dart` + `pass1_findings.json` + `probes.json`
- `tool/redteam_blind_er_20260906T2112/confirm.dart` + `confirm.json`

```
AUDITOR: REDTEAM_BLIND_ER_BAG_SINGLE_RETEST_v1
VEREDICTO: FAIL_P1
```

RESUMO_NUMERICO: P0=0 P1=1 P2=0 P3=0 TOTAL=1
