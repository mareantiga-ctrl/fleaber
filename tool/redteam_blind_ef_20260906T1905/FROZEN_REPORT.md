# FROZEN_REPORT — REDTEAM_BLIND_EF_BAG_MUTEX_POS_OPEN_v1

## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 1
P2 aberto: SIM → quantos: 1
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 2

1. P0 dinheiro irreversível? NÃO
2. Quantos P0: 0
3. P1 caminho explorável? SIM
4. Quantos P1: 1
5. P2 hygiene? SIM
6. Quantos P2: 1
7. P3 baixo risco? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_EF_BAG_MUTEX_POS_OPEN_v1
FROZEN_AT: 2026-09-06T19:15:00+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 22
classes_novas: 11
races: 12
stripe_test_pago: true
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTEF-20260906T1905-` · pasta: `tool/redteam_blind_ef_20260906T1905/`.  
Atacantes: anon · buyer JWT fresco (`9905ff82-be97-45b5-bcfa-afb2a6150dab`) · seller JWT · buyer2 · seller2. `service_role` só fixture/observação.

Oráculo Session: sem `sk_test_` local. GET HTML do Checkout contém `expired` no JS (falso positivo). Prova de dual = **2× HTTP 200** + **2 `cs_test_` distintas** + `reused=false` + settle **402** em ambas. Pass2 confirmou B1/B3/B7. A6/B8 pass2 = 1 `cs_` + reused.

Fix OPEN (write=claim, sem shadow) **prova-se** em saco idêntico (A6, B4, B8). **Parte** ainda em overlap de conjuntos diferentes (6∥4, ABCDE∥C, bag∥single, shrink/expand).

---

## P1-1 — Overlaps de conjuntos diferentes: duas Sessions (6∥4, ABCDE∥C, bag∥single, shrink/expand)

**O que isto é:** o comprador pede ao mesmo tempo o pagamento de um saco e, em paralelo, um subconjunto, um artigo avulso, ou o mesmo saco a encolher/expandir 50 ms depois. O cadeado (após write=claim) tinha de entregar no máximo um link Stripe útil, ou recusar o segundo. Sacos **idênticos** já reutilizam a mesma Session; conjuntos **diferentes** ainda não.

**Quem / onde:** comprador (JWT buyer3 fresco) no checkout do saco.

**O que fizemos:**
- B1: `Future.wait` saco ABCDEF ∥ saco BCDE a t=0 **e** t=50 ms. Confirm pass2.
- B3: saco de 5 ∥ pagamento avulso da linha **C** (meio). Confirm pass2.
- B5: saco ∥ avulso +200 ms ∥ saco (3 corrotinas).
- B6: saco cheio t=0 → sleep 50 ms → subset.
- B7: subset t=0 → sleep 50 ms → superset (expand). Confirm pass2.

**Esperado vs resultado**
- API B1 6∥4 t=0: esperado ≤1 `cs_` ou 2.º contention/reuse · visto **2** `cs_test_` distintas, ambas HTTP 200, `reused=false` (`a1fquO7A…` + `a1KOKBgN…`); ledger nas 6 linhas = saco de 6; órfã de 4. Pass2: `a1BZp9We…` + `a1ASqHMo…`, dual_create=true, settle 402 nas duas.
- B1 t=50 ms: **2** `cs_` (`a1fAYk67…` + `a1h02CBR…`); ledger = saco de 6.
- API B3 ABCDE∥C: **2** `cs_` (`a1OHdGM4…` ledger + órfã `a1xbKycC…`); pass2 `a1BblyU0…` + `a1Go3aKa…`.
- API B5 bag∥single∥bag: **2** `cs_` (ledger `a1uqSV3l…` + órfã `a1awiqY2…`; 3.º HTTP 200 reused do saco).
- API B6 stagger 50 ms full→subset: **2** `cs_` (ledger `a1pERVhC…` + órfã `a11DEjXE…`).
- API B7 expand 50 ms: **2** `cs_` HTTP 200 `reused=false` (`a1GmKgCU…` subset + `a10etC5Q…` superset); ledger nas 4 linhas = sid do **superset**. Pass2: `a1dkgVM3…` + `a1Ffr9Hm…` (ledger = superset). A menor **não** foi recusada; o cliente recebeu dois links. Sem retrieve nativo não dá para jurar `status=expired` na órfã — settle **402** nas duas.
- Stripe: sem `sk_test_` local. **Não pagámos as duas.**

**Conclusão:** **P1** — o cliente recebeu dois links em overlap de conjuntos diferentes; uma Session ficou órfã no ledger. Não é P0: não pagámos as duas. O write=claim **fechou** o saco idêntico (A6/B4/B8 = 1 `cs_` + reused). Triângulo AB∥BC∥CA e timeout 100 ms∥retry **fecharam**. **Bloqueia abertura** (gate dual Session).  
**Prova:** `probes.json` B1/B3/B5/B6/B7 + `pass2.json`.

---

## P2-1 — Denylist off residual: `bizum` abre Session Stripe

**O que isto é:** um método de pagamento fora da app (Bizum, comum em ES/PT) não deve abrir um link Stripe. A matrix multibanco/ifthenpay/COD fica no pack EH; aqui só 1 linha residual.

**Quem / onde:** comprador JWT, checkout.

**O que fizemos:** insert `payment_method=bizum`; CPI.

**Esperado vs resultado**
- API: esperado 400 off-platform · visto **200** + `cs_test_a1pKyavt…`
- BD: método gravado `bizum`; Session criada

**Conclusão:** **P2** — falha de denylist residual (não é mutex; não é P1). O dinheiro ainda entra pela Checkout da plataforma.  
**Prova:** `probes.json` C5.

---

## Anti-atrofia

Exactos **não corridos / não contados** (HOLD residual clássico):
- 4∥2 clássico — **não** na tabela (substituído por 6∥4 0 ms e 50 ms)
- 5∥3 clássico — **não** na tabela
- `mb way x` — **não**
- claiming TTL exacto — **não** (A2 = futuro/malform)
- multibanco exact 400 — **não** (C5 = bizum 1 linha; matrix EH)

Fechos novos documentados (FAIL = ataque bloqueado):
- **A6** 2× bag idêntico mesma ordem → 200 + 200 **mesmo** `cs_` (`reused=true`); pass2 confirma 1 sid
- **B8** 3× mesmo bag → 3× HTTP 200 **1** `cs_` (reused); pass2 confirma
- B4 2× bag UUID invertido → 200 + 200 mesmo `cs_` (`reused=true`)
- B2 AB∥BC∥CA → 400 overlapping + 400 overlapping + 200; 1 `cs_`
- A3 timeout 100 ms ∥ complete ∥ retry 800 ms → 598 + 200 + 200 mesmo `cs_`; 1 sid
- A1 dead `cs_` → buyer2 400; owner reclaim 200
- A2 claiming futuro → RPC JWT 403; CPI 200 `cs_` coerente
- A4 bags disjuntos → 2 `cs_` (linhas sem overlap); JWT mutex **403**
- A5 JWT PATCH `cs_` 403 immutable; RPC claim alheio 403; buyer2 CPI 400; owner 400 contention
- C1 underpay → Session **2323** ¢
- C2 PATCH shipping HTTP 200 **sem mutar** (`entrega em mão`); amount 2995 estável
- C3 2.º insert 400 `order_hold_exceeds_stock`
- C4 unlist∥CPI → CPI 400 not listed
- D1 pago 4242 coerente
- D2 cross-seller 400
- D3 qty JWT 403; CPI 1745 ¢ (1 unidade)

HOLD na tabela = B1/B3/B5/B6/B7 (um P1) + C5 (um P2) = **6/22 = 27%** < 40%. **Não** ATROFIA_ABORT.  
classe_nova=SIM: A3, A6, B1, B2, B3, B4, B5, B6, B7, B8, C5 (**11** ≥ 5).

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|-----------|------------------|--------------|
| A1 | EF-A | plant `cs_test_dead`; buyer2 CPI; owner retry | buyer2 400; retry 200 `cs_test_a1hv1LTR…` | sid novo; morta não persiste | FAIL | NÃO |
| A2 | EF-A | `claiming:<now+1y>:malformtok12ab` + RPC JWT | RPC 403; CPI 200 | sid `cs_test_a16NyZ7T…` coerente | FAIL | NÃO |
| A3 | EF-A | Future.wait bag timeout 100ms ∥ complete ∥ retry +800ms | 598 + 200 + 200 mesmo `cs_` | ledger `a17waa1u…`; 1 sid | FAIL | SIM |
| A4 | EF-A | Future.wait 2 bags disjuntos mesmo buyer | 200+200 duas `cs_` | bags A/B sid distintos; JWT mutex 403 | FAIL | NÃO |
| A5 | EF-A | JWT PATCH cs_ sem claim; buyer2 RPC token alheio + CPI | PATCH 403; RPC 403; CPI 400; owner 400 contention | claiming plantado | FAIL | NÃO |
| A6 | EF-A | Future.wait 2× bag idêntico mesma ordem (write=claim) | 200+200 mesmo `cs_` reused | 1 `cs_test_a1rdiz14…`; pass2 1 sid | FAIL | SIM |
| B1 | EF-B | Future.wait bag 6∥4 stagger **0ms E 50ms** | t=0 200+200 duas `cs_`; t=50 200+200 duas `cs_` | ledger saco de 6; órfã de 4; pass2 dual_create | **HOLD** P1-1 | SIM |
| B2 | EF-B | Future.wait bag AB ∥ BC ∥ CA (triângulo 3 CPI) | 400+400+200 overlapping | 1 `cs_test_a14B0ZA8…` | FAIL | SIM |
| B3 | EF-B | Future.wait bag ABCDE ∥ CPI single **C** (meio) | 200+200 duas `cs_` | ledger saco; single órfã; pass2 dual_create | **HOLD** P1-1 | SIM |
| B4 | EF-B | Future.wait 2× bag idêntico ordem UUID invertida | 200+200 mesmo `cs_` reused | 1 `cs_test_a1Gume8g…` | FAIL | SIM |
| B5 | EF-B | Future.wait bag ∥ single +200ms ∥ bag (3 corrotinas) | 200+200+200 duas `cs_` (3.º reused) | ledger `a1uqSV3l…`; órfã `a1awiqY2…` | **HOLD** P1-1 | SIM |
| B6 | EF-B | Future.wait bag full → sleep 50ms → subset | 200+200 duas `cs_` | ledger full `a1pERVhC…`; órfã `a11DEjXE…` | **HOLD** P1-1 | SIM |
| B7 | EF-B | Future.wait subset → 50ms → superset expand | 200+200 duas `cs_` reused=false | ledger superset; subset órfã; pass2 dual_create | **HOLD** P1-1 | SIM |
| B8 | EF-B | Future.wait 3× mesmo bag paralelo | 200+200+200 **1** `cs_` | ledger `a17HDgcU…`; pass2 1 sid | FAIL | SIM |
| C1 | EF-C | `total_eur=0`+`item_price=0.01` SKU 18€ | 200 **2323** ¢ | amount catálogo | FAIL | NÃO |
| C2 | EF-C | Session open → JWT PATCH shipping=ctt; coupon SAVE90 | PATCH 200; re-CPI/coupon 2995 | shipping **não** mudou (`entrega em mão`) | FAIL | NÃO |
| C3 | EF-C | 2 buyers última unidade qty=1 | insert2 400 `order_hold_exceeds_stock` | 0 Sessions do 2.º | FAIL | NÃO |
| C4 | EF-C | Future.wait CPI ∥ unlist+qty=0 | CPI 400 not listed | `list_on_marketplace=false` qty=0 | FAIL | NÃO |
| C5 | EF-C | payment_method bizum (1 linha residual) | 200 + `cs_test_a1pKyavt…` | pm `bizum`; Session aberta | **HOLD** P2-1 | SIM |
| D1 | EF-D | Stripe TEST pago 4242 + caixa | e2e `setup_paid_order` 200 | `pago` PI `pi_3UCkYjH7FWYUN3jh17eVMiSc` 590¢ stock 2→1 `applied=1` | FAIL | NÃO |
| D2 | EF-D | bag 2 sellers | 400 one seller | sem `cs_` | FAIL | NÃO |
| D3 | EF-D | JWT PATCH qty=99; CPI quantity=99 stock=1 | JWT 403; CPI 1745 ¢ | quantity imutável | FAIL | NÃO |

Linhas na tabela: **22** (≥22). Races `Future.wait`: **12** (A3, A4, A6, B1, B2, B3, B4, B5, B6, B7, B8, C4). Stripe TEST pago: **sim**. classe_nova=SIM: **11**.

HOLD na tabela = findings. FAIL = ataque bloqueado. SKIP = 0.

---

## Tácticas mínimas (quota)

1. Checkout Stripe TEST pago (4242 / `setup_paid_order`): **sim** — order `288b227d-5c3a-4916-a072-f2fd775d2669`, PI `pi_3UCkYjH7FWYUN3jh17eVMiSc`, `amount_paid_cents=590`, qty 2→1
2. ≥6 races `Future.wait` distintas: **sim** (12)
3. Tabela ≥22: **22**
4. Matriz EF-A (6) EF-B (8) EF-C (5) EF-D (3): **sim**
5. ≥5 classe_nova: **11** (A3, A6, B1–B8, C5)
6. ≥1 pago: **sim**

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → sem retrieve `status=open` nativo; HTML Checkout tem `expired` no bundle JS (oráculo ingénuo inválido). Settle 402 nas órfãs e nas úteis.
- **Não pagámos as duas** Sessions do overlap — P1 (dois links), não P0.
- Seller wallet 4,00→19,00 nesta ronda (e2e creditou o pago; delta extra não auditado como finding).
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_ef_20260906T1905/_rtef.dart`
- `tool/redteam_blind_ef_20260906T1905/pass1.dart` + `pass1_findings.json` + `probes.json`
- `tool/redteam_blind_ef_20260906T1905/pass2.dart` + `pass2.json`

RESUMO_NUMERICO: P0=0 P1=1 P2=1 P3=0 TOTAL=2
