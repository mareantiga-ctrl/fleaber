// ignore_for_file: avoid_print
/// RTB-B-BANK-01/02 (aguarda_confirmacao) + RT-E-P2-01 (pending stock).
/// dart run tool/sec_rtb_b_aguarda_confirmacao_pending_hostile.dart
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

String clip(Object? v, [int n = 240]) {
  final s = '$v';
  return s.length <= n ? s : s.substring(0, n);
}

bool hasBanking(dynamic body) {
  if (body is List && body.isNotEmpty) {
    final m = Map<String, dynamic>.from(body.first as Map);
    return '${m['iban'] ?? ''}'.trim().isNotEmpty ||
        '${m['mb_way'] ?? ''}'.trim().isNotEmpty;
  }
  return false;
}

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    final s = '${(body.first as Map)['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  return null;
}

String statusOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return '${(body.first as Map)['status'] ?? ''}'.toLowerCase().trim();
  }
  return '';
}

int? asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: staging only');
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

  Future<Map<String, dynamic>> rpc(
    String name,
    Map<String, dynamic> body,
    Map<String, String> h,
  ) =>
      req('POST', '$url/rest/v1/rpc/$name', h, body);

  final cleanup = <Future Function()>[];

  await req('PATCH', '$url/rest/v1/profiles?id=eq.$sellerId', SVC, {
    'external_payments_enabled': true,
    'iban': 'PT50000201231234567890154',
    'mb_way': '910000000',
  });

  // Limpar orders reveláveis desta dupla (senão o RPC mascara o assert de oráculo).
  final revealOrders = await req(
    'GET',
    '$url/rest/v1/orders?buyer_id=eq.$buyerId&seller_id=eq.$sellerId&status=in.(reservado,aguarda_confirmacao,aguarda_pagamento)&select=id',
    SVC,
  );
  if (revealOrders['body'] is List) {
    for (final row in revealOrders['body'] as List) {
      final id = '${(row as Map)['id'] ?? ''}';
      if (id.isEmpty) continue;
      await req(
        'PATCH',
        '$url/rest/v1/orders?id=eq.$id',
        SVC,
        {'status': 'cancelado'},
      );
    }
  }

  final prods = await sb.select(
    'products',
    filter: 'seller_id=eq.$sellerId&quantity=gt.0',
    limit: 1,
  );
  final pid = prods.isNotEmpty ? '${prods.first['id']}' : '';
  final price = prods.isNotEmpty ? (prods.first['price'] as num? ?? 8.2) : 8.2;
  add('fixture_product', pid.isNotEmpty, {'product_id': pid, 'price': price});

  // ---- RTB-B-BANK-01: INSERT aguarda_confirmacao ----
  final insAc = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 1,
    'price_total': price,
    'status': 'aguarda_confirmacao',
    'payment_method': 'MB WAY',
  });
  final oidAc = idOf(insAc['body']);
  final stAc = statusOf(insAc['body']);
  final bankAc = await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': sellerId},
    BH,
  );
  add(
    'BANK01_insert_aguarda_confirmacao_rewritten_no_pii',
    oidAc != null && stAc == 'reserva_pendente' && !hasBanking(bankAc['body']),
    {
      'http': insAc['http'],
      'status': stAc,
      'order_id': oidAc,
      'rpc_pii': hasBanking(bankAc['body']),
      'body': clip(insAc['text']),
    },
  );
  if (oidAc != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$oidAc', SVC);
    });
  }

  // ---- RTB-B-BANK-02: PATCH reserva_pendente → aguarda_confirmacao ----
  final insPend = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 1,
    'price_total': price,
    'status': 'reserva_pendente',
    'payment_method': 'MB WAY',
  });
  final oidPend = idOf(insPend['body']);
  if (oidPend != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$oidPend', SVC);
    });
  }
  final patchAc = await req(
    'PATCH',
    '$url/rest/v1/orders?id=eq.$oidPend',
    BH,
    {'status': 'aguarda_confirmacao'},
  );
  final chkPend = await req(
    'GET',
    '$url/rest/v1/orders?id=eq.$oidPend&select=status',
    SVC,
  );
  final stAfterPatch = statusOf(chkPend['body']);
  final bankPatch = await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': sellerId},
    BH,
  );
  add(
    'BANK02_patch_to_aguarda_confirmacao_blocked_no_pii',
    oidPend != null &&
        stAfterPatch == 'reserva_pendente' &&
        !hasBanking(bankPatch['body']),
    {
      'patch_http': patchAc['http'],
      'status': stAfterPatch,
      'rpc_pii': hasBanking(bankPatch['body']),
      'body': clip(patchAc['text']),
    },
  );

  // ---- Happy: seller accept → reservado → PII; buyer proof → aguarda_confirmacao ----
  final happyIns = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 1,
    'price_total': price,
    'status': 'reserva_pendente',
    'payment_method': 'MB WAY',
  });
  final oidHappy = idOf(happyIns['body']);
  if (oidHappy != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$oidHappy', SVC);
    });
  }
  final sellerAccept = await req(
    'PATCH',
    '$url/rest/v1/orders?id=eq.$oidHappy',
    SH,
    {'status': 'reservado'},
  );
  final chkAccept = await req(
    'GET',
    '$url/rest/v1/orders?id=eq.$oidHappy&select=status',
    SVC,
  );
  final stAccept = statusOf(chkAccept['body']);
  final bankOk = await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': sellerId},
    BH,
  );
  final proof = await req(
    'PATCH',
    '$url/rest/v1/orders?id=eq.$oidHappy',
    BH,
    {'status': 'aguarda_confirmacao'},
  );
  final chkProof = await req(
    'GET',
    '$url/rest/v1/orders?id=eq.$oidHappy&select=status',
    SVC,
  );
  final stProof = statusOf(chkProof['body']);
  final bankAfterProof = await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': sellerId},
    BH,
  );
  add(
    'HAPPY_seller_accept_banking_then_buyer_proof',
    oidHappy != null &&
        stAccept == 'reservado' &&
        hasBanking(bankOk['body']) &&
        stProof == 'aguarda_confirmacao' &&
        hasBanking(bankAfterProof['body']),
    {
      'accept_http': sellerAccept['http'],
      'accept_status': stAccept,
      'banking_after_accept': hasBanking(bankOk['body']),
      'proof_http': proof['http'],
      'proof_status': stProof,
      'banking_after_proof': hasBanking(bankAfterProof['body']),
    },
  );

  // ---- Regression: INSERT reservado still rewritten ----
  final insRes = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 1,
    'price_total': price,
    'status': 'reservado',
    'payment_method': 'MB WAY',
  });
  final oidRes = idOf(insRes['body']);
  if (oidRes != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$oidRes', SVC);
    });
  }
  add(
    'REG_insert_reservado_still_rewritten',
    oidRes != null && statusOf(insRes['body']) == 'reserva_pendente',
    {'status': statusOf(insRes['body']), 'http': insRes['http']},
  );

  // ---- RT-E-P2-01: pending qty=99 must not zero available ----
  final lives = await req(
    'GET',
    '$url/rest/v1/lives?or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&select=id,status&order=created_at.desc&limit=5',
    SVC,
  );
  String? liveId;
  String? liveItemId;
  int? availBefore;
  if (lives['body'] is List) {
    for (final row in lives['body'] as List) {
      final lid = '${(row as Map)['id']}';
      final items = await req(
        'GET',
        '$url/rest/v1/live_items?live_id=eq.$lid&select=id&limit=3',
        SVC,
      );
      if (items['body'] is! List || (items['body'] as List).isEmpty) continue;
      for (final it in items['body'] as List) {
        final iid = '${(it as Map)['id']}';
        final stock = await rpc('batata_live_item_stock', {'p_live_item_id': iid}, BH);
        final body = stock['body'];
        if (body is Map && body['ok'] == true) {
          final avail = asInt(body['available_qty']) ?? 0;
          final total = asInt(body['total_qty']) ?? 0;
          if (avail >= 1 && total >= 1) {
            liveId = lid;
            liveItemId = iid;
            availBefore = avail;
            break;
          }
        }
      }
      if (liveItemId != null) break;
    }
  }

  if (liveItemId == null || liveId == null || availBefore == null) {
    add('P2_pending_qty99_fixture', false, {
      'note': 'no live_item with available>=1; skip remaining P2 asserts',
    });
  } else {
    add('P2_pending_qty99_fixture', true, {
      'live_id': liveId,
      'live_item_id': liveItemId,
      'available_before': availBefore,
    });

    final pendIns = await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
      'live_id': liveId,
      'live_item_id': liveItemId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'requested_qty': 99,
      'status': 'accepted',
      'source': 'fleaber_live',
    });
    final rid = idOf(pendIns['body']);
    final stRes = statusOf(pendIns['body']);
    if (rid != null) {
      cleanup.add(() async {
        await req(
          'DELETE',
          '$url/rest/v1/live_reservation_requests?id=eq.$rid',
          SVC,
        );
      });
    }
    final stockAfter = await rpc(
      'batata_live_item_stock',
      {'p_live_item_id': liveItemId},
      BH,
    );
    final afterMap = stockAfter['body'] is Map
        ? Map<String, dynamic>.from(stockAfter['body'] as Map)
        : <String, dynamic>{};
    final availAfter = asInt(afterMap['available_qty']) ?? -1;
    final pendingBag = asInt(afterMap['pending_bag_qty']) ?? 0;
    add(
      'P2_pending_qty99_does_not_zero_available',
      rid != null &&
          stRes == 'pending' &&
          availAfter == availBefore &&
          availAfter > 0,
      {
        'insert_http': pendIns['http'],
        'status': stRes,
        'available_before': availBefore,
        'available_after': availAfter,
        'pending_bag_qty': pendingBag,
        'body': clip(pendIns['text']),
      },
    );

    // Seller still cannot accept qty 99
    if (rid != null) {
      final accept99 = await req(
        'PATCH',
        '$url/rest/v1/live_reservation_requests?id=eq.$rid',
        SH,
        {'status': 'accepted'},
      );
      final chkRes = await req(
        'GET',
        '$url/rest/v1/live_reservation_requests?id=eq.$rid&select=status,requested_qty',
        SVC,
      );
      final stillPending = statusOf(chkRes['body']) == 'pending' ||
          (accept99['http'] as int) >= 400;
      add(
        'P2_seller_accept_qty99_still_blocked',
        stillPending,
        {
          'patch_http': accept99['http'],
          'body': clip(accept99['text']),
          'row': clip(chkRes['text']),
        },
      );
    }
  }

  for (final c in cleanup.reversed) {
    try {
      await c();
    } catch (_) {}
  }

  final failed = results.where((r) => r['ok'] != true).length;
  final out = {
    'tag': 'rtb_b_aguarda_confirmacao_pending',
    'at': DateTime.now().toUtc().toIso8601String(),
    'pass': results.length - failed,
    'fail': failed,
    'total': results.length,
    'results': results,
  };
  final path =
      'tool/reports/sec_rtb_b_aguarda_pending_hostile_${DateTime.now().millisecondsSinceEpoch}.json';
  await Directory('tool/reports').create(recursive: true);
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('\n$failed FAIL / ${results.length} total → $path');
  exit(failed == 0 ? 0 : 1);
}
