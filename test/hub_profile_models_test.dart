import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/hub/data/hub_models.dart';

void main() {
  group('HubProfile.fromMap', () {
    test('mapeia follower_count e hub_bio', () {
      final p = HubProfile.fromMap({
        'id': 'p1',
        'handle': 'maria',
        'full_name': 'Maria Silva',
        'follower_count': 1250,
        'hub_bio': '  Roupa vintage no Porto.  ',
      });
      expect(p.followerCount, 1250);
      expect(p.hubBio, '  Roupa vintage no Porto.  ');
      expect(p.hasAboutSection, isTrue);
    });

    test('defaults quando campos ausentes', () {
      final p = HubProfile.fromMap({
        'id': 'p1',
        'handle': 'maria',
        'full_name': 'Maria',
      });
      expect(p.followerCount, 0);
      expect(p.hubBio, isNull);
      expect(p.hasAboutSection, isFalse);
    });
  });

  group('HubProfileBundle', () {
    test('pastLives inclui ended e live encerrada (live + is_active false)', () {
      final bundle = HubProfileBundle(
        profile: const HubProfile(
          id: 'p1',
          handle: 'x',
          fullName: 'X',
        ),
        lives: [
          HubLive(
            id: 'l1',
            sellerId: 'p1',
            sellerHandle: 'x',
            status: 'live',
            isActive: true,
          ),
          HubLive(
            id: 'l2',
            sellerId: 'p1',
            sellerHandle: 'x',
            status: 'ended',
            muxVodPlaybackId: 'vod1',
          ),
          HubLive(
            id: 'l3',
            sellerId: 'p1',
            sellerHandle: 'x',
            status: 'live',
            isActive: false,
          ),
        ],
        products: const [],
        reviews: const [],
      );
      expect(bundle.activeLive?.id, 'l1');
      expect(bundle.pastLives.map((l) => l.id).toList(), ['l2', 'l3']);
    });
  });
}
