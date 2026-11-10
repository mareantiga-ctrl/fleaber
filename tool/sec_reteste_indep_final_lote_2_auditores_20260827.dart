// ignore_for_file: avoid_print
/// RETESTE INDEPENDENTE FINAL — lote P1 pós-2 auditores (auditoria só).
/// NÃO altera código/SQL. Descartável.
/// dart run tool/sec_reteste_indep_final_lote_2_auditores_20260827.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
]) async {
  final r = method == 'POST'
      ? await http.post(Uri.parse(u), headers: h, body: jsonEncode(body))
      : method == 'PATCH'
          ? await http.patch(Uri.parse(u), headers: h, body: jsonEncode(body))
          : method == 'DELETE'
              ? await http.delete(Uri.parse(u), headers: h)
              : await http.get(Uri.parse(u), headers: h);
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

bool hasCs(Map<String, dynamic> r) {
  final b = r['body'];
  if (b is! Map) return false;
  final url = '${b['checkoutUrl'] ?? ''}';
  final sid = '${b['checkoutSessionId'] ?? ''}';
  return r['http'] == 200 &&
      (url.contains('checkout.stripe.com') || sid.startsWith('cs_'));
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT not staging');
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
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SH = {
    'apikey': anon,
    'Authorization': 'Bearer $sellerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final ANON = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final findings = <Map<String, dynamic>>[];
  final probes = <Map<String, dynamic>>[];
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final products = <String>[];
  String? savedBuyerType;

  void probe(String id, Object detail) {
    probes.add({'id': id, 'detail': detail});
    stdout.writeln('PROBE $id — $detail');
  }

  void hit(
    String id,
    String sev,
    String area,
    String impact,
    Object evidence, {
    String estado = 'ABERTO',
  }) {
    findings.add({
      'id': id,
      'sev': sev,
      'area': area,
      'impact': impact,
      'estado': estado,
      'evidence': evidence,
    });
    stdout.writeln('HIT $sev $id — $impact');
  }

  Future<Map<String, dynamic>> mkProduct({
    num price = 9,
    int qty = 5,
    String? seller,
  }) async {
    final p = await sb.insert('products', {
      'seller_id': seller ?? sellerId,
      'title': 'RI $stamp $price',
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
    required String pid,
    String pm = 'Pagamento na App',
    num price = 9,
    int qty = 1,
  }) async {
    final r = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': qty,
      'price_total': price,
      'status': 'reserva_pendente',
      'payment_method': pm,
      'shipping_method': 'entrega em mão',
    });
    return row(r['body']);
  }

  Future<Map<String, dynamic>?> orderSnap(String oid) async {
    return row((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$oid&select=status,amount_paid_cents,stock_units_applied,contract_unit_cents,contract_qty,quantity,payment_method,stripe_payment_intent_id,stripe_checkout_session_id',
      SVC,
    ))['body']);
  }

  Future<num?> productQty(String pid) async {
    final r = row((await req(
      'GET',
      '$url/rest/v1/products?id=eq.$pid&select=quantity',
      SVC,
    ))['body']);
    return r == null ? null : n(r['quantity']);
  }

  Future<bool?> isOff(String pm) async {
    final r = await req(
      'POST',
      '$url/rest/v1/rpc/batata_is_off_platform_payment',
      BH,
      {'p_method': pm},
    );
    if ((r['http'] as int) >= 400) return null;
    final b = r['body'];
    if (b is bool) return b;
    return null;
  }

  Future<Map<String, dynamic>?> e2eProbe(
    String probeName, [
    Map<String, dynamic>? extra,
  ]) async {
    if (e2e.isEmpty) return null;
    final body = <String, dynamic>{
      'probe': probeName,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      ...?extra,
    };
    final r = await req(
      'POST',
      '$url/functions/v1/staging-e2e-harness',
      {
        'apikey': anon,
        'Authorization': 'Bearer $buyerTok',
        'Content-Type': 'application/json',
        'x-fleaber-e2e-secret': e2e,
      },
      body,
    );
    return r;
  }

  Future<void> cleanup() async {
    if (savedBuyerType != null) {
      await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyerId', SVC, {
        'user_type': savedBuyerType,
      });
    }
    for (final pid in products) {
      final ords = await req(
        'GET',
        '$url/rest/v1/orders?product_id=eq.$pid&select=id',
        SVC,
      );
      if (ords['body'] is List) {
        for (final o in ords['body'] as List) {
          if (o is! Map || o['id'] == null) continue;
          final oid = o['id'];
          await req('DELETE', '$url/rest/v1/reviews?order_id=eq.$oid', SVC);
          await req(
            'DELETE',
            '$url/rest/v1/order_disputes?order_id=eq.$oid',
            SVC,
          );
        }
      }
      await req('DELETE', '$url/rest/v1/live_items?product_id=eq.$pid', SVC);
      await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid', SVC);
      await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
    }
  }

  // ===================== A STOCK / SESSIONS =====================
  final pA = await mkProduct(price: 14, qty: 1);
  final oA1 = await mkOrder(pid: '${pA['id']}', price: 14);
  final oA2 = await mkOrder(pid: '${pA['id']}', price: 14);
  final oA3 = await mkOrder(pid: '${pA['id']}', price: 14);
  probe('A1_orders', {
    'o1': oA1?['id'],
    'o2': oA2?['id'],
    'o3': oA3?['id'],
    'stock': await productQty('${pA['id']}'),
  });

  Map<String, dynamic>? cs1;
  Map<String, dynamic>? cs2;
  Map<String, dynamic>? cs3;
  if (oA1 != null && oA2 != null) {
    // concurrent create
    final f1 = req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oA1['id'],
      'shipping_method': 'entrega em mão',
    });
    final f2 = req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oA2['id'],
      'shipping_method': 'entrega em mão',
    });
    final pair = await Future.wait([f1, f2]);
    cs1 = pair[0];
    cs2 = pair[1];
  }
  if (oA3 != null) {
    cs3 = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oA3['id'],
      'shipping_method': 'entrega em mão',
    });
  }
  final sessions = [cs1, cs2, cs3].where((c) => c != null && hasCs(c!)).length;
  probe('A2_sessions', {
    'sessions_ok': sessions,
    'cs1': hasCs(cs1 ?? {}),
    'cs2': hasCs(cs2 ?? {}),
    'cs3': hasCs(cs3 ?? {}),
    'h1': cs1?['http'],
    'h2': cs2?['http'],
    'h3': cs3?['http'],
  });
  if (sessions >= 2) {
    probe('A_note_two_sessions',
        'duas+ Sessions unpaid observadas — não é prova de duas vendas');
  }

  // same bag
  if (oA1 != null && oA2 != null) {
    final bag = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oA1['id'],
      'bag_checkout': true,
      'shipping_method': 'entrega em mão',
      'bag_lines': [
        {'order_id': oA1['id']},
        {'order_id': oA2['id']},
      ],
    });
    probe('A_same_bag', {'http': bag['http'], 'body': bag['body']});
    if (hasCs(bag)) {
      hit(
        'RI-A-BAG',
        'P1',
        'STOCK',
        'Bag same-SKU stock=1 criou Session',
        bag,
      );
    }
  }

  // same order two sessions
  if (oA1 != null) {
    final r1 = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oA1['id'],
      'shipping_method': 'entrega em mão',
    });
    final r2 = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oA1['id'],
      'shipping_method': 'entrega em mão',
    });
    probe('A14_same_order_two_cs', {
      'r1': hasCs(r1),
      'r2': hasCs(r2),
      'h1': r1['http'],
      'h2': r2['http'],
    });
  }

  // Dual capture attempt via e2e if available
  var dualCaptureProved = false;
  var dualCaptureNet = false;
  if (e2e.isNotEmpty) {
    final paidA = await e2eProbe('setup_paid_order', {
      'initial_qty': 1,
      'price': 6.0,
    });
    probe('A_e2e_setup_paid', {
      'http': paidA?['http'],
      'keys': paidA?['body'] is Map
          ? (paidA!['body'] as Map).keys.toList()
          : paidA?['body'],
    });
    // Second paid on SAME product if harness returns product_id
    if (paidA != null &&
        paidA['body'] is Map &&
        (paidA['body'] as Map)['product_id'] != null) {
      final pidPaid = '${(paidA['body'] as Map)['product_id']}';
      products.add(pidPaid);
      final oExtra = await mkOrder(pid: pidPaid, price: 6);
      if (oExtra != null) {
        final cpi = await req(
          'POST',
          '$url/functions/v1/create-payment-intent',
          BH,
          {
            'buyer_id': buyerId,
            'order_id': oExtra['id'],
            'shipping_method': 'entrega em mão',
          },
        );
        probe('A_second_order_after_paid', {
          'http': cpi['http'],
          'has_cs': hasCs(cpi),
          'qty': await productQty(pidPaid),
          'o1': (paidA['body'] as Map)['order'],
        });
      }
      final qtyAfter = await productQty(pidPaid);
      final o1st = (paidA['body'] as Map)['order'];
      probe('A_after_one_paid', {'qty': qtyAfter, 'order': o1st});
      if (qtyAfter == 0 &&
          o1st is Map &&
          '${o1st['status']}' == 'pago' &&
          n(o1st['stock_units_applied']) == 1) {
        dualCaptureProved = true; // one capture OK path
      }
    }
  } else {
    probe('A_dual_capture', 'NÃO COMPROVADO — sem e2e secret / sem pagar 2 CS');
  }
  probe('A_dual_capture_net_verdict', {
    'two_sessions_seen': sessions >= 2,
    'two_net_captures_proved': dualCaptureNet,
    'one_paid_path_seen': dualCaptureProved,
    'note':
        'Duas capturas líquidas permanentes: NÃO COMPROVADO neste reteste (não pagámos 2 CS reais).',
  });

  // ===================== C PAYMENT =====================
  final pmCases = <String, bool?>{};
  for (final pm in [
    'Pagamento na App',
    'Seguro Fleaber',
    'MB WAY',
    'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    'transferencia',
    'pagamento directo',
    'entrega em mão',
    '',
    ' ',
    '\t',
    '\n',
    'mb way',
    'MB WAY',
    'Pagamento na App MB WAY',
    'Seguro Fleaber transferência',
    'Stripe MB WAY',
    'MB WAY Pagamento na App',
    'Pagamento na App (MB WAY/Transf)',
    'stripe transferencia',
    'qualquer lixo mb way',
    'pix_inventado',
    '  MB WAY  ',
    '\u00A0MB WAY', // nbsp prefix
  ]) {
    pmCases[pm] = await isOff(pm);
  }
  probe('C_classifier', pmCases);

  Future<void> trySellerPago(String id, String pm, {bool expectPago = false}) async {
    final p = await mkProduct(price: 8);
    final o = await mkOrder(pid: '${p['id']}', pm: pm, price: 8);
    if (o == null) {
      probe(id, {'err': 'no order'});
      return;
    }
    await req('PATCH', '$url/rest/v1/orders?id=eq.${o['id']}', SH, {
      'status': 'pago',
    });
    final after = await orderSnap('${o['id']}');
    final qty = await productQty('${p['id']}');
    final gotPago = after != null && '${after['status']}' == 'pago';
    probe(id, {
      'pm': pm,
      'status': after?['status'],
      'stock_units': after?['stock_units_applied'],
      'amount_paid': after?['amount_paid_cents'],
      'product_qty': qty,
      'got_pago': gotPago,
    });
    if (gotPago && !expectPago) {
      hit(
        'RI-C-$id',
        'P1',
        'PAYMENT',
        'Seller JWT→pago com método que não deveria ser off-platform',
        {'pm': pm, 'after': after, 'qty': qty},
      );
    }
    if (!gotPago && expectPago) {
      hit(
        'RI-C-LEGIT-$id',
        'P1',
        'PAYMENT',
        'MB WAY / off-platform legítimo NÃO chegou a pago',
        {'pm': pm, 'after': after},
      );
    }
  }

  await trySellerPago('spoof_app_mbway', 'Pagamento na App (MB WAY/Transf)');
  await trySellerPago('spoof_seguro_transf', 'Seguro Fleaber transferência');
  await trySellerPago('spoof_stripe_mbway', 'Stripe MB WAY');
  await trySellerPago('spoof_app_mbway_space', 'Pagamento na App MB WAY');
  await trySellerPago('empty', '');
  await trySellerPago('unknown', 'xyzzy_pay');
  await trySellerPago(
    'legit_mbway',
    'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    expectPago: true,
  );
  await trySellerPago('legit_short', 'MB WAY', expectPago: true);

  // ===================== B REVIEWS =====================
  final pRev = await mkProduct(price: 10);
  final oRev = await mkOrder(
    pid: '${pRev['id']}',
    pm: 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    price: 10,
  );
  if (oRev != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oRev['id']}', SH, {
      'status': 'pago',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oRev['id']}', SH, {
      'status': 'enviado',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oRev['id']}', BH, {
      'status': 'concluido',
    });
    await req('DELETE', '$url/rest/v1/reviews?order_id=eq.${oRev['id']}', SVC);

    Future<Map<String, dynamic>> insRev(String? role, {String? comment}) {
      final body = <String, dynamic>{
        'order_id': oRev['id'],
        'buyer_id': buyerId,
        'target_id': sellerId,
        'stars': 5,
        'comment': comment ?? 'RI $role',
      };
      if (role != null) body['author_role'] = role;
      return req('POST', '$url/rest/v1/reviews', BH, body);
    }

    final roles = [
      'buyer',
      'comprador',
      'BUYER',
      'COMPRADOR',
      'Buyer',
      '  buyer  ',
      null,
      '',
      'seller',
      'vendedor',
    ];
    final first = await insRev('buyer');
    final firstR = row(first['body']);
    probe('B_first', {'http': first['http'], 'row': firstR});

    for (final role in roles.skip(1)) {
      final r = await insRev(role);
      probe('B_alias_${role ?? 'null'}', {
        'http': r['http'],
        'body': r['body'],
        'row': row(r['body']),
      });
      if ((r['http'] as int) < 300 && role != 'seller' && role != 'vendedor') {
        hit(
          'RI-B-DUP-${role ?? 'null'}',
          'P1',
          'REVIEW',
          'Segunda review comprador via alias $role',
          r,
        );
      }
    }

    // UPDATE role then reinsert
    if (firstR != null) {
      final upd = await req(
        'PATCH',
        '$url/rest/v1/reviews?id=eq.${firstR['id']}',
        BH,
        {'author_role': 'vendedor'},
      );
      probe('B6_update_role', {'http': upd['http'], 'body': upd['body']});
      final afterUpd = row((await req(
        'GET',
        '$url/rest/v1/reviews?id=eq.${firstR['id']}&select=author_role',
        SVC,
      ))['body']);
      final rein = await insRev('comprador', comment: 'after update');
      probe('B6_reinsert', {
        'role_after': afterUpd,
        'http': rein['http'],
        'body': rein['body'],
      });
      if ((rein['http'] as int) < 300) {
        hit(
          'RI-B-UPDATE-REINSERT',
          'P1',
          'REVIEW',
          'UPDATE author_role + reinsert criou 2ª review',
          {'after': afterUpd, 'rein': rein},
        );
      }
    }

    // concurrent dual insert on fresh order
    final oRace = await mkOrder(
      pid: '${pRev['id']}',
      pm: 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
      price: 10,
    );
    if (oRace != null) {
      await req('PATCH', '$url/rest/v1/orders?id=eq.${oRace['id']}', SH, {
        'status': 'pago',
      });
      await req('PATCH', '$url/rest/v1/orders?id=eq.${oRace['id']}', SH, {
        'status': 'enviado',
      });
      await req('PATCH', '$url/rest/v1/orders?id=eq.${oRace['id']}', BH, {
        'status': 'concluido',
      });
      final race = await Future.wait([
        req('POST', '$url/rest/v1/reviews', BH, {
          'order_id': oRace['id'],
          'buyer_id': buyerId,
          'target_id': sellerId,
          'stars': 4,
          'comment': 'race buyer',
          'author_role': 'buyer',
        }),
        req('POST', '$url/rest/v1/reviews', BH, {
          'order_id': oRace['id'],
          'buyer_id': buyerId,
          'target_id': sellerId,
          'stars': 3,
          'comment': 'race comprador',
          'author_role': 'comprador',
        }),
      ]);
      final okN = race.where((r) => (r['http'] as int) < 300).length;
      final cnt = await req(
        'GET',
        '$url/rest/v1/reviews?order_id=eq.${oRace['id']}&select=id,author_role',
        SVC,
      );
      final nRows = cnt['body'] is List ? (cnt['body'] as List).length : -1;
      probe('B7_race', {'okN': okN, 'nRows': nRows, 'bodies': race});
      if (nRows > 1) {
        hit(
          'RI-B-RACE',
          'P1',
          'REVIEW',
          'Race buyer+comprador deixou >1 review',
          {'nRows': nRows, 'race': race},
        );
      }
    }

    // spoof buyer_id / order
    final spoofB = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': oRev['id'],
      'buyer_id': sellerId,
      'target_id': sellerId,
      'stars': 1,
      'comment': 'spoof buyer',
      'author_role': 'comprador',
    });
    probe('B9_spoof_buyer', {'http': spoofB['http'], 'body': spoofB['body']});

    // auto-feedback JWT
    final af = await req('POST', '$url/rest/v1/rpc/batata_generate_auto_feedback', BH, {
      'p_now': DateTime.now().toUtc().add(const Duration(days: 4000)).toIso8601String(),
    });
    probe('B11_autofeedback_jwt', {'http': af['http'], 'body': af['body']});
  }

  // ===================== D MUX / VENDEDOR =====================
  final prof0 = row((await req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type',
    SVC,
  ))['body']);
  savedBuyerType = '${prof0?['user_type'] ?? 'comprador'}';
  await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyerId', SVC, {
    'user_type': 'comprador',
  });
  final muxPure = await req('POST', '$url/functions/v1/create-mux-live', BH, {
    'title': 'RI pure buyer',
  });
  probe('D_mux_pure_buyer', {
    'http': muxPure['http'],
    'body': muxPure['body'],
  });
  if ((muxPure['http'] as int) == 200) {
    hit(
      'RI-D-MUX-BUYER',
      'P1',
      'MUX',
      'Comprador puro criou Mux live',
      muxPure,
    );
  }

  final promo = await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyerId', BH, {
    'user_type': 'vendedor',
  });
  final afterPromo = row((await req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type',
    SVC,
  ))['body']);
  probe('D_promote', {
    'http': promo['http'],
    'type': afterPromo?['user_type'],
  });

  final adminTry = await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyerId', BH, {
    'user_type': 'admin',
  });
  final afterAdm = row((await req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type',
    SVC,
  ))['body']);
  probe('D_admin', {'http': adminTry['http'], 'type': afterAdm?['user_type']});
  if ('${afterAdm?['user_type']}'.toLowerCase() == 'admin') {
    hit('RI-D-ADMIN', 'P0', 'AUTHZ', 'Buyer auto-promoveu a admin', afterAdm!);
  }

  // stream keys alheias
  final livesSeller = await sb.select(
    'lives',
    filter: 'seller_id=eq.$sellerId',
    limit: 1,
  );
  if (livesSeller.isNotEmpty) {
    final lid = livesSeller.first['id'];
    final keysBuyer = await req(
      'GET',
      '$url/rest/v1/lives?id=eq.$lid&select=stream_key,mux_stream_key,mux_live_id',
      BH,
    );
    probe('D_foreign_keys', {
      'http': keysBuyer['http'],
      'body': keysBuyer['body'],
    });
    final kr = row(keysBuyer['body']);
    if (kr != null &&
        ((kr['stream_key'] != null && '${kr['stream_key']}'.isNotEmpty) ||
            (kr['mux_stream_key'] != null &&
                '${kr['mux_stream_key']}'.isNotEmpty))) {
      hit(
        'RI-D-STREAM-KEY',
        'P1',
        'MUX',
        'Buyer leu stream key de live alheia',
        kr,
      );
    }
  }

  // restore early
  await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyerId', SVC, {
    'user_type': savedBuyerType,
  });

  // ===================== E LIVE RESERVATIONS =====================
  final lives = await sb.select('lives', filter: 'seller_id=eq.$sellerId', limit: 1);
  if (lives.isEmpty) {
    probe('E_skip', 'no live');
  } else {
    final liveId = '${lives.first['id']}';
    final items = await sb.select(
      'live_items',
      filter: 'live_id=eq.$liveId',
      limit: 1,
    );
    if (items.isEmpty) {
      probe('E_skip', 'no item');
    } else {
      final li = items.first;
      final liId = '${li['id']}';
      await req(
        'DELETE',
        '$url/rest/v1/live_reservation_requests?buyer_id=eq.$buyerId&live_item_id=eq.$liId&status=in.(pending,accepted)',
        SVC,
      );
      // force qty 1 context if product present
      if (li['product_id'] != null) {
        await req(
          'PATCH',
          '$url/rest/v1/products?id=eq.${li['product_id']}',
          SVC,
          {'quantity': 1},
        );
      }
      await req('PATCH', '$url/rest/v1/live_items?id=eq.$liId', SVC, {
        'quantity': 1,
        'status': 'available',
      });

      final pend = await req(
        'POST',
        '$url/rest/v1/live_reservation_requests',
        BH,
        {
          'live_id': liveId,
          'live_item_id': liId,
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'requested_qty': 9,
          'status': 'accepted',
          'queue_position': 1,
          'source': 'fleaber_live',
        },
      );
      final pr = row(pend['body']);
      probe('E_pending_force_accepted', {
        'http': pend['http'],
        'status': pr?['status'],
        'qty': pr?['requested_qty'],
        'qpos': pr?['queue_position'],
      });
      if (pr != null && '${pr['status']}' == 'accepted') {
        hit(
          'RI-E-BUYER-ACCEPT-INSERT',
          'P1',
          'LIVE',
          'Buyer INSERT accepted directo',
          pr,
        );
      }

      if (pr != null) {
        final patchAcc = await req(
          'PATCH',
          '$url/rest/v1/live_reservation_requests?id=eq.${pr['id']}',
          BH,
          {'status': 'accepted', 'requested_qty': 9},
        );
        final afterB = row((await req(
          'GET',
          '$url/rest/v1/live_reservation_requests?id=eq.${pr['id']}&select=status,requested_qty',
          SVC,
        ))['body']);
        probe('E_buyer_patch_accepted', {
          'http': patchAcc['http'],
          'after': afterB,
        });
        if (afterB != null && '${afterB['status']}' == 'accepted') {
          hit(
            'RI-E-BUYER-PATCH-ACCEPT',
            'P1',
            'LIVE',
            'Buyer PATCH→accepted',
            afterB,
          );
        }

        // seller direct PATCH (bypass RPC)
        final sellerPatch = await req(
          'PATCH',
          '$url/rest/v1/live_reservation_requests?id=eq.${pr['id']}',
          SH,
          {'status': 'accepted', 'requested_qty': 9},
        );
        final afterS = row((await req(
          'GET',
          '$url/rest/v1/live_reservation_requests?id=eq.${pr['id']}&select=status,requested_qty',
          SVC,
        ))['body']);
        probe('E_seller_direct_patch', {
          'http': sellerPatch['http'],
          'after': afterS,
          'body': sellerPatch['body'],
        });
        if (afterS != null &&
            '${afterS['status']}' == 'accepted' &&
            n(afterS['requested_qty']) >= 9) {
          // check capacity via stock rpc if possible
          hit(
            'RI-E-SELLER-PATCH-OVER',
            'P1',
            'LIVE',
            'Seller PATCH directo accepted qty>=9 (possível bypass RPC capacity)',
            afterS,
          );
        }

        // seller RPC accept
        await req(
          'PATCH',
          '$url/rest/v1/live_reservation_requests?id=eq.${pr['id']}',
          SVC,
          {'status': 'pending', 'requested_qty': 9},
        );
        final rpc = await req(
          'POST',
          '$url/rest/v1/rpc/batata_process_live_reservation_request',
          SH,
          {'p_request_id': pr['id'], 'p_action': 'accept'},
        );
        probe('E_seller_rpc_accept', rpc);
        final rpcBody = rpc['body'];
        if (rpcBody is Map &&
            rpcBody['ok'] == true &&
            n(rpcBody['requested'] != null
                    ? rpcBody['requested']
                    : afterS?['requested_qty']) >
                1) {
          // ok only if capacity allows
        }
        if (rpcBody is Map &&
            rpcBody['ok'] == true &&
            (rpcBody['error'] == null)) {
          // verify reserved vs capacity
          final st = row((await req(
            'GET',
            '$url/rest/v1/live_reservation_requests?id=eq.${pr['id']}&select=status,requested_qty',
            SVC,
          ))['body']);
          if (st != null &&
              '${st['status']}' == 'accepted' &&
              n(st['requested_qty']) > 1) {
            // need available — if qty was forced 1, this is over
            final stock = await req(
              'POST',
              '$url/rest/v1/rpc/batata_live_item_stock',
              SH,
              {'p_live_item_id': liId},
            );
            probe('E_stock_after_rpc', stock);
            if (stock['body'] is Map &&
                n((stock['body'] as Map)['available_qty']) < 0) {
              hit(
                'RI-E-RPC-OVER',
                'P1',
                'LIVE',
                'RPC accept deixou available negativo',
                {'rpc': rpcBody, 'stock': stock['body']},
              );
            }
          }
        }

        // extreme qty
        for (final q in [0, -1, 100, 9999]) {
          final ex = await req(
            'POST',
            '$url/rest/v1/live_reservation_requests',
            BH,
            {
              'live_id': liveId,
              'live_item_id': liId,
              'buyer_id': buyerId,
              'seller_id': sellerId,
              'requested_qty': q,
              'status': 'pending',
              'source': 'fleaber_live',
            },
          );
          probe('E_qty_$q', {
            'http': ex['http'],
            'row': row(ex['body']),
            'body': ex['body'],
          });
        }

        await req(
          'DELETE',
          '$url/rest/v1/live_reservation_requests?buyer_id=eq.$buyerId&live_item_id=eq.$liId&status=in.(pending,accepted)',
          SVC,
        );
      }
    }
  }

  // ===================== F DISPUTES =====================
  final pD = await mkProduct(price: 11);
  final oD = await mkOrder(
    pid: '${pD['id']}',
    pm: 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    price: 11,
  );
  if (oD != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oD['id']}', SH, {
      'status': 'pago',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oD['id']}', SH, {
      'status': 'enviado',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oD['id']}', BH, {
      'status': 'concluido',
    });
    final dIns = await req('POST', '$url/rest/v1/order_disputes', BH, {
      'order_id': oD['id'],
      'buyer_id': buyerId,
      'reason': 'outro',
      'description': 'RI dispute probe independent',
    });
    final d = row(dIns['body']);
    probe('F_open', {'http': dIns['http'], 'row': d});
    if (d != null) {
      final turnB = await req(
        'PATCH',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}',
        BH,
        {'current_turn': 'administracao'},
      );
      final liveTurn = row((await req(
        'GET',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}&select=status,current_turn,seller_refund_percent',
        SVC,
      ))['body']);
      probe('F_buyer_turn_admin', {
        'http': turnB['http'],
        'live': liveTurn,
      });
      if (liveTurn != null &&
          '${liveTurn['current_turn']}' == 'administracao' &&
          '${liveTurn['status']}' != 'resolvida') {
        hit(
          'RI-F-TURN-OPEN',
          'P1',
          'DISPUTE',
          'Buyer pôs current_turn=administracao em disputa aberta',
          liveTurn,
        );
      }

      final turnS = await req(
        'PATCH',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}',
        SH,
        {'current_turn': 'administracao'},
      );
      final liveTurnS = row((await req(
        'GET',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}&select=status,current_turn',
        SVC,
      ))['body']);
      probe('F_seller_turn_admin', {
        'http': turnS['http'],
        'live': liveTurnS,
      });
      if (liveTurnS != null &&
          '${liveTurnS['current_turn']}' == 'administracao' &&
          '${liveTurnS['status']}' != 'resolvida') {
        hit(
          'RI-F-SELLER-TURN-OPEN',
          'P1',
          'DISPUTE',
          'Seller pôs current_turn=administracao em disputa aberta',
          liveTurnS,
        );
      }

      // buyer offer percent
      final pct = await req(
        'PATCH',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}',
        BH,
        {'seller_refund_percent': 100, 'seller_offer_type': 'partial_refund'},
      );
      final livePct = row((await req(
        'GET',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}&select=seller_refund_percent,seller_offer_type',
        SVC,
      ))['body']);
      probe('F_buyer_percent', {'http': pct['http'], 'live': livePct});
      if (livePct != null && n(livePct['seller_refund_percent']) == 100) {
        hit(
          'RI-F-BUYER-PCT',
          'P1',
          'DISPUTE',
          'Buyer definiu seller_refund_percent=100',
          livePct,
        );
      }

      // legit cancel
      final cancel = await req(
        'PATCH',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}',
        BH,
        {
          'status': 'resolvida',
          'buyer_decision': 'cancelled',
          'current_turn': 'administracao',
        },
      );
      final liveRes = row((await req(
        'GET',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}&select=status,current_turn,buyer_decision,seller_refund_percent',
        SVC,
      ))['body']);
      probe('F_legit_cancel', {'http': cancel['http'], 'live': liveRes});

      // terminal financial rewrite
      final termPct = await req(
        'PATCH',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}',
        SH,
        {'seller_refund_percent': 10, 'status': 'aberta'},
      );
      final liveTerm = row((await req(
        'GET',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}&select=status,current_turn,seller_refund_percent,admin_resolution',
        SVC,
      ))['body']);
      probe('F_terminal_rewrite', {
        'http': termPct['http'],
        'live': liveTerm,
      });
      if (liveTerm != null &&
          ('${liveTerm['status']}' == 'aberta' ||
              n(liveTerm['seller_refund_percent']) == 10)) {
        hit(
          'RI-F-TERMINAL',
          'P1',
          'DISPUTE',
          'JWT reescreveu disputa terminal',
          liveTerm,
        );
      }

      final adminF = await req(
        'PATCH',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}',
        BH,
        {
          'admin_resolution': 'full_refund',
          'admin_resolution_note': 'hijack',
        },
      );
      final liveAdm = row((await req(
        'GET',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}&select=admin_resolution,admin_resolution_note',
        SVC,
      ))['body']);
      probe('F_admin_fields', {'http': adminF['http'], 'live': liveAdm});
      if (liveAdm != null && liveAdm['admin_resolution'] == 'full_refund') {
        hit(
          'RI-F-ADMIN-FIELD',
          'P1',
          'DISPUTE',
          'Buyer escreveu admin_resolution',
          liveAdm,
        );
      }
    }
  }

  // ===================== G SAT-RT-01 =====================
  Future<void> tryStatus(
    String id,
    String pm,
    String from,
    String to,
    Map<String, String> who, {
    bool expectBlocked = true,
  }) async {
    final p = await mkProduct(price: 7);
    final o = await mkOrder(pid: '${p['id']}', pm: pm, price: 7);
    if (o == null) {
      probe(id, 'no order');
      return;
    }
    if (from != 'reserva_pendente') {
      await req('PATCH', '$url/rest/v1/orders?id=eq.${o['id']}', SVC, {
        'status': from,
      });
    }
    await req('PATCH', '$url/rest/v1/orders?id=eq.${o['id']}', who, {
      'status': to,
    });
    final after = await orderSnap('${o['id']}');
    final blocked = after != null && '${after['status']}' != to;
    probe(id, {'from': from, 'to': to, 'after': after?['status'], 'blocked': blocked});
    if (expectBlocked && !blocked) {
      hit(
        'RI-G-$id',
        'P0',
        'SAT-RT-01',
        'Transição unpaid $from→$to permitida',
        after!,
      );
    }
  }

  await tryStatus(
    'off_reserva_entregue',
    'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    'reserva_pendente',
    'entregue',
    BH,
  );
  await tryStatus(
    'off_reserva_concluido',
    'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    'reserva_pendente',
    'concluido',
    BH,
  );
  await tryStatus(
    'off_reservado_entregue',
    'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    'reservado',
    'entregue',
    BH,
  );
  await tryStatus(
    'app_reserva_concluido',
    'Pagamento na App',
    'reserva_pendente',
    'concluido',
    BH,
  );

  // legit MB WAY path
  final pLeg = await mkProduct(price: 9);
  final oLeg = await mkOrder(
    pid: '${pLeg['id']}',
    pm: 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    price: 9,
  );
  var legitOk = false;
  if (oLeg != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oLeg['id']}', SH, {
      'status': 'pago',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oLeg['id']}', SH, {
      'status': 'enviado',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oLeg['id']}', BH, {
      'status': 'concluido',
    });
    final st = await orderSnap('${oLeg['id']}');
    final rev = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': oLeg['id'],
      'buyer_id': buyerId,
      'target_id': sellerId,
      'stars': 5,
      'comment': 'RI legit',
      'author_role': 'comprador',
    });
    legitOk = st != null &&
        '${st['status']}' == 'concluido' &&
        (rev['http'] as int) < 300;
    probe('G_legit_mbway_cycle', {
      'order': st,
      'rev_http': rev['http'],
      'ok': legitOk,
    });
    if (!legitOk) {
      hit(
        'RI-G-LEGIT-BROKEN',
        'P1',
        'SAT-RT-01',
        'Fluxo MB WAY legítimo partido',
        {'st': st, 'rev': rev},
      );
    }
  }

  // ===================== H P0 SAMPLE =====================
  // contract JWT
  final pC = await mkProduct(price: 40);
  final oC = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pC['id'],
    'quantity': 1,
    'price_total': 0.4,
    'contract_unit_cents': 40,
    'contract_qty': 9,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na App',
    'shipping_method': 'entrega em mão',
  });
  final oCr = row(oC['body']);
  probe('H_contract', {
    'cuc': oCr?['contract_unit_cents'],
    'cq': oCr?['contract_qty'],
  });
  if (oCr != null &&
      (n(oCr['contract_unit_cents']) == 40 || n(oCr['contract_qty']) == 9)) {
    hit(
      'RI-H-CONTRACT',
      'P0',
      'CONTRACT',
      'JWT contract_* aceite',
      oCr,
    );
  }

  // internal flags
  final pF = await mkProduct(price: 5);
  final oF = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pF['id'],
    'quantity': 1,
    'price_total': 5,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na App',
    'shipping_method': 'entrega em mão',
    'stock_units_applied': 1,
    'amount_paid_cents': 500,
    'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String(),
  });
  final oFr = row(oF['body']);
  probe('H_flags', {
    'stock': oFr?['stock_units_applied'],
    'paid': oFr?['amount_paid_cents'],
    'wallet': oFr?['wallet_release_processed_at'],
  });
  if (oFr != null &&
      (n(oFr['stock_units_applied']) == 1 ||
          n(oFr['amount_paid_cents']) == 500 ||
          oFr['wallet_release_processed_at'] != null)) {
    hit('RI-H-FLAGS', 'P0', 'ORDER', 'JWT injectou flags internos', oFr);
  }

  // wallet balance patch
  final wPatch = await req(
    'PATCH',
    '$url/rest/v1/wallets?user_id=eq.$buyerId',
    BH,
    {'balance_cents': 999999},
  );
  probe('H_wallet_patch', {'http': wPatch['http'], 'body': wPatch['body']});

  // wallet insert
  final wIns = await req('POST', '$url/rest/v1/wallet_ledger', BH, {
    'user_id': buyerId,
    'amount_cents': 50000,
    'entry_type': 'credit',
    'reason': 'RI mint',
  });
  probe('H_wallet_ledger', {'http': wIns['http'], 'body': wIns['body']});
  if ((wIns['http'] as int) < 300) {
    hit('RI-H-WALLET-LEDGER', 'P0', 'WALLET', 'Buyer INSERT ledger', wIns);
  }

  // admin anon
  final anonProf = await req(
    'GET',
    '$url/rest/v1/profiles?select=id,user_type&limit=3',
    ANON,
  );
  probe('H_anon_profiles', {
    'http': anonProf['http'],
    'n': anonProf['body'] is List ? (anonProf['body'] as List).length : 0,
  });

  // lab rpc anon
  final lab = await req(
    'POST',
    '$url/rest/v1/rpc/batata_lab_clear_all_fm_pending',
    ANON,
    {},
  );
  probe('H_lab_anon', {'http': lab['http'], 'body': lab['body']});
  if ((lab['http'] as int) < 300) {
    hit('RI-H-LAB', 'P0', 'RPC', 'Anon lab clear', lab);
  }

  // alg=none rough
  final nonePayload = base64Url
      .encode(utf8.encode('{"sub":"$buyerId","role":"authenticated"}'))
      .replaceAll('=', '');
  final noneTok =
      'eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.$nonePayload.';
  final noneReq = await req(
    'GET',
    '$url/rest/v1/orders?select=id&limit=1',
    {
      'apikey': anon,
      'Authorization': 'Bearer $noneTok',
      'Content-Type': 'application/json',
    },
  );
  probe('H_alg_none', {'http': noneReq['http'], 'body': noneReq['body']});

  // phone
  final phone = await req(
    'PATCH',
    '$url/rest/v1/profiles?id=eq.$buyerId',
    BH,
    {'phone_verified_at': DateTime.now().toUtc().toIso8601String()},
  );
  final phoneAfter = row((await req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$buyerId&select=phone_verified_at',
    SVC,
  ))['body']);
  probe('H_phone', {'http': phone['http'], 'after': phoneAfter});

  // webhook unsigned smoke
  final wh = await req(
    'POST',
    '$url/functions/v1/stripe-webhook',
    {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
    },
    {'type': 'checkout.session.completed', 'data': {}},
  );
  probe('H_webhook', {'http': wh['http'], 'body': wh['body']});

  // composition: spoof pm + concluido
  final pComp = await mkProduct(price: 6);
  final oComp = await mkOrder(
    pid: '${pComp['id']}',
    pm: 'Pagamento na App (MB WAY/Transf)',
    price: 6,
  );
  if (oComp != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oComp['id']}', SH, {
      'status': 'pago',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oComp['id']}', BH, {
      'status': 'concluido',
    });
    final st = await orderSnap('${oComp['id']}');
    probe('X_comp_spoof_pm_cycle', {'status': st});
    if (st != null &&
        ('${st['status']}' == 'pago' || '${st['status']}' == 'concluido')) {
      hit(
        'RI-X-SPOOF-CYCLE',
        'P1',
        'COMPOSE',
        'Spoof PM permitiu ciclo pago/concluido',
        st,
      );
    }
  }

  await cleanup();

  final out = {
    'when': DateTime.now().toUtc().toIso8601String(),
    'staging': 'fxdknzrqjenzqcvnwqqq',
    'findings': findings,
    'probes': probes,
    'finding_count': findings.length,
  };
  File('tool/reports/RETESTE_INDEPENDENTE_FINAL_LOTE_2_AUDITORES_2026-08-27_RAW.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('FINDINGS=${findings.length}');
  for (final f in findings) {
    stdout.writeln('  ${f['sev']} ${f['id']} — ${f['impact']}');
  }
  exit(0);
}
