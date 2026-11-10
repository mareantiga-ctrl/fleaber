import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/live_item_price_gate.dart';

void main() {
  group('LiveItemPriceGate', () {
    test('hasPayableUnitPrice rejects null and zero', () {
      expect(
        LiveItemPriceGate.hasPayableUnitPrice(liveItemPrice: null),
        isFalse,
      );
      expect(
        LiveItemPriceGate.hasPayableUnitPrice(liveItemPrice: 0),
        isFalse,
      );
      expect(
        LiveItemPriceGate.hasPayableUnitPrice(liveItemPrice: -1),
        isFalse,
      );
    });

    test('hasPayableUnitPrice accepts positive live item price', () {
      expect(
        LiveItemPriceGate.hasPayableUnitPrice(liveItemPrice: 12),
        isTrue,
      );
    });

    test('product price takes precedence when positive', () {
      expect(
        LiveItemPriceGate.hasPayableUnitPrice(
          liveItemPrice: null,
          productPrice: 9.5,
        ),
        isTrue,
      );
      expect(
        LiveItemPriceGate.hasPayableUnitPrice(
          liveItemPrice: 12,
          productPrice: 0,
        ),
        isTrue,
      );
    });

    test('effectiveUnitPrice returns null when no payable price', () {
      expect(
        LiveItemPriceGate.effectiveUnitPrice(liveItemPrice: 0),
        isNull,
      );
      expect(
        LiveItemPriceGate.effectiveUnitPrice(
          liveItemPrice: null,
          productPrice: 0,
        ),
        isNull,
      );
    });

    test('effectiveUnitPrice returns product price when set', () {
      expect(
        LiveItemPriceGate.effectiveUnitPrice(
          liveItemPrice: 5,
          productPrice: 8,
        ),
        8,
      );
    });

    test('pending label is stable', () {
      expect(
        LiveItemPriceGate.pendingPriceLabel,
        'Preço a definir pela vendedora',
      );
    });

    test('awaiting seller price label is stable', () {
      expect(
        LiveItemPriceGate.awaitingSellerPriceLabel,
        'Aguarda que a vendedora defina o preço',
      );
    });
  });
}
