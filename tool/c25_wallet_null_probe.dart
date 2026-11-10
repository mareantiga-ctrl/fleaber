// ignore_for_file: avoid_print
import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL')),
    anonKey: envRequire(e, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const oid = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';
  await c.patch('orders', 'id=eq.$oid', {'wallet_release_processed_at': null});
  final t0 = await c.select('orders', filter: 'id=eq.$oid', limit: 1);
  print('t0: ${t0.first['wallet_release_processed_at']}');
  await Future<void>.delayed(const Duration(seconds: 5));
  final t1 = await c.select('orders', filter: 'id=eq.$oid', limit: 1);
  print('t5: ${t1.first['wallet_release_processed_at']}');
  print(jsonEncode(t1.first));
}
