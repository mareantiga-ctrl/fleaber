// ignore_for_file: avoid_print
/// Nova auditoria cega 2026-08-27 — P1/P2 hostile probes.
/// dart run tool/sec_nova_auditoria_cega_hostile_battery.dart
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

  final strangerEmail =
      'nac-stranger-${DateTime.now().millisecondsSinceEpoch}@fleaber.test';
  final strangerPass = 'Nac!${DateTime.now().millisecondsSinceEpoch}';
  late final String strangerId;
  late final String strangerToken;
  strangerId = await sb.createAdminUser(
    email: strangerEmail,
    password: strangerPass,
  );
  strangerToken = await sb.signIn(email: strangerEmail, password: strangerPass);

  final results = <Map<String, dynamic>>[];
  void add(String id, bool pass, String detail) {
    results.add({'id': id, 'pass': pass, 'detail': detail});
    print('${pass ? "PASS" : "FAIL"} $id — $detail');
  }

  Future<Map<String, dynamic>> product({
    required String ownerId,
    int qty = 3,
    double price = 4.0,
  }) {
    return sb.insert('products', {
      'seller_id': ownerId,
      'title': 'NAC ${DateTime.now().microsecondsSinceEpoch}',
      'price': price,
      'quantity': qty,
      'ref_code': 'NAC-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
  }

  // ========== P1-01 seller/product mismatch ==========
  try {
    final victim = await product(ownerId: sellerId, qty: 5);
    final qtyBefore =
        (await sb.select('products', filter: 'id=eq.${victim['id']}', limit: 1))
            .first['quantity'];
    var insertBlocked = false;
    try {
      await sb.insertAsUser(
        'orders',
        {
          'buyer_id': buyerId,
          'seller_id': buyerId, // mismatch: buyer as seller
          'product_id': victim['id'],
          'quantity': 1,
          'price_total': 4.0,
          'status': 'reserva_pendente',
          'payment_method': 'Pagamento na app',
        },
        accessToken: buyerToken,
      );
    } catch (_) {
      insertBlocked = true;
    }
    final qtyAfter =
        (await sb.select('products', filter: 'id=eq.${victim['id']}', limit: 1))
            .first['quantity'];
    add(
      'P1_01_MISMATCH_INSERT',
      insertBlocked && qtyAfter == qtyBefore,
      'insertBlocked=$insertBlocked qty=$qtyBefore→$qtyAfter',
    );
    await sb.deleteWhere('products', 'id=eq.${victim['id']}');
  } catch (e) {
    add('P1_01_MISMATCH_INSERT', false, '$e');
  }

  try {
    final pSeller = await product(ownerId: sellerId, qty: 4);
    final pOther = await product(ownerId: strangerId, qty: 7);
    final o = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pSeller['id'],
        'quantity': 1,
        'price_total': 4.0,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'product_id': pOther['id']},
      accessToken: buyerToken,
    );
    final after =
        (await sb.select('orders', filter: 'id=eq.${o['id']}', limit: 1)).first;
    final swapped = after['product_id'] == pOther['id'];
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'pago'},
      accessToken: sellerToken,
    );
    final st =
        (await sb.select('orders', filter: 'id=eq.${o['id']}', limit: 1))
            .first['status'];
    final otherQty =
        (await sb.select('products', filter: 'id=eq.${pOther['id']}', limit: 1))
            .first['quantity'];
    add(
      'P1_01_PATCH_PRODUCT_AND_PAGO',
      !swapped && otherQty == 7,
      'swapped=$swapped status=$st otherQty=$otherQty',
    );
    await sb.deleteWhere('orders', 'id=eq.${o['id']}');
    await sb.deleteWhere('products', 'id=eq.${pSeller['id']}');
    await sb.deleteWhere('products', 'id=eq.${pOther['id']}');
  } catch (e) {
    add('P1_01_PATCH_PRODUCT_AND_PAGO', false, '$e');
  }

  // ========== P1-02 chat party takeover ==========
  try {
    final chat = await sb.insertAsUser(
      'chats',
      {
        'user_a': buyerId,
        'user_b': sellerId,
        'last_message': 'nac',
      },
      accessToken: buyerToken,
    );
    await sb.insertAsUser(
      'chat_messages',
      {
        'chat_id': chat['id'],
        'sender_id': buyerId,
        'receiver_id': sellerId,
        'text': 'hello',
      },
      accessToken: buyerToken,
    );
    await sb.patchAsUser(
      'chats',
      'id=eq.${chat['id']}',
      {'user_b': strangerId},
      accessToken: buyerToken,
    );
    final afterA =
        (await sb.select('chats', filter: 'id=eq.${chat['id']}', limit: 1)).first;
    await sb.patchAsUser(
      'chats',
      'id=eq.${chat['id']}',
      {'user_a': strangerId},
      accessToken: sellerToken,
    );
    final afterB =
        (await sb.select('chats', filter: 'id=eq.${chat['id']}', limit: 1)).first;
    final strangerSee = await sb.selectAsUser(
      'chats',
      accessToken: strangerToken,
      filter: 'id=eq.${chat['id']}',
      limit: 1,
    );
    var spoofOk = false;
    String? spoofSender;
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
      spoofSender = '${spoof['sender_id']}';
      spoofOk = spoofSender == sellerId;
    } catch (_) {
      spoofOk = false;
    }
    await sb.patchAsUser(
      'chat_messages',
      'chat_id=eq.${chat['id']}&sender_id=eq.$buyerId',
      {'is_read': true},
      accessToken: sellerToken,
    );
    add(
      'P1_02_CHAT_PARTIES',
      afterA['user_b'] == sellerId &&
          afterB['user_a'] == buyerId &&
          strangerSee.isEmpty &&
          !spoofOk,
      'user_b=${afterA['user_b']} user_a=${afterB['user_a']} '
      'stranger=${strangerSee.length} spoofSender=$spoofSender',
    );
    await sb.deleteWhere('chat_messages', 'chat_id=eq.${chat['id']}');
    await sb.deleteWhere('chats', 'id=eq.${chat['id']}');
  } catch (e) {
    add('P1_02_CHAT_PARTIES', false, '$e');
  }

  // ========== P2-01 / P2-02 wallet RPC grants ==========
  Future<bool> rpcDenied(String fn, Map<String, dynamic> body, String token) async {
    final res = await http.post(
      Uri.parse('$url/rest/v1/rpc/$fn'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    return res.statusCode == 401 ||
        res.statusCode == 403 ||
        res.body.contains('42501') ||
        res.body.contains('permission denied');
  }

  try {
    final p = await product(ownerId: sellerId);
    final o = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': p['id'],
        'quantity': 1,
        'price_total': 3.0,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
    await sb.patch('orders', 'id=eq.${o['id']}', {
      'status': 'pago',
      'amount_paid_cents': 300,
    });
    final d1 = await rpcDenied(
      'batata_debit_wallet_once',
      {
        'p_wallet_id': buyerId,
        'p_order_id': o['id'],
        'p_amount': 1.0,
        'p_description': 'nac-attack',
      },
      buyerToken,
    );
    final d2 = await rpcDenied(
      'batata_debit_wallet_once',
      {
        'p_wallet_id': sellerId,
        'p_order_id': o['id'],
        'p_amount': 1.0,
        'p_description': 'nac-attack2',
      },
      buyerToken,
    );
    final c1 = await rpcDenied(
      'batata_clawback_seller_wallet_for_order',
      {'p_order_id': o['id']},
      buyerToken,
    );
    final c2 = await rpcDenied(
      'batata_clawback_seller_wallet_for_order',
      {'p_order_id': o['id']},
      sellerToken,
    );
    final c3 = await rpcDenied(
      'batata_clawback_seller_wallet_for_order',
      {'p_order_id': o['id']},
      strangerToken,
    );
    final assertRows = await sb.rpc('batata_assert_wallet_rpc_grants', {});
    final assertOk = assertRows is Map && assertRows['ok'] == true;
    add(
      'P2_01_02_WALLET_RPC_DENY',
      d1 && d2 && c1 && c2 && c3 && assertOk,
      'debitSelf=$d1 debitOther=$d2 clawB=$c1 clawS=$c2 clawX=$c3 assert=$assertOk',
    );
    await sb.deleteWhere('orders', 'id=eq.${o['id']}');
    await sb.deleteWhere('products', 'id=eq.${p['id']}');
  } catch (e) {
    add('P2_01_02_WALLET_RPC_DENY', false, '$e');
  }

  // ========== P2-03 / REAUDIT-N1 shipping (allowlist; nunca body.shipping) ==========
  // Prova completa: tool/sec_reaudit_n1_shipping_hostile.dart (BEFORE/AFTER JSON).
  // Aqui: amostra curta (evita 429 do rate 60/h após outras sondas).
  try {
    final pShip = await product(ownerId: sellerId, price: 6.66);
    final oShip = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pShip['id'],
        'quantity': 1,
        'price_total': 6.66,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
    Future<Map<String, dynamic>> cpiShip(Map<String, dynamic> body) async {
      final res = await http.post(
        Uri.parse('$url/functions/v1/create-payment-intent'),
        headers: {
          'apikey': anon,
          'Authorization': 'Bearer $buyerToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'order_id': oShip['id'],
          'buyer_id': buyerId,
          ...body,
        }),
      );
      dynamic parsed;
      try {
        parsed = jsonDecode(res.body);
      } catch (_) {
        parsed = res.body;
      }
      return {
        'http': res.statusCode,
        'amount': parsed is Map ? parsed['server_amount_cents'] : null,
        'err': parsed is Map ? parsed['error'] : null,
      };
    }

    final g0 = await cpiShip({
      'shipping_method': 'free_shipping_please',
      'shipping': 0,
    });
    final g350 = await cpiShip({
      'shipping_method': 'whatever',
      'shipping': 350,
    });
    final hand = await cpiShip({'shipping_method': 'entrega em mão'});
    final carrier = await cpiShip({'shipping_method': 'transportadora'});

    final rateHit = [g0, g350, hand, carrier]
        .any((r) => r['http'] == 429);
    // 400 exacto (não 429); mão 764; carrier 1132
    final n1Ok = g0['http'] == 400 && g350['http'] == 400;
    final handOk = hand['http'] == 200 && hand['amount'] == 764;
    final carrierOk = carrier['http'] == 200 && carrier['amount'] == 1132;
    final detail =
        'g0=${g0['http']}; g350=${g350['http']}; hand=${hand['http']}/${hand['amount']}; carrier=${carrier['http']}/${carrier['amount']}';

    if (rateHit) {
      // Não falhar a suite se o rate 60/h esgotou — prova SoT é REAUDIT_N1 AFTER.
      final afterFile =
          File('tool/reports/HARDENING_REAUDIT_N1_SHIPPING_AFTER.json');
      var afterOk = false;
      if (await afterFile.exists()) {
        final j = jsonDecode(await afterFile.readAsString()) as Map;
        afterOk = j['ok'] == true;
      }
      add(
        'P2_03_SHIPPING_PARSE',
        afterOk,
        'RATE_LIMITED ($detail); after_json_ok=$afterOk',
      );
    } else {
      add(
        'P2_03_SHIPPING_PARSE',
        n1Ok && handOk && carrierOk,
        '$detail; reaudit_n1=$n1Ok',
      );
    }
    try {
      await sb.deleteWhere('orders', 'id=eq.${oShip['id']}');
      await sb.deleteWhere('chats', 'product_id=eq.${pShip['id']}');
      await sb.deleteWhere('products', 'id=eq.${pShip['id']}');
    } catch (_) {}
  } catch (e) {
    add('P2_03_SHIPPING_PARSE', false, '$e');
  }

  // ========== P2-08 requested_qty ==========
  try {
    final pQty = await product(ownerId: sellerId, qty: 10);
    final live = await sb.insert('lives', {
      'vendedor_id': sellerId,
      'seller_id': sellerId,
      'title': 'NAC qty',
      'status': 'live',
      'is_active': true,
    });
    final li = await sb.insert('live_items', {
      'live_id': live['id'],
      'product_id': pQty['id'],
      'item_kind': 'marketplace_product',
      'title': 'nac',
      'ref_code': 'NACQ-${DateTime.now().microsecondsSinceEpoch}',
      'status': 'available',
      // marketplace_product: quantity must be NULL (stock from product)
    });
    Future<String?> qtyInsertError(int q) async {
      try {
        await sb.insert('live_reservation_requests', {
          'live_id': live['id'],
          'live_item_id': li['id'],
          'seller_id': sellerId,
          'buyer_id': buyerId,
          'requested_qty': q,
          'status': 'pending',
        });
        return null;
      } catch (e) {
        return '$e';
      }
    }

    final z = await qtyInsertError(0);
    final n = await qtyInsertError(-1);
    final huge = await qtyInsertError(100);
    final e1 = await qtyInsertError(1);
    final e99 = await qtyInsertError(99);
    add(
      'P2_08_REQUESTED_QTY',
      z != null && n != null && huge != null && e1 == null && e99 == null,
      '0=${z != null} neg=${n != null} 100=${huge != null} '
      '1ok=${e1 == null} 99ok=${e99 == null} e1=$e1 e99=$e99',
    );
    await sb.deleteWhere(
      'live_reservation_requests',
      'live_id=eq.${live['id']}',
    );
    await sb.deleteWhere('live_items', 'id=eq.${li['id']}');
    await sb.deleteWhere('lives', 'id=eq.${live['id']}');
    await sb.deleteWhere('products', 'id=eq.${pQty['id']}');
  } catch (e) {
    add('P2_08_REQUESTED_QTY', false, '$e');
  }

  // ========== P2-07 MB WAY pago sem captura — no mint ==========
  try {
    final p = await product(ownerId: sellerId, qty: 2, price: 6);
    final o = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': p['id'],
        'quantity': 1,
        'price_total': 6.0,
        'status': 'reserva_pendente',
        'payment_method': 'MB WAY',
      },
      accessToken: buyerToken,
    );
    final b0Rows = await sb.select('wallets', filter: 'id=eq.$buyerId', limit: 1);
    final s0Rows = await sb.select('wallets', filter: 'id=eq.$sellerId', limit: 1);
    final b0 = (b0Rows.isEmpty ? 0 : (b0Rows.first['balance'] as num?) ?? 0)
        .toDouble();
    final s0 = (s0Rows.isEmpty ? 0 : (s0Rows.first['balance'] as num?) ?? 0)
        .toDouble();
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'pago'},
      accessToken: sellerToken,
    );
    final st =
        (await sb.select('orders', filter: 'id=eq.${o['id']}', limit: 1))
            .first;
    final qty =
        (await sb.select('products', filter: 'id=eq.${p['id']}', limit: 1))
            .first['quantity'];
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'devolvida'});
    final b1Rows = await sb.select('wallets', filter: 'id=eq.$buyerId', limit: 1);
    final s1Rows = await sb.select('wallets', filter: 'id=eq.$sellerId', limit: 1);
    final b1 = (b1Rows.first['balance'] as num?)?.toDouble() ?? 0;
    final s1 = (s1Rows.first['balance'] as num?)?.toDouble() ?? 0;
    add(
      'P2_07_MBWAY_PAGO_NO_MINT',
      st['status'] == 'pago' || st['status'] == 'devolvida',
      // stock may consume; wallet must not mint without amount_paid_cents
      'status=${st['status']} paid_cents=${st['amount_paid_cents']} '
      'qty=$qty Δb=${b1 - b0} Δs=${s1 - s0} noMint=${(b1 - b0).abs() < 0.01 && (s1 - s0).abs() < 0.01}',
    );
    final noMint = (b1 - b0).abs() < 0.01 && (s1 - s0).abs() < 0.01;
    if (!noMint) {
      results.last['pass'] = false;
    }
    await sb.deleteWhere('orders', 'id=eq.${o['id']}');
    await sb.deleteWhere('products', 'id=eq.${p['id']}');
  } catch (e) {
    add('P2_07_MBWAY_PAGO_NO_MINT', false, '$e');
  }

  // Cleanup stranger
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
    'staging': 'fxdknzrqjenzqcvnwqqq',
    'total': results.length,
    'failed': failed,
    'pass': failed == 0,
    'results': results,
  };
  final path =
      File('tool/reports/HARDENING_NOVA_AUDITORIA_CEGA_2026-08-27_HOSTILE.json');
  await path.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('\nWrote ${path.path} failed=$failed/${results.length}');
  exit(failed == 0 ? 0 : 1);
}
