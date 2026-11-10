/// PASS 3 — último ciclo: de onde veio +10 seller; release→devolvida; restock após refund saco.
import 'dart:io';
import '_rtp.dart';

void main() async {
  final env = loadEnv();
  final c = Rtp.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  final w0 = await c.wallets();
  c.note('p3.w0', 'wallets', w0, lens: 'P10');

  final tx = await c.walletTxns(walletId: c.sellerId, limit: 15);
  c.note('p3.seller.tx', 'últimos créditos seller', tx, lens: 'P10');

  for (final oid in [
    '45134e15-e61d-4d6e-b965-231875b27ce4', // pass1 concluido
    'c88d2171-09ec-4065-8075-48699ce04661', // pass2 release
    'ec49661c-76c7-48e4-b408-f11bb94affbc', // pass2 refund pago
  ]) {
    final row = await c.orderRow(oid);
    c.note('p3.ord.$oid', 'order observe', {
      'st': row?['status'],
      'paid': row?['amount_paid_cents'],
      'rid': row?['stripe_refund_id'],
      'rel': row?['wallet_release_processed_at'],
      'refw': row?['wallet_refund_processed_at'],
    }, lens: 'P10');
  }

  // P1+P5: após release, buyer PATCH devolvida (mint estorno)
  final paid = await c.e2e('setup_paid_order', {'initial_qty': 2});
  final oid = c.parseE2eOrderId(paid);
  c.note('p3.paid', 'pago', paid.brief, lens: 'P5');
  if (oid != null) {
    c.createdOrderIds.add(oid);
    await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
      'shipping_method': 'entrega em mão',
      'status': 'enviado',
    });
    await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
      'status': 'concluido',
    });
    final wB = await c.wallets();
    final rel = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oid},
      jwt: c.buyerJwt,
    );
    final wR = await c.wallets();
    final devB = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: c.buyerJwt,
      body: {'status': 'devolvida'},
    );
    final devS = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: c.sellerJwt,
      body: {'status': 'devolvida'},
    );
    final wD = await c.wallets();
    final row = await c.orderRow(oid);
    c.note('p3.dev', 'release + PATCH devolvida', {
      'rel': rel.brief,
      'devB': devB.brief,
      'devS': devS.brief,
      'status': row?['status'],
      'dSellerRel': (wR['seller'] ?? 0) - (wB['seller'] ?? 0),
      'dBuyerDev': (wD['buyer'] ?? 0) - (wR['buyer'] ?? 0),
      'dSellerDev': (wD['seller'] ?? 0) - (wR['seller'] ?? 0),
    }, lens: 'P1');
    final dBuyer = (wD['buyer'] ?? 0) - (wR['buyer'] ?? 0);
    if (dBuyer > 0.01 && (row?['stripe_refund_id'] == null)) {
      c.hold(
        id: 'RTP-P1-003',
        lens: 'P1+P5',
        severity: 'P0',
        title: 'Após release, PATCH devolvida minta carteira comprador sem Stripe refund',
        actor: 'buyer/seller JWT',
        pre: 'concluido+release $oid',
        repro: 'PATCH status=devolvida',
        expected: 'sem crédito buyer sem stripe_refund_id',
        obtained: {'dBuyer': dBuyer, 'row': row, 'devB': devB.brief, 'devS': devS.brief},
      );
    }
  }

  // P7+P2: refund linha A → restock → 2.º hold/checkout no mesmo SKU enquanto B pago
  final bag = await c.e2e('setup_paid_bag', {});
  final bm = bag.map ?? {};
  final oa = bm['order_a_id']?.toString();
  final pa = bm['product_a_id']?.toString();
  c.note('p3.bag', 'bag', {'oa': oa, 'pa': pa, 'qtyA': bm['orders']}, lens: 'P7');
  if (oa != null && pa != null) {
    await c.edge('refund-order', {'order_id': oa}, jwt: c.sellerJwt);
    final prod = await c.productRow(pa);
    final ins = await c.rest('POST', 'orders', jwt: c.buyer2Jwt, body: {
      'buyer_id': c.buyer2Id,
      'seller_id': c.sellerId,
      'product_id': pa,
      'price_total': 3.0,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    HttpHit? ck;
    if (ins.firstId != null) {
      ck = await c.checkout(
        orderId: ins.firstId!,
        jwt: c.buyer2Jwt,
        buyer: c.buyer2Id,
      );
    }
    c.note('p3.restock', 'refund A → hold B2 no SKU A', {
      'prod': prod,
      'ins': ins.brief,
      'ck': ck?.brief,
      'sid': ck?.map?['checkoutSessionId'],
    }, lens: 'P7');
    // Restock + 2.ª venda é LEGÍTIMO se qty inicial era 3. Só finding se qty era 1 e oversell.
  }

  final wEnd = await c.wallets();
  c.note('p3.wEnd', 'wallets', {'w0': w0, 'wEnd': wEnd}, lens: 'P10');

  await dumpJson('${outDir()}/pass3.json', {
    'pass': 3,
    'findings': c.findings,
    'notes': c.notes,
    'w0': w0,
    'wEnd': wEnd,
  });
  stdout.writeln('PASS3 FINDINGS ${c.findings.length}');
  for (final f in c.findings) {
    stdout.writeln('  ${f['severity']} ${f['id']} ${f['title']}');
  }
}
