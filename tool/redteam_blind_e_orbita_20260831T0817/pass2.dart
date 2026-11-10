/// Blind E Órbita pass2 — fechar estado final + cadeia + Stripe session.
import 'dart:io';

import '_rte.dart';

void main() async {
  final env = loadEnv();
  final c = Rte.fromEnv(env);
  await c.loginActors(env);
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final findings = <Map<String, dynamic>>[];
  final out = <String, dynamic>{
    'pass': 2,
    'stamp': stamp,
  };

  void add(Map<String, dynamic> f) {
    findings.add(f);
    stdout.writeln(
      '${f['proven'] == true ? "HIT" : "try"} ${f['severity']} ${f['id']} ${f['title']}',
    );
  }

  const racePid = 'a11ee70e-fc62-4295-8cf0-a1034f3268c5';
  const raceOid = '477310c4-7730-4b54-874e-cfd81f3f492b';
  const unlistedPid = 'a3e21bc8-851c-4bc6-8c94-e219164cb551';
  const soldPid = 'abdd21f8-91ec-4e7e-a6fe-f2d16bf44c6a';
  const listedPid = 'bf306122-db0d-4810-a23a-4fcebe6772dc';
  const bundleUnlisted = '917e6472-3fcc-4b52-a628-405907091673';
  const endedLive = '53d40ca4-8bb5-40b6-8fea-9355bb848aba';

  // --- E10 race final state ---
  final prod = await c.rest(
    'GET',
    'products?id=eq.$racePid&select=id,list_on_marketplace,is_sold,quantity,title',
    service: true,
  );
  final ord = await c.rest(
    'GET',
    'orders?id=eq.$raceOid&select=id,status,product_id,quantity,price_total,amount_paid_cents,stripe_checkout_session_id,stock_units_applied',
    service: true,
  );
  out['race_product'] = prod.map;
  out['race_order'] = ord.map;
  final listedNow = prod.map?['list_on_marketplace'] == true;
  final orderHold = ['pendente', 'reservado', 'reserva_pendente', 'aguarda_confirmacao']
      .contains((ord.map?['status'] ?? '').toString().toLowerCase());

  add(finding(
    id: 'E10-RACE-FINAL',
    lens: 'E10',
    severity: (!listedNow && orderHold) ? 'P2' : 'info',
    title: 'após race: produto unlistado com order ainda em hold',
    pre: 'GET product+order service',
    repro: 'observe racePid+raceOid',
    proven: !listedNow && orderHold,
    evidence: {'product': prod.map, 'order': ord.map},
    note: 'Hold iniciado enquanto listed=true e depois unlist = venda legítima em curso, NÃO morto-que-vende. P1 só se checkout/captura DEPOIS de unlist committed.',
  ));

  // Control: fresh product, unlist FIRST, then hold
  final pidCtrl = await c.insertProduct(title: '$prefix ctrl-unlist-first', price: 9.0);
  await c.rest(
    'PATCH',
    'products?id=eq.$pidCtrl',
    jwt: c.sellerJwt,
    body: {'list_on_marketplace': false},
  );
  final holdAfter = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pidCtrl,
    'quantity': 1,
    'status': 'pendente',
    'price_total': 9.0,
  });
  add(finding(
    id: 'E6-UNLIST-THEN-HOLD',
    lens: 'E6',
    severity: holdAfter.ok ? 'P1' : 'info',
    title: 'hold depois de unlist committed',
    pre: 'PATCH unlist; POST order',
    repro: 'sequential unlist then hold',
    proven: holdAfter.ok,
    evidence: {'http': holdAfter.status, 'body': holdAfter.snippet, 'pid': pidCtrl},
  ));

  // Checkout session on race order (product now unlisted)
  final payRace = await c.edge('create-payment-intent', jwt: c.buyerJwt, body: {
    'order_id': raceOid,
    'buyer_id': c.buyerId,
    'shipping_method': 'ctt',
  });
  final sessionIssued = payRace.ok &&
      (payRace.body.contains('checkoutUrl') ||
          payRace.body.contains('cs_') ||
          payRace.body.contains('checkoutSessionId'));
  add(finding(
    id: 'E10-UNLIST-CHECKOUT-SESSION',
    lens: 'E10',
    severity: sessionIssued ? 'P1' : 'info',
    title: 'create-payment-intent emite Session para order de produto já unlistado',
    pre: 'product list_on_marketplace=false + order pendente da race',
    repro: 'POST create-payment-intent order_id=raceOid',
    proven: sessionIssued,
    evidence: {
      'listed_now': listedNow,
      'http': payRace.status,
      'body': clip(payRace.body, 400),
    },
  ));
  out['pay_race'] = {'http': payRace.status, 'body': clip(payRace.body, 500)};

  // --- E1 cross-user is_live ---
  final patchAlien = await c.rest(
    'PATCH',
    'profiles?id=eq.${c.sellerId}',
    jwt: c.buyer2Jwt,
    body: {'is_live': true},
  );
  add(finding(
    id: 'E1-ISLIVE-CROSS-USER',
    lens: 'E1',
    severity: patchAlien.ok && (patchAlien.list.isNotEmpty) ? 'P1' : 'info',
    title: 'buyer2 PATCH is_live no perfil do seller',
    pre: 'PATCH profiles?id=seller',
    repro: 'PATCH is_live as buyer2',
    proven: patchAlien.ok && patchAlien.list.isNotEmpty,
    evidence: {'http': patchAlien.status, 'body': patchAlien.snippet},
  ));

  // Buyer self is_live → discovery (no hub_published)
  await c.rest(
    'PATCH',
    'profiles?id=eq.${c.buyer2Id}',
    jwt: c.buyer2Jwt,
    body: {
      'is_live': true,
      'hub_published': false,
      'full_name': '$prefix-buyer2-pii',
    },
  );
  final discB2 = await c.rest(
    'GET',
    'hub_profiles_discovery_public?id=eq.${c.buyer2Id}&select=id,full_name,location,hub_published,is_live,handle',
  );
  add(finding(
    id: 'E1-BUYER-ISLIVE-DISCOVERY',
    lens: 'E1',
    severity: discB2.list.isNotEmpty ? 'P2' : 'info',
    title: 'comprador unpublished entra na discovery só com is_live',
    pre: 'buyer2 PATCH is_live',
    repro: 'GET hub_profiles_discovery_public as anon',
    proven: discB2.list.isNotEmpty,
    evidence: {'disc': discB2.snippet},
  ));
  await c.rest(
    'PATCH',
    'profiles?id=eq.${c.buyer2Id}',
    service: true,
    body: {'is_live': false},
    prefer: 'return=minimal',
  );

  // Unpublished lives in discovery (count)
  final discLives = await c.rest(
    'GET',
    'hub_lives_discovery_public?select=id,seller_id,seller_name,status,mux_playback_id&limit=50',
  );
  final pubCheck = <String, bool>{};
  for (final row in discLives.list) {
    if (row is! Map) continue;
    final sid = row['seller_id']?.toString();
    if (sid == null || pubCheck.containsKey(sid)) continue;
    final p = await c.rest(
      'GET',
      'profiles?id=eq.$sid&select=id,hub_published,handle',
      service: true,
    );
    pubCheck[sid] = p.map?['hub_published'] == true;
  }
  final unpubSellers = pubCheck.entries.where((e) => e.value != true).length;
  add(finding(
    id: 'E1-DISCOVERY-LIVES-UNPUB-COUNT',
    lens: 'E1',
    severity: unpubSellers > 0 ? 'P2' : 'info',
    title: 'discovery lives inclui sellers hub_published=false ($unpubSellers)',
    pre: 'anon GET hub_lives_discovery_public + profiles service',
    repro: 'cross-check hub_published',
    proven: unpubSellers > 0,
    evidence: {
      'lives_n': discLives.list.length,
      'sellers_checked': pubCheck.length,
      'unpub_sellers': unpubSellers,
      'map': pubCheck,
      'fixture_live': endedLive,
    },
  ));

  // FOMO / items discovery on unpublished live
  final itemsDisc = await c.rest(
    'GET',
    'hub_live_items_discovery_public?live_id=eq.$endedLive&select=id,title,price,ref_code',
  );
  add(finding(
    id: 'E1-ITEMS-DISC-UNPUB',
    lens: 'E1',
    severity: itemsDisc.list.isNotEmpty ? 'P2' : 'info',
    title: 'itens de live unpublished na discovery',
    pre: 'GET hub_live_items_discovery_public',
    repro: 'live_id=ended unpublished',
    proven: itemsDisc.list.isNotEmpty,
    evidence: {'http': itemsDisc.status, 'body': itemsDisc.snippet},
  ));

  // Catalog oracle
  final cat = await c.rpc(
    'batata_product_bundles_catalog_subtotal',
    {
      'p_product_ids': [unlistedPid, soldPid],
    },
    jwt: c.buyerJwt,
  );
  add(finding(
    id: 'E4-CATALOG-ORACLE',
    lens: 'E4',
    severity: cat.body.contains('55') ? 'P3' : 'info',
    title: 'subtotal 55 = unlisted 22 + sold 33',
    pre: 'rpc catalog_subtotal',
    repro: 'rpc [unlisted,sold]',
    proven: cat.body.contains('55'),
    evidence: {'http': cat.status, 'body': cat.snippet},
  ));

  // Bundle mixed: try bag checkout quote (listed+unlisted orders)
  final holdListed = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': listedPid,
    'bundle_id': bundleUnlisted,
    'quantity': 1,
    'status': 'pendente',
    'price_total': 11.0,
    'shipping_method': 'ctt',
  });
  out['hold_listed_from_bundle'] = {
    'http': holdListed.status,
    'body': holdListed.snippet,
    'id': holdListed.firstId,
  };

  if (holdListed.ok && holdListed.firstId != null) {
    final bag = await c.edge('create-payment-intent', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'bag_checkout': true,
      'shipping_method': 'ctt',
      'bag_lines': [
        {'order_id': holdListed.firstId},
      ],
    });
    out['bag_listed'] = {'http': bag.status, 'body': clip(bag.body, 300)};
  }

  // notifications_view
  final nvAnon = await c.rest('GET', 'notifications_view?select=*&limit=5');
  final nvB2 = await c.rest(
    'GET',
    'notifications_view?select=*&limit=8',
    jwt: c.buyer2Jwt,
  );
  final nvAlien = nvB2.list.any((e) =>
      e is Map && e['target_user_id']?.toString() != c.buyer2Id);
  add(finding(
    id: 'E3-NOTIF-VIEW',
    lens: 'E3',
    severity: nvAnon.ok && nvAnon.list.isNotEmpty
        ? 'P1'
        : (nvAlien ? 'P1' : 'info'),
    title: 'notifications_view leak anon/cross-user',
    pre: 'GET notifications_view',
    repro: 'anon + buyer2',
    proven: (nvAnon.ok && nvAnon.list.isNotEmpty) || nvAlien,
    evidence: {
      'anon': {'http': nvAnon.status, 'n': nvAnon.list.length, 'snip': nvAnon.snippet},
      'b2': {'http': nvB2.status, 'n': nvB2.list.length, 'snip': nvB2.snippet},
    },
  ));

  // release as buyer2 on race order
  final relB2 = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': raceOid},
    jwt: c.buyer2Jwt,
  );
  add(finding(
    id: 'E2-RELEASE-ALIEN-ORDER',
    lens: 'E2',
    severity: relB2.ok && relB2.body.contains('true') ? 'P1' : 'info',
    title: 'buyer2 dispara release da order de buyer1',
    pre: 'rpc batata_release_seller_wallet_for_order',
    repro: 'rpc as buyer2',
    proven: relB2.ok && relB2.body.contains('true'),
    evidence: {'http': relB2.status, 'body': relB2.snippet},
  ));

  // follows burst
  var folOk = 0;
  for (var i = 0; i < 8; i++) {
    final f = await c.rest('POST', 'follows', jwt: c.buyer2Jwt, body: {
      'follower_id': c.buyer2Id,
      'following_id': c.sellerId,
    });
    if (f.ok) folOk++;
  }
  add(finding(
    id: 'E8-FOLLOW-BURST',
    lens: 'E8',
    severity: folOk >= 3 ? 'P3' : 'info',
    title: 'follows duplicados burst ${folOk}x',
    pre: 'POST follows 8x',
    repro: 'POST follows',
    proven: folOk >= 3,
    evidence: {'ok': folOk},
  ));

  // Deep link stripe-success with alien session via GET (already did)
  // Hub products of unpublished seller2
  final hubProdS2 = await c.rest(
    'GET',
    'hub_products_public?seller_id=eq.${c.seller2Id}',
  );
  out['hub_products_s2'] = {'http': hubProdS2.status, 'n': hubProdS2.list.length};

  out['findings'] = findings;
  out['proven'] = findings.where((f) => f['proven'] == true).toList();
  await dumpJson('tool/redteam_blind_e_orbita_$stamp/out/pass2.json', out);
  stdout.writeln('proven ${out['proven'].length} / ${findings.length}');
}
