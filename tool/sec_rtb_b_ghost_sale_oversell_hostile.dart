// ignore_for_file: avoid_print
/// RTB-B ghost sale P1 + F-RTF oversell refund (e2e settle) hostile.
/// dart run tool/sec_rtb_b_ghost_sale_oversell_hostile.dart
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
    return s.isEmpty ? null : s;
  }
  return null;
}

String statusOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return '${(body.first as Map)['status'] ?? ''}'.toLowerCase().trim();
  }
  return '';
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT staging only');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final e2eSecret = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
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
    if (e2eSecret.length >= 16) 'x-fleaber-e2e-secret': e2eSecret,
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final cleanup = <Future Function()>[];
  final stamp = DateTime.now().millisecondsSinceEpoch;

  // Produto do seller
  final prodIns = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'Ghost sale probe $stamp',
    'price': 7.5,
    'quantity': 2,
    'ref_code': 'GHOST-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = idOf(prodIns['body']);
  add('fixture_product', pid != null, {'product_id': pid, 'http': prodIns['http']});
  if (pid != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid', SVC);
      await req('DELETE', '$url/rest/v1/product_offers?product_id=eq.$pid', SVC);
      await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
    });
  }

  // ---- RTB-B-P1-01: seller inventa buyer sem oferta ----
  final ghost = await req('POST', '$url/rest/v1/orders', SH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'status': 'pendente',
    'price_total': 7.5,
    'quantity': 1,
    'payment_method': 'mbway',
  });
  final ghostOid = idOf(ghost['body']);
  final ghostBlocked = (ghost['http'] as int) >= 400 && ghostOid == null;
  add(
    'P1_01_seller_ghost_insert_blocked',
    ghostBlocked,
    {
      'http': ghost['http'],
      'order_id': ghostOid,
      'body': clip(ghost['text']),
    },
  );
  if (ghostOid != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$ghostOid', SVC);
    });
  }

  // ---- Buyer INSERT self ainda OK ----
  final buyerOrd = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'price_total': 7.5,
    'quantity': 1,
    'payment_method': 'MB WAY',
  });
  final buyerOid = idOf(buyerOrd['body']);
  add(
    'HAPPY_buyer_insert_ok',
    buyerOid != null && (buyerOrd['http'] as int) < 300,
    {'http': buyerOrd['http'], 'order_id': buyerOid, 'status': statusOf(buyerOrd['body'])},
  );
  if (buyerOid != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$buyerOid', SVC);
    });
  }

  // ---- Happy: proposta aceite → seller INSERT com product_offer_id ----
  final offerIns = await req('POST', '$url/rest/v1/product_offers', BH, {
    'product_id': pid,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 6.0,
    'offered_by': 'buyer',
    'status': 'pending',
    'expires_at': DateTime.now()
        .toUtc()
        .add(const Duration(hours: 48))
        .toIso8601String(),
  });
  final offerId = idOf(offerIns['body']);
  add('fixture_offer_pending', offerId != null, {
    'http': offerIns['http'],
    'offer_id': offerId,
    'body': clip(offerIns['text']),
  });
  if (offerId != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/product_offers?id=eq.$offerId', SVC);
    });
    final accept = await req(
      'PATCH',
      '$url/rest/v1/product_offers?id=eq.$offerId',
      SH,
      {
        'status': 'accepted',
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    final offerChk = await req(
      'GET',
      '$url/rest/v1/product_offers?id=eq.$offerId&select=status,responded_at',
      SVC,
    );
    final stOffer = statusOf(offerChk['body']);
    add('fixture_offer_accepted', stOffer == 'accepted', {
      'patch_http': accept['http'],
      'status': stOffer,
      'body': clip(accept['text']),
    });

    if (stOffer == 'accepted') {
      final sellerOfferOrd = await req('POST', '$url/rest/v1/orders', SH, {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pid,
        'product_offer_id': offerId,
        'status': 'reservado',
        'price_total': 6.0,
        'quantity': 1,
        'payment_method': 'Proposta de preço aceite',
        'is_reservation': true,
      });
      final offerOid = idOf(sellerOfferOrd['body']);
      add(
        'HAPPY_seller_insert_with_accepted_offer',
        offerOid != null && (sellerOfferOrd['http'] as int) < 300,
        {
          'http': sellerOfferOrd['http'],
          'order_id': offerOid,
          'status': statusOf(sellerOfferOrd['body']),
          'body': clip(sellerOfferOrd['text']),
        },
      );
      if (offerOid != null) {
        cleanup.add(() async {
          await req('DELETE', '$url/rest/v1/orders?id=eq.$offerOid', SVC);
        });
      }
    }

    final revGhost = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': ghostOid ?? '00000000-0000-0000-0000-000000000001',
      'target_id': sellerId,
      'buyer_id': buyerId,
      'stars': 5,
      'author_role': 'comprador',
      'target_type': 'seller',
      'comment': 'forced-sale-review-blocked',
    });
    add(
      'P1_02_review_without_ghost_order_blocked',
      (revGhost['http'] as int) >= 400,
      {'http': revGhost['http'], 'body': clip(revGhost['text'])},
    );
  }

  // ---- F-RTF: e2e dual PI oversell → refund ----
  final oversell = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {'buyer_id': buyerId, 'seller_id': sellerId},
  );
  Map<String, dynamic> ovBody = {};
  try {
    ovBody = Map<String, dynamic>.from(jsonDecode(oversell['text'] as String) as Map);
  } catch (_) {}
  final checks = ovBody['checks'] is Map
      ? Map<String, dynamic>.from(ovBody['checks'] as Map)
      : <String, dynamic>{};
  add(
    'F_RTF_e2e_oversell_refund_settle',
    oversell['http'] == 200 &&
        ovBody['ok'] == true &&
        checks['refund_created'] == true &&
        checks['settle_b_oversell'] == true,
    {
      'http': oversell['http'],
      'ok': ovBody['ok'],
      'checks': {
        'refund_created': checks['refund_created'],
        'settle_b_oversell': checks['settle_b_oversell'],
        'loser_cancelado': checks['loser_cancelado'],
        'winner_order_pago': checks['winner_order_pago'],
      },
    },
  );

  for (final c in cleanup.reversed) {
    try {
      await c();
    } catch (_) {}
  }

  final failed = results.where((r) => r['ok'] != true).length;
  final out = {
    'tag': 'rtb_b_ghost_sale_oversell',
    'at': DateTime.now().toUtc().toIso8601String(),
    'pass': results.length - failed,
    'fail': failed,
    'total': results.length,
    'results': results,
  };
  final path =
      'tool/reports/sec_rtb_b_ghost_oversell_hostile_${DateTime.now().millisecondsSinceEpoch}.json';
  await Directory('tool/reports').create(recursive: true);
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('\n$failed FAIL / ${results.length} total → $path');
  exit(failed == 0 ? 0 : 1);
}
