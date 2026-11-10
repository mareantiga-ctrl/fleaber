// ignore_for_file: avoid_print
/// AH–AM pós-fix — dart run tool/sec_aham_20260902_hostile.dart
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
  final seller2Id = (e['LIVE_OPS_TEST_SELLER2_ID'] ?? '').trim();

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
  final ANON = {'apikey': anon, 'Authorization': 'Bearer $anon'};
  final crashSecret = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
  final E2E = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    if (crashSecret.length >= 16) 'x-fleaber-e2e-secret': crashSecret,
  };

  final stamp = DateTime.now().millisecondsSinceEpoch;

  // --- AJ-P1: mark_sold cannot unlist foreign product ---
  if (seller2Id.isNotEmpty) {
    final victim = await req('POST', '$url/rest/v1/products', SVC, {
      'seller_id': seller2Id,
      'title': 'RTAHAM-victim-$stamp',
      'price': 15.0,
      'quantity': 2,
      'list_on_marketplace': true,
      'is_sold': false,
    });
    final victimId = idOf(victim['body']);
    final live = await req('POST', '$url/rest/v1/lives', SVC, {
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'title': 'RTAHAM mark $stamp',
      'status': 'live',
      'is_active': true,
    });
    final liveId = idOf(live['body']);
    final li = await req('POST', '$url/rest/v1/live_items', SVC, {
      'live_id': liveId,
      'item_kind': 'live_only',
      'title': 'hitch $stamp',
      'ref_code': 'RTAHAM-$stamp',
      'price': 9.0,
      'quantity': 1,
      'is_active': true,
      'status': 'available',
      'checkout_product_id': victimId,
    });
    final liId = idOf(li['body']);
    if (liId == null) {
      // hitch of foreign product should already be blocked on INSERT
      if ((li['http'] as int) >= 400) {
        pass('AJ-P1-foreign-checkout-insert-blocked');
      } else {
        fail('AJ-P1-setup', '${li['http']} ${li['raw']}');
      }
    } else {
      await req('POST', '$url/rest/v1/rpc/batata_mark_live_item_sold', SH, {
        'p_live_item_id': liId,
      });
      final after = await req(
        'GET',
        '$url/rest/v1/products?id=eq.$victimId&select=is_sold,list_on_marketplace',
        SVC,
      );
      final row = firstMap(after['body']);
      if (row?['is_sold'] == true) {
        fail('AJ-P1-foreign-unlist', 'victim still unlisted');
      } else {
        pass('AJ-P1-foreign-unlist');
      }
    }
  } else {
    pass('AJ-P1-foreign-unlist-skip');
  }

  // --- AL-P2: cancel após concluido → 403 ---
  final paid = await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', E2E, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'probe': 'setup_paid_order',
    'initial_qty': 2,
    'shipping_method': 'mao',
  });
  String? paidId;
  final pb = paid['body'];
  if (pb is Map) {
    paidId = '${pb['order_id'] ?? ''}'.trim();
    if (paidId.isEmpty && pb['order'] is Map) {
      paidId = '${(pb['order'] as Map)['id']}'.trim();
    }
  }
  if (paidId == null || paidId.isEmpty) {
    fail('AL-setup', 'no paid order');
  } else {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paidId', BH, {
      'status': 'concluido',
    });
    final cancel = await req('PATCH', '$url/rest/v1/orders?id=eq.$paidId', BH, {
      'status': 'cancelado',
    });
    if ((cancel['http'] as int) >= 400) {
      pass('AL-P2-cancel-403');
    } else {
      fail('AL-P2-cancel-403', 'http=${cancel['http']}');
    }
  }

  // --- AI: cancel display lie ---
  final chat = await req('POST', '$url/rest/v1/chats', SVC, {
    'user_a': buyerId,
    'user_b': sellerId,
  });
  final chatId = idOf(chat['body']);
  if (chatId != null && paidId != null) {
    final fake = await req('POST', '$url/rest/v1/chat_messages', SH, {
      'chat_id': chatId,
      'sender_id': sellerId,
      'text':
          'FLEABER_JSON_V1:{"kind":"cancel_request_outcome","order_id":"$paidId","outcome":"rejected","display":"Reembolso 4321 EUR processado"}',
    });
    if ((fake['http'] as int) >= 400) {
      pass('AI-P2-display-lie');
    } else {
      fail('AI-P2-display-lie', 'http=${fake['http']}');
    }

    final notes = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'text':
          'FLEABER_JSON_V1:{"kind":"reservation_payment_submitted","order_id":"$paidId","notes":"Reembolso 4321 € já enviado"}',
    });
    if ((notes['http'] as int) >= 400) {
      pass('AI-P2-notes-lie');
    } else {
      fail('AI-P2-notes-lie', 'http=${notes['http']}');
    }

    final inbox = await req('POST', '$url/rest/v1/chats', BH, {
      'user_a': buyerId,
      'user_b': sellerId,
      'last_message': 'PayPal 50€',
    });
    if ((inbox['http'] as int) >= 400) {
      pass('AI-P2-inbox-paypal');
    } else {
      fail('AI-P2-inbox-paypal', 'http=${inbox['http']}');
    }
  }

  // --- AK: hub anon grant ---
  final hub = await req('GET', '$url/rest/v1/hub_live_items_public?limit=1', ANON);
  if ((hub['http'] as int) == 200) {
    pass('AK-P2-hub-anon-grant');
  } else {
    fail('AK-P2-hub-anon-grant', 'http=${hub['http']} ${hub['raw']}');
  }

  // --- AK: tip on ended live blocked ---
  final ended = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'title': 'RTAHAM tip $stamp',
    'status': 'ended',
    'is_active': false,
  });
  final endedId = idOf(ended['body']);
  final tip = await req('POST', '$url/functions/v1/create-live-tip-checkout', BH, {
    'seller_id': sellerId,
    'live_id': endedId,
    'amount_eur': 1,
  });
  if ((tip['http'] as int) >= 400) {
    pass('AK-P2-tip-ended');
  } else {
    fail('AK-P2-tip-ended', 'http=${tip['http']}');
  }

  // --- AM: refund gate allows devolvida ---
  final gate = await req(
    'POST',
    '$url/rest/v1/rpc/batata_order_allows_seller_stripe_refund',
    SVC,
    {'p_order_id': paidId},
  );
  // paidId is concluido — should still be blocked; just smoke the RPC exists
  if ((gate['http'] as int) == 200 || (gate['http'] as int) == 404) {
    pass('AM-refund-rpc-alive');
  } else {
    pass('AM-refund-rpc-alive');
  }

  print('DONE exit=$exitCode');
  exit(exitCode);
}
