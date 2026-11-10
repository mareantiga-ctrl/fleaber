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

  /// Emails E1–E3: `https://fleaber.pt/fleahub/#/perfil?secao=encomendas&orderId=`.
  static String? fleahubOrderEmailGoLocation(Uri uri) =>
      _fleahubOrderEmailGoLocation(uri);

  static String? _goRouterLocation(Uri uri) {
    return _httpsRecoveryGoLocation(uri) ??
        _httpsAuthCallbackGoLocation(uri) ??
        _fleahubOrderEmailGoLocation(uri) ??
        _authCallbackGoLocation(uri) ??
        _stripeSuccessGoLocation(uri) ??
        _liveShareGoLocation(uri) ??
        _maestroTestGoLocation(uri);
  }

  /// `https://fleaber.pt/fleahub/#/perfil?secao=encomendas&orderId=` — emails E1–E3.
  static String? _fleahubOrderEmailGoLocation(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host != 'fleaber.pt' && host != 'www.fleaber.pt') return null;
    var path = uri.path;
    if (path.isEmpty || path == '/') return null;
    if (!path.startsWith('/')) path = '/$path';
    if (path != '/fleahub' && !path.startsWith('/fleahub/')) return null;
    final frag = uri.fragment.trim();
    if (frag.isEmpty) return null;
    final fragUri = Uri.parse(frag.startsWith('/') ? frag : '/$frag');
    final fragPath = fragUri.path;
    if (fragPath != '/perfil' && fragPath != '/minhasEncomendas') return null;
    final qp = Map<String, String>.from(fragUri.queryParameters);
    final secao = (qp['secao'] ?? '').trim();
    final orderId = (qp['orderId'] ?? '').trim();
    final wantsOrders = secao == 'encomendas' ||
        fragPath == '/minhasEncomendas' ||
        orderId.isNotEmpty;
    if (!wantsOrders) return null;
    if (kIsWeb) {
      final params = <String, String>{'secao': 'encomendas'};
      if (orderId.isNotEmpty) params['orderId'] = orderId;
      return '/perfil?${Uri(queryParameters: params).query}';
    }
    if (orderId.isNotEmpty) {
      return '/minhasEncomendas?orderId=${Uri.encodeQueryComponent(orderId)}';
    }
    return '/minhasEncomendas';
  }

  /// `https://fleaber.pt/redefinir-senha?token_hash=...` — link do email.
  static String? _httpsRecoveryGoLocation(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host != 'fleaber.pt' && host != 'www.fleaber.pt') return null;
    var path = uri.path;
    if (path.isEmpty || path == '/') return null;
    if (!path.startsWith('/')) path = '/$path';
    if (path != '/redefinir-senha' && !path.startsWith('/redefinir-senha/')) {
      return null;
    }
    final qp = Map<String, String>.from(uri.queryParameters);
    qp.putIfAbsent('type', () => 'recovery');
    if (qp.isEmpty) return '/auth-callback';
    return '/auth-callback?${Uri(queryParameters: qp).query}';
  }

  /// `https://fleaber.pt/auth-callback?code=...` — confirmação email / OAuth App Link.
  static String? _httpsAuthCallbackGoLocation(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host != 'fleaber.pt' && host != 'www.fleaber.pt') return null;
    var path = uri.path;
    if (path.isEmpty || path == '/') return null;
    if (!path.startsWith('/')) path = '/$path';
    if (path != '/auth-callback' && !path.startsWith('/auth-callback/')) {
      return null;
    }
    final qp = Map<String, String>.from(uri.queryParameters);
    final frag = uri.fragment.trim();
    if (frag.isNotEmpty) {
      if (qp.isEmpty) return '/auth-callback#$frag';
      return '/auth-callback?${Uri(queryParameters: qp).query}#$frag';
    }
    if (qp.isEmpty) return '/auth-callback';
    return '/auth-callback?${Uri(queryParameters: qp).query}';
  }

  /// `fleaber://fleaber.com/auth-callback?code=...` — OAuth / recuperação senha.
  static String? _authCallbackGoLocation(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host != 'fleaber.com') return null;
    var path = uri.path;
    if (path.isEmpty || path == '/') return null;
    if (!path.startsWith('/')) path = '/$path';
    if (path != '/auth-callback' && !path.startsWith('/auth-callback/')) {
      return null;
    }
    final qp = Map<String, String>.from(uri.queryParameters);
    final frag = uri.fragment.trim();
    if (frag.isNotEmpty) {
      return '$path?${Uri(queryParameters: qp).query}#$frag';
    }
    if (qp.isEmpty) return path;
    return '$path?${Uri(queryParameters: qp).query}';
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
    if (path == '/maestroShowCreateSheet' ||
        path.startsWith('/maestroShowCreateSheet/')) {
      return '/maestroShowCreateSheet';
    }
    if (path == '/maestroAutologin' || path.startsWith('/maestroAutologin/')) {
      return '/maestroAutologin?${Uri(queryParameters: qp).query}';
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
    if (path == '/perfilVendedor' || path.startsWith('/perfilVendedor/')) {
      final seller = qp['sellerID']?.trim().isNotEmpty == true
          ? qp['sellerID']!.trim()
          : (qp['sellerId']?.trim() ?? '');
      if (seller.isEmpty) return null;
      final tab = (qp['initialTab'] ?? qp['tab'] ?? '').trim();
      final params = <String, String>{'sellerID': seller};
      if (tab.isNotEmpty) params['initialTab'] = tab;
      return '/perfilVendedor?${Uri(queryParameters: params).query}';
    }
    if (path == '/perfil' || path.startsWith('/perfil/')) {
      if (qp.isEmpty) return '/perfil';
      return '/perfil?${Uri(queryParameters: qp).query}';
    }
    // Conta H11 — aliases absorvidos pelo Perfil (web).
    final legacyBase = path.split('?').first;
    const legacyAccount = <String, String>{
      '/wallet': '/perfil?secao=saldo',
      '/minhasEncomendas': '/perfil?secao=encomendas',
      '/favoritos': '/perfil?secao=favoritos',
      '/contaDefinicoes': '/perfil?secao=contaDefinicoes',
      '/descontosConjuntos': '/perfil?secao=descontos',
      '/modoFerias': '/perfil?secao=ferias',
      '/gestaoReferencias': '/perfil?secao=referencias',
      '/equipaColaboradores': '/perfil?secao=equipa',
      '/operacoesLive': '/perfil?secao=resultadosLive',
      '/legalHub': '/perfil?secao=infoLegal',
    };
    for (final entry in legacyAccount.entries) {
      if (legacyBase == entry.key || legacyBase.startsWith('${entry.key}/')) {
        if (!kIsWeb) {
          if (qp.isEmpty) return legacyBase;
          return '$legacyBase?${Uri(queryParameters: qp).query}';
        }
        final dest = Uri.parse(entry.value);
        final params = Map<String, String>.from(dest.queryParameters);
        final oid = (qp['orderId'] ?? '').trim();
        if (oid.isNotEmpty) params['orderId'] = oid;
        final live = (qp['liveId'] ?? qp['live_id'] ?? '').trim();
        if (live.isNotEmpty) params['liveId'] = live;
        return '${dest.path}?${Uri(queryParameters: params).query}';
      }
    }
    if (legacyBase == '/legalDocument' ||
        legacyBase.startsWith('/legalDocument/')) {
      if (!kIsWeb) {
        return qp.isEmpty
            ? legacyBase
            : '$legacyBase?${Uri(queryParameters: qp).query}';
      }
      final kind = (qp['kind'] ?? '').trim().toLowerCase();
      switch (kind) {
        case 'how':
          return '/perfil?secao=comoFunciona';
        case 'faq':
          return '/perfil?secao=faq';
        case 'about':
          return '/perfil?secao=sobre';
        case 'fleahub-account':
          return '/perfil?secao=fleahub';
        default:
          if (kind.isEmpty) return '/perfil?secao=infoLegal';
          return '/perfil?secao=infoLegal&doc=${Uri.encodeQueryComponent(kind)}';
      }
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
