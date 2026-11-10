// ignore_for_file: avoid_print
/// Y/Z/AA pós-fix — dart run tool/sec_yzaa_20260901_hostile.dart
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
      ? await http.post(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body))
      : method == 'PATCH'
          ? await http.patch(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body))
          : await http.get(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'raw': r.body};
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

String? orderIdFromE2E(dynamic body) {
  if (body is Map) {
    final m = Map<String, dynamic>.from(body);
    final direct = '${m['order_id'] ?? ''}'.trim();
    if (direct.isNotEmpty && direct != 'null') return direct;
  }
  return idOf(body);
}

bool denied(Map<String, dynamic> r) => (r['http'] as int) >= 400;

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: wrong project');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final buyer2Id = (e['LIVE_OPS_TEST_BUYER2_ID'] ?? '').trim();
  final crashSecret = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
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
  void add(String id, bool ok, [Object? d]) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    print('${ok ? 'PASS' : 'FAIL'} $id ${d ?? ''}');
  }

  // --- Y-P0 bundle qty>1 blocked ---
  final pa = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'HOSTILE-YZAA-A',
    'price': 20,
    'quantity': 8,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final pb = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'HOSTILE-YZAA-B',
    'price': 20,
    'quantity': 8,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final pidA = idOf(pa['body']);
  final pidB = idOf(pb['body']);
  if (pidA != null && pidB != null) {
    final bun = await req('POST', '$url/rest/v1/product_bundles', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_ids': [pidA, pidB],
    });
    final bid = idOf(bun['body']);
    if (bid != null) {
      await req('PATCH', '$url/rest/v1/product_bundles?id=eq.$bid', SH, {
        'status': 'accepted',
        'discount_pct': 50,
      });
      final o3 = await req('POST', '$url/rest/v1/orders', BH, {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pidA,
        'quantity': 3,
        'bundle_id': bid,
        'status': 'reserva_pendente',
        'price_total': 60,
      });
      add('Y2_bundle_qty3_insert_blocked', denied(o3), {'http': o3['http'], 'body': o3['body']});
    }
  }

  // --- Y-P1 bundle buyer mismatch ---
  if (pidA != null && pidB != null && buyer2Id.isNotEmpty) {
    final bun2 = await req('POST', '$url/rest/v1/product_bundles', SVC, {
      'buyer_id': buyer2Id,
      'seller_id': sellerId,
      'product_ids': [pidA, pidB],
    });
    final bid2 = idOf(bun2['body']);
    if (bid2 != null) {
      await req('PATCH', '$url/rest/v1/product_bundles?id=eq.$bid2', SH, {
        'status': 'accepted',
        'discount_pct': 50,
      });
      final o1 = await req('POST', '$url/rest/v1/orders', BH, {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pidA,
        'quantity': 1,
        'status': 'reserva_pendente',
        'price_total': 20,
      });
      final oid1 = idOf(o1['body']);
      if (oid1 != null) {
        final att = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid1', BH, {
          'bundle_id': bid2,
        });
        add('Y2_bundle_buyer_mismatch_blocked', denied(att), {'http': att['http']});
      }
    }
  } else {
    add('Y2_bundle_buyer_mismatch_blocked', true, 'skip no buyer2');
  }

  // --- Y-P1 captured order cannot reopen checkout ---
  final paid = await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', E2E, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'probe': 'setup_paid_order',
    'initial_qty': 2,
    'shipping_method': 'mao',
  });
  final paidOid = orderIdFromE2E(paid['body']);
  if (paidOid != null) {
    final hop = await req('PATCH', '$url/rest/v1/orders?id=eq.$paidOid', SH, {
      'status': 'reserva_pendente',
    });
    final afterHop = firstMap(
      (await req('GET', '$url/rest/v1/orders?id=eq.$paidOid&select=status,amount_paid_cents', SVC))['body'],
    );
    add(
      'Y8_captured_no_hop_to_hold',
      '${afterHop?['status']}' == 'pago' || denied(hop),
      {'hop_http': hop['http'], 'after': afterHop},
    );

    final ck = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'order_id': paidOid,
      'buyer_id': buyerId,
    });
    add(
      'Y8_checkout_blocked_after_capture',
      denied(ck) || '${ck['body']}'.contains('blocked'),
      {'http': ck['http'], 'brief': '${ck['body']}'.substring(0, 120.clamp(0, '${ck['body']}'.length))},
    );
  } else {
    add('Y8_captured_no_hop_to_hold', false, 'no paid order');
    add('Y8_checkout_blocked_after_capture', false, 'no paid order');
  }

  // --- Y-P2 seller cannot regress pago to hold aliases ---
  if (paidOid != null) {
    final reg = await req('PATCH', '$url/rest/v1/orders?id=eq.$paidOid', SH, {
      'status': 'aguarda_confirmacao',
    });
    final afterReg = firstMap(
      (await req('GET', '$url/rest/v1/orders?id=eq.$paidOid&select=status', SVC))['body'],
    );
    add(
      'Y1_pago_no_regress_hold',
      '${afterReg?['status']}' == 'pago' || denied(reg),
      {'http': reg['http'], 'status': afterReg?['status']},
    );
  }

  // --- Z chat cards ---
  final chat = await req('POST', '$url/rest/v1/chats', SVC, {
    'user_a': buyerId,
    'user_b': sellerId,
  });
  final chatId = idOf(chat['body']);
  if (chatId != null && paidOid != null) {
    final rawJson = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'text': '{"kind":"bundle_proposal","total_eur":8888}',
    });
    add('Z_raw_json_blocked', denied(rawJson), {'http': rawJson['http']});

    final fakeBundle = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'text':
          'FLEABER_JSON_V1:${jsonEncode({'kind': 'bundle_proposal', 'total_eur': 6543.21})}',
    });
    add('Z_bundle_no_id_blocked', denied(fakeBundle), {'http': fakeBundle['http']});

    final evilProof = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'text':
          'FLEABER_JSON_V1:${jsonEncode({'kind': 'reservation_payment_submitted', 'order_id': paidOid, 'proof_url': 'javascript:alert(1)'})}',
    });
    add('Z_proof_url_xss_blocked', denied(evilProof), {'http': evilProof['http']});

    final fakeDispute = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'text':
          'FLEABER_JSON_V1:${jsonEncode({'kind': 'order_dispute_opened', 'order_id': paidOid})}',
    });
    add('Z_dispute_card_without_dispute_blocked', denied(fakeDispute), {'http': fakeDispute['http']});

    final fakeCancel = await req('POST', '$url/rest/v1/chat_messages', SH, {
      'chat_id': chatId,
      'sender_id': sellerId,
      'text':
          'FLEABER_JSON_V1:${jsonEncode({'kind': 'reservation_cancelled_by_seller', 'order_id': paidOid})}',
    });
    add('Z_cancel_card_on_paid_blocked', denied(fakeCancel), {'http': fakeCancel['http']});

    final evilImg = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'text':
          'FLEABER_JSON_V1:${jsonEncode({'kind': 'chat_image', 'url': 'https://evil.example/x.png', 'path': 'chat_uploads/$buyerId/$chatId/x.png'})}',
    });
    add('Z_chat_image_evil_url_blocked', denied(evilImg), {'http': evilImg['http']});

    final inboxForge = await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
      'last_message': 'Compra paga através do Seguro Fleaber (9999.00 €)',
    });
    add('Z_inbox_forge_blocked', denied(inboxForge), {'http': inboxForge['http']});
  } else {
    for (final id in [
      'Z_raw_json_blocked',
      'Z_bundle_no_id_blocked',
      'Z_proof_url_xss_blocked',
      'Z_dispute_card_without_dispute_blocked',
      'Z_cancel_card_on_paid_blocked',
      'Z_chat_image_evil_url_blocked',
      'Z_inbox_forge_blocked',
    ]) {
      add(id, false, 'no chat/order');
    }
  }

  // --- Z proof_url on unpaid order ---
  final resOrder = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pidA ?? sellerId,
    'quantity': 1,
    'status': 'reservado',
    'price_total': 20,
  });
  final resOid = idOf(resOrder['body']);
  if (resOid != null) {
    final evilOrderProof = await req('PATCH', '$url/rest/v1/orders?id=eq.$resOid', BH, {
      'proof_url': 'https://evil.example/fake.png',
    });
    add('Z_order_proof_url_external_blocked', denied(evilOrderProof), {'http': evilOrderProof['http']});
  }

  // --- AA PATCH converted without paid order ---
  final live = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'title': 'HOSTILE-YZAA-LIVE',
    'status': 'live',
    'is_active': true,
  });
  final liveId = idOf(live['body']);
  if (liveId != null) {
    final item = await req('POST', '$url/rest/v1/live_items', SVC, {
      'live_id': liveId,
      'ref_code': 'HYZ',
      'title': 'HOSTILE item',
      'price': 5,
      'quantity': 3,
      'status': 'available',
      'is_active': true,
      'item_kind': 'live_only',
    });
    final itemId = idOf(item['body']);
    if (itemId != null) {
      final res = await req('POST', '$url/rest/v1/live_reservation_requests', SVC, {
        'live_id': liveId,
        'live_item_id': itemId,
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'source': 'facebook_manual',
        'status': 'pending',
        'requested_qty': 1,
        'external_display_name': 'Hostile Buyer',
      });
      final resId = idOf(res['body']);
      if (resId != null) {
        final conv = await req('PATCH', '$url/rest/v1/live_reservation_requests?id=eq.$resId', SH, {
          'status': 'converted',
        });
        final afterConv = firstMap(
          (await req(
            'GET',
            '$url/rest/v1/live_reservation_requests?id=eq.$resId&select=status,processed_by_user_id',
            SVC,
          ))['body'],
        );
        add(
          'AA_patch_converted_without_pi_blocked',
          denied(conv) || '${afterConv?['status']}' != 'converted',
          {'http': conv['http'], 'after': afterConv},
        );
      }
    }
  }

  final fails = results.where((r) => r['ok'] != true).length;
  final outPath =
      '${Directory.current.path}/tool/reports/sec_yzaa_20260901_hostile_${DateTime.now().millisecondsSinceEpoch}.json';
  await File(outPath).writeAsString(jsonEncode({'results': results, 'pass': results.length - fails, 'total': results.length}));
  print('--- YZAA hostile ${results.length - fails}/${results.length} PASS ---');
  print('report: $outPath');
  exit(fails > 0 ? 1 : 0);
}
