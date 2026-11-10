// ignore_for_file: avoid_print
/// C1 fecho RI-E PATCH accept + RI-B forge vendedor.
/// dart run tool/sec_c1_ri_e_ri_b_hostile.dart
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
      ? await http.post(Uri.parse(u), headers: h, body: jsonEncode(body))
      : method == 'PATCH'
          ? await http.patch(Uri.parse(u), headers: h, body: jsonEncode(body))
          : method == 'DELETE'
              ? await http.delete(Uri.parse(u), headers: h)
              : await http.get(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p};
}

Map<String, dynamic>? row(dynamic b) {
  if (b is List && b.isNotEmpty && b.first is Map) {
    return Map<String, dynamic>.from(b.first as Map);
  }
  return null;
}

num n(Object? v) => v is num ? v : num.tryParse('$v') ?? -1;

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
  void add(String id, bool ok, Object d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final products = <String>[];

  Future<Map<String, dynamic>> mkProduct({num price = 9, int qty = 5}) async {
    final p = await sb.insert('products', {
      'seller_id': sellerId,
      'title': 'C1RI $stamp $price',
      'price': price,
      'quantity': qty,
      'list_on_marketplace': false,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    products.add('${p['id']}');
    return p;
  }

  // ===== E: seller PATCH over capacity =====
  final lives = await sb.select('lives', filter: 'seller_id=eq.$sellerId', limit: 1);
  if (lives.isEmpty) {
    add('E_PATCH_OVER_BLOCKED', false, 'no live');
    add('E_PENDING_WAITLIST', false, 'no live');
    add('E_RPC_ACCEPT_1_OK', false, 'no live');
  } else {
    final liveId = '${lives.first['id']}';
    final items = await sb.select(
      'live_items',
      filter: 'live_id=eq.$liveId',
      limit: 1,
    );
    if (items.isEmpty) {
      add('E_PATCH_OVER_BLOCKED', false, 'no item');
      add('E_PENDING_WAITLIST', false, 'no item');
      add('E_RPC_ACCEPT_1_OK', false, 'no item');
    } else {
      final liId = '${items.first['id']}';
      if (items.first['product_id'] != null) {
        await req(
          'PATCH',
          '$url/rest/v1/products?id=eq.${items.first['product_id']}',
          SVC,
          {'quantity': 1},
        );
      }
      await req('PATCH', '$url/rest/v1/live_items?id=eq.$liId', SVC, {
        'quantity': 1,
        'status': 'available',
      });
      await req(
        'DELETE',
        '$url/rest/v1/live_reservation_requests?buyer_id=eq.$buyerId&live_item_id=eq.$liId&status=in.(pending,accepted)',
        SVC,
      );

      final pend = await req(
        'POST',
        '$url/rest/v1/live_reservation_requests',
        BH,
        {
          'live_id': liveId,
          'live_item_id': liId,
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'requested_qty': 9,
          'status': 'pending',
          'source': 'fleaber_live',
        },
      );
      final pr = row(pend['body']);
      add(
        'E_PENDING_WAITLIST',
        pr != null &&
            '${pr['status']}' == 'pending' &&
            n(pr['requested_qty']) == 9,
        {'row': pr},
      );

      if (pr != null) {
        final patch = await req(
          'PATCH',
          '$url/rest/v1/live_reservation_requests?id=eq.${pr['id']}',
          SH,
          {'status': 'accepted', 'requested_qty': 9},
        );
        final after = row((await req(
          'GET',
          '$url/rest/v1/live_reservation_requests?id=eq.${pr['id']}&select=status,requested_qty',
          SVC,
        ))['body']);
        final blocked = after != null && '${after['status']}' != 'accepted';
        add('E_PATCH_OVER_BLOCKED', blocked, {
          'http': patch['http'],
          'body': patch['body'],
          'after': after,
        });

        // RPC also blocked
        final rpc = await req(
          'POST',
          '$url/rest/v1/rpc/batata_process_live_reservation_request',
          SH,
          {'p_request_id': pr['id'], 'p_action': 'accept'},
        );
        final rpcBody = rpc['body'];
        add(
          'E_RPC_OVER_BLOCKED',
          rpcBody is Map && rpcBody['error'] == 'qty_exceeds_stock',
          rpc,
        );

        // legit accept qty 1
        await req(
          'DELETE',
          '$url/rest/v1/live_reservation_requests?buyer_id=eq.$buyerId&live_item_id=eq.$liId&status=in.(pending,accepted)',
          SVC,
        );
        final p1 = await req(
          'POST',
          '$url/rest/v1/live_reservation_requests',
          BH,
          {
            'live_id': liveId,
            'live_item_id': liId,
            'buyer_id': buyerId,
            'seller_id': sellerId,
            'requested_qty': 1,
            'status': 'pending',
            'source': 'fleaber_live',
          },
        );
        final p1r = row(p1['body']);
        if (p1r != null) {
          final rpcOk = await req(
            'POST',
            '$url/rest/v1/rpc/batata_process_live_reservation_request',
            SH,
            {'p_request_id': p1r['id'], 'p_action': 'accept'},
          );
          final st = row((await req(
            'GET',
            '$url/rest/v1/live_reservation_requests?id=eq.${p1r['id']}&select=status,requested_qty',
            SVC,
          ))['body']);
          add(
            'E_RPC_ACCEPT_1_OK',
            st != null && '${st['status']}' == 'accepted',
            {'rpc': rpcOk['body'], 'st': st},
          );
          await req(
            'POST',
            '$url/rest/v1/rpc/batata_process_live_reservation_request',
            SH,
            {'p_request_id': p1r['id'], 'p_action': 'reject'},
          );
        } else {
          add('E_RPC_ACCEPT_1_OK', false, 'no pending1');
        }

        await req(
          'DELETE',
          '$url/rest/v1/live_reservation_requests?buyer_id=eq.$buyerId&live_item_id=eq.$liId&status=in.(pending,accepted)',
          SVC,
        );
      } else {
        add('E_PATCH_OVER_BLOCKED', false, 'no pending');
        add('E_RPC_OVER_BLOCKED', false, 'no pending');
        add('E_RPC_ACCEPT_1_OK', false, 'no pending');
      }
    }
  }

  // ===== B: forge vendedor =====
  final p = await mkProduct(price: 10);
  final o = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': p['id'],
    'quantity': 1,
    'price_total': 10,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    'shipping_method': 'entrega em mão',
  });
  final or = row(o['body']);
  if (or != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.${or['id']}', SH, {
      'status': 'pago',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.${or['id']}', SH, {
      'status': 'enviado',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.${or['id']}', BH, {
      'status': 'concluido',
    });
    await req('DELETE', '$url/rest/v1/reviews?order_id=eq.${or['id']}', SVC);

    final forge = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': or['id'],
      'buyer_id': buyerId,
      'target_id': sellerId,
      'stars': 5,
      'comment': 'forge seller',
      'author_role': 'vendedor',
    });
    final fr = row(forge['body']);
    add(
      'B_FORGE_VENDEDOR_FORCED_COMPRADOR',
      fr != null && '${fr['author_role']}' == 'comprador',
      {'http': forge['http'], 'row': fr, 'body': forge['body']},
    );

    final forge2 = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': or['id'],
      'buyer_id': buyerId,
      'target_id': sellerId,
      'stars': 4,
      'comment': 'forge seller2',
      'author_role': 'seller',
    });
    add(
      'B_FORGE_SELLER_DUP_BLOCKED',
      (forge2['http'] as int) >= 400,
      {'http': forge2['http'], 'body': forge2['body']},
    );

    final legit = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': or['id'],
      'buyer_id': buyerId,
      'target_id': sellerId,
      'stars': 5,
      'comment': 'should fail dup',
      'author_role': 'comprador',
    });
    // first already created as comprador — second should fail
    // unless first failed — then this is the legit one
    final cnt = await req(
      'GET',
      '$url/rest/v1/reviews?order_id=eq.${or['id']}&select=id,author_role',
      SVC,
    );
    final nRows = cnt['body'] is List ? (cnt['body'] as List).length : -1;
    add('B_ONE_COMPRADOR_ROW', nRows == 1, {
      'n': nRows,
      'rows': cnt['body'],
      'legit_http': legit['http'],
    });

    // alias buyer still OK on fresh order
    final o2 = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': p['id'],
      'quantity': 1,
      'price_total': 10,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
      'shipping_method': 'entrega em mão',
    });
    final o2r = row(o2['body']);
    if (o2r != null) {
      await req('PATCH', '$url/rest/v1/orders?id=eq.${o2r['id']}', SH, {
        'status': 'pago',
      });
      await req('PATCH', '$url/rest/v1/orders?id=eq.${o2r['id']}', SH, {
        'status': 'enviado',
      });
      await req('PATCH', '$url/rest/v1/orders?id=eq.${o2r['id']}', BH, {
        'status': 'concluido',
      });
      final rBuyer = await req('POST', '$url/rest/v1/reviews', BH, {
        'order_id': o2r['id'],
        'buyer_id': buyerId,
        'target_id': sellerId,
        'stars': 5,
        'comment': 'alias buyer',
        'author_role': 'buyer',
      });
      final rb = row(rBuyer['body']);
      add(
        'B_ALIAS_BUYER_OK',
        rb != null && '${rb['author_role']}' == 'comprador',
        {'http': rBuyer['http'], 'row': rb},
      );
    } else {
      add('B_ALIAS_BUYER_OK', false, 'no o2');
    }
  } else {
    for (final id in [
      'B_FORGE_VENDEDOR_FORCED_COMPRADOR',
      'B_FORGE_SELLER_DUP_BLOCKED',
      'B_ONE_COMPRADOR_ROW',
      'B_ALIAS_BUYER_OK',
    ]) {
      add(id, false, 'no order');
    }
  }

  for (final pid in products) {
    final ords = await req(
      'GET',
      '$url/rest/v1/orders?product_id=eq.$pid&select=id',
      SVC,
    );
    if (ords['body'] is List) {
      for (final o in ords['body'] as List) {
        if (o is Map && o['id'] != null) {
          await req('DELETE', '$url/rest/v1/reviews?order_id=eq.${o['id']}', SVC);
        }
      }
    }
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
  }

  final fails = results.where((r) => r['ok'] != true).toList();
  File('tool/reports/HARDENING_C1_RI_E_RI_B_HOSTILE.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'when': DateTime.now().toUtc().toIso8601String(),
      'fail_count': fails.length,
      'results': results,
    }),
  );
  stdout.writeln('FAILS=${fails.length}/${results.length}');
  exit(fails.isEmpty ? 0 : 1);
}
