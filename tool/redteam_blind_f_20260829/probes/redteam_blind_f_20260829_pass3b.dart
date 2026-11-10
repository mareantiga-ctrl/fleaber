/// PASS 3b — duplicate review, raffle draw, mark sold, observe dual-pay state.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stagingRef = 'fxdknzrqjenzqcvnwqqq';
const outDir = 'tool/redteam_blind_f_20260829';

Future<http.Response> rest(
  LiveOpsStagingClient c, {
  required String method,
  required String path,
  String? token,
  bool service = false,
  Object? body,
}) {
  final headers = <String, String>{
    'apikey': service ? c.serviceRoleKey : c.anonKey,
    'Authorization':
        'Bearer ${service ? c.serviceRoleKey : (token ?? c.anonKey)}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final uri = Uri.parse('${c.url}$path');
  if (method == 'GET') return http.get(uri, headers: headers);
  if (method == 'POST') {
    return http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
  }
  if (method == 'PATCH') {
    return http.patch(uri, headers: headers, body: jsonEncode(body ?? {}));
  }
  return http.delete(uri, headers: headers);
}

Future<http.Response> rpc(
  LiveOpsStagingClient c,
  String fn,
  Map<String, dynamic> p, {
  required String token,
}) {
  return rest(c, method: 'POST', path: '/rest/v1/rpc/$fn', token: token, body: p);
}

List<Map<String, dynamic>> asList(String body) {
  try {
    final d = jsonDecode(body);
    if (d is List) {
      return [for (final e in d) if (e is Map) Map<String, dynamic>.from(e)];
    }
  } catch (_) {}
  return [];
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final c = LiveOpsStagingClient(
    url: url,
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );

  final out = <String, dynamic>{};

  // Cleanup leftover reviews from pass3 on that order
  await rest(
    c,
    method: 'DELETE',
    path:
        '/rest/v1/reviews?order_id=eq.bb56dbbf-589f-4a5b-ba2d-81526e87cc33&comment=like.*rtf3*',
    service: true,
  );

  final r1 = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/reviews',
    token: buyerTok,
    body: {
      'target_id': sellerId,
      'buyer_id': buyerId,
      'stars': 5,
      'comment': 'rtf3b first',
      'target_type': 'seller',
      'author_role': 'comprador',
      'order_id': 'bb56dbbf-589f-4a5b-ba2d-81526e87cc33',
    },
  );
  final r2 = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/reviews',
    token: buyerTok,
    body: {
      'target_id': sellerId,
      'buyer_id': buyerId,
      'stars': 1,
      'comment': 'rtf3b dup no delete',
      'target_type': 'seller',
      'author_role': 'comprador',
      'order_id': 'bb56dbbf-589f-4a5b-ba2d-81526e87cc33',
    },
  );
  final listed = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/reviews?order_id=eq.bb56dbbf-589f-4a5b-ba2d-81526e87cc33&select=id,stars,comment,author_role,buyer_id',
    service: true,
  );
  out['review_first'] = {'http': r1.statusCode, 'body': r1.body};
  out['review_dup'] = {'http': r2.statusCode, 'body': r2.body};
  out['reviews_on_order'] = listed.body;

  // Real raffles
  final raffles = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/live_raffles?select=id,status,seller_id,live_id&limit=10',
    service: true,
  );
  out['raffles'] = raffles.body;
  final rf = asList(raffles.body);
  if (rf.isNotEmpty) {
    final rid = rf.first['id'];
    final draw = await rpc(
      c,
      'batata_draw_live_raffle_winners',
      {'p_raffle_id': rid},
      token: buyerTok,
    );
    out['draw_as_buyer'] = {'http': draw.statusCode, 'body': draw.body, 'raffle': rid};
    final join = await rpc(
      c,
      'batata_join_live_raffle',
      {'p_raffle_id': rid},
      token: buyerTok,
    );
    out['join_as_buyer'] = {'http': join.statusCode, 'body': join.body};
  }

  final items = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/live_items?select=id,status,live_id&limit=3',
    service: true,
  );
  final li = asList(items.body);
  if (li.isNotEmpty) {
    final mark = await rpc(
      c,
      'batata_mark_live_item_sold',
      {'p_live_item_id': li.first['id']},
      token: buyerTok,
    );
    out['mark_sold_as_buyer'] = {
      'http': mark.statusCode,
      'body': mark.body,
      'item': li.first['id'],
      'before': li.first,
    };
    final after = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/live_items?select=id,status&id=eq.${li.first['id']}',
      service: true,
    );
    out['mark_sold_after'] = after.body;
  }

  // Dual-pay observe
  const oa = 'b241022c-2883-42ed-828f-6e68415b72e5';
  const ob = '10c41bc5-fb04-43c0-9810-ef992077bef8';
  const pid = '7c7de7b2-e6d0-4875-8477-471a109b169d';
  final ords = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/orders?id=in.($oa,$ob)&select=id,status,stock_units_applied,stripe_payment_intent_id,amount_paid_cents,stripe_refund_id',
    service: true,
  );
  final prod = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/products?id=eq.$pid&select=id,quantity,is_sold',
    service: true,
  );
  out['dual_pay_orders_before_browser'] = ords.body;
  out['dual_pay_product_before_browser'] = prod.body;

  // credit wallet with guessed param names
  for (final params in [
    {'p_wallet_id': buyerId, 'p_amount': 1, 'p_key': 'x'},
    {'p_user_id': buyerId, 'p_amount_cents': 1, 'p_idempotency_key': 'x'},
    {'p_uid': buyerId, 'p_eur': 1},
  ]) {
    final r = await rpc(c, 'batata_credit_wallet_once', params, token: buyerTok);
    out['credit_${params.keys.join("_")}'] = '${r.statusCode} ${r.body}';
  }

  File('$outDir/pass3b_raw.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(out),
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
