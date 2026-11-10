import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/dpd_shipping_rates.dart';
import 'package:fleaber/utils/order_shipment_weight.dart';

void main() {
  test('ZIP140 não assume 0–3 kg sem peso', () {
    final q = fleaberCheckoutDpdQuote(pickup: true);
    expect(q.ok, isFalse);
    expect(q.error, 'weight_required');
  });

  test('ZIP140 agrega kg de vários artigos', () {
    final agg = fleaberAggregateShipmentWeight([
      const FleaberShipmentWeightInput(weightKg: 1.2, quantity: 2),
      const FleaberShipmentWeightInput(weightKg: 0.5, quantity: 1),
    ]);
    expect(agg.ok, isTrue);
    expect(agg.totalKg, closeTo(2.9, 0.001));
    expect(agg.band, FleaberDpdWeightBand.upTo3);
  });

  test('ZIP140 artigo sem peso → bloqueia (peso do vendedor)', () {
    final agg = fleaberAggregateShipmentWeight([
      const FleaberShipmentWeightInput(weightKg: 1, quantity: 1),
      const FleaberShipmentWeightInput(),
    ]);
    expect(agg.ok, isFalse);
    expect(agg.needsBuyerBandChoice, isTrue);
    expect(agg.message, contains('vendedor'));
  });

  test('ZIP140 Célia table intacta', () {
    expect(
      fleaberDpdTablePriceEur(
        modality: FleaberDpdModality.shopToShop,
        band: FleaberDpdWeightBand.from3To6,
      ),
      3.49,
    );
  });

  test('ZIP140 quote com band explícito', () {
    final eur = fleaberCheckoutDpdShippingEur(
      pickup: true,
      band: FleaberDpdWeightBand.upTo3,
    );
    expect(eur, 2.99);
  });

  test('ZIP140 selo charged band/modality', () {
    final seal = fleaberOrderShippingSealFields(
      handDelivery: false,
      weightKg: 2.5,
      band: FleaberDpdWeightBand.upTo3,
      pickup: true,
      shippingEurCharged: 2.99,
    );
    expect(seal['shipping_weight_charged_band'], '0_3');
    expect(seal['shipping_modality'], 'shop_to_shop');
    expect(seal['shipping_cents_charged'], 299);
  });
}
