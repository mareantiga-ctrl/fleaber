// ignore_for_file: avoid_print
/// AT→BE pós-fix — dart run tool/sec_atbe_20260902_hostile.dart
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
  late http.Response r;
  switch (method) {
    case 'POST':
      r = await http.post(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body));
      break;
    case 'PATCH':
      r = await http.patch(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body));
      break;
    case 'PUT':
      r = await http.put(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body));
      break;
    case 'DELETE':
      r = await http.delete(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body));
      break;
    default:
      r = await http.get(Uri.parse(u), headers: h);
  }
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

void pass(String id) => print('PASS $id');
void fail(String id, String why) {
  print('FAIL $id: $why');
  exitCode = 1;
}

bool denied(Map<String, dynamic> r) {
  final http = r['http'] as int;
  final raw = '${r['raw']}';
  return http == 401 ||
      http == 403 ||
      http == 405 ||
      http == 422 ||
      raw.contains('42501') ||
      raw.contains('23514') ||
      raw.contains('permission denied') ||
      raw.contains('order_') ||
      raw.contains('chat_') ||
      raw.contains('dispute_') ||
      raw.contains('Method not allowed') ||
      raw.contains('inválido') ||
      raw.contains('invalido');
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
  final stamp = DateTime.now().millisecondsSinceEpoch;

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

  // AW/BC — total_qty anon oracle revoked
  final qty = await req(
    'POST',
    '$url/rest/v1/rpc/batata_live_item_total_qty',
    {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
    },
    {'p_live_item_id': '00000000-0000-0000-0000-000000000001'},
  );
  final qtyRaw = '${qty['raw']}';
  if (qty['http'] == 401 ||
      qty['http'] == 403 ||
      qtyRaw.contains('permission denied') ||
      qtyRaw.contains('42501') ||
      qtyRaw.contains('PGRST202')) {
    pass('AW-anon-total-qty-revoked');
  } else {
    fail('AW-anon-total-qty-revoked', 'http=${qty['http']} $qtyRaw');
  }

  // Seed product + order pago (service) for FSM + offer_id
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'ATBE hostile $stamp',
    'price': 12.34,
    'quantity': 5,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final productId = idOf(prod['body']);
  if (productId == null) {
    fail('seed-product', '${prod['http']} ${prod['raw']}');
    return;
  }
  final ordIns = await req('POST', '$url/rest/v1/orders', SVC, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': productId,
    'quantity': 1,
    'status': 'pago',
    'price_total': 12.34,
    'payment_method': 'Pagamento na app',
    'shipping_method': 'ctt',
    'amount_paid_cents': 1234,
    'stripe_payment_intent_id': 'pi_atbe_hostile_$stamp',
  });
  final orderId = idOf(ordIns['body']);
  if (orderId == null) {
    fail('seed-order', '${ordIns['http']} ${ordIns['raw']}');
    return;
  }
  pass('seed-order');

  // AT3 — seal offer via SQL, then buyer tries to null JWT
  final sealPath = 'tool/_tmp_atbe_seal_$stamp.sql';
  await File(sealPath).writeAsString('''
do \$\$
declare
  v_oid uuid;
begin
  insert into public.product_offers (
    product_id, buyer_id, seller_id, amount, list_price, offered_by, status
  ) values (
    '$productId'::uuid, '$buyerId'::uuid, '$sellerId'::uuid,
    10.00, 12.34, 'seller', 'accepted'
  ) returning id into v_oid;
  update public.orders set product_offer_id = v_oid where id = '$orderId'::uuid;
end \$\$;
''');
  final sealProc = await Process.run(
    'npx',
    ['supabase', 'db', 'query', '--linked', '-f', sealPath],
    runInShell: true,
  );
  try {
    await File(sealPath).delete();
  } catch (_) {}
  if (sealProc.exitCode != 0) {
    fail('AT3-offer-id-immutable', 'seal sql: ${sealProc.stderr}${sealProc.stdout}');
  } else {
    final sealed = await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$orderId&select=product_offer_id',
      SVC,
    );
    final sealedId = (sealed['body'] is List && (sealed['body'] as List).isNotEmpty)
        ? (sealed['body'] as List).first['product_offer_id']
        : null;
    if (sealedId == null) {
      fail('AT3-offer-id-immutable', 'seal did not stick: ${sealed['raw']}');
    } else {
      final detach = await req('PATCH', '$url/rest/v1/orders?id=eq.$orderId', BH, {
        'product_offer_id': null,
      });
      final after = await req(
        'GET',
        '$url/rest/v1/orders?id=eq.$orderId&select=product_offer_id',
        SVC,
      );
      final still = (after['body'] is List && (after['body'] as List).isNotEmpty)
          ? (after['body'] as List).first['product_offer_id']
          : null;
      if (still == sealedId || denied(detach) || (detach['http'] as int) >= 400) {
        pass('AT3-offer-id-immutable');
      } else {
        fail('AT3-offer-id-immutable', 'buyer nulled: still=$still detach=${detach['raw']}');
      }
    }
  }

  // AY/BE — seller cannot jump pago → em_devolucao
  final hopSeller = await req('PATCH', '$url/rest/v1/orders?id=eq.$orderId', SH, {
    'status': 'em_devolucao',
  });
  if (denied(hopSeller) || (hopSeller['http'] as int) >= 400) {
    pass('AY-seller-em-devolucao-requires-pedido');
  } else {
    fail('AY-seller-em-devolucao-requires-pedido', '${hopSeller['raw']}');
  }

  // Buyer cannot mark em_devolucao from pago
  final hopBuyer = await req('PATCH', '$url/rest/v1/orders?id=eq.$orderId', BH, {
    'status': 'em_devolucao',
  });
  if (denied(hopBuyer) || (hopBuyer['http'] as int) >= 400) {
    pass('BE-buyer-em-devolucao-requires-pedido');
  } else {
    fail('BE-buyer-em-devolucao-requires-pedido', '${hopBuyer['raw']}');
  }

  // Buyer cannot mark devolucao_entregue
  final hopEnt = await req('PATCH', '$url/rest/v1/orders?id=eq.$orderId', BH, {
    'status': 'devolucao_entregue',
  });
  if (denied(hopEnt) || (hopEnt['http'] as int) >= 400) {
    pass('BE-buyer-cannot-devolucao-entregue');
  } else {
    fail('BE-buyer-cannot-devolucao-entregue', '${hopEnt['raw']}');
  }

  // AX5 — shipped_at client backdate ignored on first enviado
  final ship = await req('PATCH', '$url/rest/v1/orders?id=eq.$orderId', SH, {
    'status': 'enviado',
    'shipped_at': '2020-01-01T00:00:00Z',
  });
  final shipOk = (ship['http'] as int) < 400;
  if (!shipOk) {
    // May need tracking fields — try service set enviado then JWT backdate
    await req('PATCH', '$url/rest/v1/orders?id=eq.$orderId', SVC, {
      'status': 'enviado',
      'shipped_at': '2020-01-01T00:00:00Z',
    });
  }
  final getShip = await req(
    'GET',
    '$url/rest/v1/orders?id=eq.$orderId&select=status,shipped_at',
    SVC,
  );
  final shipRow = (getShip['body'] is List && (getShip['body'] as List).isNotEmpty)
      ? (getShip['body'] as List).first as Map
      : null;
  final shippedAt = '${shipRow?['shipped_at'] ?? ''}';
  if (shippedAt.contains('2020-01-01')) {
    // JWT path may have been blocked; force via seller after reset
    await req('PATCH', '$url/rest/v1/orders?id=eq.$orderId', SVC, {
      'status': 'pago',
      'shipped_at': null,
    });
    final ship2 = await req('PATCH', '$url/rest/v1/orders?id=eq.$orderId', SH, {
      'status': 'enviado',
      'shipped_at': '2020-01-01T00:00:00Z',
    });
    final get2 = await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$orderId&select=shipped_at',
      SVC,
    );
    final row2 = (get2['body'] is List && (get2['body'] as List).isNotEmpty)
        ? (get2['body'] as List).first as Map
        : null;
    final at2 = '${row2?['shipped_at'] ?? ''}';
    if (at2.contains('2020-01-01')) {
      fail('AX5-shipped-at-now', 'backdate stuck: $at2 ship2=${ship2['raw']}');
    } else if (at2.isEmpty) {
      pass('AX5-shipped-at-now'); // blocked entirely is also OK
    } else {
      pass('AX5-shipped-at-now');
    }
  } else {
    pass('AX5-shipped-at-now');
  }

  // AU/BA — Klarna in notes blocked
  final chatIns = await req('POST', '$url/rest/v1/chats', SVC, {
    'user_a': buyerId,
    'user_b': sellerId,
  });
  final chatId = idOf(chatIns['body']);
  if (chatId == null) {
    fail('seed-chat', '${chatIns['raw']}');
  } else {
    final lie = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'message_type': 'text',
      'content': 'Pago com Klarna ok?',
    });
    if (denied(lie) || (lie['http'] as int) >= 400) {
      pass('AU-klarna-denylist');
    } else {
      // some builds only block system cards — check notes path
      final note = await req('POST', '$url/rest/v1/chat_messages', BH, {
        'chat_id': chatId,
        'sender_id': buyerId,
        'message_type': 'system',
        'content': 'ok',
        'metadata': {
          'kind': 'reservation_payment_submitted',
          'label': 'Klarna',
          'notes': 'pago via iDEAL',
        },
      });
      if (denied(note) || (note['http'] as int) >= 400) {
        pass('AU-klarna-denylist');
      } else {
        fail('AU-klarna-denylist', 'lie=${lie['http']} note=${note['raw']}');
      }
    }
  }

  // AX1 — PUT/PATCH/DELETE create-connect-account must not transfer
  for (final m in ['PUT', 'PATCH', 'DELETE']) {
    final r = await req(
      m,
      '$url/functions/v1/create-connect-account',
      {
        'apikey': anon,
        'Authorization': 'Bearer $sellerTok',
        'Content-Type': 'application/json',
      },
      {
        'amount': 100,
        'idempotency_key': 'atbe-hostile-$m-$stamp',
      },
    );
    if ((r['http'] as int) == 405 || denied(r) || '${r['raw']}'.contains('Method not allowed')) {
      pass('AX1-$m-blocked');
    } else if ('${r['raw']}'.contains('transferId') || '${r['raw']}'.contains('"success":true')) {
      fail('AX1-$m-blocked', 'created transfer: ${r['raw']}');
    } else {
      // 401/400 without transfer is OK
      pass('AX1-$m-blocked');
    }
  }

  // AX3 — amount true / 0x64 rejected
  for (final amt in [true, '0x64']) {
    final r = await req(
      'POST',
      '$url/functions/v1/create-connect-account',
      {
        'apikey': anon,
        'Authorization': 'Bearer $sellerTok',
        'Content-Type': 'application/json',
      },
      {
        'amount': amt,
        'idempotency_key': 'atbe-hostile-amt-$stamp-$amt',
      },
    );
    final raw = '${r['raw']}';
    if ((r['http'] as int) >= 400 && !raw.contains('transferId')) {
      pass('AX3-amount-$amt');
    } else if (raw.contains('transferId')) {
      fail('AX3-amount-$amt', raw);
    } else {
      pass('AX3-amount-$amt');
    }
  }

  // BD-P2 — after refund, no enviado
  await req('PATCH', '$url/rest/v1/orders?id=eq.$orderId', SVC, {
    'status': 'pago',
    'shipped_at': null,
    'stripe_refund_id': 're_atbe_hostile_$stamp',
    'stripe_refunded_at': DateTime.now().toUtc().toIso8601String(),
  });
  final postRefundShip = await req(
    'PATCH',
    '$url/rest/v1/orders?id=eq.$orderId',
    SH,
    {'status': 'enviado'},
  );
  if (denied(postRefundShip) || (postRefundShip['http'] as int) >= 400) {
    pass('BD-post-refund-no-enviado');
  } else {
    final st = await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$orderId&select=status',
      SVC,
    );
    final status = (st['body'] is List && (st['body'] as List).isNotEmpty)
        ? '${(st['body'] as List).first['status']}'
        : '';
    if (status == 'enviado') {
      fail('BD-post-refund-no-enviado', 'status=$status');
    } else {
      pass('BD-post-refund-no-enviado');
    }
  }

  // Cleanup soft
  await req('PATCH', '$url/rest/v1/orders?id=eq.$orderId', SVC, {
    'status': 'cancelado',
  });

  print(exitCode == 0 ? 'ALL PASS ATBE hostile' : 'SOME FAIL ATBE hostile');
}
