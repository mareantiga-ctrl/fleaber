# FROZEN_REPORT — REDTEAM_BLIND_DZ_BAG_MUTEX_POS_DTDY_v1

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
AUDITOR: REDTEAM_BLIND_DZ_BAG_MUTEX_POS_DTDY_v1
FROZEN_AT: 2026-09-06T18:40:00+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 20
classes_novas: 9
lentes_cobertas: [DZ1, DZ2, DZ3, DZ4, DZ5, DZ6, DZ7, DZ8]
pocos_tentados: [DZ-A, DZ-B, DZ-C, DZ-D]
races_future_wait: [A3, A4, B1, B2, B3, B4, B5, B6, B7, C4]
stripe_test_pago: true
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTDZ-20260906T1827-` · pasta: `tool/redteam_blind_dz_20260906T1827/`.  
Atacantes: anon · buyer JWT fresco (`ab2a0239-f982-4978-95c8-6b8c9a6f0f2a`) · seller JWT · buyer2 · seller2. `service_role` só fixture/observação.

Oráculo Session: sem `sk_test_` local. GET HTML do Checkout contém a substring `expired` no JS (falso positivo). Prova de *open/payable* = **2× HTTP 200** + **2 `cs_test_` distintas** + `reused=false` + settle **402** em ambas. Pass2 confirmou B1/B3/B7.

---

## P1-1 — Overlaps pós-DTDY (6∥4 0ms e 50ms, ABCDE∥C, bag∥single∥bag, stagger shrink/expand): duas Sessions

**O que isto é:** o comprador pede ao mesmo tempo o pagamento de um saco grande e, em paralelo, um subconjunto, um artigo avulso, ou o mesmo saco com 50 ms de atraso (encolher ou expandir). Depois do fecho DTDY (espera 40×200 ms + expandir→expirar + re-claim), o cadeado tinha de entregar no máximo um link Stripe *open/payable*, ou recusar o segundo.

**Quem / onde:** comprador (JWT buyer3 fresco) no checkout do saco.

**O que fizemos:**
- B1: `Future.wait` saco ABCDEF ∥ saco BCDE a t=0 **e** t=50 ms. Confirm pass2 + `full_urls.json`.
- B3: saco de 5 ∥ pagamento avulso da linha **C** (meio). Confirm pass2.
- B5: saco ∥ avulso +200 ms ∥ saco (3 corrotinas).
- B6: saco cheio t=0 → sleep 50 ms → subset.
- B7: subset t=0 → sleep 50 ms → superset (expand + re-claim). Confirm pass2.

**Esperado vs resultado**
- API B1 6∥4 t=0: esperado ≤1 `cs_` open/payable ou 2.º contention/reuse · visto **2** `cs_test_` distintas, ambas HTTP 200, `reused=false` (`a1tb6kvv…` + `a1ma4E8x…`); pass2 `a1jhT4w5…` + `a1SIY17H…`; capture `a1ht8Lkq…` + `a1TJMr7G…`
- B1 t=50 ms: **2** `cs_` (`a1c4PtL6…` + `a1sAVIdP…`)
- Ledger B1: A–F com a Session do saco de 6; a Session de 4 linhas ficou órfã (pass1, pass2, capture)
- API B3 ABCDE∥C: **2** `cs_` (`a10VhLZg…` + `a1H6w0VD…`); pass2 `a1XSLrHq…` + `a1MdyA6j…`; ledger = sid do saco; single órfã
- API B5 bag∥single∥bag: **2** `cs_` (`a1CML9TP…` no ledger + órfã `a15dxA4g…`; 3.º HTTP 200 reused da órfã)
- API B6 stagger 50 ms full→subset: **2** `cs_` (`a1b7cqHm…` ledger + órfã `a17VS2sb…`)
- API B7 expand 50 ms: **2** `cs_` HTTP 200 `reused=false` (`a1XcTK4p…` subset + `a1ZkjgmV…` superset); ledger nas 4 linhas = sid do **superset**; pass2 `a1SFhd56…` + `a1NazXyX…` (ledger = superset). A menor **não** foi recusada; o cliente recebeu dois links. Sem retrieve nativo não dá para jurar `status=expired` na órfã — settle **402** nas duas.
- Stripe: sem `sk_test_` local. **Não pagámos as duas.**

**Conclusão:** **P1** — o cliente recebeu dois links; uma Session ficou órfã no ledger. Não é P0: não pagámos as duas. A espera 40×200 ms + re-claim DTDY **não** impede duas criações em overlap 6∥4 (0 ms e 50 ms), ABCDE∥C, bag∥single∥bag, nem stagger shrink/expand. Triângulo AB∥BC∥CA, 2× bag UUID invertido e timeout 100 ms∥retry **fecharam** (≤1 / reuse / overlapping).  
**Prova:** `probes.json` B1/B3/B5/B6/B7 + `pass2.json` + `full_urls.json`.

---

## P2-1 — Denylist off-platform não cobre multibanco / ifthenpay JSON / contra-reembolso

**O que isto é:** encomendas marcadas com métodos que em Portugal são fora da app (Multibanco SIBS, Ifthenpay, contra-reembolso) não devem abrir um link Stripe.

**Quem / onde:** comprador JWT, checkout.

**O que fizemos:** insert `payment_method=multibanco`; insert serviço `{"psp":"ifthenpay","entity":"11234"}`; insert `contra_reembolso`; CPI em cada um.

**Esperado vs resultado**
- API: esperado 400 off-platform · visto **200** + `cs_test_` nos três (`a1inopqy…`, `a1UT24hQ…`, `a1qxSCZ1…`)
- BD: métodos gravados como enviados; Sessions criadas

**Conclusão:** **P2** — falha de denylist (ângulos novos, não wrap `x`/`via`). O dinheiro ainda entra pela Checkout da plataforma; não há prova de cobrança dupla. Não é P1 de mutex.  
**Prova:** `probes.json` C5.

---

## Anti-atrofia

Exactos **não corridos / não contados** (HOLD residual clássico):
- 4∥2 clássico — **não** na tabela (substituído por 6∥4 0 ms e 50 ms)
- 5∥3 clássico — **não** na tabela
- bag∥single meio clássico como linha extra — **não** (B3 = ABCDE∥C na matriz obrigatória)
- `mb way x` — **não** (C5 = multibanco / ifthenpay / COD)
- claiming TTL exacto — **não** (A2 = futuro/malform)
- expand clássico «1 open + menor expired» como linha extra — **não** (B7 na matriz; resultado = dual create)

Fechos novos documentados (FAIL, ataque bloqueado):
- B2 AB∥BC∥CA → 400 overlapping + 200 + 400; 1 `cs_`
- B4 2× bag UUID invertido → 200 + 200 **mesmo** `cs_` (`reused=true` num dos dois)
- A3 timeout 100 ms ∥ complete ∥ retry 800 ms → 598 + 200 + 200 mesmo `cs_`; 1 sid
- A1 dead `cs_` → buyer2 400; owner reclaim 200
- A2 claiming futuro → RPC JWT 403; CPI 200 `cs_` coerente
- A4 bags disjuntos → 2 `cs_` (linhas sem overlap); JWT mutex **403**
- A5 JWT PATCH `cs_` 403 immutable; RPC claim alheio 403; buyer2 CPI 400
- C1 underpay → Session **2323** ¢
- C2 PATCH shipping HTTP 200 **sem mutar** (`entrega em mão`); amount 2995 estável
- C3 2.º insert 400 `order_hold_exceeds_stock`
- C4 unlist∥CPI → CPI 400 not listed
- D1 pago 4242 coerente
- D2 cross-seller 400
- D3 qty JWT 403; CPI 1745 ¢ (1 unidade)

HOLD na tabela = B1/B3/B5/B6/B7 (um P1) + C5 (um P2) = **6/20 = 30%** < 40%. **Não** ATROFIA_ABORT.  
classe_nova=SIM: A3, B1, B2, B3, B4, B5, B6, B7, C5 (**9** ≥ 4).

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|-----------|------------------|--------------|
| A1 | DZ-A | plant `cs_test_dead`; buyer2 CPI; owner retry | buyer2 400; retry 200 `cs_test_a1iXRb7x…` | sid novo; morta não persiste | FAIL | NÃO |
| A2 | DZ-A | `claiming:<now+1y>:malformtok12ab` + RPC JWT | RPC 403; CPI 200 | sid `cs_test_a17ibdsO…` coerente | FAIL | NÃO |
| A3 | DZ-A | Future.wait bag timeout 100ms ∥ complete ∥ retry +800ms | 598 + 200 + 200 mesmo `cs_` | ledger `a1iQRzJU…`; 1 sid | FAIL | SIM |
| A4 | DZ-A | Future.wait 2 bags disjuntos mesmo buyer | 200+200 duas `cs_` | bags A/B sid distintos; JWT mutex 403 | FAIL | NÃO |
| A5 | DZ-A | JWT PATCH cs_ sem claim; buyer2 RPC token alheio + CPI | PATCH 403; RPC 403; CPI 400; owner 400 contention | claiming plantado | FAIL | NÃO |
| B1 | DZ-B | Future.wait bag 6∥4 stagger **0ms E 50ms** | t=0 200+200 duas `cs_`; t=50 200+200 duas `cs_` | ledger saco de 6; órfã de 4; pass2 repeat 2 `cs_` settle 402 | **HOLD** P1-1 | SIM |
| B2 | DZ-B | Future.wait bag AB ∥ BC ∥ CA (triângulo 3 CPI) | 400+200+400 overlapping | 1 `cs_test_a1Ta7vn6…` | FAIL | SIM |
| B3 | DZ-B | Future.wait bag ABCDE ∥ CPI single **C** (meio) | 200+200 duas `cs_` | ledger saco; single órfã; pass2 repeat 2 `cs_` | **HOLD** P1-1 | SIM |
| B4 | DZ-B | Future.wait 2× bag idêntico ordem UUID invertida | 200+200 mesmo `cs_` reused | 1 `cs_test_a13yi8Km…` | FAIL | SIM |
| B5 | DZ-B | Future.wait bag ∥ single +200ms ∥ bag (3 corrotinas) | 200+200+200 duas `cs_` (3.º reused) | ledger `a1CML9TP…`; órfã `a15dxA4g…` | **HOLD** P1-1 | SIM |
| B6 | DZ-B | Future.wait bag full → sleep 50ms → subset | 200+200 duas `cs_` | ledger full `a1b7cqHm…`; órfã `a17VS2sb…` | **HOLD** P1-1 | SIM |
| B7 | DZ-B | Future.wait subset → 50ms → superset expand + re-claim | 200+200 duas `cs_` reused=false | ledger superset; subset órfã; pass2 repeat 2 `cs_`; settle 402 nas duas | **HOLD** P1-1 | SIM |
| C1 | DZ-C | `total_eur=0`+`item_price=0.01` SKU 18€ | 200 **2323** ¢ | amount catálogo | FAIL | NÃO |
| C2 | DZ-C | Session open → JWT PATCH shipping=ctt; coupon SAVE90 | PATCH 200; re-CPI/coupon 2995 | shipping **não** mudou (`entrega em mão`) | FAIL | NÃO |
| C3 | DZ-C | 2 buyers última unidade qty=1 | insert2 400 `order_hold_exceeds_stock` | 0 Sessions do 2.º | FAIL | NÃO |
| C4 | DZ-C | Future.wait CPI ∥ unlist+qty=0 | CPI 400 not listed | `list_on_marketplace=false` qty=0 | FAIL | NÃO |
| C5 | DZ-C | multibanco + JSON ifthenpay + contra_reembolso | 200+200+200 três `cs_` | pm gravados; Sessions abertas | **HOLD** P2-1 | SIM |
| D1 | DZ-D | Stripe TEST pago 4242 + caixa | e2e `setup_paid_order` 200 | `pago` PI `pi_3UCjvlH7FWYUN3jh0mJ2zLpK` 590¢ stock 2→1 `applied=1` | FAIL | NÃO |
| D2 | DZ-D | bag 2 sellers | 400 one seller | sem `cs_` | FAIL | NÃO |
| D3 | DZ-D | JWT PATCH qty=99; CPI quantity=99 stock=1 | JWT 403; CPI 1745 ¢ | quantity imutável | FAIL | NÃO |

Linhas na tabela: **20** (≥20). Races `Future.wait`: **10** (A3, A4, B1, B2, B3, B4, B5, B6, B7, C4). Stripe TEST pago: **sim**. classe_nova=SIM: **9**.

HOLD na tabela = findings. FAIL = ataque bloqueado. SKIP = 0.

---

## Lentes (≥6/8)

| Lente | Evidência |
|-------|-----------|
| DZ1 Session open | B1 2× `cs_` 200; D2 bag sem Session cross-seller |
| DZ2 mutex | A4 bags disjuntos; JWT sem GRANT (403) |
| DZ3 expand re-claim | B7 2 HTTP 200; ledger = superset; órfã settle 402 |
| DZ4 timing | A3 100 ms ≤1; B5/B6 stagger 50–200 ms dual create |
| DZ5 stock | C3 hold stock; C4 unlist 400; D3 qty 403 / 1745 ¢ |
| DZ6 preço | C1 2323 ¢; C2 amount estável 2995; C5 denylist gap |
| DZ7 claim | A1 reclaim morta; A2 futuro; A5 JWT/RPC/CPI alheio 403/400 |
| DZ8 caixa | PI succeeded 590¢; buyer3 0 estável; seller 5,00→4,00 nesta ronda (e2e não creditou o pago 5,90 €) |

---

## Tácticas mínimas (quota)

1. Checkout Stripe TEST pago (4242 / `setup_paid_order`): **sim** — order `c8175efa-a8d4-42d6-ba74-4c03aed9f2ef`, PI `pi_3UCjvlH7FWYUN3jh0mJ2zLpK`, `amount_paid_cents=590`, qty 2→1
2. ≥5 races `Future.wait` distintas: **sim** (10)
3. Tabela ≥20: **20**
4. Matriz DZ-A (5) DZ-B (7) DZ-C (5) DZ-D (3): **sim**
5. Lentes ≥6/8: **8/8**
6. ≥4 classe_nova: **9** (A3, B1–B7, C5)

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → sem retrieve `status=open` nativo; HTML Checkout tem `expired` no bundle JS (oráculo ingénuo inválido). Settle 402 nas órfãs e nas úteis.
- Webview Checkout mostrou «timed out» **também** na Session do ledger (hash completo) — não serve para distinguir expire.
- Seller wallet 5,00→4,00 na ronda (pago 5,90 € via e2e não creditou imediato — igual a DT/DN); **não** contado como finding extra.
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_dz_20260906T1827/_rtdz.dart`
- `tool/redteam_blind_dz_20260906T1827/pass1.dart` + `pass1_findings.json` + `probes.json`
- `tool/redteam_blind_dz_20260906T1827/pass2.dart` + `pass2.json`
- `tool/redteam_blind_dz_20260906T1827/full_urls.json` (URLs Checkout completas B1/B7)
- `tool/redteam_blind_dz_20260906T1827/capture_urls.dart`

RESUMO_NUMERICO: P0=0 P1=1 P2=1 P3=0 TOTAL=2
