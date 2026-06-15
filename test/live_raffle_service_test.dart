import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/utils/live_raffle_service.dart';

void main() {
  group('LiveRaffleService.formatCountdown', () {
    test('mm:ss abaixo de 1h', () {
      expect(LiveRaffleService.formatCountdown(125), '02:05');
      expect(LiveRaffleService.formatCountdown(0), '00:00');
    });

    test('horas quando >= 60 min', () {
      expect(LiveRaffleService.formatCountdown(3661), '1h 01m');
    });
  });

  group('LiveRaffleState.fromRpc', () {
    test('sem rifa', () {
      final s = LiveRaffleState.fromRpc({'ok': true, 'has_raffle': false});
      expect(s.hasRaffle, isFalse);
    });

    test('rifa activa com timer', () {
      final s = LiveRaffleState.fromRpc({
        'ok': true,
        'has_raffle': true,
        'raffle': {
          'id': 'r1',
          'live_id': 'l1',
          'title': 'Vestido vintage',
          'status': 'active',
          'has_timer': true,
          'seconds_left': 90,
          'winner_count': 1,
        },
        'viewer': {'joined': true, 'ticket_balance': 1},
        'winners': [],
      });
      expect(s.hasRaffle, isTrue);
      expect(s.raffle?.title, 'Vestido vintage');
      expect(s.raffle?.hasTimer, isTrue);
      expect(s.raffle?.secondsLeft, 90);
      expect(s.viewer.ticketBalance, 1);
    });

    test('bonus flags follow e share', () {
      final s = LiveRaffleState.fromRpc({
        'ok': true,
        'has_raffle': true,
        'raffle': {
          'id': 'r3',
          'live_id': 'l1',
          'title': 'Colar',
          'status': 'active',
          'has_timer': false,
          'winner_count': 1,
        },
        'viewer': {
          'joined': true,
          'ticket_balance': 3,
          'follow_bonus_claimed': true,
          'share_bonus_claimed': false,
        },
        'winners': [],
      });
      expect(s.viewer.followBonusClaimed, isTrue);
      expect(s.viewer.shareBonusClaimed, isFalse);
      expect(s.viewer.ticketBalance, 3);
    });

    test('leaderboard e purchase bonus', () {
      final s = LiveRaffleState.fromRpc({
        'ok': true,
        'has_raffle': true,
        'raffle': {
          'id': 'r4',
          'live_id': 'l1',
          'title': 'Pack',
          'status': 'active',
          'has_timer': false,
          'winner_count': 1,
          'show_public_leaderboard': true,
        },
        'viewer': {
          'joined': true,
          'ticket_balance': 4,
          'purchase_bonus_claimed': true,
        },
        'leaderboard': [
          {
            'rank': 1,
            'user_id': 'u1',
            'display_name': 'Ana',
            'ticket_balance': 5,
          },
          {
            'rank': 2,
            'user_id': 'u2',
            'display_name': 'Bea',
            'ticket_balance': 3,
          },
        ],
        'winners': [],
      });
      expect(s.raffle?.showPublicLeaderboard, isTrue);
      expect(s.viewer.purchaseBonusClaimed, isTrue);
      expect(s.leaderboard, hasLength(2));
      expect(s.leaderboard.first.displayName, 'Ana');
      expect(s.leaderboard.first.ticketBalance, 5);
    });

    test('rifa sem timer', () {
      final s = LiveRaffleState.fromRpc({
        'ok': true,
        'has_raffle': true,
        'raffle': {
          'id': 'r2',
          'live_id': 'l1',
          'title': 'Brincos',
          'status': 'active',
          'has_timer': false,
          'winner_count': 2,
        },
        'viewer': {'joined': false, 'ticket_balance': 0},
        'winners': [],
      });
      expect(s.raffle?.hasTimer, isFalse);
      expect(s.raffle?.secondsLeft, isNull);
    });
  });

  group('LiveRaffleShareClaimResult.fromRpc', () {
    test('ok com duplicate', () {
      final r = LiveRaffleShareClaimResult.fromRpc({
        'ok': true,
        'duplicate': true,
        'ticket_balance': 2,
      });
      expect(r.ok, isTrue);
      expect(r.duplicate, isTrue);
      expect(r.ticketBalance, 2);
    });
  });
}
