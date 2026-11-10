import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/dpd_shipping_rates.dart';
import 'package:fleaber/utils/fee_calculator.dart';

void main() {
  test('ZIP136 Célia table IVA incl.', () {
    expect(
      fleaberDpdTablePriceEur(
        modality: FleaberDpdModality.shopToShop,
        band: FleaberDpdWeightBand.upTo3,
      ),
      2.99,
    );
    expect(
      fleaberDpdTablePriceEur(
        modality: FleaberDpdModality.shopToShop,
        band: FleaberDpdWeightBand.from3To6,
      ),
      3.49,
    );
    expect(
      fleaberDpdTablePriceEur(
        modality: FleaberDpdModality.shopToShop,
        band: FleaberDpdWeightBand.from6To10,
      ),
      4.99,
    );
    expect(
      fleaberDpdTablePriceEur(
        modality: FleaberDpdModality.shopToHome,
        band: FleaberDpdWeightBand.upTo3,
      ),
      4.49,
    );
    expect(
      fleaberDpdTablePriceEur(
        modality: FleaberDpdModality.shopToHome,
        band: FleaberDpdWeightBand.from3To6,
      ),
      5.99,
    );
    expect(
      fleaberDpdTablePriceEur(
        modality: FleaberDpdModality.shopToHome,
        band: FleaberDpdWeightBand.from6To10,
      ),
      8.99,
    );
  });

  test('ZIP136 rates live — no fixed 3.50 on DPD paths', () {
    expect(kFleaberDpdShippingRatesLive, isTrue);
    expect(kFleaberDpdHomeChargesEnabled, isTrue);
    final s2s = fleaberCheckoutDpdShippingEur(
      pickup: true,
      band: FleaberDpdWeightBand.upTo3,
    );
    final s2h = fleaberCheckoutDpdShippingEur(
      pickup: false,
      band: FleaberDpdWeightBand.upTo3,
    );
    expect(s2s, 2.99);
    expect(s2h, 4.49);
    expect(s2s, isNot(kFleaberCarrierShippingEur));
    // ZIP 140: carrier sem peso/escalão falha (não assume 0–3).
    expect(() => fleaberShippingEurFromMethod('carrier'), throwsFormatException);
    expect(fleaberShippingEurFromMethod('hand'), 0);
  });

  test('ZIP136 Home premium (fuel+door) deltas', () {
    // Prémio Home vs Shop embutido na tabela Célia (combustível + porta).
    expect(4.49 - 2.99, closeTo(1.50, 0.001));
    expect(5.99 - 3.49, closeTo(2.50, 0.001));
    expect(8.99 - 4.99, closeTo(4.00, 0.001));
  });
}
