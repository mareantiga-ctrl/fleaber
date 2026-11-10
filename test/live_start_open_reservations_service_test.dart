import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/live_start_open_reservations_service.dart';

void main() {
  group('orderStatusIsOpenForStartWarning', () {
    test('estados abertos V1', () {
      expect(orderStatusIsOpenForStartWarning('reserva_pendente'), isTrue);
      expect(orderStatusIsOpenForStartWarning('reservado'), isTrue);
      expect(orderStatusIsOpenForStartWarning('aguarda_confirmacao'), isTrue);
      expect(orderStatusIsOpenForStartWarning('pendente'), isTrue);
    });

    test('estados fechados V1', () {
      expect(orderStatusIsOpenForStartWarning('pago'), isFalse);
      expect(orderStatusIsOpenForStartWarning('enviado'), isFalse);
      expect(orderStatusIsOpenForStartWarning('cancelado'), isFalse);
      expect(orderStatusIsOpenForStartWarning('converted'), isFalse);
    });
  });

  group('liveRequestIsOpenForStartWarning', () {
    test('pending e accepted contam', () {
      expect(
        liveRequestIsOpenForStartWarning(status: 'pending'),
        isTrue,
      );
      expect(
        liveRequestIsOpenForStartWarning(status: 'accepted'),
        isTrue,
      );
    });

    test('bag_removed não conta', () {
      expect(
        liveRequestIsOpenForStartWarning(
          status: 'pending',
          notes: 'bag_removed by buyer',
        ),
        isFalse,
      );
    });

    test('converted não conta', () {
      expect(
        liveRequestIsOpenForStartWarning(status: 'converted'),
        isFalse,
      );
    });
  });

  group('LiveStartOpenReservationsReport.fromRpc', () {
    test('parse payload com itens e resumo', () {
      final report = LiveStartOpenReservationsReport.fromRpc({
        'ok': true,
        'summary': {
          'items_with_open': 1,
          'total_reservations': 2,
          'total_units': 3,
        },
        'items': [
          {
            'live_item_id': 'item-1',
            'title': 'Puzzle',
            'ref_code': 'A12',
            'photo_url': 'https://example.com/p.jpg',
            'current_stock': 1,
            'reservation_count': 2,
            'reserved_units': 3,
            'stock_warning': true,
            'origins': ['Direto anterior', 'Marketplace'],
            'reservations': [
              {
                'kind': 'live_request',
                'id': 'r1',
                'buyer_id': 'b1',
                'buyer_name': 'Marina',
                'status': 'pending',
                'quantity': 2,
                'queue_position': 1,
                'created_at': '2026-05-28T10:00:00Z',
                'origin': 'Direto anterior',
              },
              {
                'kind': 'order',
                'id': 'o1',
                'buyer_name': 'João',
                'status': 'reserva_pendente',
                'quantity': 1,
                'origin': 'Marketplace',
              },
            ],
          },
        ],
      });

      expect(report.summary.itemsWithOpen, 1);
      expect(report.summary.totalReservations, 2);
      expect(report.summary.totalUnits, 3);
      expect(report.items, hasLength(1));
      expect(report.items.first.stockWarning, isTrue);
      expect(report.items.first.reservations, hasLength(2));
      expect(report.items.first.reservations.first.statusLabel, 'Pendente');
      expect(
        report.items.first.reservations.last.statusLabel,
        'Pedido de reserva',
      );
    });

    test('payload vazio → sem itens', () {
      final report = LiveStartOpenReservationsReport.fromRpc({
        'ok': true,
        'summary': {
          'items_with_open': 0,
          'total_reservations': 0,
          'total_units': 0,
        },
        'items': [],
      });
      expect(report.summary.hasOpen, isFalse);
      expect(report.items, isEmpty);
    });
  });

  group('summarizeOpenReservationItems', () {
    test('agrega totais', () {
      const item = LiveStartOpenReservationsItem(
        liveItemId: 'x',
        title: 'T',
        refCode: 'R1',
        currentStock: 2,
        reservationCount: 2,
        reservedUnits: 4,
        stockWarning: true,
        origins: ['Gravado'],
        reservations: [],
      );
      final s = summarizeOpenReservationItems([item, item]);
      expect(s.itemsWithOpen, 2);
      expect(s.totalReservations, 4);
      expect(s.totalUnits, 8);
    });
  });
}
