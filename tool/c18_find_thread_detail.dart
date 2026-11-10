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

  // Thread mais recente com shipped+completed: 0de859a8
  final threads = await sb.select('chats',
    filter: 'id=eq.0de859a8-003b-461e-89cf-60d63706965b', limit: 1);
  if (threads.isEmpty) {
    // Tentar outro nome de tabela
    print('chat_threads vazio — tentar chats');
    final chats = await sb.select('chats',
      filter: 'id=eq.0de859a8-003b-461e-89cf-60d63706965b', limit: 1);
    print('chats: $chats');
    return;
  }
  for (final t in threads) print(t);

  // Ver profiles dos participantes
  final sellerId = threads.first['seller_id']?.toString() ?? '';
  final buyerId = threads.first['buyer_id']?.toString() ?? '';
  if (sellerId.isNotEmpty) {
    final s = await sb.select('profiles', filter: 'id=eq.$sellerId', limit: 1);
    print('seller: ${s.firstOrNull}');
  }
  if (buyerId.isNotEmpty) {
    final b = await sb.select('profiles', filter: 'id=eq.$buyerId', limit: 1);
    print('buyer: ${b.firstOrNull}');
  }
}
