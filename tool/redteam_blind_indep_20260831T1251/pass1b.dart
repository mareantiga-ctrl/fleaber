/// Pass 1b — lacunas: zombie live (fixture service), anon SELECT, bundle checkout pós-unlist.
import 'dart:io';
import '_rt.dart';

bool persisted(HttpR r) =>
    r.ok && (r.list.isNotEmpty || (r.map != null && r.map!['id'] != null));

Future<void> main() async {
  final c = Rti4(loadEnv());
  await c.boot();

  // Anon products without phantom columns
  final baseAnon = await c.rest(
    'GET',
    'products?select=id,title,price,quantity,list_on_marketplace,is_sold&limit=5',
  );
  c.note('p3.products.anon2', 'products anon no cost_price', baseAnon.brief, well: '3');
  if (baseAnon.ok && baseAnon.list.isNotEmpty) {
    c.finding(
      id: 'P3-ANON-PRODUCTS',
      title: 'Anon SELECT na tabela products',
      actor: 'anon',
      sev: 'P2',
      well: '3',
      pre: 'GET products',
      request: 'GET /rest/v1/products',
      before: null,
      after: clip(baseAnon.body, 400),
      impact: 'Catálogo base fora da view Hub',
      repro: 'GET products as anon',
    );
  } else {
    c.hold('p3.products.anon2', 'anon sem SELECT products', baseAnon.brief, well: '3');
  }

  final profAnon = await c.rest(
    'GET',
    'profiles?select=id,full_name,phone,location,iban,mb_way,shipping_line1&limit=3',
  );
  c.note('p3.profiles.anon2', 'profiles anon', profAnon.brief, well: '3');
  if (profAnon.ok && profAnon.list.any((e) {
        if (e is! Map) return false;
        final phone = '${e['phone'] ?? ''}';
        final iban = '${e['iban'] ?? ''}';
        return phone.isNotEmpty || iban.isNotEmpty;
      })) {
    c.finding(
      id: 'P3-ANON-PII',
      title: 'Anon lê PII em profiles',
      actor: 'anon',
      sev: 'P1',
      well: '3',
      pre: 'GET profiles',
      request: 'GET profiles phone/iban',
      before: null,
      after: clip(profAnon.body, 400),
      impact: 'Telefone/IBAN públicos',
      repro: 'GET profiles as anon',
    );
  } else if (profAnon.ok && profAnon.list.isNotEmpty) {
    c.hold('p3.profiles.anon.no.pii', 'anon vê profiles mas sem PII nesta amostra',
        {'n': profAnon.list.length}, well: '3');
  } else {
    c.hold('p3.profiles.anon2', 'anon sem SELECT profiles', profAnon.brief, well: '3');
  }

  final unlisted = await c.insertProduct(listed: false, sold: false, title: '$prefix-Z-UL');
  final listed = await c.insertProduct(listed: true, sold: false, title: '$prefix-Z-L', qty: 1);
  if (unlisted == null) {
    await c.dump('pass1b');
    return;
  }
  final uid = unlisted['id'].toString();

  // Buyer select unlist (correct columns)
  final buyU = await c.rest(
    'GET',
    'products?id=eq.$uid&select=id,title,price,quantity,list_on_marketplace,is_sold',
    token: c.buyerJwt,
  );
  c.note('p1.buyer.unlist.select2', 'buyer unlist', buyU.brief, well: '1');
  if (buyU.ok && buyU.list.isNotEmpty) {
    c.finding(
      id: 'P1-BUYER-SELECT-UNLIST',
      title: 'Buyer lê produto unlist sem order',
      actor: 'buyer JWT',
      sev: 'P2',
      well: '1',
      pre: 'unlist, sem order',
      request: 'GET products',
      before: null,
      after: buyU.brief,
      impact: 'Oráculo de preço de SKU morto',
      repro: 'GET products unlist as buyer',
    );
  } else {
    c.hold('p1.buyer.unlist.select2', 'buyer não vê unlist', buyU.brief, well: '1');
  }

  // Zombie live via service fixture + seller PATCH
  final liveIns = await c.rest(
    'POST',
    'lives',
    service: true,
    body: {
      'seller_id': c.sellerId,
      'vendedor_id': c.sellerId,
      'title': '$prefix-ZOMBIE-SVC',
      'status': 'ended',
      'is_active': false,
    },
  );
  c.note('p1.live.svc', 'service INSERT ended live', liveIns.brief, well: '1');
  String? liveId;
  if (liveIns.list.isNotEmpty) liveId = (liveIns.list.first as Map)['id']?.toString();
  liveId ??= liveIns.map?['id']?.toString();
  if (liveId != null) c.createdLiveIds.add(liveId);

  if (liveId != null) {
    final zSeller = await c.rest(
      'PATCH',
      'lives?id=eq.$liveId',
      token: c.sellerJwt,
      body: {'is_active': true, 'status': 'ended'},
    );
    c.note('p1.zombie.seller.patch', 'seller PATCH is_active', zSeller.brief, well: '1');
    var liveAfter = await c.getOne('lives', liveId, select: 'id,status,is_active,seller_id');
    var zombieOn = liveAfter?['is_active'] == true;

    if (!zombieOn) {
      final zSvc = await c.rest(
        'PATCH',
        'lives?id=eq.$liveId',
        service: true,
        body: {'is_active': true, 'status': 'ended'},
      );
      c.note('p1.zombie.svc.patch', 'service PATCH is_active (observe leftover)', zSvc.brief,
          well: '1');
      liveAfter = await c.getOne('lives', liveId, select: 'id,status,is_active');
      zombieOn = liveAfter?['is_active'] == true;
      // If only service can set it, leftover is_active is still an attacker path IF
      // seller can do it. If seller PATCH 403/silent, not seller-attacker.
    }

    final oZ = await c.insertOrder(
      token: c.buyerJwt,
      productId: uid,
      liveId: liveId,
    );
    c.note('p1.zombie.order', 'unlist+live_id', {
      'zombieOn': zombieOn,
      'live': liveAfter,
      'order': oZ.brief,
      'sellerPatchHttp': zSeller.status,
    }, well: '1');

    if (persisted(oZ)) {
      final oid = c.orderIdOf(oZ)!;
      final chk = await c.checkout(
        token: c.buyerJwt,
        orderId: oid,
        productId: uid,
        extra: {'live_id': liveId},
      );
      final sessionIssued = chk.ok &&
          '${chk.map?['checkoutUrl'] ?? chk.map?['url'] ?? chk.map?['session_id']}'
              .trim()
              .isNotEmpty;
      final sellerCanZombie = zSeller.ok &&
          (zSeller.list.isEmpty ||
              (zSeller.list.first as Map)['is_active'] == true);
      c.finding(
        id: 'P1-ZOMBIE-LIVE-UNLIST',
        title: 'live ended+is_active permite hold/checkout de unlist',
        actor: sellerCanZombie ? 'seller JWT + buyer JWT' : 'buyer JWT + live is_active leftover',
        sev: sessionIssued ? 'P1' : 'P2',
        well: '1',
        pre: 'unlist; live status=ended is_active=${liveAfter?['is_active']}',
        request: 'POST orders live_id; create-payment-intent',
        before: liveAfter,
        after: {
          'order': oZ.brief,
          'checkout': clip(chk.body, 500),
          'session': sessionIssued,
          'seller_patch': zSeller.brief,
        },
        impact: sessionIssued
            ? 'Session Stripe para SKU morto via live-zombie'
            : 'Hold unlist via live is_active',
        repro: 'live ended is_active=true; POST orders unlist+live_id',
      );
    } else if (zSeller.ok && zombieOn) {
      c.hold('p1.zombie.order', 'seller consegue is_active mas hold bloqueado', oZ.brief,
          well: '1');
    } else {
      c.hold('p1.zombie.blocked', 'unlist+ended live não hold', {
        'order': oZ.brief,
        'sellerPatch': zSeller.brief,
        'live': liveAfter,
      }, well: '1');
    }

    // live_items table as buyer on ended
    if (listed != null) {
      final li = await c.rest(
        'POST',
        'live_items',
        service: true,
        body: {
          'live_id': liveId,
          'seller_id': c.sellerId,
          'product_id': listed['id'],
          'title': '$prefix-LI',
          'price': 4.5,
          'is_active': true,
        },
      );
      c.note('p1.li.svc', 'live_item fixture', li.brief, well: '3');
      final liId = li.list.isNotEmpty
          ? (li.list.first as Map)['id']?.toString()
          : li.map?['id']?.toString();
      if (liId != null) {
        final liBuy = await c.rest(
          'GET',
          'live_items?id=eq.$liId&select=id,live_id,product_id,price,title',
          token: c.buyerJwt,
        );
        final liAnon = await c.rest(
          'GET',
          'live_items?id=eq.$liId&select=id,product_id,price,title',
        );
        c.note('p3.li.buyer', 'buyer live_items', liBuy.brief, well: '3');
        c.note('p3.li.anon', 'anon live_items', liAnon.brief, well: '3');
        if (liAnon.ok && liAnon.list.isNotEmpty) {
          c.finding(
            id: 'P3-ANON-LIVE-ITEMS',
            title: 'Anon lê live_items (product_id) fora da view Hub',
            actor: 'anon',
            sev: 'P2',
            well: '3',
            pre: 'live ended',
            request: 'GET live_items',
            before: null,
            after: liAnon.brief,
            impact: 'UUID de produto via tabela base',
            repro: 'GET live_items as anon',
          );
        } else {
          c.hold('p3.li.anon', 'anon sem live_items', liAnon.brief, well: '3');
        }
      }
    }

    await c.rest(
      'PATCH',
      'lives?id=eq.$liveId',
      service: true,
      body: {'is_active': false, 'status': 'ended'},
    );
  }

  // Bundle accept after unlist → checkout
  final a = await c.insertProduct(listed: true, sold: false, title: '$prefix-BA', price: 6);
  final b = await c.insertProduct(listed: true, sold: false, title: '$prefix-BB', price: 7);
  if (a != null && b != null) {
    final bun = await c.rest(
      'POST',
      'product_bundles',
      token: c.buyerJwt,
      body: {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_ids': [a['id'], b['id']],
        'status': 'pending',
      },
    );
    if (persisted(bun)) {
      final bid = c.orderIdOf(bun)!;
      await c.rest(
        'PATCH',
        'products?id=eq.${b['id']}',
        token: c.sellerJwt,
        body: {'list_on_marketplace': false, 'is_sold': true},
      );
      await c.rest(
        'PATCH',
        'product_bundles?id=eq.$bid',
        token: c.sellerJwt,
        body: {'status': 'accepted'},
      );
      final bunAfter = await c.getOne(
        'product_bundles',
        bid,
        select: 'id,status,total_eur,product_ids,subtotal_eur',
      );
      // Orders from bundle members
      final oA = await c.insertOrder(
        token: c.buyerJwt,
        productId: a['id'].toString(),
        extra: {'bundle_id': bid},
      );
      final oB = await c.insertOrder(
        token: c.buyerJwt,
        productId: b['id'].toString(),
        extra: {'bundle_id': bid},
      );
      c.note('p1.bundle.compose', 'orders after accept+dead member', {
        'bundle': bunAfter,
        'oA': oA.brief,
        'oB': oB.brief,
      }, well: '1');
      if (persisted(oB)) {
        final oidB = c.orderIdOf(oB)!;
        final chk = await c.checkout(
          token: c.buyerJwt,
          orderId: oidB,
          productId: b['id'].toString(),
        );
        c.finding(
          id: 'P1-BUNDLE-DEAD-CHECKOUT',
          title: 'Checkout do SKU morto via bundle aceite',
          actor: 'buyer JWT',
          sev: chk.ok ? 'P1' : 'P2',
          well: '1',
          pre: 'bundle accepted após unlist+sold do membro B',
          request: 'POST orders bundle_id; create-payment-intent',
          before: bunAfter,
          after: {'order': oB.brief, 'checkout': clip(chk.body, 400)},
          impact: 'Venda de SKU morto costurado ao conjunto',
          repro: 'bundle accept after unlist; order member B',
        );
      } else {
        c.hold('p1.bundle.dead.order', 'order do membro morto bloqueada', oB.brief, well: '1');
      }
      if (persisted(oA) && c.orderIdOf(oA) != null) {
        final chkA = await c.checkout(
          token: c.buyerJwt,
          orderId: c.orderIdOf(oA)!,
          productId: a['id'].toString(),
        );
        c.note('p1.bundle.live.member.checkout', 'checkout membro vivo', chkA.brief, well: '1');
      }
    }
  }

  // Offer unlist → order already P2; try checkout if any pending offer-order
  final offer = await c.rest(
    'POST',
    'product_offers',
    token: c.buyerJwt,
    body: {
      'product_id': uid,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'amount': 3.0,
      'offered_by': 'buyer',
      'status': 'pending',
    },
  );
  if (persisted(offer)) {
    final ofId = c.orderIdOf(offer)!;
    await c.rest(
      'PATCH',
      'product_offers?id=eq.$ofId',
      token: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    final oOff = await c.insertOrder(
      token: c.buyerJwt,
      productId: uid,
      extra: {'product_offer_id': ofId},
    );
    c.note('p1.offer.order2', 'order after accepted unlist offer', oOff.brief, well: '1');
    if (persisted(oOff)) {
      final chk = await c.checkout(
        token: c.buyerJwt,
        orderId: c.orderIdOf(oOff)!,
        productId: uid,
      );
      c.finding(
        id: 'P1-OFFER-UNLIST-SESSION',
        title: 'Session/hold via oferta aceite em unlist',
        actor: 'buyer JWT',
        sev: chk.ok ? 'P1' : 'P2',
        well: '1',
        pre: 'offer accepted unlist',
        request: 'POST orders + checkout',
        before: offer.brief,
        after: {'order': oOff.brief, 'checkout': chk.brief},
        impact: 'Venda de morto via oferta',
        repro: 'accept offer unlist; checkout',
      );
    } else {
      c.hold('p1.offer.order2', 'hold após offer unlist bloqueado', oOff.brief, well: '1');
    }
  }

  await c.dump('pass1b');
  stdout.writeln('pass1b done findings=${c.findings.length} holds=${c.holds.length}');
}
