// ignore_for_file: avoid_print
/// Testes hostis FASE 2 — oversell / stock atómico / restore.
/// dart run tool/sec_fase2_hostile_battery.dart
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
  final stripeKey = (env['STRIPE_SECRET_KEY'] ?? '').trim();

  final results = <Map<String, dynamic>>[];
  void add(String id, bool pass, String detail) {
    results.add({'id': id, 'pass': pass, 'detail': detail});
    print('${pass ? "PASS" : "FAIL"} $id — $detail');
  }

  Future<Map<String, dynamic>> makeProduct(int qty) async {
    return sb.insert('products', {
      'seller_id': sellerId,
      'title': 'F2 oversell $qty ${DateTime.now().microsecondsSinceEpoch}',
      'price': 5,
      'quantity': qty,
      'ref_code': 'F2-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
  }

  Future<Map<String, dynamic>> makeOrder({
    required String productId,
    required int qty,
    String status = 'reserva_pendente',
  }) async {
    return sb.insert('orders', {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': productId,
      'price_total': 5.0 * qty,
      'quantity': qty,
      'status': status,
      'payment_method': 'Pagamento na app',
    });
  }

  Future<http.Response> patchOrderPago(String orderId) {
    return http.patch(
      Uri.parse('$url/rest/v1/orders?id=eq.$orderId'),
      headers: {
        'apikey': service,
        'Authorization': 'Bearer $service',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      },
      body: jsonEncode({'status': 'pago', 'is_reservation': false}),
    );
  }

  Future<int> productQty(String productId) async {
    final rows = await sb.select(
      'products',
      filter: 'id=eq.$productId',
      limit: 1,
    );
    return (rows.first['quantity'] as num).toInt();
  }

  Future<Map<String, dynamic>?> orderRow(String orderId) async {
    final rows = await sb.select(
      'orders',
      filter: 'id=eq.$orderId',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  // --- TEST 1: última unidade, duas orders ---
  try {
    final p = await makeProduct(1);
    final pid = p['id'].toString();
    final a = await makeOrder(productId: pid, qty: 1);
    final b = await makeOrder(productId: pid, qty: 1);
    final ra = await patchOrderPago(a['id'].toString());
    final rb = await patchOrderPago(b['id'].toString());
    final oa = await orderRow(a['id'].toString());
    final ob = await orderRow(b['id'].toString());
    final qty = await productQty(pid);
    final paid = [
      oa?['status']?.toString().toLowerCase(),
      ob?['status']?.toString().toLowerCase(),
    ].where((s) => s == 'pago').length;
    final oneFail = ra.statusCode >= 400 || rb.statusCode >= 400;
    final pass = paid == 1 && qty == 0 && oneFail;
    add(
      'T1_LAST_UNIT_RACE',
      pass,
      'paid=$paid qty=$qty httpA=${ra.statusCode} httpB=${rb.statusCode} '
      'statusA=${oa?['status']} statusB=${ob?['status']} '
      'err=${_clip(ra.statusCode >= 400 ? ra.body : rb.body)}',
    );
    await sb.deleteWhere('orders', 'product_id=eq.$pid');
    await sb.deleteWhere('products', 'id=eq.$pid');
  } catch (e) {
    add('T1_LAST_UNIT_RACE', false, '$e');
  }

  // --- TEST 2: stock 2, duas orders de 2 ---
  try {
    final p = await makeProduct(2);
    final pid = p['id'].toString();
    final a = await makeOrder(productId: pid, qty: 2);
    final b = await makeOrder(productId: pid, qty: 2);
    final resultsHttp = await Future.wait([
      patchOrderPago(a['id'].toString()),
      patchOrderPago(b['id'].toString()),
    ]);
    final oa = await orderRow(a['id'].toString());
    final ob = await orderRow(b['id'].toString());
    final qty = await productQty(pid);
    final paid = [
      oa?['status']?.toString().toLowerCase(),
      ob?['status']?.toString().toLowerCase(),
    ].where((s) => s == 'pago').length;
    final failCount = resultsHttp.where((r) => r.statusCode >= 400).length;
    final pass = paid == 1 && qty == 0 && failCount == 1;
    add(
      'T2_QTY2_VS_2x2',
      pass,
      'paid=$paid qty=$qty failHttp=$failCount '
      'A=${oa?['status']} B=${ob?['status']}',
    );
    await sb.deleteWhere('orders', 'product_id=eq.$pid');
    await sb.deleteWhere('products', 'id=eq.$pid');
  } catch (e) {
    add('T2_QTY2_VS_2x2', false, '$e');
  }

  // --- TEST 3: quantidades que cabem ---
  try {
    final p = await makeProduct(3);
    final pid = p['id'].toString();
    final a = await makeOrder(productId: pid, qty: 1);
    final b = await makeOrder(productId: pid, qty: 2);
    final ra = await patchOrderPago(a['id'].toString());
    final rb = await patchOrderPago(b['id'].toString());
    final oa = await orderRow(a['id'].toString());
    final ob = await orderRow(b['id'].toString());
    final qty = await productQty(pid);
    final pass = ra.statusCode < 300 &&
        rb.statusCode < 300 &&
        oa?['status']?.toString().toLowerCase() == 'pago' &&
        ob?['status']?.toString().toLowerCase() == 'pago' &&
        qty == 0;
    add(
      'T3_FITS_1_AND_2',
      pass,
      'qty=$qty A=${oa?['status']} B=${ob?['status']} '
      'http=${ra.statusCode}/${rb.statusCode}',
    );
    await sb.deleteWhere('orders', 'product_id=eq.$pid');
    await sb.deleteWhere('products', 'id=eq.$pid');
  } catch (e) {
    add('T3_FITS_1_AND_2', false, '$e');
  }

  // --- TEST 4: mesma order 2× ---
  try {
    final p = await makeProduct(2);
    final pid = p['id'].toString();
    final a = await makeOrder(productId: pid, qty: 1);
    final oid = a['id'].toString();
    final r1 = await patchOrderPago(oid);
    final qty1 = await productQty(pid);
    final r2 = await patchOrderPago(oid);
    final qty2 = await productQty(pid);
    final oa = await orderRow(oid);
    final pass = r1.statusCode < 300 &&
        qty1 == 1 &&
        qty2 == 1 &&
        oa?['status']?.toString().toLowerCase() == 'pago' &&
        (oa?['stock_units_applied'] as num?)?.toInt() == 1;
    add(
      'T4_SAME_ORDER_IDEMPOTENT',
      pass,
      'qty1=$qty1 qty2=$qty2 applied=${oa?['stock_units_applied']} '
      'http=${r1.statusCode}/${r2.statusCode}',
    );
    await sb.deleteWhere('orders', 'product_id=eq.$pid');
    await sb.deleteWhere('products', 'id=eq.$pid');
  } catch (e) {
    add('T4_SAME_ORDER_IDEMPOTENT', false, '$e');
  }

  // --- TEST 5: pagamento sem stock (SQL + reconciliação; Stripe se key) ---
  try {
    final p = await makeProduct(1);
    final pid = p['id'].toString();
    final winner = await makeOrder(productId: pid, qty: 1);
    final loser = await makeOrder(productId: pid, qty: 1);
    final rw = await patchOrderPago(winner['id'].toString());
    final rl = await patchOrderPago(loser['id'].toString());
    final qtyAfter = await productQty(pid);
    final loserBefore = await orderRow(loser['id'].toString());

    var stripeOk = true;
    var refundId = 'sim_refund_${DateTime.now().microsecondsSinceEpoch}';
    var usedRealStripe = false;
    if (stripeKey.isNotEmpty && rl.statusCode >= 400) {
      try {
        final piRes = await http.post(
          Uri.parse('https://api.stripe.com/v1/payment_intents'),
          headers: {
            'Authorization': 'Bearer $stripeKey',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body:
              'amount=500&currency=eur&confirm=true&payment_method=pm_card_visa'
              '&automatic_payment_methods[enabled]=true'
              '&automatic_payment_methods[allow_redirects]=never',
        );
        if (piRes.statusCode < 300) {
          final pi = jsonDecode(piRes.body) as Map<String, dynamic>;
          final piId = pi['id']?.toString() ?? '';
          await sb.patch('orders', 'id=eq.${loser['id']}', {
            'stripe_payment_intent_id': piId,
            'price_total': 5.0,
          });
          final refundRes = await http.post(
            Uri.parse('https://api.stripe.com/v1/refunds'),
            headers: {
              'Authorization': 'Bearer $stripeKey',
              'Content-Type': 'application/x-www-form-urlencoded',
              'Idempotency-Key': 'fleaber_oversell_refund_${loser['id']}',
            },
            body: 'payment_intent=$piId',
          );
          usedRealStripe = true;
          stripeOk = refundRes.statusCode < 300;
          if (stripeOk) {
            refundId =
                (jsonDecode(refundRes.body) as Map)['id']?.toString() ??
                    refundId;
          } else {
            refundId = 'stripe_fail_${_clip(refundRes.body)}';
          }
        }
      } catch (e) {
        usedRealStripe = true;
        stripeOk = false;
        refundId = 'stripe_err_$e';
      }
    }

    await sb.patch('orders', 'id=eq.${loser['id']}', {
      'status': 'cancelado',
      'stripe_refund_id': refundId,
      'stripe_refunded_at': DateTime.now().toUtc().toIso8601String(),
    });
    final qtyFinal = await productQty(pid);
    final loserAfter = await orderRow(loser['id'].toString());
    final wallets = await sb.select(
      'wallets',
      filter: 'id=eq.$sellerId',
      limit: 1,
    );
    final sellerBal = wallets.isEmpty ? null : wallets.first['balance'];

    final notPago = loserBefore?['status']?.toString().toLowerCase() != 'pago' &&
        loserAfter?['status']?.toString().toLowerCase() == 'cancelado';
    final stockUntouched = qtyAfter == 0 && qtyFinal == 0;
    final noStockApplied = loserAfter?['stock_units_applied'] == null;
    // PASS core: SQL rejeita «pago», cancelado sem consumo, stock intacto.
    // Stripe real é bónus se STRIPE_SECRET_KEY existir no env.
    final pass = rw.statusCode < 300 &&
        rl.statusCode >= 400 &&
        notPago &&
        stockUntouched &&
        noStockApplied &&
        (!usedRealStripe || stripeOk);
    add(
      'T5_PAID_NO_STOCK',
      pass,
      'winnerHttp=${rw.statusCode} loserHttp=${rl.statusCode} '
      'loserStatus=${loserAfter?['status']} refund=$refundId '
      'qty=$qtyFinal applied=${loserAfter?['stock_units_applied']} '
      'seller_wallet=$sellerBal realStripe=$usedRealStripe stripeOk=$stripeOk',
    );
    await sb.deleteWhere('orders', 'product_id=eq.$pid');
    await sb.deleteWhere('products', 'id=eq.$pid');
  } catch (e) {
    add('T5_PAID_NO_STOCK', false, '$e');
  }

  // --- TEST 6: cancelamento / restauro idempotente ---
  try {
    final p = await makeProduct(1);
    final pid = p['id'].toString();
    final a = await makeOrder(productId: pid, qty: 1);
    final oid = a['id'].toString();
    final rPago = await patchOrderPago(oid);
    final qtyPaid = await productQty(pid);
    await sb.patch('orders', 'id=eq.$oid', {'status': 'cancelado'});
    final qtyRestored = await productQty(pid);
    final after1 = await orderRow(oid);
    // Retry cancel (já cancelado) — não pode +1 outra vez
    await sb.patch('orders', 'id=eq.$oid', {'status': 'cancelado'});
    final qtyRetry = await productQty(pid);

    final pass = rPago.statusCode < 300 &&
        qtyPaid == 0 &&
        qtyRestored == 1 &&
        after1?['stock_units_applied'] == null &&
        qtyRetry == 1;
    add(
      'T6_CANCEL_RESTORE',
      pass,
      'qtyPaid=$qtyPaid restored=$qtyRestored retry=$qtyRetry '
      'applied=${after1?['stock_units_applied']}',
    );
    await sb.deleteWhere('orders', 'id=eq.$oid');
    await sb.deleteWhere('products', 'id=eq.$pid');
  } catch (e) {
    add('T6_CANCEL_RESTORE', false, '$e');
  }

  final failed = results.where((r) => r['pass'] != true).length;
  final out = {
    'at': DateTime.now().toUtc().toIso8601String(),
    'failed': failed,
    'results': results,
  };
  final path = 'tool/reports/HARDENING_FASE_2_HOSTILE_RESULTS.json';
  await Directory('tool/reports').create(recursive: true);
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('\nEscrito: $path failed=$failed');
  exit(failed == 0 ? 0 : 1);
}

String _clip(String s, [int n = 180]) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length <= n) return t;
  return '${t.substring(0, n)}…';
}
