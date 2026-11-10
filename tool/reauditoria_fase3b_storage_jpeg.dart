// ignore_for_file: avoid_print
/// Storage follow-up: image/jpeg into fleaber_private + cross-user.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

/// Minimal JPEG (1x1).
final jpeg = Uint8List.fromList([
  255, 216, 255, 224, 0, 16, 74, 70, 73, 70, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0,
  255, 219, 0, 67, 0, 8, 6, 6, 7, 6, 5, 8, 7, 7, 7, 9, 9, 8, 10, 12, 20, 13,
  12, 11, 11, 12, 25, 18, 19, 15, 20, 29, 26, 31, 30, 29, 26, 28, 28, 32, 36,
  46, 39, 32, 34, 44, 35, 28, 28, 40, 55, 41, 44, 48, 49, 52, 52, 52, 31, 39,
  57, 61, 56, 50, 60, 46, 51, 52, 50, 255, 201, 0, 11, 8, 0, 1, 0, 1, 1, 1,
  17, 0, 255, 204, 0, 6, 0, 16, 16, 5, 255, 218, 0, 8, 1, 1, 0, 0, 63, 0,
  210, 207, 32, 255, 217,
]);

void main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final client = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: 'unused',
  );
  final buyerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  Future<void> put(String id, String bucketPath, String jwt) async {
    final r = await http.post(
      Uri.parse('$url/storage/v1/object/$bucketPath'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'image/jpeg',
        'x-upsert': 'true',
      },
      body: jpeg,
    );
    print('R $id status=${r.statusCode} body=${r.body}');
  }

  await put(
    'F02J_CROSS_PRIVATE',
    'fleaber_private/order_proofs/$sellerId/reaudit_cross.jpg',
    buyerJwt,
  );
  await put(
    'F02J_OWN_PRIVATE',
    'fleaber_private/order_proofs/$buyerId/reaudit_own.jpg',
    buyerJwt,
  );
  await put(
    'F02J_OWN_DISPUTE',
    'fleaber_private/order_disputes/$buyerId/reaudit_d.jpg',
    buyerJwt,
  );

  final pub = await http.get(
    Uri.parse(
      '$url/storage/v1/object/public/fleaber_private/order_proofs/$buyerId/reaudit_own.jpg',
    ),
  );
  print('R F02J_ANON_PUBLIC_GET status=${pub.statusCode} len=${pub.body.length}');

  final signed = await http.post(
    Uri.parse(
      '$url/storage/v1/object/sign/fleaber_private/order_proofs/$buyerId/reaudit_own.jpg',
    ),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'expiresIn': 60}),
  );
  print('R F02J_SIGNED status=${signed.statusCode} body=${signed.body}');

  try {
    final m = jsonDecode(signed.body);
    final token = (m is Map ? m['signedURL'] ?? m['signedUrl'] : null)?.toString();
    if (token != null && token.isNotEmpty) {
      final abs = token.startsWith('http')
          ? token
          : '$url/storage/v1${token.startsWith('/') ? token : '/$token'}';
      final got = await http.get(Uri.parse(abs));
      print('R F02J_SIGNED_FETCH status=${got.statusCode} len=${got.body.length}');
    }
  } catch (e) {
    print('R F02J_SIGNED_PARSE $e');
  }

  final sellerAuth = await http.get(
    Uri.parse(
      '$url/storage/v1/object/authenticated/fleaber_private/order_proofs/$buyerId/reaudit_own.jpg',
    ),
    headers: {'apikey': anon, 'Authorization': 'Bearer $sellerJwt'},
  );
  print(
    'R F02J_SELLER_AUTH_GET status=${sellerAuth.statusCode} len=${sellerAuth.body.length}',
  );

  final listPriv = await http.post(
    Uri.parse('$url/storage/v1/object/list/fleaber_private'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'prefix': 'order_proofs/', 'limit': 10}),
  );
  print('R F02J_ANON_LIST_AFTER_UPLOAD status=${listPriv.statusCode} body=${listPriv.body}');
}
