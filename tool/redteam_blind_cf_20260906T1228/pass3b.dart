/// REDTEAM_BLIND_CF_LIVE_POS_BXCC_v1 — pass3b Mux irmãs + PI JWT.
/// Staging only. No fixes.
import 'dart:io';

import '_rtcf.dart';

Future<void> main() async {
  final c = Rtcf.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2(hubPublished: false);

  const fakePb = 'CF3BPLAY1228fake0001';
  final liveSched = await c.createLive(
    seller: c.seller2Id,
    title: '$prefix p3b sched',
    status: 'scheduled',
    active: false,
    extra: {
      'playback_id': fakePb,
      'livekit_room_name': 'CF3BROOM1228',
      'mux_playback_id': 'CF3BMUX1228fake0001',
    },
  );
  final liveEnded = await c.createLive(
    seller: c.seller2Id,
    title: '$prefix p3b ended',
    status: 'ended',
    active: false,
    extra: {
      'playback_id': 'CF3BENDED1228fake01',
      'mux_vod_playback_id': 'CF3BVOD1228fake0001',
    },
  );
  final liveActiveUnpub = await c.createLive(
    seller: c.seller2Id,
    title: '$prefix p3b live unpub',
    extra: {
      'playback_id': 'CF3BLIVE1228fake0001',
      'mux_playback_id': 'CF3BLIVEMUX1228fk01',
    },
  );

  Future<void> probe(String? liveId, String col, String tag) async {
    if (liveId == null) return;
    final h = await c.rest(
      'GET',
      'lives?id=eq.$liveId&select=id,status,is_active,$col',
      jwt: c.buyerJwt,
    );
    final val = h.map?[col]?.toString();
    final leaked = h.ok && val != null && val.isNotEmpty;
    if (leaked) {
      c.hold(
        id: 'p3b.$tag',
        lens: 'CF7',
        severity: 'P2',
        title: 'buyer lê $col ($tag)',
        actor: 'buyer JWT',
        pre: 'seller2 unpublished',
        repro: 'GET lives select=$col',
        expected: 'vazio/403',
        obtained: h.brief,
        evidence: {'col': col, 'val': val, 'live': liveId},
      );
    } else {
      c.block('p3b.$tag', 'CF7', 'não lê $col $tag', h.brief);
    }
  }

  await probe(liveSched, 'playback_id', 'sched.playback_id');
  await probe(liveSched, 'livekit_room_name', 'sched.room');
  await probe(liveEnded, 'playback_id', 'ended.playback_id');
  await probe(liveActiveUnpub, 'playback_id', 'live.playback_id');

  final hub = await c.rest(
    'GET',
    'hub_lives_public?id=eq.$liveActiveUnpub&select=id,mux_playback_id,status',
    jwt: c.buyerJwt,
  );
  c.note('p3b.hub.unpub', 'Hub unpublished', hub.brief, lens: 'CF7');

  // Buyer PATCH PI em produto marketplace (não live exhausted).
  final sku = await c.createProduct(
    title: '$prefix p3b mkt',
    qty: 3,
    live: false,
  );
  if (sku != null) {
    final ord = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': sku,
      'quantity': 1,
      'price_total': 9,
      'status': 'pendente',
      'payment_method': 'MB WAY',
      'shipping_method': 'entrega em mão',
    });
    if (ord.firstId != null) c.createdOrderIds.add(ord.firstId!);
    c.note('p3b.order.insert', 'marketplace pendente', ord.brief, lens: 'CF1');
    if (ord.ok && ord.firstId != null) {
      final patch = await c.rest(
        'PATCH',
        'orders?id=eq.${ord.firstId}',
        jwt: c.buyerJwt,
        body: {
          'stripe_payment_intent_id': 'pi_rtcf_stolen_mkt_$stamp',
          'status': 'pago',
          'amount_paid_cents': 900,
        },
      );
      final after = await c.rest(
        'GET',
        'orders?id=eq.${ord.firstId}&select=id,status,stripe_payment_intent_id,amount_paid_cents',
        service: true,
      );
      final stole = after.map?['status']?.toString() == 'pago' ||
          '${after.map?['stripe_payment_intent_id']}'.contains('stolen');
      if (patch.ok && stole) {
        c.hold(
          id: 'p3b.buyer.patch.pi',
          lens: 'CF1',
          severity: 'P0',
          title: 'Buyer PATCH order marketplace para pago+PI',
          actor: 'buyer JWT',
          pre: 'order pendente própria',
          repro: 'PATCH status=pago + stripe_payment_intent_id',
          expected: 'colunas financeiras imutáveis',
          obtained: {'patch': patch.brief, 'row': after.map},
        );
      } else {
        c.block('p3b.buyer.patch.pi', 'CF1', 'buyer não marca pago/PI',
            {'patch': patch.brief, 'row': after.map});
      }
    }
  }

  await dumpJson('${outDir()}/pass3b.json', {
    'auditor': 'REDTEAM_BLIND_CF_LIVE_POS_BXCC_v1',
    'prefix': prefix,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
      'pass3b done findings=${c.findings.length} blocked=${c.blocked.length}');
}
