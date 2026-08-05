# Fleaber — Inventário completo de achados de segurança (SEC)

**Data:** 2026-08-04 (actualizado 2026-08-05)  
**Âmbito:** auditoria estática do repositório (SQL, Edge Functions, app, docs).  
**Não inclui:** penetração live em produção; Stripe **live** (só sandbox — limite assinalado).  

**SQL — corre tu:** lista ordenada em [`docs/SECURITY_SQL_APPLY_LIST.md`](SECURITY_SQL_APPLY_LIST.md) (não assumir que o agente já aplicou).

### Changelog fechos (risco Baixo)

| Data | IDs | Artefacto |
|------|-----|-----------|
| 2026-08-04 | SEC-012, SEC-022, SEC-023 | `sec_low_hardening_batata.sql` — **aplicado em staging** `fxdknzrqjenzqcvnwqqq` |
| 2026-08-04 | SEC-019 | `_shared/cors.ts` + edges — **deployed staging** |
| 2026-08-04 | SEC-001 | `sec_001_guard_user_type_batata.sql` — **aplicado staging** · QA `tool/SECURITY_QA_RETEST.md` |
| 2026-08-04 | SEC-002 fase1 | `sec_002_guard_order_paid_batata.sql` — **aplicado staging** · APP-SEC-002 |
| 2026-08-04 | SEC-002b+003+004 | `sec_002b_003_004_hardening_batata.sql` + `sec_003b_lives_safe_columns_batata.sql` — staging |
| 2026-08-04 | SEC-008p+009+010+020+021 | `sec_008_009_010_020_021_batata.sql` — staging (SEC-008 parcial: rate-limit claim; código 6 dígitos residual) |
| 2026-08-05 | SEC-014 | `sec_014_helper_permissions_guard_batata.sql` — **correr tu** (lista `docs/SECURITY_SQL_APPLY_LIST.md`) |
| 2026-08-05 | SEC-016+017 | SQL `sec_016_017_mux_rate_batata.sql` + edges `resolve-mux-playback` / `create-mux-live` — **correr tu** + redeploy |
| 2026-08-05 | SEC-024 | `sec_024_live_room_select_batata.sql` — **correr tu** |
| 2026-08-05 | SEC-027+020r+034 | `sec_027_storage_chat_media_batata.sql` + edge tip GET rate — **correr tu** + redeploy tip |
| 2026-08-05 | SEC-025+026 | `sec_025_wallet_party_guard_batata.sql` — **correr tu**; SEC-026 ACEITE ops |
| 2026-08-05 | SEC-011 | edge `refund-order` seller-only — **redeploy tu** |
| 2026-08-05 | SEC-013p+015p | `sec_013_claim_live_scoped_batata.sql` — **correr tu**; SEC-015 = esta lista |
| 2026-08-05 | SEC-018/035/036 + refund rate | ACEITE residual docs; `refund-order` +rate-limit fail-open |
| 2026-08-05 | SEC-006p | `create-payment-intent` observe + rate 60/h fail-open — **redeploy tu** |
| 2026-08-05 | SEC-034b/028b/029o | tip POST rate 30/h; meta-del rate 20/h; SQL observe dual seller (só SELECT) |
| 2026-08-05 | SEC-007a | `sec_007_revoke_anon_profiles_batata.sql` — **correr tu** (anon off; auth intacto) |
| 2026-08-05 | SEC-018b | `create-payment-intent` GET settle rate 30/h fail-open — **redeploy tu** |
| 2026-08-05 | SEC-038 | `delete-test-account` rate 5/h fail-open (só staging) — **redeploy tu** |
| 2026-08-05 | SEC-005p | edge `stripe-webhook` aditivo (reusa GET settle) — **deploy + whsec + Dashboard** |

**Lista completa SQL para correres tu:** `docs/SECURITY_SQL_APPLY_LIST.md` (não assumir CLI).

**Regra:** alterações de código só nos itens de risco Baixo pedidos; críticos/altos ficam para lotes seguintes.  
**Pausa recomendada:** SEC-007 **fase 1b** (auth SELECT), SEC-006 full, SEC-029 — **só com OK explícito**.  
SEC-005 parcial = webhook aditivo escrito; falta deploy + secret Stripe (tu).

**Fontes cruzadas:**
- Auditoria Ago 2026 (edge + SQL/RLS/RPC)
- `docs/auditoria-fleaber-escala.md` (Mai 2026) — IDs C1–C12 onde aplicável
- Código em `supabase/sql/`, `supabase/functions/`, `lib/`

**Como usar este ficheiro**
1. Ler por **gravidade** (secções abaixo).
2. Em cada item: **risco de regressão do fix** = probabilidade de partir funcionalidade já PASS se aplicarem o remendo à pressa.
3. Escolher lotes pequenos (ex. 1–2 críticos) → testar → próximo lote.
4. Marcar estado: `ABERTO` | `EM CURSO` | `FECHADO` | `ACEITE (risco residual)`.

**Legenda — risco de alterar funcionalidades ao fixar**

| Nível | Significado |
|-------|-------------|
| **Baixo** | Fix localizado; pouco impacto UX se SQL/edge correcto; reteste curto |
| **Médio** | Pode partir 1–2 fluxos (perfil, claim, admin UI); reteste guiado obrigatório |
| **Alto** | Toca pagamentos, encomendas, live, reservas; exige bateria QA antes/depois |
| **Muito alto** | Muda o modelo de confiança (webhook, quem escreve «pago»); risco de lives/checkout a falhar se mal feito |

**Legenda — gravidade do buraco (antes do fix)**

| Gravidade | Critério |
|-----------|----------|
| **Crítica** | Fraude dinheiro/stock/admin, ou roubo de transmissão, com conta normal ou anon |
| **Alta** | PII em massa, abuso grave sem ser «esvaziar wallet» imediato, ou pagamento frágil |
| **Média** | Abuso, DoS, enumeração, compliance, custo, ou agrava outros buracos |
| **Baixa** | Endurecimento, higiene, ou risco só com condições raras |

---

## Índice rápido (todos os IDs)

| ID | Gravidade | Título curto | Risco do fix | Estado |
|----|-----------|--------------|--------------|--------|
| SEC-001 | Crítica | Auto-promoção a admin (`user_type`) | Médio | FECHADO (staging) — retest APP-SEC-001 |
| SEC-002 | Crítica | Comprador/vendedor UPDATE livre em `orders` (falso pago) | **Alto** | FECHADO fase1+2 (staging) — APP-SEC-002 |
| SEC-003 | Crítica | Stream keys legíveis em `lives` | Médio | FECHADO (staging) — APP-SEC-003 |
| SEC-004 | Crítica | `batata_live_reservation_stripe_convert` sem dono | **Alto** | FECHADO (staging) — APP-SEC-004 |
| SEC-005 | Crítica | Sem webhook Stripe (settle só no cliente/return URL) | **Muito alto** | FECHADO parcial — edge `stripe-webhook` · redeploy + whsec |
| SEC-006 | Alta | Checkout: amount confiado no cliente | **Alto** | FECHADO parcial — observe + rate 60/h · redeploy |
| SEC-007 | Alta | `profiles` SELECT aberto (PII / IBAN / MB WAY) | **Alto** | FECHADO parcial — anon off · lista #14 |
| SEC-008 | Alta | PS pairing 6 dígitos → device token | Médio | FECHADO parcial (staging) — rate-limit; 6 dígitos residual |
| SEC-009 | Alta | `batata_create_raffle_prize_order` sem auth | Médio | FECHADO (staging) — APP-SEC-009 |
| SEC-010 | Alta | `batata_award_live_raffle_tickets` sem auth | Médio | FECHADO (staging) — APP-SEC-010 |
| SEC-011 | Alta | Buyer pode iniciar `refund-order` | **Alto** | FECHADO (código edge) — APP-SEC-011 · redeploy |
| SEC-012 | Alta | `batata_find_user_id_by_email` (enumeração) | Baixo | FECHADO (staging) |
| SEC-013 | Alta | Claim reservas FB por nome (`batata_claim_external_reservations`) | **Alto** | FECHADO parcial — APP-SEC-013 · lista #12 |
| SEC-014 | Alta | Helper aceita convite e pode alargar `permissions` | Médio | FECHADO (SQL pronto) — APP-SEC-014 · correr lista |
| SEC-015 | Alta | Deploy SQL ad-hoc / drift staging↔prod | **Alto** (processo) | FECHADO parcial — lista `SECURITY_SQL_APPLY_LIST.md` |
| SEC-016 | Média | `resolve-mux-playback` público + escrita em `lives` | Médio | FECHADO (código+SQL) — APP-SEC-016 · redeploy |
| SEC-017 | Média | `create-mux-live` — abuso de custo (qualquer auth) | Médio | FECHADO (código) — APP-SEC-017 · redeploy |
| SEC-018 | Média | Edge pagamentos `verify_jwt=false` (mitigado parcialmente) | Médio | ACEITE + rate GET settle · redeploy |
| SEC-019 | Média | CORS `*` em edges sensíveis | Baixo | FECHADO (staging) |
| SEC-020 | Média | `batata_live_system_message` / broadcast rifa em qualquer live | Médio | FECHADO (staging) — APP-SEC-020 · +broadcast authz no #10 |
| SEC-021 | Média | `batata_recompact_reservation_queue` / recompute sem ownership | Médio | FECHADO (staging) — APP-SEC-021 |
| SEC-022 | Média | `app_logs` INSERT aberto (anon) | Baixo | FECHADO (staging) |
| SEC-023 | Média | `live_vendor_studio_logs` sem FK / spoof | Baixo | FECHADO (staging) |
| SEC-024 | Média | Chat/viewers live SELECT demasiado aberto | Médio | FECHADO (SQL pronto) — APP-SEC-024 · correr lista |
| SEC-025 | Média | `batata_process_partial_refund_dispute` — auth/grants pouco claros | **Alto** | FECHADO (SQL pronto) — APP-SEC-025 · correr lista |
| SEC-026 | Média | Secrets staging em disco local (`tool/*.env`) | Baixo (ops) | ACEITE (ops) — sem SQL |
| SEC-027 | Média | Storage (`chat_media`) policies ausentes no repo | Médio | FECHADO (SQL pronto) — APP-SEC-027 · correr lista |
| SEC-028 | Média | Meta data-deletion só regista (compliance) | Médio | ACEITE residual + rate POST |
| SEC-029 | Média | Dual `seller_id` / `vendedor_id` (reservas invisíveis / auth bugs) | **Alto** | ABERTO — pausado · observe #13 |
| SEC-030 | Média | Race em `queue_position` (integridade fila) | Médio | ACEITE parcial |
| SEC-031 | Média | Estados órfãos sem cron (pending/expired) | Médio | ACEITE deferred |
| SEC-032 | Baixa | Anon key hardcoded no Flutter (esperado) | Baixo | ACEITE |
| SEC-033 | Baixa | Admin UI só esconde ecrã (segurança = RLS) | Baixo | ACEITE* |
| SEC-034 | Baixa | Tip checkout GET settle sem JWT de user | Médio | FECHADO parcial — rate GET+POST · redeploy |
| SEC-035 | Baixa | Realtime tables não publicadas (força polling — superfície ops) | Médio | ACEITE — Hub anon usa poll de propósito |
| SEC-036 | Baixa | Tabelas core `orders`/`profiles` schema fora do repo | **Alto** (docs) | ACEITE parcial — inventário + `SECURITY_SQL_APPLY_LIST.md` |
| SEC-037 | Baixa | `create-connect-account` sem rate-limit (wallet/Connect spam) | Baixo | FECHADO (código) — rate 20/h fail-open · redeploy |
| SEC-038 | Baixa | `delete-test-account` sem rate-limit (staging nuke) | Baixo | FECHADO (código) — rate 5/h fail-open · redeploy |

\*SEC-033 fica aceite **só depois** de SEC-001 fechado.

---

# Crítica

### SEC-001 — Auto-promoção a admin via `profiles.user_type`
- **Estado:** FECHADO (SQL `sec_001_guard_user_type_batata.sql` — staging) · **Retest:** `APP-SEC-001` em `tool/SECURITY_QA_RETEST.md`
- **Evidência:** `supabase/sql/profiles_rls_batata.sql` (`profiles_update_own` sem restrição de colunas); `admin_batata.sql` (`batata_is_admin` lê `user_type`)  
- **Exploit:** conta normal → `UPDATE` próprio perfil → `user_type=admin` → disputas/wallets/admin RLS  
- **Fix aplicado:** trigger BEFORE INSERT/UPDATE OF `user_type` — JWT `authenticated` não pode gravar valores admin*; service_role / SQL Editor sem uid de end-user podem  
- **Risco do fix:** **Médio** — registo/perfil com `vendedor` continua; promover admin só ops  
- **Stripe:** independente  

### SEC-002 — UPDATE amplo em `orders` (falso pago / wallet / stock)
- **Estado:** FECHADO **fase 1+2** (staging) · **Retest:** `APP-SEC-002`  
- **Fix aplicado:**
  - Fase1: buyer ≠ `pago` excepto `premio_rifa`→`pago`
  - Fase2: buyer ≠ `enviado` / `devolvida`; `concluido` só a partir de estados pós-pagamento/disputa (`enviado`,`pago`,`pedido_devolucao`,…)
- **Preservado:** V confirma MB WAY; V marca enviado; V aceita disputa→devolvida; B receção; B fecho disputa; B prémio mão  
- **Risco do fix:** Médio (retest chat encomendas / disputas)  

### SEC-003 — `mux_stream_key` / `stream_key` legíveis em `lives`
- **Estado:** FECHADO (staging) · **Retest:** `APP-SEC-003`  
- **Evidência staging:** política FlutterFlow `Lives ativas são visíveis por todos` com `using (true)`  
- **Fix aplicado:** drop política aberta; `lives_select_feed_or_owner`; SELECT autenticado **sem** colunas `stream_key` / `mux_stream_key` / `mux_live_id` / `livekit_egress_id` (grant coluna a coluna)  
- **Preservado:** Home feed, playback IDs, seller obtém key via `create-mux-live`  
- **Risco do fix:** Médio — retest criar/terminar directo + Home Diretos  

### SEC-004 — `batata_live_reservation_stripe_convert` sem ownership  
- **Estado:** FECHADO (staging) · **Retest:** `APP-SEC-004` (smoke checkout live se houver)  
- **Fix aplicado:** `REVOKE` execute a `authenticated`; só `service_role` · app já usa `batata_live_reconcile_stripe_order` (com ownership)  
- **Risco do fix:** Baixo–Médio — se algum cliente chamava `convert` directo, deixa de funcionar (não há callers Dart)  

### SEC-005 — Sem webhook Stripe; settle via return URL / app resume  
- **Estado:** FECHADO parcial (BATATA aditivo) · **Aplicar:** deploy `stripe-webhook` + secret + endpoint Stripe  
- **Evidência:** novo `supabase/functions/stripe-webhook/index.ts`; GET return URL **mantém-se**  
- **Exploit / falha mitigada:** pagamento real sem return URL (browser fechado) → webhook chama o mesmo settle  
- **Fix aplicado:**  
  1. Verifica assinatura `STRIPE_WEBHOOK_SECRET`  
  2. Só `checkout.session.completed` / `async_payment_succeeded` com `payment_status=paid`  
  3. Reutiliza GET de `create-payment-intent` ou `create-live-tip-checkout` (sem duplicar lógica)  
  4. Log em `stripe_checkout_events` (`webhook.checkout.session.settled`)  
- **NÃO alterado:** fluxo UX do return URL / deep link; stock trigger continua idempotente em re-settle  
- **Ops (tu):**  
  1. `npx supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_… --project-ref fxdknzrqjenzqcvnwqqq`  
  2. Deploy edge `stripe-webhook`  
  3. Stripe Dashboard (test) → Webhook → URL `…/functions/v1/stripe-webhook` → events acima  
- **Risco do fix:** **Baixo–médio** (aditivo); QA sandbox obrigatória antes de money real  
- **Stripe:** sandbox primeiro  

---

# Alta

### SEC-006 — Checkout: `amount` / linhas vindas do cliente  
- **Estado:** FECHADO parcial (observe + rate-limit, BATATA) · **Aplicar:** redeploy `create-payment-intent`  
- **Evidência:** `create-payment-intent/index.ts`  
- **Exploit:** sessão Stripe barata vs encomenda cara / spam de sessões  
- **Fix parcial:**  
  1. compara `amount` com `orders.price_total`; se |delta| > 2 € → log + evento — **não bloqueia** (portes/taxas/descontos)  
  2. rate-limit POST **60/h** por buyer (`create_payment_intent:…`) — fail-open se RPC falhar  
- **Residual:** rejeitar mismatch / recalcular BD = SEC-006 full (só após logs `sec006_amount_observe`)  
- **Risco do fix parcial:** **Muito baixo** (telemetria + limite absurdo)  
- **Stripe:** impacto real do exploit só com keys live  

### SEC-007 — `profiles` SELECT aberto (anon + auth)  
- **Estado:** FECHADO parcial (fase 1a) · **Aplicar:** lista #14 `sec_007_revoke_anon_profiles_batata.sql` · **Já em escala:** C3  
- **Evidência:** `profiles_rls_batata.sql` (`profiles_select_anon` USING true)  
- **Exploit:** dump PII sem login (anon key) — IBAN, MB WAY, moradas, telefone  
- **Fix fase 1a:** drop `profiles_select_anon` + `REVOKE SELECT` de `anon` — **authenticated intacto**  
- **Preservado (BATATA):** app logada; Hub via `hub_profiles_public`; MB WAY/IBAN entre buyer/seller autenticados  
- **Residual (fase 1b — pausa):** autenticado ainda lê todos os perfis (risco FlutterFlow alto)  
- **Risco do fix 1a:** **Baixo** — Hub/web anónimos devem usar views; app usa JWT  
- **Stripe:** N/A · **GDPR**  
- **QA:** Hub público OK; login + perfil + MB WAY no checkout OK; com anon key `select * from profiles` deve falhar/vazio  

### SEC-008 — PS pairing: código 6 dígitos → token em claro na resposta  
- **Estado:** FECHADO parcial (staging) — `sec_008_009_010_020_021_batata.sql` · **Retest:** `APP-SEC-008`  
- **Evidência:** `ps-pairing-claim`, `batata_ps_claim_pairing`  
- **Exploit:** brute-force / shoulder → token → reservas FB falsas  
- **Fix aplicado:** rate-limit 40 claims/hora/device (`batata_anon_rate_limits`); TTL 10 min já existia; one-time claim  
- **Residual:** código ainda 6 dígitos (mudar comprimento parte UX PS Reader — lote futuro)  
- **Risco do fix:** **Médio** — emparelhamento seller mais chato se spam; retestar PS no PC  
- **Stripe:** N/A  

### SEC-009 — `batata_create_raffle_prize_order` sem authz  
- **Estado:** FECHADO (staging) · **Retest:** `APP-SEC-009`  
- **Evidência:** `live_raffle_premio_order_batata.sql`  
- **Exploit:** criar encomendas prémio / queimar stock  
- **Fix aplicado:** `REVOKE` authenticated/anon; só `service_role` (+ chamadas aninhadas DEFINER no draw)  
- **Risco do fix:** **Médio** — fluxo prémio rifa via draw interno  
- **Stripe:** parcial (prémio pode ter portes)  

### SEC-010 — `batata_award_live_raffle_tickets` sem authz  
- **Estado:** FECHADO (staging) · **Retest:** `APP-SEC-010`  
- **Evidência:** `live_raffles_batata.sql`  
- **Exploit:** mint tickets / adulterar sorteio  
- **Fix aplicado:** `REVOKE` authenticated/anon; só `service_role` (+ join/share/tip DEFINER)  
- **Risco do fix:** **Médio** — tips/share/follow via RPCs públicas de produto  
- **Stripe:** N/A  

### SEC-011 — `refund-order` permite buyer  
- **Estado:** FECHADO (código edge) · **Retest:** `APP-SEC-011` · **Aplicar:** redeploy `refund-order`  
- **Evidência:** `supabase/functions/refund-order/index.ts`  
- **Exploit:** reembolso Stripe sem disputa/seller  
- **Fix aplicado:** só `user.id === seller_id` (app já só chama via `applyOrderCancelAndRelist` com check de seller — BATATA verificado nos callers)  
- **Risco do fix:** **Alto** mitigado — **zero** UI buyer a pedir refund-order no código  
- **Stripe:** sandbox limita €  

### SEC-012 — `batata_find_user_id_by_email`
- **Estado:** FECHADO (código SQL em `sec_low_hardening_batata.sql` — aplicar no Supabase)
- **Evidência:** `supabase/sql/seller_helpers_staff_batata.sql`  
- **Exploit:** saber se email existe + UUID  
- **Fix aplicado:** auth obrigatório + máx. 30 lookups/hora/user (`batata_rpc_rate_limits`); email inválido → null  
- **Risco do fix:** **Baixo** — convites helper; se rate_limited, esperar 1h ou novo user  
- **Stripe:** N/A  

### SEC-013 — Claim reservas externas por display name  
- **Estado:** FECHADO parcial — `sec_013_claim_live_scoped_batata.sql` · **Retest:** `APP-SEC-013` · lista #12  
- **Evidência:** `ps_claim_reservations_batata.sql`  
- **Exploit:** nome igual ao FB → roubar reservas órfãs  
- **Fix aplicado (BATATA):** `p_live_id` obrigatório (Hub já envia); rate-limit 20/h; **matching por nome inalterado**  
- **Residual:** sem prova FB/código — nome coincidente na mesma live ainda claima  
- **Risco do fix:** **Baixo** neste parcial (app já passa live_id)  
- **Stripe:** N/A  

### SEC-014 — Helper pending: UPDATE pode alargar `permissions`  
- **Estado:** FECHADO (SQL pronto) — `sec_014_helper_permissions_guard_batata.sql` · **Retest:** `APP-SEC-014` · **Aplicar:** `docs/SECURITY_SQL_APPLY_LIST.md` #7  
- **Evidência:** `seller_helpers_staff_batata.sql` (WITH CHECK frouxo)  
- **Exploit:** helper dá a si próprio permissões perigosas  
- **Fix aplicado:** trigger `batata_seller_helpers_guard_helper_update` — helper não muda `permissions`/identidade; só accepted/rejected; seller mantém controlo  
- **Risco do fix:** **Médio** — aceitar convite / editar equipa  
- **Stripe:** N/A  

### SEC-015 — Deploy SQL ad-hoc (49 scripts, sem migrations rígidas)  
- **Estado:** FECHADO parcial (processo) — checklist `docs/SECURITY_SQL_APPLY_LIST.md`  
- **Evidência:** docs escala; pasta `supabase/sql/`  
- **Exploit / risco:** staging «parece» patchado e prod não (ou o contrário)  
- **Fix parcial:** lista ordenada idempotente + ordem SQL/edges; prod só após staging+QA  
- **Residual:** migrations versionadas rígidas (Supabase migrate) — futuro  
- **Risco do fix:** **Alto** se migrarem à pressa — usar a lista  
- **Stripe:** N/A  

---

# Média

### SEC-016 — `resolve-mux-playback` sem auth útil + escreve `lives`  
- **Estado:** FECHADO (código + SQL #8) · **Retest:** `APP-SEC-016` · **Aplicar:** SQL lista + redeploy edge  
- **Evidência:** `resolve-mux-playback/index.ts`  
- **Exploit:** spam Mux API (custo); forçar VOD ids  
- **Fix aplicado:** rate-limit 30/h/live via `batata_anon_rate_check`; update VOD só se `mux_vod_playback_id` ainda null (não sobrescreve); Hub anon + cache cedo inalterados  
- **Risco do fix:** **Médio** — gravados / Hub «gravação a preparar»  
- **Stripe:** N/A  

### SEC-017 — Qualquer auth cria Mux live (`create-mux-live`)  
- **Estado:** FECHADO (código edge) · **Retest:** `APP-SEC-017` · **Aplicar:** redeploy `create-mux-live`  
- **Evidência:** `create-mux-live/index.ts`  
- **Exploit:** factura Mux  
- **Fix aplicado:** quota **10** creates Mux / 24h / user (conta `lives` com `mux_live_id`); auth Bearer já existia; **não** exige seller «verificado» (BATATA onboarding)  
- **Risco do fix:** **Médio** — registo → primeiro directo; testes Maestro se >10/dia  
- **Stripe:** N/A  

### SEC-018 — Edges pagamento com `verify_jwt=false`  
- **Estado:** ACEITE residual + rate GET settle · **Aplicar:** redeploy `create-payment-intent`  
- **Evidência:** `config.toml` + `getUser()` interno  
- **Exploit:** regressão futura se alguém remover `getUser`; martelar return URL  
- **Mitigação actual:** POST exige Bearer + `getUser()`; GET sem JWT só no return URL Stripe (necessário)  
- **Fix adicional (BATATA):** GET settle rate-limit **30/h** por `session_id` — fail-open; **não** muda marcar pago  
- **Não fazer agora:** `verify_jwt=true` no GET return — parte deep link / browser  
- **Residual:** webhook (SEC-005) + não remover getUser  
- **Risco do fix adicional:** **Muito baixo** — return URL normal 1–3 hits  
- **Stripe:** ligado a SEC-005  

### SEC-019 — CORS `Access-Control-Allow-Origin: *`  
- **Estado:** FECHADO (código — `supabase/functions/_shared/cors.ts` + edges; **redeploy** edges)
- **Evidência:** headers nas edges  
- **Exploit:** browser + sessão roubada chama edges de qualquer origem  
- **Fix aplicado:** allowlist fleaber.pt / localhost / chrome-extension; sem Origin (app nativa) → `*`  
- **Risco do fix:** **Baixo** — Hub web / localhost / PS extension  
- **Stripe:** N/A  

### SEC-020 — Mensagens sistema / rifa injectáveis em qualquer live  
- **Estado:** FECHADO (staging) · **Retest:** `APP-SEC-020`  
- **Evidência:** `live_messages_system_batata.sql`, raffle broadcast grants  
- **Exploit:** spam / phishing no chat da live  
- **Fix aplicado:** rate-limit 60/h + body ≤400 em `batata_live_system_message`; `batata_live_raffle_social_broadcast` só service_role; **+** `batata_live_purchase_broadcast` só buyer/seller/staff (`sec_027_…`)  
- **Nota BATATA:** não restringimos system message a seller — comprador precisa (saco/FOMO)  
- **Risco do fix:** **Médio** — FOMO / anúncios saco / «comprou» no chat  
- **Stripe:** N/A  

### SEC-021 — Recompact / recompute status sem ownership  
- **Estado:** FECHADO (staging) · **Retest:** `APP-SEC-021`  
- **Evidência:** `live_ops_hotfix_batata.sql`  
- **Exploit:** DoS / flicker stock  
- **Fix aplicado:** `batata_can_ops_live_item` — seller/staff `can_manage_reservations` / participante da fila / service_role  
- **Risco do fix:** **Médio** — studio / saco / sync após venda  
- **Stripe:** N/A  

### SEC-022 — `app_logs` INSERT anon  
- **Estado:** FECHADO (SQL em `sec_low_hardening_batata.sql` — aplicar no Supabase)
- **Evidência:** `app_logs_batata.sql` · **Já em escala:** C10  
- **Exploit:** spam BD  
- **Fix aplicado:** revogado INSERT anon; só authenticated  
- **Risco do fix:** **Baixo** — logs pré-login deixam de ir para BD  
- **Stripe:** N/A  

### SEC-023 — `live_vendor_studio_logs` spoofável  
- **Estado:** FECHADO (SQL em `sec_low_hardening_batata.sql` — aplicar no Supabase)
- **Evidência:** `live_vendor_studio_logs_batata.sql` · **Já em escala:** C9  
- **Exploit:** lixo de auditoria com seller_id alheio  
- **Fix aplicado:** INSERT exige `actor_id = auth.uid()` e seller próprio ou helper aceite (ou seller_id null)  
- **Risco do fix:** **Baixo**  
- **Stripe:** N/A  

### SEC-024 — `live_messages` / `live_viewers` SELECT aberto  
- **Estado:** FECHADO (SQL pronto) — `sec_024_live_room_select_batata.sql` · **Retest:** `APP-SEC-024` · **Aplicar:** lista #9  
- **Evidência:** `live_room_batata.sql` (`using true`)  
- **Exploit:** enumerar chat/viewers de outras lives  
- **Fix aplicado:** SELECT messages só se live `live`/`ended`/`is_active` ou seller/staff `can_manage_chat`; viewers só próprio row ou seller/staff dashboard; anon continua só via `hub_live_messages_public`; ping viewers via RPC DEFINER  
- **Risco do fix:** **Médio** — player chat / FOMO viewers / resultados de sessão seller  
- **Stripe:** N/A  

### SEC-025 — `batata_process_partial_refund_dispute` auth pouco claro  
- **Estado:** FECHADO (SQL pronto) — `sec_025_wallet_party_guard_batata.sql` · **Retest:** `APP-SEC-025` · lista #11  
- **Evidência:** `wallets_batata.sql`  
- **Exploit:** se EXECUTE estiver em authenticated → créditos wallet arbitrários  
- **Fix aplicado (BATATA):** só `buyer_id` / `seller_id` / admin; % preferido da disputa; `credit_wallet_once` + commission só `service_role`; `ensure_wallet` só própria conta; `refund_buyer` só participantes  
- **Risco do fix:** **Alto** mitigado — fluxo «aceitar reembolso parcial» no chat **preservado**  
- **Stripe:** ligado a dinheiro  

### SEC-026 — Ficheiros `.env` staging locais (gitignored)  
- **Estado:** ACEITE (ops) — sem alteração de app  
- **Evidência:** padrão `tool/*.env`, `.gitignore`  
- **Exploit:** malware no PC / backup → service role  
- **Fix:** secret manager; rotação se alguma vez partilhado; não commit  
- **Risco do fix:** **Baixo** (ops) — não muda app  
- **Stripe:** inclui chaves test  

### SEC-027 — Políticas Storage não versionadas no repo  
- **Estado:** FECHADO (SQL pronto) — `sec_027_storage_chat_media_batata.sql` · **Retest:** `APP-SEC-027` · **Aplicar:** lista #10  
- **Evidência:** escala A1.8  
- **Exploit:** upload/leitura media indevida (se bucket frouxo no dashboard)  
- **Fix aplicado:** bucket `chat_media` público (URLs); SELECT público; INSERT só `authenticated`; UPDATE/DELETE só se path contém `auth.uid()`; **sem** exigir uid em `chat_uploads/` / `order_proofs/` (BATATA)  
- **Risco do fix:** **Médio** — fotos chat / produtos / perfil / comprovativos  
- **Stripe:** N/A  

### SEC-028 — Meta data-deletion incompleto  
- **Estado:** ACEITE residual + rate-limit POST (BATATA — sem apagar contas) · **Aplicar:** redeploy `meta-data-deletion`  
- **Evidência:** `meta-data-deletion/index.ts`  
- **Nota:** callback Meta App Review = confirma pedido + URL de estado; **purge RGPD completo** = projecto separado  
- **Fix aplicado:** após HMAC válido, rate-limit **20/h** por `facebook_user_id` (fail-open) — não muda resposta feliz  
- **Risco do fix completo (purge):** **Alto** — contas FB / dados encomendas  
- **Stripe:** N/A  

### SEC-029 — Dual `seller_id` / `vendedor_id`  
- **Estado:** ABERTO — **pausado** (risco extremo de regressão live) · observe opcional  
- **Evidência:** docs escala A1.1  
- **Exploit:** checks que leem só uma coluna → bypass ou lives órfãs  
- **Diagnóstico (zero risco):** `sec_029_observe_seller_cols_batata.sql` — só SELECT  
- **Fix (só com OK teu + plano de backfill):** normalizar + coalesce em todos os RPCs  
- **Risco do fix:** **Muito alto** — quase tudo live/seller  
- **Stripe:** N/A  

### SEC-030 — Race `queue_position`  
- **Estado:** ACEITE parcial · **Já em escala:** C8 + SEC-021 (`recompact_live_queue` com ownership)  
- **Evidência:** escala A1.6  
- **Nota:** race sob pico extremo possível; serializable/lock = risco de fila a falhar no directo  
- **Risco do fix completo:** **Médio–alto** — fila live  
- **Stripe:** N/A  

### SEC-031 — Sem cron de expiração de estados  
- **Estado:** ACEITE deferred · **Já em escala:** C6  
- **Evidência:** escala  
- **Nota:** precisa de TTL de produto acordado; cron errado = stock «desaparece»  
- **Risco do fix:** **Médio** — reservas / pending  
- **Stripe:** N/A  

---

# Baixa / aceite residual

### SEC-032 — Anon key no cliente Flutter  
- **Estado:** ACEITE (desenho Supabase)  
- **Nota:** não é secret; segurança = RLS (SEC-001–007…)  
- **Risco do fix:** N/A (não «fixar» escondendo a key)  

### SEC-033 — Admin UI client-side gate  
- **Estado:** ACEITE* após SEC-001  
- **Risco do fix:** Baixo (melhorar UX não substitui RLS)  

### SEC-034 — Tip checkout GET settle  
- **Estado:** FECHADO parcial (rate-limit GET + POST) · **Retest:** `APP-SEC-034` · residual: webhook Stripe = SEC-005  
- **Evidência:** `create-live-tip-checkout`  
- **Fix aplicado:**  
  1. GET settle: rate-limit **20/h** por `session_id`  
  2. POST create: rate-limit **30/h** por buyer (fail-open)  
  3. settle continua a exigir Stripe `payment_status=paid`  
- **Risco do fix:** **Muito baixo** — gorjeta normal 1–2 hits  
- **Stripe:** sandbox  

### SEC-035 — Realtime publication gap  
- **Estado:** ACEITE (produto) · **Já em escala:** C5  
- **Nota:** Hub anon usa poll de propósito (`hub_live_messages_public`); auth usa Realtime em `live_messages`  
- **Não «fixar»** à pressa com publication extra — risco de partir studio/Hub  
- **Risco do fix:** **Médio**  
- **Stripe:** N/A  

### SEC-036 — Schema core fora do repo  
- **Estado:** ACEITE parcial (docs) · **Já em escala:** C11  
- **Fix parcial:** inventário SEC + `docs/SECURITY_SQL_APPLY_LIST.md` como checklist deploy  
- **Residual:** dump schema `orders`/`profiles` versionado — quando houver janela de docs, não bloqueia hardening  
- **Risco do fix completo:** **Alto** se migrarem sem inventário  
- **Stripe:** N/A  

### SEC-037 — `create-connect-account` sem rate-limit  
- **Estado:** FECHADO (código edge) · **Aplicar:** redeploy `create-connect-account`  
- **Evidência:** `create-connect-account/index.ts` (onboarding Stripe Connect + levantamentos)  
- **Exploit:** spam de AccountLinks / tentativas de transfer  
- **Fix aplicado:** rate-limit **20/h** por user após `getUser()` — fail-open se RPC falhar  
- **Risco do fix:** **Muito baixo** — wallet normal 1–3 hits  
- **Stripe:** sandbox — onboarding/levantamento intactos  
- **QA:** abrir wallet / link Connect OK; 429 só com spam absurdo  

### SEC-038 — `delete-test-account` sem rate-limit  
- **Estado:** FECHADO (código edge) · **Aplicar:** redeploy `delete-test-account`  
- **Evidência:** `delete-test-account/index.ts` (só staging + `ALLOW_TEST_ACCOUNT_NUKE`)  
- **Exploit:** spam de nuke da própria conta de teste  
- **Fix aplicado:** rate-limit **5/h** por user após auth — fail-open  
- **Risco do fix:** **Nulo** na app de produção (edge bloqueada fora de staging)  
- **Stripe:** N/A  

---

## Matriz sugerida para «avançar aos poucos»

| Lote | IDs | Porquê | Risco conjunto do lote |
|------|-----|--------|-------------------------|
| **L0 — Confirmar factos** | SEC-003, SEC-015, SEC-025, SEC-027 | Verificar no Dashboard o que está mesmo aplicado (sem código) | Nenhum (só leitura) |
| **L1 — Admin & dinheiro BD** | SEC-001, SEC-002 | Pior fraude com conta grátis | Alto — reteste contas + encomendas |
| **L2 — Live keys & convert** | SEC-003, SEC-004 | Transmissão + fila | Alto — lives + checkout live |
| **L3 — PII** | SEC-007, SEC-012 | GDPR / confiança | Alto — muitos ecrãs perfil |
| **L4 — Stripe de verdade** | SEC-005, SEC-006, SEC-011, SEC-018, SEC-034 | Money real | Muito alto |
| **L5 — PS & rifas** | SEC-008, SEC-009, SEC-010, SEC-013 | Abuso live/FB | Médio–Alto |
| **L6 — Resto** | SEC-014, SEC-016–024, SEC-028–031, … | Endurecimento | Variável |

---

## Limites honestos desta auditoria

1. **Só o que está no repo** — prod pode ter SQL diferente (SEC-015).  
2. **Stripe sandbox** — SEC-005/006/011/034 precisam validação com keys live + webhook.  
3. **Não testámos exploits activos** contra staging (sem autorização explícita de penetração).  
4. **Storage / Dashboard Supabase** — parcialmente cego (SEC-027).  

---

## Próximo passo (quando quiseres)

**Fase fail-safe (código):** esgotada — rate-limits + observes + SQL 1–12 escritos.  
**Teu lado agora:** correr SQL 1–12 + redeploys da lista (sem isto, staging não fica endurecido).

Depois, **só com OK explícito** (risco real de regressão):

1. **SEC-007 fase 1b** — restringir SELECT authenticated em `profiles`  
2. **SEC-006 full** — rejeitar amounts (após logs observe)  
3. **SEC-029** — normalizar `seller_id` / `vendedor_id` (após SQL observe #13)

**SEC-005 parcial:** edge `stripe-webhook` escrita — deploy + `STRIPE_WEBHOOK_SECRET` + endpoint Dashboard (tu).  
**Já escrito (correr tu):** SEC-007 fase 1a = lista SQL **#14** (só anon).
