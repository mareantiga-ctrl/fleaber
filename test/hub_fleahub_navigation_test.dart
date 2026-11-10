import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/hub/data/hub_models.dart';
import 'package:fleaber/hub/hub_navigation.dart';
import 'package:fleaber/hub/routing/hub_reserved_slugs.dart';
import 'package:fleaber/hub/routing/hub_route_paths.dart';

void main() {
  group('FleaHub landing navigation', () {
    test('rota canónica /fleahub', () {
      expect(HubRoutePaths.landing, '/fleahub');
    });

    test('fleahub não é handle Hub', () {
      expect(HubReservedSlugs.blocksHubHandle('fleahub'), isTrue);
      expect(HubReservedSlugs.blocksHubHandle('FleaHub'), isTrue);
    });
  });

  group('Hub 404 paths (B3)', () {
    test('suffix inválido sob handle', () {
      expect(HubNavigation.isUnhandledHubPath('/maria-silva/liv'), isTrue);
      expect(HubNavigation.isUnhandledHubPath('/maria-silva/live'), isFalse);
    });

    test('rotas app não são Hub 404', () {
      expect(HubNavigation.isUnhandledHubPath('/login'), isFalse);
      expect(HubNavigation.isUnhandledHubPath('/login/extra'), isFalse);
    });
  });

  group('Hub live badges (B12)', () {
    test('estados AO VIVO / GRAVADO / preparar', () {
      const liveNow = HubLive(
        id: '1',
        sellerId: 's',
        sellerHandle: 'demo',
        status: 'live',
        isActive: true,
        muxPlaybackId: 'pb',
      );
      const recorded = HubLive(
        id: '2',
        sellerId: 's',
        sellerHandle: 'demo',
        status: 'ended',
        muxVodPlaybackId: 'vod',
      );
      const preparing = HubLive(
        id: '3',
        sellerId: 's',
        sellerHandle: 'demo',
        status: 'ended',
      );

      expect(hubLiveDisplayStatus(liveNow), HubLiveDisplayStatus.live);
      expect(hubLiveDisplayStatus(recorded), HubLiveDisplayStatus.recorded);
      expect(hubLiveDisplayStatus(preparing), HubLiveDisplayStatus.preparing);
    });
  });
}
