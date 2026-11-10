// ignore_for_file: avoid_print
/// AG pass2 — fechar pontas. dart run tool/redteam_blind_ag_20260901T1916_pass2.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

const prefix = 'RTAG-20260901T1916p2';

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
  final seller2Tok = await sb.signIn(
    email: '${'RTAG-20260901T1916'.toLowerCase()}-seller2@staging.fleaber.bot',
    password: 'RTAG_Seller2_2026!x',
  );
  final helperTok = await sb.signIn(
    email: '${'RTAG-20260901T1916'.toLowerCase()}-helper@staging.fleaber.bot',
    password: 'RTAG_Helper_2026!x',
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
  final S2H = {
    'apikey': anon,
    'Authorization': 'Bearer $seller2Tok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final HH = {
    'apikey': anon,
    'Authorization': 'Bearer $helperTok',
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

  final live = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'title': '$prefix-live',
    'status': 'live',
    'is_active': true,
  });
  final liveId = idOf(live['body']);
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': '$prefix-sku',
    'price': 8,
    'quantity': 2,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final pid = idOf(prod['body']);
  final itemLo = await req('POST', '$url/rest/v1/live_items', SVC, {
    'live_id': liveId,
    'ref_code': 'P2LO',
    'title': '$prefix-lo',
    'price': 8,
    'quantity': 1,
    'status': 'available',
    'is_active': true,
    'item_kind': 'live_only',
  });
  final loId = idOf(itemLo['body']);
  final itemMp = await req('POST', '$url/rest/v1/live_items', SVC, {
    'live_id': liveId,
    'ref_code': 'P2MP',
    'title': '$prefix-mp',
    'price': 8,
    'status': 'available',
    'is_active': true,
    'item_kind': 'marketplace_product',
    'product_id': pid,
  });
  final mpId = idOf(itemMp['body']);
  probe('fixture', {'liveId': liveId, 'loId': loId, 'mpId': mpId, 'pid': pid, 'mp_http': itemMp['http'], 'mp_body': itemMp['body']});

  // Source 403 body
  final srcBad = await req('POST', '$url/rest/v1/live_reservation_requests', SH, {
    'live_id': liveId,
    'live_item_id': loId,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'requested_qty': 1,
    'status': 'accepted',
    'source': 'whatsapp',
  });
  probe('AG1-source-whatsapp-body', {'http': srcBad['http'], 'body': srcBad['body']});

  // WELL: facebook_manual pending → PATCH accepted (not exact AD convert)
  final fm = await req('POST', '$url/rest/v1/live_reservation_requests', SH, {
    'live_id': liveId,
    'live_item_id': loId,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'requested_qty': 1,
    'status': 'pending',
    'source': 'facebook_manual',
    'external_display_name': 'FB Guest',
  });
  final fmId = idOf(fm['body']);
  probe('AG1-fm-insert', {'http': fm['http'], 'id': fmId, 'status': firstMap(fm['body'])?['status']});
  if (fmId != null) {
    final acc = await req('PATCH', '$url/rest/v1/live_reservation_requests?id=eq.$fmId', SH, {
      'status': 'accepted',
    });
    final afterAcc = await row('live_reservation_requests', fmId, 'status,source,requested_qty');
    final stock = (await req('POST', '$url/rest/v1/rpc/batata_live_item_stock', BH, {
      'p_live_item_id': loId,
    }))['body'];
    probe('AG1-fm-patch-accepted-no-pi', {
      'http': acc['http'],
      'body': acc['body'],
      'after': afterAcc,
      'stock': stock,
      'open': '${afterAcc['status']}' == 'accepted' &&
          (stock is Map && (stock['available_qty'] == 0 || stock['available_qty'] == '0')),
    });
    final conv = await req('PATCH', '$url/rest/v1/live_reservation_requests?id=eq.$fmId', SH, {
      'status': 'converted',
    });
    probe('AG1-fm-patch-converted-after-accept', {
      'http': conv['http'],
      'body': conv['body'],
      'after': await row('live_reservation_requests', fmId, 'status'),
    });
  }

  // Buyer still reserves / checkout when reserved_full
  final pending2 = await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
    'live_id': liveId,
    'live_item_id': loId,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'requested_qty': 1,
    'status': 'pending',
    'source': 'fleaber_live',
  });
  probe('AG3-buyer-pending-while-reserved-full', {
    'http': pending2['http'],
    'id': idOf(pending2['body']),
    'status': firstMap(pending2['body'])?['status'],
  });
  final ensure = await req('POST', '$url/rest/v1/rpc/batata_ensure_checkout_product', BH, {
    'p_live_item_id': loId,
  });
  probe('AG3-buyer-ensure-checkout-reserved-full', {
    'http': ensure['http'],
    'body': ensure['body'],
  });
  final checkout = await req('POST', '$url/functions/v1/create-live-checkout', BH, {
    'live_item_id': loId,
    'live_id': liveId,
    'quantity': 1,
  });
  probe('AG3-create-live-checkout-reserved-full', {
    'http': checkout['http'],
    'raw': '${checkout['raw']}'.substring(0, ('${checkout['raw']}'.length).clamp(0, 500)),
  });
  final orderIns = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'live_id': liveId,
    'live_item_id': loId,
    'quantity': 1,
    'price_total': 8,
    'status': 'reserva_pendente',
  });
  probe('AG3-buyer-insert-order-reserved-full', {
    'http': orderIns['http'],
    'id': idOf(orderIns['body']),
    'body': orderIns['body'] is Map ? orderIns['body'] : firstMap(orderIns['body']),
  });

  // mark_sold seller regression
  final mk = await req('POST', '$url/rest/v1/rpc/batata_mark_live_item_sold', SH, {
    'p_live_item_id': loId,
  });
  probe('AG4-seller-mark-sold-rpc', {
    'http': mk['http'],
    'body': mk['body'],
    'item': loId == null ? null : await row('live_items', loId, 'status'),
  });

  // inflate marketplace product qty with live hold
  if (mpId != null && pid != null) {
    final inflLi = await req('PATCH', '$url/rest/v1/live_items?id=eq.$mpId', SH, {
      'quantity': 50,
    });
    final inflP = await req('PATCH', '$url/rest/v1/products?id=eq.$pid', SH, {
      'quantity': 99,
    });
    probe('AG5-inflate-marketplace-product-and-live-item', {
      'li_http': inflLi['http'],
      'li_body': inflLi['body'],
      'p_http': inflP['http'],
      'p_body': inflP['body'],
      'product': await row('products', pid, 'quantity'),
      'live_item': await row('live_items', mpId, 'quantity,item_kind'),
    });
  }

  // AG6 sequential + parallel with bodies
  final liveR = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'title': '$prefix-race',
    'status': 'live',
    'is_active': true,
  });
  final liveRId = idOf(liveR['body']);
  final itemR = await req('POST', '$url/rest/v1/live_items', SVC, {
    'live_id': liveRId,
    'ref_code': 'P2RC',
    'title': 'race',
    'price': 3,
    'quantity': 1,
    'status': 'available',
    'is_active': true,
    'item_kind': 'live_only',
  });
  final itemRId = idOf(itemR['body']);
  final ra = await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
    'live_id': liveRId,
    'live_item_id': itemRId,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'requested_qty': 1,
    'status': 'pending',
    'source': 'fleaber_live',
  });
  final seller2Id = await sb.userIdForAccessToken(seller2Tok);
  final rb = await req('POST', '$url/rest/v1/live_reservation_requests', S2H, {
    'live_id': liveRId,
    'live_item_id': itemRId,
    'buyer_id': seller2Id,
    'seller_id': sellerId,
    'requested_qty': 1,
    'status': 'pending',
    'source': 'fleaber_live',
  });
  final raId = idOf(ra['body']);
  final rbId = idOf(rb['body']);
  probe('AG6-res-create', {
    'ra_http': ra['http'],
    'rb_http': rb['http'],
    'ra': raId,
    'rb': rbId,
    'rb_body': rb['body'],
  });
  if (raId != null && rbId != null) {
    final a1 = await req('POST', '$url/rest/v1/rpc/batata_process_live_reservation_request', SH, {
      'p_request_id': raId,
      'p_action': 'accept',
    });
    final b1 = await req('POST', '$url/rest/v1/rpc/batata_process_live_reservation_request', SH, {
      'p_request_id': rbId,
      'p_action': 'accept',
    });
    probe('AG6-sequential-accept-stock1', {
      'a_http': a1['http'],
      'a_body': a1['body'],
      'b_http': b1['http'],
      'b_body': b1['body'],
      'a_status': await row('live_reservation_requests', raId, 'status'),
      'b_status': await row('live_reservation_requests', rbId, 'status'),
    });
  }

  // mux hijack with title
  final mux = await req('POST', '$url/functions/v1/create-mux-live', S2H, {
    'live_id': liveId,
    'title': 'hijack mux',
  });
  probe('AG7-create-mux-alien-with-title', {
    'http': mux['http'],
    'raw': '${mux['raw']}'.substring(0, ('${mux['raw']}'.length).clamp(0, 600)),
  });
  final livesOk = await req(
    'GET',
    '$url/rest/v1/lives?id=eq.$liveId&select=id,status,is_active,mux_playback_id,title',
    BH,
  );
  probe('AG7-buyer-select-live-no-stream-key', {
    'http': livesOk['http'],
    'body': livesOk['body'],
  });

  // helper_manual consume
  final hm = await req('POST', '$url/rest/v1/live_reservation_requests', HH, {
    'live_id': liveId,
    'live_item_id': loId,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'requested_qty': 1,
    'status': 'pending',
    'source': 'helper_manual',
  });
  probe('AG2-helper-manual-insert', {
    'http': hm['http'],
    'body': hm['body'],
    'id': idOf(hm['body']),
  });

  // wallet
  final wal = await req(
    'GET',
    '$url/rest/v1/wallets?id=eq.$sellerId&select=id,balance',
    SVC,
  );
  probe('AG8-wallet', {'http': wal['http'], 'body': wal['body']});

  // JWT stamp PI on new order
  final o = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'status': 'reserva_pendente',
    'price_total': 8,
    'quantity': 1,
    'payment_method': 'mbway',
    'live_item_id': loId,
    'live_id': liveId,
  });
  final oid = idOf(o['body']);
  probe('AG8-order-insert', {'http': o['http'], 'id': oid, 'status': firstMap(o['body'])?['status']});
  if (oid != null) {
    final p1 = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {
      'status': 'pago',
    });
    final p2 = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {
      'stripe_payment_intent_id': 'pi_fake',
      'amount_paid_cents': 800,
    });
    probe('AG8-seller-stamp-pago-pi', {
      'pago_http': p1['http'],
      'pago_body': p1['body'],
      'pi_http': p2['http'],
      'pi_body': p2['body'],
      'after': await row('orders', oid, 'status,amount_paid_cents,stripe_payment_intent_id'),
    });
  }

  await req('PATCH', '$url/rest/v1/lives?id=eq.$liveId', SVC, {'status': 'ended', 'is_active': false});
  await req('PATCH', '$url/rest/v1/lives?id=eq.$liveRId', SVC, {'status': 'ended', 'is_active': false});

  final f = File('tool/redteam_blind_ag_20260901T1916/probes_pass2.json');
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert({'probes': probes}));
  print('WROTE ${f.path} n=${probes.length}');
}
