import 'live_ops_staging_client.dart';
Future<void> main() async {
  final s = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(url: normalizeSupabaseProjectUrl(envRequire(s,'SUPABASE_URL')), anonKey: envRequire(s,'SUPABASE_ANON_KEY'), serviceRoleKey: envRequire(s,'SUPABASE_SERVICE_ROLE_KEY'));
  await c.patch('lives', 'id=eq.7c8a5cb8-80f1-4303-a722-8e0341d93983', {'status':'ended','is_active':false});
  print('ended G');
}
