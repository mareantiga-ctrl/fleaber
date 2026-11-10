// ignore_for_file: avoid_print
/// RT-D P0 tip mint + RTB2 BANK/MUX P1 hostile battery.
/// dart run tool/sec_rtd_p0_tip_bank_mux_hostile.dart
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
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body};
}

String clip(Object? v, [int n = 220]) {
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

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    final s = '${(body.first as Map)['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  return null;
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

  // Snapshot balances
  Future<num> bal(String uid) async {
    final r = await req(
      'GET',
      '$url/rest/v1/wallets?id=eq.$uid&select=balance',
      SVC,
    );
    if (r['body'] is List && (r['body'] as List).isNotEmpty) {
      return (r['body'] as List).first['balance'] as num? ?? 0;
    }
    return 0;
  }

  final buyerBal0 = await bal(buyerId);

  // ========== P0 tip mint ==========
  // Create pending tip via Edge (no pay)
  final tipEdge = await req(
    'POST',
    '$url/functions/v1/create-live-tip-checkout',
    {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
      'Content-Type': 'application/json',
    },
    {'seller_id': sellerId, 'amount_eur': 1},
  );
  // Find latest pending tip for buyer
  final tips = await req(
    'GET',
    '$url/rest/v1/live_tips?buyer_id=eq.$buyerId&status=eq.pending&order=created_at.desc&limit=1&select=id,amount,seller_amount,status,payment_source',
    SVC,
  );
  final tipId = tips['body'] is List && (tips['body'] as List).isNotEmpty
      ? '${(tips['body'] as List).first['id']}'
      : '';
  add('P0_tip_pending_fixture', tipId.isNotEmpty, {
    'edge_http': tipEdge['http'],
    'tip_id': tipId,
    'edge': clip(tipEdge['text']),
  });

  final mint = await rpc(
    'batata_wallet_apply_tip_once',
    {
      'p_wallet_id': buyerId,
      'p_tip_id': tipId.isEmpty ? '00000000-0000-0000-0000-000000000001' : tipId,
      'p_amount': 50,
      'p_type': 'venda',
      'p_description': 'rt hostile mint',
    },
    BH,
  );
  final buyerBal1 = await bal(buyerId);
  add(
    'P0_jwt_apply_tip_blocked',
    (mint['http'] as int) >= 400 && buyerBal1 == buyerBal0,
    {
      'http': mint['http'],
      'body': clip(mint['text']),
      'bal_before': buyerBal0,
      'bal_after': buyerBal1,
    },
  );

  // Even service with wrong amount on pending should be constrained if we call
  // with JWT-shaped - skip; service settle path not tested here.

  // ========== P1 BANK ==========
  await req('PATCH', '$url/rest/v1/profiles?id=eq.$sellerId', SVC, {
    'external_payments_enabled': true,
    'iban': 'PT50000201231234567890154',
    'mb_way': '911000000',
  });

  final prods = await sb.select(
    'products',
    filter: 'seller_id=eq.$sellerId&quantity=gt.0',
    limit: 1,
  );
  final pid = prods.isNotEmpty ? '${prods.first['id']}' : '';
  final price = prods.isNotEmpty ? (prods.first['price'] as num? ?? 10) : 10;

  final beforeBank = await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': sellerId},
    BH,
  );

  final mintOrder = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 1,
    'price_total': price,
    'status': 'reservado',
    'payment_method': 'MB WAY',
  });
  final oid = idOf(mintOrder['body']);
  final statusAfter = mintOrder['body'] is List &&
          (mintOrder['body'] as List).isNotEmpty
      ? '${(mintOrder['body'] as List).first['status']}'
      : '';
  final afterBank = await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': sellerId},
    BH,
  );
  add(
    'P1_bank_buyer_insert_reservado_rewritten',
    oid != null &&
        statusAfter.toLowerCase() == 'reserva_pendente' &&
        !hasBanking(afterBank['body']),
    {
      'insert_http': mintOrder['http'],
      'status': statusAfter,
      'order_id': oid,
      'rpc_before_pii': hasBanking(beforeBank['body']),
      'rpc_after_pii': hasBanking(afterBank['body']),
      'body': clip(mintOrder['text']),
    },
  );
  if (oid != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$oid', SVC);
    });
    // PATCH elevate
    final elev = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$oid',
      BH,
      {'status': 'reservado'},
    );
    final chk = await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$oid&select=status',
      SVC,
    );
    final st = chk['body'] is List && (chk['body'] as List).isNotEmpty
        ? '${(chk['body'] as List).first['status']}'
        : '';
    add(
      'P1_bank_buyer_patch_reservado_noop',
      st.toLowerCase() != 'reservado',
      {'patch_http': elev['http'], 'status': st},
    );
  } else {
    add('P1_bank_buyer_patch_reservado_noop', false, 'no order');
  }

  // Happy: seller accept path — service sets reservado (simula seller accept)
  final hold = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 1,
    'price_total': price,
    'status': 'reserva_pendente',
    'payment_method': 'MB WAY',
  });
  final holdId = idOf(hold['body']);
  if (holdId != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$holdId', SVC);
    });
    // Seller PATCH accept
    final acc = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$holdId',
      SH,
      {'status': 'reservado'},
    );
    final bankOk = await rpc(
      'batata_seller_direct_payment_details',
      {'p_seller_id': sellerId},
      BH,
    );
    add(
      'P1_bank_seller_accept_reveal_ok',
      (acc['http'] as int) < 300 && hasBanking(bankOk['body']),
      {
        'patch_http': acc['http'],
        'rpc': bankOk['body'],
        'patch_body': clip(acc['text']),
      },
    );
  } else {
    add('P1_bank_seller_accept_reveal_ok', false, clip(hold['text']));
  }

  // ========== P1 MUX ==========
  final prof0 = await req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type',
    SVC,
  );
  final ut0 = prof0['body'] is List && (prof0['body'] as List).isNotEmpty
      ? '${(prof0['body'] as List).first['user_type']}'
      : '';

  final flip = await req(
    'PATCH',
    '$url/rest/v1/profiles?id=eq.$buyerId',
    BH,
    {'user_type': 'vendedor'},
  );
  final prof1 = await req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type',
    SVC,
  );
  final ut1 = prof1['body'] is List && (prof1['body'] as List).isNotEmpty
      ? '${(prof1['body'] as List).first['user_type']}'
      : '';
  add(
    'P1_mux_user_type_freeze',
    ut1.toLowerCase() == ut0.toLowerCase() &&
        ut1.toLowerCase() != 'vendedor',
    {
      'patch_http': flip['http'],
      'before': ut0,
      'after': ut1,
      'body': clip(flip['text']),
    },
  );

  final mux = await req(
    'POST',
    '$url/functions/v1/create-mux-live',
    {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
      'Content-Type': 'application/json',
    },
    {'title': 'rt hostile mux $tag'},
  );
  add(
    'P1_mux_create_buyer_403',
    (mux['http'] as int) == 403 ||
        (mux['text']?.toString().contains('vendedor') ?? false),
    {'http': mux['http'], 'body': clip(mux['text'])},
  );

  // Seller mux still allowed (smoke — may hit quota)
  final muxS = await req(
    'POST',
    '$url/functions/v1/create-mux-live',
    {
      'apikey': anon,
      'Authorization': 'Bearer $sellerTok',
      'Content-Type': 'application/json',
    },
    {'title': 'rt seller mux $tag'},
  );
  final muxSellerOk = (muxS['http'] as int) == 200 ||
      (muxS['http'] as int) == 429; // quota ok
  add(
    'P1_mux_seller_still_allowed_or_quota',
    muxSellerOk,
    {'http': muxS['http'], 'body': clip(muxS['text'])},
  );
  if ((muxS['http'] as int) == 200) {
    final liveId = muxS['body'] is Map ? '${muxS['body']['live']?['id'] ?? muxS['body']['id'] ?? ''}' : '';
    // Try parse live id from body
    String? lid;
    try {
      final b = muxS['body'];
      if (b is Map) {
        lid = '${b['id'] ?? b['live_id'] ?? (b['live'] is Map ? b['live']['id'] : '')}';
        if (lid == 'null' || lid.isEmpty) lid = null;
      }
    } catch (_) {}
    if (lid != null) {
      cleanup.add(() async {
        await req('PATCH', '$url/rest/v1/lives?id=eq.$lid', SVC, {
          'status': 'ended',
          'is_active': false,
        });
      });
    }
  }

  // Restore buyer type if somehow changed
  await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyerId', SVC, {
    'user_type': ut0.isEmpty ? 'comprador' : ut0,
  });

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
  final path = 'tool/reports/sec_rtd_p0_tip_bank_mux_hostile_$tag.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('\nSUMMARY ${out['pass']}/${results.length} → $path');
  exit(failed.isEmpty ? 0 : 1);
}
