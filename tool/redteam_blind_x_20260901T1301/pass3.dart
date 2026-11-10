/// REDTEAM_BLIND_X pass3 — helper inflate/mark_sold + raffle share.
/// Staging only. No production. No Fase 4. No fixes.
import 'dart:io';

import '_rtx.dart';

Future<void> main() async {
  final c = Rtx.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureSeller2();
  await c.ensureHelper();

  final live = await c.insertLive();
  if (live == null) throw StateError('live');

  final item = await c.insertLiveOnlyItem(
    liveId: live,
    qty: 2,
    ref: 'XH3',
    jwt: c.sellerJwt,
  );

  final hPatch = await c.rest(
    'PATCH',
    'live_items?id=eq.$item',
    jwt: c.helperJwt,
    body: {'quantity': 40},
  );
  final after = await c.itemRow(item!);
  c.note('p3.helper.patch-qty', 'helper PATCH live_items.quantity', {
    'patch': hPatch.brief,
    'qty': after?['quantity'],
  }, lens: 'X2');
  if (hPatch.ok && (numOf(after?['quantity']) ?? 0) >= 40) {
    c.hold(
      id: 'RTX-X2-helper-inflate-qty',
      lens: 'X2',
      severity: 'P1',
      title: 'helper inflaciona quantity do live_item',
      actor: 'helper JWT',
      pre: 'can_manage_reservations; item qty=2',
      repro: 'PATCH live_items.quantity=40 JWT helper',
      expected: 'RLS recusa (só dono da live)',
      obtained: after,
    );
  } else {
    c.block('RTX-X2-helper-inflate-qty', 'X2', 'helper PATCH qty recusado/sem mutação',
        {'patch': hPatch.brief, 'qty': after?['quantity']});
  }

  final markH = await c.rpc('batata_mark_live_item_sold', {
    'p_live_item_id': item,
  }, jwt: c.helperJwt);
  final item2 = await c.itemRow(item);
  c.note('p3.helper.mark-sold', 'helper mark_sold sem can_mark_items_sold', {
    'rpc': markH.brief,
    'item': item2,
  }, lens: 'X2');
  if (markH.rpcOk || item2?['status'] == 'sold') {
    c.hold(
      id: 'RTX-X2-helper-mark-sold-without-perm',
      lens: 'X2',
      severity: 'P1',
      title: 'helper sem can_mark_items_sold marca artigo sold',
      actor: 'helper JWT (só reservas)',
      pre: 'permissions sem can_mark_items_sold',
      repro: 'rpc batata_mark_live_item_sold JWT helper',
      expected: 'not_allowed',
      obtained: {'rpc': markH.map, 'item': item2},
    );
  } else {
    c.block('RTX-X2-helper-mark-sold-without-perm', 'X2',
        'helper mark_sold recusado', markH.brief);
  }

  final raf = await c.rpc('batata_create_live_raffle', {
    'p_live_id': live,
    'p_title': '$prefix p3 raffle',
    'p_activate': true,
  }, jwt: c.sellerJwt);
  final rafId = raf.map?['raffle_id']?.toString();
  c.note('p3.raffle', 'create', raf.brief, lens: 'X6');
  if (rafId != null) {
    final shareS2 = await c.rpc('batata_claim_live_raffle_share_intent', {
      'p_raffle_id': rafId,
    }, jwt: c.seller2Jwt);
    c.note('p3.share.s2', 'seller2 claim share rifa alheia', shareS2.brief,
        lens: 'X6');
    if (shareS2.rpcOk) {
      c.hold(
        id: 'RTX-X6-s2-share-foreign-raffle',
        lens: 'X6',
        severity: 'P2',
        title: '2.º seller ganha entrada de partilha na rifa alheia',
        actor: 'seller2 JWT',
        pre: 'rifa active live seller1',
        repro: 'rpc batata_claim_live_raffle_share_intent JWT seller2',
        expected: 'entrada de viewer OK se a rifa é pública; FAIL se exige viewer da live',
        obtained: shareS2.map ?? shareS2.brief,
      );
    } else {
      c.block('RTX-X6-s2-share-foreign-raffle', 'X6',
          'share foreign recusado ou não aplica', shareS2.brief);
    }
  } else {
    c.skip('RTX-X6-p3', 'X6', 'create raffle falhou', raf.brief);
  }

  await c.endLives();
  final out = {
    'auditor': 'REDTEAM_BLIND_X_LIVE_MANUAL_STAFF_v1',
    'pass': 3,
    'production_touched': false,
    'fase4': false,
    'lenses': c.lensesHit.toList()..sort(),
    'findings': c.findings,
    'blocked': c.blocked,
    'skipped': c.skipped,
    'notes': c.notes,
  };
  await dumpJson('${outDir()}/pass3.json', out);
  stdout.writeln(
      'WROTE pass3.json findings=${c.findings.length} blocked=${c.blocked.length}');
}
