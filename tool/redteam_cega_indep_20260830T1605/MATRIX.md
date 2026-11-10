# Matriz de ataques (condensada) — RT1605

Fonte completa: `out/pass1.json`, `out/pass23.json`, `out/pass4.json`, `out/pass5.json`, `out/pass6.json`.

| SUPERFÍCIE | ATAQUE | IDENTIDADE | RESULTADO | IMPACTO | SEVERIDADE | EVIDÊNCIA |
|------------|--------|------------|-----------|---------|------------|-----------|
| WALLET | INSERT balance=9999 | buyer | 403 permission denied | sem mint | info | pass1 |
| WALLET | PATCH balance=8888 | buyer | HTTP 200, persist 14.00 (não 8888) | sem mint | info | pass1 |
| LEDGER | INSERT wallet_transactions | buyer | 403 RLS | sem ledger JWT | info | pass1 |
| WALLET | SELECT wallet alheia | buyer→seller | 200 rows=0 | RLS | info | pass1 |
| RPC | batata_credit_wallet_once | anon/buyer/seller | 401/403 | GRANT | info | pass1 |
| RPC | batata_wallet_payout_debit | JWT | 403 | GRANT | info | pass1 |
| ORDERS | INSERT pago+PI+contract 1c+qty 99 | buyer | 201; row `reserva_pendente` 42€ qty 1 PI null | selo | info | order `6c4e2d3c-…` |
| ORDER FSM | PATCH contract/PI/parties | buyer | HTTP 200; row imutável | selo | info | pass1 |
| CHECKOUT | amount=50 item_price=0.01 | buyer | Session; mais tarde `server_amount_cents=3215` em caso 30€ | servidor manda | info | pass4 |
| CHECKOUT | seller JWT + buyer_id alheio | seller | 400 Invalid checkout user | authz | info | pass1 |
| CHECKOUT | anon | anon | 400 Invalid checkout user | authz | info | pass1 |
| CHECKOUT | prize_shipping em não-rifa | buyer | 400 not a raffle prize | authz | info | pass1 |
| CHECKOUT | 8× mesma order | buyer | 1 session, reused | anti-dup | info | pass4 |
| BAG | 2 linhas + amount=50 | buyer | `server_amount_cents=2144` | servidor manda | info | pass6 |
| REFUNDS | buyer refund-order | buyer | 403 Sem permissão | seller-only | info | pass1 |
| REFUNDS | seller sem PI | seller | 422 Sem PaymentIntent | fail-closed | info | pass1 |
| PAYOUT | buyer user_id=seller | buyer | 400 Cannot create another user | authz | info | pass1 |
| PAYOUT | 2 keys 1¢ | seller | 2 transferIds TEST | J ok | info | pass23 |
| PAYOUT | mesma key | seller | mesmo transferId idempotent | I ok | info | pass4 |
| STOCK | 2 INSERT stock=1 | buyer+B2 | 201 + hold_exceeds | D ok | info | pass23 |
| OFFERS | INSERT accepted 0.50€ | buyer | 201 mas status final `pending` | trigger | info | pass4 |
| PRICE | order com offer hostil | buyer | contract 2500, offer_id null | L ok | info | pass23 |
| SHIP | PATCH carrier→hand | buyer | ship permanece carrier | selo | info | pass23 |
| HELPERS | INSERT self na loja alheia | buyer | 403 | RLS | info | pass23 |
| HELPERS | PATCH perms payouts no accept | buyer | perms payouts continuam false | sem escalada | info | pass23 |
| REVIEWS | INSERT order não paga | buyer | 400 review_order_invalid_status | trigger | info | pass1 |
| REVIEWS | seller forja buyer | seller | 403 review_order_not_yours | trigger | info | pass1 |
| DISPUTES | INSERT order pendente | buyer | 403 RLS | info | info | pass1 |
| LIVE | SELECT mux_stream_key | JWT/anon | 403/401 column denied | keys | info | pass1 |
| MUX | create-mux-live buyer | buyer | 403 só vendedor | authz | info | pass4 |
| EDGE | stripe-webhook sem assinatura | anon | 400 missing_signature | verify | info | pass1 |
| EDGE | sec-fase2-e2e-oversell JWT | buyer | 401 Só service_role | authz | info | pass1 |
| EDGE | delete-test-account | JWT | 403 allowlist | staging | info | pass1 |
| STORAGE | B2 list proofs buyer1 | buyer2 | 200 [] | scoped | info | pass4 |
| ORDERS | B2 SELECT | buyer2 | 0 rows | RLS | info | pass23 |
| CHAT | B2 SELECT messages | buyer2 | 0 rows | RLS | info | pass23 |
| STRIPE EVENTS | INSERT refund_created própria order | buyer | **201** | diário mutável | **P2** | pass5 `f12c0cd7-…` |
| STRIPE EVENTS | B2 INSERT order alheia | buyer2 | 403 | RLS | info | pass5 |
| TIPS | send_live_tip_from_wallet 1€ | buyer | tip completed; −1.00 / +0.57 | conservação | info | pass6 |
| PS | B2 create_pairing live alheia | buyer2 | ok:false not_allowed | authz | info | pass6 |
| RPC | admin_list_profiles | anon | 400 Acesso negado | authz | info | pass5 |
| RPC | staging_nuke / credit / payout_debit | JWT | 403/401/denied | GRANT | info | pass1/5 |
