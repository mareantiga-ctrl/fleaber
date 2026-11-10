// ignore_for_file: avoid_print
/// Follow-up 2: bag refund cap, settle retry, live_item stock, shipping 350.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

final out = <String, dynamic>{};
void rec(String id, Object? v) {
  out[id] = v;
  final s = jsonEncode(v);
  print('$id: ${s.length > 360 ? s.substring(0, 360) : s}');
}

Future<Map<String, dynamic>> req(
  String method,
  String url,
  Map<String, String> headers, [
  Object? body,
]) async {
  final uri = Uri.parse(url);
  late http.Response r;
  final b = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'GET':
      r = await http.get(uri, headers: headers);
      break;
    case 'POST':
      r = await http.post(uri, headers: headers, body: b);
      break;
    case 'DELETE':
      r = await http.delete(uri, headers: headers);
      break;
    default:
      throw StateError(method);
  }
  Object? parsed;
  try {
    parsed = jsonDecode(r.body);
  } catch (_) {
    parsed = r.body;
  }
  return {'ok': r.statusCode >= 200 && r.statusCode < 300, 'status': r.statusCode, 'body': parsed};
}

Map<String, dynamic>? rowMap(Object? body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
  return null;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY').trim();
  final e2e = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final c = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerJwt = await c.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await c.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerJwt',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SH = {
    'apikey': anon,
    'Authorization': 'Bearer $sellerJwt',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final e2eHdr = {
    ...SVC,
    if (e2e.length >= 16) 'x-fleaber-e2e-secret': e2e,
  };

  rec(
    'live_item_svc',
    await req(
      'GET',
      '$url/rest/v1/live_items?select=id,live_id,quantity,available_qty,stock,product_id,title&id=eq.ffb7b7e5-3007-44c7-b59d-44f99f36cb7f',
      SVC,
    ),
  );

  rec(
    'wallets_before_bag',
    await req(
      'GET',
      '$url/rest/v1/wallets?select=id,balance&id=in.($buyerId,$sellerId)',
      SVC,
    ),
  );

  final bag = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    e2eHdr,
    {
      'probe': 'setup_paid_bag',
      'buyer_id': buyerId,
      'seller_id': sellerId,
    },
  );
  rec('bag2b', {
    'status': bag['status'],
    'ok': bag['body'] is Map ? (bag['body'] as Map)['ok'] : null,
    'pi': bag['body'] is Map ? (bag['body'] as Map)['payment_intent_id'] : null,
    'pi_amt': bag['body'] is Map ? (bag['body'] as Map)['pi_amount_cents'] : null,
    'paid_a': bag['body'] is Map ? (bag['body'] as Map)['paid_a'] : null,
    'paid_b': bag['body'] is Map ? (bag['body'] as Map)['paid_b'] : null,
    'order_a': bag['body'] is Map ? (bag['body'] as Map)['order_a_id'] : null,
    'order_b': bag['body'] is Map ? (bag['body'] as Map)['order_b_id'] : null,
    'product_a': bag['body'] is Map ? (bag['body'] as Map)['product_a_id'] : null,
    'product_b': bag['body'] is Map ? (bag['body'] as Map)['product_b_id'] : null,
    'checks': bag['body'] is Map ? (bag['body'] as Map)['checks'] : null,
  });
  final bm = bag['body'] is Map ? bag['body'] as Map : {};
  final oa = bm['order_a_id']?.toString();
  final ob = bm['order_b_id']?.toString();
  final pi = bm['payment_intent_id']?.toString();
  final pa = bm['product_a_id']?.toString();
  final pb = bm['product_b_id']?.toString();

  if (oa != null && ob != null && pi != null) {
    // retry settle with Edge-local secret via... dart service_role only
    rec(
      'retry_settle_auth_only',
      await req(
        'POST',
        '$url/functions/v1/create-payment-intent?fase2_e2e_settle=1',
        {
          'Authorization': 'Bearer $svc',
          'Content-Type': 'application/json',
        },
        {
          'bag_checkout': true,
          'bag_lines': [
            {'order_id': oa, 'product_id': pa},
            {'order_id': ob, 'product_id': pb},
          ],
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'payment_intent_id': pi,
        },
      ),
    );
    rec(
      'retry_settle_svc_headers',
      await req(
        'POST',
        '$url/functions/v1/create-payment-intent?fase2_e2e_settle=1',
        SVC,
        {
          'bag_checkout': true,
          'bag_lines': [
            {'order_id': oa, 'product_id': pa},
            {'order_id': ob, 'product_id': pb},
          ],
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'payment_intent_id': pi,
        },
      ),
    );

    rec(
      'orders_before_refund',
      await req(
        'GET',
        '$url/rest/v1/orders?select=id,status,price_total,amount_paid_cents,stripe_refund_id,stripe_payment_intent_id&id=in.($oa,$ob)',
        SVC,
      ),
    );

    rec(
      'refund_line_a_seller',
      await req('POST', '$url/functions/v1/refund-order', SH, {
        'order_id': oa,
      }),
    );

    rec(
      'orders_after_refund_a',
      await req(
        'GET',
        '$url/rest/v1/orders?select=id,status,price_total,amount_paid_cents,stripe_refund_id,stripe_refunded_at&id=in.($oa,$ob)',
        SVC,
      ),
    );

    rec(
      'refund_line_a_again',
      await req('POST', '$url/functions/v1/refund-order', SH, {
        'order_id': oa,
      }),
    );
  }

  rec(
    'wallets_after_bag',
    await req(
      'GET',
      '$url/rest/v1/wallets?select=id,balance&id=in.($buyerId,$sellerId)',
      SVC,
    ),
  );

  // 3-line JWT + CPI rounding set 1.00 / 1.00 / 1.01
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final prices = [1.00, 1.00, 1.01];
  final pids = <String>[];
  final oids = <String>[];
  for (var i = 0; i < 3; i++) {
    final p = await req('POST', '$url/rest/v1/products', SH, {
      'seller_id': sellerId,
      'title': 'REAUDIT27 r3 ${i + 1} $stamp',
      'price': prices[i],
      'quantity': 3,
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
    });
    final pid = rowMap(p['body'])?['id']?.toString();
    if (pid == null) continue;
    pids.add(pid);
    final o = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': prices[i],
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    });
    final id = rowMap(o['body'])?['id']?.toString();
    if (id != null) oids.add(id);
  }
  rec('r3_ids', {'products': pids, 'orders': oids});
  if (oids.length == 3) {
    final lines = [
      for (var i = 0; i < 3; i++) {'order_id': oids[i], 'product_id': pids[i]},
    ];
    final cpi = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oids.first,
      'bag_checkout': true,
      'bag_lines': lines,
      'shipping_method': 'hand',
    });
    rec('r3_cpi', {
      'status': cpi['status'],
      'amount': cpi['body'] is Map ? (cpi['body'] as Map)['server_amount_cents'] : null,
      'err': cpi['body'] is Map ? (cpi['body'] as Map)['error'] : null,
    });
    rec(
      'r3_price_totals',
      await req(
        'GET',
        '$url/rest/v1/orders?select=id,price_total,amount_paid_cents,status&id=in.(${oids.join(',')})',
        BH,
      ),
    );
  }

  // shipping 350 with garbage
  final prod = await req('POST', '$url/rest/v1/products', SH, {
    'seller_id': sellerId,
    'title': 'REAUDIT27 ship350',
    'price': 6.66,
    'quantity': 2,
    'list_on_marketplace': false,
    'available_for_live': false,
    'is_sold': false,
  });
  final prodId = rowMap(prod['body'])?['id']?.toString();
  if (prodId != null) {
    final ord = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': prodId,
      'quantity': 1,
      'price_total': 6.66,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    });
    final oid = rowMap(ord['body'])?['id']?.toString();
    if (oid != null) {
      rec(
        'ship_garbage_plus_350',
        await req('POST', '$url/functions/v1/create-payment-intent', BH, {
          'buyer_id': buyerId,
          'order_id': oid,
          'shipping_method': 'whatever',
          'shipping': 350,
        }),
      );
      rec(
        'ship_garbage_plus_1',
        await req('POST', '$url/functions/v1/create-payment-intent', BH, {
          'buyer_id': buyerId,
          'order_id': oid,
          'shipping_method': 'whatever',
          'shipping': 1,
        }),
      );
    }
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$prodId', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$prodId', SVC);
  }

  if (pa != null || pb != null) {
    rec(
      'bag2b_cleanup',
      await req(
        'POST',
        '$url/functions/v1/sec-fase2-e2e-oversell',
        e2eHdr,
        {
          'probe': 'cleanup_bag_fixture',
          'product_a_id': pa,
          'product_b_id': pb,
        },
      ),
    );
  }
  for (final id in pids) {
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$id', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$id', SVC);
  }
  await req(
    'DELETE',
    '$url/rest/v1/live_reservation_requests?buyer_id=eq.$buyerId&source=eq.fleaber_live&status=eq.pending',
    SVC,
  );
  await req(
    'DELETE',
    '$url/rest/v1/chat_messages?text=eq.REAUDIT27%20insert%20spoof',
    SVC,
  );

  final path = 'tool/reports/REAUDITORIA_CEGA_2026_08_27_FOLLOWUP2.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('WROTE $path');
}
