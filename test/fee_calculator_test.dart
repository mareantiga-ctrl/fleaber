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
    test('artigo 5 € sem portes', () {
      expect(
        calculateFleaberBuyerTotal(itemPriceEur: 5, includeProtectionFee: true),
        closeTo(5.90, 0.001),
      );
    });

    test('artigo 5 € + portes 3,50 €', () {
      expect(
        calculateFleaberBuyerTotal(
          itemPriceEur: 5,
          shippingEur: 3.5,
          includeProtectionFee: true,
        ),
        closeTo(9.58, 0.001),
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
  });
}
