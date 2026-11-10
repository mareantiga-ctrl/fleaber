import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  // Search in ALL chats for the product_id of 0f632c04 (66310bfa)
  final pid = '66310bfa-2d21-417e-a4fa-41995764d2d8';
  final chats = await sb.select('chats', filter: 'product_id=eq.$pid', limit: 5);
  print('chats for product: ${chats.length}');
  for (final c in chats) {
    print('  chat=${c['id']} ua=${(c['user_a'] as String).substring(0,8)} ub=${(c['user_b'] as String).substring(0,8)} last_msg=${c['last_message']}');
    // get recent messages
    final msgs = await sb.select('chat_messages',
      filter: 'chat_id=eq.${c['id']}&created_at=gt.2026-08-24T00:00:00Z', limit: 5);
    for (final m in msgs) {
      print('    msg id=${m['id']} text=${(m['text'] ?? '').toString().substring(0, ((m['text'] ?? '').toString().length).clamp(0,100))}');
    }
  }
}
