// ignore_for_file: avoid_print
/// POS_DBDG DH–DM — dart run tool/sec_dhdm_20260906_hostile.dart
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
  final client = http.Client();
  try {
    late http.Response r;
    final uri = Uri.parse(u);
    if (method == 'POST') {
      r = await client.post(uri,
          headers: h, body: body == null ? null : jsonEncode(body));
    } else if (method == 'GET') {
      r = await client.get(uri, headers: h);
    } else {
      r = await client.patch(uri,
          headers: h, body: body == null ? null : jsonEncode(body));
    }
    dynamic p;
    try {
      p = r.body.isEmpty ? null : jsonDecode(r.body);
    } catch (_) {
      p = r.body;
    }
    return {'http': r.statusCode, 'body': p, 'raw': r.body};
  } finally {
    client.close();
  }
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
    stderr.writeln('ABORT');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final buyerId = await sb.userIdForAccessToken(buyerTok);
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final stamp = DateTime.now().millisecondsSinceEpoch;

  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final ANON = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
  };
  final SH = {
    'apikey': anon,
    'Authorization': 'Bearer $sellerTok',
    'Content-Type': 'application/json',
  };

  Future<bool> off(String pm) async {
    final r = await req(
      'POST',
      '$url/rest/v1/rpc/batata_is_off_platform_payment',
      SVC,
      {'p_method': pm},
    );
    return r['body'] == true;
  }

  // --- DH P1-2 wraps ---
  for (final pm in [
    'mb way x',
    'xxmbway',
    'via mb way',
    'transferencia extra',
    'mb way',
    'mbωay',
  ]) {
    await off(pm)
        ? pass('dh-off-$pm')
        : fail('dh-off-$pm', 'expected true');
  }
  await off('Pagamento na App')
      ? fail('dh-app-false', 'App marked off')
      : pass('dh-app-ok');
  await off('card') ? fail('dh-card-false', 'card off') : pass('dh-card-ok');

  // --- Regressão DBDG unicode ---
  await off('𝗺𝗯𝘄𝗮𝘆') ? pass('reg-math') : fail('reg-math', 'false');
  await off('ⲙbway') ? pass('reg-coptic') : fail('reg-coptic', 'false');

  // --- DM P2-1 Hub hold ---
  // Ensure seller hub published
  await req('POST', '$url/rest/v1/rpc/batata_publish_hub', SH, {
    'p_publish': true,
  });

  final prodIns = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'dhdm-hub-$stamp',
    'price': 9.9,
    'quantity': 1,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  String? pid;
  if (prodIns['body'] is List && (prodIns['body'] as List).isNotEmpty) {
    pid = '${(prodIns['body'] as List).first['id']}';
  } else if (prodIns['body'] is Map) {
    pid = '${(prodIns['body'] as Map)['id']}';
  }
  if (pid == null) {
    fail('dm-prod', '${prodIns['raw']}');
  } else {
    final hubBefore = await req(
      'GET',
      '$url/rest/v1/hub_products_public?id=eq.$pid&select=id',
      ANON,
    );
    final nBefore = hubBefore['body'] is List
        ? (hubBefore['body'] as List).length
        : -1;
    nBefore == 1
        ? pass('dm-hub-listed')
        : fail('dm-hub-listed', 'n=$nBefore ${hubBefore['raw']}');

    final live = await req('POST', '$url/rest/v1/lives', SVC, {
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'status': 'live',
      'is_active': true,
      'title': 'dhdm-$stamp',
    });
    String? liveId;
    if (live['body'] is List && (live['body'] as List).isNotEmpty) {
      liveId = '${(live['body'] as List).first['id']}';
    } else if (live['body'] is Map) {
      liveId = '${(live['body'] as Map)['id']}';
    }

    String? liId;
    if (liveId != null) {
      final li = await req('POST', '$url/rest/v1/live_items', SVC, {
        'live_id': liveId,
        'product_id': pid,
        'checkout_product_id': pid,
        'title': 'dhdm-item-$stamp',
        'ref_code': 'DHDM-$stamp',
        'price': 9.9,
        'is_active': true,
        'status': 'available',
        'item_kind': 'marketplace_product',
      });
      if (li['http'] == 201 || li['http'] == 200) {
        if (li['body'] is List && (li['body'] as List).isNotEmpty) {
          final id = (li['body'] as List).first['id']?.toString();
          if (id != null && id != 'null' && id.length > 10) liId = id;
        } else if (li['body'] is Map) {
          final id = (li['body'] as Map)['id']?.toString();
          if (id != null && id != 'null' && id.length > 10) liId = id;
        }
      }
      if (liId == null) {
        fail('dm-live-item', '${li['raw']}');
      }
    }

    if (liId != null) {
      final res = await req(
        'POST',
        '$url/rest/v1/live_reservation_requests',
        SVC,
        {
          'live_id': liveId,
          'live_item_id': liId,
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'requested_qty': 1,
          'status': 'accepted',
          'source': 'fleaber_live',
        },
      );
      final okRes = res['http'] == 201 || res['http'] == 200;
      okRes ? pass('dm-accept') : fail('dm-accept', '${res['raw']}');

      final sellable = await req(
        'POST',
        '$url/rest/v1/rpc/batata_product_hub_sellable',
        SVC,
        {'p_product_id': pid},
      );
      sellable['body'] == false
          ? pass('dm-sellable-false')
          : fail('dm-sellable-false', '${sellable['raw']}');

      final hubAfter = await req(
        'GET',
        '$url/rest/v1/hub_products_public?id=eq.$pid&select=id',
        ANON,
      );
      final nAfter =
          hubAfter['body'] is List ? (hubAfter['body'] as List).length : -1;
      nAfter == 0
          ? pass('dm-hub-hidden')
          : fail('dm-hub-hidden', 'n=$nAfter ${hubAfter['raw']}');
    } else {
      fail('dm-live-item', 'missing');
    }

    if (liveId != null) {
      await req('PATCH', '$url/rest/v1/lives?id=eq.$liveId', SVC, {
        'status': 'ended',
        'is_active': false,
      });
    }
    await req('PATCH', '$url/rest/v1/products?id=eq.$pid', SVC, {
      'list_on_marketplace': false,
      'is_sold': true,
    });
  }

  // Buyer token touch (sessão válida)
  buyerTok.isNotEmpty ? pass('buyer-tok') : fail('buyer-tok', 'empty');

  if (exitCode == 0) print('ALL PASS');
}
