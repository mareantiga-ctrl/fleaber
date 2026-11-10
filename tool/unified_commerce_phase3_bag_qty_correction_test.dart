// ignore_for_file: avoid_print
/// Phase 3 correction — bag qty must not inflate available for non-blocking lines.
///
///   dart run tool/unified_commerce_phase3_bag_qty_correction_test.dart
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

  // Ephemeral second buyer for isolation + concurrency (no BUYER_B in env).
  final buyerBEmail =
      'p3qty.buyerb.${DateTime.now().millisecondsSinceEpoch}@fleaber.test';
  const buyerBPassword = 'P3QtyBuyerB!staging';
  final buyerBId = await client.createAdminUser(
    email: buyerBEmail,
    password: buyerBPassword,
    userMetadata: {'display_name': 'P3 Qty Buyer B'},
  );
  try {
    await client.insert('profiles', {
      'id': buyerBId,
      'display_name': 'P3 Qty Buyer B',
      'hub_published': false,
    });
  } catch (_) {
    // profile may already exist via trigger
  }
  final buyerBToken = await client.signIn(
    email: buyerBEmail,
    password: buyerBPassword,
  );

  final checks = <_Check>[];
  void add(String id, bool ok, [String detail = '']) {
    checks.add((id: id, ok: ok, detail: detail));
    print('${ok ? 'PASS' : 'FAIL'} $id ${detail.isEmpty ? '' : '— $detail'}');
  }

  final tag =
      'p3qty_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  Future<void> upsertTrust(String mode, {String? buyer}) async {
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {
        'p_seller_id': sellerId,
        'p_buyer_id': buyer ?? buyerId,
        'p_mode': mode,
      },
      accessToken: sellerToken,
    );
  }

  Future<Map<String, String>> seedLive({
    required String suffix,
    required int qty,
  }) async {
    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P3QTY $tag-$suffix',
      'price': 7,
      'quantity': qty,
      'ref_code': 'P3QTY-$tag-$suffix',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live = await client.insert('lives', {
      'title': 'P3QTY_${tag}_$suffix',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final item = await client.insert('live_items', {
      'live_id': live['id'],
      'ref_code': 'P3QTY-$tag-$suffix',
      'title': 'P3QTY $suffix',
      'price': 7,
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

  Future<Map<String, dynamic>> reserve({
    required Map<String, String> s,
    required String token,
    required String buyer,
    int qty = 1,
  }) async {
    return await client.rpc(
      'batata_reserve_with_policy',
      {
        'p_seller_id': sellerId,
        'p_buyer_id': buyer,
        'p_live_id': s['liveId'],
        'p_live_item_id': s['itemId'],
        'p_qty': qty,
        'p_source': 'fleaber_live',
        'p_guest_session_id': null,
        'p_identity_linked': true,
        'p_notes': null,
      },
      accessToken: token,
    ) as Map<String, dynamic>;
  }

  Future<int> avail(String itemId) async {
    final snap = await client.rpc(
      'batata_live_item_stock',
      {'p_live_item_id': itemId},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    return (snap['available_qty'] as num?)?.toInt() ?? -1;
  }

  final createdRequestIds = <String>[];
  final createdItemIds = <String>[];
  final createdLiveIds = <String>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  void track(Map<String, String> s) {
    createdProductIds.add(s['productId']!);
    createdLiveIds.add(s['liveId']!);
    createdItemIds.add(s['itemId']!);
  }

  await client.patch('profiles', 'id=eq.$sellerId', {'hub_published': true});

  try {
    // ------------------------------------------------------------------ Q1
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': 'trust', 'untrusted_mode': 'approval'},
    );
    await upsertTrust('distrusted');
    final s1 = await seedLive(suffix: 'Q1', qty: 1);
    track(s1);
    final r1 = await reserve(s: s1, token: buyerToken, buyer: buyerId);
    final id1 = r1['request_id']?.toString();
    if (id1 != null) createdRequestIds.add(id1);
    final a1 = await avail(s1['itemId']!);
    final q1 = await client.rpc(
      'batata_live_bag_update_qty',
      {'p_request_id': id1, 'p_qty': 2},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'Q1.pending_stock1_qty2_rejected',
      r1['outcome'] == 'PENDING_APPROVAL' &&
          a1 == 1 &&
          q1['ok'] == false &&
          q1['error'] == 'qty_exceeds_stock' &&
          q1['available_qty'] == 1,
      'avail=$a1 res=${jsonEncode(q1)}',
    );

    // ------------------------------------------------------------------ Q2
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': 'pay_only', 'untrusted_mode': 'pay_required'},
    );
    await upsertTrust('trusted');
    final s2 = await seedLive(suffix: 'Q2', qty: 1);
    track(s2);
    final r2 = await reserve(s: s2, token: buyerToken, buyer: buyerId);
    final id2 = r2['request_id']?.toString();
    if (id2 != null) createdRequestIds.add(id2);
    final row2 = id2 == null
        ? null
        : (await client.select(
            'live_reservation_requests',
            filter: 'id=eq.$id2',
            limit: 1,
          )).firstOrNull;
    final q2 = await client.rpc(
      'batata_live_bag_update_qty',
      {'p_request_id': id2, 'p_qty': 2},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'Q2.bag_hold_none_stock1_qty2_rejected',
      (r2['outcome'] == 'BAG_UNGUARANTEED' ||
              row2?['request_kind'] == 'bag_hold_none') &&
          q2['ok'] == false &&
          q2['error'] == 'qty_exceeds_stock',
      'kind=${row2?['request_kind']} res=${jsonEncode(q2)}',
    );

    // ------------------------------------------------------------------ Q3
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': 'trust', 'untrusted_mode': 'approval'},
    );
    await upsertTrust('distrusted');
    final s3 = await seedLive(suffix: 'Q3', qty: 3);
    track(s3);
    final r3 = await reserve(s: s3, token: buyerToken, buyer: buyerId);
    final id3 = r3['request_id']?.toString();
    if (id3 != null) createdRequestIds.add(id3);
    final q3 = await client.rpc(
      'batata_live_bag_update_qty',
      {'p_request_id': id3, 'p_qty': 3},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'Q3.pending_stock3_qty3_allowed',
      r3['outcome'] == 'PENDING_APPROVAL' &&
          q3['ok'] == true &&
          q3['requested_qty'] == 3 &&
          q3['available_qty'] == 3,
      jsonEncode(q3),
    );

    // ------------------------------------------------------------------ Q4
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': 'pay_only', 'untrusted_mode': 'pay_required'},
    );
    await upsertTrust('trusted');
    final s4 = await seedLive(suffix: 'Q4', qty: 3);
    track(s4);
    final r4 = await reserve(s: s4, token: buyerToken, buyer: buyerId);
    final id4 = r4['request_id']?.toString();
    if (id4 != null) createdRequestIds.add(id4);
    final q4 = await client.rpc(
      'batata_live_bag_update_qty',
      {'p_request_id': id4, 'p_qty': 3},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'Q4.bag_hold_none_stock3_qty3_allowed',
      q4['ok'] == true &&
          q4['requested_qty'] == 3 &&
          q4['available_qty'] == 3,
      jsonEncode(q4),
    );

    // ------------------------------------------------------------------ Q5
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': 'trust', 'untrusted_mode': 'approval'},
    );
    await upsertTrust('distrusted', buyer: buyerId);
    await upsertTrust('trusted', buyer: buyerBId);
    final s5 = await seedLive(suffix: 'Q5', qty: 3);
    track(s5);
    final r5p = await reserve(s: s5, token: buyerToken, buyer: buyerId);
    final id5p = r5p['request_id']?.toString();
    if (id5p != null) createdRequestIds.add(id5p);
    final r5g = await reserve(
      s: s5,
      token: buyerBToken,
      buyer: buyerBId,
      qty: 2,
    );
    final id5g = r5g['request_id']?.toString();
    if (id5g != null) createdRequestIds.add(id5g);
    final a5 = await avail(s5['itemId']!);
    final q5 = await client.rpc(
      'batata_live_bag_update_qty',
      {'p_request_id': id5p, 'p_qty': 2},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'Q5.pending_after_other_guarantee_qty2_rejected',
      r5p['outcome'] == 'PENDING_APPROVAL' &&
          r5g['outcome'] == 'GUARANTEED' &&
          a5 == 1 &&
          q5['ok'] == false &&
          q5['error'] == 'qty_exceeds_stock' &&
          q5['available_qty'] == 1,
      'avail=$a5 g=${r5g['outcome']} res=${jsonEncode(q5)}',
    );

    // ------------------------------------------------------------------ Q6
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': 'pay_only', 'untrusted_mode': 'pay_required'},
    );
    await upsertTrust('trusted', buyer: buyerId);
    await upsertTrust('trusted', buyer: buyerBId);
    // Buyer A bag_hold_none needs pay_only; then switch B can still guarantee?
    // With pay_only, trusted also gets bag_hold_none. Need trust policy for B guarantee.
    // Seed under pay_only for A, then flip policy to trust for B guarantee.
    final s6 = await seedLive(suffix: 'Q6', qty: 3);
    track(s6);
    final r6u = await reserve(s: s6, token: buyerToken, buyer: buyerId);
    final id6u = r6u['request_id']?.toString();
    if (id6u != null) createdRequestIds.add(id6u);
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': 'trust', 'untrusted_mode': 'approval'},
    );
    final r6g = await reserve(
      s: s6,
      token: buyerBToken,
      buyer: buyerBId,
      qty: 2,
    );
    final id6g = r6g['request_id']?.toString();
    if (id6g != null) createdRequestIds.add(id6g);
    final a6 = await avail(s6['itemId']!);
    final q6 = await client.rpc(
      'batata_live_bag_update_qty',
      {'p_request_id': id6u, 'p_qty': 2},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'Q6.unguaranteed_after_other_guarantee_qty2_rejected',
      (r6u['outcome'] == 'BAG_UNGUARANTEED' ||
              r6u['outcome'] == 'PENDING_APPROVAL') &&
          r6g['outcome'] == 'GUARANTEED' &&
          a6 == 1 &&
          q6['ok'] == false &&
          q6['available_qty'] == 1,
      'avail=$a6 u=${r6u['outcome']} g=${r6g['outcome']} res=${jsonEncode(q6)}',
    );

    // ------------------------------------------------------------------ Q7
    await upsertTrust('trusted', buyer: buyerId);
    final s7 = await seedLive(suffix: 'Q7', qty: 2);
    track(s7);
    final r7 = await reserve(s: s7, token: buyerToken, buyer: buyerId);
    final id7 = r7['request_id']?.toString();
    if (id7 != null) createdRequestIds.add(id7);
    final q7 = await client.rpc(
      'batata_live_bag_update_qty',
      {'p_request_id': id7, 'p_qty': 2},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'Q7.guaranteed_qty_immutable',
      r7['outcome'] == 'GUARANTEED' &&
          q7['ok'] == false &&
          q7['error'] == 'guaranteed_qty_immutable',
      jsonEncode(q7),
    );

    // ------------------------------------------------------------------ Q8
    await upsertTrust('distrusted', buyer: buyerId);
    final s8 = await seedLive(suffix: 'Q8', qty: 1);
    track(s8);
    final r8 = await reserve(s: s8, token: buyerToken, buyer: buyerId);
    final id8 = r8['request_id']?.toString();
    if (id8 != null) createdRequestIds.add(id8);
    final q8hi = await client.rpc(
      'batata_live_bag_update_qty',
      {'p_request_id': id8, 'p_qty': 99},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final a8 = await avail(s8['itemId']!);
    add(
      'Q8.no_oversell_stock_never_negative',
      q8hi['ok'] == false && a8 >= 0 && a8 <= 1,
      'avail=$a8 res=${jsonEncode(q8hi)}',
    );

    // ------------------------------------------------------------------ T17 isolation
    final bagA = await client.rpc(
      'batata_commerce_seller_bag',
      {'p_seller_id': sellerId},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final bagB = await client.rpc(
      'batata_commerce_seller_bag',
      {'p_seller_id': sellerId},
      accessToken: buyerBToken,
    ) as Map<String, dynamic>;
    final bagSeller = await client.rpc(
      'batata_commerce_seller_bag',
      {'p_seller_id': sellerId},
      accessToken: sellerToken,
    ) as Map<String, dynamic>;
    final idsA = ((bagA['lrr_lines'] as List?) ?? [])
        .map((e) => (e as Map)['id']?.toString())
        .whereType<String>()
        .toSet();
    final idsB = ((bagB['lrr_lines'] as List?) ?? [])
        .map((e) => (e as Map)['id']?.toString())
        .whereType<String>()
        .toSet();
    final overlap = idsA.intersection(idsB);
    add(
      'T17.buyer_A_sees_only_own_bag',
      bagA['ok'] == true &&
          bagA['buyer_id']?.toString() == buyerId &&
          idsA.isNotEmpty,
      'buyer=${bagA['buyer_id']} n=${idsA.length}',
    );
    add(
      'T17.buyer_B_cannot_see_buyer_A_lines',
      bagB['ok'] == true &&
          bagB['buyer_id']?.toString() == buyerBId &&
          overlap.isEmpty,
      'overlap=$overlap bN=${idsB.length}',
    );
    add(
      'T17.seller_token_does_not_grant_buyer_bag_access',
      bagSeller['ok'] == true &&
          bagSeller['buyer_id']?.toString() == sellerId &&
          ((bagSeller['lrr_lines'] as List?) ?? []).every((e) {
            final m = e as Map;
            return m['buyer_id']?.toString() == sellerId ||
                m['buyer_id'] == null;
          }) &&
          !idsA.any((id) => ((bagSeller['lrr_lines'] as List?) ?? [])
              .any((e) => (e as Map)['id']?.toString() == id)),
      'sellerBuyerId=${bagSeller['buyer_id']} sellerLines=${bagSeller['line_count']}',
    );

    // Buyer B cannot alter A's request qty
    final qCross = await client.rpc(
      'batata_live_bag_update_qty',
      {'p_request_id': id1, 'p_qty': 1},
      accessToken: buyerBToken,
    ) as Map<String, dynamic>;
    add(
      'T17.buyer_B_cannot_alter_buyer_A_qty',
      qCross['ok'] == false && qCross['error'] == 'not_allowed',
      jsonEncode(qCross),
    );

    // ------------------------------------------------------------------ MP semantics proof
    final mpP = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P3QTY MP $tag',
      'price': 5,
      'quantity': 2,
      'ref_code': 'P3QTY-MP-$tag',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    createdProductIds.add(mpP['id']!.toString());
    final liveMp = await client.insert('lives', {
      'title': 'P3QTY_MP_$tag',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    createdLiveIds.add(liveMp['id']!.toString());
    final itemMp = await client.insert('live_items', {
      'live_id': liveMp['id'],
      'ref_code': 'P3QTY-MP-$tag',
      'title': 'P3QTY MP',
      'price': 5,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': mpP['id'],
      'checkout_product_id': mpP['id'],
      'quantity': null,
    });
    createdItemIds.add(itemMp['id']!.toString());
    final beforeMp = await avail(itemMp['id']!.toString());
    final ordPend = await client.insert('orders', {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': mpP['id'],
      'live_item_id': itemMp['id'],
      'live_id': liveMp['id'],
      'quantity': 1,
      'status': 'reserva_pendente',
      'is_reservation': true,
      'price_total': 5.0,
      'payment_method': 'manual',
    });
    createdOrderIds.add(ordPend['id']!.toString());
    final afterPend = await avail(itemMp['id']!.toString());
    await client.patch(
      'orders',
      'id=eq.${ordPend['id']}',
      {'status': 'reservado', 'is_reservation': true},
    );
    final afterRes = await avail(itemMp['id']!.toString());
    add(
      'MP.reserva_pendente_does_not_block_stock',
      beforeMp == 2 && afterPend == 2,
      'before=$beforeMp afterPend=$afterPend',
    );
    add(
      'MP.reservado_blocks_stock',
      afterRes == 1,
      'afterReservado=$afterRes',
    );
  } catch (e, st) {
    add('ZZ.unhandled', false, '$e\n$st');
  } finally {
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': 'trust', 'untrusted_mode': 'approval'},
    );
    for (final id in createdOrderIds) {
      try {
        await client.deleteWhere('orders', 'id=eq.$id');
      } catch (_) {}
    }
    for (final id in createdRequestIds) {
      try {
        await client.deleteWhere(
          'commerce_reservation_events',
          'request_id=eq.$id',
        );
      } catch (_) {}
      try {
        await client.deleteWhere('live_reservation_requests', 'id=eq.$id');
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
        await client.deleteWhere('products', 'id=eq.$id');
      } catch (_) {}
    }
  }

  final failed = checks.where((c) => !c.ok).length;
  print('');
  print('SUMMARY: ${checks.length - failed}/${checks.length} PASS');
  stdout.writeln(jsonEncode({
    'passed': checks.where((c) => c.ok).map((c) => c.id).toList(),
    'failed': checks
        .where((c) => !c.ok)
        .map((c) => {'id': c.id, 'detail': c.detail})
        .toList(),
  }));
  if (failed > 0) exit(1);
}
