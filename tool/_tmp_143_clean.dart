import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  for (final oid in [
    'b0d566cf-f8e2-4068-8f0b-af1e2cd02216',  // 6.43 Seguro
    'f45f7865-75fd-4863-ac4b-df3af7823a33',   // 37.93 Seguro
    '664a5183-a117-4329-a034-9698b3dc45e1',   // 16.93 Seguro
  ]) {
    final rows = await sb.select('orders', filter: 'id=eq.$oid', limit:1);
    if (rows.isEmpty) { print('$oid NOT FOUND'); continue; }
    final o = rows.first;
    final pid = o['product_id']?.toString() ?? '';
    final chats = pid.isNotEmpty
      ? await sb.select('chats', filter: 'product_id=eq.$pid', limit:3)
      : [];
    final disputes = await sb.select('order_disputes', filter: 'order_id=eq.$oid', limit:3);
    print(jsonEncode({
      'id': oid.substring(0,8),
      'status': o['status'],
      'pm': (o['payment_method'] as String? ?? '').substring(0, ((o['payment_method'] as String? ?? '').length).clamp(0,20)),
      'total': o['price_total'],
      'stripe_refund_id': o['stripe_refund_id'],
      'chat_id': chats.isNotEmpty ? chats.first['id'] : null,
      'disputes': disputes.length,
      'buyer_id': (o['buyer_id'] as String?)?.substring(0,8),
    }));
  }
}
