# FROZEN_REPORT — REDTEAM_BLIND_DT_BAG_MUTEX_POS_DNDS_v1

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
AUDITOR: REDTEAM_BLIND_DT_BAG_MUTEX_POS_DNDS_v1
FROZEN_AT: 2026-09-06T17:52:54+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 20
classes_novas: 9
lentes_cobertas: [DT1, DT2, DT3, DT4, DT5, DT6, DT7, DT8]
pocos_tentados: [DT-A, DT-B, DT-C, DT-D]
races_future_wait: [A3, A4, B1, B2, B3, B4, B5, B6, B7, C4]
stripe_test_pago: true
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTDT-20260906T1739-` · pasta: `tool/redteam_blind_dt_20260906T1739/`.  
Atacantes: anon · buyer JWT (buyer3 fresco — LIVE_OPS buyer no tecto 60/h da campanha DN) · seller JWT · buyer2 · seller2. `service_role` só fixture/observação (`plantClaim`, `setup_paid_order`, mutex peek).

Pass1 inicial contra o buyer LIVE_OPS devolveu 429 «Demasiados checkouts» em quase todas as CPI — **não** entra na tabela (prova de rate-limit, não de mutex). Ronda LIVE da tabela = buyer3 `049260cd-e073-4134-8293-029635420cbb`.

---

## P1-1 — Overlaps novos pós-DNDS: 6∥4, ABCDE∥single-B, bag∥single∥bag, stagger 50ms: duas Sessions Stripe

**O que isto é:** o comprador pede ao mesmo tempo o pagamento de um saco grande e, em paralelo, um subconjunto, um artigo avulso, ou o mesmo saco com 50 ms de atraso (encolher ou expandir). O cadeado DNDS (guarda pré-create + reuse fail-closed) tinha de entregar no máximo um link Stripe útil, ou recusar o segundo.

**Quem / onde:** comprador (JWT buyer3) no checkout do saco.

**O que fizemos:**
- B1: 6 encomendas. `Future.wait` saco ABCDEF ∥ saco BCDE (subset 4, não 5∥3). Confirm pass2.
- B3: saco de 5 ∥ pagamento avulso da linha B (índice 2/5, nem extrema nem meio). Confirm pass2.
- B5: saco ∥ avulso +200 ms ∥ saco (3 corrotinas). Pass1 duas `cs_`; pass2 1 `cs_` (flaky).
- B6: saco cheio t=0 → sleep 50 ms → subset. Confirm pass2.
- B7: subset t=0 → sleep 50 ms → superset (expand). Confirm pass2.

**Esperado vs resultado**
- API B1 6∥4: esperado ≤1 `cs_` útil ou 2.º contention · visto **2** `cs_test_` distintas, ambas HTTP 200 (`a1RNcTaV…` + `a17w0bL0…`); `reused=false` nas duas; pass2 `a15Rtiqul…` + `a1IgwxMF…`
- Ledger B1: A–F todas com a Session do saco de 6; a Session de 4 linhas ficou órfã (pass1 e pass2)
- API B3 ABCDE∥single-B: **2** `cs_test_` (`a1iucoWZ…` + `a134aznb…`); pass2 `a1GmvqMq…` + `a1Hz1K7o…`; ledger nas 5 linhas = sid do saco; single órfã
- API B5 bag∥single∥bag: pass1 **2** `cs_` (`a1N0QLcr…` + `a1oRoFZW…`, 3.º reused); pass2 1 `cs_` (`a1bIJnPr…`) — corrida instável
- API B6 stagger 50 ms full→subset: **2** `cs_` (`a1QxdlCM…` + `a1A978Gj…`); pass2 `a1U4XHCZ…` + `a159L69M…`; ledger = sid do saco cheio
- API B7 stagger 50 ms subset→superset: **2** `cs_` (`a1sTR7NS…` + `a1WRM6mj…`); pass2 `a1pFS4NC…` + `a1cyJhz1…`; ledger nas 4 linhas = sid do **superset**; subset órfã (expand não expirou a menor)
- Stripe: sem `sk_test_` local; settle 402 nas duas (payable=2). **Não pagámos as duas.**

**Conclusão:** **P1** — o cliente recebeu dois links; uma Session ficou órfã. Não é P0: não pagámos as duas. A guarda pré-create / reuse DNDS **não** impede duas criações em overlap 6∥4, bag∥single índice 2, nem stagger 50 ms (encolher e expandir). Triângulo AB∥BC∥CA, 2× bag UUID invertido e timeout 100 ms∥retry **fecharam** (≤1 / reuse / overlapping bag session).  
**Prova:** `probes.json` B1/B3/B5/B6/B7 + `pass2.json`.

---

## Anti-atrofia

Exactos **não corridos / não contados** (HOLD residual clássico):
- 4∥2 clássico — **não** na tabela (substituído por 6∥4)
- 5∥3 clássico — **não** na tabela
- bag∥single meio clássico — **não** na tabela (substituído por índice 2/5 = B)
- `mb way x` / `mbωay` / PaysafeCash — **não** na tabela (C5 = array JSON `["MB WAY"]` + notes mismatch)
- claiming TTL exacto — **não** na tabela (A2 = futuro/malform, 1 linha)

Fechos novos documentados (FAIL, não contar como finding):
- B2 AB∥BC∥CA → 400 + 400 overlapping + 200; 1 `cs_`
- B4 2× bag UUID invertido → 200 + 200 **mesmo** `cs_` (`reused=true` no 2.º)
- A3 timeout 100 ms ∥ complete ∥ retry 800 ms → 599 + 200 + 200 mesmo `cs_`; payable=1
- A1 dead `cs_` → buyer2 400; owner reclaim 200
- A2 claiming futuro → RPC JWT 403; CPI 200 `cs_` coerente no ledger
- A4 bags disjuntos → 2 `cs_` após serializar (linhas sem overlap); JWT mutex **403**
- A5 JWT PATCH `cs_` 403 immutable; RPC claim alheio 403; buyer2 CPI 400
- C1 underpay → Session **2323** ¢
- C2 PATCH shipping HTTP 200 **sem mutar** (`entrega em mão`); amount 2995 estável
- C3 2.º insert 400 `order_hold_exceeds_stock`
- C4 unlist∥CPI → CPI 400 not listed
- C5 array `["MB WAY"]` → 400 off-platform; notes mismatch em order in-app → Session (BD manda)
- D1 pago 4242 coerente
- D2 cross-seller 400
- D3 qty JWT 403; CPI 1745 ¢ (1 unidade)

HOLD na tabela = 5 linhas (B1, B3, B5, B6, B7) = **1** finding P1-1. 5/20 = 25% < 40%. **Não** ATROFIA_ABORT.  
classe_nova=SIM: A3, B1, B2, B3, B4, B5, B6, B7, C5 (**9** ≥ 4).

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|-----------|------------------|--------------|
| A1 | DT-A | plant `cs_test_dead`; buyer2 CPI; owner retry | buyer2 400; retry 200 `cs_test_a1yGSaju…` | sid novo; morta não persiste | FAIL | NÃO |
| A2 | DT-A | `claiming:<now+1y>:malformtok12ab` + RPC JWT | RPC 403; CPI 200 | sid `cs_test_a1UrgPooo…` coerente | FAIL | NÃO |
| A3 | DT-A | Future.wait bag timeout 100ms ∥ complete ∥ retry +800ms | 599 + 200 + 200 mesmo `cs_` | ledger `a1QlExGb…`; payable=1 | FAIL | SIM |
| A4 | DT-A | Future.wait 2 bags disjuntos mesmo buyer | 200+200 duas `cs_` | bags A/B sid distintos; JWT mutex 403 | FAIL | NÃO |
| A5 | DT-A | JWT PATCH cs_ sem claim; buyer2 RPC token alheio + CPI | PATCH 403; RPC 403; CPI 400; owner 400 contention | claiming plantado | FAIL | NÃO |
| B1 | DT-B | Future.wait bag 6-line ∥ bag 4-line subset meio (BCDE) | 200+200 duas `cs_` | A–F `a1RNcTaV…`; órfã `a17w0bL0…`; pass2 repeat 2 `cs_` | **HOLD** P1-1 | SIM |
| B2 | DT-B | Future.wait bag AB ∥ BC ∥ CA (triângulo 3 CPI) | 400+400 overlapping + 200 | 1 `cs_test_a1eYcTcr…` | FAIL | SIM |
| B3 | DT-B | Future.wait bag ABCDE ∥ CPI single índice 2/5 (B) | 200+200 duas `cs_` | ledger saco `a1iucoWZ…`; single órfã `a134aznb…`; pass2 repeat 2 `cs_` | **HOLD** P1-1 | SIM |
| B4 | DT-B | Future.wait 2× bag idêntico ordem UUID invertida | 200+200 mesmo `cs_` reused | 1 `cs_test_a1W32pff…` | FAIL | SIM |
| B5 | DT-B | Future.wait bag ∥ single +200ms ∥ bag (3 corrotinas) | 200+200+200 duas `cs_` (3.º reused) | ledger `a1N0QLcr…`; órfã `a1oRoFZW…`; pass2 1 `cs_` flaky | **HOLD** P1-1 | SIM |
| B6 | DT-B | Future.wait bag full → sleep 50ms → subset | 200+200 duas `cs_` | ledger full `a1QxdlCM…`; órfã `a1A978Gj…`; pass2 repeat 2 `cs_` | **HOLD** P1-1 | SIM |
| B7 | DT-B | Future.wait subset first → sleep 50ms → superset expand | 200+200 duas `cs_` | ledger superset `a1WRM6mj…`; órfã `a1sTR7NS…`; pass2 repeat 2 `cs_` | **HOLD** P1-1 | SIM |
| C1 | DT-C | `total_eur=0`+`item_price=0.01` SKU 18€ | 200 **2323** ¢ | amount catálogo | FAIL | NÃO |
| C2 | DT-C | Session open → JWT PATCH shipping=ctt; coupon SAVE90 | PATCH 200; re-CPI/coupon 2995 | shipping **não** mudou (`entrega em mão`) | FAIL | NÃO |
| C3 | DT-C | 2 buyers última unidade qty=1 | insert2 400 `order_hold_exceeds_stock` | 0 Sessions do 2.º | FAIL | NÃO |
| C4 | DT-C | Future.wait CPI ∥ unlist+qty=0 | CPI 400 not listed | `list_on_marketplace=false` qty=0 | FAIL | NÃO |
| C5 | DT-C | payment_method JSON array `["MB WAY"]` + notes mismatch | array 400 off-platform; mismatch in-app 200 | arrPm `["MB WAY"]`; sem `cs_` no array | FAIL | SIM |
| D1 | DT-D | Stripe TEST pago 4242 + caixa | e2e `setup_paid_order` 200 | `pago` PI `pi_3UCjDaH7FWYUN3jh0CZnRCSz` 590¢ stock 2→1 `applied=1` | FAIL | NÃO |
| D2 | DT-D | bag 2 sellers | 400 one seller | sem `cs_` | FAIL | NÃO |
| D3 | DT-D | JWT PATCH qty=99; CPI quantity=99 stock=1 | JWT 403; CPI 1745 ¢ | quantity imutável | FAIL | NÃO |

Linhas na tabela: **20** (≥20). Races `Future.wait`: **10** (A3, A4, B1, B2, B3, B4, B5, B6, B7, C4). Stripe TEST pago: **sim**. classe_nova=SIM: **9**.

HOLD na tabela = finding (B1/B3/B5/B6/B7 = um P1). FAIL = ataque bloqueado. SKIP = 0.

---

## Lentes (≥6/8)

| Lente | Evidência |
|-------|-----------|
| DT1 Session | D1 PI succeeded; D2 bag sem Session cross-seller |
| DT2 mutex | A4 bags disjuntos; JWT sem GRANT (403) na tabela mutex |
| DT3 overlap novo | B1 6∥4 duas `cs_`; B3 ABCDE∥idx2 duas `cs_`; B2 triângulo 400; B4 reuse |
| DT4 timing | A3 100ms ≤1; B5/B6/B7 stagger 50–200 ms |
| DT5 stock | C3 hold stock; C4 unlist 400; D3 qty 403 / 1745 ¢ |
| DT6 preço | C1 2323 ¢; C2 amount estável 2995; C5 array off-platform |
| DT7 claim | A1 reclaim morta; A2 futuro; A5 JWT/RPC/CPI alheio 403/400 |
| DT8 caixa | PI succeeded 590¢; buyer3 0 estável; seller 2,00→1,00 nesta ronda (e2e não creditou o pago 5,90 €) |

---

## Tácticas mínimas (quota)

1. Checkout Stripe TEST pago (4242 / `setup_paid_order`): **sim** — order `db436fff-51a3-4ce8-ac7d-cd38092895d5`, PI `pi_3UCjDaH7FWYUN3jh0CZnRCSz`, `amount_paid_cents=590`, qty 2→1
2. ≥5 races `Future.wait` distintas: **sim** (10: A3, A4, B1, B2, B3, B4, B5, B6, B7, C4)
3. Tabela ≥20: **20**
4. Matriz DT-A (5) DT-B (7) DT-C (5) DT-D (3): **sim**
5. Lentes ≥6/8: **8/8**
6. ≥4 classe_nova: **9** (A3, B1–B7, C5)

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → sem expire/retrieve nativo; settle 402
- A5 owner CPI 400 `order claim contention` enquanto o token `claiming:` plantado por service_role ainda estava vivo — esperado no TTL; **não** é finding (JWT não escreveu o claim)
- Buyer LIVE_OPS no tecto 60/h (pass1 429) — ronda LIVE isolada em buyer3
- Seller wallet 2,00→1,00 na ronda (pago 5,90 € via e2e não creditou wallet imediato — igual a DN); **não** contado como P2 sem nexo causal com as probes de saco
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_dt_20260906T1739/_rtdt.dart`
- `tool/redteam_blind_dt_20260906T1739/pass1.dart` + `pass1_findings.json` + `probes.json`
- `tool/redteam_blind_dt_20260906T1739/pass2.dart` + `pass2.json`
- `tool/redteam_blind_dt_20260906T1739/probes_429_rate_limit.json` (ronda LIVE_OPS 429, fora da tabela)

RESUMO_NUMERICO: P0=0 P1=1 P2=0 P3=0 TOTAL=1
