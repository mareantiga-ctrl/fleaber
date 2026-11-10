// ignore_for_file: avoid_print
/// Phase 4 final correction — guest foundation + authenticated regression.
///
///   dart run tool/unified_commerce_phase4_guest_correction_test.dart
library;

import 'dart:async';
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
      'p4g_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
  final outDir = Directory(
    '13-unified-commerce-phase4-final-correction/raw',
  )..createSync(recursive: true);

  final checks = <_Check>[];
  void add(String id, bool ok, [String detail = '']) {
    checks.add((id: id, ok: ok, detail: detail));
    print('${ok ? 'PASS' : 'FAIL'} $id ${detail.isEmpty ? '' : '— $detail'}');
  }

  Future<Map<String, String>> seed({required String suffix, required int qty}) async {
    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P4G $tag-$suffix',
      'price': 10,
      'quantity': qty,
      'ref_code': 'P4G-$tag-$suffix',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live = await client.insert('lives', {
      'title': 'P4G_${tag}_$suffix',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final item = await client.insert('live_items', {
      'live_id': live['id'],
      'ref_code': 'P4G-$tag-$suffix',
      'title': 'P4G $suffix',
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

  Future<Map<String, dynamic>> guestCreate() async {
    final raw = await client.rpc('batata_commerce_guest_session_create', {
      'p_ttl_seconds': 3600,
    });
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<Map<String, dynamic>> beginGuest({
    required String token,
    required List<Map<String, dynamic>> lines,
    required String key,
    Map<String, dynamic>? delivery,
    bool confirm = false,
  }) async {
    try {
      final raw = await client.rpc(
        'batata_commerce_checkout_begin',
        {
          'p_lines': lines,
          'p_shipping_method': 'Entrega em Mão (€0.00)',
          'p_payment_rail': 'stripe',
          'p_delivery': delivery ?? <String, dynamic>{},
          'p_client_idempotency_key': key,
          'p_confirm_remainder': confirm,
          'p_guest_token': token,
        },
      );
      return Map<String, dynamic>.from(raw as Map);
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> beginAuth({
    required List<Map<String, dynamic>> lines,
    required String key,
    String? rid,
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
          // Explicit null → single 8-arg signature (avoids PGRST203 overload)
          'p_guest_token': null,
        },
        accessToken: buyerToken,
      );
      return Map<String, dynamic>.from(raw as Map);
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  // ---------- GUEST-01..03 ----------
  final gA = await guestCreate();
  add('GUEST-01', gA['ok'] == true && gA['guest_token'] != null,
      'session=${gA['guest_session_id']}');

  final s1 = await seed(suffix: 'g1', qty: 2);
  final begin1 = await beginGuest(
    token: gA['guest_token'] as String,
    lines: [
      {
        'product_id': s1['product_id'],
        'live_item_id': s1['live_item_id'],
        'quantity': 1,
      }
    ],
    key: 'g01_$tag',
    delivery: {
      'recipient_name': 'Guest A',
      'line1': 'Rua Guest 1',
      'postal_code': '1000-100',
      'city': 'Lisboa',
      'country': 'PT',
    },
  );
  add('GUEST-02', begin1['ok'] == true && begin1['mode'] == 'guest',
      'attempt=${begin1['checkout_attempt_id']}');

  // Null guest token as anon → identity_required
  Map<String, dynamic> beginNull = {};
  try {
    final raw = await client.rpc('batata_commerce_checkout_begin', {
      'p_lines': [
        {
          'product_id': s1['product_id'],
          'live_item_id': s1['live_item_id'],
          'quantity': 1,
        }
      ],
      'p_shipping_method': 'Entrega em Mão (€0.00)',
      'p_payment_rail': 'stripe',
      'p_delivery': <String, dynamic>{},
      'p_client_idempotency_key': 'g03_$tag',
      'p_confirm_remainder': false,
      'p_guest_token': null,
    });
    beginNull = Map<String, dynamic>.from(raw as Map);
  } catch (e) {
    beginNull = {'ok': false, 'error': e.toString()};
  }
  add(
    'GUEST-03',
    beginNull['ok'] != true &&
        '${beginNull['error']}'.contains('identity_required'),
    '${beginNull['error']}',
  );

  // ---------- GUEST-04 cross-guest ----------
  final gB = await guestCreate();
  final attemptA = begin1['checkout_attempt_id']?.toString() ?? '';
  final getB = await client.rpc('batata_commerce_checkout_get_attempt', {
    'p_attempt_id': attemptA,
    'p_guest_token': gB['guest_token'],
  }) as Map;
  add('GUEST-04', getB['ok'] != true && getB['error'] == 'forbidden',
      '${getB['error']}');

  // ---------- GUEST-05 / 06 trust isolation ----------
  final failBefore = await client.countRows(
    'buyer_trust_events',
    filter: 'kind=eq.failure',
  );
  final fulfillBefore = await client.countRows(
    'buyer_trust_events',
    filter: 'kind=eq.fulfillment&source_id=eq.$attemptA',
  );
  final completeGuest = await client.rpc('batata_commerce_checkout_complete', {
    'p_attempt_id': attemptA,
  }) as Map;
  final fulfillAfter = await client.countRows(
    'buyer_trust_events',
    filter: 'kind=eq.fulfillment&source_id=eq.$attemptA',
  );
  add(
    'GUEST-05',
    completeGuest['ok'] == true &&
        (completeGuest['fulfillment'] as Map?)?['skipped'] == true &&
        fulfillAfter == fulfillBefore,
    'fulfill skipped',
  );

  final sFail = await seed(suffix: 'gfail', qty: 1);
  final gFail = await guestCreate();
  final beginFail = await beginGuest(
    token: gFail['guest_token'] as String,
    lines: [
      {
        'product_id': sFail['product_id'],
        'live_item_id': sFail['live_item_id'],
        'quantity': 1,
      }
    ],
    key: 'g06_$tag',
  );
  final rel = await client.rpc('batata_commerce_checkout_release', {
    'p_attempt_id': beginFail['checkout_attempt_id'],
    'p_reason': 'payment_failed_technical',
    'p_guest_token': gFail['guest_token'],
  }) as Map;
  final failAfter = await client.countRows(
    'buyer_trust_events',
    filter: 'kind=eq.failure',
  );
  add(
    'GUEST-06',
    rel['ok'] == true &&
        rel['no_trust_failure'] == true &&
        failAfter == failBefore,
    'failures=$failBefore→$failAfter',
  );

  // ---------- GUEST-07 idempotency ----------
  final sIdem = await seed(suffix: 'gidem', qty: 2);
  final gIdem = await guestCreate();
  final b1 = await beginGuest(
    token: gIdem['guest_token'] as String,
    lines: [
      {
        'product_id': sIdem['product_id'],
        'live_item_id': sIdem['live_item_id'],
        'quantity': 1,
      }
    ],
    key: 'g07_$tag',
  );
  final b2 = await beginGuest(
    token: gIdem['guest_token'] as String,
    lines: [
      {
        'product_id': sIdem['product_id'],
        'live_item_id': sIdem['live_item_id'],
        'quantity': 1,
      }
    ],
    key: 'g07_$tag',
  );
  add(
    'GUEST-07',
    b1['ok'] == true &&
        b2['reused'] == true &&
        b1['checkout_attempt_id'] == b2['checkout_attempt_id'],
    'reused=${b2['reused']}',
  );

  // ---------- GUEST-08 / 09 concurrency ----------
  final sRace = await seed(suffix: 'grace', qty: 1);
  final gR1 = await guestCreate();
  final gR2 = await guestCreate();
  final race = await Future.wait([
    beginGuest(
      token: gR1['guest_token'] as String,
      lines: [
        {
          'product_id': sRace['product_id'],
          'live_item_id': sRace['live_item_id'],
          'quantity': 1,
        }
      ],
      key: 'g08a_$tag',
    ),
    beginGuest(
      token: gR2['guest_token'] as String,
      lines: [
        {
          'product_id': sRace['product_id'],
          'live_item_id': sRace['live_item_id'],
          'quantity': 1,
        }
      ],
      key: 'g08b_$tag',
    ),
  ]);
  final winners =
      race.where((r) => r['ok'] == true).length;
  File('${outDir.path}/GUEST-08_concurrency.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({'results': race, 'winners': winners}),
  );
  add('GUEST-08', winners == 1, 'guest-guest winners=$winners');

  final sRace2 = await seed(suffix: 'gauth', qty: 1);
  final gVs = await guestCreate();
  final race2 = await Future.wait([
    beginAuth(
      lines: [
        {
          'product_id': sRace2['product_id'],
          'live_item_id': sRace2['live_item_id'],
          'quantity': 1,
        }
      ],
      key: 'g09a_$tag',
    ),
    beginGuest(
      token: gVs['guest_token'] as String,
      lines: [
        {
          'product_id': sRace2['product_id'],
          'live_item_id': sRace2['live_item_id'],
          'quantity': 1,
        }
      ],
      key: 'g09b_$tag',
    ),
  ]);
  final w2 = race2.where((r) => r['ok'] == true).length;
  File('${outDir.path}/GUEST-09_auth_vs_guest.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({'results': race2, 'winners': w2}),
  );
  add('GUEST-09', w2 == 1, 'auth-vs-guest winners=$w2');

  // ---------- GUEST-10 / 11 order + complete idempotency ----------
  final sPay = await seed(suffix: 'gpay', qty: 1);
  final gPay = await guestCreate();
  final beginPay = await beginGuest(
    token: gPay['guest_token'] as String,
    lines: [
      {
        'product_id': sPay['product_id'],
        'live_item_id': sPay['live_item_id'],
        'quantity': 1,
      }
    ],
    key: 'g10_$tag',
  );
  final aid = beginPay['checkout_attempt_id']?.toString() ?? '';
  final oids = (beginPay['order_ids'] as List? ?? []).map((e) => '$e').toList();
  for (final oid in oids) {
    await client.patch('orders', 'id=eq.$oid', {'status': 'pago'});
  }
  final c1 = await client.rpc('batata_commerce_checkout_complete', {
    'p_attempt_id': aid,
  }) as Map;
  final c2 = await client.rpc('batata_commerce_checkout_complete', {
    'p_attempt_id': aid,
  }) as Map;
  final orders = await client.select('orders', filter: 'checkout_attempt_id=eq.$aid');
  add('GUEST-10', beginPay['ok'] == true && orders.length == 1, 'orders=${orders.length}');
  add('GUEST-11', c1['ok'] == true && c2['already'] == true, 'dup complete');

  // ---------- GUEST-12 / 13 delivery snapshot ----------
  final getOwn = await client.rpc('batata_commerce_checkout_get_attempt', {
    'p_attempt_id': begin1['checkout_attempt_id'],
    'p_guest_token': gA['guest_token'],
  }) as Map;
  final att = getOwn['attempt'] as Map? ?? {};
  add(
    'GUEST-12',
    getOwn['ok'] == true &&
        att['delivery_line1'] == 'Rua Guest 1' &&
        att['delivery_snapshot_at'] != null,
    'line1=${att['delivery_line1']}',
  );
  // mutate attempt delivery should be frozen after snapshot — try patch via service
  // freeze trigger on orders; check order snapshot unchanged after profile-less "change"
  final oidSnap = (begin1['order_ids'] as List).first.toString();
  final before = await client.select('orders', filter: 'id=eq.$oidSnap');
  try {
    await client.patch('orders', 'id=eq.$oidSnap', {
      'delivery_line1': 'HACKED',
    });
  } catch (_) {}
  final after = await client.select('orders', filter: 'id=eq.$oidSnap');
  final still = after.first['delivery_line1']?.toString();
  add(
    'GUEST-13',
    still == 'Rua Guest 1' || still == before.first['delivery_line1'],
    'after=$still (frozen or unchanged)',
  );

  // ---------- GUEST-14 authenticated still works ----------
  final sAuth = await seed(suffix: 'auth', qty: 2);
  final rid = await client.insert('live_reservation_requests', {
    'live_id': sAuth['live_id'],
    'live_item_id': sAuth['live_item_id'],
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'status': 'accepted',
    'request_kind': 'guaranteed',
    'requested_qty': 1,
    'source': 'fleaber_live',
    'expires_at': DateTime.now().toUtc().add(const Duration(hours: 2)).toIso8601String(),
  });
  final authBegin = await beginAuth(
    lines: [
      {
        'product_id': sAuth['product_id'],
        'live_item_id': sAuth['live_item_id'],
        'reservation_request_id': rid['id'],
        'quantity': 1,
      }
    ],
    key: 'g14_$tag',
  );
  add('GUEST-14', authBegin['ok'] == true && authBegin['mode'] == 'authenticated',
      '${authBegin['error']}');

  // ---------- AUTH regression sample ----------
  final sMix = await seed(suffix: 'mix', qty: 2);
  final sMix2Prod = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'P4G mix2',
    'price': 10,
    'quantity': 2,
    'ref_code': 'P4G-$tag-mix2',
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final sMix2Item = await client.insert('live_items', {
    'live_id': sMix['live_id'],
    'ref_code': 'P4G-$tag-mix2',
    'title': 'mix2',
    'price': 10,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': sMix2Prod['id'],
    'checkout_product_id': sMix2Prod['id'],
  });
  final ridG = await client.insert('live_reservation_requests', {
    'live_id': sMix['live_id'],
    'live_item_id': sMix['live_item_id'],
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'status': 'accepted',
    'request_kind': 'guaranteed',
    'requested_qty': 1,
    'source': 'fleaber_live',
    'expires_at': DateTime.now().toUtc().add(const Duration(hours: 2)).toIso8601String(),
  });
  final ridB = await client.insert('live_reservation_requests', {
    'live_id': sMix['live_id'],
    'live_item_id': sMix2Item['id'],
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'status': 'pending',
    'request_kind': 'bag_hold_none',
    'requested_qty': 1,
    'source': 'fleaber_live',
  });
  final mix = await beginAuth(
    lines: [
      {
        'product_id': sMix['product_id'],
        'live_item_id': sMix['live_item_id'],
        'reservation_request_id': ridG['id'],
        'quantity': 1,
      },
      {
        'product_id': sMix2Prod['id'],
        'live_item_id': sMix2Item['id'],
        'reservation_request_id': ridB['id'],
        'quantity': 1,
      },
    ],
    key: 'reg_mix_$tag',
  );
  add(
    'AUTH-REG-MIX',
    mix['ok'] == true && (mix['order_ids'] as List?)?.length == 2,
    '${mix['error'] ?? mix}',
  );

  Map ifthenRail = {};
  try {
    final ifpSeed = await seed(suffix: 'ifp', qty: 1);
    ifthenRail = await client.rpc('batata_commerce_checkout_begin', {
      'p_lines': [
        {
          'product_id': ifpSeed['product_id'],
          'live_item_id': ifpSeed['live_item_id'],
          'quantity': 1,
        }
      ],
      'p_shipping_method': 'Entrega em Mão (€0.00)',
      'p_payment_rail': 'ifthenpay',
      'p_delivery': <String, dynamic>{},
      'p_client_idempotency_key': 'ifp_$tag',
      'p_confirm_remainder': false,
      'p_guest_token': null,
    }, accessToken: buyerToken) as Map;
  } catch (e) {
    ifthenRail = {'ok': false, 'error': e.toString()};
  }
  add(
    'IFTHENPAY-PREPARED',
    ifthenRail['error']?.toString() == 'ifthenpay_integration_pending' ||
        '${ifthenRail['error']}'.contains('ifthenpay_integration_pending'),
    '${ifthenRail['error']}',
  );

  File('${outDir.path}/all_checks.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(
      checks.map((c) => {'id': c.id, 'ok': c.ok, 'detail': c.detail}).toList(),
    ),
  );

  final failed = checks.where((c) => !c.ok).toList();
  print('\n=== SUMMARY ${checks.length - failed.length}/${checks.length} PASS ===');
  for (final f in failed) {
    print('FAIL ${f.id} — ${f.detail}');
  }
  if (failed.isNotEmpty) exitCode = 1;
}
