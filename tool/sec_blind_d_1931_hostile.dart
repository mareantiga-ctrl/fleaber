// ignore_for_file: avoid_print
/// Blind D 1931 P2 — dart run tool/sec_blind_d_1931_hostile.dart
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
  final buyerEmail = envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final crashSecret = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
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

  // ---- Fixtures: product, chat, order pago ----
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'D1931 p2 $stamp',
    'price': 5.0,
    'quantity': 2,
    'ref_code': 'D1931-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final prodId = idOf(prod['body']);
  add('fixture_product', prodId != null, prodId);

  final chat = await req('POST', '$url/rest/v1/chats', SVC, {
    'user_a': buyerId,
    'user_b': sellerId,
    'product_id': prodId,
  });
  final chatId = idOf(chat['body']);
  add('fixture_chat', chatId != null, chatId);

  final order = await req('POST', '$url/rest/v1/orders', SVC, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': prodId,
    'status': 'pago',
    'quantity': 1,
    'price_total': 5.0,
    'shipping_method': 'mao',
    'payment_method': 'Pagamento na app',
    'amount_paid_cents': 500,
  });
  final orderId = idOf(order['body']);
  add('fixture_order', orderId != null, orderId);

  final forgeText =
      'FLEABER_JSON_V1:${jsonEncode({
        'kind': 'reservation_seller_confirmed_receipt',
        'order_id': orderId,
        'v': 1,
      })}';

  // P2-01: buyer forges seller receipt card
  final forge = await req('POST', '$url/rest/v1/chat_messages', BH, {
    'sender_id': sellerId,
    'receiver_id': sellerId,
    'chat_id': chatId,
    'text': forgeText,
    'is_read': false,
  });
  add(
    'P2_chat_forge_seller_card_blocked',
    (forge['http'] as int) >= 400,
    {'http': forge['http'], 'body': forge['body']},
  );

  // Seller legitimate card OK
  final okCard = await req('POST', '$url/rest/v1/chat_messages', SH, {
    'sender_id': sellerId,
    'receiver_id': buyerId,
    'chat_id': chatId,
    'text': forgeText,
    'is_read': false,
  });
  add(
    'anti_reg_seller_json_card_ok',
    (okCard['http'] as int) < 300,
    {'http': okCard['http'], 'id': idOf(okCard['body'])},
  );

  // Plain text still OK
  final plain = await req('POST', '$url/rest/v1/chat_messages', BH, {
    'sender_id': buyerId,
    'receiver_id': sellerId,
    'chat_id': chatId,
    'text': 'ola d1931 $stamp',
    'is_read': false,
  });
  add(
    'anti_reg_plain_chat_ok',
    (plain['http'] as int) < 300,
    {'http': plain['http']},
  );

  // P2-02: email oracle closed for JWT
  final oracle = await req(
    'POST',
    '$url/rest/v1/rpc/batata_find_user_id_by_email',
    SH,
    {'p_email': buyerEmail},
  );
  final oracleBody = oracle['body'];
  add(
    'P2_email_oracle_null',
    (oracle['http'] as int) < 300 &&
        (oracleBody == null || '$oracleBody' == 'null' || '$oracleBody'.isEmpty),
    {'http': oracle['http'], 'body': oracleBody},
  );

  // Invite by email still works (creates/reuses pending)
  final invite = await req(
    'POST',
    '$url/rest/v1/rpc/batata_staff_invite_helper_by_email',
    SH,
    {
      'p_email': buyerEmail,
      'p_display_name': 'Helper D1931 $stamp',
      'p_permissions': {'live': true},
    },
  );
  // body is uuid string
  final inviteUuid = '${invite['body']}'.replaceAll('"', '').trim();
  add(
    'anti_reg_invite_by_email_ok',
    (invite['http'] as int) < 300 &&
        RegExp(
          r'^[0-9a-fA-F-]{36}$',
        ).hasMatch(inviteUuid),
    {'http': invite['http'], 'body': invite['body']},
  );
  if (inviteUuid.length > 20 && !inviteUuid.contains('error')) {
    await req('DELETE', '$url/rest/v1/seller_helpers?id=eq.$inviteUuid', SVC);
  }

  // P2-03: heartbeat alien live
  final tokRpc = await req(
    'POST',
    '$url/rest/v1/rpc/batata_create_seller_device_token',
    SH,
    {'p_device_id': 'd1931-hb-$stamp', 'p_label': 'd1931'},
  );
  final tokMap = firstMap(tokRpc['body']) ??
      (tokRpc['body'] is Map
          ? Map<String, dynamic>.from(tokRpc['body'] as Map)
          : null);
  final deviceToken = '${tokMap?['token'] ?? ''}'.trim();
  add('fixture_device_token', deviceToken.length > 10, {
    'http': tokRpc['http'],
    'ok': tokMap?['ok'],
  });

  final alienLive = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': buyerId,
    'title': 'D1931 alien $stamp',
    'status': 'ended',
    'is_active': false,
  });
  final alienId = idOf(alienLive['body']);
  add('fixture_alien_live', alienId != null, alienId);

  final ownLive = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'title': 'D1931 own $stamp',
    'status': 'live',
    'is_active': true,
  });
  final ownId = idOf(ownLive['body']);
  add('fixture_own_live', ownId != null, ownId);

  if (deviceToken.length > 10 && alienId != null) {
    final hbAlien = await req(
      'POST',
      '$url/functions/v1/ps-heartbeat',
      {
        'apikey': anon,
        'Content-Type': 'application/json',
        'x-device-token': deviceToken,
      },
      {
        'live_id': alienId,
        'device_id': 'd1931-hb-$stamp',
        'status': 'online',
      },
    );
    final hbMap = firstMap(hbAlien['body']) ??
        (hbAlien['body'] is Map
            ? Map<String, dynamic>.from(hbAlien['body'] as Map)
            : null);
    add(
      'P2_heartbeat_alien_blocked',
      hbMap?['ok'] != true &&
          '${hbMap?['error'] ?? ''}'.contains('live_not_owned'),
      {'http': hbAlien['http'], 'body': hbAlien['body']},
    );
  } else {
    add('P2_heartbeat_alien_blocked', false, 'missing token/live');
  }

  if (deviceToken.length > 10 && ownId != null) {
    final hbOwn = await req(
      'POST',
      '$url/functions/v1/ps-heartbeat',
      {
        'apikey': anon,
        'Content-Type': 'application/json',
        'x-device-token': deviceToken,
      },
      {
        'live_id': ownId,
        'device_id': 'd1931-hb-$stamp',
        'status': 'online',
      },
    );
    final hbMap = firstMap(hbOwn['body']) ??
        (hbOwn['body'] is Map
            ? Map<String, dynamic>.from(hbOwn['body'] as Map)
            : null);
    add(
      'anti_reg_heartbeat_own_ok',
      hbMap?['ok'] == true,
      {'http': hbOwn['http'], 'body': hbOwn['body']},
    );
  } else {
    add('anti_reg_heartbeat_own_ok', false, 'missing token/live');
  }

  // Anti-reg mão → concluido
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
  if (paidId != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paidId', SVC, {
      'shipping_method': 'mao',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paidId', BH, {
      'status': 'concluido',
    });
    final hs = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$paidId&select=status',
      SVC,
    ))['body']);
    add('anti_reg_hand_concluido_ok', '${hs?['status']}' == 'concluido', hs);
  } else {
    add('anti_reg_hand_concluido_ok', false, paid);
  }

  // Cleanup lives
  if (ownId != null) {
    await req('PATCH', '$url/rest/v1/lives?id=eq.$ownId', SVC, {
      'status': 'ended',
      'is_active': false,
    });
  }

  final fail = results.where((r) => r['ok'] != true).length;
  stdout.writeln('\n=== ${results.length - fail}/${results.length} PASS ===');
  exit(fail == 0 ? 0 : 1);
}
