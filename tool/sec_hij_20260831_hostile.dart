// ignore_for_file: avoid_print
/// HIJ 20260831 — dart run tool/sec_hij_20260831_hostile.dart
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
          : await http.get(Uri.parse(u), headers: h);
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

Map<String, dynamic>? firstMap(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
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

  // Snapshot wallets
  final wb0 = firstMap((await req(
    'GET',
    '$url/rest/v1/wallets?id=eq.$buyerId&select=balance',
    SVC,
  ))['body']);
  final buyerBal0 = (wb0?['balance'] as num?)?.toDouble() ?? -1;

  // ---- P1 J: plain → JSON server kind blocked ----
  final chats = await req(
    'GET',
    '$url/rest/v1/chats?or=(and(user_a.eq.$buyerId,user_b.eq.$sellerId),and(user_a.eq.$sellerId,user_b.eq.$buyerId))&select=id&limit=1',
    BH,
  );
  var chatId = idOf(chats['body']);
  if (chatId == null) {
    final c = await req('POST', '$url/rest/v1/chats', BH, {
      'user_a': buyerId,
      'user_b': sellerId,
    });
    chatId = idOf(c['body']);
  }
  final plain = await req('POST', '$url/rest/v1/chat_messages', BH, {
    'chat_id': chatId,
    'sender_id': buyerId,
    'text': 'plain hij $stamp',
    'is_read': false,
  });
  final mid = idOf(plain['body']);
  final forge = await req(
    'PATCH',
    '$url/rest/v1/chat_messages?id=eq.$mid',
    BH,
    {
      'text':
          'FLEABER_JSON_V1:${jsonEncode({
            'kind': 'marketplace_bag_paid',
            'total': 0.01,
          })}',
    },
  );
  add(
    'P1_plain_to_json_blocked',
    (forge['http'] as int) >= 400,
    {'http': forge['http'], 'body': forge['body']},
  );

  // ---- 1-A: seguro_fleaber_paid on unpaid hold blocked ----
  final p = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'HIJ unpaid $stamp',
    'price': 12.0,
    'quantity': 2,
    'ref_code': 'HIJU-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = idOf(p['body']);
  final hold = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 12.0,
    'shipping_method': 'mao',
    'payment_method': 'Pagamento na app',
  });
  final oid = idOf(hold['body']);
  final seguro = await req('POST', '$url/rest/v1/chat_messages', BH, {
    'chat_id': chatId,
    'sender_id': buyerId,
    'text':
        'FLEABER_JSON_V1:${jsonEncode({
          'kind': 'seguro_fleaber_paid',
          'order_id': oid,
          'total': 8888.88,
        })}',
    'is_read': false,
  });
  add(
    '1A_seguro_unpaid_blocked',
    (seguro['http'] as int) >= 400,
    {'http': seguro['http'], 'body': seguro['body']},
  );

  // ---- P0 I: paid → release → drain wallet → devolvida sem mint ----
  final paid = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'probe': 'setup_paid_order',
      'initial_qty': 2,
      'shipping_method': 'mao',
    },
  );
  final paidOid = idOf(paid['body']) ??
      '${(paid['body'] is Map ? (paid['body'] as Map)['order_id'] : '')}'.trim();
  add('fixture_paid', paidOid != null && paidOid.isNotEmpty && paidOid != 'null', {
    'http': paid['http'],
    'id': paidOid,
  });

  if (paidOid != null && paidOid.isNotEmpty && paidOid != 'null') {
    await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$paidOid',
      SVC,
      {'shipping_method': 'mao'},
    );
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
    await req(
      'POST',
      '$url/rest/v1/rpc/batata_release_seller_wallet_for_order',
      BH,
      {'p_order_id': paidOid},
    );

    // Drain seller wallet to 0 (simulate payout already done) without remint
    await req(
      'PATCH',
      '$url/rest/v1/wallets?id=eq.$sellerId',
      SVC,
      {'balance': 0},
    );

    final wbBefore = firstMap((await req(
      'GET',
      '$url/rest/v1/wallets?id=eq.$buyerId&select=balance',
      SVC,
    ))['body']);
    final balBefore = (wbBefore?['balance'] as num?)?.toDouble() ?? -1;

    await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$paidOid',
      SVC,
      {'status': 'devolvida'},
    );

    final wbAfter = firstMap((await req(
      'GET',
      '$url/rest/v1/wallets?id=eq.$buyerId&select=balance',
      SVC,
    ))['body']);
    final balAfter = (wbAfter?['balance'] as num?)?.toDouble() ?? -1;

    final estorno = await req(
      'GET',
      '$url/rest/v1/wallet_transactions?order_id=eq.$paidOid&type=eq.estorno&select=id,amount',
      SVC,
    );
    final estornoN =
        estorno['body'] is List ? (estorno['body'] as List).length : -1;
    final reemb = await req(
      'GET',
      '$url/rest/v1/wallet_transactions?order_id=eq.$paidOid&type=eq.reembolso&select=id,amount',
      SVC,
    );
    final reembN = reemb['body'] is List ? (reemb['body'] as List).length : -1;

    add(
      'P0_devolvida_no_buyer_mint_when_drained',
      balAfter == balBefore && reembN == 0,
      {
        'bal_before': balBefore,
        'bal_after': balAfter,
        'reemb': reembN,
        'estorno': estornoN,
        'buyer0': buyerBal0,
      },
    );
    add(
      'P0_no_phantom_estorno_when_empty',
      estornoN == 0,
      {'estorno': estornoN, 'body': estorno['body']},
    );
  }

  // ---- reviews_gerais: buyer_id alheio hidden ----
  final rg = await req(
    'GET',
    '$url/rest/v1/reviews_gerais?select=id,buyer_id,target_id&limit=20',
    BH,
  );
  var leak = false;
  if (rg['body'] is List) {
    for (final row in rg['body'] as List) {
      if (row is Map) {
        final bid = '${row['buyer_id']}';
        final tid = '${row['target_id']}';
        if (bid != buyerId && tid != buyerId) {
          leak = true;
          break;
        }
      }
    }
  }
  add('6A_reviews_gerais_no_stranger', !leak, {
    'http': rg['http'],
    'rows': rg['body'] is List ? (rg['body'] as List).length : -1,
  });

  // cleanup hold
  if (oid != null) {
    await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$oid',
      SVC,
      {'status': 'cancelado'},
    );
  }

  final failed = results.where((r) => r['ok'] != true).length;
  stdout.writeln('--- ${results.length - failed}/${results.length} PASS ---');
  exit(failed == 0 ? 0 : 1);
}
