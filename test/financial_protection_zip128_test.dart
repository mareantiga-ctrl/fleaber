import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/backend/supabase/database/tables/orders.dart';
import 'package:fleaber/backend/supabase/database/tables/wallets.dart';
import 'package:fleaber/legal/legal_texts.dart';

void main() {
  group('ZIP 128 — proteção financeira (contratos locais)', () {
    test('OrdersRow.isB2cChannel', () {
      final c2c = OrdersRow({'commerce_channel': 'c2c'});
      final b2c = OrdersRow({'commerce_channel': 'b2c'});
      final empty = OrdersRow({});
      expect(c2c.isB2cChannel, isFalse);
      expect(b2c.isB2cChannel, isTrue);
      expect(empty.isB2cChannel, isFalse);
    });

    test('WalletsRow.availableBalance = balance - held', () {
      final w = WalletsRow({
        'balance': 100.0,
        'held_balance': 25.5,
        'risk_status': 'clear',
      });
      expect(w.availableBalance, closeTo(74.5, 0.001));
      expect(w.heldBalance, closeTo(25.5, 0.001));
    });

    test('held > balance → available 0', () {
      final w = WalletsRow({
        'balance': 10.0,
        'held_balance': 40.0,
      });
      expect(w.availableBalance, 0.0);
    });

    test('Termos mencionam C2C 48h e B2C 14 dias', () {
      final termsBody =
          LegalTexts.terms.map((s) => s.body).join('\n');
      final refundsBody =
          LegalTexts.refunds.map((s) => s.body).join('\n');
      expect(termsBody.contains('48 horas'), isTrue);
      expect(termsBody.toLowerCase().contains('14 dias'), isTrue);
      expect(termsBody.toLowerCase().contains('livre resolução'), isTrue);
      expect(termsBody.contains('valor contestado'), isTrue);
      expect(refundsBody.toLowerCase().contains('livre resolução'), isTrue);
      expect(refundsBody.contains('B2C'), isTrue);
    });

    test('Reembolsos distingue Proteção 48h de livre resolução', () {
      final section = LegalTexts.refunds.firstWhere(
        (s) => s.title.toLowerCase().contains('livre resolução'),
      );
      expect(section.body.contains('14 dias'), isTrue);
      expect(section.body.contains('48 h'), isTrue);
    });
  });
}
