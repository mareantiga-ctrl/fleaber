# FROZEN_REPORT — RED TEAM CEGO DL · Edge settle / tip / refund / webhook · POS_DBDG

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 0

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_DL_EDGE_SETTLE_POS_DBDG_v1
FROZEN_AT: 2026-09-06T16:25:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DL1, DL2, DL3, DL4, DL5, DL6, DL7]
probes_na_tabela: 13
VEREDICTO: PASS_CEGO_SATURADO
prefix: RTDL-20260906T1612
staging: fxdknzrqjenzqcvnwqqq
```

Staging · Stripe TEST (Sessions `cs_test_*` + PI `pi_3UCho*` succeeded + refunds `re_3UCho*` + Transfers `tr_1UCho*`) · JWT B1/S1 + B2/S2 fixture · `service_role` só fixture / observação / restore. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

Sem `STRIPE_SECRET_KEY` `sk_test_` no env local → sem expire/confirm/metadata Stripe nativo. A4 = reuse da Session open + GET `cs_` morta. Captura 4242 das Checkout Sessions **não** exercitada; dinheiro TEST = e2e `setup_paid_order` + refund-order + Connect Transfer.

--------------------------------------------------
## TABELA DE PROVAS (13)
--------------------------------------------------

| probe_id | edge/rpc | payload | HTTP | Stripe/BD Δ | HOLD\|FAIL\|SKIP |
|----------|----------|---------|------|-------------|------------------|
| A1 | create-payment-intent GET | settle unpaid `cs_test_a1glkAL…` | **402** unpaid | order `b2eaff60-…` `reserva_pendente` amount_paid null | **HOLD** |
| A2 | GET settle tip↔order | `cs_tip` no endpoint encomenda; `cs_order` no endpoint tip | tip→order **402**; order→tip 200 texto unpaid | A/B `reserva_pendente`; tip `d4c61054-…` **pending** | **HOLD** |
| A3 | create-payment-intent POST | body amount=1 total=50 vs SKU 12,00€ | **200** | `server_amount_cents=1325` `amount_total=1325` price_total 13,25 | **HOLD** |
| A4 | POST reuse + GET dead cs_ | 2.º POST mesma order; GET `cs_test_dead…` | reuse **mesmo** `cs_test_a1glkAL…`; dead **400**; GET unpaid 402 | status `reserva_pendente` | **HOLD** |
| A5 | stripe-webhook POST | assinatura forjada `checkout.session.completed` paid | **400** `invalid_signature` | order A inalterada | **HOLD** |
| B1 | create-live-tip-checkout POST | amount 0/0.01/-1/0.5/501 + tip_id cliente | todos **400** | 0 Session | **HOLD** |
| B2 | create-live-tip-checkout GET | Session S1 → unpublish hub → GET unpaid | create 200 `cs_test_a1ACQI2…`; GET unpaid | tip `eecaf597-…` **pending** Δwallet **0** hub restored | **HOLD** |
| B3 | create-live-tip-checkout POST | seller_id ≠ dono da live (S2 na live S1 e S1 na live S2) | **400** `Tip seller does not own this live` | — | **HOLD** |
| C1 | refund-order | JWT comprador order pago `ab76a649-…` | **403** Sem permissão | status `pago`; Δseller 0; refund_id null | **HOLD** (não conta) |
| C2 | refund-order ×2 | seller 2× no pago `1d9ea733-…` PI `pi_3UChoUH…` 590¢ | 200 + 200 `already_refunded` `idempotent` | **1** `re_3UChoUH7FWYUN3jh12oWZmK8`; status `cancelado` | **HOLD** |
| C3 | refund-order ∥ release | Future.wait seller refund + release buyer/seller | refund 200 `re_3UChoaH…` 590¢; release **false** | Δwallet **0** | **HOLD** |
| C4 | create-connect-account | mesma key amount 100 depois 500; S2 reutiliza key S1 | 200 + 200 `idempotent`; S2 **400** IBAN | **1** `tr_1UChohH7FWYUN3jhhaPsRuq4` Δ=−1,00 | **HOLD** |
| C5 | create-connect-account | dest=`acct_1UChokHMTQUwRF3q` usd; amount=99999999 | dest 200 Transfer **própria**; huge **400** insuficiente | `tr_1UChoqH7FWYUN3jhGuB1mQnS` Δhuge **0** | **HOLD** |

DL-A: 5 (A1–A5) · DL-B: 3 · DL-C: 5 · **total 13** (≥12).

Buyer refund 403 = anti-atrofia **não conta**. Coptic / charset 400 **não corridos**. Residual clássico 1/13 (C1) ≪ 50%. ATROFIA: NÃO.

Dinheiro Stripe TEST real: **sim** — 3 PI succeeded 590¢ (`pi_3UChoQH…`, `pi_3UChoUH…`, `pi_3UChoaH…`); 2 refunds (`re_3UChoUH…`, `re_3UChoaH…`); 2 Transfers (`tr_1UChohH…`, `tr_1UChoqH…`).

A3 extra: body amount=99999 na order `d5c93937-…` → evento `checkout_session_created` **amount=1325** (`confirm_a2amt.json`).

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Settle unpaid GET credita — NÃO (402)
10. session_id alheio tip↔order credita — NÃO
11. metadata/body amount vs servidor — NÃO (1325 vs 1 / 99999)
12. Reuse Session morta/2.º POST duplica captura — NÃO (mesmo sid; dead 400)
13. Webhook assinatura forjada — NÃO (400)
14. Tip amount / tip_id cliente — NÃO (400)
15. Tip mid-unpublish unpaid credita — NÃO (pending Δ=0)
16. Tip seller≠owner — NÃO (400)
17. Buyer refund seller-only aberto — NÃO (403)
18. Seller refund 2× duplica re_ — NÃO (mesmo id)
19. Refund∥release cria dinheiro líquido — NÃO (release false Δ=0)
20. Connect key hostil (amount mutate / cross-user) 2 Transfers — NÃO
21. Dest alheio / overbalance mint — NÃO
22. JWT cria saldo unpaid — NÃO
23. Edge confia total do cliente — NÃO
24. Saturação P0–P2=0 após quota ≥12 + ≥1 dinheiro TEST — SIM

Lacuna honesta: expire nativo Stripe + captura 4242 da Checkout Session **não** (sem `sk_test_` local). Refund/Transfer TEST via Edge **sim**.

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

Nenhum. P0=0 P1=0 P2=0 P3=0.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| A1 GET unpaid | 402; `reserva_pendente` |
| A2 tip↔order | 402 / texto unpaid; tip pending |
| A3 amount cliente | quote 1325¢; evento 99999→1325 |
| A4 reuse + dead | mesmo `cs_`; dead 400; sem expire nativo |
| A5 webhook forge | 400 invalid_signature |
| B1 amount/tip_id | 400 |
| B2 mid-unpublish unpaid | pending Δ=0; S1 `hub_published=true` restored |
| B3 seller≠owner | 400 |
| C1 buyer refund | **403** — **não conta** (anti-atrofia) |
| C2 refund 2× | 1 `re_`; idempotent |
| C3 race | refund sim; release false; Δ=0 |
| C4 key 100→500 + S2 | 1 `tr_`; S2 400 IBAN (não Connect ready) |
| C5 dest/overbal | Transfer própria `acct_1U5mYbQeUNx8ar08`; huge 400 Δ=0 |
| Coptic / charset 400 | não corridos |

Pass1 A1/A3 SKIP `order claim contention` + B1 429 checkout — **não** na tabela final; A1–A4 = pass2b (JWT B2).

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| DL1 settle | SIM A1/A2/A3/A4/A5 | não |
| DL2 tip | SIM B1/B2/B3 | não |
| DL3 refund actor | SIM C1 | não (403) |
| DL4 idempotency | SIM C2 + C4 | não |
| DL5 race | SIM C3 | não |
| DL6 Connect | SIM C4/C5 dest | não |
| DL7 Δwallet | SIM C3/C4/C5 | não (sem mint) |

Lentes 7/7 (mín. 5).

--------------------------------------------------
## INVARIANTES
--------------------------------------------------

Settle GET não confia `checkout_return=success` se Session unpaid. Tip amount/`tip_id` autoridade servidor (400). Refund seller-only 403. Refund Stripe idempotente (1 `re_`). Race refund∥release sem crédito wallet. Connect ignora destination do body; overbalance 400; mesma idempotency_key + amount hostil = 1 Transfer.

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_dl_20260906T1612/_rtdl.dart`
- `probes.dart` + `probes.json` (B/C + A5)
- `pass2.dart` (B1 429 — descontinuado)
- `pass2b.dart` + `pass2b.json` (A1–A4)
- `confirm_a2amt.json` (amount 99999 → 1325)
- este `FROZEN_REPORT.md` + `FROZEN_REPORT.json`

**NÃO CORRIGIR.** Seller-only refund: **não abriu** (403).
