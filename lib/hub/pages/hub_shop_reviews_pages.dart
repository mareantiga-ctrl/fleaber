import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/hub_models.dart';
import '../data/hub_public_repository.dart';
import '../hub_navigation.dart';
import '../routing/hub_route_paths.dart';
import '../seo/hub_seo_meta.dart';
import '../seo/hub_seo_policy.dart';
import '../theme/hub_theme.dart';
import '../widgets/hub_content_widgets.dart';
import '../widgets/hub_reviews_layout.dart';
import '../widgets/hub_seo_scope.dart';
import '../widgets/hub_shared_widgets.dart';
import 'hub_loading_page.dart';

/// Tab marketplace — `/{handle}/shop` (Fase 1.1).
class HubShopPage extends StatelessWidget {
  const HubShopPage({
    super.key,
    required this.handle,
    required this.profileId,
  });

  final String handle;
  final String profileId;

  @override
  Widget build(BuildContext context) {
    return _HubFocusedListPage(
      handle: handle,
      profileId: profileId,
      title: 'Marketplace',
      contentMaxWidthFor: HubTheme.shopContentMaxWidthFor,
      loader: (repo) => repo.fetchProductsForSeller(profileId, limit: 48),
      builder: (context, products) {
        if (products.isEmpty) {
          return const HubEmptyState(
            message: 'Esta seller ainda não tem artigos no marketplace.',
            icon: Icons.storefront_outlined,
          );
        }
        final cols = HubTheme.shopGridCrossAxisCount(context);
        return GridView.builder(
          padding: const EdgeInsets.all(HubTheme.shopGridPadding),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: HubTheme.shopGridGap,
            crossAxisSpacing: HubTheme.shopGridGap,
            childAspectRatio: HubTheme.shopGridChildAspectRatio,
          ),
          itemCount: products.length,
          itemBuilder: (context, i) => HubProductTile(
            product: products[i],
            onTap: () => context.push(
              '/productDetails?product_id=${products[i].id}',
            ),
          ),
        );
      },
    );
  }
}

/// Tab avaliações — `/{handle}/reviews` (Página 05 · layout B + paginação).
class HubReviewsPage extends StatefulWidget {
  const HubReviewsPage({
    super.key,
    required this.handle,
    required this.profileId,
  });

  final String handle;
  final String profileId;

  @override
  State<HubReviewsPage> createState() => _HubReviewsPageState();
}

class _HubReviewsPageState extends State<HubReviewsPage> {
  final _repo = HubPublicRepository();
  HubProfile? _profile;
  HubReviewsStatsResult _stats = const HubReviewsStatsResult.empty();
  final List<HubReview> _reviews = [];
  final Set<String> _seenIds = {};
  bool _bootLoading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _error;
  int? _starsFilter;
  String _sort = 'newest';
  int _listGen = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _bootLoading = true;
      _error = null;
    });
    try {
      final profile = await _repo.fetchProfileById(widget.profileId);
      final stats = await _repo.fetchReviewsStatsForSeller(widget.profileId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _stats = stats;
      });
      await _reloadList();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _bootLoading = false);
    }
  }

  Future<void> _reloadList() async {
    final gen = ++_listGen;
    setState(() {
      _reviews.clear();
      _seenIds.clear();
      _hasMore = false;
      _loadingMore = true;
      _error = null;
    });
    try {
      final page = await _repo.fetchReviewsPageForSeller(
        widget.profileId,
        limit: 10,
        starsFilter: _starsFilter,
        sort: _sort,
      );
      if (!mounted || gen != _listGen) return;
      _appendPage(page);
    } catch (e) {
      if (!mounted || gen != _listGen) return;
      setState(() => _error = e);
    } finally {
      if (mounted && gen == _listGen) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _reviews.isEmpty) return;
    final gen = _listGen;
    setState(() => _loadingMore = true);
    try {
      final last = _reviews.last;
      final page = await _repo.fetchReviewsPageForSeller(
        widget.profileId,
        limit: 10,
        starsFilter: _starsFilter,
        sort: _sort,
        cursorCreatedAt: last.createdAt,
        cursorId: last.id,
        cursorStars: last.stars,
      );
      if (!mounted || gen != _listGen) return;
      _appendPage(page);
    } catch (e) {
      if (!mounted || gen != _listGen) return;
      setState(() => _error = e);
    } finally {
      if (mounted && gen == _listGen) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _appendPage(HubReviewsPageResult page) {
    var added = 0;
    for (final r in page.items) {
      if (r.id.isEmpty || _seenIds.contains(r.id)) continue;
      _seenIds.add(r.id);
      _reviews.add(r);
      added++;
    }
    setState(() {
      // Se o servidor repetiu tudo, não fingir que há mais.
      _hasMore = page.hasMore && added > 0;
      if (page.items.isEmpty) _hasMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bootLoading) return const HubLoadingPage();

    final seoMeta = _profile != null
        ? HubSeoMeta.forSection(
            section: HubSection.reviews,
            profile: _profile!,
            indexable: HubSeoPolicy.allowHubIndexing(),
          )
        : HubSeoMeta.notFound();

    if (_error != null && _reviews.isEmpty) {
      return HubPageShell(
        child: Scaffold(
          backgroundColor: HubTheme.bg,
          appBar: hubConditionalAppBar(
            context,
            title: '@${widget.handle} · Avaliações',
          ),
          body: HubSeoScope(
            meta: seoMeta,
            child: HubErrorState(onRetry: _bootstrap),
          ),
        ),
      );
    }

    return HubPageShell(
      child: Scaffold(
        backgroundColor: HubTheme.bg,
        appBar: hubConditionalAppBar(
          context,
          title: '@${widget.handle} · Avaliações',
        ),
        body: HubSeoScope(
          meta: seoMeta,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: HubTheme.reviewsContentMaxWidthFor(context),
              ),
              child: SizedBox(
                width: double.infinity,
                child: RefreshIndicator(
                  color: const Color(0xFF00A3AD),
                  onRefresh: _bootstrap,
                  child: HubReviewsPageBody(
                    stats: _stats,
                    reviews: List.unmodifiable(_reviews),
                    hasMore: _hasMore,
                    loadingMore: _loadingMore,
                    starsFilter: _starsFilter,
                    sort: _sort,
                    onStarsFilter: (v) {
                      setState(() => _starsFilter = v);
                      _reloadList();
                    },
                    onSort: (v) {
                      setState(() => _sort = v);
                      _reloadList();
                    },
                    onLoadMore: _loadMore,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HubFocusedListPage<T> extends StatefulWidget {
  const _HubFocusedListPage({
    required this.handle,
    required this.profileId,
    required this.title,
    required this.loader,
    required this.builder,
    this.contentMaxWidthFor = HubTheme.contentMaxWidthFor,
  });

  final String handle;
  final String profileId;
  final String title;
  final Future<List<T>> Function(HubPublicRepository repo) loader;
  final Widget Function(BuildContext context, List<T> items) builder;
  /// Reviews mantém [HubTheme.contentMaxWidthFor]; shop usa largura desktop.
  final double Function(BuildContext context) contentMaxWidthFor;

  @override
  State<_HubFocusedListPage<T>> createState() => _HubFocusedListPageState<T>();
}

class _HubFocusedListPageState<T> extends State<_HubFocusedListPage<T>> {
  final _repo = HubPublicRepository();
  late Future<({HubProfile? profile, List<T> items})> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<({HubProfile? profile, List<T> items})> _load() async {
    final profile = await _repo.fetchProfileById(widget.profileId);
    final items = await widget.loader(_repo);
    return (profile: profile, items: items);
  }

  HubSection get _section => widget.title == 'Marketplace'
      ? HubSection.shop
      : HubSection.reviews;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({HubProfile? profile, List<T> items})>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          // HubLoadingPage → HubLoadingShell → HubPageShell (chrome 1×).
          return const HubLoadingPage();
        }
        if (snap.hasError) {
          return HubPageShell(
            child: Scaffold(
              backgroundColor: HubTheme.bg,
              appBar: _appBar(context),
              body: HubSeoScope(
                meta: HubSeoMeta.notFound(),
                child: HubErrorState(
                  onRetry: () => setState(() => _future = _load()),
                ),
              ),
            ),
          );
        }
        final data = snap.data;
        final profile = data?.profile;
        final items = data?.items ?? [];
        final seoMeta = profile != null
            ? HubSeoMeta.forSection(
                section: _section,
                profile: profile,
                indexable: HubSeoPolicy.allowHubIndexing(),
              )
            : HubSeoMeta.notFound();

        return HubPageShell(
          child: Scaffold(
            backgroundColor: HubTheme.bg,
            appBar: _appBar(context),
            body: HubSeoScope(
              meta: seoMeta,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: widget.contentMaxWidthFor(context),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: RefreshIndicator(
                      color: const Color(0xFF00A3AD),
                      onRefresh: () async {
                        setState(() => _future = _load());
                        await _future;
                      },
                      child: widget.builder(context, items),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    return hubConditionalAppBar(
      context,
      title: '@${widget.handle} · ${widget.title}',
    );
  }
}
