/// Rotas públicas Hub (path patterns web).
///
/// Entrypoint de dados: [HubHandleResolver] → `batata_resolve_handle`.
/// Consumo de dados: views `hub_*` + RPC FOMO — nunca tabelas base.
class HubRoutePaths {
  HubRoutePaths._();

  static const profile = '/:handle';
  static const live = '/:handle/live';
  static const shop = '/:handle/shop';
  static const reviews = '/:handle/reviews';

  static const landing = '/fleahub';

  /// Páginas informativas públicas (sob `/fleahub/…`).
  static const howItWorks = '/fleahub/como-funciona';
  static const buySafe = '/fleahub/comprar-com-seguranca';
  static const sell = '/fleahub/vender';
  static const help = '/fleahub/ajuda';
  static const contacts = '/fleahub/contactos';

  /// Landing com tab Explorar (`diretos` | `marketplace`).
  /// Aliases legados: `live`/`recordings` → diretos; `hubs` → marketplace.
  static String landingExploreTab(String tab) =>
      '$landing?tab=${Uri.encodeQueryComponent(tab)}';

  static String profileFor(String handle) => '/${_trim(handle)}';

  /// Tab H02: `diretos` | `marketplace` | `opinioes` (aliases: shop, reviews, live…).
  static String profileTabFor(String handle, String tab) =>
      '/${_trim(handle)}?tab=${Uri.encodeQueryComponent(tab.trim())}';

  /// Live Hub — sem [liveId] usa `pickPrimaryLive`; com [liveId] abre essa sessão.
  static String liveFor(String handle, {String? liveId}) {
    final base = '/${_trim(handle)}/live';
    final id = liveId?.trim();
    if (id == null || id.isEmpty) return base;
    return '$base?liveId=${Uri.encodeQueryComponent(id)}';
  }

  /// Compat: rota antiga `/{handle}/shop` → redirect H02 `?tab=marketplace`.
  static String shopFor(String handle) => '/${_trim(handle)}/shop';

  /// Compat: rota antiga `/{handle}/reviews` → redirect H02 `?tab=opinioes`.
  static String reviewsFor(String handle) => '/${_trim(handle)}/reviews';

  static String _trim(String handle) =>
      handle.trim().replaceAll(RegExp(r'^/+|/+$'), '');
}

/// Secção Hub activa (mapeia suffix URL).
enum HubSection {
  profile(''),
  live('live'),
  shop('shop'),
  reviews('reviews');

  const HubSection(this.pathSuffix);

  final String pathSuffix;

  static HubSection fromUriPath(List<String> segments) {
    if (segments.length < 2) return HubSection.profile;
    return switch (segments[1].toLowerCase()) {
      'live' => HubSection.live,
      'shop' => HubSection.shop,
      'reviews' => HubSection.reviews,
      _ => HubSection.profile,
    };
  }
}
