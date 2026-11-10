# FROZEN_REPORT — RED TEAM CEGO DX · Edge settle / tip / refund / webhook / CORS · POS_DNDS

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
AUDITOR: REDTEAM_BLIND_DX_EDGE_POS_DNDS_v1
FROZEN_AT: 2026-09-06T17:42:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DX1, DX2, DX3, DX4, DX5, DX6, DX7]
probes_na_tabela: 16
classes_novas: 7
races: 4
VEREDICTO: PASS_CEGO_SATURADO
prefix: RTDX-20260906T1738
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (Sessions `cs_test_*` + PI `pi_3UCjF*` succeeded + refunds `re_3UCjF*` + Transfer `tr_1UCjFr*`) · JWT B1/S1 + B2/S2 fixture · `service_role` só fixture / observação / restore / end_live. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

Sem `STRIPE_SECRET_KEY` `sk_test_` no env local → sem expire/confirm/metadata Stripe nativo. A4 = reuse da Session open + GET `cs_` morta. Captura 4242 das Checkout Sessions **não** exercitada; dinheiro TEST = e2e `setup_paid_order` + refund-order + Connect Transfer.

Buyer refund 403 = anti-atrofia **não conta**. Coptic / charset 400 **não corridos**. Residual clássico 1/16 (B3 seller≠owner) ≪ 40%. ATROFIA: NÃO.

--------------------------------------------------
## TABELA DE PROVAS (16)
--------------------------------------------------

| probe_id | edge/rpc | payload | HTTP | Stripe/BD Δ | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|----------|---------|------|-------------|------------------|--------------|
| A1 | create-payment-intent GET | unpaid `cs_test_a1Ianu…` + sem session_id + `cs_test_inexistente` | unpaid **402**; missing **400** «Sessão em falta»; fake **400** genérico | oidA `d5b52087-…` `reserva_pendente` amount_paid null | **HOLD** | **SIM** |
| A2 | GET settle alheio | sidA (B2) + `order_id=oidB` (B1); qs `session_id` duplicado | ckB **429** quota; cross **402**; dup **402** | oidA e oidB `reserva_pendente`; sidB vazio | **HOLD** | **SIM** |
| A3 | create-payment-intent POST | amount=1 total=50 + `web_return_origin=https://evil.com` vs SKU 12,00€ | **200** | `server_amount_cents=1325` `amount_total=1325`; URL **sem** evil.com; price_total 13,25 | **HOLD** | **SIM** |
| A4 | POST reuse + GET dead | 2.º POST mesma order; GET `cs_test_dead_expired` | reuse **mesmo** `cs_test_a1Ianu…`; dead **400** | status `reserva_pendente` | **HOLD** | não |
| A5 | GET settle ∥ GET | Future.wait sidA ×2 | **402** + **402** | `reserva_pendente` amount_paid null | **HOLD** | **SIM** |
| B1 | create-live-tip-checkout POST | amount 0/-1/0.5/501 + tip_id cliente + live_id UUID fake | todos **400** (invalid / too high / Client tip_id / Live not found) | 0 Session | **HOLD** | **SIM** |
| B2 | tip ∥ end_live/unpublish | Future.wait POST tip + PATCH ended + hub unpublish | tip **400** broadcasting; end **204** | Δwallet **0**; 0 tip row | **HOLD** | **SIM** |
| B3 | create-live-tip-checkout POST | seller_id S2 na live S1; S1 na live S2 | **400** `Tip seller does not own this live` ×2 | — | **HOLD** | não |
| B4 | create-live-tip-checkout GET | Session TEST + GET unpaid + GET `live_id` query alheio | create **200** `cs_test_a1xplg…`; GET unpaid 200 texto | tip `29c25c8a-…` **pending** amount=2 Δwallet **0** | **HOLD** | não |
| C1 | refund-order | JWT comprador order pago `acc7defe-…` | **403** Sem permissão | status `pago`; Δseller 0; refund_id null; PI `pi_3UCjFS…` | **HOLD** (não conta) | não |
| C2 | refund-order ×2 | seller 2× no pago `15732717-…` PI `pi_3UCjFW…` 590¢ | 200 + 200 `already_refunded` `idempotent` | **1** `re_3UCjFWH7FWYUN3jh0EUxS3I3`; status `cancelado` | **HOLD** | não |
| C3 | refund-order ∥ release | Future.wait seller refund + release buyer/seller | refund 200 `re_3UCjFcH…` 590¢; release **false** | Δwallet **0** | **HOLD** | não |
| C4 | stripe-webhook POST | sem sig + `v1=deadbeef` `checkout.session.completed` paid | **400** `missing_signature`; **400** `invalid_signature`; GET **405** | — | **HOLD** | não |
| C5 | CORS OPTIONS/GET/POST | Origin `https://evil.com` + `chrome-extension://abcdef123456` | OPTIONS/GET/POST CPI/tip/refund ACAO `https://fleaber.pt`; webhook OPTIONS `*` | ACAO ≠ Origin hostil; ACAC vazio | **HOLD** | **SIM** |
| D1 | setup_paid_order | pago Stripe TEST real | 200 | order `f10242f4-…` **pago** `pi_3UCjFmH7FWYUN3jh1LTgCp7g` 590¢ | **HOLD** | não |
| D2 | create-connect-account | key `rtdx1738xfer01` 100 depois ∥ 100+500 | 200 + 200 `idempotent` + 200 `idempotent` | **1** `tr_1UCjFrH7FWYUN3jhmg0BHLcd` Δ=−1,00 | **HOLD** | não |

DX-A: 5 · DX-B: 4 · DX-C: 5 · DX-D: 2 · **total 16**.

`classe_nova=SIM`: A1 (session inexistente / oráculo), A2 (settle order_id alheio + qs duplicado), A3 (`web_return_origin` evil), A5 (settle∥settle), B1 (live_id UUID fake), B2 (tip∥end_live), C5 (CORS evil / chrome-extension) → **7** (≥4).  
Races: A5, B2, C3, D2 → **4** (≥3: settle∥settle, tip∥unpublish, refund∥release).

Dinheiro Stripe TEST real: **sim** — 4 PI succeeded 590¢ (`pi_3UCjFS…`, `pi_3UCjFW…`, `pi_3UCjFc…`, `pi_3UCjFm…`); 2 refunds (`re_3UCjFW…`, `re_3UCjFc…`); 1 Transfer (`tr_1UCjFr…`); tip Session unpaid `cs_test_a1xplg…`.

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
10. Session inexistente ecoa oráculo Stripe — NÃO (400 genérico)
11. session_id / order_id alheio credita — NÃO
12. metadata/body amount vs servidor — NÃO (1325 vs 1 / 50)
13. web_return_origin evil no checkoutUrl — NÃO
14. Reuse Session morta duplica captura — NÃO (mesmo sid; dead 400)
15. GET settle 2× paralelo unpaid credita — NÃO (402+402)
16. Tip amount / tip_id / live_id hostil — NÃO (400)
17. Tip∥end_live credita — NÃO (400 broadcasting Δ=0)
18. Tip seller≠owner — NÃO (400)
19. Tip Session unpaid credita — NÃO (pending Δ=0)
20. Buyer refund seller-only aberto — NÃO (403)
21. Seller refund 2× duplica re_ — NÃO (mesmo id)
22. Refund∥release cria dinheiro líquido — NÃO (release false Δ=0)
23. Webhook assinatura forjada / ausente — NÃO (400)
24. CORS ecoa evil.com / chrome-extension — NÃO (fleaber.pt; webhook OPTIONS `*` ≠ echo)
25. Connect mesma key 2 Transfers — NÃO (1 `tr_`)
26. Saturação P0–P2=0 após quota ≥16 + ≥4 classe_nova + ≥3 races + ≥1 dinheiro TEST — SIM

Lacuna honesta: expire nativo Stripe + captura 4242 da Checkout Session **não** (sem `sk_test_` local). A2 checkout B1 **429** após retries — sem sidB; settle sidA↛oidB mesmo assim. Refund/Transfer TEST via Edge **sim**.

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

Nenhum. P0=0 P1=0 P2=0 P3=0.

C5 webhook OPTIONS `Access-Control-Allow-Origin: *` — **não** ecoa `https://evil.com`; Stripe webhook não é superfície browser. **Não contar.**

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| A1 GET unpaid + inexistente | 402 / 400 genérico; `reserva_pendente` |
| A2 sidA + order_id B | 402; oidB `reserva_pendente`; ckB 429 |
| A3 amount + evil return | quote 1325¢; URL sem evil.com |
| A4 reuse + dead | mesmo `cs_`; dead 400; sem expire nativo |
| A5 settle∥settle | 402+402 |
| B1 amount/tip_id/live_id | 400 |
| B2 tip∥end | 400 broadcasting Δ=0 |
| B3 seller≠owner | **400** — **1 residual clássico** |
| B4 unpaid oracle | pending Δ=0 |
| C1 buyer refund | **403** — **não conta** (anti-atrofia) |
| C2 refund 2× | 1 `re_`; idempotent |
| C3 race | refund sim; release false; Δ=0 |
| C4 webhook forge | 400 missing/invalid_signature |
| C5 CORS | fleaber.pt; webhook OPTIONS `*` |
| D1 pago TEST | `pi_3UCjFm…` status pago 590¢ |
| D2 Connect | 1 `tr_`; paralelo idempotent |
| Coptic / charset 400 | não corridos |

Residual clássico na tabela (B3 seller≠owner) = 1/16 ≪ 40%. **ATROFIA: NÃO.**

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| DX1 settle | SIM A1/A2/A3/A4 | não |
| DX2 tip | SIM B1/B3 | não |
| DX3 refund | SIM C1/C2 | não (C1 403) |
| DX4 webhook | SIM C4 | não |
| DX5 CORS | SIM C5 | não |
| DX6 race | SIM A5/B2/C3/D2 | não |
| DX7 Δwallet | SIM B4/C3/D1/D2 | não (sem mint) |

Lentes **7/7** (mín. 5).

--------------------------------------------------
## INVARIANTES
--------------------------------------------------

Settle GET não confia `checkout_return=success` se Session unpaid ou inexistente (402/400 genérico, sem oráculo Stripe). Body amount / `web_return_origin` hostil ignorados (quote 1325¢; URL sem evil.com). GET settle paralelo unpaid não liquida. Tip amount/`tip_id`/`live_id` autoridade servidor (400). Tips só enquanto broadcasting. Seller≠owner 400. Unpaid não credita (pending Δ=0). Refund seller-only 403. Refund Stripe idempotente (1 `re_`). Race refund∥release sem crédito wallet. Webhook recusa forge (400). CORS de CPI/tip/refund não ecoa `evil.com` nem `chrome-extension://` (cai em `https://fleaber.pt`). Connect mesma idempotency_key = 1 Transfer.

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_dx_20260906T1738/_rtdx.dart`
- `tool/redteam_blind_dx_20260906T1738/pass1.dart` + `pass1.json`
- este `FROZEN_REPORT.md` + `FROZEN_REPORT.json`

**NÃO CORRIGIR.** Seller-only refund: **não abriu** (403).

```
AUDITOR: REDTEAM_BLIND_DX_EDGE_POS_DNDS_v1
probes_na_tabela: 16 · classes_novas: 7
VEREDICTO: PASS_CEGO_SATURADO
```

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
