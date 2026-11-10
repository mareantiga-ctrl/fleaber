import 'dart:convert';
import 'dart:io';

import '_http.dart';

Future<void> main() async {
  final ctx = await boot();
  final out = <String, dynamic>{};

  Future<dynamic> svc(String path) async {
    final h = await ctx.rest('GET', path, service: true);
    return {'status': h.status, 'body': h.json};
  }

  out['seller_wallet'] = await svc(
      '/rest/v1/wallets?id=eq.${ctx.sellerId}&select=id,balance,updated_at');
  out['buyer_wallet'] = await svc(
      '/rest/v1/wallets?id=eq.${ctx.buyerId}&select=id,balance,updated_at');

  out['seller_tx'] = await svc(
      '/rest/v1/wallet_transactions?wallet_id=eq.${ctx.sellerId}&select=id,amount,type,description,order_id,created_at&order=created_at.desc&limit=25');
  out['buyer_tx'] = await svc(
      '/rest/v1/wallet_transactions?wallet_id=eq.${ctx.buyerId}&select=id,amount,type,description,order_id,created_at&order=created_at.desc&limit=25');

  out['payout_ledger'] = await svc(
      '/rest/v1/wallet_payout_ledger?user_id=eq.${ctx.sellerId}&select=idempotency_key,amount_cents,amount_eur,status,stripe_transfer_id,balance_after,created_at,updated_at&order=created_at.desc&limit=15');

  out['mbway_order'] = await svc(
      '/rest/v1/orders?id=eq.baaff7f4-2cb4-4229-b0bb-0e7467f269d8&select=id,status,payment_method,price_total,amount_paid_cents,wallet_release_processed_at,wallet_refund_processed_at,stock_units_applied,stripe_payment_intent_id');

  out['review_mbway'] = await svc(
      '/rest/v1/reviews?id=eq.a1ed1c22-86a4-4887-b939-3fce44f13bc5&select=id,order_id,stars,purchase_verified,author_role,target_id,buyer_id,is_automatic,comment');

  out['public_ratings_mbway'] = await svc(
      '/rest/v1/reviews_public_ratings?id=eq.a1ed1c22-86a4-4887-b939-3fce44f13bc5&select=*');

  out['stripe_order1'] = await svc(
      '/rest/v1/orders?id=eq.68f58953-b754-417f-aa31-caebc97880ff&select=id,status,amount_paid_cents,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,price_total');

  out['stripe_order2'] = await svc(
      '/rest/v1/orders?id=eq.51ce2be1-d0f4-42e5-b7af-5f166a59d570&select=id,status,amount_paid_cents,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,price_total');

  out['checkout_order'] = await svc(
      '/rest/v1/orders?id=eq.3c9d060b-fa04-4e4c-926a-0e61f138306e&select=id,status,price_total,contract_unit_cents,contract_qty,amount_paid_cents,stripe_checkout_session_id');

  // reproduce off-platform mint with a FRESH product/order
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final wBefore = await ctx.select(
    'wallets',
    service: true,
    filter: 'id=eq.${ctx.sellerId}',
    select: 'balance',
  );
  out['repro_wallet_before'] = wBefore.json;

  final prod = await ctx.rest('POST', '/rest/v1/products', jwt: ctx.sellerJwt, body: {
    'seller_id': ctx.sellerId,
    'title': 'CEGA1243 mint repro $stamp',
    'price': 8.00,
    'quantity': 1,
    'list_on_marketplace': true,
  });
  String? pid;
  if (prod.json is List && (prod.json as List).isNotEmpty) {
    pid = ((prod.json as List).first as Map)['id']?.toString();
  }
  out['repro_product'] = {'status': prod.status, 'id': pid};

  String? oid;
  if (pid != null) {
    final o = await ctx.rest('POST', '/rest/v1/orders', jwt: ctx.buyerJwt, body: {
      'buyer_id': ctx.buyerId,
      'seller_id': ctx.sellerId,
      'product_id': pid,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'MB WAY',
      'shipping_method': 'hand',
    });
    if (o.json is List && (o.json as List).isNotEmpty) {
      oid = ((o.json as List).first as Map)['id']?.toString();
    }
    out['repro_order_insert'] = {'status': o.status, 'id': oid, 'body': o.snippet};
  }
  if (oid != null) {
    final a = await ctx.rest('PATCH', '/rest/v1/orders?id=eq.$oid',
        jwt: ctx.sellerJwt, body: {'status': 'reservado'});
    final b = await ctx.rest('PATCH', '/rest/v1/orders?id=eq.$oid',
        jwt: ctx.sellerJwt, body: {'status': 'pago'});
    final c = await ctx.rest('PATCH', '/rest/v1/orders?id=eq.$oid',
        jwt: ctx.sellerJwt, body: {'status': 'enviado'});
    final d = await ctx.rest('PATCH', '/rest/v1/orders?id=eq.$oid',
        jwt: ctx.buyerJwt, body: {'status': 'concluido'});
    out['repro_fsm'] = {
      'reservado': a.snippet,
      'pago': b.status,
      'enviado': c.status,
      'concluido': d.status,
    };
    final ord = await ctx.select('orders', service: true, filter: 'id=eq.$oid',
        select: 'id,status,payment_method,price_total,amount_paid_cents,wallet_release_processed_at');
    out['repro_order_before_release'] = ord.json;

    final rel = await ctx.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oid},
      jwt: ctx.buyerJwt,
    );
    out['repro_release'] = {'status': rel.status, 'body': rel.json};

    final wAfter = await ctx.select(
      'wallets',
      service: true,
      filter: 'id=eq.${ctx.sellerId}',
      select: 'balance',
    );
    out['repro_wallet_after'] = wAfter.json;

    final tx = await ctx.select(
      'wallet_transactions',
      service: true,
      filter: 'order_id=eq.$oid',
      select: 'id,wallet_id,amount,type,description,created_at',
    );
    out['repro_tx'] = tx.json;
  }

  // payout: observe latest rows vs stripe transfer
  // try a unique amount to avoid resume-by-amount
  final uniq = 123; // 1.23 EUR
  final w0 = await ctx.select('wallets', service: true, filter: 'id=eq.${ctx.sellerId}', select: 'balance');
  final pay = await ctx.edge('create-connect-account', {
    'amount': uniq,
    'idempotency_key': 'cega-uniq-$stamp-payout1',
  }, jwt: ctx.sellerJwt);
  final pay2 = await ctx.edge('create-connect-account', {
    'amount': uniq,
    'idempotency_key': 'cega-uniq-$stamp-payout2',
  }, jwt: ctx.sellerJwt);
  final w1 = await ctx.select('wallets', service: true, filter: 'id=eq.${ctx.sellerId}', select: 'balance');
  out['payout_uniq'] = {
    'before': w0.json,
    'p1': {'status': pay.status, 'body': pay.snippet},
    'p2': {'status': pay2.status, 'body': pay2.snippet},
    'after': w1.json,
  };

  await writeOut('pass3b_verify.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'wallet_before_repro': out['repro_wallet_before'],
    'release': out['repro_release'],
    'wallet_after_repro': out['repro_wallet_after'],
    'tx': out['repro_tx'],
    'payout_uniq': out['payout_uniq'],
  }));
}
