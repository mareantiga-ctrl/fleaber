import 'package:flutter/foundation.dart';

import '/backend/supabase/supabase.dart';

/// Política de indexação Hub — staging sempre noindex; produção só `fleaber.pt` + Supabase prod.
abstract final class HubSeoPolicy {
  /// Host canónico Hub produção (sem scheme).
  static const productionHosts = {'fleaber.pt', 'www.fleaber.pt'};

  /// Project ref staging — **nunca** indexar enquanto a app aponta aqui.
  static const stagingSupabaseProjectRef = 'fxdknzrqjenzqcvnwqqq';

  static bool isProductionHubHost(String host) {
    final h = host.trim().toLowerCase();
    if (h.isEmpty) return false;
    return productionHosts.contains(h);
  }

  static bool isLocalDevHost(String host) {
    final h = host.trim().toLowerCase();
    return h == 'localhost' ||
        h == '127.0.0.1' ||
        h.endsWith('.localhost') ||
        h.contains('ngrok') ||
        h.startsWith('192.168.');
  }

  static bool isStagingSupabaseProject([String? supabaseUrl]) {
    final url = (supabaseUrl ?? SupaFlow.supabaseUrl).toLowerCase();
    return url.contains(stagingSupabaseProjectRef);
  }

  /// `index,follow` só quando **ambos**: host produção **e** backend não-staging.
  static bool allowHubIndexing({String? host, String? supabaseUrl}) {
    if (!kIsWeb) return false;
    final resolvedHost = (host ?? _currentHost()).toLowerCase();
    if (!isProductionHubHost(resolvedHost)) return false;
    if (isStagingSupabaseProject(supabaseUrl)) return false;
    return true;
  }

  static String robotsDirective({required bool indexable}) {
    return indexable ? 'index,follow,max-image-preview:large' : 'noindex,nofollow';
  }

  static String _currentHost() {
    if (!kIsWeb) return '';
    return Uri.base.host;
  }
}
