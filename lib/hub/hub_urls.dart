/// URLs canónicas públicas Hub — browser-first `fleaber.pt`.
class HubUrls {
  HubUrls._();

  static const canonicalHost = 'https://fleaber.pt';

  /// Host curto para UI seller (sem protocolo).
  static const displayHost = 'fleaber.pt';

  static String displayPath(String slug) {
    final s = slug.trim().replaceAll(RegExp(r'^/+|/+$'), '').toLowerCase();
    if (s.isEmpty || s == '…') return '$displayHost/…';
    return '$displayHost/$s';
  }

  /// Perfil público — hash sob `/fleahub/` (P12: nginx não reescreve handles limpos).
  static String profile(String handle) =>
      '$canonicalHost/fleahub/index.html#/${_slug(handle)}';

  /// URL Live Hub partilhável. Com [liveId] aponta para sessão específica.
  /// Usa hash sob `/fleahub/` para abrir no shell Flutter sem rewrite nginx (P12).
  static String live(String handle, {String? liveId}) =>
      liveWebHash(handle, liveId: liveId);

  /// URL live Hub em fleaber.pt (deploy hash — funciona sem location de handles).
  static String liveWebHash(String handle, {String? liveId}) {
    final base = '$canonicalHost/fleahub/index.html#/${_slug(handle)}/live';
    final id = liveId?.trim();
    if (id == null || id.isEmpty) return base;
    return '$base?liveId=${Uri.encodeQueryComponent(id)}';
  }

  /// Path limpo legado (requer bridge nginx/Apache P12). Preferir [live]/[profile].
  static String liveCleanPath(String handle, {String? liveId}) {
    final base = '$canonicalHost/${_slug(handle)}/live';
    final id = liveId?.trim();
    if (id == null || id.isEmpty) return base;
    return '$base?liveId=${Uri.encodeQueryComponent(id)}';
  }

  static String shop(String handle) =>
      '$canonicalHost/fleahub/index.html#/${_slug(handle)}/shop';

  static String reviews(String handle) =>
      '$canonicalHost/fleahub/index.html#/${_slug(handle)}/reviews';

  static String fleahubLanding() => '$canonicalHost/fleahub/';

  /// Links de instalação (funil Hub → App).
  /// [installAndroidPublished]: `false` → botão «Em breve» sem navegação.
  /// Quando a app estiver na Play Store, pôr `true` (URL já preparada).
  static const installAndroidPublished = false;
  static const installAndroid =
      'https://play.google.com/store/apps/details?id=pt.fleaber.app';
  static const installIos =
      'https://apps.apple.com/app/fleaber/id0000000000';

  static String _slug(String handle) =>
      handle.trim().replaceAll(RegExp(r'^/+|/+$'), '').toLowerCase();
}
