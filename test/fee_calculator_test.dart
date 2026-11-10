import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/utils/fee_calculator.dart';

void main() {
  group('calculateFleaberProtectionFee', () {
    test('5 € artigo → 0,65 + 5% = 0,90', () {
      expect(calculateFleaberProtectionFee(5), closeTo(0.90, 0.001));
    });

    test('inclui portes na base do seguro', () {
      final withoutShipping = calculateFleaberProtectionFee(5, shippingEur: 0);
      final withShipping = calculateFleaberProtectionFee(5, shippingEur: 3.5);
      expect(withShipping, greaterThan(withoutShipping));
    });

    test('zero ou negativo → 0', () {
      expect(calculateFleaberProtectionFee(0), 0);
      expect(calculateFleaberProtectionFee(-1), 0);
    });
  });

  group('calculateFleaberBuyerTotal', () {
    test('artigo 5 € sem portes — conta independente', () {
      // esperado: 5 + (0,65 + 5%×5) = 5 + 0,65 + 0,25 = 5,90
      const item = 5.0;
      const feeFixed = 0.65;
      const feePct = 0.05;
      final expected = item + feeFixed + item * feePct;
      expect(expected, closeTo(5.90, 0.001));
      expect(
        calculateFleaberBuyerTotal(itemPriceEur: item, includeProtectionFee: true),
        closeTo(expected, 0.001),
      );
    });

    test('artigo 5 € + portes 3,50 € — conta independente', () {
      // base seguro = 5 + 3,50 = 8,50 → fee = 0,65 + 5%×8,50 = 0,65+0,425 = 1,075
      // total = 8,50 + 1,075 = 9,575 ≈ 9,58
      const item = 5.0;
      const shipping = 3.5;
      const feeFixed = 0.65;
      const feePct = 0.05;
      final base = item + shipping;
      final fee = feeFixed + base * feePct;
      final expected = base + fee;
      expect(expected, closeTo(9.575, 0.001));
      expect(
        calculateFleaberBuyerTotal(
          itemPriceEur: item,
          shippingEur: shipping,
          includeProtectionFee: true,
        ),
        closeTo(expected, 0.01),
      );
    });

    test('sem seguro', () {
      expect(
        calculateFleaberBuyerTotal(
          itemPriceEur: 5,
          shippingEur: 3.5,
          includeProtectionFee: false,
        ),
        closeTo(8.5, 0.001),
      );
    });

    test('B2 directo Live: 7/20/99,99 € + transportadora inclui portes', () {
      for (final item in [7.0, 20.0, 99.99]) {
        final total = calculateFleaberBuyerTotal(
          itemPriceEur: item,
          shippingEur: kFleaberCarrierShippingEur,
          includeProtectionFee: false,
        );
        expect(total, closeTo(item + 3.5, 0.001));
      }
    });

    test('B2 directo + mão = só artigos', () {
      expect(
        calculateFleaberBuyerTotal(
          itemPriceEur: 20,
          shippingEur: 0,
          includeProtectionFee: false,
        ),
        closeTo(20, 0.001),
      );
    });
  });

  group('fleaberShippingEurFromMethod (B3)', () {
    test('labels canónicos', () {
      expect(
        fleaberShippingEurFromMethod(kFleaberShippingCarrierLabel),
        3.5,
      );
      expect(fleaberShippingEurFromMethod(kFleaberShippingHandLabel), 0);
      expect(fleaberShippingEurFromMethod('carrier'), 3.5);
      expect(fleaberShippingEurFromMethod('hand'), 0);
    });

    test('lixo → FormatException (fail-closed)', () {
      expect(
        () => fleaberShippingEurFromMethod('porta_gratis_inventada'),
        throwsFormatException,
      );
    });

    test('lenient: legado mão / transportadora', () {
      expect(fleaberShippingEurFromMethodLenient('Entrega em Mão'), 0);
      expect(
        fleaberShippingEurFromMethodLenient('qualquer transportadora xyz'),
        3.5,
      );
      expect(fleaberShippingEurFromMethodLenient('???'), 0);
    });
  });

  group('liveSellerEarningsEur', () {
    test('pagamento directo 2×5 € + portes 3,50 = 13,50 (não 14,83)', () {
      const items = 10.0;
      const shipping = 3.5;
      const stored = 13.5;
      final buyerWithProtection = calculateFleaberBuyerTotal(
        itemPriceEur: items,
        shippingEur: shipping,
        includeProtectionFee: true,
      );
      expect(buyerWithProtection, closeTo(14.83, 0.001));
      expect(
        liveSellerEarningsEur(
          storedPriceTotal: stored,
          isDirectPayment: true,
          lineItemEur: items,
          shippingEur: shipping,
        ),
        closeTo(13.5, 0.001),
      );
    });

    test('directo sem total gravado = artigos + portes, sem protecção', () {
      expect(
        liveSellerEarningsEur(
          storedPriceTotal: 0,
          isDirectPayment: true,
          lineItemEur: 10,
          shippingEur: 3.5,
        ),
        closeTo(13.5, 0.001),
      );
    });

    test('pagamento na app = artigos + portes (sem protecção comprador)', () {
      expect(
        liveSellerEarningsEur(
          storedPriceTotal: 15.88,
          isDirectPayment: false,
          lineItemEur: 11,
          shippingEur: 3.5,
        ),
        closeTo(14.5, 0.001),
      );
    });

    test('catálogo sem encomenda não inventa portes nem protecção', () {
      expect(liveSellerEarningsEstimateFromCatalog(10), closeTo(10, 0.001));
      expect(liveSellerEarningsEstimateFromCatalog(0), 0);
    });
  });
}
