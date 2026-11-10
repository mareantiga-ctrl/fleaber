// ignore_for_file: avoid_print
/// Blind E 1810 — dart run tool/sec_blind_e_1810_hostile.dart
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
  final AH = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
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

  // ---- P1: dead product cannot hold ----
  final dead = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'E6 dead $stamp',
    'price': 6.0,
    'quantity': 2,
    'ref_code': 'E6D-$stamp',
    'list_on_marketplace': false,
    'is_sold': true,
    'image_urls': <String>[],
  });
  final deadId = idOf(dead['body']);
  add('fixture_dead', deadId != null, {'id': deadId});

  final hold = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': deadId,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 6.0,
    'shipping_method': 'mao',
    'payment_method': 'Pagamento na app',
  });
  add(
    'P1_dead_hold_blocked',
    (hold['http'] as int) >= 400,
    {'http': hold['http'], 'body': hold['body']},
  );

  // Unlist but not sold, qty>0, no live → also blocked
  final unlist = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'E6 unlist $stamp',
    'price': 7.0,
    'quantity': 2,
    'ref_code': 'E6U-$stamp',
    'list_on_marketplace': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final unlistId = idOf(unlist['body']);
  final hold2 = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': unlistId,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 7.0,
    'shipping_method': 'mao',
    'payment_method': 'Pagamento na app',
  });
  add(
    'P1_unlist_hold_blocked',
    (hold2['http'] as int) >= 400,
    {'http': hold2['http'], 'body': hold2['body']},
  );

  // Listed alive still works
  final liveP = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'E6 ok $stamp',
    'price': 8.0,
    'quantity': 2,
    'ref_code': 'E6OK-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final okPid = idOf(liveP['body']);
  final holdOk = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': okPid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 8.0,
    'shipping_method': 'mao',
    'payment_method': 'Pagamento na app',
  });
  final okOid = idOf(holdOk['body']);
  add('listed_hold_ok', okOid != null, {
    'http': holdOk['http'],
    'id': okOid,
  });

  // ---- P2: stranger cannot read dead unlisted (unless shadow) ----
  // Create second buyer via signup is heavy — use seller reading is own OK;
  // buyer reads dead: should fail if no live shadow
  final readDead = await req(
    'GET',
    '$url/rest/v1/products?id=eq.$deadId&select=id,title,is_sold,list_on_marketplace',
    BH,
  );
  final deadRows = readDead['body'] is List ? (readDead['body'] as List).length : -1;
  add(
    'P2_buyer_cannot_read_dead_unlist',
    deadRows == 0 || (readDead['http'] as int) >= 400,
    {'http': readDead['http'], 'rows': deadRows, 'body': readDead['body']},
  );

  // ---- P2: bundle self-accept ----
  if (okPid != null) {
    final bundle = await req('POST', '$url/rest/v1/product_bundles', BH, {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'product_ids': [okPid],
      'status': 'pending',
      'total_eur': 8.0,
      'subtotal_eur': 8.0,
    });
    final bid = idOf(bundle['body']);
    add('fixture_bundle', bid != null, {
      'http': bundle['http'],
      'id': bid,
      'body': bundle['body'],
    });
    if (bid != null) {
      final self = await req(
        'PATCH',
        '$url/rest/v1/product_bundles?id=eq.$bid',
        BH,
        {'status': 'accepted', 'total_eur': 0.50},
      );
      final after = firstMap((await req(
        'GET',
        '$url/rest/v1/product_bundles?id=eq.$bid&select=status,total_eur',
        SVC,
      ))['body']);
      final blocked = '${after?['status']}' != 'accepted' ||
          (self['http'] as int) >= 400;
      add('P2_bundle_self_accept_blocked', blocked, {
        'http': self['http'],
        'status': after?['status'],
        'total': after?['total_eur'],
        'body': self['body'],
      });

      final sellerAcc = await req(
        'PATCH',
        '$url/rest/v1/product_bundles?id=eq.$bid',
        SH,
        {'status': 'accepted'},
      );
      final afterS = firstMap((await req(
        'GET',
        '$url/rest/v1/product_bundles?id=eq.$bid&select=status',
        SVC,
      ))['body']);
      add('seller_accept_bundle_ok', '${afterS?['status']}' == 'accepted', {
        'http': sellerAcc['http'],
        'status': afterS?['status'],
      });
      await req('DELETE', '$url/rest/v1/product_bundles?id=eq.$bid', SVC);
    }
  }

  // ---- P3: discovery no unpublished ----
  final disc = await req(
    'GET',
    '$url/rest/v1/hub_profiles_discovery_public?hub_published=eq.false&select=id,hub_published,is_live&limit=5',
    AH,
  );
  var badUnpub = 0;
  if (disc['body'] is List) {
    for (final row in disc['body'] as List) {
      if (row is Map &&
          row['hub_published'] == false &&
          row['is_live'] != true) {
        badUnpub++;
      }
    }
  }
  add('P3_discovery_no_unpublished', badUnpub == 0, {
    'http': disc['http'],
    'bad': badUnpub,
  });

  // ---- P3: anon admin resolve ----
  final adm = await req(
    'POST',
    '$url/rest/v1/rpc/batata_admin_resolve_dispute',
    AH,
    {
      'p_dispute_id': '00000000-0000-0000-0000-000000000001',
      'p_resolution': 'x',
      'p_note': 'y',
    },
  );
  add(
    'P3_anon_admin_resolve_denied',
    (adm['http'] as int) >= 400,
    {'http': adm['http'], 'body': adm['body']},
  );

  if (okOid != null) {
    await req('DELETE', '$url/rest/v1/orders?id=eq.$okOid', SVC);
  }
  for (final id in [deadId, unlistId, okPid]) {
    if (id != null) {
      await req('DELETE', '$url/rest/v1/products?id=eq.$id', SVC);
    }
  }

  final failed = results.where((r) => r['ok'] != true).length;
  final out =
      'tool/reports/sec_blind_e_1810_hostile_$stamp.json';
  await File(out).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'stamp': stamp,
      'pass': results.length - failed,
      'fail': failed,
      'total': results.length,
      'results': results,
    }),
  );
  stdout.writeln('Wrote $out (${results.length - failed}/${results.length})');
  exit(failed == 0 ? 0 : 1);
}
