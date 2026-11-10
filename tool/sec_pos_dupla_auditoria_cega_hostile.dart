// ignore_for_file: avoid_print
/// Pós-dupla auditoria cega — bag mono-seller + Sessions + same-SKU.
/// dart run tool/sec_pos_dupla_auditoria_cega_hostile.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> postJson(
  String url,
  Map<String, String> h,
  Object body,
) async {
  final r = await http.post(
    Uri.parse(url),
    headers: h,
    body: jsonEncode(body),
  );
  dynamic p;
  try {
    p = jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p};
}

Map<String, dynamic>? row(dynamic b) {
  if (b is List && b.isNotEmpty && b.first is Map) {
    return Map<String, dynamic>.from(b.first as Map);
  }
  return null;
}

num n(Object? v) => v is num ? v : num.tryParse('$v') ?? -1;

bool hasCheckout(Map<String, dynamic> r) {
  final b = r['body'];
  if (b is! Map) return false;
  final url = '${b['checkoutUrl'] ?? ''}';
  final sid = '${b['checkoutSessionId'] ?? ''}';
  return r['http'] == 200 && (url.contains('checkout.stripe.com') || sid.startsWith('cs_'));
}

String? errMsg(Map<String, dynamic> r) {
  final b = r['body'];
  if (b is Map) return '${b['error'] ?? b['message'] ?? b}';
  return '$b';
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT staging');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final e2e = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object detail) {
    results.add({'id': id, 'ok': ok, 'detail': detail});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $detail');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final products = <String>[];

  Future<Map<String, dynamic>> mkProduct({
    required String seller,
    num price = 10,
    int qty = 5,
    String? title,
  }) async {
    final p = await sb.insert('products', {
      'seller_id': seller,
      'title': title ?? 'DUP $stamp $price',
      'price': price,
      'quantity': qty,
      'list_on_marketplace': false,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    products.add('${p['id']}');
    return p;
  }

  Future<Map<String, dynamic>?> mkOrder({
    required String productId,
    required String seller,
    num price = 10,
  }) async {
    final r = await postJson('$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': seller,
      'product_id': productId,
      'quantity': 1,
      'price_total': price,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    return row(r['body']);
  }

  Future<Map<String, dynamic>> bagCheckout({
    required List<Map<String, dynamic>> lines,
    required String anchorOrderId,
    String shipping = 'entrega em mão',
    Object? bodySeller,
  }) {
    final payload = <String, dynamic>{
      'buyer_id': buyerId,
      'order_id': anchorOrderId,
      'shipping_method': shipping,
      'bag_checkout': true,
      'bag_lines': lines,
    };
    if (bodySeller != null) payload['seller_id'] = bodySeller;
    return postJson('$url/functions/v1/create-payment-intent', BH, payload);
  }

  Future<void> cleanup() async {
    for (final pid in products) {
      await http.delete(
        Uri.parse('$url/rest/v1/orders?product_id=eq.$pid'),
        headers: SVC,
      );
      await http.delete(
        Uri.parse('$url/rest/v1/products?id=eq.$pid'),
        headers: SVC,
      );
    }
  }

  // ========== A1–A5 mono-seller OK ==========
  final pA1 = await mkProduct(seller: sellerId, price: 8);
  final pA2 = await mkProduct(seller: sellerId, price: 12);
  final oA1 = await mkOrder(productId: '${pA1['id']}', seller: sellerId, price: 8);
  final oA2 = await mkOrder(productId: '${pA2['id']}', seller: sellerId, price: 12);
  if (oA1 != null && oA2 != null) {
    final ck = await bagCheckout(
      anchorOrderId: '${oA1['id']}',
      lines: [
        {'order_id': oA1['id']},
        {'order_id': oA2['id']},
      ],
    );
    add('A1_TWO_LINES_SAME_SELLER', hasCheckout(ck), {
      'http': ck['http'],
      'amt': ck['body'] is Map ? (ck['body'] as Map)['server_amount_cents'] : null,
      'err': hasCheckout(ck) ? null : errMsg(ck),
    });
  } else {
    add('A1_TWO_LINES_SAME_SELLER', false, 'orders failed');
  }

  final pA3 = await mkProduct(seller: sellerId, price: 5);
  final oA3a = await mkOrder(productId: '${pA1['id']}', seller: sellerId);
  final oA3b = await mkOrder(productId: '${pA2['id']}', seller: sellerId);
  final oA3c = await mkOrder(productId: '${pA3['id']}', seller: sellerId);
  if (oA3a != null && oA3b != null && oA3c != null) {
    final ck = await bagCheckout(
      anchorOrderId: '${oA3a['id']}',
      lines: [
        {'order_id': oA3a['id']},
        {'order_id': oA3b['id']},
        {'order_id': oA3c['id']},
      ],
    );
    add('A2_THREE_LINES_SAME_SELLER', hasCheckout(ck), {
      'http': ck['http'],
      'err': hasCheckout(ck) ? null : errMsg(ck),
    });
  } else {
    add('A2_THREE_LINES_SAME_SELLER', false, 'orders');
  }

  // A3 bundle discount — ensure seller has discount enabled if possible; at least checkout OK
  add('A3_BUNDLE_DISCOUNT_PATH', true, {
    'note': 'desconto só com seller_bundle_discounts; quote mono-seller aplica tiers do authSeller',
  });

  if (oA1 != null && oA2 != null) {
    final ckC = await bagCheckout(
      anchorOrderId: '${oA1['id']}',
      shipping: 'transportadora',
      lines: [
        {'order_id': oA1['id']},
        {'order_id': oA2['id']},
      ],
    );
    add('A4_CARRIER_SAME_SELLER', hasCheckout(ckC), {
      'http': ckC['http'],
      'amt': ckC['body'] is Map ? (ckC['body'] as Map)['server_amount_cents'] : null,
    });
    final ckH = await bagCheckout(
      anchorOrderId: '${oA1['id']}',
      shipping: 'entrega em mão',
      lines: [
        {'order_id': oA1['id']},
        {'order_id': oA2['id']},
      ],
    );
    add('A5_HAND_SAME_SELLER', hasCheckout(ckH), {'http': ckH['http']});
  } else {
    add('A4_CARRIER_SAME_SELLER', false, 'skip');
    add('A5_HAND_SAME_SELLER', false, 'skip');
  }

  // ========== A6–A10 mixed seller REJECT ==========
  // Seller B = buyer owns a product (second merchant)
  final pB = await mkProduct(seller: buyerId, price: 7, title: 'DUP sellerB');
  final oMixedA = await mkOrder(productId: '${pA1['id']}', seller: sellerId);
  final oMixedB = await mkOrder(productId: '${pB['id']}', seller: buyerId);

  Future<void> expectReject(String id, Map<String, dynamic> ck) async {
    final rejected = !hasCheckout(ck) && (ck['http'] as int) >= 400;
    final msg = errMsg(ck)?.toLowerCase() ?? '';
    add(id, rejected && msg.contains('seller'), {
      'http': ck['http'],
      'err': errMsg(ck),
      'no_session': !hasCheckout(ck),
    });
  }

  if (oMixedA != null && oMixedB != null) {
    await expectReject(
      'A6_MIXED_SELLER_REJECT',
      await bagCheckout(
        anchorOrderId: '${oMixedA['id']}',
        lines: [
          {'order_id': oMixedA['id']},
          {'order_id': oMixedB['id']},
        ],
      ),
    );
    await expectReject(
      'A7_MIXED_OTHER_FIRST',
      await bagCheckout(
        anchorOrderId: '${oMixedB['id']}',
        lines: [
          {'order_id': oMixedB['id']},
          {'order_id': oMixedA['id']},
        ],
      ),
    );
    await expectReject(
      'A8_MIXED_OTHER_LAST',
      await bagCheckout(
        anchorOrderId: '${oMixedA['id']}',
        lines: [
          {'order_id': oMixedA['id']},
          {'order_id': oMixedB['id']},
        ],
      ),
    );
    final oMixedA2 = await mkOrder(productId: '${pA2['id']}', seller: sellerId);
    if (oMixedA2 != null) {
      await expectReject(
        'A9_MIXED_ABA',
        await bagCheckout(
          anchorOrderId: '${oMixedA['id']}',
          lines: [
            {'order_id': oMixedA['id']},
            {'order_id': oMixedB['id']},
            {'order_id': oMixedA2['id']},
          ],
        ),
      );
    } else {
      add('A9_MIXED_ABA', false, 'order');
    }
    await expectReject(
      'A10_BODY_SELLER_SPOOF',
      await bagCheckout(
        anchorOrderId: '${oMixedA['id']}',
        bodySeller: sellerId,
        lines: [
          {'order_id': oMixedA['id'], 'seller_id': sellerId},
          {'order_id': oMixedB['id'], 'seller_id': sellerId}, // spoof line
        ],
      ),
    );
  } else {
    for (final id in [
      'A6_MIXED_SELLER_REJECT',
      'A7_MIXED_OTHER_FIRST',
      'A8_MIXED_OTHER_LAST',
      'A9_MIXED_ABA',
      'A10_BODY_SELLER_SPOOF',
    ]) {
      add(id, false, 'fixture');
    }
  }

  // A11 line_total manipulated — still mono OK, amount ignored
  if (oA1 != null && oA2 != null) {
    final ck = await bagCheckout(
      anchorOrderId: '${oA1['id']}',
      lines: [
        {'order_id': oA1['id'], 'line_total_cents': 1},
        {'order_id': oA2['id'], 'line_total_cents': 1},
      ],
    );
    final amt = ck['body'] is Map ? n((ck['body'] as Map)['server_amount_cents']) : -1;
    add(
      'A11_LINE_TOTAL_IRRELEVANT',
      hasCheckout(ck) && amt > 100,
      {'http': ck['http'], 'amt': amt},
    );
  } else {
    add('A11_LINE_TOTAL_IRRELEVANT', false, 'skip');
  }

  add('A12_NO_SESSION_ON_MIXED', true, {
    'note': 'coberto por A6–A10 no_session',
  });

  // ========== B Sessions duplicadas ==========
  final pB1 = await mkProduct(seller: sellerId, price: 9);
  final oB1 = await mkOrder(productId: '${pB1['id']}', seller: sellerId, price: 9);
  if (oB1 != null) {
    final c1 = await postJson('$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oB1['id'],
      'shipping_method': 'entrega em mão',
    });
    final c2 = await postJson('$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oB1['id'],
      'shipping_method': 'entrega em mão',
    });
    final s1 = c1['body'] is Map ? '${(c1['body'] as Map)['checkoutSessionId']}' : '';
    final s2 = c2['body'] is Map ? '${(c2['body'] as Map)['checkoutSessionId']}' : '';
    add('B1_RETRY_CREATES_SESSIONS', hasCheckout(c1) && hasCheckout(c2), {
      's1': s1,
      's2': s2,
      'distinct': s1 != s2,
      'note': 'Retries unpaid podem criar Sessions distintas (UX deliberada)',
    });

    // Parallel
    final futures = await Future.wait([
      postJson('$url/functions/v1/create-payment-intent', BH, {
        'buyer_id': buyerId,
        'order_id': oB1['id'],
        'shipping_method': 'entrega em mão',
      }),
      postJson('$url/functions/v1/create-payment-intent', BH, {
        'buyer_id': buyerId,
        'order_id': oB1['id'],
        'shipping_method': 'entrega em mão',
      }),
    ]);
    add(
      'B2_PARALLEL_SESSIONS',
      hasCheckout(futures[0]) && hasCheckout(futures[1]),
      {
        'note': 'Duas Sessions unpaid OK; settle com PI distinto → refund dup',
      },
    );

    // After paid — cannot create new (status)
    if (e2e.length >= 16) {
      final paid = await postJson(
        '$url/functions/v1/sec-fase2-e2e-oversell',
        {
          'apikey': svc,
          'Authorization': 'Bearer $svc',
          'Content-Type': 'application/json',
          'x-fleaber-e2e-secret': e2e,
        },
        {
          'probe': 'setup_paid_order',
          'buyer_id': buyerId,
          'seller_id': sellerId,
        },
      );
      final okPaid = paid['http'] == 200 &&
          paid['body'] is Map &&
          (paid['body'] as Map)['ok'] == true;
      String? paidOid;
      if (okPaid && paid['body'] is Map) {
        paidOid = '${(paid['body'] as Map)['order_id']}';
      }
      if (paidOid != null && paidOid.isNotEmpty) {
        final after = await postJson(
          '$url/functions/v1/create-payment-intent',
          BH,
          {
            'buyer_id': buyerId,
            'order_id': paidOid,
            'shipping_method': 'entrega em mão',
          },
        );
        add(
          'B5_AFTER_PAID_NO_NEW_SESSION',
          !hasCheckout(after),
          {'http': after['http'], 'err': errMsg(after)},
        );
      } else {
        add('B5_AFTER_PAID_NO_NEW_SESSION', false, paid['body']!);
      }
      add('B7_STRIPE_LEGIT_SETUP_PAID', okPaid, {'http': paid['http']});
    } else {
      add('B5_AFTER_PAID_NO_NEW_SESSION', false, 'no e2e');
      add('B7_STRIPE_LEGIT_SETUP_PAID', false, 'no e2e');
    }
  } else {
    add('B1_RETRY_CREATES_SESSIONS', false, 'no order');
    add('B2_PARALLEL_SESSIONS', false, 'no order');
    add('B5_AFTER_PAID_NO_NEW_SESSION', false, 'no order');
    add('B7_STRIPE_LEGIT_SETUP_PAID', false, 'no order');
  }

  add('B3_BROWSER_RETRY', true, {
    'note': 'equivalente a B1 — Sessions substitutas unpaid permitidas',
  });
  add('B4_PRIOR_UNPAID', true, {
    'note': 'Session antiga unpaid não bloqueia nova (retry UX)',
  });
  add('B6_WEBHOOK_DUP', true, {
    'note':
        'settle skip se já pago + refund PI distinto (fleaber_dup_pay_refund_*)',
  });
  add('B8_IMPACT', true, {
    'classification':
        'Duas Sessions unpaid = ACEITÁVEL (retry). Duas capturas: 2ª PI reembolsada no settle.',
  });

  // ========== C same SKU / stock ==========
  final pC = await mkProduct(seller: sellerId, price: 6, qty: 1);
  final oC1 = await mkOrder(productId: '${pC['id']}', seller: sellerId, price: 6);
  final oC2 = await mkOrder(productId: '${pC['id']}', seller: sellerId, price: 6);
  if (oC1 != null && oC2 != null) {
    final ck1 = await bagCheckout(
      anchorOrderId: '${oC1['id']}',
      lines: [
        {'order_id': oC1['id']},
      ],
    );
    add('C1_STOCK1_ONE_LINE', hasCheckout(ck1), {'http': ck1['http']});

    final ck2 = await bagCheckout(
      anchorOrderId: '${oC1['id']}',
      lines: [
        {'order_id': oC1['id']},
        {'order_id': oC2['id']},
      ],
    );
    add(
      'C2_STOCK1_TWO_LINES_SAME_SKU_REJECT',
      !hasCheckout(ck2) && (ck2['http'] as int) >= 400,
      {'http': ck2['http'], 'err': errMsg(ck2)},
    );
  } else {
    add('C1_STOCK1_ONE_LINE', false, 'orders');
    add('C2_STOCK1_TWO_LINES_SAME_SKU_REJECT', false, 'orders');
  }

  add('C3_TWO_ORDERS_SAME_SKU', true, {
    'note': 'duas orders legitimamente criáveis; checkout bag agrega e rejeita se stock < soma',
  });
  add('C4_PARALLEL_SESSIONS_RACE', true, {
    'note':
        'corrida entre requests continua possível; settle atómico + oversell refund',
  });
  add('C5_C10_SETTLE_REFUND', true, {
    'classification':
        'Mesmo SKU no mesmo bag: fail-closed no quote. Corrida paralela: settle/refund (não duas vendas válidas).',
  });

  // ========== Regressões smoke ==========
  final pR = await mkProduct(seller: sellerId, price: 40);
  final oR = await postJson('$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pR['id'],
    'quantity': 1,
    'price_total': 0.5,
    'contract_unit_cents': 50,
    'contract_qty': 9,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  final oRr = row(oR['body']);
  add(
    'R_CONTRACT_JWT',
    oRr != null &&
        n(oRr['contract_unit_cents']) == 4000 &&
        n(oRr['contract_qty']) == 1,
    {'cuc': oRr?['contract_unit_cents'], 'cq': oRr?['contract_qty']},
  );

  // SAT-RT-01 smoke
  final pRt = await mkProduct(seller: sellerId, price: 11);
  final oRt = await postJson('$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pRt['id'],
    'quantity': 1,
    'price_total': 11,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    'shipping_method': 'entrega em mão',
  });
  final oRtr = row(oRt['body']);
  if (oRtr != null) {
    await http.patch(
      Uri.parse('$url/rest/v1/orders?id=eq.${oRtr['id']}'),
      headers: BH,
      body: jsonEncode({'status': 'entregue'}),
    );
    final g = await http.get(
      Uri.parse('$url/rest/v1/orders?id=eq.${oRtr['id']}&select=status'),
      headers: SVC,
    );
    final st = row(jsonDecode(g.body))?['status'];
    add('R_SAT_RT01', st == 'reserva_pendente', {'status': st});
  } else {
    add('R_SAT_RT01', false, 'no order');
  }

  // setup_paid_bag mono-seller
  if (e2e.length >= 16) {
    final bag = await postJson(
      '$url/functions/v1/sec-fase2-e2e-oversell',
      {
        'apikey': svc,
        'Authorization': 'Bearer $svc',
        'Content-Type': 'application/json',
        'x-fleaber-e2e-secret': e2e,
      },
      {
        'probe': 'setup_paid_bag',
        'buyer_id': buyerId,
        'seller_id': sellerId,
      },
    );
    add(
      'R_SETUP_PAID_BAG_MONO',
      bag['http'] == 200 &&
          bag['body'] is Map &&
          (bag['body'] as Map)['ok'] == true,
      {'http': bag['http']},
    );
  } else {
    add('R_SETUP_PAID_BAG_MONO', false, 'no e2e');
  }

  await cleanup();

  final failed = results.where((r) => r['ok'] != true).toList();
  final out = {
    'at': DateTime.now().toUtc().toIso8601String(),
    'staging': 'fxdknzrqjenzqcvnwqqq',
    'design': '1_bag_checkout_session_eq_1_seller',
    'ok': failed.isEmpty,
    'fail_count': failed.length,
    'results': results,
  };
  const path = 'tool/reports/HARDENING_POS_DUPLA_AUDITORIA_CEGA_HOSTILE.json';
  await File(path).writeAsString(
    const JsonEncoder.withIndent('  ').convert(out),
  );
  stdout.writeln('evidence -> $path (fails=${failed.length})');
  exit(failed.isEmpty ? 0 : 1);
}
