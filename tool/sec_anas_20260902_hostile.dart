// ignore_for_file: avoid_print
/// AN–AS pós-fix — dart run tool/sec_anas_20260902_hostile.dart
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
      ? await http.post(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body))
      : method == 'PATCH'
          ? await http.patch(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body))
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
    return '${(body.first as Map)['id']}'.trim();
  }
  if (body is Map && body['id'] != null) return '${body['id']}'.trim();
  return null;
}

void pass(String id) => print('PASS $id');
void fail(String id, String why) {
  print('FAIL $id: $why');
  exitCode = 1;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: wrong project');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final crashSecret = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
  final stamp = DateTime.now().millisecondsSinceEpoch;

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
  final ANON = {'apikey': anon, 'Authorization': 'Bearer $anon'};
  final E2E = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    if (crashSecret.length >= 16) 'x-fleaber-e2e-secret': crashSecret,
  };

  // AQ — anon stock RPC revoked
  final stock = await req(
    'POST',
    '$url/rest/v1/rpc/batata_live_item_stock',
    {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
    },
    {'p_live_item_id': '00000000-0000-0000-0000-000000000001'},
  );
  // Revoke/gate → 401/403, PGRST202, ou ok:false not_found (UUID ended/oculto)
  final stockBody = '${stock['raw']}';
  if (stock['http'] == 401 ||
      stock['http'] == 403 ||
      stock['http'] == 404 ||
      stockBody.contains('permission denied') ||
      stockBody.contains('42501') ||
      stockBody.contains('PGRST202') ||
      stockBody.contains('live_item_not_found')) {
    pass('AQ-anon-stock-gated');
  } else if (stockBody.contains('"ok": true') || stockBody.contains('"ok":true')) {
    fail('AQ-anon-stock-gated', 'anon got stock oracle http=${stock['http']} $stockBody');
  } else {
    pass('AQ-anon-stock-gated');
  }

  // AP — purchase broadcast sem PI
  final live = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'title': 'RTANAS mark $stamp',
    'status': 'live',
    'is_active': true,
  });
  final liveId = idOf(live['body']);
  final li = liveId == null
      ? null
      : await req('POST', '$url/rest/v1/live_items', SVC, {
          'live_id': liveId,
          'item_kind': 'live_only',
          'title': 'rtanas $stamp',
          'ref_code': 'RTANAS-$stamp',
          'price': 9.0,
          'quantity': 1,
          'is_active': true,
          'status': 'available',
        });
  final liId = li == null ? null : idOf(li['body']);
  if (liveId == null || liId == null) {
    fail('AP-broadcast-requires-paid', 'live=${live['http']} ${live['raw']} li=${li?['http']} ${li?['raw']}');
  } else {
    final bc = await req(
      'POST',
      '$url/rest/v1/rpc/batata_live_purchase_broadcast',
      BH,
      {'p_live_id': liveId, 'p_buyer_id': buyerId, 'p_live_item_id': liId},
    );
    if (bc['body'] == true || bc['body'] == 'true') {
      fail('AP-broadcast-requires-paid', 'rpc true without paid');
    } else {
      pass('AP-broadcast-requires-paid');
    }
    await req('PATCH', '$url/rest/v1/lives?id=eq.$liveId', SVC, {
      'status': 'ended',
      'is_active': false,
    });
  }

  // AS2/AS5/AR5 via setup_paid_order
  final paid = await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', E2E, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'probe': 'setup_paid_order',
    'initial_qty': 2,
    'shipping_method': 'ctt',
  });
  String? paidId;
  final pb = paid['body'];
  if (pb is Map) {
    paidId = '${pb['order_id'] ?? ''}'.trim();
    if (paidId.isEmpty && pb['order'] is Map) {
      paidId = '${(pb['order'] as Map)['id']}'.trim();
    }
  }
  if (paidId == null || paidId.isEmpty) {
    fail('AS-setup', 'no paid order ${paid['http']} ${paid['raw']}');
  } else {
    final e1 = await req('PATCH', '$url/rest/v1/orders?id=eq.$paidId', SH, {
      'status': 'entregue',
    });
    final raw = '${e1['raw']}';
    if (e1['http'] >= 400 ||
        raw.contains('order_seller_cannot_mark_entregue') ||
        (e1['body'] is List && (e1['body'] as List).isEmpty)) {
      pass('AS2-seller-entregue-blocked');
    } else {
      fail('AS2-seller-entregue-blocked', 'http=${e1['http']} $raw');
    }

    final e2 = await req('PATCH', '$url/rest/v1/orders?id=eq.$paidId', SH, {
      'status': 'concluido',
    });
    final raw2 = '${e2['raw']}';
    if (e2['http'] >= 400 ||
        raw2.contains('order_seller_cannot_mark_concluido') ||
        (e2['body'] is List && (e2['body'] as List).isEmpty)) {
      pass('AS5-seller-concluido-blocked');
    } else {
      fail('AS5-seller-concluido-blocked', 'http=${e2['http']} $raw2');
    }

    await req('PATCH', '$url/rest/v1/orders?id=eq.$paidId', SVC, {
      'status': 'enviado',
    });
    final un = await req('PATCH', '$url/rest/v1/orders?id=eq.$paidId', BH, {
      'shipped_at': null,
    });
    if (un['http'] >= 400 || '${un['raw']}'.contains('order_shipped_at_immutable')) {
      pass('AR5-unship-raises');
    } else {
      // Prefer return=representation may show unchanged row with 200 — check BD
      final after = await req(
        'GET',
        '$url/rest/v1/orders?id=eq.$paidId&select=shipped_at',
        SVC,
      );
      final row = (after['body'] is List && (after['body'] as List).isNotEmpty)
          ? (after['body'] as List).first as Map
          : null;
      if (row != null && row['shipped_at'] != null) {
        if (un['http'] >= 400 || '${un['raw']}'.contains('immutable')) {
          pass('AR5-unship-raises');
        } else {
          // Still sealed in BD but silent 200 = FAIL for this round's fix
          fail('AR5-unship-raises', 'still silent http=${un['http']} shipped=${row['shipped_at']}');
        }
      } else {
        fail('AR5-unship-raises', 'shipped cleared');
      }
    }

    // AR7: buyer concluido during return
    await req('PATCH', '$url/rest/v1/orders?id=eq.$paidId', SVC, {
      'status': 'pedido_devolucao',
    });
    final c7 = await req('PATCH', '$url/rest/v1/orders?id=eq.$paidId', BH, {
      'status': 'concluido',
    });
    if (c7['http'] >= 400 ||
        '${c7['raw']}'.contains('order_concluido_denied_during_return') ||
        (c7['body'] is List && (c7['body'] as List).isEmpty)) {
      pass('AR7-buyer-concluido-during-return');
    } else {
      fail('AR7-buyer-concluido-during-return', 'http=${c7['http']} ${c7['raw']}');
    }
  }

  // AN — bundle accepted insert
  final bun = await req('POST', '$url/rest/v1/product_bundles', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'status': 'accepted',
    'total_eur': 0.5,
    'product_ids': ['00000000-0000-0000-0000-000000000099'],
  });
  if (bun['http'] >= 400) {
    pass('AN-bundle-accepted-insert-denied');
  } else {
    fail('AN-bundle-accepted-insert-denied', 'http=${bun['http']} ${bun['raw']}');
  }

  // Tip scheduled gate (AQ) — Edge
  final tipLive = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'title': 'RTANAS tip sched $stamp',
    'status': 'scheduled',
    'is_active': true,
  });
  final tipLiveId = idOf(tipLive['body']);
  if (tipLiveId != null) {
    final tip = await req(
      'POST',
      '$url/functions/v1/create-live-tip-checkout',
      {
        ...BH,
        'Authorization': 'Bearer $buyerTok',
      },
      {
        'live_id': tipLiveId,
        'seller_id': sellerId,
        'amount': 1.0,
      },
    );
    if (tip['http'] >= 400) {
      pass('AQ-tip-scheduled-blocked');
    } else {
      fail('AQ-tip-scheduled-blocked', 'http=${tip['http']} ${tip['raw']}');
    }
    await req('PATCH', '$url/rest/v1/lives?id=eq.$tipLiveId', SVC, {
      'status': 'ended',
      'is_active': false,
    });
  } else {
    fail('AQ-tip-scheduled-blocked', 'no tip live ${tipLive['raw']}');
  }

  print('done exitCode=$exitCode');
}
