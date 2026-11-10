import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  // get product_id for each order to find chat
  for (final oid in ['0f632c04-b3c5-4074-8957-892e258f7f92',
                     '903c41b3-8c43-4c75-a4b2-d49786bef009']) {
    final o = (await sb.select('orders', filter: 'id=eq.$oid', limit: 1)).first;
    final pid = o['product_id']?.toString() ?? '';
    final sellerId = o['seller_id']?.toString() ?? '';
    final buyerId  = o['buyer_id']?.toString() ?? '';
    List chats = [];
    if (pid.isNotEmpty) {
      chats = await sb.select('chats',
        filter: 'product_id=eq.$pid',
        limit: 3,
      );
    }
    print(jsonEncode({
      'order_id': oid,
      'status': o['status'],
      'payment_method': o['payment_method'],
      'price_total': o['price_total'],
      'product_id': pid,
      'seller_id': sellerId.substring(0,8),
      'buyer_id': buyerId.substring(0,8),
      'stripe_checkout_session_id': o['stripe_checkout_session_id'],
      'chats': chats.map((c) => {'id': c['id'], 'ua': c['user_a'], 'ub': c['user_b']}).toList(),
    }));
  }
}
