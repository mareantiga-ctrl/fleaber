class ValidationIssue {
  ValidationIssue(this.severity, this.message);

  final String severity; // error | warn
  final String message;

  @override
  String toString() => '[$severity] $message';
}

class BotSimValidators {
  static List<ValidationIssue> run({
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
    required String runNotesTag,
    required int expectedChatEvents,
    required int botCount,
  }) {
    final issues = <ValidationIssue>[];

    _viewerCount(after, issues);
    _chatMessages(before, after, runNotesTag, expectedChatEvents, issues);
    _reservations(after, runNotesTag, issues);
    _stockNonNegative(after, issues);
    _raffles(after, issues);
    _ordersZeroPrice(after, issues);
    _orphanReservations(after, issues);
    _appLogsSevere(before, after, issues);

    return issues;
  }

  static void _viewerCount(
    Map<String, dynamic> after,
    List<ValidationIssue> issues,
  ) {
    final live = (after['live'] as List?)?.cast<Map<String, dynamic>>();
    final viewers = (after['live_viewers'] as List?)?.length ?? 0;
    final reported = live?.isNotEmpty == true
        ? (live!.first['viewer_count'] as num?)?.toInt()
        : null;
    if (reported != null && reported != viewers) {
      issues.add(ValidationIssue(
        'warn',
        'viewer_count ($reported) != live_viewers rows ($viewers) — TTL pode estar a expirar',
      ));
    }
  }

  static void _chatMessages(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
    String tag,
    int expectedMin,
    List<ValidationIssue> issues,
  ) {
    final beforeN = (before['live_messages_count'] as int?) ?? 0;
    final afterN = (after['live_messages_count'] as int?) ?? 0;
    final delta = afterN - beforeN;
    if (expectedMin > 0 && delta < expectedMin) {
      issues.add(ValidationIssue(
        'error',
        'Mensagens de chat: esperadas >= $expectedMin novas, obtidas $delta',
      ));
    }
    final sample = (after['live_messages_sample'] as List?) ?? [];
    final botMsgs = sample.where((m) {
      final map = Map<String, dynamic>.from(m as Map);
      final label = map['sender_label']?.toString() ?? '';
      return label.contains('DEMO_BOT') || label.contains('STRESS_TEST');
    }).length;
    if (expectedMin > 0 && botMsgs == 0) {
      issues.add(ValidationIssue(
        'warn',
        'Nenhuma mensagem bot encontrada na amostra (tag $tag)',
      ));
    }
  }

  static void _reservations(
    Map<String, dynamic> after,
    String runNotesTag,
    List<ValidationIssue> issues,
  ) {
    final rows = (after['live_reservation_requests'] as List?) ?? [];
    final tagged = rows.where((r) {
      final notes = Map<String, dynamic>.from(r as Map)['notes']?.toString() ?? '';
      return notes.contains(runNotesTag);
    }).toList();

    final byBuyerItem = <String, int>{};
    for (final r in tagged) {
      final m = Map<String, dynamic>.from(r as Map);
      if (m['status'] != 'pending') continue;
      final key =
          '${m['buyer_id']}|${m['live_item_id']}';
      byBuyerItem[key] = (byBuyerItem[key] ?? 0) + 1;
    }
    for (final e in byBuyerItem.entries) {
      if (e.value > 1) {
        issues.add(ValidationIssue(
          'error',
          'Reservas pending duplicadas para ${e.key} (count=${e.value})',
        ));
      }
    }
  }

  static void _stockNonNegative(
    Map<String, dynamic> after,
    List<ValidationIssue> issues,
  ) {
    final items = (after['live_items'] as List?) ?? [];
    for (final it in items) {
      final m = Map<String, dynamic>.from(it as Map);
      final id = m['id']?.toString() ?? '';
      final qty = m['quantity'];
      if (qty is num && qty < 0) {
        issues.add(ValidationIssue(
          'error',
          'Stock negativo live_item $id quantity=$qty',
        ));
      }
    }
  }

  static void _raffles(
    Map<String, dynamic> after,
    List<ValidationIssue> issues,
  ) {
    final winners = (after['live_raffle_winners'] as List?) ?? [];
    final entries = (after['live_raffle_entries'] as List?) ?? [];
    final entryUserIds =
        entries.map((e) => Map<String, dynamic>.from(e as Map)['user_id']).toSet();

    for (final w in winners) {
      final m = Map<String, dynamic>.from(w as Map);
      final uid = m['user_id']?.toString();
      if (uid != null && !entryUserIds.contains(uid)) {
        issues.add(ValidationIssue(
          'error',
          'Vencedor rifa $uid não está nos participantes',
        ));
      }
    }

    // Duplicados join por user/raffle
    final seen = <String>{};
    for (final e in entries) {
      final m = Map<String, dynamic>.from(e as Map);
      final key = '${m['raffle_id']}|${m['user_id']}';
      if (seen.contains(key)) {
        issues.add(ValidationIssue(
          'error',
          'Entrada rifa duplicada $key',
        ));
      }
      seen.add(key);
    }
  }

  static void _ordersZeroPrice(
    Map<String, dynamic> after,
    List<ValidationIssue> issues,
  ) {
    final orders = (after['live_orders'] as List?) ??
        (after['orders'] as List?) ??
        [];
    for (final o in orders) {
      final m = Map<String, dynamic>.from(o as Map);
      final pt = m['price_total'];
      final status = m['status']?.toString() ?? '';
      if (pt is num &&
          pt <= 0 &&
          status != 'cancelado' &&
          status != 'cancelled') {
        issues.add(ValidationIssue(
          'error',
          'Order ${m['id']} com price_total=$pt indevido',
        ));
      }
    }
  }

  static void _orphanReservations(
    Map<String, dynamic> after,
    List<ValidationIssue> issues,
  ) {
    final rows = (after['live_reservation_requests'] as List?) ?? [];
    final itemIds = ((after['live_items'] as List?) ?? [])
        .map((it) => Map<String, dynamic>.from(it as Map)['id']?.toString())
        .whereType<String>()
        .toSet();

    for (final r in rows) {
      final m = Map<String, dynamic>.from(r as Map);
      final itemId = m['live_item_id']?.toString();
      if (itemId != null &&
          itemId.isNotEmpty &&
          !itemIds.contains(itemId) &&
          m['status'] == 'pending') {
        issues.add(ValidationIssue(
          'warn',
          'Reserva órfã ${m['id']} → live_item inexistente $itemId',
        ));
      }
    }
  }

  static void _appLogsSevere(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
    List<ValidationIssue> issues,
  ) {
    final beforeLogs = ((before['app_logs_recent'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map)['id'])
        .toSet();
    final afterLogs = (after['app_logs_recent'] as List?) ?? [];
    for (final log in afterLogs) {
      final m = Map<String, dynamic>.from(log as Map);
      if (beforeLogs.contains(m['id'])) continue;
      final cat = m['category']?.toString().toLowerCase() ?? '';
      final msg = m['error_message']?.toString().toLowerCase() ?? '';
      if (cat.contains('fatal') ||
          cat.contains('crash') ||
          msg.contains('fatal')) {
        issues.add(ValidationIssue(
          'error',
          'app_logs grave novo: ${m['id']} $cat',
        ));
      }
    }
  }
}
