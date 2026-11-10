| `190-C1-dpd-prod-bulkgate.zip` | **2026-11-10** C1 ZIP 190 · DPD OAuth **PROD PASS** (fix VPS `host_not_allowed`) · create OFF · BulkGate kill-switch + deploy · secrets ID/token/hook **FAIL** · SMS **STOP** · handoff C3 em `docs/redteam-handoff/` (branch `c1/190-redteam-handoff`) · **0 €** |
| `189-C1-pre-redteam-readiness.zip` | **2026-11-09** C1 ZIP 189 · pré-Red Team · DPD LIVE secrets + probe · OAuth PROD aviso allowlist · Hub férias · BulkGate pendente · **STOP** Red Team ofensivo |
| `187-C2-auth-email-templates-pt.zip` | **2026-11-09** C2 ZIP 187 · templates Auth PT-PT (confirmação/recovery/email_change) restaurados · SMTP Amen intocado · 1 envio real PASS · Amazon worker intocado · **STOP** |
| `184-C2-amazon-revisao-autonoma-diretos.zip` | **2026-11-09** C2 ZIP 184 · revisão autónoma 211 needs_review (piloto 1/5 recovered + full PID detached) · diretos EAN/ASIN/LPN/FLB + overlay/montra + Hub botão dono · Moloni multiempresa sim PASS · **sem publish/docs reais** · **STOP** |
| `188-C1-android-hub-carteira-stripe-live.zip` | **2026-11-09** C1 ZIP 188 · App Links email · gravados alinhados Hub · carteira copy PT · Connect individual · SMS **FAIL** (BulkGate off prod) · APK **1880** · Hub FTP · LIVE onboarding **STOP** · **0 €** |
| `187-C1-signup-scale-amen500.zip` | **2026-11-09** C1 ZIP 187 · Auth **500/h** (=Amen dia) · hook anti-abuso IP/email/device + desafio adaptativo · simulação pico **PASS** · APK **1870** no Redmi · DKIM ainda ausente · **0 €** · **STOP** |
| `186-C1-smtp-amen-auth-geral.zip` | **2026-11-09** C1 ZIP 186 · SMTP Amen `geral@fleaber.pt` no Supabase Auth · rate 20/h · Hub+Android confirm **PASS** · SPF/DMARC OK · **DKIM ausente** · sem password no ZIP · **STOP** |
| `185-C1-registo-publico-hub-android.zip` | **2026-11-09** C1 ZIP 185 · registo público Hub+Android desbloqueado · causa=`FLEABER_PUBLIC_REGISTRATION` · Hub/Android/email **PASS** · APK **1850** · João/Cláudia **SIM** · **STOP** |
| `184-C1-dpd-envios-qa-rui.zip` | **2026-11-09** C1 ZIP 184 · 2 envios QA para Rui (S2S `09861652000006O` + S2H `09861659000011M`) · PDFs · email pronto · create OFF · **sem PROD/email auto** · **STOP** |
| `182.1-C1-stripe-connect-onboarding-app-hub-pass.zip` | **2026-11-09** C1 ZIP 182.1 · Hub UI E2E **PASS** (saldo→Stripe `[Test]`→return fleahub) + Android PASS · sem docs reais/LIVE/dinheiro · **STOP** |
| `182-C1-stripe-connect-onboarding-app-hub.zip` | **2026-11-09** C1 ZIP 182 · onboarding Connect Android+Hub · fix return fleahub + refresh + launcher · APK release · supersedido por **182.1** (Hub E2E fechado) · TEST · **STOP** |
| `181-C1-stripe-connect-live-piloto.zip` | **2026-11-09** C1 ZIP 181 · piloto LIVE restrito (allowlist+teto+MONEY_GO=0) · Express **0** · cenário **1,70 €** · **STOP antes de dinheiro** · GO global=0 |
| `180-C1-stripe-connect-documentacao-solucao.zip` | **2026-11-09** C1 ZIP 180 · docs oficiais: Platform setup ≠ charge type · SCT **COMPATÍVEL** com defaults Direct · falso alarme 179 · 0 code/Dashboard · GO=0 dinheiro · **GO preparar** LIVE · **STOP** |
| `179-C1-stripe-connect-modelo-fleaber.zip` | **2026-11-09** C1 ZIP 179 · modelo real = **Separate charges and transfers** · Dashboard direct charges **desalinhado** · retenção carteira · GO=0 · **NO-GO** · **STOP** |
| `178-C1-stripe-connect-live-readiness.zip` | **2026-11-09** C1 ZIP 178 · Connect readiness · Requires setup = 0 contas LIVE (webhook enabled) · transfer.canceled + Connect TEST/LIVE gate · GO=0 · **NO-GO LIVE** · **STOP** |
| `174.1-C1-stripe-live-credenciais-20261109.zip` | **2026-11-09** C1 ZIP 174.1 · Stripe LIVE sk+2 whsec no Edge · GO=0 · TEST intocado · DPD comercial PENDENTE · sem pagamentos · **STOP** |
| `174-C1-stripe-dpd-credenciais-reais-20261106.zip` | **2026-11-06** C1 ZIP 174 · GO flags OFF · TEST+QA OK · LIVE/COMERCIAL **credenciais ausentes** (CredMan+script prontos) · ops-env-audit · sem pagamentos/etiquetas/Hub/APK · **STOP aguarda CredMan** |
| `172-C1-ambientes-dual-stripe-dpd-20261106.zip` | **2026-11-06** C1 ZIP 172 · fecho dual Stripe/DPD · sem fallback LIVE→global · DPD por encomenda (sem DPD_MODE) · imutabilidade pós-finance/ship · TEST+QA OK · 3 modos reais bloqueados · Edges deploy · sem Hub/APK/GO · **STOP autorização** |
| `171-C1-ambientes-stripe-dpd-redteam.zip` | **2026-11-06** C1 ZIP 171 · sticky TEST/QA · painel Ambientes · LIVE/COMERCIAL PENDENTE GO · Hub167/APK1680 · sem publish/install · **STOP autorização** |
| `169-C1-monitorizacao-backups-recuperacao-20261106.zip` | **2026-11-06** C1 ZIP 169 · WALG PASS · restauro ISO PASS · LiveKit cron PASS · ops-health PASS (email PENDENTE) · Hub167/APK1680 preservados · LIVE/DPD/cron comercial OFF · **STOP aguarda feito** |
| `168-C1-livekit-mux-fecho-lancamento-20261106.zip` | **2026-11-06** C1 ZIP 168 · fecho LiveKit/Mux · `ended_at` + UX gravação · 0 lives activas · 0 egress LiveKit · APK **1680** no ZIP (**sem install**) · Hub **não** republished · cleanup cron secret **PENDENTE** · STOP aguarda feito |
| `fleaber-168-C1-livekit-mux.apk` | APK solto versionCode **1680** (mesmo do ZIP 168-C1) — **não instalado** |
| `167-fleaber-unificacao-final-hub-android-20261106.zip` | **2026-11-06** C1 ZIP 167 · unificação **166.2-C1 + 166.1-C2** · APK **1670** instalado TCL · Hub **publicado** stamp 167 · LIVE/DPD/cron OFF |
| `166.2-C1-fleaber-hub-apk-wallet-ponto11-20261106.zip` | **2026-11-06** C1 ZIP 166.2 · Hub+APK **1662** carteira Disponível/Pendente/Retido + Connect + levantamentos · base 165 preservada · **sem install/FTP** · conflitos C2 166.1 listados · LIVE OFF · **STOP aguarda feito** |
| `166-fleaber-ponto11-saldos-pagamentos-vendedores-20261106.zip` | **2026-11-06** C1 ZIP 166 · Ponto 11 Connect/saldos · notify libertação+payout · account.updated + transfer.failed · UI Disponível/Pendente/Retido · smoke BD PASS · Edges deploy · **sem Hub/APK** · LIVE OFF · **STOP aguarda feito** |
| `165-fleaber-unificacao-c1-c2-20261106.zip` | **2026-11-06** C1 ZIP 165 · unificação C1 160 + C2 164.1 · APK **1650** instalado TCL · Hub **publicado** stamp 165 · Stripe TEST · DPD comercial OFF · sync OFF |
| `169-C2-fotos-precos-moloni-sim-20261106.zip` | **2026-11-06** C2 ZIP 169 · galerias 20/20 multi-foto · preços auditados **sem alterar** · Moloni Edge simulation 3 artigos · secrets por configurar · **sem Hub/APK/live Moloni** · **STOP aguarda feito** |
| `168-C2-amazon-20-publicados-mare-20261106.zip` | **2026-11-06** C2 ZIP 168 · **20 anúncios** publicados Mare Antiga (marketplace+Hub) · distintos dos 15 · PT-PT/fotos/preço/peso/estado · **sem Moloni/Hub code/APK/625** · **STOP avaliação visual** |
| `166.1-C2-importador-aprovacao-gate-20261106.zip` | **2026-11-06** C2 ZIP 166.1 · gate aprovação backend (trigger+RPC) · incompletos bloqueados · massa com motivos · prova PROD PASS · causa 3 ASIN=snapshot vs sim · **sem Hub/APK/584** · **STOP aguarda feito** |
| `166-C2-importador-lote-preparacao-20261106.zip` | **2026-11-06** C2 ZIP 166 · preparação lote 584/625 · pausa/retoma · revisão/aprovação em massa · Moloni/Fleaber **só simulação** · demo 25 linhas BD · **sem FTP/APK/publish** · **STOP aguarda feito** |
| `164.1-amazon-android-camera-detect-20261106.zip` | **2026-11-06** C2 ZIP 164.1 · câmara TCL lê + encontra artigo do lote (APK **1645**) · EAN fora do lote = não encontrado OK · backup vc1595 · **STOP aguarda feito** |
| `164-amazon-android-camera-fix-20261106.zip` | **2026-11-06** C2 ZIP 164 · câmara Android TCL PASS (sem Snapshot; hardware CONNECT) · APK teste 1642 + backup vc1595 · EAN/LPN/multi PASS · decode físico etiqueta PENDENTE (apontar) · sem Hub republish / sem 584 / C1 DPD intocado · **STOP aguarda feito** |
| `163-amazon-scanner-camera-lpn-20261106.zip` | **2026-11-06** C2 ZIP 163 · leitor Hub PASS (EAN/LPN/multi/missing) · 15 LPN manifesto · mobile_scanner Android · APK teste 1630 (NAO instalar TCL) · prova camera device PENDENTE · sem 584 / C1 intocado · aguarda feito |
| `162-amazon-seller-weight-scan-20261105.zip` | **2026-11-05** C2 ZIP 162 · nome Mariana Soares (anon Hub PASS) · peso manifesto +10% → products.shipping_weight_kg · leitor EAN/LPN/ASIN admin · Hub stamp 162 · câmara Android pendente · sem 584 / C1 DPD intocado · aguarda feito |
| `160-fleaber-dpd-fecho-integracao-20261106.zip` | **2026-11-06** C1 ZIP 160 · etiqueta QA real 09861652000005Q + PDF · idempotência · tracking in-app empty OK · sync OFF · CP limpa localidade · APK 160 · Hub não republished (C2) · comercial OFF |
| `159.5.1-tcl-prints-ultimos-20min-20261106.zip` | **2026-11-06** C1 · 3 prints TCL (~05:21–05:22) últimos 20 min |
| `159.5.1-fleaber-peso-escalao-vendedor-20261105.zip` | **2026-11-05** C1 · vendedor kg **ou** escalão · auto-escalão a partir do kg · checkout comprador intocado (159.5) · prints TCL + APK 1596.1 · Hub = mesmo form (sem republish C2) |
| `159.5-fleaber-checkout-dpd-correcoes-20261105.zip` | **2026-11-05** C1 · Pickup CP/localidade + teclado · portes auto (sem escalão comprador) · etiqueta sem PII · QA create ON / comercial OFF · APK 1596 · Stripe staging disabled confirmado · Hub não republicado (C2 UTF-8) · aguarda feito + prints |
| `159.4.2-tcl-prints-ultimos-10min-20261105.zip` | **2026-11-05** C1 · 3 prints TCL (~19:04) puxados do telemóvel · pausa antes Stripe staging |
| `159.4.2-fleaber-stripe-staging-webhook-disable-20261105.zip` | **2026-11-05** C1 · Stripe TEST: desactivado só webhook staging `fxdknzr…/stripe-webhook` (`we_1U17RE…`) · Prod `bpmpkz…` permanece enabled · prova list before/after + health 400 missing_signature · DPD não retestado · Live intocado |
| `161.1-amazon-hub-utf8-encoding-live-20261105.zip` | **2026-11-05** C2 ZIP 161.1 · Hub **publicado** stamp `161.1-hub-utf8-encoding` · Descrição/€ PASS Chrome · CanvasKit local + dart-defines · APK 161.1 · **sem 584 / C1 DPD intocado** |
| `161-amazon-importer-fecho-dedupe-encoding-20261105.zip` | **2026-11-05** C2 ZIP 161 · fecho 15: dedupe visual galerias · UTF-8 fonte Flutter · rehost chat_media 15/15 · Hub prints · **sem 584 / sem FTP / C1 intocado** · aguarda feito |
| `160-amazon-15-anuncios-correcao-20261105.zip` | **2026-11-05** C2 ZIP 160 · 15 títulos/desc PASS · galeria ~12 fotos · UTF-8 limpo · **15 despublicados p/ revisão Novo↔dano** · sem 584 |
| `159.1-amazon-15-publicados-mare-20261105.zip` | **2026-11-05** C2 · **13/15 publicados** marketplace Mare Antiga · 2 bloqueados sem preço (não inventado) · Hub `/mariana-prod` |
| `159-amazon-importer-15-drafts-mare-20261105.zip` | **2026-11-05** C2 ZIP 159 · **15 rascunhos** Mare Antiga (privados) · fotos 15/15 · **sem publicar / sem 584 / sem FTP** · aguarda análise visual |
| `159-fleaber-dpd-hub-fix-matriz-20261105.zip` | **2026-11-05** C1 ZIP 159 ? Hub ecr� branco corrigido � matriz DPD � QA pudo/quotes PASS � create OFF � APK TCL � gui�o manual � DPD comercial OFF |
| `158-amazon-importer-browser-fotos-20261105.zip` | **2026-11-05** C2 ZIP 158 · fotos **15/15** (CDN+HTML+Playwright) · CAPTCHA humano 0 · **sem 584 / sem FTP** · aguarda feito |
# FleaHub / Unified Commerce ? ZIPs de entrega (pasta ?nica)

| `157-amazon-importer-fotos-llm-fix-20261104.zip` | **2026-11-04** C2 ZIP 157 · fotos 13/15 · LLM qwen2.5:7b 14/15 PASS · RPC segura · **sem 584 / sem FTP** · aguarda feito |
| `156-amazon-importer-fotos-llm-local-20261104.zip` | **2026-11-04** C2 ZIP 156 � fotos CDN auto 8/15 � direitos pendentes � Ollama qwen2.5:7b PT-PT � teste real 15 � migra��o+Edge PROD � **sem FTP Hub / sem 584** � aguarda feito |
| `155-amazon-importer-regras-finais-demo-20261104.zip` | **2026-11-04** C2 ZIP 155 � regras finais: s� Amazon ES?IT?DE?FR � sem �noutros sites� � fotos+origem+UI � PT-PT � estado Novo/manifesto � CAPTCHA alternativas � demo ?30 � Edges PROD � **sem FTP Hub / sem 584** � aguarda feito |
| `154-amazon-importer-price-priority-external-20261104.zip` | **2026-11-04** C2 ZIP 154 � prioridade ES?IT?DE?FR � ignora unavailable � pesquisa noutros sites � 15 replay 13 OK � probe 30 CAPTCHA 29/30 � **sem FTP Hub / sem 584** |
| `152.2-fleaber-emails-conjuntos-correcao-final-20261104.zip` | **2026-11-04** C1 ZIP 152.2 ? emails conjuntos: prazo 1 frase; lab valores coerentes + fotos reais fleaber.pt; incoer�ncia 18/22 vs 8,50 s� lab 152.1; 1 email mareantiga@; notify-dispatch PROD; Android/Hub intocados |
| `152.1-fleaber-android-visual-emails-conjuntos-20261104.zip` | **2026-11-04** C1 ZIP 152.1 � capturas TCL + UI conjuntos (fotos/totais/estado) + emails editoriais + lab mareantiga@ � Hub 151 intocado � DPD OFF |
| `153-amazon-importer-phase1-prod-go-20261104.zip` | **2026-11-04** C2 ZIP 153 � Importador Amazon Fase 1 GO � migra��o+Edge PROD � valida��o comercial 15 ASIN: 12 OK / 3 Por confirmar � **sem FTP Hub / sem lote 584** � aguarda regra pre�o + feito |
| `152-amazon-importer-phase1-hub-android-20261104.zip` | **2026-11-04** C2 ZIP 152 ? Importador Amazon Fase 1 ? Perfil admin ? CSV/RLS/Edge research ? viabilidade 15/15 ? Moloni/Fleaber stubs ? **sem PROD / sem deploy** ? aguarda GO |
| `152-fleaber-android-emails-bundle-fecho-20261104.zip` | **2026-11-04** C1 ZIP 152 ? Android TCL agostinha + APK prod ? emails conjuntos reais mareantiga@ ? templates proposal/48h ? notify-dispatch PROD ? fecho UI+BD ? Hub 151 intocado ? sem cron / DPD create OFF |
| `151-bundle-checkout-final-hub-e2e.zip` | **2026-11-04** C1 ZIP 151 ? fecho conjuntos+checkout ? 48h/48h sem reserva ? Hub publicado fleaber.pt/fleahub stamp 151 ? E2E PROD Stripe TEST 13 PASS/0 FAIL ? FTP ok ? Android n?o testado (sem adb) ? sem cron / DPD create OFF |
| `149.1-fleaber-bundle-pay48-webhook-idempotent-20261104.zip` | **2026-11-04** C1 ZIP 149.1 ? pay deadline 48h ON ? webhook replay HTTP 200 idempotente ? anti-shipping_delta com flags ON ? aditamento C2 ? FAIL=0 ? sem cron ? DPD create OFF ? sem deploy Hub/app |
| `149-fleaber-bundle-quote-before-pay-return-url-20261104.zip` | **2026-11-04** C1 ZIP 149 ? conjuntos sem reserva/pay at? cota??o 48h ? awaiting_payment ? pay 1? Stripe ? return_url PI ? contrato C2 ? FAIL=0 ? DPD create OFF ? sem cron ? sem deploy Hub/app |
| `144.3-fleaber-checkout-amount-align-20261104.zip` | **2026-11-04** C1 ZIP 144.3 ? drift begin/CPI/settle corrigido (portes DPD 299?) ? fluxo real begin?pago 12,71 ? ? webhook 1? ? mensagem montante ? esgotado ? notify-dispatch `sb_secret_` ? FAIL=0 ? DPD create OFF ? sem cron |
| `144.2-fleaber-stripe-e2e-prod-proofs-20261104.zip` | **2026-11-04** C1 ZIP 144.2 ? E2E Stripe TEST PROD ? checkout pago ? delta JWT+webhook sem double-settle ? expire 48h+refund idempotente ? DPD gate ? C2 144/145 contratos ? FAIL=0 ? flags OFF ? sem cron ? DPD create OFF ? pend?ncia drift begin?CPI?settle |
| `150-fleaber-bundle-quote-ui-hub-android-20261104.zip` | **2026-11-04** C2 ZIP 150 ? UI conjuntos quote-before-pay 48h ? Pagar/Desistir/Confirmar portes ? emails kinds ? build web OK ? **sem deploy** |
| `148-fleaber-hub-integrate-145.1-146.1-147.1-20261104.zip` | **2026-11-04** C2 ZIP 148 ? integra 145.1+146.1+147.1 ? ciclo ProductDetails resolvido ? `flutter build web` OK ? 19 PASS ? C1 144.3 preservado ? **sem deploy** |
| `147.1-fleaber-hub-anuncios-perfil-ajuda-followup-20261104.zip` | **2026-11-04** C2 ZIP 147.1 ? foto marketplace obrigat?ria + MIME/contentType ? Explorar?tab diretos ? banner f?rias PT partilhado ? refs CTA rascunhos ? 13 PASS fecho ? **sem deploy** ? 145.1/146.1 intocados |
| `147-fleaber-hub-anuncios-perfil-ajuda-20261104.zip` | **2026-11-04** C2 ZIP 147 ? an?ncio 1 ecr? Cancelar/Rascunho/Publicar ? f?rias BD verify ? Explorar FleaHub go ? Como funciona lan?amento ? refs intro ? 19 PASS ? **sem deploy** ? 145.1/146.1 intocados |
| `146.1-fleaber-notif-fcm-h10-badge-fix-20261104.zip` | **2026-11-04** C2 ZIP 146.1 ? FCM `notification_id`?openDestination ? badge `user_notifications` ? H10 split chat ? chatId resolve other ? 22 PASS ? **sem deploy** |
| `146-fleaber-notif-mensagens-hub-nav-20261104.zip` | **2026-11-04** C2 ZIP 146 ? notif?encomenda/artigo (n?o chat errado) ? Mensagens H10 unificadas Hub/Conta ? snack portes ? painel sino realtime ? testes 11 PASS ? **sem deploy** ? C1 Stripe/DPD intocado |
| `145.1-fleaber-post-purchase-ux-refund-fix-full-pack-20261104.zip` | **2026-11-04** C2 ZIP 145.1 ? reembolso conclu?do s? com `stripe_refunded_at` ? ZIP completo (incl. minhas_encomendas + notify-dispatch index) ? integra??o pain?is/C1 confirmada ? Deno 15 + Flutter 6 ? **sem deploy** |
| `145-fleaber-post-purchase-ux-encomendas-20261103.zip` | **2026-11-03** C2 ZIP 145 ? fecho 144 datas DD/MM/AAAA + reembolso iniciado/conclu?do ? painel p?s-compra comprador/vendedor (peso/delta/DPD/tracking) ? notif?orderId ? testes Deno 15 + Flutter 6 ? **sem deploy** ? C1 Stripe/Edges intocados |
| `144.1-fleaber-prod-integrated-test-results-20261103.zip` | **2026-11-03** C1 ZIP 144.1 ? GO-0?D PROD ? migra??es 140?142 + hotfix `updated_at` + notify allowlist ? Edges deploy ? bateria T1?T12 **PASS** ? flags OFF ? Stripe test ? DPD create OFF ? sem cron ? C2 141.x preservado |
| `144-fleaber-ponto7-emails-shipping-delta-142-20261103.zip` | **2026-11-03** C2 templates ZIP 142 ? 4 kinds delta/prazo ? allowlist + deep link ? lab 7/7 mareantiga@ ? Deno 14/14 ? **sem deploy / sem GO activa??o** ? C1 intocado |
| `141.2-fleaber-ponto7-emails-fecho-copy-e2-e3-20261103.zip` | **2026-11-03** C2 fecho copy ? E2 ajuda s? no rodap? ? E3 singular/plural ?receberes o(s) artigo(s)? ? Deno 11/11 ? **sem reenvio / sem deploy** |
| `141.1-fleaber-ponto7-emails-fecho-envio-lab-20261103.zip` | **2026-11-03** C2 fecho definitivo ? deep link obrigat?rio (sem lista) ? fail `missing_order_id` ? PT *diretamente/ativares/atual* ? focusOnly ? Deno 11 + Flutter 5 ? **lab 9/9** mareantiga@ ? **sem deploy PROD** |
| `141-fleaber-ponto7-emails-fecho-pos139-navegacao-20261103.zip` | **2026-11-03** C2 fecho p?s-139 ? sem chips Pago ? Valor da venda ? plural ? Auth bot?o=link ? **deep link orderId E1?E3** + login returnTo + ACL ? Deno 11/11 ? **sem deploy/reenvio PROD** |
| `143-fleaber-prod-integrated-test-plan-20261103.zip` | **2026-11-03** C1 ZIP 143 ? **plano** testes integrados PROD ? ops GO-0?D ? backup/rollback ? bateria T1?T12 ? **nada aplicado** ? C2 141.x preservado ? aguarda GO |
| `142-fleaber-order-weight-shipping-delta-fix-tests-20261103.zip` | **2026-11-03** C1 ZIP 142 p?s-140 ? PSD2 fee absorb default ? webhook anti-settle ? testes 23 PASS ? contratos C2 ? **141/141.1 intocados** ? sem PROD/cron/flags ON |
| `140-fleaber-order-weight-shipping-delta-impl-20261103.zip` | **2026-11-03** C1 ZIP 140 implementa??o peso/portes/delta/prazos ? selo charged ? PI Stripe delta ? gate DPD ? flags OFF ? cron OFF ? **sem PROD / sem create DPD comercial** ? C2 templates intocados |
| `135-fleaber-dpd-implementacao-prod-20261103.zip` | **2026-11-03** C1 DPD GO implementa??o PROD ? schema Rui ? tarifas C?lia BD ? peso an?ncio ? etiqueta sem stub ? admin DPD ? Edges deploy ? **create/tarifas/sync OFF** ? sem Live ? sem cobran?a nova |
| `134-fleaber-dpd-rui-registarExpedicao-qa-20261103.zip` | **2026-11-03** C1 DPD ? cURL Rui ? OAuth fresco proxy ? `registarExpedicao` S2S+S2H QA **OK** ? `Conta invalida` resolvido (`sub_account.code`) ? guias teste ? **sem PROD / sem Live / sem implementa??o** |
| `132-fleaber-dpd-mapeamento-integral-20261103.zip` | **2026-11-03** C1 DPD ZIP 132 ? mapeamento integral Android+Hub ? matriz ficheiros/Edge/RPC ? estado OK/PARCIAL/FALTA ? plano ordenado ? perguntas Rui/n?s ? **sem implementa??o / sem PROD / sem Live** |
| `131-fleaber-dpd-qa-create-20261102.zip` | **2026-11-02** C1 DPD ZIP 131 ? QA OAuth+proxy OK ? schema create mapeado ? **Conta invalida** bloqueia create 01/02 ? sem etiquetas ? create/Live **off** ? pedido Rui |
| `130-fleaber-dpd-tracking-20261102.zip` | **2026-11-02** C1 DPD ZIP 130 ? Trace API real ? UI hist?rico Android/Hub ? auth por encomenda ? Pickup no saco ? create/Live **ainda off** ? Stripe 128 intocado |
| `129-fleaber-dpd-integracao-20261102.zip` | **2026-11-02** C1 DPD ? GetPudoList Pickup ? checkout escolha loja ? Sender/shipper=vendedor ? create QA gated ? tracking stub ? **sem activa??o Live/PROD DPD** |
| `128-fleaber-implementacao-protecao-financeira-20261101.zip` | **2026-11-01** C1 ZIP 128 fase 1 ? C2C 48h ? B2C hold 14d ? chargeback freeze parcial ? risk hold ? Termos/UI ? migra??o+edges PROD ? Sandbox ? **fase 2 testes finais pendente GO** |
| `127-fleaber-validacao-legal-documental-20261101.zip` | **2026-11-01** C1 valida??o legal documental ? DR/EUR-Lex/BdP/Stripe ? C2C 48h ? B2C 14d ? hold ? resolu??o ? chargeback ? **sem implementa??o / n?o ? parecer OA** |
| `126-fleaber-plano-conformidade-protecao-financeira-20261101.zip` | **2026-11-01** C1 plano conformidade/prote??o financeira ? C2C 48h ? B2C 14d ? chargeback ? risco ? compat 123.10 ? **sem implementa??o / JUR pendente** |

| `125-fleaber-stripe-connect-diagnostico-20261101.zip` | **2026-11-01** C1 Ponto 10 diagn?stico Stripe Connect ? carril c?digo OK ? gaps live/KYC sync/chargeback ? **sem implementa??o / sem secrets** |
| `139-fleaber-ponto7-emails-correcao-final-pos138-20261103.zip` | **2026-11-03** C2 correc??o p?s-138 ? cart?o multi-artigo + foto `image_urls` ? breakdown attempt ? ?a caminho?=`dpd_accept_at` ? **sem deploy/reenvio** ? deps C1 deep-link/fotos |
| `138-fleaber-ponto7-emails-revisao-final-20261103.zip` | **2026-11-03** C2 revis?o final 9 emails ? assuntos/tom aprovados ? tipografia ? E2 pr?ximos passos ? E3 ?a caminho? s? com guia ? Auth PT sem emoji ? lab `mareantiga@` ? Auth Dashboard **n?o** aplicado |
| `133-fleaber-ponto7-emails-fecho-definitivo-20261103.zip` | **2026-11-03** C2 fecho Ponto 7 emails ? E1?E3 + gate `enviado` + guia DPD opcional ? Auth PT no repo ? deploy dry-run ? **sem Resend/DNS/Auth Dashboard/envios reais** ? DPD APIs intocadas |
| `124.1-fleaber-dpd-api-business-qa-complementar-20261101.zip` | **2026-11-01** Complemento ZIP 124 ? docs p?blicas vs API PT ? subcontas 01/02 ? perguntas Rui reduzidas ? hist?rico s? leitura ? **sem implementa??o** |
| `124-fleaber-dpd-api-business-qa-investigacao-20261030.zip` | **2026-10-30** Investiga??o API DPD Business QA ? OAuth OK VPS 135.125.254.159 ? IP casa 403 ? expedition/create confirmado ? **sem implementa??o / sem secrets** |
| `123.10-fleaber-ponto7-implementacao-emails-c2-20261101.zip` | **2026-11-01** C2 implementa??o E1?E3 HTML + Auth PT no repo + anti-dup seguro_fleaber_paid ? deploy Edge dry-run ? **sem Resend/DNS/Auth Dashboard/envios** |
| `123.9-fleaber-ponto7-auditoria-final-emails-c2.zip` | **2026-11-01** C2 auditoria final emails ? 3 comerciais aprovados ? Prote??o Fleaber ? matriz+HTML+Auth PT ? DPD opcional E3 ? **sem implementa??o / sem envios** |
| `123.8-fleaber-ponto7-auditoria-emails-prod-20261030.zip` | **2026-10-30** C1 Ponto 7 auditoria global emails PROD ? matriz A?F ? Auth EN activo ? Resend inactivo ? mockups ? **sem envios / sem altera??es** |
| `123.4-fleaber-ponto7-sql-prod-applied-20261030.zip` | **2026-10-30** Ponto 7 SQL PROD aplicado ? RPC/triggers/RLS OK ? Edge/secrets N?O ? aguarda GO Edge |
| `123.3-fleaber-ponto7-firebase-prep-prod-status-20261030.zip` | **2026-10-30** google-services integrado ? FCM v1 secrets local gitignored ? PROD: SQL/Edge ainda N?O ? aguarda GO SQL |
| `123.2-fleaber-ponto7-fcm-v1-prod-prep-20261030.zip` | **2026-10-30** Ponto 7 FCM HTTP v1 only ? plano PROD/backup/rollback ? **SQL N?O aplicado** ? aguarda GO |
| `123.1-fleaber-ponto7-implementacao-codigo-20261030.zip` | **2026-10-30** C1 Ponto 7 c?digo local ? inbox RPC ? FCM/e-mail Edge ? **PRODU??O N?O** ? falta Firebase+apply+prova TCL |
| `86.1-fleaber-e86.1-hub-web-validacao-visual-20261030.zip` | **2026-10-30 E86.1** Valida??o visual PASS ? fix saco vazio CTA + ?cone topbar ? checkout/resultados/nav OK ? SHA 9620A370? ? stamp e86.1-? ? backup _backup_ftp_pre_e86_1_20261030_112302 |
| `86-fleaber-e86-hub-web-fecho-visual-nav-20261030.zip` | **2026-10-30 E86** Fecho visual+nav: checkout 768/640 ? Home saco painel ? Resultados polish ? data-deletion FleaHub ? smoke H15?H19 ? SHA AF2059BB? ? stamp e86-? ? backup _backup_ftp_pre_e86_20261030_104434 |
| `85.4-fleaber-e85.4-bundle-buy-reuse-pending-20261030.zip` | **2026-10-30 E85.4** Ver conjunto proposta?Comprar agora: reuse pending (sem INSERT purchased) ? Stripe Sandbox ? SHA D0F9850D? ? stamp e85.4-? ? backup _backup_ftp_pre_e85_4_20261030_094518 |
| `85.3-fleaber-e85.3-buy-stripe-h10-cachebust-20261030.zip` | **2026-10-30 E85.3** E85.2 reprovado: resume Stripe?H10 (n?o ChatPage) ? web sempre ListaConversas ? SW await ? return /fleahub/# ? SHA F59CC5F0? ? stamp e85.3-? ? backup _backup_ftp_pre_e85_3_20261030_090357 |
| `123-fleaber-ponto7-notificacoes-diagnostico-20261030.zip` | **2026-10-30** C1 Ponto 7 diagn?stico ? push ausente ? inbox+chat OK parcial ? e-mail s? Auth ? P0/P1/P2 ? **sem c?digo** |
| `85.2-fleaber-e85.2-buy-pending-stripe-chat-20261030.zip` | **2026-10-30 E85.2** compra c/ proposta pendente (pending?purchased) + Stripe ? chat H10 ListaConversas ? SHA 189A5808? ? stamp e85.2-? ? backup _backup_ftp_pre_e85_2_20261030_082729 |
| `85.1-fleaber-e85.1-registo-real-checkout-20261029.zip` | **2026-10-29 E85.1** registo real (pending email ? falha) + trigger perfil + checkout evidencia consistente ? SHA 66AB8127? ? stamp e85.1-? ? backup _backup_ftp_pre_e85_1_20261029_172359 |
| `122.2-fleaber-seller-studio-p0-p1-live-panel-fecho-20261030.zip` | **2026-10-30** Fecho ponto 6 ? painel LIVE ?Pago nesta live? ? TCL ss122 ? LiveKit/Mux ended ? **sem ponto 7** |
| `85-fleaber-e85-registo-checkout-nav-20261029.zip` | **2026-10-29 E85** fix Registar loop + registo p?blico ON ? openCheckout=1 ? SHA 18D34C3B? ? prod /fleahub/ |
| `84-fleaber-e84-e82-e83-integrate-publish-20261029.zip` | **2026-10-29 E84** Integra E82+E83 ? prod /fleahub/ ? stamp e84-? ? SHA 6086EAA8? ? backup _backup_ftp_pre_117_1_prod_20261029_151420 |
| `83-fleaber-e83-checkout-desktop-visual-20261029.zip` | **2026-10-29 E83** Checkout desktop visual ? chrome partilhado ? cat?logo #/e83CheckoutCatalog ? preview /fleahub-checkout-preview/ ? PRODU??O N?O ? STOP |
| `32.9.4-hub-web-p13-independent-bundle-chats-20261029.zip` | **2026-10-29** P13.9.4 chats independentes por pedido conjunto (
orceNew) ? prova A/B/C ? preview isolada ? PRODU??O N?O ? STOP |
| `81.1-fleaber-e81-fleahub-consolidate-publish-20261029.zip` | **2026-10-29 E81** consolida??o 120.1+121.2+121.3+32.9.4 ? prod /fleahub/ ? SHA 9C5721CF? ? backup _backup_ftp_pre_e81_consolidate_20261029_131302 ? previews H11/P13 intactas |
| `82-fleaber-h14-saco-reservas-visual-preview-20261029.zip` | **2026-10-29 E82** H14 Saco/Reservas visual ? preview /fleahub-h14-preview/ ? cat?logo #/h14SacoReservasCatalog ? SHA 89A92A79? ? prod E81 intocada |
| `32.9.3-hub-web-p13-enviar-mensagem-real-login-20261029.zip` | **2026-10-29** P13.9.3 Enviar mensagem login real ? inbox Conjunto ? desconto clarificado ? preview isolada ? PRODU??O N?O ? STOP |
| `32.9.2-hub-web-p13-conjuntos-enviar-mensagem-20261029.zip` | **2026-10-29** P13.9.2 Enviar mensagem undle_total_mismatch ? expand qty + total persistido ? H10 Conjunto ? preview isolada ? PRODU??O N?O ? STOP |
| `32.9.1-hub-web-p13-conjuntos-qty-h10-20261029.zip` | **2026-10-29** P13.9.1 qty +/- ? H10 Conjunto hydrate ? dados teste ? preview isolada ? PRODU??O N?O ? STOP |
| `32.9-hub-web-p13-conjuntos-fecho-funcional-20261029.zip` | **2026-10-29** P13.9 +/- ap?s 0 ? stock=2 ? mensagem conjunto ? imagens Unsplash 404 ? calcs ? preview isolada ? PRODU??O N?O ? STOP |
| `121-fleaber-h11-resumo-remodel-preview-20261029.zip` | **2026-10-29** C1 H11 Resumo remodel ? preview /fleahub-h11-resumo-preview/ ? prod+P13 intocados ? SHA CB4D1FAE? |
| `120.1-fleaber-h15-h19-canonical-short-20261029.zip` | **2026-10-29** C1 H15 can?nico 4 passos ? elimina diverg?ncia prod vs P13 ? stamp 120.1 ? SHA 58866F8E? ? P13 intocado |
| `120-fleaber-h15-h19-info-consolidation-20261028.zip` | **2026-10-28** C1 H15?H19 fonte ?nica + data-deletion modernizado ? nav Ajuda 7 itens ? stamp 120-h15-h19 ? SHA 9864D9D6? |
| `119.9-fleaber-h11-c1-seller-professional-corrections-20261028.zip` | **2026-10-28** C1 119.9 Contactar abaixo ? perfil badge ? checkout legal discreto ? leave-request admin ? PT-PT |
| `32.8-hub-web-p13-criar-ver-fecho-c1-badge-20261028.zip` | **2026-10-28** P13.8 qty 0=retirar ? mensagens H10 ? badge cart?es ? an?ncios realistas ? preview isolada ? PRODU??O N?O ? STOP |
| `32.7-hub-web-p13-criar-ver-fecho-visual-20261028.zip` | **2026-10-28** P13.7 fecho visual Criar/Ver (stepper 0 em todos + imagens) ? 7 viewports ? preview isolada ? PRODU??O N?O ? STOP |
| `32.6-hub-web-p13-criar-ver-conjunto-viewports-20261028.zip` | **2026-10-28** P13.6 qty/cards + 7 viewports + Ver conjunto ? preview /fleahub-p13-preview/ ? PRODU??O /fleahub/ N?O ? STOP |
| `32.5-hub-web-p13-lightbox-criar-conjunto-20261027.zip` | **2026-10-27** P13.5 lightbox setas/thumbs/teclado ? Criar/Ver conjunto desktop ? an?lise Android ? preview isolada ? PRODU??O N?O ? STOP |
| `119.7-fleaber-h11-c1-seller-professional-close-20261027.zip` | **2026-10-27** C1 fecho profissionais ? badge s? verified ? suspens?o vendas ? admin review ? PDF ? P13 ? SHA 136D1503? |
| `119.6-fleaber-h11-c1-seller-professional-20261027.zip` | **2026-10-27** C1 vendedores profissionais + DPD + legais APP/WEB ? stamp 119.6.1 ? SHA D71432A6? ? APK teste |
| `119.5-fleaber-h11-c1-legal-hub-fix-20261027.zip` | **2026-10-27** C1 fix ?ndice legal vazio (ListView?Column embedded) ? SHA D9593B00? |
| `119.4-fleaber-h11-c1-legal-fecho-20261027.zip` | **2026-10-27** C1 fecho Informa??o Legal ? ?ndice 5 docs ? SelectionArea ? auditoria Privacy/Terms/Refunds/Cookies/Delete ? SHA `E9B22745?` |
| `118.7-fleaber-h11-c2-integrado-20261027.zip` | **2026-10-27** C2 publish integrado C1+Defini??es grelha ? SHA `FA5A0CFD?` |
| `118.6.1-fleaber-h11-definicoes-desktop-grid-20261027.zip` | **2026-10-27** Defini??es desktop grelha 2 col ? SHA `FA5A0CFD?` |

| `32.4-hub-web-p13-gallery-fecho-20261027.zip` | **2026-10-27** P13.4 galeria 8 fotos teste ? fix CORS cart?es ? desc max 820px ? testes smoke ? preview isolada ? PRODU??O N?O ? STOP |

| `32.3-hub-web-p13-desktop-final-20261027.zip` | **2026-10-27** P13.3 galeria 490px+contain ? desc longa Ver mais ? Criar conjunto junto ao t?tulo ? badge Profissional hook ? preview isolada ? PRODU??O N?O ? STOP |

| `32.2-hub-web-p13-desktop-visual-20261027.zip` | **2026-10-27** P13.2 desktop chrome+cart?es+envio real ? mobile app preservado ? preview isolada ? PRODU??O N?O ? STOP |

| `32.1-hub-web-p13-desktop-preview-cookies-20261027.zip` | **2026-10-27** P13.1 CTAs vs cookies + preview isolada `/fleahub-p13-preview/` ? PRODU??O `/fleahub/` N?O ? STOP |

| `32-hub-web-p13-desktop-remodel-20261027.zip` | **2026-10-27** P13 detalhe produto desktop 2 cols (=1024) ? mobile intacto ? capturas 390?1280 ? PRODUCTION WEB NO ? STOP |

**Caminho fixo:** `00-fleahub-zips/`

Todos os ZIPs de entrega v?o **sempre** para aqui.  
N?o deixar `.zip` soltos na raiz do repo.

**Ordem por fase (Unified Commerce):** `faseN` ? `faseN.1` ? `faseN.2` ? (cronol?gico).

## P?gina 01 ? Landing

| Ficheiro | O qu? |
|----------|--------|
| `01-landing-2027-proposal.zip` | Proposta V1 |
| `01-landing-2027-proposal-v2.zip` | Proposta V2 |
| `01-landing-2027-implementation.zip` | Implementa??o |
| `01-landing-2027-polish-final.zip` | Polish final |
| `01-landing-desktop-melhoria-20261023.zip` | **2026-10-23** desktop densifica??o + textos + Play Em breve + fix gravados Hub ? preview local ? PRODUCTION WEB NO ? STOP |
| `01-landing-desktop-melhoria-r2-20261023.zip` | **2026-10-23 r2** hero sem demo fict?cia + dobra compacta + cart?es 3:4 + Play Em breve ? preview local ? PRODUCTION WEB NO ? STOP |
| `01-landing-desktop-melhoria-r3-20261023.zip` | **2026-10-23 r3** identidade Fleaber clara + cart?es HomeMuxLiveCard overlay + hero/FB/how ? preview local ? PRODUCTION WEB NO ? STOP |
| `01-landing-desktop-melhoria-r3-final-20261023.zip` | **2026-10-23 r3 final** texto passo 3 + auditoria overflow (corte 1920 = captura) + shots por sec??o ? PRODUCTION WEB NO ? STOP |
| `01-landing-comercial-lancamento-20261023.zip` | **2026-10-23** landing comercial lan?amento ? CTA Explorar ? vantagens comprador ? pitch vendedor ? shots 1440/1920/390 ? PRODUCTION WEB NO ? STOP |
| `01-landing-visual-final-20261023.zip` | **2026-10-23** revis?o visual final ? Visa/MC/DPD ? cards + canais mobile ? capturas ? PRODUCTION WEB NO ? STOP |
| `01-landing-marketplace-homepage-20261025.zip` | **2026-10-25** homepage marketplace (sem 3 colunas) ? paginas Como funciona / Seguranca / Vender / Ajuda ? capturas ? PRODUCTION WEB NO ? STOP |
| `01-landing-3zones-final-20261025.zip` | **2026-10-25** homepage 3 zonas finais ? topbar pesquisa ? saco/encomendas ? docs decisoes ? PRODUCTION WEB NO ? STOP |

## P?gina 02 ? Vendedor

| Ficheiro | O qu? |
|----------|--------|
| `02-vendedor-recapture.zip` | Recaptura visual real |
| `02-vendedor-2027-proposal.zip` | Proposta desktop |
| `02-vendedor-2027-implementation.zip` | Implementa??o |
| `02-vendedor-recordings-final.zip` | Investiga??o Gravados (sem altera??o) |

## P?gina 05 ? Opini?es

| Ficheiro | O qu? |
|----------|--------|
| `05-opinioes-recapture-20261004-194136.zip` | Recaptura / auditoria (pr?-implementa??o) |
| `05-opinioes-qa-seed-20261004-205545.zip` | Seed QA + proposta layout B |
| `05-opinioes-implementacao-final-20261011.zip` | **Implementa??o visual layout B + leitura p?blica staging** ? PRODUCTION NO ? STOP |
| `05-opinioes-validacao-final-20261011.zip` | **Valida??o final:** pagina??o 10+Ver mais, stats server, seguran?a leitura p?blica, testes/capturas ? PRODUCTION NO ? STOP ? aguarda auditoria |
| `05-opinioes-correcao-tecnica-final-20261011.zip` | **Correc??o t?cnica:** cursores oldest/lowest, keyset+?ndices NULLS LAST, walks IDs, perf 10k, UI auth/ler mais/filtro ? PRODUCTION NO ? STOP ? aguarda auditoria |

## P?gina 03 ? Live

| Ficheiro | O qu? |
|----------|--------|
| `03-live-recapture-functional-map.zip` | Recaptura real + mapa funcional (sem mockup / sem c?digo) |
| `03-live-2027-proposal.zip` | Propostas visuais A (conservadora) + B (desktop 2027) ? sem implementa??o |
| `03-live-2027-final.zip` | **B FINAL** aprovada como direc??o ? refer?ncia visual + B1/B2/B3 (sem implementa??o) |
| `03-live-b1-implementation.zip` | **B1** shell desktop + chat coluna (sem B2/B3) |
| `03-live-b2-implementation.zip` | **B2** produtos coluna esquerda (sem B3) |
| `03-live-b2-1-polish.zip` | **B2.1** polish desktop (max-width + header; sem B3) |
| `03-live-b3-implementation.zip` | **B3** saco/fila desktop + verifica??o v?deo |
| `03-live-final-validation.zip` | Valida??o final Live (vertical + E2E; sem B4) |
| `03-live-vertical-source-fix.zip` | Fix v1 flag portrait encode (docs) |
| `03-live-vertical-source-fix-v2.zip` | Fix v2 adaptOutputFormat (docs; BEFORE only) |
| `03-live-vertical-source-fix-v2-validation.zip` | Captura AFTER p?s-V2 ? **PASS** Live + Replay (`d4b2b649?`) |
| `03-live-facebook-audit.zip` | Auditoria Facebook/PS/Meta vs P?gina 03 (zero c?digo) |
| `03-live-facebook-claim-audit.zip` | Regress?o UI login+claim Facebook comprador Hub (zero c?digo) |

## Unified Commerce ? Fase 4 (ordem cronol?gica)

| Ficheiro | O qu? |
|----------|--------|
| `13-fase4-existing-audit-and-delta.zip` | Auditoria existente + delta (recupera??o) |
| `13-fase4.1-checkout-payment.zip` | Checkout / payment implementado |
| `13-fase4.2-final-correction.zip` | Guest foundation + regress?o auth |
| `13-fase4.3-final-evidence.zip` | TTL guest, idem race, evid?ncia bag_changed |
| `13-fase4.4-visual-app-screenshots.zip` | **?ltimo** ? 3 screenshots app normal + ui_backend_link (bag_changed staging) |

Pr?ximo ZIP desta fase: `13-fase4.5-?`

## Auditoria desktop (c?pia)

`auditoria-desktop-2026-09-30/` ? ZIPs `01-landing` ? `14-saco-reservas` da auditoria original.

As pastas de trabalho (`01-landing-2027-?/`, `02-vendedor-?/`) continuam na raiz do repo com o conte?do descompactado; **s? os ZIPs** concentram-se aqui.
- `13-fase4.5-bag-changed-ui-prune-evidence.zip` ? Fase 4 corre??o visual: bag_changed Continuar reconstr?i checkout s? com linhas dispon?veis (Artigos 1 + KEEP + 12,36 ?) + raw attempt + regress?o.

- `14-unified-commerce-phase5-live-seller-studio-YYYYMMDD.zip` ? Fase 5 Live + Seller Studio policy/trust UX (staging).

## Unified Commerce ? Phase 5

| Ficheiro | O qu? |
|----------|--------|
| `14-unified-commerce-phase5.1-live-seller-studio-tcl-screenshots.zip` | TCL real shots A?F,H?K,O + ?ndice/veredicto PASS COM AVISO |
| `14-unified-commerce-phase5.2-final-evidence.zip` | Evid?ncia final G+L+M+N (UI?BD) + regress?o F5/F3?4 ? PHASE 5 PASS |
| `14-unified-commerce-phase5.3-final-polish.zip` | Polimento PT-PT Seller Studio + expiry history + checkout copy ? PHASE 5 PASS |
| `14-unified-commerce-phase5.4-final-visual-proof.zip` | Prova visual REAL (Recusar, B/D/E/J/K/L/R) ? G/H/I NOT CAPTURED ? PHASE 5 PARTIAL |
| `14-unified-commerce-phase5.5-product-polish-final.zip` | Polimento produto (dropdown TTL, copy humana, Por pagar) + G/H/I REAL ? **PHASE 5 FINAL = PASS** ? READY FOR PHASE 6 |
| `14-unified-commerce-phase5.6-visual-final.zip` | Corre??o visual curta (copy, selector ?, bottom Mais, PT-PT money, loading bag_changed, I2 landscape 2074?1166) ? **PHASE 5 FINAL = PASS** ? STOP |
| `15-unified-commerce-phase6-psreader-integration.zip` | PS Reader ? motor can?nico + ledger idempot?ncia + regress?o Fase 5 ? **PHASE 6 INTERNAL = PASS** ? EXTERNAL BLOCKED ? STOP |
| `15-unified-commerce-phase6.1-final-validation.zip` | Fecho t?cnico: PGRST203 claim, supersede safe, concorr?ncia real ?10 ? **PHASE 6 INTERNAL = PASS** ? STOP |
| `15-unified-commerce-phase6.2-final.zip` | Last-comment-wins (pending+guaranteed), FB ref-only identity, qty history, concorr?ncia ? **PHASE 6 INTERNAL = PASS** ? EXTERNAL BLOCKED ? READY FOR PHASE 7 ? STOP |
| `15-unified-commerce-phase6.3-checkout-final.zip` | Checkout gate (anti dup), guest FB, falso PASS corrigido ? **PHASE 6 INTERNAL = PASS** ? Studio UI NOT RUN ? READY FOR PHASE 7 ? STOP |
| `15-unified-commerce-phase6.4-concurrency-final.zip` | Race PS qty?checkout: lock can?nico nos dois lados ? **PHASE 6 INTERNAL = PASS** ? tokens revogados ? READY FOR PHASE 7 ? STOP |
| `15-unified-commerce-phase6.5-security-financial-final.zip` | Auth ownership + fee recompute p?s-sync ? guest revalidate bypass fechado ? **33 PASS / 0 FAIL** ? PRODUCTION NO ? READY FOR PHASE 7 ? STOP |
| `16-unified-commerce-phase7-buyer-fleahub-messaging.zip` | Buyer Hub + D19 Fleaber DM (garantida/expire/reject) ? **21 PASS / 0 FAIL** ? PRODUCTION NO ? READY FOR PHASE 8 ? STOP |
| `17-unified-commerce-phase7.1-final-validation.zip` | Fecho 7.1: t10 estrito, DM at?mica concorrente, anti-forge, destinat?rios ? **19 PASS / 0 FAIL** ? UI device NOT RUN ? PRODUCTION NO ? STOP |
| `18-unified-commerce-phase8-meta-integration.zip` | Fase 8: Meta Graph/webhook/Messenger prep, dedup PS+Graph, docs App Review ? IMPLEMENTA??O PASS ? STAGING harness NOT RUN (migration pending apply) ? GRAPH/MESSENGER BLOCKED EXTERNAL ? PRODUCTION NO ? STOP |
| `19-unified-commerce-phase8.1-internal-validation.zip` | Fase 8.1: migration staging aplicada, parser no bundle Edge, poll binding, webhook reclaim, Messenger claim ? harness **0 FAIL** ? GRAPH/MESSENGER BLOCKED EXTERNAL ? PRODUCTION NO ? STOP |

| `06-not-found-implementacao-e-auditoria-20261011.zip` | P?gina 06 Not Found + fecho QA P05 + auditoria read-only staging/prod UC 1?8.1 ? STOP ? sem p?gina 07 ? produ??o intocada |
| `06-fecho-final-paginas-05-06-20261011.zip` | Fecho final P06 CTA?/fleahub + P05 ordena??o ?4 inequ?voca ? STOP ? sem p?gina 07 |
| `109-fleaber-h06-not-found-light-20261026.zip` | **2026-10-26** H06 404 chrome claro H01/H02 ? capturas 390?1920 ? testes widget ? **CDN N?O** ? STOP ? sem H07 |
| `109.1-fleaber-h06-fecho-copy-desktop-20261026.zip` | **2026-10-26** H06 fecho: copy PT-PT final + capturas 1440/1920 ? **aprovada e conclu?da** ? CDN pendente ? sem H07 |

| `08-login-conta-proposta-20261011.zip` | P08 Login/Conta ? proposta visual only (sem c?digo app) ? aguarda aprova??o |

| `08-login-conta-implementacao-20261011.zip` | P08 Login/Conta implementa??o + evid?ncias ? sem deploy ? Google indispon?vel |
| `08-login-conta-fecho-final-20261012.zip` | P08 fecho final: escala 1920, scroll 390?667+cookies, Google oculto no login, testes + antes/depois ? sem deploy |
| `09-registo-implementacao-20261012.zip` | **A** P09 Registo shell P08 + capturas 390?1920 + testes ? Google oculto ? sem deploy |
| `09-auditorias-transversais-20261012.zip` | **B** PT-PT + diagn?stico preparar directo + invent?rio staging + checklist promo??o ? sem deploy |
| `09-registo-implementacao-20261013.zip` | **A** P09 revalida??o visual + capturas + c?digo ? sem deploy |
| `10-preparar-directo-performance-20261013.zip` | **B** Prep directo: p?gina 40, infinite scroll, pesquisa server, stock batch ? sem deploy |
| `11-staging-inventario-20261013.zip` | **C** Invent?rio staging (~2835 entradas) + checklist promo??o ? sem deploy |
| `12-ptpt-correcoes-20261013.zip` | **D** PT-PT valida??o + ficheiros copy ? sem deploy |
| `13-fecho-entregas-20261013.zip` | Fecho 13/10: prep keyset+refs+selec??o, invent?rio staging, bloqueios ? sem deploy |
| `14-p09-fecho-visual-20261013.zip` | **A** P09 visual: scroll 390+cookies, escala 1024/1920, copy uniforme, capturas ? sem deploy |
| `15-prep-directo-fecho-20261013.zip` | **B** Prep: prova `.or()` AND, refs `complete`, testes unit ? E2E 1000 NOT RUN ? sem deploy |
| `16-staging-inventario-fecho-20261013.zip` | **C** Invent?rio staging + plano commits + checklist ? sem deploy |
| `17-ptpt-fecho-20261013.zip` | **D** PT-PT: s? novas copy registo + pend?ncias email Auth ? sem deploy |
| `09-registo-implementacao-20261013.zip` | **A** P09 Registo revalidado (capturas + c?digo) ? sem deploy |
| `10-preparar-directo-performance-20261013.zip` | **B** Prep directo: p?gina 40, scroll infinito, pesquisa server, stock batch ? sem deploy |
| `11-staging-inventario-20261013.zip` | **C** Invent?rio staging (~2835) + checklist promo??o ? sem deploy |
| `12-ptpt-copy-20261013.zip` | **D** PT-PT valida??o + ficheiros copy ? sem deploy |

| `18-validacao-final-prep-staging-auth-20261013.zip` | Valida??o final PREP-PERF (1100 isolado PASS) + Auth API PASS COM LIMITES + invent?rio staging?prod + PT-PT mailer ? PRODUCTION NO ? STOP |

| `19-fecho-bloqueios-entrega18-20261013.zip` | Fecho bloqueios Entrega 18: prep UI binding, auth residuais/recover/returnTo, Hub publicado=fleaber.pt Sep-14, templates PT-PT prontos ? PRODUCTION NO ? STOP |

## Entrega 20 ? Auditoria Hub publicado + TCL + fecho (2026-10-14)

| Ficheiro | O qu? |
|----------|--------|
| `20-auditoria-hub-publicado-tcl-fecho-20261014.zip` | Hub publicado = pack 14-Out; P05 FAIL RPC prod; TCL NOT RUN (smoke parcial); invent?rio; PT-PT pendente; **sem** deploy/migration prod |

## Entrega 21 ? Bloqueios reais Hub (2026-10-14)

| Ficheiro | O qu? |
|----------|--------|
| `21-bloqueios-reais-hub-20261014.zip` | P05 SQL proposto (n?o aplicado); P02=RPC; P08 cookies PASS; TCL prep parcial; invent?rio |

## Entrega 22 ? P02/P05 SQL + APK prep (2026-10-15)

| Ficheiro | O qu? |
|----------|--------|
| `22-p02-p05-apk-prep-20261015.zip` | SQL m?nimo P02/P05 (n?o aplicado); APK e22prep gerado n?o instalado; TCL features novas NOT RUN |

## Ronda web ? Congelamento + P07 Hub Dev (2026-10-15)

| Ficheiro | O qu? |
|----------|--------|
| `23-hub-web-p07-congelamento-20261015.zip` | Congelamento Flutter/backend registado; P07 `/hub-dev` redesign responsivo + capturas + testes ? **sem deploy** ? Entrega 23 Flutter cancelada |

## Ronda web ? P10 Mensagens (2026-10-16)

| Ficheiro | O qu? |
|----------|--------|
| `24-hub-web-p10-mensagens-20261016.zip` | P10 Mensagens: tema Hub web + split lista/conversa =1024; before/after; login staging com dados reais ? **sem deploy** ? P11 n?o iniciado |
| `25-hub-web-p10-fecho-20261016.zip` | P10 fecho: chrome conversa escuro (cards claros); Notifica??es Hub; capturas; envio/realtime/disputa **NOT RUN** ? **sem deploy** ? sem P11 |
| `26-hub-web-p10-refinamento-final-20261016.zip` | P10 refinamento final desktop: lista =480, empty state, notif =840, thread =720; before/after 390?1920; envio/realtime **NOT RUN** ? **sem deploy** ? sem P11 |
| `27-hub-web-p11-perfil-20261016.zip` | P11 Perfil app: layout conta Hub web =768 (sec??es Conta / Compras / Vendas / Ajuda); mobile 390 claro preservado; before/after ? **sem deploy** ? sem P12 |
| `28-hub-web-p11-qa-final-20261016.zip` | P11 QA final: bottom nav mantida; breakpoints 767?1920; fix nome/retry web; matriz nav; helper/admin **NOT RUN** ? **sem deploy** ? sem P12 |
| `29-hub-web-p11-diagnostico-funcional-20261016.zip` | P11 diagn?stico: E28 login = sess?o ausente + requireAuth; com sess?o Favoritos/Encomendas PASS; nome ? API profiles; **sem c?digo** ? **sem deploy** ? sem P12 |
| `30-hub-web-p12-diagnostico-urls-20261016.zip` | P12 diagn?stico URLs: 404 nginx CONFIRMADO em `/fleahub-demo-ux` e `/joao84/live`; plano corre??o; **sem implementa??o** ? **sem deploy** ? sem P13 |
| `31-hub-web-p13-auditoria-produto-20261016.zip` | P13 Detalhe produto: auditoria c?digo + capturas 390?1920 + mapa funcional + proposta 2 cols web ? **sem implementa??o** ? **sem deploy** ? sem P14 |
| `33-fleaber-auditoria-historica-prod-staging-dpd.zip` | **E33** auditoria hist?rica prod vs staging + matriz + planos backup/reconcilia??o + DPD IP ? **READ-ONLY** ? E32 pausada ? **sem apply/backup/deploy** |
| `34-fleaber-auditoria-live-historico.zip` | **E34** auditoria LIVE prod/staging objectos+md5 + historico Cursor ? **READ-ONLY** ? E32 pausada ? **sem backup/deploy** |
- `35-fleaber-auditoria-historico-c1.zip` ? E35 auditoria hist?rica C1 (READ-ONLY) desde Hub go-live + cruzamento E34
- `36-fleaber-historico-integral-agente-principal.zip` ? E36 hist?rico integral agente principal (READ-ONLY, sem filtro C1)
- `37-fleaber-validacao-operacoes-e-diffs-prod-staging.zip` ? E37 valida??o opera??es + diffs LIVE prod/staging
- `38-fleaber-staging-pos-producao-nao-promovido.zip` ? E38 staging p?s-produ??o ainda n?o promovido (UC 1?8 + Hub)
- `39-fleaber-plano-integracao-seletiva.zip` ? E39 plano integra??o seletiva staging?prod (READ-ONLY, sem execu??o)
- `40-fleaber-resolucao-tecnica-bloqueios-e39.zip` ? E40 resolu??o t?cnica bloqueios E39 (fus?es SQL + edges remotas)
- `41-fleaber-analise-real-sql-edge-primeira-etapa.zip` ? E41 an?lise real SQL/edge primeira etapa UC F1
- `42-fleaber-validacao-final-fase1-uc.zip` ? E42 valida??o final Fase 1 Unified Commerce
- `43-fleaber-ensaio-isolado-fase1-uc.zip` ? E43 ensaio isolado Fase 1 Unified Commerce
- `44-fleaber-fecho-ensaio-isolado-fase1-uc.zip` ? E44 fecho ensaio isolado Fase 1 UC
- `45-fleaber-pacote-sql-final-fase1-reduzida.zip` ? E45 pacote SQL final Fase 1 reduzida UC
| `46-fleaber-integracao-seletiva-staging.zip` | **E46** integra??o seletiva staging ? fus?es stock/queue ? testes PASS ? prod RO ? STOP |
| `47-fleaber-validacao-funcional-reservas-staging.zip` | **E47** valida??o concorrente reservas staging ? RPC real ? 1/10 PASS ? sem correc??o ? STOP |
| `48-fleaber-expiracao-checkout-e2e-staging.zip` | **E48** expire garantidas + checkout off_platform E2E ? 4 PASS REAL ? STOP |
| `49-fleaber-financas-preparacao-producao.zip` | **E49** finan?as + fix off_platform prot staging + plano migra??o stock/AQ ? STOP |
| `50-fleaber-pacote-migracao-seletiva-final.zip` | **E50** migra??o seletiva final ? Wave A PASS ensaio ? Wave B GATE ? STOP |
| `51-fleaber-migracao-uc-pacote-executavel.zip` | **E51** pacote execut?vel UC ? Wave A+B aut?nomas ? ensaio conjunto PASS ? E49 testada ? **PRODUCTION NO** ? STOP |
| `52-fleaber-fecho-operacional-producao.zip` | **E52** fecho operacional ? compat prod RO ? activa??o gradual ? expire real PASS ? deps Edge/Web ? **PRODUCTION NO** ? STOP |
| `53-fleaber-correcao-final-gates-producao.zip` | **E53** stock quantitativo + isolamento RPCs/RLS + hash financeiro hard-fail ? cron pendente ? **SQL pronto / lan?amento N?O** ? **PRODUCTION NO** ? STOP |

| `54-fleaber-fecho-ativacao-uc.zip` | **E54** fecho activa??o ? cron SQL corrigido (pg_cron NOT RUN) ? grants superf?cie ? ciclo off/on/off PASS ? **PRODUCTION NO** ? STOP |
| `55-fleaber-pacote-operacional-definitivo.zip` | **E55** pacote operacional definitivo ? Waves A+B + gates E53 + activate E54 ? backup/GO-NO-GO/recupera??o ? expire auto NO-GO ? valida??o iso PASS ? **PRODUCTION NO** ? STOP |
| `56-fleaber-correcao-operacional-final.zip` | **E56** correc??o E55 ? wallets verify-only ? backup 0-RO/0-WRITE ? legacy LRR pending?rejected ? expire NO-GO ? **PRODUCTION NO** ? STOP |

| `57-fleaber-backup-real-producao.zip` | **E57** backup real produ??o ? **NO-GO** (falta password dump) ? s? relat?rio ? **PRODUCTION RO** ? STOP |
| `57.1-fleaber-backup-execucao-relatorio.zip` | **E57 backup execu??o** ? dump Session Pooler :5432 ? SHA-256 ? restauro parcial iso ? dados s? AppData ? STOP |
| `57.2-fleaber-validacao-restauro.zip` | **E57.2** valida??o restauro ? **GO BACKUP** ? SHA ok ? 78 erros classificados ? contagens = prod RO ? STOP |
| `58-fleaber-preparacao-wave-a.zip` | **E58** pr?-execu??o Wave A ? **READY FOR WAVE A** ? prod RO ? scripts E56 = E51 ? STOP (sem APPLY) |
| `59-fleaber-wave-a-producao.zip` | **E59** Wave A produ??o ? **WAVE A PASS** ? stock/aq fused ? request_kind ? STOP (sem Wave B) |
| `60-fleaber-preparacao-wave-b.zip` | **E60** prep Wave B ? **NO-GO** (falta backup p?s-Wave A) ? Wave A ?ntegra ? prod RO ? STOP |
| `60.1-fleaber-backup-pos-wave-a.zip` | **E60.1** backup p?s-Wave A ? **GO BACKUP** ? **READY FOR WAVE B** ? R11 PASS ? STOP |
| `61-fleaber-wave-b-producao.zip` | **E61** Wave B produ??o ? **WAVE B PASS** ? gates OFF ? UC instalado inactivo ? STOP (sem activate) |
| `62-fleaber-preparacao-ativacao-uc.zip` | **E62** prep activa??o UC ? **READY FOR CONTROLLED ACTIVATION** (Fase 1) ? expire auto Fase 2 ? prod RO ? STOP |
| `63-fleaber-ativacao-tecnica-testes-internos.zip` | **E63** backup p?s-B + activate Fase 1 + testes internos ? **PHASE 1 INTERNAL PASS** ? UC ON ? expire OFF ? STOP (sem Fase 2/p?blico) |
| `64-fleaber-testes-funcionais-app-hub.zip` | **E64** testes reais App+Hub ? **APP/HUB PARTIAL** ? live/reserva/stock ? Hub Reservar click pendente ? STOP |
| `65-fleaber-fecho-testes-comprador.zip` | **E65** fecho comprador Hub UI ? **APP/HUB PARTIAL** ? Reservar+login+saco PASS ? Aceitar seller UI FAIL ? STOP |
| `66-fleaber-fecho-aceitacao-e-checkout.zip` | **E66** guard marketplace qty em prod ? Aceitar+Recusar UI PASS ? **APP/HUB PARTIAL** ? saco/checkout pendentes ? STOP |
| `67-fleaber-fecho-saco-checkout-reservas.zip` | **E67** saco Hub p?s-aceite + checkout UI (sem pagar) + pol?ticas manual/auto/trust ? **APP/HUB PARTIAL** (aviso pre?o 0?) ? 0 lives ? STOP |
| `67.1-fleaber-correcao-preco-limpeza.zip` | **E67.1** causa RLS?0?; fix cliente via RPC bag; 5 LRR rejected; unit+RO ? **PARTIAL** (falta publish Hub) ? STOP |
| `67.2-fleaber-publicacao-controlada-hub.zip` | **E67.2** invent?rio deploy ? **BLOQUEADO** (working tree n?o isol?vel) ? **sem FTP** ? fleaber.pt = 14-Out ? STOP |
| `67.3-fleaber-base-limpa-hub.zip` | **E67.3** live=pack 14-Out ? **NO-GO** (fonte Dart do build ausente) ? sem FTP ? STOP |
| `68-fleaber-reconciliacao-final-staging-producao.zip` | **E68** matriz staging?prod ? plano H0?A1 ? **sem muta??o** ? aguarda GO plano |
| `69-fleaber-base-unificada-hub.zip` | **E69** base H0-B isolada + build candidato ? **PARTIAL** ? sem FTP ? STOP |
| `70-fleaber-validacao-candidato-hub.zip` | **E70** valida??o candidato ? saco/checkout **18 ?** ? **READY FOR GO** ? sem FTP ? STOP |
| `71-fleaber-publicacao-hub-unificado.zip` | **E71** ? **PUBLICADO** Hub E70 (`0B47DD83?`) + www completo ? smoke OK ? pend?ncias E68 mantidas ? STOP (sem E72) |
| `72-fleaber-unificacao-global-staging-producao.zip` | **E72** pacote promo??o P05/guest/PS/Meta dormant/A1 ? **AGUARDA GO** ? sem apply prod ? Hub E71 intacto ? STOP (sem E73) |
| `73-fleaber-promocao-consolidada-producao.zip` | **E73** Lote A **APLICADO** (P05+guest+Meta dormant+account deletion) ? Lote B PS **BLOQUEADO** (OCR) ? backup `20261020-071537Z` ? Hub E71 intacto ? STOP |

| `74-fleaber-fecho-global-unificacao.zip` | **E74** fecho unifica??o ? PS/OCR compat + guest fix + DM kinds + expire prep ? **sem apply prod** ? Hub E71 intacto ? STOP |
| `75-fleaber-promocao-final-e74-producao.zip` | **E75** promo??o E74 **APLICADA** (SQL 01?04 + Edge OCR v15) ? backup `20261020-085013Z` ? OCR intacto ? guest resolve ON ? checkout anon begin pendente grants ? Hub E71 intacto ? STOP |
| `76-fleaber-unificacao-final-android-hub-backend.zip` | **E76** guest checkout SQL+cliente ? APK+Hub builds ? DM UI ? testes staging ? **sem apply prod** ? Hub E71 online intacto ? STOP |
| `77-fleaber-fecho-operacional-unificacao.zip` | **E77** guest checkout **APLICADO** prod ? Android smoke 6102D ? FTP pack Hub ? live E2E NOT RUN ? STOP |
| `78-fleaber-validacao-final-unificacao.zip` | **E78** valida??o final ? **PASS COM LIMITES** ? FTP pack+backup E71 ? Android Home PASS ? guest recheck ? live E2E BLOCKED ? OCR NOT RUN ? Hub ainda E71 ? **STOP** (sem E79) |
| `79-fleaber-qa-final-producao.zip` | **E79** QA prod ? **PASS COM LIMITES** ? Hub login+Explorar ? Android Home ? guest_revoked ? live BLOCKED ? Hub CDN ainda E71 ? **STOP** (sem E80) |
| `80-fleaber-fecho-global-unificacao.zip` | **E80** fecho c?digo guest+P12+rebuilds ? CDN = ficheiro E71 no disco ? P13 N?O ? pack `E77E88A7?` ? APK `79C50DDD?` ? **STOP** |
| `81-fleaber-unificacao-fecho-definitivo.zip` | **E81** FTP exacto nginx?htaccess ? freeze+expire flags ON ? cron gate ? Meta preparada N?O activa ? Stripe OFF ? **STOP** |
| `82-fleaber-pendencias-internas-fecho.zip` | **E82** Hub CDN=E80 ? pg_cron expire `*/10` ? freeze ON ? account-deletion 404 manual ? 24 tests PASS ? **STOP** |
| `83-fleaber-auditoria-prioridades-lancamento.zip` | **2026-10-22** auditoria READ-ONLY ? ranking 14 tarefas at? lan?amento ? evid?ncias E82/DPD/Meta/QA ? Ifthenpay exclu?da ? **sem muta??o** |
| `84-fleaber-live-covers-mvp-auditoria.zip` | **2026-10-22** capas autom?ticas directos MVP ? 60 WebP + cat?logo + SQL/RPC + UI Home/Hub ? **sem apply prod** ? aguarda GO migra??o ? STOP |
| `85-fleaber-paridade-app-hub-backend-todo.zip` | **2026-10-22** To-Do ponto 3 ranking ? 32 tarefas paridade App?Hub?backend ? canvas + evid?ncias E82/E64 ? **s? auditoria** ? STOP |
| `86-fleaber-live-covers-producao-e84.zip` | **2026-10-22** capas E84 ? SQL+RPC aplicados prod ? APK Prod TCL ? pack Hub ? FTP CDN pendente ? backup meta ? STOP |

Hist?rico Waves UC (permanente): `tool/reports/UC_WAVE_HISTORICO.md`.

| `87-fleaber-hub-web-auditoria-final-dossier.zip` | **2026-10-22** dossier 14 p?ginas Hub Web ? ZIPs 87.01?87.14 ? reutilizado+capturas prod ? STOP |
| `88-fleaber-meta-integracao-preparacao.zip` | **2026-10-22** Meta/FB/IG prepara??o ? relat?rio 4 partes + checklist + refs ? **s? an?lise** ? STOP |
| `88.1-fleaber-meta-integracao-preparacao-completa.zip` | **2026-10-22** Meta **pacote completo** ? relat?rio + arquitectura Facebook Commerce + E81 + SQL Phase8 + edges Meta/OCR/claim + PS Face + C3 deletion + evid?ncias ? **s? an?lise** ? STOP |
| `88.2-fleaber-meta-bloqueio-permissoes-investigacao.zip` | **2026-10-23** causa bloqueio use cases Meta ? Login consumidor ? P?ginas ? 2.? app recomendada ? procedimento painel ? refs oficiais ? **s? an?lise** ? STOP |
| `88.3-fleaber-meta-auditoria-pos-config-2026-10-23.zip` | **2026-10-23** auditoria p?s Fleaber Pages + Login for Business ? **N?O submeter App Review** ? Live Video API adiar ? Private Reply fase 2 ? pr?ximos passos painel+c?digo ? STOP |
| `88.4-fleaber-meta-live-preflight-audit-2026-10-23.zip` | **2026-10-23** pr?-directo FB Live Novidades ? token expirado ? sem binding ? **N?O iniciar** ? BD+evidence+briefing ? sem secrets ? STOP |

## Entrega 92 ? H01 valida??o visual

| Ficheiro | O qu? |
|----------|--------|
| `92-fleaber-h01-validacao-visual-home-20261025.zip` | **2026-10-25 Entrega 92** valida??o visual H01 Home ? 10 viewports ? preview `notif-center+footer-slim` ? sem correc??es ? STOP |

## Entrega 93 ? H01 correc??o responsiva

| Ficheiro | O qu? |
|----------|--------|
| `93-fleaber-h01-responsive-compact-20261025.zip` | **2026-10-25 Entrega 93** chrome compacto ?+3 tabs ? breakpoints 720/1180 ? preview `h01-responsive-compact` ? auth capturas ? **CDN n?o publicado** ? STOP |

## Entrega 94 ? Diretos/Marketplace + topbar slim

| Ficheiro | O qu? |
|----------|--------|
| `94-fleaber-h01-diretos-marketplace-topbar-20261025.zip` | **2026-10-25 Entrega 94** tabs Diretos/Marketplace ? avatar dropdown ? preview `h01-diretos-marketplace-topbar` ? **CDN n?o publicado** ? STOP |

## Entrega 95 ? H02 perfil visual H01 (rejeitada)

| Ficheiro | O qu? |
|----------|--------|
| `95-fleaber-h02-perfil-visual-h01-20261025.zip` | **2026-10-25 Entrega 95** perfil p?blico ? **rejeitada** (panor?micos / grelhas empilhadas / opini?es no fundo) ? CDN n?o publicado |

## Entrega 96 ? H02 perfil tabs + cards H01

| Ficheiro | O qu? |
|----------|--------|
| `96-fleaber-h02-perfil-tabs-cards-h01-20261025.zip` | **2026-10-25 Entrega 96** H02: rating no header ? tabs Diretos\|Marketplace ? HomeMuxLiveCard 9:16 ? Seguir/Partilhar compactos desktop ? mobile 390 auth ? preview `#/vendedora-prod` ? **CDN n?o publicado** ? STOP |

## Entrega 97 ? H02 perfil final (dois eixos)

| Ficheiro | O qu? |
|----------|--------|
| `97-fleaber-h02-perfil-final-20261025.zip` | **2026-10-25 Entrega 97** H02 dois eixos ? 3 tabs ? MarketplaceProductCard ? H04/H05 redirect compat ? mobile 390 ? **CDN n?o publicado** ? STOP (sem Entrega 98) |

## Entrega 98 ? H02 polish tipografia / loading / demo

| Ficheiro | O qu? |
|----------|--------|
| `98-fleaber-h02-polish-type-loading-demo-20261025.zip` | **2026-10-25 Entrega 98** tipografia partilhada ? topbar bleed ? loading claro ? tabs sticky ? artigos demo realistas ? shots m390+d1440 ? **CDN n?o publicado** ? STOP |

## Entrega 99 ? H01/H02 corre??es visuais

| Ficheiro | O qu? |
|----------|--------|
| `99-fleaber-h01-h02-visual-corrections-20261025.zip` | **2026-10-25 Entrega 99** hairline 1px ? H02 MP default ? MP 5/6 vs Diretos 6 ? H01 card partilhado ? mobile compacto ? empty Opini?es ? shots m390 ? **CDN n?o publicado** ? STOP |

## Entrega 100 ? H02 acabamento visual

| Ficheiro | O qu? |
|----------|--------|
| `100-fleaber-h02-finish-spacing-footer-back-20261025.zip` | **2026-10-25 Entrega 100** gap topbar ? rodap? centrado ? Seguir\|Partilhar 60/40 ? voltar topbar ? shots m390 ? **CDN n?o publicado** ? STOP |

## Entrega 101 ? H02 valida??o final

| Ficheiro | O qu? |
|----------|--------|
| `101-fleaber-h02-final-responsive-demo-reviews-20261025.zip` | **2026-10-25 Entrega 101** hairline 14px ? rodap? sem dup Contactos ? 12 demo reviews locais ? matriz 10 viewports (67 shots) ? **CDN n?o publicado** ? H02 GO humano pendente ? STOP (sem H03) |

## Entrega 102 ? Fecho H02 + H03 Live light

| Ficheiro | O qu? |
|----------|--------|
| `102-fleaber-h02-close-h03-live-light-20261025.zip` | **2026-10-25 Entrega 102** H02 hairline s? multi-eixo + Opini?es s? ? ? H03 chrome light + 3 eixos desktop ? shots 390/768/1180/1440 ? **CDN n?o publicado** ? STOP (sem H04) |

## Entrega 103 ? H03 reformula??o

| Ficheiro | O qu? |
|----------|--------|
| `103-fleaber-h03-reform-player-axes-20261025.zip` | **2026-10-25 Entrega 103** H03 mobile = player Fleaber ? desktop eixos + marketplace compacto ? Em breve Play ? chip Facebook ? shots 360?1920 ? **CDN n?o publicado** ? STOP (sem H04) |

## Entrega 104 ? H03 revis?o final

| Ficheiro | O qu? |
|----------|--------|
| `104-fleaber-h03-final-five-zones-20261025.zip` | **2026-10-25 Entrega 104** H03 5 zonas desktop ? rail a??es ? FB permanente ? mobile + cookies ? shots 390/768/1366/1920 ? **CDN n?o publicado** ? STOP (sem H04) |

## Entrega 105 ? H03 v?deo + layout + modals

| Ficheiro | O qu? |
|----------|--------|
| `105-fleaber-h03-video-layout-modals-20261026.zip` | **2026-10-26 Entrega 105** H03 v?deo gravado restaurado ? layout apertado ? modal produto ? saco lateral ? FB copy ? matriz testes ? **CDN n?o publicado** ? STOP (sem H04) |

## Dossier 87 ? actualiza??o H01?H19 (2026-10-25)

| Ficheiro | O qu? |
|----------|--------|
| `87-fleaber-hub-web-auditoria-final-dossier.zip` | Dossier actualizado (?ndice H01?H19 + ZIPs 87.15?87.19) |
| `87.15-hub-audit-como-funciona.zip` ? `87.19-hub-audit-contactos.zip` | P?ginas informativas / Contactos (preview 390/768/1440) |

## Entrega 106 ? H03 polish final

| Ficheiro | O qu? |
|----------|--------|
| `106-fleaber-h03-polish-layout-mp-bag-20261026.zip` | **2026-10-26 Entrega 106** H03 chat fixo ? MP 2 cols/faixa ? saco claro ? modal foto ? gorjeta ? FB Consultar reservas ? **CDN n?o publicado** ? STOP |
- `107-fleaber-h03-integral-layout-controls-20261026.zip` ? H03 Entrega 107 integral (layout 1280/1920, invent?rio, saco/modal/FB/v?deo); **sem publish dom?nio**; GO pendente.

## Entrega 108 ? H03 correc??o cir?rgica (p?s-107)

| Ficheiro | O qu? |
|----------|--------|
| `108-fleaber-h03-surgical-desktop-bag-modal-20261026.zip` | **2026-10-26 Entrega 108** H03 5 zonas flex ? chat +18?22% ? saco light drawer ? modal TESTE 05 foto ? painel FB/saco ? **CDN n?o publicado** ? STOP |

## H03 ? Live (108.1)

| `108.1-fleaber-h03-bag-chat-contrast-20261026.zip` | **2026-10-26** H03 108.1 saco contraste real (E63 pendente+aceite) + chat light ? preview local ? PRODUCTION WEB NO ? STOP |

## Publica??o produ??o 108b (2026-10-26)

| `backup-prod-fleahub-stamp106-pre-108b-20261026.zip` | **Backup CDN stamp 106** antes de publicar 108b ? rollback |
| Pack publicado | `h03-entrega108b-bag-chat-2026-10-26` ? SHA `BBA2E5C2?E03E` ? relat?rio `tool/reports/fleahub_publish_108b_2026-10-26/` |

## Auth H08/H09/Recupera??o ? auditoria 108b

| `110-fleaber-auth-h08-h09-recup-audit-20261026.zip` | **2026-10-26** auditoria conjunta Login+Registo+Esqueci+Nova senha ? prints 1440/390 prod 108b ? hist?rico 87.08/87.09 ? **sem c?digo** |

## Auth uniformiza??o H08/H09/Recupera??o

| `111-fleaber-auth-h08-h09-recup-uniform-20261026.zip` | **2026-10-26** uniformiza??o visual Login+Registo+Esqueci+Nova ? preview :7380 ? **CDN N?O** ? STOP |

## H11 ? Perfil app (conta autenticada)

| Ficheiro | O qu? |
|----------|--------|
| `111-fleaber-h11-perfil-desktop-redesign-20261026.zip` | **2026-10-26** redesenho desktop (header+sidebar+cart?es claros) + mobile tema branco ? capturas 1440/1920/390 ? PRODUCTION WEB NO ? STOP |

| `111.1-fleaber-auth-recup-split-desktop-20261026.zip` | **2026-10-26** Esqueci+Nova com split desktop igual Login/Registo ? preview :7380 ? **CDN N?O** ? STOP |

## H11 ? Perfil app ? arquitectura navega??o (planeamento)

| Ficheiro | O qu? |
|----------|--------|
| `112-fleaber-h11-perfil-nav-architecture-plan-20261026.zip` | **2026-10-26** invent?rio 16 op??es + extras + tabela t?cnica + menu definitivo + excep??es ? **s? planeamento** ? sem c?digo ? PRODUCTION WEB NO ? STOP |

## H10 ? Mensagens ? auditoria visual (pr?-implementa??o)

| Ficheiro | O qu? |
|----------|--------|
| `114-fleaber-h10-mensagens-audit-visual-20261026.zip` | **2026-10-26** invent?rio 17 fam?lias F1?F17 + matriz cores + contraste + proposta layout + estrat?gia capturas + riscos ? ref 87.10 ? **sem c?digo** ? PRODUCTION WEB NO ? STOP ? pendente auth 111.1 (bordas NovaSenha + cookies) registado ? parte |

## H11 ? Perfil app ? shell desktop (implementa??o)

| Ficheiro | O qu? |
|----------|--------|
| `113-fleaber-h11-perfil-desktop-shell-20261026.zip` | **2026-10-26** menu lateral + painel conte?do real full-width ? embeds 16 op??es ? capturas 1280?2560/390 ? PRODUCTION WEB NO ? STOP |

## H10 ? Mensagens tema branco (implementa??o)

| Ficheiro | O qu? |
|----------|--------|
| `115-fleaber-h10-mensagens-tema-branco-20261026.zip` | **2026-10-26** H10 Mensagens tema branco + cat?logo 17 fam?lias ? preview :7380 ? **CDN N?O** ? STOP |

## H10 ? Mensagens acabamento visual 115.1

| Ficheiro | O qu? |
|----------|--------|
| `115.1-fleaber-h10-mensagens-polish-visual-20261026.zip` | **2026-10-26** cabe?alho+cart?o artigo+composer+tabs+17 fam?lias MD5 ?nicos ? preview :7380 ? **CDN N?O** ? STOP |

| `113.1-fleaber-h11-perfil-shell-fix-publish-20261026.zip` | **2026-10-26** H11 Perfil shell fix + 16 sec??es distintas + publish Prod stamp h11-perfil-shell-113.1 ? hash CBF59FFA? |

- `115.2-fleaber-h10-mensagens-header-demo-envio-20261026.zip` ? H10 115.2: cabe?alho original, demo 17 fam?lias, fix envio (sem publish).

- `116-fleaber-h10-mensagens-mockup-b-conversa-real-20261026.zip` ? H10 116 Mockup B desktop + conversa real TESTE COMPLETO (sem publish layout).

- `116.1-fleaber-h10-mensagens-conta-mariana-botoes-20261026.zip` ? H10 116.1: conversa na conta mareantiga + Comprar/Proposta (sem publish).

| `113.2-fleaber-h11-perfil-uniform-data-fix-20261026.zip` | **2026-10-26** H11 Perfil 113.2 ? dados preenchidos, f?rias/saldo/encomendas/favoritos/legal in-pane, stamp h11-perfil-shell-113.2 ? hash 9275B3A3? |

| `114-fleaber-fleahub-nav-consolidate-20261026.zip` | **2026-10-26** Consolida??o nav FleaHub ? p?s-login/Home nova, alias /homePage?/fleahub, preserva H10 ? hash 48EB8A10? |

- `117-fleaber-h10-mensagens-acabamento-visual-20261026.zip` ? H10 Mensagens acabamento visual + artigo realista + conjunto/imagem (116.1+).

| `114.1-fleaber-fleahub-account-nav-h11-20261026.zip` | **2026-10-26** Nav Conta?H11 sec??es; cart?o encomendas; redirects legacy ? hash E0712EFB? |
| `h10-mensagens-117.1-prod-2026-10-27` (stamp) | **2026-10-27** Publica??o produ??o H10 117.1 sobre base 114.1 ? backup `_backup_ftp_pre_117_1_h10_20261027_055614` ? fix ?at? ?? ? PRODUCTION WEB YES |

| `114.2-fleaber-fleahub-account-nav-final-20261027.zip` | **2026-10-27** Nav Conta H11 final; mobile sem shell comprimido; legais; matriz Prod ? hash 50D9F5AA? |

| `118-fleaber-h11-visual-g1-20261027.zip` | **2026-10-27** H11 visual G1 (defini??es/encomendas/resultados embutidos) ? hash 1E0FDB72? |

| `118.1-fleaber-h11-novo-anuncio-criar-20261027.zip` | **2026-10-27** Novo an?ncio desktop 1 p?gina + di?logo Criar ? stamp h11-novo-anuncio-criar-118.1 ? hash 1E0FDB72? ? PRODUCTION WEB YES |

| `118.1-fleaber-h11-visual-g1-publish-fix-20261027.zip` | **2026-10-27** H11 Visual G1 fecho publica??o ? cache-bust `?v=118.1-visual-g1` ? stamp C2 ? capturas mobile 4 sec??es + 6 tabs ? SHA `1E0FDB72?` |

| `118.1-fleaber-h11-novo-anuncio-criar-20261027.zip` | **2026-10-27** 118.1 FIX form desktop 580/2col + Criar ancorado ? stamp 118.1-fix ? hash 980B2434? ? mobile captures ? PRODUCTION YES |

| `118.2-fleaber-h11-novo-anuncio-drafts-20261027.zip` | **2026-10-27** Novo an?ncio rascunhos + nav Voltar/Cancelar + picker fotos desktop nativo + polish 30/70 ? migra??o `is_draft` ? stamp `h11-novo-anuncio-drafts-118.2` ? SHA `10A847B5?` ? capturas mobile ? PRODUCTION YES |

| `118.5-fleaber-h11-novo-anuncio-desktop-20261027.zip` | **2026-10-27** Fecho visual Novo an?ncio: topbar Hub desktop, form 1040px 2 colunas, bot?es rodap? Cancelar/Rascunho/Publicar; mobile qty helper + chip Rascunhos; stamp `h11-novo-anuncio-desktop-118.5` ? SHA `97C81EC6?` ? PRODUCTION YES |
| `118.6-fleaber-h11-visual-restantes-20261027.zip` | **2026-10-27** H11 visual restantes: Saldo, FleaHub in-pane, Descontos, F?rias toast, Refer?ncias (?1 reserva?), Equipa convite in-pane, Ajuda (sem Explorar sidebar + Como funciona); mobile captures; stamp `h11-visual-restantes-118.6` ? SHA `FA5A0CFD?` ? PRODUCTION YES |
| `118.8.2-fleaber-h11-c2-visual-fix-20261027.zip` | **2026-10-27** C2 polish: descontos maxWidth 920; refs filtros Wrap mobile (sem chips cortados) + ?1 reserva?; saldo hist?rico maxWidth + sem IDs t?cnicos; f?rias legibilidade; stamp `h11-c2-visual-fix-118.8.2` ? SHA `219A10EE?` ? PRODUCTION YES |
| `118.9-fleaber-h11-c1-validacao-5paginas-20261027.zip` | **2026-10-27** C1 valida??o 5 p?ginas: capturas mobile limpas + interm?dios 600/768/900/1024/1280; bug captura Hist?rico diagnosticado; saldo 0? real; mid polish descontos/equipa; Prod na entrega = C2 `119.1` (sem overwrite) |
| `119.2-fleaber-h11-c1-info-pages-20261027.zip` | **2026-10-27** C1 Como funciona / FAQ / Sobre: coluna 880px ? esquerda, tipografia, FAQ f?rias=ocultar, link Livro Reclama??es; sem Info legal; stamp `h11-c1-info-pages-119.2` ? SHA `89A748B3?` ? PRODUCTION YES |
| `119.3-fleaber-h11-c1-faq-scroll-20261027.zip` | **2026-10-27** C1 FAQ: sem scroll interno ? lista cresce, scroll s? do painel; multi-aberto; stamp `h11-c1-faq-scroll-119.3` ? SHA `2777A61D?` ? PRODUCTION YES |

| ``118.3-fleaber-h11-fecho-visual-nav-20261027.zip`` | **2026-10-27** H11 fecho ? grelha Defini??es ? seta/encomendas?H10 ? Resultados nav+KPI ? SHA ``313AF9FB?`` |
| `118.4-fleaber-h11-fecho-safe-republish-20261027.zip` | **2026-10-27** Republica??o segura H11 118.3 ? buildConfig limpo ? SHA `0D2CEE0A?` |

| `119-fleaber-midwidth-h09-h10-audit-20261027.zip` | **2026-10-27** C2 auditoria mid-width 600?1280 H09/H10/auth (+ amostra H01/H08) ? overflowX 0 ? **sem altera??es de c?digo** ? **CDN N?O** (C1 H11 activo) |

| `119.1-fleaber-midwidth-fecho-cookies-home-20261027.zip` | **2026-10-27** Fecho 119: Home 768/900/1280 carregada + cookies slot acima bottom nav (&lt;1024) ? stamp `h11-c2-midwidth-fecho-119.1` ? SHA `0699A80B?` ? PRODUCTION YES |

| `119.2.1-fleaber-fecho-1189-1191-estados-20261027.zip` | **2026-10-27** C2 fecho: 118.9 fixes j? em 119.2 ? capturas estados distintos (refs/equipa/descontos) ? **sem publish** ? SHA prod `89A748B3?` (119.2 C1) |

- `119.8-fleaber-h11-c1-seller-professional-qa-20261027.zip` ? QA visual/funcional vendedor profissional (web+TCL) + APK; stamp 119.8 SHA MATCH.

- `121.1-fleaber-h11-resumo-redesign-preview-20261029.zip` ? H11 Resumo redesign preview (hash URL + provas 1440/1280/390); sem publish /fleahub/

| `32.9.1-hub-web-p13-conjuntos-qty-h10-20261029.zip` | C2 P13: `+` desde qty 0 + H10 cabe?alho Conjunto (preview isolada) |
| `32.9.3-hub-web-p13-enviar-mensagem-real-login-20261029.zip` | **2026-10-29** P13.9.3 Enviar mensagem login real ? inbox Conjunto ? desconto clarificado ? preview isolada ? PRODU??O N?O ? STOP |
| `32.9.2-hub-web-p13-conjuntos-enviar-mensagem-20261029.zip` | **2026-10-29** P13.9.2 Enviar mensagem total_mismatch fix ? expand qty ? preview isolada ? PRODU??O N?O ? STOP |

- `121.2-fleaber-h11-resumo-fecho-visual-preview-20261029.zip` ? H11 Resumo fecho visual + t?tulo Perfil; preview isolada (sem /fleahub/)
| `121.3-fleaber-h11-public-profile-nav-preview-20261029.zip` | **2026-10-29** C1 121.3 H11 ?Ver perfil p?blico? ? HubProfilePage H02 `/{handle}` ? preview isolada ? SHA `01F6C627?` ? prod/P13 intocados |

| `122.1-fleaber-seller-studio-p0-p1-tcl-validacao-20261029.zip` | **2026-10-29** Valida??o TCL ZIP 122 ? APK `1.0.0-ss122`/122 ? prints Home/Preparar/Resultados/Saldo/Perfil ? 4 estados ? live KPI NOT RUN ? **sem Play/Hub** |
| `122-fleaber-seller-studio-p0-p1-20261029.zip` | **2026-10-29** C1 Seller Studio P0/P1 ? stubs Duplicar/Arquivar/Bundle removidos ? legendas pago nesta live ? Saldo ? teste fila alinhado ? **sem Hub/DPD/Stripe** ? ponto 6 N?O fechado |

- `85.3-fleaber-e85.3-buy-stripe-h10-cachebust-20261030.zip` ? E85.3: chat H10 p?s-Stripe (resume+narrow+return URL) + SW await + buy pending; stamp e85.3-fleahub-buy-stripe-h10-cachebust
- `123.5-fleaber-ponto7-edge-prod-push-blocked-grants-20261030.zip` ? Ponto 7 Edge PROD: secrets FCM + notify-dispatch ACTIVE; push bloqueado por GRANT service_role em device_push_tokens (sem secrets).
- `123.6-fleaber-ponto7-grant-service-role-push-proof-20261030.zip` ? Ponto 7 GO GRANT service_role + prova push FCM real TCL (chat/proposta fg/bg/killed); PASS COM AVISO shade muted; sem secrets.
- `123.7-fleaber-ponto7-fecho-push-visivel-tap-20261030.zip` ? Ponto 7 fecho PUSH: canal fleaber_alerts + DND lab; notifs vis?veis fg/bg/killed; tap abre conversa correcta; APK 1237; sem secrets.
- `123.8-fleaber-ponto7-auditoria-emails-prod-20261030.zip` ? Auditoria global emails PROD (A?F): Auth activo EN; comerciais Resend inactivos; propostas PT-PT + mockups; sem envios nem altera??es.

- `136-fleaber-dpd-qa-labels-portes-20261103.zip` ? Etiquetas QA S2S/S2H PDFs + tracking simulado + portes C?lia activas (create OFF)

- `137-fleaber-order-mgmt-weight-shipping-delta-map-20261103.zip` ? Mapeamento (sem implement): peso, checkouts, estados/prazos tipo Vinted, diferen?a portes, Stripe delta, contratos email C2


- `159.2-fleaber-dpd-go-create-qa-20261105.zip` — DPD GO create QA: anuncio teste, fixes proxy/ref/profiles, etiquetas Pickup+Home, UI deposito vendedor, guiao manual.

- `159.3-fleaber-dpd-go-create-fecho-20261105.zip` — Fecho DPD GO create QA: PDF Storage Fleaber, create OFF, APK 1593 dropoff, compra Hub+etiqueta.

- `159.4-fleaber-dpd-stripe-moradas-20261105.zip` — Checkout Casa/Pickup/mão, Pickup CP-only, moradas PT, diagnóstico Stripe staging.

- `159.4.1-fleaber-dpd-stripe-followup-20261105.zip` — Follow-up: live bag 3 modalidades, Stripe settle 400 staging, flag home ON.

- `170-C2-moloni-readonly-liga-20261106.zip` � ZIP 170-C2 Moloni readonly (OAuth+leituras; escritas off)
| `177-C2-amazon-importacao-massa-ready.zip` | **2026-11-09** C2 ZIP 177 · prep lote 584/625 · PASS COM AVISO · 1 LPN em falta · Moloni mock · prova 176 visivel (fix preparado) · **STOP sem publish** |
| `183-C2-diretos-amazon-moloni-multiempresa.zip` | **2026-11-09** C2 ZIP 183 · scan Amazon no directo + Moloni multiempresa sim · worker 178 intacto · **STOP** |

- `188.1-C1-android-hub-carteira-usb-proofs.zip` — ZIP 188.1 USB Redmi provas App Link/Gravados/Carteira + APK 1881 (2026-11-09)

- `189-C1-pre-redteam-readiness.zip` — Pré-Red Team: DPD PROD creds+oauth QA, Hub férias, BulkGate/Stripe docs (2026-11-09)
