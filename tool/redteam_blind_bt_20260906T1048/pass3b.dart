/// REDTEAM_BLIND_BT_LIVE_POS_BLBQ_v1 — pass3b Mux colunas + FOMO visível.
/// Staging only. No fixes.
import 'dart:io';

import '_rtbt.dart';

Future<void> main() async {
  final c = Rtbt.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureSeller2();

  const fakePlayback = 'RTBTfakePlaybk22222222222222222222';
  const fakeStream = 'RTBTfakeStreamKeyColProbe';
  const fakeMuxLive = 'RTBTfakeMuxLiveIdColProbexxxx';
  const fakeVod = 'RTBTfakeVodPlaybackColProbexxxx';

  final liveId = await c.createLive(
    title: '$prefix mux cols',
    extra: {
      'mux_playback_id': fakePlayback,
      'mux_stream_key': fakeStream,
      'mux_live_id': fakeMuxLive,
      'mux_vod_playback_id': fakeVod,
      'mux_asset_id': 'RTBTfakeAsset2',
      'stream_key': fakeStream,
      'playback_id': fakePlayback,
    },
  );
  if (liveId == null) {
    stderr.writeln('no live');
    exit(4);
  }

  Future<void> col({
    required String id,
    required String actor,
    required String select,
    String? jwt,
    bool service = false,
  }) async {
    final h = await c.rest(
      'GET',
      'lives?id=eq.$liveId&select=$select',
      jwt: jwt,
      service: service,
    );
    final body = h.body.toLowerCase();
    final isStream = select.contains('stream_key');
    final isMuxLive = select.contains('mux_live_id');
    final isVod = select.contains('mux_vod');
    final isAsset = select.contains('mux_asset');
    final leakedStream = h.ok && body.contains('rtbtfakestream');
    final leakedId = h.ok &&
        (body.contains('rtbtfakemuxlive') ||
            body.contains('rtbtfakevod') ||
            body.contains('rtbtfakeasset'));
    if (actor != 'owner' && actor != 'service' && leakedStream && isStream) {
      c.hold(
        id: id,
        lens: 'BT7',
        severity: 'P1',
        title: '$actor leu stream key da live alheia ($select)',
        actor: actor,
        pre: 'live broadcasting; GRANT/RLS Mux',
        repro: 'GET lives?id=eq.&select=$select',
        expected: '401/403 ou coluna ausente/null',
        obtained: h.brief,
      );
    } else if (actor != 'owner' &&
        actor != 'service' &&
        leakedId &&
        (isMuxLive || isVod || isAsset) &&
        h.ok) {
      c.hold(
        id: id,
        lens: 'BT7',
        severity: 'P2',
        title: '$actor leu $select da live alheia',
        actor: actor,
        pre: 'revoke BLBQ não cobre mux_live_id; VOD só ended na view',
        repro: 'GET lives select=$select',
        expected: 'coluna oculta a não-owner / VOD null enquanto live',
        obtained: h.brief,
      );
    } else {
      c.note(id, '$actor $select', h.brief, lens: 'BT7');
    }
  }

  for (final sel in [
    'id,status,is_active',
    'id,mux_playback_id',
    'id,mux_vod_playback_id',
    'id,mux_asset_id',
    'id,mux_stream_key',
    'id,mux_live_id',
    'id,stream_key',
    'id,playback_id',
  ]) {
    await col(id: 'p3b.anon.$sel', actor: 'anon', select: sel);
    await col(
      id: 'p3b.buyer.$sel',
      actor: 'buyer',
      select: sel,
      jwt: c.buyerJwt,
    );
    await col(
      id: 'p3b.s2.$sel',
      actor: 'seller2',
      select: sel,
      jwt: c.seller2Jwt,
    );
    await col(
      id: 'p3b.owner.$sel',
      actor: 'owner',
      select: sel,
      jwt: c.sellerJwt,
    );
  }

  final hub = await c.rest(
    'GET',
    'hub_lives_public?id=eq.$liveId&select=id,status,mux_playback_id,mux_vod_playback_id',
  );
  c.note('p3b.hub.anon', 'hub_lives_public anon', hub.brief, lens: 'BT7');
  if (hub.ok && hub.body.contains('RTBTfakeVod')) {
    c.hold(
      id: 'p3b.hub.vod.while.live',
      lens: 'BT7',
      severity: 'P2',
      title: 'hub_lives_public expôs VOD enquanto status=live',
      actor: 'anon',
      pre: 'view: VOD só ended',
      repro: 'GET hub_lives_public mux_vod_playback_id',
      expected: 'mux_vod_playback_id null',
      obtained: hub.brief,
    );
  }

  final resolve = await c.edge(
    'resolve-mux-playback',
    {'live_id': liveId},
    jwt: c.buyerJwt,
  );
  c.note('p3b.resolve.buyer', 'resolve-mux-playback buyer', resolve.brief,
      lens: 'BT7');
  if (resolve.ok && resolve.body.contains('RTBTfakeStream')) {
    c.hold(
      id: 'p3b.resolve.stream_key',
      lens: 'BT7',
      severity: 'P1',
      title: 'resolve-mux-playback devolveu stream key',
      actor: 'buyer JWT',
      pre: 'Edge só playback público',
      repro: 'POST resolve-mux-playback',
      expected: 'playback_id HLS, nunca stream_key',
      obtained: resolve.brief,
    );
  }

  // Owner PATCH colunas Mux vs título.
  final patchTitle = await c.rest(
    'PATCH',
    'lives?id=eq.$liveId',
    jwt: c.sellerJwt,
    body: {'title': '$prefix mux cols patched'},
  );
  c.note('p3b.owner.patch.title', 'owner PATCH title', patchTitle.brief,
      lens: 'BT7');
  final patchMux = await c.rest(
    'PATCH',
    'lives?id=eq.$liveId',
    jwt: c.sellerJwt,
    body: {'mux_playback_id': 'SHOULDNOTSTICK'},
  );
  final afterMux = await c.rest(
    'GET',
    'lives?id=eq.$liveId&select=id,mux_playback_id,title',
    service: true,
  );
  c.note('p3b.owner.patch.mux', 'owner PATCH mux_playback_id', {
    'patch': patchMux.brief,
    'row': afterMux.map,
  }, lens: 'BT7');
  if (patchMux.ok &&
      afterMux.map?['mux_playback_id']?.toString() == 'SHOULDNOTSTICK') {
    c.note('p3b.owner.can.write.mux', 'owner pode escrever mux_playback_id',
        afterMux.map,
        lens: 'BT7');
  }

  // FOMO visível para o comprador (impacto real do P2).
  final liveF = await c.createLive(title: '$prefix fomo vis');
  if (liveF != null) {
    final send = await c.rpc(
      'batata_live_system_message',
      {'p_live_id': liveF, 'p_body': 'esgotado', 'p_sender_label': 'Sistema'},
      jwt: c.sellerJwt,
    );
    final seen = await c.rest(
      'GET',
      'live_messages?live_id=eq.$liveF&kind=eq.system&select=id,body,kind&order=created_at.desc&limit=5',
      jwt: c.buyerJwt,
    );
    final visible = seen.ok && seen.body.contains('esgotado');
    if (send.map?['ok'] == true && visible) {
      c.note('p3b.fomo.buyer.sees', 'buyer vê system esgotado', seen.brief,
          lens: 'BT2');
    } else {
      c.note('p3b.fomo.buyer.sees.fail', 'buyer não viu ou rpc falhou', {
        'send': send.brief,
        'seen': seen.brief,
      }, lens: 'BT2');
    }
  }

  // Crossed hitch: checkout Edge usa qual product?
  final skuA = await c.createProduct(title: '$prefix cxA', qty: 1, live: true);
  final skuB = await c.createProduct(title: '$prefix cxB', qty: 1, live: true);
  final liveX = await c.createLive(title: '$prefix cx pay');
  if (skuA != null && skuB != null && liveX != null) {
    final lx1 = await c.createLiveItem(
      liveId: liveX,
      title: 'cx1',
      ref: 'RTBT-PAY1',
      kind: 'marketplace_product',
      productId: skuA,
      checkoutProductId: skuB,
    );
    if (lx1 != null) {
      final bag = await c.rest(
        'POST',
        'live_reservation_requests',
        jwt: c.buyerJwt,
        body: {
          'live_id': liveX,
          'live_item_id': lx1,
          'seller_id': c.sellerId,
          'buyer_id': c.buyerId,
          'requested_qty': 1,
          'source': 'fleaber_live',
          'status': 'pending',
        },
      );
      if (bag.firstId != null) c.createdResIds.add(bag.firstId!);
      if (bag.firstId != null) {
        await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.${bag.firstId}',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
      }
      final pay = await c.edge(
        'create-payment-intent',
        {
          'live_item_id': lx1,
          'live_id': liveX,
          'quantity': 1,
        },
        jwt: c.buyerJwt,
      );
      c.note('p3b.pay.crossed', 'create-payment-intent item A/checkout B',
          pay.brief,
          lens: 'BT8');
    }
  }

  await c.endAllCreatedLives();
  await dumpJson('${outDir()}/pass3b.json', {
    'prefix': prefix,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
      'PASS3b done findings=${c.findings.length} notes=${c.notes.length}');
}
