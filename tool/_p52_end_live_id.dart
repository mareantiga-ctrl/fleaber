import 'dart:io';
import 'live_ops_staging_client.dart';
Future<void> main(List<String> args) async {
  final id = args.first;
  final s = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(url: normalizeSupabaseProjectUrl(envRequire(s,'SUPABASE_URL')), anonKey: envRequire(s,'SUPABASE_ANON_KEY'), serviceRoleKey: envRequire(s,'SUPABASE_SERVICE_ROLE_KEY'));
  await c.patch('lives', 'id=eq.$id', {'status':'ended','is_active':false});
  print('ended $id');
}