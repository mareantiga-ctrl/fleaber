import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final chatId = '6a1d51f2-f57b-4eda-b675-905cd97dbdfb';
  final msgs = await sb.select('chat_messages',
    filter: 'chat_id=eq.$chatId', limit: 20);
  for (final m in msgs) {
    final body = (m['body'] ?? '').toString();
    print(jsonEncode({
      'created_at': m['created_at'],
      'body_preview': body.substring(0, body.length.clamp(0, 150)),
    }));
  }
}
