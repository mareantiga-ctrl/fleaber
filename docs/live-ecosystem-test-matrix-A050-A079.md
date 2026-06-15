# Matriz expandida — A050 a A079

**Área:** Criar directo · publish · teardown · gravado origem  
**Versão:** 1.0 · **2026-06-14**  
**Estado:** Fichas expandidas — **sem implementação de testes**.

Substitui a tabela compacta A050–A079 em `live-ecosystem-test-matrix.md`.

**Runner:** todos os adapters desta faixa serão invocados apenas via `dart run tool/fleaber_regression_runner.dart` (secção 9 da matriz principal).

---

## A050 — Criar directo via deep link (sem prep)

| Campo | Valor |
|-------|-------|
| **ID** | A050 |
| **Nome** | Deep link `/criarDirecto` salta preparar |
| **Pré-condições** | Vendedor autenticado; deep link válido |
| **Passos** | 1. Abrir link autenticado 2. Ver ecrã câmara |
| **Resultado esperado** | `criar_directo_page_widget` abre; catálogo vazio ou último sync; sem crash |
| **Componentes afectados** | `criar_directo_page_widget.dart`, `nav.dart`, deep links |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | seller JWT, deep link URI |
| **Validar BD** | Opcional: draft `lives` criado ao preview |
| **Validar UI** | Preview câmara; título editável |
| **Risco de regressão** | Médio — atalho contorna prep A001–A049 |
| **Dependências** | — |

---

## A051 — Título &lt; 3 caracteres bloqueia start

| Campo | Valor |
|-------|-------|
| **ID** | A051 |
| **Nome** | Validação título mínimo no criar directo |
| **Pré-condições** | Página criar directo aberta |
| **Passos** | 1. Introduzir título «ab» (2 chars) 2. Tentar Iniciar Directo |
| **Resultado esperado** | CTA desactivado ou snack/validação; **sem** `status=live` |
| **Componentes afectados** | `criar_directo_page_widget.dart` |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | — |
| **Validar BD** | Sem live `live` criada |
| **Validar UI** | Botão Iniciar disabled |
| **Risco de regressão** | Baixo |
| **Dependências** | A050 ou fluxo normal prep→criar |

---

## A052 — create-mux-live primeira vez

| Campo | Valor |
|-------|-------|
| **ID** | A052 |
| **Nome** | Edge cria stream Mux no primeiro preview |
| **Pré-condições** | Live draft sem `mux_stream_key` |
| **Passos** | 1. Entrar criar directo / preview câmara 2. Aguardar edge |
| **Resultado esperado** | `mux_stream_key`, `mux_live_id` persistidos em `lives` |
| **Componentes afectados** | edge `create-mux-live`, `criar_directo_page_widget.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | seller, live_id draft |
| **Validar BD** | `select mux_stream_key, mux_live_id from lives where id=$id` not null |
| **Validar UI** | Preview deixa de estar em «A preparar câmara» (A076 negativo) |
| **Risco de regressão** | Crítico — sem Mux não há live |
| **Dependências** | A074 |

---

## A053 — Reutilizar stream key ao reentrar

| Campo | Valor |
|-------|-------|
| **ID** | A053 |
| **Nome** | Mesmo live_id — não duplica asset Mux |
| **Pré-condições** | A052 completo; seller saiu da página sem terminar |
| **Passos** | 1. Reentrar criar directo mesmo draft 2. Query Mux ids |
| **Resultado esperado** | Mesmo `live_id`; `mux_live_id` inalterado; sem segundo POST create-mux |
| **Componentes afectados** | `criar_directo_page_widget.dart`, session state |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | live_id existente |
| **Validar BD** | 1 row lives; mux ids estáveis |
| **Validar UI** | Retoma preview |
| **Risco de regressão** | Alto — duplicação Mux custa dinheiro |
| **Dependências** | A052 |

---

## A054 — Iniciar directo LiveKit→Mux (Android default)

| Campo | Valor |
|-------|-------|
| **ID** | A054 |
| **Nome** | Go-live com publish activo e studio |
| **Pré-condições** | Câmara/mic OK; catálogo sync (A074); título ≥3 |
| **Passos** | 1. Iniciar Directo 2. Confirmar avisos (A055 se aplicável) 3. Ver studio |
| **Resultado esperado** | `lives.status=live`, `is_active=true`; LiveKit egress; painel vendedor |
| **Componentes afectados** | `livekit_publish_controller.dart`, `livekit-mux-publish`, `registerActiveBroadcast` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual + Maestro |
| **Dados necessários** | device Android, staging keys |
| **Validar BD** | status live; `registerActiveBroadcast` prefs |
| **Validar UI** | Studio 3 tabs; feed LIVE (A075) |
| **Risco de regressão** | Crítico — núcleo publish |
| **Dependências** | A052, A074; A055 opcional |

---

## A055 — Aviso reservas abertas — confirmar

| Campo | Valor |
|-------|-------|
| **ID** | A055 |
| **Nome** | Sheet open reservations — confirmar go-live |
| **Pré-condições** | A006 — reservas abertas noutra sessão (Puzzle/gravado/marketplace) |
| **Passos** | 1. Iniciar directo 2. Ler popup 3. Confirmar |
| **Resultado esperado** | Lista correcta de origens; live inicia após confirmar |
| **Componentes afectados** | `live_start_reservations_warning_sheet.dart`, `batata_live_start_open_reservations_check` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual + Bot |
| **Dados necessários** | open reservations seed |
| **Validar BD** | live live após confirm |
| **Validar UI** | Copy origem Direto/Gravado/Marketplace |
| **Risco de regressão** | Alto — regressão aviso omitido |
| **Dependências** | A006 |

---

## A056 — Aviso reservas abertas — recusar

| Campo | Valor |
|-------|-------|
| **ID** | A056 |
| **Nome** | Recusar aviso cancela go-live |
| **Pré-condições** | A055 setup |
| **Passos** | 1. Iniciar 2. Recusar/Cancelar no sheet |
| **Resultado esperado** | Pop criar directo; `status` **não** `live` |
| **Componentes afectados** | warning sheet |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | open reservations |
| **Validar BD** | draft ou ended; não live |
| **Validar UI** | Volta atrás sem studio |
| **Risco de regressão** | Médio |
| **Dependências** | A055 |

---

## A057 — _markLiveActiveInDb falha visível

| Campo | Valor |
|-------|-------|
| **ID** | A057 |
| **Nome** | Erro BD ao marcar live — não publicar silenciosamente |
| **Pré-condições** | Simular RLS/rede falha no mark live |
| **Passos** | 1. Iniciar com BD indisponível momentâneo |
| **Resultado esperado** | Erro UI; publish **não** continua sem BD `live` |
| **Componentes afectados** | `criar_directo_page_widget.dart` `_markLiveActiveInDb` |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | mock offline / RLS deny |
| **Validar BD** | status ≠ live se mark falhou |
| **Validar UI** | Snack/dialog erro |
| **Risco de regressão** | Alto — live fantasma no ar |
| **Dependências** | A054 |

---

## A058 — Terminar directo → Arena gravado

| Campo | Valor |
|-------|-------|
| **ID** | A058 |
| **Nome** | Teardown explícito navega para player VOD |
| **Pré-condições** | Live activa (A054) |
| **Passos** | 1. Tocar Terminar directo 2. Confirmar |
| **Resultado esperado** | `status=ended`, `is_active=false`; navega `FleaberLivePlayer` replay |
| **Componentes afectados** | `_teardownLiveSession`, `LivePublishCleanup.finalizeEnded`, player |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual + Integration |
| **Dados necessários** | live_id live |
| **Validar BD** | ended; prefs broadcast cleared |
| **Validar UI** | Player modo gravado; badge GRAVADO |
| **Risco de regressão** | Crítico — fim de sessão |
| **Dependências** | A054; A060 |

---

## A059 — Sair (X) → Home

| Campo | Valor |
|-------|-------|
| **ID** | A059 |
| **Nome** | Fechar UI termina live e vai Home |
| **Pré-condições** | Live activa |
| **Passos** | 1. Tocar X/fechar 2. Ver destino |
| **Resultado esperado** | Home (não Arena gravado); live `ended` na BD |
| **Componentes afectados** | `criar_directo_page_widget.dart`, teardown |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | live activa |
| **Validar BD** | ended |
| **Validar UI** | Home shell |
| **Risco de regressão** | Médio — diferença vs A058 |
| **Dependências** | A054 |

---

## A060 — complete-mux-live gera VOD playback_id

| Campo | Valor |
|-------|-------|
| **ID** | A060 |
| **Nome** | Edge pós-teardown preenche `mux_vod_playback_id` |
| **Pré-condições** | A058 ou A059 (ended) |
| **Passos** | 1. Aguardar até 60s 2. Poll `lives` |
| **Resultado esperado** | `mux_vod_playback_id` not null; replay reproduzível |
| **Componentes afectados** | edge `complete-mux-live`, `LivePublishCleanup._runBackendTeardown` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | ended live_id |
| **Validar BD** | `mux_vod_playback_id` preenchido |
| **Validar UI** | Player HLS VOD (A295+) |
| **Risco de regressão** | Crítico — gravado sem vídeo (A068) |
| **Dependências** | A058 |

---

## A061 — PopScope/back termina live

| Campo | Valor |
|-------|-------|
| **ID** | A061 |
| **Nome** | Botão sistema back fecha directo (não minimiza só) |
| **Pré-condições** | Live activa Android |
| **Passos** | 1. Press back 2. Ver BD e destino |
| **Resultado esperado** | Teardown equivalente; não orphan silencioso |
| **Componentes afectados** | `PopScope` criar directo, cleanup |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | live activa |
| **Validar BD** | ended ou confirm dialog |
| **Validar UI** | Dialog se regra BATATA |
| **Risco de regressão** | Médio — overlap A062 |
| **Dependências** | A054 |

---

## A062 — App kill → orphan cleanup no restart

| Campo | Valor |
|-------|-------|
| **ID** | A062 |
| **Nome** | Kill app com live activa — restart fecha órfão |
| **Pré-condições** | A054; `registerActiveBroadcast` em prefs |
| **Passos** | 1. Kill processo 2. Reabrir app 3. `reconcileOnAppStart` |
| **Resultado esperado** | Live `ended`; prefs limpas; Mux teardown best-effort |
| **Componentes afectados** | `live_publish_cleanup.dart` orphan path |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | prefs com live_id |
| **Validar BD** | ended após restart |
| **Validar UI** | Sem card LIVE fantasma no feed |
| **Risco de regressão** | Alto |
| **Dependências** | A069; A054 |

---

## A063 — fullSweep login fecha lives teste (MAESTRO)

| Campo | Valor |
|-------|-------|
| **ID** | A063 |
| **Nome** | `reconcileOnAppStart(fullSweep:true)` não mata live Maestro partilhado |
| **Pré-condições** | Live `MAESTRO_*` ou `MAESTRO_SKIP_CLEANUP=1`; bot seed activo |
| **Passos** | 1. Bot cria live 2. Seller login/home trigger fullSweep 3. Buyer ainda no player |
| **Resultado esperado** | Live teste **permanece** `live` quando flag/convenção activa; senão ended (H07) |
| **Componentes afectados** | `live_publish_cleanup.dart`, `home_live_feed_grid.dart`, `main.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration + Bot |
| **Dados necessários** | MAESTRO live_id, `.maestro/.env` |
| **Validar BD** | status live após login se skip; ended se sem protecção |
| **Validar UI** | Harness H01 não perde sessão |
| **Risco de regressão** | **Crítico** — smoke Maestro falha (histórico ended) |
| **Dependências** | A071; H07 |

---

## A064 — HaishinKit RTMP branch

| Campo | Valor |
|-------|-------|
| **ID** | A064 |
| **Nome** | Publish RTMP alternativo (se flag activa) |
| **Pré-condições** | Build com Haishin; seller escolhe RTMP |
| **Passos** | 1. Iniciar via branch RTMP 2. Ver stream |
| **Resultado esperado** | Live live; path RTMP distinto de LiveKit default |
| **Componentes afectados** | Haishin publish branch, `live_publish_config.dart` |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | flag RTMP on |
| **Validar BD** | live status |
| **Validar UI** | Indicador modo RTMP |
| **Risco de regressão** | Baixo — branch secundário |
| **Dependências** | A054 |

---

## A065 — Permissão câmara negada

| Campo | Valor |
|-------|-------|
| **ID** | A065 |
| **Nome** | UX quando câmara recusada |
| **Pré-condições** | Permissão camera denied |
| **Passos** | 1. Abrir criar directo |
| **Resultado esperado** | Aviso + CTA definições; não crash; não go-live |
| **Componentes afectados** | permission_handler, criar directo |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | emulador sem camera |
| **Validar BD** | — |
| **Validar UI** | Placeholder + texto |
| **Risco de regressão** | Baixo |
| **Dependências** | — |

---

## A066 — Permissão microfone negada

| Campo | Valor |
|-------|-------|
| **ID** | A066 |
| **Nome** | UX quando microfone recusado |
| **Pré-condições** | Mic denied; camera ok |
| **Passos** | 1. Preview 2. Tentar iniciar |
| **Resultado esperado** | Aviso áudio; política BATATA (bloquear ou mute) |
| **Componentes afectados** | criar directo, LiveKit audio |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | permissões mock |
| **Validar BD** | — |
| **Validar UI** | Estado mic |
| **Risco de regressão** | Baixo |
| **Dependências** | A065 |

---

## A067 — LiveKit egress stop no teardown

| Campo | Valor |
|-------|-------|
| **ID** | A067 |
| **Nome** | `stop_egress` invocado ao terminar |
| **Pré-condições** | A054 LiveKit path |
| **Passos** | 1. Terminar live 2. Ver logs edge |
| **Resultado esperado** | POST `livekit-mux-publish` step `stop_egress`; sem egress zombie |
| **Componentes afectados** | `LivePublishCleanup._runBackendTeardown` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | live_id ended |
| **Validar BD** | — (logs Mux/LiveKit) |
| **Validar UI** | — |
| **Risco de regressão** | Médio — custos egress |
| **Dependências** | A058 |

---

## A068 — complete-mux-live falha — gravado sem vídeo

| Campo | Valor |
|-------|-------|
| **ID** | A068 |
| **Nome** | Falha edge — ended sem playback_id |
| **Pré-condições** | Simular timeout/erro Mux |
| **Passos** | 1. Terminar 2. Edge falha 3. Query lives |
| **Resultado esperado** | `ended` mas `mux_vod_playback_id` null; UI gravado degradada documentada |
| **Componentes afectados** | `complete-mux-live`, player replay guards |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | mock edge 500 |
| **Validar BD** | playback_id null |
| **Validar UI** | Placeholder «vídeo indisponível» |
| **Risco de regressão** | Médio |
| **Dependências** | A060 (negativo) |

---

## A069 — registerActiveBroadcast prefs sobrevive kill

| Campo | Valor |
|-------|-------|
| **ID** | A069 |
| **Nome** | Prefs `batata_active_broadcast_live_id_v1` após kill |
| **Pré-condições** | A054 go-live |
| **Passos** | 1. Kill app 2. Ler SharedPreferences antes restart |
| **Resultado esperado** | Pref contém live_id; usado por A062 |
| **Componentes afectados** | `LivePublishCleanup.registerActiveBroadcast` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | device com prefs |
| **Validar BD** | — |
| **Validar UI** | — |
| **Risco de regressão** | Médio — orphan detection |
| **Dependências** | A054 |

---

## A070 — Helper route criarDirecto bloqueado

| Campo | Valor |
|-------|-------|
| **ID** | A070 |
| **Nome** | Staff helper não inicia directo próprio |
| **Pré-condições** | Conta helper/staff sem seller owner |
| **Passos** | 1. Tentar navegar criar directo |
| **Resultado esperado** | Bloqueio ou redirect; sem publish |
| **Componentes afectados** | `SellerStaffContext`, routes guard |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | staff user |
| **Validar BD** | sem live criada |
| **Validar UI** | Acesso negado |
| **Risco de regressão** | Baixo |
| **Dependências** | A078 |

---

## A071 — Maestro harness sem câmara

| Campo | Valor |
|-------|-------|
| **ID** | A071 |
| **Nome** | `maestro_seller_studio_page_widget` debug |
| **Pré-condições** | Build debug; flow Maestro configurado |
| **Passos** | 1. Abrir harness 2. Operação → Aceitar |
| **Resultado esperado** | Studio funcional sem câmara real; H01 pass |
| **Componentes afectados** | `maestro_seller_studio_page_widget.dart`, `.maestro/flows/` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | `MAESTRO_LIVE_ID`, bot seed |
| **Validar BD** | accept RPC |
| **Validar UI** | «Operação» não «A tratar» |
| **Risco de regressão** | Alto — CI smoke |
| **Dependências** | A063; H01 |

---

## A072 — Landscape encode flag viewer

| Campo | Valor |
|-------|-------|
| **ID** | A072 |
| **Nome** | Orientação landscape no encode/view |
| **Pré-condições** | Live activa; rotação device |
| **Passos** | 1. Rodar telemóvel 2. Ver preview/player |
| **Resultado esperado** | Vídeo correcto ou letterbox conforme flag |
| **Componentes afectados** | encode settings, player |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | device físico |
| **Validar BD** | — |
| **Validar UI** | Orientação |
| **Risco de regressão** | Baixo |
| **Dependências** | A054 |

---

## A073 — Diagnostic/preview mode

| Campo | Valor |
|-------|-------|
| **ID** | A073 |
| **Nome** | Modo diagnóstico preview (debug) |
| **Pré-condições** | Flag debug |
| **Passos** | 1. Activar diagnostic 2. Ver overlay/stats |
| **Resultado esperado** | Info técnica visível só debug; não em release |
| **Componentes afectados** | preview diagnostic |
| **Prioridade** | P3 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | debug build |
| **Validar BD** | — |
| **Validar UI** | Overlay |
| **Risco de regressão** | Baixo |
| **Dependências** | — |

---

## A074 — Sincronizar catálogo antes de go-live

| Campo | Valor |
|-------|-------|
| **ID** | A074 |
| **Nome** | Catálogo prep sync na BD antes de Iniciar |
| **Pré-condições** | Prep com ≥1 item seleccionado |
| **Passos** | 1. Continuar prep → criar 2. Query `live_items` antes go-live |
| **Resultado esperado** | Items na BD com stock/preço; carrossel pronto pós-live |
| **Componentes afectados** | prep sync, `live_catalog_stock_service.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | produtos prep |
| **Validar BD** | `live_items` count > 0 |
| **Validar UI** | Catálogo studio pós A054 |
| **Risco de regressão** | Alto — live vazia |
| **Dependências** | A001–A049 prep |

---

## A075 — Live feed refresh após go-live

| Campo | Valor |
|-------|-------|
| **ID** | A075 |
| **Nome** | Home feed mostra card LIVE após A054 |
| **Pré-condições** | Go-live completo |
| **Passos** | 1. Navegar Home 2. Ver grid |
| **Resultado esperado** | Card LIVE com título; `requestLiveFeedRefresh` |
| **Componentes afectados** | `home_live_feed_grid.dart`, `marketplace_feed_refresh.dart` |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | live live |
| **Validar BD** | lives is_active |
| **Validar UI** | Badge LIVE |
| **Risco de regressão** | Médio |
| **Dependências** | A054 |

---

## A076 — Mux timeout «A preparar câmara»

| Campo | Valor |
|-------|-------|
| **ID** | A076 |
| **Nome** | Timeout create-mux — UX de espera/erro |
| **Pré-condições** | Edge lento ou offline |
| **Passos** | 1. Abrir criar 2. Esperar > timeout |
| **Resultado esperado** | Mensagem «A preparar câmara» → erro retry; não hang infinito |
| **Componentes afectados** | create-mux-live client timeout |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | simular latência |
| **Validar BD** | — |
| **Validar UI** | Loading → erro |
| **Risco de regressão** | Médio |
| **Dependências** | A052 (negativo) |

---

## A077 — Dois devices seller — só um publish

| Campo | Valor |
|-------|-------|
| **ID** | A077 |
| **Nome** | Segundo device não publica em paralelo |
| **Pré-condições** | Mesma conta seller; device A live |
| **Passos** | 1. Login device B 2. Tentar go-live |
| **Resultado esperado** | Bloqueio ou teardown A; política single publish |
| **Componentes afectados** | cleanup fullSweep, session guards |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | 2 devices |
| **Validar BD** | ≤1 live live seller |
| **Validar UI** | Aviso conflito |
| **Risco de regressão** | Alto — A397 relacionado |
| **Dependências** | A063; A054 |

---

## A078 — Staff vê painel em helper_live_ops

| Campo | Valor |
|-------|-------|
| **ID** | A078 |
| **Nome** | Helper HLS + painel operações |
| **Pré-condições** | Helper convidado; live activa seller |
| **Passos** | 1. Abrir `helper_live_ops` 2. Ver fila |
| **Resultado esperado** | Painel operações; **sem** terminar live (A374) |
| **Componentes afectados** | `helper_live_ops_page_widget.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | helper account |
| **Validar BD** | — |
| **Validar UI** | HLS + Operação |
| **Risco de regressão** | Médio |
| **Dependências** | A054; A370–A375 |

---

## A079 — Legacy route /liveStreamVendor morta

| Campo | Valor |
|-------|-------|
| **ID** | A079 |
| **Nome** | Rota antiga não navega |
| **Pré-condições** | Deep link ou bookmark legacy |
| **Passos** | 1. Abrir `/liveStreamVendor` |
| **Resultado esperado** | 404 redirect ou home; sem crash |
| **Componentes afectados** | `nav.dart` routes |
| **Prioridade** | P3 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | legacy URI |
| **Validar BD** | — |
| **Validar UI** | Não abre UI antiga |
| **Risco de regressão** | Baixo |
| **Dependências** | — |

---

## Apêndice A — Resumo A050–A079

| Bloco | IDs | Foco |
|-------|-----|------|
| Entrada + Mux | A050–A053 | Deep link, título, create-mux, reutilizar key |
| Go-live | A054–A057 | LiveKit publish, aviso reservas, mark BD |
| Teardown + VOD | A058–A060 | Terminar, Sair, complete-mux-live |
| Cleanup | A061–A069 | Back, kill, fullSweep, egress, prefs |
| Auxiliar | A070–A079 | Helper, harness, feed, multi-device, legacy |

**Total fichas:** 30 (A050–A079).

---

## Apêndice B — P0 desta faixa (8)

| ID | Nome curto |
|----|------------|
| A052 | create-mux-live |
| A054 | Go-live LiveKit |
| A055 | Aviso reservas confirmar |
| A058 | Terminar → gravado |
| A060 | VOD playback_id |
| A062 | Orphan cleanup kill |
| A063 | fullSweep vs MAESTRO |
| A074 | Sync catálogo pré-live |

---

## Apêndice C — Top 10 a automatizar primeiro (runner fase publish)

| # | ID | Porquê | Tipo |
|---|-----|--------|------|
| 1 | A063 | fullSweep mata Maestro — blocker CI | Integration |
| 2 | A060 | VOD playback — gravado downstream | Integration |
| 3 | A074 | Catálogo vazio quebra live | Integration |
| 4 | A062 | Orphan cleanup | Integration |
| 5 | A067 | stop_egress custos | Integration |
| 6 | A069 | Prefs orphan path | Integration |
| 7 | A071 | Harness smoke | Maestro |
| 8 | A052 | Mux create (API) | Integration |
| 9 | A068 | Falha VOD degradada | Integration |
| 10 | A075 | Feed refresh | Integration |

---

## Apêndice D — Classificação por tipo

| Tipo | IDs |
|------|-----|
| **Unit** | — (faixa UI/infra) |
| **Integration** | A052, A053, A060, A062, A063, A067, A068, A069, A074, A075 |
| **Bot** | A055 (seed reservas) |
| **Maestro** | A050, A051, A061, A065, A066, A071, A079 |
| **Manual** | A054, A055, A056, A057, A058, A059, A064, A070, A072, A073, A076, A077, A078 |
| **Híbrido** | A054, A055, A058, A062, A063 |

---

## Apêndice E — Riscos críticos

1. **A063 fullSweep:** login/home fecha lives `MAESTRO` — smoke harness falha (`live_status=ended`).
2. **A054 go-live:** falha silenciosa (A057) → stream sem BD live.
3. **A060/A068 VOD:** sem `playback_id` bloqueia A295+ gravado.
4. **A074 sync:** go-live sem items → carrossel/comprador vazio.
5. **A062/A069 orphan:** prefs + kill mal reconciliados → cards LIVE fantasmas.
6. **A055 aviso:** omitir popup → vendas cross-session inconsistentes.
7. **A077 multi-device:** dois publish simultâneos corrompem sessão Mux.

---

## Apêndice F — Risk graph (entrada para runner)

Exemplo arestas para `test/regression/risk_graph.json`:

| Fix / componente | Retest sugerido |
|------------------|-----------------|
| `live_publish_cleanup.dart` | A062, A063, A069, A077 |
| `complete-mux-live` | A060, A058, A068, A295 |
| `criar_directo_page_widget.dart` | A050–A057, A054, A074 |
| `live_start_reservations_warning_sheet` | A055, A056, A006 |

---

*Fim A050–A079.*
