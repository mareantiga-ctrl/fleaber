// ignore_for_file: avoid_print
/// C1 — RI-E converted capacity class hostile battery (descartável).
/// dart run tool/sec_c1_ri_e_converted_capacity_final_hostile.dart
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

bool consumes(String? st) {
  final s = (st ?? '').trim().toLowerCase();
  return s == 'accepted' || s == 'converted';
}

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
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final products = <String>[];

  final lives = await sb.select('lives', filter: 'seller_id=eq.$sellerId', limit: 1);
  if (lives.isEmpty) {
    stderr.writeln('FAIL no live fixture');
    exit(1);
  }
  final liveId = '${lives.first['id']}';
  final items = await sb.select('live_items', filter: 'live_id=eq.$liveId', limit: 1);
  if (items.isEmpty) {
    stderr.writeln('FAIL no live_item');
    exit(1);
  }
  final li = items.first;
  final liId = '${li['id']}';
  final productId = li['product_id']?.toString();

  Future<void> forceCap1() async {
    if (productId != null && productId.isNotEmpty) {
      await req('PATCH', '$url/rest/v1/products?id=eq.$productId', SVC, {
        'quantity': 1,
      });
    }
    await req('PATCH', '$url/rest/v1/live_items?id=eq.$liId', SVC, {
      'quantity': 1,
      'status': 'available',
    });
  }

  Future<void> clearBuyerRes() async {
    await req(
      'DELETE',
      '$url/rest/v1/live_reservation_requests?live_item_id=eq.$liId&status=in.(pending,accepted,converted)',
      SVC,
    );
  }

  Future<Map<String, dynamic>?> mkPending(int qty, {Map<String, String>? tok}) async {
    final r = await req(
      'POST',
      '$url/rest/v1/live_reservation_requests',
      tok ?? BH,
      {
        'live_id': liveId,
        'live_item_id': liId,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'requested_qty': qty,
        'status': 'pending',
        'source': 'fleaber_live',
      },
    );
    return row(r['body']);
  }

  Future<Map<String, dynamic>?> snap(String id) async {
    return row((await req(
      'GET',
      '$url/rest/v1/live_reservation_requests?id=eq.$id&select=id,status,requested_qty',
      SVC,
    ))['body']);
  }

  Future<int> consumingSum() async {
    final r = await req(
      'GET',
      '$url/rest/v1/live_reservation_requests?live_item_id=eq.$liId&status=in.(accepted,converted)&select=requested_qty',
      SVC,
    );
    if (r['body'] is! List) return -1;
    var s = 0;
    for (final e in r['body'] as List) {
      if (e is Map) s += n(e['requested_qty']).toInt();
    }
    return s;
  }

  await forceCap1();
  await clearBuyerRes();

  // ---- T1 accepted over ----
  {
    final p = await mkPending(9);
    final patch = await req(
      'PATCH',
      '$url/rest/v1/live_reservation_requests?id=eq.${p!['id']}',
      SH,
      {'status': 'accepted'},
    );
    final a = await snap('${p['id']}');
    add(
      'T1_PATCH_ACCEPTED_Q9_BLOCKED',
      a != null && !consumes('${a['status']}') && n(a['requested_qty']) == 9,
      {'http': patch['http'], 'after': a, 'body': patch['body']},
    );
    await clearBuyerRes();
  }

  // ---- T2 converted over (exploit) ----
  {
    final p = await mkPending(9);
    final patch = await req(
      'PATCH',
      '$url/rest/v1/live_reservation_requests?id=eq.${p!['id']}',
      SH,
      {'status': 'converted'},
    );
    final a = await snap('${p['id']}');
    add(
      'T2_PATCH_CONVERTED_Q9_BLOCKED',
      a != null && '${a['status']}' != 'converted' && n(a['requested_qty']) == 9,
      {'http': patch['http'], 'after': a, 'body': patch['body']},
    );
    await clearBuyerRes();
  }

  // ---- T3/T4 qty=2 ----
  for (final st in ['accepted', 'converted']) {
    final p = await mkPending(2);
    final patch = await req(
      'PATCH',
      '$url/rest/v1/live_reservation_requests?id=eq.${p!['id']}',
      SH,
      {'status': st},
    );
    final a = await snap('${p['id']}');
    add(
      'T_${st.toUpperCase()}_Q2_BLOCKED',
      a != null && !consumes('${a['status']}'),
      {'http': patch['http'], 'after': a},
    );
    await clearBuyerRes();
  }

  // ---- T5 accepted qty=1 OK ----
  String? acceptedId;
  {
    final p = await mkPending(1);
    final patch = await req(
      'PATCH',
      '$url/rest/v1/live_reservation_requests?id=eq.${p!['id']}',
      SH,
      {'status': 'accepted'},
    );
    final a = await snap('${p['id']}');
    final ok = a != null && '${a['status']}' == 'accepted' && n(a['requested_qty']) == 1;
    add('T5_PATCH_ACCEPTED_Q1_OK', ok, {'http': patch['http'], 'after': a});
    if (ok) acceptedId = '${p['id']}';
  }

  // ---- T6 convert legit from accepted ----
  {
    if (acceptedId == null) {
      add('T6_CONVERT_FROM_ACCEPTED_OK', false, 'no accepted');
    } else {
      final patch = await req(
        'PATCH',
        '$url/rest/v1/live_reservation_requests?id=eq.$acceptedId',
        SH,
        {'status': 'converted'},
      );
      final a = await snap(acceptedId);
      // same qty, already consuming → allowed
      add(
        'T6_CONVERT_FROM_ACCEPTED_OK',
        a != null && '${a['status']}' == 'converted' && n(a['requested_qty']) == 1,
        {'http': patch['http'], 'after': a, 'body': patch['body']},
      );
      // cleanup via svc
      await req(
        'DELETE',
        '$url/rest/v1/live_reservation_requests?id=eq.$acceptedId',
        SVC,
      );
    }
    await clearBuyerRes();
  }

  // ---- T7/T8 buyer ----
  {
    final p = await mkPending(1);
    for (final st in ['accepted', 'converted']) {
      final patch = await req(
        'PATCH',
        '$url/rest/v1/live_reservation_requests?id=eq.${p!['id']}',
        BH,
        {'status': st},
      );
      final a = await snap('${p['id']}');
      add(
        'T_BUYER_PATCH_${st.toUpperCase()}_BLOCKED',
        a != null && '${a['status']}' == 'pending',
        {'http': patch['http'], 'after': a},
      );
    }
    await clearBuyerRes();
  }

  // ---- T9 buyer INSERT accepted q9 ----
  {
    final ins = await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
      'live_id': liveId,
      'live_item_id': liId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'requested_qty': 9,
      'status': 'accepted',
      'source': 'fleaber_live',
    });
    final r = row(ins['body']);
    add(
      'T9_BUYER_INSERT_ACCEPTED_FORCED_PENDING',
      r != null && '${r['status']}' == 'pending' && n(r['requested_qty']) == 9,
      {'http': ins['http'], 'row': r},
    );
    await clearBuyerRes();
  }

  // ---- T10/T11 seller INSERT ----
  for (final st in ['accepted', 'converted']) {
    final ins = await req('POST', '$url/rest/v1/live_reservation_requests', SH, {
      'live_id': liveId,
      'live_item_id': liId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'requested_qty': 9,
      'status': st,
      'source': 'fleaber_live',
    });
    final r = row(ins['body']);
    final blocked = (ins['http'] as int) >= 400 ||
        (r != null && !consumes('${r['status']}'));
    add('T_SELLER_INSERT_${st.toUpperCase()}_Q9_BLOCKED', blocked, {
      'http': ins['http'],
      'row': r,
      'body': ins['body'],
    });
    await clearBuyerRes();
  }

  // ---- T12 qty up on accepted ----
  {
    final p = await mkPending(1);
    await req(
      'PATCH',
      '$url/rest/v1/live_reservation_requests?id=eq.${p!['id']}',
      SH,
      {'status': 'accepted'},
    );
    final up = await req(
      'PATCH',
      '$url/rest/v1/live_reservation_requests?id=eq.${p['id']}',
      SH,
      {'requested_qty': 9},
    );
    final a = await snap('${p['id']}');
    add(
      'T12_ACCEPTED_QTY_UP_BLOCKED',
      a != null && n(a['requested_qty']) == 1,
      {'http': up['http'], 'after': a, 'body': up['body']},
    );
    await clearBuyerRes();
  }

  // ---- T13 qty up on converted ----
  {
    final p = await mkPending(1);
    await req(
      'PATCH',
      '$url/rest/v1/live_reservation_requests?id=eq.${p!['id']}',
      SH,
      {'status': 'accepted'},
    );
    await req(
      'PATCH',
      '$url/rest/v1/live_reservation_requests?id=eq.${p['id']}',
      SH,
      {'status': 'converted'},
    );
    final up = await req(
      'PATCH',
      '$url/rest/v1/live_reservation_requests?id=eq.${p['id']}',
      SH,
      {'requested_qty': 9},
    );
    final a = await snap('${p['id']}');
    add(
      'T13_CONVERTED_QTY_UP_BLOCKED',
      a != null && n(a['requested_qty']) == 1 && '${a['status']}' == 'converted',
      {'http': up['http'], 'after': a, 'body': up['body']},
    );
    await clearBuyerRes();
  }

  // ---- Status variants ----
  for (final st in [
    'ACCEPTED',
    'Accepted',
    ' accepted ',
    'CONVERTED',
    'Converted',
    ' converted ',
  ]) {
    final p = await mkPending(9);
    final patch = await req(
      'PATCH',
      '$url/rest/v1/live_reservation_requests?id=eq.${p!['id']}',
      SH,
      {'status': st},
    );
    final a = await snap('${p['id']}');
    add(
      'VAR_${st.trim()}_Q9_BLOCKED',
      a != null && !consumes('${a['status']}'),
      {'http': patch['http'], 'after': a, 'tried': st},
    );
    await clearBuyerRes();
  }

  // ---- Waitlist regression ----
  {
    final a = await mkPending(9);
    final b = await mkPending(1);
    add(
      'WAITLIST_PENDING9_OK',
      a != null && '${a['status']}' == 'pending' && n(a['requested_qty']) == 9,
      a,
    );
    final acc = await req(
      'PATCH',
      '$url/rest/v1/live_reservation_requests?id=eq.${b!['id']}',
      SH,
      {'status': 'accepted'},
    );
    final bs = await snap('${b['id']}');
    final as_ = await snap('${a!['id']}');
    add(
      'WAITLIST_B_ACCEPT1_OK',
      bs != null && '${bs['status']}' == 'accepted' && n(bs['requested_qty']) == 1,
      {'http': acc['http'], 'b': bs},
    );
    add(
      'WAITLIST_A_STILL_PENDING',
      as_ != null && '${as_['status']}' == 'pending',
      as_,
    );
    await clearBuyerRes();
  }

  // ---- RPC accept 1 OK / over blocked ----
  {
    final p9 = await mkPending(9);
    final rpcBad = await req(
      'POST',
      '$url/rest/v1/rpc/batata_process_live_reservation_request',
      SH,
      {'p_request_id': p9!['id'], 'p_action': 'accept'},
    );
    add(
      'RPC_ACCEPT_Q9_BLOCKED',
      rpcBad['body'] is Map &&
          (rpcBad['body'] as Map)['error'] == 'qty_exceeds_stock',
      rpcBad['body']!,
    );
    await clearBuyerRes();
    final p1 = await mkPending(1);
    final rpcOk = await req(
      'POST',
      '$url/rest/v1/rpc/batata_process_live_reservation_request',
      SH,
      {'p_request_id': p1!['id'], 'p_action': 'accept'},
    );
    final st = await snap('${p1['id']}');
    add(
      'RPC_ACCEPT_Q1_OK',
      st != null && '${st['status']}' == 'accepted',
      {'rpc': rpcOk['body'], 'st': st},
    );
    await clearBuyerRes();
  }

  // ---- Concurrency ----
  Future<void> racePair(String label, String stA, String stB) async {
    await clearBuyerRes();
    await forceCap1();
    final r1 = await mkPending(1);
    final r2 = await mkPending(1);
    final f1 = req(
      'PATCH',
      '$url/rest/v1/live_reservation_requests?id=eq.${r1!['id']}',
      SH,
      {'status': stA},
    );
    final f2 = req(
      'PATCH',
      '$url/rest/v1/live_reservation_requests?id=eq.${r2!['id']}',
      SH,
      {'status': stB},
    );
    final outs = await Future.wait([f1, f2]);
    final sum = await consumingSum();
    final s1 = await snap('${r1['id']}');
    final s2 = await snap('${r2['id']}');
    add(
      'RACE_$label',
      sum >= 0 && sum <= 1,
      {
        'sum_consuming': sum,
        'cap': 1,
        'h1': outs[0]['http'],
        'h2': outs[1]['http'],
        's1': s1,
        's2': s2,
      },
    );
    await clearBuyerRes();
  }

  await racePair('AA', 'accepted', 'accepted');
  await racePair('CC', 'converted', 'converted');
  await racePair('AC', 'accepted', 'converted');
  await racePair('CA', 'converted', 'accepted');

  // ---- RI-B smoke ----
  {
    final p = await sb.insert('products', {
      'seller_id': sellerId,
      'title': 'C1CONV $stamp',
      'price': 8,
      'quantity': 3,
      'list_on_marketplace': false,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    products.add('${p['id']}');
    final o = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': p['id'],
      'quantity': 1,
      'price_total': 8,
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
      final f1 = await req('POST', '$url/rest/v1/reviews', BH, {
        'order_id': or['id'],
        'buyer_id': buyerId,
        'target_id': sellerId,
        'stars': 5,
        'comment': 'forge v',
        'author_role': 'vendedor',
      });
      final fr = row(f1['body']);
      add(
        'RIB_FORGE_VENDEDOR',
        fr != null && '${fr['author_role']}' == 'comprador',
        fr,
      );
      final race = await Future.wait([
        req('POST', '$url/rest/v1/reviews', BH, {
          'order_id': or['id'],
          'buyer_id': buyerId,
          'target_id': sellerId,
          'stars': 4,
          'comment': 'r1',
          'author_role': 'buyer',
        }),
        req('POST', '$url/rest/v1/reviews', BH, {
          'order_id': or['id'],
          'buyer_id': buyerId,
          'target_id': sellerId,
          'stars': 3,
          'comment': 'r2',
          'author_role': 'seller',
        }),
      ]);
      final cnt = await req(
        'GET',
        '$url/rest/v1/reviews?order_id=eq.${or['id']}&select=id',
        SVC,
      );
      final nRows = cnt['body'] is List ? (cnt['body'] as List).length : -1;
      add('RIB_ONE_ROW', nRows == 1, {
        'n': nRows,
        'race_http': race.map((e) => e['http']).toList(),
      });
    } else {
      add('RIB_FORGE_VENDEDOR', false, 'no order');
      add('RIB_ONE_ROW', false, 'no order');
    }
  }

  // ---- Minimal contract smoke ----
  {
    final p = await sb.insert('products', {
      'seller_id': sellerId,
      'title': 'C1CONV CTR $stamp',
      'price': 40,
      'quantity': 2,
      'list_on_marketplace': false,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    products.add('${p['id']}');
    final o = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': p['id'],
      'quantity': 1,
      'price_total': 0.4,
      'contract_unit_cents': 40,
      'contract_qty': 9,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na App',
      'shipping_method': 'entrega em mão',
    });
    final or = row(o['body']);
    add(
      'SMOKE_CONTRACT_JWT',
      or != null &&
          n(or['contract_unit_cents']) == 4000 &&
          n(or['contract_qty']) == 1,
      {'cuc': or?['contract_unit_cents'], 'cq': or?['contract_qty']},
    );
    // platform seller pago blocked
    await req('PATCH', '$url/rest/v1/orders?id=eq.${or!['id']}', SH, {
      'status': 'pago',
    });
    final after = row((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.${or['id']}&select=status',
      SVC,
    ))['body']);
    add(
      'SMOKE_PLATFORM_SELLER_PAGO',
      after != null && '${after['status']}' != 'pago',
      after,
    );
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
  await clearBuyerRes();

  final fails = results.where((r) => r['ok'] != true).toList();
  File('tool/reports/HARDENING_C1_RI_E_CONVERTED_CAPACITY_FINAL.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'when': DateTime.now().toUtc().toIso8601String(),
    'fail_count': fails.length,
    'pass_count': results.length - fails.length,
    'results': results,
  }));
  stdout.writeln('FAILS=${fails.length}/${results.length}');
  exit(fails.isEmpty ? 0 : 1);
}
