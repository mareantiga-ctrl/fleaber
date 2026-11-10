/// CJ pass2 — C1 last-unit (qty=2→1), B1c cross-offer fresco, A5 dual URL live.
import 'dart:io';

import '_rtcj.dart';

Future<void> main() async {
  final c = Rtcj.fromEnv(loadEnv());
  stdout.writeln('CJ pass2 staging=${c.url}');
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  // C1: 2 holds then PATCH qty=1 then race CPI
  final pid = await c.createProduct(title: '$prefix-c1b-last', qty: 2, price: 11);
  HttpHit? c1a;
  HttpHit? c1b;
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
      c1a = hits[0];
      c1b = hits[1];
      for (final h in hits) {
        c.trackSession(h);
      }
      final ok = hits.where((h) => h.ok).length;
      c.note('C1.pass2', '2 holds + qty=1 + Future.wait CPI', {
        'patch': patch.brief,
        'ok': ok,
        'a': hits[0].brief,
        'b': hits[1].brief,
      }, lens: 'CJ6', well: 'CJ-C');
      if (ok >= 2) {
        c.hold(
          id: 'P0-C1',
          lens: 'CJ5',
          severity: 'P0',
          title: '2 buyers Session após PATCH qty=1',
          actor: 'buyer+buyer2',
          pre: '2 holds; quantity=1',
          repro: 'Future.wait 2× CPI',
          expected: '≤1 Session',
          obtained: hits.map((h) => h.brief).toList(),
        );
        c.probe(
          id: 'C1',
          poco: 'CJ-C',
          payload: 'Future.wait 2 buyers CPI após 2 holds + PATCH qty=1',
          http: hits.map((h) => h.brief).toList(),
          bd: {'ok': ok, 'patch': patch.status},
          verdict: 'HOLD',
          lens: 'CJ5',
        );
      } else {
        c.block('C1-LAST', 'CJ5', 'última unidade ≤1 Session', {'ok': ok});
        c.probe(
          id: 'C1',
          poco: 'CJ-C',
          payload: 'Future.wait 2 buyers CPI após 2 holds + PATCH qty=1',
          http: hits.map((h) => h.brief).toList(),
          bd: {'ok': ok},
          verdict: 'FAIL',
          lens: 'CJ5',
        );
      }
    }
  }

  // B1c fresco: offer seller2 colada em SKU seller1
  final p1 = await c.createProduct(title: '$prefix-b1c-s1', qty: 3, price: 18);
  final p2 = await c.createProduct(
    seller: c.seller2Id,
    title: '$prefix-b1c-s2',
    qty: 3,
    price: 40,
  );
  if (p1 != null && p2 != null) {
    final off2 = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
      'product_id': p2,
      'buyer_id': c.buyerId,
      'seller_id': c.seller2Id,
      'amount': 1,
      'list_price': 40,
      'offered_by': 'buyer',
      'status': 'pending',
    });
    final oidOff2 = off2.firstId;
    if (oidOff2 != null) {
      await c.rest(
        'PATCH',
        'product_offers?id=eq.$oidOff2',
        jwt: c.seller2Jwt,
        body: {'status': 'accepted'},
      );
      final hijack = await c.insertOrder(
        productId: p1,
        price: 1,
        offerId: oidOff2,
        jwt: c.buyerJwt,
      );
      if (hijack != null) {
        final ck = await c.checkout(orderId: hijack, productId: p1, amount: 1);
        c.trackSession(ck);
        c.note('B1c.pass2', 'offer S2 em SKU S1', {
          'ck': ck.brief,
          'amt': ck.amountTotal,
        }, lens: 'CJ7', well: 'CJ-B');
        if (ck.ok && ck.amountTotal != null && ck.amountTotal! < 400) {
          c.hold(
            id: 'P0-B1c',
            lens: 'CJ7',
            severity: 'P0',
            title: 'Offer outro seller baixou SKU',
            actor: 'buyer JWT',
            pre: 'offer S2 aceite em order S1',
            repro: 'INSERT order product_offer_id alheio; CPI',
            expected: 'catálogo 18€ ou bloqueio',
            obtained: ck.brief,
          );
          c.probe(
            id: 'B1c',
            poco: 'CJ-B',
            payload: 'offer seller2 aceite colada em SKU seller1 (fresco)',
            http: ck,
            bd: ck.amountTotal,
            verdict: 'HOLD',
            lens: 'CJ7',
          );
        } else {
          c.block('B1c-CROSS', 'CJ7', 'offer outro seller não underpay', {
            'amt': ck.amountTotal,
            'status': ck.status,
          });
          c.probe(
            id: 'B1c',
            poco: 'CJ-B',
            payload: 'offer seller2 aceite colada em SKU seller1',
            http: ck,
            bd: ck.amountTotal,
            verdict: 'FAIL',
            lens: 'CJ7',
          );
        }
      } else {
        c.probe(
          id: 'B1c',
          poco: 'CJ-B',
          payload: 'offer S2 em SKU S1 — insert falhou',
          http: 'insertOrder fail',
          bd: '-',
          verdict: 'SKIP',
          lens: 'CJ7',
        );
      }
    }
  }

  // A5 dual URL liveness
  const sid4 = 'cs_test_a1FttdGw2k2ue2V2ifYVAvMQ5WrDATWkmDrN6QEm1cskODQxjeyEY0PWdo';
  const sid2 = 'cs_test_a1ZlGY9Zhtg1KTDzfbV1HIhU95aySHH2rJ8N8dhGjRKYMpbBmb0lkKpAJe';
  final st4 = await c.settleGet(sid4);
  final st2 = await c.settleGet(sid2);
  final page4 = await c.req(
    'GET',
    'https://checkout.stripe.com/c/pay/$sid4',
  );
  final page2 = await c.req(
    'GET',
    'https://checkout.stripe.com/c/pay/$sid2',
  );
  c.note('A5.live', 'settle + GET páginas overlap 4∥2', {
    'settle4': st4.brief,
    'settle2': st2.brief,
    'page4': '${page4.status} ${clip(page4.body, 160)}',
    'page2': '${page2.status} ${clip(page2.body, 160)}',
  }, lens: 'CJ2', well: 'CJ-A');
  c.probe(
    id: 'A5b',
    poco: 'CJ-A',
    payload: 'settle GET + HTTP GET páginas das 2 cs_ overlap 4∥2',
    http: {
      'settle4': st4.brief,
      'settle2': st2.brief,
      'page4': page4.status,
      'page2': page2.status,
    },
    bd: {'sid4': sid4, 'sid2': sid2},
    verdict: 'FAIL',
    lens: 'CJ2',
  );

  await c.dumpAll('pass2_findings.json');
  stdout.writeln(
    'DONE2 probes=${c.probes.length} findings=${c.findings.length} '
    'c1a=${c1a?.status} c1b=${c1b?.status}',
  );
}
