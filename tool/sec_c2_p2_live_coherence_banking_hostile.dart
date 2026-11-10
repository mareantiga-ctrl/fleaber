// ignore_for_file: avoid_print
/// C2-P2-01 live coherence + C2-P2-02 banking pós-aceitação.
/// dart run tool/sec_c2_p2_live_coherence_banking_hostile.dart
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
              ? await http.delete(
                  Uri.parse(u),
                  headers: h,
                  body: body == null ? null : jsonEncode(body),
                )
              : await http.get(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body};
}

String clip(Object? v, [int n = 200]) {
  final s = '$v';
  return s.length <= n ? s : s.substring(0, n);
}

bool hasBanking(dynamic body) {
  if (body is List && body.isNotEmpty) {
    final m = Map<String, dynamic>.from(body.first as Map);
    return '${m['iban'] ?? ''}'.trim().isNotEmpty ||
        '${m['mb_way'] ?? ''}'.trim().isNotEmpty;
  }
  return false;
}

String? rowId(dynamic body) {
  Object? id;
  if (body is List && body.isNotEmpty && body.first is Map) {
    id = (body.first as Map)['id'];
  } else if (body is Map) {
    id = body['id'];
  }
  final s = id?.toString().trim() ?? '';
  if (s.isEmpty || s == 'null') return null;
  return s;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
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
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  Future<Map<String, dynamic>> rpc(
    String name,
    Map<String, dynamic> body,
    Map<String, String> h,
  ) =>
      req('POST', '$url/rest/v1/rpc/$name', h, body);

  final tag = DateTime.now().millisecondsSinceEpoch;
  final cleanup = <Future Function()>[];

  // Two live_items from different lives (or fabricate second live)
  final items = await sb.select(
    'live_items',
    filter: 'product_id=not.is.null&status=eq.available',
    limit: 20,
  );
  if (items.length < 2) {
    stderr.writeln('Need >=2 live_items with product');
    exit(1);
  }
  // Prefer items where live_item.seller_id == products.seller_id (coerente)
  Map<String, dynamic>? itemA;
  Map<String, dynamic>? itemB;
  for (final a in items) {
    final pa = await sb.select(
      'products',
      filter: 'id=eq.${a['product_id']}',
      limit: 1,
    );
    if (pa.isEmpty) continue;
    final ps = '${pa.first['seller_id']}';
    final ls = '${a['seller_id'] ?? ''}';
    if (ls.isNotEmpty && ls != ps) continue;
    for (final b in items) {
      if ('${a['id']}' == '${b['id']}') continue;
      if ('${a['live_id']}' == '${b['live_id']}') continue;
      final pb = await sb.select(
        'products',
        filter: 'id=eq.${b['product_id']}',
        limit: 1,
      );
      if (pb.isEmpty) continue;
      itemA = {...a, 'seller_id': ps};
      itemB = b;
      break;
    }
    if (itemA != null) break;
  }
  if (itemA == null) {
    // fallback: any two different lives
    for (final a in items) {
      for (final b in items) {
        if ('${a['live_id']}' != '${b['live_id']}') {
          final pa = await sb.select(
            'products',
            filter: 'id=eq.${a['product_id']}',
            limit: 1,
          );
          itemA = {
            ...a,
            if (pa.isNotEmpty) 'seller_id': pa.first['seller_id'],
          };
          itemB = b;
          break;
        }
      }
      if (itemA != null) break;
    }
  }
  itemA ??= items[0];
  itemB ??= items.length > 1 ? items[1] : items[0];

  final liveA = '${itemA!['live_id']}';
  final liveB = '${itemB!['live_id']}';
  final liA = '${itemA['id']}';
  final liB = '${itemB['id']}';
  final prodA = '${itemA['product_id']}';
  final prodB = '${itemB['product_id']}';
  final sellerA = '${itemA['seller_id'] ?? sellerId}';

  // Wrong-seller probe: use a different seller uuid if available
  final otherSeller = sellerA == sellerId ? buyerId : sellerId;

  // Lab product for marketplace (no live)
  final labProds = await sb.select(
    'products',
    filter: 'seller_id=eq.$sellerId&quantity=gt.0',
    limit: 1,
  );
  final labPid = labProds.isNotEmpty ? '${labProds.first['id']}' : prodA;

  // Ensure seller has external payments
  await req('PATCH', '$url/rest/v1/profiles?id=eq.$sellerId', SVC, {
    'external_payments_enabled': true,
    'iban': 'PT50000201231234567890154',
    'mb_way': '911000000',
  });

  // ========== C2-P2-01 ==========
  final mix1 = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerA,
    'product_id': prodA,
    'live_id': liveA,
    'live_item_id': liB, // other live
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na App',
    'price_total': 10,
    'quantity': 1,
  });
  add(
    'P201_liveA_itemB_blocked',
    (mix1['http'] as int) >= 400,
    {'http': mix1['http'], 'body': clip(mix1['text'])},
  );

  final mix2 = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerA,
    'product_id': prodB, // wrong product for item A
    'live_id': liveA,
    'live_item_id': liA,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na App',
    'price_total': 10,
    'quantity': 1,
  });
  add(
    'P201_item_wrong_product_blocked',
    (mix2['http'] as int) >= 400,
    {'http': mix2['http'], 'body': clip(mix2['text'])},
  );

  final mix3 = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': otherSeller,
    'product_id': prodA,
    'live_id': liveA,
    'live_item_id': liA,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na App',
    'price_total': 10,
    'quantity': 1,
  });
  add(
    'P201_wrong_seller_blocked',
    (mix3['http'] as int) >= 400,
    {
      'http': mix3['http'],
      'claimed_seller': otherSeller,
      'auth_seller': sellerA,
      'body': clip(mix3['text']),
    },
  );

  // Coherent LIVE order
  final okLive = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerA,
    'product_id': prodA,
    'live_id': liveA,
    'live_item_id': liA,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na App',
    'price_total': 12,
    'quantity': 1,
  });
  final okLiveId = rowId(okLive['body']);
  add(
    'P201_coherent_live_ok',
    (okLive['http'] as int) >= 200 &&
        (okLive['http'] as int) < 300 &&
        okLiveId != null,
    {'http': okLive['http'], 'id': okLiveId, 'body': clip(okLive['text'])},
  );
  if (okLiveId != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$okLiveId', SVC);
    });

    // PATCH swap live_id / live_item / product / seller
    final pLive = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$okLiveId',
      BH,
      {'live_id': liveB},
    );
    final pItem = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$okLiveId',
      BH,
      {'live_item_id': liB},
    );
    final pProd = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$okLiveId',
      BH,
      {'product_id': prodB},
    );
    final pSel = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$okLiveId',
      BH,
      {'seller_id': buyerId},
    );
    final check = await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$okLiveId&select=live_id,live_item_id,product_id,seller_id',
      SVC,
    );
    final row = check['body'] is List && (check['body'] as List).isNotEmpty
        ? Map<String, dynamic>.from((check['body'] as List).first as Map)
        : <String, dynamic>{};
    add(
      'P201_patch_context_immutable',
      '${row['live_id']}' == liveA &&
          '${row['live_item_id']}' == liA &&
          '${row['product_id']}' == prodA &&
          '${row['seller_id']}' == sellerA,
      {
        'patch_https': [pLive['http'], pItem['http'], pProd['http'], pSel['http']],
        'final': row,
      },
    );
  } else {
    add('P201_patch_context_immutable', false, 'no coherent order');
  }

  // Marketplace sem live
  final mkt = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': labPid,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na App',
    'price_total': 8,
    'quantity': 1,
  });
  final mktId = rowId(mkt['body']);
  add(
    'P201_marketplace_no_live_ok',
    (mkt['http'] as int) >= 200 && (mkt['http'] as int) < 300,
    {'http': mkt['http'], 'id': mktId, 'body': clip(mkt['text'])},
  );
  if (mktId != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$mktId', SVC);
    });
  }

  // Valid UUIDs crossed (fake live_item)
  final crossUuid = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': labPid,
    'live_id': liveA,
    'live_item_id': '00000000-0000-0000-0000-000000000099',
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na App',
    'price_total': 8,
    'quantity': 1,
  });
  add(
    'P201_valid_uuid_cross_blocked',
    (crossUuid['http'] as int) >= 400,
    {'http': crossUuid['http'], 'body': clip(crossUuid['text'])},
  );

  // Checkout coherent (quote) — may fail for other reasons; must NOT accept mixed
  // Create legacy-like mixed via service_role then checkout should fail-closed
  final legacyMix = await req('POST', '$url/rest/v1/orders', SVC, {
    'buyer_id': buyerId,
    'seller_id': sellerA,
    'product_id': prodA,
    'live_id': liveA,
    'live_item_id': liB,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na App',
    'price_total': 12,
    'quantity': 1,
    'contract_unit_cents': 1200,
    'contract_qty': 1,
  });
  final legacyId = rowId(legacyMix['body']);
  // service_role bypasses JWT freeze but trigger still runs assert — should block INSERT
  add(
    'P201_svc_mixed_also_blocked_or_edge',
    (legacyMix['http'] as int) >= 400 || legacyId == null,
    {'http': legacyMix['http'], 'id': legacyId, 'body': clip(legacyMix['text'])},
  );
  if (legacyId != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$legacyId', SVC);
    });
    // If somehow inserted (shouldn't), edge must fail
    final edge = await req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      {
        'apikey': anon,
        'Authorization': 'Bearer $buyerTok',
        'Content-Type': 'application/json',
      },
      {
        'buyer_id': buyerId,
        'order_id': legacyId,
        'shipping_method': 'hand',
      },
    );
    add(
      'P201_checkout_legacy_mix_failclosed',
      (edge['http'] as int) >= 400,
      {'http': edge['http'], 'body': clip(edge['text'])},
    );
  } else {
    add('P201_checkout_legacy_mix_failclosed', true, {
      'note': 'insert blocked by trigger — edge path N/A',
    });
  }

  // Coherent checkout smoke (may 4xx for stock/status — not a finding if blocked for other reason)
  if (okLiveId != null) {
    final edgeOk = await req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      {
        'apikey': anon,
        'Authorization': 'Bearer $buyerTok',
        'Content-Type': 'application/json',
      },
      {
        'buyer_id': buyerId,
        'order_id': okLiveId,
        'shipping_method': 'hand',
      },
    );
    final edgeBody = clip(edgeOk['text']);
    final notLiveMismatch = !edgeBody.contains('live_id does not match') &&
        !edgeBody.contains('live item does not match');
    add(
      'P201_checkout_coherent_no_live_mismatch',
      notLiveMismatch,
      {'http': edgeOk['http'], 'body': edgeBody},
    );
  }

  // ========== C2-P2-02 ==========
  // Fresh buyer account
  final freshEmail = 'c2p2.fresh.$tag@axinoquaa.pt';
  final freshPass = 'TestFresh_$tag!';
  final createFresh = await req(
    'POST',
    '$url/auth/v1/admin/users',
    {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
      'Content-Type': 'application/json',
    },
    {'email': freshEmail, 'password': freshPass, 'email_confirm': true},
  );
  final freshId = '${(createFresh['body'] as Map?)?['id'] ?? ''}';
  if (freshId.isEmpty) {
    stderr.writeln('fresh user fail ${createFresh['body']}');
    exit(1);
  }
  cleanup.add(() async {
    await req('DELETE', '$url/auth/v1/admin/users/$freshId', {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
    });
  });
  await req('POST', '$url/rest/v1/profiles', SVC, {
    'id': freshId,
    'full_name': 'C2 Fresh',
    'user_type': 'comprador',
  });
  final freshTok = await sb.signIn(email: freshEmail, password: freshPass);
  final FH = {
    'apikey': anon,
    'Authorization': 'Bearer $freshTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final bank0 = await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': sellerId},
    FH,
  );
  add(
    'P202_fresh_no_relation_empty',
    !hasBanking(bank0['body']),
    {'body': bank0['body']},
  );

  final stripeHold = await req('POST', '$url/rest/v1/orders', FH, {
    'buyer_id': freshId,
    'seller_id': sellerId,
    'product_id': labPid,
    'status': 'reserva_pendente',
    'payment_method': 'Seguro Fleaber',
    'price_total': 9,
    'quantity': 1,
  });
  final stripeHoldId = rowId(stripeHold['body']);
  final bankStripe = await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': sellerId},
    FH,
  );
  add(
    'P202_seguro_reserva_pendente_empty',
    !hasBanking(bankStripe['body']),
    {
      'order_http': stripeHold['http'],
      'order_id': stripeHoldId,
      'rpc': bankStripe['body'],
    },
  );
  if (stripeHoldId != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$stripeHoldId', SVC);
    });
  }

  final mbHold = await req('POST', '$url/rest/v1/orders', FH, {
    'buyer_id': freshId,
    'seller_id': sellerId,
    'product_id': labPid,
    'status': 'reserva_pendente',
    'payment_method': 'MB WAY',
    'price_total': 9,
    'quantity': 1,
  });
  final mbHoldId = rowId(mbHold['body']);
  final bankMbPend = await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': sellerId},
    FH,
  );
  add(
    'P202_mbway_reserva_pendente_empty',
    (mbHold['http'] as int) < 300 && !hasBanking(bankMbPend['body']),
    {
      'order_http': mbHold['http'],
      'order_id': mbHoldId,
      'rpc': bankMbPend['body'],
      'body': clip(mbHold['text']),
    },
  );

  // Wrong seller
  final bankWrongSeller = await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': buyerId},
    FH,
  );
  add(
    'P202_wrong_seller_empty',
    !hasBanking(bankWrongSeller['body']),
    {'body': bankWrongSeller['body']},
  );

  // Other buyer's order shouldn't help — fresh has no access to lab buyer orders
  final bankOther = await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': sellerId},
    BH, // lab buyer may have historical — we check cancelled path separately
  );
  // Just document; not a fail if lab buyer has legitimate reservado

  // Cancelled
  if (mbHoldId != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$mbHoldId', SVC, {
      'status': 'cancelado',
    });
    final bankCancel = await rpc(
      'batata_seller_direct_payment_details',
      {'p_seller_id': sellerId},
      FH,
    );
    add(
      'P202_cancelled_empty',
      !hasBanking(bankCancel['body']),
      {'rpc': bankCancel['body']},
    );

    // Legitimate: set reservado + MB WAY
    await req('PATCH', '$url/rest/v1/orders?id=eq.$mbHoldId', SVC, {
      'status': 'reservado',
      'payment_method': 'MB WAY',
    });
    final bankOk = await rpc(
      'batata_seller_direct_payment_details',
      {'p_seller_id': sellerId},
      FH,
    );
    add(
      'P202_mbway_reservado_gets_pii',
      hasBanking(bankOk['body']),
      {'rpc': bankOk['body']},
    );

    // After pago — no longer reveal
    await req('PATCH', '$url/rest/v1/orders?id=eq.$mbHoldId', SVC, {
      'status': 'pago',
      'stock_units_applied': 1,
    });
    final bankPago = await rpc(
      'batata_seller_direct_payment_details',
      {'p_seller_id': sellerId},
      FH,
    );
    add(
      'P202_after_pago_empty',
      !hasBanking(bankPago['body']),
      {'rpc': bankPago['body']},
    );
  } else {
    add('P202_cancelled_empty', false, 'no mb hold');
    add('P202_mbway_reservado_gets_pii', false, 'no mb hold');
    add('P202_after_pago_empty', false, 'no mb hold');
  }

  // Cross-user: lab buyer vs fresh's order (if reservado was reset)
  // Recreate reservado for concurrency test
  final conc = await req('POST', '$url/rest/v1/orders', FH, {
    'buyer_id': freshId,
    'seller_id': sellerId,
    'product_id': labPid,
    'status': 'reserva_pendente',
    'payment_method': 'MB WAY',
    'price_total': 7,
    'quantity': 1,
  });
  final concId = rowId(conc['body']);
  if (concId != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$concId', SVC);
    });
    // Parallel: accept vs read before accept
    final before = await rpc(
      'batata_seller_direct_payment_details',
      {'p_seller_id': sellerId},
      FH,
    );
    add(
      'P202_toctou_before_accept_empty',
      !hasBanking(before['body']),
      {'rpc': before['body']},
    );
    await req('PATCH', '$url/rest/v1/orders?id=eq.$concId', SVC, {
      'status': 'reservado',
    });
    final after = await rpc(
      'batata_seller_direct_payment_details',
      {'p_seller_id': sellerId},
      FH,
    );
    add(
      'P202_toctou_after_accept_ok',
      hasBanking(after['body']),
      {'rpc': after['body']},
    );
    await req('PATCH', '$url/rest/v1/orders?id=eq.$concId', SVC, {
      'status': 'cancelado',
    });
    final afterCancel = await rpc(
      'batata_seller_direct_payment_details',
      {'p_seller_id': sellerId},
      FH,
    );
    add(
      'P202_toctou_after_cancel_empty',
      !hasBanking(afterCancel['body']),
      {'rpc': afterCancel['body']},
    );
  }

  // Lab buyer cannot read banking using only fresh's cancelled relation —
  // after cleanup fresh has no eligible order; if lab buyer has PII it is from lab history.
  add(
    'P202_fresh_isolation_documented',
    true,
    {
      'lab_buyer_has_own_eligible_pii': hasBanking(bankOther['body']),
      'note': 'lab buyer PII só se tiver order própria elegível — esperado',
    },
  );

  // ========== Regressões smoke ==========
  final wallet = await rpc(
    'batata_credit_wallet_once',
    {
      'p_user_id': buyerId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 1,
      'p_kind': 'x',
      'p_idempotency_key': 'c2-$tag',
    },
    BH,
  );
  add('REG_wallet_jwt_no_exec', (wallet['http'] as int) >= 400, {
    'http': wallet['http'],
  });

  final selfBank = await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': sellerId},
    SH,
  );
  add(
    'REG_seller_self_banking_ok',
    (selfBank['http'] as int) == 200 && hasBanking(selfBank['body']),
    {'rpc': selfBank['body']},
  );

  // Cleanup
  for (final c in cleanup.reversed) {
    try {
      await c();
    } catch (_) {}
  }

  final failed = results.where((r) => r['ok'] != true).toList();
  final out = {
    'at': DateTime.now().toIso8601String(),
    'project': 'fxdknzrqjenzqcvnwqqq',
    'production_touched': false,
    'stripe': 'TEST',
    'fase4': false,
    'pass': results.length - failed.length,
    'fail': failed.length,
    'results': results,
  };
  final path = 'tool/reports/sec_c2_p2_hostile_$tag.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('\nSUMMARY ${out['pass']}/${results.length} → $path');
  exit(failed.isEmpty ? 0 : 1);
}
