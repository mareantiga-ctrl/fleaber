import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/hub/data/hub_models.dart';
import 'package:fleaber/utils/live_row_playback_status.dart';

void main() {
  group('Live ended status (Hub + player alinhados)', () {
    test('live + is_active=false → ended (feed Hub gravado)', () {
      const live = HubLive(
        id: '1',
        sellerId: 's',
        sellerHandle: 'demo',
        status: 'live',
        isActive: false,
        muxVodPlaybackId: 'vod-1',
      );
      expect(live.isLiveNow, isFalse);
      expect(live.isEnded, isTrue);
      expect(hubLiveDisplayStatus(live), HubLiveDisplayStatus.recorded);
      expect(liveRowIsEnded(status: 'live', isActive: false), isTrue);
      expect(liveRowIsLiveNow(status: 'live', isActive: false), isFalse);
    });

    test('live + is_active null → não ended (player live activa)', () {
      expect(liveRowIsEnded(status: 'live', isActive: null), isFalse);
      expect(liveRowIsLiveNow(status: 'live', isActive: null), isTrue);
    });

    test('status ended → ended', () {
      const live = HubLive(
        id: '2',
        sellerId: 's',
        sellerHandle: 'demo',
        status: 'ended',
        muxVodPlaybackId: 'vod-2',
      );
      expect(live.isEnded, isTrue);
      expect(hubLiveDisplayStatus(live), HubLiveDisplayStatus.recorded);
      expect(liveRowIsEnded(status: 'ended', isActive: true), isTrue);
    });

    test('live activa real → AO VIVO', () {
      const live = HubLive(
        id: '3',
        sellerId: 's',
        sellerHandle: 'demo',
        status: 'live',
        isActive: true,
        muxPlaybackId: 'pb-live',
      );
      expect(live.isLiveNow, isTrue);
      expect(hubLiveDisplayStatus(live), HubLiveDisplayStatus.live);
      expect(liveRowIsEnded(status: 'live', isActive: true), isFalse);
    });

    test('ended sem VOD → GRAVAÇÃO A PREPARAR', () {
      const live = HubLive(
        id: '4',
        sellerId: 's',
        sellerHandle: 'demo',
        status: 'ended',
      );
      expect(hubLiveDisplayStatus(live), HubLiveDisplayStatus.preparing);
    });
  });
}
