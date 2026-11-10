// Pass 5 — checkout-eligible statuses + poisoned contract → Session amount.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stamp = '20260830T1443';
const tag = 'RTI5-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

final attacks = <Map<String, dynamic>>[];

void logA(String k, Object v) {
  attacks.add({'k': k, 'v': v});
  stdout.writeln('$k :: $v');
}

String clip(String s, [int n = 360]) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= n ? t : '${t.substring(0, n)}…';
}

void main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) exit(2);
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final admin = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerTok = await admin.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );

  Map<String, String> hUser(String tok) => {
        'apikey': anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  Map<String, String> hSvc() => {
        'apikey': svc,
        'Authorization': 'Bearer $svc',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Future<http.Response> post(String path, Object body, {String? tok}) {
    return http.post(
      Uri.parse('$url$path'),
      headers: tok == null ? hSvc() : hUser(tok),
      body: jsonEncode(body),
    );
  }

  Future<Map<String, dynamic>?> svcOrder(String id) async {
    final r = await http.get(
      Uri.parse('$url/rest/v1/orders?id=eq.$id&select=*&limit=1'),
      headers: hSvc(),
    );
    final d = jsonDecode(r.body);
    if (d is List && d.isNotEmpty) return Map<String, dynamic>.from(d.first as Map);
    return null;
  }

  Future<void> cancel(String id) async {
    try {
      await admin.patch('orders', 'id=eq.$id', {'status': 'cancelado'});
    } catch (_) {}
  }

  final prod = await admin.insert('products', {
    'seller_id': sellerId,
    'title': '$tag 31.00',
    'price': 31.00,
    'quantity': 8,
    'is_sold': false,
    'list_on_marketplace': true,
    'description': tag,
  });
  final pid = prod['id'].toString();

  Future<void> trial(String name, Map<String, dynamic> orderBody) async {
    final ins = await post('/rest/v1/orders', orderBody, tok: buyerTok);
    logA('${name}_insert', '${ins.statusCode} ${clip(ins.body, 220)}');
    String? oid;
    try {
      final d = jsonDecode(ins.body);
      if (d is List && d.isNotEmpty) oid = (d.first as Map)['id']?.toString();
    } catch (_) {}
    if (oid == null) return;
    final live = await svcOrder(oid);
    logA('${name}_sealed', {
      'id': oid,
      'status': live?['status'],
      'unit': live?['contract_unit_cents'],
      'qty': live?['contract_qty'],
      'price': live?['price_total'],
      'offer': live?['product_offer_id'],
      'pm': live?['payment_method'],
    });
    final chk = await post(
      '/functions/v1/create-payment-intent',
      {
        'order_id': oid,
        'buyer_id': buyerId,
        'amount': 1,
        'quantity': 99,
      },
      tok: buyerTok,
    );
    logA('${name}_checkout', '${chk.statusCode} ${clip(chk.body, 400)}');
    try {
      final cb = jsonDecode(chk.body);
      if (cb is Map) {
        logA('${name}_session', {
          'amount_total': cb['amount_total'],
          'session': cb['checkoutSessionId'],
          'error': cb['error'],
        });
      }
    } catch (_) {}
    await cancel(oid);
  }

  const statuses = [
    'reserva_pendente',
    'reservado',
    'aguarda_confirmacao',
    'aguarda_pagamento',
  ];

  for (final st in statuses) {
    await trial('proposta_$st', {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 0.50,
      'status': st,
      'payment_method': 'proposta',
    });
  }

  await trial('contract_cents_reserva', {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 1,
    'price_total': 0.01,
    'status': 'reserva_pendente',
    'payment_method': 'pagamento na app',
    'contract_unit_cents': 1,
    'contract_qty': 1,
  });

  await trial('seguro_low_price_reserva', {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 1,
    'price_total': 0.50,
    'status': 'reserva_pendente',
    'payment_method': 'pagamento na app',
  });

  await trial('proposta_qty3', {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 3,
    'price_total': 0.50,
    'status': 'reserva_pendente',
    'payment_method': 'Proposta aceite',
  });

  // PATCH pendente → reserva_pendente then checkout
  final insP = await post(
    '/rest/v1/orders',
    {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 0.50,
      'status': 'pendente',
      'payment_method': 'proposta',
    },
    tok: buyerTok,
  );
  String? oidP;
  try {
    final d = jsonDecode(insP.body);
    if (d is List && d.isNotEmpty) oidP = (d.first as Map)['id']?.toString();
  } catch (_) {}
  logA('patchpath_insert', '${insP.statusCode} oid=$oidP');
  if (oidP != null) {
    final p = await http.patch(
      Uri.parse('$url/rest/v1/orders?id=eq.$oidP'),
      headers: hUser(buyerTok),
      body: jsonEncode({'status': 'reserva_pendente'}),
    );
    logA('patchpath_patch', '${p.statusCode} ${clip(p.body, 180)}');
    final live = await svcOrder(oidP);
    logA('patchpath_status', live?['status']);
    final chk = await post(
      '/functions/v1/create-payment-intent',
      {'order_id': oidP, 'buyer_id': buyerId},
      tok: buyerTok,
    );
    logA('patchpath_checkout', '${chk.statusCode} ${clip(chk.body, 400)}');
    await cancel(oidP);
  }

  try {
    await admin.patch('products', 'id=eq.$pid', {
      'list_on_marketplace': false,
      'quantity': 0,
    });
  } catch (_) {}

  Directory('tool/redteam_indep_cega_20260830T1443').createSync(recursive: true);
  File('tool/redteam_indep_cega_20260830T1443/pass5.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({'stamp': stamp, 'attacks': attacks}),
  );
  stdout.writeln('PASS5 written');
}
