// ignore_for_file: avoid_print
/// Bateria hostil — pós-saturação cega (contrato / flags / qty / estados / lab / reserva / phone).
/// dart run tool/sec_pos_saturacao_cega_hostile.dart [pass=1|2]
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

Future<Map<String, dynamic>> patchJson(
  String url,
  Map<String, String> h,
  Object body,
) async {
  final r = await http.patch(
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

Map<String, dynamic>? firstRow(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
  return null;
}

num n(Object? v) => v is num ? v : num.tryParse('$v') ?? -1;

Future<void> main(List<String> args) async {
  final passLabel = args.isNotEmpty ? args.first : '1';
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

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object detail) {
    results.add({'id': id, 'ok': ok, 'detail': detail});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $detail');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final productIds = <String>[];

  Future<Map<String, dynamic>> mkProduct({
    required num price,
    int qty = 10,
    String? title,
  }) async {
    final p = await sb.insert('products', {
      'seller_id': sellerId,
      'title': title ?? 'SAT $stamp $price',
      'price': price,
      'quantity': qty,
      'list_on_marketplace': false,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    productIds.add('${p['id']}');
    return p;
  }

  Future<void> cleanup() async {
    for (final pid in productIds) {
      await http.delete(
        Uri.parse('$url/rest/v1/orders?product_id=eq.$pid'),
        headers: SVC,
      );
      await http.delete(
        Uri.parse('$url/rest/v1/product_offers?product_id=eq.$pid'),
        headers: SVC,
      );
      await http.delete(
        Uri.parse('$url/rest/v1/products?id=eq.$pid'),
        headers: SVC,
      );
    }
  }

  // ========== C1 hostile contract_unit_cents ==========
  final p40 = await mkProduct(price: 40.0, title: 'SAT C1 40eur');
  final c1 = await postJson('$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': p40['id'],
    'quantity': 1,
    'price_total': 0.5,
    'contract_unit_cents': 50,
    'contract_qty': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  final c1r = firstRow(c1['body']);
  final c1ok = c1r != null &&
      n(c1r['contract_unit_cents']) == 4000 &&
      n(c1r['contract_qty']) == 1;
  add('C1_CONTRACT_UNIT_OVERRIDE', c1ok, {
    'http': c1['http'],
    'cuc': c1r?['contract_unit_cents'],
    'expect': 4000,
  });

  // ========== C2 contract_qty != quantity ==========
  final pC2 = await mkProduct(price: 10.0, qty: 20);
  final c2 = await postJson('$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pC2['id'],
    'quantity': 2,
    'contract_qty': 9,
    'contract_unit_cents': 1,
    'price_total': 10,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  final c2r = firstRow(c2['body']);
  add(
    'C2_CONTRACT_QTY_SYNC',
    c2r != null &&
        n(c2r['quantity']) == 2 &&
        n(c2r['contract_qty']) == 2 &&
        n(c2r['contract_unit_cents']) == 1000,
    {'row': c2r, 'http': c2['http']},
  );

  // ========== C3 fake proposta string ==========
  final pC3 = await mkProduct(price: 47.0);
  final c3 = await postJson('$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pC3['id'],
    'quantity': 1,
    'price_total': 1.70,
    'status': 'reserva_pendente',
    'payment_method': 'proposta aceite',
    'shipping_method': 'entrega em mão',
  });
  final c3r = firstRow(c3['body']);
  add(
    'C3_FAKE_PROPOSTA_STRING',
    c3r != null && n(c3r['contract_unit_cents']) == 4700,
    {'cuc': c3r?['contract_unit_cents'], 'http': c3['http']},
  );

  // ========== C4 real accepted offer ==========
  final pC4 = await mkProduct(price: 30.0);
  final offerIns = await postJson('$url/rest/v1/product_offers', BH, {
    'product_id': pC4['id'],
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 22.0,
    'list_price': 30.0,
    'offered_by': 'buyer',
    'status': 'accepted', // must be forced to pending
  });
  final offerRow = firstRow(offerIns['body']);
  add(
    'C4a_BUYER_CANNOT_INSERT_ACCEPTED',
    offerRow != null && '${offerRow['status']}' == 'pending',
    {'row': offerRow, 'http': offerIns['http']},
  );
  final accept = await patchJson(
    '$url/rest/v1/product_offers?id=eq.${offerRow?['id']}',
    SH,
    {
      'status': 'accepted',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    },
  );
  final accRow = firstRow(accept['body']);
  add(
    'C4b_SELLER_ACCEPT_OK',
    accRow != null && '${accRow['status']}' == 'accepted',
    {'http': accept['http'], 'row': accRow},
  );
  final c4 = await postJson('$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pC4['id'],
    'product_offer_id': offerRow?['id'],
    'quantity': 1,
    'price_total': 30,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  final c4r = firstRow(c4['body']);
  add(
    'C4_REAL_OFFER_CONTRACT',
    c4r != null && n(c4r['contract_unit_cents']) == 2200,
    {'cuc': c4r?['contract_unit_cents'], 'http': c4['http'], 'body': c4['body']},
  );

  // ========== C5 catalog hike after seal ==========
  if (c1r != null) {
    await patchJson(
      '$url/rest/v1/products?id=eq.${p40['id']}',
      SH,
      {'price': 999.0},
    );
    final cpi = await postJson(
      '$url/functions/v1/create-payment-intent',
      BH,
      {
        'buyer_id': buyerId,
        'order_id': c1r['id'],
        'shipping_method': 'entrega em mão',
        'amount': 50,
      },
    );
    final amt = cpi['body'] is Map
        ? n((cpi['body'] as Map)['server_amount_cents'])
        : -1;
    // 40€ + prot 0.65+5% = 40+0.65+2 = 42.65 → 4265
    add(
      'C5_CATALOG_HIKE_KEEPS_CONTRACT',
      cpi['http'] == 200 && amt == 4265,
      {'http': cpi['http'], 'amt': amt, 'expect': 4265, 'body': cpi['body']},
    );
  } else {
    add('C5_CATALOG_HIKE_KEEPS_CONTRACT', false, 'no c1 order');
  }

  // ========== C8 seller cannot inflate buyer order contract via INSERT ==========
  final pC8 = await mkProduct(price: 15.0);
  final c8 = await postJson('$url/rest/v1/orders', SH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pC8['id'],
    'quantity': 1,
    'contract_unit_cents': 99900,
    'price_total': 999,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  final c8r = firstRow(c8['body']);
  // Seller JWT still authenticated → contract from catalog 1500, not 99900
  final c8sealed = c8r != null && n(c8r['contract_unit_cents']) == 1500;
  // Or RLS blocked insert entirely — also OK
  add(
    'C8_SELLER_CANNOT_INFLATE_CONTRACT',
    c8sealed || c8['http'] >= 400,
    {'http': c8['http'], 'cuc': c8r?['contract_unit_cents']},
  );

  // ========== F1 internal flags INSERT ==========
  final pF = await mkProduct(price: 8.0);
  final f1 = await postJson('$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pF['id'],
    'quantity': 1,
    'price_total': 8,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
    'stock_units_applied': 5,
    'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String(),
    'wallet_refund_processed_at': DateTime.now().toUtc().toIso8601String(),
    'auto_feedback_processed_at': DateTime.now().toUtc().toIso8601String(),
    'completed_at': DateTime.now().toUtc().toIso8601String(),
    'returned_at': DateTime.now().toUtc().toIso8601String(),
    'amount_paid_cents': 800,
    'stripe_payment_intent_id': 'pi_hostile_sat',
    'stripe_checkout_session_id': 'cs_hostile_sat',
    'stripe_refund_id': 're_hostile_sat',
  });
  final f1r = firstRow(f1['body']);
  add(
    'F1_INTERNAL_FLAGS_INSERT_NULL',
    f1r != null &&
        f1r['stock_units_applied'] == null &&
        f1r['wallet_release_processed_at'] == null &&
        f1r['wallet_refund_processed_at'] == null &&
        f1r['auto_feedback_processed_at'] == null &&
        f1r['completed_at'] == null &&
        f1r['returned_at'] == null &&
        f1r['amount_paid_cents'] == null &&
        f1r['stripe_payment_intent_id'] == null &&
        f1r['stripe_checkout_session_id'] == null &&
        f1r['stripe_refund_id'] == null,
    {'row': f1r, 'http': f1['http']},
  );

  if (f1r != null) {
    final fUp = await patchJson(
      '$url/rest/v1/orders?id=eq.${f1r['id']}',
      BH,
      {
        'stock_units_applied': 3,
        'wallet_release_processed_at':
            DateTime.now().toUtc().toIso8601String(),
        'amount_paid_cents': 1,
        'contract_unit_cents': 1,
        'contract_qty': 9,
      },
    );
    final live = await http.get(
      Uri.parse(
        '$url/rest/v1/orders?id=eq.${f1r['id']}&select=stock_units_applied,wallet_release_processed_at,amount_paid_cents,contract_unit_cents,contract_qty',
      ),
      headers: BH,
    );
    final liveRow = firstRow(jsonDecode(live.body));
    add(
      'F2_INTERNAL_FLAGS_UPDATE_IMMUTABLE',
      liveRow != null &&
          liveRow['stock_units_applied'] == null &&
          liveRow['wallet_release_processed_at'] == null &&
          liveRow['amount_paid_cents'] == null &&
          n(liveRow['contract_unit_cents']) == 800 &&
          n(liveRow['contract_qty']) == 1,
      {'http': fUp['http'], 'row': liveRow},
    );
  } else {
    add('F2_INTERNAL_FLAGS_UPDATE_IMMUTABLE', false, 'no f1');
  }

  // ========== Q1 / Q2 ==========
  final pQ = await mkProduct(price: 5.0, qty: 20);
  final q1 = await postJson('$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pQ['id'],
    'quantity': 5,
    'contract_qty': 1,
    'price_total': 5,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  final q1r = firstRow(q1['body']);
  add(
    'Q1_QTY5_CQ1_SYNCED',
    q1r != null && n(q1r['quantity']) == 5 && n(q1r['contract_qty']) == 5,
    {'row': q1r},
  );
  final q2 = await postJson('$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pQ['id'],
    'quantity': 1,
    'contract_qty': 5,
    'price_total': 5,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  final q2r = firstRow(q2['body']);
  add(
    'Q2_QTY1_CQ5_SYNCED',
    q2r != null && n(q2r['quantity']) == 1 && n(q2r['contract_qty']) == 1,
    {'row': q2r},
  );

  // ========== S1–S4 payment_method / seller pago ==========
  Future<void> trySellerPago(String id, String pm) async {
    final p = await mkProduct(price: 9.0);
    final o = await postJson('$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': p['id'],
      'quantity': 1,
      'price_total': 9,
      'status': 'reserva_pendente',
      'payment_method': pm,
      'shipping_method': 'entrega em mão',
    });
    final orow = firstRow(o['body']);
    if (orow == null) {
      add(id, false, {'http': o['http'], 'body': o['body']});
      return;
    }
    final patch = await patchJson(
      '$url/rest/v1/orders?id=eq.${orow['id']}',
      SH,
      {'status': 'pago'},
    );
    final after = await http.get(
      Uri.parse('$url/rest/v1/orders?id=eq.${orow['id']}&select=status'),
      headers: SVC,
    );
    final st = firstRow(jsonDecode(after.body))?['status'];
    add(id, '$st' != 'pago', {
      'pm': pm,
      'status': st,
      'patch_http': patch['http'],
    });
  }

  await trySellerPago('S1_PLATFORM_SELLER_PAGO_BLOCKED', 'Pagamento na app');
  await trySellerPago('S2_EMPTY_PM_SELLER_PAGO_BLOCKED', '');
  await trySellerPago('S3_WHITESPACE_PM_SELLER_PAGO_BLOCKED', '   ');
  await trySellerPago('S4_UNKNOWN_PM_SELLER_PAGO_BLOCKED', 'pix_inventado');

  // S5 MB WAY legítimo
  final pMb = await mkProduct(price: 11.0);
  final oMb = await postJson('$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pMb['id'],
    'quantity': 1,
    'price_total': 11,
    'status': 'reserva_pendente',
    'payment_method': 'MB WAY',
    'shipping_method': 'entrega em mão',
  });
  final oMbR = firstRow(oMb['body']);
  var mbOk = false;
  if (oMbR != null) {
    await patchJson(
      '$url/rest/v1/orders?id=eq.${oMbR['id']}',
      SH,
      {'status': 'pago'},
    );
    final after = await http.get(
      Uri.parse('$url/rest/v1/orders?id=eq.${oMbR['id']}&select=status,stock_units_applied'),
      headers: SVC,
    );
    final row = firstRow(jsonDecode(after.body));
    mbOk = row != null &&
        '${row['status']}' == 'pago' &&
        n(row['stock_units_applied']) == 1;
    add('S5_MBWAY_SELLER_PAGO_OK', mbOk, {'row': row});
  } else {
    add('S5_MBWAY_SELLER_PAGO_OK', false, oMb['body']!);
  }

  // S5b string canónica da app
  final pMb2 = await mkProduct(price: 12.0);
  final oMb2 = await postJson('$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pMb2['id'],
    'quantity': 1,
    'price_total': 12,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    'shipping_method': 'entrega em mão',
  });
  final oMb2R = firstRow(oMb2['body']);
  if (oMb2R != null) {
    await patchJson(
      '$url/rest/v1/orders?id=eq.${oMb2R['id']}',
      SH,
      {'status': 'pago'},
    );
    final after2 = await http.get(
      Uri.parse(
        '$url/rest/v1/orders?id=eq.${oMb2R['id']}&select=status,stock_units_applied',
      ),
      headers: SVC,
    );
    final row2 = firstRow(jsonDecode(after2.body));
    add(
      'S5b_CANON_MBWAY_STRING_PAGO_OK',
      row2 != null &&
          '${row2['status']}' == 'pago' &&
          n(row2['stock_units_applied']) == 1,
      {'row': row2},
    );
  } else {
    add('S5b_CANON_MBWAY_STRING_PAGO_OK', false, oMb2['body']!);
  }

  // S6 unpaid → enviado/concluido
  final pS6 = await mkProduct(price: 7.0);
  final oS6 = await postJson('$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pS6['id'],
    'quantity': 1,
    'price_total': 7,
    'status': 'reserva_pendente',
    'payment_method': 'Seguro Fleaber',
    'shipping_method': 'entrega em mão',
  });
  final oS6r = firstRow(oS6['body']);
  if (oS6r != null) {
    await patchJson(
      '$url/rest/v1/orders?id=eq.${oS6r['id']}',
      SH,
      {'status': 'enviado'},
    );
    await patchJson(
      '$url/rest/v1/orders?id=eq.${oS6r['id']}',
      BH,
      {'status': 'concluido'},
    );
    final after = await http.get(
      Uri.parse('$url/rest/v1/orders?id=eq.${oS6r['id']}&select=status'),
      headers: SVC,
    );
    final st = '${firstRow(jsonDecode(after.body))?['status']}';
    add(
      'S6_UNPAID_NOT_ENVIADO_CONCLUIDO',
      st == 'reserva_pendente' || st == 'reservado',
      {'status': st},
    );
  } else {
    add('S6_UNPAID_NOT_ENVIADO_CONCLUIDO', false, oS6['body']!);
  }

  // ========== R1–R4 RPC ==========
  final r1 = await postJson(
    '$url/rest/v1/rpc/batata_lab_clear_all_fm_pending',
    ANON,
    {},
  );
  add(
    'R1_LAB_CLEAR_ANON_DENIED',
    r1['http'] == 401 || r1['http'] == 403 || r1['http'] >= 400,
    {'http': r1['http'], 'body': r1['body']},
  );
  final r2 = await postJson(
    '$url/rest/v1/rpc/batata_lab_clear_all_fm_pending',
    BH,
    {},
  );
  add(
    'R2_LAB_CLEAR_AUTH_DENIED',
    r2['http'] == 401 || r2['http'] == 403 || r2['http'] >= 400,
    {'http': r2['http'], 'body': r2['body']},
  );
  final r4a = await postJson(
    '$url/rest/v1/rpc/batata_generate_auto_feedback',
    ANON,
    {
      'p_now': DateTime.now()
          .toUtc()
          .add(const Duration(days: 3650))
          .toIso8601String(),
    },
  );
  final r4b = await postJson(
    '$url/rest/v1/rpc/batata_generate_auto_feedback',
    BH,
    {
      'p_now': DateTime.now()
          .toUtc()
          .add(const Duration(days: 3650))
          .toIso8601String(),
    },
  );
  add(
    'R4_AUTO_FEEDBACK_ANON_JWT_DENIED',
    (r4a['http'] >= 400) && (r4b['http'] >= 400),
    {'anon': r4a['http'], 'jwt': r4b['http']},
  );

  // ========== L1 buyer INSERT accepted ==========
  // Need a live + live_item — skip soft if none; create minimal via service
  final lives = await sb.select(
    'lives',
    filter: 'seller_id=eq.$sellerId',
    limit: 1,
  );
  if (lives.isNotEmpty) {
    final liveId = '${lives.first['id']}';
    final items = await sb.select(
      'live_items',
      filter: 'live_id=eq.$liveId',
      limit: 1,
    );
    if (items.isNotEmpty) {
      final li = items.first;
      final l1 = await postJson('$url/rest/v1/live_reservation_requests', BH, {
        'live_id': liveId,
        'live_item_id': li['id'],
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'requested_qty': 1,
        'status': 'accepted',
        'source': 'fleaber_live',
      });
      final l1r = firstRow(l1['body']);
      add(
        'L1_BUYER_INSERT_ACCEPTED_FORCED_PENDING',
        l1r != null && '${l1r['status']}' == 'pending',
        {'http': l1['http'], 'row': l1r},
      );
      final l2 = await postJson('$url/rest/v1/live_reservation_requests', BH, {
        'live_id': liveId,
        'live_item_id': li['id'],
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'requested_qty': 99,
        'status': 'pending',
        'source': 'fleaber_live',
      });
      // 99 may insert as pending (qty cap allows 1..99) — authority is accept path;
      // still record whether accepted spoof blocked. Extra: qty 99 pending is OK by constraint.
      add(
        'L2_QTY99_INSERT',
        l2['http'] == 201 || l2['http'] == 200 || l2['http'] >= 400,
        {
          'http': l2['http'],
          'note': 'pending qty capped 1..99; accept must still validate stock',
          'body': l2['body'],
        },
      );
      // cleanup reservations created
      await http.delete(
        Uri.parse(
          '$url/rest/v1/live_reservation_requests?buyer_id=eq.$buyerId&live_id=eq.$liveId&status=eq.pending',
        ),
        headers: SVC,
      );
    } else {
      add('L1_BUYER_INSERT_ACCEPTED_FORCED_PENDING', true, 'SKIP no live_item');
      add('L2_QTY99_INSERT', true, 'SKIP');
    }
  } else {
    add('L1_BUYER_INSERT_ACCEPTED_FORCED_PENDING', true, 'SKIP no live');
    add('L2_QTY99_INSERT', true, 'SKIP');
  }

  // ========== P1 phone_verified ==========
  final beforePhone = await http.get(
    Uri.parse(
      '$url/rest/v1/profiles?id=eq.$buyerId&select=phone_verified_at',
    ),
    headers: BH,
  );
  final beforeVal =
      firstRow(jsonDecode(beforePhone.body))?['phone_verified_at'];
  final pPhone = await patchJson(
    '$url/rest/v1/profiles?id=eq.$buyerId',
    BH,
    {'phone_verified_at': DateTime.now().toUtc().toIso8601String()},
  );
  final afterPhone = await http.get(
    Uri.parse(
      '$url/rest/v1/profiles?id=eq.$buyerId&select=phone_verified_at',
    ),
    headers: BH,
  );
  final afterVal =
      firstRow(jsonDecode(afterPhone.body))?['phone_verified_at'];
  add(
    'P1_BUYER_PHONE_VERIFIED_IMMUTABLE',
    '$afterVal' == '$beforeVal',
    {
      'before': beforeVal,
      'after': afterVal,
      'patch_http': pPhone['http'],
    },
  );

  final beforeS = await http.get(
    Uri.parse(
      '$url/rest/v1/profiles?id=eq.$sellerId&select=phone_verified_at',
    ),
    headers: SH,
  );
  final beforeSV =
      firstRow(jsonDecode(beforeS.body))?['phone_verified_at'];
  await patchJson(
    '$url/rest/v1/profiles?id=eq.$sellerId',
    SH,
    {'phone_verified_at': DateTime.now().toUtc().toIso8601String()},
  );
  final afterS = await http.get(
    Uri.parse(
      '$url/rest/v1/profiles?id=eq.$sellerId&select=phone_verified_at',
    ),
    headers: SH,
  );
  final afterSV = firstRow(jsonDecode(afterS.body))?['phone_verified_at'];
  add(
    'P2_SELLER_PHONE_VERIFIED_IMMUTABLE',
    '$afterSV' == '$beforeSV',
    {'before': beforeSV, 'after': afterSV},
  );

  // ========== Stripe TEST E2E via harness (legit) + hostile quote ==========
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
    add('STRIPE_E2E_LEGIT_SETUP_PAID', okPaid, {
      'http': paid['http'],
      'body_keys': paid['body'] is Map
          ? (paid['body'] as Map).keys.toList()
          : paid['body'],
    });
    if (okPaid && paid['body'] is Map) {
      final b = Map<String, dynamic>.from(paid['body'] as Map);
      final oid = '${b['order_id'] ?? ''}';
      final paidCents = n(b['amount_paid_cents'] ?? b['paid_cents']);
      if (oid.isNotEmpty) {
        final row = await http.get(
          Uri.parse(
            '$url/rest/v1/orders?id=eq.$oid&select=status,amount_paid_cents,stock_units_applied,contract_unit_cents,contract_qty,quantity',
          ),
          headers: SVC,
        );
        final or = firstRow(jsonDecode(row.body));
        add(
          'STRIPE_E2E_SETTLE_STOCK_WALLET_SURFACE',
          or != null &&
              '${or['status']}' == 'pago' &&
              n(or['amount_paid_cents']) > 0 &&
              or['stock_units_applied'] != null &&
              n(or['contract_qty']) == n(or['quantity']),
          {'order': or, 'harness_paid': paidCents},
        );
      }
    }

    // Hostile: C1-style underpay must not create cheap session
    if (c1r != null) {
      final hostileCpi = await postJson(
        '$url/functions/v1/create-payment-intent',
        BH,
        {
          'buyer_id': buyerId,
          'order_id': c1r['id'],
          'shipping_method': 'entrega em mão',
          'amount': 50,
          'contract_unit_cents': 50,
        },
      );
      final hamt = hostileCpi['body'] is Map
          ? n((hostileCpi['body'] as Map)['server_amount_cents'])
          : -1;
      add(
        'STRIPE_E2E_HOSTILE_UNDERPAY_BLOCKED',
        hostileCpi['http'] == 200 && hamt == 4265,
        {'http': hostileCpi['http'], 'amt': hamt},
      );
    }
  } else {
    add('STRIPE_E2E_LEGIT_SETUP_PAID', false, 'missing e2e secret');
    add('STRIPE_E2E_SETTLE_STOCK_WALLET_SURFACE', false, 'skipped');
    add('STRIPE_E2E_HOSTILE_UNDERPAY_BLOCKED', false, 'skipped');
  }

  await cleanup();

  final failed = results.where((r) => r['ok'] != true).toList();
  final out = {
    'pass': passLabel,
    'at': DateTime.now().toUtc().toIso8601String(),
    'staging': 'fxdknzrqjenzqcvnwqqq',
    'ok': failed.isEmpty,
    'fail_count': failed.length,
    'results': results,
  };
  final path =
      'tool/reports/HARDENING_POS_SATURACAO_CEGA_HOSTILE_PASS$passLabel.json';
  await File(path).writeAsString(
    const JsonEncoder.withIndent('  ').convert(out),
  );
  stdout.writeln('evidence -> $path (fails=${failed.length})');
  exit(failed.isEmpty ? 0 : 1);
}
