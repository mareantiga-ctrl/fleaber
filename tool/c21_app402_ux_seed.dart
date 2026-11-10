// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _title = 'C21_APP402_UX_SEED';
const _initialQty = 5;
const _sellQty = 2;

Future<Map<String, dynamic>> _stock(LiveOpsStagingClient sb, String liveItemId) async {
  final raw = await sb.rpc('batata_live_item_stock', {'p_live_item_id': liveItemId});
  if (raw is Map) return Map<String, dynamic>.from(raw);
  throw StateError('invalid stock rpc');
}

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

  final profile = await sb.select('profiles', filter: 'id=eq.$sellerId&select=id,full_name,handle', limit: 1);
  final handle = profile.isEmpty ? 'fleahub-demo-ux' : (profile.first['handle']?.toString() ?? 'fleahub-demo-ux');

  final live = await sb.insert('lives', {
    'title': _title,
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
    'mux_playback_id': 'maestro-smoke-staging-playback',
  });
  final liveId = live['id']!.toString();
  final ref = 'C21UX402-${DateTime.now().millisecondsSinceEpoch}';
  final product = await sb.insert('products', {
    'seller_id': sellerId,
    'title': 'C21 APP402 UX Produto',
    'price': 11,
    'quantity': _initialQty,
    'ref_code': ref,
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final productId = product['id']!.toString();
  final item = await sb.insert('live_items', {
    'live_id': liveId,
    'ref_code': ref,
    'title': 'C21 APP402 UX Item',
    'price': 11,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': productId,
    'checkout_product_id': productId,
  });
  final liveItemId = item['id']!.toString();

  final req = await sb.insert('live_reservation_requests', {
    'live_id': liveId,
    'live_item_id': liveItemId,
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'requested_qty': _sellQty,
    'source': 'fleaber_live',
    'status': 'pending',
  });
  await sb.rpc('batata_process_live_reservation_request', {
    'p_request_id': req['id'],
    'p_action': 'accept',
    'p_processed_by': sellerId,
  });
  final order = await sb.insert('orders', {
    'product_id': productId,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'price_total': 22,
    'shipping_method': 'Envio Transportadora (€3.50)',
    'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    'status': 'pago',
    'is_reservation': true,
    'quantity': _sellQty,
    'live_id': liveId,
    'live_item_id': liveItemId,
  });
  await sb.rpc('batata_sync_live_item_for_order', {'p_order_id': order['id']});

  final stock = await _stock(sb, liveItemId);
  final pNow = await sb.select('products', filter: 'id=eq.$productId', limit: 1);

  final outDir = Directory('tool/reports/battery_c21_2026-08-19/bd');
  await outDir.create(recursive: true);
  final outFile = File('${outDir.path}/c21_app402_ux_seed.json');
  await outFile.writeAsString(const JsonEncoder.withIndent('  ').convert({
    'generated_at': DateTime.now().toIso8601String(),
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'seller_handle': handle,
    'live_id': liveId,
    'live_item_id': liveItemId,
    'product_id': productId,
    'order_id': order['id'],
    'reservation_id': req['id'],
    'ref_code': ref,
    'expected_available_after_paid': 3,
    'stock_after_paid': stock,
    'product_after_paid': pNow.isEmpty ? null : pNow.first,
    'deeplinks': {
      'product_details': 'fleaber://fleaber.com/productDetails?product_id=$productId',
      'seller_profile_market': 'fleaber://fleaber.com/perfilVendedor?sellerID=$sellerId&initialTab=marketplace',
      'home': 'fleaber://fleaber.com/homePage',
      'hub_profile': 'https://fleaber.pt/$handle',
      'hub_shop': 'https://fleaber.pt/$handle/shop',
    },
  }));

  print('wrote ${outFile.path}');
}
