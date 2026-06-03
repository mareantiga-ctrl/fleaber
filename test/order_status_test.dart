import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/order_cancel_eligibility.dart';

void main() {
  group('normalizeOrderStatusKey', () {
    test('pago em várias formas', () {
      expect(normalizeOrderStatusKey('pago'), 'pago');
      expect(normalizeOrderStatusKey('Pago'), 'pago');
      expect(normalizeOrderStatusKey(' PAGO '), 'pago');
    });

    test('reserva_pendente', () {
      expect(normalizeOrderStatusKey('reserva_pendente'), 'reserva_pendente');
      expect(normalizeOrderStatusKey('Reserva_Pendente'), 'reserva_pendente');
    });

    test('remove zero-width e BOM', () {
      expect(
        normalizeOrderStatusKey('\uFEFFpago\u200B'),
        'pago',
      );
    });

    test('vazio', () {
      expect(normalizeOrderStatusKey(null), '');
      expect(normalizeOrderStatusKey(''), '');
    });
  });

  group('orderIsCancelled', () {
    test('variantes cancelado', () {
      expect(orderIsCancelled('cancelado'), isTrue);
      expect(orderIsCancelled('Cancelada'), isTrue);
      expect(orderIsCancelled('pago'), isFalse);
    });
  });
}
