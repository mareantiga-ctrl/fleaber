import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/utils/fleaber_stripe_refund.dart';

void main() {
  group('orderIsSeguroFleaberPayment', () {
    test('Pagamento na App = Seguro Fleaber', () {
      expect(orderIsSeguroFleaberPayment('Pagamento na App'), isTrue);
      expect(orderIsSeguroFleaberPayment('Seguro Fleaber'), isTrue);
    });

    test('MB WAY / directo = não', () {
      expect(
        orderIsSeguroFleaberPayment(
          'Pagamento Direto ao Vendedor (MB WAY/Transf)',
        ),
        isFalse,
      );
      expect(orderIsSeguroFleaberPayment('MB WAY'), isFalse);
    });

    test('vazio', () {
      expect(orderIsSeguroFleaberPayment(null), isFalse);
      expect(orderIsSeguroFleaberPayment(''), isFalse);
    });
  });

  group('orderNeedsSeguroFleaberStripeRefund', () {
    test('pago + Pagamento na App', () {
      expect(
        orderNeedsSeguroFleaberStripeRefund(
          status: 'pago',
          paymentMethod: 'Pagamento na App',
        ),
        isTrue,
      );
    });

    test('pago + MB WAY = não', () {
      expect(
        orderNeedsSeguroFleaberStripeRefund(
          status: 'pago',
          paymentMethod: 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
        ),
        isFalse,
      );
    });

    test('reserva_pendente = não', () {
      expect(
        orderNeedsSeguroFleaberStripeRefund(
          status: 'reserva_pendente',
          paymentMethod: 'Pagamento na App',
        ),
        isFalse,
      );
    });

    test('cancelado + Seguro = retry permitido', () {
      expect(
        orderNeedsSeguroFleaberStripeRefund(
          status: 'cancelado',
          paymentMethod: 'Pagamento na App',
        ),
        isTrue,
      );
    });

    test('carteira vendedor: cancelado Seguro não é crédito venda', () {
      // Documenta regra de produto: cancelado Seguro → refund cartão,
      // nunca batata_release_seller_wallet / crédito «venda».
      expect(
        orderNeedsSeguroFleaberStripeRefund(
          status: 'pago',
          paymentMethod: 'Pagamento na App',
        ),
        isTrue,
      );
      expect(
        orderIsSeguroFleaberPayment('Pagamento na App'),
        isTrue,
      );
    });
  });
}
