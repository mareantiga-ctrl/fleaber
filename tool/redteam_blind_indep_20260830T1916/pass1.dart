/// PASS 1 — segunda onda: morto/montra, pós-caixa, política fina, órbita.
/// Auditor cego. Não corrige. Staging only.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '_rti4.dart';

Future<void> main() async {
  final c = await boot();
  final t = tag();
  stderr.writeln('RTI4 pass1 $t');

  Future<http.Response> g(
    String path, {
    required Map<String, String> h,
  }) =>
      rest(c.url, 'GET', path, headers: h);

  Future<String?> mkProduct({
    required String title,
    bool listed = true,
    bool sold = false,
    int qty = 2,
    double price = 9.5,
    String? seller,
  }) async {
    final r = await rest(c.url, 'POST', 'products', headers: c.svcH, body: {
      'seller_id': seller ?? c.sellerId,
      'title': '$prefix $title',
      'price': price,
      'quantity': qty,
      'is_sold': sold,
      'list_on_marketplace': listed,
      'available_for_live': false,
      'description': t,
      'image_urls': <String>[],
    });
    rec(
      surface: 'fixture',
      attack: 'svc insert product $title listed=$listed sold=$sold',
      identity: 'service_role',
      result: briefBody(r),
    );
    return firstId(decode(r));
  }

  Future<String?> mkOrder({
    required String pid,
    required Map<String, String> h,
    required String buyer,
    String? liveId,
    String? liveItemId,
    String? liveRaffleId,
    String status = 'reserva_pendente',
    double price = 9.5,
    int qty = 1,
    String ship = 'carrier',
    String pay = 'pagamento na app',
  }) async {
    final body = <String, dynamic>{
      'buyer_id': buyer,
      'seller_id': c.sellerId,
      'product_id': pid,
      'quantity': qty,
      'price_total': price,
      'status': status,
      'payment_method': pay,
      'shipping_method': ship,
    };
    if (liveId != null) body['live_id'] = liveId;
    if (liveItemId != null) body['live_item_id'] = liveItemId;
    if (liveRaffleId != null) body['live_raffle_id'] = liveRaffleId;
    final r = await rest(c.url, 'POST', 'orders', headers: h, body: body);
    rec(
      surface: 'orders.insert',
      attack: 'hold pid=$pid live=$liveId raffle=$liveRaffleId item=$liveItemId',
      identity: h == c.buyerH
          ? 'buyer'
          : h == c.sellerH
              ? 'seller'
              : h == c.anonH
                  ? 'anon'
                  : 'other',
      result: briefBody(r),
    );
    return firstId(decode(r));
  }

  Future<http.Response> checkoutSingle(String oid, String pid,
      {Map<String, String>? h, Map<String, dynamic>? extra}) {
    return edge(c.url, 'create-payment-intent', {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'order_id': oid,
      'quantity': 1,
      'amount': 1,
      'currency': 'eur',
      'shipping_method': 'carrier',
      ...?extra,
    }, headers: h ?? c.buyerH);
  }

  Future<http.Response> checkoutBag(List<Map<String, dynamic>> lines,
      {Map<String, String>? h}) {
    return edge(c.url, 'create-payment-intent', {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': lines.first['product_id'],
      'order_id': lines.first['order_id'],
      'quantity': 1,
      'amount': 1,
      'currency': 'eur',
      'shipping_method': 'carrier',
      'bag_checkout': true,
      'bag_lines': lines,
    }, headers: h ?? c.buyerH);
  }

  Future<Map<String, dynamic>?> row(
      String table, String id, String cols) async {
    final r = await g('$table?id=eq.$id&select=$cols', h: c.svcH);
    final maps = asMaps(decode(r));
    return maps.isEmpty ? null : maps.first;
  }

  // ------------------------------------------------------------------
  // Fresh buyer (signup fixture via admin — allowed)
  // ------------------------------------------------------------------
  wells['orbita'] = true;
  final freshEmail =
      'rti4.${DateTime.now().toUtc().millisecondsSinceEpoch}@fleaber.invalid';
  try {
    final fid = await c.admin.createAdminUser(
      email: freshEmail,
      password: 'TesteTeste1!',
      userMetadata: {'full_name': 'RTI4 fresh'},
    );
    final fj = await c.admin.signIn(
      email: freshEmail,
      password: 'TesteTeste1!',
    );
    c.freshId = fid;
    c.freshJwt = fj;
    rec(
      surface: 'auth',
      attack: 'signup fresh buyer',
      identity: 'service_role+jwt',
      result: 'ok $fid',
    );
  } catch (e) {
    rec(
      surface: 'auth',
      attack: 'signup fresh buyer',
      identity: 'service_role',
      result: 'FAIL $e',
    );
    gaps.add('fresh buyer signup failed: $e');
  }

  // ------------------------------------------------------------------
  // Fixtures
  // ------------------------------------------------------------------
  final pidListed = await mkProduct(title: 'listed-ok', listed: true, qty: 2);
  final pidUnlisted =
      await mkProduct(title: 'unlisted-shadow', listed: false, qty: 2);
  final pidSold =
      await mkProduct(title: 'sold-dead', listed: true, sold: true, qty: 1);
  final pidSoldUnlist = await mkProduct(
      title: 'sold-unlist', listed: false, sold: true, qty: 1);
  final pidBagUnlist =
      await mkProduct(title: 'bag-then-unlist', listed: true, qty: 2);
  final pidQty1 = await mkProduct(title: 'qty1-race', listed: true, qty: 1);
  final pidHubSold =
      await mkProduct(title: 'hub-sold-still-listed', listed: true, sold: true, qty: 0);

  String? endedLiveId;
  String? liveItemId;
  String? raffleId;
  try {
    final live = await c.admin.insert('lives', {
      'title': '$prefix ended-live',
      'status': 'ended',
      'seller_id': c.sellerId,
      'vendedor_id': c.sellerId,
      'is_active': false,
    });
    endedLiveId = live['id']?.toString();
    rec(
      surface: 'fixture',
      attack: 'ended live',
      identity: 'service_role',
      result: '$endedLiveId',
    );
  } catch (e) {
    rec(
      surface: 'fixture',
      attack: 'ended live',
      identity: 'service_role',
      result: '$e',
    );
  }

  if (endedLiveId != null && pidUnlisted != null) {
    try {
      final item = await c.admin.insert('live_items', {
        'live_id': endedLiveId,
        'title': '$prefix ended-item',
        'price': 9.5,
        'product_id': pidUnlisted,
        'checkout_product_id': pidUnlisted,
        'seller_id': c.sellerId,
        'is_active': false,
        'status': 'ended',
      });
      liveItemId = item['id']?.toString();
    } catch (e) {
      rec(
        surface: 'fixture',
        attack: 'live_item ended',
        identity: 'service_role',
        result: '$e',
      );
    }
    try {
      final rf = await c.admin.insert('live_raffles', {
        'live_id': endedLiveId,
        'seller_id': c.sellerId,
        'status': 'ended',
      });
      raffleId = rf['id']?.toString();
    } catch (e) {
      rec(
        surface: 'fixture',
        attack: 'live_raffles insert',
        identity: 'service_role',
        result: '$e',
      );
    }
  }

  // Unpublished hub profile (second seller)
  String? ghostSellerId;
  try {
    final ghostEmail =
        'rti4.ghost.${DateTime.now().toUtc().millisecondsSinceEpoch}@fleaber.invalid';
    ghostSellerId = await c.admin.createAdminUser(
      email: ghostEmail,
      password: 'TesteTeste1!',
      userMetadata: {'full_name': 'RTI4 Ghost'},
    );
  } catch (e) {
    rec(
      surface: 'fixture',
      attack: 'ghost unpublished seller',
      identity: 'service_role',
      result: '$e',
    );
  }
  if (ghostSellerId != null) {
    await rest(c.url, 'PATCH', 'profiles?id=eq.$ghostSellerId',
        headers: c.svcH,
        body: {
          'hub_published': false,
          'full_name': 'RTI4 Ghost Unpublished',
        });
  }

  // ------------------------------------------------------------------
  // POÇO 1 — MORTO / MONTRA
  // ------------------------------------------------------------------
  wells['morto_montra'] = true;

  // Anon hub vs base table
  if (pidHubSold != null) {
    final hubSold = await g(
      'hub_products_public?id=eq.$pidHubSold&select=id,title,is_sold,price,seller_handle',
      h: c.anonH,
    );
    rec(
      surface: 'hub_products_public',
      attack: 'anon GET sold+listed',
      identity: 'anon',
      result: briefBody(hubSold),
    );
    final rows = asMaps(decode(hubSold));
    if (rows.isNotEmpty) {
      finding(
        id: 'RTI4-P1-HUB-SOLD',
        severity: 'P2',
        title: 'Hub público lista produto is_sold=true se ainda list_on_marketplace',
        actor: 'anon',
        pre: 'produto is_sold=true e list_on_marketplace=true',
        repro: 'GET hub_products_public?id=eq.<sold>',
        impact: 'vitrine mostra mortos; compra depende do gate de checkout',
        evidence: rows,
      );
    }
  }

  final baseSoldAnon = await g(
    'products?is_sold=eq.true&select=id,title,is_sold,list_on_marketplace,price,seller_id&limit=5',
    h: c.anonH,
  );
  rec(
    surface: 'products',
    attack: 'anon GET is_sold=true tabela base',
    identity: 'anon',
    result: briefBody(baseSoldAnon),
  );

  final unlistedAnon = pidUnlisted == null
      ? null
      : await g(
          'products?id=eq.$pidUnlisted&select=id,title,list_on_marketplace,is_sold',
          h: c.anonH,
        );
  if (unlistedAnon != null) {
    rec(
      surface: 'products',
      attack: 'anon GET unlisted id',
      identity: 'anon',
      result: briefBody(unlistedAnon),
    );
  }

  final hubUnlisted = pidUnlisted == null
      ? null
      : await g(
          'hub_products_public?id=eq.$pidUnlisted&select=id,title',
          h: c.anonH,
        );
  if (hubUnlisted != null) {
    rec(
      surface: 'hub_products_public',
      attack: 'anon GET unlisted',
      identity: 'anon',
      result: briefBody(hubUnlisted),
    );
  }

  // JWT hold sold / unlisted / raffle-forge / live-forge
  if (pidSold != null) {
    final oidSold = await mkOrder(pid: pidSold, h: c.buyerH, buyer: c.buyerId);
    rec(
      surface: 'hold',
      attack: 'JWT hold is_sold',
      identity: 'buyer',
      result: oidSold == null ? 'blocked' : 'HOLD CREATED $oidSold',
      impact: oidSold != null ? 'stock hold em morto' : '',
      severity: oidSold != null ? 'P1' : '',
    );
    if (oidSold != null) {
      finding(
        id: 'RTI4-P1-HOLD-SOLD',
        severity: 'P1',
        title: 'JWT cria hold em produto is_sold',
        actor: 'buyer JWT',
        pre: 'is_sold=true list_on_marketplace=true qty=1',
        repro: 'POST orders product_id=sold status=reserva_pendente',
        impact: 'unidade morta reservável',
        evidence: {'oid': oidSold, 'pid': pidSold},
      );
      final ck = await checkoutSingle(oidSold, pidSold);
      rec(
        surface: 'edge.checkout',
        attack: 'single checkout after sold-hold',
        identity: 'buyer',
        result: briefBody(ck),
      );
      if (looksSession(ck)) {
        finding(
          id: 'RTI4-P1-CK-SOLD',
          severity: 'P1',
          title: 'Checkout Session em produto is_sold',
          actor: 'buyer JWT + Edge',
          pre: 'hold em is_sold',
          repro: 'POST create-payment-intent order is_sold',
          impact: 'SESSION CRIADA (≠ captura)',
          evidence: briefBody(ck),
        );
      }
    }
  }

  if (pidUnlisted != null) {
    final oidU = await mkOrder(pid: pidUnlisted, h: c.buyerH, buyer: c.buyerId);
    rec(
      surface: 'hold',
      attack: 'JWT hold unlisted sem live',
      identity: 'buyer',
      result: oidU == null ? 'blocked' : 'HOLD CREATED $oidU',
    );
    if (oidU != null) {
      finding(
        id: 'RTI4-P1-HOLD-UNLIST',
        severity: 'P1',
        title: 'JWT hold em produto list_on_marketplace=false sem live',
        actor: 'buyer JWT',
        pre: 'unlist, sem live_*',
        repro: 'POST orders unlisted',
        impact: 'montra vazia mas PostgREST vende',
        evidence: {'oid': oidU, 'pid': pidUnlisted},
      );
    }

    // live_id of ended live (same seller)
    if (endedLiveId != null) {
      final oidLive = await mkOrder(
        pid: pidUnlisted,
        h: c.buyerH,
        buyer: c.buyerId,
        liveId: endedLiveId,
      );
      rec(
        surface: 'hold',
        attack: 'JWT hold unlisted + live_id ended',
        identity: 'buyer',
        result: oidLive == null ? 'blocked' : 'HOLD CREATED $oidLive',
      );
      if (oidLive != null) {
        finding(
          id: 'RTI4-P1-LIVEID-UNLIST',
          severity: 'P1',
          title: 'live_id de directo ended bypassa unlist no hold',
          actor: 'buyer JWT',
          pre: 'product unlist; lives.status=ended is_active=false',
          repro: 'POST orders live_id=<ended> product unlist',
          impact: 'sombra morta vendável via JWT',
          evidence: {'oid': oidLive, 'live': endedLiveId},
        );
        final ck = await checkoutSingle(oidLive, pidUnlisted);
        rec(
          surface: 'edge.checkout',
          attack: 'single checkout unlist+ended live_id',
          identity: 'buyer',
          result: briefBody(ck),
        );
        if (looksSession(ck)) {
          finding(
            id: 'RTI4-P1-CK-LIVEID-UNLIST',
            severity: 'P1',
            title: 'Edge cria Session para unlist com live_id ended',
            actor: 'buyer JWT + Edge',
            pre: 'hold com live_id ended',
            repro: 'create-payment-intent',
            impact: 'SESSION CRIADA em montra vazia',
            evidence: briefBody(ck),
          );
        }
      }
    }

    // live_raffle_id forge (random UUID — no coherence on raffle)
    final fakeRaffle = '00000000-0000-4000-8000-000000000001';
    final oidRaffle = await mkOrder(
      pid: pidUnlisted,
      h: c.buyerH,
      buyer: c.buyerId,
      liveRaffleId: raffleId ?? fakeRaffle,
    );
    rec(
      surface: 'hold',
      attack: 'JWT hold unlisted + live_raffle_id',
      identity: 'buyer',
      result: oidRaffle == null ? 'blocked' : 'HOLD CREATED $oidRaffle',
    );
    if (oidRaffle != null) {
      finding(
        id: 'RTI4-P1-RAFFLE-UNLIST',
        severity: 'P1',
        title: 'live_raffle_id bypassa unlist no hold (sem live_item)',
        actor: 'buyer JWT',
        pre: 'unlist; live_raffle_id set',
        repro: 'POST orders live_raffle_id=… product unlist',
        impact: 'flag live_raffle_id = v_live_ok no trigger de hold',
        evidence: {
          'oid': oidRaffle,
          'raffle': raffleId ?? fakeRaffle,
        },
      );
      final ck = await checkoutSingle(oidRaffle, pidUnlisted);
      rec(
        surface: 'edge.checkout',
        attack: 'single checkout unlist+raffle flag',
        identity: 'buyer',
        result: briefBody(ck),
      );
      if (looksSession(ck)) {
        finding(
          id: 'RTI4-P1-CK-RAFFLE-UNLIST',
          severity: 'P1',
          title: 'Edge Session em unlist via live_raffle_id',
          actor: 'buyer JWT + Edge',
          pre: 'hold com raffle flag',
          repro: 'create-payment-intent',
          impact: 'SESSION CRIADA',
          evidence: briefBody(ck),
        );
      }
    }
  }

  // Composition: hold while listed → unlist → bag + single
  if (pidBagUnlist != null) {
    final oidA =
        await mkOrder(pid: pidBagUnlist, h: c.buyerH, buyer: c.buyerId);
    final before = await row(
        'products', pidBagUnlist, 'id,quantity,is_sold,list_on_marketplace');
    final unl = await rest(
      c.url,
      'PATCH',
      'products?id=eq.$pidBagUnlist',
      headers: c.sellerH,
      body: {'list_on_marketplace': false},
    );
    rec(
      surface: 'products.patch',
      attack: 'seller unlist after hold',
      identity: 'seller',
      result: briefBody(unl),
    );
    final after = await row(
        'products', pidBagUnlist, 'id,quantity,is_sold,list_on_marketplace');
    rec(
      surface: 'compose',
      attack: 'state after unlist',
      identity: 'observe',
      result: 'before=$before after=$after oid=$oidA',
    );
    if (oidA != null) {
      final ckS = await checkoutSingle(oidA, pidBagUnlist);
      rec(
        surface: 'edge.checkout',
        attack: 'single after unlist (hold existente)',
        identity: 'buyer',
        result: briefBody(ckS),
      );
      final ckB = await checkoutBag([
        {
          'order_id': oidA,
          'product_id': pidBagUnlist,
          'seller_id': c.sellerId,
          'quantity': 1,
        }
      ]);
      rec(
        surface: 'edge.checkout',
        attack: 'BAG after unlist (hold existente)',
        identity: 'buyer',
        result: briefBody(ckB),
      );
      if (looksSession(ckS) || looksSession(ckB)) {
        finding(
          id: 'RTI4-P1-COMPOSE-UNLIST-CK',
          severity: 'P1',
          title: 'Hold pré-unlist → Edge ainda cria Session após montra vazia',
          actor: 'buyer JWT + Edge',
          pre: 'order pendente; seller list_on_marketplace=false',
          repro: 'hold → PATCH unlist → create-payment-intent single e bag',
          impact:
              'composição: Hub vazio + Session. Distinguir SESSION≠CAPTURA.',
          evidence: {
            'single': briefBody(ckS),
            'bag': briefBody(ckB),
            'before': before,
            'after': after,
          },
        );
      }
    }
  }

  // Bundle with sold products
  if (pidSold != null && pidListed != null) {
    final bun = await rest(c.url, 'POST', 'product_bundles',
        headers: c.buyerH,
        body: {
          'buyer_id': c.buyerId,
          'seller_id': c.sellerId,
          'product_ids': [pidSold, pidListed],
          'status': 'pending',
          'total_eur': 1.0,
        });
    rec(
      surface: 'product_bundles',
      attack: 'buyer INSERT bundle incl is_sold',
      identity: 'buyer',
      result: briefBody(bun),
    );
    final bid = firstId(decode(bun));
    if (bid != null) {
      final acc = await rest(
        c.url,
        'PATCH',
        'product_bundles?id=eq.$bid',
        headers: c.sellerH,
        body: {'status': 'accepted'},
      );
      rec(
        surface: 'product_bundles',
        attack: 'seller accept bundle with sold SKU',
        identity: 'seller',
        result: briefBody(acc),
      );
    }
    final selfAcc = await rest(c.url, 'POST', 'product_bundles',
        headers: c.buyerH,
        body: {
          'buyer_id': c.buyerId,
          'seller_id': c.buyerId,
          'product_ids': [pidListed],
          'status': 'accepted',
          'total_eur': 0.01,
        });
    rec(
      surface: 'product_bundles',
      attack: 'buyer self-accept bundle',
      identity: 'buyer',
      result: briefBody(selfAcc),
    );
  }

  // ------------------------------------------------------------------
  // POÇO 2 — PÓS-CAIXA
  // ------------------------------------------------------------------
  wells['pos_caixa'] = true;

  String? paidOid;
  String? paidPid;
  if (pidListed != null) {
    try {
      final prod = await c.admin.insert('products', {
        'seller_id': c.sellerId,
        'title': '$prefix paid-fixture',
        'price': 12.0,
        'quantity': 3,
        'is_sold': false,
        'list_on_marketplace': true,
        'image_urls': <String>[],
      });
      paidPid = prod['id']?.toString();
      final ord = await c.admin.insert('orders', {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': paidPid,
        'quantity': 1,
        'price_total': 12.0,
        'status': 'pago',
        'payment_method': 'pagamento na app',
        'shipping_method': 'carrier',
        'amount_paid_cents': 1640,
        'stripe_payment_intent_id': 'pi_rti4_fixture_$t',
      });
      paidOid = ord['id']?.toString();
      rec(
        surface: 'fixture',
        attack: 'svc paid order',
        identity: 'service_role',
        result: 'oid=$paidOid pid=$paidPid',
      );
    } catch (e) {
      rec(
        surface: 'fixture',
        attack: 'svc paid order',
        identity: 'service_role',
        result: '$e',
      );
      gaps.add('paid fixture: $e');
    }
  }

  Future<void> jump(String who, Map<String, String> h, String status) async {
    if (paidOid == null) return;
    final before = await row('orders', paidOid!,
        'id,status,wallet_release_processed_at,amount_paid_cents,buyer_id,seller_id');
    final r = await rest(
      c.url,
      'PATCH',
      'orders?id=eq.$paidOid',
      headers: h,
      body: {'status': status},
    );
    final after = await row('orders', paidOid!,
        'id,status,wallet_release_processed_at,amount_paid_cents');
    rec(
      surface: 'orders.status',
      attack: '$who PATCH status=$status (silent?)',
      identity: who,
      result:
          'http=${r.statusCode} before=${before?['status']} after=${after?['status']} body=${briefBody(r)}',
    );
    if (after != null &&
        before != null &&
        after['status'] != before['status'] &&
        r.statusCode < 300) {
      rec(
        surface: 'orders.status',
        attack: 'STATUS CHANGED $who → $status',
        identity: who,
        result: '${before['status']} → ${after['status']}',
        impact: 'salto persistido',
      );
    }
  }

  await jump('buyer', c.buyerH, 'concluido');
  await jump('buyer', c.buyerH, 'enviado');
  await jump('seller', c.sellerH, 'enviado');
  await jump('buyer', c.buyerH, 'concluido');
  if (c.freshH != null && paidOid != null) {
    await jump('fresh', c.freshH!, 'concluido');
  }

  // JWT ≠ body: refund other order, release other, dispute
  if (paidOid != null) {
    final relBuyer = await rpc(
      c.url,
      'batata_release_seller_wallet_for_order',
      {'p_order_id': paidOid},
      headers: c.buyerH,
    );
    rec(
      surface: 'release',
      attack: 'buyer JWT release paid fixture',
      identity: 'buyer',
      result: briefBody(relBuyer),
    );
    final relSeller = await rpc(
      c.url,
      'batata_release_seller_wallet_for_order',
      {'p_order_id': paidOid},
      headers: c.sellerH,
    );
    rec(
      surface: 'release',
      attack: 'seller JWT release (not buyer)',
      identity: 'seller',
      result: briefBody(relSeller),
    );
    if (c.freshH != null) {
      final relF = await rpc(
        c.url,
        'batata_release_seller_wallet_for_order',
        {'p_order_id': paidOid},
        headers: c.freshH!,
      );
      rec(
        surface: 'release',
        attack: 'fresh JWT release alien order',
        identity: 'fresh',
        result: briefBody(relF),
      );
    }
    final wBefore = await g(
      'wallets?id=eq.${c.sellerId}&select=id,balance',
      h: c.svcH,
    );

    final refund = await edge(c.url, 'refund-order', {
      'order_id': paidOid,
    }, headers: c.sellerH);
    rec(
      surface: 'edge.refund',
      attack: 'seller refund fixture PI fake',
      identity: 'seller',
      result: briefBody(refund),
    );
    if (c.freshH != null) {
      final refundF = await edge(c.url, 'refund-order', {
        'order_id': paidOid,
      }, headers: c.freshH!);
      rec(
        surface: 'edge.refund',
        attack: 'fresh refund alien order',
        identity: 'fresh',
        result: briefBody(refundF),
      );
    }

    final disp = await rest(c.url, 'POST', 'order_disputes', headers: c.buyerH,
        body: {
          'order_id': paidOid,
          'buyer_id': c.buyerId,
          'status': 'aberta',
          'reason': '$prefix dispute',
        });
    rec(
      surface: 'order_disputes',
      attack: 'buyer open dispute on fixture',
      identity: 'buyer',
      result: briefBody(disp),
    );
    final relAfterDisp = await rpc(
      c.url,
      'batata_release_seller_wallet_for_order',
      {'p_order_id': paidOid},
      headers: c.buyerH,
    );
    rec(
      surface: 'release',
      attack: 'buyer release while dispute open',
      identity: 'buyer',
      result: briefBody(relAfterDisp),
    );

    // seller close dispute
    final did = firstId(decode(disp));
    if (did != null) {
      final close = await rest(
        c.url,
        'PATCH',
        'order_disputes?id=eq.$did',
        headers: c.sellerH,
        body: {'status': 'fechada'},
      );
      rec(
        surface: 'order_disputes',
        attack: 'seller PATCH dispute fechada',
        identity: 'seller',
        result: briefBody(close),
      );
    }

    final wAfter = await g(
      'wallets?id=eq.${c.sellerId}&select=id,balance',
      h: c.svcH,
    );
    rec(
      surface: 'wallet',
      attack: 'seller wallet Δ after release/dispute',
      identity: 'observe',
      result: 'before=${briefBody(wBefore)} after=${briefBody(wAfter)}',
    );

    final afterPaid = await row('orders', paidOid!,
        'id,status,wallet_release_processed_at,wallet_refund_processed_at,amount_paid_cents,stripe_refund_id');
    rec(
      surface: 'orders.final',
      attack: 'paid fixture estado final',
      identity: 'observe',
      result: jsonEncode(afterPaid),
    );
  }

  // Reviews forge
  final rev = await rest(c.url, 'POST', 'reviews', headers: c.buyerH, body: {
    'target_id': c.sellerId,
    'buyer_id': c.buyerId,
    'stars': 1,
    'comment': '$prefix forged',
    'target_type': 'seller',
    'author_role': 'comprador',
    'is_automatic': false,
  });
  rec(
    surface: 'reviews',
    attack: 'buyer INSERT review sem order_id',
    identity: 'buyer',
    result: briefBody(rev),
  );
  if (c.freshH != null && paidOid != null) {
    final revF = await rest(c.url, 'POST', 'reviews', headers: c.freshH!, body: {
      'target_id': c.sellerId,
      'buyer_id': c.freshId,
      'stars': 5,
      'comment': '$prefix stolen order',
      'order_id': paidOid,
      'target_type': 'seller',
      'author_role': 'comprador',
    });
    rec(
      surface: 'reviews',
      attack: 'fresh review on alien order_id',
      identity: 'fresh',
      result: briefBody(revF),
    );
  }

  // Dual GET settle forged
  final settleFake = await edge(
    c.url,
    'create-payment-intent',
    null,
    headers: c.anonH,
    method: 'GET',
    query: {
      'session_id': 'cs_test_rti4_forged',
      'checkout_return': 'success',
    },
  );
  rec(
    surface: 'edge.settle',
    attack: 'GET settle session forjada',
    identity: 'anon',
    result: briefBody(settleFake),
  );

  // ------------------------------------------------------------------
  // POÇO 3 — POLÍTICA FINA
  // ------------------------------------------------------------------
  wells['politica_fina'] = true;

  final notifAnon = await g('notifications_view?select=*&limit=5', h: c.anonH);
  rec(
    surface: 'notifications_view',
    attack: 'anon SELECT',
    identity: 'anon',
    result: briefBody(notifAnon),
  );
  final notifBuyer =
      await g('notifications_view?select=*&limit=20', h: c.buyerH);
  rec(
    surface: 'notifications_view',
    attack: 'buyer SELECT (should be empty — not seller of favs)',
    identity: 'buyer',
    result: briefBody(notifBuyer),
  );
  final notifSeller =
      await g('notifications_view?select=*&limit=20', h: c.sellerH);
  rec(
    surface: 'notifications_view',
    attack: 'seller SELECT own favs',
    identity: 'seller',
    result: briefBody(notifSeller),
  );

  // Cross-user products via live shadow
  if (pidUnlisted != null) {
    final shadow = await g(
      'products?id=eq.$pidUnlisted&select=id,title,list_on_marketplace,is_sold,price',
      h: c.buyerH,
    );
    rec(
      surface: 'products.rls',
      attack: 'buyer SELECT unlisted (shadow live ended?)',
      identity: 'buyer',
      result: briefBody(shadow),
    );
  }

  // Unpublished discovery
  if (ghostSellerId != null) {
    final disc = await g(
      'hub_profiles_discovery_public?id=eq.$ghostSellerId&select=id,handle,hub_published,full_name',
      h: c.anonH,
    );
    rec(
      surface: 'hub_profiles_discovery_public',
      attack: 'anon unpublished ghost',
      identity: 'anon',
      result: briefBody(disc),
    );
    final pub = await g(
      'hub_profiles_public?id=eq.$ghostSellerId&select=id,handle,full_name',
      h: c.anonH,
    );
    rec(
      surface: 'hub_profiles_public',
      attack: 'anon unpublished ghost',
      identity: 'anon',
      result: briefBody(pub),
    );
  }

  // Edge blocks vs INSERT: buyer INSERT status=pago
  if (pidListed != null) {
    final pagoIns = await mkOrder(
      pid: pidListed,
      h: c.buyerH,
      buyer: c.buyerId,
      status: 'pago',
    );
    rec(
      surface: 'orders.insert',
      attack: 'buyer INSERT status=pago',
      identity: 'buyer',
      result: pagoIns == null ? 'no row' : 'row $pagoIns',
    );
    if (pagoIns != null) {
      final st = await row('orders', pagoIns, 'id,status,amount_paid_cents');
      rec(
        surface: 'orders.insert',
        attack: 'observe status after INSERT pago',
        identity: 'observe',
        result: jsonEncode(st),
      );
    }
  }

  // FOMO anon
  if (endedLiveId != null) {
    final fomo = await rpc(
      c.url,
      'batata_hub_live_fomo_snapshot',
      {'p_live_id': endedLiveId},
      headers: c.anonH,
    );
    rec(
      surface: 'fomo',
      attack: 'anon FOMO ended live',
      identity: 'anon',
      result: briefBody(fomo),
    );
  }

  // Admin RPC
  final adminRpc = await rpc(
    c.url,
    'batata_admin_resolve_dispute',
    {
      'p_dispute_id': paidOid ?? c.buyerId,
      'p_resolution': 'favor_buyer',
      'p_note': 'rti4',
    },
    headers: c.anonH,
  );
  rec(
    surface: 'admin.rpc',
    attack: 'anon admin_resolve_dispute',
    identity: 'anon',
    result: briefBody(adminRpc),
  );

  // ------------------------------------------------------------------
  // POÇO 4 — ÓRBITA
  // ------------------------------------------------------------------
  wells['orbita'] = true;

  final cronFns = <String, Object?>{
    'batata_generate_auto_feedback': {
      'p_now': DateTime.utc(2099, 1, 1).toIso8601String(),
    },
    'batata_release_seller_wallet_for_order': {
      'p_order_id': paidOid ?? c.buyerId,
    },
    'batata_invoke_livekit_egress_cleanup': <String, dynamic>{},
    'batata_tick_live_raffle': {
      'p_raffle_id': raffleId ?? c.buyerId,
    },
    'batata_expire_product_offers': <String, dynamic>{},
  };
  for (final e in cronFns.entries) {
    for (final ident in [
      ('anon', c.anonH),
      ('buyer', c.buyerH),
      ('seller', c.sellerH),
    ]) {
      final r = await rpc(c.url, e.key, e.value, headers: ident.$2);
      rec(
        surface: 'cron.rpc',
        attack: '${ident.$1} EXECUTE ${e.key}',
        identity: ident.$1,
        result: briefBody(r),
      );
      final ok = r.statusCode == 200 &&
          !r.body.toLowerCase().contains('permission') &&
          !r.body.toLowerCase().contains('not_allowed') &&
          r.body.trim() != 'false' &&
          r.body.trim() != 'null';
      if (ok &&
          ident.$1 != 'service' &&
          (e.key.contains('auto_feedback') ||
              e.key.contains('egress') ||
              e.key.contains('expire'))) {
        finding(
          id: 'RTI4-P4-CRON-${e.key}',
          severity: 'P2',
          title: 'JWT/anon executa job ${e.key}',
          actor: ident.$1,
          pre: 'RPC grant',
          repro: 'POST rpc/${e.key}',
          impact: 'órbita: job invocável fora do cron',
          evidence: briefBody(r),
        );
      }
    }
  }

  // Connect origin
  final evil = await edge(c.url, 'create-connect-account', {
    'web_return_origin': 'https://evil.example/steal',
    'amount': 100,
  }, headers: c.sellerH);
  rec(
    surface: 'connect',
    attack: 'evil web_return_origin',
    identity: 'seller',
    result: briefBody(evil),
  );
  final loc = evil.headers['location'] ?? '';
  if (loc.contains('evil.example')) {
    finding(
      id: 'RTI4-P4-CONNECT-REDIRECT',
      severity: 'P1',
      title: 'Connect devolve Location para origem hostil',
      actor: 'seller JWT',
      pre: 'web_return_origin=https://evil.example/steal',
      repro: 'POST create-connect-account',
      impact: 'open redirect pós-Connect',
      evidence: loc,
    );
  }

  // Favorites / follows
  if (pidListed != null) {
    final favAlien = await rest(c.url, 'POST', 'favorites', headers: c.buyerH,
        body: {
          'user_id': c.sellerId,
          'product_id': pidListed,
        });
    rec(
      surface: 'favorites',
      attack: 'buyer INSERT favorite as seller user_id',
      identity: 'buyer',
      result: briefBody(favAlien),
    );
    if (favAlien.statusCode < 300) {
      finding(
        id: 'RTI4-P4-FAV-FOREIGN',
        severity: 'P2',
        title: 'JWT grava favorite com user_id alheio',
        actor: 'buyer',
        pre: 'user_id=seller',
        repro: 'POST favorites',
        impact: 'enum/atribuição cruzada',
        evidence: briefBody(favAlien),
      );
    }
  }
  final fol = await rest(c.url, 'POST', 'follows', headers: c.buyerH, body: {
    'follower_id': c.sellerId,
    'following_id': c.buyerId,
  });
  rec(
    surface: 'follows',
    attack: 'buyer INSERT follow as seller',
    identity: 'buyer',
    result: briefBody(fol),
  );

  // Tip bind
  if (endedLiveId != null) {
    final tip = await edge(c.url, 'create-live-tip-checkout', {
      'live_id': endedLiveId,
      'seller_id': c.buyerId,
      'amount_eur': 5,
      'tip_id': '00000000-0000-4000-8000-000000000099',
      'stripe_session_id': 'cs_test_bind_me',
      'web_return_origin': 'https://evil.example',
    }, headers: c.buyerH);
    rec(
      surface: 'tip',
      attack: 'tip seller≠live + client tip_id + evil origin',
      identity: 'buyer',
      result: briefBody(tip),
    );
    final tipOk = await edge(c.url, 'create-live-tip-checkout', {
      'live_id': endedLiveId,
      'seller_id': c.sellerId,
      'amount_eur': 5,
    }, headers: c.buyerH);
    rec(
      surface: 'tip',
      attack: 'tip bind seller=live ended, amount 5',
      identity: 'buyer',
      result: briefBody(tipOk),
    );
  }

  // Race: N parallel holds qty=1
  if (pidQty1 != null) {
    final futs = List.generate(
      6,
      (_) => rest(c.url, 'POST', 'orders', headers: c.buyerH, body: {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': pidQty1,
        'quantity': 1,
        'price_total': 9.5,
        'status': 'reserva_pendente',
        'payment_method': 'pagamento na app',
        'shipping_method': 'carrier',
      }),
    );
    final rs = await Future.wait(futs);
    final created = rs.where((r) => r.statusCode < 300 && r.body.contains('"id"')).length;
    rec(
      surface: 'race',
      attack: '6 parallel holds qty=1',
      identity: 'buyer',
      result: 'created=$created statuses=${rs.map((e) => e.statusCode).toList()}',
    );
    if (created >= 2) {
      finding(
        id: 'RTI4-P1-RACE-HOLD',
        severity: 'P1',
        title: 'qty=1 aceitou ≥2 holds JWT em paralelo',
        actor: 'buyer JWT race',
        pre: 'quantity=1 listed',
        repro: '6 POST orders parallel',
        impact: 'oversell de hold (não captura)',
        evidence: {
          'created': created,
          'bodies': rs.map(briefBody).toList(),
        },
      );
    }
  }

  // Payload mutation Edge: alien buyer_id
  if (pidListed != null) {
    final oid = await mkOrder(pid: pidListed, h: c.buyerH, buyer: c.buyerId);
    if (oid != null) {
      final mut = await checkoutSingle(oid, pidListed, extra: {
        'buyer_id': c.sellerId,
        'amount': 50,
        'quantity': 99,
        'item_price': 0.01,
      });
      rec(
        surface: 'edge.mutation',
        attack: 'checkout body buyer_id=seller qty=99 amount=0.01',
        identity: 'buyer',
        result: briefBody(mut),
      );
    }
  }

  // Short Pass-1 núcleo (não saturar): listed checkout session vs underpay
  if (pidListed != null) {
    final oid = await mkOrder(pid: pidListed, h: c.buyerH, buyer: c.buyerId);
    if (oid != null) {
      final ck = await checkoutSingle(oid, pidListed);
      rec(
        surface: 'edge.checkout',
        attack: 'happy listed single (núcleo curto)',
        identity: 'buyer',
        result: briefBody(ck),
      );
    }
  }

  await dumpJson('pass1', {
    'auditor': 'REDTEAM_BLIND_INDEP_v4',
    'frozen_at_note': 'pass1 raw — freeze later',
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
    'wells': wells,
    'findings': findings,
    'matrix': matrix,
    'gaps': gaps,
    'invariants': invariants,
    'fresh_id': c.freshId,
    'paid_oid': paidOid,
    'pids': {
      'listed': pidListed,
      'unlisted': pidUnlisted,
      'sold': pidSold,
      'sold_unlist': pidSoldUnlist,
      'bag_unlist': pidBagUnlist,
      'qty1': pidQty1,
      'hub_sold': pidHubSold,
      'ended_live': endedLiveId,
      'live_item': liveItemId,
      'raffle': raffleId,
    },
  });
  stderr.writeln(
      'pass1 done findings=${findings.length} matrix=${matrix.length}');
}
