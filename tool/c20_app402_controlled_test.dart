// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _liveTitle = 'C20_APP402_CONTROLLED';
const _initialQty = 5;
const _sellQty = 2;

Future<void> _wipe(LiveOpsStagingClient client, String sellerId) async {
  final lives = await client.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&title=eq.$_liveTitle',
    limit: 20,
  );
  for (final live in lives) {
    final id = live['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    await client.deleteWhere('live_reservation_requests', 'live_id=eq.$id');
    await client.deleteWhere('orders', 'live_id=eq.$id');
    await client.deleteWhere('live_items', 'live_id=eq.$id');
    await client.deleteWhere('lives', 'id=eq.$id');
  }
}

Future<Map<String, dynamic>> _stock(
  LiveOpsStagingClient client,
  String liveItemId,
) async {
  final raw = await client.rpc('batata_live_item_stock', {
    'p_live_item_id': liveItemId,
  });
  if (raw is Map) return Map<String, dynamic>.from(raw);
  throw StateError('stock rpc inválido: $raw');
}

Map<String, dynamic> _stockView(Map<String, dynamic> s) {
  int i(String k) => (s[k] as num?)?.toInt() ?? 0;
  return {
    'total_qty': i('total_qty'),
    'blocked_qty': i('blocked_qty'),
    'reserved_accepted_qty': i('reserved_accepted_qty'),
    'pending_bag_qty': i('pending_bag_qty'),
    'sold_converted_qty': i('sold_converted_qty'),
    'available_qty': i('available_qty'),
  };
}

Future<void> main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final outDir = Directory('tool/reports/battery_c20_2026-08-19/bd');
  await outDir.create(recursive: true);

  var sellerId = staging['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  var buyerId = staging['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
  final sellerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  if (!isUuid(sellerId)) {
    sellerId = await client.userIdForAccessToken(sellerToken);
  }
  if (!isUuid(buyerId)) {
    final t = await client.signIn(
      email: envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
    );
    buyerId = await client.userIdForAccessToken(t);
  }

  await _wipe(client, sellerId);

  final live = await client.insert('lives', {
    'title': _liveTitle,
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
  });
  final liveId = live['id']!.toString();
  final ref = 'C20-APP402-${DateTime.now().millisecondsSinceEpoch}';
  final product = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'C20 APP-402 Produto Controlado',
    'price': 11,
    'quantity': _initialQty,
    'ref_code': ref,
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final productId = product['id']!.toString();
  final item = await client.insert('live_items', {
    'live_id': liveId,
    'ref_code': ref,
    'title': 'C20 APP-402 Item',
    'price': 11,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': productId,
    'checkout_product_id': productId,
  });
  final itemId = item['id']!.toString();

  final before = await _stock(client, itemId);

  final req = await client.insert('live_reservation_requests', {
    'live_id': liveId,
    'live_item_id': itemId,
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'requested_qty': _sellQty,
    'source': 'fleaber_live',
    'status': 'pending',
  });
  await client.rpc('batata_process_live_reservation_request', {
    'p_request_id': req['id'],
    'p_action': 'accept',
    'p_processed_by': sellerId,
  });
  final afterAccept = await _stock(client, itemId);

  final order = await client.insert('orders', {
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
    'live_item_id': itemId,
  });
  await client.rpc('batata_sync_live_item_for_order', {
    'p_order_id': order['id'],
  });
  final afterPaid = await _stock(client, itemId);

  await client.patch(
    'orders',
    'id=eq.${order['id']}',
    {'status': 'cancelado'},
  );
  final afterCancel = await _stock(client, itemId);

  final expectedAfterPaidAvailable = _initialQty - _sellQty;
  final expectedAfterCancelAvailable = _initialQty;

  final pass = ((afterPaid['available_qty'] as num?)?.toInt() ?? -1) ==
          expectedAfterPaidAvailable &&
      ((afterCancel['available_qty'] as num?)?.toInt() ?? -1) ==
          expectedAfterCancelAvailable;

  final report = {
    'generated_at': DateTime.now().toIso8601String(),
    'test_id': 'APP-402-CONTROLLED-C20',
    'setup': {
      'live_id': liveId,
      'live_item_id': itemId,
      'product_id': productId,
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'initial_qty': _initialQty,
      'sell_qty': _sellQty,
    },
    'expected': {
      'before_available': _initialQty,
      'after_paid_available': expectedAfterPaidAvailable,
      'after_cancel_available': expectedAfterCancelAvailable,
    },
    'states': {
      'before': _stockView(before),
      'after_accept': _stockView(afterAccept),
      'after_paid': _stockView(afterPaid),
      'after_cancel': _stockView(afterCancel),
    },
    'checks': {
      'paid_moves_stock_down': ((afterPaid['available_qty'] as num?)?.toInt() ?? -1) ==
          expectedAfterPaidAvailable,
      'cancel_moves_stock_up': ((afterCancel['available_qty'] as num?)?.toInt() ?? -1) ==
          expectedAfterCancelAvailable,
      'final_pass': pass,
    },
  };

  final outFile = File('${outDir.path}/c20_app402_controlled_result.json');
  await outFile.writeAsString(const JsonEncoder.withIndent('  ').convert(report));

  // end disposable live (BATATA: no live left active)
  await client.patch('lives', 'id=eq.$liveId', {'status': 'ended', 'is_active': false});
  await _wipe(client, sellerId);

  print('APP-402 C20 final_pass=$pass');
  print('result_file=${outFile.path}');
  exit(pass ? 0 : 1);
}
