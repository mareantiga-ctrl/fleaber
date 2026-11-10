// dart run tool/redteam_blind_b_20260829T1755_pass4.dart
// Cycle 4: raffle / dispute / storage / refund / waitlist — other perspective
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

const stamp = '20260829T1755';
const stagingRef = 'fxdknzrqjenzqcvnwqqq';
typedef Json = Map<String, dynamic>;
final findings = <Json>[];
final probes = <Json>[];

Json snap(http.Response r, {int max = 700}) {
  var b = r.body;
  if (b.length > max) b = '${b.substring(0, max)}…';
  return {'status': r.statusCode, 'body': b};
}

Future<http.Response> rest(
  String url,
  String key,
  String bearer, {
  String method = 'GET',
  required String path,
  Object? body,
}) {
  final h = {
    'apikey': key,
    'Authorization': 'Bearer $bearer',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final uri = Uri.parse('$url$path');
  if (method == 'POST') return http.post(uri, headers: h, body: jsonEncode(body));
  if (method == 'PATCH') return http.patch(uri, headers: h, body: jsonEncode(body));
  return http.get(uri, headers: h);
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final client = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  Future<void> hit(String id, Future<http.Response> f) async {
    probes.add({'id': id, ...snap(await f)});
  }

  await hit(
    'p4.raffles',
    rest(url, anon, buyerJwt, path: '/rest/v1/live_raffles?select=*&limit=5'),
  );
  await hit(
    'p4.winners',
    rest(url, anon, buyerJwt, path: '/rest/v1/live_raffle_winners?select=*&limit=5'),
  );
  await hit(
    'p4.entries',
    rest(url, anon, buyerJwt, path: '/rest/v1/live_raffle_entries?select=*&limit=5'),
  );
  await hit(
    'p4.disputes_all',
    rest(url, anon, buyerJwt, path: '/rest/v1/order_disputes?select=*&limit=8'),
  );
  await hit(
    'p4.dispute_insert',
    rest(
      url,
      anon,
      buyerJwt,
      method: 'POST',
      path: '/rest/v1/order_disputes',
      body: {
        'order_id': '00000000-0000-0000-0000-000000000001',
        'buyer_id': sellerId,
        'reason': 'outro',
        'description': 'p4',
      },
    ),
  );
  await hit(
    'p4.refund_buyer',
    http.post(
      Uri.parse('$url/functions/v1/refund-order'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerJwt',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'order_id': '00000000-0000-0000-0000-000000000001'}),
    ),
  );
  await hit(
    'p4.waitlist',
    rest(
      url,
      anon,
      buyerJwt,
      path: '/rest/v1/live_reservation_requests?select=*&limit=5',
    ),
  );
  await hit(
    'p4.storage_proofs',
    http.post(
      Uri.parse('$url/storage/v1/object/list/chat_media'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerJwt',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'prefix': 'order_proofs/', 'limit': 20}),
    ),
  );
  await hit(
    'p4.storage_disputes',
    http.post(
      Uri.parse('$url/storage/v1/object/list/chat_media'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerJwt',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'prefix': 'order_disputes/', 'limit': 20}),
    ),
  );
  await hit(
    'p4.follows',
    rest(url, anon, buyerJwt, path: '/rest/v1/follows?select=*&limit=10'),
  );
  await hit(
    'p4.hub_reviews',
    rest(url, anon, buyerJwt, path: '/rest/v1/hub_reviews_public?select=*&limit=5'),
  );

  // Classify only if clearly new P0/P1 (not offer/price_total class)
  for (final p in probes) {
    final id = p['id'];
    final st = p['status'];
    final body = '${p['body'] ?? ''}';
    if (id == 'p4.winners' && st == 200 && body.contains('"user_id"') && body.contains('"id"')) {
      findings.add({
        'id': 'RTB-B-1755-P2-RAFFLE-WINNERS',
        'title': 'Buyer lê live_raffle_winners globais',
        'severity': 'P2',
        'result': p,
      });
    }
    if (id == 'p4.storage_proofs' && st == 200 && body.length > 5 && body != '[]') {
      findings.add({
        'id': 'RTB-B-1755-P1-STORAGE-PROOFS',
        'title': 'Listagem order_proofs',
        'severity': 'P1',
        'result': p,
      });
    }
  }

  File('tool/redteam_blind_b_${stamp}_pass4.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'pass': 4,
      'frozen_at': DateTime.now().toUtc().toIso8601String(),
      'findings': findings,
      'probes': probes,
    }),
  );
  stdout.writeln('pass4 findings=${findings.length}');
}
