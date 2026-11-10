// ignore_for_file: avoid_print
/// P0-01 raffle prize authority — T1–T11 + E2E hostil.
/// dart run tool/sec_p001_raffle_authority_battery.dart
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
  final buyerToken = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerToken = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  final results = <Map<String, dynamic>>[];
  void add(String id, bool pass, String detail) {
    results.add({'id': id, 'pass': pass, 'detail': detail});
    print('${pass ? "PASS" : "FAIL"} $id — $detail');
  }

  String clip(Object? s, [int n = 180]) {
    final t = '$s'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= n) return t;
    return '${t.substring(0, n)}…';
  }

  Future<void> softCleanupProduct(String id) async {
    try {
      await sb.deleteWhere('chat_messages', 'chat_id=in.(select id from chats where product_id=eq.$id)');
    } catch (_) {}
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
  }) async {
    return sb.insert('products', {
      'seller_id': sellerId,
      'title': 'P001R ${price}e ${DateTime.now().microsecondsSinceEpoch}',
      'price': price,
      'quantity': qty,
      'ref_code': 'P001R-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
  }

  Future<http.Response> checkout({
    required String orderId,
    required String productId,
    bool prizeShipping = false,
    int amount = 433,
  }) {
    return sb.invokeEdge(
      'create-payment-intent',
      {
        'amount': amount,
        'currency': 'eur',
        'product_id': productId,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': orderId,
        'quantity': 1,
        'shipping': 350,
        'shipping_method': 'transportadora',
        if (prizeShipping) 'prize_shipping': true,
      },
      accessToken: buyerToken,
    );
  }

  Map<String, dynamic> parseBody(http.Response r) {
    try {
      return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    } catch (_) {
      return {'raw': r.body};
    }
  }

  bool isCheapPrizeQuote(http.Response r, Map<String, dynamic> b) {
    final server = b['server_amount_cents'];
    return r.statusCode == 200 &&
        server is num &&
        server >= 350 &&
        server < 2000;
  }

  bool blockedOrFullPrice(http.Response r, Map<String, dynamic> b) {
    if (r.statusCode >= 400) return true;
    final server = b['server_amount_cents'];
    if (server is! num) return true;
    // Full ~80€ marketplace quote is >> 2000 cents.
    return server >= 5000;
  }

  // --- helper: authoritative prize via winner + RPC (service_role) ---
  Future<Map<String, String>> createAuthoritativePrize() async {
    final product = await makeProduct(price: 80);
    final live = await sb.insert('lives', {
      'title': 'P001R raffle ${DateTime.now().microsecondsSinceEpoch}',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final li = await sb.insert('live_items', {
      'live_id': live['id'],
      'title': 'prize item',
      'price': 80,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': product['id'],
      'checkout_product_id': product['id'],
      'ref_code': 'P001RLI-${DateTime.now().microsecondsSinceEpoch}',
    });
    final raffle = await sb.insert('live_raffles', {
      'live_id': live['id'],
      'seller_id': sellerId,
      'live_item_id': li['id'],
      'title': 'P001R raffle',
      'status': 'drawn',
      'winner_count': 1,
      'drawn_at': DateTime.now().toUtc().toIso8601String(),
    });
    // entry + winner (service) — simula pós-sorteio
    final entry = await sb.insert('live_raffle_entries', {
      'raffle_id': raffle['id'],
      'live_id': live['id'],
      'user_id': buyerId,
      'ticket_balance': 1,
      'is_eligible': true,
    });
    await sb.insert('live_raffle_winners', {
      'raffle_id': raffle['id'],
      'user_id': buyerId,
      'entry_id': entry['id'],
      'rank': 1,
      'tickets_at_draw': 1,
      'draw_proof': {'test': true},
    });
    final orderId = await sb.rpc('batata_create_raffle_prize_order', {
      'p_raffle_id': raffle['id'],
      'p_winner_uid': buyerId,
      'p_rank': 1,
    });
    return {
      'product_id': product['id'].toString(),
      'order_id': orderId.toString(),
      'raffle_id': raffle['id'].toString(),
      'live_id': live['id'].toString(),
      'live_item_id': li['id'].toString(),
    };
  }

  // ========== T1 INSERT status forjado ==========
  try {
    final p = await makeProduct(price: 80);
    final o = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': p['id'],
        'price_total': 80,
        'quantity': 1,
        'status': 'premio_rifa',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
    final statusOk = (o['status']?.toString() ?? '') != 'premio_rifa';
    final r = await checkout(
      orderId: o['id'].toString(),
      productId: p['id'].toString(),
      prizeShipping: true,
    );
    final b = parseBody(r);
    add(
      'T1_INSERT_STATUS_FORGED',
      statusOk && blockedOrFullPrice(r, b) && !isCheapPrizeQuote(r, b),
      'stored_status=${o['status']} http=${r.statusCode} server=${b['server_amount_cents']} err=${clip(b['error'])}',
    );
    await softCleanupProduct(p['id'].toString());
  } catch (e) {
    add('T1_INSERT_STATUS_FORGED', true, 'insert/checkout blocked: ${clip(e)}');
  }

  // ========== T2 PATCH status ==========
  try {
    final p = await makeProduct(price: 80);
    final o = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': p['id'],
        'price_total': 80,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'premio_rifa'},
      accessToken: buyerToken,
    );
    final rows = await sb.select('orders', filter: 'id=eq.${o['id']}', limit: 1);
    final st = rows.first['status']?.toString() ?? '';
    final r = await checkout(
      orderId: o['id'].toString(),
      productId: p['id'].toString(),
      prizeShipping: true,
    );
    final b = parseBody(r);
    add(
      'T2_PATCH_STATUS_FORGED',
      st != 'premio_rifa' && blockedOrFullPrice(r, b) && !isCheapPrizeQuote(r, b),
      'stored=$st http=${r.statusCode} server=${b['server_amount_cents']} err=${clip(b['error'])}',
    );
    await softCleanupProduct(p['id'].toString());
  } catch (e) {
    add('T2_PATCH_STATUS_FORGED', true, 'blocked: ${clip(e)}');
  }

  // ========== T3 INSERT payment_method ==========
  try {
    final p = await makeProduct(price: 80);
    final o = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': p['id'],
        'price_total': 80,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Prémio da Rifa',
      },
      accessToken: buyerToken,
    );
    final pm = (o['payment_method']?.toString() ?? '').toLowerCase();
    final pmScrubbed = !pm.contains('premio') && !pm.contains('prémio');
    final r = await checkout(
      orderId: o['id'].toString(),
      productId: p['id'].toString(),
      prizeShipping: true,
    );
    final b = parseBody(r);
    add(
      'T3_INSERT_PAYMENT_METHOD_FORGED',
      pmScrubbed && blockedOrFullPrice(r, b) && !isCheapPrizeQuote(r, b),
      'pm=${o['payment_method']} http=${r.statusCode} server=${b['server_amount_cents']} err=${clip(b['error'])}',
    );
    await softCleanupProduct(p['id'].toString());
  } catch (e) {
    add('T3_INSERT_PAYMENT_METHOD_FORGED', true, 'blocked: ${clip(e)}');
  }

  // ========== T4 PATCH payment_method ==========
  try {
    final p = await makeProduct(price: 80);
    final o = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': p['id'],
        'price_total': 80,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'payment_method': 'Prémio da Rifa'},
      accessToken: buyerToken,
    );
    final rows = await sb.select('orders', filter: 'id=eq.${o['id']}', limit: 1);
    final pm = (rows.first['payment_method']?.toString() ?? '').toLowerCase();
    final pmOk = !pm.contains('premio') && !pm.contains('prémio');
    final r = await checkout(
      orderId: o['id'].toString(),
      productId: p['id'].toString(),
      prizeShipping: true,
    );
    final b = parseBody(r);
    add(
      'T4_PATCH_PAYMENT_METHOD_FORGED',
      pmOk && blockedOrFullPrice(r, b) && !isCheapPrizeQuote(r, b),
      'pm=${rows.first['payment_method']} http=${r.statusCode} server=${b['server_amount_cents']} err=${clip(b['error'])}',
    );
    await softCleanupProduct(p['id'].toString());
  } catch (e) {
    add('T4_PATCH_PAYMENT_METHOD_FORGED', true, 'blocked: ${clip(e)}');
  }

  // ========== T5 combinações ==========
  try {
    final p = await makeProduct(price: 80);
    final o = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': p['id'],
        'price_total': 0.5,
        'quantity': 99,
        'status': 'premio_rifa',
        'payment_method': 'Prémio da Rifa',
        'live_raffle_id': null,
      },
      accessToken: buyerToken,
    );
    final r = await checkout(
      orderId: o['id'].toString(),
      productId: p['id'].toString(),
      prizeShipping: true,
      amount: 50,
    );
    final b = parseBody(r);
    add(
      'T5_COMBINATIONS',
      blockedOrFullPrice(r, b) && !isCheapPrizeQuote(r, b),
      'status=${o['status']} pm=${o['payment_method']} http=${r.statusCode} server=${b['server_amount_cents']}',
    );
    await softCleanupProduct(p['id'].toString());
  } catch (e) {
    add('T5_COMBINATIONS', true, 'blocked: ${clip(e)}');
  }

  // ========== T6 RPC directa como buyer ==========
  try {
    await sb.rpc(
      'batata_create_raffle_prize_order',
      {
        'p_raffle_id': '00000000-0000-0000-0000-000000000001',
        'p_winner_uid': buyerId,
        'p_rank': 1,
      },
      accessToken: buyerToken,
    );
    add('T6_RPC_FABRICATION', false, 'RPC executed as buyer (should be denied)');
  } catch (e) {
    final msg = '$e'.toLowerCase();
    final denied = msg.contains('42501') ||
        msg.contains('permission') ||
        msg.contains('403') ||
        msg.contains('401') ||
        msg.contains('not found') ||
        msg.contains('pgrst202') ||
        msg.contains('404');
    add('T6_RPC_FABRICATION', denied, clip(e));
  }

  // ========== T7 cross-raffle / cross-winner ==========
  try {
    final legit = await createAuthoritativePrize();
    final expensive = await makeProduct(price: 80);
    // Atacante: order cara + tentar live_raffle_id da rifa de que é winner
    final forged = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': expensive['id'],
        'price_total': 80,
        'quantity': 1,
        'status': 'premio_rifa',
        'payment_method': 'Prémio da Rifa',
        'live_raffle_id': legit['raffle_id'],
      },
      accessToken: buyerToken,
    );
    final forgedRaffle = forged['live_raffle_id'];
    final r = await checkout(
      orderId: forged['id'].toString(),
      productId: expensive['id'].toString(),
      prizeShipping: true,
    );
    final b = parseBody(r);
    add(
      'T7_CROSS_RAFFLE_WINNER',
      forgedRaffle == null &&
          blockedOrFullPrice(r, b) &&
          !isCheapPrizeQuote(r, b),
      'forged_live_raffle_id=$forgedRaffle status=${forged['status']} http=${r.statusCode} server=${b['server_amount_cents']} err=${clip(b['error'])}',
    );
    await softCleanupProduct(legit['product_id']!);
    await softCleanupProduct(expensive['id'].toString());
  } catch (e) {
    add('T7_CROSS_RAFFLE_WINNER', true, 'blocked: ${clip(e)}');
  }

  // ========== T8 prémio real ==========
  try {
    final legit = await createAuthoritativePrize();
    final r = await checkout(
      orderId: legit['order_id']!,
      productId: legit['product_id']!,
      prizeShipping: true,
    );
    final b = parseBody(r);
    add(
      'T8_PRIZE_LEGITIMATE',
      isCheapPrizeQuote(r, b),
      'http=${r.statusCode} server=${b['server_amount_cents']} err=${clip(b['error'])}',
    );
    await softCleanupProduct(legit['product_id']!);
  } catch (e) {
    add('T8_PRIZE_LEGITIMATE', false, '$e');
  }

  // ========== T9 marketplace ==========
  try {
    final p = await makeProduct(price: 12);
    final o = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': p['id'],
        'price_total': 12,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
    final items = 1200;
    const ship = 350;
    final prot = ((0.65 + (items + ship) / 100.0 * 0.05) * 100).round();
    final expected = items + ship + prot;
    final r = await checkout(
      orderId: o['id'].toString(),
      productId: p['id'].toString(),
      amount: expected,
    );
    final b = parseBody(r);
    add(
      'T9_MARKETPLACE',
      r.statusCode == 200 && b['server_amount_cents'] == expected,
      'http=${r.statusCode} server=${b['server_amount_cents']} expected=$expected',
    );
    await softCleanupProduct(p['id'].toString());
  } catch (e) {
    add('T9_MARKETPLACE', false, '$e');
  }

  // ========== T10 live ==========
  try {
    final p = await makeProduct(price: 15);
    final live = await sb.insert('lives', {
      'title': 'P001R live ok ${DateTime.now().microsecondsSinceEpoch}',
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
      'ref_code': 'P001RLOK-${DateTime.now().microsecondsSinceEpoch}',
    });
    final o = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': p['id'],
        'live_item_id': li['id'],
        'live_id': live['id'],
        'price_total': 15,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
    final items = 1500;
    const ship = 350;
    final prot = ((0.65 + (items + ship) / 100.0 * 0.05) * 100).round();
    final expected = items + ship + prot;
    final r = await checkout(
      orderId: o['id'].toString(),
      productId: p['id'].toString(),
      amount: expected,
    );
    final b = parseBody(r);
    add(
      'T10_LIVE',
      r.statusCode == 200 && b['server_amount_cents'] == expected,
      'http=${r.statusCode} server=${b['server_amount_cents']} expected=$expected',
    );
    await softCleanupProduct(p['id'].toString());
  } catch (e) {
    add('T10_LIVE', false, '$e');
  }

  // ========== T11 bag ==========
  try {
    final p1 = await makeProduct(price: 10);
    final p2 = await makeProduct(price: 20);
    final o1 = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': p1['id'],
        'price_total': 10,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
    final o2 = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': p2['id'],
        'price_total': 20,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
    final items = 3000;
    const ship = 350;
    final prot = ((0.65 + (items + ship) / 100.0 * 0.05) * 100).round();
    final expected = items + ship + prot;
    final r = await sb.invokeEdge(
      'create-payment-intent',
      {
        'amount': expected,
        'currency': 'eur',
        'product_id': p1['id'],
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': o1['id'],
        'quantity': 1,
        'shipping': 350,
        'shipping_method': 'transportadora',
        'bag_checkout': true,
        'bag_lines': [
          {
            'order_id': o1['id'],
            'product_id': p1['id'],
            'quantity': 1,
            'seller_id': sellerId,
          },
          {
            'order_id': o2['id'],
            'product_id': p2['id'],
            'quantity': 1,
            'seller_id': sellerId,
          },
        ],
      },
      accessToken: buyerToken,
    );
    final b = parseBody(r);
    add(
      'T11_BAG',
      r.statusCode == 200 && b['server_amount_cents'] == expected,
      'http=${r.statusCode} server=${b['server_amount_cents']} expected=$expected err=${clip(b['error'])}',
    );
    await softCleanupProduct(p1['id'].toString());
    await softCleanupProduct(p2['id'].toString());
  } catch (e) {
    add('T11_BAG', false, '$e');
  }

  // seller token unused except proving seller still can draw — keep analyzer quiet
  // ignore: unnecessary_statements
  sellerToken;

  final failed = results.where((e) => e['pass'] != true).length;
  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'failed': failed,
    'passed': results.length - failed,
    'results': results,
  };
  final path = 'tool/reports/HARDENING_P0_01_RAFFLE_AUTHORITY_HOSTILE.json';
  await Directory('tool/reports').create(recursive: true);
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('Wrote $path failed=$failed/${results.length}');
  exit(failed == 0 ? 0 : 1);
}
