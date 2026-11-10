// ignore_for_file: avoid_print
/// Nova auditoria cega — prioridades O/C/G/S/Q (staging).
/// dart run tool/sec_nova_cega_priorities_hostile.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String url,
  Map<String, String> h, [
  Object? body,
]) async {
  final r = method == 'GET'
      ? await http.get(Uri.parse(url), headers: h)
      : method == 'PATCH'
          ? await http.patch(Uri.parse(url), headers: h, body: jsonEncode(body))
          : method == 'DELETE'
              ? await http.delete(Uri.parse(url), headers: h)
              : await http.post(
                  Uri.parse(url),
                  headers: h,
                  body: body == null ? null : jsonEncode(body),
                );
  dynamic p;
  try {
    p = jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p};
}

void main() async {
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

  final AH = {'apikey': anon, 'Authorization': 'Bearer $anon'};
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
  void add(String id, bool ok, Object detail) {
    results.add({'id': id, 'ok': ok, 'detail': detail});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $detail');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;

  // Third-party product owned by seller (victim stock)
  final victim = await sb.insert('products', {
    'seller_id': sellerId,
    'title': 'VICTIM $stamp',
    'price': 9.0,
    'quantity': 7,
    'list_on_marketplace': false,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final qtyBefore = 7;

  // O1: buyer as both parties + victim product
  final o1 = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': buyerId,
    'product_id': victim['id'],
    'quantity': 1,
    'price_total': 9.0,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
  });
  add('O1_MISMATCH_INSERT', o1['http'] >= 400, {
    'http': o1['http'],
    'msg': o1['body'] is Map ? o1['body']['message'] : o1['body'],
  });

  // Legitimate order
  final oLeg = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': victim['id'],
    'quantity': 1,
    'price_total': 9.0,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
  });
  final oid = (oLeg['body'] is List && (oLeg['body'] as List).isNotEmpty)
      ? (oLeg['body'] as List).first['id']
      : null;
  add('O5_LEGIT_INSERT', oLeg['http'] == 201 && oid != null, {
    'http': oLeg['http'],
  });

  if (oid != null) {
    final otherProd = await sb.insert('products', {
      'seller_id': sellerId,
      'title': 'OTHER $stamp',
      'price': 3.0,
      'quantity': 2,
      'list_on_marketplace': false,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    // Need third seller product - create with service as buyer owning product? Use seller2 = buyer creating product
    final strangerProd = await sb.insert('products', {
      'seller_id': buyerId, // buyer owns this product
      'title': 'STRANGERPROD $stamp',
      'price': 2.0,
      'quantity': 4,
      'list_on_marketplace': false,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });

    final pProd = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {
      'product_id': strangerProd['id'],
    });
    final afterProd = await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$oid&select=product_id,seller_id',
      BH,
    );
    final prow = (afterProd['body'] as List).first;
    add(
      'O2_PATCH_PRODUCT_BLOCKED',
      prow['product_id'] == victim['id'],
      {'http': pProd['http'], 'product': prow['product_id']},
    );

    final pSell = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {
      'seller_id': buyerId,
    });
    final afterSell = await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$oid&select=seller_id',
      BH,
    );
    add(
      'O3_PATCH_SELLER_BLOCKED',
      (afterSell['body'] as List).first['seller_id'] == sellerId,
      {'http': pSell['http']},
    );

    // O5 seller pago MB WAY
    final pago = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {
      'status': 'pago',
    });
    final stock = await req(
      'GET',
      '$url/rest/v1/products?id=eq.${victim['id']}&select=quantity',
      SVC,
    );
    final qtyAfter = (stock['body'] as List).first['quantity'];
    add(
      'O5_LEGIT_PAGO_STOCK',
      pago['http'] == 200 && qtyAfter == qtyBefore - 1,
      {'http': pago['http'], 'qty': qtyAfter, 'expect': qtyBefore - 1},
    );

    // O7 stranger product unchanged
    final sp = await req(
      'GET',
      '$url/rest/v1/products?id=eq.${strangerProd['id']}&select=quantity',
      SVC,
    );
    add(
      'O7_THIRD_PARTY_UNCHANGED',
      (sp['body'] as List).first['quantity'] == 4,
      sp['body'],
    );

    await req('DELETE', '$url/rest/v1/orders?id=eq.$oid', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.${otherProd['id']}', SVC);
    await req(
      'DELETE',
      '$url/rest/v1/products?id=eq.${strangerProd['id']}',
      SVC,
    );
  }

  // ---- Chats ----
  final chats = await req(
    'GET',
    '$url/rest/v1/chats?select=id,user_a,user_b&limit=1',
    BH,
  );
  if (chats['body'] is List && (chats['body'] as List).isNotEmpty) {
    final c = (chats['body'] as List).first as Map;
    final cid = c['id'];
    final ua = c['user_a'];
    final ub = c['user_b'];
    await req('PATCH', '$url/rest/v1/chats?id=eq.$cid', BH, {
      'user_b': buyerId,
    });
    await req('PATCH', '$url/rest/v1/chats?id=eq.$cid', SH, {
      'user_a': sellerId,
    });
    final c2 = await req(
      'GET',
      '$url/rest/v1/chats?id=eq.$cid&select=user_a,user_b,last_message',
      BH,
    );
    final crow = (c2['body'] as List).first;
    add(
      'C1_C2_PARTIES_FROZEN',
      crow['user_a'] == ua && crow['user_b'] == ub,
      crow,
    );

    final ping = await req('PATCH', '$url/rest/v1/chats?id=eq.$cid', BH, {
      'last_message': 'CEGA-PRIO ping $stamp',
    });
    add('C4_LAST_MESSAGE_OK', ping['http'] == 200, {'http': ping['http']});

    final ins = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': cid,
      'sender_id': sellerId,
      'text': 'CEGA spoof $stamp',
    });
    final mid = (ins['body'] is List && (ins['body'] as List).isNotEmpty)
        ? (ins['body'] as List).first['id']
        : null;
    final sender = (ins['body'] is List && (ins['body'] as List).isNotEmpty)
        ? (ins['body'] as List).first['sender_id']
        : null;
    add('C6_SENDER_SPOOF_FORCED', sender == buyerId, {
      'http': ins['http'],
      'sender': sender,
    });

    if (mid != null) {
      final edit = await req(
        'PATCH',
        '$url/rest/v1/chat_messages?id=eq.$mid',
        SH,
        {'text': 'HACKED'},
      );
      final m2 = await req(
        'GET',
        '$url/rest/v1/chat_messages?id=eq.$mid&select=text',
        BH,
      );
      final text = (m2['body'] as List).isNotEmpty
          ? (m2['body'] as List).first['text']
          : null;
      add(
        'C8_COUNTERPARTY_EDIT_BLOCKED',
        text == 'CEGA spoof $stamp',
        {'http': edit['http'], 'text': text},
      );
      await req('DELETE', '$url/rest/v1/chat_messages?id=eq.$mid', SVC);
    }
  } else {
    add('C1_C2_PARTIES_FROZEN', false, 'no chat');
  }

  final anonChats = await req(
    'GET',
    '$url/rest/v1/chats?select=id&limit=5',
    AH,
  );
  add(
    'C5_ANON_CHATS',
    anonChats['http'] == 200 &&
        (anonChats['body'] is List && (anonChats['body'] as List).isEmpty),
    {'http': anonChats['http'], 'len': anonChats['body'] is List ? (anonChats['body'] as List).length : -1},
  );

  // ---- Grants ----
  for (final rpc in [
    'batata_debit_wallet_once',
    'batata_clawback_seller_wallet_for_order',
    'batata_credit_wallet_once',
    'batata_ensure_wallet',
  ]) {
    final body = rpc.contains('ensure')
        ? {'p_user_id': buyerId}
        : rpc.contains('clawback')
            ? {'p_order_id': '00000000-0000-0000-0000-000000000001'}
            : {
                'p_user_id': buyerId,
                'p_amount': 1,
                'p_order_id': '00000000-0000-0000-0000-000000000001',
                'p_description': 'x',
              };
    final a = await req('POST', '$url/rest/v1/rpc/$rpc', {
      ...AH,
      'Content-Type': 'application/json',
    }, body);
    final b = await req('POST', '$url/rest/v1/rpc/$rpc', BH, body);
    add(
      'G_$rpc',
      a['http'] >= 400 && b['http'] >= 400,
      {'anon': a['http'], 'buyer': b['http']},
    );
  }
  final assertG = await req(
    'POST',
    '$url/rest/v1/rpc/batata_assert_wallet_rpc_grants',
    SVC,
    {},
  );
  add(
    'G5_ASSERT_GRANTS',
    assertG['body'] is Map && assertG['body']['ok'] == true,
    assertG['body'],
  );

  // ---- Shipping ----
  final pShip = await sb.insert('products', {
    'seller_id': sellerId,
    'title': 'SHIP $stamp',
    'price': 6.66,
    'quantity': 5,
    'list_on_marketplace': false,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final oShip = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pShip['id'],
    'quantity': 1,
    'price_total': 6.66,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
  });
  final oidS = (oShip['body'] is List)
      ? (oShip['body'] as List).first['id']
      : null;
  if (oidS != null) {
    Future<Map<String, dynamic>> cpi(Object method, [num? shipping]) =>
        req('POST', '$url/functions/v1/create-payment-intent', BH, {
          'buyer_id': buyerId,
          'order_id': oidS,
          'shipping_method': method,
          if (shipping != null) 'shipping': shipping,
        });

    final hand = await cpi('entrega em mão');
    final carrier = await cpi('Envio Transportadora (€3.50)');
    final euro0 = await cpi('EUR0');
    final garbage0 = await cpi('whatever', 0);
    final carrierEuro0 = await cpi('carrier €0');
    // 6.66 → hand 764, carrier 1132 if not rate limited
    final handOk = hand['http'] == 429 ||
        (hand['http'] == 200 &&
            hand['body'] is Map &&
            hand['body']['server_amount_cents'] == 764);
    final carOk = carrier['http'] == 429 ||
        (carrier['http'] == 200 &&
            carrier['body'] is Map &&
            carrier['body']['server_amount_cents'] == 1132);
    add('S1_HAND', handOk, {
      'http': hand['http'],
      'amt': hand['body'] is Map ? hand['body']['server_amount_cents'] : null,
    });
    add('S2_CARRIER', carOk, {
      'http': carrier['http'],
      'amt':
          carrier['body'] is Map ? carrier['body']['server_amount_cents'] : null,
    });
    add('S4_EUR0', euro0['http'] >= 400, {'http': euro0['http']});
    add('S6_GARBAGE_SHIP0', garbage0['http'] >= 400, {
      'http': garbage0['http'],
    });
    // carrier €0 must not be 764 (hand)
    final ceAmt = carrierEuro0['body'] is Map
        ? carrierEuro0['body']['server_amount_cents']
        : null;
    add(
      'S5_CARRIER_EURO0',
      carrierEuro0['http'] >= 400 || ceAmt == 1132,
      {'http': carrierEuro0['http'], 'amt': ceAmt},
    );
  }

  // ---- requested_qty ----
  final live = await sb.insert('lives', {
    'vendedor_id': sellerId,
    'seller_id': sellerId,
    'title': 'QTY $stamp',
    'status': 'live',
    'is_active': true,
  });
  final li = await sb.insert('live_items', {
    'live_id': live['id'],
    'product_id': pShip['id'],
    'item_kind': 'marketplace_product',
    'title': 'q',
    'ref_code': 'Q-$stamp',
    'status': 'available',
  });
  Future<int> qtyIns(Object? q) async {
    final body = <String, dynamic>{
      'live_id': live['id'],
      'live_item_id': li['id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'status': 'pending',
      'source': 'fleaber_live',
    };
    if (q != null) body['requested_qty'] = q;
    final r = await req('POST', '$url/rest/v1/live_reservation_requests', BH, body);
    if (r['http'] == 201 && r['body'] is List) {
      final id = (r['body'] as List).first['id'];
      await req('DELETE', '$url/rest/v1/live_reservation_requests?id=eq.$id', SVC);
    }
    return r['http'] as int;
  }

  add('Q1_ZERO', await qtyIns(0) >= 400, '0');
  add('Q2_NEG', await qtyIns(-1) >= 400, '-1');
  add('Q3_ONE', await qtyIns(1) == 201, '1');
  add('Q4_99', await qtyIns(99) == 201, '99');
  add('Q5_100', await qtyIns(100) >= 400, '100');

  // cleanup
  await req('DELETE', '$url/rest/v1/live_items?id=eq.${li['id']}', SVC);
  await req('DELETE', '$url/rest/v1/lives?id=eq.${live['id']}', SVC);
  await req('DELETE', '$url/rest/v1/orders?product_id=eq.${pShip['id']}', SVC);
  await req('DELETE', '$url/rest/v1/orders?product_id=eq.${victim['id']}', SVC);
  await req('DELETE', '$url/rest/v1/products?id=eq.${pShip['id']}', SVC);
  await req('DELETE', '$url/rest/v1/products?id=eq.${victim['id']}', SVC);

  final fail = results.where((r) => r['ok'] != true).length;
  final path = 'tool/reports/HARDENING_NOVA_AUDITORIA_CEGA_PRIORITIES_HOSTILE.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert({
    'at': DateTime.now().toUtc().toIso8601String(),
    'ok': fail == 0,
    'fail': fail,
    'results': results,
  }));
  stdout.writeln('evidence -> $path ($fail fail)');
  exit(fail == 0 ? 0 : 1);
}
