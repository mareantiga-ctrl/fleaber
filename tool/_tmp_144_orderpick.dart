import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final orders = await sb.select('orders', filter: 'seller_id=eq.$sellerId&buyer_id=eq.$buyerId&status=eq.pago&payment_method=eq.Pagamento Direto ao Vendedor (MB WAY/Transf)&order=created_at.desc', limit: 10);
  for (final o in orders) {
    print(jsonEncode({
      'id': o['id'],
      'created_at': o['created_at'],
      'price_total': o['price_total'],
      'stripe_refund_id': o['stripe_refund_id'],
      'stripe_checkout_session_id': o['stripe_checkout_session_id'],
      'wallet_refund_processed_at': o['wallet_refund_processed_at'],
    }));
  }
}
