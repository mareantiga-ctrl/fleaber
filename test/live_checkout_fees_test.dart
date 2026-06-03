import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/utils/fee_calculator.dart';
import 'package:fleaber/utils/live_in_stream_checkout.dart';

void main() {
  group('Live checkout portes (#1 manual)', () {
    test('transportadora 3,50 €', () {
      expect(
        LiveInStreamCheckout.shippingCostForMethod(
          LiveInStreamCheckout.shippingCarrier,
        ),
        LiveInStreamCheckout.shippingCarrierEur,
      );
      expect(LiveInStreamCheckout.shippingCarrierEur, 3.5);
    });

    test('entrega em mão 0 €', () {
      expect(
        LiveInStreamCheckout.shippingCostForMethod(
          LiveInStreamCheckout.shippingHand,
        ),
        0,
      );
    });

    test('saco 2 linhas 5 € + portes transportadora', () {
      const unit = 5.0;
      var items = 0.0;
      for (var i = 0; i < 2; i++) {
        items += calculateFleaberBuyerTotal(
          itemPriceEur: unit,
          includeProtectionFee: true,
        );
      }
      final shipping = LiveInStreamCheckout.shippingCostForMethod(
        LiveInStreamCheckout.shippingCarrier,
      );
      final total = items + shipping;
      expect(shipping, 3.5);
      expect(items, closeTo(11.80, 0.01));
      expect(total, closeTo(15.30, 0.01));
      expect(LiveInStreamCheckout.euroCents(total), 1530);
    });

    test('euroCents arredonda', () {
      expect(LiveInStreamCheckout.euroCents(5.905), 591);
      expect(LiveInStreamCheckout.euroCents(5.904), 590);
    });
  });
}
