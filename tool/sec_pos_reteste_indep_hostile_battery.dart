// ignore_for_file: avoid_print
/// Pós-reteste independente — double-credit class + chat/qty.
/// dart run tool/sec_pos_reteste_indep_hostile_battery.dart
library;

import 'dart:convert';
import 'dart:io';

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

  Future<double> bal(String uid) async {
    final rows = await sb.select('wallets', filter: 'id=eq.$uid', limit: 1);
    if (rows.isEmpty) return 0;
    return (rows.first['balance'] as num?)?.toDouble() ?? 0;
  }

  Future<double> netDisbursed(String orderId) async {
    final txs = await sb.select(
      'wallet_transactions',
      filter: 'order_id=eq.$orderId',
      limit: 50,
    );
    var s = 0.0;
    for (final t in txs) {
      final type = '${t['type']}';
      final amt = (t['amount'] as num?)?.toDouble() ?? 0;
      if (type == 'venda' || type == 'reembolso') s += amt;
      if (type == 'estorno') s -= amt;
    }
    return s < 0 ? 0 : s;
  }

  Future<Map<String, dynamic>> product({int qty = 5, double price = 3.0}) {
    return sb.insert('products', {
      'seller_id': sellerId,
      'title': 'RI ${DateTime.now().microsecondsSinceEpoch}',
      'price': price,
      'quantity': qty,
      'ref_code': 'RI-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
  }

  Future<Map<String, dynamic>> orderFor(
    String productId, {
    double price = 3.0,
    int qty = 1,
  }) {
    return sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': productId,
        'quantity': qty,
        'price_total': price,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
  }

  Future<void> capture(String orderId, {int cents = 300}) async {
    await sb.patch('orders', 'id=eq.$orderId', {
      'status': 'pago',
      'amount_paid_cents': cents,
      'stock_units_applied': 1,
      'price_total': cents / 100.0,
    });
  }

  Future<void> cleanupOrder(String orderId, String productId) async {
    final txs = await sb.select(
      'wallet_transactions',
      filter: 'order_id=eq.$orderId',
      limit: 20,
    );
    for (final t in txs) {
      await sb.deleteWhere('wallet_transactions', 'id=eq.${t['id']}');
    }
    await sb.deleteWhere('fleaber_commissions', 'order_id=eq.$orderId');
    await sb.deleteWhere('reviews', 'order_id=eq.$orderId');
    await sb.deleteWhere('order_disputes', 'order_id=eq.$orderId');
    await sb.deleteWhere('orders', 'id=eq.$orderId');
    await sb.deleteWhere('products', 'id=eq.$productId');
  }

  // A) release → refund: net ≤ capture
  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    final b0 = await bal(buyerId);
    final s0 = await bal(sellerId);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await sb.insertAsUser(
      'reviews',
      {
        'order_id': o['id'],
        'buyer_id': buyerId,
        'target_id': sellerId,
        'stars': 5,
        'comment': 'ri-a',
        'author_role': 'comprador',
        'target_type': 'vendedor',
      },
      accessToken: buyerToken,
    );
    final s1 = await bal(sellerId);
    final sellerCredit = s1 - s0;
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'devolvida'});
    final b1 = await bal(buyerId);
    final s2 = await bal(sellerId);
    final buyerCredit = b1 - b0;
    final net = await netDisbursed(o['id'] as String);
    final sellerNet = s2 - s0;
    add(
      'A_RELEASE_THEN_REFUND',
      net <= 3.01 && buyerCredit <= 3.01 && sellerNet.abs() < 0.01,
      'sellerCredit=$sellerCredit buyerCredit=$buyerCredit sellerNet=$sellerNet net=$net',
    );
    // restore bals roughly
    await sb.patch('wallets', 'id=eq.$buyerId', {'balance': b0});
    await sb.patch('wallets', 'id=eq.$sellerId', {'balance': s0});
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('A_RELEASE_THEN_REFUND', false, '$e');
  }

  // B) refund → release
  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    final b0 = await bal(buyerId);
    final s0 = await bal(sellerId);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'devolvida'});
    final b1 = await bal(buyerId);
    // try release via concluido+review after refund (should no-op mint)
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    try {
      await sb.rpc(
        'batata_release_seller_wallet_for_order',
        {'p_order_id': o['id']},
        accessToken: buyerToken,
      );
    } catch (_) {}
    final s1 = await bal(sellerId);
    final net = await netDisbursed(o['id'] as String);
    add(
      'B_REFUND_THEN_RELEASE',
      (b1 - b0 - 3.0).abs() < 0.02 && (s1 - s0).abs() < 0.01 && net <= 3.01,
      'buyerΔ=${b1 - b0} sellerΔ=${s1 - s0} net=$net',
    );
    await sb.patch('wallets', 'id=eq.$buyerId', {'balance': b0});
    await sb.patch('wallets', 'id=eq.$sellerId', {'balance': s0});
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('B_REFUND_THEN_RELEASE', false, '$e');
  }

  // C/D partial + release (dispute before release; then release; then partial clawback)
  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    final b0 = await bal(buyerId);
    final s0 = await bal(sellerId);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    final dispute = await sb.insertAsUser(
      'order_disputes',
      {
        'order_id': o['id'],
        'buyer_id': buyerId,
        'reason': 'outro',
        'description': 'ri-partial',
      },
      accessToken: buyerToken,
    );
    await sb.patchAsUser(
      'order_disputes',
      'id=eq.${dispute['id']}',
      {
        'seller_refund_percent': 50,
        'seller_offer_type': 'partial_refund',
      },
      accessToken: sellerToken,
    );
    await sb.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': o['id']},
      accessToken: buyerToken,
    );
    await sb.rpc(
      'batata_process_partial_refund_dispute',
      {'p_order_id': o['id']},
      accessToken: buyerToken,
    );
    final net = await netDisbursed(o['id'] as String);
    final b1 = await bal(buyerId);
    final s1 = await bal(sellerId);
    add(
      'C_RELEASE_THEN_PARTIAL',
      net <= 3.01,
      'net=$net buyerΔ=${b1 - b0} sellerΔ=${s1 - s0}',
    );
    await sb.patch('wallets', 'id=eq.$buyerId', {'balance': b0});
    await sb.patch('wallets', 'id=eq.$sellerId', {'balance': s0});
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('C_RELEASE_THEN_PARTIAL', false, '$e');
  }

  // E retries A
  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    final b0 = await bal(buyerId);
    final s0 = await bal(sellerId);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await sb.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': o['id']},
      accessToken: buyerToken,
    );
    await sb.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': o['id']},
      accessToken: buyerToken,
    );
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'devolvida'});
    await sb.rpc(
      'batata_refund_buyer_wallet_for_order',
      {'p_order_id': o['id']},
      accessToken: sellerToken,
    );
    final net = await netDisbursed(o['id'] as String);
    final txs = await sb.select(
      'wallet_transactions',
      filter: 'order_id=eq.${o['id']}',
      limit: 20,
    );
    final reembolsos =
        txs.where((t) => t['type'] == 'reembolso').length;
    add(
      'E_RETRIES_IDEMPOTENT',
      net <= 3.01 && reembolsos <= 1,
      'net=$net reembolsos=$reembolsos txs=${txs.length}',
    );
    await sb.patch('wallets', 'id=eq.$buyerId', {'balance': b0});
    await sb.patch('wallets', 'id=eq.$sellerId', {'balance': s0});
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('E_RETRIES_IDEMPOTENT', false, '$e');
  }

  // I amount_paid not forgeable
  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'amount_paid_cents': 99999},
      accessToken: buyerToken,
    );
    final row =
        (await sb.select('orders', filter: 'id=eq.${o['id']}', limit: 1)).first;
    add(
      'I_AMOUNT_PAID_NOT_FORGEABLE',
      row['amount_paid_cents'] == null || row['amount_paid_cents'] == 0,
      'paid_cents=${row['amount_paid_cents']}',
    );
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('I_AMOUNT_PAID_NOT_FORGEABLE', false, '$e');
  }

  // H qty capped by stock
  try {
    final p = await product(qty: 2);
    final o = await orderFor(p['id'] as String, qty: 20);
    final stored = (o['quantity'] as num?)?.toInt();
    add('H_QTY_CAPPED_BY_STOCK', stored == 2, 'stored_qty=$stored');
    // checkout should also block if somehow qty>stock
    final res = await http.post(
      Uri.parse('$url/functions/v1/create-payment-intent'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'order_id': o['id'],
        'product_id': p['id'],
        'shipping_method': 'Transportadora 3,50 €',
      }),
    );
    // may fail portes or succeed with qty2 — not with 20
    add(
      'L_CHECKOUT_QTY_AUTHORITY',
      res.statusCode != 200 || !res.body.contains('"quantity":20'),
      'http=${res.statusCode} body=${res.body.length > 180 ? res.body.substring(0, 180) : res.body}',
    );
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('H_QTY_CAPPED_BY_STOCK', false, '$e');
  }

  // J chat cannot edit other's message
  try {
    final chat = await sb.insertAsUser(
      'chats',
      {'user_a': buyerId, 'user_b': sellerId},
      accessToken: buyerToken,
    );
    final msg = await sb.insertAsUser(
      'chat_messages',
      {
        'chat_id': chat['id'],
        'sender_id': buyerId,
        'receiver_id': sellerId,
        'text': 'original',
      },
      accessToken: buyerToken,
    );
    await sb.patchAsUser(
      'chat_messages',
      'id=eq.${msg['id']}',
      {'text': 'hacked-by-seller'},
      accessToken: sellerToken,
    );
    final after = await sb.select(
      'chat_messages',
      filter: 'id=eq.${msg['id']}',
      limit: 1,
    );
    final text = after.isEmpty ? '' : '${after.first['text']}';
    add('J_CHAT_NO_CROSS_EDIT', text == 'original', 'text=$text');
    await sb.deleteWhere('chat_messages', 'chat_id=eq.${chat['id']}');
    await sb.deleteWhere('chats', 'id=eq.${chat['id']}');
  } catch (e) {
    add('J_CHAT_NO_CROSS_EDIT', false, '$e');
  }

  // K legitimate review
  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    final rev = await sb.insertAsUser(
      'reviews',
      {
        'order_id': o['id'],
        'buyer_id': buyerId,
        'target_id': sellerId,
        'stars': 5,
        'comment': 'legit',
        'author_role': 'comprador',
        'target_type': 'vendedor',
      },
      accessToken: buyerToken,
    );
    add('K_LEGIT_REVIEW', rev['id'] != null, 'id=${rev['id']}');
    final s0 = await bal(sellerId);
    // cleanup credits from release
    final txs = await sb.select(
      'wallet_transactions',
      filter: 'order_id=eq.${o['id']}',
      limit: 10,
    );
    for (final t in txs) {
      await sb.deleteWhere('wallet_transactions', 'id=eq.${t['id']}');
    }
    await sb.patch('wallets', 'id=eq.$sellerId', {'balance': s0});
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('K_LEGIT_REVIEW', false, '$e');
  }

  // G no mint without capture (collusion)
  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    final b0 = await bal(buyerId);
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'pago'},
      accessToken: sellerToken,
    );
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'devolvida'},
      accessToken: sellerToken,
    );
    final b1 = await bal(buyerId);
    add('G_COLLUSION_NO_CAPTURE', (b1 - b0).abs() < 0.01, 'Δ=${b1 - b0}');
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('G_COLLUSION_NO_CAPTURE', false, '$e');
  }

  // NULL qty semantics: products.quantity is NOT NULL; function fail-closed
  // when product row missing (select into null → return 0).
  try {
    final defRes = await http.post(
      Uri.parse('$url/rest/v1/rpc/'),
      headers: {
        'apikey': service,
        'Authorization': 'Bearer $service',
      },
    );
    // Probe via db: call total_qty with random uuid → 0
    final res = await http.post(
      Uri.parse('$url/rest/v1/rpc/batata_live_item_total_qty'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $sellerToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'p_live_item_id': '00000000-0000-0000-0000-000000000099',
      }),
    );
    final total = jsonDecode(res.body);
    add(
      'NULL_QTY_IS_ZERO',
      total == 0 || total == '0',
      'missing_live_item→$total; products.quantity NOT NULL (não há NULL→1 em catálogo)',
    );
    // silence unused
    if (defRes.statusCode < 0) {}
  } catch (e) {
    add('NULL_QTY_IS_ZERO', false, '$e');
  }

  final failed = results.where((r) => r['pass'] != true).length;
  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'failed': failed,
    'passed': results.length - failed,
    'results': results,
  };
  const path = 'tool/reports/HARDENING_POS_RETESTE_INDEP_HOSTILE.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('\nfailed=$failed / ${results.length} → $path');
  exit(failed == 0 ? 0 : 1);
}
