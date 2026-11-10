# SQL de segurança — lista para correres tu

**Actualizado:** 2026-08-05  
**Pedido:** não assumir que já correste SQL; no fim da ronda de hardening, esta é a lista completa.  
**Projecto staging:** `fxdknzrqjenzqcvnwqqq` (Fleaber eu-west-1)  
**Produção:** só depois de staging + retest QA — **não** misturar.

### Nota honesta

Em sessões anteriores o agente pode ter aplicado alguns destes ficheiros via `npx supabase db query --linked` em staging. **Tu pediste a lista para correres tu** — trata a lista abaixo como fonte de verdade: corre **todos** por ordem no SQL Editor (ou CLI). São **idempotentes** (re-correr é seguro).

### Como correr (SQL Editor)

1. Supabase Dashboard → projecto **staging** `fxdknzrqjenzqcvnwqqq`  
2. SQL → New query  
3. Abre cada ficheiro, cola, Run  
4. Marca ☑️ nesta lista  

### Ordem obrigatória (SQL)

| # | Ficheiro | Fecha | ☑️ |
|---|----------|-------|----|
| 1 | `supabase/sql/sec_low_hardening_batata.sql` | SEC-012, SEC-022, SEC-023 | ☑️ 2026-08-05 |
| 2 | `supabase/sql/sec_001_guard_user_type_batata.sql` | SEC-001 | ☑️ |
| 3 | `supabase/sql/sec_002_guard_order_paid_batata.sql` | SEC-002 fase 1 | ☑️ |
| 4 | `supabase/sql/sec_002b_003_004_hardening_batata.sql` | SEC-002 fase 2, SEC-003 policy, SEC-004 | ☑️ |
| 5 | `supabase/sql/sec_003b_lives_safe_columns_batata.sql` | SEC-003 colunas stream keys | ☑️ |
| 6 | `supabase/sql/sec_008_009_010_020_021_batata.sql` | SEC-008p, 009, 010, 020, 021 | ☑️ |
| 7 | `supabase/sql/sec_014_helper_permissions_guard_batata.sql` | SEC-014 | ☑️ |
| 8 | `supabase/sql/sec_016_017_mux_rate_batata.sql` | SEC-016 (RPC rate) + suporte SEC-017 | ☑️ |
| 9 | `supabase/sql/sec_024_live_room_select_batata.sql` | SEC-024 chat/viewers SELECT | ☑️ |
| 10 | `supabase/sql/sec_027_storage_chat_media_batata.sql` | SEC-027 storage + broadcast authz | ☑️ |
| 11 | `supabase/sql/sec_025_wallet_party_guard_batata.sql` | SEC-025 wallet só participantes | ☑️ |
| 11b | `supabase/sql/sec_025_partial_refund_nested_ensure_batata.sql` | SEC-025 Aceitar reembolso parcial (nest ensure) | ☑️ 2026-08-23 |
| 12 | `supabase/sql/sec_013_claim_live_scoped_batata.sql` | SEC-013 parcial claim FB scoped | ☑️ |
| 14 | `supabase/sql/sec_007_revoke_anon_profiles_batata.sql` | SEC-007 fase 1a — anon sem SELECT profiles | ☑️ |
| 15 | `supabase/sql/sec_anon_rate_limits_rls_batata.sql` | Alerta `rls_disabled_in_public` em `batata_anon_rate_limits` | ☑️ 2026-08-18 |

**Não corras** (legado / falhou a abordagem): `sec_003_revoke_stream_keys_batata.sql` — substituído pelo **#5** (`sec_003b_…`).

**Nota:** o #13 (observe SEC-029) está na secção opcional abaixo — não é obrigatório antes do #14.

### Fora de SQL (edges / deploy) — também teu checklist

| Item | O quê | Como | ☑️ |
|------|--------|------|----|
| SEC-019 | CORS allowlist | Redeploy edges que usam `_shared/cors.ts` | |
| SEC-016 | `resolve-mux-playback` | Redeploy edge `resolve-mux-playback` (após SQL #8) | |
| SEC-017 | `create-mux-live` | Redeploy edge `create-mux-live` | |
| SEC-034 | Tip GET+POST rate-limit | Redeploy `create-live-tip-checkout` (após SQL #8) | |
| SEC-011 | `refund-order` só vendedor (+ rate-limit) | Redeploy `refund-order` | |
| SEC-006p | Observe amount + rate POST 60/h + GET settle 30/h | Redeploy `create-payment-intent` | |
| SEC-028b | Rate-limit Meta callback (não apaga contas) | Redeploy `meta-data-deletion` | |
| SEC-037 | Wallet/Connect rate 20/h fail-open | Redeploy `create-connect-account` | |
| SEC-038 | Staging nuke rate 5/h fail-open | Redeploy `delete-test-account` | |
| SEC-005p | Webhook Stripe aditivo | Deploy `stripe-webhook` + `STRIPE_WEBHOOK_SECRET` + endpoint no Dashboard Stripe (test) | |
| SEC-026 | Secrets locais `.env` | Ops: não commit; rodar chaves se PC partilhado — **sem SQL** | |
| SEC-015 | Drift staging↔prod | Usar **esta lista** como checklist; prod só depois de staging+QA | |
| PII | SEC-007 fase 1b | **Pausa** — restringir SELECT authenticated (FlutterFlow) | |
| SEC-006 full | Rejeitar mismatch / recalcular BD | **Pausa** — depois de ver logs `sec006_amount_observe` | |
| Dual seller cols | SEC-029 | **Pausa** — risco extremo live; opcional: SQL observe #13 | |

### Opcional (só SELECT — zero risco)

| # | Ficheiro | Fecha | ☑️ |
|---|----------|-------|----|
| 13 | `supabase/sql/sec_029_observe_seller_cols_batata.sql` | SEC-029 diagnóstico (não altera nada) | |

### Fase fail-safe — estado

SQL **1–12 + #14** + edges acima = endurecimento sem partir fluxos autenticados.  
SEC-007 fase 1a = só corta **anon** (dump sem login).

Restam com risco real de partir coisas (só com OK explícito teu):

1. **SEC-007 fase 1b** — restringir SELECT authenticated em `profiles`  
2. **SEC-006 full** — rejeitar amounts (só após logs observe)  
3. **SEC-029** — normalizar `seller_id` / `vendedor_id` (depois de correres o #13)

**SEC-005:** código pronto (aditivo); falta ops Stripe (secret + Dashboard + deploy).

**Não avançar 1–3 sem pedido explícito.**

Exemplo deploy (staging):

```bash
npx supabase functions deploy resolve-mux-playback --project-ref fxdknzrqjenzqcvnwqqq
npx supabase functions deploy create-mux-live --project-ref fxdknzrqjenzqcvnwqqq
npx supabase functions deploy create-live-tip-checkout --project-ref fxdknzrqjenzqcvnwqqq
npx supabase functions deploy refund-order --project-ref fxdknzrqjenzqcvnwqqq
npx supabase functions deploy create-payment-intent --project-ref fxdknzrqjenzqcvnwqqq
npx supabase functions deploy meta-data-deletion --project-ref fxdknzrqjenzqcvnwqqq
npx supabase functions deploy create-connect-account --project-ref fxdknzrqjenzqcvnwqqq
npx supabase functions deploy delete-test-account --project-ref fxdknzrqjenzqcvnwqqq
npx supabase functions deploy stripe-webhook --project-ref fxdknzrqjenzqcvnwqqq
# Depois: secrets set STRIPE_WEBHOOK_SECRET=whsec_… e criar endpoint no Dashboard Stripe (test)
```

### Depois de correres

1. Marca ☑️ acima (ou diz no chat «SQL 1–12 OK» + edges se aplicável).  
2. QA futuro: `tool/SECURITY_QA_RETEST.md` + fila em `tool/reports/MANUAL_QA_PENDING.md`  
3. Inventário: `docs/SECURITY_AUDIT_INVENTORY.md`

### Anti-regressão rápida

| Após | Smoke (1 minuto) |
|------|------------------|
| #10 storage | 1 foto chat + 1 perfil/produto |
| #11 wallet | Se tiveres disputa parcial: buyer aceita % como antes; carteira própria abre |
| #12 claim FB | No Hub duma live: «são as minhas reservas» / claim 1× — deve continuar |

### Changelog desta lista

| Data | Alteração |
|------|-----------|
| 2026-08-05 | +SEC-006p observe-only em create-payment-intent (não rejeita) |
| 2026-08-05 | ACEITE SEC-018/035/036; refund-order +rate-limit (mesmo redeploy SEC-011) |
| 2026-08-05 | +#12 SEC-013 parcial (live_id obrigatório + rate-limit; matching igual) |
| 2026-08-05 | +edge SEC-011 refund-order seller-only |
| 2026-08-05 | +#11 SEC-025 party guard (buyer/seller only); SEC-026 ops na checklist |
| 2026-08-05 | +#10 SEC-027 storage + purchase_broadcast; edge tip SEC-034 |
| 2026-08-05 | +#9 SEC-024 live_messages/viewers SELECT scoped |
| 2026-08-05 | +#8 SEC-016/017 Mux rate; edges resolve + create-mux na checklist |
| 2026-08-05 | Lista criada; incluído SEC-014 (#7); clarificado que és tu a correr |
| 2026-08-04 | Itens 1–6 escritos / eventualmente aplicados via CLI em staging |
