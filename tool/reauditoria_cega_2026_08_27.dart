// ignore_for_file: avoid_print
/// Reauditoria independente — findings da cega 2026-08-27.
/// Não usa JSON/PASS do C1. JWT buyer/seller. service_role = limpeza/inspect.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

final out = <String, dynamic>{};
void rec(String id, Object? v) {
  out[id] = v;
  final s = jsonEncode(v);
  print('$id: ${s.length > 280 ? s.substring(0, 280) : s}');
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
  final b = body == null
      ? null
      : (body is String ? body : jsonEncode(body));
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
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: só staging');
    exit(2);
  }
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
  final BH = hUser(anon, buyerJwt);
  final SH = hUser(anon, sellerJwt);
  final AH = hAnon(anon);
  final SVC = hSvc(svc);

  rec('meta', {
    'at': DateTime.now().toUtc().toIso8601String(),
    'staging': 'fxdknzrqjenzqcvnwqqq',
    'production_touched': false,
  });

  // ========== P1-01 stock mismatch ==========
  final prod = await req('POST', '$url/rest/v1/products', SH, {
    'seller_id': sellerId,
    'title': 'REAUDIT27 stock probe',
    'price': 6.66,
    'quantity': 5,
    'list_on_marketplace': false,
    'available_for_live': false,
    'is_sold': false,
    'description': 'REAUDIT27',
  });
  rec('p101_seller_product', {'status': prod['status'], 'id': rowId(prod['body'])});
  final prodId = rowId(prod['body']);
  if (prodId == null) {
    rec('p101_abort', prod);
  } else {
    final mismatchIns = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': buyerId,
      'product_id': prodId,
      'quantity': 2,
      'price_total': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    });
    rec('p101_insert_mismatch', {
      'status': mismatchIns['status'],
      'body': mismatchIns['body'],
    });
    final mismatchId = rowId(mismatchIns['body']);
    if (mismatchId != null) {
      final pago = await req(
        'PATCH',
        '$url/rest/v1/orders?id=eq.$mismatchId',
        BH,
        {'status': 'pago'},
      );
      rec('p101_mismatch_pago', {
        'status': pago['status'],
        'order': rowMap(pago['body']),
      });
    }
    final qty1 = await req(
      'GET',
      '$url/rest/v1/products?select=id,quantity,is_sold,seller_id&id=eq.$prodId',
      SH,
    );
    rec('p101_qty_after_mismatch', qty1['body']);

    // legitimate order then try to retarget product_id / seller_id
    final legit = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': prodId,
      'quantity': 1,
      'price_total': 6.66,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    });
    rec('p101_legit_insert', {
      'status': legit['status'],
      'order': rowMap(legit['body']),
    });
    final legitId = rowId(legit['body']);
    if (legitId != null) {
      rec(
        'p101_patch_product_id_other',
        await req('PATCH', '$url/rest/v1/orders?id=eq.$legitId', BH, {
          'product_id': '00000000-0000-0000-0000-000000000001',
        }),
      );
      rec(
        'p101_patch_seller_id_self',
        await req('PATCH', '$url/rest/v1/orders?id=eq.$legitId', BH, {
          'seller_id': buyerId,
        }),
      );
      rec(
        'p101_seller_pago_legit',
        await req('PATCH', '$url/rest/v1/orders?id=eq.$legitId', SH, {
          'status': 'pago',
        }),
      );
    }
    rec(
      'p101_qty_after_legit_pago',
      (await req(
        'GET',
        '$url/rest/v1/products?select=id,quantity,is_sold&id=eq.$prodId',
        SH,
      ))['body'],
    );
  }

  // ========== P2-07 MB WAY mint ==========
  final bwBefore = await req(
    'GET',
    '$url/rest/v1/wallets?select=id,balance&id=eq.$buyerId',
    BH,
  );
  final swBefore = await req(
    'GET',
    '$url/rest/v1/wallets?select=id,balance&id=eq.$sellerId',
    SH,
  );
  rec('p207_wallets_before', {
    'buyer': rowMap(bwBefore['body']),
    'seller': rowMap(swBefore['body']),
  });
  if (prodId != null) {
    final mb = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': prodId,
      'quantity': 1,
      'price_total': 6.66,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    });
    rec('p207_mb_insert', {'status': mb['status'], 'order': rowMap(mb['body'])});
    final mbId = rowId(mb['body']);
    if (mbId != null) {
      rec(
        'p207_seller_pago',
        await req('PATCH', '$url/rest/v1/orders?id=eq.$mbId', SH, {
          'status': 'pago',
        }),
      );
      rec(
        'p207_buyer_concluido',
        await req('PATCH', '$url/rest/v1/orders?id=eq.$mbId', BH, {
          'status': 'concluido',
        }),
      );
      rec(
        'p207_release',
        await req('POST', '$url/rest/v1/rpc/batata_release_seller_wallet_for_order', BH, {
          'p_order_id': mbId,
        }),
      );
      rec(
        'p207_refund_rpc',
        await req('POST', '$url/rest/v1/rpc/batata_refund_buyer_wallet_for_order', BH, {
          'p_order_id': mbId,
        }),
      );
    }
  }
  rec('p207_wallets_after', {
    'buyer': rowMap((await req(
      'GET',
      '$url/rest/v1/wallets?select=id,balance&id=eq.$buyerId',
      BH,
    ))['body']),
    'seller': rowMap((await req(
      'GET',
      '$url/rest/v1/wallets?select=id,balance&id=eq.$sellerId',
      SH,
    ))['body']),
  });

  // ========== P1-02 chat parties ==========
  final chats = await req(
    'GET',
    '$url/rest/v1/chats?select=id,user_a,user_b&limit=5',
    BH,
  );
  rec('p102_chats', chats['body']);
  String? chatId;
  if (chats['body'] is List && (chats['body'] as List).isNotEmpty) {
    final first = Map<String, dynamic>.from((chats['body'] as List).first as Map);
    chatId = first['id']?.toString();
    final origA = first['user_a']?.toString();
    final origB = first['user_b']?.toString();
    rec('p102_original', {'id': chatId, 'user_a': origA, 'user_b': origB});
    if (chatId != null) {
      rec(
        'p102_buyer_swap_b',
        await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
          'user_b': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        }),
      );
      rec(
        'p102_after_buyer_swap',
        (await req(
          'GET',
          '$url/rest/v1/chats?select=id,user_a,user_b&id=eq.$chatId',
          BH,
        ))['body'],
      );
      rec(
        'p102_seller_swap_a',
        await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', SH, {
          'user_a': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        }),
      );
      rec(
        'p102_buyer_takeover_both',
        await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
          'user_a': buyerId,
          'user_b': buyerId,
        }),
      );
      rec(
        'p102_legit_last_message',
        await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
          'last_message': 'REAUDIT27 ping',
        }),
      );
      rec(
        'p102_after_all',
        (await req(
          'GET',
          '$url/rest/v1/chats?select=id,user_a,user_b,last_message&id=eq.$chatId',
          BH,
        ))['body'],
      );
      final msgs = await req(
        'GET',
        '$url/rest/v1/chat_messages?select=id,sender_id,text,is_read&chat_id=eq.$chatId&limit=5',
        BH,
      );
      rec('p102_msgs', {'status': msgs['status'], 'n': msgs['body'] is List ? (msgs['body'] as List).length : 0});
      if (msgs['body'] is List && (msgs['body'] as List).isNotEmpty) {
        final m = Map<String, dynamic>.from((msgs['body'] as List).first as Map);
        final mid = m['id']?.toString();
        final sid = m['sender_id']?.toString();
        if (mid != null) {
          rec(
            'p102_spoof_sender',
            await req('PATCH', '$url/rest/v1/chat_messages?id=eq.$mid', BH, {
              'sender_id': sellerId,
              'text': 'REAUDIT27 spoof',
            }),
          );
          rec(
            'p102_mark_read',
            await req('PATCH', '$url/rest/v1/chat_messages?id=eq.$mid', BH, {
              'is_read': true,
            }),
          );
          rec(
            'p102_msg_after',
            (await req(
              'GET',
              '$url/rest/v1/chat_messages?select=id,sender_id,text,is_read&id=eq.$mid',
              BH,
            ))['body'],
          );
        }
        rec('p102_other_sender', sid);
      }
      rec(
        'p102_insert_spoof_sender',
        await req('POST', '$url/rest/v1/chat_messages', BH, {
          'chat_id': chatId,
          'sender_id': sellerId,
          'text': 'REAUDIT27 insert spoof',
        }),
      );
      // restore parties if drifted
      await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', SVC, {
        'user_a': origA,
        'user_b': origB,
      });
    }
  }

  // ========== P1-03 / P2-01 / P2-02 GRANTs ==========
  final oid = '00000000-0000-0000-0000-000000000099';
  for (final who in ['anon', 'buyer', 'seller']) {
    final hdr = who == 'anon' ? AH : (who == 'buyer' ? BH : SH);
    rec(
      'grant_debit_$who',
      await req('POST', '$url/rest/v1/rpc/batata_debit_wallet_once', hdr, {
        'p_wallet_id': who == 'seller' ? sellerId : buyerId,
        'p_order_id': oid,
        'p_amount': 0.01,
        'p_description': 'REAUDIT27',
      }),
    );
    rec(
      'grant_clawback_$who',
      await req('POST', '$url/rest/v1/rpc/batata_clawback_seller_wallet_for_order', hdr, {
        'p_order_id': oid,
      }),
    );
    rec(
      'grant_credit_$who',
      await req('POST', '$url/rest/v1/rpc/batata_credit_wallet_once', hdr, {
        'p_wallet_id': buyerId,
        'p_order_id': oid,
        'p_amount': 1,
        'p_type': 'venda',
        'p_description': 'REAUDIT27',
      }),
    );
    rec(
      'grant_ensure_$who',
      await req('POST', '$url/rest/v1/rpc/batata_ensure_wallet', hdr, {
        'p_user_id': who == 'anon' ? buyerId : (who == 'buyer' ? sellerId : buyerId),
      }),
    );
  }
  rec('p201_wallets_after_grant', {
    'buyer': rowMap((await req(
      'GET',
      '$url/rest/v1/wallets?select=id,balance&id=eq.$buyerId',
      BH,
    ))['body']),
    'seller': rowMap((await req(
      'GET',
      '$url/rest/v1/wallets?select=id,balance&id=eq.$sellerId',
      SH,
    ))['body']),
  });

  // ========== P2-03 shipping ==========
  if (prodId != null) {
    final shipOrder = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': prodId,
      'quantity': 1,
      'price_total': 6.66,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    });
    final soid = rowId(shipOrder['body']);
    rec('p203_order', {'status': shipOrder['status'], 'id': soid});
    if (soid != null) {
      Future<Map<String, dynamic>> cpi(String method) => req(
            'POST',
            '$url/functions/v1/create-payment-intent',
            BH,
            {
              'buyer_id': buyerId,
              'order_id': soid,
              'shipping_method': method,
              'amount': 50,
            },
          );
      rec('p203_hand', await cpi('hand'));
      rec('p203_carrier', await cpi('carrier'));
      rec('p203_transportadora', await cpi('transportadora'));
      rec('p203_euro0', await cpi('Transportadora 3.50 EUR0'));
      rec('p203_euro0_symbol', await cpi('envio EUR 0'));
      rec('p203_carrier_euro0', await cpi('transportadora EUR0'));
      rec('p203_mao_hidden', await cpi('CTT envio mao'));
      rec('p203_garbage', await cpi('free_shipping_please'));
      rec('p203_empty', await cpi(''));
    }
  }

  // ========== P2-06 harnesses ==========
  rec(
    'p206_nuke',
    await req('POST', '$url/functions/v1/delete-test-account', BH, {
      'confirm': 'APAGAR TUDO',
    }),
  );
  rec(
    'p206_e2e_jwt',
    await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', BH, {
      'probe': 'setup_paid_bag',
      'buyer_id': buyerId,
      'seller_id': sellerId,
    }),
  );
  rec(
    'p206_e2e_settle_jwt',
    await req('POST', '$url/functions/v1/create-payment-intent?fase2_e2e_settle=1', BH, {
      'order_id': oid,
      'payment_intent_id': 'pi_fake',
    }),
  );
  rec(
    'p206_refund_crash_no_secret',
    await req('POST', '$url/functions/v1/refund-order', SH, {
      'order_id': oid,
      'crash_inject': 'after_stripe_before_db',
    }),
  );

  // ========== P3-02 stream_key ==========
  rec(
    'p302_buyer_egress',
    await req('POST', '$url/functions/v1/livekit-mux-publish', BH, {
      'step': 'egress',
      'live_id': oid,
      'stream_key': 'injected_fake_key',
    }),
  );
  final lives = await req(
    'GET',
    '$url/rest/v1/lives?select=id,status,seller_id&seller_id=eq.$sellerId&limit=3',
    SH,
  );
  rec('p302_seller_lives', {'status': lives['status'], 'n': lives['body'] is List ? (lives['body'] as List).length : 0});
  String? liveId;
  if (lives['body'] is List && (lives['body'] as List).isNotEmpty) {
    liveId = Map<String, dynamic>.from((lives['body'] as List).first as Map)['id']?.toString();
  }
  if (liveId != null) {
    rec(
      'p302_seller_inject',
      await req('POST', '$url/functions/v1/livekit-mux-publish', SH, {
        'step': 'egress',
        'live_id': liveId,
        'stream_key': 'injected_fake_key_by_owner',
      }),
    );
    rec(
      'p302_buyer_on_seller_live',
      await req('POST', '$url/functions/v1/livekit-mux-publish', BH, {
        'step': 'egress',
        'live_id': liveId,
        'stream_key': 'injected_fake_key',
      }),
    );
  }

  // ========== P2-08 requested_qty ==========
  final items = await req(
    'GET',
    '$url/rest/v1/live_items?select=id,live_id,seller_id,quantity&limit=5',
    SH,
  );
  rec('p208_live_items_status', items['status']);
  Map<String, dynamic>? item;
  if (items['body'] is List && (items['body'] as List).isNotEmpty) {
    item = Map<String, dynamic>.from((items['body'] as List).first as Map);
  }
  if (item != null) {
    final li = item['id']?.toString();
    final lid = item['live_id']?.toString();
    Future<Map<String, dynamic>> insQty(Object? qty, {bool omit = false}) {
      final row = <String, dynamic>{
        'live_id': lid,
        'live_item_id': li,
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'source': 'fleaber_live',
        'status': 'pending',
      };
      if (!omit) row['requested_qty'] = qty;
      return req('POST', '$url/rest/v1/live_reservation_requests', BH, row);
    }

    rec('p208_qty_0', await insQty(0));
    rec('p208_qty_neg', await insQty(-1));
    rec('p208_qty_1', await insQty(1));
    rec('p208_qty_99', await insQty(99));
    rec('p208_qty_100', await insQty(100));
    rec('p208_qty_null', await insQty(null));
    rec('p208_qty_omit', await insQty(null, omit: true));
    rec('p208_qty_string', await insQty('abc'));
    rec('p208_bag_rpc_100', await req('POST', '$url/rest/v1/rpc/batata_live_bag_update_qty', BH, {
      'p_request_id': oid,
      'p_qty': 100,
    }));
    rec('p208_bag_rpc_0', await req('POST', '$url/rest/v1/rpc/batata_live_bag_update_qty', BH, {
      'p_request_id': oid,
      'p_qty': 0,
    }));
  } else {
    rec('p208_skip', 'no live_item visible to seller JWT');
  }

  // ========== P2-04 bag: JWT 3 lines + CPI quote; Stripe pay if key ==========
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final prices = [1.11, 2.22, 3.33];
  final pids = <String>[];
  final oids = <String>[];
  for (var i = 0; i < prices.length; i++) {
    final p = await req('POST', '$url/rest/v1/products', SH, {
      'seller_id': sellerId,
      'title': 'REAUDIT27 bag ${i + 1} $stamp',
      'price': prices[i],
      'quantity': 4,
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'description': 'REAUDIT27 bag',
    });
    final id = rowId(p['body']);
    rec('p204_prod_$i', {'status': p['status'], 'id': id, 'price': prices[i]});
    if (id == null) continue;
    pids.add(id);
    final o = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': id,
      'quantity': 1,
      'price_total': prices[i],
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    });
    final oidB = rowId(o['body']);
    rec('p204_order_$i', {'status': o['status'], 'id': oidB});
    if (oidB != null) oids.add(oidB);
  }
  if (oids.length == 3) {
    final bagLines = [
      for (var i = 0; i < oids.length; i++)
        {'order_id': oids[i], 'product_id': pids[i], 'line_total_cents': 1},
    ];
    final cpiBag = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oids.first,
      'bag_checkout': true,
      'bag_lines': bagLines,
      'shipping_method': 'hand',
      'amount': 1,
    });
    rec('p204_cpi_bag', {
      'status': cpiBag['status'],
      'body': cpiBag['body'],
    });
    final afterCpi = <Map<String, dynamic>>[];
    for (final id in oids) {
      final r = await req(
        'GET',
        '$url/rest/v1/orders?select=id,status,price_total,amount_paid_cents&id=eq.$id',
        BH,
      );
      afterCpi.add(rowMap(r['body']) ?? {});
    }
    rec('p204_orders_after_cpi', afterCpi);

    // retry CPI (idempotent session?)
    final cpiBag2 = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oids.first,
      'bag_checkout': true,
      'bag_lines': bagLines,
      'shipping_method': 'hand',
      'amount': 1,
    });
    rec('p204_cpi_retry', {'status': cpiBag2['status']});

    final stripeKey = (Platform.environment['STRIPE_SECRET_KEY'] ?? '').trim();
    rec('p204_has_stripe_env', stripeKey.startsWith('sk_test_'));
    if (stripeKey.startsWith('sk_test_') && cpiBag['ok'] == true) {
      // Pay via PaymentIntent independently, then e2e bag settle.
      final itemsC = afterCpi
          .map((o) => ((o['price_total'] as num?) ?? 0) * 100)
          .fold<int>(0, (a, b) => a + b.round());
      rec('p204_sum_price_total_cents', itemsC);
    }

    // Independent bag settle via existing e2e endpoint with OUR order ids
    // requires a succeeded PI — created only if we have stripe test key on Edge
    // (fase2_e2e_settle). We create PI by paying oversell setup? Skip hardcoded 3+7.
  }

  // Independent 3-line bag using Edge settle + PI created on Edge via
  // create-payment-intent is unpaid. Use Stripe TEST PI through e2e oversell
  // setup_paid_order three times? That would be 3 PIs not one bag.
  // Create one PI using fase2 path: call oversell with custom? can't.
  // Use JWT CPI session_id GET settle unpaid:
  if (cpiSessionId(cpiBody: cpiBagBody(out['p204_cpi_bag'])) != null) {
    final sid = cpiSessionId(cpiBody: cpiBagBody(out['p204_cpi_bag']))!;
    rec(
      'p204_settle_unpaid',
      await req(
        'GET',
        '$url/functions/v1/create-payment-intent?checkout_return=success&session_id=$sid',
        AH,
      ),
    );
  }

  // Cleanup reservations created
  await req(
    'DELETE',
    '$url/rest/v1/live_reservation_requests?buyer_id=eq.$buyerId&source=eq.fleaber_live&status=eq.pending',
    SVC,
  );
  if (prodId != null) {
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$prodId', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$prodId', SVC);
  }
  for (final id in pids) {
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$id', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$id', SVC);
  }

  final path = 'tool/reports/REAUDITORIA_CEGA_2026_08_27_PROBES.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('WROTE $path keys=${out.length}');
}

Map<String, dynamic>? cpiBagBody(Object? recVal) {
  if (recVal is Map && recVal['body'] is Map) {
    return Map<String, dynamic>.from(recVal['body'] as Map);
  }
  return null;
}

String? cpiSessionId({Map<String, dynamic>? cpiBody}) {
  if (cpiBody == null) return null;
  for (final k in ['session_id', 'sessionId', 'id']) {
    final v = cpiBody[k]?.toString();
    if (v != null && v.startsWith('cs_')) return v;
  }
  final url = (cpiBody['url'] ?? cpiBody['checkout_url'] ?? '').toString();
  final m = RegExp(r'cs_(test|live)_[A-Za-z0-9]+').firstMatch(url);
  return m?.group(0);
}
