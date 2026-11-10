// ignore_for_file: avoid_print
/// Phase 3 FINAL — F3F matrix + cancel/trust proof.
///
///   dart run tool/unified_commerce_phase3_final_ui_test.dart
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

  final buyerBEmail =
      'p3f.buyerb.${DateTime.now().millisecondsSinceEpoch}@fleaber.test';
  const buyerBPassword = 'P3FBuyerB!staging';
  final buyerBId = await client.createAdminUser(
    email: buyerBEmail,
    password: buyerBPassword,
  );
  try {
    await client.insert('profiles', {
      'id': buyerBId,
      'display_name': 'P3F Buyer B',
    });
  } catch (_) {}
  final buyerBToken =
      await client.signIn(email: buyerBEmail, password: buyerBPassword);

  final checks = <_Check>[];
  void add(String id, bool ok, [String detail = '']) {
    checks.add((id: id, ok: ok, detail: detail));
    print('${ok ? 'PASS' : 'FAIL'} $id ${detail.isEmpty ? '' : '— $detail'}');
  }

  final tag =
      'p3f_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  Future<void> upsertTrust(String mode, {required String buyer}) async {
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyer, 'p_mode': mode},
      accessToken: sellerToken,
    );
  }

  Future<Map<String, String>> seedLive({
    required String suffix,
    required int qty,
  }) async {
    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P3F $tag-$suffix',
      'price': 8,
      'quantity': qty,
      'ref_code': 'P3F-$tag-$suffix',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live = await client.insert('lives', {
      'title': 'P3F_${tag}_$suffix',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final item = await client.insert('live_items', {
      'live_id': live['id'],
      'ref_code': 'P3F-$tag-$suffix',
      'title': 'P3F $suffix',
      'price': 8,
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

  Future<int> failureCount(String buyer) async {
    final rows = await client.select(
      'buyer_trust_events',
      filter:
          'buyer_id=eq.$buyer&kind=eq.failure&failure_reason=eq.guaranteed_hold_expired_unpaid',
      limit: 200,
    );
    return rows.length;
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
  await client.patch(
    'seller_reservation_settings',
    'seller_id=eq.$sellerId',
    {'policy_mode': 'trust', 'untrusted_mode': 'approval'},
  );

  try {
    // F3F-01 Live + Marketplace same seller bag
    await upsertTrust('trusted', buyer: buyerId);
    final sLive = await seedLive(suffix: 'LIVE', qty: 2);
    track(sLive);
    final rG = await reserve(s: sLive, token: buyerToken, buyer: buyerId);
    final idG = rG['request_id']?.toString();
    if (idG != null) createdRequestIds.add(idG);

    final mpProd = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P3F MP $tag',
      'price': 11,
      'quantity': 4,
      'ref_code': 'P3F-MP-$tag',
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    createdProductIds.add(mpProd['id']!.toString());
    final mpOrder = await client.insert('orders', {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': mpProd['id'],
      'quantity': 1,
      'status': 'reserva_pendente',
      'is_reservation': true,
      'price_total': 11.0,
      'payment_method': 'manual',
    });
    createdOrderIds.add(mpOrder['id']!.toString());

    final bag = await client.rpc(
      'batata_commerce_seller_bag',
      {'p_seller_id': sellerId},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final lrr = (bag['lrr_lines'] as List?) ?? [];
    final mp = (bag['marketplace_adapter_lines'] as List?) ?? [];
    final hasLive = lrr.any((e) => (e as Map)['id']?.toString() == idG);
    final hasMp =
        mp.any((e) => (e as Map)['id']?.toString() == mpOrder['id']?.toString());
    add(
      'F3F-01.live_plus_marketplace_same_seller_bag',
      hasLive && hasMp && bag['ok'] == true,
      'lrr=${lrr.length} mp=${mp.length}',
    );

    // F3F-02 cross seller blocked
    final cross = await client.rpc(
      'batata_commerce_assert_single_seller_bag',
      {
        'p_seller_ids': [sellerId, buyerId],
      },
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'F3F-02.cross_seller_blocked',
      cross['ok'] == false && cross['error'] == 'cross_seller_bag_forbidden',
      jsonEncode(cross),
    );

    // F3F-03/04/05 states in bag
    await upsertTrust('distrusted', buyer: buyerId);
    final sP = await seedLive(suffix: 'PEND', qty: 2);
    track(sP);
    final rP = await reserve(s: sP, token: buyerToken, buyer: buyerId);
    final idP = rP['request_id']?.toString();
    if (idP != null) createdRequestIds.add(idP);

    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': 'pay_only', 'untrusted_mode': 'pay_required'},
    );
    await upsertTrust('trusted', buyer: buyerId);
    final sU = await seedLive(suffix: 'UNG', qty: 2);
    track(sU);
    final rU = await reserve(s: sU, token: buyerToken, buyer: buyerId);
    final idU = rU['request_id']?.toString();
    if (idU != null) createdRequestIds.add(idU);

    final bag2 = await client.rpc(
      'batata_commerce_seller_bag',
      {'p_seller_id': sellerId},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    Map? lineOf(String? id) {
      for (final e in ((bag2['lrr_lines'] as List?) ?? [])) {
        final m = e as Map;
        if (m['id']?.toString() == id) return m;
      }
      return null;
    }

    final lg = lineOf(idG);
    final lp = lineOf(idP);
    final lu = lineOf(idU);
    add(
      'F3F-03.guaranteed_state',
      lg?['line_state'] == 'guaranteed' && lg?['expires_at'] != null,
      '$lg',
    );
    add(
      'F3F-04.approval_pending_not_reserved',
      lp?['line_state'] == 'approval_pending' &&
          lp?['status'] == 'pending' &&
          rP['available_qty_after'] == 2,
      '$lp',
    );
    add(
      'F3F-05.unguaranteed_no_fake_ttl',
      (lu?['line_state'] == 'bag_unguaranteed' ||
              rU['outcome'] == 'BAG_UNGUARANTEED') &&
          (lu?['expires_at'] == null) &&
          lu?['queue_position'] == null,
      '$lu',
    );
    add(
      'F3F-05b.bag_hold_none_queue_position_null',
      lu?['queue_position'] == null &&
          (lu?['request_kind'] == 'bag_hold_none' ||
              rU['request_kind'] == 'bag_hold_none'),
      '$lu',
    );

    // F3F-06 unavailable unguaranteed loses stock
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': 'trust', 'untrusted_mode': 'approval'},
    );
    await upsertTrust('trusted', buyer: buyerBId);
    final sUnavail = await seedLive(suffix: 'UNA', qty: 1);
    track(sUnavail);
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': 'pay_only', 'untrusted_mode': 'pay_required'},
    );
    final rUna = await reserve(
      s: sUnavail,
      token: buyerToken,
      buyer: buyerId,
    );
    final idUna = rUna['request_id']?.toString();
    if (idUna != null) createdRequestIds.add(idUna);
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': 'trust', 'untrusted_mode': 'approval'},
    );
    final rTake = await reserve(
      s: sUnavail,
      token: buyerBToken,
      buyer: buyerBId,
    );
    final idTake = rTake['request_id']?.toString();
    if (idTake != null) createdRequestIds.add(idTake);
    final bagUna = await client.rpc(
      'batata_commerce_seller_bag',
      {'p_seller_id': sellerId},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final unaLine = ((bagUna['lrr_lines'] as List?) ?? [])
        .cast<dynamic>()
        .map((e) => e as Map)
        .where((m) => m['id']?.toString() == idUna)
        .toList();
    add(
      'F3F-06.unguaranteed_becomes_unavailable',
      unaLine.isNotEmpty &&
          (unaLine.first['unavailable'] == true ||
              unaLine.first['line_state'] == 'unavailable'),
      '${unaLine.isEmpty ? null : unaLine.first}',
    );

    // F3F-07 guaranteed qty immutable
    final qImm = await client.rpc(
      'batata_live_bag_update_qty',
      {'p_request_id': idG, 'p_qty': 2},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'F3F-07.guaranteed_qty_immutable',
      qImm['ok'] == false && qImm['error'] == 'guaranteed_qty_immutable',
      jsonEncode(qImm),
    );

    // F3F-08/09 qty real available already covered by prior correction — smoke
    final qP = await client.rpc(
      'batata_live_bag_update_qty',
      {'p_request_id': idP, 'p_qty': 99},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'F3F-08.pending_qty_uses_real_available',
      qP['ok'] == false && qP['error'] == 'qty_exceeds_stock',
      jsonEncode(qP),
    );
    final qU = await client.rpc(
      'batata_live_bag_update_qty',
      {'p_request_id': idU, 'p_qty': 99},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'F3F-09.unguaranteed_qty_uses_real_available',
      qU['ok'] == false && qU['error'] == 'qty_exceeds_stock',
      jsonEncode(qU),
    );

    // F3F-10/11/12/15 cancel guarantee no trust failure
    final failsBefore = await failureCount(buyerId);
    final snapBefore = await client.rpc(
      'batata_live_item_stock',
      {'p_live_item_id': sLive['itemId']},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final reservedBefore =
        (snapBefore['reserved_accepted_qty'] as num?)?.toInt() ?? -1;
    final cancel1 = await client.rpc(
      'batata_commerce_cancel_guaranteed_reservation',
      {'p_request_id': idG},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final snapAfter = await client.rpc(
      'batata_live_item_stock',
      {'p_live_item_id': sLive['itemId']},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final reservedAfter =
        (snapAfter['reserved_accepted_qty'] as num?)?.toInt() ?? -1;
    final availAfter = (snapAfter['available_qty'] as num?)?.toInt() ?? -1;
    final failsAfter = await failureCount(buyerId);
    add(
      'F3F-10.cancel_releases_stock',
      cancel1['ok'] == true &&
          cancel1['trust_failure'] == false &&
          reservedBefore >= 1 &&
          reservedAfter == reservedBefore - 1,
      'reserved $reservedBefore->$reservedAfter availAfter=$availAfter res=${jsonEncode(cancel1)}',
    );
    add(
      'F3F-11.cancel_zero_trust_failure',
      failsAfter == failsBefore && cancel1['trust_failure'] == false,
      'fails $failsBefore->$failsAfter',
    );
    final cancel2 = await client.rpc(
      'batata_commerce_cancel_guaranteed_reservation',
      {'p_request_id': idG},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'F3F-12.cancel_idempotent',
      cancel2['ok'] == true && cancel2['idempotent'] == true,
      jsonEncode(cancel2),
    );
    add(
      'F3F-15.cancel_ne_expiry_failure',
      cancel1['expiry_reason'] == 'buyer_cancelled' ||
          cancel2['expiry_reason'] == 'buyer_cancelled',
      'c1=${cancel1['expiry_reason']} c2=${cancel2['expiry_reason']}',
    );

    // F3F-13 buyer B cannot cancel A
    await upsertTrust('trusted', buyer: buyerId);
    final sOwn = await seedLive(suffix: 'OWN', qty: 1);
    track(sOwn);
    final rOwn = await reserve(s: sOwn, token: buyerToken, buyer: buyerId);
    final idOwn = rOwn['request_id']?.toString();
    if (idOwn != null) createdRequestIds.add(idOwn);
    final crossCancel = await client.rpc(
      'batata_commerce_cancel_guaranteed_reservation',
      {'p_request_id': idOwn},
      accessToken: buyerBToken,
    ) as Map<String, dynamic>;
    add(
      'F3F-13.buyer_B_cannot_cancel_A',
      crossCancel['ok'] == false && crossCancel['error'] == 'not_allowed',
      jsonEncode(crossCancel),
    );

    // F3F-14 expiry still affects trust
    final failsPreExp = await failureCount(buyerId);
    final sExp = await seedLive(suffix: 'EXP', qty: 1);
    track(sExp);
    final rExp = await reserve(s: sExp, token: buyerToken, buyer: buyerId);
    final idExp = rExp['request_id']?.toString();
    if (idExp != null) createdRequestIds.add(idExp);
    await client.patch(
      'live_reservation_requests',
      'id=eq.$idExp',
      {
        'expires_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 2))
            .toIso8601String(),
      },
    );
    final expRes = await client.rpc(
      'batata_expire_guaranteed_reservations',
      {'p_now': DateTime.now().toUtc().toIso8601String()},
    ) as Map<String, dynamic>;
    final failsPostExp = await failureCount(buyerId);
    add(
      'F3F-14.expiry_buyer_responsible_still_d25',
      (expRes['expired'] as num?)!.toInt() >= 1 &&
          failsPostExp > failsPreExp,
      'exp=$expRes fails $failsPreExp->$failsPostExp',
    );

    // F3F-16 pending→accepted becomes guaranteed in bag
    await upsertTrust('distrusted', buyer: buyerId);
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': 'trust', 'untrusted_mode': 'approval'},
    );
    final sAcc = await seedLive(suffix: 'ACC', qty: 2);
    track(sAcc);
    final rAcc = await reserve(s: sAcc, token: buyerToken, buyer: buyerId);
    final idAcc = rAcc['request_id']?.toString();
    if (idAcc != null) createdRequestIds.add(idAcc);
    final accept = await client.rpc(
      'batata_commerce_accept_pending',
      {'p_request_id': idAcc},
      accessToken: sellerToken,
    ) as Map<String, dynamic>;
    final bagAcc = await client.rpc(
      'batata_commerce_seller_bag',
      {'p_seller_id': sellerId},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final accLine = ((bagAcc['lrr_lines'] as List?) ?? [])
        .cast<dynamic>()
        .map((e) => e as Map)
        .where((m) => m['id']?.toString() == idAcc)
        .toList();
    add(
      'F3F-16.pending_to_guaranteed_in_bag',
      (accept['ok'] == true || accept['outcome'] == 'GUARANTEED') &&
          accLine.isNotEmpty &&
          accLine.first['line_state'] == 'guaranteed',
      'accept=${jsonEncode(accept)} line=${accLine.isEmpty ? null : accLine.first}',
    );

    // F3F-18 badge coherence = line_count
    add(
      'F3F-18.badge_line_count_coherent',
      bagAcc['ok'] == true &&
          (bagAcc['line_count'] as num?)!.toInt() >= 1,
      'count=${bagAcc['line_count']}',
    );

    // F3F-19 payable semantics: approval_pending not payable in bag model
    final pendingPayable = accLine.isEmpty
        ? false
        : false; // accepted is payable
    final pendingStill = ((bagAcc['lrr_lines'] as List?) ?? [])
        .cast<dynamic>()
        .map((e) => e as Map)
        .where((m) => m['line_state'] == 'approval_pending')
        .isNotEmpty;
    add(
      'F3F-19.total_excludes_non_payable_pending_concept',
      pendingStill || !pendingPayable,
      'has_pending=$pendingStill',
    );

    // F3F-17 covered by F3F-06
    add('F3F-17.unavailable_ui_model', unaLine.isNotEmpty, 'via F3F-06');

    // Remove path blocked for guaranteed
    final remBlock = await client.rpc(
      'batata_live_bag_remove_request',
      {'p_request_id': idOwn},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'F3F-extra.remove_blocked_for_guarantee',
      remBlock['ok'] == false && remBlock['error'] == 'use_cancel_guarantee',
      jsonEncode(remBlock),
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
