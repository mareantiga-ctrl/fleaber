import '/backend/supabase/supabase.dart';

/// Rascunhos de anúncios (`products.is_draft = true`) — app + FleaHub.
class ProductDraftService {
  ProductDraftService._();

  static Future<List<ProductsRow>> listForSeller(String sellerId) async {
    final sid = sellerId.trim();
    if (sid.isEmpty) return const [];
    return ProductsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('seller_id', sid)
          .eqOrNull('is_draft', true)
          .order('created_at', ascending: false),
      limit: 100,
    );
  }

  static Future<void> deleteDraft({
    required String productId,
    required String sellerId,
  }) async {
    final id = productId.trim();
    final sid = sellerId.trim();
    if (id.isEmpty || sid.isEmpty) return;
    await ProductsTable().delete(
      matchingRows: (q) =>
          q.eqOrNull('id', id).eqOrNull('seller_id', sid).eqOrNull('is_draft', true),
    );
  }
}
