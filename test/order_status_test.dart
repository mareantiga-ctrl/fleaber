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

  group('orderStatusDisplayPhrase', () {
    test('premio_rifa nunca diz Pago', () {
      expect(orderStatusDisplayPhrase('premio_rifa'), 'Prémio da Rifa · Envio a pagar');
      expect(orderStatusDisplayPhrase('pago'), 'Pago');
    });

    test('disputa_devolucao_vendedor é humano, não snake_case', () {
      expect(
        orderStatusDisplayPhrase('disputa_devolucao_vendedor'),
        'Problema com a devolução',
      );
    });

    test('devolucao_entregue é humano', () {
      expect(
        orderStatusDisplayPhrase('devolucao_entregue'),
        'Devolução entregue',
      );
    });

    test('chave desconhecida snake_case não vaza para UI', () {
      expect(
        orderStatusDisplayPhrase('estado_interno_xyz'),
        'Em processamento',
      );
    });
  });

  group('orderStatusIsPaidOrPrize', () {
    test('pago e premio_rifa', () {
      expect(orderStatusIsPaidOrPrize('pago'), isTrue);
      expect(orderStatusIsPaidOrPrize('premio_rifa'), isTrue);
      expect(orderStatusIsPaidOrPrize('reservado'), isFalse);
    });
  });
}
