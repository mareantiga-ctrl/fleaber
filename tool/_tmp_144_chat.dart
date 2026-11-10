import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final oid = '70517197-6f1c-4ae1-8e4b-6db6dbf44a97';
  final o = (await sb.select('orders', filter: 'id=eq.$oid', limit: 1)).first;
  final pid = o['product_id']?.toString() ?? '';
  final chats = await sb.select('chats', filter: 'product_id=eq.$pid', limit: 5);
  for (final c in chats) {
    final msgs = await sb.select('chat_messages',
      filter: 'chat_id=eq.${c['id']}&created_at=gt.2026-08-24T08:00:00Z', limit: 10);
    for (final m in msgs) {
      print(jsonEncode({
        'chat': (c['id'] as String).substring(0, 8),
        'text': m['text'],
        'created_at': m['created_at'],
      }));
    }
    if (msgs.isEmpty) {
      print(jsonEncode({'chat': (c['id'] as String).substring(0, 8), 'last_message': c['last_message']}));
    }
  }
}
