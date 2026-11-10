// ignore_for_file: avoid_print
/// RT2120 anon DEFINER + offer qty=1 + live hold.
/// dart run tool/sec_rt2120_anon_offer_hostile.dart
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
      ? await http.post(Uri.parse(u), headers: h, body: jsonEncode(body ?? {}))
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

String clip(Object? v, [int n = 260]) {
  final s = '$v';
  return s.length <= n ? s : s.substring(0, n);
}

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    final s = '${(body.first as Map)['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  return null;
}

bool deniedRpc(Map<String, dynamic> r) {
  final c = r['http'] as int;
  if (c == 401 || c == 403 || c == 404) return true;
  final t = '${r['body'] ?? r['text']}'.toLowerCase();
  return t.contains('not_allowed') ||
      t.contains('permission') ||
      t.contains('42501');
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
  final ANON = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
  };
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

  // Fixtures: product + live_item marketplace
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'RT2120 $stamp',
    'price': 20.0,
    'quantity': 5,
    'ref_code': 'RT2120-$stamp',
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = idOf(prod['body']);
  add('fixture_product', pid != null, {'id': pid});
  if (pid == null) exit(1);
  cleanup.add(() async {
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid', SVC);
    await req('DELETE', '$url/rest/v1/product_offers?product_id=eq.$pid', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
  });

  final lives = await req(
    'GET',
    '$url/rest/v1/lives?select=id&or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&limit=1',
    SVC,
  );
  String? liveId;
  if (lives['body'] is List && (lives['body'] as List).isNotEmpty) {
    liveId = '${(lives['body'] as List).first['id']}';
  }
  String? lid;
  if (liveId != null) {
    final li = await req('POST', '$url/rest/v1/live_items', SVC, {
      'live_id': liveId,
      'title': 'RT2120 li $stamp',
      'price': 20.0,
      'quantity': null,
      'status': 'available',
      'ref_code': 'LI$stamp',
      'item_kind': 'marketplace_product',
      'product_id': pid,
      'is_active': true,
    });
    lid = idOf(li['body']);
    add('fixture_live_item', lid != null, {'id': lid, 'http': li['http']});
    if (lid != null) {
      cleanup.add(() async {
        await req(
          'DELETE',
          '$url/rest/v1/live_reservation_requests?live_item_id=eq.$lid',
          SVC,
        );
        await req('DELETE', '$url/rest/v1/live_items?id=eq.$lid', SVC);
      });
    }
  } else {
    add('fixture_live_item', false, {'no_live': true});
  }

  // ---- P1 mark sold anon ----
  if (lid != null) {
    final before = await req(
      'GET',
      '$url/rest/v1/products?select=id,is_sold&id=eq.$pid',
      SVC,
    );
    final markAnon = await req(
      'POST',
      '$url/rest/v1/rpc/batata_mark_live_item_sold',
      ANON,
      {'p_live_item_id': lid},
    );
    final after = await req(
      'GET',
      '$url/rest/v1/products?select=id,is_sold&id=eq.$pid',
      SVC,
    );
    final soldAfter = after['body'] is List &&
        (after['body'] as List).isNotEmpty &&
        (after['body'] as List).first['is_sold'] == true;
    add(
      'P1_mark_sold_anon_denied',
      deniedRpc(markAnon) && !soldAfter,
      {
        'http': markAnon['http'],
        'body': clip(markAnon['body']),
        'sold_after': soldAfter,
        'before': clip(before['body']),
      },
    );

    // Seller JWT pode marcar
    final markSeller = await req(
      'POST',
      '$url/rest/v1/rpc/batata_mark_live_item_sold',
      SH,
      {'p_live_item_id': lid},
    );
    final okSeller = markSeller['body'] is Map &&
        ((markSeller['body'] as Map)['ok'] == true ||
            (markSeller['body'] as Map)['error'] == null);
    // Restaurar produto para resto dos testes
    await req('PATCH', '$url/rest/v1/products?id=eq.$pid', SVC, {
      'is_sold': false,
      'list_on_marketplace': true,
      'quantity': 5,
    });
    await req('PATCH', '$url/rest/v1/live_items?id=eq.$lid', SVC, {
      'status': 'available',
    });
    add('HAPPY_mark_sold_seller_ok', (markSeller['http'] as int) < 300 && okSeller, {
      'http': markSeller['http'],
      'body': clip(markSeller['body']),
    });
  }

  // ---- P1 reconcile anon ----
  final reconAnon = await req(
    'POST',
    '$url/rest/v1/rpc/batata_live_reconcile_stripe_order',
    ANON,
    {'p_order_id': '00000000-0000-0000-0000-000000000001'},
  );
  add('P1_reconcile_anon_denied', deniedRpc(reconAnon), {
    'http': reconAnon['http'],
    'body': clip(reconAnon['body']),
  });

  final syncAnon = await req(
    'POST',
    '$url/rest/v1/rpc/batata_sync_live_item_for_order',
    ANON,
    {'p_order_id': '00000000-0000-0000-0000-000000000001'},
  );
  add('P1_sync_anon_denied', deniedRpc(syncAnon), {
    'http': syncAnon['http'],
    'body': clip(syncAnon['body']),
  });

  // ---- Offer qty>1 blocked; qty=1 OK ----
  final offer = await req('POST', '$url/rest/v1/product_offers', BH, {
    'product_id': pid,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 5.0,
    'offered_by': 'buyer',
    'status': 'pending',
    'expires_at': DateTime.now()
        .toUtc()
        .add(const Duration(hours: 48))
        .toIso8601String(),
  });
  final offerId = idOf(offer['body']);
  add('fixture_offer', offerId != null, {'id': offerId});
  if (offerId != null) {
    await req('PATCH', '$url/rest/v1/product_offers?id=eq.$offerId', SH, {
      'status': 'accepted',
    });
    final bad = await req('POST', '$url/rest/v1/orders', BH, {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'product_id': pid,
      'product_offer_id': offerId,
      'status': 'reserva_pendente',
      'quantity': 4,
      'price_total': 5.0,
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    add(
      'OFFER_qty4_blocked',
      (bad['http'] as int) >= 400 &&
          '${bad['body']}'.contains('offer_quantity_must_be_one'),
      {'http': bad['http'], 'body': clip(bad['body'])},
    );

    final good = await req('POST', '$url/rest/v1/orders', BH, {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'product_id': pid,
      'product_offer_id': offerId,
      'status': 'reserva_pendente',
      'quantity': 1,
      'price_total': 5.0,
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    final oid = idOf(good['body']);
    final row = (good['body'] is List && (good['body'] as List).isNotEmpty)
        ? Map<String, dynamic>.from((good['body'] as List).first as Map)
        : null;
    final unit = int.tryParse('${row?['contract_unit_cents'] ?? ''}');
    final qty = int.tryParse('${row?['contract_qty'] ?? ''}');
    add(
      'OFFER_qty1_ok_unit_500',
      oid != null && unit == 500 && qty == 1,
      {'id': oid, 'unit': unit, 'qty': qty, 'http': good['http']},
    );
    if (oid != null) {
      await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {
        'status': 'reservado',
      });
      final cpi = await req(
        'POST',
        '$url/functions/v1/create-payment-intent',
        BH,
        {
          'buyer_id': buyerId,
          'order_id': oid,
          'shipping_method': 'entrega em mão',
        },
      );
      final amt = cpi['body'] is Map
          ? int.tryParse(
              '${(cpi['body'] as Map)['server_amount_cents'] ?? ''}',
            )
          : null;
      // 500 + prot (~41) ≈ 541, não 2165
      add(
        'OFFER_checkout_not_multi_unit',
        (cpi['http'] as int) == 200 && amt != null && amt < 800,
        {'http': cpi['http'], 'server_amount_cents': amt},
      );
    }
  }

  for (final f in cleanup.reversed) {
    try {
      await f();
    } catch (_) {}
  }

  final pass = results.where((r) => r['ok'] == true).length;
  final fail = results.where((r) => r['ok'] != true).length;
  final outPath = 'tool/reports/sec_rt2120_anon_offer_hostile_$stamp.json';
  await File(outPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'stamp': stamp,
      'pass': pass,
      'fail': fail,
      'results': results,
    }),
  );
  stdout.writeln('\n$pass/${results.length} PASS → $outPath');
  exit(fail == 0 ? 0 : 1);
}
