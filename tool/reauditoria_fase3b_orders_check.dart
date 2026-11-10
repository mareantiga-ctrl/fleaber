// ignore_for_file: avoid_print
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

void main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final buyer = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final client = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: 'unused',
  );
  final s = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final r = await http.get(
    Uri.parse('$url/rest/v1/orders?buyer_id=eq.$buyer&select=id,status&limit=5'),
    headers: {'apikey': anon, 'Authorization': 'Bearer $s'},
  );
  print('orders_seller_sees_with_new_buyer status=${r.statusCode} body=${r.body}');
}
