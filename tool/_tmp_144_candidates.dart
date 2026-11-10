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

  final orders = await sb.select('orders', filter: 'seller_id=eq.$sellerId&buyer_id=eq.$buyerId&status=eq.pago&payment_method=eq.Pagamento Direto ao Vendedor (MB WAY/Transf)', limit: 20);
  for (final o in orders) {
    final pid = o['product_id']?.toString() ?? '';
    final prod = pid.isNotEmpty ? await sb.select('products', filter: 'id=eq.$pid', limit: 1) : <Map<String,dynamic>>[];
    final title = prod.isNotEmpty ? (prod.first['title']?.toString() ?? '') : '';
    final chats = pid.isNotEmpty ? await sb.select('chats', filter: 'product_id=eq.$pid', limit: 5) : <Map<String,dynamic>>[];
    final candidateChats = chats.where((c){
      final ua = c['user_a']?.toString() ?? '';
      final ub = c['user_b']?.toString() ?? '';
      return (ua == buyerId && ub == sellerId) || (ua == sellerId && ub == buyerId);
    }).toList();

    var hasStripeText = false;
    var sample = <String>[];
    for (final c in candidateChats) {
      final msgs = await sb.select('chat_messages', filter: 'chat_id=eq.${c['id']}', limit: 20);
      for (final m in msgs) {
        final t = (m['text'] ?? '').toString();
        if (t.contains('Reembolso Stripe iniciado') || t.contains('pagamento original') || t.contains('anulou a venda')) {
          hasStripeText = true;
        }
        if (sample.length < 2 && t.isNotEmpty) sample.add(t);
      }
    }

    print(jsonEncode({
      'order_id': o['id'],
      'total': o['price_total'],
      'title': title,
      'status': o['status'],
      'payment_method': o['payment_method'],
      'chat_count': candidateChats.length,
      'has_refund_text_in_chat': hasStripeText,
      'sample_msgs': sample,
    }));
  }
}
