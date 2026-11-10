// ignore_for_file: avoid_print
/// Blind B 1245/1250 — P0 refund crash→release + P1 raffle/storage + P2 tip/payout.
/// dart run tool/sec_blind_b_1245_1250_hostile.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
]) async {
  final r = method == 'POST'
      ? await http.post(
          Uri.parse(u),
          headers: h,
          body: body == null ? null : jsonEncode(body),
        )
      : method == 'PATCH'
          ? await http.patch(
              Uri.parse(u),
              headers: h,
              body: body == null ? null : jsonEncode(body),
            )
          : method == 'GET'
              ? await http.get(Uri.parse(u), headers: h)
              : await http.delete(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body};
}

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    final s = '${(body.first as Map)['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  if (body is Map && body['id'] != null) {
    final s = '${body['id']}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  return null;
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
  final crashSecret = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
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
  final E2E = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    if (crashSecret.length >= 16) 'x-fleaber-e2e-secret': crashSecret,
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;

  // ========== P0: crash refund → release must NOT mint ==========
  final paid = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'probe': 'setup_paid_order',
      'initial_qty': 2,
    },
  );
  Map<String, dynamic> paidBody = {};
  if (paid['body'] is Map) {
    paidBody = Map<String, dynamic>.from(paid['body'] as Map);
  }
  final paidOid = '${paidBody['order_id'] ?? ''}';
  add(
    'P0_fixture_paid',
    paid['http'] == 200 && paidBody['ok'] == true && paidOid.isNotEmpty,
    {'order_id': paidOid, 'http': paid['http']},
  );
  if (paidOid.isEmpty) {
    stderr.writeln('ABORT no paid fixture');
    exit(1);
  }

  final balBefore = await req(
    'GET',
    '$url/rest/v1/wallets?id=eq.$sellerId&select=balance',
    SVC,
  );
  num sellerBal0 = 0;
  if (balBefore['body'] is List && (balBefore['body'] as List).isNotEmpty) {
    sellerBal0 = num.tryParse(
          '${(balBefore['body'] as List).first['balance']}',
        ) ??
        0;
  }

  final crashRefund = await req(
    'POST',
    '$url/functions/v1/refund-order',
    {
      ...SH,
      if (crashSecret.length >= 16)
        'x-fleaber-crash-inject-secret': crashSecret,
      'x-fleaber-crash-inject': 'after_stripe_before_db',
    },
    {
      'order_id': paidOid,
      'crash_inject': 'after_stripe_before_db',
    },
  );
  final crashOk = crashRefund['http'] == 500 &&
      '${crashRefund['text']}'.contains('refund_pending_reconcile');
  add('P0_crash_refund_500', crashOk, {
    'http': crashRefund['http'],
    'body': crashRefund['body'],
  });

  final afterCrash = await req(
    'GET',
    '$url/rest/v1/orders?id=eq.$paidOid&select=status,stripe_refund_id,amount_paid_cents',
    SVC,
  );
  Map<String, dynamic> rowCrash = {};
  if (afterCrash['body'] is List && (afterCrash['body'] as List).isNotEmpty) {
    rowCrash = Map<String, dynamic>.from(
      (afterCrash['body'] as List).first as Map,
    );
  }
  final earlySeal = '${rowCrash['stripe_refund_id'] ?? ''}'.startsWith('re_');
  add('P0_early_stripe_refund_id_seal', earlySeal, rowCrash);

  // Tentar caminho do auditor: enviado → concluido → release
  await req(
    'PATCH',
    '$url/rest/v1/orders?id=eq.$paidOid',
    SH,
    {'status': 'enviado'},
  );
  await req(
    'PATCH',
    '$url/rest/v1/orders?id=eq.$paidOid',
    BH,
    {'status': 'concluido'},
  );
  final release = await req(
    'POST',
    '$url/rest/v1/rpc/batata_release_seller_wallet_for_order',
    BH,
    {'p_order_id': paidOid},
  );
  final releaseBlocked = release['body'] == false || release['body'] == null;
  add('P0_release_blocked_after_crash', releaseBlocked, {
    'rpc': release['body'],
    'http': release['http'],
  });

  final balAfter = await req(
    'GET',
    '$url/rest/v1/wallets?id=eq.$sellerId&select=balance',
    SVC,
  );
  num sellerBal1 = sellerBal0;
  if (balAfter['body'] is List && (balAfter['body'] as List).isNotEmpty) {
    sellerBal1 = num.tryParse(
          '${(balAfter['body'] as List).first['balance']}',
        ) ??
        sellerBal0;
  }
  final delta = sellerBal1 - sellerBal0;
  add('P0_no_wallet_mint', delta <= 0.001, {
    'before': sellerBal0,
    'after': sellerBal1,
    'delta': delta,
  });

  final retry = await req(
    'POST',
    '$url/functions/v1/refund-order',
    SH,
    {'order_id': paidOid},
  );
  final retryOk = retry['http'] == 200 &&
      (retry['body'] is Map) &&
      ((retry['body'] as Map)['ok'] == true ||
          (retry['body'] as Map)['already_refunded'] == true ||
          (retry['body'] as Map)['status'] == 'cancelado');
  add('P1_refund_retry_reconciles', retryOk, {
    'http': retry['http'],
    'body': retry['body'],
  });

  final afterRetry = await req(
    'GET',
    '$url/rest/v1/orders?id=eq.$paidOid&select=status,stripe_refund_id',
    SVC,
  );
  Map<String, dynamic> rowRetry = {};
  if (afterRetry['body'] is List && (afterRetry['body'] as List).isNotEmpty) {
    rowRetry = Map<String, dynamic>.from(
      (afterRetry['body'] as List).first as Map,
    );
  }
  final cancelled =
      '${rowRetry['status']}'.toLowerCase() == 'cancelado' &&
          '${rowRetry['stripe_refund_id']}'.startsWith('re_');
  add('P1_order_cancelled_after_retry', cancelled, rowRetry);

  // ========== P2 tip sem live_id ==========
  final tipNoLive = await req(
    'POST',
    '$url/functions/v1/create-live-tip-checkout',
    BH,
    {'seller_id': sellerId, 'amount_eur': 1},
  );
  add(
    'P2_tip_requires_live_id',
    tipNoLive['http'] >= 400,
    {'http': tipNoLive['http'], 'body': tipNoLive['body']},
  );

  // ========== P3 anon stock ==========
  final anonStock = await req(
    'POST',
    '$url/rest/v1/rpc/batata_live_item_stock',
    {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
    },
    {'p_live_item_id': '00000000-0000-0000-0000-000000000001'},
  );
  add(
    'P3_anon_stock_denied',
    anonStock['http'] == 401 ||
        anonStock['http'] == 403 ||
        anonStock['http'] == 404,
    {'http': anonStock['http']},
  );

  // ========== P1 storage scoped by order_id ==========
  final prodA = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'Proof A $stamp',
    'price': 3.0,
    'quantity': 5,
    'ref_code': 'PROOF-A-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final prodB = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'Proof B $stamp',
    'price': 4.0,
    'quantity': 5,
    'ref_code': 'PROOF-B-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pidA = idOf(prodA['body']);
  final pidB = idOf(prodB['body']);
  final oA = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pidA,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 3.0,
    'shipping_method': 'hand',
    'payment_method': 'Pagamento na app',
  });
  final oB = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pidB,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 4.0,
    'shipping_method': 'hand',
    'payment_method': 'Pagamento na app',
  });
  final oidA = idOf(oA['body']);
  final oidB = idOf(oB['body']);
  add('P1_storage_orders', oidA != null && oidB != null, {
    'a': oidA,
    'b': oidB,
    'oa_http': oA['http'],
    'ob_http': oB['http'],
  });

  if (oidA != null && oidB != null) {
    final bytes = Uint8List.fromList(List<int>.filled(64, 7));
    final pathB = 'order_proofs/$buyerId/$oidB/hostile_$stamp.jpg';
    final up = await http.post(
      Uri.parse('$url/storage/v1/object/fleaber_private/$pathB'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerTok',
        'Content-Type': 'image/jpeg',
        'x-upsert': 'true',
      },
      body: bytes,
    );
    add('P1_storage_upload_b', up.statusCode < 300, {'http': up.statusCode});

    final getSeller = await http.get(
      Uri.parse('$url/storage/v1/object/fleaber_private/$pathB'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $sellerTok',
      },
    );
    // Seller partilha oidB → pode ler B. Ler só prova A falha se path for de B? 
    // Cross-order: seller com A e B pode ler B (partilha B). Precisamos provar
    // que NÃO lê path de order C de outro vendedor — ou path A sem relação?
    // Auditor: 1 order → lê TODA a pasta buyer. Aqui: com A+B, path B é OK.
    // Criar order só com product isolado e path de order histórica alheia:
    // Usar path inventado order_proofs/buyer/{uuid-fake}/x.jpg → 400/403/404
    final fakeOid = '0ed33415-11ad-4cde-80cc-9420866aae4c';
    final fakePath = 'order_proofs/$buyerId/$fakeOid/resid_hostile.jpg';
    // upload como service para existir object
    await http.post(
      Uri.parse('$url/storage/v1/object/fleaber_private/$fakePath'),
      headers: {
        'apikey': svc,
        'Authorization': 'Bearer $svc',
        'Content-Type': 'image/jpeg',
        'x-upsert': 'true',
      },
      body: bytes,
    );
    final getFake = await http.get(
      Uri.parse('$url/storage/v1/object/fleaber_private/$fakePath'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $sellerTok',
      },
    );
    add(
      'P1_storage_cross_order_denied',
      getFake.statusCode == 400 ||
          getFake.statusCode == 403 ||
          getFake.statusCode == 404,
      {'http': getFake.statusCode, 'shared_b_http': getSeller.statusCode},
    );
    // Cleanup storage
    await http.delete(
      Uri.parse('$url/storage/v1/object/fleaber_private/$pathB'),
      headers: {'apikey': svc, 'Authorization': 'Bearer $svc'},
    );
    await http.delete(
      Uri.parse('$url/storage/v1/object/fleaber_private/$fakePath'),
      headers: {'apikey': svc, 'Authorization': 'Bearer $svc'},
    );
    await req('DELETE', '$url/rest/v1/orders?id=eq.$oidA', SVC);
    await req('DELETE', '$url/rest/v1/orders?id=eq.$oidB', SVC);
    if (pidA != null) {
      await req('DELETE', '$url/rest/v1/products?id=eq.$pidA', SVC);
    }
    if (pidB != null) {
      await req('DELETE', '$url/rest/v1/products?id=eq.$pidB', SVC);
    }
  }

  // ========== P1 raffle: helper dash-only ==========
  final helperEmail = 'rtb3helper$stamp@fleaber.test';
  final helperPass = 'TesteRaffle$stamp!';
  final created = await req(
    'POST',
    '$url/auth/v1/signup',
    {
      'apikey': anon,
      'Content-Type': 'application/json',
    },
    {'email': helperEmail, 'password': helperPass},
  );
  String? helperId;
  if (created['body'] is Map) {
    final u = (created['body'] as Map)['user'];
    if (u is Map) helperId = '${u['id']}';
  }
  add('P1_helper_signup', helperId != null && helperId!.isNotEmpty, {
    'http': created['http'],
    'id': helperId,
  });

  if (helperId != null && helperId!.isNotEmpty) {
    final invite = await req('POST', '$url/rest/v1/seller_helpers', SVC, {
      'seller_id': sellerId,
      'helper_user_id': helperId,
      'invited_email': helperEmail,
      'invitation_status': 'accepted',
      'active': true,
      'permissions': {
        'can_view_live_dashboard': true,
        'can_manage_raffles': false,
        'can_manage_reservations': false,
        'can_manage_chat': false,
        'can_mark_items_sold': false,
      },
    });
    final inviteId = idOf(invite['body']);
    add('P1_helper_invite', inviteId != null, {
      'http': invite['http'],
      'body': invite['body'],
    });

    final helperTok = await sb.signIn(email: helperEmail, password: helperPass);
    final HH = {
      'apikey': anon,
      'Authorization': 'Bearer $helperTok',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

    // live fixture via svc
    final live = await req('POST', '$url/rest/v1/lives', SVC, {
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'status': 'live',
      'is_active': true,
      'title': 'RTB3 hostile $stamp',
    });
    final liveId = idOf(live['body']);
    add('P1_live_fixture', liveId != null, {'id': liveId});

    if (liveId != null) {
      final raffle = await req(
        'POST',
        '$url/rest/v1/rpc/batata_create_live_raffle',
        HH,
        {
          'p_live_id': liveId,
          'p_title': 'hostile',
          'p_winner_count': 1,
        },
      );
      final denied = raffle['http'] >= 400 ||
          '${raffle['text']}'.contains('not_allowed');
      add('P1_dash_helper_raffle_denied', denied, {
        'http': raffle['http'],
        'body': raffle['body'],
      });
      await req(
        'PATCH',
        '$url/rest/v1/lives?id=eq.$liveId',
        SVC,
        {'status': 'ended', 'is_active': false},
      );
    }

    if (inviteId != null) {
      await req('DELETE', '$url/rest/v1/seller_helpers?id=eq.$inviteId', SVC);
    }
  }

  // ========== P2 payout foreign key ==========
  final foreignKey = 'foreign-key-hostile-$stamp-abcdef';
  // plant ledger row as seller with service
  await req('POST', '$url/rest/v1/wallet_payout_ledger', SVC, {
    'idempotency_key': foreignKey,
    'user_id': sellerId,
    'amount_cents': 100,
    'amount_eur': 1.0,
    'status': 'debited',
    'balance_after': 0,
  });
  final hijack = await req(
    'POST',
    '$url/functions/v1/create-connect-account',
    BH,
    {
      'amount': 100,
      'idempotency_key': foreignKey,
    },
  );
  final hijackDenied = hijack['http'] >= 400 ||
      '${hijack['text']}'.contains('inválida') ||
      '${hijack['text']}'.contains('invalid') ||
      '${hijack['text']}'.contains('Connect') ||
      '${hijack['text']}'.contains('IBAN');
  // Buyer sem Connect ready pode falhar antes do debit — OK se não transferir.
  // Melhor: chamar RPC via service simulating debit with buyer id + foreign key
  final debitRpc = await req(
    'POST',
    '$url/rest/v1/rpc/batata_wallet_payout_debit',
    SVC,
    {
      'p_user_id': buyerId,
      'p_amount_cents': 100,
      'p_idempotency_key': foreignKey,
    },
  );
  Map<String, dynamic> debitBody = {};
  if (debitRpc['body'] is Map) {
    debitBody = Map<String, dynamic>.from(debitRpc['body'] as Map);
  }
  add(
    'P2_payout_key_foreign_denied',
    debitBody['ok'] == false &&
        debitBody['error'] == 'idempotency_key_foreign',
    {'rpc': debitBody, 'edge_http': hijack['http']},
  );
  await req(
    'DELETE',
    '$url/rest/v1/wallet_payout_ledger?idempotency_key=eq.$foreignKey',
    SVC,
  );

  final failed = results.where((r) => r['ok'] != true).length;
  final outPath =
      'tool/reports/sec_blind_b_1245_1250_hostile_$stamp.json';
  await File(outPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'stamp': stamp,
      'pass': results.length - failed,
      'fail': failed,
      'total': results.length,
      'results': results,
    }),
  );
  stdout.writeln('Wrote $outPath (${results.length - failed}/${results.length})');
  exit(failed == 0 ? 0 : 1);
}
