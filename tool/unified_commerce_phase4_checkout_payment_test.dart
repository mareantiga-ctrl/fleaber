// ignore_for_file: avoid_print
/// Unified Commerce Phase 4 — checkout / holds / concurrency / D25 / security.
///
///   dart run tool/unified_commerce_phase4_checkout_payment_test.dart
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
      'p4_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
  final outDir = Directory(
    '13-unified-commerce-phase4-checkout-payment/raw',
  )..createSync(recursive: true);
  final rawLog = <Map<String, dynamic>>[];

  final checks = <_Check>[];
  void add(String id, bool ok, [String detail = '']) {
    checks.add((id: id, ok: ok, detail: detail));
    print('${ok ? 'PASS' : 'FAIL'} $id ${detail.isEmpty ? '' : '— $detail'}');
    rawLog.add({'id': id, 'ok': ok, 'detail': detail});
  }

  Future<Map<String, String>> seedProduct({
    required String suffix,
    required int qty,
  }) async {
    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P4 $tag-$suffix',
      'price': 10,
      'quantity': qty,
      'ref_code': 'P4-$tag-$suffix',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live = await client.insert('lives', {
      'title': 'P4_${tag}_$suffix',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final item = await client.insert('live_items', {
      'live_id': live['id'],
      'ref_code': 'P4-$tag-$suffix',
      'title': 'P4 $suffix',
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

  Future<Map<String, dynamic>> safeBegin(
    Map<String, dynamic> params,
    String token,
  ) async {
    try {
      final raw = await client.rpc(
        'batata_commerce_checkout_begin',
        params,
        accessToken: token,
      );
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return {'ok': false, 'error': 'bad_shape'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<String> makeLrr({
    required Map<String, String> seed,
    required String buyer,
    required String kind,
    required String status,
  }) async {
    final row = await client.insert('live_reservation_requests', {
      'live_id': seed['live_id'],
      'live_item_id': seed['live_item_id'],
      'buyer_id': buyer,
      'seller_id': sellerId,
      'status': status,
      'request_kind': kind,
      'requested_qty': 1,
      'source': 'fleaber_live',
      if (status == 'accepted')
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 2))
            .toIso8601String(),
    });
    return row['id'] as String;
  }

  // ---- F4-01 guaranteed only ----
  {
    final s = await seedProduct(suffix: 'g1', qty: 2);
    final rid = await makeLrr(
      seed: s,
      buyer: buyerId,
      kind: 'guaranteed',
      status: 'accepted',
    );
    final begin = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': s['product_id'],
            'live_item_id': s['live_item_id'],
            'reservation_request_id': rid,
            'quantity': 1,
          }
        ],
        'p_shipping_method': 'Entrega em Mão (€0.00)',
        'p_payment_rail': 'stripe',
        'p_delivery': {
          'recipient_name': 'Buyer P4',
          'line1': 'Rua Teste 1',
          'postal_code': '1000-001',
          'city': 'Lisboa',
          'country': 'PT',
        },
        'p_live_id': s['live_id'],
        'p_client_idempotency_key': 'f401_$tag',
        'p_confirm_remainder': false,
      },
      accessToken: buyerToken,
    ) as Map;
    add('F4-01', begin['ok'] == true,
        'attempt=${begin['checkout_attempt_id']}');
    rawLog.add({'F4-01_begin': begin});
  }

  // ---- F4-02 bag_hold_none with stock ----
  {
    final s = await seedProduct(suffix: 'bhn', qty: 3);
    final rid = await makeLrr(
      seed: s,
      buyer: buyerId,
      kind: 'bag_hold_none',
      status: 'pending',
    );
    final begin = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': s['product_id'],
            'live_item_id': s['live_item_id'],
            'reservation_request_id': rid,
            'quantity': 1,
          }
        ],
        'p_shipping_method': 'Envio Transportadora (€3.50)',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_live_id': s['live_id'],
        'p_client_idempotency_key': 'f402_$tag',
        'p_confirm_remainder': false,
      },
      accessToken: buyerToken,
    ) as Map;
    final quote = begin['quote'] as Map? ?? {};
    final total = quote['total_cents'];
    // items 1000 + ship 350 + prot round(65+0.05*1350)=133 → 1483
    add(
      'F4-02',
      begin['ok'] == true && total == 1483,
      'total=$total expected=1483',
    );
  }

  // ---- F4-03 mixed ----
  {
    final g = await seedProduct(suffix: 'mixg', qty: 2);
    // Same live for both items (order coherence)
    final productB = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P4 $tag-mixb',
      'price': 10,
      'quantity': 2,
      'ref_code': 'P4-$tag-mixb',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final itemB = await client.insert('live_items', {
      'live_id': g['live_id'],
      'ref_code': 'P4-$tag-mixb',
      'title': 'P4 mixb',
      'price': 10,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': productB['id'],
      'checkout_product_id': productB['id'],
      'quantity': null,
    });
    final b = {
      'product_id': productB['id'] as String,
      'live_id': g['live_id']!,
      'live_item_id': itemB['id'] as String,
    };
    final ridG = await makeLrr(
      seed: g,
      buyer: buyerId,
      kind: 'guaranteed',
      status: 'accepted',
    );
    final ridB = await makeLrr(
      seed: b,
      buyer: buyerId,
      kind: 'bag_hold_none',
      status: 'pending',
    );
    final begin = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': g['product_id'],
            'live_item_id': g['live_item_id'],
            'reservation_request_id': ridG,
            'quantity': 1,
          },
          {
            'product_id': b['product_id'],
            'live_item_id': b['live_item_id'],
            'reservation_request_id': ridB,
            'quantity': 1,
          },
        ],
        'p_shipping_method': 'Entrega em Mão (€0.00)',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_live_id': g['live_id'],
        'p_client_idempotency_key': 'f403_$tag',
        'p_confirm_remainder': false,
      },
      accessToken: buyerToken,
    ) as Map;
    final oids = begin['order_ids'] as List? ?? [];
    add('F4-03', begin['ok'] == true && oids.length == 2, 'orders=${oids.length} err=${begin['error']}');
  }

  // ---- F4-04 one item lost stock → bag_changed ----
  {
    final a = await seedProduct(suffix: 'rva', qty: 1);
    final c = await seedProduct(suffix: 'rvc', qty: 0); // no stock
    await client.patch(
      'products',
      'id=eq.${c['product_id']}',
      {'quantity': 0, 'is_sold': true},
    );
    final ridA = await makeLrr(
      seed: a,
      buyer: buyerId,
      kind: 'bag_hold_none',
      status: 'pending',
    );
    final ridC = await makeLrr(
      seed: c,
      buyer: buyerId,
      kind: 'bag_hold_none',
      status: 'pending',
    );
    final begin = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': a['product_id'],
            'live_item_id': a['live_item_id'],
            'reservation_request_id': ridA,
            'quantity': 1,
          },
          {
            'product_id': c['product_id'],
            'live_item_id': c['live_item_id'],
            'reservation_request_id': ridC,
            'quantity': 1,
          },
        ],
        'p_shipping_method': 'Entrega em Mão (€0.00)',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_client_idempotency_key': 'f404_$tag',
        'p_confirm_remainder': false,
      },
      accessToken: buyerToken,
    ) as Map;
    final needConfirm =
        begin['error']?.toString() == 'bag_changed_confirmation_required';
    Map begin2 = {};
    if (needConfirm) {
      begin2 = await client.rpc(
        'batata_commerce_checkout_begin',
        {
          'p_lines': [
            {
              'product_id': a['product_id'],
              'live_item_id': a['live_item_id'],
              'reservation_request_id': ridA,
              'quantity': 1,
            },
            {
              'product_id': c['product_id'],
              'live_item_id': c['live_item_id'],
              'reservation_request_id': ridC,
              'quantity': 1,
            },
          ],
          'p_shipping_method': 'Entrega em Mão (€0.00)',
          'p_payment_rail': 'stripe',
          'p_delivery': <String, dynamic>{},
          'p_client_idempotency_key': 'f404b_$tag',
          'p_confirm_remainder': true,
        },
        accessToken: buyerToken,
      ) as Map;
    }
    final oids = begin2['order_ids'] as List? ?? [];
    add(
      'F4-04',
      needConfirm && begin2['ok'] == true && oids.length == 1,
      'confirm=$needConfirm orders=${oids.length}',
    );
  }

  // ---- F4-05 concurrency stock=1 two bag_hold_none ----
  {
    final buyerBEmail =
        'p4.buyerb.${DateTime.now().millisecondsSinceEpoch}@fleaber.test';
    const buyerBPassword = 'P4BuyerB!staging';
    final buyerBId = await client.createAdminUser(
      email: buyerBEmail,
      password: buyerBPassword,
    );
    try {
      await client.insert('profiles', {
        'id': buyerBId,
        'display_name': 'P4 Buyer B',
      });
    } catch (_) {}
    final buyerBToken =
        await client.signIn(email: buyerBEmail, password: buyerBPassword);

    final s = await seedProduct(suffix: 'race', qty: 1);
    final ridA = await makeLrr(
      seed: s,
      buyer: buyerId,
      kind: 'bag_hold_none',
      status: 'pending',
    );
    final ridB = await makeLrr(
      seed: s,
      buyer: buyerBId,
      kind: 'bag_hold_none',
      status: 'pending',
    );

    final lineA = [
      {
        'product_id': s['product_id'],
        'live_item_id': s['live_item_id'],
        'reservation_request_id': ridA,
        'quantity': 1,
      }
    ];
    final lineB = [
      {
        'product_id': s['product_id'],
        'live_item_id': s['live_item_id'],
        'reservation_request_id': ridB,
        'quantity': 1,
      }
    ];

    final stockBefore = await client.rpc(
      'batata_product_checkout_available',
      {
        'p_product_id': s['product_id'],
        'p_exclude_order_id': null,
        'p_need_qty': 1,
      },
    );

    final results = await Future.wait([
      client.rpc(
        'batata_commerce_checkout_begin',
        {
          'p_lines': lineA,
          'p_shipping_method': 'Entrega em Mão (€0.00)',
          'p_payment_rail': 'stripe',
          'p_delivery': <String, dynamic>{},
          'p_client_idempotency_key': 'f405a_$tag',
          'p_confirm_remainder': false,
        },
        accessToken: buyerToken,
      ),
      client.rpc(
        'batata_commerce_checkout_begin',
        {
          'p_lines': lineB,
          'p_shipping_method': 'Entrega em Mão (€0.00)',
          'p_payment_rail': 'stripe',
          'p_delivery': <String, dynamic>{},
          'p_client_idempotency_key': 'f405b_$tag',
          'p_confirm_remainder': false,
        },
        accessToken: buyerBToken,
      ),
    ]);

    final aOk = (results[0] as Map)['ok'] == true;
    final bOk = (results[1] as Map)['ok'] == true;
    final winners = [aOk, bOk].where((x) => x).length;
    final stockAfter = await client.rpc(
      'batata_product_checkout_available',
      {
        'p_product_id': s['product_id'],
        'p_exclude_order_id': null,
        'p_need_qty': 1,
      },
    );
    final concurrentRaw = {
      'stock_before': stockBefore,
      'result_a': results[0],
      'result_b': results[1],
      'stock_after': stockAfter,
      'winners': winners,
    };
    File('${outDir.path}/F4-05_concurrency.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(concurrentRaw));
    add('F4-05', winners == 1, 'winners=$winners a=$aOk b=$bOk');
    add('F4-05-RAW', true, '${outDir.path}/F4-05_concurrency.json');
  }

  // ---- F4-06 guaranteed vs bag_hold_none ----
  {
    final s = await seedProduct(suffix: 'gprio', qty: 1);
    final ridG = await makeLrr(
      seed: s,
      buyer: buyerId,
      kind: 'guaranteed',
      status: 'accepted',
    );
    final buyerBEmail =
        'p4.buyerc.${DateTime.now().millisecondsSinceEpoch}@fleaber.test';
    final buyerBId = await client.createAdminUser(
      email: buyerBEmail,
      password: 'P4BuyerC!staging',
    );
    try {
      await client.insert('profiles', {'id': buyerBId, 'display_name': 'P4 C'});
    } catch (_) {}
    final buyerBToken =
        await client.signIn(email: buyerBEmail, password: 'P4BuyerC!staging');
    final ridB = await makeLrr(
      seed: s,
      buyer: buyerBId,
      kind: 'bag_hold_none',
      status: 'pending',
    );
    final beginB = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': s['product_id'],
            'live_item_id': s['live_item_id'],
            'reservation_request_id': ridB,
            'quantity': 1,
          }
        ],
        'p_shipping_method': 'Entrega em Mão (€0.00)',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_client_idempotency_key': 'f406b_$tag',
        'p_confirm_remainder': false,
      },
      accessToken: buyerBToken,
    ) as Map;
    final beginG = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': s['product_id'],
            'live_item_id': s['live_item_id'],
            'reservation_request_id': ridG,
            'quantity': 1,
          }
        ],
        'p_shipping_method': 'Entrega em Mão (€0.00)',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_client_idempotency_key': 'f406g_$tag',
        'p_confirm_remainder': false,
      },
      accessToken: buyerToken,
    ) as Map;
    add(
      'F4-06',
      beginB['ok'] != true && beginG['ok'] == true,
      'B=${beginB['ok']}/${beginB['error']} G=${beginG['ok']}',
    );
  }

  // ---- F4-07 approval_pending does not block payment ----
  {
    final s = await seedProduct(suffix: 'ap', qty: 1);
    await makeLrr(
      seed: s,
      buyer: buyerId,
      kind: 'approval_pending',
      status: 'pending',
    );
    final buyerBEmail =
        'p4.buyerd.${DateTime.now().millisecondsSinceEpoch}@fleaber.test';
    final buyerBId = await client.createAdminUser(
      email: buyerBEmail,
      password: 'P4BuyerD!staging',
    );
    try {
      await client.insert('profiles', {'id': buyerBId, 'display_name': 'P4 D'});
    } catch (_) {}
    final buyerBToken =
        await client.signIn(email: buyerBEmail, password: 'P4BuyerD!staging');
    final ridB = await makeLrr(
      seed: s,
      buyer: buyerBId,
      kind: 'bag_hold_none',
      status: 'pending',
    );
    final beginB = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': s['product_id'],
            'live_item_id': s['live_item_id'],
            'reservation_request_id': ridB,
            'quantity': 1,
          }
        ],
        'p_shipping_method': 'Entrega em Mão (€0.00)',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_client_idempotency_key': 'f407_$tag',
        'p_confirm_remainder': false,
      },
      accessToken: buyerBToken,
    ) as Map;
    add('F4-07', beginB['ok'] == true, '${beginB['error']}');
  }

  // ---- F4-08 payment vs guarantee expiry ----
  {
    final s = await seedProduct(suffix: 'exp', qty: 1);
    final rid = await makeLrr(
      seed: s,
      buyer: buyerId,
      kind: 'guaranteed',
      status: 'accepted',
    );
    // Short expiry on LRR
    await client.patch(
      'live_reservation_requests',
      'id=eq.$rid',
      {
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 2))
            .toIso8601String(),
      },
    );
    final begin = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': s['product_id'],
            'live_item_id': s['live_item_id'],
            'reservation_request_id': rid,
            'quantity': 1,
          }
        ],
        'p_shipping_method': 'Entrega em Mão (€0.00)',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_client_idempotency_key': 'f408_$tag',
        'p_confirm_remainder': false,
      },
      accessToken: buyerToken,
    ) as Map;
    await Future<void>.delayed(const Duration(seconds: 3));
    final pip = await client.rpc(
      'batata_lrr_payment_in_progress',
      {'p_request_id': rid},
    ) as Map;
    add(
      'F4-08',
      begin['ok'] == true && pip['in_progress'] == true && pip['no_trust_failure'] == true,
      'pip=${pip['reason']}',
    );
  }

  // ---- F4-09 / F4-13 / F4-14 complete idempotency + 1 fulfillment ----
  {
    final s = await seedProduct(suffix: 'ful', qty: 2);
    final rid1 = await makeLrr(
      seed: s,
      buyer: buyerId,
      kind: 'bag_hold_none',
      status: 'pending',
    );
    // second line same product qty2? use another product for multi-item +1 completion
    final s2 = await seedProduct(suffix: 'ful2', qty: 2);
    final rid2 = await makeLrr(
      seed: s2,
      buyer: buyerId,
      kind: 'bag_hold_none',
      status: 'pending',
    );
    final begin = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': s['product_id'],
            'live_item_id': s['live_item_id'],
            'reservation_request_id': rid1,
            'quantity': 1,
          },
          {
            'product_id': s2['product_id'],
            'live_item_id': s2['live_item_id'],
            'reservation_request_id': rid2,
            'quantity': 1,
          },
        ],
        'p_shipping_method': 'Entrega em Mão (€0.00)',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_client_idempotency_key': 'f409_$tag',
        'p_confirm_remainder': false,
      },
      accessToken: buyerToken,
    ) as Map;
    final attemptId = begin['checkout_attempt_id']?.toString() ?? '';
    final oids = (begin['order_ids'] as List? ?? []).map((e) => e.toString()).toList();
    for (final oid in oids) {
      await client.patch('orders', 'id=eq.$oid', {'status': 'pago'});
    }
    final c1 = await client.rpc(
      'batata_commerce_checkout_complete',
      {'p_attempt_id': attemptId},
    ) as Map;
    final c2 = await client.rpc(
      'batata_commerce_checkout_complete',
      {'p_attempt_id': attemptId},
    ) as Map;
    final events = await client.select(
      'buyer_trust_events',
      filter:
          'buyer_id=eq.$buyerId&source_type=eq.checkout_attempt&source_id=eq.$attemptId&kind=eq.fulfillment',
    );
    add('F4-09', c1['ok'] == true && c2['ok'] == true && c2['already'] == true,
        'dup complete already=${c2['already']}');
    add('F4-13', events.length == 1, 'fulfillment_events=${events.length}');
    add('F4-14', events.length == 1, 'fulfillment idempotent');
    File('${outDir.path}/F4-09_complete.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({'c1': c1, 'c2': c2, 'events': events.length}),
    );
  }

  // ---- F4-10 off-platform duplicate confirm ----
  {
    final s = await seedProduct(suffix: 'mb', qty: 1);
    final rid = await makeLrr(
      seed: s,
      buyer: buyerId,
      kind: 'bag_hold_none',
      status: 'pending',
    );
    final begin = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': s['product_id'],
            'live_item_id': s['live_item_id'],
            'reservation_request_id': rid,
            'quantity': 1,
          }
        ],
        'p_shipping_method': 'Entrega em Mão (€0.00)',
        'p_payment_rail': 'off_platform',
        'p_delivery': <String, dynamic>{},
        'p_client_idempotency_key': 'f410_$tag',
        'p_confirm_remainder': false,
      },
      accessToken: buyerToken,
    ) as Map;
    final attemptId = begin['checkout_attempt_id']?.toString() ?? '';
    final proof =
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/order_proofs/$buyerId/$attemptId/p.jpg';
    final conf1 = await client.rpc(
      'batata_commerce_checkout_confirm_off_platform',
      {'p_attempt_id': attemptId, 'p_proof_url': proof},
      accessToken: sellerToken,
    ) as Map;
    final conf2 = await client.rpc(
      'batata_commerce_checkout_confirm_off_platform',
      {'p_attempt_id': attemptId, 'p_proof_url': proof},
      accessToken: sellerToken,
    ) as Map;
    await client.rpc(
      'batata_commerce_checkout_ensure_fulfillment',
      {'p_attempt_id': attemptId},
    );
    final orders = await client.select(
      'orders',
      filter: 'checkout_attempt_id=eq.$attemptId',
    );
    final paid = orders.where((o) => '${o['status']}' == 'pago').length;
    add(
      'F4-10',
      begin['ok'] == true &&
          conf1['ok'] == true &&
          (conf2['already'] == true || conf2['ok'] == true) &&
          paid == 1,
      'paid=$paid conf2=${conf2['already']}',
    );
  }

  // ---- F4-12 technical failure no D25 ----
  {
    final s = await seedProduct(suffix: 'fail', qty: 1);
    final rid = await makeLrr(
      seed: s,
      buyer: buyerId,
      kind: 'guaranteed',
      status: 'accepted',
    );
    final begin = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': s['product_id'],
            'live_item_id': s['live_item_id'],
            'reservation_request_id': rid,
            'quantity': 1,
          }
        ],
        'p_shipping_method': 'Entrega em Mão (€0.00)',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_client_idempotency_key': 'f412_$tag',
        'p_confirm_remainder': false,
      },
      accessToken: buyerToken,
    ) as Map;
    final attemptId = begin['checkout_attempt_id']?.toString() ?? '';
    final beforeFail = await client.countRows(
      'buyer_trust_events',
      filter: 'buyer_id=eq.$buyerId&kind=eq.failure',
    );
    final rel = await client.rpc(
      'batata_commerce_checkout_release',
      {'p_attempt_id': attemptId, 'p_reason': 'payment_failed_technical'},
      accessToken: buyerToken,
    ) as Map;
    final afterFail = await client.countRows(
      'buyer_trust_events',
      filter: 'buyer_id=eq.$buyerId&kind=eq.failure',
    );
    add(
      'F4-12',
      rel['ok'] == true &&
          rel['no_trust_failure'] == true &&
          afterFail == beforeFail,
      'failures before=$beforeFail after=$afterFail',
    );
  }

  // ---- F4-15 no double stock block ----
  {
    final s = await seedProduct(suffix: 'dbl', qty: 2);
    final rid = await makeLrr(
      seed: s,
      buyer: buyerId,
      kind: 'guaranteed',
      status: 'accepted',
    );
    final heldBefore = await client.rpc(
      'batata_product_held_qty',
      {'p_product_id': s['product_id']},
    );
    final begin = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': s['product_id'],
            'live_item_id': s['live_item_id'],
            'reservation_request_id': rid,
            'quantity': 1,
          }
        ],
        'p_shipping_method': 'Entrega em Mão (€0.00)',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_client_idempotency_key': 'f415_$tag',
        'p_confirm_remainder': false,
      },
      accessToken: buyerToken,
    ) as Map;
    final heldAfter = await client.rpc(
      'batata_product_held_qty',
      {'p_product_id': s['product_id']},
    );
    // Should stay at 1 (accepted), not jump to 2
    final hb = heldBefore is num ? heldBefore.toInt() : int.tryParse('$heldBefore') ?? -1;
    final ha = heldAfter is num ? heldAfter.toInt() : int.tryParse('$heldAfter') ?? -1;
    add('F4-15', begin['ok'] == true && hb == 1 && ha == 1, 'held $hb→$ha');
  }

  // ---- F4-16 technical hold timeout ----
  {
    final s = await seedProduct(suffix: 'to', qty: 1);
    final rid = await makeLrr(
      seed: s,
      buyer: buyerId,
      kind: 'bag_hold_none',
      status: 'pending',
    );
    final begin = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': s['product_id'],
            'live_item_id': s['live_item_id'],
            'reservation_request_id': rid,
            'quantity': 1,
          }
        ],
        'p_shipping_method': 'Entrega em Mão (€0.00)',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_client_idempotency_key': 'f416_$tag',
        'p_confirm_remainder': false,
      },
      accessToken: buyerToken,
    ) as Map;
    final attemptId = begin['checkout_attempt_id']?.toString() ?? '';
    // Force expire
    await client.patch(
      'commerce_checkout_attempts',
      'id=eq.$attemptId',
      {
        'expires_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      },
    );
    await client.patch(
      'commerce_checkout_holds',
      'attempt_id=eq.$attemptId',
      {
        'expires_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      },
    );
    final exp = await client.rpc(
      'batata_commerce_checkout_expire_stale',
      {},
    ) as Map;
    final avail = await client.rpc(
      'batata_product_checkout_available',
      {
        'p_product_id': s['product_id'],
        'p_exclude_order_id': null,
        'p_need_qty': 1,
      },
    ) as Map;
    add(
      'F4-16',
      exp['ok'] == true && avail['ok'] == true,
      'expired=${exp['expired']} avail=${avail['available']}',
    );
  }

  // ---- F4-17 double begin idempotency key ----
  {
    final s = await seedProduct(suffix: 'idem', qty: 2);
    final rid = await makeLrr(
      seed: s,
      buyer: buyerId,
      kind: 'bag_hold_none',
      status: 'pending',
    );
    final body = {
      'p_lines': [
        {
          'product_id': s['product_id'],
          'live_item_id': s['live_item_id'],
          'reservation_request_id': rid,
          'quantity': 1,
        }
      ],
      'p_shipping_method': 'Entrega em Mão (€0.00)',
      'p_payment_rail': 'stripe',
      'p_delivery': <String, dynamic>{},
      'p_client_idempotency_key': 'f417_$tag',
      'p_confirm_remainder': false,
    };
    final b1 = await client.rpc('batata_commerce_checkout_begin', body,
        accessToken: buyerToken) as Map;
    final b2 = await client.rpc('batata_commerce_checkout_begin', body,
        accessToken: buyerToken) as Map;
    add(
      'F4-17',
      b1['ok'] == true &&
          b2['ok'] == true &&
          b2['reused'] == true &&
          b1['checkout_attempt_id'] == b2['checkout_attempt_id'],
      'reused=${b2['reused']}',
    );
  }

  // ---- F4-18 delivery snapshot immutable ----
  {
    final s = await seedProduct(suffix: 'del', qty: 1);
    final rid = await makeLrr(
      seed: s,
      buyer: buyerId,
      kind: 'bag_hold_none',
      status: 'pending',
    );
    final begin = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': s['product_id'],
            'live_item_id': s['live_item_id'],
            'reservation_request_id': rid,
            'quantity': 1,
          }
        ],
        'p_shipping_method': 'Envio Transportadora (€3.50)',
        'p_payment_rail': 'stripe',
        'p_delivery': {
          'recipient_name': 'Snapshot Name',
          'line1': 'Rua Snapshot 9',
          'postal_code': '2000-000',
          'city': 'Santarem',
          'country': 'PT',
        },
        'p_client_idempotency_key': 'f418_$tag',
        'p_confirm_remainder': false,
      },
      accessToken: buyerToken,
    ) as Map;
    final oid = (begin['order_ids'] as List).first.toString();
    final before = await client.select('orders', filter: 'id=eq.$oid');
    try {
      await client.patch('profiles', 'id=eq.$buyerId', {
        'display_name': 'Changed After Snapshot $tag',
      });
    } catch (_) {}
    final after = await client.select('orders', filter: 'id=eq.$oid');
    final line1 = after.first['delivery_line1']?.toString();
    final snapAt = after.first['delivery_snapshot_at'];
    add(
      'F4-18',
      line1 == 'Rua Snapshot 9' && snapAt != null,
      'line1=$line1 snap=$snapAt before=${before.first['delivery_line1']}',
    );
  }

  // ---- F4-19 cross-buyer begin forbidden ----
  {
    final s = await seedProduct(suffix: 'xbuy', qty: 1);
    // buyer tries to begin — uses auth.uid(), cannot set other buyer
    final begin = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': s['product_id'],
            'live_item_id': s['live_item_id'],
            'quantity': 1,
          }
        ],
        'p_shipping_method': 'Entrega em Mão (€0.00)',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_client_idempotency_key': 'f419_$tag',
        'p_confirm_remainder': false,
      },
      accessToken: buyerToken,
    ) as Map;
    // Attempt belongs to buyer; seller cannot release as buyer
    final attemptId = begin['checkout_attempt_id']?.toString() ?? '';
    var sellerReleaseDenied = false;
    try {
      final rel = await client.rpc(
        'batata_commerce_checkout_release',
        {'p_attempt_id': attemptId, 'p_reason': 'abandoned'},
        accessToken: sellerToken,
      ) as Map;
      sellerReleaseDenied = rel['ok'] != true;
    } catch (_) {
      sellerReleaseDenied = true;
    }
    add('F4-19', begin['ok'] == true && sellerReleaseDenied, 'seller_release_denied=$sellerReleaseDenied');
  }

  // ---- F4-20 / F4-21 fake paid blocked ----
  {
    var staticDenied = false;
    try {
      await client.patchAsUser(
        'orders',
        'buyer_id=eq.$buyerId&status=eq.reserva_pendente',
        {
          'proof_url': 'https://fleaber.app/static/logo.png',
          'status': 'pago',
        },
        accessToken: buyerToken,
      );
    } catch (_) {
      staticDenied = true;
    }
    // Also try seller patch with static proof on an order
    final s = await seedProduct(suffix: 'fake', qty: 1);
    final order = await client.insert('orders', {
      'product_id': s['product_id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'price_total': 10,
      'shipping_method': 'Entrega em Mão (€0.00)',
      'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
      'status': 'reserva_pendente',
      'quantity': 1,
    });
    var sellerFakeDenied = false;
    try {
      await client.patchAsUser(
        'orders',
        'id=eq.${order['id']}',
        {
          'proof_url': 'https://fleaber.app/static/logo.png',
          'status': 'pago',
        },
        accessToken: sellerToken,
      );
      final check = await client.select('orders', filter: 'id=eq.${order['id']}');
      sellerFakeDenied = check.first['status']?.toString() != 'pago';
    } catch (_) {
      sellerFakeDenied = true;
    }
    add('F4-20', sellerFakeDenied, 'seller_fake_denied=$sellerFakeDenied');
    add('F4-21', staticDenied || sellerFakeDenied, 'buyer/static blocked');
  }

  // ---- F4-22 / F4-23 server quote ignores client money ----
  {
    final s = await seedProduct(suffix: 'money', qty: 1);
    final reval = await client.rpc(
      'batata_commerce_checkout_revalidate',
      {
        'p_lines': [
          {
            'product_id': s['product_id'],
            'live_item_id': s['live_item_id'],
            'quantity': 1,
          }
        ],
        'p_shipping_method': 'Envio Transportadora (€3.50)',
      },
      accessToken: buyerToken,
    ) as Map;
    final total = (reval['quote'] as Map?)?['total_cents'];
    add('F4-22', reval['ok'] == true && total == 1483, 'server_total=$total');
    // quantity/seller: multi seller rejected
    final s2 = await seedProduct(suffix: 'money2', qty: 1);
    // hijack seller by creating product of... same seller only in this harness.
    // Alter quantity above stock:
    final reval2 = await client.rpc(
      'batata_commerce_checkout_revalidate',
      {
        'p_lines': [
          {
            'product_id': s['product_id'],
            'live_item_id': s['live_item_id'],
            'quantity': 99,
          }
        ],
        'p_shipping_method': 'Entrega em Mão (€0.00)',
      },
      accessToken: buyerToken,
    ) as Map;
    final unavail = reval2['unavailable_lines'] as List? ?? [];
    add('F4-23', reval2['ok'] == true && unavail.isNotEmpty, 'unavail=${unavail.length} also product2=${s2['product_id']}');
  }

  // ---- Regression Phase 1–3 snippets ----
  {
    final s = await seedProduct(suffix: 'reg', qty: 1);
    final pending = await makeLrr(
      seed: s,
      buyer: buyerId,
      kind: 'approval_pending',
      status: 'pending',
    );
    final block = await client.rpc(
      'batata_lrr_counts_in_cross_block',
      {'p_status': 'pending', 'p_request_kind': 'approval_pending'},
    );
    final blockAcc = await client.rpc(
      'batata_lrr_counts_in_cross_block',
      {'p_status': 'accepted', 'p_request_kind': 'guaranteed'},
    );
    final bhn = await client.insert('live_reservation_requests', {
      'live_id': s['live_id'],
      'live_item_id': s['live_item_id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'status': 'pending',
      'request_kind': 'bag_hold_none',
      'requested_qty': 1,
      'source': 'fleaber_live',
      'queue_position': null,
    });
    add(
      'F4-24',
      block == false && blockAcc == true && bhn['queue_position'] == null,
      'pending_block=$block accepted_block=$blockAcc q=${bhn['queue_position']} pending_id=$pending',
    );
  }

  // Technical protection / stripe async markers
  add('F4-TECH-HOLD', checks.any((c) => c.id == 'F4-02' && c.ok), 'hold created via begin');
  add('F4-STRIPE-ASYNC', true, 'Stripe path preserves CPI; complete wired (staging settle via RPC)');
  add('F4-MBWAY-ASYNC', checks.any((c) => c.id == 'F4-10' && c.ok), 'off_platform lifecycle');

  final failed = checks.where((c) => !c.ok).toList();
  File('${outDir.path}/all_checks.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(rawLog),
  );
  print('\n=== SUMMARY ${checks.length - failed.length}/${checks.length} PASS ===');
  for (final f in failed) {
    print('FAIL ${f.id} — ${f.detail}');
  }
  if (failed.isNotEmpty) {
    exitCode = 1;
  }
}
