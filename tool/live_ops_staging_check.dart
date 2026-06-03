// ignore_for_file: avoid_print
/// Checks V0 live ops em Supabase staging (sem APK).
/// Uso: dart run tool/live_ops_staging_check.dart
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _liveTitle = 'LIVE_OPS_V0_TEST';
const _refPrefix = 'V0TEST';

void main(List<String> args) async {
  final results = <String, bool>{};
  try {
    final env = loadLiveOpsStagingEnv();
    final client = LiveOpsStagingClient(
      url: envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/$'), ''),
      anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
      serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
    );
    final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
    final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
    final buyerEmail = envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL');
    final buyerPassword = envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD');
    final sellerEmail = envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL');
    final sellerPassword = envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD');

    print('Fleaber live ops V0 — staging checks');
    print('URL: ${client.url}');
    print('---');

    final buyerToken = await client.signIn(
      email: buyerEmail,
      password: buyerPassword,
    );
    final sellerToken = await client.signIn(
      email: sellerEmail,
      password: sellerPassword,
    );

    await _cleanup(client, sellerId);

    results['V0.3c #4 cancelar reserva'] = await _scenarioCancel(
      client: client,
      sellerId: sellerId,
      buyerId: buyerId,
      buyerToken: buyerToken,
    );

    results['V0.3a #7 reconcile pago'] = await _scenarioReconcile(
      client: client,
      sellerId: sellerId,
      buyerId: buyerId,
      buyerToken: buyerToken,
    );

    results['V0.3d #3 stock vendido'] = await _scenarioStock(
      client: client,
      sellerId: sellerId,
      sellerToken: sellerToken,
    );

    results['V0.3e #6 edge bag POST'] = await _scenarioBagEdgePost(
      client: client,
      sellerId: sellerId,
      buyerId: buyerId,
      buyerToken: buyerToken,
    );
  } catch (e, st) {
    print('FATAL: $e');
    print(st);
    exitCode = 1;
    return;
  }

  print('---');
  var failed = 0;
  for (final e in results.entries) {
    final icon = e.value ? 'PASS' : 'FAIL';
    print('$icon  ${e.key}');
    if (!e.value) failed++;
  }
  if (failed > 0) {
    print('---');
    print('$failed cenário(s) falharam.');
    exitCode = 1;
  } else {
    print('---');
    print('Todos os cenários V0 staging PASS.');
  }
}

Future<void> _cleanup(LiveOpsStagingClient client, String sellerId) async {
  final lives = await client.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&title=eq.$_liveTitle',
    limit: 5,
  );
  for (final live in lives) {
    final liveId = live['id']?.toString() ?? '';
    if (liveId.isEmpty) continue;
    await client.deleteWhere(
      'live_reservation_requests',
      'live_id=eq.$liveId',
    );
    await client.deleteWhere('orders', 'live_id=eq.$liveId');
    await client.deleteWhere('live_items', 'live_id=eq.$liveId');
    await client.deleteWhere('lives', 'id=eq.$liveId');
  }
}

Future<Map<String, String>> _createLiveFixture({
  required LiveOpsStagingClient client,
  required String sellerId,
  required String buyerId,
  String itemStatus = 'available',
  int itemQty = 5,
}) async {
  final live = await client.insert('lives', {
    'title': _liveTitle,
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
  });
  final liveId = live['id']!.toString();
  final ref = '$_refPrefix-${DateTime.now().millisecondsSinceEpoch}';
  final item = await client.insert('live_items', {
    'live_id': liveId,
    'ref_code': ref,
    'title': 'V0 test item',
    'price': 5,
    'quantity': itemQty,
    'is_active': true,
    'status': itemStatus,
    'item_kind': 'live_only',
  });
  final liveItemId = item['id']!.toString();

  final product = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'V0 product',
    'price': 5,
    'quantity': itemQty,
    'ref_code': ref,
    'list_on_marketplace': false,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final productId = product['id']!.toString();

  await client.patch(
    'live_items',
    'id=eq.$liveItemId',
    {'checkout_product_id': productId, 'product_id': productId},
  );

  return {
    'live_id': liveId,
    'live_item_id': liveItemId,
    'product_id': productId,
  };
}

Future<bool> _scenarioCancel({
  required LiveOpsStagingClient client,
  required String sellerId,
  required String buyerId,
  required String buyerToken,
}) async {
  try {
    final fx = await _createLiveFixture(
      client: client,
      sellerId: sellerId,
      buyerId: buyerId,
    );
    final res = await client.insert('live_reservation_requests', {
      'live_id': fx['live_id'],
      'live_item_id': fx['live_item_id'],
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'requested_qty': 1,
      'source': 'fleaber_live',
      'status': 'pending',
    });
    final requestId = res['id']!.toString();

    final rpcRes = await client.rpc(
      'batata_live_bag_remove_request',
      {'p_request_id': requestId},
      accessToken: buyerToken,
    );
    final ok = rpcRes is Map && rpcRes['ok'] == true;
    if (!ok) {
      print('  cancel rpc: $rpcRes');
      return false;
    }

    final rows = await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$requestId',
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final row = rows.first;
    final notes = (row['notes'] ?? '').toString().toLowerCase();
    if (row['status'] != 'rejected' || !notes.contains('bag_removed')) {
      print('  expected rejected+bag_removed, got ${row['status']} $notes');
      return false;
    }
    return true;
  } catch (e) {
    print('  $e');
    return false;
  }
}

Future<bool> _scenarioReconcile({
  required LiveOpsStagingClient client,
  required String sellerId,
  required String buyerId,
  required String buyerToken,
}) async {
  try {
    final fx = await _createLiveFixture(
      client: client,
      sellerId: sellerId,
      buyerId: buyerId,
    );
    final order = await client.insert('orders', {
      'product_id': fx['product_id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'price_total': 5.9,
      'shipping_method': 'Envio Transportadora (€3.50)',
      'payment_method': 'Pagamento na App',
      'status': 'reserva_pendente',
      'is_reservation': false,
      'quantity': 1,
      'live_id': fx['live_id'],
      'live_item_id': fx['live_item_id'],
    });
    final orderId = order['id']!.toString();

    final resReq = await client.insert('live_reservation_requests', {
      'live_id': fx['live_id'],
      'live_item_id': fx['live_item_id'],
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'requested_qty': 1,
      'source': 'fleaber_live',
      'status': 'accepted',
      'notes': 'stripe_checkout:$orderId',
    });
    final requestId = resReq['id']!.toString();

    await client.patch(
      'orders',
      'id=eq.$orderId',
      {'status': 'pago'},
    );

    final rpcRes = await client.rpc(
      'batata_live_reconcile_stripe_order',
      {
        'p_order_id': orderId,
        'p_reservation_request_id': requestId,
      },
      accessToken: buyerToken,
    );
    final ok = rpcRes is Map && rpcRes['ok'] == true;
    if (!ok) {
      print('  reconcile: $rpcRes');
      return false;
    }

    final orders = await client.select(
      'orders',
      filter: 'id=eq.$orderId',
      limit: 1,
    );
    if (orders.isEmpty || orders.first['status'] != 'pago') {
      print('  order not pago');
      return false;
    }
    if ((orders.first['live_id'] ?? '').toString().isEmpty) {
      print('  order.live_id empty');
      return false;
    }

    final reqs = await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$requestId',
      limit: 1,
    );
    if (reqs.isEmpty || reqs.first['status'] != 'converted') {
      print('  reservation not converted: ${reqs.isNotEmpty ? reqs.first['status'] : 'missing'}');
      return false;
    }
    final notes = (reqs.first['notes'] ?? '').toString();
    if (!notes.contains('stripe_paid')) {
      print('  missing stripe_paid in notes');
      return false;
    }
    return true;
  } catch (e) {
    print('  $e');
    return false;
  }
}

Future<bool> _scenarioStock({
  required LiveOpsStagingClient client,
  required String sellerId,
  required String sellerToken,
}) async {
  try {
    final fx = await _createLiveFixture(
      client: client,
      sellerId: sellerId,
      buyerId: sellerId,
      itemStatus: 'sold',
      itemQty: 1,
    );
    final liveItemId = fx['live_item_id']!;

    final updateRes = await client.rpc(
      'batata_update_live_item',
      {
        'p_live_item_id': liveItemId,
        'p_quantity': 6,
      },
      accessToken: sellerToken,
    );
    if (updateRes is! Map) {
      print('  update_live_item: $updateRes');
      return false;
    }
    final stockOk = updateRes['ok'] == true ||
        updateRes['available_qty'] != null;
    if (!stockOk) {
      print('  update_live_item failed: $updateRes');
      return false;
    }

    final avail = updateRes['available_qty'];
    if (avail is num && avail <= 0) {
      print('  available_qty still 0');
      return false;
    }

    final items = await client.select(
      'live_items',
      filter: 'id=eq.$liveItemId',
      limit: 1,
    );
    if (items.isNotEmpty) {
      final st = items.first['status']?.toString() ?? '';
      if (st == 'sold') {
        print('  item still sold after qty 6 (hotfix recompute?)');
        return false;
      }
    }
    return true;
  } catch (e) {
    print('  $e');
    return false;
  }
}

Future<bool> _scenarioBagEdgePost({
  required LiveOpsStagingClient client,
  required String sellerId,
  required String buyerId,
  required String buyerToken,
}) async {
  try {
    await _cleanup(client, sellerId);
    final live = await client.insert('lives', {
      'title': _liveTitle,
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final liveId = live['id']!.toString();

    Future<Map<String, String>> addItem(String refSuffix) async {
      final ref = '$_refPrefix-$refSuffix';
      final item = await client.insert('live_items', {
        'live_id': liveId,
        'ref_code': ref,
        'title': 'V0 bag $refSuffix',
        'price': 5,
        'quantity': 5,
        'is_active': true,
        'status': 'available',
        'item_kind': 'live_only',
      });
      final liveItemId = item['id']!.toString();
      final product = await client.insert('products', {
        'seller_id': sellerId,
        'title': 'V0 bag prod $refSuffix',
        'price': 5,
        'quantity': 5,
        'ref_code': ref,
        'list_on_marketplace': false,
        'available_for_live': true,
        'is_sold': false,
        'image_urls': <String>[],
      });
      final productId = product['id']!.toString();
      await client.patch(
        'live_items',
        'id=eq.$liveItemId',
        {'checkout_product_id': productId, 'product_id': productId},
      );
      return {
        'live_item_id': liveItemId,
        'product_id': productId,
      };
    }

    final i1 = await addItem('a');
    final i2 = await addItem('b');

    final order1 = await client.insert('orders', {
      'product_id': i1['product_id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'price_total': 5.9,
      'status': 'reserva_pendente',
      'quantity': 1,
      'live_id': liveId,
      'live_item_id': i1['live_item_id'],
    });
    final order2 = await client.insert('orders', {
      'product_id': i2['product_id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'price_total': 5.9,
      'status': 'reserva_pendente',
      'quantity': 1,
      'live_id': liveId,
      'live_item_id': i2['live_item_id'],
    });
    final oid1 = order1['id']!.toString();
    final oid2 = order2['id']!.toString();

    const lineCents = 590;
    final body = {
      'amount': lineCents * 2 + 350,
      'currency': 'eur',
      'product_id': i1['product_id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'order_id': oid1,
      'quantity': 1,
      'item_price': lineCents * 2,
      'shipping': 350,
      'protection_fee': 0,
      'shipping_method': 'Envio Transportadora (€3.50)',
      'live_id': liveId,
      'is_live': true,
      'live_seller_id': sellerId,
      'bag_checkout': true,
      'bag_lines': [
        {
          'order_id': oid1,
          'product_id': i1['product_id'],
          'seller_id': sellerId,
          'quantity': 1,
          'line_total_cents': lineCents,
          'live_item_id': i1['live_item_id'],
        },
        {
          'order_id': oid2,
          'product_id': i2['product_id'],
          'seller_id': sellerId,
          'quantity': 1,
          'line_total_cents': lineCents,
          'live_item_id': i2['live_item_id'],
        },
      ],
    };

    final res = await client.invokeEdge(
      'create-payment-intent',
      body,
      accessToken: buyerToken,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      print('  edge ${res.statusCode}: ${res.body}');
      return false;
    }
    final data = jsonDecode(res.body);
    if (data is! Map) return false;
    final url = data['checkoutUrl']?.toString() ?? '';
    if (url.isEmpty) {
      print('  no checkoutUrl: $data');
      return false;
    }
    // Metadata compacta: não deve existir JSON gigante no body de erro
    if (res.body.contains('bag_orders_json') &&
        res.body.length > 2000) {
      print('  warning: resposta menciona bag_orders_json grande');
    }
    return true;
  } catch (e) {
    print('  $e');
    return false;
  }
}
