import '/order_cancel_eligibility.dart';

/// Âncora temporal do aceite de reserva (BUG-044 / APP-095).
///
/// `reservation_expires_at - 5d` só é fiável se foi definido no aceite.
/// Pedidos `reserva_pendente` antigos tinham expires na criação — usar
/// `updated_at` quando for claramente posterior (aceite recente).
DateTime? reservationAcceptanceAnchor({
  required String? status,
  required DateTime? reservationExpiresAt,
  required DateTime? updatedAt,
  required DateTime? createdAt,
}) {
  final key = normalizeOrderStatusKey(status);
  final updated = updatedAt;
  final exp = reservationExpiresAt?.toUtc();

  if (exp != null &&
      (key == 'reservado' ||
          key == 'aguarda_confirmacao' ||
          key == 'pago')) {
    final fromExp = exp.subtract(const Duration(days: 5)).toLocal();
    if (updated != null &&
        updated.isAfter(fromExp.add(const Duration(minutes: 2)))) {
      return updated;
    }
    return fromExp;
  }
  return updated ?? createdAt;
}

/// 1.º lembrete: ≥ 2 h após âncora. Repetição: ≥ 24 h desde o último.
bool shouldInsertReservationReminder({
  required DateTime now,
  required DateTime? anchor,
  required DateTime? lastReminderAt,
  Duration firstDelay = const Duration(hours: 2),
  Duration repeatDelay = const Duration(hours: 24),
}) {
  if (lastReminderAt == null) {
    if (anchor == null) return false;
    return !now.isBefore(anchor.add(firstDelay));
  }
  return !now.isBefore(lastReminderAt.add(repeatDelay));
}
