# Matriz de ataques — auditoria cega G (congelada 2026-08-29T16:55:52Z)

SUPERFÍCIE | ATAQUE | IDENTIDADE | RESULTADO | IMPACTO | SEVERIDADE | EVIDÊNCIA
---|---|---|---|---|---|---
WALLET | PATCH balance=99999 | buyer | HTTP 200 body [] | saldo inalterado 39.81 | — | pass1 fin.wallet.patch.buyer
LEDGER | INSERT +500 | buyer | 403 RLS | sem mint | — | pass1
ORDERS | INSERT pago+amount_paid | buyer | 201 status reserva_pendente paid=null | FSM sanitiza | — | pass1
ORDERS | ghost sale INSERT buyer alheio pago | seller | 403 attribution_denied | — | — | pass1
PRICE/CONTRACT | INSERT price_total=0.50 contract=1 qty=99 | buyer | selo 2500/qty=1 | cliente não manda | — | pass2 5adae88d
CHECKOUT | CPI order «barata» | buyer | amount 2690 | Stripe=contrato | — | pass2
CHECKOUT | CPI após catálogo 25→1 | buyer | 2690 | K holds | — | pass2
CHECKOUT | prize_shipping spoof | buyer | 400 not prize | — | — | pass2
QTY | INSERT qty=99 stock=2 | buyer | 23514 exceeds_stock | — | — | pass2
OFFERS | INSERT accepted 0.50 | buyer | persistiu pending | — | — | pass2
OFFERS | PATCH accept | buyer | 403 offer_accept_not_authorized | — | — | pass2
AUTH | PATCH user_type=admin | buyer | user_type continua comprador | — | — | pass1
EDGE payout | user_id=seller amount=1 | buyer | 400 | — | — | pass1
EDGE refund | order unpaid | buyer | 403 | — | — | pass1
EDGE webhook | sem signature | anon | 400 | — | — | pass1
EDGE mux | create as buyer | buyer | 403 | — | — | pass1
RPC payout_debit | EXECUTE | buyer | 403 | — | — | pass1
RPC apply_tip_once | EXECUTE | buyer | 403 | — | — | pass1
RPC release | MB WAY concluido | buyer | true mas saldo 6.41→6.41 | sem mint | FP | pass3
STOCK | seller MB WAY pago | seller | qty 1→0 is_sold | off-platform | — | pass3 90b06d7c
REVIEWS | review MB WAY | buyer | 201 purchase_verified=false | reputação sem captura | P2 | G-P2-02
ORDER FSM | buyer self-pago | buyer | revertido reserva_pendente | — | — | pass3
PARTIAL REFUND | 100% sem disputa | buyer | dispute_refund_offer_required | — | — | pass3
STOCK | 12 INSERT stock=1 | buyer | 12 pending | não são vendas | P2/race | pass2
STRIPE SESSION | 2 CPI stock=1 | buyer | 2 cs_test @ 590 | captura dupla NÃO COMPROVADA | P2 | G-P2-03
SETTLE | GET unpaid session | buyer | não pago | — | — | pass3
PAYOUT | same idempotency | seller | 1 transfer idempotent | I holds | — | pass3
PAYOUT | two keys | seller | 2 transfers 1¢ | J holds | — | pass3
PRIVACY | notifications_view | anon | 200 rows | PII social | P2 | G-P2-01
PRIVACY | IBAN profiles | buyer | [] | — | — | pass1
PRIVACY | lives.mux_stream_key | buyer | 403 table | — | — | pass2
CHAT | extra SELECT | extra | [] | — | — | pass3c
CHAT | INSERT sender=seller | buyer | 201 sender=buyer | trigger reescreve | — | pass3c id=796
RAFFLES | create_prize_order | buyer | 403 EXECUTE | — | — | pass3d
RAFFLES | INSERT winners | buyer | 403 RLS | — | — | pass3d
RAFFLES | SELECT winners | buyer | 200 + draw_proof | visibilidade | P2 | G-P2-04
STORAGE | list product_photos/seller | buyer | 200 fotos públicas | marketplace | P3 | pass2
PS/OCR | claim 000000 | anon | invalid_or_expired | — | — | pass1
TIPS | send_live_tip wallet | buyer | 403 not_allowed | — | — | pass3
