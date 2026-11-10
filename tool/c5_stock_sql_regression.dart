// ignore_for_file: avoid_print
/// Regressão SQL stock (cancelar / rejeitar / pago) numa live descartável.
/// Não toca na live MAESTRO_SMOKE_LIVE da Corrida 5.
///
///   dart run tool/c5_stock_sql_regression.dart
library;

import 'dart:io';

import 'live_ops_staging_client.dart';

const _title = 'C5_SQL_REGRESSION';

Future<void> _wipe(LiveOpsStagingClient client, String sellerId) async {
  final lives = await client.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&title=eq.$_title',
    limit: 10,
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

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
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
    'title': _title,
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
  });
  final liveId = live['id']!.toString();
  final product = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'C5 SQL regression product',
    'price': 5,
    'quantity': 5,
    'ref_code': 'C5SQL-${DateTime.now().millisecondsSinceEpoch}',
    'list_on_marketplace': false,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final productId = product['id']!.toString();
  final item = await client.insert('live_items', {
    'live_id': liveId,
    'ref_code': product['ref_code'],
    'title': 'C5 SQL item',
    'price': 5,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': productId,
    'checkout_product_id': productId,
  });
  final itemId = item['id']!.toString();

  var fail = 0;
  void check(String name, bool ok, [String detail = '']) {
    print('${ok ? "PASS" : "FAIL"} $name ${detail.isEmpty ? "" : "— $detail"}');
    if (!ok) fail++;
  }

  final rejected = await client.insert('live_reservation_requests', {
    'live_id': liveId,
    'live_item_id': itemId,
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'requested_qty': 1,
    'source': 'fleaber_live',
    'status': 'pending',
  });
  final rejectRes = await client.rpc('batata_process_live_reservation_request', {
    'p_request_id': rejected['id'],
    'p_action': 'reject',
    'p_processed_by': sellerId,
    'p_notes': 'c5_sql_reject',
  });
  final afterReject = await _stock(client, itemId);
  check(
    'rejeitar não conta como reserva',
    (afterReject['reserved_accepted_qty'] as num?)?.toInt() == 0 &&
        (rejectRes is Map && rejectRes['ok'] == true),
    'reserved=${afterReject['reserved_accepted_qty']}',
  );

  final cancelled = await client.insert('live_reservation_requests', {
    'live_id': liveId,
    'live_item_id': itemId,
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'requested_qty': 1,
    'source': 'fleaber_live',
    'status': 'pending',
  });
  await client.patch(
    'live_reservation_requests',
    'id=eq.${cancelled['id']}',
    {'status': 'expired'},
  );
  final afterCancel = await _stock(client, itemId);
  check(
    'expirar/cancelar não conta como reserva',
    (afterCancel['reserved_accepted_qty'] as num?)?.toInt() == 0 &&
        (afterCancel['pending_bag_qty'] as num?)?.toInt() == 0,
    'reserved=${afterCancel['reserved_accepted_qty']} pending=${afterCancel['pending_bag_qty']}',
  );

  final accepted = await client.insert('live_reservation_requests', {
    'live_id': liveId,
    'live_item_id': itemId,
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'requested_qty': 2,
    'source': 'fleaber_live',
    'status': 'pending',
  });
  await client.rpc('batata_process_live_reservation_request', {
    'p_request_id': accepted['id'],
    'p_action': 'accept',
    'p_processed_by': sellerId,
  });
  final afterAccept = await _stock(client, itemId);
  check(
    'aceite sem pago conta como reserva (não como vendido)',
    (afterAccept['reserved_accepted_qty'] as num?)?.toInt() == 2 &&
        (afterAccept['sold_converted_qty'] as num?)?.toInt() == 0,
    'reserved=${afterAccept['reserved_accepted_qty']} sold=${afterAccept['sold_converted_qty']}',
  );

  final order = await client.insert('orders', {
    'product_id': productId,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'price_total': 13.5,
    'shipping_method': 'Envio Transportadora (€3.50)',
    'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    'status': 'pago',
    'is_reservation': true,
    'quantity': 2,
    'live_id': liveId,
    'live_item_id': itemId,
  });
  await client.rpc('batata_sync_live_item_for_order', {
    'p_order_id': order['id'],
  });
  final afterPago = await _stock(client, itemId);
  check(
    'pago: vendido 2, reservas 0 (sem contar duas vezes)',
    (afterPago['sold_converted_qty'] as num?)?.toInt() == 2 &&
        (afterPago['reserved_accepted_qty'] as num?)?.toInt() == 0,
    'sold=${afterPago['sold_converted_qty']} reserved=${afterPago['reserved_accepted_qty']} avail=${afterPago['available_qty']}',
  );

  await _wipe(client, sellerId);
  exit(fail > 0 ? 1 : 0);
}
