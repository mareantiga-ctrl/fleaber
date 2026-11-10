# 02 — Inventário de superfícies

Inventário **inicial** para o C3 completar. Não é exaustivo ao nível de cada botão; cobre famílias e pontos de ataque.

## A. Autenticação e sessões

| Item | Onde | Notas |
|------|------|-------|
| Login email/password | `lib/pages/login/` | |
| Registo | `lib/pages/registo/` | Flag `FLEABER_PUBLIC_REGISTRATION` |
| Recuperação password | `esqueci_senha`, `nova_senha` | App Links / deep links |
| Verificar telemóvel | `phone_verify_sheet`, `PhoneVerificationService` | Depende BulkGate + Phone hook |
| Logout / sessão JWT | Supabase Auth | |

## B. Perfis e privacidade

| Item | Onde |
|------|------|
| Perfil próprio | `lib/perfil/`, Definições conta |
| Perfil vendedor público | `perfil_vendedor`, Hub `hub_profile_page` |
| Modo férias | oculta descoberta / anúncios / diretos a visitantes (app+Hub alinhados ZIP 189) |
| Handles reservados | tabela `reserved_handles` |

## C. Marketplace

| Fluxo | Superfícies |
|-------|-------------|
| Criar / editar anúncio | `seller_product_form`, sheet «Criar» (`FleaberCreateSheet`) |
| Rascunho / fotos | storage product photos |
| Favoritos | `favoritos` |
| Gestão referências | páginas vendedor |
| Stock / reservas | live bag + `live_reservation_requests` + RPCs stock |
| Bundle / conjuntos | `lib/pages/bundle/` |

## D. Checkout e encomendas

| Fluxo | Superfícies |
|-------|-------------|
| Checkout produto / bundle / live | sheets + `create-payment-intent` |
| Métodos envio | DPD Pickup, DPD Home, mão |
| Protecção Fleaber | fee_calculator + breakdown UI |
| Minhas encomendas | `minhas_encomendas` |
| Etiqueta / tracking DPD | `dpd-expedition`, `dpd-tracking` (gated) |
| Disputas / evidência | `order_disputes`, `submit-dispute-evidence` |
| Reembolso | Edge `refund-order` + RPCs `batata_*` |

## E. Mensagens e notificações

| Item | Onde |
|------|------|
| Lista conversas / chat | `lista_conversas`, `chat_page` |
| Notificações in-app | `user_notifications` |
| Push | FCM (device tokens) |
| Emails transaccionais | Auth templates + `notify-dispatch` |

## F. Carteira Stripe Connect

| Item | Onde |
|------|------|
| Saldo / pendente / retido | `lib/wallet/` + Hub seller sheet |
| Onboarding Connect | `create-connect-account` |
| Webhooks | `stripe-webhook`, `stripe-webhook-ops` |
| Levantamentos | ledger `wallet_payout_ledger` |

## G. Directos e gravações

| Item | Onde |
|------|------|
| Studio vendedor | `lib/vendedor/`, live stream vendor |
| Player comprador | `fleaber_live_player` |
| Hub live / gravados | `hub_live_page`, separador Gravados no perfil |
| Rifas | `live_raffles*` |
| Overlay / montra | **C2** — não alterar |

## H. Administração / Hub staff

| Item | Onde |
|------|------|
| Admin app | `lib/admin/` |
| Staff helpers | `lib/pages/staff/` |
| Amazon importer | `lib/amazon_importer/` (**C2**) |

## I. Tabelas de referência (amostra)

`profiles`, `products`, `orders`, `chats`, `chat_messages`, `reviews`, `favorites`, `follows`, `wallets`, `wallet_transactions`, `wallet_payout_ledger`, `fleaber_commissions`, `product_bundles`, `product_offers`, `seller_bundle_discounts`, `lives`, `live_items`, `live_messages`, `live_viewers`, `live_tips`, `live_reservation_requests`, `live_raffles`, `order_disputes`, `stripe_checkout_events`, `user_notifications`, `dpd_shipping_rates`, `fleaber_feature_flags`, `seller_trade_profiles`, `amazon_import_lots`, `moloni_companies`, `ops_env_sessions`, `signup_guard_config`, `batata_checkout_mutex`, `batata_anon_rate_limits`

## J. RLS / políticas

- Fonte de verdade e quarentena: `docs/SCHEMA_SOURCE_OF_TRUTH.md`
- Migrations com `*_rls*` e cadeia `sec_*_batata.sql`
- Foco C3: IDOR em `orders`, `chats`, `wallets`, `lives` privadas, storage paths, RPC com argumentos JWT manipuláveis

## K. Edge Functions (slugs)

`create-payment-intent`, `create-connect-account`, `create-live-tip-checkout`, `stripe-webhook`, `stripe-webhook-ops`, `refund-order`, `submit-dispute-evidence`, `dpd-expedition`, `dpd-pudo-list`, `dpd-tracking`, `dpd-tracking-sync`, `dpd-oauth-probe`, `dpd-qa-rui-create`, `pt-postal-resolve`, `send-sms-bulkgate`, `create-mux-live`, `livekit-mux-publish`, `resolve-mux-playback`, `complete-mux-live`, `livekit-egress-cleanup`, `notify-dispatch`, `ops-env-audit`, `ops-health`, `order-shipping-deadline-tick`, `request-account-deletion`, `delete-test-account`, `meta-webhook`, `meta-graph-poll`, `meta-graph-post-ingest`, `meta-messenger-outbound`, `meta-data-deletion`, `ingest-ocr-reservation`, `ps-heartbeat`, `ps-pairing-claim`, `ps-panel-log`, `moloni-api`, `amazon-importer-enrich-write`, `amazon-importer-external-research`, `amazon-importer-research`, `sec-fase2-e2e-oversell`

## L. Botões / CTAs críticos (amostra)

| CTA | Componente |
|-----|------------|
| CTAs teal principais | `FleaberPrimaryButton` |
| Sheet Criar | `FleaberCreateSheet.show` |
| Ativar carteira | copy carteira Android/Hub |
| Verificar telemóvel | Definições / registo |
| Seguir (live) | `FleaberPrimaryButton.compact` |

O C3 deve expandir esta lista por ecrã no exame numerado.
