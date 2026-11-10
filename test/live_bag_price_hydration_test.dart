import 'package:fleaber/backend/supabase/database/tables/live_items.dart';
import 'package:fleaber/backend/supabase/database/tables/products.dart';
import 'package:fleaber/utils/live_catalog_stock_service.dart';
import 'package:fleaber/utils/live_item_price_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('liveItemRowFromBagRpcs', () {
    test('usa preço da live quando > 0 (caso aceite marketplace 18€)', () {
      final snap = LiveCatalogStockSnapshot(
        liveItemId: 'li-1',
        liveId: 'live-1',
        itemKind: 'marketplace_product',
        productId: 'prod-1',
        refCode: 'T02',
        totalQty: 1,
        blockedQty: 0,
        reservedAcceptedQty: 1,
        pendingBagQty: 0,
        soldConvertedQty: 0,
        availableQty: 0,
        liveItemPrice: 18,
      );
      final row = LiveCatalogStockService.liveItemRowFromBagRpcs(
        liveItemId: 'li-1',
        snap: snap,
        checkoutProduct: ProductsRow({
          'id': 'prod-1',
          'seller_id': 'seller-1',
          'title': 'Vestido floral verão — TESTE 02',
          'price': 18,
          'ref_code': 'T02',
          'image_urls': <String>['https://example.com/t02.jpg'],
        }),
      );
      expect(row, isA<LiveItemsRow>());
      expect(row.price, 18);
      expect(row.refCode, 'T02');
      expect(row.title, contains('Vestido'));
      expect(
        LiveItemPriceGate.hasPayableUnitPrice(liveItemPrice: row.price),
        isTrue,
      );
    });

    test('fallback para preço do produto se live price ausente', () {
      final snap = LiveCatalogStockSnapshot(
        liveItemId: 'li-2',
        liveId: 'live-1',
        itemKind: 'marketplace_product',
        productId: 'prod-2',
        refCode: 'T08',
        totalQty: 1,
        blockedQty: 0,
        reservedAcceptedQty: 1,
        pendingBagQty: 0,
        soldConvertedQty: 0,
        availableQty: 0,
        liveItemPrice: null,
      );
      final row = LiveCatalogStockService.liveItemRowFromBagRpcs(
        liveItemId: 'li-2',
        snap: snap,
        checkoutProduct: ProductsRow({
          'id': 'prod-2',
          'seller_id': 'seller-1',
          'title': 'Blazer',
          'price': 32,
          'ref_code': 'T08',
        }),
      );
      expect(row.price, 32);
      expect(
        LiveItemPriceGate.hasPayableUnitPrice(liveItemPrice: row.price),
        isTrue,
      );
    });

    test('sem preços → row sem preço (UI continua a pedir definição)', () {
      final row = LiveCatalogStockService.liveItemRowFromBagRpcs(
        liveItemId: 'li-3',
        snap: LiveCatalogStockSnapshot(
          liveItemId: 'li-3',
          liveId: 'live-1',
          itemKind: 'live_only',
          totalQty: 1,
          blockedQty: 0,
          reservedAcceptedQty: 0,
          pendingBagQty: 1,
          soldConvertedQty: 0,
          availableQty: 0,
          liveItemPrice: 0,
        ),
        checkoutProduct: null,
      );
      expect(
        LiveItemPriceGate.hasPayableUnitPrice(liveItemPrice: row.price),
        isFalse,
      );
    });
  });
}
