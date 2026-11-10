// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _title = 'C20_APP402_ROOT_CAUSE';
const _initialQty = 5;
const _sellQty = 2;

Future<Map<String, dynamic>> _stock(LiveOpsStagingClient sb, String liveItemId) async {
  final raw = await sb.rpc('batata_live_item_stock', {'p_live_item_id': liveItemId});
  if (raw is Map) return Map<String, dynamic>.from(raw);
  throw StateError('invalid stock rpc');
}

Future<Map<String, dynamic>> _product(LiveOpsStagingClient sb, String productId) async {
  final p = await sb.select('products', filter: 'id=eq.$productId', limit: 1);
  return p.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(p.first);
}

Future<Map<String, dynamic>> _orderSums(LiveOpsStagingClient sb, String productId) async {
  final orders = await sb.select(
    'orders',
    filter: 'product_id=eq.$productId&order=created_at.desc',
    limit: 50,
  );
  final sums = <String, int>{};
  for (final o in orders) {
    final st = (o['status'] ?? '').toString().trim().toLowerCase();
    final q = (o['quantity'] as num?)?.toInt() ?? 1;
    sums[st] = (sums[st] ?? 0) + q;
  }
  return {
    'count': orders.length,
    'qty_by_status': sums,
    'sample': orders
        .take(5)
        .map((o) => {
              'id': o['id'],
              'status': o['status'],
              'quantity': o['quantity'],
              'created_at': o['created_at'],
            })
        .toList(),
  };
}

Future<Map<String, dynamic>> _reservationSums(LiveOpsStagingClient sb, String liveItemId) async {
  final reqs = await sb.select(
    'live_reservation_requests',
    filter: 'live_item_id=eq.$liveItemId&order=created_at.desc',
    limit: 50,
  );
  final sums = <String, int>{};
  for (final r in reqs) {
    final st = (r['status'] ?? '').toString().trim().toLowerCase();
    final q = (r['requested_qty'] as num?)?.toInt() ?? 1;
    sums[st] = (sums[st] ?? 0) + q;
  }
  return {
    'count': reqs.length,
    'qty_by_status': sums,
    'sample': reqs
        .take(5)
        .map((r) => {
              'id': r['id'],
              'status': r['status'],
              'requested_qty': r['requested_qty'],
              'created_at': r['created_at'],
            })
        .toList(),
  };
}

Map<String, dynamic> _view(Map<String, dynamic> s) {
  int i(String k) => (s[k] as num?)?.toInt() ?? 0;
  return {
    'total_qty': i('total_qty'),
    'blocked_qty': i('blocked_qty'),
    'reserved_accepted_qty': i('reserved_accepted_qty'),
    'pending_bag_qty': i('pending_bag_qty'),
    'sold_converted_qty': i('sold_converted_qty'),
    'available_qty': i('available_qty'),
    'formula_without_sold': (i('total_qty') - i('blocked_qty') - i('reserved_accepted_qty') - i('pending_bag_qty')).clamp(0, 999999),
    'formula_with_sold': (i('total_qty') - i('blocked_qty') - i('reserved_accepted_qty') - i('pending_bag_qty') - i('sold_converted_qty')).clamp(0, 999999),
  };
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final outDir = Directory('tool/reports/battery_c20_2026-08-19/bd');
  await outDir.create(recursive: true);

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

  final live = await sb.insert('lives', {
    'title': _title,
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
  });
  final liveId = live['id']!.toString();

  final ref = 'C20RC-${DateTime.now().millisecondsSinceEpoch}';
  final product = await sb.insert('products', {
    'seller_id': sellerId,
    'title': 'C20 RC Produto',
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
    'title': 'C20 RC Item',
    'price': 11,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': productId,
    'checkout_product_id': productId,
  });
  final liveItemId = item['id']!.toString();

  final beforeStock = await _stock(sb, liveItemId);
  final beforeProduct = await _product(sb, productId);

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
  final afterAcceptStock = await _stock(sb, liveItemId);
  final afterAcceptProduct = await _product(sb, productId);

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
  final afterPaidStock = await _stock(sb, liveItemId);
  final afterPaidProduct = await _product(sb, productId);
  final afterPaidOrders = await _orderSums(sb, productId);
  final afterPaidReqs = await _reservationSums(sb, liveItemId);

  await sb.patch('orders', 'id=eq.${order['id']}', {'status': 'cancelado'});
  final afterCancelStock = await _stock(sb, liveItemId);
  final afterCancelProduct = await _product(sb, productId);
  final afterCancelOrders = await _orderSums(sb, productId);
  final afterCancelReqs = await _reservationSums(sb, liveItemId);

  final result = {
    'generated_at': DateTime.now().toIso8601String(),
    'ids': {
      'live_id': liveId,
      'live_item_id': liveItemId,
      'product_id': productId,
      'order_id': order['id'],
      'reservation_id': req['id'],
    },
    'expected': {
      'initial_qty': _initialQty,
      'sell_qty': _sellQty,
      'after_paid_target_available': _initialQty - _sellQty,
      'after_cancel_target_available': _initialQty,
    },
    'before': {
      'stock': _view(beforeStock),
      'product_quantity': beforeProduct['quantity'],
    },
    'after_accept': {
      'stock': _view(afterAcceptStock),
      'product_quantity': afterAcceptProduct['quantity'],
    },
    'after_paid': {
      'stock': _view(afterPaidStock),
      'product_quantity': afterPaidProduct['quantity'],
      'orders': afterPaidOrders,
      'reservations': afterPaidReqs,
    },
    'after_cancel': {
      'stock': _view(afterCancelStock),
      'product_quantity': afterCancelProduct['quantity'],
      'orders': afterCancelOrders,
      'reservations': afterCancelReqs,
    },
    'diagnosis': {
      'paid_available_is_lower_than_target':
          ((_view(afterPaidStock)['available_qty'] as int) < (_initialQty - _sellQty)),
      'product_quantity_decreased_on_paid':
          ((afterPaidProduct['quantity'] as num?)?.toInt() ?? -1) < _initialQty,
      'blocked_includes_paid_or_similar':
          ((_view(afterPaidStock)['blocked_qty'] as int) >= _sellQty),
    },
  };

  final file = File('${outDir.path}/c20_app402_root_cause.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(result));
  print('wrote ${file.path}');
}
