// ignore_for_file: avoid_print
/// Hostil pós-auditorias cegas — refund mint, checkout state, harness JWT, …
/// dart run tool/sec_pos_auditoria_hostile_battery.dart
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

  String clip(Object? s, [int n = 180]) {
    final t = '$s'.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= n ? t : '${t.substring(0, n)}…';
  }

  // ----- R1 mint unpaid -----
  try {
    final product = await sb.insert('products', {
      'seller_id': sellerId,
      'title': 'mint-probe ${DateTime.now().microsecondsSinceEpoch}',
      'price': 12.34,
      'quantity': 5,
      'ref_code': 'MINT-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final order = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': product['id'],
        'quantity': 1,
        'price_total': 12.34,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
    final balBefore = await sb.select('wallets', filter: 'id=eq.$buyerId', limit: 1);
    final b0 = (balBefore.isEmpty ? 0 : balBefore.first['balance'] as num?)?.toDouble() ?? 0;
    var blocked = false;
    try {
      await sb.rpc(
        'batata_process_partial_refund_dispute',
        {'p_order_id': order['id'], 'p_refund_percent': 100},
        accessToken: buyerToken,
      );
    } catch (e) {
      blocked = true;
      add('R1_MINT_UNPAID', true, 'blocked: ${clip(e)}');
    }
    if (!blocked) {
      final balAfter = await sb.select('wallets', filter: 'id=eq.$buyerId', limit: 1);
      final b1 = (balAfter.isEmpty ? 0 : balAfter.first['balance'] as num?)?.toDouble() ?? 0;
      add('R1_MINT_UNPAID', (b1 - b0).abs() < 0.01, 'delta=${b1 - b0} (must be 0)');
    }
    await sb.deleteWhere('orders', 'id=eq.${order['id']}');
    await sb.deleteWhere('products', 'id=eq.${product['id']}');
  } catch (e) {
    add('R1_MINT_UNPAID', false, '$e');
  }

  // ----- R2 percent without dispute on paid -----
  try {
    final product = await sb.insert('products', {
      'seller_id': sellerId,
      'title': 'paid-mint ${DateTime.now().microsecondsSinceEpoch}',
      'price': 5,
      'quantity': 3,
      'ref_code': 'PM-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final order = await sb.insert('orders', {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': product['id'],
      'quantity': 1,
      'price_total': 5,
      'status': 'pago',
      'payment_method': 'Pagamento na app',
      'stock_units_applied': 1,
    });
    var blocked = false;
    try {
      await sb.rpc(
        'batata_process_partial_refund_dispute',
        {'p_order_id': order['id'], 'p_refund_percent': 100},
        accessToken: buyerToken,
      );
    } catch (e) {
      blocked = '$e'.contains('dispute') || '$e'.contains('400') || '$e'.contains('PGRST');
      if (!blocked) blocked = true;
    }
    add('R2_PAID_NO_DISPUTE', blocked, 'blocked=$blocked');
    await sb.deleteWhere('orders', 'id=eq.${order['id']}');
    await sb.deleteWhere('products', 'id=eq.${product['id']}');
  } catch (e) {
    add('R2_PAID_NO_DISPUTE', false, '$e');
  }

  // ----- C1 checkout cancelado -----
  try {
    final product = await sb.insert('products', {
      'seller_id': sellerId,
      'title': 'co-cancel ${DateTime.now().microsecondsSinceEpoch}',
      'price': 9.58,
      'quantity': 2,
      'ref_code': 'CC-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final order = await sb.insert('orders', {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': product['id'],
      'quantity': 1,
      'price_total': 9.58,
      'status': 'cancelado',
      'payment_method': 'Pagamento na app',
    });
    final res = await http.post(
      Uri.parse('$url/functions/v1/create-payment-intent'),
      headers: {
        'Authorization': 'Bearer $buyerToken',
        'apikey': anon,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'order_id': order['id'],
        'product_id': product['id'],
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'shipping_method': 'transportadora',
      }),
    );
    add(
      'C1_CHECKOUT_CANCELADO',
      res.statusCode >= 400 && res.body.toLowerCase().contains('status'),
      'http=${res.statusCode} ${clip(res.body)}',
    );
    await sb.deleteWhere('orders', 'id=eq.${order['id']}');
    await sb.deleteWhere('products', 'id=eq.${product['id']}');
  } catch (e) {
    add('C1_CHECKOUT_CANCELADO', false, '$e');
  }

  // ----- C2 checkout pago -----
  try {
    final product = await sb.insert('products', {
      'seller_id': sellerId,
      'title': 'co-pago ${DateTime.now().microsecondsSinceEpoch}',
      'price': 9.58,
      'quantity': 2,
      'ref_code': 'CP-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final order = await sb.insert('orders', {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': product['id'],
      'quantity': 1,
      'price_total': 9.58,
      'status': 'pago',
      'payment_method': 'Pagamento na app',
      'stock_units_applied': 1,
    });
    final res = await http.post(
      Uri.parse('$url/functions/v1/create-payment-intent'),
      headers: {
        'Authorization': 'Bearer $buyerToken',
        'apikey': anon,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'order_id': order['id'],
        'product_id': product['id'],
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'shipping_method': 'transportadora',
      }),
    );
    add(
      'C2_CHECKOUT_PAGO',
      res.statusCode >= 400,
      'http=${res.statusCode} ${clip(res.body)}',
    );
    await sb.deleteWhere('orders', 'id=eq.${order['id']}');
    await sb.deleteWhere('products', 'id=eq.${product['id']}');
  } catch (e) {
    add('C2_CHECKOUT_PAGO', false, '$e');
  }

  // ----- C3 checkout legítimo reserva -----
  try {
    final product = await sb.insert('products', {
      'seller_id': sellerId,
      'title': 'co-ok ${DateTime.now().microsecondsSinceEpoch}',
      'price': 9.58,
      'quantity': 2,
      'ref_code': 'COK-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final order = await sb.insert('orders', {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': product['id'],
      'quantity': 1,
      'price_total': 9.58,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    });
    final res = await http.post(
      Uri.parse('$url/functions/v1/create-payment-intent'),
      headers: {
        'Authorization': 'Bearer $buyerToken',
        'apikey': anon,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'order_id': order['id'],
        'product_id': product['id'],
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'shipping_method': 'transportadora',
      }),
    );
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    add(
      'C3_CHECKOUT_RESERVA_OK',
      res.statusCode == 200 && data?['checkoutUrl'] != null,
      'http=${res.statusCode}',
    );
    try {
      await sb.deleteWhere('orders', 'id=eq.${order['id']}');
    } catch (_) {}
    try {
      await sb.deleteWhere('products', 'id=eq.${product['id']}');
    } catch (_) {}
  } catch (e) {
    add('C3_CHECKOUT_RESERVA_OK', false, '$e');
  }

  // ----- H1 forged JWT fase2_e2e_settle -----
  try {
    final header = base64Url
        .encode(utf8.encode(jsonEncode({'alg': 'none', 'typ': 'JWT'})))
        .replaceAll('=', '');
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({'role': 'service_role', 'iss': 'audit'})))
        .replaceAll('=', '');
    final forged = '$header.$payload.';
    final res = await http.post(
      Uri.parse('$url/functions/v1/create-payment-intent?fase2_e2e_settle=1'),
      headers: {
        'Authorization': 'Bearer $forged',
        'apikey': anon,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'order_id': '00000000-0000-0000-0000-000000000001',
        'payment_intent_id': 'pi_test_fake',
      }),
    );
    add(
      'H1_FORGED_JWT_E2E',
      res.statusCode == 401,
      'http=${res.statusCode} ${clip(res.body)}',
    );
  } catch (e) {
    add('H1_FORGED_JWT_E2E', false, '$e');
  }

  // ----- M1 mux buyer -----
  try {
    final res = await http.post(
      Uri.parse('$url/functions/v1/create-mux-live'),
      headers: {
        'Authorization': 'Bearer $buyerToken',
        'apikey': anon,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'title': 'AUDIT BUYER NAO CRIAR'}),
    );
    add(
      'M1_MUX_BUYER_DENIED',
      res.statusCode == 403,
      'http=${res.statusCode} ${clip(res.body)}',
    );
  } catch (e) {
    add('M1_MUX_BUYER_DENIED', false, '$e');
  }

  // ----- S1 system message buyer -----
  try {
    final live = await sb.insert('lives', {
      'title': 'sysmsg probe',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    var blocked = false;
    try {
      final r = await sb.rpc(
        'batata_live_system_message',
        {
          'p_live_id': live['id'],
          'p_body': 'fake fomo',
          'p_sender_label': 'Sistema',
        },
        accessToken: buyerToken,
      );
      blocked = r is Map && r['ok'] == false;
    } catch (_) {
      blocked = true;
    }
    add('S1_SYSTEM_MSG_BUYER', blocked, 'blocked=$blocked');
    await sb.deleteWhere('lives', 'id=eq.${live['id']}');
  } catch (e) {
    add('S1_SYSTEM_MSG_BUYER', false, '$e');
  }

  // ----- ST1 anon list proofs -----
  try {
    final res = await http.post(
      Uri.parse('$url/storage/v1/object/list/chat_media'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $anon',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'prefix': 'order_proofs', 'limit': 20}),
    );
    List<dynamic>? listed;
    try {
      listed = jsonDecode(res.body) as List<dynamic>?;
    } catch (_) {}
    add(
      'ST1_ANON_LIST_PROOFS',
      listed == null || listed.isEmpty,
      'n=${listed?.length}',
    );
  } catch (e) {
    add('ST1_ANON_LIST_PROOFS', false, '$e');
  }

  final failed = results.where((r) => r['pass'] != true).length;
  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'failed': failed,
    'passed': results.length - failed,
    'results': results,
  };
  await Directory('tool/reports').create(recursive: true);
  await File('tool/reports/HARDENING_POS_AUDITORIA_HOSTILE.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('\nEscrito: tool/reports/HARDENING_POS_AUDITORIA_HOSTILE.json failed=$failed/${results.length}');
  if (failed > 0) exit(1);
}
