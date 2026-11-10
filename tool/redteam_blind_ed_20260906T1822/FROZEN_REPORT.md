# FROZEN_REPORT — RED TEAM CEGO ED · Edge settle / tip / refund / webhook / CORS · POS_DTDY

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
AUDITOR: REDTEAM_BLIND_ED_EDGE_POS_DTDY_v1
FROZEN_AT: 2026-09-06T18:26:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [ED1, ED2, ED3, ED4, ED5, ED6, ED7]
probes_na_tabela: 16
classes_novas: 13
races: 4
VEREDICTO: PASS_CEGO_SATURADO
prefix: RTED-20260906T1822
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (Sessions `cs_test_*` + PI `pi_3UCjs*`/`pi_3UCjt*`/`pi_3UCju*` succeeded + refunds `re_3UCjsw*` / `re_3UCjt2*`) · JWT B1/S1 + B2/S2 fixture · `service_role` só fixture / observação / restore / end_live. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

DX saturado clássicos — este ED não repetiu só buyer 403. Ângulos novos: POST settle qs, `fase2_e2e_settle` JWT, bag `currency=usd`, cs_tip/pi_ no CPI, GET∥POST, Origin `null`, webhook replay 2×, RPC `batata_settle_live_tip_from_stripe` JWT, tip GET settle∥unpublish, tip∥CPI.

Sem `STRIPE_SECRET_KEY` `sk_test_` no env local → sem expire/confirm 4242 das Checkout Sessions de tip. D2 = Session TEST unpaid + RPC buyer 403 + Δwallet 0. D1 pass1 `settle_get_replay` SKIP (`session missing payment_intent`); D1 = pass2 `setup_paid_order` 4242 + GET settle + fase2 JWT.

Buyer refund 403 = anti-atrofia **não conta**. Coptic / charset 400 **não corridos**. Settle unpaid GET 402 clássico **dentro** de A1 POST (não é linha residual). Residual clássico 1/16 (B3 seller≠owner) ≪ 40%. ATROFIA: NÃO.

--------------------------------------------------
## TABELA DE PROVAS (16)
--------------------------------------------------

| probe_id | edge/rpc | payload | HTTP | Stripe/BD Δ | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|----------|---------|------|-------------|------------------|--------------|
| A1 | CPI POST?qs settle + GET fake | POST `checkout_return=success` unpaid + GET unpaid + `cs_inexistente` + sid whitespace | POST **400** metadata; GET **402**; fake/ws **400** genérico | oidA `reserva_pendente` amount_paid null | **HOLD** | **SIM** |
| A2 | CPI GET session alheio | `cs_tip` no CPI + `pi_3UCjsX…` como session_id + `order_id` B | tip→CPI **402**; pi_ **400** | oidB `reserva_pendente`; pago A2 `ebe08ada-…` inalterado `pi_3UCjsXH…` 590¢ | **HOLD** | **SIM** |
| A3 | CPI POST bag_checkout | line_total_cents=1 qty=99 **currency=usd** amount=1 vs SKU 12€ | **400** «only EUR is supported» | price_total 12,00; 0 Session | **HOLD** | **SIM** |
| A4 | GET cancel + reuse + fase2 JWT | GET cancel sidA; 2.º POST mesma order; POST `?fase2_e2e_settle=1` JWT B2 PI alheio→oidB | cancel **402**; reuse **mesmo** `cs_test_a1oiy9…`; fase2 **401** `service_role required` | oidA/oidB `reserva_pendente` | **HOLD** | **SIM** |
| A5 | CPI GET ∥ POST settle | Future.wait GET sidA ∥ POST qs settle | **402** + **400** | `reserva_pendente` | **HOLD** | **SIM** |
| B1 | tip POST + RPC JWT | amount 0/-1/`2,00`/0.5/501/`1e6` + playback + tip_id + live fake + `batata_settle_live_tip_from_stripe` JWT B2 | todos **400**; RPC **403** `42501 permission denied` | 0 Session hostil | **HOLD** | **SIM** |
| B2 | tip GET settle ∥ end/unpublish | Session unpaid já criada; Future.wait GET settle ∥ PATCH ended ∥ hub unpublish | create **200** `cs_test_a1TtIR…`; GET 200 texto unpaid | tip `dd2b3cfc-…` **pending** Δwallet **0** | **HOLD** | **SIM** |
| B3 | tip POST seller≠owner | S2 na live S1; S1 na live S2 | **400** `Tip seller does not own this live` ×2 | — | **HOLD** | não |
| B4 | tip POST ∥ CPI + GET unpaid | Future.wait tip Session ∥ CPI mesma B2; GET tip unpaid | tip **200** `cs_test_a1F2Ia…`; CPI **200** `cs_test_a1OP7I…` | tip pending; CPI `reserva_pendente`; Δ **0** | **HOLD** | **SIM** |
| C1 | stripe-webhook forge + replay | sem sig + 2× mesmo body `checkout.session.completed` paid `v1=deadbeef` Origin null | **400** `missing_signature`; **400** `invalid_signature` ×2; GET **405** | — | **HOLD** | **SIM** |
| C2 | CORS Origin null / evil / ext | Origin `null` + `https://evil.com` + `chrome-extension://` CPI/tip/refund/webhook | OPTIONS/GET ACAO `https://fleaber.pt`; webhook OPTIONS `*` | ACAO ≠ `null` / evil / ext | **HOLD** | **SIM** |
| C3 | refund-order buyer + seller ×2 | JWT comprador `0e4819ba-…`; seller 2× `fae7ade0-…` PI `pi_3UCjsw…` | buyer **403**; seller 200 + 200 `already_refunded` `idempotent` | **1** `re_3UCjswH7FWYUN3jh0SukLkfs`; buyer `pago` Δ0 | **HOLD** | não |
| C4 | refund ∥ release | Future.wait seller refund + release buyer/seller | refund 200 `re_3UCjt2H…`; release **false** | Δwallet **0** PI `pi_3UCjt2H…` | **HOLD** | não |
| D1 | setup_paid_order + settle extra | PI 4242 `2364e83d-…`; GET cs_morta + pi_ como sid; fase2 JWT (pass2; pass1 e2e replay SKIP) | GET **400**; fase2 **401** | **pago** `pi_3UCju8H7FWYUN3jh1zFL83sP` 590¢ refund vazio Δ **0** | **HOLD** | **SIM** |
| D2 | tip Session + RPC buyer + GET | POST tip 2€; RPC settle JWT paid_cents=200; GET unpaid | create **200** `cs_test_a1V0Sk…`; RPC **403** 42501; GET unpaid | tip `e59c8c44-…` **pending** Δwallet **0** | **HOLD** | **SIM** |
| D3 | CPI amount hostil + GET qs | body amount/total/amount_total=1 vs SKU 12€; GET settle `&amount=1` | POST **200**; GET **402** | `server_amount_cents=1325` `amount_total=1325`; `reserva_pendente` | **HOLD** | **SIM** |

ED-A: 5 · ED-B: 4 · ED-C: 4 · ED-D: 3 · **total 16**.

`classe_nova=SIM`: A1 POST qs settle · A2 cs_tip/pi_ no CPI · A3 bag USD · A4 fase2 JWT · A5 GET∥POST · B1 RPC tip JWT + `1e6` · B2 GET settle∥unpublish · B4 tip∥CPI · C1 webhook replay · C2 Origin null · D1 settle pós-pago · D2 RPC no tip real · D3 amount qs settle → **13** (≥4).  
Races: A5, B2, B4, C4 → **4** (≥3: settle∥settle, tip∥unpublish, refund∥release; extra tip∥CPI).

Dinheiro Stripe TEST real: **sim** — PI succeeded 590¢ `pi_3UCjsXH…`, `pi_3UCjssH…`, `pi_3UCjswH…`, `pi_3UCjt2H…`, `pi_3UCju8H…`; refunds `re_3UCjswH…`, `re_3UCjt2H…`; tip Sessions unpaid `cs_test_a1Vhzi…` / `cs_test_a1TtIR…` / `cs_test_a1F2Ia…` / `cs_test_a1V0Sk…`.

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
9. POST settle qs unpaid credita — NÃO (400)
10. Session inexistente / whitespace ecoa oráculo Stripe — NÃO (400 genérico)
11. cs_tip ou pi_ no CPI credita order alheia — NÃO
12. bag line_total / currency USD vs servidor — NÃO (400 só EUR)
13. fase2_e2e_settle JWT comprador — NÃO (401 service_role required)
14. Reuse Session / GET cancel liquida unpaid — NÃO (mesmo sid; 402)
15. GET∥POST settle unpaid credita — NÃO (402+400)
16. Tip amount / tip_id / live_id / `1e6` hostil — NÃO (400)
17. RPC `batata_settle_live_tip_from_stripe` JWT buyer — NÃO (403 42501)
18. Tip GET settle∥end_live credita — NÃO (pending Δ=0)
19. Tip seller≠owner — NÃO (400)
20. Tip∥CPI unpaid credita — NÃO (pending + reserva_pendente Δ=0)
21. Tip Session unpaid / RPC no tip real credita — NÃO (pending Δ=0)
22. Buyer refund seller-only aberto — NÃO (403)
23. Seller refund 2× duplica re_ — NÃO (mesmo id)
24. Refund∥release cria dinheiro líquido — NÃO (release false Δ=0)
25. Webhook forge / replay body — NÃO (400+400)
26. CORS ecoa `null` / evil.com / chrome-extension — NÃO (fleaber.pt; webhook OPTIONS `*` ≠ echo)
27. amount_total Session ≠ body cliente (servidor perde) — NÃO (1325 vs 1)
28. Pago 4242 + settle extra minta/refund — NÃO (pago 590¢ Δ0 fase2 401)
29. Saturação P0–P2=0 após quota ≥16 + ≥4 classe_nova + ≥3 races + ≥1 dinheiro TEST — SIM

Lacuna honesta: expire nativo Stripe + captura 4242 das Checkout Sessions de **tip** não (sem `sk_test_` local). D1 e2e `settle_get_replay` falhou `session missing payment_intent` — caixa D1 fechada no pass2 via PI 4242. GET tip unpaid responde **200** texto (não 402) — copy «ainda não confirmado», sem crédito; **não contar** (igual DX).

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

Nenhum. P0=0 P1=0 P2=0 P3=0.

C2 webhook OPTIONS `Access-Control-Allow-Origin: *` com Origin `null` — **não** ecoa `null`; Stripe webhook não é superfície browser. **Não contar.**

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| A1 POST qs + GET unpaid/inexistente | 400/402/400 genérico; `reserva_pendente` |
| A2 cs_tip + pi_ no CPI | 402/400; oidB pendente |
| A3 bag USD + line_total=1 | 400 só EUR |
| A4 cancel/reuse/fase2 JWT | mesmo `cs_`; 401 service_role |
| A5 GET∥POST | 402+400 |
| B1 amount/tip_id/live/RPC | 400 + RPC 403 42501 |
| B2 GET settle∥end | pending Δ=0 |
| B3 seller≠owner | **400** — **1 residual clássico** |
| B4 tip∥CPI | pending + reserva_pendente Δ=0 |
| C1 webhook forge+replay | 400 missing/invalid_signature ×2 |
| C2 CORS null/evil/ext | fleaber.pt; webhook OPTIONS `*` |
| C3 buyer + seller 2× | **403** (não conta) + 1 `re_` |
| C4 race | refund sim; release false; Δ=0 |
| D1 pago+settle extra | `pi_3UCju8…` pago 590¢ Δ0 |
| D2 tip unpaid+RPC | pending Δ=0; RPC 403 |
| D3 amount body/qs | quote 1325¢; GET 402 |
| Coptic / charset 400 | não corridos |
| e2e settle_get_replay | SKIP pass1 — Session sem PI imediato |

Residual clássico na tabela (B3 seller≠owner) = 1/16 ≪ 40%. C3 buyer 403 é anti-atrofia **não conta** (mesmo probe tem seller 2× obrigatório). **ATROFIA: NÃO.**

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| ED1 settle | SIM A1/A2/A3/A4 | não |
| ED2 tip | SIM B1/B3 | não |
| ED3 webhook | SIM C1 | não |
| ED4 CORS | SIM C2 | não |
| ED5 refund | SIM C3 | não (buyer 403) |
| ED6 race | SIM A5/B2/B4/C4 | não |
| ED7 caixa | SIM D1/D2/D3 | não (sem mint) |

Lentes **7/7** (mín. 5).

--------------------------------------------------
## INVARIANTES
--------------------------------------------------

POST `?checkout_return=success` não liquida Session unpaid (400 metadata; GET 402). Session inexistente / whitespace / `pi_` como `session_id` → 400 genérico, sem oráculo Stripe. `cs_tip` no CPI não paga order alheia. bag `currency=usd` recusado (EUR only). `fase2_e2e_settle` exige Bearer=service_role (401 JWT). GET∥POST settle unpaid sem crédito. Tip amount/`tip_id`/`live_id`/`1e6` autoridade servidor (400). RPC settle tip **não** está em `authenticated` (403 42501). Tips GET settle unpaid não creditam (pending Δ=0) mesmo em paralelo com end_live/unpublish ou CPI. Seller≠owner 400. Refund seller-only 403. Refund Stripe idempotente (1 `re_`). Race refund∥release sem crédito wallet. Webhook recusa forge e replay (400). CORS CPI/tip/refund não ecoa `null` / `evil.com` / `chrome-extension://` (cai em `https://fleaber.pt`). Body amount vs quote: servidor 1325¢. Pago 4242 + GET settle extra não minta nem refund.

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_ed_20260906T1822/_rted.dart`
- `tool/redteam_blind_ed_20260906T1822/pass1.dart` + `pass1.json`
- `tool/redteam_blind_ed_20260906T1822/pass2.dart` + `pass2.json` (D1)
- este `FROZEN_REPORT.md` + `FROZEN_REPORT.json`

**NÃO CORRIGIR.** Seller-only refund: **não abriu** (403).

```
AUDITOR: REDTEAM_BLIND_ED_EDGE_POS_DTDY_v1
probes_na_tabela: 16 · classes_novas: 13
VEREDICTO: PASS_CEGO_SATURADO
```

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
