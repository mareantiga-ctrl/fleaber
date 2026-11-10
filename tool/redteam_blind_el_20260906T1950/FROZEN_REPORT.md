# FROZEN_REPORT — REDTEAM_BLIND_EL_BAG_RETEST_POS_OPEN_v1

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

```
AUDITOR: REDTEAM_BLIND_EL_BAG_RETEST_POS_OPEN_v1
FROZEN_AT: 2026-09-06T20:02:00+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 18
classes_novas: 8
races: 12
stripe_test_pago: true
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTEL-20260906T1950-` · pasta: `tool/redteam_blind_el_20260906T1950/`.  
Atacantes: anon · buyer JWT fresco (`4c416bd9-9af2-430b-ad36-0dc0a0ebcf01`) · seller JWT · buyer2 · seller2. `service_role` só fixture/observação.

Oráculo Session: sem `sk_test_` local. GET HTML do Checkout contém `expired` no JS (falso positivo). Prova de dual = **2× HTTP 200** + **2 `cs_test_` distintas** + `reused=false` + settle **402** em ambas. Pass2 confirmou B5. A1/B1/B3/B7 pass2 = 1 `cs_` / 400 overlapping.

**Vs EF:** 6∥4, expand, shrink e triângulo **fecharam** (400 overlapping ou reuse). **bizum** passou a 400 sem `cs_` (P2 EF fechado). Fica o furo **bag∥single** (e bag∥single∥bag).

---

## P1-1 — Bag paralelo com artigo avulso: duas Sessions (ABCDE∥C, bag∥single∥bag)

**O que isto é:** o comprador pede ao mesmo tempo o pagamento do saco e, em paralelo, o pagamento avulso de um artigo que está no meio do saco. O cadeado fail-closed (overlap/expand → 400) tinha de entregar no máximo um link Stripe, ou recusar o segundo. Sacos **idênticos**, **6∥4**, **expand**, **shrink** e **triângulo** já fecham; o cruzamento **saco ∥ avulso** ainda cria duas Sessions.

**Quem / onde:** comprador (JWT buyer3 fresco) no checkout do saco e no checkout avulso da mesma linha.

**O que fizemos:**
- B5: `Future.wait` saco ABCDE ∥ pagamento avulso da linha **C** (meio). Confirm pass2.
- B6: saco ∥ avulso +200 ms ∥ saco (3 corrotinas). Pass1.

**Esperado vs resultado**
- API B5: esperado 200+400 overlapping ou 1 `cs_` reused · visto **2** `cs_test_` distintas, ambas HTTP 200, `reused=false` (`a14Lg6Ao…` + `a1ddL19T…`). Ledger nas 5 linhas = saco; órfã do avulso. Pass2: `a1A9ul7R…` + `a1HyOIsm…`, `dual_create=true`, settle **402** nas duas.
- API B6: **2** `cs_` (`a1mEBtX3…` + ledger `a1AehpZt…`); 3× HTTP 200 (um reused do primeiro sid).
- Stripe: sem `sk_test_` local. **Não pagámos as duas.**

**Conclusão:** **P1** — o cliente recebeu dois links (saco e avulso); uma Session ficou órfã no ledger. Não é P0: não pagámos as duas. 6∥4 / expand / shrink / triângulo **fecharam**. **Bloqueia abertura** (gate dual Session; B5/B6).  
**Prova:** `probes.json` B5/B6 + `pass2.json` B5.

---

## Anti-atrofia

Exactos **não corridos / não contados** (HOLD residual clássico):
- 4∥2 clássico — **não** na tabela (substituído por 6∥4 t=0 e t=50)
- multibanco exact 400 — **não**
- bizum exact se só 400 — **está** na matriz como reteste D2 (FAIL = ataque bloqueado; **não** HOLD)

Fechos novos / reteste documentados (FAIL = ataque bloqueado):
- **A1** 2× bag idêntico → 200 + 200 **mesmo** `cs_` (`reused=true`); pass2 confirma 1 sid
- **A2** 3× mesmo bag → 3× HTTP 200 **1** `cs_` (reused)
- **A3** UUID invertido → 200 + 200 mesmo `cs_` (`reused=true`)
- **A4** timeout 100 ms ∥ complete ∥ retry 800 ms → 598 + 200 + 200 mesmo `cs_`; 1 sid
- **B1** 6∥4 t=0 → 400 overlapping + 200; 1 `cs_`; pass2 confirma
- **B2** 6∥4 t=50 → 400 overlapping + 200; 1 `cs_`
- **B3** expand 50 ms → 200 + **400 overlapping**; 1 `cs_`; pass2 confirma (nunca 2.ª)
- **B4** shrink 50 ms → 200 + 200 **mesmo** `cs_` (`reused=true` do maior)
- **B7** AB∥BC∥CA → 200 + 400 + 400 overlapping; 1 `cs_`; pass2 400+400+200
- **C1** 2 bags disjuntos → 2 `cs_` OK
- **C2** underpay → Session **2323** ¢
- **C3** 2.º insert 400 `order_hold_exceeds_stock`
- **C4** bag 2 sellers → 400 one seller
- **D1** pago 4242 coerente
- **D2** **bizum** → 400 off-platform **sem** `cs_` (P2 EF fechado)
- **D3** Pagamento na App → `cs_` OK

HOLD na tabela = B5/B6 (um P1) = **2/18 = 11%** < 40%. **Não** ATROFIA_ABORT.  
classe_nova=SIM: A4, B1, B2, B3, B4, B5, B6, B7 (**8** ≥ 4).

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|-----------|------------------|--------------|
| A1 | EL-A | Future.wait 2× bag idêntico mesma ordem | 200+200 mesmo `cs_` reused | 1 `cs_test_a1fOKMWf…`; pass2 1 sid | FAIL | NÃO |
| A2 | EL-A | Future.wait 3× mesmo bag paralelo | 200+200+200 **1** `cs_` | ledger `a1DCCDrl…` | FAIL | NÃO |
| A3 | EL-A | Future.wait 2× bag UUID invertido | 200+200 mesmo `cs_` reused | 1 `cs_test_a1sUYQfQ…` | FAIL | NÃO |
| A4 | EL-A | Future.wait bag timeout 100ms ∥ complete ∥ retry +800ms | 598 + 200 + 200 mesmo `cs_` | ledger `a15QwMXb…`; 1 sid | FAIL | SIM |
| B1 | EL-B | Future.wait bag 6∥4 t=0 | 400 overlapping + 200 | 1 `cs_test_a1CfNntg…`; pass2 dual_create=false | FAIL | SIM |
| B2 | EL-B | Future.wait bag 6∥4 t=50ms | 400 overlapping + 200 | 1 `cs_test_a1aOjWTD…` | FAIL | SIM |
| B3 | EL-B | Future.wait subset → 50ms → superset expand | 200 + **400 overlapping** | 1 `cs_test_a17sH1x4…`; pass2 200+400 | FAIL | SIM |
| B4 | EL-B | Future.wait full → 50ms → subset shrink | 200+200 mesmo `cs_` reused | 1 `cs_test_a1DJy4ah…` (reuse do maior) | FAIL | SIM |
| B5 | EL-B | Future.wait bag ABCDE ∥ CPI single C (meio) | 200+200 duas `cs_` reused=false | ledger saco `a14Lg6Ao…`; órfã `a1ddL19T…`; pass2 dual_create | **HOLD** P1-1 | SIM |
| B6 | EL-B | Future.wait bag ∥ single +200ms ∥ bag | 200+200+200 duas `cs_` | ledger `a1AehpZt…`; órfã `a1mEBtX3…` | **HOLD** P1-1 | SIM |
| B7 | EL-B | Future.wait bag AB ∥ BC ∥ CA (triângulo) | 200+400+400 overlapping | 1 `cs_test_a1i4PxR3…`; pass2 400+400+200 | FAIL | SIM |
| C1 | EL-C | Future.wait 2 bags disjuntos mesmo buyer | 200+200 duas `cs_` | bags A/B sid distintos | FAIL | NÃO |
| C2 | EL-C | `total_eur=0`+`item_price=0.01` SKU 18€ | 200 **2323** ¢ | amount catálogo | FAIL | NÃO |
| C3 | EL-C | 2 buyers última unidade qty=1 | insert2 400 `order_hold_exceeds_stock` | 0 Sessions do 2.º | FAIL | NÃO |
| C4 | EL-C | bag 2 sellers | 400 one seller | sem `cs_` | FAIL | NÃO |
| D1 | EL-D | Stripe TEST pago 4242 + caixa | e2e `setup_paid_order` 200 | `pago` PI `pi_3UClEOH7FWYUN3jh0aL4vBmH` 590¢ stock 2→1 `applied=1` | FAIL | NÃO |
| D2 | EL-D | payment_method bizum (1 linha reteste P2) | **400** off-platform | pm `bizum`; **sem** `cs_` | FAIL | NÃO |
| D3 | EL-D | Pagamento na App → CPI | 200 + `cs_test_a1lHkkef…` | pm `Pagamento na app` | FAIL | NÃO |

Linhas na tabela: **18** (≥18). Races `Future.wait`: **12** (A1–A4, B1–B7, C1). Overlap races: **7** (B1–B7 ≥5). Stripe TEST pago: **sim**. classe_nova=SIM: **8**.

HOLD na tabela = findings. FAIL = ataque bloqueado. SKIP = 0.

---

## Tácticas mínimas (quota)

1. Checkout Stripe TEST pago (4242 / `setup_paid_order`): **sim** — order `834a0a4b-7321-48b5-b30d-a9eb1936eb05`, PI `pi_3UClEOH7FWYUN3jh0aL4vBmH`, `amount_paid_cents=590`, qty 2→1
2. ≥5 races overlap: **sim** (B1–B7 = 7)
3. Tabela ≥18: **18**
4. Matriz EL-A (4) EL-B (7) EL-C (4) EL-D (3): **sim**
5. ≥4 classe_nova: **8** (A4, B1–B7)
6. ≥1 pago: **sim**
7. bizum → 400: **sim** (D2)

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → sem retrieve `status=open` nativo; HTML Checkout tem `expired` no bundle JS (oráculo ingénuo inválido). Settle 402 nas órfãs e nas úteis.
- **Não pagámos as duas** Sessions do bag∥single — P1 (dois links), não P0.
- Wallet seller 18,00→18,00 nesta ronda (e2e marcou `pago` + stock; saldo snapshot não moveu — não auditado como finding).
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_el_20260906T1950/_rtel.dart`
- `tool/redteam_blind_el_20260906T1950/pass1.dart` + `pass1_findings.json` + `probes.json`
- `tool/redteam_blind_el_20260906T1950/pass2.dart` + `pass2.json`

RESUMO_NUMERICO: P0=0 P1=1 P2=0 P3=0 TOTAL=1
