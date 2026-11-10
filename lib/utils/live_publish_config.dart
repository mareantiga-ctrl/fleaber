/// Backend de publicação do vendedor (BATATA: viewers continuam em Mux HLS).
enum LivePublishBackend {
  /// HaishinKit → RTMP/RTMPS directo para Mux (TikTok / Facebook Live mobile).
  muxRtmp,

  /// LiveKit WebRTC no telemóvel; egress no servidor → Mux.
  livekitMuxEgress,
}

/// TCL/MTK: HaishinKit crasha no `connect()` RTMP (ver MERDA.md, teste 25 Mai).
/// Android usa LiveKit até haver ingest alternativo estável no dispositivo.
LivePublishBackend get kLivePublishBackend {
  return LivePublishBackend.livekitMuxEgress;
}

bool get kPublishUsesLiveKit =>
    kLivePublishBackend == LivePublishBackend.livekitMuxEgress;

/// Captura/egress portrait (720×1280, LiveKit preset 4).
///
/// Histórico (MERDA.md, Mai 2026 / TCL T775H): `true` (1280×720 + preset 0) foi
/// um workaround MTK quando o egress portrait letterboxava. Em Out 2026 (TCL 6102D
/// + Live real `d49203b4`) o landscape_encode produz 16:9 com cena portrait
/// pillarbox no centro — Mux/HLS e FleaHub web mostram «miniatura». Voltar a
/// portrait no publisher (sem crop no player web). Ver `03-live-vertical-source-fix/`.
bool get kLivekitMuxLandscapeEncode => false;

/// Preview WebRTC: alinhado ao HLS viewer (0). Rotação 1 deixava a cara de lado.
int get kMuxLandscapePreviewQuarterTurns => 0;

/// 0=contain (faixa pequena), 1=cover (zoom excessivo). ~0.72 = meio-termo no TCL.
double get kMuxLandscapePreviewFillFactor => 0.72;

/// HLS Mux 960×540: sem rotação (thumb portrait Mux OK; rodar no player estraga).
int get kMuxLandscapePlaybackQuarterTurns => 0;

bool publishBackendUsesLandscapeMux(String? publishBackend) =>
    publishBackend == 'livekit_mux_landscape';

String get kLivePublishBackendLabel => switch (kLivePublishBackend) {
      LivePublishBackend.muxRtmp => 'Haishin RTMP→Mux',
      LivePublishBackend.livekitMuxEgress => 'LiveKit→Mux',
    };
