import '/backend/supabase/supabase.dart';
import 'package:flutter/foundation.dart';

class FavoriteToggleResult {
  const FavoriteToggleResult({
    required this.isFavorited,
    required this.favoritesCount,
    this.didFail = false,
  });

  final bool isFavorited;
  final int favoritesCount;
  final bool didFail;
}

final ValueNotifier<int> favoritesUiRefreshTick = ValueNotifier<int>(0);
final Map<String, int> _favoriteCountUiByProductId = <String, int>{};

int? favoriteCountUiOverrideForProduct(String? productId) {
  final id = _normalizeUuidString(productId);
  if (id.isEmpty) return null;
  return _favoriteCountUiByProductId[id];
}

void setFavoriteCountUiOverrideForProduct(String? productId, int count) {
  final id = _normalizeUuidString(productId);
  if (id.isEmpty) return;
  final safe = count < 0 ? 0 : count;
  final prev = _favoriteCountUiByProductId[id];
  if (prev == safe) return;
  _favoriteCountUiByProductId[id] = safe;
  favoritesUiRefreshTick.value++;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);

String _normalizeUuidString(String? value) {
  return (value ?? '').trim();
}

Future<bool> isProductFavoritedByUser({
  required String userId,
  required String productId,
}) async {
  final rows = await FavoritesTable().queryRows(
    queryFn: (q) => q
        .eqOrNull('user_id', userId)
        .eqOrNull('product_id', productId)
        .limit(1),
  );
  return rows.isNotEmpty;
}

Future<FavoriteToggleResult> toggleProductFavorite({
  required String userId,
  required ProductsRow product,
}) async {
  final productId = _normalizeUuidString(product.id);
  if (productId.isEmpty) {
    return FavoriteToggleResult(
      isFavorited: false,
      favoritesCount: product.favoritesCount,
      didFail: true,
    );
  }
  if (!_uuidPattern.hasMatch(productId)) {
    print('ERRO FATAL FAVORITOS: product_id inválido "$productId"');
    return FavoriteToggleResult(
      isFavorited: false,
      favoritesCount: product.favoritesCount,
      didFail: true,
    );
  }
  final normalizedUserId = _normalizeUuidString(userId);
  if (!_uuidPattern.hasMatch(normalizedUserId)) {
    print('ERRO FATAL FAVORITOS: user_id inválido "$normalizedUserId"');
    return FavoriteToggleResult(
      isFavorited: false,
      favoritesCount: product.favoritesCount,
      didFail: true,
    );
  }

  final sellerId = _normalizeUuidString(product.sellerId);
  if (sellerId.isNotEmpty && sellerId == normalizedUserId) {
    return FavoriteToggleResult(
      isFavorited: false,
      favoritesCount: product.favoritesCount,
      didFail: true,
    );
  }

  try {
    final existingRows = await FavoritesTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('user_id', normalizedUserId)
          .eqOrNull('product_id', productId)
          .limit(1),
    );
    final currentlyFavorited = existingRows.isNotEmpty;

    if (currentlyFavorited) {
      await FavoritesTable().delete(
        matchingRows: (rows) => rows
            .eqOrNull('user_id', normalizedUserId)
            .eqOrNull('product_id', productId),
      );
      final nextCount = await _syncFavoritesCountForProduct(productId);
      product.favoritesCount = nextCount;
      setFavoriteCountUiOverrideForProduct(productId, nextCount);
      return FavoriteToggleResult(
        isFavorited: false,
        favoritesCount: nextCount,
      );
    }

    await FavoritesTable().insert({
      'user_id': normalizedUserId,
      'product_id': productId,
    });
    final nextCount = await _syncFavoritesCountForProduct(productId);
    product.favoritesCount = nextCount;
    setFavoriteCountUiOverrideForProduct(productId, nextCount);
    return FavoriteToggleResult(
      isFavorited: true,
      favoritesCount: nextCount,
    );
  } catch (e) {
    print('ERRO FATAL FAVORITOS: $e');
    return FavoriteToggleResult(
      isFavorited: product.favoritesCount > 0,
      favoritesCount: product.favoritesCount,
      didFail: true,
    );
  }
}

Future<int> _syncFavoritesCountForProduct(String productId) async {
  final favoriteRows = await FavoritesTable().queryRows(
    queryFn: (q) => q.eqOrNull('product_id', productId),
    limit: 10000,
  );
  final nextCount = favoriteRows.length;
  await ProductsTable().update(
    data: {'favorites_count': nextCount},
    matchingRows: (rows) => rows.eqOrNull('id', productId),
  );
  return nextCount;
}
