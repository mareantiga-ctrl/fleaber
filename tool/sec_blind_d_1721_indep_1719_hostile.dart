// ignore_for_file: avoid_print
/// Blind D 1721 + Indep 1719 — dart run tool/sec_blind_d_1721_indep_1719_hostile.dart
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
      ? await http.post(
          Uri.parse(u),
          headers: h,
          body: body == null ? null : jsonEncode(body),
        )
      : method == 'PATCH'
          ? await http.patch(
              Uri.parse(u),
              headers: h,
              body: body == null ? null : jsonEncode(body),
            )
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
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT staging');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final crashSecret = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
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
  final E2E = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    if (crashSecret.length >= 16) 'x-fleaber-e2e-secret': crashSecret,
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;

  // ---- RT1719-20: buyer cannot mutate seller offer amount ----
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'RT1719 $stamp',
    'price': 25.0,
    'quantity': 5,
    'ref_code': 'RT1719-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = idOf(prod['body']);
  add('fixture_product', pid != null, {'id': pid});

  final offer = await req('POST', '$url/rest/v1/product_offers', SH, {
    'product_id': pid,
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'offered_by': 'seller',
    'amount': 20.0,
    'status': 'pending',
  });
  final offerId = idOf(offer['body']);
  add('fixture_offer', offerId != null, {'id': offerId, 'http': offer['http']});

  final mut = await req(
    'PATCH',
    '$url/rest/v1/product_offers?id=eq.$offerId',
    BH,
    {'amount': 0.50},
  );
  final mutHttp = mut['http'] as int;
  final afterMut = await req(
    'GET',
    '$url/rest/v1/product_offers?id=eq.$offerId&select=amount,status',
    SVC,
  );
  final am = firstMap(afterMut['body']);
  final amountOk =
      mutHttp >= 400 || (am != null && (am['amount'] as num).toDouble() >= 19.0);
  add('P1_offer_amount_immutable', amountOk, {
    'http': mutHttp,
    'amount': am?['amount'],
    'body': mut['body'],
  });

  // ---- D1 early confirm: carrier pago → concluido blocked ----
  final paidCarrier = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'probe': 'setup_paid_order',
      'initial_qty': 2,
      'shipping_method': 'ctt',
    },
  );
  final carrierOid = idOf(paidCarrier['body']) ??
      '${(paidCarrier['body'] is Map) ? (paidCarrier['body'] as Map)['order_id'] : ''}';
  String? cOid = carrierOid.trim().isEmpty ? null : carrierOid.trim();
  if (cOid == null && paidCarrier['body'] is Map) {
    final m = paidCarrier['body'] as Map;
    final o = '${m['order_id'] ?? m['id'] ?? ''}'.trim();
    cOid = o.isEmpty ? null : o;
  }
  add('fixture_paid_carrier', cOid != null, {
    'http': paidCarrier['http'],
    'body': paidCarrier['body'],
  });

  if (cOid != null) {
    await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$cOid',
      SVC,
      {'shipping_method': 'ctt'},
    );
    final early = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$cOid',
      BH,
      {'status': 'concluido'},
    );
    final st = await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$cOid&select=status,wallet_release_processed_at',
      SVC,
    );
    final row = firstMap(st['body']);
    final blocked = '${row?['status']}' == 'pago' ||
        (early['http'] as int) >= 400;
    add('P1_early_confirm_carrier_blocked', blocked, {
      'http': early['http'],
      'status': row?['status'],
      'body': early['body'],
    });

    // Seller ship then buyer concluido OK
    await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$cOid',
      SH,
      {'status': 'enviado'},
    );
    final okConfirm = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$cOid',
      BH,
      {'status': 'concluido'},
    );
    final st2 = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$cOid&select=status',
      SVC,
    ))['body']);
    add('P1_confirm_after_ship_ok', '${st2?['status']}' == 'concluido', {
      'http': okConfirm['http'],
      'status': st2?['status'],
    });

    // ---- Dispute: seller cannot close ----
    final disp = await req('POST', '$url/rest/v1/order_disputes', BH, {
      'order_id': cOid,
      'buyer_id': buyerId,
      'reason': 'outro',
      'description': 'hostile D1 $stamp',
      'status': 'aberta',
    });
    final did = idOf(disp['body']);
    add('fixture_dispute', did != null, {
      'http': disp['http'],
      'id': did,
      'body': disp['body'],
    });

    if (did != null) {
      final sellerClose = await req(
        'PATCH',
        '$url/rest/v1/order_disputes?id=eq.$did',
        SH,
        {'status': 'resolvida', 'buyer_decision': 'cancelled'},
      );
      final dAfter = firstMap((await req(
        'GET',
        '$url/rest/v1/order_disputes?id=eq.$did&select=status',
        SVC,
      ))['body']);
      final sellerBlocked = '${dAfter?['status']}' == 'aberta' ||
          (sellerClose['http'] as int) >= 400;
      add('P1_seller_cannot_close_dispute', sellerBlocked, {
        'http': sellerClose['http'],
        'status': dAfter?['status'],
        'body': sellerClose['body'],
      });

      // Reopen blocked
      final reopen = await req('POST', '$url/rest/v1/order_disputes', BH, {
        'order_id': cOid,
        'buyer_id': buyerId,
        'reason': 'outro',
        'description': 'reopen $stamp',
        'status': 'aberta',
      });
      add(
        'P2_dispute_reopen_blocked',
        (reopen['http'] as int) >= 400,
        {'http': reopen['http'], 'body': reopen['body']},
      );

      // Buyer can close
      final buyerClose = await req(
        'PATCH',
        '$url/rest/v1/order_disputes?id=eq.$did',
        BH,
        {'status': 'resolvida'},
      );
      final d2 = firstMap((await req(
        'GET',
        '$url/rest/v1/order_disputes?id=eq.$did&select=status',
        SVC,
      ))['body']);
      add('buyer_close_dispute_ok', '${d2?['status']}' == 'resolvida', {
        'http': buyerClose['http'],
        'status': d2?['status'],
      });
    }
  }

  // ---- Hand: pago → concluido still allowed ----
  final paidHand = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'probe': 'setup_paid_order',
      'initial_qty': 2,
      'shipping_method': 'mao',
    },
  );
  String? hOid;
  if (paidHand['body'] is Map) {
    final m = paidHand['body'] as Map;
    final o = '${m['order_id'] ?? m['id'] ?? ''}'.trim();
    hOid = o.isEmpty ? null : o;
  }
  if (hOid != null) {
    await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$hOid',
      SVC,
      {'shipping_method': 'mao'},
    );
    final handConfirm = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$hOid',
      BH,
      {'status': 'concluido'},
    );
    final hs = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$hOid&select=status',
      SVC,
    ))['body']);
    add('hand_pago_to_concluido_ok', '${hs?['status']}' == 'concluido', {
      'http': handConfirm['http'],
      'status': hs?['status'],
      'body': handConfirm['body'],
    });
  } else {
    add('hand_pago_to_concluido_ok', false, {
      'http': paidHand['http'],
      'body': paidHand['body'],
    });
  }

  // ---- P3 reservation qty clamp (live do seller lab) ----
  final items = await req(
    'GET',
    '$url/rest/v1/live_items?live_id=eq.06e42f26-62aa-442d-99e3-f0e365c570da&select=id,live_id,quantity&limit=1',
    SVC,
  );
  final itemRow = firstMap(items['body']);
  final itemId = itemRow == null ? null : '${itemRow['id']}'.trim();
  const liveId = '06e42f26-62aa-442d-99e3-f0e365c570da';
  if (itemId != null && itemId.isNotEmpty) {
    final res = await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
      'live_id': liveId,
      'live_item_id': itemId,
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'requested_qty': 99,
      'status': 'accepted',
      'source': 'fleaber_live',
      'external_display_name': 'P3clamp $stamp',
    });
    final rr = firstMap(res['body']);
    final qty = rr == null ? null : rr['requested_qty'];
    final qtyN = qty is num ? qty.toInt() : int.tryParse('$qty');
    add(
      'P3_reservation_qty_clamped',
      qtyN != null && qtyN <= 20 && '${rr?['status']}' == 'pending',
      {
        'http': res['http'],
        'qty': qtyN,
        'status': rr?['status'],
        'body': res['body'],
      },
    );
    final rid = idOf(res['body']);
    if (rid != null) {
      await req(
        'DELETE',
        '$url/rest/v1/live_reservation_requests?id=eq.$rid',
        SVC,
      );
    }
  } else {
    add('P3_reservation_qty_clamped', false, {
      'reason': 'no live_item',
      'body': items['body'],
    });
  }

  if (pid != null) {
    await req('DELETE', '$url/rest/v1/product_offers?product_id=eq.$pid', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
  }

  final failed = results.where((r) => r['ok'] != true).length;
  final outPath =
      'tool/reports/sec_blind_d_1721_indep_1719_hostile_$stamp.json';
  await File(outPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'stamp': stamp,
      'pass': results.length - failed,
      'fail': failed,
      'total': results.length,
      'results': results,
    }),
  );
  stdout.writeln(
    'Wrote $outPath (${results.length - failed}/${results.length})',
  );
  exit(failed == 0 ? 0 : 1);
}
