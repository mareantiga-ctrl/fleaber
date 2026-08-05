# QA — Retestes de segurança (SEC)

**Estado:** documentado para corrida futura — **não executar agora** (pedido 2026-08-04).  
**Inventário:** `docs/SECURITY_AUDIT_INVENTORY.md`  
**Lista mestre:** IDs `APP-SEC-*` em `tool/FLEABER_APP_QA_MASTER_LIST.md`  
**Fila sessão:** também em `tool/reports/MANUAL_QA_PENDING.md` (bloco SEC)

**Como usar:** na próxima corrida manual (ou ao fechar ARCO-PROF / APP-002 registo), incluir estes IDs. Responder só `APP-SEC-xxx: PASS/FAIL`.

**Dispositivos:** V TCL · B Redmi · PC Chrome (SQL/API)

---

## Já fechados em staging (retest obrigatório)

### APP-SEC-012 — Lookup email com rate limit (SEC-012)

**Pré-condição:** SQL `sec_low_hardening_batata.sql` aplicado; conta vendedor logada.

**Quem:** V (TCL)

1. Perfil / equipa → convidar helper com email **válido** de outra conta Fleaber.
2. Confirma que o convite encontra o utilizador (como antes).
3. (Opcional PC) Em loop rápido, >30 lookups/hora do mesmo user → deve falhar `rate_limited` (não precisa no telemóvel se convite 1× OK).

**No ecrã deve aparecer:**
- Convite helper continua a funcionar com 1–2 emails.

Responde: `APP-SEC-012: PASS / FAIL`

---

### APP-SEC-019 — CORS allowlist (SEC-019)

**Pré-condição:** edges redeployadas com `_shared/cors.ts`.

**Quem:** PC Chrome + (se usares) extensão PS

1. Abre Hub `fleaber.pt` (ou staging Hub) — login / acção que chame edge (ex. criar connect ou playback).
2. Se usas PS: pairing / heartbeat a partir da extensão.

**No ecrã deve aparecer:**
- Hub e app web sem erro CORS no DevTools.
- PS continua a emparelhar.

**FAIL se:** pedido bloqueado CORS em fleaber.pt ou chrome-extension.

Responde: `APP-SEC-019: PASS / FAIL`

---

### APP-SEC-022 — app_logs só autenticado (SEC-022)

**Pré-condição:** SQL low-hardening aplicado.

**Quem:** B ou V

1. Com sessão **terminada** (logout): provoca um erro se possível — não deve criar linha anónima (verificar no Supabase Table Editor `app_logs` se tiveres acesso, ou SKIP verificação BD).
2. Com sessão **iniciada**: usa a app até gerar um log remoto (erro ou evento).

**No ecrã:**
- App logada continua normal.
- Logs pré-login podem falhar em silêncio (esperado).

Responde: `APP-SEC-022: PASS / FAIL / SKIP (sem acesso BD)`

---

### APP-SEC-023 — studio logs sem spoof seller (SEC-023)

**Pré-condição:** SQL low-hardening; conta vendedor.

**Quem:** V

1. Abre studio / directo (ou preparar) até haver actividade que grave `live_vendor_studio_logs`.
2. Confirma que a app não parte (logs opcionais).

**FAIL se:** studio deixa de funcionar por erro de permissão em cascata.

Responde: `APP-SEC-023: PASS / FAIL`

---

### APP-SEC-001 — Não auto-promover a admin (SEC-001)

**Pré-condição:** SQL `sec_001_guard_user_type_batata.sql` aplicado; conta **não**-admin.

**Quem:** PC (Supabase) ou agente com RPC; + V registo/perfil

**Parte A — ataque (deve falhar)**

1. Login como utilizador normal (vendedor/comprador).
2. Tenta: `update profiles set user_type = 'admin' where id = auth.uid()` (SQL via cliente autenticado / Table Editor com RLS da conta, ou REST).
3. Recarrega perfil / tenta abrir `/admin`.

**No ecrã / BD deve aparecer:**
- `user_type` **não** fica `admin`.
- Painel admin **não** abre (ou abre e BD nega acções admin).

**Parte B — regressão (deve continuar OK)** — juntar a **APP-002** se estiver na mesma corrida

1. Registo novo ou `ProfilePatchService` / tornar vendedor.
2. Perfil mantém ou define `user_type = vendedor` sem erro.

**Parte C — ops (opcional)**  
Promover admin real só via SQL Editor / service_role (documentar quem é admin).

Responde: `APP-SEC-001: PASS / FAIL`

---

### APP-SEC-002 — Guard estados encomenda (SEC-002 fase 1+2)

**Pré-condição:** SQL `sec_002_*` + `sec_002b_*` aplicados.

**Quem:** V + B

**Ataques (devem falhar)**
1. B força `pago` sem ser `premio_rifa`.
2. B força `enviado` ou `devolvida`.
3. B força `concluido` a partir de `reservado` / `reserva_pendente`.

**Regressões (devem PASS)**
1. V confirma MB WAY → `pago`.
2. V marca enviado → `enviado`.
3. B confirma receção (`enviado`→`concluido`) ou mão (`pago`→`concluido`).
4. B prémio rifa mão (`premio_rifa`→`pago`).
5. Disputa: V → `devolvida`; B fecha disputa → `concluido`; B inicia devolução → `em_devolucao`.

Responde: `APP-SEC-002: PASS / FAIL`

---

### APP-SEC-003 — Stream keys fora do SELECT de lives (SEC-003)

**Pré-condição:** `sec_003b_lives_safe_columns_batata.sql` aplicado.

**Quem:** V + B

1. Home → Diretos: vê lives (vídeo/HLS OK).
2. V: criar/iniciar directo (key via edge `create-mux-live`).
3. V: terminar directo.

**FAIL se:** Home vazia; criar directo falha; player sem HLS.

Responde: `APP-SEC-003: PASS / FAIL`

---

### APP-SEC-004 — stripe_convert só servidor (SEC-004)

**Pré-condição:** revoke authenticated aplicado.

**Quem:** smoke

1. Se houver checkout live/Stripe: fluxo de conversão de reserva como antes.
2. SKIP se não houver compra live nesta sessão.

Responde: `APP-SEC-004: PASS / FAIL / SKIP`

---

## Ordem sugerida na próxima corrida

1. APP-SEC-001 (admin)  
2. APP-SEC-002 (encomendas / MB WAY / rifa / disputa)  
3. APP-SEC-003 (criar directo + Home Diretos)  
4. APP-SEC-004 (smoke checkout live ou SKIP)  
5. APP-SEC-008 (PS pairing) + APP-SEC-009/010 (rifa smoke)  
6. APP-SEC-014 (aceitar convite helper)  
7. APP-SEC-016 / 017 (Gravados + criar directo — após SQL #8 + redeploy edges)  
8. APP-SEC-020 (chat sistema / FOMO) + APP-SEC-021 (saco / fila)  
9. APP-SEC-024 (chat + contagem espectadores no directo)  
10. APP-SEC-027 (1 upload chat + 1 perfil ou produto)  
11. APP-SEC-025 (só se houver disputa com reembolso parcial — senão SKIP)  
12. APP-SEC-011 (anular venda Seguro Fleaber / SKIP se sem caso)  
13. APP-SEC-013 (Hub: claim reservas FB 1× numa live)  
14. APP-SEC-034 (gorjeta return URL — se testares tips)  
15. APP-SEC-012 / 023 / 019 / 022  

Encaixar no fim da sessão ou arranque da seguinte — **não** agora.

**SQL a correr tu (lista completa):** `docs/SECURITY_SQL_APPLY_LIST.md`

---

### APP-SEC-008 — PS pairing rate-limit (SEC-008 parcial)

**Pré-condição:** SQL `sec_008_009_010_020_021_batata.sql`; Studio + PS Reader PC.

**Quem:** V (TCL) + PC

1. No studio, gera código de emparelhamento PS.
2. No PC, introduz o código correcto — deve emparelhar como antes.
3. FAIL se pairing deixar de funcionar com 1–2 tentativas normais.

**No ecrã deve aparecer:**
- Código 6 dígitos continua a funcionar; ligação PS OK.

Responde: `APP-SEC-008: PASS / FAIL`

---

### APP-SEC-009 — Prémio rifa sem RPC directa (SEC-009)

**Pré-condição:** SQL aplicado; live com rifa de catálogo (se tiveres).

**Quem:** V + B

1. Corre um sorteio / atribuição de prémio como no fluxo normal (não chames RPC à mão).
2. Confirma que o vencedor recebe encomenda/prémio como antes.

**FAIL se:** draw/prémio parte com erro de permissão.

Responde: `APP-SEC-009: PASS / FAIL / SKIP (sem rifa catálogo)`

---

### APP-SEC-010 — Tickets rifa via join/share (SEC-010)

**Pré-condição:** rifa activa na live.

**Quem:** B

1. Entra na rifa / partilha / tip conforme o fluxo habitual.
2. Confirma que recebes bilhetes (número sobe).

**FAIL se:** join/share deixa de dar bilhetes.

Responde: `APP-SEC-010: PASS / FAIL / SKIP`

---

### APP-SEC-020 — Mensagens sistema live (SEC-020)

**Pré-condição:** SQL aplicado.

**Quem:** B (+ V se studio anunciar)

1. Reserva artigo para o saco na live — deve aparecer mensagem sistema no chat («reservou…»).
2. Se stock desce para 1 unidade: FOMO «Última unidade» (se aplicável).

**FAIL se:** mensagens sistema deixam de aparecer no uso normal.

Responde: `APP-SEC-020: PASS / FAIL`

---

### APP-SEC-021 — Fila recompact com ownership (SEC-021)

**Pré-condição:** SQL aplicado.

**Quem:** B + V

1. B: reserva 2 artigos / cancela um do saco — posições da fila actualizam.
2. V: no studio, aceita/recusa reserva — stock/estado do artigo actualiza.

**FAIL se:** fila fica presa ou studio não actualiza estado após acção.

Responde: `APP-SEC-021: PASS / FAIL`

---

### APP-SEC-014 — Helper não alarga permissions (SEC-014)

**Pré-condição:** SQL #7 em `docs/SECURITY_SQL_APPLY_LIST.md`; conta V com convite helper pendente (ou cria um).

**Quem:** B (como helper convidado) + V

1. B: aceita o convite de colaborador na app (fluxo normal).
2. V: em Equipa, confirma que as permissões do helper são as que **tu definiste** no convite (não «tudo ligado»).
3. V: edita permissões do helper (ligar/desligar uma) — deve gravar.

**FAIL se:** aceitar convite falha; ou helper fica com permissões financeiras/admin sem o seller ter dado.

Responde: `APP-SEC-014: PASS / FAIL`

---

### APP-SEC-016 — Resolve Mux playback (SEC-016)

**Pré-condição:** SQL #8 + edge `resolve-mux-playback` redeployada.

**Quem:** B ou PC Hub

1. Abre um directo **terminado** em Gravados / Hub (com ou sem VOD já pronto).
2. Confirma que o vídeo / «Gravação a preparar» comporta-se como antes (não parte o ecrã).

**FAIL se:** gravados deixam de abrir ou erro permanente no player.

Responde: `APP-SEC-016: PASS / FAIL`

---

### APP-SEC-017 — Create Mux quota (SEC-017)

**Pré-condição:** edge `create-mux-live` redeployada.

**Quem:** V

1. Cria **um** directo novo (fluxo normal Novo Direto) — deve funcionar.
2. Não precisas testar o limite 10/dia no telemóvel (só se estiveres a spammar creates).

**FAIL se:** o 1.º / 2.º directo do dia falha com erro de quota ou auth.

Responde: `APP-SEC-017: PASS / FAIL`

---

### APP-SEC-024 — Chat / viewers SELECT scoped (SEC-024)

**Pré-condição:** SQL #9 em `docs/SECURITY_SQL_APPLY_LIST.md`.

**Quem:** B + V

1. B: entra num directo **ao vivo**, vê chat a actualizar e contagem de espectadores.
2. V: no studio, vê chat e contagem; após terminar, resultados de sessão ainda mostram actividade do chat se aplicável.

**FAIL se:** chat vazio com gente a falar; ou contagem sempre 0; ou studio sem histórico de mensagens da própria live.

Responde: `APP-SEC-024: PASS / FAIL`

---

### APP-SEC-027 — Storage chat_media (SEC-027)

**Pré-condição:** SQL #10.

**Quem:** B e/ou V

1. Envia **uma imagem no chat** (comprador ou vendedor).
2. (Opcional) V: sobe foto de produto **ou** foto de perfil.

**FAIL se:** upload falha com erro de storage / permissão.

Responde: `APP-SEC-027: PASS / FAIL`

---

### APP-SEC-025 — Wallet disputa só participantes (SEC-025)

**Pré-condição:** SQL #11; idealmente uma disputa com proposta de reembolso parcial.

**Quem:** B (aceita parcial) — fluxo normal do chat

1. Se tiveres disputa com % proposto pelo vendedor: aceita o reembolso parcial como sempre.
2. Confirma que a app não mostra erro de permissão e o estado da disputa avança.

**FAIL se:** «aceitar parcial» deixa de funcionar para o comprador da encomenda.  
**SKIP** se não houver disputa parcial nesta sessão.

Responde: `APP-SEC-025: PASS / FAIL / SKIP`

---

### APP-SEC-011 — Refund Stripe só vendedor (SEC-011)

**Pré-condição:** edge `refund-order` redeployada.

**Quem:** V

1. Se tiveres encomenda **Seguro Fleaber** paga: anula a venda como vendedor (fluxo normal).
2. Confirma que o cancelamento / mensagem de reembolso se comporta como antes.

**FAIL se:** anular venda Seguro Fleaber falha com «Sem permissão» para o **vendedor**.  
**SKIP** se não houver encomenda Seguro Fleaber para anular.

Responde: `APP-SEC-011: PASS / FAIL / SKIP`

---

### APP-SEC-013 — Claim FB scoped (SEC-013 parcial)

**Pré-condição:** SQL #12.

**Quem:** B (Hub) ou quem usa claim PS

1. Numa live no Hub com reservas Facebook órfãs (se tiveres): corre o claim / «são as minhas» **uma vez**.
2. Confirma que liga as tuas reservas como antes.

**FAIL se:** claim one-tap deixa de funcionar com live_id normal.  
**SKIP** se não houver reservas FB para claimar.

Responde: `APP-SEC-013: PASS / FAIL / SKIP`

---

### APP-SEC-034 — Tip GET settle rate-limit (SEC-034 parcial)

**Pré-condição:** edge `create-live-tip-checkout` redeployada (+ SQL #8 para rate RPC).

**Quem:** B

1. Faz **uma** gorjeta normal no directo (fluxo Stripe sandbox).
2. Confirma que a gorjeta regista / aparece no chat como antes.

**FAIL se:** return URL / settle da gorjeta parte no 1.º pagamento.

Responde: `APP-SEC-034: PASS / FAIL / SKIP`

---

### APP-SEC-007 — Profiles: anon sem SELECT (SEC-007 fase 1a)

**Pré-condição:** SQL lista **#14** (`sec_007_revoke_anon_profiles_batata.sql`) corrido em staging.

**Quem:** B (app) + PC (Hub)

1. App logada: abre Perfil / definições / vês MB WAY ou morada tua — deve funcionar como antes.
2. Compra ou chat onde vejas dados de pagamento do vendedor (se aplicável) — deve continuar a aparecer **com login**.
3. Hub público no browser (sem login): página do vendedor / loja — deve abrir via vitrine pública.
4. (Opcional ops) Com só anon key, `select` directo a `profiles` não deve devolver IBAN/moradas.

**FAIL se:** app logada deixa de carregar perfil; Hub público parte; MB WAY some para comprador autenticado.

Responde: `APP-SEC-007: PASS / FAIL`

---

### APP-SEC-018 — Checkout return URL rate-limit (SEC-018b)

**Pré-condição:** edge `create-payment-intent` redeployada (+ SQL #8 para rate RPC).

**Quem:** B

1. Faz **uma** compra Stripe sandbox normal até ao return / deep link.
2. Confirma que a encomenda fica paga / app abre como antes.

**FAIL se:** o 1.º return após pagar dá erro ou a encomenda não marca pago.

Responde: `APP-SEC-018: PASS / FAIL / SKIP`

---

### APP-SEC-005 — Webhook Stripe settle aditivo (SEC-005 parcial)

**Pré-condição:**  
- edge `stripe-webhook` deployed  
- secret `STRIPE_WEBHOOK_SECRET` no projecto staging  
- endpoint no Stripe Dashboard (modo **test**) a apontar para `…/functions/v1/stripe-webhook`  
- eventos: `checkout.session.completed`, `checkout.session.async_payment_succeeded`

**Quem:** B (+ opcional V)

1. Faz **uma** compra Stripe sandbox normal (marketplace ou saco) até pagar.
2. Confirma que a encomenda fica **pago** como antes (return URL / app).
3. (Opcional stress) Fecha o browser **antes** do redirect e confirma que a encomenda **mesmo assim** fica paga via webhook (pode demorar 1–5 s).
4. (Opcional) Uma gorjeta Stripe — deve continuar a registar.

**FAIL se:** compra normal deixa de marcar pago; stock duplica (qty cai 2×); chat «Compra paga» aparece em duplicado de forma confusa.

Responde: `APP-SEC-005: PASS / FAIL / SKIP`



