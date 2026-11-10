# Schema — fonte de verdade (pós-auditorias cegas)

**Ambiente de referência auditado:** staging `fxdknzrqjenzqcvnwqqq`  
**Problema:** 100+ ficheiros `supabase/sql/*.sql` aplicados manualmente; poucas migrations versionadas. Reaplicar scripts antigos pode **reabrir** RLS/GRANTs/mint financeiro.

## Regra operacional

1. **Nunca** reaplicar SQL legado listado em «Quarentena» abaixo.
2. Hardening recente vive em ficheiros `sec_fase*_*.sql` / `sec_fase3b_*.sql` / `sec_pos_auditoria_*.sql` — estes são a ordem segura de *delta*.
3. Para um **novo** projecto produção: dump do schema staging endurecido (`pg_dump --schema-only`) + cadeia de migrations a partir desse baseline — **não** reaplicar a pasta `sql/` inteira por ordem alfabética.
4. Qualquer hotfix novo: **um** ficheiro novo + entrada neste documento + (idealmente) cópia em `supabase/migrations/`.
5. **Fase 4** = consolidação completa baseline; **não** sacrificar o estado endurecido actual por “migrations bonitas”.

## Delta hardening (ordem)

| Ordem | Ficheiro | Notas |
|------|----------|--------|
| 1 | `sec_fase1_hardening_batata.sql` | wallet / freeze / payout ledger |
| 2 | `sec_fase2_oversell_batata.sql` | stock atómico |
| 3 | P0-01 / raffle SQL aplicável | trust boundary |
| 4 | `sec_fase3_authz_state_batata.sql` | bag qty, status, grants |
| 5 | `sec_fase3b_hardening_batata.sql` | tips amount, storage, nuke restore |
| 6 | `sec_pos_auditoria_cega_hardening_batata.sql` | **P0 refund mint**, storage counterparty, system_message seller-only |
| 7 | `sec_residuais_pre_fase4_batata.sql` | finalize refund atómico · `amount_paid_cents` · partial cap · counterparty order-scoped |
| 8 | `sec_fase3c_financial_authority_batata.sql` | **P0 wallet mint class** · disputa oferta seller-only · chats/reviews RLS · stock devolvida · qty0 |
| 9 | `sec_pos_reteste_indep_double_credit_batata.sql` | **double-credit class** · clawback seller · remaining≤captura · chat UPDATE · qty≤stock |
| 10 | `sec_pos_reauditoria_dc_batata.sql` | **P2/P3 DC** · estados devolução JWT · ledger append-only (estorno) · Stripe×wallet · advisory lock · qty fail-closed · reviews_public_ratings |
| 11 | `sec_nova_auditoria_cega_2026_08_27_batata.sql` | **P1 seller↔product · chat parties · wallet GRANT revoke authenticated · requested_qty fail-closed · assert grants** |
| 12 | `sec_indep_p1_price_total_refund_bag_batata.sql` | **P1-B price_total JWT freeze · (refund bag = Edge)** |
| 13 | `sec_blind_p1_contract_qty_pago_batata.sql` | **QUARENTENA** — selo original confiava JWT `contract_*` / string proposta (P0). Não reaplicar. |
| 14 | `sec_pos_saturacao_cega_batata.sql` | **SAT 2026-08-27** contract OUTPUT-only · qty canónica · flags internos · payment allowlist · lab REVOKE · reservas · phone · offers · reviews |
| 15 | `sec_sat_rt01_order_state_machine_batata.sql` | **SAT-RT-01** FSM fail-closed: unpaid↛entregue/concluido/review; MB WAY seller→pago preservado |
| 16 | `sec_lote_final_pos_2_auditores_batata.sql` | **LOTE FINAL P1** payment allowlist exacta · reviews role canónica · dispute turn admin só terminal |
| 17 | `sec_c1_ri_e_patch_accept_ri_b_review_role_batata.sql` | **C1 reteste** accept capacity no PATCH/INSERT · buyer review só comprador |
| 18 | `sec_c1_ri_e_converted_capacity_final_batata.sql` | **C1 RI-E class** capacity gate accepted\|converted · advisory lock · status canonical |

Migration espelho 3B: `supabase/migrations/20260826140000_fase3b_hardening_guards.sql`  
Migration blind P1: `supabase/migrations/20260827200000_blind_p1_contract_qty_pago.sql`  
Migration price_total: `supabase/migrations/20260827190000_indep_p1_price_total_freeze.sql`

## Autoridade financeira (refund parcial / disputa / wallet)

| Função | Fonte autoritativa |
|--------|-------------------|
| `batata_order_platform_funds_eur` / `batata_order_wallet_base_eur` | **`sec_fase3c_financial_authority_batata.sql`** — só `amount_paid_cents` |
| `batata_process_partial_refund_dispute` | **3C** (substitui residuais/pos-auditoria nesta função) |
| `batata_refund_buyer_wallet_for_order` / `batata_release_seller_wallet_for_order` | **pos-reauditoria DC (#10)** sobre 3C — remaining/clawback append-only; dispute bloqueia release; `stripe_refund_id` sem mint wallet |
| Regras | JWT não fabrica saldo; `%` disputa só com `seller_offer_set_by=seller`; cliente `%` ignorado |

## Quarentena (NÃO aplicar / redefine removida)

| Ficheiro | Motivo |
|----------|--------|
| `profiles_rls_batata.sql` | **Abort no topo** — `USING (true)` / anon SELECT |
| `live_tips_batata.sql` | Versão antiga settle **sem** `p_paid_amount_cents`; grants desactualizados |
| `sec_025_wallet_party_guard_batata.sql` | mesma redefine pré-gate (quarentena notice); refund/release agora = **3C**; **reaplicar reabre GRANT authenticated em ensure_wallet** |
| `sec_025_partial_refund_nested_ensure_batata.sql` | mesma redefine pré-gate; **GRANT credit_wallet_once** pode voltar a authenticated |
| `sec_025_ensure_wallet_trigger_hotfix_batata.sql` | redefine settle 2-args (bypass F01) |
| `sec_pos_auditoria_cega_hardening_batata.sql` (bloco partial refund) | **superseded** por 3C para a função RPC — não reaplicar só esse bloco por cima do 3C |
| `sec_residuais_pre_fase4_batata.sql` (bloco partial refund) | **superseded** por 3C para a função RPC |
| `sec_blind_p1_contract_qty_pago_batata.sql` | **SAT 2026-08-27** — selo JWT-trust + proposta-string; usar `sec_pos_saturacao_cega_batata.sql` |

Scripts em quarentena devem começar com `raise exception 'QUARANTINED…'` **ou** notice + body removido quando tocados.

## Verificação pós-apply (staging)

```sql
-- Settle tip exige 3 args
select pg_get_function_identity_arguments(p.oid)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.proname='batata_settle_live_tip_from_stripe';
-- Esperado: tip uuid, session text, paid_amount_cents int  (NÃO só 2 args)

-- Refund dispute: comment / body com order_not_paid_for_refund
select pg_get_functiondef(p.oid)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.proname='batata_process_partial_refund_dispute';

-- Wallet primitives: authenticated NÃO deve ter EXECUTE
select public.batata_assert_wallet_rpc_grants();
-- Esperado: {"ok": true, "leaked_to_authenticated": []}
```

## Produção

Não copiar `delete-test-account` / E2E oversell para o projecto live.  
Consolidações restantes: Fase 4 (`AUD1-P0-05`).

### Fase 4 — ponte (2026-09-14)

- Plano: `tool/reports/FASE4_PRODUCTION_PLAN.md`
- Execução: `tool/reports/fase4_execution_2026-09-13/SCOREBOARD.md`
- Denylist apply/deploy: `tool/reports/FASE4_PROD_APPLY_DENYLIST.md`
- Check: `tool/fase4_check_prod_denylist.ps1`
- **Baseline dump completo:** `tool/reports/fase4_baseline_staging_schema.sql` (pg_dump schema-only · 57 tables · 289 functions · 2026-09-14 · sem Docker)
- Cliente app: default staging; prod só com `--dart-define=FLEABER_ENV=production` + URL/anon (rejeita ref staging)
- Builds: `docs/FASE4_BUILD_COMMANDS.md`
- **Próximo bloqueio humano:** P4.3 criar projecto Supabase produção
