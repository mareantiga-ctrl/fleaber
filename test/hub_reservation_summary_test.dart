import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/backend/supabase/supabase.dart';
import 'package:fleaber/hub/hub_live_reservation_ui.dart';

void main() {
  group('HubReservationSummary', () {
    test('headline e subline', () {
      const s = HubReservationSummary(
        total: 3,
        inQueue: 1,
        confirmed: 2,
        pendingAwaiting: 0,
      );
      expect(s.headline, 'Tens 3 reservas');
      expect(s.subline, '1 em fila · 2 confirmadas');
    });

    test('sem reservas — vazio', () {
      const s = HubReservationSummary(
        total: 0,
        inQueue: 0,
        confirmed: 0,
        pendingAwaiting: 0,
      );
      expect(s.hasAny, isFalse);
      expect(s.headline, isEmpty);
    });
    test('hubCard copy urgente vs normal', () {
      const urgent = HubReservationSummary(
        total: 3,
        inQueue: 3,
        confirmed: 0,
        pendingAwaiting: 0,
        needsPayment: 2,
        duePayment: 2,
      );
      expect(urgent.hubCardTitle, 'Tens 3 reservas por concluir');
      expect(urgent.hubCardSubline, '3 em fila · 2 por pagar');
      expect(urgent.hubCardCta, 'Ver saco e pagar');

      const calm = HubReservationSummary(
        total: 3,
        inQueue: 3,
        confirmed: 0,
        pendingAwaiting: 0,
      );
      expect(calm.hubCardTitle, 'Tens 3 reservas');
      expect(calm.hubCardCta, 'Ver saco');
    });

    test('fromRows soma unidades (requestedQty), não linhas', () {
      final rows = [
        LiveReservationRequestsRow({
          'id': 'r1',
          'status': 'pending',
          'requested_qty': 3,
          'queue_position': 1,
        }),
      ];
      final s = HubReservationSummary.fromRows(rows);
      expect(s.total, 3);
      expect(s.inQueue, 3);
      expect(s.headline, 'Tens 3 reservas');
    });
  });
}
