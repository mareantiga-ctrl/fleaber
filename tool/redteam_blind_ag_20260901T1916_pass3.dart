// ignore_for_file: avoid_print
/// AG pass3 — convert após pago falso + freeze waitlist + PI ghost. dart run tool/redteam_blind_ag_20260901T1916_pass3.dart
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
  final encoded = body == null ? null : jsonEncode(body);
  final r = method == 'POST'
      ? await http.post(Uri.parse(u), headers: h, body: encoded)
      : method == 'PATCH'
          ? await http.patch(Uri.parse(u), headers: h, body: encoded)
          : await http.get(Uri.parse(u), headers: h);
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
    final s = '${(body.first as Map)['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  if (body is Map && body['id'] != null) {
    final s = '${body['id']}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  return null;
}

Map<String, dynamic>? firstMap(dynamic body) {
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
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
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

  final probes = <Map<String, dynamic>>[];
  void probe(String id, Map<String, dynamic> d) {
    probes.add({'id': id, ...d});
    print('PROBE $id ${jsonEncode(d)}');
  }

  Future<Map<String, dynamic>> row(String table, String id, String sel) async {
    return firstMap(
          (await req('GET', '$url/rest/v1/$table?id=eq.$id&select=$sel', SVC))['body'],
        ) ??
        {};
  }

  // Reuse pass2 live item + fake pago order if still there; else create fresh.
  const loId = 'fb9614ac-da94-4c26-adf6-db216d2bfce6';
  const liveId = '6448362b-4f3c-4729-823c-7922ca3c1f07';
  const fmId = '9850d331-58a9-49df-a7ad-57fd00491489';
  const fakePago = 'db2da223-4245-44ec-bcf3-9ce95a9860c0';
  const ghostOrd = '3e43ac19-3ca6-4067-b177-63af9c0d2004';

  await req('PATCH', '$url/rest/v1/lives?id=eq.$liveId', SVC, {
    'status': 'live',
    'is_active': true,
  });

  final fm = await row('live_reservation_requests', fmId, 'status,source,live_item_id,buyer_id');
  final ord = await row('orders', fakePago, 'status,amount_paid_cents,stripe_payment_intent_id,live_item_id,buyer_id');
  probe('state', {'fm': fm, 'ord': ord});

  final convPatch = await req(
    'PATCH',
    '$url/rest/v1/live_reservation_requests?id=eq.$fmId',
    SH,
    {'status': 'converted'},
  );
  final convRpc = await req(
    'POST',
    '$url/rest/v1/rpc/batata_process_live_reservation_request',
    SH,
    {'p_request_id': fmId, 'p_action': 'convert'},
  );
  probe('AG1-convert-after-fake-pago-no-cents', {
    'patch_http': convPatch['http'],
    'patch_body': convPatch['body'],
    'rpc_http': convRpc['http'],
    'rpc_body': convRpc['body'],
    'fm_after': await row('live_reservation_requests', fmId, 'status'),
    'open': '${(await row('live_reservation_requests', fmId, 'status'))['status']}' == 'converted',
  });

  final wal1 = firstMap(
    (await req('GET', '$url/rest/v1/wallets?id=eq.$sellerId&select=id,balance', SVC))['body'],
  );
  probe('AG8-wallet-after-fake-pago', {'wallet': wal1});

  final piGhost = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
    'order_id': ghostOrd,
  });
  probe('AG8-pi-on-ghost-order-reserved-full', {
    'http': piGhost['http'],
    'raw': '${piGhost['raw']}'.substring(0, ('${piGhost['raw']}'.length).clamp(0, 700)),
  });

  final piFake = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
    'order_id': fakePago,
  });
  probe('AG8-pi-on-fake-pago-order', {
    'http': piFake['http'],
    'raw': '${piFake['raw']}'.substring(0, ('${piFake['raw']}'.length).clamp(0, 700)),
  });

  // Waitlist freeze: qty=1, two pendings, accept first
  final live = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'title': 'RTAG-p3-freeze',
    'status': 'live',
    'is_active': true,
  });
  final lid = idOf(live['body']);
  final item = await req('POST', '$url/rest/v1/live_items', SVC, {
    'live_id': lid,
    'ref_code': 'FZ1',
    'title': 'freeze',
    'price': 4,
    'quantity': 1,
    'status': 'available',
    'is_active': true,
    'item_kind': 'live_only',
  });
  final iid = idOf(item['body']);
  final p1 = await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
    'live_id': lid,
    'live_item_id': iid,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'requested_qty': 1,
    'status': 'pending',
    'source': 'fleaber_live',
  });
  final accOnly = await req(
    'POST',
    '$url/rest/v1/rpc/batata_process_live_reservation_request',
    SH,
    {'p_request_id': idOf(p1['body']), 'p_action': 'accept'},
  );
  probe('AG6-accept-one-pending-qty1', {
    'p1': idOf(p1['body']),
    'http': accOnly['http'],
    'body': accOnly['body'],
    'status': idOf(p1['body']) == null
        ? null
        : await row('live_reservation_requests', idOf(p1['body'])!, 'status'),
  });

  final p2 = await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
    'live_id': lid,
    'live_item_id': iid,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'requested_qty': 1,
    'status': 'pending',
    'source': 'fleaber_live',
  });
  // second pending while first already accepted? or reject first and do 2 pending then accept
  probe('AG3-second-pending-after-accept', {
    'http': p2['http'],
    'id': idOf(p2['body']),
    'status': firstMap(p2['body'])?['status'],
  });

  // Fresh freeze: qty=1, TWO pendings, then accept
  final live2 = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'title': 'RTAG-p3-freeze2',
    'status': 'live',
    'is_active': true,
  });
  final lid2 = idOf(live2['body']);
  final item2 = await req('POST', '$url/rest/v1/live_items', SVC, {
    'live_id': lid2,
    'ref_code': 'FZ2',
    'title': 'freeze2',
    'price': 4,
    'quantity': 1,
    'status': 'available',
    'is_active': true,
    'item_kind': 'live_only',
  });
  final iid2 = idOf(item2['body']);
  final a = await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
    'live_id': lid2,
    'live_item_id': iid2,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'requested_qty': 1,
    'status': 'pending',
    'source': 'fleaber_live',
  });
  final helperTok = await sb.signIn(
    email: 'rtag-20260901t1916-helper@staging.fleaber.bot',
    password: 'RTAG_Helper_2026!x',
  );
  final helperId = await sb.userIdForAccessToken(helperTok);
  final HH = {
    'apikey': anon,
    'Authorization': 'Bearer $helperTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final b = await req('POST', '$url/rest/v1/live_reservation_requests', HH, {
    'live_id': lid2,
    'live_item_id': iid2,
    'buyer_id': helperId,
    'seller_id': sellerId,
    'requested_qty': 1,
    'status': 'pending',
    'source': 'fleaber_live',
  });
  final accA = await req(
    'POST',
    '$url/rest/v1/rpc/batata_process_live_reservation_request',
    SH,
    {'p_request_id': idOf(a['body']), 'p_action': 'accept'},
  );
  final accPatch = await req(
    'PATCH',
    '$url/rest/v1/live_reservation_requests?id=eq.${idOf(a['body'])}',
    SH,
    {'status': 'accepted'},
  );
  probe('AG6-waitlist-freeze-accept', {
    'a': idOf(a['body']),
    'b': idOf(b['body']),
    'b_http': b['http'],
    'rpc_http': accA['http'],
    'rpc_body': accA['body'],
    'patch_http': accPatch['http'],
    'patch_body': accPatch['body'],
    'a_status': idOf(a['body']) == null
        ? null
        : await row('live_reservation_requests', idOf(a['body'])!, 'status'),
    'b_status': idOf(b['body']) == null
        ? null
        : await row('live_reservation_requests', idOf(b['body'])!, 'status'),
    'open_frozen': '${accA['body']}'.contains('live_item_qty_below_reservations') &&
        '${(await row('live_reservation_requests', idOf(a['body'])!, 'status'))['status']}' != 'accepted',
  });

  // End mux leftover + fixtures
  await req('PATCH', '$url/rest/v1/lives?id=eq.d37677a1-3436-4cee-b838-02142e2737fa', SVC, {
    'status': 'ended',
    'is_active': false,
  });
  for (final id in [lid, lid2, liveId]) {
    await req('PATCH', '$url/rest/v1/lives?id=eq.$id', SVC, {
      'status': 'ended',
      'is_active': false,
    });
  }

  final f = File('tool/redteam_blind_ag_20260901T1916/probes_pass3.json');
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert({'probes': probes}));
  print('WROTE ${f.path} n=${probes.length}');
}
