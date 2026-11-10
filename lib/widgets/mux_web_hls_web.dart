import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '/utils/mux_urls.dart';

final Set<String> _registeredMuxWebViews = <String>{};

/// Chrome/Edge no desktop não tocam HLS nativo — usa o player Mux (iframe).
///
/// Gravado (`isRecording`): controlos Mux + pointer-events activos — o browser
/// bloqueia autoplay com som (`muted=false`), e com `pointer-events: none` o
/// botão Play do Mux ficava inacessível (regressão H03).
///
/// Directo ao vivo: `pointer-events: none` para o chat/botões Flutter por cima
/// continuarem a receber toques; começa em mute para o autoplay ser permitido.
Widget buildMuxWebHlsPlayer({
  required String url,
  required bool isRecording,
  required BoxFit fit,
  VoidCallback? onRetry,
}) {
  final playbackId = MuxUrls.playbackIdFromStreamUrl(url)?.trim() ?? '';
  if (playbackId.isEmpty) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: TextButton(
          onPressed: onRetry,
          child: const Text('Sinal indisponível · Tentar outra vez'),
        ),
      ),
    );
  }

  final streamType = isRecording ? 'on-demand' : 'live';
  // Gravado: UI Mux + cliques. Live: overlay Flutter por cima.
  final interactive = isRecording;
  final muted = true; // autoplay policy — unmute via controlos Mux no gravado
  final controls = interactive;
  final pointerEvents = interactive ? 'auto' : 'none';
  final viewType =
      'fleaber-mux-$playbackId-$streamType-i${interactive ? 1 : 0}-m1-c${controls ? 1 : 0}';

  if (!_registeredMuxWebViews.contains(viewType)) {
    _registeredMuxWebViews.add(viewType);
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src =
            'https://player.mux.com/$playbackId?stream_type=$streamType&autoplay=true&muted=$muted&playsinline=true&controls=$controls'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.pointerEvents = pointerEvents
        ..allow = 'autoplay; fullscreen; encrypted-media; picture-in-picture'
        ..setAttribute('allowfullscreen', 'true');
      return iframe;
    });
  }

  return SizedBox.expand(
    child: ColoredBox(
      color: Colors.black,
      child: HtmlElementView(viewType: viewType),
    ),
  );
}
