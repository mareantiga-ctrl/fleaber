import 'package:flutter/foundation.dart';

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

/// TCL/MTK: pedir 720×1280 portrait pode gerar letterbox horizontal nos pixels;
/// captura 1280×720 + egress preset landscape (0) + player roda (ver MERDA.md).
bool get kLivekitMuxLandscapeEncode =>
    defaultTargetPlatform == TargetPlatform.android;

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
