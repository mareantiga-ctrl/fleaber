import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/backend/supabase/database/tables/user_notifications.dart';
import 'package:fleaber/backend/supabase/database/tables/wallets.dart';
import 'package:fleaber/utils/fleaber_notifications_inbox.dart';

void main() {
  group('ZIP 166 Ponto 11 wallet', () {
    test('availableBalance = balance − held (nunca negativo)', () {
      final row = WalletsRow({
        'id': '00000000-0000-0000-0000-000000000001',
        'balance': 50.0,
        'held_balance': 12.5,
        'risk_status': 'clear',
      });
      expect(row.availableBalance, 37.5);

      final overHeld = WalletsRow({
        'balance': 5.0,
        'held_balance': 9.0,
      });
      expect(overHeld.availableBalance, 0.0);
    });

    test('notificações wallet → destino carteira', () {
      for (final kind in [
        'wallet_funds_released',
        'wallet_payout_sent',
        'wallet_payout_failed',
      ]) {
        final n = UserNotificationsRow({
          'id': 'n1',
          'kind': kind,
          'title': 't',
          'body': 'b',
        });
        expect(
          FleaberNotificationsInbox.destinationFor(n),
          FleaberNotificationDestination.wallet,
          reason: kind,
        );
      }
    });
  });
}
