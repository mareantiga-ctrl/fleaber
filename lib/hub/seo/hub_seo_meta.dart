import '/utils/mux_urls.dart';

import '../data/hub_models.dart';
import '../hub_urls.dart';
import '../routing/hub_route_paths.dart';
import 'hub_seo_policy.dart';

/// Meta tags Hub — derivadas **só** de dados públicos (`hub_*`), sem PII.
class HubSeoMeta {
  const HubSeoMeta({
    required this.title,
    required this.description,
    required this.ogTitle,
    required this.ogDescription,
    required this.ogImage,
    required this.canonicalUrl,
    required this.robots,
    this.ogType = 'website',
    this.ogUrl,
  });

  final String title;
  final String description;
  final String ogTitle;
  final String ogDescription;
  final String ogImage;
  final String canonicalUrl;
  final String robots;
  final String ogType;
  final String? ogUrl;

  String get effectiveOgUrl => ogUrl ?? canonicalUrl;

  static const defaultOgImage =
      'https://storage.googleapis.com/flutterflow-prod-hosting/og_splash_gradient.png';

  static const _appTitle = 'Fleaber';
  static const _appDescription =
      'Live shopping e marketplace em Portugal — reserva, compra e segue sellers ao vivo.';

  static HubSeoMeta appDefault() => HubSeoMeta(
        title: _appTitle,
        description: _appDescription,
        ogTitle: _appTitle,
        ogDescription: _appDescription,
        ogImage: defaultOgImage,
        canonicalUrl: HubUrls.canonicalHost,
        robots: HubSeoPolicy.robotsDirective(indexable: false),
      );

  /// Conta autenticada (`/perfil`) — noindex; não confundir com 404 Hub.
  static HubSeoMeta forAccountPerfil() => HubSeoMeta(
        title: 'Perfil — $_appTitle',
        description: 'A tua conta Fleaber.',
        ogTitle: 'Perfil — $_appTitle',
        ogDescription: 'A tua conta Fleaber.',
        ogImage: defaultOgImage,
        canonicalUrl: '${HubUrls.canonicalHost}/fleahub/#/perfil',
        robots: HubSeoPolicy.robotsDirective(indexable: false),
      );

  static HubSeoMeta loading({String? handle}) => HubSeoMeta(
        title: 'A carregar… · $_appTitle',
        description: _appDescription,
        ogTitle: _appTitle,
        ogDescription: _appDescription,
        ogImage: defaultOgImage,
        canonicalUrl: handle != null && handle.isNotEmpty
            ? HubUrls.profile(handle)
            : HubUrls.canonicalHost,
        robots: HubSeoPolicy.robotsDirective(indexable: false),
      );

  static HubSeoMeta notFound() => HubSeoMeta(
        title: 'Página não encontrada · $_appTitle',
        description: 'Este link não está disponível.',
        ogTitle: 'Página não encontrada · $_appTitle',
        ogDescription: 'Este link não está disponível.',
        ogImage: defaultOgImage,
        canonicalUrl: HubUrls.canonicalHost,
        robots: HubSeoPolicy.robotsDirective(indexable: false),
      );

  static HubSeoMeta forFleaHubLanding({bool indexable = false}) {
    const title =
        'FleaHub · Descobre, reserva e compra num só sítio · $_appTitle';
    const desc =
        'Acompanha diretos, vê gravações e explora produtos dos teus vendedores. '
        'Faz reservas, acompanha pedidos e compra tudo no FleaHub.';
    return HubSeoMeta(
      title: title,
      description: desc,
      ogTitle: title,
      ogDescription: desc,
      ogImage: defaultOgImage,
      canonicalUrl: HubUrls.fleahubLanding(),
      robots: HubSeoPolicy.robotsDirective(indexable: indexable),
    );
  }

  static HubSeoMeta forFleaHubInfo({
    required String title,
    required String description,
    required String path,
    bool indexable = false,
  }) {
    final canonical = '${HubUrls.canonicalHost}$path';
    return HubSeoMeta(
      title: '$title · $_appTitle',
      description: description,
      ogTitle: title,
      ogDescription: description,
      ogImage: defaultOgImage,
      canonicalUrl: canonical,
      robots: HubSeoPolicy.robotsDirective(indexable: indexable),
    );
  }

  static HubSeoMeta forProfile({
    required HubProfile profile,
    required HubProfileBundle bundle,
    bool indexable = false,
  }) {
    final handle = profile.handle;
    final name = _displayName(profile);
    final title = '$name (@$handle) · $_appTitle';
    final desc = _profileDescription(profile, bundle);
    final image = _absoluteImage(profile.photoUrl) ?? defaultOgImage;
    return HubSeoMeta(
      title: title,
      description: desc,
      ogTitle: title,
      ogDescription: desc,
      ogImage: image,
      canonicalUrl: HubUrls.profile(handle),
      robots: HubSeoPolicy.robotsDirective(indexable: indexable),
    );
  }

  static HubSeoMeta forLive({
    required HubProfile profile,
    required HubLiveBundle bundle,
    bool indexable = false,
  }) {
    final handle = profile.handle;
    final name = _displayName(profile);
    final live = bundle.live;
    final presentation = hubLivePresentation(live);
    final liveLabel = switch (presentation) {
      HubLivePresentation.liveActive => 'AO VIVO',
      HubLivePresentation.vodReplay => 'Gravado',
      HubLivePresentation.scheduledOnly => 'Directo agendado',
      HubLivePresentation.noLive => 'Directo',
    };
    final title = '$liveLabel · $name · $_appTitle';
    final desc = _liveDescription(profile, live, bundle);
    final image = _liveOgImage(live, profile) ?? defaultOgImage;
    final ogType =
        presentation == HubLivePresentation.liveActive ? 'video.other' : 'website';
    return HubSeoMeta(
      title: title,
      description: desc,
      ogTitle: title,
      ogDescription: desc,
      ogImage: image,
      canonicalUrl: HubUrls.live(
        handle,
        liveId: live != null && presentation == HubLivePresentation.vodReplay
            ? live.id
            : null,
      ),
      ogType: ogType,
      robots: HubSeoPolicy.robotsDirective(indexable: indexable),
    );
  }

  static HubSeoMeta forSection({
    required HubSection section,
    required HubProfile profile,
    bool indexable = false,
  }) {
    final handle = profile.handle;
    final name = _displayName(profile);
    final (suffix, path) = switch (section) {
      HubSection.shop => ('Marketplace', HubUrls.shop(handle)),
      HubSection.reviews => ('Avaliações', HubUrls.reviews(handle)),
      _ => ('', HubUrls.profile(handle)),
    };
    final title = '$suffix · @$handle · $_appTitle';
    final desc = section == HubSection.shop
        ? 'Artigos de $name no marketplace Fleaber.'
        : 'Opiniões de compradoras sobre $name.';
    final image = _absoluteImage(profile.photoUrl) ?? defaultOgImage;
    return HubSeoMeta(
      title: title,
      description: desc,
      ogTitle: title,
      ogDescription: desc,
      ogImage: image,
      canonicalUrl: path,
      robots: HubSeoPolicy.robotsDirective(indexable: indexable),
    );
  }

  static String _displayName(HubProfile profile) {
    final n = profile.fullName.trim();
    if (n.isNotEmpty) return n;
    return '@${profile.handle}';
  }

  static String _profileDescription(HubProfile profile, HubProfileBundle bundle) {
    final parts = <String>[];
    final loc = profile.location?.trim();
    if (loc != null && loc.isNotEmpty) parts.add(loc);
    if (bundle.activeLive != null) {
      parts.add('Directo ao vivo agora');
    } else if (bundle.upcomingLives.isNotEmpty) {
      parts.add('Próximos diretos agendados');
    }
    if (bundle.products.isNotEmpty) {
      parts.add('Marketplace Fleaber');
    }
    if (parts.isEmpty) {
      return 'Vitrine pública de ${_displayName(profile)} na Fleaber — live shopping.';
    }
    return '${parts.join(' · ')} — live shopping na Fleaber.';
  }

  static String _liveDescription(
    HubProfile profile,
    HubLive? live,
    HubLiveBundle bundle,
  ) {
    final seller = _displayName(profile);
    final liveTitle = live?.title?.trim();
    if (liveTitle != null && liveTitle.isNotEmpty) {
      return '$liveTitle · directo de $seller na Fleaber. Reserva e compra ao vivo.';
    }
    if (bundle.activeItem?.title?.trim().isNotEmpty == true) {
      return '${bundle.activeItem!.title} · directo de $seller na Fleaber.';
    }
    return 'Directo de $seller na Fleaber — vídeo, catálogo e marketplace.';
  }

  static String? _liveOgImage(HubLive? live, HubProfile profile) {
    final playbackId = live?.effectivePlaybackId;
    if (playbackId != null && playbackId.isNotEmpty) {
      return MuxUrls.portraitThumbnail(
        playbackId,
        width: 600,
        live: live?.isLiveNow ?? false,
      );
    }
    return _absoluteImage(profile.photoUrl);
  }

  static String? _absoluteImage(String? url) {
    final u = url?.trim() ?? '';
    if (u.isEmpty) return null;
    if (u.startsWith('https://') || u.startsWith('http://')) return u;
    return null;
  }
}
