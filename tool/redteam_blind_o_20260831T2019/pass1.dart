/// REDTEAM_BLIND_O pass 1 — catalog + disputa/envio pós-pago (staging only).
import 'dart:io';

import '_rto.dart';

Future<void> main() async {
  final c = Rto.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final w0 = await c.wallets();
  c.note('p1.wallets0', 'saldos iniciais', w0, lens: 'O8');

  final rpcNames = [
    'batata_order_allows_seller_stripe_refund',
    'batata_process_partial_refund_dispute',
    'batata_refund_buyer_wallet_for_order',
    'batata_release_seller_wallet_for_order',
    'batata_finalize_stripe_order_refund',
    'batata_order_wallet_reembolso_cents',
    'batata_clawback_seller_wallet_for_order',
  ];
  final rpcCat = <String, Object?>{};
  for (final fn in rpcNames) {
    final anon = await c.rpc(fn, {'p_order_id': c.buyerId});
    final buyer = await c.rpc(fn, {'p_order_id': c.buyerId}, jwt: c.buyerJwt);
    rpcCat[fn] = {
      'anon': anon.brief,
      'buyer': buyer.brief,
    };
  }
  c.note('p1.rpc_catalog', 'RPCs disputa/caixa', rpcCat, lens: 'O4');

  final openapi = await c.req(
    'GET',
    '/rest/v1/',
    service: true,
    extra: {'Accept': 'application/openapi+json'},
  );
  final oa = openapi.json is Map ? openapi.json as Map : {};
  final paths = oa['paths'] is Map ? oa['paths'] as Map : {};
  final disputePath = paths['/order_disputes'];
  final ordersPath = paths['/orders'];
  String? colList(Object? pathNode) {
    if (pathNode is! Map) return null;
    final get = pathNode['get'];
    if (get is! Map) return null;
    final params = get['parameters'];
    if (params is! List) return null;
    for (final p in params) {
      if (p is Map && p['name'] == 'select') {
        final sch = p['schema'];
        if (sch is Map && sch['enum'] is List) {
          return (sch['enum'] as List).map((e) => '$e').join(',');
        }
      }
    }
    return null;
  }

  c.note('p1.openapi', 'colunas LIVE', {
    'openapi_http': openapi.status,
    'has_order_disputes': disputePath != null,
    'has_orders': ordersPath != null,
    'dispute_select_hint': clip(colList(disputePath), 400),
    'orders_select_hint': clip(colList(ordersPath), 500),
  }, lens: 'O1');

  // ---- Stripe TEST pago ----
  final fx = await c.payToPago(lens: 'O1', qty: 3);
  if (fx == null) {
    stderr.writeln('setup_paid_order failed');
    await dumpJson('${outDir()}/pass1.json', {
      'notes': c.notes,
      'findings': c.findings,
    });
    return;
  }
  final oid = fx.oid;
  final pid = fx.pid;
  var ord = await c.orderRow(oid);
  var prod = await c.productRow(pid);
  c.note('p1.pago', 'order+product após captura', {
    'order': ord,
    'product': prod,
  }, lens: 'O1');

  // O1 — disputa em pago (UI esconde; API?)
  final dPago = await c.insertDispute(oid);
  final dPagoRow = await c.disputeRow(oid);
  c.note('p1.o1.disp_pago', 'INSERT disputa status=pago', {
    'http': dPago.brief,
    'row': dPagoRow,
    'order': (await c.orderRow(oid))?['status'],
  }, lens: 'O1');
  if (dPago.ok && dPagoRow != null) {
    c.hold(
      id: 'RTO-O1-dispute-on-pago',
      lens: 'O1',
      severity: 'P1',
      title: 'Comprador abre disputa com encomenda ainda em pago (não recebido)',
      actor: 'buyer JWT',
      pre: 'Stripe TEST captura, status=pago, UI só permite concluido/entregue',
      repro: 'POST order_disputes JWT buyer com order.status=pago',
      expected: '403 / RLS / trigger — disputa só após receção',
      obtained: dPago.brief,
      evidence: {'dispute': dPagoRow, 'order': await c.orderRow(oid)},
    );
  }

  // O1 — buyer2 / seller / anon
  final dB2 = await c.insertDispute(oid, jwt: c.buyer2Jwt, buyer: c.buyer2Id);
  final dS = await c.insertDispute(oid, jwt: c.sellerJwt, buyer: c.sellerId);
  final dAnon = await c.insertDispute(oid, jwt: null);
  c.note('p1.o1.cross', 'disputa alheia/anon', {
    'b2': dB2.brief,
    'seller': dS.brief,
    'anon': dAnon.brief,
  }, lens: 'O1');
  if (dB2.ok) {
    c.hold(
      id: 'RTO-O1-buyer2-dispute',
      lens: 'O1',
      severity: 'P0',
      title: '2.º comprador abre disputa na encomenda alheia',
      actor: 'buyer2 JWT',
      pre: 'order de B1',
      repro: 'POST order_disputes JWT B2',
      expected: '403',
      obtained: dB2.brief,
    );
  }

  // O6 — shipping_method pós-pago
  final shipMao = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
    'shipping_method': 'entrega em mão',
  });
  final shipCarrier = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
    'shipping_method': 'CTT',
  });
  final shipAfter = await c.orderRow(oid);
  c.note('p1.o6.ship_seal', 'PATCH shipping_method pós-pago', {
    'buyer_mao': shipMao.brief,
    'seller_ctt': shipCarrier.brief,
    'shipping_method': shipAfter?['shipping_method'],
  }, lens: 'O6');
  if (shipMao.ok && shipAfter?['shipping_method'] == 'entrega em mão') {
    c.hold(
      id: 'RTO-O6-unseal-shipping',
      lens: 'O6',
      severity: 'P1',
      title: 'Comprador muda portes para mão depois de pago',
      actor: 'buyer JWT',
      pre: 'order Stripe paga',
      repro: 'PATCH shipping_method=entrega em mão',
      expected: 'order_shipping_frozen_after_payment',
      obtained: '${shipMao.brief} method=${shipAfter?['shipping_method']}',
    );
  }

  // O6 — tracking / proof_url alheio
  final proof = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
    'proof_url': 'https://evil.example/tracking/ALHEIO',
  });
  c.note('p1.o6.proof', 'PATCH proof_url', proof.brief, lens: 'O6');

  // O2 — enviado com disputa (se disputa em pago colou, senão só enviado)
  final env = await c.markEnviado(oid);
  ord = await c.orderRow(oid);
  c.note('p1.o2.enviado', 'seller enviado', {
    'http': env.brief,
    'status': ord?['status'],
    'dispute': await c.disputeRow(oid),
  }, lens: 'O2');

  // O1 — disputa em enviado (se ainda não há)
  if (await c.disputeRow(oid) == null) {
    final dEnv = await c.insertDispute(oid);
    c.note('p1.o1.disp_enviado', 'INSERT disputa status=enviado', {
      'http': dEnv.brief,
      'row': await c.disputeRow(oid),
    }, lens: 'O1');
    if (dEnv.ok) {
      c.hold(
        id: 'RTO-O1-dispute-on-enviado',
        lens: 'O1',
        severity: 'P1',
        title: 'Disputa aberta com artigo só marcado enviado (não recebido)',
        actor: 'buyer JWT',
        pre: 'status=enviado',
        repro: 'POST order_disputes',
        expected: 'bloqueado — só concluido/entregue',
        obtained: dEnv.brief,
        evidence: {'order': await c.orderRow(oid), 'dispute': await c.disputeRow(oid)},
      );
    }
  }

  // O5 — buyer concluido
  final conc = await c.markConcluido(oid);
  ord = await c.orderRow(oid);
  c.note('p1.o5.concluido', 'buyer concluido', {
    'http': conc.brief,
    'order': ord,
  }, lens: 'O5');

  // O1 — disputa em concluido (caminho UI)
  if (await c.disputeRow(oid) == null) {
    final dConc = await c.insertDispute(oid);
    c.note('p1.o1.disp_concluido', 'INSERT disputa concluido', dConc.brief, lens: 'O1');
  }

  // O3 — pedido_devolucao sem disputa vs com
  final pd = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
    'status': 'pedido_devolucao',
  });
  c.note('p1.o3.pedido_dev', 'PATCH pedido_devolucao', {
    'http': pd.brief,
    'status': (await c.orderRow(oid))?['status'],
    'has_dispute': await c.disputeRow(oid) != null,
  }, lens: 'O3');

  // O4 — refund-order em vários estados
  final refS = await c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt);
  final refB = await c.edge('refund-order', {'order_id': oid}, jwt: c.buyerJwt);
  final refS2 = await c.edge('refund-order', {'order_id': oid}, jwt: c.seller2Jwt);
  c.note('p1.o4.refund', 'refund-order', {
    'seller': refS.brief,
    'buyer': refB.brief,
    'seller2': refS2.brief,
    'order': await c.orderRow(oid),
  }, lens: 'O4');

  // O4 — wallet RPCs nesta order
  final rwB = await c.rpc('batata_refund_buyer_wallet_for_order', {'p_order_id': oid},
      jwt: c.buyerJwt);
  final rwS = await c.rpc('batata_refund_buyer_wallet_for_order', {'p_order_id': oid},
      jwt: c.sellerJwt);
  final relB = await c.rpc('batata_release_seller_wallet_for_order', {'p_order_id': oid},
      jwt: c.buyerJwt);
  c.note('p1.o4.wallet_rpc', 'refund/release JWT', {
    'refund_buyer': rwB.brief,
    'refund_seller': rwS.brief,
    'release_buyer': relB.brief,
    'wallets': await c.wallets(),
    'txns': await c.walletTxns(orderId: oid),
  }, lens: 'O4');

  // O6 — seller enviado em reserva (sem captura)
  final holdProd = await c.rest('POST', 'products', jwt: c.sellerJwt, body: {
    'seller_id': c.sellerId,
    'title': '$prefix-unpaid',
    'price': 4.5,
    'quantity': 2,
    'is_sold': false,
    'list_on_marketplace': true,
    'available_for_live': false,
    'description': prefix,
    'image_urls': <String>[],
  });
  final holdPid = holdProd.firstId;
  HttpHit? holdOrd;
  if (holdPid != null) {
    c.createdProductIds.add(holdPid);
    holdOrd = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': holdPid,
      'price_total': 4.5,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'CTT',
    });
  }
  String? holdOid = holdOrd?.firstId;
  HttpHit? holdEnv;
  if (holdOid != null) {
    c.createdOrderIds.add(holdOid);
    holdEnv = await c.markEnviado(holdOid);
  }
  c.note('p1.o6.enviado_unpaid', 'enviado sem captura', {
    'product': holdProd.brief,
    'order': holdOrd?.brief,
    'enviado': holdEnv?.brief,
    'status': holdOid == null ? null : (await c.orderRow(holdOid))?['status'],
  }, lens: 'O6');
  if (holdEnv != null &&
      holdEnv.ok &&
      (await c.orderRow(holdOid!))?['status'] == 'enviado') {
    c.hold(
      id: 'RTO-O6-enviado-sem-captura',
      lens: 'O6',
      severity: 'P1',
      title: 'Vendedor marca enviado sem pagamento capturado',
      actor: 'seller JWT',
      pre: 'reserva_pendente sem PI',
      repro: 'PATCH status=enviado',
      expected: 'estado permanece reserva_pendente',
      obtained: '${holdEnv.brief} status=${(await c.orderRow(holdOid))?['status']}',
    );
  }

  final out = {
    'auditor': 'REDTEAM_BLIND_O_DISPUTA_ENVIO_v1',
    'stamp': stamp,
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
    'wallets0': w0,
    'wallets1': await c.wallets(),
    'notes': c.notes,
    'findings': c.findings,
    'orders': c.createdOrderIds,
    'products': c.createdProductIds,
  };
  await dumpJson('${outDir()}/pass1.json', out);
  stdout.writeln('WROTE pass1.json findings=${c.findings.length}');
}
