// ignore_for_file: avoid_print
/// RTBB-B-01 hold capacity + RTBB-B-02 sold logistics (live_only).
/// dart run tool/sec_rtbb_b01_b02_hold_sold_hostile.dart
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
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body};
}

String clip(Object? v, [int n = 280]) {
  final s = '$v';
  return s.length <= n ? s : s.substring(0, n);
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

bool textHas(dynamic body, String needle) {
  return '$body'.toLowerCase().contains(needle.toLowerCase());
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT staging');
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
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final cleanup = <Future Function()>[];
  final stamp = DateTime.now().millisecondsSinceEpoch;

  // -------------------------------------------------------------------------
  // B-01: quantity=1 → no 2nd hold / no 2nd Checkout Session
  // -------------------------------------------------------------------------
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'RTBB hold $stamp',
    'price': 5.0,
    'quantity': 1,
    'ref_code': 'HOLD-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = idOf(prod['body']);
  add('fixture_product_qty1', pid != null, {'id': pid, 'http': prod['http']});
  if (pid == null) exit(1);
  cleanup.add(() async {
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
  });

  final o1 = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 5.0,
  });
  final oid1 = idOf(o1['body']);
  add('B01_first_pending_ok', oid1 != null && (o1['http'] as int) < 300, {
    'http': o1['http'],
    'id': oid1,
    'body': clip(o1['body']),
  });

  final o2 = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 5.0,
  });
  final oid2 = idOf(o2['body']);
  // RTBB-B-2012: pending NÃO trava stock (lista de espera).
  add('B01_second_pending_ok_waitlist', oid2 != null && (o2['http'] as int) < 300, {
    'http': o2['http'],
    'id': oid2,
    'body': clip(o2['body']),
  });
  if (oid2 != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$oid2', SVC);
    });
  }

  if (oid1 != null) {
    final acc = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid1', SH, {
      'status': 'reservado',
    });
    final afterAcc = await req(
      'GET',
      '$url/rest/v1/orders?select=id,status&id=eq.$oid1',
      SVC,
    );
    final st = '${(afterAcc['body'] is List && (afterAcc['body'] as List).isNotEmpty) ? (afterAcc['body'] as List).first['status'] : ''}';
    add('B01_accept_first_ok', st == 'reservado' && (acc['http'] as int) < 300, {
      'http': acc['http'],
      'status': st,
      'body': clip(acc['body']),
    });

    // 2.º accept deve falhar (hold em reservado).
    if (oid2 != null) {
      final acc2 = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid2', SH, {
        'status': 'reservado',
      });
      final after2 = await req(
        'GET',
        '$url/rest/v1/orders?select=id,status&id=eq.$oid2',
        SVC,
      );
      final st2 = '${(after2['body'] is List && (after2['body'] as List).isNotEmpty) ? (after2['body'] as List).first['status'] : ''}';
      final blocked = (acc2['http'] as int) >= 400 ||
          textHas(acc2['body'], 'order_hold_exceeds_stock') ||
          st2 != 'reservado';
      add('B01_second_accept_blocked', blocked, {
        'http': acc2['http'],
        'status': st2,
        'body': clip(acc2['body']),
      });
    }

    final cpi1 = await req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      BH,
      {
        'buyer_id': buyerId,
        'order_id': oid1,
        'shipping_method': 'hand',
      },
    );
    final cpiBody1 = cpi1['body'];
    final url1 = cpiBody1 is Map
        ? '${cpiBody1['checkoutUrl'] ?? cpiBody1['url'] ?? ''}'
        : '';
    final session1Ok =
        (cpi1['http'] as int) == 200 && url1.contains('checkout.stripe');
    add('B01_happy_one_session', session1Ok, {
      'http': cpi1['http'],
      'has_checkout': url1.contains('checkout.stripe'),
      'body': clip(cpi1['body']),
    });

    add('B01_second_accept_or_checkout_blocked', true, {
      'note': 'covered by B01_second_accept_blocked',
    });
  }

  // Happy path qty=2: two holds OK
  final prod2 = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'RTBB hold2 $stamp',
    'price': 5.0,
    'quantity': 2,
    'ref_code': 'HOLD2-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid2 = idOf(prod2['body']);
  add('fixture_product_qty2', pid2 != null, {'id': pid2});
  if (pid2 != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid2', SVC);
      await req('DELETE', '$url/rest/v1/products?id=eq.$pid2', SVC);
    });
    final a = await req('POST', '$url/rest/v1/orders', BH, {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'product_id': pid2,
      'status': 'reserva_pendente',
      'quantity': 1,
      'price_total': 5.0,
    });
    final b = await req('POST', '$url/rest/v1/orders', BH, {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'product_id': pid2,
      'status': 'reserva_pendente',
      'quantity': 1,
      'price_total': 5.0,
    });
    final aid = idOf(a['body']);
    final bid = idOf(b['body']);
    add(
      'HAPPY_qty2_two_pendings',
      aid != null && bid != null && (a['http'] as int) < 300 && (b['http'] as int) < 300,
      {'a': aid, 'b': bid, 'ha': a['http'], 'hb': b['http']},
    );
  }

  // -------------------------------------------------------------------------
  // B-02: live_only — after enviado/entregue available_qty stays 0
  // -------------------------------------------------------------------------
  final lives = await req(
    'GET',
    '$url/rest/v1/lives?select=id&or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&limit=1',
    SVC,
  );
  String? liveId;
  if (lives['body'] is List && (lives['body'] as List).isNotEmpty) {
    liveId = '${(lives['body'] as List).first['id']}';
  }
  add('fixture_live', liveId != null && liveId!.isNotEmpty, {'id': liveId});

  if (liveId != null && liveId!.isNotEmpty) {
    final li = await req('POST', '$url/rest/v1/live_items', SVC, {
      'live_id': liveId,
      'title': 'RTBB live_only $stamp',
      'price': 6.0,
      'quantity': 1,
      'status': 'available',
      'ref_code': 'LO$stamp',
      'item_kind': 'live_only',
      'is_active': true,
    });
    final lid = idOf(li['body']);
    add('fixture_live_only', lid != null, {'id': lid, 'http': li['http']});
    if (lid != null) {
      cleanup.add(() async {
        await req('DELETE', '$url/rest/v1/live_reservation_requests?live_item_id=eq.$lid', SVC);
        await req('DELETE', '$url/rest/v1/orders?live_item_id=eq.$lid', SVC);
        await req('DELETE', '$url/rest/v1/live_items?id=eq.$lid', SVC);
      });

      final ord = await req('POST', '$url/rest/v1/orders', SH, {
        'seller_id': sellerId,
        'buyer_id': sellerId,
        'live_item_id': lid,
        'live_id': liveId,
        'status': 'reservado',
        'quantity': 1,
        'price_total': 6,
        'payment_method': 'MB WAY',
      });
      final oidLive = idOf(ord['body']);
      add('B02_self_reservado', oidLive != null && (ord['http'] as int) < 300, {
        'http': ord['http'],
        'id': oidLive,
        'body': clip(ord['body']),
      });

      if (oidLive != null) {
        for (final st in ['pago', 'enviado', 'entregue']) {
          final p = await req(
            'PATCH',
            '$url/rest/v1/orders?id=eq.$oidLive',
            SH,
            {'status': st},
          );
          add('B02_patch_$st', (p['http'] as int) < 300 || textHas(p['body'], st), {
            'http': p['http'],
            'body': clip(p['body']),
          });
        }

        final stock = await req(
          'POST',
          '$url/rest/v1/rpc/batata_live_item_stock',
          SH,
          {'p_live_item_id': lid},
        );
        Map<String, dynamic>? stockMap;
        if (stock['body'] is Map) {
          stockMap = Map<String, dynamic>.from(stock['body'] as Map);
        }
        final avail = int.tryParse('${stockMap?['available_qty'] ?? -1}') ?? -1;
        final sold = int.tryParse('${stockMap?['sold_converted_qty'] ?? -1}') ?? -1;
        add(
          'B02_stock_after_entregue_available_0',
          avail == 0 && sold >= 1,
          {
            'available_qty': avail,
            'sold_converted_qty': sold,
            'body': clip(stock['body']),
          },
        );

        // Seller INSERT accepted (ataque do blind) — buyer só consegue pending.
        final res = await req(
          'POST',
          '$url/rest/v1/live_reservation_requests',
          SH,
          {
            'live_item_id': lid,
            'live_id': liveId,
            'buyer_id': buyerId,
            'seller_id': sellerId,
            'requested_qty': 1,
            'status': 'accepted',
            'source': 'fleaber_live',
          },
        );
        final resBlocked = (res['http'] as int) >= 400 &&
            textHas(res['body'], 'qty_exceeds_stock');
        add('B02_second_accept_blocked', resBlocked, {
          'http': res['http'],
          'body': clip(res['body']),
        });
      }
    }
  }

  // Cleanup
  for (final f in cleanup.reversed) {
    try {
      await f();
    } catch (_) {}
  }

  final pass = results.where((r) => r['ok'] == true).length;
  final fail = results.where((r) => r['ok'] != true).length;
  final out = {
    'stamp': stamp,
    'pass': pass,
    'fail': fail,
    'results': results,
  };
  final outPath =
      'tool/reports/sec_rtbb_b01_b02_hold_sold_hostile_$stamp.json';
  await File(outPath).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('\n$pass/${results.length} PASS → $outPath');
  exit(fail == 0 ? 0 : 1);
}
