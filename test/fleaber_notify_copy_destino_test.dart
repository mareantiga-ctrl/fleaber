import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/fleaber_notification_copy.dart';
import 'package:fleaber/utils/fleaber_notifications_inbox.dart';
import 'package:fleaber/backend/supabase/database/tables/user_notifications.dart';

UserNotificationsRow _row(Map<String, dynamic> data) =>
    UserNotificationsRow(data);

void main() {
  group('fleaberNotificationInboxTitle', () {
    test('bundle não usa copy «gostou»', () {
      final t = fleaberNotificationInboxTitle(
        kind: 'bundle_proposal',
        inboxTitle: 'Nova proposta de conjunto',
        likerName: 'X',
        productTitle: 'Y',
      );
      expect(t, 'Nova proposta de conjunto');
      expect(t.toLowerCase().contains('gostou'), isFalse);
    });

    test('bundle_quote_ready fallback PT', () {
      final t = fleaberNotificationInboxTitle(
        kind: 'bundle_quote_ready',
        inboxTitle: null,
        likerName: 'X',
        productTitle: 'Y',
      );
      expect(t.toLowerCase(), contains('pagar'));
      expect(t.toLowerCase().contains('gostou'), isFalse);
    });

    test('seguro_fleaber_paid fallback', () {
      final t = fleaberNotificationInboxTitle(
        kind: 'seguro_fleaber_paid',
        inboxTitle: null,
        likerName: 'X',
        productTitle: 'Y',
      );
      expect(t, 'Compra paga');
    });

    test('shipped fallback', () {
      final t = fleaberNotificationInboxTitle(
        kind: 'reservation_order_shipped',
        inboxTitle: null,
        likerName: 'X',
        productTitle: 'Y',
      );
      expect(t, 'Encomenda enviada');
    });

    test('shipping_delta_requested fallback', () {
      final t = fleaberNotificationInboxTitle(
        kind: 'shipping_delta_requested',
        inboxTitle: null,
        likerName: 'X',
        productTitle: 'Y',
      );
      expect(t, 'Diferença de portes');
    });
  });

  group('destinationFor', () {
    test('bundle com chat → chat', () {
      final d = FleaberNotificationsInbox.destinationFor(
        _row({
          'kind': 'bundle_proposal',
          'chat_id': '11111111-1111-1111-1111-111111111111',
        }),
      );
      expect(d, FleaberNotificationDestination.chat);
    });

    test('seguro_fleaber_paid com chat → chat', () {
      final d = FleaberNotificationsInbox.destinationFor(
        _row({
          'kind': 'seguro_fleaber_paid',
          'chat_id': '11111111-1111-1111-1111-111111111111',
        }),
      );
      expect(d, FleaberNotificationDestination.chat);
    });

    test('shipped sem chat → orders', () {
      final d = FleaberNotificationsInbox.destinationFor(
        _row({
          'kind': 'reservation_order_shipped',
        }),
      );
      expect(d, FleaberNotificationDestination.orders);
    });

    test('order_paid com chat → orders (não chat)', () {
      final d = FleaberNotificationsInbox.destinationFor(
        _row({
          'kind': 'order_paid_buyer',
          'chat_id': '11111111-1111-1111-1111-111111111111',
          'dedupe_key':
              'order_paid:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee:buyer',
        }),
      );
      expect(d, FleaberNotificationDestination.orders);
      expect(
        FleaberNotificationsInbox.orderIdFromNotification(
          _row({
            'dedupe_key':
                'order_paid:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee:buyer',
          }),
        ),
        'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );
    });

    test('shipping_delta_requested → orders', () {
      final d = FleaberNotificationsInbox.destinationFor(
        _row({'kind': 'shipping_delta_requested'}),
      );
      expect(d, FleaberNotificationDestination.orders);
    });

    test('favorite com product → product', () {
      final d = FleaberNotificationsInbox.destinationFor(
        _row({
          'kind': 'favorite',
          'product_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        }),
      );
      expect(d, FleaberNotificationDestination.product);
    });

    test('reserva sem chat → bag', () {
      final d = FleaberNotificationsInbox.destinationFor(
        _row({'kind': 'reservation_held'}),
      );
      expect(d, FleaberNotificationDestination.bag);
    });
  });
}
