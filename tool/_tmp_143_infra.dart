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

  // Check stripe columns exist via orders table
  final cols = await sb.rpc('run_sql_string', params: {
    'sql': "select column_name from information_schema.columns where table_schema='public' and table_name='orders' and column_name like 'stripe_%'"
  });
  print('stripe_cols: ${jsonEncode(cols)}');

  // check triggers
  final trgs = await sb.rpc('run_sql_string', params: {
    'sql': "select tgname from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='orders' and (tgname like '%cancel%' or tgname like '%wallet%')"
  });
  print('triggers: ${jsonEncode(trgs)}');
}
