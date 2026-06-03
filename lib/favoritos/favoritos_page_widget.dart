import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/favorites_util.dart';
import '/widgets/fleaber_primary_button.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/home_page/home_page_widget.dart';
import '/product_details/product_details_page_widget.dart';
import '/marketplace_feed_refresh.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_typography.dart';
import '/utils/fleaber_grid_spacing.dart';
import '/widgets/marketplace_product_card.dart';

/// Artigos de outros vendedores guardados nos favoritos (estilo Vinted).
class FavoritosPageWidget extends StatefulWidget {
  const FavoritosPageWidget({super.key});

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

    final products = await ProductsTable().queryRows(
      queryFn: (q) => q
          .inFilter('id', ids)
          .eqOrNull('list_on_marketplace', true)
          .eqOrNull('is_sold', false),
      limit: 200,
    );
    products.sort((a, b) {
      final ai = ids.indexOf(a.id ?? '');
      final bi = ids.indexOf(b.id ?? '');
      return ai.compareTo(bi);
    });
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
      body: FutureBuilder<List<ProductsRow>>(
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
                      onPressed: () =>
                          context.pushNamed(HomePageWidget.routeName),
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
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: kFleaberTwoColumnGridGap,
                      crossAxisSpacing: kFleaberTwoColumnGridGap,
                      childAspectRatio: MarketplaceProductCard.gridChildAspectRatio,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final product = products[index];
                        final id = product.id ?? '';
                        final count =
                            _favoriteCountsOverride[id] ?? product.favoritesCount;
                        return MarketplaceProductCard(
                          imageUrl: _firstImage(product),
                          title: product.title ?? 'Artigo',
                          stateLabel: product.state ?? '',
                          priceLabel: _formatPrice(product),
                          favoritesCount: count,
                          isFavorited: _favoriteProductIds.contains(id),
                          onTap: () {
                            if (id.isEmpty) return;
                            context.push(
                              ProductDetailsPageWidget.routePath,
                              extra: ProductDetailsPageWidget.routeExtraForProduct(
                                product,
                              ),
                            );
                          },
                          onFavoriteTap: () => _toggleFavorite(product),
                        );
                      },
                      childCount: products.length,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
