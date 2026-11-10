import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/nav/nav.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/utils/live_cover_assign.dart';
import '/utils/live_reservation_queue_service.dart';
import '/utils/mux_urls.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/home_mux_live_card.dart';
import '/widgets/marketplace_product_card.dart';

import '../data/hub_models.dart';
import '../data/hub_public_repository.dart';
import '../hub_actions.dart';
import '../hub_live_reservation_ui.dart';
import '../hub_urls.dart';
import '../routing/hub_route_paths.dart';
import '../seo/hub_seo_meta.dart';
import '../seo/hub_seo_policy.dart';
import '../widgets/fleahub_landing_buyer_rail.dart';
import '../widgets/fleahub_site_chrome.dart';
import '../widgets/hub_live_bag_sheet.dart';
import '../widgets/hub_seo_scope.dart';

/// Landing FleaHub — topbar + 3 zonas (nav · explorar · compras).
class FleaHubLandingPage extends StatefulWidget {
  const FleaHubLandingPage({super.key});

  static const routePath = HubRoutePaths.landing;
  static const routeName = 'FleaHubLanding';

  @override
  State<FleaHubLandingPage> createState() => _FleaHubLandingPageState();
}

enum _ExploreTab { diretos, marketplace }

class _FleaHubLandingPageState extends State<FleaHubLandingPage> {
  final _repo = HubPublicRepository();
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();
  final _exploreKey = GlobalKey();

  late Future<HubDiscoveryFeed> _discoveryFuture;
  Future<HubSearchResult>? _searchFuture;
  _ExploreTab _exploreTab = _ExploreTab.diretos;
  bool _exploreTabSeeded = false;
  String? _lastTabQuery;
  String _searchQuery = '';
  Timer? _searchDebounce;
  int _bagBadge = 0;
  List<LiveReservationRequestsRow> _bagRows = const [];

  @override
  void initState() {
    super.initState();
    _discoveryFuture = _repo.fetchDiscoveryFeed();
    _refreshBagBadge();
    AppStateNotifier.instance.addListener(_onAuth);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyTabFromQuery();
  }

  @override
  void dispose() {
    AppStateNotifier.instance.removeListener(_onAuth);
    _searchDebounce?.cancel();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onAuth() {
    _refreshBagBadge();
    if (mounted) setState(() {});
  }

  Future<void> _refreshBagBadge() async {
    final uid = currentUserUid.trim();
    if (uid.isEmpty) {
      if (mounted) {
        setState(() {
          _bagBadge = 0;
          _bagRows = const [];
        });
      }
      return;
    }
    try {
      final rows =
          await LiveReservationQueueService().buyerRequests(buyerId: uid);
      final summary = HubReservationSummary.fromRows(rows);
      if (!mounted) return;
      setState(() {
        _bagRows = rows;
        _bagBadge = summary.total;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bagRows = const [];
        _bagBadge = 0;
      });
    }
  }

  void _applyTabFromQuery() {
    final uri = GoRouterState.of(context).uri;
    final q = uri.queryParameters['q']?.trim();
    if (q != null && q.length >= 2 && q != _searchQuery) {
      _searchCtrl.text = q;
      setState(() {
        _searchQuery = q;
        _searchFuture = _repo.searchPublic(query: q);
      });
    }
    final tab = uri.queryParameters['tab']?.trim();
    if (tab == null || tab == _lastTabQuery) return;
    _lastTabQuery = tab;
    final next = switch (tab) {
      'diretos' || 'live' || 'recordings' => _ExploreTab.diretos,
      'marketplace' || 'hubs' => _ExploreTab.marketplace,
      _ => null,
    };
    if (next == null) return;
    if (next != _exploreTab) setState(() => _exploreTab = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToExplore();
    });
  }

  void _scrollToExplore() {
    final ctx = _exploreKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      alignment: 0.04,
    );
  }

  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      final q = raw.trim();
      setState(() {
        _searchQuery = q;
        _searchFuture = q.length < 2 ? null : _repo.searchPublic(query: q);
      });
    });
  }

  void _onSearchSubmitted(String raw) {
    _searchDebounce?.cancel();
    final q = raw.trim();
    setState(() {
      _searchQuery = q;
      _searchFuture = q.length < 2 ? null : _repo.searchPublic(query: q);
    });
    _scrollToExplore();
  }

  void _setExploreTab(_ExploreTab tab) {
    setState(() {
      _exploreTab = tab;
      _searchQuery = '';
      _searchCtrl.clear();
      _searchFuture = null;
    });
    _scrollToExplore();
  }

  void _seedExploreTabSafe(HubDiscoveryFeed feed) {
    if (_exploreTabSeeded) return;
    if (_lastTabQuery != null && _lastTabQuery!.isNotEmpty) {
      _exploreTabSeeded = true;
      return;
    }
    // Preferir Diretos se há live/gravados; senão Marketplace (artigos ou lojas).
    _ExploreTab next = _ExploreTab.diretos;
    if (feed.hasDiretos) {
      next = _ExploreTab.diretos;
    } else if (feed.marketplaceProducts.isNotEmpty ||
        feed.publishedHubs.isNotEmpty) {
      next = _ExploreTab.marketplace;
    }
    _exploreTabSeeded = true;
    if (next != _exploreTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _exploreTab = next);
      });
    }
  }

  Future<void> _openBag() async {
    if (currentUserUid.isEmpty) {
      HubActions.openLoginForReturn(context, returnTo: HubRoutePaths.landing);
      return;
    }
    if (!mounted) return;

    // E86: painel direito in-place (igual ao live) — sem push live / Encomendas.
    String sellerId = '';
    String liveId = '';
    for (final r in _bagRows) {
      final status = r.status;
      if (status != 'pending' && status != 'accepted') continue;
      final sid = (r.sellerId ?? '').trim();
      if (sid.isEmpty) continue;
      sellerId = sid;
      liveId = (r.liveId ?? '').trim();
      break;
    }

    final uid = currentUserUid.trim();
    final bagSellerId = sellerId;
    final bagLiveId = liveId;

    await HubLiveBagSheet.show(
      context,
      liveId: bagLiveId,
      sellerId: bagSellerId,
      itemsById: const {},
      summary: HubReservationSummary.fromRows(_bagRows),
      loadRows: () async {
        final buyer = currentUserUid.trim();
        if (buyer.isEmpty) return const <LiveReservationRequestsRow>[];
        if (bagSellerId.isNotEmpty) {
          return LiveReservationQueueService().sellerBagDisplayRequests(
            sellerId: bagSellerId,
            buyerId: buyer,
          );
        }
        if (bagLiveId.isNotEmpty) {
          return LiveReservationQueueService().liveBagDisplayRequests(
            liveId: bagLiveId,
            buyerId: buyer,
          );
        }
        // Saco vazio Home: estado H14 «Continuar a explorar».
        return const <LiveReservationRequestsRow>[];
      },
      loadSellerBagMeta: bagSellerId.isEmpty
          ? null
          : () => LiveReservationQueueService()
              .loadSellerBag(sellerId: bagSellerId),
      onChanged: () {
        unawaited(_refreshBagBadge());
      },
    );
    if (mounted && uid.isNotEmpty) await _refreshBagBadge();
  }

  @override
  Widget build(BuildContext context) {
    return HubSeoScope(
      meta: HubSeoMeta.forFleaHubLanding(
        indexable: HubSeoPolicy.allowHubIndexing(),
      ),
      child: FleaHubSiteScaffold(
        scrollController: _scrollCtrl,
        searchController: _searchCtrl,
        onSearchChanged: _onSearchChanged,
        onSearchSubmitted: _onSearchSubmitted,
        onBagTap: () => unawaited(_openBag()),
        bagBadgeCount: _bagBadge,
        body: _mainBody(context),
      ),
    );
  }

  Widget _mainBody(BuildContext context) {
    final pad = FleaHubSiteLayout.pagePadding(context);
    final three = FleaHubSiteLayout.isThreeZone(context);

    final center = KeyedSubtree(
      key: _exploreKey,
      child: _exploreColumn(context),
    );
    final left = _leftNav(context);
    final right = FleaHubLandingBuyerRail(onOpenBag: () => unawaited(_openBag()));

    final topGap = FleaHubSiteLayout.contentTopGap(context);

    if (three) {
      return Padding(
        padding: EdgeInsets.fromLTRB(pad.left, topGap, pad.right, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 17, child: left),
            const SizedBox(width: 16),
            Expanded(flex: 62, child: center),
            const SizedBox(width: 16),
            Expanded(flex: 21, child: right),
          ],
        ),
      );
    }

    // Compacto (&lt;1180): 3 separadores legíveis + grelha + rail abaixo.
    // (O antigo layout «2 zonas» 900–1180 comprimia nav/cartões — Entrega 92.)
    return Padding(
      padding: EdgeInsets.fromLTRB(pad.left, topGap, pad.right, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!FleaHubSiteLayout.showsLeftRail(context)) ...[
            _exploreTabBar(context),
            const SizedBox(height: 12),
          ],
          center,
          const SizedBox(height: 14),
          right,
        ],
      ),
    );
  }

  Widget _leftNav(BuildContext context) {
    Widget item({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool selected = false,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: selected
              ? FleaberColors.teal.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: selected ? FleaberColors.teal : FleaberColors.muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        color: selected ? FleaberColors.teal : FleaberColors.text,
                        fontSize: FleaHubSiteLayout.typeNav,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      decoration: BoxDecoration(
        color: FleaberColors.surface,
        borderRadius: BorderRadius.circular(FleaberRadius.md),
        border: Border.all(color: FleaberColors.alternate),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              'Explorar',
              style: GoogleFonts.inter(
                color: FleaberColors.text,
                fontSize: FleaHubSiteLayout.typeNavTitle,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          item(
            icon: Icons.videocam_outlined,
            label: 'Diretos',
            selected:
                _exploreTab == _ExploreTab.diretos && _searchQuery.length < 2,
            onTap: () => _setExploreTab(_ExploreTab.diretos),
          ),
          item(
            icon: Icons.storefront_outlined,
            label: 'Marketplace',
            selected: _exploreTab == _ExploreTab.marketplace &&
                _searchQuery.length < 2,
            onTap: () => _setExploreTab(_ExploreTab.marketplace),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Divider(height: 1),
          ),
          item(
            icon: Icons.route_outlined,
            label: 'Como funciona',
            onTap: () => context.push(HubRoutePaths.howItWorks),
          ),
          item(
            icon: Icons.verified_user_outlined,
            label: 'Comprar com segurança',
            onTap: () => context.push(HubRoutePaths.buySafe),
          ),
          item(
            icon: Icons.store_mall_directory_outlined,
            label: 'Vender na Fleaber',
            onTap: () => context.push(HubRoutePaths.sell),
          ),
          item(
            icon: Icons.help_outline_rounded,
            label: 'Ajuda',
            onTap: () => context.push(HubRoutePaths.help),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _googlePlayBadge(),
          ),
        ],
      ),
    );
  }

  /// Dois separadores (Diretos / Marketplace) — alinhados à Home da app.
  Widget _exploreTabBar(BuildContext context) {
    Widget tab({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Material(
          color: selected
              ? FleaberColors.teal.withValues(alpha: 0.12)
              : FleaberColors.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? FleaberColors.teal.withValues(alpha: 0.4)
                      : FleaberColors.alternate,
                ),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  color: selected ? FleaberColors.teal : FleaberColors.text,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final searching = _searchQuery.length >= 2;
    return Row(
      children: [
        tab(
          label: 'Diretos',
          selected: !searching && _exploreTab == _ExploreTab.diretos,
          onTap: () => _setExploreTab(_ExploreTab.diretos),
        ),
        const SizedBox(width: 8),
        tab(
          label: 'Marketplace',
          selected: !searching && _exploreTab == _ExploreTab.marketplace,
          onTap: () => _setExploreTab(_ExploreTab.marketplace),
        ),
      ],
    );
  }

  Widget _googlePlayBadge() {
    final published = HubUrls.installAndroidPublished;
    return Opacity(
      opacity: published ? 1 : 0.85,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: published ? () => HubActions.openInstallApp() : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF000000),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.play_arrow_rounded,
                  size: 28,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        published ? 'DISPONÍVEL NO' : 'EM BREVE NO',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        'Google Play',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _exploreColumn(BuildContext context) {
    final searching = _searchQuery.length >= 2;
    // Tabs Diretos/Marketplace: lateral (desktop) ou barra compacta — sem duplicar.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!searching) ...[
          FutureBuilder<HubDiscoveryFeed>(
            future: _discoveryFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(color: FleaberColors.teal),
                  ),
                );
              }
              if (snap.hasError) {
                return _empty(
                  'Não foi possível carregar.',
                  action: TextButton(
                    onPressed: () {
                      setState(() {
                        _exploreTabSeeded = false;
                        _discoveryFuture = _repo.fetchDiscoveryFeed();
                      });
                    },
                    child: const Text('Tentar novamente'),
                  ),
                );
              }
              final feed = snap.data;
              if (feed == null || feed.isEmpty) {
                return _empty(
                  'Ainda não há diretos nem artigos no Marketplace.',
                );
              }
              _seedExploreTabSafe(feed);
              return _exploreGrid(context, feed);
            },
          ),
        ] else ...[
          Text(
            'Resultados para «$_searchQuery»',
            style: GoogleFonts.inter(
              color: FleaberColors.text,
              fontSize: FleaHubSiteLayout.typeSection,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<HubSearchResult>(
            future: _searchFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CircularProgressIndicator(color: FleaberColors.teal),
                  ),
                );
              }
              final result = snap.data;
              if (result == null || result.isEmpty) {
                return _empty('Sem resultados para esta pesquisa.');
              }
              return _searchResults(context, result);
            },
          ),
        ],
      ],
    );
  }

  Widget _empty(String message, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(Icons.storefront_outlined, color: FleaberColors.muted, size: 36),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: FleaberColors.muted,
              fontSize: FleaHubSiteLayout.typeBody,
              height: 1.4,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 10), action],
        ],
      ),
    );
  }

  Widget _exploreGrid(BuildContext context, HubDiscoveryFeed feed) {
    switch (_exploreTab) {
      case _ExploreTab.diretos:
        // Como a app: diretos activos; se não houver, gravados disponíveis.
        final lives = feed.liveNow;
        final recs = feed.recentRecordings;
        if (lives.isNotEmpty) {
          return _responsiveCardWrap([
            for (final live in lives)
              _discoveryLiveCard(context, live: live, isLiveNow: true),
          ]);
        }
        if (recs.isNotEmpty) {
          return _responsiveCardWrap([
            for (final live in recs)
              _discoveryLiveCard(context, live: live, isLiveNow: false),
          ]);
        }
        return _empty('Não há diretos ao vivo nem gravados neste momento.');

      case _ExploreTab.marketplace:
        final products = feed.marketplaceProducts;
        final hubs = feed.publishedHubs;
        if (products.isEmpty && hubs.isEmpty) {
          return _empty('Ainda sem artigos no Marketplace.');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (products.isNotEmpty)
              _marketplaceCardWrap([
                for (final p in products) _marketplaceProductCard(context, p),
              ]),
            if (hubs.isNotEmpty) ...[
              if (products.isNotEmpty) const SizedBox(height: 20),
              Text(
                'Lojas FleaHub',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: FleaHubSiteLayout.typeBody,
                  color: FleaberColors.muted,
                ),
              ),
              const SizedBox(height: 8),
              _responsiveCardWrap([
                for (final p in hubs) _hubCoverCard(context, p),
              ]),
            ],
          ],
        );
    }
  }

  Widget _searchResults(BuildContext context, HubSearchResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result.profiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Vendedores',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: FleaHubSiteLayout.typeBody,
                color: FleaberColors.muted,
              ),
            ),
          ),
        _responsiveCardWrap(
          result.profiles.map((p) => _hubCoverCard(context, p)).toList(),
        ),
        if (result.products.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Marketplace',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: FleaHubSiteLayout.typeBody,
              color: FleaberColors.muted,
            ),
          ),
          const SizedBox(height: 8),
          _marketplaceCardWrap([
            for (final p in result.products) _marketplaceProductCard(context, p),
          ]),
        ],
        if (result.items.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Artigos em direto',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: FleaHubSiteLayout.typeBody,
              color: FleaberColors.muted,
            ),
          ),
          const SizedBox(height: 8),
          _responsiveCardWrap(
            result.items.map((i) => _itemSearchCard(context, i)).toList(),
          ),
        ],
      ],
    );
  }

  /// Diretos / capas Hub — grelha 9:16 (5 cols Home aprovada).
  Widget _responsiveCardWrap(List<Widget> cards) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final mobile = maxW < 520;
        final gap = mobile ? 10.0 : 12.0;
        final target = FleaHubSiteLayout.exploreCardTargetWidth;
        final minW = FleaHubSiteLayout.exploreCardMinWidth;
        final maxCard = FleaHubSiteLayout.exploreCardMaxWidth;

        if (mobile) {
          final cardW = (maxW - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final c in cards)
                SizedBox(width: cardW, height: cardW * 16 / 9, child: c),
            ],
          );
        }

        // Preferir 5 cols quando cada cartão ≥ minW; senão reduzir (nunca forçar estreitos).
        final maxColsFit = ((maxW + gap) / (minW + gap)).floor().clamp(2, 6);
        var cols = 5.clamp(2, maxColsFit);
        var cardW = (maxW - gap * (cols - 1)) / cols;
        if (cardW > maxCard) {
          cols = ((maxW + gap) / (target + gap)).floor().clamp(2, maxColsFit);
          cardW = ((maxW - gap * (cols - 1)) / cols).clamp(minW, maxCard);
        } else {
          cardW = cardW.clamp(minW, maxCard);
        }

        return Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final c in cards)
                SizedBox(width: cardW, height: cardW * 16 / 9, child: c),
            ],
          ),
        );
      },
    );
  }

  /// Marketplace Home — mesmo cartão H02 (foto + texto abaixo); 5/fila.
  Widget _marketplaceCardWrap(List<Widget> cards) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final gap = maxW < 520 ? 10.0 : 12.0;
        final minW = 128.0;
        final maxCols = maxW >= 1280
            ? 6
            : (maxW >= 900
                ? 5
                : (maxW >= 700 ? 4 : (maxW >= 520 ? 3 : 2)));
        final cols =
            ((maxW + gap) / (minW + gap)).floor().clamp(2, maxCols);
        final cardW = (maxW - gap * (cols - 1)) / cols;
        final cardH = MarketplaceProductCard.horizontalListHeight(cardW);

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final c in cards)
              SizedBox(width: cardW, height: cardH, child: c),
          ],
        );
      },
    );
  }

  Widget _discoveryLiveCard(
    BuildContext context, {
    required HubLive live,
    required bool isLiveNow,
  }) {
    final handle = live.sellerHandle.trim();
    final name = (live.sellerName?.trim().isNotEmpty == true)
        ? live.sellerName!.trim()
        : (handle.isNotEmpty ? handle : 'Vendedor');
    final coverId = LiveCoverAssign.resolveCoverId(
      liveId: live.id,
      persistedCoverId: live.coverId,
    );
    final preparing = !isLiveNow &&
        (live.effectivePlaybackId == null ||
            live.effectivePlaybackId!.trim().isEmpty);
    final playbackId = live.effectivePlaybackId?.trim() ?? '';
    final landscapeThumb =
        MuxUrls.publishBackendUsesLandscapeThumb(live.publishBackend);
    final thumbUrl = playbackId.isEmpty
        ? ''
        : (landscapeThumb
            ? MuxUrls.landscapeThumbnail(
                playbackId,
                width: 360,
                live: isLiveNow,
              )
            : MuxUrls.portraitThumbnail(
                playbackId,
                width: 360,
                live: isLiveNow,
              ));

    void open() {
      if (handle.isEmpty) return;
      context.push(HubRoutePaths.liveFor(handle, liveId: live.id));
    }

    final title = live.title?.trim();

    return HomeMuxLiveCard(
      sellerName: name,
      liveTitle: (title != null && title.isNotEmpty) ? title : null,
      thumbnailUrl: thumbUrl,
      fallbackAvatarUrl: live.sellerPhotoUrl,
      ratingLabel: '5.0',
      coverId: coverId,
      isLive: isLiveNow,
      isRecordingPreparing: preparing,
      onOpenLive: handle.isEmpty ? () {} : open,
      onOpenSellerProfile: handle.isEmpty
          ? null
          : () => context.push(HubRoutePaths.profileFor(handle)),
      onOpenSellerOpinions: handle.isEmpty
          ? null
          : () => context.push(HubRoutePaths.reviewsFor(handle)),
    );
  }

  Widget _hubCoverCard(BuildContext context, HubProfile profile) {
    final name = profile.fullName.trim().isNotEmpty
        ? profile.fullName.trim()
        : profile.handle;
    final loc = profile.location?.trim();
    final subtitle = (loc != null && loc.isNotEmpty) ? loc : 'FleaHub';

    return _LandingHubCard(
      onTap: () => context.push(HubRoutePaths.profileFor(profile.handle)),
      coverUrl: profile.photoUrl,
      name: name,
      subtitle: subtitle,
      isLive: profile.isLive,
    );
  }

  Widget _marketplaceProductCard(BuildContext context, HubProduct product) {
    final price = product.price;
    final priceLabel =
        price == null ? '—' : '${price.toStringAsFixed(2)} €';
    return MarketplaceProductCard(
      title: product.title.trim().isEmpty ? 'Artigo' : product.title.trim(),
      stateLabel: product.state,
      priceLabel: priceLabel,
      imageUrl: product.primaryImage,
      favoritesCount: 0,
      isFavorited: false,
      onFavoriteTap: null,
      onTap: () {
        if (product.id.isEmpty) return;
        context.push('/productDetails?product_id=${product.id}');
      },
    );
  }

  Widget _itemSearchCard(BuildContext context, HubLiveItem item) {
    final handle = item.sellerHandle.trim();
    final title = (item.title?.trim().isNotEmpty == true)
        ? item.title!.trim()
        : (item.refCode?.trim().isNotEmpty == true
            ? item.refCode!.trim()
            : 'Artigo');
    final price = item.price;
    final priceLabel = price == null ? null : '${price.toStringAsFixed(2)} €';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(FleaberRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(FleaberRadius.lg),
        onTap: handle.isEmpty
            ? null
            : () => context.push(
                  HubRoutePaths.liveFor(handle, liveId: item.liveId),
                ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(FleaberRadius.lg),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (item.photoUrl != null && item.photoUrl!.trim().isNotEmpty)
                BatataCachedNetworkImage(
                  imageUrl: item.photoUrl!.trim(),
                  fit: BoxFit.cover,
                  placeholderColor: FleaberColors.alternate,
                )
              else
                Container(
                  color: FleaberColors.alternate,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.shopping_bag_outlined,
                    color: FleaberColors.muted,
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.72),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: FleaHubSiteLayout.typeBody,
                      ),
                    ),
                    if (priceLabel != null)
                      Text(
                        priceLabel,
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w600,
                          fontSize: FleaHubSiteLayout.typeSecondary,
                        ),
                      ),
                    Text(
                      '@$handle',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: FleaHubSiteLayout.typeCaption,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LandingHubCard extends StatelessWidget {
  const _LandingHubCard({
    required this.onTap,
    required this.coverUrl,
    required this.name,
    required this.subtitle,
    required this.isLive,
  });

  final VoidCallback onTap;
  final String? coverUrl;
  final String name;
  final String subtitle;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(FleaberRadius.lg),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FleaberRadius.lg),
        child: Stack(
          fit: StackFit.expand,
          children: [
            InkWell(
              onTap: onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (coverUrl != null && coverUrl!.trim().isNotEmpty)
                    BatataCachedNetworkImage(
                      imageUrl: coverUrl!.trim(),
                      fit: BoxFit.cover,
                      placeholderColor: FleaberColors.alternate,
                    )
                  else
                    Container(
                      color: FleaberColors.alternate,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.storefront_outlined,
                        color: FleaberColors.muted,
                        size: 40,
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.08),
                          Colors.black.withValues(alpha: 0.72),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isLive)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: FleaberColors.danger,
                    borderRadius: FleaberRadius.circularSm,
                  ),
                  child: Text(
                    'AO VIVO',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: FleaHubSiteLayout.typeCaption,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w600,
                      fontSize: FleaHubSiteLayout.typeSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
