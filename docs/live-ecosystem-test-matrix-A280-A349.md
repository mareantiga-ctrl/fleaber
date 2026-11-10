# Matriz expandida — A280 a A349

**Área:** Mensagens · gravado · cross-pool · marketplace  
**Versão:** 1.1 · **2026-06-14**  
**Estado:** Fichas expandidas — sem implementação de testes.

Substitui a tabela compacta homónima em `live-ecosystem-test-matrix.md`.

**IDs A304–A339:** reservados na v1.0 mas vazios; preenchidos nesta expansão (mensagens FOMO + gravado estendido).

---

## A280 — Mensagem pública de reserva (`🛍️`)

| Campo | Valor |
|-------|-------|
| **ID** | A280 |
| **Nome** | Mensagem pública de reserva no chat |
| **Pré-condições** | Live `status=live`; comprador autenticado; artigo com stock e preço definido; chat público activo |
| **Passos** | 1. Comprador entra no player 2. Reserva 1 un. no carrossel 3. Abre painel chat público (comprador e vendedor) |
| **Resultado esperado** | Linha social humana «{Nome} reservou {Artigo}»; **sem** formato ERP; **sem** preço no chat público; visível para comprador e vendedor |
| **Componentes afectados** | `fleaber_live_player_widget.dart` (emit), `live_room_service.dart`, `live_system_chat_humanizer.dart`, `live_public_chat_line.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot + Unit |
| **Dados necessários** | `live_id`, `live_item_id`, buyer com `profiles.full_name`, item com `title`/`ref_code` |
| **Validar BD** | `select body, kind, user_id from live_messages where live_id=$id and kind='system' order by created_at desc limit 5` — body contém `reservou` ou emoji `🛍️` |
| **Validar UI** | Chat player: texto humanizado; vendedor studio chat público: mesma frase |

---

## A281 — Aceite de reserva: backoffice vs público

| Campo | Valor |
|-------|-------|
| **ID** | A281 |
| **Nome** | Mensagem de aceite oculta no chat público |
| **Pré-condições** | Reserva `pending`; vendedor com permissão aceitar |
| **Passos** | 1. Comprador reserva 2. Vendedor aceita 3. Comparar chat público vs painel backoffice/notas |
| **Resultado esperado** | Detalhes de aceite (prazo, ERP, «aceitaste vender») **não** no chat público; comprador vê card verde/banner saco (outros testes) |
| **Componentes afectados** | `live_system_chat_humanizer.dart` (`isVisibleInPublicChat`), RPC accept broadcast |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Unit + Bot |
| **Dados necessários** | Reserva com `status=accepted` após RPC; msg sistema associada |
| **Validar BD** | `live_messages` com body tipo aceite — pode existir como `system` |
| **Validar UI** | `LivePublicChatSystemLine.isVisibleInPublicChat(body)==false` para linhas aceite backoffice; chat público sem linha «aceitaste» |

---

## A282 — Compra: broadcast social «comprou»

| Campo | Valor |
|-------|-------|
| **ID** | A282 |
| **Nome** | Mensagem pública pós-compra |
| **Pré-condições** | Reserva `accepted` ou compra directa; pagamento `pago` (ou simular RPC broadcast) |
| **Passos** | 1. Concluir pagamento 2. `batata_live_purchase_broadcast` dispara 3. Ver chat |
| **Resultado esperado** | «{Nome} comprou {Artigo}» no chat público; sem preço/portes; prefixo `✅` normalizado pelo humanizer |
| **Componentes afectados** | `batata_live_purchase_broadcast` (SQL), `fleaber_stripe_checkout_context.dart`, humanizer |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot + Integration |
| **Dados necessários** | Order `pago`, `live_id`, buyer_id, `live_item_id` |
| **Validar BD** | `live_messages.body` like `%comprou%`; `kind='system'`; sem duplicata exacta em 5s (ver A289) |
| **Validar UI** | Chat player mostra linha social; vendedor vê igual |

---

## A283 — Preço definido: broadcast no chat

| Campo | Valor |
|-------|-------|
| **ID** | A283 |
| **Nome** | Mensagem «Preço definido» após seller definir preço |
| **Pré-condições** | Item live com preço 0 / price_pending; vendedor no catálogo |
| **Passos** | 1. Comprador tenta reservar (opcional) 2. Vendedor define preço no painel 3. Ver chat público |
| **Resultado esperado** | Broadcast sistema visível no chat; comprador pode passar a reservar/pagar; copy «Artigo — Preço» ou equivalente humanizado |
| **Componentes afectados** | `live_price_pending_batata.sql`, `live_catalog_stock_service.dart`, humanizer |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | `live_item` sem preço → update preço > 0 |
| **Validar BD** | `live_items.price` > 0; `live_messages` nova linha system com referência ao artigo |
| **Validar UI** | Chat mostra preço definido; modal comprador deixa de mostrar «Preço pendente» |

---

## A284 — FOMO última unidade

| Campo | Valor |
|-------|-------|
| **ID** | A284 |
| **Nome** | Broadcast FOMO «última unidade» |
| **Pré-condições** | Stock grosso = 1 disponível; item activo na vitrine |
| **Passos** | 1. Seller activa artigo com 1 un. 2. Trigger FOMO (stock threshold) 3. Ver chat comprador |
| **Resultado esperado** | Linha «Última unidade de {Artigo}» (humanizer aceita `Ultima`/`Última` na origem) |
| **Componentes afectados** | `live_fomo_broadcaster.dart`, humanizer |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | `batata_live_item_stock` → `available_qty=1` |
| **Validar BD** | `live_messages.body` contém `Ultima` ou `Última` |
| **Validar UI** | Chat público comprador; **não** duplicar spam (&lt;2 linhas iguais seguidas) |

---

## A285 — FOMO esgotado

| Campo | Valor |
|-------|-------|
| **ID** | A285 |
| **Nome** | Broadcast FOMO «artigo esgotou» |
| **Pré-condições** | Stock esgotado após aceite/venda; badge ESGOTADO aplicável |
| **Passos** | 1. Esgotar stock (aceite ou venda) 2. Ver chat |
| **Resultado esperado** | «{Artigo} esgotou» no chat público |
| **Componentes afectados** | `live_fomo_broadcaster.dart`, humanizer, stock RPC |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | Item `reserved_full` ou `available_qty=0` pós-aceite |
| **Validar BD** | Msg system com `esgotou` |
| **Validar UI** | Chat + badge carrossel ESGOTADO coerente |

---

## A286 — Gorjeta no chat público

| Campo | Valor |
|-------|-------|
| **ID** | A286 |
| **Nome** | Mensagem de gorjeta visível no chat |
| **Pré-condições** | Live activa; comprador com wallet/Stripe tip configurado |
| **Passos** | 1. Enviar gorjeta (P15) 2. Ver chat |
| **Resultado esperado** | Linha social com nome + valor; fallback se sem nome |
| **Componentes afectados** | `live_tip_flow.dart`, `live_tips_batata.sql`, humanizer |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | Tip row em `live_tips` ou msg `kind=tip` |
| **Validar BD** | `live_messages.kind='tip'` ou system gorjeta |
| **Validar UI** | Chat player + painel vendedor gorjetas |

---

## A287 — Cancelamento pelo comprador no chat

| Campo | Valor |
|-------|-------|
| **ID** | A287 |
| **Nome** | Mensagem de cancelamento comprador |
| **Pré-condições** | Reserva `pending` ou `accepted` |
| **Passos** | 1. Comprador remove do saco 2. Ver chat |
| **Resultado esperado** | Linha cancelamento com nome se disponível; seller **sem** Aceitar/Recusar na fila |
| **Componentes afectados** | `batata_live_bag_remove_request`, humanizer, studio queue filters |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot + Maestro |
| **Dados necessários** | Reserva `rejected` + notes `bag_removed` |
| **Validar BD** | `live_reservation_requests.status='rejected'`; notes contém `bag_removed` |
| **Validar UI** | Saco chip cancelado; fila vendedor em «Cancelados pelo comprador» |

---

## A288 — Rejeição vendedor oculta no chat público

| Campo | Valor |
|-------|-------|
| **ID** | A288 |
| **Nome** | Recusa vendedor só backoffice |
| **Pré-condições** | Reserva `pending` |
| **Passos** | 1. Vendedor rejeita 2. Ver chat público comprador |
| **Resultado esperado** | Recusa **não** aparece no chat público; comprador vê chip «Recusado» no saco |
| **Componentes afectados** | humanizer, `live_reservation_queue_service.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Unit |
| **Dados necessários** | Reserva `rejected` por seller |
| **Validar BD** | `status=rejected`; sem msg pública de recusa (ou filtrada) |
| **Validar UI** | Chat público sem linha recusa; saco com label rejeição |

---

## A289 — Dedupe compra duplicada no chat

| Campo | Valor |
|-------|-------|
| **ID** | A289 |
| **Nome** | Uma linha «comprou» por par comprador+artigo |
| **Pré-condições** | Mesmo comprador, mesmo artigo |
| **Passos** | 1. Disparar `batata_live_purchase_broadcast` 2x seguidas 2. Ver chat |
| **Resultado esperado** | UI mostra **uma** linha social; segunda suprimida por dedupe key `purchase\|nome\|item` |
| **Componentes afectados** | `live_public_chat_line.dart`, `_visibleSystemMessageIds` no player |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Unit + Bot |
| **Dados necessários** | 2 msgs system idênticas ou RPC duplicado |
| **Validar BD** | Podem existir 2 rows `live_messages` |
| **Validar UI** | Render lista chat: count visível = 1 |

---

## A290 — Prazo «5 dias» removido do chat público

| Campo | Valor |
|-------|-------|
| **ID** | A290 |
| **Nome** | Prazo de pagamento não aparece no chat público |
| **Pré-condições** | Aceite com prazo N dias na msg SQL |
| **Passos** | 1. Aceitar reserva 2. Inspeccionar body raw vs UI |
| **Resultado esperado** | Chat público **sem** «5 dias» / «tem N dias»; prazo só saco/banner privado |
| **Componentes afectados** | humanizer (strip prazo), tests `live_public_chat_line_test.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Unit |
| **Dados necessários** | System msg com substring `dias` |
| **Validar BD** | Body pode conter prazo |
| **Validar UI** | `compactFromBody` sem dias |

---

## A291 — Prazo dinâmico no banner/card (não hardcoded)

| Campo | Valor |
|-------|-------|
| **ID** | A291 |
| **Nome** | Prazo aceite reflecte valor SQL |
| **Pré-condições** | Aceite com prazo ≠ 5 dias (ex. 4d configurado) |
| **Passos** | 1. Aceitar 2. Ver card verde player e banner saco |
| **Resultado esperado** | Copy mostra prazo **real**; não sempre «5 dias» |
| **Componentes afectados** | `live_bag_sheet.dart`, player accept card, humanizer private copy |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | Reserva accepted com metadata prazo |
| **Validar BD** | Notes ou RPC retorno com prazo |
| **Validar UI** | Banner texto = prazo SQL |

---

## A292 — Copy «saco» vs «carrinho» no humanizer

| Campo | Valor |
|-------|-------|
| **ID** | A292 |
| **Nome** | Normalização «ao saco» → «ao carrinho» |
| **Pré-condições** | Msg sistema «adicionou ao saco» |
| **Passos** | 1. Trigger msg saco 2. Ver chat |
| **Resultado esperado** | UI «carrinho»; branding saco mantém-se noutros ecrãs |
| **Componentes afectados** | humanizer A2 copy |
| **Prioridade** | P3 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Unit |
| **Dados necessários** | Body com `ao saco` |
| **Validar BD** | Body original intacto |
| **Validar UI** | Texto render «carrinho» |

---

## A293 — «Adicionou ao saco» linha social

| Campo | Valor |
|-------|-------|
| **ID** | A293 |
| **Nome** | Mensagem social de adição ao saco |
| **Pré-condições** | Acção que gera msg saco (waitlist/queue) |
| **Passos** | 1. Reserva em fila 2. Ver chat |
| **Resultado esperado** | Frase humana tipo «{Nome} adicionou {Artigo} ao carrinho» |
| **Componentes afectados** | humanizer, reservation queue |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Unit |
| **Dados necessários** | System msg padrão saco |
| **Validar BD** | `live_messages` row |
| **Validar UI** | Visível chat público |

---

## A294 — Pedido acima stock: só backoffice

| Campo | Valor |
|-------|-------|
| **ID** | A294 |
| **Nome** | Alerta qty>stock oculto do chat público |
| **Pré-condições** | `requested_qty` > `available_qty` |
| **Passos** | 1. Reserva qty 2 stock 1 2. Comprador Pagar 3. Ver msgs |
| **Resultado esperado** | Msg ERP/qty_confirm **não** no chat público; card urgente vendedor (outro teste) |
| **Componentes afectados** | humanizer, studio urgent card |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Unit |
| **Dados necessários** | Notes `qty_confirm_needed` |
| **Validar BD** | Reserva com tag qty |
| **Validar UI** | `isVisibleInPublicChat==false` |

---

## A295 — Chat replay sincronizado com seek (L15)

| Campo | Valor |
|-------|-------|
| **ID** | A295 |
| **Nome** | Mensagens aparecem no instante de playback (gravado) |
| **Pré-condições** | Live `ended` com `mux_vod_playback_id`; msgs durante live com timestamps; comprador no player VOD |
| **Passos** | 1. Abrir gravado 2. Reproduzir do início 3. Seek para meio 4. Seek para fim |
| **Resultado esperado** | Msgs filtradas por `_filterMessagesForPlayback`; aparecem/desaparecem com playhead; skew Mux vs `went_live_at` compensado |
| **Componentes afectados** | `fleaber_live_player_widget.dart` (`_filterMessagesForPlayback`, `_isVodReplay`) |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | Gravado ≥5 min; msgs em t=1min, t=3min, t=5min |
| **Validar BD** | `lives.status=ended`; `mux_vod_playback_id` not null; `live_messages.created_at` ordenado |
| **Validar UI** | Aos 1min só msgs ≤1min; após seek msgs futuras ocultas |

---

## A296 — Vitrine catálogo sincronizada com replay

| Campo | Valor |
|-------|-------|
| **ID** | A296 |
| **Nome** | Highlight carrossel segue timeline gravado |
| **Pré-condições** | `live_item_show_events` gravados durante live; gravado com múltiplos «mostrar» |
| **Passos** | 1. Abrir gravado 2. Play 3. Seek pelos eventos |
| **Resultado esperado** | `_vodActiveItemId` actualiza; card correcto highlighted; sem poll activo (só eventos) |
| **Componentes afectados** | player `_vodActiveItemId`, `live_item_show_events` |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | ≥2 show events com `shown_at` |
| **Validar BD** | `select * from live_item_show_events where live_id=$id order by shown_at` |
| **Validar UI** | Carrossel highlight muda ao seek |

---

## A297 — Reservar artigo em gravado (ended)

| Campo | Valor |
|-------|-------|
| **ID** | A297 |
| **Nome** | Reserva permitida em live terminada |
| **Pré-condições** | `lives.status=ended`; item ainda com stock no pool; comprador autenticado |
| **Passos** | 1. Abrir gravado 2. Reservar no carrossel |
| **Resultado esperado** | `pending` criada; saco actualiza; **sem** chat input; msg reserva pode emitir |
| **Componentes afectados** | player guards `_isVodReplay`, `createRequest` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | `live_id` ended, stock > 0 |
| **Validar BD** | Nova row `live_reservation_requests` `status=pending` com `live_id` gravado |
| **Validar UI** | Botão Reservar activo; snack OK; saco mostra linha |

---

## A298 — Pagar / checkout em gravado

| Campo | Valor |
|-------|-------|
| **ID** | A298 |
| **Nome** | Checkout permitido em VOD |
| **Pré-condições** | Reserva `accepted` em live `ended` |
| **Passos** | 1. Abrir gravado 2. Saco → Pagar 3. Abrir checkout sheet |
| **Resultado esperado** | `LiveBagCheckoutSheet` abre; portes/seguro visíveis; Stripe pode abrir (manual) |
| **Componentes afectados** | `live_bag_sheet.dart`, `live_in_stream_checkout.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro + Manual |
| **Dados necessários** | Reserva accepted, preço > 0 |
| **Validar BD** | Reserva accepted; order eventual `reserva_pendente` |
| **Validar UI** | Sheet checkout visível; total > 0 |

---

## A299 — Gorjetas desactivadas em gravado

| Campo | Valor |
|-------|-------|
| **ID** | A299 |
| **Nome** | UX gorjeta em VOD |
| **Pré-condições** | Live ended; comprador no player |
| **Passos** | 1. Procurar CTA gorjeta 2. Tentar enviar |
| **Resultado esperado** | Tip **desactivado** ou snack «directo terminou»; sem crash |
| **Componentes afectados** | `live_tip_flow.dart`, player `_isVodReplay` guards |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | Gravado ended |
| **Validar BD** | Sem novas `live_tips` após tentativa |
| **Validar UI** | Botão ausente/desactivado |

---

## A300 — Card Home «GRAVADO» com playback

| Campo | Valor |
|-------|-------|
| **ID** | A300 |
| **Nome** | Feed Home abre gravado com HLS VOD |
| **Pré-condições** | Live `ended` com `mux_vod_playback_id`; visível no feed |
| **Passos** | 1. Home 2. Tap card GRAVADO 3. Esperar vídeo |
| **Resultado esperado** | Player VOD; badge GRAVADO; vídeo reproduz (ou spinner → play) |
| **Componentes afectados** | `home_mux_live_card.dart`, `home_live_feed_grid.dart`, `mux_playback_resolve.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro + Manual |
| **Dados necessários** | Live ended + playback_id |
| **Validar BD** | `lives.status=ended`, `mux_vod_playback_id` not null |
| **Validar UI** | Player carrega; label GRAVADO; sem crash 30s |

---

## A301 — Sessão pós-live em `/operacoesLive`

| Campo | Valor |
|-------|-------|
| **ID** | A301 |
| **Nome** | Painel operações live — KPIs sessão |
| **Pré-condições** | Live ended com vendas/reservas |
| **Passos** | 1. Vendedor → operacoesLive 2. Abrir sessão da live |
| **Resultado esperado** | KPIs vendas/reservas coerentes com BD; drill-down linhas |
| **Componentes afectados** | `live_sales_sessions_page_widget.dart`, `live_session_results_service.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | `live_id` com orders convertidas |
| **Validar BD** | Sum orders `pago` por `live_id` = KPI |
| **Validar UI** | Totais batem certo ± portes |

---

## A302 — VOD ausente — UX de erro

| Campo | Valor |
|-------|-------|
| **ID** | A302 |
| **Nome** | Gravado sem playback_id |
| **Pré-condições** | Live `ended`; `mux_vod_playback_id` null (complete-mux falhou) |
| **Passos** | 1. Abrir gravado do feed |
| **Resultado esperado** | Mensagem amigável; não spinner infinito; card Home pode mostrar sem play |
| **Componentes afectados** | `mux_playback_resolve.dart`, `live_hls_viewer.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | Live ended sem VOD |
| **Validar BD** | `mux_vod_playback_id is null` |
| **Validar UI** | Erro/placeholder; sem ANR |

---

## A303 — RLS gravados públicos (buyer select)

| Campo | Valor |
|-------|-------|
| **ID** | A303 |
| **Nome** | Comprador vê lives ended no feed |
| **Pré-condições** | `lives_ended_public_select` aplicado; live ended pública |
| **Passos** | 1. Buyer autenticado 2. Query/API feed |
| **Resultado esperado** | Row visível; player abre |
| **Componentes afectados** | `lives_ended_public_select_batata.sql`, RLS `lives` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | Live ended seller público |
| **Validar BD** | `select id from lives where status=ended` como buyer JWT |
---

## A304 — Mensagem rifa social `🎟️ Rifa:`

| Campo | Valor |
|-------|-------|
| **ID** | A304 |
| **Nome** | Broadcast rifa no chat sem prefixo duplicado |
| **Pré-condições** | Rifa activa; evento social (participação, leaderboard, etc.) |
| **Passos** | 1. Trigger broadcast rifa 2. Ver chat |
| **Resultado esperado** | Uma linha «🎟️ Rifa: …» humanizada; dedupe `raffle\|line` |
| **Componentes afectados** | `live_raffles_batata.sql`, humanizer, `live_public_chat_line_test.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Unit + Bot |
| **Dados necessários** | `live_raffles.status=active`; msg system rifa |
| **Validar BD** | `live_messages.body` like `🎟️ Rifa:%` |
| **Validar UI** | Chat sem duplicar prefixo «🎟️» duas vezes |

---

## A305 — Aceite público «ficou com o artigo»

| Campo | Valor |
|-------|-------|
| **ID** | A305 |
| **Nome** | Mensagem aceite visível no chat público (variante social) |
| **Pré-condições** | Aceite com broadcast público configurado |
| **Passos** | 1. Aceitar reserva 2. Ver chat |
| **Resultado esperado** | «{Nome} ficou com {Artigo}» **sem** prazo no público |
| **Componentes afectados** | humanizer, accept broadcast SQL |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Unit |
| **Dados necessários** | Msg accept pública |
| **Validar BD** | Body contém `ficou com` |
| **Validar UI** | Visível comprador+vendedor |

---

## A306 — Overlay comprador aceite (privado)

| Campo | Valor |
|-------|-------|
| **ID** | A306 |
| **Nome** | Copy overlay «Ficaste com {Artigo}» |
| **Pré-condições** | Reserva aceite; comprador no player live |
| **Passos** | 1. Seller aceita 2. Ver player comprador |
| **Resultado esperado** | Card verde/overlay com copy 2ª pessoa; coerente com saco; um único overlay (R1) |
| **Componentes afectados** | player accept UI, humanizer overlay parser |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | accepted + buyer no player |
| **Validar BD** | `status=accepted` |
| **Validar UI** | Um overlay; sem dialog duplicado |

---

## A307 — Compra com preço na origem — strip no público

| Campo | Valor |
|-------|-------|
| **ID** | A307 |
| **Nome** | Preço € não aparece na linha «comprou» |
| **Pré-condições** | Broadcast com preço no body SQL |
| **Passos** | 1. Compra 2. Ver chat |
| **Resultado esperado** | Só nome + artigo |
| **Componentes afectados** | humanizer |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Unit |
| **Dados necessários** | Body com `€` |
| **Validar BD** | Body pode ter preço |
| **Validar UI** | Render sem `€` |

---

## A308 — Sequência FOMO última unidade → esgotado

| Campo | Valor |
|-------|-------|
| **ID** | A308 |
| **Nome** | Duas mensagens FOMO em ordem lógica |
| **Pré-condições** | Stock 1 → 0 |
| **Passos** | 1. Última unidade 2. Venda/aceite esgota |
| **Resultado esperado** | Primeiro «última unidade», depois «esgotou»; sem spam &gt;2 |
| **Componentes afectados** | `live_fomo_broadcaster.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | Transição stock 1→0 |
| **Validar BD** | 2 msgs distintas |
| **Validar UI** | Ordem cronológica correcta |

---

## A309 — Formato ERP compactFromBody nunca público

| Campo | Valor |
|-------|-------|
| **ID** | A309 |
| **Nome** | Mensagens com `|` ou campos ERP ocultas |
| **Pré-condições** | System msg formato ERP |
| **Passos** | 1. Inserir/msg com pipes 2. Render chat |
| **Resultado esperado** | `compactFromBody` vazio ou backoffice; não listada no público |
| **Componentes afectados** | `LivePublicChatSystemLine.compactFromBody` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Unit |
| **Dados necessários** | Body ERP sample |
| **Validar BD** | Row existe |
| **Validar UI** | Ausente chat público |

---

## A310 — Deep link gravado `isLive=false`

| Campo | Valor |
|-------|-------|
| **ID** | A310 |
| **Nome** | Entrada directa VOD por URL |
| **Pré-condições** | Live ended; deep link `fleaberLivePlayer?liveId=&isLive=false` |
| **Passos** | 1. Abrir link |
| **Resultado esperado** | Modo replay; guards VOD activos |
| **Componentes afectados** | `nav.dart`, `fleaber_deep_link_service.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | `live_id` ended |
| **Validar BD** | `status=ended` |
| **Validar UI** | Sem input chat; saco OK |

---

## A311 — Player detecta ended sem hint isLive

| Campo | Valor |
|-------|-------|
| **ID** | A311 |
| **Nome** | BD `ended` força VOD mesmo com isLive=true no link |
| **Pré-condições** | Link com `isLive=true` mas BD `ended` |
| **Passos** | 1. Abrir player |
| **Resultado esperado** | `_isVodReplay=true`; não trata como live activa |
| **Componentes afectados** | player init live row |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | Mismatch link vs BD |
| **Validar BD** | `lives.status` |
| **Validar UI** | Comportamento gravado |

---

## A312 — Poll playback_id até disponível

| Campo | Valor |
|-------|-------|
| **ID** | A312 |
| **Nome** | VOD aparece após complete-mux async |
| **Pré-condições** | Live acabada de terminar; playback_id ainda null |
| **Passos** | 1. Terminar 2. Abrir gravado &lt;60s 3. Esperar |
| **Resultado esperado** | Spinner → vídeo quando ID disponível; ou retry poll |
| **Componentes afectados** | `mux_playback_resolve.dart`, player poll |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | Teardown recente |
| **Validar BD** | `mux_vod_playback_id` preenchido em ≤90s |
| **Validar UI** | Vídeo inicia |

---

## A313 — Placeholder chat gravado

| Campo | Valor |
|-------|-------|
| **ID** | A313 |
| **Nome** | Texto «Chat da gravação…» sem input |
| **Pré-condições** | Gravado sem msgs ou a carregar |
| **Passos** | 1. Abrir gravado 2. Ver área chat |
| **Resultado esperado** | Placeholder; `_showChatInput==false` |
| **Componentes afectados** | player chat panel |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | VOD |
| **Validar BD** | — |
| **Validar UI** | Sem TextField enviar |

---

## A314 — loadOlder mensagens desactivado em VOD

| Campo | Valor |
|-------|-------|
| **ID** | A314 |
| **Nome** | Não paginar histórico infinito em replay |
| **Pré-condições** | Gravado com muitas msgs |
| **Passos** | 1. Scroll chat topo |
| **Resultado esperado** | `enableOlderLoad=false`; só msgs do instante replay |
| **Componentes afectados** | player `enableOlderLoad` |
| **Prioridade** | P2 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | >50 msgs |
| **Validar BD** | — |
| **Validar UI** | Sem load infinito |

---

## A315 — Chat privado desactivado em gravado

| Campo | Valor |
|-------|-------|
| **ID** | A315 |
| **Nome** | Buyer não envia privado em VOD |
| **Pré-condições** | Gravado; UI privado existia em live |
| **Passos** | 1. Tentar abrir privado |
| **Resultado esperado** | Oculto ou read-only; sem insert |
| **Componentes afectados** | `live_private_room_service.dart`, player guards |
| **Prioridade** | P1 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | ended live |
| **Validar BD** | Sem novas `live_private_messages` |
| **Validar UI** | CTA ausente |

---

## A316 — Poll stock activo desactivado em VOD

| Campo | Valor |
|-------|-------|
| **ID** | A316 |
| **Nome** | Timer poll catálogo off em replay |
| **Pré-condições** | `_isVodReplay` |
| **Passos** | 1. Gravado 2 min |
| **Resultado esperado** | `_catalogStockPollTimer` não corre; stock actualiza só ao abrir |
| **Componentes afectados** | player timers |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | VOD |
| **Validar BD** | — |
| **Validar UI** | Qty estável sem flicker 2s |

---

## A317 — Skew Mux vs went_live_at no filtro chat

| Campo | Valor |
|-------|-------|
| **ID** | A317 |
| **Nome** | Compensação atraso início vídeo |
| **Pré-condições** | `went_live_at` anterior ao primeiro frame HLS |
| **Passos** | 1. Play t=0 2. Comparar 1ª msg visível vs timestamp real |
| **Resultado esperado** | 1ª msg alinhada ±skew configurado |
| **Componentes afectados** | `_filterMessagesForPlayback` |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | Msg nos primeiros 30s live |
| **Validar BD** | `went_live_at`, msg `created_at` |
| **Validar UI** | Msg não aparece 2min atrasada |

---

## A318 — Seek t=0: sem mensagens futuras

| Campo | Valor |
|-------|-------|
| **ID** | A318 |
| **Nome** | Replay início limpa msgs posteriores |
| **Pré-condições** | Gravado com msgs em vários instantes |
| **Passos** | 1. Seek para 0 |
| **Resultado esperado** | Lista vazia ou só msgs t≈0 |
| **Componentes afectados** | `_filterMessagesForPlayback` |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | VOD + msgs |
| **Validar BD** | — |
| **Validar UI** | Count msgs UI = subset |

---

## A319 — Seek meio: subset correcto

| Campo | Valor |
|-------|-------|
| **ID** | A319 |
| **Nome** | Mensagens acumuladas até playhead |
| **Pré-condições** | Igual A318 |
| **Passos** | 1. Seek 50% duração |
| **Resultado esperado** | Msgs com timestamp ≤ playhead |
| **Componentes afectados** | player replay filter |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | Duração conhecida |
| **Validar BD** | — |
| **Validar UI** | Msgs futuras ausentes |

---

## A320 — `live_item_show_events` → highlight

| Campo | Valor |
|-------|-------|
| **ID** | A320 |
| **Nome** | Eventos «mostrar» conduzem vitrine replay |
| **Pré-condições** | Eventos gravados na BD |
| **Passos** | 1. Replay 2. Cruzar event times com highlight |
| **Resultado esperado** | `_vodActiveItemId` = item do evento activo no instante |
| **Componentes afectados** | `live_item_show_events`, player |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | ≥2 events |
| **Validar BD** | `live_item_show_events` rows |
| **Validar UI** | Highlight = item esperado |

---

## A321 — Snack «directo terminou» ao chat em VOD

| Campo | Valor |
|-------|-------|
| **ID** | A321 |
| **Nome** | Feedback ao tentar chat live em gravado |
| **Pré-condições** | Gravado |
| **Passos** | 1. Tap área chat/input se visível |
| **Resultado esperado** | Snack informa; não envia |
| **Componentes afectados** | player `_sendChatMessage` guard |
| **Prioridade** | P2 |
| **Automatizável** | Maestro |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | ended |
| **Validar BD** | Sem insert chat |
| **Validar UI** | Snack PT |

---

## A322 — Saco histórico por `live_id` em gravado

| Campo | Valor |
|-------|-------|
| **ID** | A322 |
| **Nome** | Bag scope à live gravada |
| **Pré-condições** | Reservas durante live; depois ended |
| **Passos** | 1. Abrir gravado 2. Saco |
| **Resultado esperado** | Histórico completo dessa live; não mistura outras lives |
| **Componentes afectados** | `liveBagDisplayRequests` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | 2 lives mesmo buyer |
| **Validar BD** | `where live_id=$gravado` |
| **Validar UI** | Só linhas dessa sessão |

---

## A323 — Vendedor offline; comprador saco em gravado OK

| Campo | Valor |
|-------|-------|
| **ID** | A323 |
| **Nome** | Commerce pós-live sem studio activo |
| **Pré-condições** | Live ended; seller não no painel |
| **Passos** | 1. Buyer paga em gravado |
| **Resultado esperado** | Checkout funciona; seller vê depois em operacoesLive/pagamentos histórico |
| **Componentes afectados** | checkout, orders |
| **Prioridade** | P1 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | accepted + ended |
| **Validar BD** | Order `pago` com `live_id` |
| **Validar UI** | Checkout OK |

---

## A324 — Rifa ended: sem participate

| Campo | Valor |
|-------|-------|
| **ID** | A324 |
| **Nome** | Rifa inactiva em gravado |
| **Pré-condições** | Rifa estava activa; live ended |
| **Passos** | 1. Abrir gravado 2. Ver rifa |
| **Resultado esperado** | Sem CTA participate; estado ended/cancelled |
| **Componentes afectados** | `live_raffle_service.dart`, player |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | `live_raffles` pós-close |
| **Validar BD** | `status!=active` |
| **Validar UI** | Botão ausente |

---

## A325 — Viewer ping não corre em VOD

| Campo | Valor |
|-------|-------|
| **ID** | A325 |
| **Nome** | Contador viewers só em live |
| **Pré-condições** | Gravado |
| **Passos** | 1. Ficar 60s no player |
| **Resultado esperado** | Sem `batata_live_viewer_ping` ou contador estático |
| **Componentes afectados** | `live_room_service.dart` |
| **Prioridade** | P2 |
| **Automatizável** | Integration |
| **Tipo recomendado** | Integration |
| **Dados necessários** | ended |
| **Validar BD** | Sem pings recentes ou policy off |
| **Validar UI** | Viewer count não incrementa |

---

## A326 — Reserva gravado emite msg chat

| Campo | Valor |
|-------|-------|
| **ID** | A326 |
| **Nome** | Reserva em VOD gera linha social |
| **Pré-condições** | A297 |
| **Passos** | 1. Reservar em gravado 2. Ver replay chat no instante |
| **Resultado esperado** | Msg existe na BD; em replay aparece no timestamp se durante sessão original — **nova** reserva pós-ended: comportamento definido (msg imediata ou n/a replay) |
| **Componentes afectados** | player reserve em VOD |
| **Prioridade** | P2 |
| **Automatizável** | Bot |
| **Tipo recomendado** | Bot |
| **Dados necessários** | Nova reserva pós-end |
| **Validar BD** | Nova `live_messages` |
| **Validar UI** | Snack reserva OK |

---

## A327 — Fallback HLS live → VOD playback_id

| Campo | Valor |
|-------|-------|
| **ID** | A327 |
| **Nome** | Resolver URL VOD quando live stream parou |
| **Pré-condições** | ended + playback_id |
| **Passos** | 1. Resolver Mux URL |
| **Resultado esperado** | HLS VOD URL; não live RTMP |
| **Componentes afectados** | `mux_playback_resolve.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Integration |
| **Tipo recomendado** | Integration |
| **Dados necessários** | playback_id |
| **Validar BD** | `mux_vod_playback_id` |
| **Validar UI** | Vídeo on-demand |

---

## A328 — `mux_asset_id` após complete-mux

| Campo | Valor |
|-------|-------|
| **ID** | A328 |
| **Nome** | Asset Mux persistido |
| **Pré-condições** | Teardown OK |
| **Passos** | 1. complete-mux-live 2. Query lives |
| **Resultado esperado** | `mux_asset_id` e `mux_vod_playback_id` preenchidos |
| **Componentes afectados** | `complete-mux-live`, `lives_mux_asset_batata.sql` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | live ended |
| **Validar BD** | Colunas not null |
| **Validar UI** | — |

---

## A329 — Perfil «Diretos anteriores» só ended

| Campo | Valor |
|-------|-------|
| **ID** | A329 |
| **Nome** | Grid gravados no perfil vendedor |
| **Pré-condições** | Seller com lives ended |
| **Passos** | 1. Perfil vendedor 2. Tab lives |
| **Resultado esperado** | Só `status=ended`; tap abre VOD |
| **Componentes afectados** | `profile_lives_tab.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | ended lives |
| **Validar BD** | query ended |
| **Validar UI** | Grid gravados |

---

## A330 — Múltiplos gravados mesma ref (stock view)

| Campo | Valor |
|-------|-------|
| **ID** | A330 |
| **Nome** | Vendas em 2 gravados mesma linhagem |
| **Pré-condições** | 2 lives ended; mesmo `logical_item_id` |
| **Passos** | 1. Vendas em ambos 2. Novo live — ver pool |
| **Resultado esperado** | Pool Z82 agrega vendidos |
| **Componentes afectados** | cross-pool SQL |
| **Prioridade** | P1 |
| **Automatizável** | Integration |
| **Tipo recomendado** | Integration |
| **Dados necessários** | 2 ended + orders |
| **Validar BD** | `batata_live_item_stock` sold |
| **Validar UI** | — |

---

## A331 — Seek manual: highlight acompanha

| Campo | Valor |
|-------|-------|
| **ID** | A331 |
| **Nome** | Scrub bar altera vitrine replay |
| **Pré-condições** | A320 |
| **Passos** | 1. Arrastar scrub 2. Observar carrossel |
| **Resultado esperado** | Highlight muda sem lag &gt;1s |
| **Componentes afectados** | player VOD |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | events + vídeo |
| **Validar BD** | — |
| **Validar UI** | Sync visual |

---

## A332 — `ref_histories` actualiza venda gravado

| Campo | Valor |
|-------|-------|
| **ID** | A332 |
| **Nome** | Histórico ref após venda em VOD |
| **Pré-condições** | Venda converted em gravado |
| **Passos** | 1. Pagar 2. Query ref_histories |
| **Resultado esperado** | Entrada venda/gravado na linhagem |
| **Componentes afectados** | `ref_histories_batata.sql` |
| **Prioridade** | P1 |
| **Automatizável** | Integration |
| **Tipo recomendado** | Integration |
| **Dados necessários** | ref_code, sale |
| **Validar BD** | `ref_histories` row |
| **Validar UI** | Sheet linhagem futuro mostra stats |

---

## A333 — Transição live→gravado no mesmo player

| Campo | Valor |
|-------|-------|
| **ID** | A333 |
| **Nome** | Comprador na live quando termina |
| **Pré-condições** | Buyer no player live activo |
| **Passos** | 1. Seller termina 2. Buyer continua |
| **Resultado esperado** | Modo VOD ou kick com mensagem; saco mantém |
| **Componentes afectados** | realtime lives, player refresh |
| **Prioridade** | P1 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | 2 devices |
| **Validar BD** | status ended |
| **Validar UI** | UX clara |

---

## A334 — Fotos chat em replay (Z54)

| Campo | Valor |
|-------|-------|
| **ID** | A334 |
| **Nome** | Mensagens com imagem no replay |
| **Pré-condições** | Chat com foto durante live |
| **Passos** | 1. Replay no instante da msg |
| **Resultado esperado** | Foto visível; username correcto |
| **Componentes afectados** | chat player Z54 |
| **Prioridade** | P2 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | msg com attachment |
| **Validar BD** | storage url |
| **Validar UI** | Thumbnail render |

---

## A335 — Order gravado só `product_id` (sem live_item_id)

| Campo | Valor |
|-------|-------|
| **ID** | A335 |
| **Nome** | Venda VOD via marketplace product |
| **Pré-condições** | `marketplace_product`; order só `product_id` |
| **Passos** | 1. Comprar em gravado 2. Stock novo live |
| **Resultado esperado** | Conta no pool Z82 via product_id |
| **Componentes afectados** | Z82 SQL branch `o.product_id = v_li.product_id` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | order pago product_id |
| **Validar BD** | `batata_live_item_stock` sold += qty |
| **Validar UI** | Disp novo live correcto |

---

## A336 — operacoesLive bate com orders

| Campo | Valor |
|-------|-------|
| **ID** | A336 |
| **Nome** | Reconciliação UI sessão vs orders |
| **Pré-condições** | A301 |
| **Passos** | 1. Comparar cada linha UI vs SQL |
| **Resultado esperado** | Totais iguais |
| **Componentes afectados** | `live_session_results_service.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Integration |
| **Tipo recomendado** | Integration |
| **Dados necessários** | live_id |
| **Validar BD** | sum orders |
| **Validar UI** | KPI match |

---

## A337 — Web dashboard lives ended (se web)

| Campo | Valor |
|-------|-------|
| **ID** | A337 |
| **Nome** | Filtro ended no dashboard web |
| **Pré-condições** | Build web; seller logado |
| **Passos** | 1. Abrir lives web dashboard |
| **Resultado esperado** | Lista ended; sem crash |
| **Componentes afectados** | `lives_web_dashboard_widget.dart` |
| **Prioridade** | P3 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | ended lives |
| **Validar BD** | — |
| **Validar UI** | Lista render |

---

## A338 — RLS `live_messages` leitura gravado

| Campo | Valor |
|-------|-------|
| **ID** | A338 |
| **Nome** | Buyer lê msgs de live ended |
| **Pré-condições** | RLS chat |
| **Passos** | 1. SELECT live_messages como buyer |
| **Resultado esperado** | Rows visíveis |
| **Componentes afectados** | `live_room_batata.sql` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | msgs + ended live |
| **Validar BD** | select count > 0 |
| **Validar UI** | Chat replay populado |

---

## A339 — PDP marketplace após venda gravado

| Campo | Valor |
|-------|-------|
| **ID** | A339 |
| **Nome** | Produto marketplace reflecte stock pós-VOD |
| **Pré-condições** | TYPE A listado; venda em gravado |
| **Passos** | 1. Abrir PDP produto 2. Ver stock |
| **Resultado esperado** | Stock alinhado pool; não oversell |
| **Componentes afectados** | `product_details_page_widget.dart`, pool |
| **Prioridade** | P1 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | product_id, sale |
| **Validar BD** | products stock / pool |
## A340 — Z82 pool: qty 10, 1 venda live + 1 gravado

| Campo | Valor |
|-------|-------|
| **ID** | A340 |
| **Nome** | Stock partilhado RR1 — 8 disp / 2 vendidos |
| **Pré-condições** | Ref RR1 `quantity=10` mesmo `logical_item_id`; live activa + gravado ended; item marketplace opcional |
| **Passos** | 1. Vender 1 un. na live (convert/pago) 2. Vender 1 un. no gravado (order `product_id` ou `live_item_id`) 3. Abrir novo live/catálogo |
| **Resultado esperado** | `available_qty=8`; `sold` ou equivalente = 2; **não** duplicar converted+order |
| **Componentes afectados** | `live_items_inventory_batata.sql` (`batata_live_items_same_stock_pool`, Z82), `batata_live_item_stock` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | Seller test; RR1 qty 10; 2 lives; 2 orders pagos |
| **Validar BD** | `select batata_live_item_stock('live_item_id')` → `available_qty=8`, sold=2; orders distinct count |
| **Validar UI** | Carrossel «8 disp»; catálogo seller Total·Disp; barra fundo = Disp |

---

## A341 — `blocked_qty` noutro live (A3)

| Campo | Valor |
|-------|-------|
| **ID** | A341 |
| **Nome** | Unidades bloqueadas noutro directo reflectidas na UI |
| **Pré-condições** | Live A activa com reserva aceite; Live B mesma linhagem; stock pool partilhado |
| **Passos** | 1. Aceitar reserva live A 2. Abrir catálogo live B e carrossel comprador |
| **Resultado esperado** | Catálogo B: **Disp** alinhado RPC; **Reservas** inclui blocked; sem Total errado |
| **Componentes afectados** | stock RPC, `live_vendor_studio_panel.dart`, player carousel |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | 2 live_ids mesmo seller mesmo logical_item_id |
| **Validar BD** | `blocked_qty` > 0 no RPC live B |
| **Validar UI** | Puzzle «catálogo 2 / fundo 1» **não** deve ocorrer — valores iguais Disp |

---

## A342 — `cross_reserved_qty` no carrossel comprador

| Campo | Valor |
|-------|-------|
| **ID** | A342 |
| **Nome** | KPI Reservas inclui reservas noutras lives |
| **Pré-condições** | Reserva pending/accepted noutra live mesmo pool |
| **Passos** | 1. Criar reserva live A 2. Ver carrossel live B |
| **Resultado esperado** | `displayReservedQty` = local + cross; badge coerente |
| **Componentes afectados** | `LiveCatalogStockSnapshot`, player carousel |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | 2 lives, 1 reserva live A |
| **Validar BD** | RPC `cross_reserved_qty` > 0 |
| **Validar UI** | Texto Reservas no card artigo |

---

## A343 — Ordem gravado só `product_id` conta no pool (Z82)

| Campo | Valor |
|-------|-------|
| **ID** | A343 |
| **Nome** | Branch SQL product_id-only em vendidos |
| **Pré-condições** | Gravado; order `pago` sem `live_item_id`; `product_id` match |
| **Passos** | 1. Inserir/simular order 2. RPC stock item live activo mesmo pool |
| **Resultado esperado** | `sold` inclui order; `available_qty` desconta |
| **Componentes afectados** | Z82 SQL linhas 288-295 |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | order pago product_id; live_item com mesmo product_id |
| **Validar BD** | `batata_live_item_stock` antes/depois |
| **Validar UI** | — |

---

## A344 — Converted órfão não duplica sold (Z82 dedup)

| Campo | Valor |
|-------|-------|
| **ID** | A344 |
| **Nome** | Reserva converted + order pago = 1 un. vendida |
| **Pré-condições** | Reserva `converted` com order `pago` mesmo buyer+item |
| **Passos** | 1. Reconcile 2. Stock RPC |
| **Resultado esperado** | `sold` não soma 2x; distinct on order.id |
| **Componentes afectados** | Z82 `v_sold_converted` query |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | converted + order pago ligados |
| **Validar BD** | sold = qty real (não 2×) |
| **Validar UI** | — |

---

## A345 — Novo directo: aviso reserva aberta em gravado

| Campo | Valor |
|-------|-------|
| **ID** | A345 |
| **Nome** | Popup início live lista reservas gravado (linhagem) |
| **Pré-condições** | Gravado ended; reserva `pending/accepted` mesma linhagem; novo prep Continuar |
| **Passos** | 1. Prep inherit 2. Iniciar directo |
| **Resultado esperado** | Sheet amarelo lista reserva; origem «Gravado» |
| **Componentes afectados** | `batata_live_start_open_reservations_check`, warning sheet |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | ended + open reservation + draft inherit |
| **Validar BD** | RPC retorna rows origem gravado |
| **Validar UI** | Popup com item/título correcto |

---

## A346 — Aviso reserva marketplace aberta

| Campo | Valor |
|-------|-------|
| **ID** | A346 |
| **Nome** | Popup início live — origem Marketplace |
| **Pré-condições** | Reserva/order marketplace mesmo pool |
| **Passos** | 1. Iniciar live com ref ligada |
| **Resultado esperado** | Lista mostra origem Marketplace |
| **Componentes afectados** | `live_start_open_reservations_batata.sql`, parser unit |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | marketplace open reservation |
| **Validar BD** | RPC origin field |
| **Validar UI** | Label Marketplace no popup |

---

## A347 — `batata_upsert_marketplace_live_item`

| Campo | Valor |
|-------|-------|
| **ID** | A347 |
| **Nome** | Listar produto marketplace no catálogo live (TYPE A) |
| **Pré-condições** | Produto marketplace seller; live activa |
| **Passos** | 1. Toggle listar no catálogo 2. Sync |
| **Resultado esperado** | `live_items.item_kind=marketplace_product`; `list_on_marketplace=true`; checkout via product_id |
| **Componentes afectados** | `live_catalog_stock_service.dart`, SQL upsert |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | product_id, live_id |
| **Validar BD** | `live_items` row com product_id |
| **Validar UI** | Item no catálogo; PDP link OK |

---

## A348 — Poll stock 2s seller = buyer (sem drift)

| Campo | Valor |
|-------|-------|
| **ID** | A348 |
| **Nome** | Sincronização UI após venda noutro device |
| **Pré-condições** | Live activa; seller e buyer abertos |
| **Passos** | 1. Venda/aceite 2. Observar 10s ambos |
| **Resultado esperado** | Disp atualiza em ≤4s ambos; sem divergência &gt;1 un. |
| **Componentes afectados** | player poll, studio poll, realtime |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | 2 devices |
| **Validar BD** | RPC igual em ambos momentos T+3s |
| **Validar UI** | Números iguais seller catálogo vs buyer card |

---

## A349 — LiveCatalogSync merge preserva marketplace (Z52)

| Campo | Valor |
|-------|-------|
| **ID** | A349 |
| **Nome** | Sync prep não apaga listing marketplace |
| **Pré-condições** | Item `list_on_marketplace=true` |
| **Passos** | 1. Prep sync 2. Re-sync 3. Query |
| **Resultado esperado** | `list_on_marketplace` mantém; product_id intacto |
| **Componentes afectados** | `live_catalog_sync.dart`, `batata_update_live_item` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | live_item marketplace |
| **Validar BD** | flags marketplace unchanged após merge |
| **Validar UI** | Toggle ainda ON no catálogo |

---

## Apêndice — Primeiros 20 P0 a automatizar (área A280–A349)

| Ordem | ID | Justificação |
|-------|-----|--------------|
| 1 | **A340** | Z82 é regra de negócio crítica; regressão documentada; puramente RPC-first |
| 2 | **A343** | Branch product_id-only — bug silencioso em vendas gravado |
| 3 | **A344** | Dupla contagem sold inflaciona esgotado |
| 4 | **A341** | A3 FAIL histórico — stock UI errado gera overbook |
| 5 | **A342** | Cross_reserved — comprador vê disponibilidade falsa |
| 6 | **A280** | Msg reserva — primeira acção comprador; bot fácil |
| 7 | **A282** | Compra social — confiança comunidade live |
| 8 | **A281** | Filtro aceite público — evita leak ERP |
| 9 | **A288** | Recusa oculta — privacidade vendedor |
| 10 | **A290** | Strip prazo — já tem unit; evita confusão legal |
| 11 | **A294** | Qty>stock backoffice — ligado R6 |
| 12 | **A283** | Preço definido — desbloqueia P-series |
| 13 | **A309** | ERP nunca público — segurança copy |
| 14 | **A307** | Preço strip compra — idem |
| 15 | **A345** | Warning novo directo — evita surpresa seller |
| 16 | **A347** | Marketplace TYPE A — revenue path |
| 17 | **A349** | Z52 merge — regressão apagou listings |
| 18 | **A335** | Ponte gravado→pool (igual A343 UI path) |
| 19 | **A303** | RLS ended — gravado invisível = feature morta |
| 20 | **A338** | RLS msgs — replay vazio sem isto |

*Nota: A295, A296, A300, A306, A318, A319 permanecem P0 **manuais** (replay/HLS); automatizar depois com infra vídeo.*

---
