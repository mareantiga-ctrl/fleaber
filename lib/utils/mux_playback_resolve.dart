import 'dart:async';

import '/backend/supabase/supabase.dart';
import '/utils/fleaber_logger.dart';
import '/utils/mux_urls.dart';

/// Resultado de `resolve-mux-playback` (edge) ou cache local.
class MuxResolvedPlayback {
  const MuxResolvedPlayback({
    required this.playbackId,
    required this.url,
    required this.isLive,
    this.source,
    this.assetStatus,
    this.error,
  });

  final String playbackId;
  final String url;
  final bool isLive;
  final String? source;
  final String? assetStatus;
  final String? error;

  bool get ok => playbackId.isNotEmpty && url.isNotEmpty && error == null;
}

/// Resolve URL HLS Mux — servidor primeiro, depois cache Supabase.
class MuxPlaybackResolve {
  MuxPlaybackResolve._();

  /// Chama `resolve-mux-playback` e regista `video.playback.resolve.*`.
  static Future<MuxResolvedPlayback?> fetchFromServer(
    String liveId, {
    String? logContext,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final id = liveId.trim();
    if (id.isEmpty) return null;

    unawaited(
      FleaberLogger.instance.event('video.playback.resolve.begin', {
        'live_id': id,
        if (logContext != null) 'context': logContext,
      }),
    );

    try {
      final response = await SupaFlow.client.functions
          .invoke(
            'resolve-mux-playback',
            body: {'live_id': id},
          )
          .timeout(timeout);

      final data = response.data;
      if (data is! Map) {
        unawaited(
          FleaberLogger.instance.event('video.playback.resolve.error', {
            'live_id': id,
            'error': 'invalid_response',
            'status': response.status,
          }),
        );
        return null;
      }

      final err = data['error']?.toString().trim();
      if (err != null && err.isNotEmpty) {
        unawaited(
          FleaberLogger.instance.event('video.playback.resolve.error', {
            'live_id': id,
            'error': err,
            'source': data['source'],
            'status': response.status,
          }),
        );
        return MuxResolvedPlayback(
          playbackId: '',
          url: '',
          isLive: false,
          error: err,
          source: data['source']?.toString(),
        );
      }

      final playbackId = (data['playback_id'] ??
              data['vod_playback_id'] ??
              data['mux_vod_playback_id'])
          ?.toString()
          .trim() ?? '';
      final playbackUrl = data['playback_url']?.toString().trim();
      final source = data['source']?.toString();
      final isLive = data['is_live'] == true;
      final assetStatus = data['asset_status']?.toString();

      if (playbackId.isEmpty) {
        unawaited(
          FleaberLogger.instance.event('video.playback.resolve.error', {
            'live_id': id,
            'error': 'empty_playback_id',
            'source': source,
          }),
        );
        return null;
      }

      final url = playbackUrl?.isNotEmpty == true
          ? playbackUrl!
          : MuxUrls.playbackHls(playbackId, live: isLive);

      final result = MuxResolvedPlayback(
        playbackId: playbackId,
        url: url,
        isLive: isLive,
        source: source,
        assetStatus: assetStatus,
      );

      unawaited(
        FleaberLogger.instance.event('video.playback.resolve.done', {
          'live_id': id,
          'playback_id': playbackId,
          'source': source,
          'is_live': isLive,
          'asset_status': assetStatus,
          'url_has_reduced_latency': url.contains('reduced_latency'),
        }),
      );

      return result;
    } catch (e, st) {
      unawaited(
        FleaberLogger.instance.reportFailure(
          category: 'video.playback.resolve',
          error: e,
          stackTrace: st,
          contextLines: ['live_id=$id'],
        ),
      );
      return null;
    }
  }

  static Future<({String url, bool isLive})> resolveForLive({
    required String liveId,
    String? muxPlaybackId,
    String? muxVodPlaybackId,
    String? status,
    bool forceVod = false,
  }) async {
    if (forceVod || status == 'ended') {
      final server = await fetchFromServer(liveId, logContext: 'resolveForLive');
      if (server != null && server.ok) {
        return (url: server.url, isLive: server.isLive);
      }
    }

    final isLive = !forceVod && status != 'ended';
    final liveIdPlayback = muxPlaybackId?.trim() ?? '';

    if (isLive) {
      if (liveIdPlayback.isEmpty) return (url: '', isLive: true);
      return (
        url: MuxUrls.playbackHls(liveIdPlayback, live: true),
        isLive: true,
      );
    }

    final vodCached = muxVodPlaybackId?.trim() ?? '';
    if (vodCached.isNotEmpty) {
      return (
        url: MuxUrls.playbackHls(vodCached, live: false),
        isLive: false,
      );
    }

    final server = await fetchFromServer(liveId, logContext: 'ended_no_cache');
    if (server != null && server.ok) {
      return (url: server.url, isLive: server.isLive);
    }

    if (liveIdPlayback.isNotEmpty) {
      return (
        url: MuxUrls.playbackHls(liveIdPlayback, live: false),
        isLive: false,
      );
    }

    return (url: '', isLive: false);
  }
}
