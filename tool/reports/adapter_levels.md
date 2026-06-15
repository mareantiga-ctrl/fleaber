# Adapter levels — matriz A001–A429

Total automated: 278

| A### | Nome | Layer | Nível | Validações | Campos BD | Campos UI |
|------|------|-------|-------|------------|-----------|-----------|
| A001 | Sheet «Criar» → Novo Directo | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A002 | Catálogo vazio bloqueia avanço | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A003 | Seleccionar produto marketplace no prep | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A004 | Ref nova — sem sheet linhagem (L1) | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A005 | Sheet linhagem com ≥2 cards (L3) | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A006 | Continuar Puzzle — herda reservas abertas (L4) | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A007 | «Usar como novo artigo» — UUID novo (L5) | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A008 | Cancelar sheet — draft inalterado (L11) | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A009 | Reservas Puzzle não alteradas pós L4/L5 | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A010 | Novo prep limpa refs locais anteriores | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A011 | RPC `batata_ensure_draft_live` na 1.ª entrada prep | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A012 | `batata_migrate_live_catalog` no go-live | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A013 | Detalhes ref sync para `live_items` | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A014 | Gate aviso ref activa noutro live | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A015 | SQL A2 — UUID único por artigo histórico (L2) | integration | 2 | RPC/insert staging + assert BD (logical_item_lineage) | live_items.logical_item_id | — |
| A016 | Cards sheet — stats/títulos separados (L3, L8) | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A017 | Deep link abre prep autenticado | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A019 | Fluxo prep → criar directo v1.04 | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A020 | Item sem preço no prep → «Preço pendente» live | bot | 2 | Bot sim price_pending + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A021 | Três refs distintas no draft | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A022 | Navegação back prep — estado previsível | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A023 | Sheet mostra «Última: Gravado» + stats (L7) | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A024 | Popup aviso origem Marketplace no go-live | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A025 | Script L10 — detecção uso fantasma | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A027 | RPC preview — venda ~18 meses ainda relevante (L16) | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A028 | Sem sheet quando irrelevante; com sheet se reservas antigas (L17, L18) | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A031 | Alternar tabs prep sem perder estado | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A032 | Título do directo editável no prep | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A034 | Mesmo produto adicionado duas vezes | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A035 | Remover ref/produto do draft prep | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A038 | Draft reflecte escolha linhagem (Query C) | integration | 2 | RPC/insert staging + assert BD (logical_item_lineage) | live_items.logical_item_id | — |
| A040 | Novo prep pós-live ended — estado limpo | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A041 | Um draft activo por seller | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A042 | LiveCatalogSync merge preserva listing (Z52) | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A045 | Scheme/cores ref persistem localmente entre sessões prep | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A046 | Reserva permitida com artigo price 0/null (P1) | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A047 | Seller define preço — grava BD + shadow (P2 label / P4 acção) | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A048 | Chat sistema «preço definido» após P4 (P3) | bot | 2 | Bot sim chat + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A049 | Saco sem Pagar até preço; desbloqueia após P4 (P4 gate) | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A050 | Deep link `/criarDirecto` salta preparar | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A055 | Sheet open reservations — confirmar go-live | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A056 | Recusar aviso cancela go-live | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A071 | `maestro_seller_studio_page_widget` debug | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A080 | Secção «No saco» lista reservas pending com metadata | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A081 | Aceitar reserva pending → accepted + stock + msg sistema | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A082 | Rejeitar reserva pending → rejected + notificação comprador | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A083 | Skip reserva pending → skipped; sai da fila urgente | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A084 | Aceitar qty > stock com dialog confirmação vendedor | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A085 | Reserva `bag_removed` — vendedor sem acções na fila | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A088 | Order `pago` sem convert — auto-reconcile ao abrir painel | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A089 | UI usa «Pendentes» — label legacy «A tratar» ausente | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A090 | Secção «Aceites · aguardar pagamento» lista accepted | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A091 | Secção «Sem pagamento» — accepted expirados ou unpaid | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A092 | Externos e waitlist visíveis ao vendedor | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A094 | Secção/filtro cancelados comprador (`bag_removed`) | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A095 | Fluxo T1 → Aceitar → Pagar abre Stripe sem loop urgente | hybrid | 3 | Bot seed → Maestro UI → integration BD | reservations, orders, raffles | seller harness, buyer bag/player |
| A097 | `batata_recompact_reservation_queue` mantém FIFO posições | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A107 | Tab Pagamentos lista orders convertidas da live | integration | 2 | RPC/insert staging + assert BD (stock) | batata_live_item_stock: available_qty | — |
| A108 | Log `reservation.load` inclui `stale_reconciled` count | integration | 2 | RPC/insert staging + assert BD (reservations_pending) | live_items, live_reservation_requests, orders (smoke) | — |
| A109 | Log studio `reservation.accept` com qty metadata | integration | 2 | RPC/insert staging + assert BD (reservations_pending) | live_items, live_reservation_requests, orders (smoke) | — |
| A110 | Log `checkout.pay_qty_gate` ao Pagar qty>stock | integration | 2 | RPC/insert staging + assert BD (stock) | batata_live_item_stock: available_qty | — |
| A111 | Vários compradores — ordem FIFO na fila seller e chips comprador | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A112 | Race: dois aceites simultâneos — só um ganha stock | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A113 | Expiração automática reserva pending/accepted | integration | 2 | RPC/insert staging + assert BD (reservations_pending) | live_items, live_reservation_requests, orders (smoke) | — |
| A114 | Waitlist e pedidos externos visíveis na Operação | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A117 | Vendedor cria rifa activa na live | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A118 | Fechar entradas rifa (stop join) | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A119 | Sortear vencedores rifa seller | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A120 | Cancelar rifa activa | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A121 | Toggle leaderboard público rifa | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A122 | Barra operações rifa integrada no painel Operação | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A126 | Aceite bloqueado/aviso quando stock pool noutro directo (Z82) | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A127 | RPC `batata_live_mark_qty_confirm_needed` ao Pagar qty>stock | integration | 2 | RPC/insert staging + assert BD (stock) | batata_live_item_stock: available_qty | — |
| A128 | Strings ERP/qty_confirm **não** aparecem no chat público | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A129 | Actividade: «adicionou ao saco» só pending aberto; cancel remove evento | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A130 | Activar vitrine (is_active) no catálogo | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A132 | Repor stock após sold — catálogo e carrossel sync | integration | 2 | RPC/insert staging + assert BD (stock) | batata_live_item_stock: available_qty | — |
| A133 | Badge ESGOTADO nunca só por pending | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A141 | KPI reservas reflecte pending | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A144 | `quantity` BD sync após +/- stock | integration | 2 | RPC/insert staging + assert BD (stock) | batata_live_item_stock: available_qty | — |
| A145 | Entrada player via card LIVE Home | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A146 | Player VOD via perfil vendedor | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A147 | Referral rifa via deep link | integration | 2 | RPC/insert staging + assert BD (stock) | batata_live_item_stock: available_qty | — |
| A148 | Primeira reserva — pending + chat | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A149 | Segunda reserva incrementa qty — não duplica row | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A150 | Fila de espera quando stock esgotado por aceite | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A151 | Card verde comprador ao aceite — sem dialog duplicado | hybrid | 3 | Bot seed → Maestro UI → integration BD | reservations, orders, raffles | seller harness, buyer bag/player |
| A152 | Banner saco só em `status=accepted` | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A153 | CTA Pagar no saco e player quando payable | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A156 | Contador espectadores incrementa ao entrar | bot | 2 | Bot sim viewers + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A157 | Seguir vendedor no player | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A160 | Comprador remove reserva do saco (pré-pagamento) | integration | 2 | RPC/insert staging + assert BD (stock) | batata_live_item_stock: available_qty | — |
| A161 | Comprador envia mensagem chat público | bot | 2 | Bot sim chat + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A162 | Input chat desactivado em VOD/replay | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A164 | Partilhar link da live (copy) | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A166 | Portes visíveis antes de abrir Stripe | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A167 | Linha seguro no preview checkout comprador | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A173 | UI distingue indisponível de waitlist | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A177 | Cache catálogo invalida após mutação seller | integration | 2 | RPC/insert staging + assert BD (stock) | batata_live_item_stock: available_qty | — |
| A178 | Supabase realtime actualiza carrossel | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A179 | Saco actualiza realtime (aceite/reject) | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A182 | Carrossel com muitos artigos — scroll e performance | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A183 | Feed Home coerente com BD `status`/`is_active` | integration | 2 | RPC/insert staging + assert BD (stock) | batata_live_item_stock: available_qty | — |
| A184 | Param `forceVod` força modo replay | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A185 | Param `sellerId` na rota player | integration | 2 | RPC/insert staging + assert BD (stock) | batata_live_item_stock: available_qty | — |
| A187 | Referral visit anónimo atribuído pós-login | integration | 2 | RPC/insert staging + assert BD (stock) | batata_live_item_stock: available_qty | — |
| A188 | Join rifa via sidebar player | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A189 | Join rifa via sheet modal +1 entrada | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A190 | Sheet «Saco da live» abre com secções | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A191 | Linhas pending no saco com metadata correcta | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A192 | Reserva em fila quando stock cheio | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A193 | Histórico converted no saco | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A194 | Cancelamento comprador no saco | unit | 1 | flutter test executa sem erro (filtro: variantes cancelado) | — | — (lógica Dart isolada) |
| A197 | Duas reservas mesma ref → 1 linha qty 2 | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A198 | Checkout saco multi-ref — POST create-payment-intent | integration | 2 | RPC/insert staging + assert BD (bag_edge) | live_reservation_requests multi-ref buyer | — |
| A199 | Linha portes Envio Transportadora no checkout | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A200 | Entrega em mão sem portes | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A201 | Protecção Fleaber no breakdown | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A202 | Preço pendente — Pagar bloqueado | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A206 | Retorno success → converted + order pago | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A208 | Um checkout Stripe → 2 orders pago | integration | 2 | RPC/insert staging + assert BD (bag_edge) | live_reservation_requests multi-ref buyer | — |
| A209 | Reconcile manual/API order pago órfã | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A210 | Chat «comprou» após reconcile | bot | 2 | Bot sim chat + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A212 | Entrar na rifa durante directo (+1) | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A213 | Partilha social +2 entradas | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A214 | Visitante referral — qualificação 60s | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A215 | Ranking top 5 entradas | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A216 | Countdown mm:ss até fecho | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A217 | Broadcast rifa sem spam no chat | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A218 | Sorteio + notificação vencedores | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A219 | Movimento wallet vendedor após order pago | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A220 | Fee platform na libertação | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A225 | Item shadow — `checkout_product_id` no pagamento | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A226 | TYPE A — `product_id` marketplace no order | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A227 | Preço definido → CTA Pagar habilita (incl. aceite sem preço antes) | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A228 | Seller não pode alterar preço após venda/convert | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A230 | Cancelamento comprador **antes** de pagar | integration | 2 | RPC/insert staging + assert BD (cancel) | live_reservation_requests.status=rejected, notes bag_removed | — |
| A231 | `/operacoesLive` — cards sessão com KPIs agregados | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A232 | Transição visual e BD order live checkout | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A240 | Fee platform em settle 2+ orders (saco) | integration | 2 | RPC/insert staging + assert BD (bag_edge) | live_reservation_requests multi-ref buyer | — |
| A242 | Tips incluídos no resumo `/resultadosLive` sem misturar receita artigos | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A243 | Alerta `hasAlerts` — order `pago` sem reserva `converted` | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A244 | Acção refresh/reconcile no pós-live converte órfãos | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A246 | Minhas encomendas destaca/filtra orders com `live_id` | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A247 | Lista vendas sessão filtra por estado pago/disputa/devolução | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A248 | Procedimento operacional stale order documentado e reproduzível | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A249 | 2.ª chamada reconcile não duplica crédito/conversão | integration | 2 | RPC/insert staging + assert BD (reconcile) | orders.status, live_reservation_requests.converted | — |
| A250 | Suite H04: bot join + buyer Maestro «Participar na Rifa (+1)» | unit | 1 | flutter test executa sem erro (filtro: rifa activa) | — | — (lógica Dart isolada) |
| A251 | Follow seller durante rifa — `follow_bonus_claimed` | bot | 2 | Bot sim follows + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A252 | Partilha social — `batata_claim_live_raffle_share_intent` | unit | 1 | flutter test executa sem erro (filtro: leaderboard) | — | — (lógica Dart isolada) |
| A253 | `ensureReferralLink` + `registerReferralVisit` | unit | 1 | flutter test executa sem erro (filtro: mm:ss) | — | — (lógica Dart isolada) |
| A254 | `qualifyReferralVisits` após permanência | unit | 1 | flutter test executa sem erro (filtro: horas quando) | — | — (lógica Dart isolada) |
| A255 | Ranking comprador actualizado com entradas | unit | 1 | flutter test executa sem erro (filtro: sem rifa) | — | — (lógica Dart isolada) |
| A256 | Vendedor vê resumo participantes na ops bar | unit | 1 | flutter test executa sem erro (filtro: rifa sem timer) | — | — (lógica Dart isolada) |
| A257 | Ordem cronológica entradas preservada no sorteio | unit | 1 | flutter test executa sem erro (filtro: ok com duplicate) | — | — (lógica Dart isolada) |
| A258 | Abrir live via link referral pré-preenche contexto rifa | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A259 | Seguir vendedor não dispara spam notificações (P15 overlap) | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A260 | Re-share imediato não duplica +2 | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A261 | Vendedor dispara sorteio — `batata_draw_live_raffle_winners` | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A262 | Timer zero → close + draw automático (se política activa) | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A263 | Sorteio auditável — `tickets_at_draw` por winner | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A264 | Anúncio draw no chat público humanizado | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A265 | Vencedor recebe push «Ganhaste a rifa» | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A266 | Seller notificado sorteio concluído | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A267 | Replay gravado: countdown histórico; join/participar bloqueado | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A268 | Guard `_liveIsActive` bloqueia join em ended | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A269 | Bónus share/referral não disponíveis em replay | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A270 | Rajada eventos rifa (join, +2, draw) sem spam chat | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A271 | Flow Maestro comprador rifa+saco sem falha | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A272 | `v2_seller_harness_accept` + ops bar rifa visível | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A273 | `LiveRafflePrizeEditSheet` actualiza título/imagem | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A274 | Imagem e título prémio no `LiveRaffleBuyerCard` | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A275 | Seller cancela rifa — comprador vê estado cancelado | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A276 | Bónus A211 não duplica em reconcile/repay | bot | 2 | Bot sim raffles + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A277 | 20+ bots join/share — leaderboard estável | bot | 2 | Bot sim full + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A278 | `show_public_leaderboard=false` esconde ranking | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A279 | Suite H04 completa: bot seed → Maestro → verify BD | hybrid | 3 | Bot seed → Maestro UI → integration BD | reservations, orders, raffles | seller harness, buyer bag/player |
| A280 | Mensagem pública de reserva no chat | unit | 1 | flutter test executa sem erro (filtro: reserva mantém) | — | — (lógica Dart isolada) |
| A281 | Mensagem de aceite oculta no chat público | unit | 1 | flutter test executa sem erro (filtro: reserva aceite pública) | — | — (lógica Dart isolada) |
| A282 | Mensagem pública pós-compra | unit | 1 | flutter test executa sem erro (filtro: compra mantém) | — | — (lógica Dart isolada) |
| A283 | Mensagem «Preço definido» após seller definir preço | unit | 1 | flutter test executa sem erro (filtro: preço definido) | — | — (lógica Dart isolada) |
| A284 | Broadcast FOMO «última unidade» | unit | 1 | flutter test executa sem erro (filtro: última unidade) | — | — (lógica Dart isolada) |
| A285 | Broadcast FOMO «artigo esgotou» | unit | 1 | flutter test executa sem erro (filtro: esgotado) | — | — (lógica Dart isolada) |
| A286 | Mensagem de gorjeta visível no chat | unit | 1 | flutter test executa sem erro (filtro: gorjeta com nome) | — | — (lógica Dart isolada) |
| A287 | Mensagem de cancelamento comprador | unit | 1 | flutter test executa sem erro (filtro: cancelamento) | — | — (lógica Dart isolada) |
| A288 | Recusa vendedor só backoffice | unit | 1 | flutter test executa sem erro (filtro: rejeição vendedora) | — | — (lógica Dart isolada) |
| A289 | Uma linha «comprou» por par comprador+artigo | unit | 1 | flutter test executa sem erro (filtro: dedupe compra) | — | — (lógica Dart isolada) |
| A290 | Prazo de pagamento não aparece no chat público | unit | 1 | flutter test executa sem erro (filtro: prazo 5 dias) | — | — (lógica Dart isolada) |
| A292 | Normalização «ao saco» → «ao carrinho» | unit | 1 | flutter test executa sem erro (filtro: adicionou ao saco) | — | — (lógica Dart isolada) |
| A293 | Mensagem social de adição ao saco | unit | 1 | flutter test executa sem erro (filtro: adicionou ao saco) | — | — (lógica Dart isolada) |
| A294 | Alerta qty>stock oculto do chat público | unit | 1 | flutter test executa sem erro (filtro: pedido acima stock) | — | — (lógica Dart isolada) |
| A297 | Reserva permitida em live terminada | bot | 2 | Bot sim chat + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A298 | Checkout permitido em VOD | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A300 | Feed Home abre gravado com HLS VOD | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A302 | Gravado sem playback_id | integration | 2 | RPC/insert staging + assert BD (gravado_sold) | orders.product_id, products.quantity | — |
| A303 | Comprador vê lives ended no feed | integration | 2 | RPC/insert staging + assert BD (cross_pool_product_sold) | batata_live_item_stock: available_qty, sold, sold_converted_qty | — |
| A304 | Broadcast rifa no chat sem prefixo duplicado | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A305 | Mensagem aceite visível no chat público (variante social) | unit | 1 | flutter test executa sem erro (filtro: aceite) | — | — (lógica Dart isolada) |
| A307 | Preço € não aparece na linha «comprou» | unit | 1 | flutter test executa sem erro (filtro: compra com preço) | — | — (lógica Dart isolada) |
| A308 | Duas mensagens FOMO em ordem lógica | bot | 2 | Bot sim chat + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A309 | Mensagens com `/` ou campos ERP ocultas | unit | 1 | flutter test executa sem erro (filtro: compactFromBody) | — | — (lógica Dart isolada) |
| A310 | Entrada directa VOD por URL | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A311 | BD `ended` força VOD mesmo com isLive=true no link | integration | 2 | RPC/insert staging + assert BD (gravado_sold) | orders.product_id, products.quantity | — |
| A313 | Texto «Chat da gravação…» sem input | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A321 | Feedback ao tentar chat live em gravado | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A322 | Bag scope à live gravada | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A324 | Rifa inactiva em gravado | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A325 | Contador viewers só em live | integration | 2 | RPC/insert staging + assert BD (cross_pool_product_sold) | batata_live_item_stock: available_qty, sold, sold_converted_qty | — |
| A326 | Reserva em VOD gera linha social | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A327 | Resolver URL VOD quando live stream parou | integration | 2 | RPC/insert staging + assert BD (gravado_sold) | orders.product_id, products.quantity | — |
| A329 | Grid gravados no perfil vendedor | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A330 | Vendas em 2 gravados mesma linhagem | integration | 2 | RPC/insert staging + assert BD (gravado_sold) | orders.product_id, products.quantity | — |
| A332 | Histórico ref após venda em VOD | integration | 2 | RPC/insert staging + assert BD (gravado_sold) | orders.product_id, products.quantity | — |
| A335 | Venda VOD via marketplace product | integration | 2 | RPC/insert staging + assert BD (marketplace_bridge) | orders.product_id, products.quantity | — |
| A336 | Reconciliação UI sessão vs orders | integration | 2 | RPC/insert staging + assert BD (cross_pool_product_sold) | batata_live_item_stock: available_qty, sold, sold_converted_qty | — |
| A338 | Buyer lê msgs de live ended | integration | 2 | RPC/insert staging + assert BD (cross_pool_product_sold) | batata_live_item_stock: available_qty, sold, sold_converted_qty | — |
| A340 | Stock partilhado RR1 — 8 disp / 2 vendidos | integration | 2 | RPC/insert staging + assert BD (cross_pool_rr1) | batata_live_item_stock: available_qty, sold, sold_converted_qty | — |
| A341 | Unidades bloqueadas noutro directo reflectidas na UI | integration | 2 | RPC/insert staging + assert BD (blocked_qty) | batata_live_item_stock: blocked_qty | — |
| A342 | KPI Reservas inclui reservas noutras lives | integration | 2 | RPC/insert staging + assert BD (cross_reserved) | batata_live_item_stock: cross_reserved_qty | — |
| A343 | Branch SQL product_id-only em vendidos | integration | 2 | RPC/insert staging + assert BD (cross_pool_product_sold) | batata_live_item_stock: available_qty, sold, sold_converted_qty | — |
| A344 | Reserva converted + order pago = 1 un. vendida | integration | 2 | RPC/insert staging + assert BD (cross_pool_sold_dedup) | batata_live_item_stock: available_qty, sold, sold_converted_qty | — |
| A345 | Popup início live lista reservas gravado (linhagem) | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A346 | Popup início live — origem Marketplace | integration | 2 | RPC/insert staging + assert BD (cross_pool_rr1) | batata_live_item_stock: available_qty, sold, sold_converted_qty | — |
| A347 | Listar produto marketplace no catálogo live (TYPE A) | integration | 2 | RPC/insert staging + assert BD (cross_pool_rr1) | batata_live_item_stock: available_qty, sold, sold_converted_qty | — |
| A349 | Sync prep não apaga listing marketplace | integration | 2 | RPC/insert staging + assert BD (cross_pool_rr1) | batata_live_item_stock: available_qty, sold, sold_converted_qty | — |
| A350 | Navegação carrossel → PDP com contexto live | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A351 | Home feed lista produto após `list_on_marketplace=true` | integration | 2 | RPC/insert staging + assert BD (marketplace_bridge) | orders.product_id, products.quantity | — |
| A352 | Venda live decrementa qty visível no PDP | integration | 2 | RPC/insert staging + assert BD (cross_pool_product_sold) | batata_live_item_stock: available_qty, sold, sold_converted_qty | — |
| A353 | Superfícies mostram preço correcto por canal | bot | 2 | Bot sim price_pending + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A354 | Pool RR1 com vendas live, gravado e reserva marketplace | integration | 2 | RPC/insert staging + assert BD (marketplace_bridge) | orders.product_id, products.quantity | — |
| A355 | PDP e live items partilham linhagem via `logical_item_id` | integration | 2 | RPC/insert staging + assert BD (logical_item_inherit) | live_items.logical_item_id | — |
| A356 | Prep mostra histórico vendas marketplace da ref | integration | 2 | RPC/insert staging + assert BD (marketplace_bridge) | orders.product_id, products.quantity | — |
| A359 | Shadow `live_only` ausente do feed marketplace | integration | 2 | RPC/insert staging + assert BD (marketplace_bridge) | orders.product_id, products.quantity | — |
| A360 | Compra orgânica PDP — preço `products.price`, não live | integration | 2 | RPC/insert staging + assert BD (cross_pool_product_sold) | batata_live_item_stock: available_qty, sold, sold_converted_qty | — |
| A361 | PDP indica sessão live activa ligada ao artigo | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A362 | Reserva aceite noutro live reduz qty PDP | integration | 2 | RPC/insert staging + assert BD (cross_pool_product_sold) | batata_live_item_stock: available_qty, sold, sold_converted_qty | — |
| A363 | Reservas noutras lives visíveis no stock PDP | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A365 | Marketplace listing sobrevive fim do directo | integration | 2 | RPC/insert staging + assert BD (marketplace_bridge) | orders.product_id, products.quantity | — |
| A367 | Order marketplace decrementa stock carrossel live | integration | 2 | RPC/insert staging + assert BD (marketplace_bridge) | orders.product_id, products.quantity | — |
| A368 | Novo directo inherit marketplace item — 1 product row | integration | 2 | RPC/insert staging + assert BD (marketplace_bridge) | orders.product_id, products.quantity | — |
| A369 | Re-sync prep não quebra bridge marketplace↔live↔pool | integration | 2 | RPC/insert staging + assert BD (marketplace_bridge) | orders.product_id, products.quantity | — |
| A370 | Seller convida colaborador por e-mail | integration | 2 | RPC/insert staging + assert BD (helper_seller_exists) | live_items, live_reservation_requests, orders (smoke) | — |
| A371 | Colaborador aceita convite pendente | integration | 2 | RPC/insert staging + assert BD (helper_seller_exists) | live_items, live_reservation_requests, orders (smoke) | — |
| A373 | Helper com `can_manage_reservations` aceita reserva | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A375 | Helper sem permissão reservas — aceitar bloqueado | integration | 2 | RPC/insert staging + assert BD (helper_seller_exists) | live_items, live_reservation_requests, orders (smoke) | — |
| A377 | Colaborador recusa convite pendente | integration | 2 | RPC/insert staging + assert BD (helper_seller_exists) | live_items, live_reservation_requests, orders (smoke) | — |
| A378 | Remover/desactivar colaborador aceite | integration | 2 | RPC/insert staging + assert BD (helper_seller_exists) | live_items, live_reservation_requests, orders (smoke) | — |
| A380 | Dupla verificação terminar live (UI + servidor) | integration | 2 | RPC/insert staging + assert BD (helper_seller_exists) | live_items, live_reservation_requests, orders (smoke) | — |
| A381 | `can_change_current_item` — spotlight no carrossel | bot | 2 | Bot sim reservations + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A382 | `can_manage_chat` — resposta/moderar no studio | bot | 2 | Bot sim chat + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A385 | Convite falha se utilizador não registado | integration | 2 | RPC/insert staging + assert BD (helper_seller_exists) | live_items, live_reservation_requests, orders (smoke) | — |
| A386 | Segundo convite mesmo helper bloqueado | integration | 2 | RPC/insert staging + assert BD (helper_seller_exists) | live_items, live_reservation_requests, orders (smoke) | — |
| A387 | `helperLinkId` expirado ou de outro user | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A389 | Bypass UI não contorna servidor | integration | 2 | RPC/insert staging + assert BD (helper_seller_exists) | live_items, live_reservation_requests, orders (smoke) | — |
| A393 | Corrida CI — dois flows mesmo seller/live | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A394 | Login Maestro sem Application Not Responding | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A395 | Stress 5 compradores reservam em paralelo | bot | 2 | Bot sim full + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A396 | Seller com 2 lives draft — só uma activa | integration | 2 | RPC/insert staging + assert BD (reservations_pending) | live_items, live_reservation_requests, orders (smoke) | — |
| A398 | H07 pipeline — bot prepara, Maestro valida | hybrid | 3 | Bot seed → Maestro UI → integration BD | reservations, orders, raffles | seller harness, buyer bag/player |
| A401 | Token Supabase expira mid-session — auto-refresh | integration | 2 | RPC/insert staging + assert BD (reservations_pending) | live_items, live_reservation_requests, orders (smoke) | — |
| A402 | Refresh falha — utilizador deslogado com mensagem | integration | 2 | RPC/insert staging + assert BD (reservations_pending) | live_items, live_reservation_requests, orders (smoke) | — |
| A406 | Duplo tap Reservar — dedupe ou increment qty | bot | 2 | Bot sim full + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A407 | 10+ reservas rápidas mesmo buyer — throttling | bot | 2 | Bot sim full + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A408 | Spam chat público — throttle | bot | 2 | Bot sim chat + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A409 | Falha edge pagamento — UI retry sem perder saco | integration | 2 | RPC/insert staging + assert BD (reservations_pending) | live_items, live_reservation_requests, orders (smoke) | — |
| A411 | Colaborador não acede dados de outra loja | integration | 2 | RPC/insert staging + assert BD (reservations_pending) | live_items, live_reservation_requests, orders (smoke) | — |
| A413 | Force-close durante broadcast — cleanup no próximo start | integration | 2 | RPC/insert staging + assert BD (reservations_pending) | live_items, live_reservation_requests, orders (smoke) | — |
| A415 | Seller + helper aceitam simultaneamente — idempotente | integration | 2 | RPC/insert staging + assert BD (reservations_pending) | live_items, live_reservation_requests, orders (smoke) | — |
| A416 | Subscription morta — poll corrige UI | bot | 2 | Bot sim full + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A418 | Navegação para live inexistente | maestro | 3 | Flow Maestro UI smoke + asserts visuais | — (indirecto via app) | login, player, saco, studio, rifa sidebar |
| A419 | Stock 1, N buyers — só posição #1 aceitável sem overbook | bot | 2 | Bot sim full + validators BD (stock, reservations, chat, raffles) | live_reservation_requests, live_items, live_messages, live_raffles, orders | — (opcional --observe-ui) |
| A420 | Auditoria studio — eventos críticos logados | integration | 2 | RPC/insert staging + assert BD (reconcile_idempotent) | orders.status, live_reservation_requests.converted | — |
| A421 | Recompact fila após remove/cancel | integration | 2 | RPC/insert staging + assert BD (reconcile_idempotent) | orders.status, live_reservation_requests.converted | — |
| A422 | Timer poll cancela ao sair do ecrã | unit | 1 | flutter test executa sem erro | — | — (lógica Dart isolada) |
| A424 | Apenas buyer da order pode reconcile/convert | integration | 2 | RPC/insert staging + assert BD (reconcile_idempotent) | orders.status, live_reservation_requests.converted | — |
| A425 | RLS impede leak mensagens privadas no chat público | integration | 2 | RPC/insert staging + assert BD (reconcile_idempotent) | orders.status, live_reservation_requests.converted | — |
| A427 | Egress órfão LiveKit — job cleanup | integration | 2 | RPC/insert staging + assert BD (reconcile_idempotent) | orders.status, live_reservation_requests.converted | — |
| A429 | `available_qty` decrementa exactamente 1× por aceite | integration | 2 | RPC/insert staging + assert BD (reconcile_idempotent) | orders.status, live_reservation_requests.converted | — |
