# FROZEN_REPORT — REDTEAM_BLIND_Q_POS_NOP_v1

```
AUDITOR: REDTEAM_BLIND_Q_POS_NOP_v1
FROZEN_AT: 2026-09-01T06:16:00+01:00
production_touched: false
fase4: false
corrections_applied: false
staging: fxdknzrqjenzqcvnwqqq
stripe: TEST
lentes_cobertas: [Q1, Q2, Q3, Q4, Q5, Q6, Q7, Q8]
VEREDICTO: FAIL_P0
```

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

Prefixo fixtures: `RTQ-20260901T0700-`.  
Actors: anon · buyer JWT `bfcbeeee-…` · seller JWT `980f4fa1-…` · buyer2 `9009f046-…` / `rtq-20260901t0700-b2` · seller2 `acf14a9b-…`.  
`service_role` só fixture / observação / cleanup.

Evidência bruta: `pass1.json` … `pass6.json` nesta pasta.

--------------------------------------------------
## Missão

Depois dos fechos NOP+O34, ainda há dinheiro, stock, autoridade live, ou estado de disputa que a UI esconde?

**Sim.** O spoof clássico `seller_id` está fechado; a autoridade do saco **não** está — basta `live_id` da própria live + `live_item_id` alheio. O34 segura `devolvida` sem Stripe e `process_partial` a 100%; a composição **parcial &lt;100% + relist + PI capturado** e o **convert sem pagar** no artigo alheio são P0.

--------------------------------------------------
## Findings (ordem de severidade)

### RTQ-Q1-buyer-cross-live-s2-accept — P0 — Q1 / Q7

**Variante nova** (não é `seller_id=<self>` no INSERT da live vítima).

O trigger NOP força `seller_id` = dono de `NEW.live_id`. Não valida que `live_item_id` pertence a essa live.

1. Live A (S1) com item A qty=2 no ar. Live B (S2) no ar.
2. Comprador `POST live_reservation_requests` `live_id=<B>` `live_item_id=<itemA>` `source=fleaber_live` → 201, `seller_id` reescrito para S2.
3. S2 `rpc batata_process_live_reservation_request action=accept` → `ok: true`, `reserved_qty: 1`, `item_qty: 2`.
4. Row: `status=accepted`, `seller_id=S2`, `live_item_id` = artigo de S1.

Reproduzido de novo em pass6 (`8cccbb62-…`, item `e07f495b-…`, `reserved_qty: 1`).

Spoof clássico NOP (S2 INSERT `facebook_manual` na live A com `seller_id` próprio): **403 `reservation_buyer_mismatch`**. O fecho N-P0 no campo `seller_id` segura; a autoridade **não**.

### RTQ-Q8-convert-foreign-item — P0 — Q8 ← Q1

Com a reserva cruzada accepted, S2 `action=convert` → 200, row `status=converted`, **sem PaymentIntent**. Capacidade do artigo de S1 materializada como vendida pelo dono da live B.

Checkout Stripe no mesmo cruzamento: `create-payment-intent` 400 `Missing payment metadata` (não é loot de cartão neste vector; o convert já basta).

### RTQ-Q8-wallet-and-stock-buyer-still-owns — P0 — Q8 / Q4 / Q6

Stripe TEST pago (`setup_paid_order`):

| | |
|--|--|
| order | `2560c21d-a0d5-47e1-a17e-6d9d65596895` |
| PI | `pi_3UAkv3H7FWYUN3jh1kzI1aNq` succeeded, **590 cêntimos** |
| `stripe_refund_id` | **null** |
| status final | **entregue** (comprador ainda “dono”) |
| `stock_units_applied` | 1 |

Disputa aberta + oferta **50%** com `seller_offer_set_by` = vendedor. Race `Future.wait`:

- `rpc batata_process_partial_refund_dispute` → **200 true**
- `PATCH products quantity` (7)
- `PATCH orders status=devolvida` (silencioso — fica entregue)

Ledger:

- buyer wallet **48.71 → 51.66** (+2.95 `reembolso`)
- seller wallet **4.00 → 6.05** (+2.05 `venda` residual)
- plataforma mintou **5.00 €** nas carteiras
- PI Stripe **continua capturado** (sem refund)
- stock produto **1 → 7** (antes a 9 no relist isolado)

O4 bloqueia só `>=100`. Parcial 50% minta comprador **e** vendedor na carteira sem anular o cartão; o vendedor inflaciona qty; a encomenda permanece entregue.

### RTQ-Q6-relist-while-buyer-holds — P1 — Q6

Mesmo produto, antes da race: `PATCH products quantity=9` com order `entregue` e `stock_units_applied=1` → 200, qty=9. Oversell JWT enquanto o comprador detém a unidade.

### RTQ-Q5-seller-skip-to-resolvida — P1 — Q5

`PATCH order_disputes status=resolvida` desde `aberta` → 200, `current_turn=administracao`. Reabrir: 409 `dispute_already_exists_for_order`.  
**Nota anti-atrofia:** isto é o «seller PATCH resolvida clássico». Não é o P0 desta onda; documentado. Comprador fica sem disputa nem reembolso nessa encomenda (`f0994b8a-…`, PI `pi_3UAksvH7FWYUN3jh0vXZwDq5` sem refund).

### RTQ-Q3-proof-url-fragment-evil — P2 — Q3

Variante nova vs wrap `/https://`: `proof_url=https://fleaber.app/ok#https://evil.example/phish` aceite (200). Sem loot directo.

### RTQ-Q3-label-url-fragment-evil — P2 — Q3

Mesmo fragmento em `return_label_url`. Sem loot directo.

--------------------------------------------------
## Fechos NOP+O34 que **seguram** (prova LIVE)

| Vector | Resultado |
|--------|-----------|
| N-P0 spoof `seller_id` na live da vítima | 403 `reservation_buyer_mismatch` |
| JWT UPDATE `lives` (plant `mux_live_id` / `livekit_egress_id` / ended) | 403 `permission denied for table lives` |
| Buyer `stop_egress` / `complete-mux-live` / `token` live alheia | 403 Sem permissão |
| `stop_egress` com `egress_id` alheio no body (live própria) | 403 `egress_id não pertence a esta live` |
| O3 `devolvida` em ciclo `pedido_devolucao` → `devolucao_entregue` sem refund | 403 `order_devolvida_requires_refund` |
| O3 `devolvida` directo desde `entregue` | 200 mas status **não muda** (revert silencioso) |
| O4 `process_partial` 100% com PI capturado | 403 `dispute_full_refund_requires_stripe` |
| PATCH `stripe_refund_id` fake / `payment_method` | 403 `order_money_fields_immutable` |
| JWT `batata_finalize_stripe_order_refund` / `credit_wallet_once` / `stripe_convert` | 403 permission denied |
| Helper self-insert na loja S1 | 403 RLS |
| Buyer2 disputa ordem alheia | 409 (já existe) / RLS |
| `p_processed_by` confused deputy | `not_allowed` |

Q2 (egress/publish por ID leak + plant na row): **saturado** neste perímetro JWT — GRANT na tabela `lives` e authz da Edge.

--------------------------------------------------
## Contabilidade fechada (P0 caixa)

Order `2560c21d-…` · PI `pi_3UAkv3H7FWYUN3jh1kzI1aNq` · 5,90 € capturados.

| Sítio | Esperado pós-disputa 50% | Visto |
|-------|--------------------------|-------|
| Stripe | refund proporcional ou nenhum mint | **sem** `stripe_refund_id` |
| Buyer wallet | 50% = 2,95 **ou** nada se Stripe-first | **+2,95** |
| Seller wallet | sem mint se PI ainda capturado | **+2,05 venda residual** |
| Stock | qty=1 enquanto order entregue | **qty=7** |
| Order status | alinhado ao reembolso | **entregue** |

Race Q4 verbos **≠ N/O**: `process_partial ∥ refund-order` (refund-order 403 `order_refund_blocked_status` após enviado/entregue) e `process_partial ∥ relist ∥ devolvida`.

Oferta 100% + `refund-order` após `entregue`: 403 status gate — o caminho legítimo «refund-order após oferta 100%» **não está disponível** pós-envio; O4 também recusa mint. Impasse (não é loot; o vendedor pode entretanto fechar a disputa com PATCH `resolvida`).

--------------------------------------------------
## Lentes

| # | Coberto | Resultado |
|---|---------|-----------|
| Q1 | sim | **FAIL P0** live_item ∉ live |
| Q2 | sim | saturado (GRANT + Edge) |
| Q3 | sim | O3/O4 hold; fragment P2 |
| Q4 | sim | race parcial+relist = P0 composto |
| Q5 | sim | skip `resolvida` P1 (clássico) |
| Q6 | sim | relist qty P1 |
| Q7 | sim | S2 no saco de S1 via Q1; resto bloqueado |
| Q8 | sim | **FAIL P0** convert + mint∥stock∥PI |

--------------------------------------------------
## Anti-atrofia

Findings de loot/autoridade **novos**: Q1 mismatch, Q8 convert, Q8 mint+relist+PI.  
Lista proibida (dual Session, bag unlist, seguro plain, mux draft, cancel hold, review 5★, Hub paused, spoof `seller_id` exact, abort `enviado` exact, wrap exact, `devolvida` sem stripe exact): **não são ≥50%**.  
`devolvida` sem Stripe: **refutado** (O3). Spoof `seller_id` exact: **refutado**.

--------------------------------------------------
## Tácticas

1. ≥1 Stripe TEST pago + disputa: sim (`setup_paid_order`, vários PI).
2. Contabilidade buyer/seller/stock/PI/`stripe_refund_id`: sim.
3. ≥1 race `Future.wait` com verbos diferentes de N/O: sim.
4. Fronteira REST/RPC/Edge, não Flutter: sim.
5. Seller `enviado` legítimo não partido; `refund-order` pós-100% observado (bloqueado pós-envio).

--------------------------------------------------
## Não feito / limites

- Checkout Stripe no item cruzado: 400 metadata — não se provou captura no Connect de S2.
- Payouts Connect do PI após mint de carteira: não exercido (Δwallet + PI capturado já é risco de plataforma).
- Relatórios K–P **não lidos** antes do congelamento (cegueira).

**VEREDICTO: FAIL_P0** — autoridade de stock live via `live_id`/`live_item_id` mismatch; composição disputa parcial + relist + PI sem refund.
