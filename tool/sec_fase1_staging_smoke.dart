// ignore_for_file: avoid_print
/// Smoke FASE 1 staging — checkout servidor, underpay, payout race/retry.
/// dart run tool/sec_fase1_staging_smoke.dart
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
  final buyerEmail = envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final buyerPass = envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD');
  final sellerEmail = envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL');
  final sellerPass = envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD');

  final out = <String, dynamic>{
    'at': DateTime.now().toUtc().toIso8601String(),
    'checks': <Map<String, dynamic>>[],
  };
  void check(String id, bool pass, String detail) {
    (out['checks'] as List).add({'id': id, 'pass': pass, 'detail': detail});
    print('${pass ? "PASS" : "FAIL"} $id — $detail');
  }

  final buyerToken = await sb.signIn(email: buyerEmail, password: buyerPass);
  final buyerId = await sb.userIdForAccessToken(buyerToken);
  final sellerToken = await sb.signIn(email: sellerEmail, password: sellerPass);

  // Prefer FX1 product
  var products = await sb.select(
    'products',
    filter: 'seller_id=eq.$sellerId&ref_code=eq.FX1',
    limit: 1,
  );
  if (products.isEmpty) {
    products = await sb.select(
      'products',
      filter: 'seller_id=eq.$sellerId&available_for_live=eq.true',
      limit: 1,
    );
  }
  if (products.isEmpty) {
    check('CHECKOUT_NORMAL', false, 'sem produto seller');
    _write(out);
    exit(1);
  }
  final product = products.first;
  final productId = product['id'].toString();
  final unitEur = double.parse('${product['price']}');
  const shipEur = 3.5;
  final protEur =
      ((0.65 + (unitEur + shipEur) * 0.05) * 100).round() / 100;
  final expectedCents = ((unitEur + shipEur + protEur) * 100).round();
  const shippingMethod = 'Envio Transportadora (€3.50)';

  Future<Map<String, dynamic>> createOrderAndCheckout({
    required int clientAmountCents,
    required double orderPriceTotal,
  }) async {
    final order = await sb.insert('orders', {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': productId,
      'price_total': orderPriceTotal,
      'quantity': 1,
      'status': 'reserva_pendente',
    });
    final orderId = order['id'].toString();
    final res = await sb.invokeEdge(
      'create-payment-intent',
      {
        'amount': clientAmountCents,
        'currency': 'eur',
        'product_id': productId,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': orderId,
        'quantity': 1,
        'item_price': (unitEur * 100).round(),
        'shipping': 350,
        'protection_fee': (protEur * 100).round(),
        'shipping_method': shippingMethod,
      },
      accessToken: buyerToken,
    );
    Map<String, dynamic> body = {};
    try {
      body = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    } catch (_) {
      body = {'raw': res.body};
    }
    return {
      'http': res.statusCode,
      'order_id': orderId,
      'body': body,
    };
  }

  // --- Checkout normal ---
  try {
    final normal = await createOrderAndCheckout(
      clientAmountCents: expectedCents,
      orderPriceTotal: expectedCents / 100.0,
    );
    final body = Map<String, dynamic>.from(normal['body'] as Map);
    final httpOk = (normal['http'] as int) == 200;
    final serverAmt = int.tryParse('${body['server_amount_cents']}') ?? -1;
    final amountTotal = int.tryParse('${body['amount_total']}') ?? -1;
    final urlOk = (body['checkoutUrl']?.toString() ?? '').isNotEmpty;
    final sessionOk =
        (body['checkoutSessionId']?.toString() ?? '').startsWith('cs_');
    final amountsMatch = serverAmt == expectedCents &&
        amountTotal == expectedCents;
    check(
      'CHECKOUT_NORMAL',
      httpOk && urlOk && sessionOk && amountsMatch,
      'http=${normal['http']} expected=$expectedCents server=$serverAmt amount_total=$amountTotal session=${body['checkoutSessionId']} unit=$unitEur',
    );
    out['checkout_normal'] = {
      'expected_cents': expectedCents,
      'response': body,
      'order_id': normal['order_id'],
    };
    // cancel order cleanup
    await sb.patch('orders', 'id=eq.${normal['order_id']}', {
      'status': 'cancelado',
    });
  } catch (e) {
    check('CHECKOUT_NORMAL', false, '$e');
  }

  // --- Underpay hostil ---
  try {
    final under = await createOrderAndCheckout(
      clientAmountCents: 50,
      orderPriceTotal: 0.50,
    );
    final body = Map<String, dynamic>.from(under['body'] as Map);
    final httpOk = (under['http'] as int) == 200;
    final serverAmt = int.tryParse('${body['server_amount_cents']}') ?? -1;
    final amountTotal = int.tryParse('${body['amount_total']}') ?? -1;
    // Must charge server total, NOT 50 cents
    final blockedUnderpay =
        httpOk && serverAmt == expectedCents && amountTotal == expectedCents;
    check(
      'UNDERPAY_HOSTILE',
      blockedUnderpay,
      'client_sent=50 server=$serverAmt amount_total=$amountTotal expected=$expectedCents http=${under['http']}',
    );
    out['underpay'] = {
      'expected_cents': expectedCents,
      'response': body,
      'order_id': under['order_id'],
    };
    await sb.patch('orders', 'id=eq.${under['order_id']}', {
      'status': 'cancelado',
    });
  } catch (e) {
    check('UNDERPAY_HOSTILE', false, '$e');
  }

  // --- Payout smoke + retry (Stripe Connect sandbox) ---
  try {
    try {
      await sb.rpc('batata_ensure_wallet', {'p_user_id': sellerId});
    } catch (_) {}
    final wallets = await sb.select(
      'wallets',
      filter: 'id=eq.$sellerId',
      limit: 1,
    );
    final stripeAccount = wallets.isEmpty
        ? null
        : wallets.first['stripe_account_id']?.toString();
    await sb.patch('wallets', 'id=eq.$sellerId', {'balance': 5.00});

    if (stripeAccount == null || stripeAccount.isEmpty) {
      final key = 'smoke_payout_rpc_${DateTime.now().microsecondsSinceEpoch}';
      final debit = Map<String, dynamic>.from(
        await sb.rpc('batata_wallet_payout_debit', {
          'p_user_id': sellerId,
          'p_amount_cents': 100,
          'p_idempotency_key': key,
        }) as Map,
      );
      final debit2 = Map<String, dynamic>.from(
        await sb.rpc('batata_wallet_payout_debit', {
          'p_user_id': sellerId,
          'p_amount_cents': 100,
          'p_idempotency_key': key,
        }) as Map,
      );
      check(
        'PAYOUT_NORMAL',
        debit['ok'] == true,
        'Connect ausente — RPC debit ok balance_after=${debit['balance_after']}',
      );
      check(
        'PAYOUT_RETRY',
        debit2['idempotent'] == true,
        'RPC idempotent=${debit2['idempotent']}',
      );
      await sb.rpc('batata_wallet_payout_finish', {
        'p_idempotency_key': key,
        'p_stripe_transfer_id': null,
        'p_failed': true,
      });
    } else {
      Map<String, dynamic>? successBody;
      String? successKey;
      String? lastErr;
      for (var attempt = 1; attempt <= 6; attempt++) {
        final key =
            'smoke_payout_${DateTime.now().microsecondsSinceEpoch}_$attempt';
        await sb.patch('wallets', 'id=eq.$sellerId', {'balance': 5.00});
        final edge = await sb.invokeEdge(
          'create-connect-account',
          {
            'user_id': sellerId,
            'amount': 100,
            'idempotency_key': key,
          },
          accessToken: sellerToken,
        );
        Map<String, dynamic> body = {};
        try {
          body = Map<String, dynamic>.from(jsonDecode(edge.body) as Map);
        } catch (_) {
          body = {'raw': edge.body};
        }
        if (edge.statusCode == 200 && body['transferId'] != null) {
          successBody = body;
          successKey = key;
          break;
        }
        lastErr = 'http=${edge.statusCode} body=${_clip(body)}';
        await Future<void>.delayed(const Duration(seconds: 4));
      }

      if (successBody == null || successKey == null) {
        check('PAYOUT_NORMAL', false, 'Stripe transfer falhou após retries: $lastErr');
        check('PAYOUT_RETRY', false, 'sem transfer para retry');
      } else {
        final transfer1 = successBody['transferId'].toString();
        final ledgers = await sb.select(
          'wallet_payout_ledger',
          filter: 'idempotency_key=eq.$successKey',
          limit: 1,
        );
        final led = ledgers.isEmpty ? null : ledgers.first;
        final wallets2 = await sb.select(
          'wallets',
          filter: 'id=eq.$sellerId',
          limit: 1,
        );
        final bal = wallets2.isEmpty ? null : wallets2.first['balance'];
        final consistent = led != null &&
            led['status'] == 'transferred' &&
            led['stripe_transfer_id']?.toString() == transfer1;
        check(
          'PAYOUT_NORMAL',
          consistent,
          'transfer=$transfer1 ledger_status=${led?['status']} wallet_balance=$bal resp_balance=${successBody['balance']}',
        );

        final edge2 = await sb.invokeEdge(
          'create-connect-account',
          {
            'user_id': sellerId,
            'amount': 100,
            'idempotency_key': successKey,
          },
          accessToken: sellerToken,
        );
        Map<String, dynamic> e2 = {};
        try {
          e2 = Map<String, dynamic>.from(jsonDecode(edge2.body) as Map);
        } catch (_) {
          e2 = {'raw': edge2.body};
        }
        final transfer2 = e2['transferId']?.toString();
        final retryOk = edge2.statusCode == 200 &&
            transfer2 == transfer1 &&
            e2['idempotent'] == true;
        check(
          'PAYOUT_RETRY',
          retryOk,
          'transfer1=$transfer1 transfer2=$transfer2 idempotent=${e2['idempotent']}',
        );
        out['payout'] = {
          'success': successBody,
          'retry': e2,
          'ledger': led,
          'wallet_balance': bal,
        };
      }
    }
  } catch (e) {
    check('PAYOUT_NORMAL', false, '$e');
    check('PAYOUT_RETRY', false, '$e');
  }

  final failed =
      (out['checks'] as List).where((c) => (c as Map)['pass'] != true).length;
  out['failed'] = failed;
  _write(out);
  exit(failed == 0 ? 0 : 1);
}

void _write(Map<String, dynamic> out) {
  Directory('tool/reports').createSync(recursive: true);
  const path = 'tool/reports/HARDENING_FASE_1_STAGING_SMOKE.json';
  File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print('\nEscrito: $path');
}

String _clip(Object o) {
  final s = '$o';
  return s.length > 220 ? s.substring(0, 220) : s;
}
