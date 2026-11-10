/// Blind E Órbita pass3 — checkout após unlist em status pagável; Hub lives; shipping.
import 'dart:io';

import '_rte.dart';

void main() async {
  final env = loadEnv();
  final c = Rte.fromEnv(env);
  await c.loginActors(env);
  await c.ensureBuyer2();

  final findings = <Map<String, dynamic>>[];
  final out = <String, dynamic>{'pass': 3, 'stamp': stamp};

  void add(Map<String, dynamic> f) {
    findings.add(f);
    stdout.writeln(
      '${f['proven'] == true ? "HIT" : "try"} ${f['severity']} ${f['id']} ${f['title']}',
    );
  }

  Future<HttpHit> pay(String oid) =>
      c.edge('create-payment-intent', jwt: c.buyerJwt, body: {
        'order_id': oid,
        'buyer_id': c.buyerId,
        'shipping_method': 'ctt',
      });

  bool session(HttpHit h) =>
      h.ok &&
      (h.body.contains('checkoutUrl') ||
          h.body.contains('cs_') ||
          h.body.contains('checkoutSessionId'));

  // --- payable status then unlist then checkout ---
  for (final st in ['reservado', 'aguarda_confirmacao', 'reserva_pendente']) {
    final pid = await c.insertProduct(
      title: '$prefix pay-$st',
      price: 8.5,
      qty: 3,
    );
    if (pid == null) continue;
    final o = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'quantity': 1,
      'status': st,
      'price_total': 8.5,
      'shipping_method': 'ctt',
    });
    out['hold_$st'] = {'http': o.status, 'id': o.firstId, 'snip': o.snippet};
    if (!o.ok || o.firstId == null) continue;

    final before = await pay(o.firstId!);
    out['pay_before_unlist_$st'] = {
      'http': before.status,
      'sess': session(before),
      'snip': clip(before.body, 220),
    };

    await c.rest(
      'PATCH',
      'products?id=eq.$pid',
      jwt: c.sellerJwt,
      body: {'list_on_marketplace': false},
    );
    final prod = await c.rest(
      'GET',
      'products?id=eq.$pid&select=id,list_on_marketplace,quantity',
      service: true,
    );
    final after = await pay(o.firstId!);
    final issued = session(after);
    add(finding(
      id: 'E6-CHECKOUT-AFTER-UNLIST-$st',
      lens: 'E6',
      severity: issued ? 'P1' : 'info',
      title: 'Session checkout após unlist (order $st)',
      pre: 'hold $st → unlist → create-payment-intent',
      repro: 'POST create-payment-intent order=$st after unlist',
      proven: issued && prod.map?['list_on_marketplace'] == false,
      evidence: {
        'pid': pid,
        'oid': o.firstId,
        'listed': prod.map?['list_on_marketplace'],
        'before_http': before.status,
        'after_http': after.status,
        'after_snip': clip(after.body, 280),
      },
    ));
    if (issued) {
      out['checkout_url_$st'] = after.map?['checkoutUrl'] ?? after.snippet;
    }
  }

  // PATCH pendente → reservado after unlist (status escalate)
  const raceOid = '477310c4-7730-4b54-874e-cfd81f3f492b';
  final esc = await c.rest(
    'PATCH',
    'orders?id=eq.$raceOid',
    jwt: c.buyerJwt,
    body: {'status': 'reservado'},
  );
  final payEsc = await pay(raceOid);
  add(finding(
    id: 'E6-STATUS-ESCALATE-UNLIST',
    lens: 'E6',
    severity: (esc.ok && (esc.list.isNotEmpty) && session(payEsc))
        ? 'P1'
        : 'info',
    title: 'buyer PATCH pendente→reservado em unlist e faz checkout',
    pre: 'race order unlistado',
    repro: 'PATCH status=reservado; POST create-payment-intent',
    proven: esc.ok && esc.list.isNotEmpty && session(payEsc),
    evidence: {
      'patch': {'http': esc.status, 'snip': esc.snippet},
      'pay': {'http': payEsc.status, 'snip': clip(payEsc.body, 220)},
    },
  ));

  // sold then checkout on existing reservado
  final pidSold = await c.insertProduct(
    title: '$prefix then-sold',
    price: 6.0,
  );
  if (pidSold != null) {
    final o = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pidSold,
      'quantity': 1,
      'status': 'reservado',
      'price_total': 6.0,
      'shipping_method': 'ctt',
    });
    if (o.ok && o.firstId != null) {
      await c.rest(
        'PATCH',
        'products?id=eq.$pidSold',
        jwt: c.sellerJwt,
        body: {'is_sold': true},
      );
      final after = await pay(o.firstId!);
      add(finding(
        id: 'E6-CHECKOUT-AFTER-SOLD',
        lens: 'E6',
        severity: session(after) ? 'P1' : 'info',
        title: 'Session checkout após is_sold=true (order reservado)',
        pre: 'hold reservado → sold → checkout',
        repro: 'POST create-payment-intent after is_sold',
        proven: session(after),
        evidence: {
          'oid': o.firstId,
          'http': after.status,
          'snip': clip(after.body, 280),
        },
      ));
    }
  }

  // unpublished live still in discovery by id
  const endedLive = '53d40ca4-8bb5-40b6-8fea-9355bb848aba';
  final live = await c.rest(
    'GET',
    'hub_lives_discovery_public?id=eq.$endedLive&select=id,seller_id,seller_name,mux_playback_id,status',
  );
  add(finding(
    id: 'E1-DISCOVERY-ENDED-UNPUB-RECHECK',
    lens: 'E1',
    severity: live.list.isNotEmpty ? 'P2' : 'info',
    title: 'recheck: live ended unpublished ainda na discovery',
    pre: 'GET hub_lives_discovery_public?id=eq.fixture',
    repro: 'anon GET by id',
    proven: live.list.isNotEmpty,
    evidence: {'body': live.snippet},
  ));

  // hub_published self vs other
  final pubSelf = await c.rest(
    'PATCH',
    'profiles?id=eq.${c.buyer2Id}',
    jwt: c.buyer2Jwt,
    body: {'hub_published': true},
  );
  final pubOther = await c.rest(
    'PATCH',
    'profiles?id=eq.${c.sellerId}',
    jwt: c.buyer2Jwt,
    body: {'hub_published': true},
  );
  add(finding(
    id: 'E1-HUB-PUBLISH-OTHER',
    lens: 'E1',
    severity: pubOther.ok && pubOther.list.isNotEmpty ? 'P1' : 'info',
    title: 'buyer2 publica Hub do seller',
    pre: 'PATCH hub_published',
    repro: 'PATCH profiles seller as buyer2',
    proven: pubOther.ok && pubOther.list.isNotEmpty,
    evidence: {
      'self': {'http': pubSelf.status, 'n': pubSelf.list.length},
      'other': {'http': pubOther.status, 'snip': pubOther.snippet},
    },
  ));
  await c.rest(
    'PATCH',
    'profiles?id=eq.${c.buyer2Id}',
    service: true,
    body: {'hub_published': false, 'is_live': false},
    prefer: 'return=minimal',
  );

  // shipping hostile on bag / order
  final pidShip = await c.insertProduct(title: '$prefix ship', price: 10.0);
  if (pidShip != null) {
    final o = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pidShip,
      'quantity': 1,
      'status': 'reservado',
      'price_total': 10.0,
      'shipping_method': 'hand',
    });
    if (o.ok && o.firstId != null) {
      final patchShip = await c.rest(
        'PATCH',
        'orders?id=eq.${o.firstId}',
        jwt: c.buyerJwt,
        body: {'shipping_method': 'ctt'},
      );
      add(finding(
        id: 'E4-SHIP-SEAL-FLIP',
        lens: 'E4',
        severity: patchShip.ok &&
                patchShip.list.isNotEmpty &&
                patchShip.map?['shipping_method']?.toString() == 'ctt'
            ? 'P2'
            : 'info',
        title: 'buyer muda shipping_method após selo',
        pre: 'order reservado hand → PATCH ctt',
        repro: 'PATCH orders shipping_method',
        proven: patchShip.ok &&
            patchShip.list.isNotEmpty &&
            patchShip.map?['shipping_method']?.toString() == 'ctt',
        evidence: {'http': patchShip.status, 'snip': patchShip.snippet},
      ));
    }
  }

  // anon GET seller_device_tokens
  final tokAnon = await c.rest('GET', 'seller_device_tokens?select=*&limit=2');
  add(finding(
    id: 'E3-DEVICE-ANON',
    lens: 'E3',
    severity: tokAnon.ok && tokAnon.list.isNotEmpty ? 'P1' : 'info',
    title: 'anon lê seller_device_tokens',
    pre: 'GET seller_device_tokens',
    repro: 'anon GET',
    proven: tokAnon.ok && tokAnon.list.isNotEmpty,
    evidence: {'http': tokAnon.status, 'snip': tokAnon.snippet},
  ));

  out['findings'] = findings;
  out['proven'] = findings.where((f) => f['proven'] == true).toList();
  await dumpJson('tool/redteam_blind_e_orbita_$stamp/out/pass3.json', out);
  stdout.writeln('proven ${out['proven'].length} / ${findings.length}');
}
