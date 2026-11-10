/// REDTEAM_BLIND_X pass2 — verify false positives + deepen convert/qty/caixa.
/// Staging only. No production. No Fase 4. No fixes.
import 'dart:io';

import '_rtx.dart';

Future<void> main() async {
  final c = Rtx.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.ensureHelper();

  final live = await c.insertLive();
  final liveS2 = await c.insertLive(seller: c.seller2Id);
  if (live == null || liveS2 == null) throw StateError('lives');

  // Re-invite helper if needed
  final existing = await c.rest(
    'GET',
    'seller_helpers?seller_id=eq.${c.sellerId}&helper_user_id=eq.${c.helperId}&select=id,active,invitation_status,permissions',
    service: true,
  );
  c.note('p2.helper.existing', 'helper row', existing.map, lens: 'X2');
  if (existing.firstId == null) {
    final hid = await c.inviteHelper(
      helperUserId: c.helperId!,
      helperEmail: '${prefix.toLowerCase()}-h1@fleaber.test',
    );
    if (hid != null) await c.acceptInvite(hid, jwt: c.helperJwt);
  }

  // ----- X7 observe: seller2 PATCH 200 [] did it mutate? fresh item -----
  final itemObs = await c.insertLiveOnlyItem(
    liveId: live,
    qty: 3,
    ref: 'XOBS',
    jwt: c.sellerJwt,
  );
  final before = await c.itemRow(itemObs!);
  final patchS2 = await c.rest(
    'PATCH',
    'live_items?id=eq.$itemObs',
    jwt: c.seller2Jwt,
    body: {'quantity': 999},
  );
  final after = await c.itemRow(itemObs);
  c.note('p2.x7.patch-observe', 'seller2 PATCH vs GET', {
    'patch': patchS2.brief,
    'qty_before': before?['quantity'],
    'qty_after': after?['quantity'],
    'status_after': after?['status'],
  }, lens: 'X7');
  final mutated = (numOf(after?['quantity']) ?? 0) != (numOf(before?['quantity']) ?? 0);
  if (mutated) {
    c.hold(
      id: 'RTX-X7-s2-patch-item-qty',
      lens: 'X7',
      severity: 'P0',
      title: '2.º seller altera quantity do live_item alheio (GET confirma)',
      actor: 'seller2 JWT',
      pre: 'item qty=3 do seller1',
      repro: 'PATCH live_items.quantity=999 JWT seller2 → GET',
      expected: '0 rows / qty inalterado',
      obtained: {'before': before, 'after': after, 'patch': patchS2.brief},
    );
  } else {
    c.block('RTX-X7-s2-patch-item-qty', 'X7',
        '200 [] sem mutação — RLS filtrou (falso positivo pass1)', {
      'qty_before': before?['quantity'],
      'qty_after': after?['quantity'],
      'patch': patchS2.brief,
    });
  }

  // ----- X3 inflate qty then accept more than original -----
  final itemInf = await c.insertLiveOnlyItem(
    liveId: live,
    qty: 1,
    ref: 'XINF',
    jwt: c.sellerJwt,
  );
  final stock0 = await c.stock(itemInf!);
  final inf = await c.rest(
    'PATCH',
    'live_items?id=eq.$itemInf',
    jwt: c.sellerJwt,
    body: {'quantity': 8},
  );
  final stock1 = await c.stock(itemInf);
  final fbBig = await c.insertReservation(
    liveId: live,
    liveItemId: itemInf,
    buyer: c.buyerId,
    qty: 5,
    jwt: c.sellerJwt,
  );
  HttpHit? accBig;
  if (fbBig.firstId != null) {
    c.createdReqIds.add(fbBig.firstId!);
    accBig = await c.processReservation(fbBig.firstId!, 'accept');
  }
  final stock2 = await c.stock(itemInf);
  final rowInf = await c.itemRow(itemInf);
  c.note('p2.x3.inflate-accept', 'inflate 1→8 then accept qty=5', {
    'stock0': stock0.map,
    'patch': inf.brief,
    'stock1': stock1.map,
    'insert': fbBig.brief,
    'accept': accBig?.brief,
    'stock2': stock2.map,
    'item': rowInf,
  }, lens: 'X3');
  final avail0 = numOf(stock0.map?['available_qty']) ?? 0;
  final avail1 = numOf(stock1.map?['available_qty']) ?? 0;
  final accOk = accBig?.rpcOk == true;
  if (inf.ok && avail1 > avail0 && accOk) {
    c.hold(
      id: 'RTX-X3-inflate-then-accept-over-original',
      lens: 'X3',
      severity: 'P1',
      title: 'PATCH quantity mid-live aumenta available e aceita qty>original',
      actor: 'seller JWT',
      pre: 'live_only qty=1; PATCH 8; facebook_manual qty=5',
      repro: 'PATCH live_items.quantity=8 → rpc accept qty=5',
      expected: 'total_qty/pool estável; accept qty=5 recusado',
      obtained: {
        'avail0': avail0,
        'avail1': avail1,
        'accept': accBig?.map,
        'stock2': stock2.map,
      },
    );
  } else {
    c.block('RTX-X3-inflate-then-accept', 'X3',
        'inflate não aumentou available útil ou accept recusado', {
      'avail0': avail0,
      'avail1': avail1,
      'accept': accBig?.brief,
      'stock1': stock1.map,
    });
  }

  // ----- X3 pending qty>stock then convert (skip accept) -----
  final itemP = await c.insertLiveOnlyItem(
    liveId: live,
    qty: 1,
    ref: 'XPND',
    jwt: c.sellerJwt,
  );
  final pendHi = await c.insertReservation(
    liveId: live,
    liveItemId: itemP,
    buyer: c.buyer2Id,
    qty: 4,
    jwt: c.sellerJwt,
  );
  c.note('p2.x3.pend-hi', 'INSERT pending qty=4 em item qty=1', pendHi.brief,
      lens: 'X3');
  if (pendHi.firstId != null) {
    c.createdReqIds.add(pendHi.firstId!);
    final conv = await c.processReservation(pendHi.firstId!, 'convert');
    final row = await c.reqRow(pendHi.firstId!);
    final st = await c.stock(itemP!);
    c.note('p2.x3.pend-convert', 'convert pending qty=4', {
      'rpc': conv.brief,
      'row': row,
      'stock': st.map,
    }, lens: 'X3');
    if (conv.rpcOk && row?['status'] == 'converted') {
      c.hold(
        id: 'RTX-X3-pending-overqty-convert',
        lens: 'X3',
        severity: 'P1',
        title: 'convert pending facebook_manual qty>stock sem pass by accept',
        actor: 'seller JWT',
        pre: 'item qty=1; INSERT pending requested_qty=4',
        repro: 'rpc convert (sem accept) source=facebook_manual',
        expected: 'qty_exceeds_stock no UPDATE converted',
        obtained: {'rpc': conv.map, 'row': row, 'stock': st.map},
      );
    } else {
      c.block('RTX-X3-pending-overqty-convert', 'X3',
          'convert pending over-qty recusado', conv.brief);
    }
  }

  // ----- race two convert on qty=1 -----
  final itemR = await c.insertLiveOnlyItem(
    liveId: live,
    qty: 1,
    ref: 'XRCV',
    jwt: c.sellerJwt,
  );
  final ra = await c.insertReservation(
    liveId: live,
    liveItemId: itemR,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  final rb = await c.insertReservation(
    liveId: live,
    liveItemId: itemR,
    buyer: c.buyer2Id,
    jwt: c.sellerJwt,
  );
  if (ra.firstId != null && rb.firstId != null) {
    c.createdReqIds.addAll([ra.firstId!, rb.firstId!]);
    final raced = await parallel([
      c.processReservation(ra.firstId!, 'convert'),
      c.processReservation(rb.firstId!, 'convert'),
    ]);
    final a = await c.reqRow(ra.firstId!);
    final b = await c.reqRow(rb.firstId!);
    c.note('p2.x3.race-convert', 'dois convert pending paralelo qty=1', {
      'rpc0': raced[0].brief,
      'rpc1': raced[1].brief,
      'a': a?['status'],
      'b': b?['status'],
    }, lens: 'X3');
    final n = [a?['status'], b?['status']].where((s) => s == 'converted').length;
    if (n >= 2) {
      c.hold(
        id: 'RTX-X3-race-convert-qty1',
        lens: 'X3',
        severity: 'P1',
        title: 'dois convert facebook_manual permanentes em qty=1',
        actor: 'seller JWT ×2 paralelo',
        pre: 'duas pending no mesmo live_only qty=1',
        repro: 'dois rpc convert em paralelo',
        expected: 'um converted, outro qty_exceeds_stock',
        obtained: {'a': a, 'b': b},
      );
    } else {
      c.block('RTX-X3-race-convert-qty1', 'X3', 'race convert: ≤1 converted', {
        'n': n,
        'a': a?['status'],
        'b': b?['status'],
        'rpc0': raced[0].brief,
        'rpc1': raced[1].brief,
      });
    }
  }

  // ----- X8 marketplace convert + checkout -----
  final pid = await c.createProduct(qty: 1, title: '$prefix-p2-mkt', price: 15);
  final itemM = await c.insertMarketItem(
    liveId: live,
    productId: pid!,
    ref: 'XMKT',
    jwt: c.sellerJwt,
  );
  final fbM = await c.insertReservation(
    liveId: live,
    liveItemId: itemM,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  HttpHit? accM;
  HttpHit? convM;
  if (fbM.firstId != null) {
    c.createdReqIds.add(fbM.firstId!);
    accM = await c.processReservation(fbM.firstId!, 'accept');
    convM = await c.processReservation(fbM.firstId!, 'convert');
  }
  final prodAfter = await c.productRow(pid);
  final itemAfter = itemM == null ? null : await c.itemRow(itemM);
  final orders = itemM == null ? <dynamic>[] : await c.ordersForItem(itemM);
  final wB = await c.wallets();
  c.note('p2.x8.mkt.convert', 'marketplace facebook convert', {
    'insert': fbM.brief,
    'accept': accM?.brief,
    'convert': convM?.brief,
    'product': prodAfter,
    'item': itemAfter,
    'orders': orders,
  }, lens: 'X8');

  if (convM?.rpcOk == true &&
      (fbM.firstId == null
          ? false
          : (await c.reqRow(fbM.firstId!))?['status'] == 'converted')) {
    c.hold(
      id: 'RTX-X8-mkt-fb-convert-no-pi',
      lens: 'X8',
      severity: 'P1',
      title: 'convert facebook_manual em SKU marketplace qty=1 sem PI',
      actor: 'seller JWT',
      pre: 'product qty=1 ligado ao directo; zero Stripe',
      repro: 'accept+convert facebook_manual',
      expected: 'convert_requires_paid_order ou convert sem consumir catálogo',
      obtained: {
        'convert': convM?.map,
        'product': prodAfter,
        'item': itemAfter,
        'orders': orders,
      },
    );

    final checkout = await c.edge('create-payment-intent', {
      'buyer_id': c.buyerId,
      'product_id': pid,
      'amount': 15,
      'shipping_method': 'mao',
      'quantity': 1,
    }, jwt: c.buyerJwt);
    c.note('p2.x8.checkout-after-convert', 'checkout SKU após convert FB',
        checkout.brief, lens: 'X8');
    final session = checkout.map?['checkoutSessionId'] ??
        checkout.map?['checkout_session_id'] ??
        checkout.map?['id'];
    if (checkout.ok && session != null) {
      c.hold(
        id: 'RTX-X8-checkout-after-fb-convert',
        lens: 'X8',
        severity: 'P1',
        title: 'checkout Stripe ainda possível após convert facebook_manual',
        actor: 'buyer JWT',
        pre: 'SKU qty=1 convertido FB sem PI',
        repro: 'POST create-payment-intent product_id após convert',
        expected: 'recusa stock / already sold',
        obtained: checkout.brief,
      );
    } else {
      c.block('RTX-X8-checkout-after-fb-convert', 'X8',
          'checkout após convert recusado ou sem session', checkout.brief);
    }

    final ord = await c.insertOrder(
      productId: pid,
      jwt: c.buyerJwt,
      liveItemId: itemM,
      liveId: live,
    );
    c.note('p2.x8.order-after-convert', 'INSERT order após convert FB', {
      'ins': ord.brief,
      'row': ord.firstId == null ? null : await c.orderRow(ord.firstId!),
    }, lens: 'X8');
    if (ord.ok) {
      c.hold(
        id: 'RTX-X8-order-after-fb-convert',
        lens: 'X8',
        severity: 'P1',
        title: 'INSERT order no SKU após convert facebook_manual',
        actor: 'buyer JWT',
        pre: 'convert FB converted; product ainda pedido',
        repro: 'POST orders product_id após convert',
        expected: 'hold/capacidade recusa 2.ª unidade',
        obtained: ord.map,
      );
    } else {
      c.block('RTX-X8-order-after-fb-convert', 'X8',
          'INSERT order após convert recusado', ord.brief);
    }
  } else {
    c.block('RTX-X8-mkt-fb-convert-no-pi', 'X8',
        'marketplace convert facebook_manual recusado', convM?.brief ?? fbM.brief);
  }
  c.note('p2.wallets.mkt', 'wallets após mkt convert', wB, lens: 'X8');

  // ----- helper_manual convert on fresh item -----
  final itemH = await c.insertLiveOnlyItem(
    liveId: live,
    qty: 2,
    ref: 'XHM',
    jwt: c.sellerJwt,
  );
  final hm = await c.insertReservation(
    liveId: live,
    liveItemId: itemH,
    buyer: c.buyerId,
    source: 'helper_manual',
    jwt: c.helperJwt,
  );
  c.note('p2.x8.hm.insert', 'helper_manual INSERT', hm.brief, lens: 'X8');
  if (hm.firstId != null) {
    c.createdReqIds.add(hm.firstId!);
    final acc = await c.processReservation(hm.firstId!, 'accept', jwt: c.helperJwt);
    final conv = await c.processReservation(hm.firstId!, 'convert', jwt: c.helperJwt);
    final row = await c.reqRow(hm.firstId!);
    c.note('p2.x8.hm.convert', 'helper_manual accept+convert', {
      'accept': acc.brief,
      'convert': conv.brief,
      'row': row,
    }, lens: 'X8');
    if (conv.rpcOk && row?['status'] == 'converted') {
      c.hold(
        id: 'RTX-X8-helper-manual-convert-no-pi',
        lens: 'X8',
        severity: 'P1',
        title: 'convert helper_manual sem encomenda paga',
        actor: 'helper JWT',
        pre: 'source=helper_manual accepted; item qty=2; zero PI',
        repro: 'rpc convert JWT helper source=helper_manual',
        expected: 'convert_requires_paid_order',
        obtained: {'rpc': conv.map, 'row': row},
      );
    } else {
      c.block('RTX-X8-helper-manual-convert-no-pi', 'X8',
          'helper_manual convert recusado', conv.brief);
    }
  }

  // ----- X6 raffle via RPC -----
  final raf = await c.rpc('batata_create_live_raffle', {
    'p_live_id': live,
    'p_title': '$prefix raffle',
    'p_activate': true,
  }, jwt: c.sellerJwt);
  c.note('p2.x6.create', 'create raffle', raf.brief, lens: 'X6');
  final rafId = raf.map?['raffle_id']?.toString();
  if (raf.rpcOk && rafId != null) {
    final drawS2 = await c.rpc('batata_draw_live_raffle_winners', {
      'p_raffle_id': rafId,
    }, jwt: c.seller2Jwt);
    c.note('p2.x6.draw.s2', 'seller2 draw', drawS2.brief, lens: 'X6');
    if (drawS2.rpcOk) {
      c.hold(
        id: 'RTX-X6-draw-foreign',
        lens: 'X6',
        severity: 'P1',
        title: '2.º seller sorteia rifa da live alheia',
        actor: 'seller2 JWT',
        pre: 'raffle active live seller1',
        repro: 'rpc batata_draw_live_raffle_winners JWT seller2',
        expected: 'not_allowed',
        obtained: drawS2.map ?? drawS2.brief,
      );
    } else {
      c.block('RTX-X6-draw-foreign', 'X6', 'draw foreign recusado', drawS2.brief);
    }
    final drawH = await c.rpc('batata_draw_live_raffle_winners', {
      'p_raffle_id': rafId,
    }, jwt: c.helperJwt);
    c.note('p2.x6.draw.helper', 'helper draw', drawH.brief, lens: 'X6');
    if (drawH.rpcOk) {
      c.hold(
        id: 'RTX-X6-helper-draw',
        lens: 'X6',
        severity: 'P2',
        title: 'helper sorteia rifa (perms reservas, não rifa)',
        actor: 'helper JWT',
        pre: 'can_manage_reservations only',
        repro: 'rpc batata_draw_live_raffle_winners JWT helper',
        expected: 'not_allowed se rifa ≠ reservas',
        obtained: drawH.map ?? drawH.brief,
      );
    } else {
      c.block('RTX-X6-helper-draw', 'X6', 'helper draw recusado', drawH.brief);
    }
  } else {
    c.skip('RTX-X6-raffle-create', 'X6', 'create raffle falhou', raf.brief);
  }

  // ----- X4: two lives same live_only ref_code pool -----
  final liveB = await c.insertLive();
  final iA = await c.insertLiveOnlyItem(
    liveId: live,
    qty: 1,
    ref: 'XPOOL',
    jwt: c.sellerJwt,
  );
  final iB = await c.insertLiveOnlyItem(
    liveId: liveB!,
    qty: 1,
    ref: 'XPOOL',
    jwt: c.sellerJwt,
  );
  final rA = await c.insertReservation(
    liveId: live,
    liveItemId: iA,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  final rBb = await c.insertReservation(
    liveId: liveB,
    liveItemId: iB,
    buyer: c.buyer2Id,
    jwt: c.sellerJwt,
  );
  HttpHit? cA;
  HttpHit? cB;
  if (rA.firstId != null) {
    c.createdReqIds.add(rA.firstId!);
    await c.processReservation(rA.firstId!, 'accept');
    cA = await c.processReservation(rA.firstId!, 'convert');
  }
  if (rBb.firstId != null) {
    c.createdReqIds.add(rBb.firstId!);
    await c.processReservation(rBb.firstId!, 'accept');
    cB = await c.processReservation(rBb.firstId!, 'convert');
  }
  c.note('p2.x4.ref-pool', 'mesmo ref_code duas lives convert', {
    'cA': cA?.brief,
    'cB': cB?.brief,
    'sA': rA.firstId == null ? null : (await c.reqRow(rA.firstId!))?['status'],
    'sB': rBb.firstId == null ? null : (await c.reqRow(rBb.firstId!))?['status'],
  }, lens: 'X4');
  final sa = rA.firstId == null ? null : (await c.reqRow(rA.firstId!))?['status'];
  final sb = rBb.firstId == null ? null : (await c.reqRow(rBb.firstId!))?['status'];
  if (sa == 'converted' && sb == 'converted') {
    c.hold(
      id: 'RTX-X4-same-ref-two-lives-convert',
      lens: 'X4',
      severity: 'P1',
      title: 'mesmo ref_code convertido facebook_manual em duas lives',
      actor: 'seller JWT',
      pre: 'live_only ref XPOOL qty=1 em A e B',
      repro: 'accept+convert nas duas lives',
      expected: 'pool partilhado recusa o segundo',
      obtained: {'sa': sa, 'sb': sb},
    );
  } else {
    c.block('RTX-X4-same-ref-two-lives-convert', 'X4',
        'pool ref recusou segundo convert ou accept', {
      'sa': sa,
      'sb': sb,
      'cB': cB?.brief,
    });
  }

  await c.endLives();
  final out = {
    'auditor': 'REDTEAM_BLIND_X_LIVE_MANUAL_STAFF_v1',
    'pass': 2,
    'production_touched': false,
    'fase4': false,
    'lenses': c.lensesHit.toList()..sort(),
    'findings': c.findings,
    'blocked': c.blocked,
    'skipped': c.skipped,
    'notes': c.notes,
    'ids': {
      'lives': c.createdLiveIds,
      'items': c.createdItemIds,
      'reqs': c.createdReqIds,
      'products': c.createdProductIds,
      'orders': c.createdOrderIds,
    },
  };
  await dumpJson('${outDir()}/pass2.json', out);
  stdout.writeln(
      'WROTE pass2.json findings=${c.findings.length} blocked=${c.blocked.length}');
}
