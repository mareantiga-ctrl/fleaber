import 'dart:math' as math;

import 'package:fleaber/utils/fleaber_live_capture.dart';
import 'package:fleaber/utils/live_publish_config.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

/// Preview câmara LiveKit — espelho só no ecrã do vendedor.
/// Landscape encode: um único scale (evita cover duplo renderer+FittedBox).
class LivekitPreviewTexture extends StatelessWidget {
  const LivekitPreviewTexture({
    super.key,
    required this.track,
  });

  final LocalVideoTrack track;

  @override
  Widget build(BuildContext context) {
    final webrtc = FleaberLiveCapture.readWebRtcDimensions(track);
    final useLandscape = kLivekitMuxLandscapeEncode;
    final w = (webrtc.width ?? (useLandscape ? 1280 : 720)).toDouble();
    final h = (webrtc.height ?? (useLandscape ? 720 : 1280)).toDouble();
    final landscapeBuffer = useLandscape && w > h;

    final renderer = VideoTrackRenderer(
      track,
      fit: VideoViewFit.contain,
      mirrorMode: VideoViewMirrorMode.auto,
      autoCenter: true,
    );

    if (!landscapeBuffer) {
      final turns = kMuxLandscapePreviewQuarterTurns;
      Widget video = SizedBox(width: w, height: h, child: renderer);
      if (turns != 0) {
        video = RotatedBox(
          quarterTurns: turns,
          child: SizedBox(width: h, height: w, child: renderer),
        );
      }
      return ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.contain,
              clipBehavior: Clip.hardEdge,
              alignment: Alignment.center,
              child: video,
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewW = constraints.maxWidth;
          final viewH = constraints.maxHeight;
          if (viewW <= 0 || viewH <= 0) {
            return const SizedBox.shrink();
          }

          final containScale = math.min(viewW / w, viewH / h);
          final coverScale = math.max(viewW / w, viewH / h);
          final fill = kMuxLandscapePreviewFillFactor.clamp(0.0, 1.0);
          final scale = containScale + (coverScale - containScale) * fill;

          return ClipRect(
            child: Center(
              child: SizedBox(
                width: w * scale,
                height: h * scale,
                child: renderer,
              ),
            ),
          );
        },
      ),
    );
  }
}
