// ignore_for_file: avoid_print
/// Follow-up: shipping exact €0, 3-line bag Stripe TEST settle, mark_read, qty vs stock.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

final out = <String, dynamic>{};
void rec(String id, Object? v) {
  out[id] = v;
  final s = jsonEncode(v);
  print('$id: ${s.length > 320 ? s.substring(0, 320) : s}');
}

Map<String, String> hUser(String anon, String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
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
  final SVC = hSvc(svc);

  // --- shipping exact euro0 ---
  final prod = await req('POST', '$url/rest/v1/products', SH, {
    'seller_id': sellerId,
    'title': 'REAUDIT27 ship2',
    'price': 6.66,
    'quantity': 8,
    'list_on_marketplace': false,
    'available_for_live': false,
    'is_sold': false,
  });
  final prodId = rowId(prod['body']);
  rec('ship2_prod', {'status': prod['status'], 'id': prodId});
  final ord = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': prodId,
    'quantity': 1,
    'price_total': 6.66,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
  });
  final oid = rowId(ord['body']);
  Future<Map<String, dynamic>> cpi(String method) async {
    final r = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oid,
      'shipping_method': method,
    });
    final body = r['body'];
    final amt = body is Map ? body['server_amount_cents'] : null;
    return {'status': r['status'], 'amount': amt, 'err': body is Map ? body['error'] : null};
  }

  rec('ship_exact_euro0', await cpi('\u20ac0'));
  rec('ship_exact_0', await cpi('0'));
  rec('ship_free', await cpi('gratis'));
  rec('ship_mao', await cpi('mao'));
  rec('ship_hand', await cpi('hand'));
  rec('ship_carrier', await cpi('carrier'));
  rec(
    'ship_garbage_plus_shipping0',
    await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oid,
      'shipping_method': 'free_shipping_please',
      'shipping': 0,
    }),
  );
  rec(
    'ship_empty_plus_shipping0',
    await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oid,
      'shipping_method': '',
      'shipping': 0,
    }),
  );
  rec(
    'ship_euro0_plus_shipping0',
    await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oid,
      'shipping_method': '\u20ac0',
      'shipping': 0,
    }),
  );

  rec(
    'grant_assert',
    await req('POST', '$url/rest/v1/rpc/batata_assert_wallet_rpc_grants', SVC, {}),
  );

  // --- mark_read ---
  final chats = await req('GET', '$url/rest/v1/chats?select=id&limit=1', BH);
  final chatId = rowId(chats['body']);
  if (chatId != null) {
    final ins = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'text': 'REAUDIT27 readme',
    });
    final mid = rowId(ins['body']);
    rec('msg_insert', {'status': ins['status'], 'id': mid, 'sender': rowMap(ins['body'])?['sender_id']});
    if (mid != null) {
      rec(
        'mark_read_seller',
        await req('PATCH', '$url/rest/v1/chat_messages?id=eq.$mid', SH, {
          'is_read': true,
        }),
      );
      rec(
        'msg_after_read',
        await req(
          'GET',
          '$url/rest/v1/chat_messages?select=id,sender_id,text,is_read&id=eq.$mid',
          BH,
        ),
      );
      await req('DELETE', '$url/rest/v1/chat_messages?id=eq.$mid', SVC);
    }
  }

  // --- qty 99 vs live_item stock ---
  final items = await req(
    'GET',
    '$url/rest/v1/live_items?select=id,live_id,quantity,seller_id&limit=3',
    SH,
  );
  rec('live_item_sample', items['body']);
  if (items['body'] is List && (items['body'] as List).isNotEmpty) {
    final it = Map<String, dynamic>.from((items['body'] as List).first as Map);
    rec('live_item_qty_vs_99', {
      'id': it['id'],
      'quantity': it['quantity'],
    });
    rec(
      'p208_qty99_vs_stock',
      await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
        'live_id': it['live_id'],
        'live_item_id': it['id'],
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'source': 'fleaber_live',
        'status': 'pending',
        'requested_qty': 99,
      }),
    );
  }

  rec(
    'order_qty_patch_0',
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {'quantity': 0}),
  );
  rec(
    'order_after_qty_patch',
    await req(
      'GET',
      '$url/rest/v1/orders?select=id,quantity&id=eq.$oid',
      BH,
    ),
  );

  // --- 3-line bag Stripe TEST via e2e settle (PI created on Edge, OUR jwt orders) ---
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final prices = [1.11, 2.22, 3.33];
  final pids = <String>[];
  final oids = <String>[];
  for (var i = 0; i < 3; i++) {
    final p = await req('POST', '$url/rest/v1/products', SH, {
      'seller_id': sellerId,
      'title': 'REAUDIT27 bag3 ${i + 1} $stamp',
      'price': prices[i],
      'quantity': 5,
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
  Map<String, String> e2eHdr() => {
        ...hSvc(svc),
        if (e2e.length >= 16) 'x-fleaber-e2e-secret': e2e,
      };

  rec(
    'bag2_setup_paid_bag',
    await req(
      'POST',
      '$url/functions/v1/sec-fase2-e2e-oversell',
      e2eHdr(),
      {
        'probe': 'setup_paid_bag',
        'buyer_id': buyerId,
        'seller_id': sellerId,
      },
    ),
  );
  if (oids.length == 3) {
    final bagLines = [
      for (var i = 0; i < 3; i++) {'order_id': oids[i], 'product_id': pids[i]},
    ];
    final cpiBag = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oids.first,
      'bag_checkout': true,
      'bag_lines': bagLines,
      'shipping_method': 'hand',
    });
    rec('bag3_cpi', {
      'status': cpiBag['status'],
      'amount': cpiBag['body'] is Map ? (cpiBag['body'] as Map)['server_amount_cents'] : null,
    });
    final pricesAfter = <Map<String, dynamic>>[];
    for (final id in oids) {
      final r = await req(
        'GET',
        '$url/rest/v1/orders?select=id,status,price_total,amount_paid_cents&id=eq.$id',
        BH,
      );
      pricesAfter.add(rowMap(r['body']) ?? {});
    }
    rec('bag3_price_totals', pricesAfter);

    // Create succeeded TEST PI via harness (prep only), then settle OUR 3 lines.
    final setup = await req(
      'POST',
      '$url/functions/v1/sec-fase2-e2e-oversell',
      e2eHdr(),
      {
        'probe': 'setup_paid_order',
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'initial_qty': 2,
      },
    );
    rec('bag3_setup_pi', {
      'status': setup['status'],
      'ok': setup['body'] is Map ? (setup['body'] as Map)['ok'] : null,
      'pi': setup['body'] is Map ? (setup['body'] as Map)['payment_intent_id'] : null,
      'pi_amount': setup['body'] is Map ? (setup['body'] as Map)['pi_amount_received'] : null,
      'setup_order': setup['body'] is Map ? (setup['body'] as Map)['order_id'] : null,
    });
    final piId = setup['body'] is Map
        ? (setup['body'] as Map)['payment_intent_id']?.toString()
        : null;
    if (piId != null && piId.startsWith('pi_')) {
      final settle1 = await req(
        'POST',
        '$url/functions/v1/create-payment-intent?fase2_e2e_settle=1',
        hSvc(svc),
        {
          'bag_checkout': true,
          'bag_lines': bagLines,
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'payment_intent_id': piId,
        },
      );
      rec('bag3_settle1', settle1);
      final settle2 = await req(
        'POST',
        '$url/functions/v1/create-payment-intent?fase2_e2e_settle=1',
        hSvc(svc),
        {
          'bag_checkout': true,
          'bag_lines': bagLines,
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'payment_intent_id': piId,
        },
      );
      rec('bag3_settle_retry', settle2);

      final after = <Map<String, dynamic>>[];
      for (final id in oids) {
        final r = await req(
          'GET',
          '$url/rest/v1/orders?select=id,status,price_total,amount_paid_cents,stock_units_applied&id=eq.$id',
          BH,
        );
        after.add(rowMap(r['body']) ?? {});
      }
      rec('bag3_orders_after_settle', after);
      final paid = after.map((o) => (o['amount_paid_cents'] as num?)?.toInt() ?? 0).toList();
      final sum = paid.fold<int>(0, (a, b) => a + b);
      final piAmt = (setup['body'] is Map
              ? (setup['body'] as Map)['pi_amount_received'] as num?
              : null)
          ?.toInt() ??
          0;
      rec('bag3_invariants', {
        'paid': paid,
        'sum': sum,
        'pi_amount': piAmt,
        'sum_eq_pi': sum == piAmt,
        'any_line_eq_full_pi': paid.any((x) => piAmt > 0 && x == piAmt),
        'all_pago': after.every((o) => (o['status']?.toString() ?? '') == 'pago'),
      });
      final setupOid = (out['bag3_setup_pi'] is Map)
          ? (out['bag3_setup_pi'] as Map)['setup_order']?.toString()
          : null;
      if (setupOid != null) {
        rec(
          'bag3_setup_order_after_reuse',
          await req(
            'GET',
            '$url/rest/v1/orders?select=id,status,amount_paid_cents,stripe_payment_intent_id&id=eq.$setupOid',
            SVC,
          ),
        );
      }

      // refund one line as seller JWT
      rec(
        'bag3_refund_line0',
        await req('POST', '$url/functions/v1/refund-order', SH, {
          'order_id': oids.first,
        }),
      );
      rec(
        'bag3_orders_after_refund',
        [
          for (final id in oids)
            rowMap((await req(
              'GET',
              '$url/rest/v1/orders?select=id,status,amount_paid_cents,stripe_refund_id&id=eq.$id',
              BH,
            ))['body'])
        ],
      );
    }
  }

  // cleanup
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
  final setupOid = (out['bag3_setup_pi'] is Map)
      ? (out['bag3_setup_pi'] as Map)['setup_order']?.toString()
      : null;
  if (setupOid != null && setupOid.isNotEmpty) {
    final so = await req(
      'GET',
      '$url/rest/v1/orders?select=product_id&id=eq.$setupOid',
      SVC,
    );
    final sp = rowMap(so['body'])?['product_id']?.toString();
    await req('DELETE', '$url/rest/v1/orders?id=eq.$setupOid', SVC);
    if (sp != null) await req('DELETE', '$url/rest/v1/products?id=eq.$sp', SVC);
  }

  final bag2 = out['bag2_setup_paid_bag'];
  if (bag2 is Map && bag2['body'] is Map) {
    final b = bag2['body'] as Map;
    rec(
      'bag2_cleanup',
      await req(
        'POST',
        '$url/functions/v1/sec-fase2-e2e-oversell',
        e2eHdr(),
        {
          'probe': 'cleanup_bag_fixture',
          'product_a_id': b['product_a_id'],
          'product_b_id': b['product_b_id'],
        },
      ),
    );
  }

  final path = 'tool/reports/REAUDITORIA_CEGA_2026_08_27_FOLLOWUP.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('WROTE $path');
}
