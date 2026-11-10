/// BH pass3c — MB WAY reconcile com order fixture service (JWT INSERT bloqueado por stock quantity-null).
import 'dart:io';
import '_rtbh.dart';

Future<void> main() async {
  final c = Rtbh.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureSeller2();
  final w0 = await c.wallets();

  final liveA = await c.insertLive(title: '$prefix-p3c');
  final sku = await c.insertProduct(price: 14, qty: 2, title: '$prefix-p3c-sku');
  final itemMkt = (liveA == null || sku == null)
      ? null
      : await c.insertLiveItem(
          liveId: liveA,
          kind: 'marketplace_product',
          productId: sku,
          title: '$prefix-p3c-mkt',
        );
  final itemOnly = liveA == null
      ? null
      : await c.insertLiveItem(liveId: liveA, qty: 3, title: '$prefix-p3c-only');

  if (liveA != null && itemMkt != null) {
    final stockB = await c.rpc('batata_live_item_stock', {
      'p_live_item_id': itemMkt,
    }, jwt: c.buyerJwt);
    final stockS = await c.rpc('batata_live_item_stock', {
      'p_live_item_id': itemMkt,
    }, jwt: c.sellerJwt);
    final stockA = await c.rpc('batata_live_item_stock', {
      'p_live_item_id': itemMkt,
    });
    c.note('BH3-mkt-stock', 'stock marketplace_product qty null', {
      'buyer': stockB.brief,
      'seller': stockS.brief,
      'anon': stockA.brief,
    }, lens: 'BH3');
    final buyerHidden = stockB.map?['ok'] == false || stockA.map?['ok'] == false;
    if (buyerHidden && stockS.rpcOk) {
      c.hold(
        id: 'BH3-08',
        lens: 'BH3',
        severity: 'P3',
        title: 'Stock gate trata marketplace_product (quantity NULL) como oculto a buyer/anon em live no ar',
        actor: 'buyer JWT / anon',
        pre: 'item_kind=marketplace_product quantity is null; live broadcasting',
        repro: 'rpc batata_live_item_stock; INSERT orders live_item_id → order_live_item_exhausted',
        expected: 'available_qty do produto, não live_item_not_found',
        obtained: {
          'buyer': stockB.brief,
          'anon': stockA.brief,
          'seller': stockS.brief,
        },
      );
    } else {
      c.block('BH3-08', 'BH3', 'marketplace stock visível buyer', stockB);
    }
  }

  if (liveA == null || sku == null || itemMkt == null) {
    await c.dumpAll('pass3c.json');
    exit(4);
  }

  final pend = await c.rest('POST', 'orders', service: true, body: {
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
    'amount_paid_cents': 0,
  });
  final oid = pend.firstId;
  if (oid != null) c.createdOrderIds.add(oid);
  c.note('BH8-svc-order', 'service order aguarda_confirmacao', pend, lens: 'BH8');
  if (oid == null) {
    c.skip('BH8-01', 'BH8', 'service INSERT order falhou', pend);
    await c.endAllLives();
    await c.dumpAll('pass3c.json');
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

  // also live_only bind
  HttpHit? recOnly;
  if (itemOnly != null) {
    final o2 = await c.rest('POST', 'orders', service: true, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': sku,
      'live_id': liveA,
      'live_item_id': itemOnly,
      'quantity': 1,
      'status': 'aguarda_confirmacao',
      'price_total': 14,
      'payment_method': 'MB WAY',
      'shipping_method': 'entrega em mão',
      'amount_paid_cents': 0,
    });
    final oid2 = o2.firstId;
    if (oid2 != null) {
      c.createdOrderIds.add(oid2);
      recOnly = await c.rpc('batata_live_reconcile_stripe_order', {
        'p_order_id': oid2,
      }, jwt: c.sellerJwt);
    }
  }

  final afterRes = await c.rest(
    'GET',
    'live_reservation_requests?live_id=eq.$liveA&select=id,status,notes,requested_qty,buyer_id,source,live_item_id',
    service: true,
  );
  final order = await c.rest(
    'GET',
    'orders?id=eq.$oid&select=id,status,amount_paid_cents,stripe_payment_intent_id,live_id,live_item_id',
    service: true,
  );
  final w1 = await c.wallets();
  c.note('BH8-rec', 'reconcile MB WAY', {
    'recB': recB.brief,
    'recS': recS.brief,
    'recAnon': recAnon.brief,
    'recS2': recS2?.brief,
    'recOnly': recOnly?.brief,
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
    return notes.contains('stripe_paid') || notes.contains(oid);
  }).toList();
  final unpaid = numOf(order.map?['amount_paid_cents']) == 0 &&
      (order.map?['stripe_payment_intent_id'] == null ||
          '${order.map?['stripe_payment_intent_id']}'.isEmpty);

  if (unpaid && newConsuming.isNotEmpty) {
    c.hold(
      id: 'BH8-01',
      lens: 'BH8',
      severity: 'P1',
      title: 'Reconcile MB WAY aguarda_confirmacao converte reserva sem captura',
      actor: 'buyer/seller JWT',
      pre: 'order service fixture sem PI/amount_paid, status aguarda_confirmacao',
      repro: 'rpc batata_live_reconcile_stripe_order JWT',
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
      pre: 'order não capturada',
      repro: 'rpc reconcile',
      expected: 'sem reservation stripe_paid*',
      obtained: {'recB': recB.brief, 'recS': recS.brief, 'ghosts': ghosts},
    );
  } else {
    c.block('BH8-01', 'BH8', 'reconcile MB WAY sem convert/ghost', {
      'recB': recB.brief,
      'recS': recS.brief,
      'res_n': afterRes.list.length,
      'recOnly': recOnly?.brief,
    });
  }

  final dSeller = (w1['seller'] ?? 0) - (w0['seller'] ?? 0);
  final dBuyer = (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0);
  if (dSeller > 0 || dBuyer > 0) {
    c.hold(
      id: 'BH8-03',
      lens: 'BH8',
      severity: 'P0',
      title: 'Reconcile MB WAY mint wallet',
      actor: 'JWT',
      pre: 'sem captura',
      repro: 'Δwallet',
      expected: '0',
      obtained: {'w0': w0, 'w1': w1},
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
    repro: 'rpc anon',
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
  await c.dumpAll('pass3c.json');
  stdout.writeln(
      'DONE p3c findings=${c.findings.length} blocked=${c.blocked.length} lenses=${c.lensesHit.toList()..sort()}');
}
