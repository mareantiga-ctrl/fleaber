// ignore_for_file: avoid_print
/// KLM 20260831 — dart run tool/sec_klm_20260831_hostile.dart
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

  final AH = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
  };
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

  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, [Object? detail]) {
    results.add({'id': id, 'ok': ok, 'detail': detail});
    print('${ok ? 'PASS' : 'FAIL'} $id ${detail ?? ''}');
  }

  // ---- chat + product fixture ----
  final chat = await req('POST', '$url/rest/v1/chats', SVC, {
    'user_a': buyerId,
    'user_b': sellerId,
  });
  final chatId = idOf(chat['body']);
  add('fixture_chat', chatId != null, chatId);

  final p = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'KLM hold $stamp',
    'price': 4.5,
    'quantity': 3,
    'ref_code': 'KLM-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = idOf(p['body']);
  add('fixture_product', pid != null, pid);

  // ---- K: seguro on MB WAY pago sem captura ----
  final hold = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 4.5,
    'shipping_method': 'mao',
    'payment_method': 'MB WAY',
  });
  final oid = idOf(hold['body']);
  await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {'status': 'pago'});
  final seguro = await req('POST', '$url/rest/v1/chat_messages', BH, {
    'chat_id': chatId,
    'sender_id': buyerId,
    'text':
        'FLEABER_JSON_V1:${jsonEncode({
          'kind': 'seguro_fleaber_paid',
          'order_id': oid,
          'total': 4.5,
        })}',
    'is_read': false,
  });
  add(
    'K_seguro_mbway_pago_blocked',
    (seguro['http'] as int) >= 400,
    {'http': seguro['http'], 'body': seguro['body']},
  );

  final legacy = await req('POST', '$url/rest/v1/chat_messages', BH, {
    'chat_id': chatId,
    'sender_id': buyerId,
    'text':
        'Compra paga através do Seguro Fleaber (8888.88 €) [order:$oid]',
    'is_read': false,
  });
  add(
    'K_legacy_plain_blocked',
    (legacy['http'] as int) >= 400,
    {'http': legacy['http']},
  );

  // ---- L: TTL resurrect ----
  final past = DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 3))
      .toIso8601String();
  final hold2 = await req('POST', '$url/rest/v1/orders', SVC, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 4.5,
    'shipping_method': 'mao',
    'payment_method': 'MB WAY',
    'reservation_expires_at': past,
  });
  final oid2 = idOf(hold2['body']);
  final future = DateTime.now()
      .toUtc()
      .add(const Duration(days: 7))
      .toIso8601String();
  final rez = await req(
    'PATCH',
    '$url/rest/v1/orders?id=eq.$oid2',
    BH,
    {'reservation_expires_at': future},
  );
  final afterRez = firstMap(
    (await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$oid2&select=id,reservation_expires_at,status',
      SVC,
    ))['body'],
  );
  final expAfter = '${afterRez?['reservation_expires_at'] ?? ''}';
  final resurrected = expAfter.startsWith(future.substring(0, 13));
  add(
    'L_ttl_resurrect_blocked',
    !resurrected,
    {'http': rez['http'], 'expires': expAfter, 'wanted_block_future': future},
  );

  final expJob = await req(
    'POST',
    '$url/rest/v1/rpc/batata_expire_reservation_holds',
    SVC,
    {},
  );
  final afterExp = firstMap(
    (await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$oid2&select=id,status',
      SVC,
    ))['body'],
  );
  add(
    'L_expire_job_cancels',
    '${afterExp?['status']}' == 'cancelado',
    {'rpc': expJob['body'], 'status': afterExp?['status']},
  );

  // ---- L: DELETE review forbidden ----
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
  if (paidOid.isNotEmpty && paidOid != 'null') {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paidOid', SVC, {
      'shipping_method': 'mao',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paidOid', SH, {
      'status': 'enviado',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paidOid', BH, {
      'status': 'concluido',
    });
    final rev = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': paidOid,
      'buyer_id': buyerId,
      'target_id': sellerId,
      'stars': 1,
      'comment': 'KLM hostile $stamp',
      'author_role': 'comprador',
      'target_type': 'seller',
    });
    final rid = idOf(rev['body']);
    final del2 = await req('DELETE', '$url/rest/v1/reviews?id=eq.$rid', BH);
    add(
      'L_review_1star_delete_blocked',
      rid != null && (del2['http'] as int) >= 400,
      {'http': del2['http'], 'rid': rid, 'ins': rev['http']},
    );
  } else {
    add('L_review_1star_delete_blocked', false, {'paid': paid['body']});
  }

  // ---- M: resolve_handle unpublished offline ----
  final hUnpub = await req(
    'POST',
    '$url/rest/v1/rpc/batata_resolve_handle',
    AH,
    {'p_handle': 'rtm-20260831t1802-s2'},
  );
  final foundUnpub = firstMap(hUnpub['body'])?['found'] == true;
  add(
    'M_resolve_unpub_offline_not_found',
    foundUnpub != true,
    hUnpub['body'],
  );

  // ---- M: chat_media list denied ----
  final list = await req(
    'POST',
    '$url/storage/v1/object/list/chat_media',
    AH,
    {'prefix': '', 'limit': 20},
  );
  final listBody = list['body'];
  final listed = listBody is List && listBody.isNotEmpty;
  add(
    'M_chat_media_list_denied',
    !listed || (list['http'] as int) >= 400,
    {'http': list['http'], 'n': listBody is List ? listBody.length : null},
  );

  // ---- M: CORS exact ----
  final corsBad = await http.post(
    Uri.parse('$url/functions/v1/resolve-mux-playback'),
    headers: {
      ...AH,
      'Origin': 'https://attacker.fleaber.pt',
    },
    body: jsonEncode({'live_id': '00000000-0000-0000-0000-000000000001'}),
  );
  final acao = corsBad.headers['access-control-allow-origin'] ?? '';
  add(
    'M_cors_no_wildcard_subdomain',
    acao != 'https://attacker.fleaber.pt',
    {'acao': acao},
  );

  final corsExt = await http.post(
    Uri.parse('$url/functions/v1/resolve-mux-playback'),
    headers: {
      ...AH,
      'Origin': 'chrome-extension://abcdefghijklmnopqrstuvwxyz',
    },
    body: jsonEncode({'live_id': '00000000-0000-0000-0000-000000000001'}),
  );
  final acaoExt = corsExt.headers['access-control-allow-origin'] ?? '';
  add(
    'M_cors_no_extension',
    acaoExt != 'chrome-extension://abcdefghijklmnopqrstuvwxyz',
    {'acao': acaoExt},
  );

  // ---- M: mux draft ----
  final draftLive = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'title': 'KLM draft $stamp',
    'status': 'draft',
    'is_active': false,
    'mux_playback_id': 'klm_draft_$stamp',
  });
  final draftId = idOf(draftLive['body']);
  final mux = await req(
    'POST',
    '$url/functions/v1/resolve-mux-playback',
    AH,
    {'live_id': draftId},
  );
  final muxBody = mux['body'];
  final muxErr = muxBody is Map ? '${muxBody['error'] ?? ''}' : '';
  add(
    'M_mux_draft_blocked',
    (mux['http'] as int) >= 400 || muxErr.contains('live_not_public'),
    {'http': mux['http'], 'body': muxBody},
  );

  // ---- anti-regressão: mão pago → concluido ----
  if (paidOid.isNotEmpty && paidOid != 'null') {
    final st = firstMap(
      (await req(
        'GET',
        '$url/rest/v1/orders?id=eq.$paidOid&select=status',
        SVC,
      ))['body'],
    );
    add('R_mao_concluido', '${st?['status']}' == 'concluido', st);
  }

  final failed = results.where((r) => r['ok'] != true).toList();
  print('\n=== ${results.length - failed.length}/${results.length} PASS ===');
  if (failed.isNotEmpty) {
    stderr.writeln('FAILED: ${failed.map((e) => e['id']).join(', ')}');
    exit(1);
  }
}
