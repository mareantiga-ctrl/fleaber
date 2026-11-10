import 'dart:convert';
import 'dart:io';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final sellerEmail = envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL');
  final sellerPass  = envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD');
  final jwt = await sb.signIn(email: sellerEmail, password: sellerPass);
  print('seller jwt ok');

  final res = await sb.invokeEdge('refund-order', {
    'order_id': '0f632c04-b3c5-4074-8957-892e258f7f92',
  }, accessToken: jwt);
  print('edge status: ${res.statusCode}');
  print('edge body: ${res.body}');
}
