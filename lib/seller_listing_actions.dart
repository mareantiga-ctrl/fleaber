import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/marketplace_feed_refresh.dart';
import '/order_cancel_eligibility.dart';

Future<bool> sellerProductHasBlockingOrders(String productId) async {
  if (productId.isEmpty) return false;
  final orders = await OrdersTable().queryRows(
    queryFn: (q) => q.eqOrNull('product_id', productId),
    limit: 80,
  );
  for (final o in orders) {
    if (orderIsCancelled(o.status)) continue;
    if (orderStatusBlocksNewPurchase(o.status)) return true;
  }
  return false;
}

Future<ProductsRow> _loadOwnProduct(String productId) async {
  if (currentUserUid.isEmpty) {
    throw Exception('Inicia sessão para gerir este anúncio.');
  }
  final rows = await ProductsTable().querySingleRow(
    queryFn: (q) => q.eqOrNull('id', productId),
  );
  if (rows.isEmpty) throw Exception('Artigo não encontrado.');
  final product = rows.first;
  if (product.sellerId != currentUserUid) {
    throw Exception('Sem permissão para gerir este anúncio.');
  }
  return product;
}

/// Ocultar ou republicar no marketplace (não elimina o inventário).
Future<ProductsRow> setSellerListingMarketplaceVisible({
  required String productId,
  required bool visible,
}) async {
  final product = await _loadOwnProduct(productId);
  if (product.isSold) {
    throw Exception('Artigo já vendido — não pode voltar ao marketplace.');
  }
  await ProductsTable().update(
    data: {'list_on_marketplace': visible},
    matchingRows: (rows) => rows.eqOrNull('id', productId),
  );
  requestMarketplaceFeedRefresh();
  final refreshed = await ProductsTable().querySingleRow(
    queryFn: (q) => q.eqOrNull('id', productId),
  );
  return refreshed.isNotEmpty ? refreshed.first : product;
}

/// Elimina o anúncio se não houver encomendas activas.
///
/// Retira sempre do marketplace primeiro (update fiável por RLS de dono), só
/// depois tenta o hard-delete. Assim o artigo desaparece do feed mesmo que a
/// política de DELETE do Supabase bloqueie a remoção física.
Future<void> deleteSellerListing(String productId) async {
  final product = await _loadOwnProduct(productId);
  if (product.isSold) {
    throw Exception('Artigo vendido — não pode ser eliminado.');
  }
  if (await sellerProductHasBlockingOrders(productId)) {
    throw Exception(
      'Este artigo tem encomendas activas. Oculta-o do marketplace em vez de eliminar.',
    );
  }

  await ProductsTable().update(
    data: {'list_on_marketplace': false},
    matchingRows: (rows) => rows.eqOrNull('id', productId),
  );

  await ProductsTable().delete(
    matchingRows: (rows) => rows.eqOrNull('id', productId),
  );

  requestMarketplaceFeedRefresh();

  final still = await ProductsTable().querySingleRow(
    queryFn: (q) => q.eqOrNull('id', productId),
  );
  if (still.isNotEmpty && (still.first.listOnMarketplace ?? false)) {
    throw Exception('Não foi possível eliminar o anúncio. Tenta novamente.');
  }
}
