# FROZEN_REPORT — RED TEAM CEGO EO · Maratona dinheiro · POS_OPEN_GATE

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 0

```
1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0
```

```
AUDITOR: REDTEAM_BLIND_EO_MONEY_MARATHON_POS_OPEN_v1
probes_na_tabela: 28 · classes_novas: 27 · races: 6 · stripe_ops: 11
VEREDICTO: PASS_CEGO_SATURADO
```

```
FROZEN_AT: 2026-09-06T20:05:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [EO1, EO2, EO3, EO4, EO5, EO6, EO7, EO8]
prefix: RTEO-20260906T1952
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · JWT B1/S1 + B2/S2 fixture · `service_role` só fixture / observação / restore / end_live / mark enviado-concluido. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

Coptic payout key · charset 400 = **não corridos** (HOLD anti-atrofia). GET unpaid 402 **dentro** de A1. Buyer refund 403 **dentro** de C3 (seller 3×). B6 seller≠owner = **1 residual**. Residual clássico 1/28 ≪ 40%. **Não** ATROFIA_ABORT.

Sem `sk_test_` local → captura 4242 das Checkout Sessions de tip **não**. Dinheiro TEST = e2e `setup_paid_order` + refund-order + Connect Transfer.

--------------------------------------------------
## Missão

O servidor manda no dinheiro. Cliente amount/session/tip_id/webhook forge não mintam. Idempotency: 2× settle / 2× refund / 2× payout → 1 efeito. Tip unpaid nunca credita; CORS não ecoa origins hostis.

**Resposta:** **Missão fechada.** POST settle qs unpaid **400** metadata + GET **402**; quote servidor **1325¢** vs amount cliente 1; `fase2_e2e_settle` JWT **401** `service_role required`. Tip hostil **400**; RPC JWT **403/404**; GET unpaid **pending Δ=0**. Webhook forge/replay/PI-swap **400**. CORS CPI/tip/refund → `https://fleaber.pt` (webhook OPTIONS `*` ≠ echo). Buyer refund **403**; seller 3× **1** `re_`; S2 alheia **403**; enviado/concluido **403** `order_refund_blocked_shipped`. JWT insert/patch Δ=0 acct próprio. Payout over/dest **400**. ∥ mesma key **1** `tr_`; 2.ª key **1** `tr_` distinto (esperado). release∥disputa 0ms venda+estorno **net=0** claim aberto; 50ms dispute-first **venda=0** open **both=false**. Mint JWT **não**. Double Transfer na mesma key **não**.

--------------------------------------------------
## Findings abertos

Nenhum. P0=0 P1=0 P2=0 P3=0.

--------------------------------------------------
## TABELA DE PROVAS (28)

| probe_id | edge/rpc | payload | HTTP | Stripe/BD Δ | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|----------|---------|------|-------------|------------------|--------------|
| A1 | CPI POST qs settle + GET unpaid | unpaid metadata.order_id alheio amount=1 | POST **400** metadata · GET **402** | oidA `reserva_pendente` quoted=1325 | **HOLD** | **SIM** |
| A2 | GET settle sid hostil | inexistente / `%20` / `pi_` / `session_id[]` | **400** ×4 genérico | oracle=false | **HOLD** | **SIM** |
| A3 | GET/POST sidA JWT B1 + CPI inject | sidA (B2) → oidB (B1) | GET **402** · POST **200** nova `cs_test_a1IVYz…` · CPI **400** | A/B `reserva_pendente` | **HOLD** | **SIM** |
| A4 | CPI amount body/qs ≠ quote | amount=1 vs SKU 12€; GET `&amount=1` | ck **200** · GET **402** | **quoted=1325** stripe=1325 | **HOLD** | **SIM** |
| A5 | GET∥POST settle paralelo | Future.wait sidA | **402** + **400** | `reserva_pendente` | **HOLD** | **SIM** race |
| A6 | GET cancel + reuse + PUT settle | cancel; 2.º POST; PUT metadata | cancel **402** · reuse **mesmo** `cs_test_a1kRL5…` · PUT **400** | `reserva_pendente` | **HOLD** | **SIM** |
| A7 | `fase2_e2e_settle` JWT | POST qs=1 JWT B2 PI alheio; GET JWT B1 | POST **401** `service_role required` · GET **402** | A/B pendente | **HOLD** | **SIM** |
| B1 | tip POST amounts hostis | 0/−1/`1e6`/`2,00`/0.5/501/abc + object `captured=true` + tip_id + live fake | todos **400** | 0 Session hostil | **HOLD** | **SIM** |
| B2 | RPC `batata_settle_live_tip_from_stripe` JWT | tip real unpaid paid_cents=99999 B2+S1 | B2 **403** 42501 · S1 **404** PGRST202 | tip **pending** Δ=0 | **HOLD** | **SIM** |
| B3 | tip∥end_live∥unpublish | Future.wait tip · PATCH lives JWT · hub JWT | tip **200** `cs_test_a1kXES…` · end **403** lives · unpub **200 []** | tip **pending** | **HOLD** | **SIM** race |
| B4 | tip∥CPI bag mesmo buyer | Future.wait tip · bag amount=1 | tip **200** `cs_test_a1hcRE…` · bag **400** metadata | tip pending Δ=0 | **HOLD** | **SIM** race |
| B5 | tip unpaid GET settle | GET `checkout_return=success` sid B2 | **200** texto unpaid | tip `cs_test_a1OK91…` **pending** Δ=**0** | **HOLD** | **SIM** |
| B6 | tip seller≠owner | S2 na live S1; S1 na live S2 | **400** `Tip seller does not own this live` ×2 | — | **HOLD** | não |
| C1 | stripe-webhook forge + replay 2× + PI swap | sem sig + `v1=deadbeef` ×2 livemode=true + `payment_intent.succeeded` | **400** missing · **400** invalid ×3 · GET **405** | — | **HOLD** | **SIM** |
| C2 | CORS Origin null/evil/ext | OPTIONS CPI/tip/refund/webhook + POST evil CPI | ACAO `https://fleaber.pt`; webhook OPTIONS `*` | echoes=[] | **HOLD** | **SIM** |
| C3 | buyer refund 403 + seller ×3 | oid `c94cbace-…` PI `pi_3UClH0…` | buyer **403** · seller 200 `idempotent` ×3 | **1** `re_3UClH0H7FWYUN3jh0RBOsF01` | **HOLD** | **SIM** |
| C4 | refund∥release | Future.wait refund + rel B + rel S `aca5b8dc-…` | ref **200** `re_3UClH6…` · rel **false** ×2 | Δ=**0** net=0 | **HOLD** | **SIM** race |
| C5 | refund amount body > captura | amount=999999 na order já refundida C4 | **200** `already_refunded` **amount_cents=590** | 1 `re_` 590¢ | **HOLD** | **SIM** |
| C6 | refund order alheia S2 | JWT S2 oid S1 `354d278d-…` PI `pi_3UClHE…` | **403** Sem permissão | st=`pago` refund=null | **HOLD** | **SIM** |
| C7 | refund após enviado/concluido | `4361e440-…` enviado; `6f85580c-…` concluido | **403** `order_refund_blocked_shipped` ×2 | re=null | **HOLD** | **SIM** |
| D1 | JWT INSERT txn / PATCH balance / dest | amount=7777 oid fake; balance=99999; dest alien | ins **400** 22P02 · bal **400** PGRST204 · dest **200 []** | Δ=0 acct `acct_1U5mYb…` | **HOLD** | **SIM** |
| D2 | payout over + dest/user_id alheio | 99999999 · user_id=S2 dest alien 100¢ | over **400** insuficiente · dest **400** another user | 0 Transfer | **HOLD** | **SIM** |
| D3 | payout∥payout mesma key + 2.ª key | Future.wait key `rteoParallelSame1952k` vs header; depois outra key | a/b **200** **mesmo** `tr_1UClHT…` · other **200** `tr_1UClHW…` | 1 tr_ / key; n_new=2 esperado | **HOLD** | **SIM** race |
| D4 | RPC credit/claw/finish/debit JWT | credit 50; claw fake; finish tr_fake; debit 100¢ | 403 / 403 / **404** / 403 | Δ vs D1 = −2,00 (= D3 2×100¢) | **HOLD** | **SIM** |
| D5 | release∥disputa 0ms + 50ms | `10f26682-…` 0ms; `c3016c96-…` dispute-first 50ms | 0ms rel **true** disp **201** · 50ms disp **201** | 0ms venda+estorno **net=0** open; 50ms venda=0 open **both=false** | **HOLD** | **SIM** race |
| E1 | ≥3 pagos 4242 no fio | C3/C4/C6/C7e/C7c/D5_0/D5_50 | n=**7** | 7 `pi_3UClH*` succeeded 590¢ | **HOLD** | **SIM** |
| E2 | tip Session unpaid + GET path | sid `cs_test_a1OK91…` | GET 200 texto unpaid | **pending** | **HOLD** | **SIM** |
| E3 | Transfer count | D3 same+other | n_new=2 | `tr_1UClHT…` 100¢ after=22 · `tr_1UClHW…` 100¢ after=21 | **HOLD** | **SIM** |

probes_na_tabela: **28** (A1–A7 · B1–B6 · C1–C7 · D1–D5 · E1–E3).

`classe_nova=SIM`: 27 (todas excepto B6 residual).  
Races: A5, B3, B4, C4, D3, D5 → **6**.

Dinheiro Stripe TEST real: **sim** — 7 PI succeeded 590¢ (`pi_3UClH0…`, `pi_3UClH6…`, `pi_3UClHE…`, `pi_3UClHH…`, `pi_3UClHL…`, `pi_3UClHY…`, `pi_3UClHb…`); 2 refunds (`re_3UClH0H7FWYUN3jh0RBOsF01`, `re_3UClH6H7FWYUN3jh0dFzD4E7`); 2 Transfers (`tr_1UClHTH7FWYUN3jhkAnpAHI3`, `tr_1UClHWH7FWYUN3jhrjrRgB5T`). Tip Sessions unpaid `cs_test_a1OK91…` / `cs_test_a1kXES…` / `cs_test_a1hcRE…` **não** capturadas.

Directos da corrida terminados (`is_active=false`). Hub S1 restaurado.

pass2 (não conta na quota): B3 unpub JWT B2 → **200 []** `hub_published` **true→true**; D3 ledger 1 row por `tr_` keys distintas; D5 oracle both=false (0ms clawback; 50ms sem crédito).

--------------------------------------------------
## HOLD (não contar)

| ID | Lente | Resultado |
|----|--------|-----------|
| A1 POST qs + GET unpaid | EO1 | 400/402; `reserva_pendente` |
| A2 sid fake/ws/pi_/[] | EO1 | 400 genérico; sem oráculo Stripe |
| A3 session alheia | EO1 | GET 402; POST 200 **nova** Session oidB; A/B pendente |
| A4 amount cliente | EO1 | quoted 1325¢ vs 1 |
| A5 GET∥POST | EO7 | 402+400 |
| A6 cancel/reuse/PUT | EO1 | mesmo `cs_`; PUT 400 |
| A7 fase2 JWT | EO1 | 401 service_role |
| B1 amount/tip_id/live/captured | EO2 | 400 |
| B2 RPC tip JWT | EO2 | 403 42501 / 404 assinatura |
| B3 tip∥end | EO7 | pending; lives 403; unpub 200 [] |
| B4 tip∥bag | EO7 | pending + bag 400 Δ=0 |
| B5 GET tip unpaid | EO2 | pending Δ=0 (200 copy unpaid) |
| B6 seller≠owner | EO2 | **400** — **1 residual clássico** |
| C1 webhook | EO3 | missing/invalid_signature; GET 405 |
| C2 CORS | EO4 | fleaber.pt; webhook OPTIONS `*` ≠ echo |
| C3 buyer + seller 3× | EO5 | **403** (não conta sozinho) + 1 `re_` |
| C4 race | EO7 | 1 `re_`; release false; Δ=0 |
| C5 amount body | EO5 | ignora 999999; responde 590¢ |
| C6 S2 alheia | EO5 | 403 |
| C7 enviado/concluido | EO5 | 403 shipped |
| D1 JWT forge | EO6 | 400/400/200 []; acct próprio |
| D2 over/dest | EO6 | 400 / 400 |
| D3 ∥ keys | EO7 | mesma key 1 `tr_`; 2.ª key 1 `tr_` |
| D4 RPC JWT | EO6 | 403/404; Δ−2 = D3 Transfers |
| D5 0ms+50ms | EO7 | net=0 + claim; 50ms sem venda |
| E1 caixa PI | EO8 | 7× 4242 |
| E2 tip path | EO8 | pending |
| E3 count | EO8 | 2 tr_ = 2 keys |

**Não é finding:** A3 POST 200 devolveu **nova** Checkout Session (`cs_test_a1IVYz…`) sem liquidar sidA nem oidB. C2 webhook OPTIONS `Access-Control-Allow-Origin: *` **não** ecoa `null`/evil — Stripe webhook não é superfície browser. B5 GET tip unpaid **200** copy «ainda não confirmado» sem crédito — **não contar** (igual ED/EJ). D4 Δ=−2,00 bate com D3 (1€+1€). D5 0ms `release=true` **e** disputa `201` **com** clawback net=0 (missão: sem crédito **líquido** + claim). C5 API **não** expõe amount cliente — servidor usa captura 590¢.

**Contabilidade:** D5 0ms +5 venda −5 estorno = 0; D5 50ms 0. Payout D3 −1 € −1 €. Sem mint JWT. 2 `re_`. 2 `tr_` (2 intenções).

--------------------------------------------------
## CHECKLIST

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. POST settle qs unpaid / metadata hostil credita — NÃO (400/402)
10. Session inexistente / whitespace / `pi_` / array ecoa oráculo Stripe — NÃO (400 genérico)
11. settle session alheia liquida outra order — NÃO
12. amount body/qs vence quote servidor — NÃO (1325 vs 1)
13. GET∥POST settle unpaid credita — NÃO
14. cancel / reuse / PUT settle liquida unpaid — NÃO (mesmo sid; PUT 400)
15. `fase2_e2e_settle` JWT comprador — NÃO (401)
16. Tip amount / tip_id / live fake / captured hostil — NÃO (400)
17. RPC `batata_settle_live_tip_from_stripe` JWT — NÃO (403/404)
18. tip∥end_live / unpublish credita — NÃO (pending; lives 403; unpub [])
19. tip∥CPI bag credita — NÃO
20. Tip unpaid GET settle Δwallet — NÃO (pending Δ=0)
21. Tip seller≠owner — NÃO (400 residual)
22. Webhook sem sig / sig morta / replay / PI swap — NÃO (400)
23. CORS ecoa `null` / evil.com / chrome-extension — NÃO
24. Buyer refund-order aberto — NÃO (403)
25. Seller refund 3× duplica `re_` — NÃO (1 id)
26. Refund∥release crédito líquido — NÃO (Δ=0)
27. Refund amount cliente > captura — NÃO (590¢)
28. Seller2 refund order alheia — NÃO (403)
29. Refund após enviado/concluido — NÃO (403 shipped)
30. JWT insert txn / PATCH balance / dest Connect — NÃO
31. Payout overbalance / dest alheio extra Transfer — NÃO
32. Payout∥ mesma key >1 `tr_` — NÃO (1; 2.ª key = 2.ª intenção)
33. RPC credit/clawback/finish/debit JWT — NÃO
34. Release∥disputa crédito líquido + claim — NÃO (clawback / só disputa)
35. ≥3 pagos 4242 + tip unpaid + Transfer count — SIM (7 PI, pending, 2 tr_ = 2 keys)
36. Saturação P0–P2=0 após quota ≥28 + ≥8 classe_nova + ≥6 races + ≥5 $$ TEST — SIM

Lacuna honesta: captura 4242 das Checkout Sessions de **tip** não (sem `sk_test_` local). C5 amount>captura só via campo extra no JSON — a API **não** expõe `amount` no tipo; servidor ignora. B4 bag 400 «Missing payment metadata» (mutex/claim) — tip∥bag mesmo assim Δ=0. B2 seller JWT 404 por assinatura RPC (não GRANT útil).

--------------------------------------------------
## LENTES

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| EO1 settle | SIM A1–A7 | não |
| EO2 tip | SIM B1/B2/B5/B6 | não |
| EO3 webhook | SIM C1 | não |
| EO4 CORS | SIM C2 | não |
| EO5 refund | SIM C3/C5/C6/C7 | não |
| EO6 payout | SIM D1/D2/D4 | não |
| EO7 race | SIM A5/B3/B4/C4/D3/D5 | não |
| EO8 caixa | SIM E1/E2/E3 | não (sem mint) |

Lentes **8/8** (mín. 6).

--------------------------------------------------
## INVARIANTES

POST `?checkout_return=success` unpaid + metadata hostil não liquida (400; GET 402). Sid inexistente / whitespace / `pi_` / `session_id[]` → 400 genérico. Session alheia não paga outra order. Quote servidor 1325¢ vs amount cliente 1. `fase2_e2e_settle` exige Bearer=service_role. GET∥POST / cancel / PUT settle unpaid sem crédito (reuse = mesmo `cs_`). Tip amount/`1e6`/`captured`/`tip_id`/live fake autoridade servidor (400). RPC settle tip **não** em `authenticated`. Tips GET unpaid não creditam (pending Δ=0) mesmo ∥ end_live ou bag. Seller≠owner 400. Webhook recusa forge, replay e event-swap. CORS CPI/tip/refund não ecoa `null`/evil/ext. Refund seller-only 403; 3× = 1 `re_`; S2 alheia 403; janela enviado/concluido fechada; amount cliente ignorado. JWT não minta wallet. Payout over/dest alheio 400. ∥ mesma idempotency_key = 1 Transfer. release∥disputa: clawback net=0 ou só disputa.

--------------------------------------------------
## ARTEFACTOS

- `tool/redteam_blind_eo_20260906T1952/_rteo.dart`
- `tool/redteam_blind_eo_20260906T1952/pass1.dart` + `pass1.json`
- `tool/redteam_blind_eo_20260906T1952/pass2.dart` + `pass2.json` (B3 unpub · D3 ledger · D5 oracle)
- este `FROZEN_REPORT.md` + `FROZEN_REPORT.json`

**NÃO CORRIGIR.** Seller-only refund: **não abriu** (403).

```
AUDITOR: REDTEAM_BLIND_EO_MONEY_MARATHON_POS_OPEN_v1
probes_na_tabela: 28 · classes_novas: 27 · races: 6 · stripe_ops: 11
VEREDICTO: PASS_CEGO_SATURADO
```

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
