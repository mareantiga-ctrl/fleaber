import 'package:flutter/foundation.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/live_reservation_queue_service.dart';

import 'data/hub_models.dart';

/// Modo demo PS/Facebook — staging/debug only (H4). Sem API real.
abstract final class HubPsDemo {
  static const notesMarker = 'hub_ps_demo';

  /// `?ps_demo=1` activo só em debug/profile (nunca release store).
  static bool isQueryActive(String? raw) {
    if (raw != '1') return false;
    return kDebugMode || kProfileMode;
  }

  /// Cria reservas fictícias `facebook_manual` para a buyer actual (idempotente).
  static Future<int> ensureDemoReservations({
    required String liveId,
    required String sellerId,
    required List<HubLiveItem> items,
  }) async {
    final uid = currentUserUid.trim();
    if (uid.isEmpty || liveId.isEmpty || items.isEmpty) return 0;

    final existing = await LiveReservationRequestsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('live_id', liveId)
          .eqOrNull('buyer_id', uid)
          .eqOrNull('source', 'facebook_manual'),
      limit: 20,
    );
    final demoRows = existing
        .where((r) => (r.notes ?? '').contains(notesMarker))
        .toList();
    if (demoRows.length >= 2) return demoRows.length;

    final svc = LiveReservationQueueService();
    var created = 0;
    final targets = items.take(2).toList();
    for (final item in targets) {
      if (demoRows.any((e) => e.liveItemId == item.id)) continue;
      try {
        final row = await svc.createRequest(
          liveId: liveId,
          liveItemId: item.id,
          sellerId: sellerId,
          source: LiveReservationSource.facebookManual,
          notes: notesMarker,
        );
        if (row != null) created++;
      } catch (_) {}
    }
    return demoRows.length + created;
  }
}
