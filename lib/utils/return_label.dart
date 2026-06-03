/// Regras da etiqueta de devolução Fleaber.
class ReturnLabelRules {
  ReturnLabelRules._();

  static const double shippingFeeEur = 3.50;
  static const int downloadDays = 5;

  static DateTime? deadlineFrom(DateTime? labelCreatedAt) {
    if (labelCreatedAt == null) return null;
    return labelCreatedAt.toLocal().add(const Duration(days: downloadDays));
  }

  static DateTime? effectiveDeadline({
    DateTime? labelCreatedAt,
    DateTime? labelDeadline,
  }) {
    if (labelDeadline != null) return labelDeadline.toLocal();
    return deadlineFrom(labelCreatedAt);
  }

  static String formatDeadline(
    DateTime? labelCreatedAt, {
    DateTime? labelDeadline,
  }) {
    final deadline = effectiveDeadline(
      labelCreatedAt: labelCreatedAt,
      labelDeadline: labelDeadline,
    );
    if (deadline == null) return 'Prazo não definido';
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) return 'Prazo expirado';
    if (remaining.inDays >= 1) {
      return '${remaining.inDays} dia(s) restantes';
    }
    if (remaining.inHours >= 1) {
      return '${remaining.inHours} hora(s) restantes';
    }
    return '${remaining.inMinutes} min restantes';
  }
}
