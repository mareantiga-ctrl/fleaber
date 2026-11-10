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

    test('saco 2×5 € + portes — alinhado ao sheet checkout (protecção sobre artigos+portes)', () {
      const unit = 5.0;
      const qty = 2;
      const items = unit * qty;
      final shipping = LiveInStreamCheckout.shippingCostForMethod(
        LiveInStreamCheckout.shippingCarrier,
      );
      final expected = liveBagBuyerTotalEur(
        itemsSubtotalEur: items,
        shippingEur: shipping,
      );
      expect(expected, closeTo(14.83, 0.001));
      expect(LiveInStreamCheckout.euroCents(expected), 1483);

      final perLine = allocateLiveBagBuyerTotals(
        lineItemsEur: [unit, unit],
        buyerTotalEur: expected,
      );
      expect(perLine.length, 2);
      expect(perLine.fold<double>(0, (a, b) => a + b), closeTo(expected, 0.001));
    });

    test('C27 saco 1×11 € + portes = 15,88 € (APP-214)', () {
      const items = 11.0;
      const shipping = 3.5;
      final total = liveBagBuyerTotalEur(
        itemsSubtotalEur: items,
        shippingEur: shipping,
      );
      expect(total, closeTo(15.88, 0.001));
      expect(LiveInStreamCheckout.euroCents(total), 1588);
      expect(
        liveSellerEarningsEur(
          storedPriceTotal: total,
          isDirectPayment: false,
          lineItemEur: items,
          shippingEur: shipping,
        ),
        closeTo(14.5, 0.001),
      );
    });

    test('B2 single directo carrier = artigos + 3,50 (não só artigos)', () {
      const item = 20.0;
      final shipping = LiveInStreamCheckout.shippingCostForMethod(
        LiveInStreamCheckout.shippingCarrier,
      );
      final total = calculateFleaberBuyerTotal(
        itemPriceEur: item,
        shippingEur: shipping,
        includeProtectionFee: false,
      );
      expect(total, closeTo(23.5, 0.001));
      expect(total, isNot(closeTo(item, 0.001)));
    });

    test('euroCents arredonda', () {
      expect(LiveInStreamCheckout.euroCents(5.905), 591);
      expect(LiveInStreamCheckout.euroCents(5.904), 590);
    });
  });
}
