import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/dpd_shipping_rates.dart';
import 'package:fleaber/utils/order_shipment_weight.dart';

/// Contrato arquitetura 159.5.1: vendedor kg OU escalão; comprador nunca escolhe.
void main() {
  test('kg → escalão automático (fromKg)', () {
    expect(FleaberDpdWeightBand.fromKg(1.2), FleaberDpdWeightBand.upTo3);
    expect(FleaberDpdWeightBand.fromKg(3.0), FleaberDpdWeightBand.upTo3);
    expect(FleaberDpdWeightBand.fromKg(3.1), FleaberDpdWeightBand.from3To6);
    expect(FleaberDpdWeightBand.fromKg(6.5), FleaberDpdWeightBand.from6To10);
    expect(FleaberDpdWeightBand.fromKg(10.1), isNull);
  });

  test('só escalão (sem kg) agrega e cotiza', () {
    final agg = fleaberAggregateShipmentWeight([
      const FleaberShipmentWeightInput(
        band: FleaberDpdWeightBand.upTo3,
        quantity: 1,
      ),
    ]);
    expect(agg.ok, isTrue);
    expect(agg.band, FleaberDpdWeightBand.upTo3);
  });

  test('sem kg nem escalão → bloqueia comprador (não inventa 0–3)', () {
    final agg = fleaberAggregateShipmentWeight([
      const FleaberShipmentWeightInput(),
    ]);
    expect(agg.ok, isFalse);
    expect(agg.needsBuyerBandChoice, isTrue);
    expect(kFleaberBuyerWeightMissingMessage.toLowerCase(), contains('vendedor'));
  });
}
