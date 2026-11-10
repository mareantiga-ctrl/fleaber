import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/dpd_shipping_rates.dart';
import 'package:fleaber/utils/fee_calculator.dart';

void main() {
  test('tabela Célia S2S / S2H', () {
    expect(
      fleaberDpdTablePriceEur(
        modality: FleaberDpdModality.shopToShop,
        band: FleaberDpdWeightBand.upTo3,
      ),
      2.99,
    );
    expect(
      fleaberDpdTablePriceEur(
        modality: FleaberDpdModality.shopToHome,
        band: FleaberDpdWeightBand.from6To10,
      ),
      8.99,
    );
  });

  test('escalão usa teto; >10 kg bloqueia', () {
    final q = fleaberQuoteDpdShipping(
      modality: FleaberDpdModality.shopToShop,
      band: FleaberDpdWeightBand.from3To6,
      ratesLive: true,
    );
    expect(q.ok, isTrue);
    expect(q.weightKg, 6);
    expect(q.priceEur, 3.49);

    final over = fleaberQuoteDpdShipping(
      modality: FleaberDpdModality.shopToShop,
      weightKg: 10.1,
      ratesLive: true,
    );
    expect(over.ok, isFalse);
    expect(over.error, 'over_10kg');
  });

  test('rates live off → legado 3,50', () {
    final q = fleaberQuoteDpdShipping(
      modality: FleaberDpdModality.shopToShop,
      weightKg: 1,
      ratesLive: false,
    );
    expect(q.ok, isTrue);
    expect(q.legacy, isTrue);
    expect(q.priceEur, kFleaberCarrierShippingEur);
  });

  test('home charges disabled when rates live', () {
    final q = fleaberQuoteDpdShipping(
      modality: FleaberDpdModality.shopToHome,
      weightKg: 2,
      ratesLive: true,
      homeChargesEnabled: false,
    );
    expect(q.ok, isFalse);
    expect(q.error, 'home_charges_disabled');
  });

  test('envio grátis vendedor', () {
    final q = fleaberQuoteDpdShipping(
      modality: FleaberDpdModality.shopToShop,
      weightKg: 2,
      freeBySeller: true,
      ratesLive: true,
    );
    expect(q.ok, isTrue);
    expect(q.priceEur, 0);
  });
}
