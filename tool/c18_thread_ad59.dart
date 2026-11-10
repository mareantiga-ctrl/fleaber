// ignore_for_file: avoid_print
library;
import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final t = await sb.select('chats', filter: 'id=eq.ad59f782-400e-4a5d-bc55-c6f0241f7a98', limit: 1);
  print('thread: ${t.firstOrNull}');
  if (t.isEmpty) return;
  for (final uid in [t.first['user_a'], t.first['user_b']]) {
    final p = await sb.select('profiles', filter: 'id=eq.$uid', limit: 1);
    print('$uid → ${p.firstOrNull?['full_name']} (${p.firstOrNull?['user_type']})');
  }
}
