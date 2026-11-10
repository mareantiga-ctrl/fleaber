// ignore_for_file: avoid_print
library;
import 'dart:convert';
import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final sellerId = staging['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  final buyerId = staging['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';

  // Threads do nosso seller ou buyer
  final sellerChats = await sb.select('chats', filter: 'user_a=eq.$sellerId&order=last_message_time.desc', limit: 20);
  final sellerChats2 = await sb.select('chats', filter: 'user_b=eq.$sellerId&order=last_message_time.desc', limit: 20);
  final buyerChats = await sb.select('chats', filter: 'user_a=eq.$buyerId&order=last_message_time.desc', limit: 20);
  final buyerChats2 = await sb.select('chats', filter: 'user_b=eq.$buyerId&order=last_message_time.desc', limit: 20);

  final allChats = {...sellerChats, ...sellerChats2, ...buyerChats, ...buyerChats2};
  final chatIds = allChats.map((c) => c['id']?.toString() ?? '').where((s) => s.isNotEmpty).toSet();
  print('total threads encontradas: ${chatIds.length}');
  for (final cid in chatIds) print('  $cid');

  // Ver quais têm shipped/completed
  final msgs = await sb.select('chat_messages',
    filter: 'text=like.FLEABER_JSON_V1%25&order=created_at.desc', limit: 200);
  const prefix = 'FLEABER_JSON_V1:';
  for (final m in msgs) {
    final text = m['text'] as String? ?? '';
    if (!text.startsWith(prefix)) continue;
    final cid = m['chat_id']?.toString() ?? '';
    if (!chatIds.contains(cid)) continue;
    try {
      final decoded = jsonDecode(text.substring(prefix.length));
      if (decoded is Map) {
        final kind = decoded['kind'] as String? ?? '';
        if (kind == 'reservation_order_shipped' || kind == 'reservation_order_completed') {
          print('MATCH! kind=$kind chat_id=$cid msg_id=${m['id']}');
        }
      }
    } catch (_) {}
  }
}
