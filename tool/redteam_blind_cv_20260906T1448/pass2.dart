/// CV pass2 — B2 última unidade + confirmar páginas B1/B4 + rails 429.
import 'dart:io';

import '_rtcv.dart';

Future<Map<String, Object?>> peekCheckout(Rtcv c, String sid) async {
  final settle = await c.settleGet(sid);
  final page = await c.req('GET', 'https://checkout.stripe.com/c/pay/$sid');
  final raw = page.body.toLowerCase();
  final expired = raw.contains('this session has expired') ||
      raw.contains('session expired') ||
      raw.contains('expirou') ||
      raw.contains('no longer available') ||
      page.status == 404;
  final complete = raw.contains('session is complete') ||
      raw.contains('payment successful');
  return {
    'sid': sid.length > 32 ? sid.substring(0, 32) : sid,
    'settle': settle.brief,
    'page_http': page.status,
    'expired_strict': expired,
    'complete_hint': complete,
    'has_cs_test': raw.contains('cs_test') || raw.contains(sid.toLowerCase()),
    'snip': clip(page.body.replaceAll(RegExp(r'\s+'), ' '), 160),
  };
}

Future<void> main() async {
  final c = Rtcv.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  // B1 pages
  final b1 = [
    'cs_test_a1sCy5SYclzKOPobBOMyu9k3RVhMYqHawxUz0ji59kL1MguQNN9UvLBIjm',
    'cs_test_a1lThkRTEGzLcLxAIEoB9vD9YJTvgQmehDgUKMI1lB208Jkyff315Qcve7',
  ];
  final b1peeks = <Map<String, Object?>>[];
  for (final sid in b1) {
    b1peeks.add(await peekCheckout(c, sid));
  }
  c.note('B1.pages2', 'Stripe pages B1 strict', b1peeks, lens: 'CV3', well: 'CV-B');

  final b4 = [
    'cs_test_a1hrOa1lGeKxEHuP8sTNm2hN5QUWm5LjBhFyxlFYBbe1xjJdGTfXSyNQu8',
    'cs_test_a1PLQtn5qI1JUwuDG2EYibLBEYqshRgchQloUZWuBdY8YZhchycGQAOFcY',
  ];
  final b4peeks = <Map<String, Object?>>[];
  for (final sid in b4) {
    b4peeks.add(await peekCheckout(c, sid));
  }
  c.note('B4.pages2', 'Stripe pages B4 strict', b4peeks, lens: 'CV3', well: 'CV-B');

  // B2: qty=1; 2.º insert deve 400 hold; se ambos existem, race CPI
  final pid = await c.createProduct(title: '$prefix-b2b-last', qty: 1, price: 11);
  HttpHit? i1;
  HttpHit? i2;
  HttpHit? ck1;
  HttpHit? ck2;
  String? o1;
  String? o2;
  if (pid != null) {
    i1 = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'price_total': 11,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    o1 = i1.firstId;
    if (o1 != null) c.createdOrderIds.add(o1);
    i2 = await c.rest('POST', 'orders', jwt: c.buyer2Jwt, body: {
      'buyer_id': c.buyer2Id,
      'seller_id': c.sellerId,
      'product_id': pid,
      'price_total': 11,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    o2 = i2.firstId;
    if (o2 != null) c.createdOrderIds.add(o2);
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
      ck1 = hits[0];
      ck2 = hits[1];
      for (final h in hits) {
        c.trackSession(h);
      }
    } else if (o1 != null) {
      ck1 = await c.checkout(
        orderId: o1,
        productId: pid,
        amount: 1,
        jwt: c.buyerJwt,
        buyer: c.buyerId,
      );
      c.trackSession(ck1);
    }
  }
  final sids = {
    if ((ck1?.sessionId ?? '').startsWith('cs_')) ck1!.sessionId!,
    if ((ck2?.sessionId ?? '').startsWith('cs_')) ck2!.sessionId!,
  };
  final ok = [ck1, ck2].where((h) => h != null && h.ok).length;
  final holdInsert = o2 == null &&
      i2 != null &&
      (i2.status == 400 || '${i2.body}'.contains('hold_exceeds'));
  c.note('B2.last2', '2 buyers última unidade', {
    'i1': i1?.brief,
    'i2': i2?.brief,
    'o1': o1,
    'o2': o2,
    'ck1': ck1?.brief,
    'ck2': ck2?.brief,
    'ok': ok,
    'sids': sids.toList(),
    'holdInsert': holdInsert,
  }, lens: 'CV6', well: 'CV-B');
  final twoSessions = ok >= 2 || sids.length >= 2;
  if (twoSessions) {
    c.hold(
      id: 'P0-B2',
      lens: 'CV6',
      severity: 'P0',
      title: '2 buyers Session na última unidade',
      actor: 'buyer + buyer2 JWT',
      pre: 'quantity=1',
      repro: '2 insert + Future.wait CPI',
      expected: '1 Session + 1 stock/hold block',
      obtained: {
        'i2': i2?.brief,
        'ck1': ck1?.brief,
        'ck2': ck2?.brief,
        'sids': sids.toList(),
      },
    );
    c.probe(
      id: 'B2',
      poco: 'CV-B',
      payload: 'Future.wait 2 buyers última unidade (qty=1)',
      http: {'i2': i2?.brief, 'ck1': ck1?.brief, 'ck2': ck2?.brief},
      bd: {'sids': sids.toList(), 'ok': ok},
      verdict: 'HOLD',
      lens: 'CV6',
    );
  } else {
    c.block('B2-LAST', 'CV6', 'última unidade ≤1 Session / 2.º hold', {
      'i2': i2?.brief,
      'ok': ok,
      'sids': sids.toList(),
      'holdInsert': holdInsert,
    });
    c.probe(
      id: 'B2',
      poco: 'CV-B',
      payload: 'Future.wait 2 buyers última unidade (qty=1)',
      http: {'i1': i1?.brief, 'i2': i2?.brief, 'ck1': ck1?.brief, 'ck2': ck2?.brief},
      bd: {'sids': sids.toList(), 'ok': ok, 'holdInsert': holdInsert},
      verdict: 'FAIL',
      lens: 'CV6',
    );
  }

  // Rails residual após 429 — 1 retry cada
  for (final e in {
    'CTRL-PAYSAFE': 'PaysafeCash',
    'CTRL-PICPAY': 'PicPay',
  }.entries) {
    final pid2 = await c.createProduct(title: '$prefix-${e.key}', qty: 2, price: 12);
    if (pid2 == null) continue;
    final oid = await c.insertOrder(
      productId: pid2,
      price: 12,
      payment: e.value,
    );
    if (oid == null) continue;
    final hit = await c.checkout(orderId: oid, productId: pid2, amount: 1);
    c.trackSession(hit);
    final opened = hit.ok && (hit.sessionId ?? '').startsWith('cs_');
    c.note('retry.${e.key}', e.key, hit.brief, lens: 'CV4', well: 'CV-C');
    c.probe(
      id: '${e.key}-R2',
      poco: 'CV-C',
      payload: 'anti-atrofia retry ${e.key}',
      http: hit.brief,
      bd: {'opened': opened, 'sid': hit.sessionId},
      verdict: hit.status == 429
          ? 'SKIP'
          : (opened ? 'HOLD' : 'FAIL'),
      lens: 'CV4',
    );
  }

  await dumpJson('${outDir()}/pass2.json', {
    'b1peeks': b1peeks,
    'b4peeks': b4peeks,
    'probes': c.probes,
    'findings': c.findings,
    'notes': c.notes,
  });
  await c.dumpAll('pass2_findings.json');
  stdout.writeln(
    'PASS2 probes=${c.probes.length} findings=${c.findings.length} '
    'b1=${b1peeks.length} b4=${b4peeks.length}',
  );
}
