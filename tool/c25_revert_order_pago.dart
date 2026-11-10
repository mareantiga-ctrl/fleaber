// ignore_for_file: avoid_print
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL')),
    anonKey: envRequire(e, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  await c.patch('orders', 'id=eq.e04a0fde-973d-4d0d-9663-bd2f2a4c46ae', {
    'status': 'pago',
  });
  print('reverted to pago');
}
