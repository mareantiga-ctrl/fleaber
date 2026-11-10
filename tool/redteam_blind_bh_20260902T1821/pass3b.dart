/// BH pass3b — reconcile MB WAY pending fantasma em live/item frescos.
import 'dart:io';
import '_rtbh.dart';

Future<void> main() async {
  final c = Rtbh.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureSeller2();
  final w0 = await c.wallets();

  final liveA = await c.insertLive(title: '$prefix-p3b');
  if (liveA == null) {
    await c.dumpAll('pass3b.json');
    exit(4);
  }
  final sku = await c.insertProduct(price: 14, qty: 2, title: '$prefix-p3b-sku');
  final itemMkt = sku == null
      ? null
      : await c.insertLiveItem(
          liveId: liveA,
          kind: 'marketplace_product',
          productId: sku,
          title: '$prefix-p3b-mkt',
        );
  if (sku == null || itemMkt == null) {
    c.skip('BH8-00', 'BH8', 'sem SKU', null);
    await c.dumpAll('pass3b.json');
    exit(0);
  }

  HttpHit pend = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': sku,
    'live_id': liveA,
    'live_item_id': itemMkt,
    'quantity': 1,
    'status': 'aguarda_confirmacao',
    'price_total': 14,
    'payment_method': 'MB WAY',
    'shipping_method': 'entrega em mão',
  });
  c.note('BH8-ins-ac', 'INSERT aguarda_confirmacao', pend, lens: 'BH8');
  var oid = pend.firstId;
  if (oid == null) {
    pend = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': sku,
      'live_id': liveA,
      'live_item_id': itemMkt,
      'quantity': 1,
      'status': 'reserva_pendente',
      'price_total': 14,
      'payment_method': 'MB WAY',
      'shipping_method': 'entrega em mão',
    });
    oid = pend.firstId;
    c.note('BH8-ins-rp', 'INSERT reserva_pendente', pend, lens: 'BH8');
    if (oid != null) {
      final patch = await c.rest(
        'PATCH',
        'orders?id=eq.$oid',
        jwt: c.buyerJwt,
        body: {'status': 'aguarda_confirmacao'},
      );
      c.note('BH8-patch-ac', 'PATCH aguarda_confirmacao', patch, lens: 'BH8');
    }
  }
  if (oid != null) c.createdOrderIds.add(oid);
  if (oid == null) {
    c.skip('BH8-01', 'BH8', 'não criei order MB WAY', pend);
    await c.endAllLives();
    await c.dumpAll('pass3b.json');
    return;
  }

  final recB = await c.rpc('batata_live_reconcile_stripe_order', {
    'p_order_id': oid,
  }, jwt: c.buyerJwt);
  final recS = await c.rpc('batata_live_reconcile_stripe_order', {
    'p_order_id': oid,
  }, jwt: c.sellerJwt);
  final recAnon = await c.rpc('batata_live_reconcile_stripe_order', {
    'p_order_id': oid,
  });
  final recS2 = c.seller2Jwt == null
      ? null
      : await c.rpc('batata_live_reconcile_stripe_order', {
          'p_order_id': oid,
        }, jwt: c.seller2Jwt);

  final afterRes = await c.rest(
    'GET',
    'live_reservation_requests?live_item_id=eq.$itemMkt&select=id,status,notes,requested_qty,buyer_id,source',
    service: true,
  );
  final order = await c.rest(
    'GET',
    'orders?id=eq.$oid&select=id,status,amount_paid_cents,stripe_payment_intent_id,live_id,live_item_id,payment_method',
    service: true,
  );
  final w1 = await c.wallets();
  c.note('BH8-rec', 'reconcile results', {
    'recB': recB.brief,
    'recS': recS.brief,
    'recAnon': recAnon.brief,
    'recS2': recS2?.brief,
    'order': order.map,
    'res': afterRes.list,
    'w0': w0,
    'w1': w1,
  }, lens: 'BH8');

  bool consuming(dynamic r) {
    if (r is! Map) return false;
    final st = '${r['status']}';
    return st == 'accepted' || st == 'converted';
  }

  final newConsuming = afterRes.list.where(consuming).toList();
  final ghosts = afterRes.list.where((r) {
    if (r is! Map) return false;
    final notes = '${r['notes']}';
    return notes.contains(oid!) ||
        notes.contains('stripe_paid') ||
        notes.contains('stripe_checkout');
  }).toList();

  final unpaid = numOf(order.map?['amount_paid_cents']) == 0 &&
      (order.map?['stripe_payment_intent_id'] == null ||
          '${order.map?['stripe_payment_intent_id']}'.isEmpty);

  if (unpaid && newConsuming.isNotEmpty) {
    c.hold(
      id: 'BH8-01',
      lens: 'BH8',
      severity: 'P1',
      title: 'Reconcile MB WAY aguarda_confirmacao converte/accept sem captura',
      actor: 'buyer/seller JWT',
      pre: 'order sem amount_paid nem PI',
      repro: 'rpc batata_live_reconcile_stripe_order',
      expected: 'order_not_paid',
      obtained: {
        'recB': recB.brief,
        'recS': recS.brief,
        'consuming': newConsuming,
        'order': order.map,
      },
    );
  } else if (unpaid && ghosts.isNotEmpty) {
    c.hold(
      id: 'BH8-02',
      lens: 'BH8',
      severity: 'P2',
      title: 'Reconcile MB WAY pending cria fila fantasma',
      actor: 'JWT',
      pre: 'order MB WAY não capturada',
      repro: 'rpc batata_live_reconcile_stripe_order',
      expected: 'sem INSERT reservation',
      obtained: {
        'recB': recB.brief,
        'recS': recS.brief,
        'ghosts': ghosts,
        'order': order.map,
      },
    );
  } else {
    c.block('BH8-01', 'BH8', 'reconcile MB WAY sem convert/ghost', {
      'recB': recB.brief,
      'recS': recS.brief,
      'res_n': afterRes.list.length,
    });
  }

  final dSeller = (w1['seller'] ?? 0) - (w0['seller'] ?? 0);
  final dBuyer = (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0);
  if (dSeller > 0 || dBuyer > 0) {
    c.hold(
      id: 'BH8-03',
      lens: 'BH8',
      severity: 'P0',
      title: 'Reconcile MB WAY pending mintou wallet',
      actor: 'JWT',
      pre: 'sem captura',
      repro: 'wallets antes/depois',
      expected: 'Δ=0',
      obtained: {'w0': w0, 'w1': w1, 'dSeller': dSeller, 'dBuyer': dBuyer},
    );
  } else {
    c.block('BH8-03', 'BH8', 'sem Δ wallet', {'dSeller': dSeller, 'dBuyer': dBuyer});
  }

  await c.expectDenied(
    id: 'BH8-04',
    lens: 'BH8',
    title: 'Anon reconcile',
    hit: recAnon,
    actor: 'anon',
    pre: 'GRANT',
    repro: 'rpc reconcile anon',
    severityIfOpen: 'P2',
    openIf: (h) => h.rpcOk,
  );
  if (recS2 != null) {
    await c.expectDenied(
      id: 'BH8-05',
      lens: 'BH8',
      title: 'Seller2 reconcile order alheia',
      hit: recS2,
      actor: 'seller2 JWT',
      pre: 'não é party',
      repro: 'rpc reconcile',
      severityIfOpen: 'P1',
      openIf: (h) => h.rpcOk,
    );
  }

  await c.endAllLives();
  await c.dumpAll('pass3b.json');
  stdout.writeln(
      'DONE p3b findings=${c.findings.length} blocked=${c.blocked.length} lenses=${c.lensesHit.toList()..sort()}');
}
