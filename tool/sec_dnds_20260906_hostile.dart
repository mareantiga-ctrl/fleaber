// ignore_for_file: avoid_print
/// POS_DHDM DN–DS — dart run tool/sec_dnds_20260906_hostile.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
]) async {
  final client = http.Client();
  try {
    late http.Response r;
    final uri = Uri.parse(u);
    if (method == 'POST') {
      r = await client.post(uri,
          headers: h, body: body == null ? null : jsonEncode(body));
    } else if (method == 'GET') {
      r = await client.get(uri, headers: h);
    } else {
      r = await client.patch(uri,
          headers: h, body: body == null ? null : jsonEncode(body));
    }
    dynamic p;
    try {
      p = r.body.isEmpty ? null : jsonDecode(r.body);
    } catch (_) {
      p = r.body;
    }
    return {'http': r.statusCode, 'body': p, 'raw': r.body};
  } finally {
    client.close();
  }
}

void pass(String id) => print('PASS $id');
void fail(String id, String why) {
  print('FAIL $id: $why');
  exitCode = 1;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final buyerId = await sb.userIdForAccessToken(buyerTok);
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final stamp = DateTime.now().millisecondsSinceEpoch;

  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SH = {
    'apikey': anon,
    'Authorization': 'Bearer $sellerTok',
    'Content-Type': 'application/json',
  };
  final ANON = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
  };

  // Revoke RPC
  final rev = await req(
    'POST',
    '$url/rest/v1/rpc/batata_revoke_private_object',
    {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
      'Content-Type': 'application/json',
    },
    {'p_path': 'order_disputes/$buyerId/dnds-$stamp.png'},
  );
  rev['body'] == true
      ? pass('dq-revoke')
      : fail('dq-revoke', '${rev['raw']}');

  // Raffle seal helper exists
  final sealMissing = await req(
    'POST',
    '$url/rest/v1/rpc/batata_raffle_seal_prize_stock',
    SVC,
    {'p_raffle_id': '00000000-0000-0000-0000-000000000001'},
  );
  final sealBody = sealMissing['body'];
  (sealBody is Map && sealBody['ok'] == false)
      ? pass('ds-seal-rpc')
      : fail('ds-seal-rpc', '${sealMissing['raw']}');

  // Hub sellable still works
  await req('POST', '$url/rest/v1/rpc/batata_publish_hub', SH, {
    'p_publish': true,
  });
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'dnds-$stamp',
    'price': 3.0,
    'quantity': 1,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  String? pid;
  if (prod['body'] is List && (prod['body'] as List).isNotEmpty) {
    pid = '${(prod['body'] as List).first['id']}';
  }
  if (pid != null) {
    final hub = await req(
      'GET',
      '$url/rest/v1/hub_products_public?id=eq.$pid&select=id',
      ANON,
    );
    final n = hub['body'] is List ? (hub['body'] as List).length : -1;
    n == 1 ? pass('hub-list') : fail('hub-list', 'n=$n');
    await req('PATCH', '$url/rest/v1/products?id=eq.$pid', SVC, {
      'list_on_marketplace': false,
      'is_sold': true,
    });
  } else {
    fail('prod', '${prod['raw']}');
  }

  if (exitCode == 0) print('ALL PASS');
}
