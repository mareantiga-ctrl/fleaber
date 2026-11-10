// ignore_for_file: avoid_print
/// Phase 3 — omnichannel seller bag foundation tests.
///
///   dart run tool/unified_commerce_phase3_seller_bag_test.dart
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
  final sellerB = buyerId; // second "seller" identity for cross-seller check

  final checks = <_Check>[];
  void add(String id, bool ok, [String detail = '']) {
    checks.add((id: id, ok: ok, detail: detail));
    print('${ok ? 'PASS' : 'FAIL'} $id ${detail.isEmpty ? '' : '— $detail'}');
  }

  final tag =
      'p3bag_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  Future<void> upsertTrust(String mode) async {
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': mode},
      accessToken: sellerToken,
    );
  }

  Future<Map<String, String>> seedLive({
    required String suffix,
    required String owner,
    int qty = 2,
  }) async {
    final product = await client.insert('products', {
      'seller_id': owner,
      'title': 'P3BAG $tag-$suffix',
      'price': 7,
      'quantity': qty,
      'ref_code': 'P3BAG-$tag-$suffix',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live = await client.insert('lives', {
      'title': 'P3BAG_${tag}_$suffix',
      'status': 'live',
      'seller_id': owner,
      'vendedor_id': owner,
      'is_active': true,
    });
    final item = await client.insert('live_items', {
      'live_id': live['id'],
      'ref_code': 'P3BAG-$tag-$suffix',
      'title': 'P3BAG $suffix',
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
    required String seller,
  }) async {
    return await client.rpc(
      'batata_reserve_with_policy',
      {
        'p_seller_id': seller,
        'p_buyer_id': buyerId,
        'p_live_id': s['liveId'],
        'p_live_item_id': s['itemId'],
        'p_qty': 1,
        'p_source': 'fleaber_live',
        'p_guest_session_id': null,
        'p_identity_linked': true,
        'p_notes': null,
      },
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
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
    // T5 guaranteed representation + stock
    await upsertTrust('trusted');
    final sG = await seedLive(suffix: 'G', owner: sellerId, qty: 2);
    track(sG);
    final rG = await reserve(s: sG, seller: sellerId);
    final idG = rG['request_id']?.toString();
    if (idG != null) createdRequestIds.add(idG);
    final bagG = await client.rpc(
      'batata_commerce_seller_bag',
      {'p_seller_id': sellerId},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final linesG = (bagG['lrr_lines'] as List?) ?? [];
    final hitG = linesG.cast<dynamic>().where((e) {
      final m = e as Map;
      return m['id']?.toString() == idG;
    }).toList();
    add(
      'T5.guaranteed_in_seller_bag_blocks',
      rG['outcome'] == 'GUARANTEED' &&
          hitG.isNotEmpty &&
          hitG.first['line_state'] == 'guaranteed' &&
          hitG.first['status'] == 'accepted' &&
          rG['available_qty_after'] == 1,
      'bag_line=${hitG.isEmpty ? null : hitG.first} avail=${rG['available_qty_after']}',
    );

    // T4 approval pending
    await upsertTrust('distrusted');
    final sP = await seedLive(suffix: 'P', owner: sellerId, qty: 1);
    track(sP);
    final rP = await reserve(s: sP, seller: sellerId);
    final idP = rP['request_id']?.toString();
    if (idP != null) createdRequestIds.add(idP);
    final bagP = await client.rpc(
      'batata_commerce_seller_bag',
      {'p_seller_id': sellerId},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final hitP = ((bagP['lrr_lines'] as List?) ?? []).cast<dynamic>().where((e) {
      return (e as Map)['id']?.toString() == idP;
    }).toList();
    add(
      'T4.approval_pending_no_stock_block',
      rP['outcome'] == 'PENDING_APPROVAL' &&
          hitP.isNotEmpty &&
          hitP.first['line_state'] == 'approval_pending' &&
          rP['available_qty_after'] == 1,
      'line=${hitP.isEmpty ? null : hitP.first}',
    );

    // T1 / T20 same seller mixed states in one bag
    final bagMix = await client.rpc(
      'batata_commerce_seller_bag',
      {'p_seller_id': sellerId},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final states = ((bagMix['lrr_lines'] as List?) ?? [])
        .map((e) => (e as Map)['line_state']?.toString())
        .toSet();
    add(
      'T1_T20.same_seller_mixed_states',
      states.contains('guaranteed') && states.contains('approval_pending'),
      'states=$states count=${bagMix['line_count']}',
    );

    // T3 cross-seller assert
    final cross = await client.rpc(
      'batata_commerce_assert_single_seller_bag',
      {
        'p_seller_ids': [sellerId, sellerB],
      },
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final single = await client.rpc(
      'batata_commerce_assert_single_seller_bag',
      {
        'p_seller_ids': [sellerId, sellerId],
      },
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'T3.cross_seller_bag_blocked',
      cross['ok'] == false &&
          cross['error'] == 'cross_seller_bag_forbidden' &&
          single['ok'] == true,
      'cross=$cross single=$single',
    );

    // Marketplace adapter line (T1 marketplace side)
    final mpProduct = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P3BAG MP $tag',
      'price': 9,
      'quantity': 3,
      'ref_code': 'P3BAG-MP-$tag',
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    createdProductIds.add(mpProduct['id']!.toString());
    final mpOrder = await client.insert('orders', {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': mpProduct['id'],
      'quantity': 1,
      'status': 'reserva_pendente',
      'is_reservation': true,
      'price_total': 9.0,
      'payment_method': 'manual',
    });
    createdOrderIds.add(mpOrder['id']!.toString());
    final bagMp = await client.rpc(
      'batata_commerce_seller_bag',
      {'p_seller_id': sellerId},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final mpLines = (bagMp['marketplace_adapter_lines'] as List?) ?? [];
    final hitMp = mpLines.cast<dynamic>().where((e) {
      return (e as Map)['id']?.toString() == mpOrder['id']?.toString();
    }).toList();
    add(
      'T1.marketplace_adapter_same_seller_bag',
      hitMp.isNotEmpty &&
          hitMp.first['source_channel'] == 'marketplace' &&
          hitMp.first['line_state'] == 'approval_pending',
      'mp=${hitMp.isEmpty ? null : hitMp.first}',
    );

    // T14/T16 — qty immutable on guaranteed
    final qtyTry = await client.rpc(
      'batata_live_bag_update_qty',
      {'p_request_id': idG, 'p_qty': 3},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'T16.guaranteed_qty_immutable',
      qtyTry['ok'] == false && qtyTry['error'] == 'guaranteed_qty_immutable',
      jsonEncode(qtyTry),
    );

    // T17 — buyer-facing RPC is auth.uid scoped (not seller privilege).
    // Seller token sees bag as buyer_id=sellerId (own buyer identity), never A's lines.
    final bagAsSeller = await client.rpc(
      'batata_commerce_seller_bag',
      {'p_seller_id': sellerId},
      accessToken: sellerToken,
    ) as Map<String, dynamic>;
    final sellerSeesBuyerA = ((bagAsSeller['lrr_lines'] as List?) ?? [])
        .any((e) => (e as Map)['id']?.toString() == idG);
    add(
      'T17.seller_token_cannot_read_buyer_A_bag_via_buyer_rpc',
      bagAsSeller['ok'] == true &&
          bagAsSeller['buyer_id']?.toString() == sellerId &&
          !sellerSeesBuyerA,
      'buyer_id=${bagAsSeller['buyer_id']} lines=${bagAsSeller['line_count']} sawA=$sellerSeesBuyerA',
    );

    // T6 unguaranteed: pay_only mode
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': 'pay_only', 'untrusted_mode': 'pay_required'},
    );
    await upsertTrust('trusted');
    final sU = await seedLive(suffix: 'U', owner: sellerId, qty: 2);
    track(sU);
    final rU = await reserve(s: sU, seller: sellerId);
    final idU = rU['request_id']?.toString();
    if (idU != null) createdRequestIds.add(idU);
    final rowU = idU == null
        ? null
        : (await client.select(
            'live_reservation_requests',
            filter: 'id=eq.$idU',
            limit: 1,
          )).firstOrNull;
    add(
      'T6.unguaranteed_no_fake_expires_and_no_block',
      rU['ok'] == true &&
          (rU['outcome'] == 'BAG_UNGUARANTEED' ||
              rowU?['request_kind'] == 'bag_hold_none') &&
          (rowU?['expires_at'] == null ||
              rowU?['request_kind'] == 'bag_hold_none') &&
          rU['available_qty_after'] == 2,
      'outcome=${rU['outcome']} kind=${rowU?['request_kind']} exp=${rowU?['expires_at']} avail=${rU['available_qty_after']}',
    );

    // Reset policy
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': 'trust', 'untrusted_mode': 'approval'},
    );

    // T2 facebook-origin in same seller bag (manual source row)
    final fb = await client.insert('live_reservation_requests', {
      'live_id': sG['liveId'],
      'live_item_id': sG['itemId'],
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'requested_qty': 1,
      'source': 'facebook_manual',
      'status': 'pending',
      'request_kind': 'approval_pending',
      'source_channel': 'facebook_psreader',
    });
    createdRequestIds.add(fb['id']!.toString());
    final bagFb = await client.rpc(
      'batata_commerce_seller_bag',
      {'p_seller_id': sellerId},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final fbHit = ((bagFb['lrr_lines'] as List?) ?? []).cast<dynamic>().where((e) {
      return (e as Map)['id']?.toString() == fb['id']?.toString();
    }).toList();
    add(
      'T2.facebook_origin_same_seller_bag_no_parallel_bag',
      fbHit.isNotEmpty &&
          fbHit.first['source_channel'] == 'facebook_psreader',
      'line=${fbHit.isEmpty ? null : fbHit.first}',
    );

    // Fake hold check — unguaranteed available unchanged
    add(
      'FAKE_HOLD.none_for_unguaranteed_path',
      rU['available_qty_after'] == 2,
      'avail=${rU['available_qty_after']}',
    );
  } catch (e, st) {
    add('ZZ.unhandled', false, '$e\n$st');
  } finally {
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

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
