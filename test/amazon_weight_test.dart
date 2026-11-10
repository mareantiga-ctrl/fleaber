import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/amazon_importer/amazon_weight.dart';

void main() {
  group('AmazonWeight', () {
    test('GR → kg', () {
      expect(AmazonWeight.toKg(2079.9983, 'GR'), closeTo(2.08, 0.001));
    });

    test('KG passthrough', () {
      expect(AmazonWeight.toKg(2.0, 'KG'), 2.0);
    });

    test('shipping +10% once from manifesto', () {
      final m = AmazonWeight.toKg(2000, 'GR')!;
      expect(m, 2.0);
      final s = AmazonWeight.shippingKgFromManifest(m);
      expect(s, 2.2);
      // Reaplicar sobre manifesto, não sobre shipping.
      expect(AmazonWeight.shippingKgFromManifest(m), 2.2);
    });

    test('não inventa unidade desconhecida', () {
      expect(AmazonWeight.toKg(2.0, 'XYZ'), isNull);
      expect(AmazonWeight.toKg(0, 'GR'), isNull);
      expect(AmazonWeight.toKg(null, 'GR'), isNull);
    });

    test('labels', () {
      expect(AmazonWeight.formatManifestLabel(null), 'Peso por definir');
      expect(AmazonWeight.formatShippingLabel(2.2), contains('2,2'));
    });
  });
}
