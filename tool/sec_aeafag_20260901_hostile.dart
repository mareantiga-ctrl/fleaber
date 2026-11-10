// ignore_for_file: avoid_print
/// AE/AF/AG pós-fix — dart run tool/sec_aeafag_20260901_hostile.dart
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
    return '${(body.first as Map)['id']}'.trim();
  }
  if (body is Map && body['id'] != null) return '${body['id']}'.trim();
  return null;
}

Map<String, dynamic>? firstMap(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
  return null;
}

void pass(String id) => print('PASS $id');
void fail(String id, String why) {
  print('FAIL $id: $why');
  exitCode = 1;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: wrong project');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');

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
    if ((e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim().length >= 16)
      'x-fleaber-e2e-secret': (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim(),
  };

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final chat = await req('POST', '$url/rest/v1/chats', SVC, {
    'user_a': buyerId,
    'user_b': sellerId,
  });
  final chatId = idOf(chat['body']);
  if (chatId == null) fail('setup', 'chat');

  // --- AE-P0: ended live_item must not seal below catalog ---
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'RTAEAFAG-P0-$stamp',
    'price': 40.0,
    'quantity': 5,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final productId = idOf(prod['body']);
  if (productId == null) fail('AE-P0-setup', 'product');

  final live = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'title': 'RTAEAFAG live $stamp',
    'status': 'ended',
    'is_active': false,
  });
  final liveId = idOf(live['body']);
  final li = await req('POST', '$url/rest/v1/live_items', SVC, {
    'live_id': liveId,
    'product_id': productId,
    'item_kind': 'marketplace_product',
    'price': 5.0,
    'quantity': 1,
    'is_active': true,
    'status': 'available',
  });
  final liveItemId = idOf(li['body']);

  final ord = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': productId,
    'live_item_id': liveItemId,
    'live_id': liveId,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
  });
  final orderId = idOf(ord['body']);
  final unit = firstMap(ord['body'])?['contract_unit_cents'];
  if (unit == 4000 || unit == 500) {
    pass('AE-P0-stale-live-price');
  } else {
    fail('AE-P0-stale-live-price', 'contract_unit_cents=$unit expected 4000');
  }

  // --- AF-P1-01: FF+JSON blocked ---
  final ffJson = '${String.fromCharCode(12)}{"kind":"bundle_proposal","total_eur":99}';
  final msg = await req('POST', '$url/rest/v1/chat_messages', BH, {
    'chat_id': chatId,
    'sender_id': buyerId,
    'text': ffJson,
  });
  if ((msg['http'] as int) >= 400) {
    pass('AF-P1-01-ff-json');
  } else {
    fail('AF-P1-01-ff-json', 'http=${msg['http']}');
  }

  // --- AF-P1-04: cancel outcome fake display ---
  final paidOrd = await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', E2E, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'probe': 'setup_paid_order',
    'initial_qty': 2,
    'shipping_method': 'mao',
  });
  final paidBody = paidOrd['body'];
  String? paidId;
  if (paidBody is Map) {
    paidId = '${paidBody['order_id'] ?? ''}'.trim();
    if (paidId.isEmpty && paidBody['order'] is Map) {
      paidId = '${(paidBody['order'] as Map)['id']}'.trim();
    }
  }
  if (paidId == null || paidId.isEmpty) fail('AF-setup', 'paid order');
  final fakeCancel = await req('POST', '$url/rest/v1/chat_messages', SH, {
    'chat_id': chatId,
    'sender_id': sellerId,
    'text':
        'FLEABER_JSON_V1:{"kind":"cancel_request_outcome","order_id":"$paidId","outcome":"updated","display":"Reembolso 4321 EUR"}',
  });
  if ((fakeCancel['http'] as int) >= 400) {
    pass('AF-P1-04-cancel-fake');
  } else {
    fail('AF-P1-04-cancel-fake', 'http=${fakeCancel['http']}');
  }

  // --- AF-P2-04: fleaber.app proof denied ---
  final badProof = await req('POST', '$url/rest/v1/chat_messages', BH, {
    'chat_id': chatId,
    'sender_id': buyerId,
    'text':
        'FLEABER_JSON_V1:{"kind":"reservation_payment_submitted","order_id":"$paidId","proof_url":"https://fleaber.app/favicon.ico"}',
  });
  if ((badProof['http'] as int) >= 400) {
    pass('AF-P2-04-proof-url');
  } else {
    fail('AF-P2-04-proof-url', 'http=${badProof['http']}');
  }

  // --- AG-P2-AG4: mark_sold RPC works ---
  final live2 = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'title': 'RTAEAFAG mark $stamp',
    'status': 'live',
    'is_active': true,
  });
  final live2Id = idOf(live2['body']);
  if (live2Id == null) fail('AG-P2-AG4-setup', 'live2');
  final li2 = await req('POST', '$url/rest/v1/live_items', SVC, {
    'live_id': live2Id,
    'item_kind': 'live_only',
    'title': 'item $stamp',
    'ref_code': 'RTAEAFAG-$stamp',
    'price': 10.0,
    'quantity': 1,
    'is_active': true,
    'status': 'available',
  });
  final li2Id = idOf(li2['body']);
  if (li2Id == null) {
    fail('AG-P2-AG4-setup', 'live_item insert ${li2['http']} ${li2['raw']}');
  }
  final mark = await req('POST', '$url/rest/v1/rpc/batata_mark_live_item_sold', SH, {
    'p_live_item_id': li2Id,
  });
  final markBody = firstMap(mark['body']);
  if ((mark['http'] as int) == 200 && markBody?['ok'] != false) {
    pass('AG-P2-AG4-mark-sold');
  } else {
    fail('AG-P2-AG4-mark-sold', '${mark['http']} ${mark['raw']}');
  }

  // --- AG-P2-AG8: MB WAY pago without proof blocked ---
  final mbOrd = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': productId,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'MB WAY',
  });
  final mbId = idOf(mbOrd['body']);
  final stampPago = await req('PATCH', '$url/rest/v1/orders?id=eq.$mbId', SH, {
    'status': 'pago',
  });
  final after = await req('GET', '$url/rest/v1/orders?id=eq.$mbId&select=status', SVC);
  final st = firstMap(after['body'])?['status'];
  if (st != 'pago') {
    pass('AG-P2-AG8-mbway-no-proof');
  } else {
    fail('AG-P2-AG8-mbway-no-proof', 'status still pago');
  }

  // --- AG-P3: order on exhausted live_item blocked ---
  final li3 = await req('POST', '$url/rest/v1/live_items', SVC, {
    'live_id': live2Id,
    'item_kind': 'live_only',
    'title': 'exhaust $stamp',
    'ref_code': 'RTAEAFAG-ex-$stamp',
    'price': 7.0,
    'quantity': 1,
    'is_active': true,
    'status': 'available',
  });
  final li3Id = idOf(li3['body']);
  await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
    'live_item_id': li3Id,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'requested_qty': 1,
    'status': 'accepted',
    'source': 'fleaber_live',
  });
  await req('PATCH', '$url/rest/v1/live_items?id=eq.$li3Id', SVC, {
    'status': 'reserved_full',
  });
  final badOrd = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'live_item_id': li3Id,
    'live_id': live2Id,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
  });
  if ((badOrd['http'] as int) >= 400) {
    pass('AG-P3-exhausted-order');
  } else {
    fail('AG-P3-exhausted-order', 'http=${badOrd['http']}');
  }

  // --- AF-P2-01: label PIX inteiro bloqueado se ≠ pago ---
  final badLabel = await req('POST', '$url/rest/v1/chat_messages', BH, {
    'chat_id': chatId,
    'sender_id': buyerId,
    'text':
        'FLEABER_JSON_V1:{"kind":"seguro_fleaber_paid","order_id":"$paidId","total":12.34,"label":"PIX 4321 €"}',
  });
  if ((badLabel['http'] as int) >= 400) {
    pass('AF-P2-01-label-integer');
  } else {
    fail('AF-P2-01-label-integer', 'http=${badLabel['http']}');
  }

  // --- AF-P2-02: notes MB WAY mentirosas ---
  final badNotes = await req('POST', '$url/rest/v1/chat_messages', BH, {
    'chat_id': chatId,
    'sender_id': buyerId,
    'text':
        'FLEABER_JSON_V1:{"kind":"reservation_payment_submitted","order_id":"$paidId","notes":"Comprovativo MB WAY 4321,00 € confirmado"}',
  });
  if ((badNotes['http'] as int) >= 400) {
    pass('AF-P2-02-notes-lie');
  } else {
    fail('AF-P2-02-notes-lie', 'http=${badNotes['http']}');
  }

  // --- AF-P2-03: inbox preview falso (JWT buyer cria chat) ---
  final badInbox = await req('POST', '$url/rest/v1/chats', BH, {
    'user_a': buyerId,
    'user_b': sellerId,
    'last_message': 'Transferência confirmada 4321,00 €',
  });
  if ((badInbox['http'] as int) >= 400) {
    pass('AF-P2-03-inbox-lie');
  } else {
    fail('AF-P2-03-inbox-lie', 'http=${badInbox['http']}');
  }

  // --- AG-P2-AG3: REST esconde item esgotado para buyer ---
  final ghost = await req(
    'GET',
    '$url/rest/v1/live_items?id=eq.$li3Id&select=id,status',
    BH,
  );
  final ghostRows = ghost['body'] is List ? (ghost['body'] as List).length : 0;
  if (ghostRows == 0) {
    pass('AG-P2-AG3-rest-ghost-hidden');
  } else {
    fail('AG-P2-AG3-rest-ghost-hidden', 'rows=$ghostRows');
  }

  // --- AG-P3-AG5: live_only qty inflate bloqueado ---
  final li4 = await req('POST', '$url/rest/v1/live_items', SVC, {
    'live_id': live2Id,
    'item_kind': 'live_only',
    'title': 'inflate $stamp',
    'ref_code': 'RTAEAFAG-inf-$stamp',
    'price': 3.0,
    'quantity': 2,
    'is_active': true,
    'status': 'available',
  });
  final li4Id = idOf(li4['body']);
  final inflate = await req('PATCH', '$url/rest/v1/live_items?id=eq.$li4Id', SH, {
    'quantity': 99,
  });
  if ((inflate['http'] as int) >= 400) {
    pass('AG-P3-AG5-liveonly-inflate');
  } else {
    fail('AG-P3-AG5-liveonly-inflate', 'http=${inflate['http']}');
  }

  // --- AG-P3-AG5b: product qty inflate com live_item bloqueado ---
  final prodInflate = await req('PATCH', '$url/rest/v1/products?id=eq.$productId', SH, {
    'quantity': 99,
  });
  if ((prodInflate['http'] as int) >= 400) {
    pass('AG-P3-AG5-product-inflate');
  } else {
    fail('AG-P3-AG5-product-inflate', 'http=${prodInflate['http']}');
  }

  print('DONE exit=$exitCode');
  exit(exitCode);
}
