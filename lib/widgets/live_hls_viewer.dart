import 'package:flutter/material.dart';

import '/widgets/mux_hls_player.dart';

/// HLS em ecrã cheio 9:16 (cover, sem barras — estilo TikTok).
class LiveHlsViewer extends StatelessWidget {
  const LiveHlsViewer({
    super.key,
    required this.path,
    this.liveId,
    this.flipHorizontal = false,
    this.isLive = true,
    this.thumbnailUrl,
    this.onLivePlaybackFailed,
    this.muxLandscapePlayback = false,
    this.vodControlsBottomInset = 0,
    this.vodControlsAtTop = false,
    this.vodControlsTopInset = 0,
    this.onPlaybackTick,
  });

  final String path;
  final String? liveId;
  final bool flipHorizontal;
  final bool isLive;
  final String? thumbnailUrl;
  final Future<String?> Function()? onLivePlaybackFailed;
  final bool muxLandscapePlayback;
  final double vodControlsBottomInset;
  final bool vodControlsAtTop;
  final double vodControlsTopInset;
  final void Function(Duration position, Duration duration)? onPlaybackTick;

  @override
  Widget build(BuildContext context) {
    Widget player = MuxHlsPlayer(
      url: path,
      liveId: liveId,
      thumbnailUrl: thumbnailUrl,
      fit: BoxFit.cover,
      looping: isLive,
      isRecording: !isLive,
      onLivePlaybackFailed: onLivePlaybackFailed,
      muxLandscapePlayback: muxLandscapePlayback,
      vodControlsBottomInset: vodControlsBottomInset,
      vodControlsAtTop: vodControlsAtTop,
      vodControlsTopInset: vodControlsTopInset,
      onPlaybackTick: onPlaybackTick,
    );

    if (flipHorizontal) {
      player = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
        child: player,
      );
    }

    return SizedBox.expand(child: player);
  }
}
