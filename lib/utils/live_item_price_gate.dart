import 'dart:async';

import '/backend/supabase/supabase.dart';
import '/utils/fleaber_logger.dart';
import '/utils/live_catalog_stock_service.dart';

/// Gate de pagamento — artigo live deve ter preço > 0.
abstract final class LiveItemPriceGate {
  static bool hasPayableUnitPrice({
    double? liveItemPrice,
    double? productPrice,
  }) {
    final unit = _effectiveUnit(liveItemPrice, productPrice);
    return unit != null && unit > 0;
  }

  static double? effectiveUnitPrice({
    double? liveItemPrice,
    double? productPrice,
  }) {
    final unit = _effectiveUnit(liveItemPrice, productPrice);
    if (unit == null || unit <= 0) return null;
    return unit;
  }

  static double? _effectiveUnit(double? liveItemPrice, double? productPrice) {
    if (productPrice != null && productPrice > 0) return productPrice;
    if (liveItemPrice != null && liveItemPrice > 0) return liveItemPrice;
    return null;
  }

  /// Checkout live: preço do artigo na live tem prioridade sobre shadow antigo.
  static double? _effectiveUnitLiveFirst(
    double? liveItemPrice,
    double? productPrice,
  ) {
    if (liveItemPrice != null && liveItemPrice > 0) return liveItemPrice;
    if (productPrice != null && productPrice > 0) return productPrice;
    return null;
  }

  static const pendingPriceLabel = 'Preço a definir pela vendedora';

  static const awaitingSellerPriceLabel =
      'Aguarda que a vendedora defina o preço';

  static void logCheckoutGate(
    String stage, {
    String? liveId,
    String? sellerId,
    String? liveItemId,
    String? requestId,
    String? productId,
    double? unit,
    double? liveItemPrice,
    double? productPrice,
    String? reason,
    String? ensureError,
  }) {
    final payload = <String, dynamic>{
      'stage': stage,
      if (liveItemId != null && liveItemId.isNotEmpty)
        'live_item_id': liveItemId,
      if (productId != null && productId.isNotEmpty) 'product_id': productId,
      if (unit != null) 'unit': unit,
      if (liveItemPrice != null) 'live_item_price': liveItemPrice,
      if (productPrice != null) 'product_price': productPrice,
      if (reason != null) 'reason': reason,
      if (ensureError != null && ensureError.isNotEmpty)
        'ensure_error': ensureError,
    };
    unawaited(FleaberLogger.instance.event('live.checkout.gate', payload));
    final lid = liveId?.trim() ?? '';
    final sid = sellerId?.trim() ?? '';
    if (lid.isEmpty || sid.isEmpty) return;
    unawaited(
      FleaberLogger.instance.logLiveVendorStudio(
        'checkout.$stage',
        liveId: lid,
        sellerId: sid,
        liveItemId: liveItemId,
        requestId: requestId,
        status: reason != null ? 'error' : 'ok',
        data: payload,
      ),
    );
  }

  /// Preço unitário fresco: RPC stock (security definer) + `live_items`.
  static Future<double?> resolveFreshUnitPrice({
    String? liveItemId,
    double? fallbackLiveItemPrice,
    double? productPrice,
    String? sellerId,
    String? liveId,
    LiveItemsRow? itemRow,
  }) async {
    var livePrice = fallbackLiveItemPrice;
    final id = liveItemId?.trim() ?? '';
    if (id.isNotEmpty) {
      final checkout = await LiveCatalogStockService.resolveCheckoutProduct(
        id,
        itemRow: itemRow,
        sellerId: sellerId,
        liveId: liveId,
      );
      if (checkout?.price != null && checkout!.price! > 0) {
        return checkout.price;
      }

      final snap = await LiveCatalogStockService.fetch(id);
      final rpcPrice = snap?.liveItemPrice;
      if (rpcPrice != null && rpcPrice > 0) {
        livePrice = rpcPrice;
      } else {
        final row = await LiveCatalogStockService.fetchLiveItemById(id);
        if (row?.price != null && row!.price! > 0) livePrice = row.price;
      }
    }
    return _effectiveUnitLiveFirst(livePrice, productPrice);
  }

  static Future<bool> hasFreshPayableUnitPrice({
    String? liveItemId,
    double? fallbackLiveItemPrice,
    double? productPrice,
    String? sellerId,
    String? liveId,
    LiveItemsRow? itemRow,
  }) async {
    final unit = await resolveFreshUnitPrice(
      liveItemId: liveItemId,
      fallbackLiveItemPrice: fallbackLiveItemPrice,
      productPrice: productPrice,
      sellerId: sellerId,
      liveId: liveId,
      itemRow: itemRow,
    );
    return unit != null && unit > 0;
  }

  /// Produto Stripe: RPC → synthesize (sem SELECT RLS em `products`).
  static Future<ProductsRow?> resolveProductForCheckout({
    required LiveItemsRow? itemRow,
    String? sellerId,
    String? liveId,
    Future<ProductsRow?> Function(LiveItemsRow item)? resolveProduct,
  }) async {
    if (itemRow == null) return null;
    var row = itemRow;
    final liid = row.id?.trim() ?? '';
    if (liid.isNotEmpty) {
      final fresh = await LiveCatalogStockService.fetchLiveItemById(liid);
      if (fresh != null) row = fresh;

      final rpcProduct = await LiveCatalogStockService.resolveCheckoutProduct(
        liid,
        itemRow: row,
        sellerId: sellerId,
        liveId: liveId,
      );
      if (rpcProduct != null) {
        logCheckoutGate(
          'resolve_product_ok',
          liveId: liveId,
          sellerId: sellerId,
          liveItemId: liid,
          productId: rpcProduct.id,
          productPrice: rpcProduct.price,
          liveItemPrice: row.price,
        );
        return rpcProduct;
      }

      final synth = await LiveCatalogStockService.synthesizeCheckoutProductRow(
        liveItemId: liid,
        itemRow: row,
        sellerId: sellerId,
        liveId: liveId ?? row.liveId,
      );
      if (synth != null) {
        logCheckoutGate(
          'resolve_product_synth',
          liveId: liveId,
          sellerId: sellerId,
          liveItemId: liid,
          productId: synth.id,
          productPrice: synth.price,
          liveItemPrice: row.price,
        );
        return synth;
      }
    }

    if (row.isMarketplaceProduct) {
      final pid = row.productId?.trim();
      if (pid != null && pid.isNotEmpty) {
        final list = await ProductsTable().queryRows(
          queryFn: (q) => q.eqOrNull('id', pid),
          limit: 1,
        );
        if (list.isNotEmpty) {
          logCheckoutGate(
            'resolve_product_marketplace',
            liveId: liveId,
            sellerId: sellerId,
            liveItemId: liid,
            productId: list.first.id,
            productPrice: list.first.price,
          );
          return list.first;
        }
      }
    }

    if (resolveProduct != null) {
      final fallback = await resolveProduct(row);
      logCheckoutGate(
        'resolve_product_delegate',
        liveId: liveId,
        sellerId: sellerId,
        liveItemId: liid,
        productId: fallback?.id,
        productPrice: fallback?.price,
        liveItemPrice: row.price,
        reason: fallback == null ? 'delegate_null' : null,
      );
      return fallback;
    }

    logCheckoutGate(
      'resolve_product_miss',
      liveId: liveId,
      sellerId: sellerId,
      liveItemId: liid,
      liveItemPrice: row.price,
      reason: 'no_product',
    );
    return null;
  }
}
