import 'package:fleaber/live_amazon/live_amazon_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sellable requires stock and price', () {
    const ok = LiveAmazonPresentItem(
      asin: 'B00TEST0001',
      titlePt: 'Candeeiro Teste Marca',
      fleaberPriceEur: 10,
      availableQty: 2,
    );
    expect(ok.isSellableNow, isTrue);
    expect(ok.refLabel, 'AMZ-B00TEST0001');

    const noStock = LiveAmazonPresentItem(
      asin: 'B00TEST0001',
      titlePt: 'X',
      fleaberPriceEur: 10,
      availableQty: 0,
    );
    expect(noStock.isSellableNow, isFalse);
  });

  test('json roundtrip preserves amazon ref + company', () {
    final item = LiveAmazonPresentItem(
      asin: 'B00ABCDEF1',
      titlePt: 'Frigideira Marca',
      fleaberPriceEur: 19.99,
      amazonRefPriceEur: 39.98,
      amazonRefMarket: 'es',
      amazonRefFetchedAt: DateTime.utc(2026, 11, 9),
      discountPct: 50,
      lpn: 'LPN123',
      flbReference: 'FLB000037',
      companyKey: 'mare_antiga',
      availableQty: 1,
    );
    final back = LiveAmazonPresentItem.fromJson(item.toJson());
    expect(back.asin, item.asin);
    expect(back.lpn, 'LPN123');
    expect(back.flbReference, 'FLB000037');
    expect(back.amazonRefMarket, 'es');
    expect(back.companyKey, 'mare_antiga');
    expect(back.refLabel, 'LPN123');
  });
}
