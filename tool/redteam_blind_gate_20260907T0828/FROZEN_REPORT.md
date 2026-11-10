# FROZEN_REPORT — REDTEAM_BLIND_GATE_BAG_SINGLE_v1

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
AUDITOR: REDTEAM_BLIND_GATE_BAG_SINGLE_v1
FROZEN_AT: 2026-09-07T08:36:00+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 12
classes_novas: 8
races_bag_single: 6
stripe_test_pago: true
dual_cs_fresh_buyer: true
dual_cs_pay_attempted: true
dual_cs_both_captured: false
hosted_bag_captured: false
hosted_orphan_captured: false
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTGATE-20260907T0828-` · pasta: `tool/redteam_blind_gate_20260907T0828/`.  
Atacante CPI: comprador fresco por corrida A1–A6 (`7669e07d-…` a `a0b88f93-…`). `service_role` só fixture/observação.

GATE: 2× HTTP 200 + 2 `cs_` distintas `reused=false` = P1 (bloqueia Fase 4). Esperado: ≤1 `cs_` útil. P0–P2=0 **e** A1–A4 sem dual → `PASS_CEGO_SATURADO`. Qualquer dual → `FAIL_P1`.

Reteste vs ER/ES/ET 07:44–07:46: **6∥4 e expand continuam fechados**. Saco idêntico ≤1. **Saco de 5 ∥ avulso do meio (t=0, bag-first 50 ms, single-first 50 ms) continua a entregar 2 `cs_test_` em comprador fresco.** **Saco de 3 ∥ avulso t=0 (A4) desta vez unificou** (`reused=true,false`, 1 `cs_`) — na ronda ER o saco de 3 ainda dualizava. Stagger 200 ms (A5/A6) unifica. Tentámos pagar a 2.ª: **não capturou**. Sem oversell.

---

## P1-1 — Saco de 5 e artigo avulso ao mesmo tempo: dois links

**O que isto é:** o comprador pede o pagamento do saco de cinco artigos e, no mesmo instante (ou 50 ms depois, qualquer ordem), o pagamento avulso do artigo do meio. O cadeado `may_create` (já fechado em 6∥4, expand, saco de 3 e stagger 200 ms) tinha de entregar no máximo um link. Dois links com `reused=false` é o mesmo furo das rondas ER/ES/ET.

**Quem / onde:** comprador JWT recém-criado (sem checkout prévio) no checkout do saco vs checkout avulso da mesma linha. Stripe TEST. Staging.

**O que fizemos:**
- A1: saco ABCDE ∥ avulso C, t=0, comprador fresco `7669e07d-…`.
- A2: saco primeiro → 50 ms → avulso C (outro fresco).
- A3: avulso C primeiro → 50 ms → saco ABCDE (outro fresco).
- A4: saco ABC ∥ avulso B t=0 (fresco, 3 linhas) — contraste.
- C2: tentar pagar a Session órfã A1 (caça P0).

**Esperado vs resultado**
- API A1: esperado ≤1 `cs_` · visto **2** `cs_test_` distintas, ambas HTTP 200, `reused=false` (`a1ympYGg…` saco nas 5 linhas + órfã `a1H6uUC0…`). Hub n=1×5. Settle **402** nas duas.
- API A2 (50 ms bag first, fresco): **2** `cs_test_` (`a1jU7G62…` saco + `a1cHM7MG…` órfã), `reused=false`.
- API A3 (avulso primeiro → 50 ms → saco, fresco): **2** `cs_test_` (`a1IHPmY0…` órfã + `a1Xmplyk…` saco nas 5 linhas), `reused=false`.
- API A4 (saco de 3 t=0, fresco): **1** `cs_test_a19AWkLN…` (`reused=true,false`) — **fechado**.
- C2 2.ª Session: `payment_pages` 404 «No such checkout.session»; settle **402**; stock A1 ainda qty=2, 0 `pago`. **Não é P0.**
- Stripe: sem `sk_test_` local. Checkout alojado no browser de auditoria: «This link is incomplete» (hash da URL). Captura happy via e2e `setup_paid_order` (C1).

**Conclusão:** **P1** — saco de 5 ∥ avulso da linha do meio a 0 / 50 ms (qualquer ordem) ainda entrega dois links no primeiro tiro de um comprador fresco. Saco de 3 t=0, stagger 200 ms, 6∥4 e expand **fecharam**. Dual **bloqueia Fase 4**. Não é P0: a 2.ª captura **não** aconteceu.  
**Prova:** `probes.json` A1/A2/A3 + `pay_urls.json` + `confirm.json`.

---

## Anti-atrofia

Exactos **não corridos / não contados**:
- 4∥2 clássico — **não** na tabela
- bizum / multibanco — **não** contar
- confirm_ident fresco falhou fixture (`seller_id` nulo no script) — **não** contar; B3 da tabela já mostrou ≤1

Fechos novos documentados (FAIL, ataque bloqueado / esperado):
- **A4** bag ABC ∥ single B t=0 fresco → 200+200 **1** `cs_` reused (`true,false`)
- **A5** bag∥single∥bag @200 ms → 200×3 **1** `cs_` reused (`true,false,true`)
- **A6** saco de 2 first →200 ms→ avulso → 200+200 **1** `cs_` (`true,false`)
- **B1** 6∥4 t=0 → 400+200 `overlapping bag session` · 1 `cs_test_a1R4GyCS…`
- **B2 confirm fresco** subset→50 ms→superset → 200+400 overlapping · 1 `cs_test_a18OktRu…` (`confirm.json`)
- **C1** leftover e2e: `pago`, qty 2→1, Hub n=1, PI `pi_3UCx4P…`
- **C2** 2.ª captura falhou (órfã 402)
- **C3** 2.º insert `order_hold_exceeds_stock`

HOLD na tabela = A1+A2+A3 (um P1) = **3/12 = 25%** < 40%. **Não** ATROFIA_ABORT.  
classe_nova=SIM: A1, A2, A3, A4, A5, A6, C1, C2 (**8**).

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|-----------|------------------|--------------|
| A1 | G-A | Future.wait bag ABCDE ∥ single C t=0 fresco | 200+200 duas `cs_` reused=false | ledger saco `a1ympYGg…`; órfã `a1H6uUC0…`; Hub n=1×5 | **HOLD** P1-1 | SIM |
| A2 | G-A | Future.wait bag first →50ms→ single C fresco | 200+200 duas `cs_` reused=false | ledger saco `a1jU7G62…`; órfã `a1cHM7MG…` | **HOLD** P1-1 | SIM |
| A3 | G-A | Future.wait single C first →50ms→ bag fresco | 200+200 duas `cs_` reused=false | ledger saco `a1Xmplyk…`; órfã `a1IHPmY0…` | **HOLD** P1-1 | SIM |
| A4 | G-A | Future.wait bag ABC ∥ single B t=0 fresco | 200+200 **1** `cs_` reused | 1 sid `a19AWkLN…` | FAIL | SIM |
| A5 | G-A | Future.wait bag ∥ single +200ms ∥ bag | 200×3 **1** `cs_` reused | 1 sid `a1Z9TRab…` | FAIL | SIM |
| A6 | G-A | Future.wait bag de 2 first →200ms→ single | 200+200 **1** `cs_` reused | 1 sid `a1vUXP3g…` | FAIL | SIM |
| B1 | G-B | Future.wait bag 6∥4 t=0 | 400+200 overlapping · 1 `cs_` | ledger 1 sid `a1R4GyCS…` | FAIL | NÃO |
| B2 | G-B | expand subset→50ms→superset | pass1: reuse mutex buyer3; **confirm fresco 200+400** | confirm 1 sid `a18OktRu…` overlapping | FAIL | NÃO |
| B3 | G-B | Future.wait 2× bag idêntico | 200+200 **1** `cs_` reused | mesmo sid `a1R4GyCS…` (mutex buyer3) | FAIL | NÃO |
| C1 | G-C | pago 4242 do link útil + Hub leftover | API 4242 falhou (sem `sk_test_`); e2e `setup_paid_order` 200 | `pago` qty=1 Hub n=1 PI `pi_3UCx4P…` | FAIL | SIM |
| C2 | G-C | se dual: pagar 2.ª (caça P0) | órfã pages 404; settle 402; hosted «incomplete» | 0 2.ªs capturas; A1 qty=2 | FAIL | SIM |
| C3 | G-C | 2 buyers qty=1 sem oversell | 2.º insert 400 `order_hold_exceeds_stock` | o2=null | FAIL | NÃO |

Linhas na tabela: **12**. Races `Future.wait` bag∥single: **6** (A1–A6). Stripe TEST pago: **sim** (C1 e2e). classe_nova=SIM: **8**.

HOLD na tabela = findings. FAIL = ataque bloqueado / caminho sem P0. SKIP = 0.

---

## Tácticas mínimas (quota)

1. Tabela ≥12: **12**
2. ≥5 races bag∥single (t=0, 50 ms, single-first, bag∥single∥bag, saco 3 e 5): **sim** (A1–A6)
3. Nunca 2× HTTP 200 com 2 `cs_` `reused=false`: **falhou A1 A2 A3**
4. Se dual: tentar pagar a 2.ª (caça P0): **sim** (C2) — 0 2.ªs capturas → **não P0**
5. ≥1 regressão 6∥4 e ≥1 expand (ainda 400/≤1): **sim** (B1 400+200; confirm expand 200+400)
6. ≥1 pago 4242 happy: **sim** (C1 e2e `pi_3UCx4P…`)
7. ≥1 Hub leftover após pago: **sim** (qty 2→1, Hub n=1)

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → retrieve nativo / `pm_card_visa` na Session falhou.
- Checkout alojado no browser de auditoria: «This link is incomplete» (URL com hash dummy). Não capturámos o saco A1 no alojado nesta ronda.
- B2/B3 da pass1 no buyer3 reutilizaram a Session em voo do B1 (mutex global por comprador) — expand limpo está em `confirm.json`.
- Seller wallet 21,00 estável (Δ=0).
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_gate_20260907T0828/_rtgate.dart`
- `tool/redteam_blind_gate_20260907T0828/pass1.dart` + `pass1_findings.json` + `probes.json` + `pay_urls.json`
- `tool/redteam_blind_gate_20260907T0828/confirm.dart` + `confirm.json` (expand fresco 200+400)
- `tool/redteam_blind_gate_20260907T0828/confirm_ident.dart` + `confirm_ident.json` (fixture skip)

```
AUDITOR: REDTEAM_BLIND_GATE_BAG_SINGLE_v1
VEREDICTO: FAIL_P1
```

**Ainda não Fase 4.** Dual create no saco de 5 ∥ avulso (t=0 e 50 ms, comprador fresco) permanece.

RESUMO_NUMERICO: P0=0 P1=1 P2=0 P3=0 TOTAL=1
