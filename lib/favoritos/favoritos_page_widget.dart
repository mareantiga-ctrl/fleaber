import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/favorites_util.dart';
import '/widgets/fleaber_primary_button.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/hub/hub_navigation.dart';
import '/hub/routing/hub_route_paths.dart';
import '/product_details/product_details_page_widget.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '/marketplace_feed_refresh.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_commercial_display.dart';
import '/utils/fleaber_typography.dart';
import '/utils/fleaber_grid_spacing.dart';
import '/utils/seller_professional.dart';
import '/widgets/marketplace_product_card.dart';

/// Artigos de outros vendedores guardados nos favoritos (estilo Vinted).
class FavoritosPageWidget extends StatefulWidget {
  const FavoritosPageWidget({super.key, this.embedded = false});

  /// H11 desktop shell: sem AppBar duplicada.
  final bool embedded;

  static const String routeName = 'Favoritos';
  static const String routePath = '/favoritos';

  @override
  State<FavoritosPageWidget> createState() => _FavoritosPageWidgetState();
}

class _FavoritosPageWidgetState extends State<FavoritosPageWidget> {
  static const Color _kTeal = Color(0xFF007782);
  static const Color _kBg = FleaberColors.bgTint;
  static const Color _kText = Color(0xFF101518);
  static const Color _kMuted = Color(0xFF57636C);

  late Future<List<ProductsRow>> _productsFuture;
  final Set<String> _favoriteProductIds = <String>{};
  final Map<String, int> _favoriteCountsOverride = <String, int>{};
  final Set<String> _togglingFavorites = <String>{};

  @override
  void initState() {
    super.initState();
    _reload();
    homeFavoritesUiRefreshTick.addListener(_onFavoritesTick);
  }

  @override
  void dispose() {
    homeFavoritesUiRefreshTick.removeListener(_onFavoritesTick);
    super.dispose();
  }

  void _onFavoritesTick() {
    if (!mounted) return;
    _reload();
  }

  void _reload() {
    setState(() {
      _productsFuture = _loadFavoriteProducts();
    });
  }

  Future<List<ProductsRow>> _loadFavoriteProducts() async {
    for (var i = 0; i < 25 && currentUserUid.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (currentUserUid.isEmpty) return [];

    final favRows = await FavoritesTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('user_id', currentUserUid)
          .order('created_at', ascending: false),
      limit: 200,
    );
    final ids = favRows
        .map((e) => e.productId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    if (!mounted) return [];
    setState(() {
      _favoriteProductIds
        ..clear()
        ..addAll(ids);
    });
    if (ids.isEmpty) return [];

    // Mostra todos os favoritos legíveis (não exige marketplace activo —
    // senão artigos privados / RLS de outros vendedores esvaziam a grelha).
    final products = await ProductsTable().queryRows(
      queryFn: (q) => q.inFilter('id', ids),
      limit: 200,
    );
    products.sort((a, b) {
      final ai = ids.indexOf(a.id ?? '');
      final bi = ids.indexOf(b.id ?? '');
      return ai.compareTo(bi);
    });
    await SellerProfessionalCache.warm(
      products.map((p) => p.sellerId ?? '').where((id) => id.isNotEmpty),
    );
    return products;
  }

  String? _firstImage(ProductsRow row) {
    final urls = row.imageUrls;
    if (urls.isEmpty) return null;
    return urls.first;
  }

  String _formatPrice(ProductsRow row) {
    final p = row.price;
    if (p == null) return '—';
    return '${p.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  Future<void> _toggleFavorite(ProductsRow product) async {
    if (currentUserUid.isEmpty) return;
    final productId = product.id;
    if (productId == null || productId.isEmpty) return;
    if (_togglingFavorites.contains(productId)) return;

    setState(() => _togglingFavorites.add(productId));
    try {
      final result = await toggleProductFavorite(
        userId: currentUserUid,
        product: product,
      );
      if (!mounted) return;
      if (result.didFail) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível atualizar favorito.')),
        );
        return;
      }
      setState(() {
        if (result.isFavorited) {
          _favoriteProductIds.add(productId);
          _favoriteCountsOverride[productId] = result.favoritesCount;
        } else {
          _favoriteProductIds.remove(productId);
          _favoriteCountsOverride.remove(productId);
        }
      });
      requestHomeFavoritesUiReload();
      if (!result.isFavorited) {
        _reload();
      }
    } finally {
      if (mounted) {
        setState(() => _togglingFavorites.remove(productId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<ProductsRow>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _kTeal),
            );
          }
          final products = snapshot.data ?? [];
          if (products.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.favorite_border_rounded,
                      size: 56,
                      color: _kMuted.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Ainda não guardaste favoritos',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: _kText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Toca no coração nos artigos do Marketplace para os veres aqui.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: _kMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FleaberPrimaryButton(
                      label: 'Explorar Marketplace',
                      fontWeight: FontWeight.w600,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      onPressed: () {
                        if (kIsWeb) {
                          context.go(
                            HubRoutePaths.landingExploreTab('marketplace'),
                          );
                          return;
                        }
                        HubNavigation.goAppHome(context, replace: false);
                      },
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: _kTeal,
            onRefresh: () async => _reload(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text(
                      '${products.length} artigo${products.length == 1 ? '' : 's'} guardado${products.length == 1 ? '' : 's'}',
                      style: FleaberTypography.cardMeta(
                        color: _kMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final cols = widget.embedded
                        ? ((constraints.crossAxisExtent +
                                    kFleaberTwoColumnGridGap) /
                                (200 + kFleaberTwoColumnGridGap))
                            .floor()
                            .clamp(2, 6)
                        : 2;
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: kFleaberTwoColumnGridGap,
                          crossAxisSpacing: kFleaberTwoColumnGridGap,
                          childAspectRatio:
                              MarketplaceProductCard.gridChildAspectRatio,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final product = products[index];
                            final id = product.id ?? '';
                            final count = _favoriteCountsOverride[id] ??
                                product.favoritesCount;
                            final sellerId = product.sellerId ?? '';
                            final pro =
                                SellerProfessionalCache.peek(sellerId);
                            return MarketplaceProductCard(
                              imageUrl: _firstImage(product),
                              title: fleaberCommercialTitle(product.title),
                              stateLabel: product.state ?? '',
                              priceLabel: _formatPrice(product),
                              favoritesCount: count,
                              isFavorited:
                                  _favoriteProductIds.contains(id),
                              showProfessionalBadge:
                                  pro?.showProfessionalBadge == true,
                              professionalVerified:
                                  pro?.professionalVerified == true,
                              onTap: () {
                                if (id.isEmpty) return;
                                context.push(
                                  ProductDetailsPageWidget.routePath,
                                  extra: ProductDetailsPageWidget
                                      .routeExtraForProduct(product),
                                );
                              },
                              onFavoriteTap: () =>
                                  _toggleFavorite(product),
                            );
                          },
                          childCount: products.length,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      );
    if (widget.embedded) {
      return ColoredBox(color: _kBg, child: body);
    }
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _kBg,
        foregroundColor: _kText,
        title: Text(
          'Favoritos',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: _kText,
            fontSize: 18,
          ),
        ),
      ),
      body: body,
    );
  }
}
