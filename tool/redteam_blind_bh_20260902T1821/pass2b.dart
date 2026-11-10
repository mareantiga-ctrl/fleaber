/// BH pass2b — BH6 reopen/race com end REAL (service_role). Não contar 200 [] nem end JWT 403.
import 'dart:io';
import '_rtbh.dart';

Future<void> main() async {
  final c = Rtbh.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final liveA = await c.insertLive(title: '$prefix-p2b');
  if (liveA == null) {
    stderr.writeln('no live');
    await c.dumpAll('pass2b.json');
    exit(4);
  }
  final itemA = await c.insertLiveItem(liveId: liveA, qty: 2, title: '$prefix-p2b-only');
  final sku = await c.insertProduct(price: 16, qty: 1, live: true, title: '$prefix-p2b-sku');
  final itemMkt = sku == null
      ? null
      : await c.insertLiveItem(
          liveId: liveA,
          kind: 'marketplace_product',
          productId: sku,
          title: '$prefix-p2b-mkt',
        );
  if (itemA == null) {
    await c.dumpAll('pass2b.json');
    exit(4);
  }

  final r1 = await c.buyerReserve(itemA);
  c.trackRes(r1);
  final rid = r1.firstId;
  c.note('p2b-pending', 'pending before end', r1, lens: 'BH6');

  final jwtEnd = await c.endLive(liveA);
  c.note('p2b-jwt-end', 'seller JWT PATCH ended', jwtEnd, lens: 'BH6');

  final svcEnd = await c.endLive(liveA, service: true);
  final liveEnded = await c.liveRow(liveA);
  c.note('p2b-svc-end', 'service end', {
    'patch': svcEnd.brief,
    'status': liveEnded?['status'],
    'active': liveEnded?['is_active'],
  }, lens: 'BH6');

  final reallyEnded =
      liveEnded?['status'] == 'ended' && liveEnded?['is_active'] == false;

  if (!reallyEnded) {
    c.skip('BH6-01', 'BH6', 'não consegui ended persistido', liveEnded);
  } else {
    if (rid != null) {
      final accEnded = await c.patchRes(rid, {'status': 'accepted'});
      final row = await c.resRow(rid);
      if (accEnded.ok && accEnded.list.isNotEmpty && row?['status'] == 'accepted') {
        c.hold(
          id: 'BH6-01',
          lens: 'BH6',
          severity: 'P1',
          title: 'Accept reserva após live ended (sem reopen)',
          actor: 'seller JWT',
          pre: 'service ended+inactive; pending pré-existente',
          repro: 'PATCH accepted',
          expected: 'live_ended',
          obtained: {'patch': accEnded.brief, 'row': row, 'live': liveEnded},
        );
      } else {
        c.block('BH6-01', 'BH6', 'accept após ended real', {
          'patch': accEnded.brief,
          'row': row?['status'],
        });
      }
    }
    final newRes = await c.buyerReserve(itemA);
    c.trackRes(newRes);
    if (newRes.ok && newRes.list.isNotEmpty) {
      c.hold(
        id: 'BH6-02',
        lens: 'BH6',
        severity: 'P1',
        title: 'INSERT reserva em live ended real',
        actor: 'buyer JWT',
        pre: 'lives.status=ended is_active=false',
        repro: 'POST live_reservation_requests',
        expected: 'live_ended',
        obtained: newRes.brief,
      );
    } else {
      c.block('BH6-02', 'BH6', 'INSERT ended real', newRes);
    }

    // Reopen JWT vs service
    final jwtRe = await c.reopenLive(liveA);
    c.note('BH6-03-jwt', 'seller JWT reopen', jwtRe, lens: 'BH6');
    if (jwtRe.ok && jwtRe.list.isNotEmpty) {
      c.hold(
        id: 'BH6-03j',
        lens: 'BH6',
        severity: 'P3',
        title: 'Seller JWT reabre live ended (fila pode reviver)',
        actor: 'seller JWT',
        pre: 'ended via service',
        repro: 'PATCH lives status=live is_active=true',
        expected: 'ended irreversível ou 403',
        obtained: jwtRe.brief,
      );
    } else {
      c.block('BH6-03j', 'BH6', 'seller JWT não reabre', jwtRe);
    }

    final svcRe = await c.rest(
      'PATCH',
      'lives?id=eq.$liveA',
      service: true,
      body: {'status': 'live', 'is_active': true},
    );
    final liveRe = await c.liveRow(liveA);
    c.note('BH6-03-svc', 'service reopen', {
      'patch': svcRe.brief,
      'row': {'status': liveRe?['status'], 'active': liveRe?['is_active']},
    }, lens: 'BH6');

    if (liveRe?['status'] == 'live' && liveRe?['is_active'] == true && itemMkt != null) {
      final rp = await c.buyerReserve(itemMkt);
      c.trackRes(rp);
      final rpid = rp.firstId;
      if (rpid != null) {
        final acc = await c.patchRes(rpid, {'status': 'accepted'});
        final res = await c.resRow(rpid);
        if (acc.ok && res?['status'] == 'accepted') {
          c.hold(
            id: 'BH6-03',
            lens: 'BH6',
            severity: 'P3',
            title: 'Após reopen (service) accept produto marketplace — fila revivida',
            actor: 'seller JWT',
            pre: 'ended depois service PATCH live+active; item marketplace',
            repro: 'service reopen + PATCH accepted',
            expected: 'trade-off: dono pode retomar directo',
            obtained: {'accept': acc.brief, 'res': res},
          );
        } else {
          c.block('BH6-03', 'BH6', 'reopen+accept produto', acc);
        }
      }
    }
  }

  // Race: live broadcasting, pending, parallel service-end ∥ accept
  final liveR = await c.insertLive(title: '$prefix-p2b-race');
  final itemR = liveR == null
      ? null
      : await c.insertLiveItem(liveId: liveR, qty: 1, title: '$prefix-race');
  if (liveR != null && itemR != null) {
    final rr = await c.buyerReserve(itemR);
    c.trackRes(rr);
    final rrid = rr.firstId;
    if (rrid != null) {
      final results = await Future.wait([
        c.endLive(liveR, service: true),
        c.patchRes(rrid, {'status': 'accepted'}),
        c.patchRes(rrid, {'status': 'accepted'}),
        c.endLive(liveR, service: true),
      ]);
      final res = await c.resRow(rrid);
      final live = await c.liveRow(liveR);
      c.note('BH6-05', 'race service-end ∥ accept', {
        'hits': results.map((h) => h.brief).toList(),
        'res': res,
        'live': {'status': live?['status'], 'active': live?['is_active']},
      }, lens: 'BH6');
      final acceptedOnEnded = res?['status'] == 'accepted' &&
          live?['status'] == 'ended' &&
          live?['is_active'] == false;
      if (acceptedOnEnded) {
        c.hold(
          id: 'BH6-05',
          lens: 'BH6',
          severity: 'P1',
          title: 'Race end∥accept: accepted ficou em live ended',
          actor: 'seller JWT ∥ service end',
          pre: 'pending qty=1',
          repro: 'Future.wait service endLive + accept ×2',
          expected: 'accepted só se ainda broadcasting',
          obtained: {
            'res': res,
            'live': live,
            'hits': results.map((e) => e.status).toList(),
          },
        );
      } else {
        c.block('BH6-05', 'BH6', 'race sem accepted-on-ended', {
          'res': res?['status'],
          'live': live?['status'],
          'active': live?['is_active'],
        });
      }
    }
  }

  if (c.seller2Jwt != null && liveA != null) {
    await c.endLive(liveA, service: true);
    final s2re = await c.reopenLive(liveA, jwt: c.seller2Jwt);
    await c.expectDenied(
      id: 'BH6-04',
      lens: 'BH7',
      title: 'Seller2 reabre live A',
      hit: s2re,
      actor: 'seller2 JWT',
      pre: 'live A ended',
      repro: 'PATCH lives live+active',
      severityIfOpen: 'P1',
    );
  }

  await c.endAllLives();
  await c.dumpAll('pass2b.json');
  stdout.writeln(
      'DONE p2b findings=${c.findings.length} blocked=${c.blocked.length} lenses=${c.lensesHit.toList()..sort()}');
}
