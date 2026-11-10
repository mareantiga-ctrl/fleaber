// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final orderId = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';
  final sellerEmail = envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL');
  final sellerPassword = envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD');
  final token = await client.signIn(email: sellerEmail, password: sellerPassword);
  final sellerId = await client.userIdForAccessToken(token);

  final before = (await client.select('orders', filter: 'id=eq.$orderId', limit: 1)).first;

  // Simular PATCH app (seller marca enviado)
  try {
    await client.patchAsUser(
      'orders',
      'id=eq.$orderId',
      {'status': 'enviado'},
      accessToken: token,
    );
    print('patch_auth: OK');
  } catch (e) {
    print('patch_auth FAIL: $e');
  }

  final after = (await client.select('orders', filter: 'id=eq.$orderId', limit: 1)).first;
  print(jsonEncode({
    'seller_id': sellerId,
    'before_status': before['status'],
    'after_status': after['status'],
    'order_seller': before['seller_id'],
  }));
}
