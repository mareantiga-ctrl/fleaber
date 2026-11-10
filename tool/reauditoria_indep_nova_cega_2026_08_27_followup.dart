// ignore_for_file: avoid_print
/// Follow-up: chats, ensure_wallet p_user_id, qty 99 pago, seller qty 0, 1 CPI.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

final out = <String, dynamic>{};
void rec(String id, Object? v) {
  out[id] = v;
  final s = jsonEncode(v);
  print('$id: ${s.length > 340 ? s.substring(0, 340) : s}');
}

Future<Map<String, dynamic>> req(
  String method,
  String url,
  Map<String, String> headers, [
  Object? body,
]) async {
  final uri = Uri.parse(url);
  late http.Response r;
  final b = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'GET':
      r = await http.get(uri, headers: headers);
      break;
    case 'POST':
      r = await http.post(uri, headers: headers, body: b);
      break;
    case 'PATCH':
      r = await http.patch(uri, headers: headers, body: b);
      break;
    case 'DELETE':
      r = await http.delete(uri, headers: headers);
      break;
    default:
      throw StateError(method);
  }
  Object? parsed;
  try {
    parsed = jsonDecode(r.body);
  } catch (_) {
    parsed = r.body;
  }
  return {'ok': r.statusCode >= 200 && r.statusCode < 300, 'status': r.statusCode, 'body': parsed};
}

String? rowId(Object? body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return (body.first as Map)['id']?.toString();
  }
  if (body is Map) return body['id']?.toString();
  return null;
}

Map<String, dynamic>? rowMap(Object? body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
  return null;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final c = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerJwt = await c.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await c.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  Map<String, String> u(String jwt) => {
        'apikey': anon,
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  final BH = u(buyerJwt);
  final SH = u(sellerJwt);
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final AH = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
  };

  rec('chats_buyer', await req('GET', '$url/rest/v1/chats?select=id,user_a,user_b,product_id,last_message&limit=3', BH));
  rec('chats_seller', await req('GET', '$url/rest/v1/chats?select=id,user_a,user_b&limit=3', SH));
  rec('chats_anon', await req('GET', '$url/rest/v1/chats?select=id&limit=3', AH));
  final chatId = rowId((out['chats_buyer'] as Map)['body']);
  if (chatId != null) {
    final orig = rowMap((out['chats_buyer'] as Map)['body']);
    rec('chat_orig', orig);
    rec('chat_patch_b', await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
      'user_b': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    }));
    rec('chat_patch_a', await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', SH, {
      'user_a': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    }));
    rec('chat_self', await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
      'user_a': buyerId,
      'user_b': buyerId,
    }));
    rec('chat_swap_both', await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
      'user_a': orig?['user_b'],
      'user_b': orig?['user_a'],
    }));
    rec('chat_product', await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
      'product_id': '00000000-0000-0000-0000-000000000001',
    }));
    rec('chat_last', await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
      'last_message': 'INDEP27b ping',
    }));
    rec('chat_after', await req(
      'GET',
      '$url/rest/v1/chats?select=id,user_a,user_b,product_id,last_message&id=eq.$chatId',
      BH,
    ));
    rec('msg_spoof', await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': sellerId,
      'text': 'INDEP27b spoof',
    }));
    rec('msg_foreign', await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': '00000000-0000-0000-0000-000000000099',
      'sender_id': buyerId,
      'text': 'nope',
    }));
    rec('msgs_all_limit', await req(
      'GET',
      '$url/rest/v1/chat_messages?select=id,chat_id,sender_id,text&limit=5',
      BH,
    ));
    final mid = rowId((out['msg_spoof'] as Map)['body']);
    if (mid != null) {
      rec('msg_edit_seller', await req('PATCH', '$url/rest/v1/chat_messages?id=eq.$mid', SH, {
        'text': 'hacked',
      }));
      rec('msg_read', await req('PATCH', '$url/rest/v1/chat_messages?id=eq.$mid', SH, {
        'is_read': true,
      }));
      rec('msg_after', await req(
        'GET',
        '$url/rest/v1/chat_messages?select=id,sender_id,text,is_read&id=eq.$mid',
        BH,
      ));
      await req('DELETE', '$url/rest/v1/chat_messages?id=eq.$mid', SVC);
    }
  }

  rec('ensure_self_buyer', await req('POST', '$url/rest/v1/rpc/batata_ensure_wallet', BH, {
    'p_user_id': buyerId,
  }));
  rec('ensure_other_buyer', await req('POST', '$url/rest/v1/rpc/batata_ensure_wallet', BH, {
    'p_user_id': sellerId,
  }));
  rec('ensure_other_seller', await req('POST', '$url/rest/v1/rpc/batata_ensure_wallet', SH, {
    'p_user_id': buyerId,
  }));
  rec('ensure_anon', await req('POST', '$url/rest/v1/rpc/batata_ensure_wallet', AH, {
    'p_user_id': buyerId,
  }));
  rec('partial_buyer', await req('POST', '$url/rest/v1/rpc/batata_process_partial_refund_dispute', BH, {
    'p_order_id': '00000000-0000-0000-0000-000000000001',
    'p_refund_percent': 50,
  }));
  rec('partial_seller', await req('POST', '$url/rest/v1/rpc/batata_process_partial_refund_dispute', SH, {
    'p_order_id': '00000000-0000-0000-0000-000000000001',
    'p_refund_percent': 50,
  }));

  final prod = await req('POST', '$url/rest/v1/products', SH, {
    'seller_id': sellerId,
    'title': 'INDEP27b qty99',
    'price': 6.66,
    'quantity': 5,
    'list_on_marketplace': false,
    'available_for_live': false,
    'is_sold': false,
  });
  final pid = rowId(prod['body']);
  rec('prod99', {'status': prod['status'], 'id': pid});
  final o99 = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 99,
    'price_total': 6.66,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
  });
  final oid99 = rowId(o99['body']);
  rec('ord99', {'status': o99['status'], 'id': oid99, 'qty': rowMap(o99['body'])?['quantity']});
  rec('seller_pago_99', await req('PATCH', '$url/rest/v1/orders?id=eq.$oid99', SH, {'status': 'pago'}));
  rec('qty_after_99_pago', await req(
    'GET',
    '$url/rest/v1/products?select=id,quantity,is_sold&id=eq.$pid',
    SH,
  ));
  rec('ord99_after', await req(
    'GET',
    '$url/rest/v1/orders?select=id,status,quantity,stock_units_applied&id=eq.$oid99',
    BH,
  ));

  rec('ship_one', await req('POST', '$url/functions/v1/create-payment-intent', BH, {
    'buyer_id': buyerId,
    'order_id': oid99,
    'shipping_method': 'whatever',
    'shipping': 0,
  }));
  rec('ship_hand_one', await req('POST', '$url/functions/v1/create-payment-intent', BH, {
    'buyer_id': buyerId,
    'order_id': oid99,
    'shipping_method': 'hand',
  }));

  rec('qty_seller_0', await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
    'live_id': 'd43f048f-fd95-4fec-ac7a-4bea85cadeec',
    'live_item_id': 'ffb7b7e5-3007-44c7-b59d-44f99f36cb7f',
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'source': 'fleaber_live',
    'status': 'pending',
    'requested_qty': 1,
  }));
  final rid = rowId((out['qty_seller_0'] as Map)['body']);
  if (rid != null) {
    rec('seller_qty_to_0', await req(
      'PATCH',
      '$url/rest/v1/live_reservation_requests?id=eq.$rid',
      SH,
      {'requested_qty': 0},
    ));
    rec('seller_qty_to_100', await req(
      'PATCH',
      '$url/rest/v1/live_reservation_requests?id=eq.$rid',
      SH,
      {'requested_qty': 100},
    ));
    rec('seller_qty_to_99', await req(
      'PATCH',
      '$url/rest/v1/live_reservation_requests?id=eq.$rid',
      SH,
      {'requested_qty': 99},
    ));
    rec('req_after_seller', await req(
      'GET',
      '$url/rest/v1/live_reservation_requests?select=id,requested_qty,status&id=eq.$rid',
      SH,
    ));
  }

  rec('wallets', await req(
    'GET',
    '$url/rest/v1/wallets?select=id,balance&id=in.($buyerId,$sellerId)',
    SVC,
  ));

  await req('DELETE', '$url/rest/v1/live_reservation_requests?buyer_id=eq.$buyerId&source=eq.fleaber_live&status=eq.pending', SVC);
  if (pid != null) {
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
  }

  final path = 'tool/reports/REAUDITORIA_INDEP_NOVA_CEGA_2026_08_27_FOLLOWUP.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('WROTE $path');
}
