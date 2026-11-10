import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/utils/live_catalog_stock_service.dart';
import 'package:fleaber/utils/live_raffle_service.dart';

/// Espelho da regra SQL: hold = winner_count (≥1) por rifa active/closed/drawn.
/// Ex.: total 2 + rifa 1 vencedor → hold 1 → available 1 (não zera o artigo).
int rafflePrizeHoldQty({
  required String? liveItemId,
  required String raffleStatus,
  int winnerCount = 1,
}) {
  if (liveItemId == null || liveItemId.trim().isEmpty) return 0;
  if (raffleStatus == 'active' ||
      raffleStatus == 'closed' ||
      raffleStatus == 'drawn') {
    return winnerCount < 1 ? 1 : winnerCount;
  }
  // cancelled / draft → stock volta
  return 0;
}

int availableAfterRaffleHold({
  required int totalQty,
  required int blockedQty,
  required int reservedAcceptedQty,
  required int pendingBagQty,
  required int raffleHoldQty,
  int soldConvertedQty = 0,
}) {
  var available =
      totalQty - blockedQty - reservedAcceptedQty - pendingBagQty - raffleHoldQty;
  if (soldConvertedQty >= (totalQty < 1 ? 1 : totalQty)) return 0;
  if (available < 0) return 0;
  return available;
}

void main() {
  group('AM5 raffle prize stock hold', () {
    test('active/closed/drawn retêm winner_count; cancelled devolve', () {
      expect(
        rafflePrizeHoldQty(liveItemId: 'li1', raffleStatus: 'active'),
        1,
      );
      expect(
        rafflePrizeHoldQty(
          liveItemId: 'li1',
          raffleStatus: 'active',
          winnerCount: 2,
        ),
        2,
      );
      expect(
        rafflePrizeHoldQty(liveItemId: 'li1', raffleStatus: 'closed'),
        1,
      );
      expect(
        rafflePrizeHoldQty(liveItemId: 'li1', raffleStatus: 'drawn'),
        1,
      );
      expect(
        rafflePrizeHoldQty(liveItemId: 'li1', raffleStatus: 'cancelled'),
        0,
      );
      expect(
        rafflePrizeHoldQty(liveItemId: null, raffleStatus: 'active'),
        0,
      );
    });

    test('total 2 + hold 1 → available 1 (não 0)', () {
      final hold = rafflePrizeHoldQty(
        liveItemId: 'li1',
        raffleStatus: 'active',
        winnerCount: 1,
      );
      final avail = availableAfterRaffleHold(
        totalQty: 2,
        blockedQty: 0,
        reservedAcceptedQty: 0,
        pendingBagQty: 0,
        raffleHoldQty: hold,
      );
      expect(hold, 1);
      expect(avail, 1);
    });

    test('total 1 + hold 1 → available 0', () {
      final avail = availableAfterRaffleHold(
        totalQty: 1,
        blockedQty: 0,
        reservedAcceptedQty: 0,
        pendingBagQty: 0,
        raffleHoldQty: 1,
      );
      expect(avail, 0);
    });

    test('cancelar rifa → hold 0 → available volta', () {
      final hold = rafflePrizeHoldQty(
        liveItemId: 'li1',
        raffleStatus: 'cancelled',
      );
      final avail = availableAfterRaffleHold(
        totalQty: 1,
        blockedQty: 0,
        reservedAcceptedQty: 0,
        pendingBagQty: 0,
        raffleHoldQty: hold,
      );
      expect(avail, 1);
    });

    test('snapshot RPC parseia raffle_hold_qty', () {
      final s = LiveCatalogStockSnapshot.fromRpc({
        'ok': true,
        'live_item_id': 'li1',
        'live_id': 'l1',
        'item_kind': 'live_only',
        'total_qty': 1,
        'blocked_qty': 0,
        'reserved_accepted_qty': 0,
        'pending_bag_qty': 0,
        'sold_converted_qty': 0,
        'raffle_hold_qty': 1,
        'available_qty': 0,
      });
      expect(s.raffleHoldQty, 1);
      expect(s.availableQty, 0);
    });
  });

  group('Pós-sorteio state merge', () {
    test('drawn remoto substitui active local', () {
      final local = LiveRaffleState.fromRpc({
        'ok': true,
        'has_raffle': true,
        'raffle': {
          'id': 'r1',
          'live_id': 'l1',
          'title': 'Prémio',
          'status': 'active',
          'winner_count': 1,
          'has_timer': false,
        },
        'viewer': {'joined': true, 'ticket_balance': 2},
        'winners': [],
      });
      final remote = LiveRaffleState.fromRpc({
        'ok': true,
        'has_raffle': true,
        'raffle': {
          'id': 'r1',
          'live_id': 'l1',
          'title': 'Prémio',
          'status': 'drawn',
          'winner_count': 1,
          'has_timer': false,
        },
        'viewer': {
          'joined': true,
          'ticket_balance': 2,
          'is_winner': true,
        },
        'winners': [
          {
            'rank': 1,
            'user_id': 'u1',
            'display_name': 'Marina',
            'tickets_at_draw': 2,
          },
        ],
      });
      final sticky = local.mergePreferringLocalViewer(remote);
      final rank = (String s) =>
          s == 'drawn' ? 3 : (s == 'closed' ? 2 : (s == 'active' ? 1 : 0));
      final merged = rank(remote.raffle!.status) >= rank(local.raffle!.status)
          ? remote.copyWith(viewer: sticky.viewer)
          : sticky;
      expect(merged.raffle!.isDrawn, isTrue);
      expect(merged.viewer.isWinner, isTrue);
      expect(merged.winners, isNotEmpty);
      expect(merged.viewer.ticketBalance, 2);
    });
  });
}
