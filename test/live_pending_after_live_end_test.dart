import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/utils/live_reservation_queue_service.dart';
import 'package:fleaber/utils/live_start_open_reservations_service.dart';

/// Contrato actual (sem alterar SQL): reservas pending sobrevivem ao
/// terminar o directo. O saco e o aviso do próximo directo continuam a
/// vê-las. A expiração automática aos 45 min não está implementada no
/// cliente — só o campo `expires_at` é preenchido no insert.
void main() {
  group('Reservas pending depois da live ended', () {
    test('pending continua no saco (não depende do estado da live)', () {
      expect(
        LiveReservationQueueService.buyerBagIsActionable('pending'),
        isTrue,
      );
      expect(
        LiveReservationQueueService.buyerBagIsActionable('accepted'),
        isTrue,
      );
      expect(
        LiveReservationQueueService.buyerBagIsActionable('expired'),
        isFalse,
      );
      expect(
        LiveReservationQueueService.buyerBagIsActionable('converted'),
        isFalse,
      );
    });

    test('próximo directo avisa reservas abertas de lives anteriores', () {
      expect(
        liveRequestIsOpenForStartWarning(status: 'pending'),
        isTrue,
      );
      expect(
        liveRequestIsOpenForStartWarning(status: 'accepted'),
        isTrue,
      );
      expect(
        liveRequestIsOpenForStartWarning(status: 'expired'),
        isFalse,
      );
    });

    test('origem «Direto anterior» no aviso de início', () {
      final report = LiveStartOpenReservationsReport.fromRpc({
        'ok': true,
        'summary': {
          'items_with_open': 1,
          'total_reservations': 1,
          'total_units': 2,
        },
        'items': [
          {
            'live_item_id': 'item-1',
            'title': 'Artigo B',
            'reservation_count': 1,
            'reserved_units': 2,
            'origins': ['Direto anterior'],
            'reservations': [
              {
                'kind': 'live_request',
                'id': 'r1',
                'buyer_name': 'Comprador',
                'status': 'pending',
                'quantity': 2,
              },
            ],
          },
        ],
      });
      expect(report.summary.hasOpen, isTrue);
      expect(report.summary.totalUnits, 2);
      expect(report.items.single.origins, ['Direto anterior']);
    });
  });
}
