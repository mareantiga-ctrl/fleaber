// ignore_for_file: avoid_print
/// E0817 product A decisions — dart run tool/sec_e0817_product_decisions_a_hostile.dart
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
  final createdLiveIds = <String>[];
  final createdProductIds = <String>[];
  Map<String, dynamic>? profileSnap;

  try {
    // Snapshot seller discovery flags
    final prof = await req(
      'GET',
      '$url/rest/v1/profiles?id=eq.$sellerId&select=hub_published,is_live',
      SVC,
    );
    profileSnap = firstMap(prof['body']);
    final wasPublished = profileSnap?['hub_published'] == true;
    final wasLive = profileSnap?['is_live'] == true;

    // End any active lives for seller (discovery fixture)
    final actives = await req(
      'GET',
      '$url/rest/v1/lives?or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&is_active=eq.true&select=id',
      SVC,
    );
    if (actives['body'] is List) {
      for (final row in actives['body'] as List) {
        if (row is Map && row['id'] != null) {
          await req(
            'PATCH',
            '$url/rest/v1/lives?id=eq.${row['id']}',
            SVC,
            {'is_active': false, 'status': 'ended'},
          );
        }
      }
    }

    // ---- 1A: is_live alone does NOT put unpublished seller in discovery ----
    // hub_published só via batata_publish_hub (trigger handle_immutable_use_rpc)
    final unpub = await req(
      'POST',
      '$url/rest/v1/rpc/batata_publish_hub',
      SH,
      {'p_publish': false},
    );
    await req(
      'PATCH',
      '$url/rest/v1/profiles?id=eq.$sellerId',
      SVC,
      {'is_live': true},
    );
    final discOff = await req(
      'GET',
      '$url/rest/v1/hub_profiles_discovery_public?id=eq.$sellerId&select=id',
      AH,
    );
    final offRows =
        discOff['body'] is List ? (discOff['body'] as List).length : -1;
    add('A1_is_live_alone_hidden', offRows == 0, {
      'http': discOff['http'],
      'rows': offRows,
      'unpub': unpub['body'],
    });

    // Real active live → appears even unpublished
    final liveOn = await req('POST', '$url/rest/v1/lives', SVC, {
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'title': 'E0817 live $stamp',
      'status': 'live',
      'is_active': true,
    });
    final liveOnId = idOf(liveOn['body']);
    if (liveOnId != null) createdLiveIds.add(liveOnId);
    final discOn = await req(
      'GET',
      '$url/rest/v1/hub_profiles_discovery_public?id=eq.$sellerId&select=id',
      AH,
    );
    final onRows = discOn['body'] is List ? (discOn['body'] as List).length : -1;
    add('A1_real_live_visible', onRows == 1 && liveOnId != null, {
      'http': discOn['http'],
      'rows': onRows,
      'live': liveOnId,
    });

    // ---- 2A: ended without hub_published hidden from lives discovery ----
    if (liveOnId != null) {
      await req(
        'PATCH',
        '$url/rest/v1/lives?id=eq.$liveOnId',
        SVC,
        {'is_active': false, 'status': 'ended'},
      );
    }
    final livesHid = await req(
      'GET',
      '$url/rest/v1/hub_lives_discovery_public?id=eq.$liveOnId&select=id',
      AH,
    );
    final hidRows =
        livesHid['body'] is List ? (livesHid['body'] as List).length : -1;
    add('A2_ended_unpublished_hidden', hidRows == 0, {
      'http': livesHid['http'],
      'rows': hidRows,
    });

    final pub = await req(
      'POST',
      '$url/rest/v1/rpc/batata_publish_hub',
      SH,
      {'p_publish': true},
    );
    final livesShow = await req(
      'GET',
      '$url/rest/v1/hub_lives_discovery_public?id=eq.$liveOnId&select=id',
      AH,
    );
    final showRows =
        livesShow['body'] is List ? (livesShow['body'] as List).length : -1;
    add('A2_ended_published_visible', showRows == 1, {
      'http': livesShow['http'],
      'rows': showRows,
      'pub': pub['body'],
    });

    // Restaurar publish/is_live baseline (tip/bundle não dependem)
    await req(
      'POST',
      '$url/rest/v1/rpc/batata_publish_hub',
      SH,
      {'p_publish': wasPublished},
    );
    await req(
      'PATCH',
      '$url/rest/v1/profiles?id=eq.$sellerId',
      SVC,
      {'is_live': wasLive},
    );

    // ---- 3A: bundle rejects unlist ----
    final unlist = await req('POST', '$url/rest/v1/products', SVC, {
      'seller_id': sellerId,
      'title': 'E0817 unlist $stamp',
      'price': 42.50,
      'quantity': 2,
      'ref_code': 'E817U-$stamp',
      'list_on_marketplace': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final unlistId = idOf(unlist['body']);
    if (unlistId != null) createdProductIds.add(unlistId);

    final listed = await req('POST', '$url/rest/v1/products', SVC, {
      'seller_id': sellerId,
      'title': 'E0817 listed $stamp',
      'price': 11.0,
      'quantity': 2,
      'ref_code': 'E817L-$stamp',
      'list_on_marketplace': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final listedId = idOf(listed['body']);
    if (listedId != null) createdProductIds.add(listedId);

    final badBundle = await req('POST', '$url/rest/v1/product_bundles', BH, {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'product_ids': [unlistId],
      'status': 'pending',
      'total_eur': 0.50,
      'subtotal_eur': 0.50,
    });
    final badText = '${badBundle['body']}'.toLowerCase();
    add(
      'A3_bundle_unlist_rejected',
      (badBundle['http'] as int) >= 400 &&
          (badText.contains('bundle_product_not_listed') ||
              badText.contains('23514')),
      {'http': badBundle['http'], 'body': badBundle['body']},
    );

    final okBundle = await req('POST', '$url/rest/v1/product_bundles', BH, {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'product_ids': [listedId],
      'status': 'pending',
      'total_eur': 0.50,
      'subtotal_eur': 0.50,
    });
    final okBid = idOf(okBundle['body']);
    final okMap = firstMap(okBundle['body']);
    add(
      'A3_bundle_listed_ok_catalog_price',
      okBid != null &&
          (okMap?['total_eur'] == 11 ||
              okMap?['total_eur'] == 11.0 ||
              '${okMap?['total_eur']}' == '11' ||
              '${okMap?['total_eur']}' == '11.00'),
      {
        'http': okBundle['http'],
        'id': okBid,
        'total': okMap?['total_eur'],
      },
    );

    // ---- 4A: catalog subtotal JWT hides unlist price ----
    final jwtSub = await req(
      'POST',
      '$url/rest/v1/rpc/batata_product_bundles_catalog_subtotal',
      BH,
      {
        'p_product_ids': [unlistId],
      },
    );
    final jwtVal = jwtSub['body'];
    final jwtNum = jwtVal is num
        ? jwtVal.toDouble()
        : double.tryParse('$jwtVal') ?? -1;
    add('A4_jwt_unlist_subtotal_zero', jwtNum == 0.0, {
      'http': jwtSub['http'],
      'val': jwtVal,
    });

    final svcSub = await req(
      'POST',
      '$url/rest/v1/rpc/batata_product_bundles_catalog_subtotal',
      SVC,
      {
        'p_product_ids': [unlistId],
      },
    );
    final svcVal = svcSub['body'];
    final svcNum = svcVal is num
        ? svcVal.toDouble()
        : double.tryParse('$svcVal') ?? -1;
    add('A4_svc_unlist_subtotal_price', svcNum == 42.5, {
      'http': svcSub['http'],
      'val': svcVal,
    });

    // ---- 5A: invite anti-oracle ----
    final miss = await req(
      'POST',
      '$url/rest/v1/rpc/batata_staff_invite_helper_by_email',
      SH,
      {
        'p_email': 'nobody-e0817-$stamp@example.invalid',
        'p_display_name': 'Ghost E0817',
        'p_permissions': <String, dynamic>{},
      },
    );
    final missBody = miss['body'];
    final missOk = missBody is Map && missBody['ok'] == true;
    add('A5_invite_missing_ok_shape', (miss['http'] as int) == 200 && missOk, {
      'http': miss['http'],
      'body': missBody,
    });

    final hit = await req(
      'POST',
      '$url/rest/v1/rpc/batata_staff_invite_helper_by_email',
      SH,
      {
        'p_email': envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
        'p_display_name': 'Buyer helper E0817',
        'p_permissions': <String, dynamic>{},
      },
    );
    final hitBody = hit['body'];
    final hitOk = hitBody is Map && hitBody['ok'] == true;
    // may already be member/pending — still must not return invite_unavailable
    final hitText = '${hit['body']}'.toLowerCase();
    final noOracle = !hitText.contains('invite_unavailable');
    add(
      'A5_invite_existing_no_oracle',
      noOracle &&
          ((hit['http'] as int) == 200 && hitOk ||
              hitText.contains('already_member') ||
              hitText.contains('invite_pending')),
      {'http': hit['http'], 'body': hitBody},
    );

    // Cleanup pending invite if created
    await req(
      'DELETE',
      '$url/rest/v1/seller_helpers?seller_id=eq.$sellerId&helper_user_id=eq.$buyerId&invitation_status=eq.pending',
      SVC,
    );

    // ---- Extra A: tip on ended live ----
    final ended = await req('POST', '$url/rest/v1/lives', SVC, {
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'title': 'E0817 vod tip $stamp',
      'status': 'ended',
      'is_active': false,
      'mux_vod_playback_id': 'fake-vod-$stamp',
    });
    final endedId = idOf(ended['body']);
    if (endedId != null) createdLiveIds.add(endedId);

    final tip = await req(
      'POST',
      '$url/rest/v1/rpc/batata_create_live_tip_pending',
      BH,
      {
        'p_live_id': endedId,
        'p_seller_id': sellerId,
        'p_amount': 1.0,
        'p_message': 'e0817 tip vod',
      },
    );
    final tipId = tip['body'] is String
        ? (tip['body'] as String).replaceAll('"', '')
        : idOf(tip['body']) ?? '${tip['body']}';
    final tipText = '${tip['body']}'.toLowerCase();
    add(
      'EXTRA_tip_ended_ok',
      (tip['http'] as int) == 200 &&
          tipId.isNotEmpty &&
          tipId != 'null' &&
          !tipText.contains('live_not_active'),
      {'http': tip['http'], 'tip': tipId, 'body': tip['body']},
    );

    if (tipId.isNotEmpty && tipId != 'null') {
      await req('DELETE', '$url/rest/v1/live_tips?id=eq.$tipId', SVC);
    }
  } finally {
    // Restore profile (hub_published via RPC)
    if (profileSnap != null) {
      await req(
        'POST',
        '$url/rest/v1/rpc/batata_publish_hub',
        SH,
        {'p_publish': profileSnap['hub_published'] == true},
      );
      await req(
        'PATCH',
        '$url/rest/v1/profiles?id=eq.$sellerId',
        SVC,
        {'is_live': profileSnap['is_live'] == true},
      );
    }
    for (final id in createdLiveIds) {
      await req(
        'PATCH',
        '$url/rest/v1/lives?id=eq.$id',
        SVC,
        {'is_active': false, 'status': 'ended'},
      );
    }
    for (final id in createdProductIds) {
      await req('DELETE', '$url/rest/v1/products?id=eq.$id', SVC);
    }
  }

  final failed = results.where((r) => r['ok'] != true).length;
  stdout.writeln('--- ${results.length - failed}/${results.length} PASS ---');
  exit(failed == 0 ? 0 : 1);
}
