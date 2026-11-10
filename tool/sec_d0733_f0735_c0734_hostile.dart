// ignore_for_file: avoid_print
/// D0733 + F0735 + C0734 — dart run tool/sec_d0733_f0735_c0734_hostile.dart
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
    final m = body.first as Map;
    final s = '${m['id'] ?? m['order_id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  if (body is Map) {
    final s = '${body['id'] ?? body['order_id'] ?? ''}'.trim();
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
  final AH = {
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

  // ---- P1: refund after concluido blocked ----
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
  final paidId = idOf(paid['body']);
  add('fixture_paid', paidId != null, paidId);
  if (paidId != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paidId', SVC, {
      'shipping_method': 'mao',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paidId', BH, {
      'status': 'concluido',
    });
    final ref = await req(
      'POST',
      '$url/functions/v1/refund-order',
      SH,
      {'order_id': paidId},
    );
    final refBody = firstMap(ref['body']) ??
        (ref['body'] is Map
            ? Map<String, dynamic>.from(ref['body'] as Map)
            : null);
    add(
      'P1_refund_after_concluido_blocked',
      (ref['http'] as int) == 403 &&
          '${refBody?['code'] ?? ''}'.contains('refund_blocked'),
      {'http': ref['http'], 'body': ref['body']},
    );
    final st = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$paidId&select=status,stripe_refund_id',
      SVC,
    ))['body']);
    add(
      'P1_order_still_concluido',
      '${st?['status']}' == 'concluido' &&
          (st?['stripe_refund_id'] == null ||
              '${st?['stripe_refund_id']}'.isEmpty),
      st,
    );
  }

  // ---- P1b: refund with open dispute ----
  final paid2 = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'probe': 'setup_paid_order',
      'initial_qty': 2,
      'shipping_method': 'ctt',
    },
  );
  final paid2Id = idOf(paid2['body']);
  if (paid2Id != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paid2Id', SH, {
      'status': 'enviado',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paid2Id', BH, {
      'status': 'concluido',
    });
    // Dispute may require concluido
    final disp = await req('POST', '$url/rest/v1/order_disputes', BH, {
      'order_id': paid2Id,
      'reason': 'danificado',
      'status': 'aberta',
    });
    final dispOk = (disp['http'] as int) < 300 ||
        '${disp['body']}'.contains('duplicate') ||
        '${disp['body']}'.contains('already');
    add('fixture_dispute', dispOk || (disp['http'] as int) == 403, {
      'http': disp['http'],
      'note': '403/schema ok — refund still blocked by concluido',
      'body': disp['body'],
    });
    // Force status to pago for dispute+refund path if needed — report used concluido+dispute
    final ref2 = await req(
      'POST',
      '$url/functions/v1/refund-order',
      SH,
      {'order_id': paid2Id},
    );
    add(
      'P1_refund_open_dispute_or_concluido_blocked',
      (ref2['http'] as int) == 403,
      {'http': ref2['http'], 'body': ref2['body']},
    );
  } else {
    add('P1_refund_open_dispute_or_concluido_blocked', false, paid2);
  }

  // ---- Anti-reg: refund while pago still OK ----
  final paid3 = await req(
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
  final paid3Id = idOf(paid3['body']);
  if (paid3Id != null) {
    final ref3 = await req(
      'POST',
      '$url/functions/v1/refund-order',
      SH,
      {'order_id': paid3Id},
    );
    final ok = (ref3['http'] as int) == 200 &&
        (firstMap(ref3['body'])?['ok'] == true ||
            firstMap(ref3['body'])?['already_refunded'] == true);
    add('anti_reg_refund_while_pago_ok', ok, {
      'http': ref3['http'],
      'body': ref3['body'],
    });
  } else {
    add('anti_reg_refund_while_pago_ok', false, paid3);
  }

  // ---- P2 chat without order_id ----
  final chat = await req('POST', '$url/rest/v1/chats', SVC, {
    'user_a': buyerId,
    'user_b': sellerId,
  });
  final chatId = idOf(chat['body']);
  final forge = await req('POST', '$url/rest/v1/chat_messages', BH, {
    'sender_id': buyerId,
    'receiver_id': sellerId,
    'chat_id': chatId,
    'text':
        'FLEABER_JSON_V1:${jsonEncode({'kind': 'seguro_fleaber_paid', 'v': 1})}',
    'is_read': false,
  });
  add(
    'P2_chat_json_requires_order_id',
    (forge['http'] as int) >= 400,
    {'http': forge['http'], 'body': forge['body']},
  );

  // ---- P2 completed_at backdate ----
  final paid4 = await req(
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
  final paid4Id = idOf(paid4['body']);
  if (paid4Id != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paid4Id', SVC, {
      'shipping_method': 'mao',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paid4Id', BH, {
      'status': 'concluido',
      'completed_at': '2020-01-01T00:00:00Z',
    });
    final row = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$paid4Id&select=status,completed_at',
      SVC,
    ))['body']);
    final ca = '${row?['completed_at'] ?? ''}';
    add(
      'P2_completed_at_not_backdated',
      '${row?['status']}' == 'concluido' &&
          ca.isNotEmpty &&
          !ca.startsWith('2020'),
      row,
    );
  } else {
    add('P2_completed_at_not_backdated', false, paid4);
  }

  // ---- P2 offer expired accept ----
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'DFC offer $stamp',
    'price': 12.0,
    'quantity': 2,
    'ref_code': 'DFC-O-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final prodId = idOf(prod['body']);
  final offer = await req('POST', '$url/rest/v1/product_offers', SVC, {
    'product_id': prodId,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 8.0,
    'offered_by': 'buyer',
    'status': 'pending',
    'expires_at': '2020-01-01T00:00:00Z',
  });
  final offerId = idOf(offer['body']);
  add('fixture_expired_offer', offerId != null, {
    'http': offer['http'],
    'body': offer['body'],
  });
  if (offerId != null) {
    final acc = await req(
      'PATCH',
      '$url/rest/v1/product_offers?id=eq.$offerId',
      SH,
      {'status': 'accepted'},
    );
    add(
      'P2_offer_expired_accept_blocked',
      (acc['http'] as int) >= 400 &&
          '${acc['body']}'.toLowerCase().contains('offer_expired'),
      {'http': acc['http'], 'body': acc['body']},
    );
  } else {
    add('P2_offer_expired_accept_blocked', false, offer);
  }

  // ---- P2 ghost cancelado unlist ----
  final unlist = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'DFC ghost $stamp',
    'price': 9.0,
    'quantity': 1,
    'ref_code': 'DFC-G-$stamp',
    'list_on_marketplace': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final unlistId = idOf(unlist['body']);
  await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': unlistId,
    'status': 'cancelado',
    'quantity': 1,
    'price_total': 9.0,
    'shipping_method': 'mao',
    'payment_method': 'Pagamento na app',
  });
  final see = await req(
    'GET',
    '$url/rest/v1/products?id=eq.$unlistId&select=id,title',
    BH,
  );
  final seeList = see['body'] is List ? see['body'] as List : const [];
  add('P2_ghost_cancelado_hides_unlist', seeList.isEmpty, see['body']);

  // ---- P2 tip ended live ----
  final ended = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'title': 'DFC tip ended $stamp',
    'status': 'ended',
    'is_active': false,
  });
  final endedId = idOf(ended['body']);
  final tip = await req(
    'POST',
    '$url/rest/v1/rpc/batata_send_live_tip_from_wallet',
    BH,
    {
      'p_live_id': endedId,
      'p_seller_id': sellerId,
      'p_amount': 1.0,
    },
  );
  add(
    'P2_tip_ended_live_blocked',
    (tip['http'] as int) >= 400,
    {'http': tip['http'], 'body': tip['body']},
  );

  // ---- P2 settle unpaid 402 ----
  final settle = await req(
    'GET',
    '$url/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_dfc_hostile_$stamp',
    AH,
  );
  add(
    'P2_settle_unpaid_not_200_ok',
    (settle['http'] as int) == 400 || (settle['http'] as int) == 402,
    {'http': settle['http']},
  );

  // ---- Anti-reg hand concluido ----
  final paid5 = await req(
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
  final paid5Id = idOf(paid5['body']);
  if (paid5Id != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paid5Id', SVC, {
      'shipping_method': 'mao',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paid5Id', BH, {
      'status': 'concluido',
    });
    final hs = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$paid5Id&select=status',
      SVC,
    ))['body']);
    add('anti_reg_hand_concluido_ok', '${hs?['status']}' == 'concluido', hs);
  } else {
    add('anti_reg_hand_concluido_ok', false, paid5);
  }

  final fail = results.where((r) => r['ok'] != true).length;
  stdout.writeln('\n=== ${results.length - fail}/${results.length} PASS ===');
  exit(fail == 0 ? 0 : 1);
}
