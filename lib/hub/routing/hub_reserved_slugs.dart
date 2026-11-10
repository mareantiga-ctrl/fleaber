/// Primeiro segmento de URL que **nunca** é handle Hub.
///
/// Defesa em profundidade além das rotas estáticas GoRouter (R29).
/// Espelha `reserved_handles` (reason=route) + rotas Flutter actuais.
class HubReservedSlugs {
  HubReservedSlugs._();

  /// Rotas App/registo — primeiro segmento após `/`.
  static const appStaticFirstSegments = {
    'login',
    'registo',
    'homePage',
    'stripe-success',
    'opinioes',
    'perfilVendedor',
    'perfilVendedorCopy',
    'fleaberLivePlayer',
    'listaConversas',
    'chatPage',
    'h10MensagensCatalog',
    'h10MensagensDemo',
    'perfil',
    'contaDefinicoes',
    'descontosConjuntos',
    'criarConjunto',
    'verConjunto',
    'favoritos',
    'legalHub',
    'fleahub',
    'hub-dev',
    'legalDocument',
    'minhasEncomendas',
    'wallet',
    'modoFerias',
    'gestaoReferencias',
    'equipaColaboradores',
    'acessoColaborador',
    'conviteColaborador',
    'maestroShowCreateSheet',
    'maestroAutologin',
    'maestroSellerStudio',
    'helperLiveOps',
    'operacoesLive',
    'resultadosLive',
    'admin',
    'live-director',
    'liveDirector',
    'livesWebDashboard',
    'sellerProductForm',
    'productDetails',
    'criarDirecto',
    'prepararDirecto',
    'liveStreamVendor',
    'esqueciSenha',
    'auth-callback',
  };

  /// Reservados BD (`reserved_handles`) — não usar como handle.
  static const dbReservedHandles = {
    'fleaber',
    'fleaberpt',
    'oficial',
    'suporte',
    'support',
    'admin',
    'api',
    'www',
    'app',
    'hub',
    'fleahub',
    'live',
    'shop',
    'reviews',
    'marketplace',
    'signup',
    'auth',
    'stripe',
    'mux',
    'arena',
    'minhas-reservas',
    'mensagens',
    'conta',
    'perfil',
    'home',
    'help',
    'ajuda',
    'mod',
    'staff',
    'test',
    'staging',
    'dev',
    'root',
    'system',
  };

  static bool blocksHubHandle(String rawHandle) {
    final h = rawHandle.trim().toLowerCase();
    if (h.isEmpty) return true;
    return appStaticFirstSegments.contains(h) ||
        appStaticFirstSegments.contains(_toCamelCase(h)) ||
        dbReservedHandles.contains(h);
  }

  static String _toCamelCase(String slug) {
    final parts = slug.split('-').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return slug;
    return parts.first +
        parts.skip(1).map((p) {
          if (p.isEmpty) return '';
          return p[0].toUpperCase() + p.substring(1);
        }).join();
  }
}
