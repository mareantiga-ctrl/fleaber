import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:google_fonts/google_fonts.dart';

import '/flutter_flow/nav/nav.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_elevation.dart';
import '/utils/fleaber_radius.dart';
import '/utils/live_cover_assign.dart';
import '/utils/mux_urls.dart';
import '/utils/seller_vacation_mode.dart';
import '/widgets/fleaber_cookie_consent_banner.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/home_mux_live_card.dart';
import '/widgets/marketplace_product_card.dart';
import '/widgets/profile_avatar.dart';

import '../data/hub_demo_reviews.dart';
import '../data/hub_models.dart';
import '../data/hub_public_repository.dart';
import '../hub_actions.dart';
import '../routing/hub_route_paths.dart';
import '../seo/hub_seo_meta.dart';
import '../seo/hub_seo_policy.dart';
import '../widgets/fleahub_site_chrome.dart';
import '../widgets/hub_profile_light_reviews.dart';
import '../widgets/hub_seo_scope.dart';

/// Perfil público vendedor — H02 (Entrega 97 · dois eixos + 3 tabs).
class HubProfilePage extends StatefulWidget {
  const HubProfilePage({
    super.key,
    required this.handle,
    required this.profileId,
    this.initialTab,
  });

  final String handle;
  final String profileId;

  /// `diretos` | `marketplace` | `opinioes` (+ aliases).
  final String? initialTab;

  static const double desktopBreakpoint = 900;
  static const double leftRailFraction = 0.24;
  static const int pageSize = 12;

  @override
  State<HubProfilePage> createState() => _HubProfilePageState();
}

enum _ProfileTab { diretos, marketplace, opinioes }

/// Tab inicial H02 = Marketplace. Só muda se [raw] pedir explicitamente outra.
_ProfileTab _parseTab(String? raw) {
  final t = (raw ?? '').trim().toLowerCase();
  if (t.isEmpty) return _ProfileTab.marketplace;
  switch (t) {
    case 'diretos':
    case 'live':
    case 'lives':
    case 'gravados':
    case 'recordings':
      return _ProfileTab.diretos;
    case 'opinioes':
    case 'opiniões':
    case 'reviews':
    case 'avaliacoes':
    case 'avaliações':
      return _ProfileTab.opinioes;
    case 'marketplace':
    case 'shop':
    case 'loja':
    case 'produtos':
    default:
      return _ProfileTab.marketplace;
  }
}

class _HubProfilePageState extends State<HubProfilePage> {
  final _repo = HubPublicRepository();
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();

  HubProfile? _profile;
  bool _bootLoading = true;
  Object? _bootError;

  late _ProfileTab _tab;

  final List<HubLive> _lives = [];
  bool _livesLoadingMore = false;
  bool _livesHasMore = true;

  final List<HubProduct> _products = [];
  bool _productsLoadingMore = false;
  bool _productsHasMore = true;

  HubReviewsStatsResult _reviewStats = const HubReviewsStatsResult.empty();
  final List<HubReview> _reviews = [];
  final Set<String> _reviewSeen = {};
  bool _reviewsBooted = false;
  bool _reviewsLoading = false;
  bool _reviewsLoadingMore = false;
  bool _reviewsHasMore = false;
  bool _usingDemoReviews = false;
  int? _starsFilter;
  String _reviewSort = 'newest';
  int _reviewGen = 0;

  bool? _isFollowing;

  @override
  void initState() {
    super.initState();
    _tab = _parseTab(widget.initialTab);
    _bootstrap();
    AppStateNotifier.instance.addListener(_onAuthSessionChanged);
  }

  @override
  void didUpdateWidget(covariant HubProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      final next = _parseTab(widget.initialTab);
      if (next != _tab) {
        setState(() => _tab = next);
        if (next == _ProfileTab.opinioes) unawaited(_ensureReviews());
      }
    }
    if (oldWidget.profileId != widget.profileId) {
      _bootstrap();
    }
  }

  @override
  void dispose() {
    AppStateNotifier.instance.removeListener(_onAuthSessionChanged);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onAuthSessionChanged() {
    unawaited(_refreshFollow());
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    setState(() {
      _bootLoading = true;
      _bootError = null;
    });
    try {
      final bundle = await _repo.fetchProfileBundle(
        widget.profileId,
        livesLimit: HubProfilePage.pageSize,
        productsLimit: HubProfilePage.pageSize,
        reviewsLimit: 1,
      );
      if (!mounted) return;
      if (bundle == null) {
        setState(() {
          _profile = null;
          _bootLoading = false;
        });
        return;
      }
      final stats =
          await _repo.fetchReviewsStatsForSeller(widget.profileId);
      if (!mounted) return;
      final useDemo = HubDemoReviews.shouldUse(
        realCount: stats.count,
        queryDemo: _demoReviewsQuery(),
      );
      setState(() {
        _profile = bundle.profile;
        _lives
          ..clear()
          ..addAll(bundle.lives);
        _livesHasMore = bundle.lives.length >= HubProfilePage.pageSize;
        _products
          ..clear()
          ..addAll(bundle.products);
        _productsHasMore = bundle.products.length >= HubProfilePage.pageSize;
        if (useDemo) {
          _applyDemoReviews();
          _reviewsBooted = true;
        } else {
          _reviewStats = stats;
          _usingDemoReviews = false;
        }
        _bootLoading = false;
      });
      await _refreshFollow();
      if (_tab == _ProfileTab.opinioes && !useDemo) {
        await _ensureReviews();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootError = e;
        _bootLoading = false;
      });
    }
  }

  Future<void> _refreshFollow() async {
    final v = await HubActions.queryIsFollowing(widget.profileId);
    if (mounted) setState(() => _isFollowing = v);
  }

  Future<void> _loadMoreLives() async {
    if (_livesLoadingMore || !_livesHasMore) return;
    setState(() => _livesLoadingMore = true);
    try {
      final page = await _repo.fetchLivesForSeller(
        widget.profileId,
        limit: HubProfilePage.pageSize,
        offset: _lives.length,
      );
      if (!mounted) return;
      setState(() {
        _lives.addAll(page);
        _livesHasMore = page.length >= HubProfilePage.pageSize;
        _livesLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _livesLoadingMore = false);
    }
  }

  Future<void> _loadMoreProducts() async {
    if (_productsLoadingMore || !_productsHasMore) return;
    setState(() => _productsLoadingMore = true);
    try {
      final page = await _repo.fetchProductsForSeller(
        widget.profileId,
        limit: HubProfilePage.pageSize,
        offset: _products.length,
      );
      if (!mounted) return;
      setState(() {
        _products.addAll(page);
        _productsHasMore = page.length >= HubProfilePage.pageSize;
        _productsLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _productsLoadingMore = false);
    }
  }

  String? _demoReviewsQuery() {
    try {
      return GoRouterState.of(context).uri.queryParameters['demo_reviews'];
    } catch (_) {
      return null;
    }
  }

  void _applyDemoReviews() {
    final items = HubDemoReviews.filtered(
      starsFilter: _starsFilter,
      sort: _reviewSort,
    );
    _reviews
      ..clear()
      ..addAll(items);
    _reviewSeen
      ..clear()
      ..addAll(items.map((r) => r.id));
    _reviewStats = HubDemoReviews.stats;
    _reviewsHasMore = false;
    _usingDemoReviews = true;
  }

  Future<void> _ensureReviews() async {
    if (_reviewsBooted || _reviewsLoading) return;
    setState(() => _reviewsLoading = true);
    try {
      final stats =
          await _repo.fetchReviewsStatsForSeller(widget.profileId);
      if (!mounted) return;
      final useDemo = HubDemoReviews.shouldUse(
        realCount: stats.count,
        queryDemo: _demoReviewsQuery(),
      );
      if (useDemo) {
        setState(() {
          _applyDemoReviews();
          _reviewsBooted = true;
          _reviewsLoading = false;
        });
        return;
      }
      setState(() {
        _reviewStats = stats;
        _usingDemoReviews = false;
      });
      await _reloadReviews();
      if (!mounted) return;
      setState(() {
        _reviewsBooted = true;
        _reviewsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Sem API: em preview local ainda permitir demo.
      if (HubDemoReviews.shouldUse(
        realCount: 0,
        queryDemo: _demoReviewsQuery(),
      )) {
        setState(() {
          _applyDemoReviews();
          _reviewsBooted = true;
          _reviewsLoading = false;
        });
        return;
      }
      setState(() {
        _reviewsLoading = false;
        _reviewsBooted = true;
        _usingDemoReviews = false;
      });
    }
  }

  Future<void> _reloadReviews() async {
    final gen = ++_reviewGen;
    if (_usingDemoReviews) {
      setState(() {
        _applyDemoReviews();
        _reviewsLoadingMore = false;
      });
      return;
    }
    setState(() {
      _reviews.clear();
      _reviewSeen.clear();
      _reviewsHasMore = false;
      _reviewsLoadingMore = true;
    });
    try {
      final page = await _repo.fetchReviewsPageForSeller(
        widget.profileId,
        limit: 10,
        starsFilter: _starsFilter,
        sort: _reviewSort,
      );
      if (!mounted || gen != _reviewGen) return;
      _appendReviews(page);
    } finally {
      if (mounted && gen == _reviewGen) {
        setState(() => _reviewsLoadingMore = false);
      }
    }
  }

  Future<void> _loadMoreReviews() async {
    if (_usingDemoReviews) return;
    if (!_reviewsHasMore || _reviewsLoadingMore || _reviews.isEmpty) return;
    final gen = _reviewGen;
    setState(() => _reviewsLoadingMore = true);
    try {
      final last = _reviews.last;
      final page = await _repo.fetchReviewsPageForSeller(
        widget.profileId,
        limit: 10,
        starsFilter: _starsFilter,
        sort: _reviewSort,
        cursorCreatedAt: last.createdAt,
        cursorId: last.id,
        cursorStars: last.stars,
      );
      if (!mounted || gen != _reviewGen) return;
      _appendReviews(page);
    } finally {
      if (mounted && gen == _reviewGen) {
        setState(() => _reviewsLoadingMore = false);
      }
    }
  }

  void _appendReviews(HubReviewsPageResult page) {
    var added = 0;
    for (final r in page.items) {
      if (r.id.isEmpty || _reviewSeen.contains(r.id)) continue;
      _reviewSeen.add(r.id);
      _reviews.add(r);
      added++;
    }
    setState(() {
      _reviewsHasMore = page.hasMore && added > 0;
      if (page.items.isEmpty) _reviewsHasMore = false;
    });
  }

  void _setTab(_ProfileTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
    final q = switch (tab) {
      _ProfileTab.diretos => 'diretos',
      _ProfileTab.marketplace => 'marketplace',
      _ProfileTab.opinioes => 'opinioes',
    };
    final path = HubRoutePaths.profileTabFor(widget.handle, q);
    try {
      context.replace(path);
    } catch (_) {
      try {
        context.go(path);
      } catch (_) {}
    }
    if (tab == _ProfileTab.opinioes) unawaited(_ensureReviews());
  }

  void _onSearchSubmitted(String raw) {
    final q = raw.trim();
    if (q.length < 2) {
      context.go(HubRoutePaths.landing);
      return;
    }
    context.go(
      '${HubRoutePaths.landing}?q=${Uri.encodeQueryComponent(q)}',
    );
  }

  bool _isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= HubProfilePage.desktopBreakpoint;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStateNotifier.instance,
      builder: (context, _) {
        if (_bootLoading) {
          return FleaHubLoadingShell(
            searchController: _searchCtrl,
            onSearchSubmitted: _onSearchSubmitted,
          );
        }
        if (_bootError != null) {
          return _shell(
            context,
            contentSlivers: [
              SliverToBoxAdapter(
                child: _EmptyBlock(
                  message: 'Não foi possível carregar.',
                  action: TextButton(
                    onPressed: _bootstrap,
                    child: const Text('Tentar novamente'),
                  ),
                ),
              ),
            ],
          );
        }
        final profile = _profile;
        if (profile == null) {
          return _shell(
            context,
            contentSlivers: const [
              SliverToBoxAdapter(
                child: _EmptyBlock(
                  message: 'Perfil indisponível.',
                  icon: Icons.person_off_outlined,
                ),
              ),
            ],
          );
        }

        return HubSeoScope(
          meta: HubSeoMeta.forProfile(
            profile: profile,
            bundle: HubProfileBundle(
              profile: profile,
              lives: List.unmodifiable(_lives),
              products: List.unmodifiable(_products),
              reviews: List.unmodifiable(_reviews),
            ),
            indexable: HubSeoPolicy.allowHubIndexing(),
          ),
          child: _shell(
            context,
            onRefresh: _bootstrap,
            contentSlivers: () {
              final pad = FleaHubSiteLayout.pagePadding(context);
              if (_isDesktop(context)) {
                return [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        pad.left,
                        FleaHubSiteLayout.contentTopGap(context),
                        pad.right,
                        0,
                      ),
                      child: _desktopBody(context, profile),
                    ),
                  ),
                ];
              }
              return _mobileContentSlivers(context, profile);
            }(),
          ),
        );
      },
    );
  }

  List<Widget> _mobileContentSlivers(
    BuildContext context,
    HubProfile profile,
  ) {
    final pad = FleaHubSiteLayout.pagePadding(context);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            pad.left,
            FleaHubSiteLayout.contentTopGap(context),
            pad.right,
            0,
          ),
          child: _IdentityPanel(
            profile: profile,
            handle: widget.handle,
            reviewStats: _reviewStats,
            isFollowing: _isFollowing ?? false,
            onFollow: _onFollow,
            onShare: _onShare,
            onOpenOpinions: () => _setTab(_ProfileTab.opinioes),
            desktop: false,
          ),
        ),
      ),
      SliverPersistentHeader(
        pinned: true,
        delegate: _StickyTabsDelegate(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad.left, 8, pad.right, 8),
            child: _tabBar(context),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad.left, 4, pad.right, 0),
          child: _tabContent(context, profile),
        ),
      ),
    ];
  }

  Widget _shell(
    BuildContext context, {
    required List<Widget> contentSlivers,
    Future<void> Function()? onRefresh,
  }) {
    final maxW = FleaHubSiteLayout.maxContentWidth(context);

    final scroll = CustomScrollView(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: FleaHubSiteTopBar(
            searchController: _searchCtrl,
            onSearchSubmitted: _onSearchSubmitted,
          ),
        ),
        // Hairline só no layout de dois eixos (desktop).
        if (_isDesktop(context))
          const SliverToBoxAdapter(child: FleaHubTopBarBleed()),
        ...contentSlivers,
        const SliverToBoxAdapter(child: FleaHubSiteFooter()),
        SliverToBoxAdapter(
          child: ListenableBuilder(
            listenable: FleaberCookieConsentBanner.consentAccepted,
            builder: (context, _) {
              final size = MediaQuery.sizeOf(context);
              final reserve = FleaberCookieConsentBanner.consentAccepted.value
                  ? 28.0
                  : FleaberCookieConsentBanner.scrollReserveForViewport(
                      width: size.width,
                      height: size.height,
                    );
              return SizedBox(height: reserve);
            },
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: FleaberColors.bgTint,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: onRefresh == null
                ? scroll
                : RefreshIndicator(
                    color: FleaberColors.teal,
                    onRefresh: onRefresh,
                    child: scroll,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _desktopBody(BuildContext context, HubProfile profile) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final leftW =
            (maxW * HubProfilePage.leftRailFraction).clamp(220.0, 300.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: leftW,
              child: _IdentityPanel(
                profile: profile,
                handle: widget.handle,
                reviewStats: _reviewStats,
                isFollowing: _isFollowing ?? false,
                onFollow: _onFollow,
                onShare: _onShare,
                onOpenOpinions: () => _setTab(_ProfileTab.opinioes),
                desktop: true,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _tabBar(context),
                  const SizedBox(height: 14),
                  _tabContent(context, profile),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onFollow() async {
    await HubActions.toggleFollow(
      context,
      sellerId: widget.profileId,
      isFollowing: _isFollowing == true,
    );
    await _refreshFollow();
  }

  void _onShare() {
    String? activeId;
    for (final l in _lives) {
      if (hubLiveIsCredibleNow(l)) {
        activeId = l.id;
        break;
      }
    }
    HubActions.shareProfileOrLive(
      context,
      handle: widget.handle,
      activeLiveId: activeId,
    );
  }

  Widget _tabBar(BuildContext context) {
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
                  fontSize: FleaHubSiteLayout.typeTab,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  color: selected ? FleaberColors.teal : FleaberColors.text,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(
          label: 'Diretos',
          selected: _tab == _ProfileTab.diretos,
          onTap: () => _setTab(_ProfileTab.diretos),
        ),
        const SizedBox(width: 8),
        tab(
          label: 'Marketplace',
          selected: _tab == _ProfileTab.marketplace,
          onTap: () => _setTab(_ProfileTab.marketplace),
        ),
        const SizedBox(width: 8),
        tab(
          label: 'Opiniões',
          selected: _tab == _ProfileTab.opinioes,
          onTap: () => _setTab(_ProfileTab.opinioes),
        ),
      ],
    );
  }

  Widget _tabContent(BuildContext context, HubProfile profile) {
    return switch (_tab) {
      _ProfileTab.diretos => _diretosPane(context, profile),
      _ProfileTab.marketplace => _marketplacePane(context),
      _ProfileTab.opinioes => _opinioesPane(context),
    };
  }

  List<HubLive> get _activeLives {
    final list = _lives.where(hubLiveIsCredibleNow).toList();
    list.sort((a, b) => hubLiveRecency(b).compareTo(hubLiveRecency(a)));
    return list;
  }

  List<HubLive> get _recordingLives {
    // Reutiliza regras pastLives via bundle temporário.
    final tmp = HubProfileBundle(
      profile: _profile!,
      lives: _lives,
      products: const [],
      reviews: const [],
    );
    return tmp.pastLives;
  }

  Widget _diretosPane(BuildContext context, HubProfile profile) {
    // Alinhado à app (ProfileLivesTab): em férias, ocultar diretos/gravações
    // a visitantes (o próprio vendedor continua a ver o conteúdo).
    final hideForVacation = SellerVacationMode.hideSellerFromPublicDiscovery(
      sellerOnVacation: profile.vacationMode,
      sellerId: profile.id,
    );
    if (hideForVacation) {
      return const _EmptyBlock(
        message:
            'Este vendedor está de férias. Os diretos estão temporariamente ocultos.',
        icon: Icons.beach_access_outlined,
      );
    }

    final active = _activeLives;
    final showingLive = active.isNotEmpty;
    final lives = showingLive ? active : _recordingLives;

    if (lives.isEmpty && !_livesLoadingMore) {
      return const _EmptyBlock(
        message: 'Ainda sem diretos activos nem gravações disponíveis.',
        icon: Icons.videocam_off_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          showingLive ? 'Em directo' : 'Gravações',
          style: GoogleFonts.inter(
            color: FleaberColors.muted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _liveCardWrap([
          for (final live in lives)
            _discoveryLiveCard(
              context,
              profile: profile,
              live: live,
              isLiveNow: showingLive,
            ),
        ]),
        if (_livesHasMore) ...[
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: _livesLoadingMore ? null : _loadMoreLives,
              child: _livesLoadingMore
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Ver mais',
                      style: GoogleFonts.inter(
                        color: FleaberColors.teal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _marketplacePane(BuildContext context) {
    if (_products.isEmpty && !_productsLoadingMore) {
      return const _EmptyBlock(
        message: 'Esta seller ainda não tem artigos no marketplace.',
        icon: Icons.storefront_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _productCardWrap([
          for (final p in _products) _productCard(context, p),
        ]),
        if (_productsHasMore) ...[
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: _productsLoadingMore ? null : _loadMoreProducts,
              child: _productsLoadingMore
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Ver mais artigos',
                      style: GoogleFonts.inter(
                        color: FleaberColors.teal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _opinioesPane(BuildContext context) {
    if (_reviewsLoading && !_reviewsBooted) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: FleaberColors.teal)),
      );
    }

    final empty = _reviewStats.count == 0 && _reviews.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_usingDemoReviews) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6E5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8C57A)),
            ),
            child: Text(
              HubDemoReviews.bannerLabel,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: const Color(0xFF8A5A00),
                fontSize: FleaHubSiteLayout.typeCaption,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
        // Desktop: resumo na coluna esquerda. Mobile: resumo só se houver dados.
        if (!empty && !_isDesktop(context)) ...[
          HubProfileLightReviewsSummary(stats: _reviewStats, compact: true),
          const SizedBox(height: 12),
        ],
        if (!empty) ...[
          HubProfileLightReviewsToolbar(
            starsFilter: _starsFilter,
            onStarsFilter: (v) {
              setState(() {
                _starsFilter = v;
                _reviewSort = 'newest';
              });
              unawaited(_reloadReviews());
            },
          ),
          const SizedBox(height: 8),
        ],
        if (empty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 36, 16, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: const _EmptyBlock(
                  message: 'Ainda sem avaliações públicas.',
                  icon: Icons.star_outline,
                ),
              ),
            ),
          )
        else if (_reviews.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Text(
              'Nenhuma avaliação com este filtro.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: FleaberColors.muted),
            ),
          )
        else
          for (var i = 0; i < _reviews.length; i++)
            HubProfileLightReviewTile(
              review: _reviews[i],
              showDivider: i < _reviews.length - 1,
            ),
        if (_reviewsHasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: TextButton(
                onPressed: _reviewsLoadingMore ? null : _loadMoreReviews,
                child: _reviewsLoadingMore
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        'Ver mais avaliações',
                        style: GoogleFonts.inter(
                          color: FleaberColors.teal,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// Diretos — grelha 9:16 aprovada (até 6 cols no desktop).
  Widget _liveCardWrap(List<Widget> cards) {
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

        // Preferir até 6 no desktop largo; reduzir progressivamente.
        final preferred = maxW >= 1400
            ? 6
            : (maxW >= 1100 ? 5 : (maxW >= 800 ? 4 : 3));
        final maxColsFit = ((maxW + gap) / (minW + gap)).floor().clamp(2, 6);
        var cols = preferred.clamp(2, maxColsFit);
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

  /// Marketplace — colunas progressivas (não forçar 6 em ecrãs pequenos).
  Widget _productCardWrap(List<Widget> cards) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final gap = maxW < 520 ? 10.0 : 12.0;
        final minW = 128.0;
        final maxCols = maxW >= 1400
            ? 6
            : (maxW >= 1000
                ? 5
                : (maxW >= 780
                    ? 4
                    : (maxW >= 560 ? 3 : 2)));
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
    required HubProfile profile,
    required HubLive live,
    required bool isLiveNow,
  }) {
    final handle = widget.handle.trim().isNotEmpty
        ? widget.handle.trim()
        : live.sellerHandle.trim();
    final name = profile.fullName.trim().isNotEmpty
        ? profile.fullName.trim()
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
      if (!isLiveNow && preparing) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Gravação ainda a preparar — ainda não há vídeo para ver.',
            ),
          ),
        );
        return;
      }
      context.push(HubRoutePaths.liveFor(handle, liveId: live.id));
    }

    final title = live.title?.trim();
    final ratingLabel = _reviewStats.count > 0
        ? _reviewStats.average.toStringAsFixed(1)
        : '—';

    return HomeMuxLiveCard(
      sellerName: name,
      liveTitle: (title != null && title.isNotEmpty) ? title : null,
      thumbnailUrl: thumbUrl,
      fallbackAvatarUrl: live.sellerPhotoUrl ?? profile.photoUrl,
      ratingLabel: ratingLabel,
      coverId: coverId,
      isLive: isLiveNow,
      isRecordingPreparing: preparing,
      onOpenLive: handle.isEmpty ? () {} : open,
      onOpenSellerProfile: null,
      onOpenSellerOpinions: () => _setTab(_ProfileTab.opinioes),
    );
  }

  Widget _productCard(BuildContext context, HubProduct product) {
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
}

// ─── Painel identidade (coluna esquerda / cabeçalho mobile) ───

class _IdentityPanel extends StatelessWidget {
  const _IdentityPanel({
    required this.profile,
    required this.handle,
    required this.reviewStats,
    required this.isFollowing,
    required this.onFollow,
    required this.onShare,
    required this.onOpenOpinions,
    required this.desktop,
  });

  final HubProfile profile;
  final String handle;
  final HubReviewsStatsResult reviewStats;
  final bool isFollowing;
  final VoidCallback onFollow;
  final VoidCallback onShare;
  final VoidCallback onOpenOpinions;
  final bool desktop;

  void _openAbout(BuildContext context) {
    final bio = profile.hubBio?.trim() ?? '';
    if (bio.isEmpty) return;
    final name = profile.fullName.trim().isEmpty
        ? profile.handle
        : profile.fullName.trim();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FleaberColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: FleaberColors.alternate,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Sobre $name',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: FleaHubSiteLayout.typeSection,
                    color: FleaberColors.text,
                  ),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(ctx).height * 0.55,
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      bio,
                      style: GoogleFonts.inter(
                        color: FleaberColors.text,
                        fontSize: FleaHubSiteLayout.typeBody,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Fechar',
                    style: GoogleFonts.inter(
                      color: FleaberColors.teal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = profile.fullName.trim().isEmpty
        ? profile.handle
        : profile.fullName.trim();
    final loc = profile.location?.trim();
    final hasOpinions = reviewStats.count > 0;
    final bio = profile.hubBio?.trim();
    final hasBio = bio != null && bio.isNotEmpty;

    final rating = InkWell(
      onTap: onOpenOpinions,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: hasOpinions
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RatingBarIndicator(
                    rating: reviewStats.average,
                    itemSize: 14,
                    unratedColor: FleaberColors.alternate,
                    itemBuilder: (_, __) => const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFF9CF58),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    reviewStats.average.toStringAsFixed(1),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: FleaHubSiteLayout.typeMeta,
                      color: FleaberColors.text,
                    ),
                  ),
                  Text(
                    ' (${reviewStats.count})',
                    style: GoogleFonts.inter(
                      color: FleaberColors.muted,
                      fontSize: FleaHubSiteLayout.typeCaption,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_outline_rounded,
                      size: 16, color: FleaberColors.muted),
                  const SizedBox(width: 4),
                  Text(
                    'Sem opiniões',
                    style: GoogleFonts.inter(
                      color: FleaberColors.muted,
                      fontSize: FleaHubSiteLayout.typeMeta,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );

    final nameStyle = GoogleFonts.inter(
      fontSize: desktop
          ? FleaHubSiteLayout.typeDisplay
          : FleaHubSiteLayout.typeNavTitle,
      fontWeight: FontWeight.w900,
      color: FleaberColors.text,
      height: 1.15,
    );
    final handleStyle = GoogleFonts.inter(
      color: FleaberColors.teal,
      fontWeight: FontWeight.w700,
      fontSize: FleaHubSiteLayout.typeSecondary,
    );

    final aboutLink = hasBio
        ? Align(
            alignment: desktop ? Alignment.center : Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _openAbout(context),
              style: TextButton.styleFrom(
                foregroundColor: FleaberColors.teal,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Sobre / Ver mais',
                style: GoogleFonts.inter(
                  fontSize: FleaHubSiteLayout.typeSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
        : null;

    final shareBtn = OutlinedButton(
      onPressed: onShare,
      style: OutlinedButton.styleFrom(
        foregroundColor: FleaberColors.teal,
        side: const BorderSide(color: FleaberColors.teal, width: 1.5),
        minimumSize: Size(0, desktop ? 40 : 40),
        padding: EdgeInsets.symmetric(horizontal: desktop ? 16 : 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Text(
        'Partilhar',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: desktop
              ? FleaHubSiteLayout.typeNav
              : FleaHubSiteLayout.typeBody,
        ),
      ),
    );

    final moreMenu = PopupMenuButton<String>(
      tooltip: 'Mais opções',
      onSelected: (v) {
        if (v == 'install') HubActions.openInstallApp();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'install',
          child: Row(
            children: [
              const Icon(Icons.download_outlined, size: 18),
              const SizedBox(width: 10),
              Text(
                'Instalar Fleaber',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        height: desktop ? 40 : 36,
        width: desktop ? 40 : 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: FleaberColors.alternate),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.more_horiz, size: 20, color: FleaberColors.text),
      ),
    );

    return Container(
      padding: EdgeInsets.all(desktop ? 18 : 10),
      decoration: BoxDecoration(
        color: FleaberColors.surface,
        borderRadius: BorderRadius.circular(FleaberRadius.md),
        border: Border.all(color: FleaberColors.alternate),
        boxShadow: const [FleaberElevation.sm],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (desktop) ...[
            Center(
              child: FleaberProfileAvatar(
                userId: profile.id,
                photoUrl: profile.photoUrl,
                fullName: name,
                radius: 48,
                borderColor: FleaberColors.teal.withValues(alpha: 0.35),
                borderWidth: 2,
              ),
            ),
            const SizedBox(height: 14),
            Text(name, textAlign: TextAlign.center, style: nameStyle),
            const SizedBox(height: 2),
            Text(
              '@${profile.handle}',
              textAlign: TextAlign.center,
              style: handleStyle,
            ),
            const SizedBox(height: 10),
            Center(child: rating),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FleaberProfileAvatar(
                  userId: profile.id,
                  photoUrl: profile.photoUrl,
                  fullName: name,
                  radius: 26,
                  borderColor: FleaberColors.teal.withValues(alpha: 0.35),
                  borderWidth: 2,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: nameStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text('@${profile.handle}', style: handleStyle),
                      const SizedBox(height: 2),
                      rating,
                    ],
                  ),
                ),
                moreMenu,
              ],
            ),
          ],
          SizedBox(height: desktop ? 8 : 6),
          Wrap(
            spacing: 10,
            runSpacing: 2,
            alignment: desktop ? WrapAlignment.center : WrapAlignment.start,
            children: [
              if (loc != null && loc.isNotEmpty)
                _meta(Icons.location_on_outlined, loc),
              _meta(
                Icons.people_outline,
                profile.followerCount == 0
                    ? 'Sem seguidores'
                    : '${_fmtCount(profile.followerCount)} seguidores',
              ),
            ],
          ),
          if (profile.vacationMode) ...[
            const SizedBox(height: 6),
            Text(
              SellerVacationMode.vacationBannerMessage,
              textAlign: desktop ? TextAlign.center : TextAlign.start,
              style: GoogleFonts.inter(
                color: const Color(0xFFB78103),
                fontSize: FleaHubSiteLayout.typeCaption,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (desktop && hasOpinions) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: FleaberColors.alternate),
            const SizedBox(height: 12),
            Text(
              'Opiniões',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: FleaHubSiteLayout.typeSection,
                color: FleaberColors.text,
              ),
            ),
            const SizedBox(height: 8),
            HubProfileLightReviewsSummary(
              stats: reviewStats,
              compact: true,
            ),
            TextButton(
              onPressed: onOpenOpinions,
              child: Text(
                'Ver todas',
                style: GoogleFonts.inter(
                  color: FleaberColors.teal,
                  fontWeight: FontWeight.w700,
                  fontSize: FleaHubSiteLayout.typeBody,
                ),
              ),
            ),
          ],
          if (aboutLink != null) ...[
            SizedBox(height: desktop ? 8 : 4),
            aboutLink,
          ],
          SizedBox(height: desktop ? 12 : 8),
          if (desktop) ...[
            FleaberPrimaryButton(
              label: isFollowing ? 'A seguir' : 'Seguir',
              height: 44,
              borderRadius: 14,
              fontSize: FleaHubSiteLayout.typeNav,
              onPressed: onFollow,
            ),
            const SizedBox(height: 8),
            shareBtn,
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => HubActions.openInstallApp(),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(
                'Instalar Fleaber',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: FleaHubSiteLayout.typeNav,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: FleaberColors.text,
                side: const BorderSide(color: FleaberColors.alternate),
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ] else ...[
            // Seguir ~60% · Partilhar ~40% · mesma altura
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: FleaberPrimaryButton(
                    label: isFollowing ? 'A seguir' : 'Seguir',
                    height: 40,
                    borderRadius: 14,
                    fontSize: FleaHubSiteLayout.typeBody,
                    onPressed: onFollow,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: shareBtn,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => HubActions.openInstallApp(),
                icon: const Icon(Icons.download_outlined, size: 16),
                label: Text(
                  'Instalar Fleaber',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: FleaHubSiteLayout.typeCaption,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: FleaberColors.muted,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: FleaberColors.muted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: GoogleFonts.inter(
              color: FleaberColors.muted,
              fontSize: FleaHubSiteLayout.typeMeta,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  static String _fmtCount(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)} mil';
    return '$n';
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, color: FleaberColors.muted, size: 36),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: FleaberColors.muted,
              fontSize: FleaHubSiteLayout.typeBody,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}

/// Tabs sticky no mobile — fundo sólido para não misturar com o scroll.
class _StickyTabsDelegate extends SliverPersistentHeaderDelegate {
  _StickyTabsDelegate({required this.child});

  final Widget child;

  static const double _h = 60;

  @override
  double get minExtent => _h;

  @override
  double get maxExtent => _h;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: FleaberColors.bgTint,
      elevation: overlapsContent ? 1.5 : 0,
      shadowColor: Colors.black26,
      child: SizedBox(height: _h, child: Align(child: child)),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyTabsDelegate oldDelegate) =>
      oldDelegate.child != child;
}
