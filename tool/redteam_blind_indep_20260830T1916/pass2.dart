/// PASS 2 — captura TEST 4242 no unlist+live_id ended + raffle freeze + live alheia.
/// Distinguir SESSION ≠ CAPTURA ≠ net permanente.
import 'dart:convert';
import 'dart:io';

import '_rti4.dart';

Future<void> main() async {
  final c = await boot();
  stderr.writeln('RTI4 pass2');

  const unlistPid = '8cc95520-3bff-4093-92b9-c556fe99dba7';
  const liveId = 'dc7a0dd9-6bb1-43ee-9899-d4b5bf93960d';
  const oidLive = 'edbabf9f-eabf-43b2-9582-fbe7269c8c85';
  const oidRaffle = '8450a8c0-5021-4ed3-9dfa-a0e6bd0db119';
  const csLive =
      'cs_test_a1g5rjxfzkHH912tV3dQehcK9CiPsKUa57m8aB3qtrAnx1UKsh2YawNXdN';

  Future<Map<String, dynamic>?> row(
      String table, String id, String cols) async {
    final r = await rest(
      c.url,
      'GET',
      '$table?id=eq.$id&select=$cols',
      headers: c.svcH,
    );
    final maps = asMaps(decode(r));
    return maps.isEmpty ? null : maps.first;
  }

  Future<dynamic> avail(String pid, {String? excl}) async {
    final r = await rpc(
      c.url,
      'batata_product_checkout_available',
      {
        'p_product_id': pid,
        'p_exclude_order_id': excl,
        'p_need_qty': 1,
      },
      headers: c.svcH,
    );
    return decode(r);
  }

  // --- Observe raffle hold (why Edge said not listed?) ---
  final raffleOrd = await row(
    'orders',
    oidRaffle,
    'id,status,product_id,live_id,live_item_id,live_raffle_id,quantity,buyer_id,stripe_checkout_session_id,amount_paid_cents',
  );
  rec(
    surface: 'observe',
    attack: 'raffle-hold order columns',
    identity: 'service_role',
    result: jsonEncode(raffleOrd),
  );

  final liveOrdBefore = await row(
    'orders',
    oidLive,
    'id,status,product_id,live_id,live_item_id,live_raffle_id,quantity,stripe_checkout_session_id,stripe_payment_intent_id,amount_paid_cents,price_total,contract_unit_cents,contract_qty',
  );
  rec(
    surface: 'observe',
    attack: 'unlist+live_id order BEFORE capture',
    identity: 'service_role',
    result: jsonEncode(liveOrdBefore),
  );

  final prodBefore = await row(
    'products',
    unlistPid,
    'id,quantity,is_sold,list_on_marketplace,price,title',
  );
  rec(
    surface: 'observe',
    attack: 'unlisted product BEFORE capture',
    identity: 'service_role',
    result: jsonEncode(prodBefore),
  );

  final hubBefore = await rest(
    c.url,
    'GET',
    'hub_products_public?id=eq.$unlistPid&select=id,title,is_sold',
    headers: c.anonH,
  );
  rec(
    surface: 'hub',
    attack: 'anon Hub SKU unlist before capture',
    identity: 'anon',
    result: briefBody(hubBefore),
  );

  final wBefore = await row('wallets', c.sellerId, 'id,balance');
  rec(
    surface: 'wallet',
    attack: 'seller wallet before capture',
    identity: 'observe',
    result: jsonEncode(wBefore),
  );

  rec(
    surface: 'stripe',
    attack: 'SESSION pending pay',
    identity: 'buyer',
    result: csLive,
    impact: 'SESSION CRIADA — captura via 4242 no browser/pass2b',
  );

  // --- Stock freeze: seller re-lists; fresh buyer tries hold ---
  final relist = await rest(
    c.url,
    'PATCH',
    'products?id=eq.$unlistPid',
    headers: c.sellerH,
    body: {'list_on_marketplace': true},
  );
  rec(
    surface: 'compose',
    attack: 'seller re-list while raffle+live holds exist',
    identity: 'seller',
    result: briefBody(relist),
  );
  final prodRelist = await row(
    'products',
    unlistPid,
    'id,quantity,is_sold,list_on_marketplace',
  );
  final stockNow = await avail(unlistPid);
  rec(
    surface: 'compose',
    attack: 'checkout_available after re-list with 2 holds',
    identity: 'observe',
    result: 'prod=$prodRelist avail=$stockNow',
  );

  if (c.freshH != null && c.freshId != null) {
    final freshHold = await rest(c.url, 'POST', 'orders', headers: c.freshH!,
        body: {
          'buyer_id': c.freshId,
          'seller_id': c.sellerId,
          'product_id': unlistPid,
          'quantity': 1,
          'price_total': 9.5,
          'status': 'reserva_pendente',
          'payment_method': 'pagamento na app',
          'shipping_method': 'carrier',
        });
    rec(
      surface: 'compose',
      attack: 'fresh hold after re-list (stock occupied by live_id+raffle holds)',
      identity: 'fresh',
      result: briefBody(freshHold),
    );
    if (freshHold.statusCode >= 400 &&
        freshHold.body.contains('order_hold_exceeds_stock')) {
      finding(
        id: 'RTI4-P1-RAFFLE-FREEZE',
        severity: 'P1',
        title:
            'live_raffle_id fake (ou live ended) congela stock após seller re-listar',
        actor: 'buyer JWT + fresh',
        pre: 'unlist holds via live_id ended + raffle UUID; seller lista de novo',
        repro: '2 holds sombra → PATCH list=true → 3.º JWT hold blocked',
        impact: 'capacidade económica bloqueada sem captura',
        evidence: {
          'avail': stockNow,
          'fresh': briefBody(freshHold),
          'raffle_ord': raffleOrd,
        },
      );
    }
  }

  // Unlist again so Hub stays empty for capture case
  await rest(
    c.url,
    'PATCH',
    'products?id=eq.$unlistPid',
    headers: c.sellerH,
    body: {'list_on_marketplace': false},
  );

  // --- Foreign live_id (other seller) ---
  final otherLive = await rest(
    c.url,
    'GET',
    'lives?seller_id=neq.${c.sellerId}&select=id,seller_id,status,is_active&limit=1',
    headers: c.svcH,
  );
  rec(
    surface: 'fixture',
    attack: 'pick foreign live',
    identity: 'service_role',
    result: briefBody(otherLive),
  );
  final otherMaps = asMaps(decode(otherLive));
  if (otherMaps.isNotEmpty) {
    final flid = otherMaps.first['id']?.toString();
    final pid2 = await rest(c.url, 'POST', 'products', headers: c.svcH, body: {
      'seller_id': c.sellerId,
      'title': '$prefix unlist-foreign-live',
      'price': 8.0,
      'quantity': 1,
      'is_sold': false,
      'list_on_marketplace': false,
      'image_urls': <String>[],
    });
    final p2 = firstId(decode(pid2));
    if (p2 != null && flid != null) {
      final o = await rest(c.url, 'POST', 'orders', headers: c.buyerH, body: {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': p2,
        'quantity': 1,
        'price_total': 8.0,
        'status': 'reserva_pendente',
        'payment_method': 'pagamento na app',
        'shipping_method': 'carrier',
        'live_id': flid,
      });
      rec(
        surface: 'hold',
        attack: 'unlist + live_id de OUTRO seller',
        identity: 'buyer',
        result: briefBody(o),
      );
    }
  }

  // --- is_sold + live_id ended ---
  final pidSold = '2dd7123b-55ea-474e-a8a7-b86da88ddb16';
  final soldLive = await rest(c.url, 'POST', 'orders', headers: c.buyerH, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pidSold,
    'quantity': 1,
    'price_total': 9.5,
    'status': 'reserva_pendente',
    'payment_method': 'pagamento na app',
    'shipping_method': 'carrier',
    'live_id': liveId,
  });
  rec(
    surface: 'hold',
    attack: 'is_sold + live_id ended',
    identity: 'buyer',
    result: briefBody(soldLive),
  );

  // --- Bag checkout of unlist WITH live_id on the order (oidLive) ---
  final bagLive = await edge(c.url, 'create-payment-intent', {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': unlistPid,
    'order_id': oidLive,
    'quantity': 1,
    'currency': 'eur',
    'shipping_method': 'carrier',
    'bag_checkout': true,
    'bag_lines': [
      {
        'order_id': oidLive,
        'product_id': unlistPid,
        'seller_id': c.sellerId,
        'quantity': 1,
      }
    ],
  }, headers: c.buyerH);
  rec(
    surface: 'edge.checkout',
    attack: 'BAG unlist + live_id ended (order already has session?)',
    identity: 'buyer',
    result: briefBody(bagLive),
  );

  // --- Dual session? second single checkout same order ---
  final ck2 = await edge(c.url, 'create-payment-intent', {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': unlistPid,
    'order_id': oidLive,
    'quantity': 1,
    'currency': 'eur',
    'shipping_method': 'carrier',
  }, headers: c.buyerH);
  rec(
    surface: 'edge.checkout',
    attack: 'second Session same unlist+live order',
    identity: 'buyer',
    result: briefBody(ck2),
  );

  await dumpJson('pass2', {
    'auditor': 'REDTEAM_BLIND_INDEP_v4',
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
    'cs_to_pay': csLive,
    'oid_live': oidLive,
    'findings': findings,
    'matrix': matrix,
    'gaps': gaps,
    'note':
        'Pagar cs_test com 4242; depois pass2b observa captura/stock/wallet.',
  });
  stderr.writeln('pass2 done findings=${findings.length}');
}
