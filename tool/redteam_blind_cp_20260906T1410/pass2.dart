/// CP pass2 — confirmar A4/B1 (páginas Stripe) + payment_method ZWSP + B2 last-unit.
import 'dart:io';

import '_rtcp.dart';

Future<Map<String, Object?>> peekCheckout(Rtcp c, String sid) async {
  final settle = await c.settleGet(sid);
  final page = await c.req(
    'GET',
    'https://checkout.stripe.com/c/pay/$sid',
  );
  final raw = page.body.toLowerCase();
  final expired = raw.contains('expired') ||
      raw.contains('expirou') ||
      raw.contains('no longer available') ||
      raw.contains('session is complete') ||
      page.status == 404;
  final payForm = raw.contains('card') ||
      raw.contains('payment') ||
      raw.contains('pay') ||
      page.status == 200 ||
      page.status == 403;
  return {
    'sid': sid.substring(0, 28),
    'settle': settle.brief,
    'page_http': page.status,
    'page_snip': clip(page.body, 180),
    'expired_hint': expired,
    'pay_hint': payForm && !expired,
  };
}

Future<void> main() async {
  final c = Rtcp.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  final a4 = [
    'cs_test_a1T6KKwOE1IgOanFQ3NKh1HbnGr6zDVqYDmkgOxmG523kasR83rjOftGq8',
    'cs_test_a1l1trZ1vdeeoinThnxVqzVrdo51MBT9tB7DBTMflVbtpCSXiRfUvh7tCD',
    'cs_test_a1sMZErbNuYPFM07vcEolU059uN7nCMOyKsgxVmC5gfrLDb6Vz2HxUEHvv',
  ];
  final b1 = [
    'cs_test_a1HoXqnSZLkmdbye9jlxHYifJSkcXOU1WI7YSArFx8nPaBP8udNSZIXbAF',
    'cs_test_a1ZTLk9Y92y8jtizgwgtlBwER92xL588MrnddBEZncMvRM7XvH2jjnYXAW',
  ];

  final a4peeks = <Map<String, Object?>>[];
  for (final sid in a4) {
    a4peeks.add(await peekCheckout(c, sid));
  }
  final b1peeks = <Map<String, Object?>>[];
  for (final sid in b1) {
    b1peeks.add(await peekCheckout(c, sid));
  }
  c.note('A4.pages', 'Stripe pages A4', a4peeks, lens: 'CP1', well: 'CP-A');
  c.note('B1.pages', 'Stripe pages B1', b1peeks, lens: 'CP3', well: 'CP-B');

  final zwspOrders = await c.rest(
    'GET',
    'orders?select=id,payment_method,status,stripe_checkout_session_id,price_total&stripe_checkout_session_id=eq.cs_test_a1kugyn3SFz0p9wjclBRfaDVt8Z764ARtdbJBp3UGXZCVGISxTy3UkQTpT',
    service: true,
  );
  c.note('C1.zwsp.row', 'order com cs_ ZWSP', zwspOrders.brief,
      lens: 'CP5', well: 'CP-C');
  final zwspMap = zwspOrders.map;
  final pm = '${zwspMap?['payment_method'] ?? ''}';
  final hasZwsp = pm.contains('\u200b') || pm.contains(String.fromCharCode(0x200b));
  final pmCodes = pm.runes.map((r) => r.toRadixString(16)).toList();
  c.note('C1.zwsp.pm', 'payment_method codes', {
    'pm': pm,
    'len': pm.length,
    'has_zwsp': hasZwsp,
    'codes': pmCodes,
  }, lens: 'CP5', well: 'CP-C');

  // B2: 2 buyers última unidade — qty=2 holds then PATCH qty=1 then race
  final pid = await c.createProduct(title: '$prefix-b2b-last', qty: 2, price: 11);
  if (pid != null) {
    final o1 = await c.insertOrder(productId: pid, price: 11, jwt: c.buyerJwt);
    final o2 = await c.insertOrder(
      productId: pid,
      price: 11,
      buyer: c.buyer2Id,
      jwt: c.buyer2Jwt,
    );
    final patch = await c.rest(
      'PATCH',
      'products?id=eq.$pid',
      jwt: c.sellerJwt,
      body: {'quantity': 1},
    );
    HttpHit? h1;
    HttpHit? h2;
    if (o1 != null && o2 != null) {
      final hits = await parallel([
        c.checkout(
          orderId: o1,
          productId: pid,
          amount: 1,
          jwt: c.buyerJwt,
          buyer: c.buyerId,
        ),
        c.checkout(
          orderId: o2,
          productId: pid,
          amount: 1,
          jwt: c.buyer2Jwt,
          buyer: c.buyer2Id,
        ),
      ]);
      h1 = hits[0];
      h2 = hits[1];
      for (final h in hits) {
        c.trackSession(h);
      }
    }
    final ok = [h1, h2].where((h) => h != null && h.ok).length;
    c.note('B2.last', '2 buyers last unit', {
      'o1': o1,
      'o2': o2,
      'patch': patch.brief,
      'h1': h1?.brief,
      'h2': h2?.brief,
      'ok': ok,
    }, lens: 'CP4', well: 'CP-B');
    final dual = ok >= 2;
    if (dual) {
      c.hold(
        id: 'P0-B2',
        lens: 'CP4',
        severity: 'P0',
        title: '2 buyers Session na última unidade',
        actor: 'buyer + buyer2',
        pre: 'qty 2→1 após 2 holds',
        repro: 'Future.wait 2× CPI',
        expected: '≤1 Session',
        obtained: {'h1': h1?.brief, 'h2': h2?.brief},
      );
      c.probe(
        id: 'B2',
        poco: 'CP-B',
        payload: 'Future.wait 2 buyers CPI última unidade (qty 2→1)',
        http: {'h1': h1?.brief, 'h2': h2?.brief, 'patch': patch.brief},
        bd: {'ok': ok, 'o1': o1, 'o2': o2},
        verdict: 'HOLD',
        lens: 'CP4',
      );
    } else {
      c.block('B2-LAST', 'CP4', 'última unidade ≤1 Session', {
        'ok': ok,
        'h1': h1?.status,
        'h2': h2?.status,
        'o2': o2,
      });
      c.probe(
        id: 'B2',
        poco: 'CP-B',
        payload: 'Future.wait 2 buyers CPI última unidade (qty 2→1)',
        http: {'h1': h1?.brief, 'h2': h2?.brief, 'insert2': o2 ?? 'fail'},
        bd: {'ok': ok},
        verdict: 'FAIL',
        lens: 'CP4',
      );
    }
  } else {
    c.skip('B2', 'CP4', 'SKU fail', 'createProduct');
    c.probe(
      id: 'B2',
      poco: 'CP-B',
      payload: '2 buyers last unit',
      http: 'skip',
      bd: '-',
      verdict: 'SKIP',
      lens: 'CP4',
    );
  }

  // Extra allowlist: NBSP / CR / fullwidth mbway
  final variants = <String, String>{
    'nbsp': 'mbway\u00a0',
    'cr': 'mbway\r',
    'fw': 'ｍｂｗａｙ',
    'cyr': 'мbway',
  };
  final alw = <String, Object?>{};
  for (final e in variants.entries) {
    final skus = await mkOne(c, 'alw-${e.key}', e.value);
    if (skus == null) {
      alw[e.key] = 'insert_fail';
      continue;
    }
    final hit = await c.checkout(
      orderId: skus.oid,
      productId: skus.pid,
      amount: 1,
    );
    c.trackSession(hit);
    final row = await c.orderRow(skus.oid);
    alw[e.key] = {
      'http': hit.brief,
      'pm': row?['payment_method'],
      'sid': hit.sessionId,
    };
  }
  c.note('ALW.pay', 'off-platform encoding extras', alw, lens: 'CP5', well: 'CP-C');
  final opened = variants.keys
      .where((k) {
        final v = alw[k];
        if (v is Map && v['sid'] is String) {
          return (v['sid'] as String).startsWith('cs_');
        }
        return false;
      })
      .toList();
  c.probe(
    id: 'ALW1',
    poco: 'CP-C',
    payload: 'payment_method mbway NBSP/CR/fullwidth/cyrillic',
    http: alw,
    bd: {'opened': opened},
    verdict: opened.isNotEmpty ? 'HOLD' : 'FAIL',
    lens: 'CP5',
  );
  if (opened.isNotEmpty) {
    c.hold(
      id: 'P1-ALW1',
      lens: 'CP5',
      severity: 'P1',
      title: 'allowlist off-platform bypass encodings ${opened.join(",")}',
      actor: 'buyer JWT',
      pre: 'payment_method lookalike',
      repro: 'INSERT order + CPI',
      expected: '400 off-platform',
      obtained: alw,
    );
  } else {
    c.block('ALW1-ENC', 'CP5', 'NBSP/CR/fw/cyr não abriram Stripe', alw);
  }

  await dumpJson('${outDir()}/pass2.json', {
    'a4peeks': a4peeks,
    'b1peeks': b1peeks,
    'zwsp': {
      'row': zwspOrders.brief,
      'pm': pm,
      'has_zwsp': hasZwsp,
      'codes': pmCodes,
    },
    'alw': alw,
    'probes': c.probes,
    'findings': c.findings,
  });
  await c.dumpAll('pass2_findings.json');
  stdout.writeln(
    'PASS2 done probes=${c.probes.length} findings=${c.findings.length}',
  );
}

Future<({String oid, String pid})?> mkOne(
  Rtcp c,
  String tag,
  String payment,
) async {
  final pid = await c.createProduct(title: '$prefix-$tag', qty: 2, price: 18);
  if (pid == null) return null;
  final oid = await c.insertOrder(
    productId: pid,
    price: 18,
    jwt: c.buyerJwt,
    payment: payment,
  );
  if (oid == null) return null;
  return (oid: oid, pid: pid);
}
