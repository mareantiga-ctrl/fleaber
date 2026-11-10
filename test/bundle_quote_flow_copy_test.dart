import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/bundle_quote_flow.dart';

void main() {
  group('bundle quote-before-pay copy', () {
    test('pending buyer — sem reserva + 48h', () {
      final b = {
        'status': 'pending',
        'rule_version': 'quote_before_pay_v1',
        'seller_confirm_expires_at': '2099-01-15T12:00:00Z',
      };
      expect(isQuoteBeforePayBundle(b), isTrue);
      expect(bundleBuyerStatusHeadline(b), contains('Pedido enviado'));
      expect(bundleBuyerStatusBody(b).toLowerCase(), contains('não ficam reservados'));
      expect(bundleSellerStatusHeadline(b), contains('Novo pedido'));
    });

    test('awaiting_payment — pagar / 48h', () {
      final b = {
        'status': 'awaiting_payment',
        'rule_version': 'quote_before_pay_v1',
        'pay_expires_at': '2099-01-16T12:00:00Z',
        'articles_cents': 1000,
        'shipping_cents': 299,
        'protection_cents': 50,
        'grand_total_cents': 1349,
      };
      expect(bundleBuyerStatusHeadline(b), contains('já podes pagar'));
      expect(bundleBuyerStatusBody(b).toLowerCase(), contains('desistir'));
      expect(formatBundleEur(centsToEur(1349)), '13,49 €');
    });

    test('expired — sem cobrança', () {
      final b = {'status': 'expired', 'rule_version': 'quote_before_pay_v1'};
      expect(bundleBuyerStatusHeadline(b).toLowerCase(), contains('não foste cobrada'));
    });
  });
}
