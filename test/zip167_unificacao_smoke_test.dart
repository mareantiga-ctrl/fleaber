import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/backend/supabase/database/tables/wallets.dart';
import 'package:fleaber/utils/fleaber_notifications_inbox.dart';
import 'package:fleaber/backend/supabase/database/tables/user_notifications.dart';

void main() {
  group('ZIP 167 unificação smoke', () {
    test('carteira: available = balance − held', () {
      final w = WalletsRow({
        'balance': 20.0,
        'held_balance': 5.0,
        'risk_status': 'clear',
        'stripe_account_id': 'acct_x',
        'stripe_connect_transfers_status': 'active',
        'stripe_connect_details_submitted': true,
      });
      expect(w.availableBalance, 15.0);
      expect(w.connectReadyForPayout, isTrue);
    });

    test('notif wallet destination preservada', () {
      final n = UserNotificationsRow({
        'id': '1',
        'kind': 'wallet_funds_released',
        'title': 'Saldo libertado',
      });
      expect(
        FleaberNotificationsInbox.destinationFor(n),
        FleaberNotificationDestination.wallet,
      );
    });
  });
}
