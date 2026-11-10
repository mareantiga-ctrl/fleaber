// ignore_for_file: avoid_print
/// P0-01 trust boundary â€” product/live/prize/qty/cross-order.
/// dart run tool/sec_p001_trust_boundary_battery.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: service,
  );

  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final buyerEmail = envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final buyerPass = envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD');
  final buyerToken = await sb.signIn(email: buyerEmail, password: buyerPass);

  // Segundo buyer para cross-order (criar se preciso via admin).
  final otherEmail =
      'p001_other_${DateTime.now().millisecondsSinceEpoch}@fleaber.test';
  final otherPass = 'TestP001!${Random().nextInt(99999)}';
  String otherBuyerId;
  String otherToken;
  try {
    otherBuyerId = await sb.createAdminUser(
      email: otherEmail,
      password: otherPass,
    );
    otherToken = await sb.signIn(email: otherEmail, password: otherPass);
  } catch (e) {
    print('WARN other buyer create: $e');
    otherBuyerId = buyerId;
    otherToken = buyerToken;
  }

  final results = <Map<String, dynamic>>[];
  void add(String id, bool pass, String detail) {
    results.add({'id': id, 'pass': pass, 'detail': detail});
    print('${pass ? "PASS" : "FAIL"} $id â€” $detail');
  }

  Future<void> softDeleteProduct(String id) async {
    try {
      await sb.deleteWhere('chats', 'product_id=eq.$id');
    } catch (_) {}
    try {
      await sb.deleteWhere('orders', 'product_id=eq.$id');
    } catch (_) {}
    try {
      await sb.deleteWhere('products', 'id=eq.$id');
    } catch (_) {}
  }

  Future<Map<String, dynamic>> makeProduct({
    required double price,
    int qty = 5,
    String? title,
  }) async {
    return sb.insert('products', {
      'seller_id': sellerId,
      'title': title ?? 'P001 ${price}e ${DateTime.now().microsecondsSinceEpoch}',
      'price': price,
      'quantity': qty,
      'ref_code': 'P001-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
  }

  Future<Map<String, dynamic>> makeOrder({
    required String productId,
    required String buyer,
    int qty = 1,
    String status = 'reserva_pendente',
    String? liveItemId,
    String? paymentMethod,
  }) async {
    return sb.insert('orders', {
      'buyer_id': buyer,
      'seller_id': sellerId,
      'product_id': productId,
      'price_total': 1.0,
      'quantity': qty,
      'status': status,
      'payment_method': paymentMethod ?? 'Pagamento na app',
      if (liveItemId != null) 'live_item_id': liveItemId,
    });
  }

  Future<http.Response> checkout({
    required String accessToken,
    required Map<String, dynamic> body,
  }) {
    return sb.invokeEdge('create-payment-intent', body, accessToken: accessToken);
  }

  Map<String, dynamic> parseBody(http.Response r) {
    try {
      return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    } catch (_) {
      return {'raw': r.body};
    }
  }

  String clip(Object? s, [int n = 160]) {
    final t = '$s'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= n) return t;
    return '${t.substring(0, n)}â€¦';
  }

  // Expected cents: items + ship 3.50 + prot 0.65+5%
  int expectedMarketplace(double unitEur, {int qty = 1, int ship = 350}) {
    final items = (unitEur * qty * 100).round();
    final baseEur = (items + ship) / 100.0;
    final protEur = (0.65 + baseEur * 0.05);
    final prot = (protEur * 100).round();
    return items + ship + prot;
  }

  // --- T1 product_id swap ---
  try {
    final expensive = await makeProduct(price: 80);
    final cheap = await makeProduct(price: 0.5);
    final order = await makeOrder(
      productId: expensive['id'].toString(),
      buyer: buyerId,
    );
    final r = await checkout(
      accessToken: buyerToken,
      body: {
        'amount': 50,
        'currency': 'eur',
        'product_id': cheap['id'].toString(),
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': order['id'].toString(),
        'quantity': 1,
        'shipping': 350,
        'shipping_method': 'transportadora',
      },
    );
    final b = parseBody(r);
    final blocked = r.statusCode >= 400 ||
        (b['error']?.toString().contains('product') ?? false);
    final notCheap = b['server_amount_cents'] != 50 &&
        b['amount_total'] != 50 &&
        (b['server_amount_cents'] == null ||
            (b['server_amount_cents'] as num) > 5000);
    add(
      'T1_PRODUCT_ID_SWAP',
      blocked || notCheap,
      'http=${r.statusCode} server=${b['server_amount_cents']} err=${clip(b['error'])}',
    );
    await sb.deleteWhere('orders', 'id=eq.${order['id']}');
    await softDeleteProduct(expensive['id'].toString());
    await softDeleteProduct(cheap['id'].toString());
  } catch (e) {
    add('T1_PRODUCT_ID_SWAP', false, '$e');
  }

  // --- T2 live_item_id swap ---
  try {
    final expensive = await makeProduct(price: 80);
    final cheap = await makeProduct(price: 1);
    // live item barato noutro produto
    final live = await sb.insert('lives', {
      'title': 'P001 live ${DateTime.now().microsecondsSinceEpoch}',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final cheapItem = await sb.insert('live_items', {
      'live_id': live['id'],
      'title': 'cheap li',
      'price': 1,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': cheap['id'],
      'checkout_product_id': cheap['id'],
      'ref_code': 'P001LI-${DateTime.now().microsecondsSinceEpoch}',
    });
    final order = await makeOrder(
      productId: expensive['id'].toString(),
      buyer: buyerId,
    );
    final r = await checkout(
      accessToken: buyerToken,
      body: {
        'amount': 100,
        'currency': 'eur',
        'product_id': expensive['id'].toString(),
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': order['id'].toString(),
        'live_item_id': cheapItem['id'].toString(),
        'quantity': 1,
        'shipping': 350,
        'shipping_method': 'transportadora',
      },
    );
    final b = parseBody(r);
    final blocked = r.statusCode >= 400;
    final server = b['server_amount_cents'];
    final notCheapLive = server == null || (server is num && server > 5000);
    add(
      'T2_LIVE_ITEM_SWAP',
      blocked || notCheapLive,
      'http=${r.statusCode} server=$server err=${clip(b['error'])}',
    );
    await sb.deleteWhere('orders', 'id=eq.${order['id']}');
    await sb.deleteWhere('live_items', 'id=eq.${cheapItem['id']}');
    await sb.deleteWhere('lives', 'id=eq.${live['id']}');
    await softDeleteProduct(expensive['id'].toString());
    await softDeleteProduct(cheap['id'].toString());
  } catch (e) {
    add('T2_LIVE_ITEM_SWAP', false, '$e');
  }

  // --- T3 prize_shipping forged ---
  try {
    final p = await makeProduct(price: 80);
    final order = await makeOrder(productId: p['id'].toString(), buyer: buyerId);
    final r = await checkout(
      accessToken: buyerToken,
      body: {
        'amount': 443,
        'currency': 'eur',
        'product_id': p['id'].toString(),
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': order['id'].toString(),
        'quantity': 1,
        'shipping': 350,
        'shipping_method': 'transportadora',
        'prize_shipping': true,
      },
    );
    final b = parseBody(r);
    final blocked = r.statusCode >= 400;
    final server = b['server_amount_cents'];
    // Prize-only would be ~443; full 80â‚¬ is much higher.
    final notPrizeOnly =
        server is num && server > 5000 || blocked;
    add(
      'T3_PRIZE_SHIPPING_FORGED',
      blocked || notPrizeOnly,
      'http=${r.statusCode} server=$server err=${clip(b['error'])}',
    );
    await sb.deleteWhere('orders', 'id=eq.${order['id']}');
    await softDeleteProduct(p['id'].toString());
  } catch (e) {
    add('T3_PRIZE_SHIPPING_FORGED', false, '$e');
  }

  // --- T4 underpay amount ---
  try {
    final p = await makeProduct(price: 80);
    final order = await makeOrder(productId: p['id'].toString(), buyer: buyerId);
    final expected = expectedMarketplace(80);
    final r = await checkout(
      accessToken: buyerToken,
      body: {
        'amount': 50,
        'currency': 'eur',
        'product_id': p['id'].toString(),
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': order['id'].toString(),
        'quantity': 1,
        'shipping': 350,
        'shipping_method': 'transportadora',
      },
    );
    final b = parseBody(r);
    final server = b['server_amount_cents'];
    final pass = r.statusCode == 200 && server == expected;
    add(
      'T4_UNDERPAY_AMOUNT',
      pass,
      'http=${r.statusCode} server=$server expected=$expected',
    );
    await sb.deleteWhere('orders', 'id=eq.${order['id']}');
    await softDeleteProduct(p['id'].toString());
  } catch (e) {
    add('T4_UNDERPAY_AMOUNT', false, '$e');
  }

  // --- T5 quantity manipulation ---
  try {
    final p = await makeProduct(price: 10, qty: 20);
    final order = await makeOrder(
      productId: p['id'].toString(),
      buyer: buyerId,
      qty: 1,
    );
    final expected = expectedMarketplace(10, qty: 1);
    final r = await checkout(
      accessToken: buyerToken,
      body: {
        'amount': expectedMarketplace(10, qty: 5),
        'currency': 'eur',
        'product_id': p['id'].toString(),
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': order['id'].toString(),
        'quantity': 5,
        'shipping': 350,
        'shipping_method': 'transportadora',
      },
    );
    final b = parseBody(r);
    final server = b['server_amount_cents'];
    add(
      'T5_QUANTITY_MANIPULATION',
      r.statusCode == 200 && server == expected,
      'http=${r.statusCode} server=$server expectedQty1=$expected',
    );
    await sb.deleteWhere('orders', 'id=eq.${order['id']}');
    await softDeleteProduct(p['id'].toString());
  } catch (e) {
    add('T5_QUANTITY_MANIPULATION', false, '$e');
  }

  // --- T6 cross-order / cross-buyer ---
  try {
    final p = await makeProduct(price: 25);
    final orderOther = await makeOrder(
      productId: p['id'].toString(),
      buyer: otherBuyerId,
    );
    final r = await checkout(
      accessToken: buyerToken,
      body: {
        'amount': 1000,
        'currency': 'eur',
        'product_id': p['id'].toString(),
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': orderOther['id'].toString(),
        'quantity': 1,
        'shipping': 350,
        'shipping_method': 'transportadora',
      },
    );
    final b = parseBody(r);
    final blocked = r.statusCode >= 400;
    add(
      'T6_CROSS_ORDER_BUYER',
      blocked,
      'http=${r.statusCode} err=${clip(b['error'])}',
    );
    await sb.deleteWhere('orders', 'id=eq.${orderOther['id']}');
    await softDeleteProduct(p['id'].toString());
  } catch (e) {
    add('T6_CROSS_ORDER_BUYER', false, '$e');
  }

  // --- T7 rifa: status forjado sem live_raffle_id NÃO é prémio financeiro ---
  try {
    final p = await makeProduct(price: 80);
    final order = await makeOrder(
      productId: p['id'].toString(),
      buyer: buyerId,
      status: 'premio_rifa',
      paymentMethod: 'Prémio da Rifa',
    );
    final r = await checkout(
      accessToken: buyerToken,
      body: {
        'amount': 433,
        'currency': 'eur',
        'product_id': p['id'].toString(),
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': order['id'].toString(),
        'quantity': 1,
        'shipping': 350,
        'shipping_method': 'transportadora',
        'prize_shipping': true,
      },
    );
    final b = parseBody(r);
    final server = b['server_amount_cents'];
    // Sem live_raffle_id+winner: deve rejeitar prize_shipping (não Session a ~433).
    final pass = r.statusCode >= 400 ||
        (server is num && server >= 5000) ||
        (b['error']?.toString().contains('raffle prize') ?? false);
    add(
      'T7_PRIZE_LEGITIMATE',
      pass,
      'http=${r.statusCode} server=$server err=${clip(b['error'])} (forged premio without raffle must fail)',
    );
    await sb.deleteWhere('orders', 'id=eq.${order['id']}');
    await softDeleteProduct(p['id'].toString());
  } catch (e) {
    add('T7_PRIZE_LEGITIMATE', false, '$e');
  }

  // --- T8 marketplace normal ---
  try {
    final p = await makeProduct(price: 12);
    final order = await makeOrder(productId: p['id'].toString(), buyer: buyerId);
    final expected = expectedMarketplace(12);
    final r = await checkout(
      accessToken: buyerToken,
      body: {
        'amount': expected,
        'currency': 'eur',
        'product_id': p['id'].toString(),
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': order['id'].toString(),
        'quantity': 1,
        'shipping': 350,
        'shipping_method': 'transportadora',
      },
    );
    final b = parseBody(r);
    add(
      'T8_MARKETPLACE_NORMAL',
      r.statusCode == 200 && b['server_amount_cents'] == expected,
      'http=${r.statusCode} server=${b['server_amount_cents']} expected=$expected',
    );
    await sb.deleteWhere('orders', 'id=eq.${order['id']}');
    await softDeleteProduct(p['id'].toString());
  } catch (e) {
    add('T8_MARKETPLACE_NORMAL', false, '$e');
  }

  // --- T9 live normal ---
  try {
    final p = await makeProduct(price: 15);
    final live = await sb.insert('lives', {
      'title': 'P001 live ok ${DateTime.now().microsecondsSinceEpoch}',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final li = await sb.insert('live_items', {
      'live_id': live['id'],
      'title': 'live ok',
      'price': 15,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': p['id'],
      'checkout_product_id': p['id'],
      'ref_code': 'P001OK-${DateTime.now().microsecondsSinceEpoch}',
    });
    final order = await makeOrder(
      productId: p['id'].toString(),
      buyer: buyerId,
      liveItemId: li['id'].toString(),
    );
    await sb.patch('orders', 'id=eq.${order['id']}', {
      'live_id': live['id'],
      'live_item_id': li['id'],
    });
    final expected = expectedMarketplace(15);
    final r = await checkout(
      accessToken: buyerToken,
      body: {
        'amount': expected,
        'currency': 'eur',
        'product_id': p['id'].toString(),
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': order['id'].toString(),
        'live_item_id': li['id'].toString(),
        'live_id': live['id'].toString(),
        'quantity': 1,
        'shipping': 350,
        'shipping_method': 'transportadora',
      },
    );
    final b = parseBody(r);
    add(
      'T9_LIVE_NORMAL',
      r.statusCode == 200 && b['server_amount_cents'] == expected,
      'http=${r.statusCode} server=${b['server_amount_cents']} expected=$expected',
    );
    await sb.deleteWhere('orders', 'id=eq.${order['id']}');
    await sb.deleteWhere('live_items', 'id=eq.${li['id']}');
    await sb.deleteWhere('lives', 'id=eq.${live['id']}');
    await softDeleteProduct(p['id'].toString());
  } catch (e) {
    add('T9_LIVE_NORMAL', false, '$e');
  }

  // --- T10 bag/bundle ---
  try {
    final p1 = await makeProduct(price: 10);
    final p2 = await makeProduct(price: 20);
    final o1 = await makeOrder(productId: p1['id'].toString(), buyer: buyerId);
    final o2 = await makeOrder(productId: p2['id'].toString(), buyer: buyerId);
    final items = 1000 + 2000; // 30â‚¬
    final ship = 350;
    final baseEur = (items + ship) / 100.0;
    final prot = ((0.65 + baseEur * 0.05) * 100).round();
    final expected = items + ship + prot;
    final r = await checkout(
      accessToken: buyerToken,
      body: {
        'amount': 50, // hostil
        'currency': 'eur',
        'product_id': p1['id'].toString(),
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': o1['id'].toString(),
        'quantity': 1,
        'shipping': 350,
        'shipping_method': 'transportadora',
        'bag_checkout': true,
        'bag_lines': [
          {
            'order_id': o1['id'],
            'product_id': p2['id'], // swap hostil na line
            'quantity': 99,
            'line_total_cents': 1,
            'seller_id': sellerId,
          },
          {
            'order_id': o2['id'],
            'product_id': p2['id'],
            'quantity': 1,
            'line_total_cents': 1,
            'seller_id': sellerId,
          },
        ],
      },
    );
    final b = parseBody(r);
    // Line 1 product swap should reject OR ignore â†’ if reject, PASS; if ignore use order products â†’ expected
    final pass = (r.statusCode >= 400) ||
        (r.statusCode == 200 && b['server_amount_cents'] == expected);
    add(
      'T10_BAG_BUNDLE',
      pass,
      'http=${r.statusCode} server=${b['server_amount_cents']} expected=$expected err=${clip(b['error'])}',
    );
    await sb.deleteWhere('orders', 'id=eq.${o1['id']}');
    await sb.deleteWhere('orders', 'id=eq.${o2['id']}');
    await softDeleteProduct(p1['id'].toString());
    await softDeleteProduct(p2['id'].toString());
  } catch (e) {
    add('T10_BAG_BUNDLE', false, '$e');
  }

  // Cleanup other user
  try {
    if (otherBuyerId != buyerId) {
      await http.delete(
        Uri.parse('$url/auth/v1/admin/users/$otherBuyerId'),
        headers: {
          'apikey': service,
          'Authorization': 'Bearer $service',
        },
      );
    }
  } catch (_) {}

  final failed = results.where((r) => r['pass'] != true).length;
  final out = {
    'at': DateTime.now().toUtc().toIso8601String(),
    'failed': failed,
    'results': results,
  };
  await Directory('tool/reports').create(recursive: true);
  await File('tool/reports/HARDENING_P0_01_TRUST_BOUNDARY_HOSTILE.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('\nEscrito: tool/reports/HARDENING_P0_01_TRUST_BOUNDARY_HOSTILE.json failed=$failed');
  exit(failed == 0 ? 0 : 1);
}
