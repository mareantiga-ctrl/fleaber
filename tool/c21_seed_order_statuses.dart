// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _tag = 'C21-STATUS';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  var sellerId = env['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  var buyerId = env['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
  final sellerToken = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  if (!isUuid(sellerId)) sellerId = await sb.userIdForAccessToken(sellerToken);
  if (!isUuid(buyerId)) {
    final t = await sb.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
    );
    buyerId = await sb.userIdForAccessToken(t);
  }

  final statuses = [
    'reservado',
    'pedido_devolucao',
    'em_devolucao',
    'devolucao_entregue',
    'disputa_devolucao_vendedor',
    'devolvida',
  ];

  final created = <Map<String, dynamic>>[];
  for (final st in statuses) {
    final p = await sb.insert('products', {
      'seller_id': sellerId,
      'title': '$_tag $st',
      'price': 9,
      'quantity': 1,
      'ref_code': '$_tag-${DateTime.now().millisecondsSinceEpoch}-$st',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final order = await sb.insert('orders', {
      'product_id': p['id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'price_total': 9,
      'shipping_method': 'Envio Transportadora (€3.50)',
      'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
      'status': st,
      'is_reservation': true,
      'quantity': 1,
    });
    created.add({
      'status': st,
      'order_id': order['id'],
      'product_id': p['id'],
      'product_title': p['title'],
    });
  }

  final out = File('tool/reports/battery_c21_2026-08-19/bd/c21_seed_statuses_orders.json');
  await out.writeAsString(const JsonEncoder.withIndent('  ').convert({
    'generated_at': DateTime.now().toIso8601String(),
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'created': created,
  }));
  print('seeded ${created.length} orders');
}
