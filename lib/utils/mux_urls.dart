/// URLs Mux (LL-HLS + thumbnails) usadas na Home e no player.
class MuxUrls {
  MuxUrls._();

  /// HLS Mux. Em directo usa LL-HLS; gravação (ended) usa manifesto VOD estável.
  static String playbackHls(String playbackId, {bool live = true}) {
    final id = playbackId.trim();
    final base = 'https://stream.mux.com/$id.m3u8';
    if (live) {
      // Para testes: força maior qualidade nas variantes LL-HLS.
      // (mantém reduced_latency para reduzir atraso, mas evita vídeo “muito low”.)
      return '$base?reduced_latency=true&max_resolution=1080p';
    }
    return base;
  }

  /// Limita rendições Mux (ex. `480p`) — útil em Android antigo / pouco espaço.
  static String playbackHlsCapped(
    String playbackId, {
    required String maxResolution,
    bool live = false,
  }) {
    final id = playbackId.trim();
    final base = 'https://stream.mux.com/$id.m3u8';
    if (live) {
      return '$base?reduced_latency=true&max_resolution=$maxResolution';
    }
    return '$base?max_resolution=$maxResolution';
  }

  /// Extrai playback_id de URLs `stream.mux.com`.
  static String? playbackIdFromStreamUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host != 'stream.mux.com') return null;
    final segs = uri.pathSegments;
    if (segs.isEmpty) return null;
    final first = segs.first;
    if (first.endsWith('.m3u8')) {
      return first.substring(0, first.length - 5);
    }
    return first;
  }

  /// URLs a tentar no player (plain HLS + variantes Android com resolução limitada).
  static List<String> playbackUrlsForDevice({
    required String primaryUrl,
    required bool isRecording,
    bool androidLowEndCompat = false,
  }) {
    final urls = <String>[];
    void add(String u) {
      final t = u.trim();
      if (t.isNotEmpty && !urls.contains(t)) urls.add(t);
    }

    final id = playbackIdFromStreamUrl(primaryUrl);
    if (id != null && id.isNotEmpty) {
      final base = 'https://stream.mux.com/$id.m3u8';
      final live = !isRecording;

      // Tenta SEMPRE variantes com mais qualidade primeiro.
      if (live) {
        // Teste qualidade: pedir rendição mínima 720p no LL-HLS (Mux escolhe a mais alta disponível).
        add('$base?reduced_latency=true&max_resolution=1080p&min_resolution=720p');
        add('$base?reduced_latency=true&max_resolution=1080p');
        add('$base?reduced_latency=true');
        add(base);
      } else {
        add(base);
      }

      // Só depois de tentar URLs “normais” é que tentamos caps para compatibilidade.
      if (androidLowEndCompat) {
        for (final cap in const ['720p', '480p', '360p']) {
          add(
            playbackHlsCapped(
              id,
              maxResolution: cap,
              live: live,
            ),
          );
        }
      }
    }
    final uri = Uri.tryParse(primaryUrl.trim());
    if (uri != null && uri.hasQuery) {
      add(uri.replace(queryParameters: {}).toString());
    }
    add(primaryUrl);
    return urls;
  }

  /// Thumbnail vertical (9:16) para cards da Home.
  /// `crop` preenche o card — melhor que `smartcrop` em gravações letterbox.
  static String portraitThumbnail(
    String playbackId, {
    int width = 360,
    bool live = false,
  }) {
    final height = (width * 16 / 9).round();
    final time = live ? 0 : 2;
    return 'https://image.mux.com/$playbackId/thumbnail.jpg'
        '?width=$width&height=$height&fit_mode=crop&time=$time';
  }

  /// Thumbnail 16:9 da gravação — rodar 90° no card portrait da Home.
  static String landscapeThumbnail(
    String playbackId, {
    int width = 360,
    bool live = false,
  }) {
    final height = (width * 9 / 16).round();
    final time = live ? 0 : 2;
    return 'https://image.mux.com/$playbackId/thumbnail.jpg'
        '?width=$width&height=$height&fit_mode=crop&time=$time';
  }

  static bool publishBackendUsesLandscapeThumb(String? publishBackend) =>
      publishBackend == 'livekit_mux_landscape';
}
