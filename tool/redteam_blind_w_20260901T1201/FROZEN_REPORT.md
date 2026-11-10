# FROZEN_REPORT — REDTEAM_BLIND_W_CHAT_PROVAS_v1

```
AUDITOR: REDTEAM_BLIND_W_CHAT_PROVAS_v1
production_touched: false
fase4: false
VEREDICTO: FAIL_P0
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · fixtures `RTW-20260901T1201-`  
Pasta: `tool/redteam_blind_w_20260901T1201/`  
**Não corrigi. Não toquei produção. FASE 4 não iniciada.**

Actors: anon · buyer `bfcbeeee-…7c96` · seller `980f4fa1-…9588` · buyer2 `84c7af12-…6c9d`  
Compra Stripe TEST: order `e2ea277d-…5142` PI `pi_3UAqXHH7FWYUN3jh0so9MNHT` 5,90 € / 590 cents, chat `f3b6fa36-…d0ce`.  
Hold: order `65ed4032-…baed` chat `29c061de-…bd4a`.

Lentes usadas: **W1 W2 W3 W4 W5 W6 W7 W8** (8/8).

--------------------------------------------------
MISSÃO
--------------------------------------------------
Sim: no chat/JWT dá para **forjar recibo (valor)**, **apagar recibo de servidor**, **mentir cancelamento/envio/conclusão**, **reordenar a timeline**, e **meter URLs/provas que não são da encomenda**.  
Não: **B2 não lê a thread alheia**; **refund-order / release de carteira não obedecem ao chat** (Edge/RPC ignoram a mentira). Carteiras 61,10 / 18,97 inalteradas pelo chat.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibidos como paragem única — **nenhum foi o finding principal**:

| Exact | Resultado nesta ronda |
|---|---|
| plain→JSON exact | não foi o stop; JSON text imutável (403 `chat_system_card_immutable`) |
| list `chat_media` público exact | `200 []` |
| proof_url evil exact | não usei wrap `https://…/https://` |
| `#https://` exact | não usei |
| seller PATCH `resolvida` exact | PATCH 200 mas disputa ficou `status=aberta` (pass2) |

≥50%? **Não.** `ATROFIA_ABORT` não aplica.

--------------------------------------------------
P0
--------------------------------------------------

### W2-P0-001 — Comprador apaga recibo `order_paid` inserido pelo servidor
**Lente W2.** RLS `chat_messages_delete_own` + sender_id do recibo oficial = buyer.

1. `service_role` INSERT `FLEABER_JSON_V1` kind=`order_paid` sender=buyer (msg **942**).  
2. Buyer JWT `DELETE chat_messages?id=eq.942` → 201/204; SELECT posterior vazio.

O Edge `create-payment-intent` grava o recibo com `sender_id` do comprador. Quem “recebeu” o comprovativo pode apagá-lo. Auditoria do chat deixa de ter o recibo; Stripe/BD da order mantêm-se.

--------------------------------------------------
P1
--------------------------------------------------

### W1-P1-001 — Recibo Seguro com `total` JSON inventado
**Lente W1.** Guard exige captura; **não compara** `payload.total` com `orders.price_total` / `amount_paid_cents`.  
App: `_buildSeguroFleaberPaidCard` pinta `payload['total']`.

Buyer JWT, order capturada 5,90 € / 590 cents:  
`POST chat_messages` kind=`seguro_fleaber_paid` `total=4321` `label=MacBook` → **201 msg 950**.  
UI mostraria «Comprado! · 4321,00 €».

Bloqueado (correcto): mesmo kind em hold sem captura → `chat_system_card_order_not_paid`.  
`order_paid` / `marketplace_bag_paid` → `chat_system_card_server_only`.

### W6-P1-001 — Cancelamento aceite no chat sem refund Stripe
**Lentes W6 + W8.** Guard: kind `cancel_request_outcome` é seller-only + `order_id`; **não exige** order `cancelado` nem `stripe_refund_id`.  
App: `_chatShowsOrderCancelled` trata `outcome=accepted` no chat como cancelada **mesmo se a BD não estiver**; `_buildCancelOutcomeFromPayload` mostra `display` cru.

Seller JWT INSERT outcome=accepted display=`Reembolso Stripe de 9999,99 € concluído na hora.` → **201 msg 935**.  
Order **ainda `pago`**, `stripe_refund_id=null`, carteiras iguais.

Comprador `refund-order` → **403 Sem permissão.**  
Release carteira JWT → `200 false`.  
Seller `refund-order` **depois** da mentira → Edge corre na mesma (não lê o chat); nesta ronda `already_refunded` / order `cancelado`. A mentira **não** moveu dinheiro; a UI mentiu **antes** do Edge.

### W5-P1-001 — `created_at` escolhido no INSERT (inject cronologia)
Buyer JWT INSERT kind=`order_dispute_opened` `created_at=2020-01-01T00:00:00Z` → persistido **2020-01-01**. A lista do chat ordena por `created_at`. Card de disputa no topo da timeline.

### W5-P1-002 — PATCH `created_at` de card JSON
Text JSON é imutável (403). `created_at` **não**. Seller PATCH msg 935 → **2019-06-01T12:00:00Z**. Reordena o card de “cancelado/reembolsado” para o passado.

### W5-P1-003 — Cards operacional sem estado BD
Com order **pago**: seller INSERT `reservation_order_shipped`, `reservation_seller_confirmed_receipt`; buyer INSERT `reservation_order_completed` → todos **201**. Status BD continuou `pago`. A app pinta os cards (envio / receção / concluído) a partir do JSON.

### W2-P1-001 — Metadados da mensagem do outro
RLS UPDATE = qualquer participante. Guard: se `sender_id ≠ auth.uid()` só restaura **text**.  
Seller PATCH msg plain do buyer: `created_at=2018-01-01`, `is_reservation=true`; text manteve-se. Timeline/flag do outro lado reescritos.

### W2-P1-002 — Buyer DELETE do próprio card `seguro_fleaber_paid`
O recibo forjado (e qualquer recibo com sender=buyer, incluindo o da app) é apagável. 201 + linha desaparece.

### W7-P1-001 — Card conjunto fantasma (`total_eur=8888`)
kind `bundle_proposal` na allowlist **sem** `bundle_id` real nem preço.  
INSERT bundle_id=`00000000-…0777` total_eur=8888 → **201 msg 947**.  
Flutter: bundle null + pending → mostra o total do payload.

### W7-P1-002 — Conjunto aceite: JSON 7777 € vs bundle 19,20 €
Bundle real aceite `a95d3f8e-…` `total_eur=19.2` (catálogo).  
Segundo card `total_eur=7777` → **201 msg 948**.  
`BundleProposalChatCard` frozen: `total = payload['total_eur']`.

### W4-P1-001 — `proof_url` no INSERT (trigger só UPDATE)
`trg_batata_orders_guard_proof_url` = `BEFORE UPDATE OF proof_url`.  
Buyer `POST orders` `proof_url=https://evil.example/receipt.png` → persistido.

### W4-P1-002 — Order **sem** captura: qualquer esquema de URL
Hold (cents=0, sem PI): `v_paid` falso → allowlist de host não corre. Persistidos:  
`javascript:alert(1)`, `data:image/png;base64,…`, `//evil.example/p.png`, `https://fleaber.app.evil.example/…`, `https://fxdknzrqjenzqcvnwqqq.supabase.co.evil.example/…`, `%0d%0a Location`, unicode slash, backslash.  
Isto é o comprovativo MB WAY **antes** de pago.

### W4-P1-003 — Order com captura: path storage de **outro** uid
`v_paid` é true se cents>0 **ou** PI existe (mesmo após `cancelado`). Host `…supabase.co/storage/%` chega.  
PATCH `proof_url=…/order_proofs/{seller_id}/not-mine.png` → persistido. Não amarra `{auth.uid()}/{order_id}`.  
`javascript:` no mesmo estado → **403** `order_proof_url_denied` (allowlist host). Variante **não** é o wrap `#https://` exact.

### W4-P1-004 — `order_dispute_replies.proof_photos` URLs livres
Disputa fixture (JWT INSERT disputa em `pago` falhou RLS; `service_role` abriu).  
Buyer POST reply `proof_photos=[https://evil.example/stolen-iban.png, javascript:alert(1), …]` → **201**. Sem guard de URL no array. A UI carrega as fotos no thread (`BatataCachedNetworkImage`).

### W4-P1-005 — `chat_image` URL/path arbitrários
kind `chat_image` sem check de path. INSERT `url=https://example.invalid/fake-mbway-receipt.png` e `path=chat_uploads/{seller}/{chat}/secret.jpg` → 201. Flutter resolve `http` e `chat_uploads/`. (Assinar o path alheio no storage B2 **não** funcionou — 404.)

--------------------------------------------------
P2
--------------------------------------------------

### W1-P2-001 — Inbox `chats.last_message`
Participante PATCH `last_message=Compra paga pelo Seguro Fleaber — 9999,99 €` → 200. Pré-visualização da lista de conversas mente; não é o card.

### W1-P2-002 — Plain Seguro com NBSP / espaço duplo
Regex SQL `^\s*Compra( em conjunto)? paga através do Seguro Fleaber` não apanha `Compra\u00a0paga` nem `Compra  paga`. INSERT **201** msgs **925, 926**. Flutter `startsWith('Compra paga…')` também falha → bolha de texto, não card; um humano ainda lê um recibo.

### W7-P2-001 — `price_offer_outcome` órfão
Seller INSERT outcome=accepted `amount=0.01` → 201. Sem linha `product_offers`. Card de desfecho no chat sem oferta.

--------------------------------------------------
FECHADO (defesa a trabalhar)
--------------------------------------------------
- W1: `order_paid` / `marketplace_bag_paid` JWT → `server_only`. Seguro sem captura → `order_not_paid`. Plain exact legado → `chat_seguro_legacy_plain_forbidden`. Seller `seguro_fleaber_paid` → `buyer_only`. Buyer `cancel_request_outcome` → `seller_only`.
- W2: PATCH **text** de JSON → `chat_system_card_immutable`.
- W3: B2 SELECT thread → `[]`. B2 INSERT → RLS 403. anon SELECT → 401 `batata_chat_is_participant`. GraphQL → `pg_graphql extension is not enabled`. B2 disputa → `[]`.
- W4: B2 list/get/sign `order_proofs/{b1}/` → vazio / `NoSuchKey`. Traversal `../` → 404. Upload buyer → pasta `order_disputes/{seller}` → 403. OCR sem `x-device-token` → 401. `javascript:` em order **com** captura/PI → 403.
- W8: buyer `refund-order` 403. `batata_release_seller_wallet_for_order` JWT → `false`. Carteiras inalteradas pelo chat. Edge refund **não** lê mensagens.

Chat legítimo buyer/seller da order **não** foi partido (só fixtures nesta thread).

--------------------------------------------------
W8 — composição chat → caixa
--------------------------------------------------
A mentira no chat **não** libertou carteira nem reembolsou sozinha. O vendedor **pode** ainda chamar `refund-order` (seller-only, estado da order). O dano P0/P1 é **autoridade / UI / auditoria**, não mint directo via mensagem.

--------------------------------------------------
EVIDÊNCIA
--------------------------------------------------
- `probe.json` / `pass2.json` nesta pasta  
- IDs: msgs 925–926 (plain gap), 932/950 (seguro total), 935 (cancel lie, created_at 2019), 937–939 (ops cards), 940 (backdate 2020), 942 (apagada), 947–948 (bundle), 950 (4321 €)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
