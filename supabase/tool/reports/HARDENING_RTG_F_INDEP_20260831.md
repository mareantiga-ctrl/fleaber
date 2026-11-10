# Hardening RTG/F/Indep — 20260831

**Staging:** `fxdknzrqjenzqcvnwqqq`  
**SQL:** `supabase/sql/sec_rtg_f_indep_20260831_batata.sql`  
**Migration:** `supabase/migrations/20260831143000_sec_rtg_f_indep_20260831_batata.sql`  
**Hostil:** `tool/sec_rtg_f_indep_20260831_hostile.dart` → **4/4 PASS**

## Escolhas utilizador

| # | Escolha | Implementado |
|---|---------|--------------|
| 1 | A | Hub views sem paused/inactive |
| 2 | A | Shadow unlist só live activa (+ orders buyer) |
| 3 | (agente) A | Pairing/heartbeat/claim só live activa; ended → `live_ended` |
| 4 | A | Draft pairing/reserva accept só `batata_is_admin()` |
| 5 | A | Offer/bundle rejeitam SKU morto (accept incluído) |
| 6 | A | Reviews: policy `reviews_select_parties` (sem marketplace público JWT) |
| 7 | A | Logout JWT — sem alteração |

## P1 regressão D0820 (RTG-G)

- **Causa:** `batata_orders_guard_money_cols` bloqueava carimbo interno de `wallet_release_processed_at` (cancel AFTER + review release).
- **Fix:** respeitar `batata.wallet_internal` / `batata.allow_internal_order_cols`; cancel unpaid não toca flags wallet.

## Anti-regressão

- `sec_d0820_costura_v2_hostile` — revalidar após deploy
- `sec_e0817_product_decisions_a_hostile` — 11/11 PASS (pós-fix)

## Não regressão funcional

- Mão → concluido, seller enviado, refund pago, bundle listed, tip ended — intactos nos hostis E0817 + D0820.
