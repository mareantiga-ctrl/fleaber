# Fleaber - Inventario completo de testes

Gerado: 2026-06-16 14:53:01

## Resumo

| Conjunto | Total |
|----------|-------|
| Matriz A### (regression) | 429 |
| Bateria UX+BD T01-T21 | 21 |
| **Total** | **450** |

### Matriz A### por estado de execucao

- **blocked**: 24
- **manual**: 131
- **pass**: 244
- **skip_config_missing**: 30

## Bateria UX+BD (T01-T21)

| ID | Fase | Camada | Nome | O que testa | Estado | Ultimo stamp |
|----|------|--------|------|-------------|--------|--------------|
| T01 | 1 | BD | flutter_test_core | Unit tests Flutter (raffle, chat, lineage) | **PASS** | 20260616_142156 |
| T02 | 1 | BD | live_ops_staging_check | Live ops staging V0 (RPC/BD) | **PASS** | 20260616_142156 |
| T03 | 1 | BD | integration_stock | Integracao stock A3 | **PASS** | 20260616_142156 |
| T04 | 1 | BD | integration_a3_r32_qty | Integracao A3/R32 qty | **PASS** | 20260616_142156 |
| T05 | 1 | BD | integration_cross_pool | Integracao cross-pool A340 | **PASS** | 20260616_142156 |
| T06 | 1 | BD | integration_lineage | Integracao linhagem A005 | **PASS** | 20260616_142156 |
| T07a | 1 | UX | maestro_seller_harness | Seller harness: Aceitar reserva pending | **PASS** | 20260616_110306 |
| T07b | 1 | UX | maestro_seller_stock | Seller +Stock no harness | **PASS** | 20260616_110306 |
| T07c | 1 | UX | maestro_buyer_raffle_bag | Buyer player + rifa + saco | **PASS** | 20260616_142156 |
| T08a | 1 | BD | doc_apk_v0_bd | Doc APK V0 BD | **PASS** | 20260616_110306 |
| T08b | 1 | UX | doc_apk_cancel_bag | Doc #4 APK cancelar saco | **PASS** | 20260616_142156 |
| T08c | 1 | UX | doc_apk_bag_pagar | Doc #6 APK saco Pagar | **FAIL** | 20260616_110306 |
| T08d | 1 | UX | doc_apk_seller_stock | Doc #3 APK adicionar stock | **FAIL** | 20260616_110306 |
| T08e | 1 | UX | doc_apk_stripe | Doc #7 Stripe EUR | **SKIP** | 20260616_110306 |
| T09 | 1 | UX | seller_stock_ui_maestro | Seller stock UI (bateria isolada) | **PASS** | 20260616_142156 |
| T10 | 1 | UX | pull_maestro_logs | Pull logs maestro_studio | **PASS** | 20260616_142156 |
| T11 | 2 | UX+BD | CS01 | Reserva pending -> Aceitar | **PASS** | 20260616_143805 |
| T12 | 2 | UX+BD | CS02 | Adicionar stock (+1) | **PASS** | 20260616_143805 |
| T13 | 2 | UX+BD | CS03 | A3 quick edit qty | **RUNNING** | 20260616_143805 |
| T14 | 2 | UX+BD | CS04 | R32 repor stock | **FAIL** | 20260616_124819 |
| T15 | 2 | UX+BD | CS05 | Cancelar saco | **FAIL** | 20260616_124819 |
| T16 | 2 | UX+BD | CS06 | Marcar vendido | **FAIL** | 20260616_124819 |
| T17 | 2 | BD | CS07 | Cross-pool | **SKIP** | 20260616_124819 |
| T18 | 2 | UX+BD | CS08 | Linhagem prep -> live | **FAIL** | 20260616_124819 |
| T19 | 2 | UX+BD | CS09 | Saco Pagar | **FAIL** | 20260616_124819 |
| T20 | 2 | UX+BD | CS10 | Rifa + saco | **FAIL** | 20260616_124819 |
| T21 | 2 | UX | CS11 | Stripe Doc #7 | **SKIP** | 20260616_124819 |

## Matriz A### (429 testes)

| ID | Estado exec | Implementacao | Camada | Area | Titulo | Adapter |
|----|-------------|---------------|--------|------|--------|---------|
| A001 | pass | automated | maestro | prep | Sheet Â«CriarÂ» â†’ Novo Directo | .maestro/flows/v1_04_seller_preparar_directo.yaml |
| A002 | pass | not_implemented | maestro | prep | CatÃ¡logo vazio bloqueia avanÃ§o | - |
| A003 | pass | not_implemented | integration | prep | Seleccionar produto marketplace no prep | - |
| A004 | pass | not_implemented | maestro | prep | Ref nova â€” sem sheet linhagem (L1) | - |
| A005 | pass | automated | unit | prep | Sheet linhagem com â‰¥2 cards (L3) | test/live_ref_lineage_sheet_test.dart |
| A006 | pass | not_implemented | integration | prep | Continuar Puzzle â€” herda reservas abertas (L4) | - |
| A007 | pass | not_implemented | integration | prep | Â«Usar como novo artigoÂ» â€” UUID novo (L5) | - |
| A008 | pass | not_implemented | maestro | prep | Cancelar sheet â€” draft inalterado (L11) | - |
| A009 | pass | not_implemented | integration | prep | Reservas Puzzle nÃ£o alteradas pÃ³s L4/L5 | - |
| A010 | pass | not_implemented | integration | prep | Novo prep limpa refs locais anteriores | - |
| A011 | pass | not_implemented | integration | prep | RPC `batata_ensure_draft_live` na 1.Âª entrada prep | - |
| A012 | pass | not_implemented | integration | prep | `batata_migrate_live_catalog` no go-live | - |
| A013 | pass | not_implemented | integration | prep | Detalhes ref sync para `live_items` | - |
| A014 | pass | not_implemented | bot | prep | Gate aviso ref activa noutro live | - |
| A015 | pass | not_implemented | integration | prep | SQL A2 â€” UUID Ãºnico por artigo histÃ³rico (L2) | - |
| A016 | pass | automated | unit | prep | Cards sheet â€” stats/tÃ­tulos separados (L3, L8) | test/live_ref_lineage_preview_service_test.dart |
| A017 | pass | automated | maestro | prep | Deep link abre prep autenticado | .maestro/flows/v1_01_login_buyer_home.yaml |
| A018 | manual | manual | manual | prep | Staff/helper bloqueado em Novo Directo | - |
| A019 | pass | not_implemented | maestro | prep | Fluxo prep â†’ criar directo v1.04 | - |
| A020 | pass | automated | bot | prep | Item sem preÃ§o no prep â†’ Â«PreÃ§o pendenteÂ» live | tool/fleaber_bot_simulator.dart |
| A021 | pass | not_implemented | integration | prep | TrÃªs refs distintas no draft | - |
| A022 | pass | not_implemented | maestro | prep | NavegaÃ§Ã£o back prep â€” estado previsÃ­vel | - |
| A023 | pass | automated | unit | prep | Sheet mostra Â«Ãšltima: GravadoÂ» + stats (L7) | test/live_ref_lineage_preview_service_test.dart |
| A024 | pass | not_implemented | integration | prep | Popup aviso origem Marketplace no go-live | - |
| A025 | pass | not_implemented | integration | prep | Script L10 â€” detecÃ§Ã£o uso fantasma | - |
| A026 | manual | manual | manual | prep | Cancelar sheet â€” reaparece quando relevante (L9) | - |
| A027 | pass | automated | unit | prep | RPC preview â€” venda ~18 meses ainda relevante (L16) | test/live_ref_lineage_preview_service_test.dart |
| A028 | pass | not_implemented | integration | prep | Sem sheet quando irrelevante; com sheet se reservas antigas (L17, L18) | - |
| A029 | manual | manual | manual | prep | TYPE A â€” toggle listar; sem sheet linhagem (L12) | - |
| A030 | manual | manual | manual | prep | Bundles no prep â€” comportamento documentado | - |
| A031 | pass | not_implemented | maestro | prep | Alternar tabs prep sem perder estado | - |
| A032 | pass | not_implemented | maestro | prep | TÃ­tulo do directo editÃ¡vel no prep | - |
| A033 | manual | manual | manual | prep | Imagem marketplace herdada no item prep | - |
| A034 | pass | not_implemented | integration | prep | Mesmo produto adicionado duas vezes | - |
| A035 | pass | not_implemented | maestro | prep | Remover ref/produto do draft prep | - |
| A036 | manual | manual | manual | prep | ResiliÃªncia rede no prep/sync | - |
| A037 | manual | manual | manual | prep | Prep usa catÃ¡logo da loja activa (staff) | - |
| A038 | pass | not_implemented | integration | prep | Draft reflecte escolha linhagem (Query C) | - |
| A039 | manual | manual | manual | prep | Ref alfanumÃ©rica â€” normalizaÃ§Ã£o | - |
| A040 | pass | not_implemented | integration | prep | Novo prep pÃ³s-live ended â€” estado limpo | - |
| A041 | pass | not_implemented | integration | prep | Um draft activo por seller | - |
| A042 | pass | not_implemented | integration | prep | LiveCatalogSync merge preserva listing (Z52) | - |
| A043 | manual | manual | manual | prep | Scroll prep preservado em refresh (Z50) | - |
| A044 | manual | not_implemented | not_implemented | prep | Quick edit descriÃ§Ã£o â€” **N/A no prep** (sÃ³ em live Z53) | - |
| A045 | pass | not_implemented | integration | prep | Scheme/cores ref persistem localmente entre sessÃµes prep | - |
| A046 | pass | automated | unit | prep | Reserva permitida com artigo price 0/null (P1) | test/live_item_price_gate_test.dart |
| A047 | pass | automated | unit | prep | Seller define preÃ§o â€” grava BD + shadow (P2 label / P4 acÃ§Ã£o) | test/live_item_price_gate_test.dart |
| A048 | pass | not_implemented | bot | prep | Chat sistema Â«preÃ§o definidoÂ» apÃ³s P4 (P3) | - |
| A049 | pass | automated | unit | prep | Saco sem Pagar atÃ© preÃ§o; desbloqueia apÃ³s P4 (P4 gate) | test/live_item_price_gate_test.dart |
| A050 | pass | automated | maestro | publish | Deep link `/criarDirecto` salta preparar | .maestro/flows/v1_01_login_buyer_home.yaml |
| A051 | blocked | not_implemented | maestro | publish | ValidaÃ§Ã£o tÃ­tulo mÃ­nimo no criar directo | - |
| A052 | blocked | not_implemented | integration | publish | Edge cria stream Mux no primeiro preview | - |
| A053 | blocked | not_implemented | integration | publish | Mesmo live_id â€” nÃ£o duplica asset Mux | - |
| A054 | blocked | not_implemented | maestro | publish | Go-live com publish activo e studio | - |
| A055 | pass | automated | unit | publish | Sheet open reservations â€” confirmar go-live | test/live_start_open_reservations_service_test.dart |
| A056 | pass | automated | unit | publish | Recusar aviso cancela go-live | test/live_start_open_reservations_service_test.dart |
| A057 | manual | manual | manual | publish | Erro BD ao marcar live â€” nÃ£o publicar silenciosamente | - |
| A058 | blocked | not_implemented | integration | publish | Teardown explÃ­cito navega para player VOD | - |
| A059 | manual | manual | manual | publish | Fechar UI termina live e vai Home | - |
| A060 | blocked | not_implemented | integration | publish | Edge pÃ³s-teardown preenche `mux_vod_playback_id` | - |
| A061 | blocked | not_implemented | maestro | publish | BotÃ£o sistema back fecha directo (nÃ£o minimiza sÃ³) | - |
| A062 | blocked | not_implemented | integration | publish | Kill app com live activa â€” restart fecha Ã³rfÃ£o | - |
| A063 | blocked | not_implemented | integration | publish | `reconcileOnAppStart(fullSweep:true)` nÃ£o mata live Maestro partilhado | - |
| A064 | manual | manual | manual | publish | Publish RTMP alternativo (se flag activa) | - |
| A065 | blocked | not_implemented | maestro | publish | UX quando cÃ¢mara recusada | - |
| A066 | blocked | not_implemented | maestro | publish | UX quando microfone recusado | - |
| A067 | blocked | not_implemented | integration | publish | `stop_egress` invocado ao terminar | - |
| A068 | blocked | not_implemented | integration | publish | Falha edge â€” ended sem playback_id | - |
| A069 | blocked | not_implemented | integration | publish | Prefs `batata_active_broadcast_live_id_v1` apÃ³s kill | - |
| A070 | manual | manual | manual | publish | Staff helper nÃ£o inicia directo prÃ³prio | - |
| A071 | pass | automated | maestro | publish | `maestro_seller_studio_page_widget` debug | .maestro/flows/v1_05_seller_live_studio_smoke.yaml |
| A072 | manual | manual | manual | publish | OrientaÃ§Ã£o landscape no encode/view | - |
| A073 | manual | manual | manual | publish | Modo diagnÃ³stico preview (debug) | - |
| A074 | blocked | not_implemented | integration | publish | CatÃ¡logo prep sync na BD antes de Iniciar | - |
| A075 | blocked | not_implemented | integration | publish | Home feed mostra card LIVE apÃ³s A054 | - |
| A076 | manual | manual | manual | publish | Timeout create-mux â€” UX de espera/erro | - |
| A077 | manual | manual | manual | publish | Segundo device nÃ£o publica em paralelo | - |
| A078 | manual | manual | manual | publish | Helper HLS + painel operaÃ§Ãµes | - |
| A079 | blocked | not_implemented | maestro | publish | Rota antiga nÃ£o navega | - |
| A080 | pass | automated | bot | seller_ops | SecÃ§Ã£o Â«No sacoÂ» lista reservas pending com metadata | tool/fleaber_bot_simulator.dart |
| A081 | pass | automated | unit | seller_ops | Aceitar reserva pending â†’ accepted + stock + msg sistema | test/live_reservation_queue_service_test.dart |
| A082 | pass | automated | unit | seller_ops | Rejeitar reserva pending â†’ rejected + notificaÃ§Ã£o comprador | test/live_reservation_queue_service_test.dart |
| A083 | pass | automated | unit | seller_ops | Skip reserva pending â†’ skipped; sai da fila urgente | test/live_reservation_queue_service_test.dart |
| A084 | pass | not_implemented | bot | seller_ops | Aceitar qty > stock com dialog confirmaÃ§Ã£o vendedor | - |
| A085 | pass | not_implemented | bot | seller_ops | Reserva `bag_removed` â€” vendedor sem acÃ§Ãµes na fila | - |
| A086 | manual | manual | manual | seller_ops | Card vermelho urgente vendedor â€” T1 sim, T2 nÃ£o (BATATA) | - |
| A087 | manual | manual | manual | seller_ops | KPI OperaÃ§Ã£o Â«valor vendidoÂ» = artigo + portes + seguro (R5) | - |
| A088 | pass | automated | unit | seller_ops | Order `pago` sem convert â€” auto-reconcile ao abrir painel | test/live_reservation_queue_service_test.dart |
| A089 | pass | not_implemented | maestro | seller_ops | UI usa Â«PendentesÂ» â€” label legacy Â«A tratarÂ» ausente | - |
| A090 | skip_config_missing | not_implemented | maestro | seller_ops | SecÃ§Ã£o Â«Aceites Â· aguardar pagamentoÂ» lista accepted | - |
| A091 | pass | not_implemented | bot | seller_ops | SecÃ§Ã£o Â«Sem pagamentoÂ» â€” accepted expirados ou unpaid | - |
| A092 | pass | not_implemented | bot | seller_ops | Externos e waitlist visÃ­veis ao vendedor | - |
| A093 | manual | manual | manual | seller_ops | HistÃ³rico de reservas convertidas/rejected/skipped | - |
| A094 | skip_config_missing | not_implemented | maestro | seller_ops | SecÃ§Ã£o/filtro cancelados comprador (`bag_removed`) | - |
| A095 | blocked | automated | hybrid | seller_ops | Fluxo T1 â†’ Aceitar â†’ Pagar abre Stripe sem loop urgente | tool/regression/hybrid_runner.dart |
| A096 | manual | manual | manual | seller_ops | Aceite dispara R1 card + R2 banner comprador | - |
| A097 | pass | automated | unit | seller_ops | `batata_recompact_reservation_queue` mantÃ©m FIFO posiÃ§Ãµes | test/live_reservation_queue_service_test.dart |
| A098 | manual | manual | manual | seller_ops | Helper/staff **sem** permissÃ£o nÃ£o aceita reservas | - |
| A099 | manual | manual | manual | seller_ops | Owner seller ignora restriÃ§Ãµes staff context | - |
| A100 | manual | manual | manual | seller_ops | Toggle modo chat privado vendedor | - |
| A101 | manual | manual | manual | seller_ops | Badge unread chat privado vendedor | - |
| A102 | manual | manual | manual | seller_ops | Filtro chat Â«PerguntasÂ» | - |
| A103 | manual | manual | manual | seller_ops | Filtro chat Â«ReservasÂ» | - |
| A104 | manual | manual | manual | seller_ops | Filtro chat Â«SistemaÂ» | - |
| A105 | manual | manual | manual | seller_ops | Nome chat = `profiles.full_name` (BATATA) | - |
| A106 | manual | manual | manual | seller_ops | Imagens comprador renderizam no chat pÃºblico seller | - |
| A107 | pass | not_implemented | integration | seller_ops | Tab Pagamentos lista orders convertidas da live | - |
| A108 | pass | not_implemented | integration | seller_ops | Log `reservation.load` inclui `stale_reconciled` count | - |
| A109 | pass | not_implemented | integration | seller_ops | Log studio `reservation.accept` com qty metadata | - |
| A110 | pass | not_implemented | integration | seller_ops | Log `checkout.pay_qty_gate` ao Pagar qty>stock | - |
| A111 | pass | not_implemented | bot | seller_ops | VÃ¡rios compradores â€” ordem FIFO na fila seller e chips comprador | - |
| A112 | pass | not_implemented | bot | seller_ops | Race: dois aceites simultÃ¢neos â€” sÃ³ um ganha stock | - |
| A113 | pass | not_implemented | integration | seller_ops | ExpiraÃ§Ã£o automÃ¡tica reserva pending/accepted | - |
| A114 | pass | not_implemented | bot | seller_ops | Waitlist e pedidos externos visÃ­veis na OperaÃ§Ã£o | - |
| A115 | manual | manual | manual | seller_ops | Tip/gorjeta visÃ­vel no painel vendedor | - |
| A116 | manual | manual | manual | seller_ops | KPI vendas exclui gorjetas | - |
| A117 | pass | not_implemented | bot | seller_ops | Vendedor cria rifa activa na live | - |
| A118 | pass | not_implemented | bot | seller_ops | Fechar entradas rifa (stop join) | - |
| A119 | pass | not_implemented | bot | seller_ops | Sortear vencedores rifa seller | - |
| A120 | pass | not_implemented | bot | seller_ops | Cancelar rifa activa | - |
| A121 | skip_config_missing | not_implemented | maestro | seller_ops | Toggle leaderboard pÃºblico rifa | - |
| A122 | skip_config_missing | not_implemented | maestro | seller_ops | Barra operaÃ§Ãµes rifa integrada no painel OperaÃ§Ã£o | - |
| A123 | manual | manual | manual | seller_ops | Menu Â«MaisÂ» studio â€” acÃ§Ãµes secundÃ¡rias | - |
| A124 | manual | manual | manual | seller_ops | Placeholder bundle discount Â«em breveÂ» | - |
| A125 | manual | manual | manual | seller_ops | Vendedor recusa over-stock no dialog (nÃ£o aceita qty>stock) | - |
| A126 | pass | automated | unit | seller_ops | Aceite bloqueado/aviso quando stock pool noutro directo (Z82) | test/live_reservation_queue_service_test.dart |
| A127 | pass | not_implemented | integration | seller_ops | RPC `batata_live_mark_qty_confirm_needed` ao Pagar qty>stock | - |
| A128 | pass | automated | unit | seller_ops | Strings ERP/qty_confirm **nÃ£o** aparecem no chat pÃºblico | test/live_public_chat_line_test.dart |
| A129 | pass | not_implemented | bot | seller_ops | Actividade: Â«adicionou ao sacoÂ» sÃ³ pending aberto; cancel remove evento | - |
| A130 | pass | not_implemented | bot | catalog | Activar vitrine (is_active) no catÃ¡logo | - |
| A131 | manual | manual | manual | catalog | Barra catÃ¡logo alinhada com `available_qty` RPC | - |
| A132 | pass | not_implemented | integration | catalog | Repor stock apÃ³s sold â€” catÃ¡logo e carrossel sync | - |
| A133 | pass | not_implemented | bot | catalog | Badge ESGOTADO nunca sÃ³ por pending | - |
| A134 | manual | manual | manual | catalog | Editar preÃ§o inline no catÃ¡logo live | - |
| A135 | manual | manual | manual | catalog | Editar descriÃ§Ã£o inline no catÃ¡logo live | - |
| A136 | manual | manual | manual | catalog | Alterar fotos do artigo durante live | - |
| A137 | manual | manual | manual | catalog | Editar estado/condiÃ§Ã£o do artigo no live | - |
| A138 | manual | manual | manual | catalog | Opt-in marketplace no catÃ¡logo live | - |
| A139 | manual | manual | manual | catalog | Poll stock cross-session cada ~2s | - |
| A140 | manual | manual | manual | catalog | KPI vendidos incrementa pÃ³s-pagamento | - |
| A141 | pass | not_implemented | bot | catalog | KPI reservas reflecte pending | - |
| A142 | manual | manual | manual | catalog | Barra catÃ¡logo apÃ³s aceite parcial qty multi | - |
| A143 | manual | manual | manual | catalog | Rollback UI se RPC vitrine falha | - |
| A144 | pass | automated | integration | catalog | `quantity` BD sync apÃ³s +/- stock | tool/regression_integration.dart |
| A145 | pass | automated | maestro | buyer_player | Entrada player via card LIVE Home | .maestro/flows/v1_02_buyer_live_player.yaml |
| A146 | skip_config_missing | not_implemented | maestro | buyer_player | Player VOD via perfil vendedor | - |
| A147 | pass | not_implemented | integration | buyer_player | Referral rifa via deep link | - |
| A148 | pass | automated | bot | buyer_player | Primeira reserva â€” pending + chat | tool/fleaber_bot_simulator.dart |
| A149 | pass | automated | bot | buyer_player | Segunda reserva incrementa qty â€” nÃ£o duplica row | tool/fleaber_bot_simulator.dart |
| A150 | pass | not_implemented | bot | buyer_player | Fila de espera quando stock esgotado por aceite | - |
| A151 | blocked | automated | hybrid | buyer_player | Card verde comprador ao aceite â€” sem dialog duplicado | tool/regression/hybrid_runner.dart |
| A152 | skip_config_missing | not_implemented | maestro | buyer_player | Banner saco sÃ³ em `status=accepted` | - |
| A153 | skip_config_missing | not_implemented | maestro | buyer_player | CTA Pagar no saco e player quando payable | - |
| A154 | manual | manual | manual | buyer_player | Stepper +/- qty persiste ao reabrir saco | - |
| A155 | manual | manual | manual | buyer_player | Chips por unidade â€” cores verde/Ã¢mbar | - |
| A156 | pass | automated | bot | buyer_player | Contador espectadores incrementa ao entrar | tool/fleaber_bot_simulator.dart |
| A157 | skip_config_missing | not_implemented | maestro | buyer_player | Seguir vendedor no player | - |
| A158 | manual | manual | manual | buyer_player | Checkout directo sem passar aceite vendedor | - |
| A159 | manual | manual | manual | buyer_player | Highlight carrossel segue vitrine seller | - |
| A160 | pass | not_implemented | integration | buyer_player | Comprador remove reserva do saco (prÃ©-pagamento) | - |
| A161 | pass | automated | bot | buyer_player | Comprador envia mensagem chat pÃºblico | tool/fleaber_bot_simulator.dart |
| A162 | skip_config_missing | not_implemented | maestro | buyer_player | Input chat desactivado em VOD/replay | - |
| A163 | manual | manual | manual | buyer_player | Mensagem privada comprador para vendedor | - |
| A164 | skip_config_missing | not_implemented | maestro | buyer_player | Partilhar link da live (copy) | - |
| A165 | manual | manual | manual | buyer_player | Overlay spotlight no artigo activo | - |
| A166 | pass | automated | unit | buyer_player | Portes visÃ­veis antes de abrir Stripe | test/live_checkout_fees_test.dart |
| A167 | pass | automated | unit | buyer_player | Linha seguro no preview checkout comprador | test/live_checkout_fees_test.dart |
| A168 | manual | manual | manual | buyer_player | Retomar app apÃ³s Stripe â€” reconcile pending | - |
| A169 | manual | manual | manual | buyer_player | Playback HLS live com latÃªncia reduzida | - |
| A170 | manual | manual | manual | buyer_player | Rota player invÃ¡lida â€” fallback seguro | - |
| A171 | manual | manual | manual | buyer_player | PDP marketplace preserva contexto live | - |
| A172 | manual | manual | manual | buyer_player | KPI Reservas carrossel inclui cross-live/blocked | - |
| A173 | pass | not_implemented | bot | buyer_player | UI distingue indisponÃ­vel de waitlist | - |
| A174 | manual | manual | manual | buyer_player | Enviar gorjeta na live | - |
| A175 | manual | manual | manual | buyer_player | Reentrada player â€” anÃºncio compras recentes | - |
| A176 | manual | manual | manual | buyer_player | OrientaÃ§Ã£o ecrÃ£ player | - |
| A177 | pass | not_implemented | integration | buyer_player | Cache catÃ¡logo invalida apÃ³s mutaÃ§Ã£o seller | - |
| A178 | pass | not_implemented | bot | buyer_player | Supabase realtime actualiza carrossel | - |
| A179 | pass | not_implemented | bot | buyer_player | Saco actualiza realtime (aceite/reject) | - |
| A180 | manual | manual | manual | buyer_player | Aceite realtime robusto â€” payload sem user_id | - |
| A181 | manual | manual | manual | buyer_player | Erro amigÃ¡vel â€” fila vs bloqueio total | - |
| A182 | skip_config_missing | not_implemented | maestro | buyer_player | Carrossel com muitos artigos â€” scroll e performance | - |
| A183 | pass | not_implemented | integration | buyer_player | Feed Home coerente com BD `status`/`is_active` | - |
| A184 | skip_config_missing | not_implemented | maestro | buyer_player | Param `forceVod` forÃ§a modo replay | - |
| A185 | pass | not_implemented | integration | buyer_player | Param `sellerId` na rota player | - |
| A186 | manual | manual | manual | buyer_player | Multi-device â€” saco sync mesma conta | - |
| A187 | pass | not_implemented | integration | buyer_player | Referral visit anÃ³nimo atribuÃ­do pÃ³s-login | - |
| A188 | skip_config_missing | not_implemented | maestro | buyer_player | Join rifa via sidebar player | - |
| A189 | skip_config_missing | not_implemented | maestro | buyer_player | Join rifa via sheet modal +1 entrada | - |
| A190 | skip_config_missing | automated | maestro | checkout | Sheet Â«Saco da liveÂ» abre com secÃ§Ãµes | .maestro/flows/v1_03_buyer_bag_sheet.yaml |
| A191 | pass | not_implemented | bot | checkout | Linhas pending no saco com metadata correcta | - |
| A192 | pass | automated | bot | checkout | Reserva em fila quando stock cheio | tool/fleaber_bot_simulator.dart |
| A193 | pass | not_implemented | integration | checkout | HistÃ³rico converted no saco | - |
| A194 | pass | automated | unit | checkout | Cancelamento comprador no saco | test/order_status_test.dart |
| A195 | manual | manual | manual | checkout | Seleccionar linhas a pagar no saco | - |
| A196 | manual | manual | manual | checkout | Fotos dos artigos nas linhas do checkout | - |
| A197 | pass | not_implemented | integration | checkout | Duas reservas mesma ref â†’ 1 linha qty 2 | - |
| A198 | pass | automated | integration | checkout | Checkout saco multi-ref â€” POST create-payment-intent | tool/regression_integration.dart |
| A199 | pass | automated | unit | checkout | Linha portes Envio Transportadora no checkout | test/live_checkout_fees_test.dart |
| A200 | pass | not_implemented | unit | checkout | Entrega em mÃ£o sem portes | - |
| A201 | pass | automated | unit | checkout | ProtecÃ§Ã£o Fleaber no breakdown | test/fee_calculator_test.dart |
| A202 | pass | automated | unit | checkout | PreÃ§o pendente â€” Pagar bloqueado | test/live_item_price_gate_test.dart |
| A203 | manual | manual | manual | checkout | Stepper checkout reflecte qty aceite over-stock | - |
| A204 | manual | manual | manual | checkout | Comprador vÃª dialog; vendedor card urgente â€” sÃ³ ao Pagar | - |
| A205 | manual | manual | manual | checkout | URL checkout Stripe ao confirmar pagamento | - |
| A206 | pass | automated | integration | checkout | Retorno success â†’ converted + order pago | tool/regression_integration.dart |
| A207 | manual | manual | manual | checkout | Cancelar checkout Stripe mantÃ©m reserva | - |
| A208 | pass | automated | integration | checkout | Um checkout Stripe â†’ 2 orders pago | tool/regression_integration.dart |
| A209 | pass | automated | integration | checkout | Reconcile manual/API order pago Ã³rfÃ£ | tool/regression_integration.dart |
| A210 | pass | not_implemented | bot | checkout | Chat Â«comprouÂ» apÃ³s reconcile | - |
| A211 | manual | manual | manual | checkout | BÃ³nus rifa +2 apÃ³s compra live | - |
| A212 | pass | not_implemented | bot | checkout | Entrar na rifa durante directo (+1) | - |
| A213 | pass | not_implemented | bot | checkout | Partilha social +2 entradas | - |
| A214 | pass | automated | unit | checkout | Visitante referral â€” qualificaÃ§Ã£o 60s | test/fee_calculator_test.dart |
| A215 | pass | not_implemented | bot | checkout | Ranking top 5 entradas | - |
| A216 | pass | not_implemented | unit | checkout | Countdown mm:ss atÃ© fecho | - |
| A217 | pass | not_implemented | unit | checkout | Broadcast rifa sem spam no chat | - |
| A218 | pass | not_implemented | bot | checkout | Sorteio + notificaÃ§Ã£o vencedores | - |
| A219 | pass | not_implemented | integration | checkout | Movimento wallet vendedor apÃ³s order pago | - |
| A220 | pass | not_implemented | integration | checkout | Fee platform na libertaÃ§Ã£o | - |
| A221 | manual | manual | manual | checkout | Disputa em encomenda originada na live | - |
| A222 | manual | manual | manual | checkout | DevoluÃ§Ã£o pÃ³s-pago (cancelamento depois de pagar) | - |
| A223 | manual | manual | manual | checkout | Order list com `live_id` | - |
| A224 | manual | manual | manual | checkout | Gorjeta independente do saco | - |
| A225 | pass | not_implemented | integration | checkout | Item shadow â€” `checkout_product_id` no pagamento | - |
| A226 | pass | not_implemented | integration | checkout | TYPE A â€” `product_id` marketplace no order | - |
| A227 | pass | automated | unit | checkout | PreÃ§o definido â†’ CTA Pagar habilita (incl. aceite sem preÃ§o antes) | test/live_item_price_gate_test.dart |
| A228 | pass | not_implemented | integration | checkout | Seller nÃ£o pode alterar preÃ§o apÃ³s venda/convert | - |
| A229 | manual | manual | manual | checkout | Single vs bag vs tip â€” prefs nÃ£o sobrescrevem | - |
| A230 | pass | automated | integration | checkout | Cancelamento comprador **antes** de pagar | tool/regression_integration.dart |
| A231 | pass | not_implemented | integration | payments | `/operacoesLive` â€” cards sessÃ£o com KPIs agregados | - |
| A232 | pass | not_implemented | integration | payments | TransiÃ§Ã£o visual e BD order live checkout | - |
| A233 | manual | manual | manual | payments | Reembolso parcial encomenda originada na live | - |
| A234 | manual | manual | manual | payments | Reembolso integral pÃ³s-pago live | - |
| A235 | manual | manual | manual | payments | `order_disputes` criada para order com `live_id` | - |
| A236 | manual | manual | manual | payments | Seller responde disputa; thread `order_dispute_replies` | - |
| A237 | manual | manual | manual | payments | Estado `escalada_fleaber` + painel admin | - |
| A238 | manual | manual | manual | payments | Levantamento wallet apÃ³s crÃ©ditos de orders live | - |
| A239 | manual | manual | manual | payments | Push/in-app pÃ³s-pagamento saco live | - |
| A240 | pass | not_implemented | integration | payments | Fee platform em settle 2+ orders (saco) | - |
| A241 | manual | manual | manual | payments | Painel in-stream: tips separados de `sales_value_eur` | - |
| A242 | pass | not_implemented | integration | payments | Tips incluÃ­dos no resumo `/resultadosLive` sem misturar receita artigos | - |
| A243 | pass | not_implemented | integration | payments | Alerta `hasAlerts` â€” order `pago` sem reserva `converted` | - |
| A244 | pass | not_implemented | integration | payments | AcÃ§Ã£o refresh/reconcile no pÃ³s-live converte Ã³rfÃ£os | - |
| A245 | manual | manual | manual | payments | Exportar ou copiar resumo comercial da sessÃ£o | - |
| A246 | skip_config_missing | not_implemented | maestro | payments | Minhas encomendas destaca/filtra orders com `live_id` | - |
| A247 | pass | not_implemented | integration | payments | Lista vendas sessÃ£o filtra por estado pago/disputa/devoluÃ§Ã£o | - |
| A248 | pass | not_implemented | integration | payments | Procedimento operacional stale order documentado e reproduzÃ­vel | - |
| A249 | pass | not_implemented | integration | payments | 2.Âª chamada reconcile nÃ£o duplica crÃ©dito/conversÃ£o | - |
| A250 | pass | automated | unit | raffle | Suite H04: bot join + buyer Maestro Â«Participar na Rifa (+1)Â» | test/live_raffle_service_test.dart |
| A251 | pass | automated | bot | raffle | Follow seller durante rifa â€” `follow_bonus_claimed` | tool/fleaber_bot_simulator.dart |
| A252 | pass | automated | unit | raffle | Partilha social â€” `batata_claim_live_raffle_share_intent` | test/live_raffle_service_test.dart |
| A253 | pass | automated | unit | raffle | `ensureReferralLink` + `registerReferralVisit` | test/live_raffle_service_test.dart |
| A254 | pass | automated | unit | raffle | `qualifyReferralVisits` apÃ³s permanÃªncia | test/live_raffle_service_test.dart |
| A255 | pass | automated | unit | raffle | Ranking comprador actualizado com entradas | test/live_raffle_service_test.dart |
| A256 | pass | automated | unit | raffle | Vendedor vÃª resumo participantes na ops bar | test/live_raffle_service_test.dart |
| A257 | pass | automated | unit | raffle | Ordem cronolÃ³gica entradas preservada no sorteio | test/live_raffle_service_test.dart |
| A258 | pass | automated | bot | raffle | Abrir live via link referral prÃ©-preenche contexto rifa | tool/fleaber_bot_simulator.dart |
| A259 | pass | automated | bot | raffle | Seguir vendedor nÃ£o dispara spam notificaÃ§Ãµes (P15 overlap) | tool/fleaber_bot_simulator.dart |
| A260 | pass | automated | bot | raffle | Re-share imediato nÃ£o duplica +2 | tool/fleaber_bot_simulator.dart |
| A261 | pass | automated | bot | raffle | Vendedor dispara sorteio â€” `batata_draw_live_raffle_winners` | tool/fleaber_bot_simulator.dart |
| A262 | pass | automated | bot | raffle | Timer zero â†’ close + draw automÃ¡tico (se polÃ­tica activa) | tool/fleaber_bot_simulator.dart |
| A263 | pass | automated | bot | raffle | Sorteio auditÃ¡vel â€” `tickets_at_draw` por winner | tool/fleaber_bot_simulator.dart |
| A264 | pass | automated | bot | raffle | AnÃºncio draw no chat pÃºblico humanizado | tool/fleaber_bot_simulator.dart |
| A265 | pass | automated | bot | raffle | Vencedor recebe push Â«Ganhaste a rifaÂ» | tool/fleaber_bot_simulator.dart |
| A266 | pass | automated | bot | raffle | Seller notificado sorteio concluÃ­do | tool/fleaber_bot_simulator.dart |
| A267 | pass | automated | bot | raffle | Replay gravado: countdown histÃ³rico; join/participar bloqueado | tool/fleaber_bot_simulator.dart |
| A268 | pass | automated | bot | raffle | Guard `_liveIsActive` bloqueia join em ended | tool/fleaber_bot_simulator.dart |
| A269 | pass | automated | bot | raffle | BÃ³nus share/referral nÃ£o disponÃ­veis em replay | tool/fleaber_bot_simulator.dart |
| A270 | pass | automated | bot | raffle | Rajada eventos rifa (join, +2, draw) sem spam chat | tool/fleaber_bot_simulator.dart |
| A271 | skip_config_missing | automated | maestro | raffle | Flow Maestro comprador rifa+saco sem falha | .maestro/flows/v2_buyer_raffle_bag.yaml |
| A272 | skip_config_missing | not_implemented | maestro | raffle | `v2_seller_harness_accept` + ops bar rifa visÃ­vel | - |
| A273 | pass | automated | bot | raffle | `LiveRafflePrizeEditSheet` actualiza tÃ­tulo/imagem | tool/fleaber_bot_simulator.dart |
| A274 | pass | automated | bot | raffle | Imagem e tÃ­tulo prÃ©mio no `LiveRaffleBuyerCard` | tool/fleaber_bot_simulator.dart |
| A275 | pass | automated | bot | raffle | Seller cancela rifa â€” comprador vÃª estado cancelado | tool/fleaber_bot_simulator.dart |
| A276 | pass | automated | bot | raffle | BÃ³nus A211 nÃ£o duplica em reconcile/repay | tool/fleaber_bot_simulator.dart |
| A277 | pass | automated | bot | raffle | 20+ bots join/share â€” leaderboard estÃ¡vel | tool/fleaber_bot_simulator.dart |
| A278 | pass | automated | unit | raffle | `show_public_leaderboard=false` esconde ranking | test/live_raffle_service_test.dart |
| A279 | blocked | automated | hybrid | raffle | Suite H04 completa: bot seed â†’ Maestro â†’ verify BD | tool/regression/hybrid_runner.dart |
| A280 | pass | automated | unit | messages | Mensagem pÃºblica de reserva no chat | test/live_public_chat_line_test.dart |
| A281 | pass | automated | unit | messages | Mensagem de aceite oculta no chat pÃºblico | test/live_public_chat_line_test.dart |
| A282 | pass | automated | unit | messages | Mensagem pÃºblica pÃ³s-compra | test/live_public_chat_line_test.dart |
| A283 | pass | automated | unit | messages | Mensagem Â«PreÃ§o definidoÂ» apÃ³s seller definir preÃ§o | test/live_public_chat_line_test.dart |
| A284 | pass | automated | unit | messages | Broadcast FOMO Â«Ãºltima unidadeÂ» | test/live_public_chat_line_test.dart |
| A285 | pass | automated | unit | messages | Broadcast FOMO Â«artigo esgotouÂ» | test/live_public_chat_line_test.dart |
| A286 | pass | automated | unit | messages | Mensagem de gorjeta visÃ­vel no chat | test/live_public_chat_line_test.dart |
| A287 | pass | automated | unit | messages | Mensagem de cancelamento comprador | test/live_public_chat_line_test.dart |
| A288 | pass | automated | unit | messages | Recusa vendedor sÃ³ backoffice | test/live_public_chat_line_test.dart |
| A289 | pass | automated | unit | messages | Uma linha Â«comprouÂ» por par comprador+artigo | test/live_public_chat_line_test.dart |
| A290 | pass | automated | unit | messages | Prazo de pagamento nÃ£o aparece no chat pÃºblico | test/live_public_chat_line_test.dart |
| A291 | manual | manual | manual | messages | Prazo aceite reflecte valor SQL | - |
| A292 | pass | automated | unit | messages | NormalizaÃ§Ã£o Â«ao sacoÂ» â†’ Â«ao carrinhoÂ» | test/live_public_chat_line_test.dart |
| A293 | pass | automated | unit | messages | Mensagem social de adiÃ§Ã£o ao saco | test/live_public_chat_line_test.dart |
| A294 | pass | automated | unit | messages | Alerta qty>stock oculto do chat pÃºblico | test/live_public_chat_line_test.dart |
| A295 | manual | manual | manual | messages | Mensagens aparecem no instante de playback (gravado) | - |
| A296 | manual | manual | manual | messages | Highlight carrossel segue timeline gravado | - |
| A297 | pass | not_implemented | bot | messages | Reserva permitida em live terminada | - |
| A298 | skip_config_missing | not_implemented | maestro | messages | Checkout permitido em VOD | - |
| A299 | manual | manual | manual | messages | UX gorjeta em VOD | - |
| A300 | skip_config_missing | not_implemented | maestro | messages | Feed Home abre gravado com HLS VOD | - |
| A301 | manual | manual | manual | messages | Painel operaÃ§Ãµes live â€” KPIs sessÃ£o | - |
| A302 | pass | not_implemented | integration | messages | Gravado sem playback_id | - |
| A303 | pass | not_implemented | integration | messages | Comprador vÃª lives ended no feed | - |
| A304 | pass | not_implemented | unit | messages | Broadcast rifa no chat sem prefixo duplicado | - |
| A305 | pass | not_implemented | unit | messages | Mensagem aceite visÃ­vel no chat pÃºblico (variante social) | - |
| A306 | manual | manual | manual | messages | Copy overlay Â«Ficaste com {Artigo}Â» | - |
| A307 | pass | automated | unit | messages | PreÃ§o â‚¬ nÃ£o aparece na linha Â«comprouÂ» | test/live_public_chat_line_test.dart |
| A308 | pass | not_implemented | bot | messages | Duas mensagens FOMO em ordem lÃ³gica | - |
| A309 | pass | automated | unit | messages | Mensagens com `/` ou campos ERP ocultas | test/live_public_chat_line_test.dart |
| A310 | skip_config_missing | not_implemented | maestro | gravado | Entrada directa VOD por URL | - |
| A311 | pass | not_implemented | integration | gravado | BD `ended` forÃ§a VOD mesmo com isLive=true no link | - |
| A312 | blocked | not_implemented | integration | gravado | VOD aparece apÃ³s complete-mux async | - |
| A313 | skip_config_missing | not_implemented | maestro | gravado | Texto Â«Chat da gravaÃ§Ã£oâ€¦Â» sem input | - |
| A314 | manual | manual | manual | gravado | NÃ£o paginar histÃ³rico infinito em replay | - |
| A315 | manual | manual | manual | gravado | Buyer nÃ£o envia privado em VOD | - |
| A316 | manual | manual | manual | gravado | Timer poll catÃ¡logo off em replay | - |
| A317 | manual | manual | manual | gravado | CompensaÃ§Ã£o atraso inÃ­cio vÃ­deo | - |
| A318 | manual | manual | manual | gravado | Replay inÃ­cio limpa msgs posteriores | - |
| A319 | manual | manual | manual | gravado | Mensagens acumuladas atÃ© playhead | - |
| A320 | manual | manual | manual | gravado | Eventos Â«mostrarÂ» conduzem vitrine replay | - |
| A321 | skip_config_missing | not_implemented | maestro | gravado | Feedback ao tentar chat live em gravado | - |
| A322 | pass | not_implemented | bot | gravado | Bag scope Ã  live gravada | - |
| A323 | manual | manual | manual | gravado | Commerce pÃ³s-live sem studio activo | - |
| A324 | skip_config_missing | not_implemented | maestro | gravado | Rifa inactiva em gravado | - |
| A325 | pass | not_implemented | integration | gravado | Contador viewers sÃ³ em live | - |
| A326 | pass | not_implemented | bot | gravado | Reserva em VOD gera linha social | - |
| A327 | pass | not_implemented | integration | gravado | Resolver URL VOD quando live stream parou | - |
| A328 | blocked | not_implemented | integration | gravado | Asset Mux persistido | - |
| A329 | skip_config_missing | not_implemented | maestro | gravado | Grid gravados no perfil vendedor | - |
| A330 | pass | not_implemented | integration | gravado | Vendas em 2 gravados mesma linhagem | - |
| A331 | manual | manual | manual | gravado | Scrub bar altera vitrine replay | - |
| A332 | pass | not_implemented | integration | gravado | HistÃ³rico ref apÃ³s venda em VOD | - |
| A333 | manual | manual | manual | gravado | Comprador na live quando termina | - |
| A334 | manual | manual | manual | gravado | Mensagens com imagem no replay | - |
| A335 | pass | not_implemented | integration | gravado | Venda VOD via marketplace product | - |
| A336 | pass | not_implemented | integration | gravado | ReconciliaÃ§Ã£o UI sessÃ£o vs orders | - |
| A337 | manual | manual | manual | gravado | Filtro ended no dashboard web | - |
| A338 | pass | not_implemented | integration | gravado | Buyer lÃª msgs de live ended | - |
| A339 | manual | manual | manual | gravado | Produto marketplace reflecte stock pÃ³s-VOD | - |
| A340 | pass | automated | integration | cross_pool | Stock partilhado RR1 â€” 8 disp / 2 vendidos | tool/regression_integration.dart |
| A341 | pass | automated | integration | cross_pool | Unidades bloqueadas noutro directo reflectidas na UI | tool/regression_integration.dart |
| A342 | pass | automated | integration | cross_pool | KPI Reservas inclui reservas noutras lives | tool/regression_integration.dart |
| A343 | pass | automated | integration | cross_pool | Branch SQL product_id-only em vendidos | tool/regression_integration.dart |
| A344 | pass | automated | integration | cross_pool | Reserva converted + order pago = 1 un. vendida | tool/regression_integration.dart |
| A345 | pass | not_implemented | integration | cross_pool | Popup inÃ­cio live lista reservas gravado (linhagem) | - |
| A346 | pass | not_implemented | integration | cross_pool | Popup inÃ­cio live â€” origem Marketplace | - |
| A347 | pass | not_implemented | integration | cross_pool | Listar produto marketplace no catÃ¡logo live (TYPE A) | - |
| A348 | manual | manual | manual | cross_pool | SincronizaÃ§Ã£o UI apÃ³s venda noutro device | - |
| A349 | pass | not_implemented | integration | cross_pool | Sync prep nÃ£o apaga listing marketplace | - |
| A350 | skip_config_missing | not_implemented | maestro | marketplace | NavegaÃ§Ã£o carrossel â†’ PDP com contexto live | - |
| A351 | pass | not_implemented | integration | marketplace | Home feed lista produto apÃ³s `list_on_marketplace=true` | - |
| A352 | pass | not_implemented | integration | marketplace | Venda live decrementa qty visÃ­vel no PDP | - |
| A353 | pass | not_implemented | bot | marketplace | SuperfÃ­cies mostram preÃ§o correcto por canal | - |
| A354 | pass | not_implemented | integration | marketplace | Pool RR1 com vendas live, gravado e reserva marketplace | - |
| A355 | pass | automated | integration | marketplace | PDP e live items partilham linhagem via `logical_item_id` | tool/regression_integration.dart |
| A356 | pass | not_implemented | integration | marketplace | Prep mostra histÃ³rico vendas marketplace da ref | - |
| A357 | manual | manual | manual | marketplace | Toggle Â«Listar no marketplaceÂ» durante directo activo | - |
| A358 | manual | manual | manual | marketplace | Foto quick edit live propaga carrossel + PDP | - |
| A359 | pass | not_implemented | integration | marketplace | Shadow `live_only` ausente do feed marketplace | - |
| A360 | pass | not_implemented | integration | marketplace | Compra orgÃ¢nica PDP â€” preÃ§o `products.price`, nÃ£o live | - |
| A361 | skip_config_missing | not_implemented | maestro | marketplace | PDP indica sessÃ£o live activa ligada ao artigo | - |
| A362 | pass | not_implemented | integration | marketplace | Reserva aceite noutro live reduz qty PDP | - |
| A363 | pass | not_implemented | bot | marketplace | Reservas noutras lives visÃ­veis no stock PDP | - |
| A364 | manual | manual | manual | marketplace | Toggle OFF remove marketplace feed; item permanece no carrossel | - |
| A365 | pass | not_implemented | integration | marketplace | Marketplace listing sobrevive fim do directo | - |
| A366 | manual | manual | manual | marketplace | Total Â· Disp Â· Reservas alinhados catÃ¡logo â†” marketplace | - |
| A367 | pass | not_implemented | integration | marketplace | Order marketplace decrementa stock carrossel live | - |
| A368 | pass | not_implemented | integration | marketplace | Novo directo inherit marketplace item â€” 1 product row | - |
| A369 | pass | not_implemented | integration | marketplace | Re-sync prep nÃ£o quebra bridge marketplaceâ†”liveâ†”pool | - |
| A370 | pass | not_implemented | integration | helpers | Seller convida colaborador por e-mail | - |
| A371 | pass | not_implemented | integration | helpers | Colaborador aceita convite pendente | - |
| A372 | manual | manual | manual | helpers | Painel operacional helper sobre HLS (sem cÃ¢mara) | - |
| A373 | pass | not_implemented | bot | helpers | Helper com `can_manage_reservations` aceita reserva | - |
| A374 | manual | manual | manual | helpers | `can_end_live=false` â€” sem CTA terminar | - |
| A375 | pass | not_implemented | integration | helpers | Helper sem permissÃ£o reservas â€” aceitar bloqueado | - |
| A376 | manual | manual | manual | helpers | Alternar entre loja prÃ³pria e loja assistida | - |
| A377 | pass | not_implemented | integration | helpers | Colaborador recusa convite pendente | - |
| A378 | pass | not_implemented | integration | helpers | Remover/desactivar colaborador aceite | - |
| A379 | manual | manual | manual | helpers | Helper sem editar anÃºncios â€” catÃ¡logo live read-only | - |
| A380 | pass | not_implemented | integration | helpers | Dupla verificaÃ§Ã£o terminar live (UI + servidor) | - |
| A381 | pass | not_implemented | bot | helpers | `can_change_current_item` â€” spotlight no carrossel | - |
| A382 | pass | not_implemented | bot | helpers | `can_manage_chat` â€” resposta/moderar no studio | - |
| A383 | manual | manual | manual | helpers | Helper sem ver saldo/wallet/pagamentos | - |
| A384 | manual | manual | manual | helpers | Helper nÃ£o gere outros colaboradores | - |
| A385 | pass | not_implemented | integration | helpers | Convite falha se utilizador nÃ£o registado | - |
| A386 | pass | not_implemented | integration | helpers | Segundo convite mesmo helper bloqueado | - |
| A387 | pass | not_implemented | maestro | helpers | `helperLinkId` expirado ou de outro user | - |
| A388 | manual | manual | manual | helpers | Seller muda perms â€” helper vÃª gate apÃ³s refresh | - |
| A389 | pass | not_implemented | integration | helpers | Bypass UI nÃ£o contorna servidor | - |
| A390 | manual | manual | manual | errors | Timeout Supabase â€” snack retry sem crash | - |
| A391 | manual | manual | manual | errors | Queda realtime â€” reconexÃ£o automÃ¡tica | - |
| A392 | blocked | not_implemented | integration | errors | Edge Mux lenta â€” publish nÃ£o fica zombie | - |
| A393 | skip_config_missing | not_implemented | maestro | errors | Corrida CI â€” dois flows mesmo seller/live | - |
| A394 | skip_config_missing | not_implemented | maestro | errors | Login Maestro sem Application Not Responding | - |
| A395 | pass | not_implemented | bot | errors | Stress 5 compradores reservam em paralelo | - |
| A396 | pass | not_implemented | integration | errors | Seller com 2 lives draft â€” sÃ³ uma activa | - |
| A397 | manual | manual | manual | errors | Publish device A nÃ£o morre com login fullSweep device B | - |
| A398 | blocked | automated | hybrid | errors | H07 pipeline â€” bot prepara, Maestro valida | tool/regression/hybrid_runner.dart |
| A399 | manual | manual | manual | errors | Checkout com autenticaÃ§Ã£o forte Stripe | - |
| A400 | manual | manual | manual | errors | Overlay web studio â€” dialog qty (C8B) | - |
| A401 | pass | not_implemented | integration | errors | Token Supabase expira mid-session â€” auto-refresh | - |
| A402 | pass | not_implemented | integration | errors | Refresh falha â€” utilizador deslogado com mensagem | - |
| A403 | manual | manual | manual | errors | Sem rede â€” reserva com feedback retry | - |
| A404 | manual | manual | manual | errors | Vendedor offline â€” aceitar nÃ£o aplica silenciosamente | - |
| A405 | manual | manual | manual | errors | Retomar app apÃ³s background prolongado | - |
| A406 | pass | not_implemented | bot | errors | Duplo tap Reservar â€” dedupe ou increment qty | - |
| A407 | pass | not_implemented | bot | errors | 10+ reservas rÃ¡pidas mesmo buyer â€” throttling | - |
| A408 | pass | not_implemented | bot | errors | Spam chat pÃºblico â€” throttle | - |
| A409 | pass | not_implemented | integration | errors | Falha edge pagamento â€” UI retry sem perder saco | - |
| A410 | manual | manual | manual | errors | PÃ³s-Stripe sem rede â€” context pending sobrevive | - |
| A411 | pass | not_implemented | integration | errors | Colaborador nÃ£o acede dados de outra loja | - |
| A412 | manual | manual | manual | errors | Directo termina durante checkout â€” Pagar bloqueado | - |
| A413 | pass | not_implemented | integration | errors | Force-close durante broadcast â€” cleanup no prÃ³ximo start | - |
| A414 | manual | manual | manual | errors | Logout/login outro buyer â€” saco isolado | - |
| A415 | pass | not_implemented | integration | errors | Seller + helper aceitam simultaneamente â€” idempotente | - |
| A416 | pass | not_implemented | bot | errors | Subscription morta â€” poll corrige UI | - |
| A417 | manual | manual | manual | errors | PressÃ£o memÃ³ria â€” player nÃ£o ANR/crash | - |
| A418 | skip_config_missing | not_implemented | maestro | errors | NavegaÃ§Ã£o para live inexistente | - |
| A419 | pass | not_implemented | bot | errors | Stock 1, N buyers â€” sÃ³ posiÃ§Ã£o #1 aceitÃ¡vel sem overbook | - |
| A420 | pass | not_implemented | integration | sync | Auditoria studio â€” eventos crÃ­ticos logados | - |
| A421 | pass | not_implemented | integration | sync | Recompact fila apÃ³s remove/cancel | - |
| A422 | pass | not_implemented | unit | sync | Timer poll cancela ao sair do ecrÃ£ | - |
| A423 | manual | manual | manual | sync | Painel pagamentos lista antes de totais agregados | - |
| A424 | pass | not_implemented | integration | sync | Apenas buyer da order pode reconcile/convert | - |
| A425 | pass | not_implemented | integration | sync | RLS impede leak mensagens privadas no chat pÃºblico | - |
| A426 | manual | manual | manual | sync | Modo chat privado sellerâ†”buyer no studio | - |
| A427 | pass | not_implemented | integration | sync | Egress Ã³rfÃ£o LiveKit â€” job cleanup | - |
| A428 | manual | manual | manual | sync | Card gravado home â€” thumbnail sem autoplay | - |
| A429 | pass | not_implemented | integration | sync | `available_qty` decrementa exactamente 1Ã— por aceite | - |
