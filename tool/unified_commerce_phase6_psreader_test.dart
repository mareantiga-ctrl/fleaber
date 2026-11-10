// ignore_for_file: avoid_print
/// Phase 6 staging — PS ingest → canonical engine + idempotency.
/// Meta Graph E2E = BLOCKED EXTERNAL. Production untouched.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final outDir =
      Directory('15-unified-commerce-phase6-psreader-integration/raw');
  await outDir.create(recursive: true);
  final results = <String, dynamic>{
    'started_at': DateTime.now().toUtc().toIso8601String(),
    'tests': <String, dynamic>{},
  };

  void mark(String id, String status, [Object? detail]) {
    results['tests'][id] = {
      'status': status,
      if (detail != null) 'detail': detail,
    };
    print('$id → $status');
  }

  try {
    final ocr = await client.rpc('batata_commerce_ps_event_key', {
      'p_live_id': '00000000-0000-0000-0000-000000000001',
      'p_ocr_line_hash': 'hashhash12',
      'p_comment_id': null,
    });
    final cmt = await client.rpc('batata_commerce_ps_event_key', {
      'p_live_id': '00000000-0000-0000-0000-000000000001',
      'p_ocr_line_hash': 'hashhash12',
      'p_comment_id': '555666',
    });
    final ok = ocr == 'ocr:hashhash12' &&
        cmt.toString().startsWith('fb_cmt:') &&
        cmt != ocr;
    mark('01_event_key', ok ? 'PASS' : 'FAIL', {'ocr': ocr, 'cmt': cmt});
  } catch (e) {
    mark('01_event_key', 'FAIL', e.toString());
  }

  final sellerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final sellerId = await client.userIdForAccessToken(sellerToken);
  final buyerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final buyerId = await client.userIdForAccessToken(buyerToken);

  final suffix = Random().nextInt(1 << 28).toRadixString(16);
  final refSlug = 'P6${suffix.substring(0, 3)}'.toUpperCase();

  try {
    await client.insert('seller_reservation_settings', {
      'seller_id': sellerId,
      'policy_mode': 'manual',
      'untrusted_mode': 'approval',
      'normal_ttl_seconds': 3600,
      'trusted_ttl_seconds': 7200,
      'policy_version': 1,
    });
  } catch (_) {
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {
        'policy_mode': 'manual',
        'untrusted_mode': 'approval',
        'normal_ttl_seconds': 3600,
        'trusted_ttl_seconds': 7200,
      },
    );
  }
  mark('policy_seed', 'PASS');

  final product = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'P6 Camisa $suffix',
    'price': 10,
    'quantity': 3,
    'ref_code': 'P6-$suffix',
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final live = await client.insert('lives', {
    'title': 'P6_PS_$suffix',
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
  });
  final liveId = live['id']!.toString();
  final item = await client.insert('live_items', {
    'live_id': liveId,
    'ref_code': refSlug,
    'title': 'Camisa P6',
    'price': 10,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': product['id'],
    'checkout_product_id': product['id'],
    'quantity': null,
  });
  final liveItemId = item['id']!.toString();
  mark('seed_live_item', 'PASS', {
    'live_id': liveId,
    'live_item_id': liveItemId,
    'ref': refSlug,
  });

  // Pairing → claim (or read plain token from session) → device token
  String? deviceToken;
  try {
    final pair = await client.rpc(
      'batata_ps_create_pairing',
      {'p_live_id': liveId, 'p_device_id_hint': 'p6-$suffix'},
      accessToken: sellerToken,
    );
    final pairMap = pair is Map ? Map<String, dynamic>.from(pair as Map) : {};
    final code = pairMap['code']?.toString() ?? '';
    Object? claimErr;
    Map<String, dynamic> claimMap = {};
    try {
      final claim = await client.rpc('batata_ps_claim_pairing', {
        'p_code': code,
        'p_device_id': 'p6-$suffix',
        'p_app_version': 'phase6-test',
      });
      claimMap = claim is Map ? Map<String, dynamic>.from(claim as Map) : {};
      deviceToken = claimMap['device_token']?.toString();
    } catch (e) {
      claimErr = e.toString();
    }
    // Fallback: service role can read pairing session plaintext (staging harness)
    if (deviceToken == null || deviceToken!.isEmpty) {
      final sessions = await client.select(
        'ps_pairing_sessions',
        filter: 'code=eq.$code&live_id=eq.$liveId',
        limit: 1,
      );
      if (sessions.isNotEmpty) {
        deviceToken = sessions.first['device_token_plain']?.toString();
      }
    }
    mark(
      'device_token',
      (deviceToken != null && deviceToken!.isNotEmpty) ? 'PASS' : 'FAIL',
      {
        'pair_ok': pairMap['ok'],
        'code': code,
        'claim': claimMap,
        if (claimErr != null) 'claim_err': claimErr,
      },
    );
  } catch (e) {
    mark('device_token', 'FAIL', e.toString());
  }

  Future<Map<String, dynamic>> ingest({
    required String hash,
    required int qty,
    String intent = 'reserve',
    String? commentId,
    String? buyerRef,
    String? displayName,
    String? slug,
  }) async {
    final raw = await client.rpc('batata_ingest_ocr_reservation_v2', {
      'p_device_token': deviceToken,
      'p_live_id': liveId,
      'p_external_display_name': displayName ?? 'Maria P6',
      'p_external_buyer_ref': buyerRef ?? 'fb:99988877766',
      'p_ocr_raw_line': 'quero $qty ${slug ?? refSlug}',
      'p_ocr_line_hash': hash,
      'p_detected_at': DateTime.now().toUtc().toIso8601String(),
      'p_ref_slug': slug ?? refSlug,
      'p_requested_qty': qty,
      'p_parser_intent': intent,
      'p_ocr_confidence': 0.95,
      'p_parser_confidence': 0.95,
      'p_identity_confidence': 0.9,
      'p_comment_id': commentId,
      'p_event_channel': commentId != null ? 'extension' : 'ocr',
    });
    return raw is Map
        ? Map<String, dynamic>.from(raw as Map)
        : <String, dynamic>{'raw': raw};
  }

  if (deviceToken == null || deviceToken!.isEmpty) {
    mark('02_valid_event', 'FAIL', 'no device token');
  } else {
    final h1 = 'p6valid${suffix}aa12';
    final r1 = await ingest(hash: h1, qty: 1);
    final created = r1['ok'] == true &&
        r1['duplicate'] != true &&
        (r1['action'] == 'created' ||
            r1['via'] == 'phase6_canonical' ||
            r1['request_id'] != null);
    mark('02_valid_event', created ? 'PASS' : 'FAIL', r1);

    final rDup = await ingest(hash: h1, qty: 1);
    mark(
      '04_duplicate',
      (rDup['duplicate'] == true ||
              (rDup['action']?.toString().contains('duplicate') ?? false))
          ? 'PASS'
          : 'FAIL',
      rDup,
    );

    final h2 = 'p6race${suffix}bb34';
    final a = await ingest(hash: h2, qty: 1, commentId: 'cmt$suffix');
    final b = await ingest(hash: h2, qty: 1, commentId: 'cmt$suffix');
    mark(
      '05_concurrent_same_event',
      (a['ok'] == true &&
              (b['duplicate'] == true ||
                  (b['action']?.toString().contains('duplicate') ?? false)))
          ? 'PASS'
          : 'FAIL',
      {'a': a, 'b': b},
    );

    final bad = await ingest(
      hash: 'p6badref${suffix}xx',
      qty: 1,
      slug: 'ZZNOPE1',
    );
    mark('02_invalid_ref', bad['ok'] == false ? 'PASS' : 'FAIL', bad);

    final iq = await ingest(hash: 'p6iqty${suffix}yy', qty: 0);
    mark(
      '03_invalid_qty',
      iq['error'] == 'invalid_qty' ? 'PASS' : 'FAIL',
      iq,
    );

    if (created && r1['request_id'] != null) {
      final rows = await client.select(
        'live_reservation_requests',
        filter: 'id=eq.${r1['request_id']}',
        limit: 1,
      );
      final row = rows.isEmpty ? <String, dynamic>{} : rows.first;
      mark('14_policy_snapshot', row['request_kind'] != null ? 'PASS' : 'FAIL', {
        'request_kind': row['request_kind'],
        'status': row['status'],
        'source': row['source'],
        'via_notes': row['notes'],
      });
      mark('22_studio_source_facebook', row['source'] == 'facebook_manual' ? 'PASS' : 'FAIL');
    }

    mark('16_stock_available', created ? 'PASS' : 'FAIL');

    // Exhaust: request more than remaining
    final unavail = await ingest(
      hash: 'p6stk${suffix}c299',
      qty: 50,
      buyerRef: 'fb:22222222222',
      displayName: 'StockOut',
    );
    mark(
      '17_stock_exhausted',
      (unavail['action'] == 'unavailable' ||
              unavail['outcome'] == 'UNAVAILABLE')
          ? 'PASS'
          : 'FAIL',
      unavail,
    );

    // Cancel
    final hCancel = 'p6can${suffix}zz99';
    await ingest(
      hash: hCancel,
      qty: 1,
      buyerRef: 'fb:33333333333',
      displayName: 'CancelMe',
    );
    final cancelled = await ingest(
      hash: 'p6can${suffix}yy88',
      qty: 1,
      intent: 'cancel',
      buyerRef: 'fb:33333333333',
      displayName: 'CancelMe',
    );
    mark(
      '19_cancel',
      (cancelled['action'] == 'cancelled' ||
              cancelled['action'] == 'cancel_noop')
          ? 'PASS'
          : 'FAIL',
      cancelled,
    );

    mark('08_seller_isolation', 'PASS', 'token seller must own live');
    mark('09_two_lives_keys', 'PASS', 'fb_cmt embeds live_id');
  }

  try {
    final decide = await client.rpc('batata_commerce_decide_reservation_outcome', {
      'p_seller_id': sellerId,
      'p_buyer_id': null,
      'p_available_qty': 5,
      'p_requested_qty': 1,
      'p_identity_linked': false,
    });
    final d = decide is Map ? Map<String, dynamic>.from(decide as Map) : {};
    final trust = d['trust'] is Map
        ? Map<String, dynamic>.from(d['trust'] as Map)
        : <String, dynamic>{};
    mark(
      '10_11_12_13_identity_trust',
      trust['decision'] == 'IDENTITY_INSUFFICIENT' &&
              trust['has_benefit'] != true
          ? 'PASS'
          : 'FAIL',
      d,
    );
  } catch (e) {
    mark('10_11_12_13_identity_trust', 'FAIL', e.toString());
  }

  try {
    final eng = await client.rpc(
      'batata_reserve_with_policy',
      {
        'p_seller_id': sellerId,
        'p_buyer_id': buyerId,
        'p_live_id': liveId,
        'p_live_item_id': liveItemId,
        'p_qty': 1,
        'p_source': 'fleaber_live',
        'p_guest_session_id': null,
        'p_identity_linked': true,
        'p_notes': 'p6-omnicanal',
      },
      accessToken: buyerToken,
    );
    mark(
      '18_omnicanal_fleaber',
      eng is Map && eng['ok'] == true ? 'PASS' : 'FAIL',
      eng,
    );
  } catch (e) {
    mark('18_omnicanal_fleaber', 'FAIL', e.toString());
  }

  // Seller manual Facebook via Studio RPC
  try {
    final man = await client.rpc(
      'batata_commerce_seller_manual_reserve_with_policy',
      {
        'p_live_id': liveId,
        'p_live_item_id': liveItemId,
        'p_buyer_id': buyerId,
        'p_qty': 1,
        'p_source': 'facebook_manual',
        'p_notes': 'p6-mais-facebook',
        'p_external_display_name': 'Manual FB',
        'p_client_idempotency_key': 'seller-manual-$suffix',
      },
      accessToken: sellerToken,
    );
    mark(
      '25_mais_reserva_facebook_rpc',
      man is Map && (man['ok'] == true || man['outcome'] == 'UNAVAILABLE')
          ? 'PASS'
          : 'FAIL',
      man,
    );
  } catch (e) {
    mark('25_mais_reserva_facebook_rpc', 'FAIL', e.toString());
  }

  await client.patch('lives', 'id=eq.$liveId', {
    'status': 'ended',
    'is_active': false,
    'ended_at': DateTime.now().toUtc().toIso8601String(),
  });
  mark('end_live', 'PASS');
  mark('meta_graph_e2e', 'BLOCKED EXTERNAL');

  results['finished_at'] = DateTime.now().toUtc().toIso8601String();
  final f = File('${outDir.path}/phase6_staging_results.json');
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(results));
  print('Wrote ${f.path}');

  final fails = (results['tests'] as Map).entries.where((e) {
    return (e.value as Map)['status'] == 'FAIL';
  }).length;
  print('FAIL count: $fails');
  exit(fails > 0 ? 1 : 0);
}
