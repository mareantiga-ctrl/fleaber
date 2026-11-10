import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/hub/data/hub_models.dart';
import 'package:fleaber/hub/hub_urls.dart';
import 'package:fleaber/hub/routing/hub_route_paths.dart';

void main() {
  group('Gravados → Live routing', () {
    test('liveFor sem liveId — pickPrimaryLive (directo activo)', () {
      expect(
        HubRoutePaths.liveFor('maria-silva'),
        '/maria-silva/live',
      );
    });

    test('liveFor com liveId — gravação específica', () {
      const id = '6f324f6a-5357-4ea5-a718-f8825ef809e5';
      expect(
        HubRoutePaths.liveFor('maria-silva', liveId: id),
        '/maria-silva/live?liveId=$id',
      );
    });

    test('liveFor codifica liveId com caracteres especiais', () {
      final path = HubRoutePaths.liveFor('demo', liveId: 'a b+c');
      expect(path, startsWith('/demo/live?liveId='));
      expect(Uri.parse('http://x$path').queryParameters['liveId'], 'a b+c');
    });

    test('HubUrls.live com liveId — link partilhável gravado (hash P12)', () {
      const id = '6f324f6a-5357-4ea5-a718-f8825ef809e5';
      expect(
        HubUrls.live('maria-silva', liveId: id),
        'https://fleaber.pt/fleahub/index.html#/maria-silva/live?liveId=$id',
      );
    });
  });

  group('resolveLiveForPage (contrato)', () {
    const seller = 'seller-1';
    const liveA = HubLive(
      id: 'live-a',
      sellerId: seller,
      sellerHandle: 'demo',
      status: 'ended',
      muxVodPlaybackId: 'vod-a',
    );
    const liveB = HubLive(
      id: 'live-b',
      sellerId: seller,
      sellerHandle: 'demo',
      status: 'ended',
      muxVodPlaybackId: 'vod-b',
    );
    const liveOtherSeller = HubLive(
      id: 'live-x',
      sellerId: 'other-seller',
      sellerHandle: 'other',
      status: 'ended',
      muxVodPlaybackId: 'vod-x',
    );

    HubLive? pick({String? requestedId, HubLive? fetched, HubLive? primary}) {
      final requested = requestedId?.trim();
      if (requested != null && requested.isNotEmpty) {
        if (fetched != null && fetched.sellerId == seller) {
          return fetched;
        }
      }
      return primary;
    }

    test('card B pede live-b → abre live-b, não live-a', () {
      final resolved = pick(
        requestedId: liveB.id,
        fetched: liveB,
        primary: liveA,
      );
      expect(resolved?.id, liveB.id);
    });

    test('sem liveId → primary (directo activo)', () {
      final resolved = pick(requestedId: null, fetched: null, primary: liveA);
      expect(resolved?.id, liveA.id);
    });

    test('liveId de outra seller → fallback primary', () {
      final resolved = pick(
        requestedId: liveOtherSeller.id,
        fetched: liveOtherSeller,
        primary: liveA,
      );
      expect(resolved?.id, liveA.id);
    });
  });
}
