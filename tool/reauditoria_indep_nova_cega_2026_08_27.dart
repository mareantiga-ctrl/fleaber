// ignore_for_file: avoid_print
/// Auditoria cega independente 2026-08-27 (pós-hardening).
/// Não usa relatórios anteriores como prova. JWT buyer/seller/anon.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

final out = <String, dynamic>{};
void rec(String id, Object? v) {
  out[id] = v;
  final s = jsonEncode(v);
  print('$id: ${s.length > 300 ? s.substring(0, 300) : s}');
}

Map<String, String> hUser(String anon, String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
Map<String, String> hAnon(String anon) => {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
    };
Map<String, String> hSvc(String svc) => {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

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
  return {
    'ok': r.statusCode >= 200 && r.statusCode < 300,
    'status': r.statusCode,
    'body': parsed,
  };
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

Object? compactErr(Object? body) {
  if (body is Map) {
    return {
      'message': body['message'] ?? body['error'] ?? body['msg'],
      'code': body['code'],
    };
  }
  return body;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    throw StateError('Recusado: URL não é staging');
  }
  rec('meta', {
    'at': DateTime.now().toUtc().toIso8601String(),
    'staging': 'fxdknzrqjenzqcvnwqqq',
    'production_touched': false,
  });
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final e2e = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
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
  final BH = hUser(anon, buyerJwt);
  final SH = hUser(anon, sellerJwt);
  final AH = hAnon(anon);
  final SVC = hSvc(svc);
  final noneJwt =
      'eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJyb2xlIjoic2VydmljZV9yb2xlIiwicmVmIjoiZnhka256cnFqZW56cWN2bndxcXEifQ.';
  final NONE = {
    'apikey': anon,
    'Authorization': 'Bearer $noneJwt',
    'Content-Type': 'application/json',
  };

  rec(
    'wallets0',
    await req(
      'GET',
      '$url/rest/v1/wallets?select=id,balance&id=in.($buyerId,$sellerId)',
      SVC,
    ),
  );

  // ---------- 1. ORDER / STOCK ----------
  final victim = await req('POST', '$url/rest/v1/products', SH, {
    'seller_id': sellerId,
    'title': 'INDEP27 victim stock',
    'price': 6.66,
    'quantity': 7,
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
  });
  final victimPid = rowId(victim['body']);
  rec('prod_victim', {'status': victim['status'], 'id': victimPid});

  final other = await req(
    'GET',
    '$url/rest/v1/products?select=id,seller_id,quantity,title&seller_id=neq.$sellerId&seller_id=neq.$buyerId&list_on_marketplace=eq.true&limit=2',
    BH,
  );
  rec('prod_third_party', {
    'status': other['status'],
    'n': other['body'] is List ? (other['body'] as List).length : 0,
    'ids': other['body'] is List
        ? (other['body'] as List)
            .take(2)
            .map((x) => {
                  'id': (x as Map)['id'],
                  'seller': x['seller_id'],
                  'qty': x['quantity'],
                })
            .toList()
        : other['body'],
  });
  String? thirdPid;
  String? thirdSeller;
  int? thirdQty;
  if (other['body'] is List && (other['body'] as List).isNotEmpty) {
    final m = Map<String, dynamic>.from((other['body'] as List).first as Map);
    thirdPid = m['id']?.toString();
    thirdSeller = m['seller_id']?.toString();
    thirdQty = (m['quantity'] as num?)?.toInt();
  }

  rec(
    'ord_mismatch_buyer_as_seller',
    await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': buyerId,
      'product_id': victimPid,
      'quantity': 1,
      'price_total': 6.66,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    }),
  );
  rec(
    'qty_after_mismatch',
    await req(
      'GET',
      '$url/rest/v1/products?select=id,quantity&id=eq.$victimPid',
      SH,
    ),
  );

  if (thirdPid != null) {
    rec(
      'ord_mismatch_third',
      await req('POST', '$url/rest/v1/orders', BH, {
        'buyer_id': buyerId,
        'seller_id': buyerId,
        'product_id': thirdPid,
        'quantity': 1,
        'price_total': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      }),
    );
    rec(
      'ord_mismatch_third_claim_seller',
      await req('POST', '$url/rest/v1/orders', SH, {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': thirdPid,
        'quantity': 1,
        'price_total': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
      }),
    );
    rec(
      'qty_third_after',
      await req(
        'GET',
        '$url/rest/v1/products?select=id,quantity,seller_id&id=eq.$thirdPid',
        SVC,
      ),
    );
  }

  final legit = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': victimPid,
    'quantity': 1,
    'price_total': 6.66,
    'status': 'pago',
    'amount_paid_cents': 99999,
    'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
  });
  final oid = rowId(legit['body']);
  rec('ord_legit_insert_pago_stripped', {
    'status': legit['status'],
    'id': oid,
    'status_col': rowMap(legit['body'])?['status'],
    'paid': rowMap(legit['body'])?['amount_paid_cents'],
  });

  rec(
    'ord_patch_product_id',
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {
      'product_id': thirdPid ?? '00000000-0000-0000-0000-000000000001',
    }),
  );
  rec(
    'ord_patch_seller_id',
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {
      'seller_id': buyerId,
    }),
  );
  rec(
    'ord_patch_both',
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {
      'seller_id': buyerId,
      'product_id': thirdPid ?? victimPid,
    }),
  );
  rec(
    'ord_patch_price_paid',
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {
      'amount_paid_cents': 1115,
      'price_total': 0.01,
    }),
  );
  rec(
    'ord_after_patches',
    await req(
      'GET',
      '$url/rest/v1/orders?select=id,seller_id,product_id,status,amount_paid_cents,price_total,quantity&id=eq.$oid',
      BH,
    ),
  );

  rec(
    'ord_seller_pago',
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {
      'status': 'pago',
    }),
  );
  rec(
    'qty_after_legit_pago',
    await req(
      'GET',
      '$url/rest/v1/products?select=id,quantity&id=eq.$victimPid',
      SH,
    ),
  );

  rec(
    'ord_qty99_then_pago',
    await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': victimPid,
      'quantity': 99,
      'price_total': 6.66,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    }),
  );

  final liveItem = await req(
    'GET',
    '$url/rest/v1/live_items?select=id,live_id,product_id,quantity,title&limit=3',
    SVC,
  );
  rec('live_items_svc', {
    'status': liveItem['status'],
    'rows': liveItem['body'] is List
        ? (liveItem['body'] as List).take(3).toList()
        : liveItem['body'],
  });

  rec(
    'rpc_process_reservation',
    await req('POST', '$url/rest/v1/rpc/batata_process_live_reservation_request', BH, {
      'p_request_id': oid,
      'p_action': 'accept',
      'p_actor_id': buyerId,
      'p_note': 'x',
    }),
  );

  // ---------- 2. CHATS ----------
  final chats = await req(
    'GET',
    '$url/rest/v1/chats?select=id,user_a,user_b,product_id,order_id,last_message&limit=5',
    BH,
  );
  rec('chats_buyer_n', {
    'status': chats['status'],
    'n': chats['body'] is List ? (chats['body'] as List).length : 0,
  });
  rec(
    'chats_anon',
    await req('GET', '$url/rest/v1/chats?select=id&limit=3', AH),
  );
  rec(
    'chats_foreign_guess',
    await req(
      'GET',
      '$url/rest/v1/chats?select=id,user_a,user_b&id=eq.00000000-0000-0000-0000-000000000099',
      BH,
    ),
  );
  final chatId = rowId(chats['body']);
  final chat0 = rowMap(chats['body']);
  if (chatId != null && chat0 != null) {
    rec('chat_orig', {
      'id': chatId,
      'a': chat0['user_a'],
      'b': chat0['user_b'],
    });
    rec(
      'chat_patch_b',
      await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
        'user_b': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      }),
    );
    rec(
      'chat_patch_a_seller',
      await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', SH, {
        'user_a': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      }),
    );
    rec(
      'chat_self',
      await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
        'user_a': buyerId,
        'user_b': buyerId,
      }),
    );
    rec(
      'chat_product',
      await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
        'product_id': victimPid,
      }),
    );
    rec(
      'chat_order',
      await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
        'order_id': oid,
      }),
    );
    rec(
      'chat_legit_last',
      await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
        'last_message': 'INDEP27 ping',
      }),
    );
    rec(
      'chat_after',
      await req(
        'GET',
        '$url/rest/v1/chats?select=id,user_a,user_b,product_id,order_id,last_message&id=eq.$chatId',
        BH,
      ),
    );
    rec(
      'msg_spoof',
      await req('POST', '$url/rest/v1/chat_messages', BH, {
        'chat_id': chatId,
        'sender_id': sellerId,
        'text': 'INDEP27 spoof',
      }),
    );
    rec(
      'msg_foreign_chat',
      await req('POST', '$url/rest/v1/chat_messages', BH, {
        'chat_id': '00000000-0000-0000-0000-000000000099',
        'sender_id': buyerId,
        'text': 'nope',
      }),
    );
    rec(
      'msgs_select',
      await req(
        'GET',
        '$url/rest/v1/chat_messages?select=id,sender_id,text,is_read&chat_id=eq.$chatId&text=eq.INDEP27%20spoof',
        BH,
      ),
    );
    final mid = rowId((out['msg_spoof'] as Map)['body']);
    if (mid != null) {
      rec(
        'msg_edit_as_seller',
        await req('PATCH', '$url/rest/v1/chat_messages?id=eq.$mid', SH, {
          'text': 'hacked',
        }),
      );
      rec(
        'msg_read',
        await req('PATCH', '$url/rest/v1/chat_messages?id=eq.$mid', SH, {
          'is_read': true,
        }),
      );
      rec(
        'msg_after',
        await req(
          'GET',
          '$url/rest/v1/chat_messages?select=id,sender_id,text,is_read&id=eq.$mid',
          BH,
        ),
      );
      await req('DELETE', '$url/rest/v1/chat_messages?id=eq.$mid', SVC);
    }
  }

  // ---------- 3. WALLET GRANTS ----------
  Future<void> tryRpc(String label, Map<String, String> hdr, String name, Object args) async {
    rec(label, await req('POST', '$url/rest/v1/rpc/$name', hdr, args));
  }

  final debitArgs = {
    'p_wallet_id': buyerId,
    'p_order_id': oid,
    'p_amount': 0.01,
    'p_description': 'x',
  };
  final creditArgs = {
    'p_wallet_id': sellerId,
    'p_order_id': oid,
    'p_amount': 0.01,
    'p_type': 'venda',
    'p_description': 'x',
  };
  for (final who in [
    ['anon', AH],
    ['buyer', BH],
    ['seller', SH],
    ['none', NONE],
  ]) {
    final tag = who[0] as String;
    final hdr = who[1] as Map<String, String>;
    await tryRpc('rpc_debit_$tag', hdr, 'batata_debit_wallet_once', debitArgs);
    await tryRpc('rpc_clawback_$tag', hdr, 'batata_clawback_seller_wallet_for_order', {
      'p_order_id': oid,
    });
    await tryRpc('rpc_credit_$tag', hdr, 'batata_credit_wallet_once', creditArgs);
    await tryRpc('rpc_ensure_$tag', hdr, 'batata_ensure_wallet', {'p_wallet_id': sellerId});
    await tryRpc('rpc_ensure_legacy_$tag', hdr, 'ensure_wallet', {'p_wallet_id': sellerId});
    await tryRpc('rpc_credit_legacy_$tag', hdr, 'credit_wallet_once', creditArgs);
    await tryRpc('rpc_release_$tag', hdr, 'batata_release_seller_wallet_for_order', {
      'p_order_id': oid,
    });
    await tryRpc('rpc_refundw_$tag', hdr, 'batata_refund_buyer_wallet_for_order', {
      'p_order_id': oid,
    });
    await tryRpc('rpc_partial_$tag', hdr, 'batata_process_partial_refund_dispute', {
      'p_order_id': oid,
      'p_percent': 50,
    });
  }
  rec(
    'grant_assert',
    await req('POST', '$url/rest/v1/rpc/batata_assert_wallet_rpc_grants', SVC, {}),
  );
  rec(
    'wallets_after_rpc',
    await req(
      'GET',
      '$url/rest/v1/wallets?select=id,balance&id=in.($buyerId,$sellerId)',
      SVC,
    ),
  );

  final oa = await req(
    'GET',
    '$url/rest/v1/?',
    {...AH, 'Accept': 'application/openapi+json'},
  );
  if (oa['body'] is Map) {
    final paths = (oa['body'] as Map)['paths'];
    final names = <String>[];
    if (paths is Map) {
      for (final k in paths.keys) {
        final s = k.toString().toLowerCase();
        if (s.contains('wallet') ||
            s.contains('debit') ||
            s.contains('credit') ||
            s.contains('clawback') ||
            s.contains('payout') ||
            s.contains('ensure_wallet')) {
          names.add(k.toString());
        }
      }
    }
    rec('openapi_wallet_paths', names);
  } else {
    rec('openapi_wallet_paths', {'status': oa['status']});
  }

  // ---------- 4. SHIPPING ----------
  final shipOrd = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': victimPid,
    'quantity': 1,
    'price_total': 6.66,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
  });
  final soid = rowId(shipOrd['body']);
  rec('ship_order', {'status': shipOrd['status'], 'id': soid});
  Future<Map<String, dynamic>> cpi(Map<String, dynamic> extra) async {
    final body = <String, dynamic>{
      'buyer_id': buyerId,
      'order_id': soid,
      ...extra,
    };
    final r = await req('POST', '$url/functions/v1/create-payment-intent', BH, body);
    final b = r['body'];
    return {
      'status': r['status'],
      'amount': b is Map ? b['server_amount_cents'] : null,
      'err': b is Map ? (b['error'] ?? b['message']) : null,
    };
  }

  rec('ship_hand', await cpi({'shipping_method': 'hand'}));
  rec('ship_HAND', await cpi({'shipping_method': 'HAND'}));
  rec('ship_mao', await cpi({'shipping_method': 'mao'}));
  rec('ship_mao_accent', await cpi({'shipping_method': 'mão'}));
  rec('ship_spaces', await cpi({'shipping_method': '  hand  '}));
  rec('ship_carrier', await cpi({'shipping_method': 'carrier'}));
  rec('ship_transportadora', await cpi({'shipping_method': 'transportadora'}));
  rec('ship_label_hand', await cpi({'shipping_method': 'Entrega em mão (€0.00)'}));
  rec('ship_label_car', await cpi({'shipping_method': 'Envio Transportadora (€3.50)'}));
  rec('ship_euro0', await cpi({'shipping_method': '€0'}));
  rec('ship_0', await cpi({'shipping_method': '0'}));
  rec('ship_gratis', await cpi({'shipping_method': 'gratis'}));
  rec('ship_empty', await cpi({'shipping_method': ''}));
  rec('ship_missing', await cpi({}));
  rec('ship_null', await cpi({'shipping_method': null}));
  rec('ship_garbage', await cpi({'shipping_method': 'free_shipping_please'}));
  rec('ship_garbage_0', await cpi({'shipping_method': 'whatever', 'shipping': 0}));
  rec('ship_garbage_350', await cpi({'shipping_method': 'whatever', 'shipping': 350}));
  rec('ship_hand_350', await cpi({'shipping_method': 'hand', 'shipping': 350}));
  rec('ship_carrier_0', await cpi({'shipping_method': 'carrier', 'shipping': 0}));
  rec('ship_mix', await cpi({'shipping_method': 'CTT envio mao'}));
  rec('ship_nbsp', await cpi({'shipping_method': 'hand\u00a0'}));
  rec('ship_array', await cpi({'shipping_method': ['hand']}));
  rec('ship_obj', await cpi({'shipping_method': {'v': 'hand'}}));
  rec('ship_underpay_amount', await cpi({'shipping_method': 'hand', 'amount': 50}));
  rec('ship_unicode_homoglyph', await cpi({'shipping_method': 'hаnd'})); // cyrillic a

  // ---------- 5. BAG ----------
  final prices = [1.11, 2.22, 3.33];
  final pids = <String>[];
  final oids = <String>[];
  final stamp = DateTime.now().millisecondsSinceEpoch;
  for (var i = 0; i < 3; i++) {
    final p = await req('POST', '$url/rest/v1/products', SH, {
      'seller_id': sellerId,
      'title': 'INDEP27 bag ${i + 1} $stamp',
      'price': prices[i],
      'quantity': 4,
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
    });
    final pid = rowId(p['body']);
    if (pid == null) continue;
    pids.add(pid);
    final o = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': prices[i],
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    });
    final id = rowId(o['body']);
    if (id != null) oids.add(id);
  }
  rec('bag3_ids', {'products': pids, 'orders': oids});
  if (oids.length == 3) {
    final lines = [
      for (var i = 0; i < 3; i++) {'order_id': oids[i], 'product_id': pids[i]},
    ];
    rec(
      'bag3_cpi',
      await req('POST', '$url/functions/v1/create-payment-intent', BH, {
        'buyer_id': buyerId,
        'order_id': oids.first,
        'bag_checkout': true,
        'bag_lines': lines,
        'shipping_method': 'hand',
      }),
    );
    rec(
      'bag3_totals',
      await req(
        'GET',
        '$url/rest/v1/orders?select=id,price_total,amount_paid_cents,status&id=in.(${oids.join(',')})',
        BH,
      ),
    );
    rec(
      'bag3_cpi_reversed',
      await req('POST', '$url/functions/v1/create-payment-intent', BH, {
        'buyer_id': buyerId,
        'order_id': oids.last,
        'bag_checkout': true,
        'bag_lines': lines.reversed.toList(),
        'shipping_method': 'hand',
      }),
    );
    rec(
      'bag3_totals_rev',
      await req(
        'GET',
        '$url/rest/v1/orders?select=id,price_total,amount_paid_cents,status&id=in.(${oids.join(',')})',
        BH,
      ),
    );
    rec(
      'bag3_patch_price',
      await req('PATCH', '$url/rest/v1/orders?id=eq.${oids[0]}', BH, {
        'price_total': 0.01,
      }),
    );
    rec(
      'bag3_after_price_patch',
      await req(
        'GET',
        '$url/rest/v1/orders?select=id,price_total&id=eq.${oids[0]}',
        BH,
      ),
    );
  }

  final e2eHdr = {
    ...SVC,
    if (e2e.length >= 16) 'x-fleaber-e2e-secret': e2e,
  };
  rec(
    'bag2_paid',
    await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', e2eHdr, {
      'probe': 'setup_paid_bag',
      'buyer_id': buyerId,
      'seller_id': sellerId,
    }),
  );

  // ---------- 6. HARNESS / forged JWT ----------
  rec(
    'nuke_jwt',
    await req('POST', '$url/functions/v1/delete-test-account', BH, {
      'confirm': 'APAGAR TUDO',
    }),
  );
  rec(
    'nuke_none',
    await req('POST', '$url/functions/v1/delete-test-account', NONE, {
      'confirm': 'APAGAR TUDO',
    }),
  );
  rec(
    'e2e_jwt',
    await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', BH, {
      'probe': 'setup_paid_bag',
      'buyer_id': buyerId,
      'seller_id': sellerId,
    }),
  );
  rec(
    'e2e_none',
    await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', NONE, {
      'probe': 'setup_paid_bag',
    }),
  );
  rec(
    'settle_jwt',
    await req(
      'POST',
      '$url/functions/v1/create-payment-intent?fase2_e2e_settle=1',
      BH,
      {'order_id': oid, 'payment_intent_id': 'pi_fake'},
    ),
  );
  rec(
    'settle_none',
    await req(
      'POST',
      '$url/functions/v1/create-payment-intent?fase2_e2e_settle=1',
      NONE,
      {'order_id': oid, 'payment_intent_id': 'pi_fake'},
    ),
  );
  rec(
    'crash_jwt',
    await req('POST', '$url/functions/v1/refund-order', SH, {
      'order_id': oid,
      'crash_inject': 'after_stripe_before_db',
    }),
  );

  // ---------- 7. QTY ----------
  Map<String, dynamic>? li;
  if (liveItem['body'] is List && (liveItem['body'] as List).isNotEmpty) {
    li = Map<String, dynamic>.from((liveItem['body'] as List).first as Map);
  }
  if (li != null) {
    Future<Map<String, dynamic>> insQty(Object? qty, {bool omit = false}) {
      final row = <String, dynamic>{
        'live_id': li!['live_id'],
        'live_item_id': li['id'],
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'source': 'fleaber_live',
        'status': 'pending',
      };
      if (!omit) row['requested_qty'] = qty;
      return req('POST', '$url/rest/v1/live_reservation_requests', BH, row);
    }

    rec('qty_0', await insQty(0));
    rec('qty_neg', await insQty(-1));
    rec('qty_1', await insQty(1));
    rec('qty_99', await insQty(99));
    rec('qty_100', await insQty(100));
    rec('qty_9999', await insQty(9999));
    rec('qty_null', await insQty(null));
    rec('qty_omit', await insQty(null, omit: true));
    rec('qty_str', await insQty('abc'));
    rec('qty_dec', await insQty(1.7));
    final ok1 = rowId((out['qty_1'] as Map)['body']);
    if (ok1 != null) {
      rec(
        'qty_update_100',
        await req(
          'PATCH',
          '$url/rest/v1/live_reservation_requests?id=eq.$ok1',
          BH,
          {'requested_qty': 100},
        ),
      );
      rec(
        'qty_update_0',
        await req(
          'PATCH',
          '$url/rest/v1/live_reservation_requests?id=eq.$ok1',
          BH,
          {'requested_qty': 0},
        ),
      );
      rec(
        'qty_update_50_seller',
        await req(
          'PATCH',
          '$url/rest/v1/live_reservation_requests?id=eq.$ok1',
          SH,
          {'requested_qty': 50},
        ),
      );
    }
    rec(
      'qty_rpc_bag',
      await req('POST', '$url/rest/v1/rpc/batata_live_bag_update_qty', BH, {
        'p_request_id': ok1,
        'p_qty': 0,
      }),
    );
  }

  // ---------- 8. STREAM KEY ----------
  rec(
    'mux_anon',
    await req('POST', '$url/functions/v1/livekit-mux-publish', AH, {
      'step': 'egress',
      'live_id': oid,
      'stream_key': 'injected',
    }),
  );
  rec(
    'mux_buyer_fake',
    await req('POST', '$url/functions/v1/livekit-mux-publish', BH, {
      'step': 'egress',
      'live_id': oid,
      'stream_key': 'injected',
    }),
  );
  final lives = await req(
    'GET',
    '$url/rest/v1/lives?select=id,seller_id,status&seller_id=eq.$sellerId&limit=2',
    SH,
  );
  rec('lives_n', {'status': lives['status'], 'n': lives['body'] is List ? (lives['body'] as List).length : 0});
  String? liveId;
  if (lives['body'] is List && (lives['body'] as List).isNotEmpty) {
    liveId = Map<String, dynamic>.from((lives['body'] as List).first as Map)['id']?.toString();
  }
  if (liveId != null) {
    rec(
      'mux_seller_inject',
      await req('POST', '$url/functions/v1/livekit-mux-publish', SH, {
        'step': 'egress',
        'live_id': liveId,
        'stream_key': 'injected_by_owner',
      }),
    );
    rec(
      'mux_buyer_on_seller',
      await req('POST', '$url/functions/v1/livekit-mux-publish', BH, {
        'step': 'egress',
        'live_id': liveId,
        'stream_key': 'injected',
      }),
    );
  }

  // ---------- 10. P0 wallet mint / collusion ----------
  rec(
    'p0_release_twice',
    await req('POST', '$url/rest/v1/rpc/batata_release_seller_wallet_for_order', SH, {
      'p_order_id': oid,
    }),
  );
  rec(
    'p0_refund_wallet',
    await req('POST', '$url/rest/v1/rpc/batata_refund_buyer_wallet_for_order', BH, {
      'p_order_id': oid,
    }),
  );
  rec(
    'p0_wallet_insert',
    await req('POST', '$url/rest/v1/wallets', BH, {
      'id': buyerId,
      'balance': 9999,
    }),
  );
  rec(
    'p0_wallet_patch',
    await req('PATCH', '$url/rest/v1/wallets?id=eq.$buyerId', BH, {
      'balance': 9999,
    }),
  );
  rec(
    'p0_tx_insert',
    await req('POST', '$url/rest/v1/wallet_transactions', BH, {
      'wallet_id': buyerId,
      'amount': 50,
      'type': 'venda',
      'description': 'x',
      'order_id': oid,
    }),
  );

  rec(
    'wallets_final',
    await req(
      'GET',
      '$url/rest/v1/wallets?select=id,balance&id=in.($buyerId,$sellerId)',
      SVC,
    ),
  );

  // cleanup bag2
  final bag2 = out['bag2_paid'];
  if (bag2 is Map && bag2['body'] is Map) {
    final b = bag2['body'] as Map;
    rec(
      'bag2_refund_a',
      await req('POST', '$url/functions/v1/refund-order', SH, {
        'order_id': b['order_a_id'],
      }),
    );
    rec(
      'bag2_orders_after_refund',
      await req(
        'GET',
        '$url/rest/v1/orders?select=id,status,amount_paid_cents,stripe_refund_id,price_total&id=in.(${b['order_a_id']},${b['order_b_id']})',
        SVC,
      ),
    );
    rec(
      'bag2_refund_b',
      await req('POST', '$url/functions/v1/refund-order', SH, {
        'order_id': b['order_b_id'],
      }),
    );
    rec(
      'bag2_orders_after_refund_b',
      await req(
        'GET',
        '$url/rest/v1/orders?select=id,status,amount_paid_cents,stripe_refund_id&id=in.(${b['order_a_id']},${b['order_b_id']})',
        SVC,
      ),
    );
    rec(
      'bag2_cleanup',
      await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', e2eHdr, {
        'probe': 'cleanup_bag_fixture',
        'product_a_id': b['product_a_id'],
        'product_b_id': b['product_b_id'],
      }),
    );
  }

  await req(
    'DELETE',
    '$url/rest/v1/live_reservation_requests?buyer_id=eq.$buyerId&source=eq.fleaber_live&status=eq.pending',
    SVC,
  );
  if (victimPid != null) {
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$victimPid', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$victimPid', SVC);
  }
  for (final id in pids) {
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$id', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$id', SVC);
  }

  rec('third_qty_end', {
    'pid': thirdPid,
    'seller': thirdSeller,
    'qty_start': thirdQty,
  });

  final path = 'tool/reports/REAUDITORIA_INDEP_NOVA_CEGA_2026_08_27_PROBES.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('WROTE $path keys=${out.length}');
}
