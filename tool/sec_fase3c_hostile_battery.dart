// ignore_for_file: avoid_print
/// Fase 3C — matriz adversarial autoridade financeira + authz crítica.
/// dart run tool/sec_fase3c_hostile_battery.dart
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

  // User C (estranho) — criar se necessário
  final strangerEmail =
      'fase3c.stranger.${DateTime.now().millisecondsSinceEpoch}@axinoquaa.pt';
  const strangerPass = 'testeteste';
  String strangerId = '';
  String strangerToken = '';
  try {
    final created = await http.post(
      Uri.parse('$url/auth/v1/admin/users'),
      headers: {
        'apikey': service,
        'Authorization': 'Bearer $service',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': strangerEmail,
        'password': strangerPass,
        'email_confirm': true,
      }),
    );
    final body = jsonDecode(created.body);
    strangerId = (body is Map ? body['id'] : null)?.toString() ?? '';
    if (strangerId.isEmpty) {
      throw StateError('create stranger: ${created.statusCode} ${created.body}');
    }
    try {
      await sb.insert('profiles', {
        'id': strangerId,
        'full_name': 'Fase3C Stranger',
        'user_type': 'comprador',
      });
    } catch (_) {
      // profile may already exist via auth trigger
    }
  } catch (e) {
    stderr.writeln('stranger create warn: $e');
  }
  if (strangerId.isEmpty) {
    throw StateError('failed to provision stranger user');
  }
  strangerToken = await sb.signIn(email: strangerEmail, password: strangerPass);

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

  Future<Map<String, dynamic>> makeProduct({int qty = 3, double price = 4.5}) async {
    return sb.insert('products', {
      'seller_id': sellerId,
      'title': '3C ${DateTime.now().microsecondsSinceEpoch}',
      'price': price,
      'quantity': qty,
      'ref_code': '3C-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
  }

  Future<Map<String, dynamic>> makeOrder({
    required String productId,
    String? token,
    double price = 4.5,
    int qty = 1,
    String method = 'MB WAY',
    String status = 'reserva_pendente',
  }) async {
    return sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': productId,
        'quantity': qty,
        'price_total': price,
        'status': status,
        'payment_method': method,
      },
      accessToken: token ?? buyerToken,
    );
  }

  // ========== P0-01: seller pago → devolvida sem amount_paid_cents ==========
  // JWT seller já não fabrica devolvida sem disputa (DC-reauditoria).
  // Mint/stock: service_role simula finalize legítimo.
  try {
    final p = await makeProduct(qty: 2, price: 7.77);
    final o = await makeOrder(productId: p['id'] as String, price: 7.77);
    final b0 = await bal(buyerId);
    final s0 = await bal(sellerId);
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'pago'},
      accessToken: sellerToken,
    );
    var afterPago = await sb.select('orders', filter: 'id=eq.${o['id']}', limit: 1);
    final statusPago = afterPago.first['status'];
    final applied = afterPago.first['stock_units_applied'];

    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'devolvida'},
      accessToken: sellerToken,
    );
    final afterJwt = await sb.select('orders', filter: 'id=eq.${o['id']}', limit: 1);
    final jwtBlocked = afterJwt.first['status'] != 'devolvida';

    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'devolvida'});
    afterPago = await sb.select('orders', filter: 'id=eq.${o['id']}', limit: 1);
    final b1 = await bal(buyerId);
    final s1 = await bal(sellerId);
    final prod = await sb.select('products', filter: 'id=eq.${p['id']}', limit: 1);
    final qtyAfter = (prod.first['quantity'] as num?)?.toInt();
    final noMint = (b1 - b0).abs() < 0.01 && (s1 - s0).abs() < 0.01;
    final stockOk = qtyAfter == 2; // restored on devolvida
    add(
      'P0_01_DEVOLVIDA_NO_MINT',
      jwtBlocked &&
          noMint &&
          statusPago == 'pago' &&
          afterPago.first['status'] == 'devolvida',
      'jwtBlocked=$jwtBlocked pago=$statusPago applied=$applied '
          'devolvida=${afterPago.first['status']} '
          'Δbuyer=${b1 - b0} Δseller=${s1 - s0} qty=$qtyAfter stockOk=$stockOk',
    );
    if (!stockOk) {
      add('P1_04_DEVOLVIDA_RESTORE', false, 'qty=$qtyAfter expected 2');
    } else {
      add('P1_04_DEVOLVIDA_RESTORE', true, 'qty restored to 2');
    }
    await sb.deleteWhere('orders', 'id=eq.${o['id']}');
    await sb.deleteWhere('products', 'id=eq.${p['id']}');
  } catch (e) {
    add('P0_01_DEVOLVIDA_NO_MINT', false, '$e');
  }

  // ========== P0-01: concluido + review sem captura ==========
  try {
    final p = await makeProduct(qty: 2, price: 6.5);
    final o = await makeOrder(productId: p['id'] as String, price: 6.5);
    final s0 = await bal(sellerId);
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'pago'},
      accessToken: sellerToken,
    );
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'concluido'},
      accessToken: buyerToken,
    );
    var released = false;
    try {
      await sb.insertAsUser(
        'reviews',
        {
          'order_id': o['id'],
          'buyer_id': buyerId,
          'target_id': sellerId,
          'stars': 5,
          'comment': '3c mint probe',
          'author_role': 'comprador',
          'target_type': 'vendedor',
        },
        accessToken: buyerToken,
      );
      released = true;
    } catch (_) {
      // may still insert but not mint
      released = true;
    }
    // retry release RPC
    try {
      await sb.rpc(
        'batata_release_seller_wallet_for_order',
        {'p_order_id': o['id']},
        accessToken: buyerToken,
      );
    } catch (_) {}
    final s1 = await bal(sellerId);
    final order = (await sb.select('orders', filter: 'id=eq.${o['id']}', limit: 1)).first;
    add(
      'P0_01_REVIEW_NO_MINT',
      (s1 - s0).abs() < 0.01,
      'Δseller=${s1 - s0} release_at=${order['wallet_release_processed_at']} review=$released',
    );
    await sb.deleteWhere('reviews', 'order_id=eq.${o['id']}');
    await sb.deleteWhere('orders', 'id=eq.${o['id']}');
    await sb.deleteWhere('products', 'id=eq.${p['id']}');
  } catch (e) {
    add('P0_01_REVIEW_NO_MINT', false, '$e');
  }

  // ========== P0-02: buyer forja % disputa ==========
  try {
    final p = await makeProduct(price: 9.5);
    final o = await makeOrder(productId: p['id'] as String, price: 9.5);
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'pago'},
      accessToken: sellerToken,
    );
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'concluido'},
      accessToken: buyerToken,
    );
    final b0 = await bal(buyerId);
    Map<String, dynamic>? dispute;
    try {
      dispute = await sb.insertAsUser(
        'order_disputes',
        {
          'order_id': o['id'],
          'buyer_id': buyerId,
          'reason': 'outro',
          'description': '3c forge percent',
          'seller_refund_percent': 100,
          'seller_offer_type': 'partial_refund',
        },
        accessToken: buyerToken,
      );
    } catch (e) {
      add('P0_02_BUYER_FORGE_PERCENT_STRIP', true, 'insert blocked/stripped: $e');
    }
    if (dispute != null) {
      final pct = dispute['seller_refund_percent'];
      final offer = dispute['seller_offer_type'];
      final setBy = dispute['seller_offer_set_by'];
      final stripped = pct == null && (offer == null || '$offer'.isEmpty);
      add(
        'P0_02_BUYER_FORGE_PERCENT_STRIP',
        stripped && setBy == null,
        'pct=$pct offer=$offer set_by=$setBy',
      );
    }
    var rpcBlocked = false;
    String rpcDetail = '';
    try {
      await sb.rpc(
        'batata_process_partial_refund_dispute',
        {'p_order_id': o['id'], 'p_refund_percent': 100},
        accessToken: buyerToken,
      );
    } catch (e) {
      rpcBlocked = true;
      rpcDetail = '$e';
    }
    final b1 = await bal(buyerId);
    add(
      'P0_02_RPC_NO_MINT',
      rpcBlocked && (b1 - b0).abs() < 0.01,
      'blocked=$rpcBlocked Δ=${b1 - b0} $rpcDetail',
    );
    if (dispute != null) {
      await sb.deleteWhere('order_disputes', 'id=eq.${dispute['id']}');
    }
    await sb.deleteWhere('orders', 'id=eq.${o['id']}');
    await sb.deleteWhere('products', 'id=eq.${p['id']}');
  } catch (e) {
    add('P0_02_BUYER_FORGE_PERCENT_STRIP', false, '$e');
  }

  // ========== P0-02 collusion: seller offers on unpaid (no amount_paid) ==========
  try {
    final p = await makeProduct(price: 8);
    final o = await makeOrder(productId: p['id'] as String, price: 8);
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'pago'},
      accessToken: sellerToken,
    );
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'concluido'},
      accessToken: buyerToken,
    );
    final dispute = await sb.insertAsUser(
      'order_disputes',
      {
        'order_id': o['id'],
        'buyer_id': buyerId,
        'reason': 'outro',
        'description': '3c collusion',
      },
      accessToken: buyerToken,
    );
    await sb.patchAsUser(
      'order_disputes',
      'id=eq.${dispute['id']}',
      {
        'seller_refund_percent': 100,
        'seller_offer_type': 'partial_refund',
      },
      accessToken: sellerToken,
    );
    final b0 = await bal(buyerId);
    var blocked = false;
    String detail = '';
    try {
      await sb.rpc(
        'batata_process_partial_refund_dispute',
        {'p_order_id': o['id']},
        accessToken: buyerToken,
      );
    } catch (e) {
      blocked = true;
      detail = '$e';
    }
    final b1 = await bal(buyerId);
    add(
      'P0_02_COLLUSION_UNPAID_NO_MINT',
      blocked && (b1 - b0).abs() < 0.01,
      'blocked=$blocked Δ=${b1 - b0} $detail',
    );
    await sb.deleteWhere('order_disputes', 'id=eq.${dispute['id']}');
    await sb.deleteWhere('orders', 'id=eq.${o['id']}');
    await sb.deleteWhere('products', 'id=eq.${p['id']}');
  } catch (e) {
    add('P0_02_COLLUSION_UNPAID_NO_MINT', false, '$e');
  }

  // ========== Stripe path positive: amount_paid_cents allows wallet base ==========
  try {
    final p = await makeProduct(qty: 2, price: 5.9);
    final o = await makeOrder(
      productId: p['id'] as String,
      price: 5.9,
      method: 'Pagamento na app',
    );
    // service settle-like: pago + amount_paid_cents
    await sb.patch('orders', 'id=eq.${o['id']}', {
      'status': 'pago',
      'amount_paid_cents': 590,
      'stock_units_applied': 1,
    });
    // consume stock manually to match claim
    await sb.patch('products', 'id=eq.${p['id']}', {'quantity': 1});
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'devolvida'});
    final bRows = await sb.select(
      'wallet_transactions',
      filter: 'order_id=eq.${o['id']}&type=eq.reembolso',
      limit: 5,
    );
    final credited = bRows.isNotEmpty &&
        ((bRows.first['amount'] as num?)?.toDouble() ?? 0) == 5.9;
    add(
      'POS_STRIPE_DEVOLVIDA_CREDITS',
      credited,
      'txs=${bRows.length} amount=${bRows.isEmpty ? null : bRows.first['amount']}',
    );
    // cleanup credit
    for (final t in bRows) {
      await sb.deleteWhere('wallet_transactions', 'id=eq.${t['id']}');
    }
    final bw = await bal(buyerId);
    await sb.patch('wallets', 'id=eq.$buyerId', {
      'balance': bw >= 5.9 ? bw - 5.9 : bw,
    });
    await sb.deleteWhere('orders', 'id=eq.${o['id']}');
    await sb.deleteWhere('products', 'id=eq.${p['id']}');
  } catch (e) {
    add('POS_STRIPE_DEVOLVIDA_CREDITS', false, '$e');
  }

  // ========== P1-01 chat isolation ==========
  try {
    final chat = await sb.insertAsUser(
      'chats',
      {
        'user_a': buyerId,
        'user_b': sellerId,
      },
      accessToken: buyerToken,
    );
    final msg = await sb.insertAsUser(
      'chat_messages',
      {
        'chat_id': chat['id'],
        'sender_id': buyerId,
        'receiver_id': sellerId,
        'text': '3c hello',
      },
      accessToken: buyerToken,
    );
    // stranger select
    var strangerSee = true;
    try {
      final rows = await sb.selectAsUser(
        'chats',
        accessToken: strangerToken,
        filter: 'id=eq.${chat['id']}',
        limit: 5,
      );
      strangerSee = rows.isNotEmpty;
    } catch (_) {
      strangerSee = false;
    }
    // spoof sender
    var spoofOk = false;
    try {
      final spoof = await sb.insertAsUser(
        'chat_messages',
        {
          'chat_id': chat['id'],
          'sender_id': sellerId,
          'receiver_id': buyerId,
          'text': 'spoof',
        },
        accessToken: buyerToken,
      );
      spoofOk = spoof['sender_id'] == sellerId;
    } catch (_) {
      spoofOk = false;
    }
    // stranger insert
    var strangerInsert = false;
    try {
      await sb.insertAsUser(
        'chat_messages',
        {
          'chat_id': chat['id'],
          'sender_id': strangerId,
          'text': 'intrude',
        },
        accessToken: strangerToken,
      );
      strangerInsert = true;
    } catch (_) {
      strangerInsert = false;
    }
    add(
      'P1_01_CHAT_ISOLATION',
      !strangerSee && !spoofOk && !strangerInsert && msg['sender_id'] == buyerId,
      'strangerSee=$strangerSee spoof=$spoofOk strangerIns=$strangerInsert',
    );
    await sb.deleteWhere('chat_messages', 'chat_id=eq.${chat['id']}');
    await sb.deleteWhere('chats', 'id=eq.${chat['id']}');
  } catch (e) {
    add('P1_01_CHAT_ISOLATION', false, '$e');
  }

  // ========== P1-02 review cross-order ==========
  try {
    final p = await makeProduct();
    final oOwn = await makeOrder(productId: p['id'] as String);
    final oOther = await sb.insert('orders', {
      'buyer_id': strangerId,
      'seller_id': sellerId,
      'product_id': p['id'],
      'quantity': 1,
      'price_total': 1,
      'status': 'concluido',
      'payment_method': 'MB WAY',
    });
    await sb.patchAsUser(
      'orders',
      'id=eq.${oOwn['id']}',
      {'status': 'pago'},
      accessToken: sellerToken,
    );
    await sb.patchAsUser(
      'orders',
      'id=eq.${oOwn['id']}',
      {'status': 'concluido'},
      accessToken: buyerToken,
    );
    var crossBlocked = false;
    try {
      await sb.insertAsUser(
        'reviews',
        {
          'order_id': oOther['id'],
          'buyer_id': strangerId,
          'target_id': sellerId,
          'stars': 5,
          'comment': 'cross',
          'author_role': 'comprador',
        },
        accessToken: buyerToken,
      );
    } catch (_) {
      crossBlocked = true;
    }
    add('P1_02_REVIEW_CROSS_ORDER', crossBlocked, 'blocked=$crossBlocked');
    await sb.deleteWhere('orders', 'id=eq.${oOwn['id']}');
    await sb.deleteWhere('orders', 'id=eq.${oOther['id']}');
    await sb.deleteWhere('products', 'id=eq.${p['id']}');
  } catch (e) {
    add('P1_02_REVIEW_CROSS_ORDER', false, '$e');
  }

  // ========== P1-03 price forge does not mint ==========
  try {
    final p = await makeProduct(price: 10);
    final o = await makeOrder(productId: p['id'] as String, price: 777.77);
    final stored = (o['price_total'] as num?)?.toDouble();
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
    add(
      'P1_03_FORGED_PRICE_NO_WALLET',
      (b1 - b0).abs() < 0.01,
      'stored=$stored Δ=${b1 - b0}',
    );
    await sb.deleteWhere('orders', 'id=eq.${o['id']}');
    await sb.deleteWhere('products', 'id=eq.${p['id']}');
  } catch (e) {
    add('P1_03_FORGED_PRICE_NO_WALLET', false, '$e');
  }

  // ========== P1-05 qty 0 ==========
  try {
    final p = await makeProduct(qty: 1);
    final live = await sb.insert('lives', {
      'vendedor_id': sellerId,
      'seller_id': sellerId,
      'title': '3C qty0',
      'status': 'ended',
      'is_active': false,
    });
    final li = await sb.insert('live_items', {
      'live_id': live['id'],
      'product_id': p['id'],
      'item_kind': 'marketplace_product',
      'title': 'qty0',
      'ref_code': '3CQTY0-${DateTime.now().microsecondsSinceEpoch}',
      'status': 'available',
    });
    await sb.patch('products', 'id=eq.${p['id']}', {'quantity': 0});
    final res = await http.post(
      Uri.parse('$url/rest/v1/rpc/batata_live_item_total_qty'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $sellerToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'p_live_item_id': li['id']}),
    );
    final total = jsonDecode(res.body);
    final ok = total == 0 || total == '0';
    add('P1_05_QTY0_NOT_ONE', ok, 'total_qty=$total http=${res.statusCode}');
    await sb.deleteWhere('live_items', 'id=eq.${li['id']}');
    await sb.deleteWhere('lives', 'id=eq.${live['id']}');
    await sb.deleteWhere('products', 'id=eq.${p['id']}');
  } catch (e) {
    add('P1_05_QTY0_NOT_ONE', false, '$e');
  }

  // ========== Retry idempotency devolvida ==========
  try {
    final p = await makeProduct(qty: 2, price: 3);
    final o = await makeOrder(productId: p['id'] as String, price: 3);
    await sb.patch('orders', 'id=eq.${o['id']}', {
      'status': 'pago',
      'amount_paid_cents': 300,
      'stock_units_applied': 1,
    });
    await sb.patch('products', 'id=eq.${p['id']}', {'quantity': 1});
    final b0 = await bal(buyerId);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'devolvida'});
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'devolvida'});
    try {
      await sb.rpc(
        'batata_refund_buyer_wallet_for_order',
        {'p_order_id': o['id']},
        accessToken: sellerToken,
      );
    } catch (_) {}
    final b1 = await bal(buyerId);
    final txs = await sb.select(
      'wallet_transactions',
      filter: 'order_id=eq.${o['id']}&type=eq.reembolso',
      limit: 5,
    );
    final prod = await sb.select('products', filter: 'id=eq.${p['id']}', limit: 1);
    add(
      'RETRY_DEVOLVIDA_IDEMPOTENT',
      txs.length == 1 &&
          (b1 - b0 - 3.0).abs() < 0.01 &&
          (prod.first['quantity'] as num?)?.toInt() == 2,
      'txs=${txs.length} Δ=${b1 - b0} qty=${prod.first['quantity']}',
    );
    for (final t in txs) {
      await sb.deleteWhere('wallet_transactions', 'id=eq.${t['id']}');
    }
    await sb.patch('wallets', 'id=eq.$buyerId', {'balance': b0});
    await sb.deleteWhere('orders', 'id=eq.${o['id']}');
    await sb.deleteWhere('products', 'id=eq.${p['id']}');
  } catch (e) {
    add('RETRY_DEVOLVIDA_IDEMPOTENT', false, '$e');
  }

  // cleanup stranger
  try {
    await http.delete(
      Uri.parse('$url/auth/v1/admin/users/$strangerId'),
      headers: {
        'apikey': service,
        'Authorization': 'Bearer $service',
      },
    );
  } catch (_) {}

  final failed = results.where((r) => r['pass'] != true).length;
  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'failed': failed,
    'passed': results.length - failed,
    'results': results,
  };
  final path = 'tool/reports/HARDENING_FASE_3C_HOSTILE.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('\nfailed=$failed / ${results.length} → $path');
  exit(failed == 0 ? 0 : 1);
}
