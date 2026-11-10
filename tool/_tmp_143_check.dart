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
  final buyerId  = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');

  // encomendas recentes do vendedor ou comprador de teste no estado pago/enviado
  final orders = await sb.select(
    'orders',
    filter: 'seller_id=eq.$sellerId&status=in.(pago,enviado,reservado)&limit=10',
    limit: 10,
  );
  // também ver se há alguma pago do comprador
  final bOrders = await sb.select(
    'orders',
    filter: 'buyer_id=eq.$buyerId&status=in.(pago,enviado)&limit=5',
    limit: 5,
  );

  final all = [...orders, ...bOrders];
  for (final o in all) {
    print(jsonEncode({
      'id': o['id'],
      'status': o['status'],
      'payment_method': o['payment_method'],
      'price_total': o['price_total'],
      'seller_id': (o['seller_id'] as String?)?.substring(0, 8),
      'buyer_id': (o['buyer_id'] as String?)?.substring(0, 8),
      'stripe_refund_id': o['stripe_refund_id'],
      'wallet_release_processed_at': o['wallet_release_processed_at'],
    }));
  }
  if (all.isEmpty) print('nenhuma encomenda pago/enviado encontrada');
}
