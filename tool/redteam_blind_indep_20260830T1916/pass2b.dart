/// PASS 2b — URL completa Stripe + freeze fresh + (após 4242) estado final.
import 'dart:convert';
import 'dart:io';

import '_rti4.dart';

Future<void> main() async {
  final c = await boot();
  const unlistPid = '8cc95520-3bff-4093-92b9-c556fe99dba7';
  const oidLive = 'edbabf9f-eabf-43b2-9582-fbe7269c8c85';
  const oidRaffle = '8450a8c0-5021-4ed3-9dfa-a0e6bd0db119';

  final dir = Directory('tool/redteam_blind_indep_20260830T1916/out');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  Future<Map<String, dynamic>?> row(String table, String id, String cols) async {
    final r = await rest(
      c.url,
      'GET',
      '$table?id=eq.$id&select=$cols',
      headers: c.svcH,
    );
    final maps = asMaps(decode(r));
    return maps.isEmpty ? null : maps.first;
  }

  final mode = Platform.environment['RTI4_MODE'] ?? 'url';

  if (mode == 'url') {
    final ck = await edge(c.url, 'create-payment-intent', {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': unlistPid,
      'order_id': oidLive,
      'quantity': 1,
      'currency': 'eur',
      'shipping_method': 'carrier',
    }, headers: c.buyerH);
    File('${dir.path}/checkout_unlist_live.json').writeAsStringSync(ck.body);
    stderr.writeln('wrote checkout body status=${ck.statusCode} len=${ck.body.length}');

    // Fresh freeze
    final freshEmail =
        'rti4.f2.${DateTime.now().toUtc().millisecondsSinceEpoch}@fleaber.invalid';
    final fid = await c.admin.createAdminUser(
      email: freshEmail,
      password: 'TesteTeste1!',
      userMetadata: {'full_name': 'RTI4 f2'},
    );
    final fj = await c.admin.signIn(email: freshEmail, password: 'TesteTeste1!');
    await rest(
      c.url,
      'PATCH',
      'products?id=eq.$unlistPid',
      headers: c.sellerH,
      body: {'list_on_marketplace': true},
    );
    final avail = await rpc(
      c.url,
      'batata_product_checkout_available',
      {
        'p_product_id': unlistPid,
        'p_exclude_order_id': null,
        'p_need_qty': 1,
      },
      headers: c.svcH,
    );
    final freshHold = await rest(c.url, 'POST', 'orders',
        headers: hJwt(c.anon, fj),
        body: {
          'buyer_id': fid,
          'seller_id': c.sellerId,
          'product_id': unlistPid,
          'quantity': 1,
          'price_total': 9.5,
          'status': 'reserva_pendente',
          'payment_method': 'pagamento na app',
          'shipping_method': 'carrier',
        });
    rec(
      surface: 'freeze',
      attack: 'fresh hold after re-list',
      identity: 'fresh',
      result: '${briefBody(freshHold)} avail=${briefBody(avail)}',
    );
    await rest(
      c.url,
      'PATCH',
      'products?id=eq.$unlistPid',
      headers: c.sellerH,
      body: {'list_on_marketplace': false},
    );
    await dumpJson('pass2b_url', {
      'fresh_hold': briefBody(freshHold),
      'avail': decode(avail),
      'raffle': await row('orders', oidRaffle,
          'id,status,live_id,live_raffle_id,quantity'),
      'live_ord': await row('orders', oidLive,
          'id,status,live_id,stripe_checkout_session_id,amount_paid_cents'),
      'prod': await row('products', unlistPid,
          'id,quantity,is_sold,list_on_marketplace'),
      'matrix': matrix,
    });
    return;
  }

  // mode=afterpay
  final liveOrd = await row('orders', oidLive,
      'id,status,live_id,product_id,stripe_checkout_session_id,stripe_payment_intent_id,amount_paid_cents,price_total,stock_units_applied,wallet_release_processed_at');
  final prod = await row('products', unlistPid,
      'id,quantity,is_sold,list_on_marketplace,price');
  final hub = await rest(
    c.url,
    'GET',
    'hub_products_public?id=eq.$unlistPid&select=id,title,is_sold',
    headers: c.anonH,
  );
  final w = await row('wallets', c.sellerId, 'id,balance');
  rec(
    surface: 'afterpay',
    attack: 'order after 4242',
    identity: 'observe',
    result: jsonEncode(liveOrd),
  );
  rec(
    surface: 'afterpay',
    attack: 'product after 4242',
    identity: 'observe',
    result: jsonEncode(prod),
  );
  rec(
    surface: 'afterpay',
    attack: 'hub after 4242',
    identity: 'anon',
    result: briefBody(hub),
  );
  rec(
    surface: 'afterpay',
    attack: 'wallet after 4242',
    identity: 'observe',
    result: jsonEncode(w),
  );

  final paid = (liveOrd?['amount_paid_cents'] ?? 0) as num;
  final status = '${liveOrd?['status']}';
  if (paid > 0 || status == 'pago') {
    finding(
      id: 'RTI4-P1-UNLIST-LIVE-CAPTURE',
      severity: 'P1',
      title: 'Captura Stripe TEST em produto unlist via live_id de directo ended',
      actor: 'buyer JWT + Edge + 4242',
      pre: 'list_on_marketplace=false; lives.status=ended; Hub vazio',
      repro:
          'POST orders live_id=<ended> → create-payment-intent → pagar 4242',
      impact:
          'CAPTURA real de montra morta. Hub vazio. Stock/contrato selado.',
      evidence: {
        'order': liveOrd,
        'product': prod,
        'wallet': w,
        'hub': briefBody(hub),
      },
    );
  } else {
    gaps.add('4242 ainda sem amount_paid_cents/status pago');
  }

  await dumpJson('pass2b_after', {
    'findings': findings,
    'matrix': matrix,
    'gaps': gaps,
  });
}
