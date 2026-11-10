# FROZEN_REPORT — RED TEAM CEGO M (HUB WEB / EDGE / DEEP LINK / CONNECT ORIGEM)

```
AUDITOR: REDTEAM_BLIND_M_HUB_EDGE_v1
FROZEN_AT: 2026-08-31T17:45:00Z
staging: fxdknzrqjenzqcvnwqqq
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [M1, M2, M3, M4, M5, M6, M7]
VEREDICTO: FAIL_P1
prefixo_fixtures: RTM-20260831T1802-
```

**Não corrigido. Produção não tocada. Fase 4 não iniciada.**

Provas em `tool/redteam_blind_m_20260831T1802/pass{1,2,3,4}.json`.

Anti-atrofia: Pass 1 **não** repetiu Hub paused items, invite enum, pairing ended, dual Session, mint pós-payout, nem plain→JSON. 0% dessas classes.

---

## Veredicto

A fronteira **tabela** lives/products e o **privado** `fleaber_private` aguentam: anon/JWT não lêem `lives`, produtos unlisted estão ocultos, FOMO de live não publicada devolve `live_not_public`, complete-mux / LiveKit cruzados 403, `user_id`/`tip_id` spoof recusados, ingest OCR com token fake 401, GET settle (forjado, Session de encomenda alheia, gorjeta não paga) **não captura**. Session criada ≠ crédito.

Falham superfícies **web/anon que a app trata como vitrine**:

1. **P1** — `batata_resolve_handle` devolve `profile_id` de um perfil com `hub_published=false`, **sem directo activo e invisível** em `hub_profiles_public` / `hub_profiles_discovery_public`. Basta o slug derivado do nome (`rtm-20260831t1802-s2`).
2. **P1** — o bucket público `chat_media` permite **listar a árvore** (UUIDs de utilizadores + dezenas de ficheiros) e descarregar JPEG (~3 MB) sem conhecer o URL de antemão.
3. **P2** — CORS reflecte `https://attacker.fleaber.pt` e qualquer `chrome-extension://…` (evil.com **não**). `web_return_origin` hostil **não** entra na Session Stripe (sanitize); só no log `tip_checkout_request`.
4. **P2** — `resolve-mux-playback` (anon) não exige vitrine publicada: com um `live_id` de rascunho devolve `playback_url` HLS. Discovery de directo **activo** de vitrine não publicada inclui `mux_playback_id` (decisão E0817, ainda “além do publicado”).

Não é a classe saturada (paused items / dual Session / mint payout).

---

## Contabilidade (Stripe TEST)

Nenhuma captura. Duas Checkout Sessions de gorjeta **unpaid** (não cobradas):

| Session | Montante | `live_tips.status` após GET settle |
|---------|----------|-------------------------------------|
| `cs_test_a1nl4JwatVZauQ34h8d5Sv6X1S8jKK3GBtcjYqwCGUqSU9MXneGu8Znixp` | 499,00 € | `pending` |
| `cs_test_a1uRjdlJsnutJ0FyUbp8v2cnD4V2a7FdozMUgLlGxygAVaDAZArHEmRbBD` | 1,00 € | `pending` |

GET `create-live-tip-checkout?checkout_return=success&session_id=` e GET `create-payment-intent` com os mesmos / `cs` de encomenda alheia → texto «Pagamento ainda não confirmado» (HTTP 200/402). Wallet não creditada.

---

## Findings

### RTM-M1-015 / RTM-M1-011 · M1 · P1

**Título:** Anon `batata_resolve_handle` enumera UUID de perfil com vitrine desligada e sem directo, via slug do nome.

**Actor:** anon (sem JWT).

**Passos**
1. Fixture seller2 `hub_published=false`, `handle=null`, `full_name=rtm-20260831t1802-s2`, lives `ended`, `is_live=false`.
2. `GET hub_profiles_public?id=eq.<s2>` → `[]`.
3. `GET hub_profiles_discovery_public?id=eq.<s2>` → `[]`.
4. `POST rpc/batata_resolve_handle` `p_handle=rtm-20260831t1802-s2`.

**Esperado:** `found=false` / 404 — o que a Hub não mostra não se resolve.

**Obtido:** `found=true`, `profile_id=e9c92729-ad4c-48f4-9c97-d38845a4fb45`, `hub_published=false`, `http_status=200`.

**Prova:** `pass4.json` `offline` + `pass2.json` RTM-M1-011.  
**Severidade:** P1 (oráculo de UUID / enumeração de contas “invisíveis”; Flutter não é a fronteira).

---

### RTM-M6-005 · M6 · P1

**Título:** Anon lista o bucket público `chat_media` (prefixos e UUIDs de outros users) e descarrega ficheiros.

**Actor:** anon + `apikey` anon.

**Passos**
1. `POST /storage/v1/object/list/chat_media` `prefix=""` → `live_item_photos`, `live_raffle_prize`, `product_photos`, `profile_photos`.
2. `prefix=product_photos` → 6 UUIDs (incl. comprador/vendedor de teste e outros).
3. `prefix=live_item_photos/<uuid>` → 29 JPEG.
4. `GET /storage/v1/object/public/chat_media/live_item_photos/69104e91-…/1781154945357_scaled_IMG_20260601_144232.jpg`.

**Esperado:** GET público só com URL conhecido; listagem de árvore/UUID negada.

**Obtido:** listagem 200; GET 200 `bytes=3099865` `content-type=image/jpeg`. O mesmo para `live_raffle_prize` e `profile_photos`.

**Prova:** `pass2.json` RTM-M6-005/006; `pass3.json` `product_photo_user_ids`.  
**Severidade:** P1 (enum de contas + scrape; não é `chat_uploads` privado — J).  
**Nota:** GET de foto de perfil/produto *com URL já na vitrine* pode ser intencional; o buraco é a **listagem**.

---

### RTM-M1-010 · M1 / M5 · P2

**Título:** Edge `resolve-mux-playback` anon devolve HLS sem gate de vitrine / status draft.

**Actor:** anon.

**Passos**
1. Live seller2 `status=draft`, `mux_playback_id=rtm_draft_playback_20260831T1802` (não em `hub_lives_public`).
2. `POST /functions/v1/resolve-mux-playback` `{ "live_id": "<draft>" }`.

**Esperado:** 404 / `live_not_public` (igual ao FOMO).

**Obtido:** 200 `source=live_playback_only`, `playback_url=https://stream.mux.com/rtm_draft_playback_….m3u8`. Directo ended unpublished: o mesmo padrão (`pass2` `mux_write`). Não escreveu `mux_vod_playback_id` neste caso (sem `mux_live_id` Mux real).

**Prova:** `pass1.json` RTM-M1-010.  
**Severidade:** P2 (precisa de UUID; a tabela `lives` está revogada a anon/JWT — 403/42501).

---

### RTM-M1-003 · M1 · P2

**Título:** `hub_lives_discovery_public` lista directo **activo** de vendedor com vitrine não publicada (`mux_playback_id` incluído).

**Actor:** anon.

**Passos:** seller2 `hub_published=false` + live `status=live` `is_active=true` → GET discovery por id.

**Esperado (missão M):** dados que a app esconde na vitrine completa não saem no feed.

**Obtido:** linha com `seller_handle=rtm-20260831t1802-s2`, `mux_playback_id=rtm_active_unpub_…`. Perfil discovery no mesmo estado: `location=Portugal`, `phone_verified`, `external_payments_enabled`.

**Controlo:** flag `is_live=true` **sem** live activa → discovery `[]` (E0817-1A aguenta o fantasma). FOMO RPC nessa live activa não publicada → `live_not_public` (a RPC usa `hub_lives_public`, não discovery).

**Prova:** `pass1.json` RTM-M1-003 vs `pass2.json` ghost `[]`.  
**Severidade:** P2 (produto “ao vivo na descoberta”; ainda é leak além de `hub_published`).

---

### RTM-M2-001 · M2 · P2

**Título:** CORS reflecte origens `*.fleaber.pt` e `chrome-extension://*` (não evil.com).

**Actor:** browser `Origin` header nas Edges.

**Passos:** OPTIONS/POST `create-live-tip-checkout` / `resolve-mux-playback` / GET settle gorjeta / GET `create-connect-account`.

**Esperado:** allowlist exacta alinhada a `sanitizeWebReturnOrigin` (sem `*.fleaber.pt`, sem extensão arbitrária).

**Obtido**

| Origin | `Access-Control-Allow-Origin` |
|--------|-------------------------------|
| `https://evil.com` | `https://fleaber.pt` (não reflecte) |
| `https://attacker.fleaber.pt` | **reflecte** |
| `chrome-extension://abcdefghijklmnopqrstuvwxyz` | **reflecte** |
| `https://fleaber.app` | `https://fleaber.pt` (Hub em `.app` não recebe CORS) |

GET connect `web_return_origin=https://evil.com/steal` → HTML deep link, **sem** Location evil.  
`web_return_origin=https://fleaber.pt/@evil.com` → 303 `https://fleaber.pt/wallet` (path ignorado).  
`https://127.0.0.1` → 303 `https://127.0.0.1/wallet` (allowlist localhost).  
`https://fleaber.app` → 303 `https://fleaber.app/wallet`.

**Composição:** GET settle gorjeta unpaid com `Origin: https://attacker.fleaber.pt` → `acao=https://attacker.fleaber.pt` + corpo “não confirmado” (sem captura). `tip_checkout_request` grava `web_return_origin=https://attacker.fleaber.pt`; `tip_checkout_session_created` **não** tem o campo (`pass4.json` `session_created_has_origin=false`) — sanitize no create da Session.

**Prova:** `pass1.json` CORS; `pass3.json` `connect_get` + `tip499_settle`.  
**Severidade:** P2 (subdomínio / extensão maliciosa lê respostas Edge; redirect Connect/Stripe não segue attacker).

---

## Holds (fronteira aguentou — não são findings)

| Lente | Ataque | Resultado |
|-------|--------|-----------|
| M3 | GET tip/PI settle `cs_test_rtm_forged_*` | 400 Stripe / “não confirmado” |
| M3 | B2 GET PI settle `cs_test_a1i7M1nu…` (encomenda alheia) | 402, sem captura |
| M3/M7 | GET settle Sessions gorjeta unpaid | `live_tips.status=pending` |
| M4 | `create-connect-account` `user_id=<seller>` | 400 Cannot create another user |
| M4 | `tip_id` no body | 400 Client tip_id is not allowed |
| M4 | `amount_eur=0.01` | 400 Invalid tip amount |
| M4 | ingest-ocr `x-device-token` fake, qty 99 | 401 invalid_token |
| M4 | `delete-test-account` + `user_id` seller | 403 allowlist nuke |
| M4 | `send-sms-bulkgate` anon | 200 contrato GoTrue, `Missing required headers` (não envia) |
| M4 | `meta-data-deletion` | 400 Missing signed_request |
| M5 | buyer `create-mux-live` | 403 authz |
| M5 | seller2 `complete-mux-live` / LiveKit token live A | 403 |
| M5 | `stream_key` inject (live sem key) | 400, não usa a key do cliente |
| M6 | `fleaber_private` list/GET prefixo do vendedor como buyer/B2 | `[]` / 400 NoSuchKey |
| M1 | anon/JWT `GET lives` | 401/403 permission denied |
| M1 | produto unlisted hub + REST | `[]` / 401 tabela |
| M1 | FOMO live não publicada | `live_not_public` |
| M1 | discovery só com `is_live=true` sem live real | `[]` |

`profiles_directory_public` anon: 401 (não é dump). JWT `GET profiles?id=eq.s2&select=*` → `[]` (não lê PII de perfil alheio pela tabela).

---

## Tácticas cumpridas

1. Anon Hub exercitado (views + resolve + FOMO + discovery).  
2. ≥2 Edges com origin/body hostil: `create-live-tip-checkout`, `create-connect-account`, `resolve-mux-playback`.  
3. Settle GET com `session_id` alheio e forjado (tip + payment-intent).  
4. Session gorjeta criada ≠ captura (pending).  
5. Flutter ≠ fronteira (RPC resolve + storage list + Edge mux).

---

## Retractado

**RTM-M6-008 (P0, pass2):** o prefixo listado em `fleaber_private/order_disputes` como buyer era o **próprio** UUID (`bfcbeeee-…`), não o do vendedor. Pass3: `prefix=order_disputes/<sellerId>` → `n=0` (buyer e B2). Não é finding.

**RTM-M2-005 (P1, pass3):** o origin attacker está só no evento `tip_checkout_request` (body cru). Não está em `tip_checkout_session_created`. Reclassificado como nota P2 de log, não open-redirect.

---

## Fixtures deixadas em staging

- Auth users `rtm-20260831t1802-{b2,s2}@fleaber.test` (hub não publicado).  
- Lives RTM marcadas `ended` onde o script correu `endLives`.  
- Duas Sessions Stripe TEST de gorjeta **não pagas** (expiram sozinhas).  
- Produtos `RTM-20260831T1802-*` unlisted/listed.

Não foi feito levantamento Connect nem captura. Não tocar produção.
