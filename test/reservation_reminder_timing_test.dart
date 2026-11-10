import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/utils/reservation_reminder_timing.dart';

void main() {
  group('reservationAcceptanceAnchor (APP-095 / BUG-044)', () {
    test('aceite recente — prefere updated_at a expires antigo do pendente', () {
      final pendingExp = DateTime.utc(2026, 8, 20, 12);
      final acceptedAt = DateTime.utc(2026, 8, 23, 10);
      final anchor = reservationAcceptanceAnchor(
        status: 'reservado',
        reservationExpiresAt: pendingExp.add(const Duration(days: 5)),
        updatedAt: acceptedAt,
        createdAt: DateTime.utc(2026, 8, 18, 9),
      );
      expect(anchor, acceptedAt);
    });

    test('expires alinhado ao aceite — usa expires - 5d', () {
      final acceptedAt = DateTime(2026, 8, 23, 12);
      final exp = acceptedAt.add(const Duration(days: 5));
      final anchor = reservationAcceptanceAnchor(
        status: 'reservado',
        reservationExpiresAt: exp,
        updatedAt: acceptedAt,
        createdAt: acceptedAt,
      );
      expect(anchor, acceptedAt);
    });
  });

  group('shouldInsertReservationReminder', () {
    test('1.º lembrete bloqueado antes de 2 h', () {
      final anchor = DateTime(2026, 8, 23, 10);
      expect(
        shouldInsertReservationReminder(
          now: anchor.add(const Duration(hours: 1, minutes: 59)),
          anchor: anchor,
          lastReminderAt: null,
        ),
        isFalse,
      );
      expect(
        shouldInsertReservationReminder(
          now: anchor.add(const Duration(hours: 2)),
          anchor: anchor,
          lastReminderAt: null,
        ),
        isTrue,
      );
    });

    test('repetição bloqueada antes de 24 h', () {
      final last = DateTime(2026, 8, 23, 12);
      expect(
        shouldInsertReservationReminder(
          now: last.add(const Duration(hours: 23)),
          anchor: DateTime(2026, 8, 23, 10),
          lastReminderAt: last,
        ),
        isFalse,
      );
      expect(
        shouldInsertReservationReminder(
          now: last.add(const Duration(hours: 24)),
          anchor: DateTime(2026, 8, 23, 10),
          lastReminderAt: last,
        ),
        isTrue,
      );
    });
  });
}
