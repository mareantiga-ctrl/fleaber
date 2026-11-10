// ignore_for_file: avoid_print
/// Phase 4 final evidence — guest TTL/lifecycle + concurrent idempotency.
///
///   dart run tool/unified_commerce_phase4_final_evidence_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'live_ops_staging_client.dart';

typedef _Check = ({String id, bool ok, String detail});

Future<void> main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final sellerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerId = await client.userIdForAccessToken(sellerToken);
  final buyerId = await client.userIdForAccessToken(buyerToken);

  final tag =
      'p4e_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
  final outDir = Directory('13-unified-commerce-phase4-final-evidence/raw')
    ..createSync(recursive: true);

  final checks = <_Check>[];
  void add(String id, bool ok, [String detail = '']) {
    checks.add((id: id, ok: ok, detail: detail));
    print('${ok ? 'PASS' : 'FAIL'} $id ${detail.isEmpty ? '' : '— $detail'}');
  }

  Future<Map<String, String>> seed({
    required String suffix,
    required int qty,
  }) async {
    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P4E $tag-$suffix',
      'price': 10,
      'quantity': qty,
      'ref_code': 'P4E-$tag-$suffix',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live = await client.insert('lives', {
      'title': 'P4E_${tag}_$suffix',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final item = await client.insert('live_items', {
      'live_id': live['id'],
      'ref_code': 'P4E-$tag-$suffix',
      'title': 'P4E $suffix',
      'price': 10,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': product['id'],
      'checkout_product_id': product['id'],
      'quantity': null,
    });
    return {
      'product_id': product['id'] as String,
      'live_id': live['id'] as String,
      'live_item_id': item['id'] as String,
    };
  }

  Future<Map<String, dynamic>> guestCreate([int? ttl]) async {
    final raw = await client.rpc('batata_commerce_guest_session_create', {
      'p_ttl_seconds': ttl ?? 3600,
    });
    return Map<String, dynamic>.from(raw as Map);
  }

  Duration ttlApplied(Map<String, dynamic> g) {
    final exp = DateTime.parse(g['expires_at'] as String).toUtc();
    final applied = g['ttl_seconds_applied'];
    if (applied is num) return Duration(seconds: applied.round());
    return exp.difference(DateTime.now().toUtc());
  }

  // ---------- GUEST-SESSION-01..03 TTL ----------
  final gMin = await guestCreate(60); // below min 900
  final dMin = ttlApplied(gMin);
  File('${outDir.path}/GUEST-SESSION-01_ttl_min.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(gMin),
  );
  add(
    'GUEST-SESSION-01',
    gMin['ok'] == true &&
        (gMin['ttl_seconds_applied'] == 900 ||
            (dMin.inSeconds >= 890 && dMin.inSeconds <= 920)),
    'applied=${gMin['ttl_seconds_applied']} ~${dMin.inSeconds}s',
  );

  final gNorm = await guestCreate(3600);
  File('${outDir.path}/GUEST-SESSION-02_ttl_normal.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(gNorm),
  );
  add(
    'GUEST-SESSION-02',
    gNorm['ok'] == true && gNorm['ttl_seconds_applied'] == 3600,
    'applied=${gNorm['ttl_seconds_applied']}',
  );

  final gMax = await guestCreate(99999999);
  File('${outDir.path}/GUEST-SESSION-03_ttl_max.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(gMax),
  );
  add(
    'GUEST-SESSION-03',
    gMax['ok'] == true && gMax['ttl_seconds_applied'] == 86400,
    'applied=${gMax['ttl_seconds_applied']} max=${gMax['ttl_max_seconds']}',
  );

  // ---------- GUEST-SESSION-04 expired ----------
  final gExp = await guestCreate(900);
  await client.patch(
    'commerce_guest_sessions',
    'id=eq.${gExp['guest_session_id']}',
    {
      'expires_at': DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String(),
    },
  );
  final resolveExp = await client.rpc('batata_commerce_guest_session_resolve', {
    'p_guest_token': gExp['guest_token'],
  }) as Map;
  File('${outDir.path}/GUEST-SESSION-04_expired.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'resolve': resolveExp,
      'session_id': gExp['guest_session_id'],
    }),
  );
  add(
    'GUEST-SESSION-04',
    resolveExp['ok'] != true && resolveExp['error'] == 'guest_expired',
    '${resolveExp['error']}',
  );

  // ---------- GUEST-SESSION-05 revoked ----------
  final gRev = await guestCreate(3600);
  final rev = await client.rpc('batata_commerce_guest_session_revoke', {
    'p_guest_session_id': gRev['guest_session_id'],
  }) as Map;
  final resolveRev = await client.rpc('batata_commerce_guest_session_resolve', {
    'p_guest_token': gRev['guest_token'],
  }) as Map;
  File('${outDir.path}/GUEST-SESSION-05_revoked.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'revoke': rev,
      'resolve': resolveRev,
    }),
  );
  add(
    'GUEST-SESSION-05',
    rev['ok'] == true &&
        resolveRev['ok'] != true &&
        resolveRev['error'] == 'guest_revoked',
    '${resolveRev['error']}',
  );

  // ---------- GUEST-SESSION-06 tampered ----------
  final resolveBad = await client.rpc('batata_commerce_guest_session_resolve', {
    'p_guest_token': 'deadbeef' * 8, // 64 hex chars, wrong hash
  }) as Map;
  File('${outDir.path}/GUEST-SESSION-06_tampered.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(resolveBad),
  );
  add(
    'GUEST-SESSION-06',
    resolveBad['ok'] != true &&
        (resolveBad['error'] == 'guest_not_found' ||
            resolveBad['error'] == 'invalid_guest_token'),
    '${resolveBad['error']}',
  );

  // ---------- GUEST-SESSION-07 auth + guest token ----------
  Map authGuest = {};
  try {
    authGuest = await client.rpc(
      'batata_commerce_resolve_checkout_actor',
      {'p_guest_token': gNorm['guest_token']},
      accessToken: buyerToken,
    ) as Map;
  } catch (e) {
    authGuest = {'ok': false, 'error': e.toString()};
  }
  File('${outDir.path}/GUEST-SESSION-07_auth_conflict.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(authGuest),
  );
  add(
    'GUEST-SESSION-07',
    authGuest['ok'] != true &&
        authGuest['error'] == 'authenticated_cannot_use_guest_token',
    '${authGuest['error']}',
  );

  // ---------- Concurrent idempotency ----------
  Future<Map<String, dynamic>> beginGuest({
    required String token,
    required List<Map<String, dynamic>> lines,
    required String key,
  }) async {
    try {
      final raw = await client.rpc('batata_commerce_checkout_begin', {
        'p_lines': lines,
        'p_shipping_method': 'Entrega em Mão (€0.00)',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_client_idempotency_key': key,
        'p_confirm_remainder': false,
        'p_guest_token': token,
      });
      return Map<String, dynamic>.from(raw as Map);
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> beginAuth({
    required List<Map<String, dynamic>> lines,
    required String key,
  }) async {
    try {
      final raw = await client.rpc(
        'batata_commerce_checkout_begin',
        {
          'p_lines': lines,
          'p_shipping_method': 'Entrega em Mão (€0.00)',
          'p_payment_rail': 'stripe',
          'p_delivery': <String, dynamic>{},
          'p_client_idempotency_key': key,
          'p_confirm_remainder': false,
          'p_guest_token': null,
        },
        accessToken: buyerToken,
      );
      return Map<String, dynamic>.from(raw as Map);
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  final sRace = await seed(suffix: 'gidem', qty: 3);
  final gRace = await guestCreate(3600);
  final keyG = 'guest_idem_race_$tag';
  final linesG = [
    {
      'product_id': sRace['product_id'],
      'live_item_id': sRace['live_item_id'],
      'quantity': 1,
    }
  ];
  final raceG = await Future.wait([
    beginGuest(token: gRace['guest_token'] as String, lines: linesG, key: keyG),
    beginGuest(token: gRace['guest_token'] as String, lines: linesG, key: keyG),
  ]);
  final aidsG = raceG
      .map((r) => r['checkout_attempt_id']?.toString())
      .whereType<String>()
      .toSet();
  final okG = raceG.where((r) => r['ok'] == true).length;
  final attemptG = aidsG.isEmpty ? '' : aidsG.first;
  final ordersG = attemptG.isEmpty
      ? <dynamic>[]
      : await client.select('orders', filter: 'checkout_attempt_id=eq.$attemptG');
  final holdsG = attemptG.isEmpty
      ? <dynamic>[]
      : await client.select(
          'commerce_checkout_holds',
          filter: 'attempt_id=eq.$attemptG',
        );
  File('${outDir.path}/GUEST-IDEM-RACE-01.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'results': raceG,
      'distinct_attempts': aidsG.toList(),
      'orders': ordersG.length,
      'holds': holdsG.length,
    }),
  );
  add(
    'GUEST-IDEM-RACE-01',
    okG == 2 &&
        aidsG.length == 1 &&
        ordersG.length == 1 &&
        holdsG.length == 1,
    'ok=$okG attempts=${aidsG.length} orders=${ordersG.length} holds=${holdsG.length} reused=${raceG.map((r) => r['reused']).toList()}',
  );

  final sAuth = await seed(suffix: 'aidem', qty: 3);
  final keyA = 'auth_idem_race_$tag';
  final linesA = [
    {
      'product_id': sAuth['product_id'],
      'live_item_id': sAuth['live_item_id'],
      'quantity': 1,
    }
  ];
  final raceA = await Future.wait([
    beginAuth(lines: linesA, key: keyA),
    beginAuth(lines: linesA, key: keyA),
  ]);
  final aidsA = raceA
      .map((r) => r['checkout_attempt_id']?.toString())
      .whereType<String>()
      .toSet();
  final okA = raceA.where((r) => r['ok'] == true).length;
  final attemptA = aidsA.isEmpty ? '' : aidsA.first;
  final ordersA = attemptA.isEmpty
      ? <dynamic>[]
      : await client.select('orders', filter: 'checkout_attempt_id=eq.$attemptA');
  final holdsA = attemptA.isEmpty
      ? <dynamic>[]
      : await client.select(
          'commerce_checkout_holds',
          filter: 'attempt_id=eq.$attemptA',
        );
  File('${outDir.path}/AUTH-IDEM-RACE-01.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'results': raceA,
      'distinct_attempts': aidsA.toList(),
      'orders': ordersA.length,
      'holds': holdsA.length,
    }),
  );
  add(
    'AUTH-IDEM-RACE-01',
    okA == 2 &&
        aidsA.length == 1 &&
        ordersA.length == 1 &&
        holdsA.length == 1,
    'ok=$okA attempts=${aidsA.length} orders=${ordersA.length} holds=${holdsA.length} reused=${raceA.map((r) => r['reused']).toList()}',
  );

  add(
    'ONE-ATTEMPT-SET',
    checks.any((c) => c.id == 'GUEST-IDEM-RACE-01' && c.ok) &&
        checks.any((c) => c.id == 'AUTH-IDEM-RACE-01' && c.ok),
    'guest+auth race sets',
  );

  // ---------- Seed real bag_changed scenario for UI ----------
  final prodA = await seed(suffix: 'uia', qty: 5);
  final prodB = await seed(suffix: 'uib', qty: 1);
  // Use same live for both bag lines
  final liveId = prodA['live_id']!;
  await client.patch('live_items', 'id=eq.${prodB['live_item_id']}', {
    'live_id': liveId,
  });
  final ridA = await client.insert('live_reservation_requests', {
    'live_id': liveId,
    'live_item_id': prodA['live_item_id'],
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'status': 'accepted',
    'request_kind': 'guaranteed',
    'requested_qty': 1,
    'source': 'fleaber_live',
    'expires_at': DateTime.now()
        .toUtc()
        .add(const Duration(hours: 2))
        .toIso8601String(),
  });
  // B starts as bag_hold_none (no guaranteed cover) so zeroing stock makes it unavailable
  final ridB = await client.insert('live_reservation_requests', {
    'live_id': liveId,
    'live_item_id': prodB['live_item_id'],
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'status': 'pending',
    'request_kind': 'bag_hold_none',
    'requested_qty': 1,
    'source': 'fleaber_live',
  });

  final linesUi = [
    {
      'product_id': prodA['product_id'],
      'live_item_id': prodA['live_item_id'],
      'reservation_request_id': ridA['id'],
      'quantity': 1,
    },
    {
      'product_id': prodB['product_id'],
      'live_item_id': prodB['live_item_id'],
      'reservation_request_id': ridB['id'],
      'quantity': 1,
    },
  ];

  // Zero stock on B → revalidation marks B unavailable (bag_changed)
  await client.patch('products', 'id=eq.${prodB['product_id']}', {
    'quantity': 0,
    'is_sold': true,
  });

  final reval = await client.rpc(
    'batata_commerce_checkout_revalidate',
    {
      'p_lines': linesUi,
      'p_shipping_method': 'Entrega em Mão (€0.00)',
      'p_seller_id': null,
      'p_guest_token': null,
    },
    accessToken: buyerToken,
  ) as Map;

  final beginBc = await beginAuth(lines: linesUi, key: 'ui_bag_$tag');
  // beginAuth without confirm should hit bag_changed
  Map beginNeedConfirm = beginBc;
  if (beginBc['error']?.toString() != 'bag_changed_confirmation_required') {
    // try fresh key — stock already zero
    beginNeedConfirm = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': linesUi,
        'p_shipping_method': 'Entrega em Mão (€0.00)',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_client_idempotency_key': 'ui_bag2_$tag',
        'p_confirm_remainder': false,
        'p_guest_token': null,
      },
      accessToken: buyerToken,
    ) as Map;
  }

  final beginConfirm = await client.rpc(
    'batata_commerce_checkout_begin',
    {
      'p_lines': linesUi,
      'p_shipping_method': 'Entrega em Mão (€0.00)',
      'p_payment_rail': 'stripe',
      'p_delivery': <String, dynamic>{},
      'p_client_idempotency_key': 'ui_bag_confirm_$tag',
      'p_confirm_remainder': true,
      'p_guest_token': null,
    },
    accessToken: buyerToken,
  ) as Map;

  final uiLink = {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'live_id': liveId,
    'product_a': prodA,
    'product_b': prodB,
    'rid_a': ridA['id'],
    'rid_b': ridB['id'],
    'lines_initial': linesUi,
    'line_lost_stock': prodB['product_id'],
    'revalidation': reval,
    'begin_without_confirm': beginNeedConfirm,
    'begin_with_confirm': beginConfirm,
  };
  File('${outDir.path}/ui_backend_link.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(uiLink),
  );
  // Also write seed for Flutter evidence app
  File('${outDir.path}/ui_seed_for_app.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'live_id': liveId,
      'product_a_id': prodA['product_id'],
      'product_b_id': prodB['product_id'],
      'live_item_a_id': prodA['live_item_id'],
      'live_item_b_id': prodB['live_item_id'],
      'rid_a': ridA['id'],
      'rid_b': ridB['id'],
      'quote_after_confirm': beginConfirm['quote'],
      'unavailable_from_begin': beginNeedConfirm['revalidation'],
      'buyer_email': envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    }),
  );

  add(
    'UI-BACKEND-BAG-CHANGED',
    beginNeedConfirm['error']?.toString() ==
            'bag_changed_confirmation_required' &&
        beginConfirm['ok'] == true &&
        (beginConfirm['order_ids'] as List?)?.length == 1,
    'err=${beginNeedConfirm['error']} confirm_orders=${(beginConfirm['order_ids'] as List?)?.length}',
  );

  File('${outDir.path}/all_checks.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(
      checks.map((c) => {'id': c.id, 'ok': c.ok, 'detail': c.detail}).toList(),
    ),
  );

  final failed = checks.where((c) => !c.ok).toList();
  print(
    '\n=== SUMMARY ${checks.length - failed.length}/${checks.length} PASS ===',
  );
  for (final f in failed) {
    print('FAIL ${f.id} — ${f.detail}');
  }
  if (failed.isNotEmpty) exitCode = 1;
}
