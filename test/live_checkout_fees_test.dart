import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/utils/dpd_shipping_rates.dart';
import 'package:fleaber/utils/fee_calculator.dart';
import 'package:fleaber/utils/live_in_stream_checkout.dart';

void main() {
  group('Live checkout portes (tabela Célia)', () {
    test('transportadora exige peso/escalão; default Shop2Shop ≤3 kg = 2,99 €', () {
      expect(kFleaberDpdShippingRatesLive, isTrue);
      expect(
        () => LiveInStreamCheckout.shippingCostForMethod(
          LiveInStreamCheckout.shippingCarrier,
        ),
        throwsFormatException,
      );
      expect(
        LiveInStreamCheckout.shippingCostForMethod(
          LiveInStreamCheckout.shippingCarrier,
          pickup: true,
          band: FleaberDpdWeightBand.upTo3,
        ),
        2.99,
      );
      // Constante legada ainda existe para encomendas antigas — não é cotação live.
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

    test('saco 2×5 € + portes Célia — protecção sobre artigos+portes', () {
      const unit = 5.0;
      const qty = 2;
      const items = unit * qty;
      final shipping = LiveInStreamCheckout.shippingCostForMethod(
        LiveInStreamCheckout.shippingCarrier,
        pickup: true,
        band: FleaberDpdWeightBand.upTo3,
      );
      expect(shipping, 2.99);
      final expected = liveBagBuyerTotalEur(
        itemsSubtotalEur: items,
        shippingEur: shipping,
      );
      // 10 + 2,99 = 12,99; fee = 0,65 + 5%×12,99 = 1,2995 → total ≈ 14,29
      expect(expected, closeTo(14.2895, 0.01));
      expect(LiveInStreamCheckout.euroCents(expected), 1429);

      final perLine = allocateLiveBagBuyerTotals(
        lineItemsEur: [unit, unit],
        buyerTotalEur: expected,
      );
      expect(perLine.length, 2);
      expect(perLine.fold<double>(0, (a, b) => a + b), closeTo(expected, 0.001));
    });

    test('C27 saco 1×11 € + portes Célia (APP-214 actualizado)', () {
      const items = 11.0;
      const shipping = 2.99;
      final total = liveBagBuyerTotalEur(
        itemsSubtotalEur: items,
        shippingEur: shipping,
      );
      // 13,99 + (0,65 + 5%×13,99) = 13,99 + 1,3495 ≈ 15,34
      expect(total, closeTo(15.3395, 0.01));
      expect(
        liveSellerEarningsEur(
          storedPriceTotal: total,
          isDirectPayment: false,
          lineItemEur: items,
          shippingEur: shipping,
        ),
        closeTo(13.99, 0.001),
      );
    });

    test('B2 single directo carrier = artigos + portes Célia', () {
      const item = 20.0;
      final shipping = LiveInStreamCheckout.shippingCostForMethod(
        LiveInStreamCheckout.shippingCarrier,
        pickup: true,
        band: FleaberDpdWeightBand.upTo3,
      );
      final total = calculateFleaberBuyerTotal(
        itemPriceEur: item,
        shippingEur: shipping,
        includeProtectionFee: false,
      );
      expect(total, closeTo(22.99, 0.001));
      expect(total, isNot(closeTo(item, 0.001)));
    });

    test('euroCents arredonda', () {
      expect(LiveInStreamCheckout.euroCents(5.905), 591);
      expect(LiveInStreamCheckout.euroCents(5.904), 590);
    });
  });
}
