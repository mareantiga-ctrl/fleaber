import 'dart:async';

import 'package:flutter/foundation.dart';

import '/utils/fleaber_logger.dart';

/// Diagnóstico temporário player Hub — procurar `[HubPlayerDiag]` no logcat/console.
abstract final class HubPlayerDiag {
  static const tag = 'HubPlayerDiag';

  static void log(String message, [Map<String, dynamic>? fields]) {
    final extra = fields == null || fields.isEmpty
        ? ''
        : ' ${fields.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    debugPrint('[$tag] $message$extra');
    unawaited(
      FleaberLogger.instance.event('hub.player.diag', {
        'msg': message,
        if (fields != null) ...fields,
      }),
    );
  }

  static void logOpen({
    required String? routePath,
    required String? routeQuery,
    required String? handle,
    required String? liveId,
    required bool embedInHub,
    required bool isLiveHint,
    String? playbackIdHint,
  }) {
    log('open', {
      'path': routePath ?? '',
      'query': routeQuery ?? '',
      'handle': handle ?? '',
      'live_id': liveId ?? '',
      'embed_in_hub': embedInHub,
      'is_live_hint': isLiveHint,
      'playback_id_hint': playbackIdHint ?? '',
    });
  }

  static void logLiveRow({
    required String? liveId,
    required String? status,
    required bool? isActive,
    required String? muxPlaybackId,
    required String? muxVodPlaybackId,
    required bool derivedEnded,
    required bool derivedLiveNow,
  }) {
    log('live_row', {
      'live_id': liveId ?? '',
      'status_raw': status ?? '',
      'is_active': isActive,
      'mux_playback_id': muxPlaybackId ?? '',
      'mux_vod_playback_id': muxVodPlaybackId ?? '',
      'derived_ended': derivedEnded,
      'derived_live_now': derivedLiveNow,
    });
  }

  static void logPlaybackResolve({
    required String? liveId,
    required bool forceVod,
    required bool isEnded,
    required String? resolveSource,
    required String url,
    required bool playAsLive,
    required bool retryResolve,
  }) {
    log('playback_resolve', {
      'live_id': liveId ?? '',
      'force_vod': forceVod,
      'is_ended': isEnded,
      'resolve_source': resolveSource ?? '',
      'url_empty': url.isEmpty,
      'play_as_live': playAsLive,
      'retry': retryResolve,
    });
  }

  static void logBadge({
    required String? liveId,
    required String label,
    required String reason,
    required bool playbackIsLive,
    required bool liveIsActive,
  }) {
    log('badge', {
      'live_id': liveId ?? '',
      'label': label,
      'reason': reason,
      'playback_is_live': playbackIsLive,
      'live_is_active': liveIsActive,
    });
  }

  static void logUi({
    required String? liveId,
    required String state,
    required String reason,
  }) {
    log('ui', {
      'live_id': liveId ?? '',
      'state': state,
      'reason': reason,
    });
  }

  static void logPoll({
    required String? liveId,
    required String action,
    int? tick,
  }) {
    log('vod_poll', {
      'live_id': liveId ?? '',
      'action': action,
      if (tick != null) 'tick': tick,
    });
  }

  static void logError({
    required String? liveId,
    required String phase,
    required Object error,
  }) {
    log('error', {
      'live_id': liveId ?? '',
      'phase': phase,
      'error': error.toString(),
    });
  }

  static void logCatalogStart({
    required String liveId,
    required bool skipCache,
  }) {
    log('catalog_start', {
      'live_id': liveId,
      'skip_cache': skipCache,
      'source': 'live_items',
    });
  }

  static void logCatalogResult({
    required String liveId,
    required int itemCount,
    required bool fromCache,
    required bool definitive,
  }) {
    log('catalog_result', {
      'live_id': liveId,
      'item_count': itemCount,
      'from_cache': fromCache,
      'definitive': definitive,
    });
  }

  static void logCatalogEmptyReason({
    required String liveId,
    required String reason,
    required bool loading,
  }) {
    log('catalog_empty_reason', {
      'live_id': liveId,
      'reason': reason,
      'loading': loading,
    });
  }

  static void logCatalogError({
    required String liveId,
    required Object error,
  }) {
    log('catalog_error', {
      'live_id': liveId,
      'error': error.toString(),
    });
  }
}
