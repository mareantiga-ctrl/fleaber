import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '/utils/fleaber_logger.dart';

/// Garante que `fleaber://fleaber.com/stripe-success?...` chega ao GoRouter.
class FleaberDeepLinkService {
  FleaberDeepLinkService._();

  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _sub;
  static GoRouter? _router;

  static Future<void> init(GoRouter router) async {
    _router = router;
    await _sub?.cancel();
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _scheduleNavigate(initial, source: 'initial');
      }
      _sub = _appLinks.uriLinkStream.listen(
        (uri) => _scheduleNavigate(uri, source: 'stream'),
        onError: (Object e, StackTrace st) {
          FleaberLogger.instance.warning(
            'deeplink',
            'uriLinkStream erro: $e',
          );
          debugPrint('FleaberDeepLinkService stream error: $e\n$st');
        },
      );
    } catch (e, st) {
      FleaberLogger.instance.warning('deeplink', 'init falhou: $e');
      debugPrint('FleaberDeepLinkService init error: $e\n$st');
    }
  }

  static void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    _router = null;
  }

  static void _scheduleNavigate(Uri uri, {required String source}) {
    final path = _goRouterLocation(uri);
    if (path == null) return;
    FleaberLogger.instance.info(
      'deeplink',
      '$source → $path',
    );
  Future.microtask(() {
      final router = _router;
      if (router == null) return;
      try {
        router.go(path);
      } catch (e) {
        FleaberLogger.instance.warning(
          'stripe.return',
          'go falhou ($path): $e',
        );
      }
    });
  }

  /// Devolve `/stripe-success?...` ou null se não for o nosso host/path.
  static String? stripeSuccessGoLocation(Uri uri) => _stripeSuccessGoLocation(uri);

  static String? _goRouterLocation(Uri uri) {
    return _stripeSuccessGoLocation(uri) ??
        _liveShareGoLocation(uri) ??
        _maestroTestGoLocation(uri);
  }

  /// `https://fleaber.app/live/{liveId}?ref=...` → player in-app.
  static String? _liveShareGoLocation(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host != 'fleaber.app' && host != 'fleaber.com') return null;
    var path = uri.path;
    if (path.isEmpty || path == '/') return null;
    if (!path.startsWith('/')) path = '/$path';
    final m = RegExp(r'^/live/([^/]+)/?$').firstMatch(path);
    if (m == null) return null;
    final liveId = m.group(1)?.trim() ?? '';
    if (liveId.isEmpty) return null;
    final qp = Map<String, String>.from(uri.queryParameters);
    qp['liveId'] = liveId;
    qp.putIfAbsent('isLive', () => 'true');
    return '/fleaberLivePlayer?${Uri(queryParameters: qp).query}';
  }

  /// Rotas de teste / automação (`maestro openLink`, QA manual).
  static String? _maestroTestGoLocation(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host != 'fleaber.com') return null;
    var path = uri.path;
    if (path.isEmpty || path == '/') return null;
    if (!path.startsWith('/')) path = '/$path';
    final qp = Map<String, String>.from(uri.queryParameters);
    if (path.startsWith('/fleaberLivePlayer')) {
      final live = qp['liveId']?.trim().isNotEmpty == true
          ? qp['liveId']!.trim()
          : (qp['live_id']?.trim() ?? '');
      if (live.isEmpty) return null;
      qp['liveId'] = live;
      qp.remove('live_id');
      qp.putIfAbsent('isLive', () => 'true');
      return '$path?${Uri(queryParameters: qp).query}';
    }
    if (path == '/conviteColaborador' ||
        path.startsWith('/conviteColaborador/')) {
      final linkId = qp['helperLinkId']?.trim().isNotEmpty == true
          ? qp['helperLinkId']!.trim()
          : (qp['helper_link_id']?.trim() ?? '');
      if (linkId.isEmpty) return null;
      qp['helperLinkId'] = linkId;
      qp.remove('helper_link_id');
      return '/conviteColaborador?${Uri(queryParameters: qp).query}';
    }
    if (path == '/maestroSellerStudio' ||
        path.startsWith('/maestroSellerStudio/')) {
      final live = qp['liveId']?.trim().isNotEmpty == true
          ? qp['liveId']!.trim()
          : (qp['live_id']?.trim() ?? '');
      if (live.isEmpty) return null;
      qp['liveId'] = live;
      qp.remove('live_id');
      return '/maestroSellerStudio?${Uri(queryParameters: qp).query}';
    }
    if (path == '/criarDirecto' || path == '/prepararDirecto') {
      return path;
    }
    return null;
  }

  static String? _stripeSuccessGoLocation(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host != 'fleaber.com') return null;
    var path = uri.path;
    if (path.isEmpty || path == '/') {
      // Alguns intent parsers deixam o path em fragment/query.
      if (uri.queryParameters.containsKey('session_id')) {
        path = '/stripe-success';
      } else {
        return null;
      }
    }
    if (!path.startsWith('/')) path = '/$path';
    if (!path.startsWith('/stripe-success')) return null;
    final qp = Map<String, String>.from(uri.queryParameters);
    final live = qp['liveId']?.trim().isNotEmpty == true
        ? qp['liveId']!.trim()
        : (qp['live_id']?.trim() ?? '');
    if (live.isNotEmpty) {
      qp['liveId'] = live;
      qp.remove('live_id');
    }
    if (qp.isEmpty) return path;
    return '$path?${Uri(queryParameters: qp).query}';
  }
}
