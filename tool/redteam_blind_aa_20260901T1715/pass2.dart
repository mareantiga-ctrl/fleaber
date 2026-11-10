/// REDTEAM_BLIND_AA pass2 — verificar PATCH converted, falsos 200[], composição caixa.
/// dart run tool/redteam_blind_aa_20260901T1715/pass2.dart
import 'dart:io';

import '_rtaa.dart';

Future<void> main() async {
  final c = Rtaa.fromEnv(loadEnv());
  try {
    await c.loginActors();
    await c.ensureBuyer2();
    await c.ensureSeller2();
    await c.ensureHelper();

    final w0 = await c.wallets();
    c.note('p2.w0', 'wallets', w0);

    final liveA = await c.insertLive();
    final liveS2 = await c.insertLive(seller: c.seller2Id);
    if (liveA == null || liveS2 == null) throw StateError('lives');

    final itemLo = await c.insertLiveOnlyItem(
        liveId: liveA, qty: 5, ref: 'P2A', jwt: c.sellerJwt);
    final itemOne = await c.insertLiveOnlyItem(
        liveId: liveA, qty: 1, ref: 'P2B', jwt: c.sellerJwt);
    final pid = await c.createProduct(qty: 3, title: '$prefix-p2mkt');
    final itemM = pid == null
        ? null
        : await c.insertMarketItem(
            liveId: liveA, productId: pid, ref: 'P2M', jwt: c.sellerJwt);

    final existing = await c.rest(
      'GET',
      'seller_helpers?helper_user_id=eq.${c.helperId}&seller_id=eq.${c.sellerId}&select=id,active,invitation_status,permissions',
      service: true,
    );
    var hid = existing.map?['id']?.toString();
    if (hid == null) {
      hid = await c.inviteHelper(
        helperUserId: c.helperId!,
        helperEmail: '${prefix.toLowerCase()}-h1@fleaber.test',
      );
      if (hid != null) {
        await c.acceptInvite(hid, jwt: c.helperJwt);
        await c.activateHelper(hid);
      }
    } else {
      await c.activateHelper(hid);
    }
    c.note('p2.helper', 'helper row', hid == null ? null : await c.helperRow(hid),
        lens: 'AA2');

    await verifyFalsePositives(c, itemLo);
    await helperPatchConverted(c, liveA, itemLo);
    await buyerPatchConverted(c, liveA, itemLo);
    await qtyThenPatch(c, liveA, itemLo);
    await stockAndHub(c, liveA, itemLo, itemOne);
    await paidOrderReuse(c, liveA, pid, itemM, w0);
    await helperMarkSold(c, itemLo);
    await checkoutAfterPatch(c, liveA, itemOne, pid);
    await ingestOcr(c, liveA);
    await muxResolveMutate(c, liveA, liveS2);

    final w1 = await c.wallets();
    c.note('p2.w1', 'wallets after', {'w0': w0, 'w1': w1});
    final d = (w1['seller'] ?? 0) - (w0['seller'] ?? 0);
    if (d != 0) {
      c.hold(
        id: 'RTAA-AA8-wallet-delta',
        lens: 'AA8',
        severity: 'P0',
        title: 'Δ carteira seller nesta ronda',
        actor: 'JWT',
        pre: 'pass2',
        repro: 'wallets before/after',
        expected: '0',
        obtained: {'d': d, 'w0': w0, 'w1': w1},
      );
    } else {
      c.block('RTAA-AA8-wallet-delta', 'AA8', 'Δ carteira 0', d);
    }
  } finally {
    await c.dumpAll('findings_pass2.json');
    await c.endLives();
    stdout.writeln(
        'PASS2 findings=${c.findings.length} blocked=${c.blocked.length}');
  }
}

Future<void> verifyFalsePositives(Rtaa c, String? itemLo) async {
  // Wallet PATCH 200 [] — saldo não mudou no pass1. Repetir e ler.
  final pre = await c.walletBal(c.sellerId);
  final patch = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {'balance': 99999},
  );
  final post = await c.walletBal(c.sellerId);
  c.note('p2.wallet.patch', 'reteste PATCH wallet', {
    'patch': patch.brief,
    'pre': pre,
    'post': post,
    'body_empty': patch.ok && patch.list.isEmpty,
  }, lens: 'AA8');
  if (patch.ok && post != pre) {
    c.hold(
      id: 'RTAA-AA8-wallet-patch-real',
      lens: 'AA8',
      severity: 'P0',
      title: 'PATCH wallets.balance alterou saldo',
      actor: 'seller JWT',
      pre: 'balance=$pre',
      repro: 'PATCH wallets.balance=99999',
      expected: '403 ou no-op',
      obtained: {'pre': pre, 'post': post, 'hit': patch.brief},
    );
  } else {
    c.block('RTAA-AA8-wallet-patch-real', 'AA8',
        'PATCH wallet no-op (200 vazio ou saldo igual)', {
      'hit': patch.brief,
      'pre': pre,
      'post': post,
    });
  }

  if (itemLo == null) return;
  final qPre = await c.itemRow(itemLo);
  final qPatch = await c.rest(
    'PATCH',
    'live_items?id=eq.$itemLo',
    jwt: c.seller2Jwt,
    body: {'quantity': 99},
  );
  final qPost = await c.itemRow(itemLo);
  c.note('p2.s2.qty', 'reteste seller2 PATCH qty', {
    'patch': qPatch.brief,
    'pre': qPre?['quantity'],
    'post': qPost?['quantity'],
  }, lens: 'AA7');
  final n0 = numOf(qPre?['quantity']) ?? 0;
  final n1 = numOf(qPost?['quantity']) ?? 0;
  if (qPatch.ok && n1 != n0 && n1 == 99) {
    c.hold(
      id: 'RTAA-AA7-patch-qty-foreign-real',
      lens: 'AA7',
      severity: 'P1',
      title: '2.º seller alterou qty (persistido)',
      actor: 'seller2 JWT',
      pre: 'qty=$n0',
      repro: 'PATCH live_items.quantity=99',
      expected: 'qty inalterada',
      obtained: {'pre': n0, 'post': n1, 'hit': qPatch.brief},
    );
  } else {
    c.block('RTAA-AA7-patch-qty-foreign-real', 'AA7',
        'seller2 PATCH qty não persistiu', {
      'pre': n0,
      'post': n1,
      'hit': qPatch.brief,
    });
  }
}

Future<void> helperPatchConverted(
    Rtaa c, String liveA, String? itemLo) async {
  if (itemLo == null) return;
  final fb = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemLo,
    buyer: c.buyer2Id,
    jwt: c.sellerJwt,
  );
  final id = fb.firstId;
  if (id == null) return;
  c.createdReqIds.add(id);
  final patch = await c.rest(
    'PATCH',
    'live_reservation_requests?id=eq.$id',
    jwt: c.helperJwt,
    body: {'status': 'converted'},
  );
  final row = await c.reqRow(id);
  final stock = await c.stock(itemLo);
  c.note('p2.helper.patch.converted', 'helper PATCH converted', {
    'patch': patch.brief,
    'status': row?['status'],
    'stock': stock.map,
  }, lens: 'AA2');
  if (patch.ok && row?['status'] == 'converted') {
    c.hold(
      id: 'RTAA-AA2-helper-patch-converted',
      lens: 'AA2',
      severity: 'P1',
      title: 'helper PATCH facebook_manual → converted sem PI',
      actor: 'helper JWT',
      pre: 'staff can_manage_reservations; pending',
      repro: 'PATCH live_reservation_requests.status=converted',
      expected: 'RPC convert_requires_paid_order também no PATCH',
      obtained: {'row': row, 'stock': stock.map},
    );
  } else {
    c.block('RTAA-AA2-helper-patch-converted', 'AA2',
        'helper PATCH converted recusado', patch.brief);
  }
}

Future<void> buyerPatchConverted(
    Rtaa c, String liveA, String? itemLo) async {
  if (itemLo == null) return;
  final fl = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemLo,
    buyer: c.buyerId,
    source: 'fleaber_live',
    jwt: c.buyerJwt,
  );
  final id = fl.firstId;
  if (id == null) {
    c.note('p2.buyer.insert.fl', 'buyer fleaber_live insert', fl.brief,
        lens: 'AA1');
    return;
  }
  c.createdReqIds.add(id);
  final patch = await c.rest(
    'PATCH',
    'live_reservation_requests?id=eq.$id',
    jwt: c.buyerJwt,
    body: {'status': 'converted'},
  );
  final row = await c.reqRow(id);
  c.note('p2.buyer.patch.converted', 'buyer PATCH converted', {
    'patch': patch.brief,
    'status': row?['status'],
  }, lens: 'AA1');
  if (patch.ok && row?['status'] == 'converted') {
    c.hold(
      id: 'RTAA-AA1-buyer-patch-converted',
      lens: 'AA1',
      severity: 'P1',
      title: 'comprador PATCH a própria reserva para converted',
      actor: 'buyer JWT',
      pre: 'fleaber_live pending',
      repro: 'PATCH status=converted',
      expected: 'trigger restaura pending',
      obtained: row,
    );
  } else {
    c.block('RTAA-AA1-buyer-patch-converted', 'AA1',
        'buyer PATCH converted recusado/restaurado', {
      'hit': patch.brief,
      'status': row?['status'],
    });
  }
}

Future<void> qtyThenPatch(Rtaa c, String liveA, String? itemLo) async {
  if (itemLo == null) return;
  final fb = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemLo,
    buyer: c.buyerId,
    qty: 1,
    jwt: c.sellerJwt,
  );
  final id = fb.firstId;
  if (id == null) return;
  c.createdReqIds.add(id);
  final q = await c.rest(
    'PATCH',
    'live_reservation_requests?id=eq.$id',
    jwt: c.sellerJwt,
    body: {'requested_qty': 4, 'status': 'converted'},
  );
  final row = await c.reqRow(id);
  final stock = await c.stock(itemLo);
  c.note('p2.qty+converted', 'PATCH qty=4 + converted', {
    'patch': q.brief,
    'row': row,
    'stock': stock.map,
  }, lens: 'AA3');
  final rq = numOf(row?['requested_qty']) ?? 0;
  if (q.ok && row?['status'] == 'converted' && rq >= 4) {
    c.hold(
      id: 'RTAA-AA3-patch-qty-and-converted',
      lens: 'AA3',
      severity: 'P1',
      title: 'PATCH requested_qty=4 e converted na mesma chamada sem PI',
      actor: 'seller JWT',
      pre: 'facebook_manual pending qty=1; item qty=5',
      repro: 'PATCH requested_qty=4,status=converted',
      expected: 'qty_exceeds ou convert só com pago',
      obtained: {'row': row, 'stock': stock.map},
    );
  } else {
    c.block('RTAA-AA3-patch-qty-and-converted', 'AA3',
        'PATCH qty+converted não ficou converted qty=4', {
      'hit': q.brief,
      'status': row?['status'],
      'qty': rq,
    });
  }
}

Future<void> stockAndHub(
    Rtaa c, String liveA, String? itemLo, String? itemOne) async {
  if (itemOne == null) return;
  final fb = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemOne,
    buyer: c.buyer2Id,
    jwt: c.sellerJwt,
  );
  final id = fb.firstId;
  if (id == null) return;
  c.createdReqIds.add(id);
  final stock0 = await c.stock(itemOne);
  final patch = await c.rest(
    'PATCH',
    'live_reservation_requests?id=eq.$id',
    jwt: c.sellerJwt,
    body: {'status': 'converted'},
  );
  final stock1 = await c.stock(itemOne);
  final item = await c.itemRow(itemOne);
  final hub = await c.hubItem(itemOne);
  final row = await c.reqRow(id);
  c.note('p2.stock.hub', 'qty=1 PATCH converted → stock/hub/item', {
    'stock0': stock0.map,
    'patch': patch.brief,
    'stock1': stock1.map,
    'item': item,
    'hub': hub,
    'res': row?['status'],
  }, lens: 'AA3');

  final avail = numOf(stock1.map?['available_qty'] ?? stock1.map?['available']);
  final sold = numOf(stock1.map?['sold_converted_qty']);
  final itemStatus = item?['status']?.toString();
  if (row?['status'] == 'converted') {
    if (hub != null && (avail == null || avail > 0) && itemStatus != 'sold') {
      c.hold(
        id: 'RTAA-AA3-converted-still-in-hub',
        lens: 'AA3',
        severity: 'P1',
        title: 'PATCH converted qty=1 mas Hub/item ainda disponíveis',
        actor: 'seller JWT',
        pre: 'live_only qty=1',
        repro: 'PATCH converted; GET hub_live_items_public + stock',
        expected: 'item sold / Hub esconde / available=0',
        obtained: {
          'stock': stock1.map,
          'item_status': itemStatus,
          'hub': hub,
          'avail': avail,
          'sold_converted': sold,
        },
      );
    } else {
      c.block('RTAA-AA3-converted-still-in-hub', 'AA3',
          'converted reflectiu stock/hub', {
        'avail': avail,
        'item': itemStatus,
        'hub': hub != null,
        'sold': sold,
      });
    }
  }
}

Future<void> paidOrderReuse(
  Rtaa c,
  String liveA,
  String? pid,
  String? itemM,
  Map<String, num> w0,
) async {
  if (pid == null || itemM == null) {
    c.skip('RTAA-AA8-reuse', 'AA8', 'sem SKU mkt', null);
    return;
  }
  final paid = await c.rest('POST', 'orders', service: true, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pid,
    'price_total': 12.0,
    'quantity': 1,
    'status': 'pago',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
    'live_item_id': itemM,
    'live_id': liveA,
    'amount_paid_cents': 1200,
    'stripe_payment_intent_id': 'pi_rtaa_p2_reuse',
  });
  if (paid.firstId != null) c.createdOrderIds.add(paid.firstId!);
  c.note('p2.paid.fixture', 'order paga mkt', {
    'hit': paid.brief,
    'row': paid.firstId == null ? null : await c.orderRow(paid.firstId!),
  }, lens: 'AA8');

  Future<HttpHit?> convOne() async {
    final r = await c.insertReservation(
      liveId: liveA,
      liveItemId: itemM,
      buyer: c.buyerId,
      jwt: c.sellerJwt,
    );
    final id = r.firstId;
    if (id == null) return null;
    c.createdReqIds.add(id);
    await c.processReservation(id, 'accept');
    return c.processReservation(id, 'convert');
  }

  final a = await convOne();
  final b = await convOne();
  final w1 = await c.wallets();
  c.note('p2.reuse.converts', 'convert ×2 com 1 PI', {
    'a': a?.brief,
    'b': b?.brief,
    'dSeller': (w1['seller'] ?? 0) - (w0['seller'] ?? 0),
  }, lens: 'AA8');
  if (a?.rpcOk == true && b?.rpcOk == true) {
    c.hold(
      id: 'RTAA-AA8-paid-order-reuse-real',
      lens: 'AA8',
      severity: 'P1',
      title: 'uma order paga desbloqueia dois RPC convert',
      actor: 'seller JWT',
      pre: '1 order pago qty=1 amount_paid_cents=1200; SKU qty=3',
      repro: 'accept+convert facebook_manual ×2 mesmo buyer+item',
      expected: '2.º convert recusado (order já consumida)',
      obtained: {'a': a?.brief, 'b': b?.brief},
    );
  } else {
    c.block('RTAA-AA8-paid-order-reuse-real', 'AA8',
        'não há dois convert ok', {'a': a?.brief, 'b': b?.brief});
  }

  // Convert qty=3 com order qty=1.
  final fat = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemM,
    buyer: c.buyerId,
    qty: 3,
    jwt: c.sellerJwt,
  );
  if (fat.firstId != null) {
    c.createdReqIds.add(fat.firstId!);
    await c.processReservation(fat.firstId!, 'accept');
    final conv = await c.processReservation(fat.firstId!, 'convert');
    final row = await c.reqRow(fat.firstId!);
    c.note('p2.convert.qty3', 'convert qty=3 com order qty=1', {
      'conv': conv.brief,
      'row': row,
    }, lens: 'AA8');
    if (conv.rpcOk && row?['status'] == 'converted') {
      c.hold(
        id: 'RTAA-AA8-convert-qty-gt-paid',
        lens: 'AA8',
        severity: 'P1',
        title: 'convert facebook qty=3 com order paga qty=1',
        actor: 'seller JWT',
        pre: 'order qty=1 cents=1200',
        repro: 'facebook_manual requested_qty=3 + convert',
        expected: 'convert recusado ou qty limitada à order',
        obtained: {'conv': conv.brief, 'row': row},
      );
    } else {
      c.block('RTAA-AA8-convert-qty-gt-paid', 'AA8',
          'convert qty>paid recusado', conv.brief);
    }
  }
}

Future<void> helperMarkSold(Rtaa c, String? itemLo) async {
  if (itemLo == null) return;
  final m = await c.markSold(itemLo, jwt: c.helperJwt);
  final item = await c.itemRow(itemLo);
  c.note('p2.helper.mark', 'helper mark_sold live_only dono', {
    'rpc': m.brief,
    'item': item?['status'],
  }, lens: 'AA2');
  if (m.rpcOk && item?['status'] == 'sold') {
    c.hold(
      id: 'RTAA-AA2-helper-mark-sold-owner-item',
      lens: 'AA2',
      severity: 'P1',
      title: 'helper mark_sold item do dono sem can_mark_items_sold',
      actor: 'helper JWT',
      pre: 'perms só can_manage_reservations',
      repro: 'rpc batata_mark_live_item_sold',
      expected: 'not_allowed',
      obtained: {'rpc': m.brief, 'status': item?['status']},
    );
  } else {
    c.block('RTAA-AA2-helper-mark-sold-owner-item', 'AA2',
        'helper mark_sold dono recusado', m.brief);
  }
}

Future<void> checkoutAfterPatch(
  Rtaa c,
  String liveA,
  String? itemOne,
  String? pid,
) async {
  if (itemOne == null) return;
  final st = await c.itemRow(itemOne);
  final pi = await c.edge('create-payment-intent', {
    'product_id': pid,
    'live_item_id': itemOne,
    'live_id': liveA,
    'quantity': 1,
    'shipping_method': 'entrega em mão',
  }, jwt: c.buyerJwt);
  c.note('p2.checkout.after.converted', 'PI após PATCH converted qty=1', {
    'item': st,
    'pi': pi.brief,
  }, lens: 'AA8');
  if (pi.ok && (pi.map?['client_secret'] != null || pi.body.contains('pi_'))) {
    c.hold(
      id: 'RTAA-AA8-checkout-after-converted-patch',
      lens: 'AA8',
      severity: 'P1',
      title: 'checkout Stripe ainda possível após PATCH converted (qty=1)',
      actor: 'buyer JWT',
      pre: 'item qty=1 já converted via PATCH',
      repro: 'POST create-payment-intent',
      expected: 'sem stock / item_sold',
      obtained: {'item': st, 'pi': pi.brief},
    );
  } else {
    c.block('RTAA-AA8-checkout-after-converted-patch', 'AA8',
        'checkout após converted recusado', pi.brief);
  }
}

Future<void> ingestOcr(Rtaa c, String liveA) async {
  final noTok = await c.edge('ingest-ocr-reservation', {
    'live_id': liveA,
    'ocr_line_hash': 'abcdefghijkl',
    'detected_at': DateTime.now().toUtc().toIso8601String(),
    'ref_slug': 'P2A',
    'requested_qty': 1,
    'external_display_name': 'RTAA',
  }, jwt: c.buyerJwt);
  c.note('p2.ocr.notoken', 'ingest-ocr sem device token', noTok.brief,
      lens: 'AA1');
  if (noTok.ok) {
    c.hold(
      id: 'RTAA-AA1-ocr-no-token',
      lens: 'AA1',
      severity: 'P1',
      title: 'ingest-ocr-reservation sem device token',
      actor: 'buyer JWT',
      pre: 'live A',
      repro: 'POST ingest-ocr-reservation',
      expected: '401 missing_device_token',
      obtained: noTok.brief,
    );
  } else {
    c.block('RTAA-AA1-ocr-no-token', 'AA1', 'ocr sem token recusado',
        noTok.brief);
  }

  final fake = await c.req(
    'POST',
    '/functions/v1/ingest-ocr-reservation',
    jwt: c.buyerJwt,
    body: {
      'live_id': liveA,
      'ocr_line_hash': 'abcdefghijkl',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'ref_slug': 'P2A',
      'requested_qty': 2,
      'external_display_name': 'Evil',
    },
    extra: {'x-device-token': 'rtaa-fake-token'},
  );
  c.note('p2.ocr.faketoken', 'ingest-ocr token inventado', fake.brief,
      lens: 'AA1');
  if (fake.ok) {
    c.hold(
      id: 'RTAA-AA1-ocr-fake-token',
      lens: 'AA1',
      severity: 'P1',
      title: 'ingest-ocr com device token inventado cria reserva',
      actor: 'buyer JWT',
      pre: 'x-device-token aleatório',
      repro: 'POST ingest-ocr-reservation',
      expected: '401 invalid device',
      obtained: fake.brief,
    );
  } else {
    c.block('RTAA-AA1-ocr-fake-token', 'AA1',
        'ocr fake token recusado', fake.brief);
  }
}

Future<void> muxResolveMutate(
    Rtaa c, String liveA, String liveS2) async {
  final r = await c.edge('resolve-mux-playback', {'live_id': liveS2},
      jwt: c.sellerJwt);
  c.note('p2.resolve.foreign', 'seller1 resolve playback live seller2',
      r.brief, lens: 'AA5');
  if (r.ok && r.map?['ok'] == true) {
    c.hold(
      id: 'RTAA-AA5-resolve-foreign-mutate',
      lens: 'AA5',
      severity: 'P2',
      title: 'resolve-mux-playback em live alheia',
      actor: 'seller JWT',
      pre: 'live S2',
      repro: 'POST resolve-mux-playback live_id=S2',
      expected: '403',
      obtained: r.brief,
    );
  } else {
    c.block('RTAA-AA5-resolve-foreign-mutate', 'AA5',
        'resolve foreign recusado/sem mux', r.brief);
  }
}
