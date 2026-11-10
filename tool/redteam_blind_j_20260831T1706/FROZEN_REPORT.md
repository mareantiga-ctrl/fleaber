# RED TEAM CEGO J — CHAT / REPUTAÇÃO / MEDIA / DEEP LINK
AUDITOR: REDTEAM_BLIND_J_CHAT_REPUTACAO_v1  
FROZEN_AT: 2026-08-31T17:25+01:00  
Projecto: staging `fxdknzrqjenzqcvnwqqq`  
Stripe: TEST (nenhuma captura nesta ronda) · prefixo fixtures `RTJ-20260831T1706-`  
production_touched: false  
fase4: false  
corrections_applied: false  

Probes: `tool/redteam_blind_j_20260831T1706/` (`pass1`…`pass4`, `cleanup`, `out/*.json`)

--------------------------------------------------
CONGELAMENTO
--------------------------------------------------
```
AUDITOR: REDTEAM_BLIND_J_CHAT_REPUTACAO_v1
FROZEN_AT: 2026-08-31T17:25+01:00
production_touched: false
fase4: false
corrections_applied: false
```

--------------------------------------------------
MAPA DE ATAQUE (chat / reputação / media / link)
--------------------------------------------------

| Zona | LIVE (anon / JWT) | Lente | Mentira / leak / caixa? |
|------|-------------------|-------|-------------------------|
| `chat_messages` INSERT `FLEABER_JSON_V1` kinds servidor | 403 `chat_system_card_server_only` / `kind_denied` | J1 | HOLD no INSERT |
| **UPDATE texto simples → JSON** | **200**; persiste `marketplace_bag_paid`, `raffle_prize`, `premio_rifa`, `auto_feedback_generated`, `order_paid`, `seguro_fleaber_paid` | J1 | **P1** — guard INSERT não corre no UPDATE |
| UPDATE JSON já existente | 403 `chat_system_card_immutable` | J1 | HOLD (update clássico) |
| INSERT `seguro_fleaber_paid` em `reserva_pendente` | 201; total 8888,88 € no card; order continua `reserva_pendente`, `amount_paid_cents` null | J1∩J7 | P2 visual; caixa NÃO |
| `sender_id` spoof | reescrito para JWT | J1 | HOLD |
| buyer2 INSERT/SELECT chat A↔B | 403 / `[]` | J1 | HOLD |
| DELETE msg do outro | 200 body `[]` (0 rows) | J1 | HOLD |
| `reviews` INSERT alheio / seller self / sem order | 403 / 400 | J2 | HOLD |
| `reviews` dup | 409 `review_duplicate` | J2 | HOLD |
| `reviews` UPDATE stars | 200 mas stars/comment imutáveis | J2 | HOLD |
| `reviews` TABLE JWT buyer2 | `[]` (6-A na tabela) | J2 | HOLD tabela |
| `reviews_gerais` VIEW JWT buyer2 | vê `buyer_id` alheio (ex. `4b343994-…`) | J2 | P2 residual view ≠ tabela |
| anon `reviews_gerais` | 401 | J2 | HOLD |
| `hub_reviews_public.buyer_id` | coluna inexistente | J2 | HOLD |
| `fleaber_private` GET stranger / anon | 404 | J3 | HOLD |
| `fleaber_private` GET chat counterpart | seller lê `chat_uploads/{buyer}/*` (política de participante; path sem `chat_id`) | J3 | P2 prefixo por UID |
| Upload prefixo alheio | 403 | J3 | HOLD |
| PATCH `profiles.handle` | 400 `handle_immutable_use_rpc` | J4 | HOLD |
| `batata_claim_handle` buyer2 | 400 `phone_not_verified` | J4 | HOLD |
| `batata_publish_hub` buyer2 | 400 `handle_required` | J4 | HOLD |
| `refund-order` buyer2 | 403 «Sem permissão.» | J7 | HOLD |
| `refund-order` seller em pendente + card «pago» | 422 sem PaymentIntent | J7 | HOLD caixa |
| `user_notifications` INSERT (próprio ou seller) | 403 RLS | J5 | HOLD |
| `seller_device_tokens` INSERT buyer2 | 403 | J5 | HOLD |
| favorites `user_id` alheio / follows hijack | 403 | J6 | HOLD |
| favorite + unlist | JWT deixa de ver o produto (`[]`) | J6 | HOLD leitura |
| `live_messages` tip/chat ended | 403 | J1 | HOLD |
| `product_bundles` accepted JWT | 400 `bundle_products_required` | J7 | HOLD |

Actores: seller `980f4fa1-…` · buyer `bfcbeeee-…` · buyer2 `f8859e23-…` · seller2 `d7dfcde4-…` (signup lab).  
Chat A↔B: `ac2902d3-…`. Order pendente fixture (cleanup `cancelado`): `47329115-…`.

--------------------------------------------------
FINDINGS P0 / P1
--------------------------------------------------

**RTJ1706-J1-PLAIN-TO-JSON** — J1 — **P1**

O trigger `batata_chat_messages_guard_insert` recusa kinds de servidor (`marketplace_bag_paid`, `raffle_prize`, `premio_rifa`, `auto_feedback_generated`) e kinds fora da allowlist (`order_paid`).  
O trigger `batata_chat_messages_guard_update` só congela JSON **se** `OLD.text` já começa por `FLEABER_JSON_V1:`. Texto simples do próprio remetente pode ser PATCH para qualquer JSON.

Repro (JWT buyer, participante):
1. `POST chat_messages` `text="plain …"` → 201  
2. `PATCH` `text=FLEABER_JSON_V1:{"kind":"marketplace_bag_paid","total":0.01}` → 200, persistido (msg `870`)  
3. Idem `raffle_prize` (`871`), `premio_rifa` (`872`), `auto_feedback_generated` (`873`), `order_paid` (`874`), `seguro_fleaber_paid` total 99999 (`875`)

O comentário na UI do chat trata o JSON como recibo («o recibo É o JSON»). CTAs de envio/reembolso nesta ronda leram `orders` (não o card): refund stranger 403; refund da pendente 422. **Sem mint / sem captura.** Autoridade de card de sistema = P1, não P0.

--------------------------------------------------
P2 (hardening, sem P0 demonstrado)
--------------------------------------------------

**RTJ1706-J1-SEGURO-PENDING** — J1 ∩ J7  
INSERT directo (sem bypass UPDATE) de `seguro_fleaber_paid` + `reservation_order_shipped` na order fixture `47329115-…` (`reserva_pendente`, 12,34 €). Card total 8888,88 € persistiu (msg `876`). BD: status `reserva_pendente`, `amount_paid_cents` null, sem PI. Seller `refund-order` → 422.

**RTJ1706-J1-ALLOWED-LIE** — J1  
Kinds na allowlist (`seguro_fleaber_paid`, `bundle_proposal` total 0,01, `order_direct_payment_details` IBAN inventado, `chat_image` URL privada) passam no INSERT se o actor for o papel certo e houver `order_id` quando exigido. Não validam pagamento, montante nem IBAN vs perfil. Mentira do participante no fio; sem caixa.

**RTJ1706-J2-REVIEWS-GERAIS-VIEW** — J2  
6-A na tabela `reviews`: buyer2 `GET reviews` → `[]`. A view `reviews_gerais` (JWT buyer2) devolve rows com `buyer_id` que não é o caller nem o target (ex. `4b343994-…` → `30e4bc7d-…`). Anon 401 na view. Sem IBAN/telefone. Classe «buyer_id em reviews» incompleta na view, não na tabela.

**RTJ1706-J3-CHAT-UPLOADS-PREFIX** — J3  
Política `fleaber_private_select_chat_counterparty`: quem partilha um `chats` lê **todo** `chat_uploads/{outro_uid}/%` (path sem `chat_id`). Seller GET `…/chat_uploads/{buyer}/reaudit.txt` → 200 `"chat-ok"`. buyer2 / anon → 404. Sem chat partilhado, seller não lista uploads do buyer2.

--------------------------------------------------
LACUNAS HONESTAS
--------------------------------------------------

- Captura Stripe TEST não feita: nenhuma Session `cs_` nas 8 orders lab buyer↔seller; settle `checkout_return` sem `session_id` vítima. J4 deep-link Stripe não exercitado até Session alheia.
- `create-payment-intent` GET com `session_id` forjado: sem `cs_test` válido nesta ronda.
- Upload leftover `fleaber_private/chat_uploads/{buyer2}/RTJ-20260831T1706-own.json` (DELETE storage com Content-Type JSON falhou no cleanup). Conteúdo `{"rtj":"RTJ-20260831T1706"}`.
- OpenAPI `/rest/v1/` devolveu paths vazios no pass1 (Accept); inventário RPC não refeito.
- Flutter deep link `maestroSellerStudio` / `stripe-success` só lido no código (release esconde studio; settle usa metadata Stripe, não o JWT do clique). Sem prova LIVE de hijack de Session.
- INSERT `user_notifications` 403 — o cliente Flutter tenta notificar o outro UID e o erro é engolido; só triggers definer escrevem. Sem forge JWT.
- DELETE mensagem alheia: HTTP 200 representação vazia = 0 rows. Não é apagamento.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Não gasto em dual Session, offer morto, pairing ended, cancel hold, Hub paused, invite enum.  
Update JSON **clássico** (mutar card já `FLEABER_JSON_V1`): **1 repro** → `chat_system_card_immutable`.  
Reviews `buyer_id` na **tabela**: HOLD; residual só na **view** (≠ 50% dos findings).  
Classe nova P1 = bypass UPDATE de texto simples. **ATROFIA=NÃO.**

--------------------------------------------------
RESPOSTA FINAL
--------------------------------------------------
```
P0 encontrados: 0
P1 encontrados: 1
P2 encontrados: 4

Existe mentira de card de sistema no chat (kinds servidor): SIM (P1, via UPDATE)
Existe mutação de JSON já inserido: NÃO
Existe forge de review / dupla / role errado na tabela: NÃO
Existe leak buyer_id via reviews_gerais (view): SIM (P2 residual)
Existe leitura stranger de fleaber_private: NÃO
Existe leitura de chat_uploads pelo counterpart do chat: SIM (P2, por desenho largo)
Existe hijack de handle / Hub: NÃO
Existe INSERT JWT de notificação alheia: NÃO
Existe hijack favorites/follows: NÃO
Existe composição J*→caixa (refund / status pago / PI): NÃO
Existe criação líquida de dinheiro: NÃO

Lentes J1–J7: SIM
Anon Hub / storage exercitado: SIM
Último ciclo nova classe P0: NÃO
Último ciclo nova classe P1: SIM (plain→JSON)
ATROFIA (só classes fechadas): NÃO
SATURAÇÃO no poço J (caixa não abre): SIM para P0; P1 chat-card aberto
PRODUÇÃO TOCADA: NÃO
FASE 4: NÃO
corrections_applied: false

VEREDICTO: FAIL_P1
```
