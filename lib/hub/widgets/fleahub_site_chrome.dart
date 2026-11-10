import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/flutter_flow/nav/nav.dart';
import '/legal/legal_document_page_widget.dart';
import '/legal/legal_texts.dart';
import '/lista_conversas_widget.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_elevation.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/fleaber_cookie_consent_banner.dart';
import '/widgets/profile_avatar.dart';

import '../hub_account_routes.dart';
import '../hub_actions.dart';
import '../hub_navigation.dart';
import '../hub_public_access.dart';
import '../routing/hub_route_paths.dart';
import 'fleahub_notification_center.dart';

/// Largura útil da homepage FleaHub (~90–95% em monitores largos).
abstract final class FleaHubSiteLayout {
  static const wideWidthFactor = 0.94;

  /// Cartões densos: ~5 por linha no desktop típico (~1920; adapta-se à largura).
  static const exploreCardTargetWidth = 200.0;
  static const exploreCardMinWidth = 172.0;
  static const exploreCardMaxWidth = 228.0;

  /// Escala tipográfica FleaHub (Home = referência; partilhada H01/H02/…).
  /// Mesma função ⇒ mesmo tamanho/peso em todas as páginas claras.
  static const typeLogo = 24.0;
  static const typeDisplay = 22.0; // nome vendedor / título de página
  static const typeNavTitle = 18.0; // títulos de secção rail / page H1 secundário
  static const typeNav = 15.0; // itens de navegação / botões texto
  static const typeSection = 16.0; // títulos de secção de conteúdo
  static const typeTab = 14.0; // separadores Diretos|Marketplace|…
  static const typeBody = 14.0; // texto normal, títulos de artigo em grelha
  static const typePrice = 15.0; // preços em destaque
  static const typeSecondary = 13.0; // descrições curtas, handles
  static const typeMeta = 13.0; // localização, seguidores, metadados
  static const typeCaption = 12.5; // legendas / microcopy
  static const typeSearch = 15.0;

  /// Linha 1 px sob a topbar (neutra; sem faixa pesada).
  static const Color topBarHairline = Color(0xFFD5DDE3);

  /// Espaço real entre a base da topbar e a linha 1 px (não é o gap linha→tabs).
  static const topBarToHairlineGap = 14.0;

  /// Espaço vertical após a hairline → conteúdo (desktop / mobile).
  static const contentTopGapDesktop = 12.0;
  static const contentTopGapCompact = 8.0;

  /// Largura máxima do bloco do rodapé (centrado; evita espalhar em ecrãs largos).
  static const footerMaxWidth = 960.0;

  static double contentTopGap(BuildContext context) =>
      usesCompactChrome(context) ? contentTopGapCompact : contentTopGapDesktop;

  static const topBarHeight = 68.0;
  static const topBarHeightCompact = 58.0;
  static const searchFieldHeight = 46.0;
  static const searchFieldHeightCompact = 40.0;
  static const searchMaxWidth = 640.0;

  static double maxContentWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1100) return w * wideWidthFactor;
    if (w >= 900) return w - 40;
    if (w >= 700) return w - 32;
    return w;
  }

  static EdgeInsets pagePadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = w >= 900 ? 16.0 : 12.0;
    return EdgeInsets.symmetric(horizontal: h);
  }

  static bool get threeZone => true;

  /// Desktop aprovado (3 zonas). Abaixo disto: chrome compacto (☰ + tabs).
  static const desktopShellMinWidth = 1180.0;

  /// Pesquisa inline no chrome compacto (tablet / intermédio).
  static const compactInlineSearchMinWidth = 720.0;

  static bool isThreeZone(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopShellMinWidth;

  /// Antigo «2 zonas» (900–1180) comprimia nav/cartões — desactivado.
  static bool isTwoZone(BuildContext context) => false;

  /// Lateral esquerda só no desktop aprovado.
  static bool showsLeftRail(BuildContext context) => isThreeZone(context);

  /// Topbar ☰ / lupa / 3 tabs (telemóvel, tablet, 1024).
  static bool usesCompactChrome(BuildContext context) =>
      !showsLeftRail(context);

  static bool showsInlineSearchInCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= compactInlineSearchMinWidth;
}

class FleaHubBrandMark extends StatelessWidget {
  const FleaHubBrandMark({
    super.key,
    required this.asset,
    required this.semanticLabel,
    this.height = 18,
    this.maxWidth = 48,
  });

  final String asset;
  final String semanticLabel;
  final double height;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height, maxWidth: maxWidth),
        child: Image.asset(
          asset,
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Shell: topbar + body + rodapé legal.
class FleaHubSiteScaffold extends StatelessWidget {
  const FleaHubSiteScaffold({
    super.key,
    required this.body,
    this.scrollController,
    this.searchController,
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.onBagTap,
    this.bagBadgeCount = 0,
  });

  final Widget body;
  final ScrollController? scrollController;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback? onBagTap;
  final int bagBadgeCount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FleaberColors.bgTint,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: FleaHubSiteLayout.maxContentWidth(context),
            ),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: FleaHubSiteTopBar(
                    searchController: searchController,
                    onSearchChanged: onSearchChanged,
                    onSearchSubmitted: onSearchSubmitted,
                    onBagTap: onBagTap,
                    bagBadgeCount: bagBadgeCount,
                  ),
                ),
                if (FleaHubSiteLayout.showsLeftRail(context))
                  const SliverToBoxAdapter(child: FleaHubTopBarBleed()),
                SliverToBoxAdapter(child: body),
                const SliverToBoxAdapter(child: FleaHubSiteFooter()),
                SliverToBoxAdapter(
                  child: ListenableBuilder(
                    listenable: FleaberCookieConsentBanner.consentAccepted,
                    builder: (context, _) {
                      final size = MediaQuery.sizeOf(context);
                      final reserve =
                          FleaberCookieConsentBanner.consentAccepted.value
                              ? 28.0
                              : FleaberCookieConsentBanner
                                  .scrollReserveForViewport(
                                  width: size.width,
                                  height: size.height,
                                );
                      return SizedBox(height: reserve);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Linha 1 px sob o gap da topbar (o espaço 14 px vive no fim de [FleaHubSiteTopBar]).
class FleaHubTopBarBleed extends StatelessWidget {
  const FleaHubTopBarBleed({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: FleaHubSiteLayout.topBarHairline,
      child: SizedBox(height: 1, width: double.infinity),
    );
  }
}

/// Loading claro FleaHub — mantém topbar; skeletons no corpo (sem ecrã preto).
class FleaHubLoadingShell extends StatelessWidget {
  const FleaHubLoadingShell({
    super.key,
    this.message = 'A carregar…',
    this.searchController,
    this.onSearchSubmitted,
  });

  final String message;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchSubmitted;

  @override
  Widget build(BuildContext context) {
    final pad = FleaHubSiteLayout.pagePadding(context);
    final maxW = FleaHubSiteLayout.maxContentWidth(context);
    return Scaffold(
      backgroundColor: FleaberColors.bgTint,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: FleaHubSiteTopBar(
                    searchController: searchController,
                    onSearchSubmitted: onSearchSubmitted,
                  ),
                ),
                const SliverToBoxAdapter(child: FleaHubTopBarBleed()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      pad.left,
                      FleaHubSiteLayout.contentTopGap(context),
                      pad.right,
                      24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _skel(height: 120, radius: 14),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(child: _skel(height: 44, radius: 12)),
                            const SizedBox(width: 8),
                            Expanded(child: _skel(height: 44, radius: 12)),
                            const SizedBox(width: 8),
                            Expanded(child: _skel(height: 44, radius: 12)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _skel(height: 220, radius: 16)),
                            const SizedBox(width: 10),
                            Expanded(child: _skel(height: 220, radius: 16)),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: Text(
                            message,
                            style: GoogleFonts.inter(
                              color: FleaberColors.muted,
                              fontSize: FleaHubSiteLayout.typeBody,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: FleaHubSiteFooter()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _skel({required double height, double radius = 12}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: FleaberColors.alternate.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Topbar marketplace.
/// Desktop (≥1180): logo · pesquisa centrada · conta (aprovado).
/// Compacto (&lt;1180): ☰ · logo · lupa/pesquisa · notificações · mensagens · conta.
class FleaHubSiteTopBar extends StatefulWidget {
  const FleaHubSiteTopBar({
    super.key,
    this.searchController,
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.onBagTap,
    this.bagBadgeCount = 0,
  });

  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback? onBagTap;
  final int bagBadgeCount;

  @override
  State<FleaHubSiteTopBar> createState() => _FleaHubSiteTopBarState();
}

class _FleaHubSiteTopBarState extends State<FleaHubSiteTopBar> {
  bool _searchExpanded = false;

  bool get _loggedIn => AppStateNotifier.instance.loggedIn;

  void _defaultSubmit(BuildContext context, String q) {
    final query = q.trim();
    if (query.length < 2) {
      context.go(HubRoutePaths.landing);
      return;
    }
    context.go(
      '${HubRoutePaths.landing}?q=${Uri.encodeQueryComponent(query)}',
    );
  }

  void _openInfoMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _FleaHubInfoMenuSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStateNotifier.instance,
      builder: (context, _) {
        final desktop = FleaHubSiteLayout.showsLeftRail(context);
        final compactChrome = FleaHubSiteLayout.usesCompactChrome(context);
        final inlineSearch =
            FleaHubSiteLayout.showsInlineSearchInCompact(context);
        final pad = FleaHubSiteLayout.pagePadding(context);
        final backBtn = HubBackButton.topBarLeading(context);
        final barH = compactChrome
            ? FleaHubSiteLayout.topBarHeightCompact
            : FleaHubSiteLayout.topBarHeight;
        final submit =
            widget.onSearchSubmitted ?? (q) => _defaultSubmit(context, q);

        final logo = InkWell(
          onTap: () => context.go(HubRoutePaths.landing),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Text(
              'FleaHub',
              style: GoogleFonts.inter(
                color: FleaberColors.teal,
                fontSize: compactChrome ? 20 : FleaHubSiteLayout.typeLogo,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
                height: 1.05,
              ),
            ),
          ),
        );

        final search = _SearchField(
          controller: widget.searchController,
          compact: compactChrome,
          onChanged: widget.onSearchChanged,
          onSubmitted: submit,
          autofocus: _searchExpanded && !inlineSearch,
        );

        final Widget body;
        if (desktop) {
          body = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (backBtn != null) ...[
                        backBtn,
                        const SizedBox(width: 2),
                      ],
                      Flexible(child: logo),
                    ],
                  ),
                ),
              ),
              Flexible(
                flex: 2,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: FleaHubSiteLayout.searchMaxWidth,
                    ),
                    child: search,
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _TopBarActions(
                    loggedIn: _loggedIn,
                    compact: false,
                    bagBadgeCount: widget.bagBadgeCount,
                    onBagTap: widget.onBagTap,
                    denseIcons: false,
                  ),
                ),
              ),
            ],
          );
        } else if (_searchExpanded && !inlineSearch) {
          body = Row(
            children: [
              if (backBtn != null) backBtn,
              Expanded(child: search),
              IconButton(
                tooltip: 'Fechar pesquisa',
                onPressed: () => setState(() => _searchExpanded = false),
                icon: const Icon(Icons.close_rounded, color: FleaberColors.teal),
              ),
            ],
          );
        } else {
          body = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (backBtn != null) backBtn,
              IconButton(
                tooltip: 'Menu',
                onPressed: () => _openInfoMenu(context),
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: const Icon(
                  Icons.menu_rounded,
                  color: FleaberColors.teal,
                  size: 26,
                ),
              ),
              logo,
              if (inlineSearch) ...[
                const SizedBox(width: 10),
                Expanded(child: search),
              ] else ...[
                const Spacer(),
                IconButton(
                  tooltip: 'Pesquisar',
                  onPressed: () => setState(() => _searchExpanded = true),
                  padding: const EdgeInsets.all(8),
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  icon: const Icon(
                    Icons.search_rounded,
                    color: FleaberColors.teal,
                    size: 26,
                  ),
                ),
              ],
              _TopBarActions(
                loggedIn: _loggedIn,
                compact: true,
                bagBadgeCount: widget.bagBadgeCount,
                onBagTap: widget.onBagTap,
                denseIcons: true,
              ),
            ],
          );
        }

        // Gap 14 px só em multi-eixo (≥900: H02 desktop / H03 shell).
        final showHairlineGap = MediaQuery.sizeOf(context).width >= 900;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad.left, 10, pad.right, 0),
              child: Container(
                height: barH,
                padding:
                    EdgeInsets.symmetric(horizontal: compactChrome ? 6 : 16),
                decoration: BoxDecoration(
                  color: FleaberColors.surface,
                  borderRadius: BorderRadius.circular(FleaberRadius.md),
                  border: Border.all(color: FleaberColors.alternate),
                  boxShadow: const [FleaberElevation.sm],
                ),
                alignment: Alignment.center,
                child: body,
              ),
            ),
            if (showHairlineGap)
              const SizedBox(height: FleaHubSiteLayout.topBarToHairlineGap),
          ],
        );
      },
    );
  }
}

/// Menu ☰ — páginas informativas (mobile / tablet / 1024).
class _FleaHubInfoMenuSheet extends StatelessWidget {
  const _FleaHubInfoMenuSheet();

  @override
  Widget build(BuildContext context) {
    Widget tile({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return ListTile(
        leading: Icon(icon, color: FleaberColors.teal),
        title: Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: FleaberColors.text,
          ),
        ),
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: FleaberColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: FleaberColors.alternate,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Informação',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: FleaberColors.text,
                  ),
                ),
              ),
            ),
            tile(
              icon: Icons.route_outlined,
              label: 'Como funciona',
              onTap: () => context.push(HubRoutePaths.howItWorks),
            ),
            tile(
              icon: Icons.verified_user_outlined,
              label: 'Comprar com segurança',
              onTap: () => context.push(HubRoutePaths.buySafe),
            ),
            tile(
              icon: Icons.store_mall_directory_outlined,
              label: 'Vender',
              onTap: () => context.push(HubRoutePaths.sell),
            ),
            tile(
              icon: Icons.help_outline_rounded,
              label: 'Ajuda',
              onTap: () => context.push(HubRoutePaths.help),
            ),
            tile(
              icon: Icons.contact_mail_outlined,
              label: 'Contactos',
              onTap: () => context.push(HubRoutePaths.contacts),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _TopBarActions extends StatelessWidget {
  const _TopBarActions({
    required this.loggedIn,
    required this.compact,
    required this.bagBadgeCount,
    this.onBagTap,
    this.denseIcons = false,
  });

  final bool loggedIn;
  final bool compact;
  final int bagBadgeCount;
  final VoidCallback? onBagTap;
  final bool denseIcons;

  @override
  Widget build(BuildContext context) {
    if (loggedIn) {
      // Sino + saco (atalho Home) + avatar (Mensagens/Saco/etc. no menu).
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onBagTap != null) ...[
            IconButton(
              tooltip: bagBadgeCount > 0
                  ? 'Reservas / Saco ($bagBadgeCount)'
                  : 'Reservas / Saco',
              onPressed: onBagTap,
              padding: EdgeInsets.all(denseIcons ? 6 : 8),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Badge(
                isLabelVisible: bagBadgeCount > 0,
                label: Text(
                  bagBadgeCount > 99 ? '99+' : '$bagBadgeCount',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                ),
                child: Icon(
                  Icons.shopping_bag_outlined,
                  color: FleaberColors.teal,
                  size: denseIcons ? 22 : 24,
                ),
              ),
            ),
            if (!denseIcons) const SizedBox(width: 2),
          ],
          FleaHubNotificationBell(
            onOpenBag: onBagTap,
            dense: denseIcons,
          ),
          if (!denseIcons) const SizedBox(width: 4),
          _ProfileMenuButton(
            dense: denseIcons,
            bagBadgeCount: bagBadgeCount,
            onBagTap: onBagTap,
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact && HubPublicAccess.registrationEnabled)
          TextButton(
            onPressed: () => HubActions.openRegistoForReturn(
              context,
              returnTo: HubRoutePaths.landing,
            ),
            child: Text(
              'Registar',
              style: GoogleFonts.inter(
                color: FleaberColors.teal,
                fontWeight: FontWeight.w700,
                fontSize: FleaHubSiteLayout.typeBody,
              ),
            ),
          ),
        OutlinedButton(
          onPressed: () => HubActions.openLoginForReturn(
            context,
            returnTo: HubRoutePaths.landing,
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: Size(0, compact ? 36 : 42),
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 16),
            side: const BorderSide(color: FleaberColors.teal, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            'Entrar',
            style: GoogleFonts.inter(
              color: FleaberColors.teal,
              fontWeight: FontWeight.w700,
              fontSize: FleaHubSiteLayout.typeBody,
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.compact,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final bool compact;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final h = compact
        ? FleaHubSiteLayout.searchFieldHeightCompact
        : FleaHubSiteLayout.searchFieldHeight;
    return SizedBox(
      height: h,
      child: Center(
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          autofocus: autofocus,
          textInputAction: TextInputAction.search,
          textAlignVertical: TextAlignVertical.center,
          style: GoogleFonts.inter(
            fontSize: compact ? 14 : FleaHubSiteLayout.typeSearch,
            fontWeight: FontWeight.w500,
            color: FleaberColors.text,
            height: 1.2,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: compact
                ? 'Pesquisar artigos…'
                : 'Pesquisar artigos e vendedores',
            hintStyle: GoogleFonts.inter(
              color: FleaberColors.muted,
              fontSize: compact ? 14 : FleaHubSiteLayout.typeSearch,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: compact ? 22 : 24,
              color: FleaberColors.muted,
            ),
            prefixIconConstraints: BoxConstraints(
              minWidth: compact ? 42 : 48,
              minHeight: h,
            ),
            filled: true,
            fillColor: const Color(0xFFF3F5F6),
            contentPadding: EdgeInsets.symmetric(
              vertical: compact ? 10 : 12,
              horizontal: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide(
                color: FleaberColors.alternate.withValues(alpha: 0.9),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide(
                color: FleaberColors.alternate.withValues(alpha: 0.9),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide(
                color: FleaberColors.teal.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuButton extends StatelessWidget {
  const _ProfileMenuButton({
    required this.dense,
    required this.bagBadgeCount,
    this.onBagTap,
  });

  final bool dense;
  final int bagBadgeCount;
  final VoidCallback? onBagTap;

  @override
  Widget build(BuildContext context) {
    final radius = dense ? 16.0 : 20.0;
    return PopupMenuButton<_ProfileMenuAction>(
      tooltip: 'Conta',
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: FleaberColors.surface,
      onSelected: (action) => _onSelected(context, action),
      itemBuilder: (ctx) => [
        _item(_ProfileMenuAction.messages, Icons.chat_bubble_outline_rounded,
            'Mensagens'),
        _item(_ProfileMenuAction.orders, Icons.receipt_long_outlined,
            'Compras / Encomendas'),
        _item(
          _ProfileMenuAction.bag,
          Icons.shopping_bag_outlined,
          bagBadgeCount > 0
              ? 'Reservas / Saco ($bagBadgeCount)'
              : 'Reservas / Saco',
        ),
        _item(_ProfileMenuAction.favorites, Icons.favorite_border_rounded,
            'Favoritos'),
        _item(_ProfileMenuAction.profile, Icons.person_outline_rounded,
            'Perfil'),
        const PopupMenuDivider(),
        _item(_ProfileMenuAction.signOut, Icons.logout_rounded,
            'Terminar sessão'),
      ],
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: dense ? 2 : 4, vertical: 2),
        child: FleaberProfileAvatar(
          userId: currentUserUid,
          photoUrl: currentUserPhoto,
          fullName: currentUserDisplayName,
          radius: radius,
          borderColor: FleaberColors.teal.withValues(alpha: 0.35),
          borderWidth: 1.5,
        ),
      ),
    );
  }

  PopupMenuItem<_ProfileMenuAction> _item(
    _ProfileMenuAction value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<_ProfileMenuAction>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: FleaberColors.teal),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: FleaberColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onSelected(BuildContext context, _ProfileMenuAction action) {
    switch (action) {
      case _ProfileMenuAction.messages:
        // H10 — Mensagens (rota única Hub + Conta).
        HubAccountRoutes.openMensagens(context);
      case _ProfileMenuAction.orders:
        HubAccountRoutes.openEncomendas(context);
      case _ProfileMenuAction.bag:
        if (onBagTap != null) {
          onBagTap!();
        } else {
          HubAccountRoutes.openEncomendas(context);
        }
      case _ProfileMenuAction.favorites:
        HubAccountRoutes.openFavoritos(context);
      case _ProfileMenuAction.profile:
        HubAccountRoutes.openResumo(context);
      case _ProfileMenuAction.signOut:
        authManager.signOut();
    }
  }
}

enum _ProfileMenuAction {
  messages,
  orders,
  bag,
  favorites,
  profile,
  signOut,
}

/// Rodapé institucional FleaHub/Fleaber · Maré Antiga (sem «Eliminar conta»).
class FleaHubSiteFooter extends StatelessWidget {
  const FleaHubSiteFooter({super.key});

  Future<void> _openLegal(BuildContext context, String kind) async {
    if (kIsWeb) {
      final url = switch (kind) {
        'terms' => LegalTexts.publicTermsUrl,
        'cookies' => LegalTexts.publicCookiesUrl,
        'refunds' => LegalTexts.publicRefundsUrl,
        _ => LegalTexts.publicPrivacyUrl,
      };
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    if (!context.mounted) return;
    context.pushNamed(
      LegalDocumentPageWidget.routeName,
      queryParameters: {'kind': kind},
    );
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = FleaHubSiteLayout.pagePadding(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final muted = GoogleFonts.inter(
      color: FleaberColors.muted,
      fontSize: 12.5,
      height: 1.45,
      fontWeight: FontWeight.w500,
    );
    final title = GoogleFonts.inter(
      color: FleaberColors.text,
      fontSize: 13.5,
      fontWeight: FontWeight.w800,
      height: 1.3,
    );
    final linkStyle = GoogleFonts.inter(
      color: FleaberColors.teal,
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      height: 1.35,
    );

    Widget link(String label, VoidCallback onTap) {
      return TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          alignment: Alignment.centerLeft,
        ),
        child: Text(label, style: linkStyle),
      );
    }

    final brandCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('FleaHub', style: title.copyWith(color: FleaberColors.teal, fontSize: 16)),
        const SizedBox(height: 4),
        Text(
          'Marketplace de compra em directo — marca Fleaber.',
          style: muted,
        ),
      ],
    );

    final entityCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(LegalTexts.operatorLegalName, style: title),
        const SizedBox(height: 6),
        Text('NIF ${LegalTexts.operatorNif}', style: muted),
        const SizedBox(height: 8),
        link(
          'Contactos e identificação legal',
          () => context.push(HubRoutePaths.contacts),
        ),
      ],
    );

    final legalCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Informação legal', style: title),
        const SizedBox(height: 6),
        link('Termos e Condições', () => _openLegal(context, 'terms')),
        link('Política de Privacidade', () => _openLegal(context, 'privacy')),
        link('Política de Cookies', () => _openLegal(context, 'cookies')),
        link('Reembolsos e Disputas', () => _openLegal(context, 'refunds')),
        link(
          'Livro de Reclamações Eletrónico',
          () => _openExternal(LegalTexts.livroReclamacoesUrl),
        ),
        // «Contactos…» só na coluna da empresa (evita duplicar).
      ],
    );

    final columns = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: brandCol),
              const SizedBox(width: 28),
              Expanded(child: entityCol),
              const SizedBox(width: 28),
              Expanded(child: legalCol),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              brandCol,
              const SizedBox(height: 16),
              entityCol,
              const SizedBox(height: 16),
              legalCol,
            ],
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(pad.left, 36, pad.right, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(
            height: 1,
            thickness: 1,
            color: FleaberColors.alternate.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 22),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: FleaHubSiteLayout.footerMaxWidth,
              ),
              child: columns,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            LegalTexts.copyrightLine,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: FleaberColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${LegalTexts.operatorLegalName} · NIF ${LegalTexts.operatorNif}',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: FleaberColors.muted.withValues(alpha: 0.85),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
