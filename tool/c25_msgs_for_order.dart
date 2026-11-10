import 'dart:convert';
import 'live_ops_staging_client.dart';
void main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final oid = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';
  final msgs = await sb.select(
    'chat_messages',
    filter: 'text=like.%25$oid%25&order=created_at.desc',
    limit: 20,
  );
  print(jsonEncode(msgs));
}
