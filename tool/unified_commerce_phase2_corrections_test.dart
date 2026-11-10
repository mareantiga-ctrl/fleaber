// ignore_for_file: avoid_print
/// Phase 2 corrections — payment ceiling + zero-stock UNAVAILABLE.
///
///   dart run tool/unified_commerce_phase2_corrections_test.dart
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
  final buyerB = sellerId;

  final checks = <_Check>[];
  void add(String id, bool ok, [String detail = '']) {
    checks.add((id: id, ok: ok, detail: detail));
    print('${ok ? 'PASS' : 'FAIL'} $id ${detail.isEmpty ? '' : '— $detail'}');
  }

  final tag =
      'p2c_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  Future<void> wipeTrust() async {
    await client.deleteWhere('buyer_trust_events', 'buyer_id=eq.$buyerId');
    await client.deleteWhere('buyer_trust_state', 'buyer_id=eq.$buyerId');
    await client.deleteWhere(
      'seller_buyer_trust',
      'seller_id=eq.$sellerId&buyer_id=eq.$buyerId',
    );
  }

  Future<void> upsertPolicy({
    required String mode,
    required String untrusted,
    int normalTtl = 1800,
    int trustedTtl = 3600,
  }) async {
    final existing = await client.select(
      'seller_reservation_settings',
      filter: 'seller_id=eq.$sellerId',
      limit: 1,
    );
    if (existing.isEmpty) {
      await client.insert('seller_reservation_settings', {
        'seller_id': sellerId,
        'policy_mode': mode,
        'untrusted_mode': untrusted,
        'normal_ttl_seconds': normalTtl,
        'trusted_ttl_seconds': trustedTtl,
        'accept_fleaber_global_trust': true,
      });
    } else {
      await client.patch(
        'seller_reservation_settings',
        'seller_id=eq.$sellerId',
        {
          'policy_mode': mode,
          'untrusted_mode': untrusted,
          'normal_ttl_seconds': normalTtl,
          'trusted_ttl_seconds': trustedTtl,
        },
      );
    }
  }

  Future<Map<String, String>> seedItem({
    required String suffix,
    int qty = 1,
  }) async {
    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P2C product $tag-$suffix',
      'price': 5,
      'quantity': qty,
      'ref_code': 'P2C-$tag-$suffix',
      'list_on_marketplace': false,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live = await client.insert('lives', {
      'title': 'P2C_${tag}_$suffix',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final item = await client.insert('live_items', {
      'live_id': live['id'],
      'ref_code': 'P2C-$tag-$suffix',
      'title': 'P2C item $suffix',
      'price': 5,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': product['id'],
      'checkout_product_id': product['id'],
      'quantity': null,
    });
    return {
      'productId': product['id']!.toString(),
      'liveId': live['id']!.toString(),
      'itemId': item['id']!.toString(),
    };
  }

  Future<String> makeGuaranteed({
    required Map<String, String> s,
    required String buyer,
  }) async {
    final r = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyer,
      'p_live_id': s['liveId'],
      'p_live_item_id': s['itemId'],
      'p_qty': 1,
    });
    if (r is! Map || r['request_id'] == null) {
      throw StateError('expected guaranteed, got $r');
    }
    return r['request_id'].toString();
  }

  await client.patch('profiles', 'id=eq.$sellerId', {'hub_published': true});
  await wipeTrust();
  await upsertPolicy(mode: 'trust', untrusted: 'approval');

  final createdRequestIds = <String>[];
  final createdItemIds = <String>[];
  final createdLiveIds = <String>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];

  try {
    // ------------------------------------------------------------------
    // A) Stripe recent (5 min) → protected
    // ------------------------------------------------------------------
    final sA = await seedItem(suffix: 'A', qty: 1);
    createdProductIds.add(sA['productId']!);
    createdLiveIds.add(sA['liveId']!);
    createdItemIds.add(sA['itemId']!);
    final idA = await makeGuaranteed(s: sA, buyer: buyerId);
    createdRequestIds.add(idA);
    final ordA = await client.insert('orders', {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': sA['productId'],
      'live_id': sA['liveId'],
      'live_item_id': sA['itemId'],
      'quantity': 1,
      'price_total': 5,
      'status': 'aguarda_pagamento',
      'payment_method': 'stripe',
      'stripe_payment_intent_id': 'pi_recent_$tag',
    });
    createdOrderIds.add(ordA['id']!.toString());
    // Force created_at ~5 min ago via SQL-ish: patch not allowed on created_at usually.
    // Use payment detector with p_now = created_at + 5m by reading order created_at.
    final ordARow = (await client.select('orders', filter: 'id=eq.${ordA['id']}', limit: 1)).first;
    final createdA = DateTime.parse(ordARow['created_at'].toString()).toUtc();
    await client.patch('live_reservation_requests', 'id=eq.$idA', {
      'notes': 'stripe_checkout:${ordA['id']}',
      'expires_at': createdA.add(const Duration(minutes: 1)).toIso8601String(),
    });
    final payA = await client.rpc('batata_lrr_payment_in_progress', {
      'p_request_id': idA,
      'p_now': createdA.add(const Duration(minutes: 5)).toIso8601String(),
    });
    add(
      'A.stripe_recent_5m_protected',
      payA is Map &&
          payA['in_progress'] == true &&
          payA['reason'] == 'legitimate_payment_processing',
      '$payA',
    );

    // ------------------------------------------------------------------
    // B) Stripe stale >30m with PI/session/tag → NOT protected
    // ------------------------------------------------------------------
    final payB = await client.rpc('batata_lrr_payment_in_progress', {
      'p_request_id': idA,
      'p_now': createdA.add(const Duration(minutes: 31)).toIso8601String(),
    });
    add(
      'B.stripe_stale_over_30m_not_protected',
      payB is Map &&
          payB['in_progress'] == false &&
          payB['reason'] == 'payment_stale_beyond_ceiling' &&
          payB['had_payment_intent'] == true &&
          payB['had_checkout_tag'] == true,
      '$payB',
    );

    // F) expiry after ceiling → leaves accepted
    final expB = await client.rpc('batata_expire_guaranteed_reservations', {
      'p_now': createdA.add(const Duration(minutes: 31)).toIso8601String(),
      'p_request_id': idA,
    });
    final rowB = (await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$idA',
      limit: 1,
    )).first;
    add(
      'F.expiry_after_ceiling_not_stuck_accepted',
      expB is Map &&
          expB['expired'] >= 1 &&
          rowB['status'] == 'expired' &&
          rowB['expiry_reason'] == 'guaranteed_hold_expired_unpaid',
      'exp=$expB status=${rowB['status']} reason=${rowB['expiry_reason']}',
    );

    // ------------------------------------------------------------------
    // C) MB WAY recent 5m → protected
    // ------------------------------------------------------------------
    await wipeTrust();
    final sC = await seedItem(suffix: 'C', qty: 1);
    createdProductIds.add(sC['productId']!);
    createdLiveIds.add(sC['liveId']!);
    createdItemIds.add(sC['itemId']!);
    final idC = await makeGuaranteed(s: sC, buyer: buyerId);
    createdRequestIds.add(idC);
    final ordC = await client.insert('orders', {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': sC['productId'],
      'live_id': sC['liveId'],
      'live_item_id': sC['itemId'],
      'quantity': 1,
      'price_total': 5,
      'status': 'aguarda_pagamento',
      'payment_method': 'mbway',
      'stripe_payment_intent_id': 'pi_mbway_$tag', // id present must NOT bypass ceiling
    });
    createdOrderIds.add(ordC['id']!.toString());
    final ordCRow = (await client.select('orders', filter: 'id=eq.${ordC['id']}', limit: 1)).first;
    final createdC = DateTime.parse(ordCRow['created_at'].toString()).toUtc();
    await client.patch('live_reservation_requests', 'id=eq.$idC', {
      'notes': 'stripe_checkout:${ordC['id']}',
      'expires_at': createdC.add(const Duration(minutes: 1)).toIso8601String(),
    });
    final payC = await client.rpc('batata_lrr_payment_in_progress', {
      'p_request_id': idC,
      'p_now': createdC.add(const Duration(minutes: 5)).toIso8601String(),
    });
    add(
      'C.mbway_recent_5m_protected',
      payC is Map &&
          payC['in_progress'] == true &&
          payC['ceiling_seconds'] == 900,
      '$payC',
    );

    // ------------------------------------------------------------------
    // D) MB WAY stale >15m unpaid → NOT protected
    // ------------------------------------------------------------------
    final payD = await client.rpc('batata_lrr_payment_in_progress', {
      'p_request_id': idC,
      'p_now': createdC.add(const Duration(minutes: 16)).toIso8601String(),
    });
    add(
      'D.mbway_stale_over_15m_not_protected',
      payD is Map &&
          payD['in_progress'] == false &&
          payD['reason'] == 'payment_stale_beyond_ceiling' &&
          payD['had_payment_intent'] == true,
      '$payD',
    );

    // ------------------------------------------------------------------
    // E) paid/fulfilled → never abandonment / always protected
    // ------------------------------------------------------------------
    await wipeTrust();
    final sE = await seedItem(suffix: 'E', qty: 1);
    createdProductIds.add(sE['productId']!);
    createdLiveIds.add(sE['liveId']!);
    createdItemIds.add(sE['itemId']!);
    final idE = await makeGuaranteed(s: sE, buyer: buyerId);
    createdRequestIds.add(idE);
    final ordE = await client.insert('orders', {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': sE['productId'],
      'live_id': sE['liveId'],
      'live_item_id': sE['itemId'],
      'quantity': 1,
      'price_total': 5,
      'status': 'pago',
      'payment_method': 'stripe',
      'stripe_payment_intent_id': 'pi_paid_$tag',
      'stock_units_applied': 1,
      'amount_paid_cents': 500,
    });
    createdOrderIds.add(ordE['id']!.toString());
    final ordERow = (await client.select('orders', filter: 'id=eq.${ordE['id']}', limit: 1)).first;
    final createdE = DateTime.parse(ordERow['created_at'].toString()).toUtc();
    await client.patch('live_reservation_requests', 'id=eq.$idE', {
      'notes': 'stripe_checkout:${ordE['id']}',
      'expires_at': createdE.subtract(const Duration(hours: 2)).toIso8601String(),
    });
    final payE = await client.rpc('batata_lrr_payment_in_progress', {
      'p_request_id': idE,
      'p_now': createdE.add(const Duration(hours: 5)).toIso8601String(),
    });
    final expE = await client.rpc('batata_expire_guaranteed_reservations', {
      'p_now': createdE.add(const Duration(hours: 5)).toIso8601String(),
      'p_request_id': idE,
    });
    final failE = await client.select(
      'buyer_trust_events',
      filter: 'buyer_id=eq.$buyerId&kind=eq.failure&source_id=eq.$idE',
      limit: 3,
    );
    final rowE = (await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$idE',
      limit: 1,
    )).first;
    add(
      'E.paid_fulfilled_never_abandonment',
      payE is Map &&
          payE['in_progress'] == true &&
          payE['reason'] == 'already_paid_or_fulfilled' &&
          expE is Map &&
          expE['payment_deferred'] >= 1 &&
          rowE['status'] == 'accepted' &&
          failE.isEmpty,
      'pay=$payE exp=$expE status=${rowE['status']} fails=${failE.length}',
    );

    // ------------------------------------------------------------------
    // 1–3) zero stock → UNAVAILABLE (trusted / approval / pay_required)
    // ------------------------------------------------------------------
    await wipeTrust();
    final s0 = await seedItem(suffix: 'Z0', qty: 0);
    createdProductIds.add(s0['productId']!);
    createdLiveIds.add(s0['liveId']!);
    createdItemIds.add(s0['itemId']!);
    await client.patch('products', 'id=eq.${s0['productId']}', {'quantity': 0});

    await upsertPolicy(mode: 'trust', untrusted: 'approval');
    final zTrusted = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s0['liveId'],
      'p_live_item_id': s0['itemId'],
    });
    add(
      '1.zero_stock_trusted_unavailable',
      zTrusted is Map &&
          zTrusted['outcome'] == 'UNAVAILABLE' &&
          zTrusted['request_id'] == null,
      '$zTrusted',
    );

    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
      accessToken: sellerToken,
    );
    final beforePending = await client.countRows(
      'live_reservation_requests',
      filter:
          'live_item_id=eq.${s0['itemId']}&request_kind=eq.approval_pending&status=eq.pending',
    );
    final zApproval = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s0['liveId'],
      'p_live_item_id': s0['itemId'],
    });
    final afterPending = await client.countRows(
      'live_reservation_requests',
      filter:
          'live_item_id=eq.${s0['itemId']}&request_kind=eq.approval_pending&status=eq.pending',
    );
    add(
      '2.zero_stock_approval_unavailable_no_pending',
      zApproval is Map &&
          zApproval['outcome'] == 'UNAVAILABLE' &&
          zApproval['request_id'] == null &&
          afterPending == beforePending,
      'r=$zApproval before=$beforePending after=$afterPending',
    );

    await wipeTrust();
    await upsertPolicy(mode: 'pay_only', untrusted: 'pay_required');
    final beforeBag = await client.countRows(
      'live_reservation_requests',
      filter:
          'live_item_id=eq.${s0['itemId']}&request_kind=eq.bag_hold_none',
    );
    final zBag = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s0['liveId'],
      'p_live_item_id': s0['itemId'],
    });
    final afterBag = await client.countRows(
      'live_reservation_requests',
      filter:
          'live_item_id=eq.${s0['itemId']}&request_kind=eq.bag_hold_none',
    );
    add(
      '3.zero_stock_pay_required_unavailable_no_bag',
      zBag is Map &&
          zBag['outcome'] == 'UNAVAILABLE' &&
          zBag['request_id'] == null &&
          afterBag == beforeBag,
      'r=$zBag before=$beforeBag after=$afterBag',
    );

    // ------------------------------------------------------------------
    // 4) stock 1 + pending → pending created, stock stays 1
    // ------------------------------------------------------------------
    await wipeTrust();
    await upsertPolicy(mode: 'trust', untrusted: 'approval');
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
      accessToken: sellerToken,
    );
    final s4 = await seedItem(suffix: 'P1', qty: 1);
    createdProductIds.add(s4['productId']!);
    createdLiveIds.add(s4['liveId']!);
    createdItemIds.add(s4['itemId']!);
    final pend4 = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s4['liveId'],
      'p_live_item_id': s4['itemId'],
    });
    final pend4Id = pend4 is Map ? pend4['request_id']?.toString() : null;
    if (pend4Id != null) createdRequestIds.add(pend4Id);
    final stock4 = await client.rpc('batata_live_item_stock', {
      'p_live_item_id': s4['itemId'],
    });
    add(
      '4.stock1_pending_created_stock_stays_1',
      pend4 is Map &&
          pend4['outcome'] == 'PENDING_APPROVAL' &&
          pend4Id != null &&
          stock4 is Map &&
          (stock4['available_qty'] as num) == 1,
      'pend=$pend4 stock=$stock4',
    );

    // ------------------------------------------------------------------
    // 5) stock falls to 0 → existing pending can close
    // ------------------------------------------------------------------
    final hold5 = await client.insert('live_reservation_requests', {
      'live_id': s4['liveId'],
      'live_item_id': s4['itemId'],
      'seller_id': sellerId,
      'buyer_id': buyerB,
      'requested_qty': 1,
      'status': 'accepted',
      'source': 'fleaber_live',
      'request_kind': 'guaranteed',
      'expires_at':
          DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
    });
    createdRequestIds.add(hold5['id']!.toString());
    final closed5 = await client.rpc('batata_close_pending_for_stock', {
      'p_live_item_id': s4['itemId'],
      'p_except_request_id': hold5['id'],
    });
    final row5 = pend4Id == null
        ? null
        : (await client.select(
            'live_reservation_requests',
            filter: 'id=eq.$pend4Id',
            limit: 1,
          )).first;
    add(
      '5.existing_pending_closes_when_stock_zero',
      closed5 is num &&
          closed5 >= 1 &&
          row5 != null &&
          row5['expiry_reason'] == 'stock_unavailable',
      'closed=$closed5 row=$row5',
    );

    // Decide helper unit: stock 0 ⇒ UNAVAILABLE regardless of mode
    final d0 = await client.rpc('batata_commerce_decide_reservation_outcome', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_available_qty': 0,
      'p_requested_qty': 1,
      'p_identity_linked': true,
    });
    add(
      'decide.zero_stock_unit',
      d0 is Map && d0['outcome'] == 'UNAVAILABLE' && d0['reason'] == 'insufficient_stock',
      '$d0',
    );
  } catch (e, st) {
    add('ZZ.unhandled', false, '$e\n$st');
  } finally {
    for (final id in createdRequestIds) {
      try {
        await client.deleteWhere('commerce_reservation_events', 'request_id=eq.$id');
        await client.deleteWhere('live_reservation_requests', 'id=eq.$id');
      } catch (_) {}
    }
    for (final id in createdOrderIds) {
      try {
        await client.deleteWhere('orders', 'id=eq.$id');
      } catch (_) {}
    }
    for (final id in createdItemIds) {
      try {
        await client.deleteWhere('live_items', 'id=eq.$id');
      } catch (_) {}
    }
    for (final id in createdLiveIds) {
      try {
        await client.deleteWhere('lives', 'id=eq.$id');
      } catch (_) {}
    }
    for (final id in createdProductIds) {
      try {
        await client.deleteWhere('orders', 'product_id=eq.$id');
        await client.deleteWhere('products', 'id=eq.$id');
      } catch (_) {}
    }
    await wipeTrust();
  }

  final passed = checks.where((c) => c.ok).length;
  final failed = checks.where((c) => !c.ok).length;
  final report = {
    'tag': tag,
    'passed': passed,
    'failed': failed,
    'total': checks.length,
    'checks': [
      for (final c in checks) {'id': c.id, 'ok': c.ok, 'detail': c.detail},
    ],
  };
  final outDir = Directory('11-unified-commerce-phase2-corrections');
  await outDir.create(recursive: true);
  final outFile = File(
    '11-unified-commerce-phase2-corrections/test-results-raw.json',
  );
  await outFile.writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  print('\nSUMMARY passed=$passed failed=$failed total=${checks.length}');
  print('Wrote ${outFile.path}');
  if (failed > 0) exit(1);
}
