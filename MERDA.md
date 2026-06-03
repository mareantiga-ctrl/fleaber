# MERDA — histórico completo do directo Fleaber (portrait, publish, player)

Documento de referência interna. Releitura da conversa + transcript + logs até **25 Mai 2026**.

**Problema central (ainda em aberto):** no TCL T775H (Android 30, MTK) o viewer vê o vídeo **horizontal com faixas pretas** dentro de um frame 9:16 — não é portrait “real” como TikTok / Facebook Live / YouTube mobile.

**Regra BATATA:** não remover funcionalidades nem atalhar layout Arena/player/live flows sem combinar.

---

## Estado actual do código (25 Mai 2026)

| Item | Valor |
|------|--------|
| Publish Android | **LiveKit → egress Mux** (`kLivePublishBackend = livekitMuxEgress`) |
| Haishin RTMP Android | **Desactivado** (crash no `connect()` TCL, live `f400b390`) — código mantido |
| Egress | **Track Composite** se app envia `video_track_id` + `audio_track_id` |
| Captura Android (Fase 3) | **1280×720** + `mux_encode_landscape: true` → egress **preset 0** |
| Player viewer | Landscape Mux: **sem** rotação (`manual_quarter_turns: 0`); senão 90° se `w>h` |
| Preview vendedor | Landscape encode: **0** turns (igual viewer; era 1 por engano no APK) |
| Edge `livekit-mux-publish` | **Deploy OK** 25 Mai (`npx supabase functions deploy`) |
| APK release | ✅ **OK** 25 Mai — fix `readWebRtcDimensions(LocalVideoTrack)` + preview `LocalVideoTrack` |

**Próximo passo utilizador:** `flutter build apk --release` → directo **novo** → confirmar preview vendedor + viewer ambos com cara em pé (`preview` sem `RotatedBox` nos logs).

---

## Dispositivos e ambiente

| Item | Valor |
|------|--------|
| Telemóvel principal | TCL T775H (Android 30, MTK) |
| Outros | Redmi Note 8 Pro (vídeo instável, sem áudio) |
| Locale | pt_PT |
| Viewer | Mux HLS / LL-HLS |
| Lives de referência nos logs | `267ef7aa`, `bcc6fbb0`, `678a2d86`, `f400b390` |

---

## Linha do tempo — o que tentámos e o resultado

### 1. Arranque Mux + HaishinKit RTMP (≈ 18 Mai)

**Resultado:** ❌ TCL — preview preto, crash, nunca `post_rtmp_connect` fiável. Redmi — vídeo parcial.

---

### 2. Debug Haishin — áudio OK, vídeo não (≈ 18–22 Mai)

Tentativas: 640×360, Baseline H.264, overlay debug, botões separados preparar/iniciar, RTMPS, logs encoder.

**Veredito:** encoder TCL sem frames H.264 estáveis; não era só Mux.

---

### 3. LiveKit publish (≈ 22–23 Mai)

**Resultado:** ✅ stream no viewer, VOD, áudio. ❌ portrait visual errado (letterbox).

---

### 4. Guerra portrait no player (≈ 23–24 Mai)

| # | Abordagem | Resultado |
|---|-----------|-----------|
| 4.1 | UI 9:16 + letterbox | UI OK; conteúdo horizontal |
| 4.2 | Thumbnails `crop` na home | Home OK; stream não |
| 4.3 | UI Whatnot | OK |
| 4.4 | Zoom ~3,2× letterbox | ⚠️ visual OK; **utilizador rejeitou** |
| 4.5 | Egress landscape + rotação player | ❌ insatisfeito |
| 4.6 | Egress preset 4 portrait | ❌ letterbox no encode |
| 4.7–4.10 | 720×1280, deviceId frontal, restart portrait, logs `webrtc_*` | Captura reporta portrait; egress estraga |
| 4.11 | `SCREEN_ORIENTATION_PORTRAIT` MainActivity | ❌ |
| 4.12–4.13 | Espelho / lock portrait no build | ❌ conteúdo gravado errado |

---

### 5. Logs decisivos — live `267ef7aa` (24 Mai, TCL, LiveKit)

| Prova | Detalhe |
|-------|---------|
| `live.publish.camera` | `webrtc` 720×1280 portrait |
| `video.playback.ready` | 540×960 `portrait_meta:true` |
| Visual | **landscape + faixas** |

**Conclusão:** captura OK; **letterbox nasce no egress → Mux**. VODs antigos não corrigem.

---

### 6. “Como FB/TikTok” — Haishin outra vez no Android (24–25 Mai)

**Implementado:** `muxRtmp` no Android.

**Teste 25 Mai — live `f400b390`:**

| Log | Significado |
|-----|-------------|
| `backend=Haishin RTMP→Mux` | Switch activo |
| `pre_rtmp_connect` | Entrou no connect |
| **Sem** `post_rtmp_connect` | Crash/hang TCL |

**Conclusão:** Haishin **morto no TCL**. Código revertido para **LiveKit** default Android.

---

### 7. Gorjetas Whatnot (24 Mai, paralelo)

SQL `live_tips_batata.sql`, edge `create-live-tip-checkout`, UI € no player. ⚠️ SQL + deploy edge pelo utilizador.

---

### 8. Fases LiveKit egress (25 Mai) — portrait no servidor

**Diagnóstico partilhado:** pixels “portrait” com **conteúdo 16:9 + barras** — rotação/zoom no player não cura.

#### Fase 1 — Room Composite `single-speaker` + preset 4

| Live | `bcc6fbb0` ~07:10 |
|------|-------------------|
| `egress_mode` | `room_composite` |
| Câmara | 720×1280 |
| Playback | 540×960 portrait_meta |
| Visual | **ainda landscape** |

❌ Template Chrome + preset portrait não chega.

#### Fase 2 — Track Composite + track IDs

**Código:** app envia `video_track_id` / `audio_track_id`; edge `StartTrackCompositeEgress`; logs `lk_pub_width/height`.

| Live | `678a2d86` ~07:49 |
|------|-------------------|
| `egress_mode` | `track_composite` |
| `lk_pub` | 720×1280 portrait |
| `video.playback.ready` | 540×960 portrait_meta |
| Visual | **ainda landscape** |
| Extra | `NegotiationError` m-lines SDP (preview→connect tracks recriadas; não é duplo connect — dois logs `connect.begin`) |

❌ Metadados portrait; **letterbox nos pixels**.

#### Fase 3 — Landscape buffer + egress preset 0 (Android)

**Hipótese MTK:** pedir 720×1280 força letterbox; pedir **1280×720** + preset **0** + player roda 90°.

| Live | `72062165` ~08:14 |
|------|-------------------|
| `mux_pipeline` | `landscape_encode` |
| `webrtc` / `lk_pub` | **1280×720** |
| `egress_preset` | **0** |
| `video.playback.ready` | **960×540**, `manual_quarter_turns: 1` |
| **Player viewer (live/VOD)** | ✅ utilizador: “fica top” |
| **Preview vendedor** | ❌ faixa horizontal, cara de lado |
| **Home cards GRAVADO** | ❌ faixa horizontal (thumb Mux 9:16 sobre vídeo 16:9) |

**Conclusão Fase 3:** pipeline landscape + rotação no **player** funciona. Faltava o mesmo tratamento no **preview vendedor** e nos **thumbnails da Home**.

**Correcções (25 Mai, após teste):**

| Peça | Fix |
|------|-----|
| `livekit_preview_texture.dart` | `FittedBox` + `RotatedBox` 90° + `cover` (igual lógica do `mux_hls_player`) |
| `publish_backend` na DB | `livekit_mux_landscape` quando Fase 3 activa |
| `home_live_feed_grid.dart` + `home_mux_live_card.dart` | thumb 16:9 + rotação 90° no card |
| `mux_urls.dart` | `landscapeThumbnail()` |

**Nota:** live `72062165` ficou com `publish_backend=livekit_mux` (antes do fix). Cards dessa gravação na Home podem continuar mal até **novo directo** ou UPDATE manual na DB.

#### Teste Fase 3b — live `6667b0aa` (~10:37)

| Campo | Valor |
|-------|--------|
| Captura / egress | 1280×720, preset **0** |
| `video.playback.ready` | 960×540, `manual_quarter_turns: **1**` |
| Preview vendedor | ✅ “parece bem” |
| Player viewer | ❌ roda e fica de lado (cara horizontal no ecrã 9:16) |

**Causa (6667b0aa):** rotação `1` no HLS estragava; tentámos `3` — também estragou.

#### Teste Fase 3c — live `4cb4dbaa` (~11:48)

| Campo | Valor |
|-------|--------|
| `manual_quarter_turns` | **3** no log |
| Thumb antes do HLS | ✅ “top” |
| Vídeo ao arrancar | ❌ “vira” / igual |

**Causa:** thumbnail = `portraitThumbnail` Mux (já OK). O HLS 960×540 **já vem com pessoa em pé** no buffer landscape — **não rodar** no `VideoPlayer` (`manual_quarter_turns: 0`).

**Fix actual:**

| Constante | Valor | Onde |
|-----------|-------|------|
| `kMuxLandscapePreviewQuarterTurns` | **1** | preview vendedor (WebRTC local) |
| `kMuxLandscapePlaybackQuarterTurns` | **0** | `mux_hls_player.dart` |
| Home thumb | **0** + `landscapeThumbnail()` opcional |
| Câmara TCL | `focusMode`/`exposureMode` **locked** | evita NPE `CameraUtils.setFocusPoint` |

Logs esperados: `mux_landscape_playback: true`, `manual_quarter_turns: **0**.

#### Teste Fase 3d — live `9691725b` (~12:11)

| Quem | Resultado |
|------|-----------|
| **Viewer** (VOD) | ✅ top — `manual_quarter_turns: 0`, 960×540 / 1280×720 |
| **Vendedor** (gravar) | ❌ câmara ainda de lado — preview tinha rotação **1** |

**Fix:** `kMuxLandscapePreviewQuarterTurns` → **0** (alinhar com player; rotação 1 no preview era o erro).

**Fix ecrã preto vendedor (sem «Preparar câmara»):** renderer usa track **publicada na room** (não só `_preparedVideoTrack`); removido overlay `DEBUG PIPELINE` na UI (logs remotos `app_logs` mantêm-se).

Preview vendedor + viewer HLS: rotação **0** + `contain` no preview / `cover` no player.

#### Teste Fase 3e — lives `9a3066d7` + `875e160f` (~16:25–16:29, 25 Mai)

| Quem | Resultado |
|------|-----------|
| **Viewer** `875e160f` | ✅ `video.playback.ready` 1280×720, `manual_quarter_turns: **0**` |
| **Vendedor** | ✅ imagem volta (track publicada); ❌ **ainda de lado** |
| **Código** | `kMuxLandscapePreviewQuarterTurns` estava **1** no APK (MERDA já dizia 0; não tinha sido aplicado no `live_publish_config.dart`) |

**Fix 3e:** `kMuxLandscapePreviewQuarterTurns` → **0** no código (igual viewer). Novo APK + directo para validar preview.

#### Teste Fase 3f — live `b65c9d0e` (~16:51, 25 Mai)

| Quem | Resultado |
|------|-----------|
| **Viewer** VOD | ✅ 960×540, `manual_quarter_turns: **0**` |
| **Vendedor** | ❌ preview **preto** outra vez (APK com preview turns=0) |
| **Causa** | Ramo `turns==0` em `livekit_preview_texture.dart` **sem** `SizedBox(w×h)` — no TCL o `VideoTrackRenderer` fica tamanho 0 dentro do `FittedBox` |
| **Fix 3f** | Sempre `SizedBox(width: w, height: h)` + `BoxFit.cover`; defaults 1280×720 se WebRTC ainda não reportar dims; `ValueKey(mediaStreamTrack.id)` + `setState` +600 ms após connect |

**Zoom:** não há zoom ~3,2× no player (`mux_hls_player` só `FittedBox` + rotação opcional; comentário «sem zoom artificial»). Preview = `cover` normal, não letterbox-fill.

**Fix 3g–3h:** `contain` = faixa minúscula; `cover` duplo (renderer+FittedBox) = zoom excessivo. **Fix 3i (live `c6741552`):** um único scale `contain + (cover-contain)×0.72` em `LayoutBuilder`; `VideoViewFit.contain`; `turns=0`. Viewer HLS inalterado (`manual_quarter_turns: 0`).

Se ainda falhar → **FFmpeg sidecar**, secção 9.

---

## Mapa dos backends (actual)

```
┌─────────────────────────────────────────────────────────────────┐
│  VENDEDOR ANDROID (código actual)                               │
│  LiveKit WebRTC 1280×720 → Track Composite egress preset 0      │
│  → RTMPS Mux                                                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Haishin RTMP→Mux (código existe, default OFF no TCL)           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  VIEWER                                                         │
│  Mux HLS → MuxHlsPlayer (rotação se w>h) → FleaberLivePlayer    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Ficheiros-chave

| Área | Ficheiros |
|------|-----------|
| Backend publish | `lib/utils/live_publish_config.dart` |
| Captura / pipeline | `lib/utils/fleaber_live_capture.dart` |
| LiveKit | `lib/vendedor/livekit_publish_controller.dart`, `criar_directo_page_widget.dart` |
| Preview vendedor | `lib/vendedor/livekit_preview_texture.dart` |
| Egress | `supabase/functions/livekit-mux-publish/index.ts` |
| Player | `lib/widgets/mux_hls_player.dart`, `fleaber_live_player_widget.dart` |
| Haishin (legado) | `criar_directo_page_widget.dart` (path muxRtmp) |
| Histórico | **este ficheiro** `MERDA.md` |

---

## O que funcionou ✅

- LiveKit publish + viewer vê live/VOD (TCL)
- Mux API, VOD, HLS, Arena UI, logs remotos
- Captura WebRTC reporta dimensões pedidas (nem sempre pixels correctos)
- Track Composite + Room Composite deployam sem erro
- Edge Fase 3 deployada

## O que falhou ❌

- Haishin RTMP no TCL
- Portrait via egress preset 4 (Participant, Room, Track Composite)
- Zoom player (rejeitado)
- VODs antigos com letterbox

---

## MediaMTX / SRS (secção 9)

Não substituem Mux nem encoder no telemóvel. Úteis só com **FFmpeg no meio** para crop/transpose antes do RTMP Mux.

Prioridade sem VPS: Fase 3 landscape. Com VPS: LiveKit → FFmpeg → Mux.

---

## Checklist — próximo teste (HLS sem rotação)

1. `flutter build apk --release` e instalar no TCL
2. Directo novo ou reabrir VOD `4cb4dbaa`
3. Player: thumb OK → vídeo **igual** ao thumb (não “vira” ao arrancar)
4. Log: `manual_quarter_turns: 0`
5. Sem crash `CameraUtils.setFocusPoint` ao preparar câmara

---

## Comandos

```powershell
cd c:\Users\Casa\Desktop\Fleaber\fleaber
npx supabase functions deploy livekit-mux-publish
flutter build apk --release
```

**Nota PowerShell:** erro `PSReadLine` ao colar (Ctrl+V) é bug da consola Windows — não é do Supabase/Flutter. Colar linha a linha ou usar CMD se repetir.

---

## Resumo numa frase

**Fase 3 (1280×720 + preset 0) resolve o viewer com rotação 0; preview vendedor tinha de ser 0 também (estava 1 no código). Novo APK + directo novo para validar preview + viewer.**

---

*Transcript: `962a9346-d225-4c85-9bfd-552c25e271a2`. Última actualização: 25 Mai 2026 (edge deploy OK, fix build preview).*
