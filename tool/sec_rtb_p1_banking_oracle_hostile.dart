// ignore_for_file: avoid_print
/// RTB FAIL_P1 — banking oracle + P2 email/reviews/storage hostile battery.
/// dart run tool/sec_rtb_p1_banking_oracle_hostile.dart
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
              : method == 'HEAD'
                  ? await http.head(Uri.parse(u), headers: h)
                  : await http.get(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body};
}

String clip(Object? v, [int n = 180]) {
  final s = '$v';
  return s.length <= n ? s : s.substring(0, n);
}

bool hasBanking(dynamic body) {
  if (body is List && body.isNotEmpty) {
    final m = Map<String, dynamic>.from(body.first as Map);
    final iban = '${m['iban'] ?? ''}'.trim();
    final mb = '${m['mb_way'] ?? ''}'.trim();
    return iban.isNotEmpty || mb.isNotEmpty;
  }
  if (body is Map) {
    final iban = '${body['iban'] ?? ''}'.trim();
    final mb = '${body['mb_way'] ?? ''}'.trim();
    return iban.isNotEmpty || mb.isNotEmpty;
  }
  return false;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: not staging');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerEmail = envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final sellerEmail = envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerTok = await sb.signIn(
    email: buyerEmail,
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: sellerEmail,
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
  final ANON = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
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

  // --- Victim seller (fresh, no historical buyer relation) ---
  final victimEmail = 'rtb.victim.$tag@fleaber.test';
  final victimPass = 'TestVictim_$tag!';
  final createU = await req(
    'POST',
    '$url/auth/v1/admin/users',
    {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
      'Content-Type': 'application/json',
    },
    {
      'email': victimEmail,
      'password': victimPass,
      'email_confirm': true,
    },
  );
  final victimId = '${(createU['body'] as Map?)?['id'] ?? ''}';
  if (victimId.isEmpty) {
    stderr.writeln('FAIL create victim: ${createU['body']}');
    exit(1);
  }
  cleanup.add(() async {
    await req('DELETE', '$url/auth/v1/admin/users/$victimId', {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
    });
  });

  await req('POST', '$url/rest/v1/profiles', SVC, {
    'id': victimId,
    'full_name': 'RTB Victim $tag',
    'user_type': 'vendedor',
    'iban': 'PT50000201231234567890154',
    'mb_way': '911000000',
    'external_payments_enabled': true,
  });
  // upsert if conflict
  await req('PATCH', '$url/rest/v1/profiles?id=eq.$victimId', SVC, {
    'iban': 'PT50000201231234567890154',
    'mb_way': '911000000',
    'external_payments_enabled': true,
    'user_type': 'vendedor',
  });

  final victimProd = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': victimId,
    'title': 'RTB victim sku $tag',
    'price': 12.0,
    'quantity': 3,
    'ref_code': 'RTB-$tag',
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final victimProductId =
      '${((victimProd['body'] is List && (victimProd['body'] as List).isNotEmpty) ? (victimProd['body'] as List).first['id'] : (victimProd['body'] is Map ? (victimProd['body'] as Map)['id'] : ''))}';

  // Seller lab product for cross-seller tests
  final labProds = await sb.select(
    'products',
    filter: 'seller_id=eq.$sellerId&quantity=gt.0',
    limit: 1,
  );
  final labProductId =
      labProds.isNotEmpty ? '${labProds.first['id']}' : '';

  Future<Map<String, dynamic>> banking(String sid, Map<String, String> h) =>
      rpc('batata_seller_direct_payment_details', {'p_seller_id': sid}, h);

  // ========== T1 — original attack ==========
  final t1Bundle = await req('POST', '$url/rest/v1/product_bundles', BH, {
    'seller_id': victimId,
    'buyer_id': buyerId,
    'product_ids': ['00000000-0000-0000-0000-000000000001'],
    'subtotal_eur': 1,
    'discount_pct': 0,
    'discount_eur': 0,
    'total_eur': 1,
    'status': 'pending',
  });
  final t1Rpc = await banking(victimId, BH);
  add(
    'T1_original_dummy_bundle',
    (t1Bundle['http'] as int) >= 400 && !hasBanking(t1Rpc['body']),
    {
      'bundle_http': t1Bundle['http'],
      'bundle_body': clip(t1Bundle['text']),
      'rpc_http': t1Rpc['http'],
      'rpc_has_pii': hasBanking(t1Rpc['body']),
      'rpc_body': t1Rpc['body'],
    },
  );

  // ========== T2 — dummy product (same) ==========
  add(
    'T2_dummy_product',
    (t1Bundle['http'] as int) >= 400 && !hasBanking(t1Rpc['body']),
    {'note': 'covered by T1 insert reject + empty rpc'},
  );

  // ========== T3 — product of other seller ==========
  final t3 = await req('POST', '$url/rest/v1/product_bundles', BH, {
    'seller_id': victimId,
    'buyer_id': buyerId,
    'product_ids': labProductId.isEmpty
        ? ['00000000-0000-0000-0000-000000000099']
        : [labProductId],
    'subtotal_eur': 1,
    'discount_pct': 0,
    'discount_eur': 0,
    'total_eur': 1,
    'status': 'pending',
  });
  final t3Rpc = await banking(victimId, BH);
  add(
    'T3_other_seller_product',
    (t3['http'] as int) >= 400 && !hasBanking(t3Rpc['body']),
    {'bundle_http': t3['http'], 'rpc_pii': hasBanking(t3Rpc['body'])},
  );

  // ========== T4 — pending unilateral with REAL victim product ==========
  final t4 = await req('POST', '$url/rest/v1/product_bundles', BH, {
    'seller_id': victimId,
    'buyer_id': buyerId,
    'product_ids': [victimProductId],
    'subtotal_eur': 12,
    'discount_pct': 0,
    'discount_eur': 0,
    'total_eur': 12,
    'status': 'pending',
  });
  final t4Rpc = await banking(victimId, BH);
  final t4OkInsert = (t4['http'] as int) >= 200 && (t4['http'] as int) < 300;
  add(
    'T4_pending_real_product_no_pii',
    t4OkInsert && !hasBanking(t4Rpc['body']),
    {
      'bundle_http': t4['http'],
      'bundle_id': t4OkInsert && t4['body'] is List
          ? (t4['body'] as List).first['id']
          : null,
      'rpc_pii': hasBanking(t4Rpc['body']),
    },
  );
  String? t4BundleId;
  if (t4OkInsert && t4['body'] is List && (t4['body'] as List).isNotEmpty) {
    t4BundleId = '${(t4['body'] as List).first['id']}';
    cleanup.add(() async {
      await req(
        'DELETE',
        '$url/rest/v1/product_bundles?id=eq.$t4BundleId',
        SVC,
      );
    });
  }

  // ========== T5 — swap seller_id after insert ==========
  if (t4BundleId != null) {
    final t5 = await req(
      'PATCH',
      '$url/rest/v1/product_bundles?id=eq.$t4BundleId',
      BH,
      {'seller_id': sellerId},
    );
    final check = await req(
      'GET',
      '$url/rest/v1/product_bundles?id=eq.$t4BundleId&select=seller_id',
      SVC,
    );
    final sid = check['body'] is List && (check['body'] as List).isNotEmpty
        ? '${(check['body'] as List).first['seller_id']}'
        : '';
    add(
      'T5_buyer_swap_seller_id',
      sid == victimId,
      {'patch_http': t5['http'], 'seller_id_final': sid},
    );
  } else {
    add('T5_buyer_swap_seller_id', false, 'no t4 bundle');
  }

  // ========== T6 — buyer_id spoof ==========
  final t6 = await req('POST', '$url/rest/v1/product_bundles', BH, {
    'seller_id': victimId,
    'buyer_id': sellerId, // not self
    'product_ids': [victimProductId],
    'subtotal_eur': 1,
    'discount_pct': 0,
    'discount_eur': 0,
    'total_eur': 1,
    'status': 'pending',
  });
  add(
    'T6_buyer_id_spoof',
    (t6['http'] as int) >= 400,
    {'http': t6['http'], 'body': clip(t6['text'], 120)},
  );

  // ========== T7 — legitimate relation ==========
  final t7Bundle = await req('POST', '$url/rest/v1/product_bundles', SVC, {
    'seller_id': victimId,
    'buyer_id': buyerId,
    'product_ids': [victimProductId],
    'subtotal_eur': 12,
    'discount_pct': 0,
    'discount_eur': 0,
    'total_eur': 12,
    'status': 'accepted',
  });
  final t7BundleId = t7Bundle['body'] is List &&
          (t7Bundle['body'] as List).isNotEmpty
      ? '${(t7Bundle['body'] as List).first['id']}'
      : '';
  final t7Order = await req('POST', '$url/rest/v1/orders', SVC, {
    'buyer_id': buyerId,
    'seller_id': victimId,
    'product_id': victimProductId,
    'bundle_id': t7BundleId.isEmpty ? null : t7BundleId,
    'status': 'reservado',
    'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    'price_total': 12,
    'quantity': 1,
    'is_reservation': true,
  });
  final t7OrderId = t7Order['body'] is List && (t7Order['body'] as List).isNotEmpty
      ? '${(t7Order['body'] as List).first['id']}'
      : (t7Order['body'] is Map ? '${(t7Order['body'] as Map)['id']}' : '');
  final t7Rpc = await banking(victimId, BH);
  add(
    'T7_legitimate_offplatform_gets_pii',
    hasBanking(t7Rpc['body']),
    {
      'bundle_http': t7Bundle['http'],
      'order_http': t7Order['http'],
      'order_id': t7OrderId,
      'rpc': t7Rpc['body'],
    },
  );
  cleanup.add(() async {
    if (t7OrderId.isNotEmpty) {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$t7OrderId', SVC);
    }
    if (t7BundleId.isNotEmpty) {
      await req('DELETE', '$url/rest/v1/product_bundles?id=eq.$t7BundleId', SVC);
    }
  });

  // ========== T8 — cross-user (second buyer) ==========
  final buyer2Email = 'rtb.buyer2.$tag@fleaber.test';
  final createB2 = await req(
    'POST',
    '$url/auth/v1/admin/users',
    {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
      'Content-Type': 'application/json',
    },
    {
      'email': buyer2Email,
      'password': victimPass,
      'email_confirm': true,
    },
  );
  final buyer2Id = '${(createB2['body'] as Map?)?['id'] ?? ''}';
  cleanup.add(() async {
    if (buyer2Id.isNotEmpty) {
      await req('DELETE', '$url/auth/v1/admin/users/$buyer2Id', {
        'apikey': svc,
        'Authorization': 'Bearer $svc',
      });
    }
  });
  await req('POST', '$url/rest/v1/profiles', SVC, {
    'id': buyer2Id,
    'full_name': 'RTB Buyer2',
    'user_type': 'comprador',
  });
  final b2Tok = await sb.signIn(email: buyer2Email, password: victimPass);
  final B2H = {
    'apikey': anon,
    'Authorization': 'Bearer $b2Tok',
    'Content-Type': 'application/json',
  };
  final t8Rpc = await banking(victimId, B2H);
  add(
    'T8_cross_user_no_pii',
    !hasBanking(t8Rpc['body']),
    {'rpc': t8Rpc['body']},
  );

  // ========== T9 — external payments OFF ==========
  await req('PATCH', '$url/rest/v1/profiles?id=eq.$victimId', SVC, {
    'external_payments_enabled': false,
  });
  final t9Rpc = await banking(victimId, BH);
  add(
    'T9_external_payments_off',
    !hasBanking(t9Rpc['body']),
    {'rpc': t9Rpc['body']},
  );
  await req('PATCH', '$url/rest/v1/profiles?id=eq.$victimId', SVC, {
    'external_payments_enabled': true,
  });

  // ========== T10 — cancel order / bundle ==========
  if (t7OrderId.isNotEmpty) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$t7OrderId', SVC, {
      'status': 'cancelado',
    });
  }
  if (t7BundleId.isNotEmpty) {
    await req('PATCH', '$url/rest/v1/product_bundles?id=eq.$t7BundleId', SVC, {
      'status': 'cancelled',
    });
  }
  final t10Rpc = await banking(victimId, BH);
  add(
    'T10_cancelled_no_pii',
    !hasBanking(t10Rpc['body']),
    {'rpc': t10Rpc['body']},
  );

  // ========== T11 — TOCTOU: pending bundle + parallel rpc ==========
  final t11 = await req('POST', '$url/rest/v1/product_bundles', BH, {
    'seller_id': victimId,
    'buyer_id': buyerId,
    'product_ids': [victimProductId],
    'subtotal_eur': 12,
    'discount_pct': 0,
    'discount_eur': 0,
    'total_eur': 12,
    'status': 'pending',
  });
  final futs = await Future.wait([
    banking(victimId, BH),
    banking(victimId, BH),
    banking(victimId, BH),
  ]);
  final t11Leak = futs.any((r) => hasBanking(r['body']));
  add(
    'T11_toctou_pending_no_pii',
    !t11Leak,
    {
      'bundle_http': t11['http'],
      'leaks': futs.map((r) => hasBanking(r['body'])).toList(),
    },
  );
  if (t11['body'] is List && (t11['body'] as List).isNotEmpty) {
    final id = '${(t11['body'] as List).first['id']}';
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/product_bundles?id=eq.$id', SVC);
    });
  }

  // ========== Email oracle ==========
  final emailBuyer = await rpc(
    'batata_find_user_id_by_email',
    {'p_email': sellerEmail},
    BH,
  );
  add(
    'EMAIL_buyer_oracle_blocked',
    emailBuyer['body'] == null || '${emailBuyer['body']}' == 'null',
    {'http': emailBuyer['http'], 'body': emailBuyer['body']},
  );

  final emailSeller = await rpc(
    'batata_find_user_id_by_email',
    {'p_email': buyerEmail},
    SH,
  );
  add(
    'EMAIL_seller_legit_resolves',
    '${emailSeller['body']}' == buyerId,
    {'http': emailSeller['http'], 'body': emailSeller['body']},
  );

  final emailAnon = await rpc(
    'batata_find_user_id_by_email',
    {'p_email': sellerEmail},
    ANON,
  );
  add(
    'EMAIL_anon_blocked',
    (emailAnon['http'] as int) >= 400 ||
        emailAnon['body'] == null ||
        '${emailAnon['body']}' == 'null',
    {'http': emailAnon['http'], 'body': emailAnon['body']},
  );

  final emailMissing = await rpc(
    'batata_find_user_id_by_email',
    {'p_email': 'nobody-exists-$tag@fleaber.test'},
    SH,
  );
  add(
    'EMAIL_missing_null',
    emailMissing['body'] == null || '${emailMissing['body']}' == 'null',
    {'body': emailMissing['body']},
  );

  final emailCase = await rpc(
    'batata_find_user_id_by_email',
    {'p_email': buyerEmail.toUpperCase()},
    SH,
  );
  add(
    'EMAIL_case_insensitive_seller',
    '${emailCase['body']}' == buyerId,
    {'body': emailCase['body']},
  );

  // ========== Reviews verified flag ==========
  // Off-platform completed order → review allowed, purchase_verified=false
  final revOrder = await req('POST', '$url/rest/v1/orders', SVC, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': labProductId.isEmpty ? null : labProductId,
    'status': 'concluido',
    'payment_method': 'MB WAY',
    'price_total': 5,
    'quantity': 1,
    'stock_units_applied': 1,
    'amount_paid_cents': null,
  });
  final revOrderId = revOrder['body'] is List && (revOrder['body'] as List).isNotEmpty
      ? '${(revOrder['body'] as List).first['id']}'
      : '';
  final revIns = await req('POST', '$url/rest/v1/reviews', BH, {
    'order_id': revOrderId,
    'buyer_id': buyerId,
    'target_id': sellerId,
    'stars': 5,
    'comment': 'rtb offplatform $tag',
    'author_role': 'comprador',
    'purchase_verified': true, // attempt forge
  });
  Map<String, dynamic>? revRow;
  if (revIns['body'] is List && (revIns['body'] as List).isNotEmpty) {
    revRow = Map<String, dynamic>.from((revIns['body'] as List).first as Map);
  }
  add(
    'REVIEW_offplatform_unverified',
    revIns['http'] == 201 && revRow?['purchase_verified'] == false,
    {
      'http': revIns['http'],
      'purchase_verified': revRow?['purchase_verified'],
      'body': clip(revIns['text'], 200),
    },
  );
  if (revRow != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/reviews?id=eq.${revRow!['id']}', SVC);
    });
  }
  if (revOrderId.isNotEmpty) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$revOrderId', SVC);
    });
  }

  // Platform-verified path (amount_paid_cents > 0, not off-platform)
  final revOrder2 = await req('POST', '$url/rest/v1/orders', SVC, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': labProductId.isEmpty ? null : labProductId,
    'status': 'concluido',
    'payment_method': 'Pagamento na App',
    'price_total': 5,
    'quantity': 1,
    'amount_paid_cents': 500,
    'stripe_payment_intent_id': 'pi_rtb_$tag',
  });
  final revOrder2Id =
      revOrder2['body'] is List && (revOrder2['body'] as List).isNotEmpty
          ? '${(revOrder2['body'] as List).first['id']}'
          : '';
  final revIns2 = await req('POST', '$url/rest/v1/reviews', BH, {
    'order_id': revOrder2Id,
    'buyer_id': buyerId,
    'target_id': sellerId,
    'stars': 4,
    'comment': 'rtb platform $tag',
    'author_role': 'comprador',
  });
  Map<String, dynamic>? revRow2;
  if (revIns2['body'] is List && (revIns2['body'] as List).isNotEmpty) {
    revRow2 = Map<String, dynamic>.from((revIns2['body'] as List).first as Map);
  }
  add(
    'REVIEW_platform_verified',
    revIns2['http'] == 201 && revRow2?['purchase_verified'] == true,
    {
      'http': revIns2['http'],
      'purchase_verified': revRow2?['purchase_verified'],
      'body': clip(revIns2['text'], 200),
    },
  );
  if (revRow2 != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/reviews?id=eq.${revRow2!['id']}', SVC);
    });
  }
  if (revOrder2Id.isNotEmpty) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$revOrder2Id', SVC);
    });
  }

  // Unpaid → blocked
  final revUnpaid = await req('POST', '$url/rest/v1/orders', SVC, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'status': 'concluido',
    'payment_method': 'Pagamento na App',
    'price_total': 1,
    'quantity': 1,
    'amount_paid_cents': 0,
  });
  final revUnpaidId =
      revUnpaid['body'] is List && (revUnpaid['body'] as List).isNotEmpty
          ? '${(revUnpaid['body'] as List).first['id']}'
          : '';
  final revUnpaidIns = await req('POST', '$url/rest/v1/reviews', BH, {
    'order_id': revUnpaidId,
    'buyer_id': buyerId,
    'target_id': sellerId,
    'stars': 1,
    'comment': 'should fail',
    'author_role': 'comprador',
  });
  add(
    'REVIEW_unpaid_blocked',
    (revUnpaidIns['http'] as int) >= 400,
    {'http': revUnpaidIns['http']},
  );
  if (revUnpaidId.isNotEmpty) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$revUnpaidId', SVC);
    });
  }

  // ========== Storage ==========
  final listRoot = await req(
    'POST',
    '$url/storage/v1/object/list/chat_media',
    BH,
    {'prefix': 'chat_uploads/', 'limit': 100},
  );
  final listRootBody = listRoot['body'];
  final foreignListed = listRootBody is List &&
      listRootBody.any((o) {
        if (o is! Map) return false;
        final n = '${o['name'] ?? ''}';
        return n.isNotEmpty && !n.startsWith(buyerId) && !n.contains(buyerId);
      });
  // API may return empty folders or only own — fail if foreign uid folders appear
  add(
    'STORAGE_list_chat_uploads_no_foreign',
    !foreignListed,
    {
      'http': listRoot['http'],
      'count': listRootBody is List ? listRootBody.length : null,
      'sample': listRootBody is List
          ? listRootBody.take(5).map((e) => e is Map ? e['name'] : e).toList()
          : listRootBody,
    },
  );

  final listOther = await req(
    'POST',
    '$url/storage/v1/object/list/chat_media',
    BH,
    {'prefix': 'chat_uploads/$sellerId/', 'limit': 20},
  );
  final otherEmpty = listOther['body'] is List && (listOther['body'] as List).isEmpty;
  add(
    'STORAGE_list_other_uid_empty',
    otherEmpty || (listOther['http'] as int) >= 400,
    {'http': listOther['http'], 'body': listOther['body']},
  );

  final anonList = await req(
    'POST',
    '$url/storage/v1/object/list/chat_media',
    ANON,
    {'prefix': 'chat_uploads/', 'limit': 20},
  );
  final anonEmpty =
      anonList['body'] is List && (anonList['body'] as List).isEmpty;
  add(
    'STORAGE_anon_list_chat_uploads',
    anonEmpty || (anonList['http'] as int) >= 400,
    {'http': anonList['http'], 'body': anonList['body']},
  );

  // Catalog still listable (product_photos)
  final catList = await req(
    'POST',
    '$url/storage/v1/object/list/chat_media',
    ANON,
    {'prefix': 'product_photos/', 'limit': 5},
  );
  add(
    'STORAGE_catalog_still_public_list',
    (catList['http'] as int) < 400,
    {'http': catList['http'], 'n': catList['body'] is List ? (catList['body'] as List).length : 0},
  );

  // CDN residual fechado: public HEAD legado
  final legacyPub =
      '$url/storage/v1/object/public/chat_media/chat_uploads/$buyerId/reaudit.txt';
  final anonHead = await req('HEAD', legacyPub, ANON);
  add(
    'STORAGE_anon_public_head_chat_uploads_denied',
    (anonHead['http'] as int) >= 400,
    {'http': anonHead['http'], 'url': legacyPub},
  );

  // Novos uploads em chat_media/chat_uploads bloqueados
  final blockRaw = await http.post(
    Uri.parse(
        '$url/storage/v1/object/chat_media/chat_uploads/$buyerId/rtb_block_$tag.png'),
    headers: {
      ...BH,
      'Content-Type': 'image/png',
      'x-upsert': 'true',
    },
    body: [137, 80, 78, 71, 13, 10, 26, 10], // minimal png hdr-ish
  );
  add(
    'STORAGE_insert_chat_media_chat_uploads_blocked',
    blockRaw.statusCode >= 400,
    {'http': blockRaw.statusCode, 'body': blockRaw.body},
  );

  // Upload legítimo fleaber_private
  final privPath = 'chat_uploads/$buyerId/rtb_ok_$tag.png';
  final privUp = await http.post(
    Uri.parse('$url/storage/v1/object/fleaber_private/$privPath'),
    headers: {
      ...BH,
      'Content-Type': 'image/png',
      'x-upsert': 'true',
    },
    body: [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13],
  );
  add(
    'STORAGE_insert_fleaber_private_own_ok',
    privUp.statusCode >= 200 && privUp.statusCode < 300,
    {'http': privUp.statusCode, 'body': privUp.body},
  );
  if (privUp.statusCode >= 200 && privUp.statusCode < 300) {
    cleanup.add(() async {
      await req(
        'DELETE',
        '$url/storage/v1/object/fleaber_private',
        SVC,
        {'prefixes': [privPath]},
      );
    });
  }

  // Anon GET object privado
  final anonPrivGet = await http.get(
    Uri.parse('$url/storage/v1/object/public/fleaber_private/$privPath'),
    headers: ANON,
  );
  add(
    'STORAGE_anon_public_get_fleaber_private_denied',
    anonPrivGet.statusCode >= 400,
    {'http': anonPrivGet.statusCode},
  );

  // Buyer B não lista pasta A em fleaber_private
  final listPrivOther = await req(
    'POST',
    '$url/storage/v1/object/list/fleaber_private',
    B2H,
    {'prefix': 'chat_uploads/$buyerId/', 'limit': 20},
  );
  final privOtherEmpty = listPrivOther['body'] is List &&
      (listPrivOther['body'] as List).isEmpty;
  add(
    'STORAGE_buyer2_list_buyer1_private_empty',
    privOtherEmpty || (listPrivOther['http'] as int) >= 400,
    {'http': listPrivOther['http'], 'body': listPrivOther['body']},
  );

  // ========== Financial smoke (não regressão) ==========
  final walletRpc = await rpc(
    'batata_credit_wallet_once',
    {
      'p_user_id': buyerId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 1,
      'p_kind': 'test',
      'p_idempotency_key': 'rtb-$tag',
    },
    BH,
  );
  add(
    'REG_wallet_credit_no_exec',
    (walletRpc['http'] as int) >= 400,
    {'http': walletRpc['http']},
  );

  final selfBanking = await banking(buyerId, BH);
  // buyer may not have external payments — just ensure no crash
  add(
    'REG_self_rpc_ok',
    (selfBanking['http'] as int) == 200,
    {'http': selfBanking['http'], 'body': selfBanking['body']},
  );

  // Cleanup
  for (final c in cleanup.reversed) {
    try {
      await c();
    } catch (_) {}
  }
  try {
    await req('DELETE', '$url/rest/v1/products?id=eq.$victimProductId', SVC);
  } catch (_) {}
  try {
    await req('DELETE', '$url/auth/v1/admin/users/$victimId', {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
    });
  } catch (_) {}

  final failed = results.where((r) => r['ok'] != true).toList();
  final out = {
    'at': DateTime.now().toIso8601String(),
    'project': 'fxdknzrqjenzqcvnwqqq',
    'pass': results.length - failed.length,
    'fail': failed.length,
    'results': results,
  };
  final path = 'tool/reports/sec_rtb_p1_banking_oracle_hostile_$tag.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('\nSUMMARY ${out['pass']}/${results.length} pass → $path');
  exit(failed.isEmpty ? 0 : 1);
}
