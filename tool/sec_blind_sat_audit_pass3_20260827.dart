// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

typedef Json = Map<String, dynamic>;

Future<Json> req(String m, String url, Map<String, String> h, [Object? body]) async {
  final uri = Uri.parse(url);
  final enc = body == null ? null : jsonEncode(body);
  late http.Response r;
  r = switch (m) {
    'GET' => await http.get(uri, headers: h),
    'POST' => await http.post(uri, headers: h, body: enc),
    'PATCH' => await http.patch(uri, headers: h, body: enc),
    'DELETE' => await http.delete(uri, headers: h),
    _ => throw ArgumentError(m),
  };
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p};
}

Json? row(Object? b) {
  if (b is List && b.isNotEmpty && b.first is Map) {
    return Map<String, dynamic>.from(b.first as Map);
  }
  if (b is Map) return Map<String, dynamic>.from(b);
  return null;
}

void main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  Map<String, String> h(String t) => {
        'apikey': anon,
        'Authorization': 'Bearer $t',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  final BH = h(buyerTok);
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final out = <String, dynamic>{};
  void log(String k, Object v) {
    out[k] = v;
    stdout.writeln('$k: $v');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final pids = <String>[];
  final oids = <String>[];
  try {
    final p1 = await sb.insert('products', {
      'seller_id': sellerId,
      'title': 'SAT-P3A $stamp',
      'price': 40.0,
      'quantity': 4,
      'list_on_marketplace': false,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    pids.add(p1['id'].toString());
    final o1 = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': p1['id'],
      'quantity': 1,
      'price_total': 40,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    });
    final r1 = row(o1['body']);
    if (r1 != null) oids.add(r1['id'].toString());
    log('fresh_order_status', r1?['status']);
    final rev = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': r1?['id'],
      'stars': 5,
      'comment': 'unpaid-review',
      'author_role': 'comprador',
    });
    log('review_on_reserva', {'http': rev['http'], 'body': rev['body']});

    final p2 = await sb.insert('products', {
      'seller_id': sellerId,
      'title': 'SAT-P3B $stamp',
      'price': 25.0,
      'quantity': 3,
      'list_on_marketplace': false,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    pids.add(p2['id'].toString());
    final oa = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': p1['id'],
      'quantity': 1,
      'price_total': 40,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    final ob = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': p2['id'],
      'quantity': 1,
      'price_total': 1,
      'status': 'reserva_pendente',
      'payment_method': 'proposta aceite',
      'shipping_method': 'entrega em mão',
    });
    final ra = row(oa['body']);
    final rb = row(ob['body']);
    if (ra != null) oids.add(ra['id'].toString());
    if (rb != null) oids.add(rb['id'].toString());
    log('bag_lines', {
      'a_cuc': ra?['contract_unit_cents'],
      'b_cuc': rb?['contract_unit_cents'],
      'b_pm': rb?['payment_method'],
    });
    final bag = await req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      {
        'apikey': anon,
        'Authorization': 'Bearer $buyerTok',
        'Content-Type': 'application/json',
      },
      {
        'buyer_id': buyerId,
        'bag_checkout': true,
        'bag_lines': [
          {'order_id': ra?['id']},
          {'order_id': rb?['id']},
        ],
        'shipping_method': 'entrega em mão',
      },
    );
    log('bag_checkout', bag['body']);

    final livesSafe = await req(
      'GET',
      '$url/rest/v1/lives?select=id,status,title,mux_playback_id,seller_id&limit=3',
      BH,
    );
    log('lives_safe_cols', {'http': livesSafe['http'], 'n': livesSafe['body'] is List ? (livesSafe['body'] as List).length : livesSafe['body']});

    final prodUp = await req(
      'PATCH',
      '$url/rest/v1/products?id=eq.${p1['id']}',
      BH,
      {'price': 1.0},
    );
    log('buyer_patch_seller_product', {'http': prodUp['http'], 'body': prodUp['body']});

    final handle = await req(
      'POST',
      '$url/rest/v1/rpc/batata_claim_profile_handle',
      BH,
      {'p_handle': 'sathostile$stamp'},
    );
    log('claim_handle_unverified', {'http': handle['http'], 'body': handle['body']});
  } finally {
    for (final oid in oids) {
      await http.delete(Uri.parse('$url/rest/v1/reviews?order_id=eq.$oid'), headers: SVC);
      await http.delete(Uri.parse('$url/rest/v1/orders?id=eq.$oid'), headers: SVC);
    }
    for (final pid in pids) {
      await http.delete(Uri.parse('$url/rest/v1/chats?product_id=eq.$pid'), headers: SVC);
      await http.delete(Uri.parse('$url/rest/v1/orders?product_id=eq.$pid'), headers: SVC);
      await http.delete(Uri.parse('$url/rest/v1/products?id=eq.$pid'), headers: SVC);
    }
  }
  File('tool/reports/SAT_BLIND_PASS3_20260827.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('WROTE pass3');
}
