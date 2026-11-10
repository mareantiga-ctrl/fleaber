// ignore_for_file: avoid_print
/// Indep 1443 P0 + Blind B 1442 P1/P2 — dart run tool/sec_blind_1442_1443_hostile.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
          : method == 'GET'
              ? await http.get(Uri.parse(u), headers: h)
              : await http.delete(Uri.parse(u), headers: h);
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
    return s.isEmpty || s == 'null' ? null : s;
  }
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

  // ========== P0: proposta sem oferta = catálogo ==========
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'P0 proposta $stamp',
    'price': 42.0,
    'quantity': 5,
    'ref_code': 'P0PROP-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = idOf(prod['body']);
  add('fixture_product', pid != null, {'id': pid});

  final fake = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 0.50,
    'shipping_method': 'mao',
    'payment_method': 'proposta',
  });
  Map<String, dynamic> fakeRow = {};
  if (fake['body'] is List && (fake['body'] as List).isNotEmpty) {
    fakeRow = Map<String, dynamic>.from((fake['body'] as List).first as Map);
  }
  final unit = int.tryParse('${fakeRow['contract_unit_cents']}') ?? 0;
  final pt = num.tryParse('${fakeRow['price_total']}') ?? 0;
  final oid = '${fakeRow['id'] ?? ''}';
  add(
    'P0_proposta_uses_catalog',
    oid.isNotEmpty && unit == 4200 && pt >= 41.99,
    {
      'unit': unit,
      'price_total': pt,
      'offer': fakeRow['product_offer_id'],
      'pm': fakeRow['payment_method'],
      'http': fake['http'],
    },
  );

  // Checkout must charge catalog-scale, not 0.50
  if (oid.isNotEmpty) {
    final ck = await req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      BH,
      {
        'order_id': oid,
        'buyer_id': buyerId,
        'shipping_method': 'mao',
      },
    );
    num? amount;
    if (ck['body'] is Map) {
      amount = num.tryParse('${(ck['body'] as Map)['amount_total']}');
    }
    add(
      'P0_checkout_not_subprice',
      ck['http'] == 200 && amount != null && amount! >= 4000,
      {'http': ck['http'], 'amount_total': amount, 'body': ck['body']},
    );
  }

  // P2: contract_unit_cents client ignored
  final poison = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 0.01,
    'contract_unit_cents': 1,
    'shipping_method': 'mao',
    'payment_method': 'Pagamento na app',
  });
  Map<String, dynamic> poisonRow = {};
  if (poison['body'] is List && (poison['body'] as List).isNotEmpty) {
    poisonRow =
        Map<String, dynamic>.from((poison['body'] as List).first as Map);
  }
  final pUnit = int.tryParse('${poisonRow['contract_unit_cents']}') ?? 0;
  add(
    'P2_contract_cents_ignored',
    pUnit == 4200,
    {'unit': pUnit, 'http': poison['http']},
  );
  final poisonOid = '${poisonRow['id'] ?? ''}';

  // ========== P1 storage disputes ==========
  final bytes = Uint8List.fromList(List<int>.filled(48, 9));
  final disputePath = 'order_disputes/$sellerId/hostile_$stamp.png';
  final up = await http.post(
    Uri.parse('$url/storage/v1/object/fleaber_private/$disputePath'),
    headers: {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
      'Content-Type': 'image/png',
      'x-upsert': 'true',
    },
    body: bytes,
  );
  add('P1_dispute_upload', up.statusCode < 300, {'http': up.statusCode});
  final buyerGet = await http.get(
    Uri.parse('$url/storage/v1/object/fleaber_private/$disputePath'),
    headers: {'apikey': anon, 'Authorization': 'Bearer $buyerTok'},
  );
  add(
    'P1_buyer_cannot_read_seller_disputes',
    buyerGet.statusCode == 400 ||
        buyerGet.statusCode == 403 ||
        buyerGet.statusCode == 404,
    {'http': buyerGet.statusCode},
  );
  await http.delete(
    Uri.parse('$url/storage/v1/object/fleaber_private/$disputePath'),
    headers: {'apikey': svc, 'Authorization': 'Bearer $svc'},
  );

  // ========== P1 device token survives kick ==========
  final helperEmail = 'rtb1442h$stamp@fleaber.test';
  final helperPass = 'TesteTok$stamp!';
  final created = await req(
    'POST',
    '$url/auth/v1/signup',
    {'apikey': anon, 'Content-Type': 'application/json'},
    {'email': helperEmail, 'password': helperPass},
  );
  String? helperId;
  if (created['body'] is Map) {
    final u = (created['body'] as Map)['user'];
    if (u is Map) helperId = '${u['id']}';
  }
  add('P1_helper_signup', helperId != null, {'id': helperId});

  if (helperId != null) {
    final invite = await req('POST', '$url/rest/v1/seller_helpers', SVC, {
      'seller_id': sellerId,
      'helper_user_id': helperId,
      'invited_email': helperEmail,
      'invitation_status': 'accepted',
      'active': true,
      'permissions': {
        'can_view_live_dashboard': true,
        'can_manage_reservations': true,
        'can_manage_raffles': false,
      },
    });
    final inviteId = idOf(invite['body']);
    final helperTok =
        await sb.signIn(email: helperEmail, password: helperPass);
    final HH = {
      'apikey': anon,
      'Authorization': 'Bearer $helperTok',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

    final live = await req('POST', '$url/rest/v1/lives', SVC, {
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'status': 'live',
      'is_active': true,
      'title': 'P1 pair $stamp',
    });
    final liveId = idOf(live['body']);

    final pair = await req(
      'POST',
      '$url/rest/v1/rpc/batata_ps_create_pairing',
      HH,
      {'p_live_id': liveId, 'p_device_id_hint': 'rtb1442-$stamp'},
    );
    Map<String, dynamic> pairBody = {};
    if (pair['body'] is Map) {
      pairBody = Map<String, dynamic>.from(pair['body'] as Map);
    }
    final code = '${pairBody['code'] ?? ''}';
    add('P1_helper_pairing_ok', pairBody['ok'] == true && code.length == 6, {
      'body': pairBody,
    });

    // claim anon
    final claim = await req(
      'POST',
      '$url/functions/v1/ps-pairing-claim',
      {
        'apikey': anon,
        'Content-Type': 'application/json',
      },
      {'code': code, 'device_id': 'rtb1442-claim-$stamp'},
    );
    Map<String, dynamic> claimBody = {};
    if (claim['body'] is Map) {
      claimBody = Map<String, dynamic>.from(claim['body'] as Map);
    }
    final token = '${claimBody['device_token'] ?? ''}';
    add(
      'P1_claim_token',
      claim['http'] == 200 && token.length > 20,
      {'http': claim['http'], 'seller_id': claimBody['seller_id']},
    );

    // kick helper
    if (inviteId != null) {
      await req('DELETE', '$url/rest/v1/seller_helpers?id=eq.$inviteId', SVC);
    }

    // validate RPC must reject revoked/staff-gone token
    final val = await req(
      'POST',
      '$url/rest/v1/rpc/batata_validate_seller_device_token',
      SVC,
      {'p_token': token},
    );
    Map<String, dynamic> valBody = {};
    if (val['body'] is Map) {
      valBody = Map<String, dynamic>.from(val['body'] as Map);
    }
    add(
      'P1_token_dead_after_kick',
      valBody['ok'] != true,
      {'rpc': valBody},
    );

    // ingest with full body still fails auth
    final ingest = await req(
      'POST',
      '$url/functions/v1/ingest-ocr-reservation',
      {
        'apikey': anon,
        'Content-Type': 'application/json',
        'x-device-token': token,
      },
      {
        'live_id': liveId,
        'ocr_line_hash': 'deadbeefdeadbeef',
        'detected_at': DateTime.now().toUtc().toIso8601String(),
        'ref_number': 1,
        'external_display_name': 'AFTER KICK $stamp',
      },
    );
    final ingestBlocked = ingest['http'] >= 400 &&
        !'${ingest['text']}'.contains('missing_line_hash');
    add('P1_ingest_rejects_dead_token', ingestBlocked, {
      'http': ingest['http'],
      'body': ingest['body'],
    });

    // tokens revoked in DB
    final toks = await req(
      'GET',
      '$url/rest/v1/seller_device_tokens?seller_id=eq.$sellerId&created_by=eq.$helperId&select=revoked_at,device_id',
      SVC,
    );
    var revoked = false;
    if (toks['body'] is List) {
      for (final row in toks['body'] as List) {
        if (row is Map && row['revoked_at'] != null) revoked = true;
      }
    }
    add('P1_tokens_revoked_row', revoked || ingestBlocked, {
      'rows': toks['body'],
    });

    if (liveId != null) {
      await req(
        'PATCH',
        '$url/rest/v1/lives?id=eq.$liveId',
        SVC,
        {'status': 'ended', 'is_active': false},
      );
    }

    // P2: helper cannot INSERT accepted
    final live2 = await req('POST', '$url/rest/v1/lives', SVC, {
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'status': 'live',
      'is_active': true,
      'title': 'P2 res $stamp',
    });
    final live2Id = idOf(live2['body']);
    // re-invite for insert test
    final invite2 = await req('POST', '$url/rest/v1/seller_helpers', SVC, {
      'seller_id': sellerId,
      'helper_user_id': helperId,
      'invited_email': helperEmail,
      'invitation_status': 'accepted',
      'active': true,
      'permissions': {
        'can_manage_reservations': true,
      },
    });
    final invite2Id = idOf(invite2['body']);
    final li = await req('POST', '$url/rest/v1/live_items', SVC, {
      'live_id': live2Id,
      'seller_id': sellerId,
      'title': 'item $stamp',
      'ref_code': 'R1442-$stamp',
      'price': 10.0,
      'quantity': 2,
      'status': 'available',
      'item_kind': 'live_only',
    });
    final liId = idOf(li['body']);
    add('P2_live_item_fixture', liId != null, {
      'id': liId,
      'http': li['http'],
      'body': li['body'],
    });
    if (liId == null) {
      // skip rest of P2 insert
    } else {
    final resIns = await req('POST', '$url/rest/v1/live_reservation_requests', HH, {
      'live_id': live2Id,
      'live_item_id': liId,
      'seller_id': sellerId,
      'external_display_name': 'FB $stamp',
      'source': 'facebook_manual',
      'status': 'accepted',
      'requested_qty': 1,
    });
    Map<String, dynamic> resRow = {};
    if (resIns['body'] is List && (resIns['body'] as List).isNotEmpty) {
      resRow = Map<String, dynamic>.from((resIns['body'] as List).first as Map);
    }
    add(
      'P2_manual_insert_forced_pending',
      '${resRow['status']}' == 'pending',
      {
        'status': resRow['status'],
        'http': resIns['http'],
        'body': resIns['body'],
      },
    );
    }
    if (invite2Id != null) {
      await req('DELETE', '$url/rest/v1/seller_helpers?id=eq.$invite2Id', SVC);
    }
    if (live2Id != null) {
      await req('DELETE', '$url/rest/v1/live_reservation_requests?live_id=eq.$live2Id', SVC);
      await req('DELETE', '$url/rest/v1/live_items?live_id=eq.$live2Id', SVC);
      await req(
        'PATCH',
        '$url/rest/v1/lives?id=eq.$live2Id',
        SVC,
        {'status': 'ended', 'is_active': false},
      );
    }
  }

  if (oid.isNotEmpty) {
    await req('DELETE', '$url/rest/v1/orders?id=eq.$oid', SVC);
  }
  if (poisonOid.isNotEmpty) {
    await req('DELETE', '$url/rest/v1/orders?id=eq.$poisonOid', SVC);
  }
  if (pid != null) {
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
  }

  final failed = results.where((r) => r['ok'] != true).length;
  final outPath = 'tool/reports/sec_blind_1442_1443_hostile_$stamp.json';
  await File(outPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'stamp': stamp,
      'pass': results.length - failed,
      'fail': failed,
      'total': results.length,
      'results': results,
    }),
  );
  stdout.writeln('Wrote $outPath (${results.length - failed}/${results.length})');
  exit(failed == 0 ? 0 : 1);
}
