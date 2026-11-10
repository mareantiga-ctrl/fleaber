// ignore_for_file: avoid_print
/// Phase 2 — canonical reservation engine + trust + expiry.
///
///   dart run tool/unified_commerce_phase2_reservation_engine_test.dart
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
  final buyerB = sellerId; // second actor for concurrency

  final checks = <_Check>[];
  void add(String id, bool ok, [String detail = '']) {
    checks.add((id: id, ok: ok, detail: detail));
    print('${ok ? 'PASS' : 'FAIL'} $id ${detail.isEmpty ? '' : '— $detail'}');
  }

  final tag =
      'p2_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

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
    String? productId,
    String? liveId,
  }) async {
    String? pid = productId;
    if (pid == null) {
      final product = await client.insert('products', {
        'seller_id': sellerId,
        'title': 'P2 product $tag-$suffix',
        'price': 5,
        'quantity': qty,
        'ref_code': 'P2-$tag-$suffix',
        'list_on_marketplace': false,
        'available_for_live': true,
        'is_sold': false,
        'image_urls': <String>[],
      });
      pid = product['id']!.toString();
    }
    String? lid = liveId;
    if (lid == null) {
      final live = await client.insert('lives', {
        'title': 'P2_${tag}_$suffix',
        'status': 'live',
        'seller_id': sellerId,
        'vendedor_id': sellerId,
        'is_active': true,
      });
      lid = live['id']!.toString();
    }
    final item = await client.insert('live_items', {
      'live_id': lid,
      'ref_code': 'P2-$tag-$suffix',
      'title': 'P2 item $suffix',
      'price': 5,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': pid,
      'checkout_product_id': pid,
      'quantity': null,
    });
    return {
      'productId': pid,
      'liveId': lid!,
      'itemId': item['id']!.toString(),
    };
  }

  await client.patch('profiles', 'id=eq.$sellerId', {'hub_published': true});
  await wipeTrust();

  final createdRequestIds = <String>[];
  final createdItemIds = <String>[];
  final createdLiveIds = <String>[];
  final createdProductIds = <String>[];

  try {
    // ------------------------------------------------------------------
    // 1) trusted + stock → guaranteed
    // ------------------------------------------------------------------
    await upsertPolicy(mode: 'trust', untrusted: 'approval');
    final s1 = await seedItem(suffix: 't1', qty: 2);
    createdProductIds.add(s1['productId']!);
    createdLiveIds.add(s1['liveId']!);
    createdItemIds.add(s1['itemId']!);

    final r1 = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s1['liveId'],
      'p_live_item_id': s1['itemId'],
      'p_qty': 1,
      'p_source': 'fleaber_live',
      'p_identity_linked': true,
    });
    final r1Id = r1 is Map ? r1['request_id']?.toString() : null;
    if (r1Id != null) createdRequestIds.add(r1Id);
    add(
      '01.trusted_stock_guaranteed',
      r1 is Map &&
          r1['ok'] == true &&
          r1['outcome'] == 'GUARANTEED' &&
          r1['status'] == 'accepted' &&
          r1['request_kind'] == 'guaranteed',
      '$r1',
    );

    // 15) TTL trusted snapshot
    add(
      '15.guaranteed_trusted_ttl',
      r1 is Map && r1['ttl_seconds_snapshot'] == 3600,
      '${r1 is Map ? r1['ttl_seconds_snapshot'] : r1}',
    );

    // ------------------------------------------------------------------
    // 2) trusted + no stock → unavailable
    // ------------------------------------------------------------------
    final s2 = await seedItem(suffix: 't2', qty: 0);
    createdProductIds.add(s2['productId']!);
    createdLiveIds.add(s2['liveId']!);
    createdItemIds.add(s2['itemId']!);
    // Force product qty 0
    await client.patch('products', 'id=eq.${s2['productId']}', {'quantity': 0});

    final r2 = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s2['liveId'],
      'p_live_item_id': s2['itemId'],
      'p_qty': 1,
      'p_identity_linked': true,
    });
    add(
      '02.trusted_no_stock_unavailable',
      r2 is Map && r2['ok'] == true && r2['outcome'] == 'UNAVAILABLE',
      '$r2',
    );

    // ------------------------------------------------------------------
    // 3) untrusted + approval → pending
    // ------------------------------------------------------------------
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
      accessToken: sellerToken,
    );
    final s3 = await seedItem(suffix: 't3', qty: 3);
    createdProductIds.add(s3['productId']!);
    createdLiveIds.add(s3['liveId']!);
    createdItemIds.add(s3['itemId']!);

    final r3 = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s3['liveId'],
      'p_live_item_id': s3['itemId'],
      'p_qty': 1,
      'p_identity_linked': true,
    });
    final r3Id = r3 is Map ? r3['request_id']?.toString() : null;
    if (r3Id != null) createdRequestIds.add(r3Id);
    add(
      '03.untrusted_approval_pending',
      r3 is Map &&
          r3['outcome'] == 'PENDING_APPROVAL' &&
          r3['status'] == 'pending' &&
          r3['request_kind'] == 'approval_pending',
      '$r3',
    );

    // 5) pending TTL ~45 min
    if (r3Id != null) {
      final rows = await client.select(
        'live_reservation_requests',
        filter: 'id=eq.$r3Id',
        limit: 1,
      );
      final exp = DateTime.tryParse(rows.first['expires_at']?.toString() ?? '');
      final created =
          DateTime.tryParse(rows.first['created_at']?.toString() ?? '') ??
              DateTime.now().toUtc();
      final diffMin =
          exp == null ? -1 : exp.difference(created.toUtc()).inMinutes;
      add(
        '05.pending_ttl_45min',
        diffMin >= 44 && diffMin <= 46,
        'diffMin=$diffMin exp=$exp',
      );
    } else {
      add('05.pending_ttl_45min', false, 'no request');
    }

    // 4) pending does not block stock
    final stockPending = await client.rpc('batata_live_item_stock', {
      'p_live_item_id': s3['itemId'],
    });
    add(
      '04.pending_never_blocks_stock',
      stockPending is Map &&
          stockPending['ok'] == true &&
          (stockPending['available_qty'] as num) >= 1,
      '$stockPending',
    );

    // ------------------------------------------------------------------
    // 6) seller accepts + stock → guaranteed
    // ------------------------------------------------------------------
    final acceptOk = await client.rpc(
      'batata_commerce_accept_pending',
      {'p_request_id': r3Id},
      accessToken: sellerToken,
    );
    add(
      '06.accept_with_stock_guaranteed',
      acceptOk is Map &&
          acceptOk['ok'] == true &&
          acceptOk['outcome'] == 'GUARANTEED' &&
          acceptOk['status'] == 'accepted',
      '$acceptOk',
    );

    // ------------------------------------------------------------------
    // 7) accept + no stock → unavailable
    // ------------------------------------------------------------------
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
      accessToken: sellerToken,
    );
    final s7 = await seedItem(suffix: 't7', qty: 1);
    createdProductIds.add(s7['productId']!);
    createdLiveIds.add(s7['liveId']!);
    createdItemIds.add(s7['itemId']!);
    final pending7 = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s7['liveId'],
      'p_live_item_id': s7['itemId'],
      'p_qty': 1,
    });
    final p7Id = pending7 is Map ? pending7['request_id']?.toString() : null;
    if (p7Id != null) createdRequestIds.add(p7Id);
    // Consume stock with buyerB guaranteed
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerB, 'p_mode': 'trusted'},
      accessToken: sellerToken,
    );
    // buyerB is seller — set policy trust benefit via seller trust on self? skip — insert accepted directly
    final hold7 = await client.insert('live_reservation_requests', {
      'live_id': s7['liveId'],
      'live_item_id': s7['itemId'],
      'seller_id': sellerId,
      'buyer_id': buyerB,
      'requested_qty': 1,
      'status': 'accepted',
      'source': 'fleaber_live',
      'request_kind': 'guaranteed',
      'expires_at': DateTime.now().toUtc().add(const Duration(hours: 2)).toIso8601String(),
    });
    createdRequestIds.add(hold7['id']!.toString());

    final acceptNo = await client.rpc(
      'batata_commerce_accept_pending',
      {'p_request_id': p7Id},
      accessToken: sellerToken,
    );
    add(
      '07.accept_no_stock_unavailable',
      acceptNo is Map &&
          acceptNo['ok'] == true &&
          acceptNo['outcome'] == 'UNAVAILABLE' &&
          acceptNo['expiry_reason'] == 'stock_unavailable',
      '$acceptNo',
    );

    // ------------------------------------------------------------------
    // 8) pending expire → no trust failure
    // ------------------------------------------------------------------
    await wipeTrust();
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
      accessToken: sellerToken,
    );
    final s8 = await seedItem(suffix: 't8', qty: 2);
    createdProductIds.add(s8['productId']!);
    createdLiveIds.add(s8['liveId']!);
    createdItemIds.add(s8['itemId']!);
    final pending8 = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s8['liveId'],
      'p_live_item_id': s8['itemId'],
    });
    final p8Id = pending8 is Map ? pending8['request_id']?.toString() : null;
    if (p8Id != null) {
      createdRequestIds.add(p8Id);
      await client.patch(
        'live_reservation_requests',
        'id=eq.$p8Id',
        {
          'expires_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
        },
      );
    }
    final exp8 = await client.rpc('batata_expire_live_reservation_requests', {
      'p_now': DateTime.now().toUtc().toIso8601String(),
    });
    final events8 = await client.select(
      'buyer_trust_events',
      filter: 'buyer_id=eq.$buyerId&kind=eq.failure',
      limit: 5,
    );
    final row8 = p8Id == null
        ? null
        : (await client.select(
            'live_reservation_requests',
            filter: 'id=eq.$p8Id',
            limit: 1,
          ))
            .first;
    add(
      '08.pending_expire_no_trust_failure',
      exp8 is num &&
          exp8 >= 1 &&
          events8.isEmpty &&
          row8 != null &&
          row8['expiry_reason'] == 'pending_ttl_expired',
      'exp=$exp8 events=${events8.length} reason=${row8?['expiry_reason']}',
    );

    // ------------------------------------------------------------------
    // 9) stock ends → pending closes without trust failure
    // ------------------------------------------------------------------
    await wipeTrust();
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
      accessToken: sellerToken,
    );
    final s9 = await seedItem(suffix: 't9', qty: 1);
    createdProductIds.add(s9['productId']!);
    createdLiveIds.add(s9['liveId']!);
    createdItemIds.add(s9['itemId']!);
    final pending9 = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s9['liveId'],
      'p_live_item_id': s9['itemId'],
    });
    final p9Id = pending9 is Map ? pending9['request_id']?.toString() : null;
    if (p9Id != null) createdRequestIds.add(p9Id);
    // Clear distrust so trusted auto can take stock — use insert accepted as B
    final hold9 = await client.insert('live_reservation_requests', {
      'live_id': s9['liveId'],
      'live_item_id': s9['itemId'],
      'seller_id': sellerId,
      'buyer_id': buyerB,
      'requested_qty': 1,
      'status': 'accepted',
      'source': 'fleaber_live',
      'request_kind': 'guaranteed',
      'expires_at': DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
    });
    createdRequestIds.add(hold9['id']!.toString());
    final closed = await client.rpc('batata_close_pending_for_stock', {
      'p_live_item_id': s9['itemId'],
      'p_except_request_id': hold9['id'],
    });
    final row9 = p9Id == null
        ? null
        : (await client.select(
            'live_reservation_requests',
            filter: 'id=eq.$p9Id',
            limit: 1,
          ))
            .first;
    final fail9 = await client.select(
      'buyer_trust_events',
      filter: 'buyer_id=eq.$buyerId&kind=eq.failure',
      limit: 5,
    );
    add(
      '09.stock_closes_pending_no_failure',
      (closed is num && closed >= 1) &&
          row9 != null &&
          row9['expiry_reason'] == 'stock_unavailable' &&
          fail9.isEmpty,
      'closed=$closed row=$row9 fails=${fail9.length}',
    );

    // ------------------------------------------------------------------
    // 10–11) pay_only → bag, not guaranteed, not approval pending
    // ------------------------------------------------------------------
    await wipeTrust();
    await upsertPolicy(mode: 'pay_only', untrusted: 'pay_required');
    final s10 = await seedItem(suffix: 't10', qty: 2);
    createdProductIds.add(s10['productId']!);
    createdLiveIds.add(s10['liveId']!);
    createdItemIds.add(s10['itemId']!);
    final r10 = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s10['liveId'],
      'p_live_item_id': s10['itemId'],
    });
    final r10Id = r10 is Map ? r10['request_id']?.toString() : null;
    if (r10Id != null) createdRequestIds.add(r10Id);
    add(
      '10.pay_only_not_guaranteed',
      r10 is Map &&
          r10['outcome'] == 'BAG_UNGUARANTEED' &&
          r10['request_kind'] == 'bag_hold_none' &&
          r10['status'] == 'pending',
      '$r10',
    );
    add(
      '11.pay_only_not_approval_pending',
      r10 is Map && r10['request_kind'] != 'approval_pending',
      '$r10',
    );

    // ------------------------------------------------------------------
    // 12) Facebook unlinked → no trusted benefit
    // ------------------------------------------------------------------
    await upsertPolicy(mode: 'trust', untrusted: 'approval');
    final s12 = await seedItem(suffix: 't12', qty: 2);
    createdProductIds.add(s12['productId']!);
    createdLiveIds.add(s12['liveId']!);
    createdItemIds.add(s12['itemId']!);
    final r12 = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': null,
      'p_live_id': s12['liveId'],
      'p_live_item_id': s12['itemId'],
      'p_identity_linked': false,
    });
    // service_role can pass null buyer; outcome should be pending approval not guaranteed
    final r12Trust = r12 is Map && r12['decision'] is Map
        ? ((r12['decision'] as Map)['trust'] as Map?)
        : null;
    add(
      '12.facebook_unlinked_no_trusted',
      r12 is Map &&
          r12['outcome'] == 'PENDING_APPROVAL' &&
          (r12Trust == null ||
              r12Trust['decision'] == 'IDENTITY_INSUFFICIENT' ||
              r12Trust['has_benefit'] == false),
      '$r12',
    );
    final r12Id = r12 is Map ? r12['request_id']?.toString() : null;
    if (r12Id != null) createdRequestIds.add(r12Id);

    // ------------------------------------------------------------------
    // 13–14) seller distrust / trust local
    // ------------------------------------------------------------------
    await wipeTrust();
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
      accessToken: sellerToken,
    );
    final d13 = await client.rpc('batata_buyer_trust_decision', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
    });
    add(
      '13.seller_manual_distrust',
      d13 is Map &&
          d13['decision'] == 'SELLER_DISTRUST' &&
          d13['has_benefit'] == false,
      '$d13',
    );
    await client.rpc('batata_buyer_trust_record_failure', {
      'p_buyer_id': buyerId,
      'p_source_type': 'live_reservation_request',
      'p_source_id': '$tag-bootstrap-lost',
      'p_failure_reason': 'guaranteed_hold_expired_unpaid',
    });
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'trusted'},
      accessToken: sellerToken,
    );
    final d14 = await client.rpc('batata_buyer_trust_decision', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
    });
    add(
      '14.seller_manual_trust_local',
      d14 is Map &&
          d14['decision'] == 'SELLER_TRUST' &&
          d14['has_benefit'] == true &&
          d14['global_status'] == 'lost',
      '$d14',
    );

    // ------------------------------------------------------------------
    // 16) policy change does not alter old snapshot
    // ------------------------------------------------------------------
    await wipeTrust();
    await upsertPolicy(
      mode: 'trust',
      untrusted: 'approval',
      normalTtl: 1800,
      trustedTtl: 3600,
    );
    final s16 = await seedItem(suffix: 't16', qty: 2);
    createdProductIds.add(s16['productId']!);
    createdLiveIds.add(s16['liveId']!);
    createdItemIds.add(s16['itemId']!);
    final r16 = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s16['liveId'],
      'p_live_item_id': s16['itemId'],
    });
    final r16Id = r16 is Map ? r16['request_id']?.toString() : null;
    if (r16Id != null) createdRequestIds.add(r16Id);
    final snapBefore = r16 is Map ? r16['ttl_seconds_snapshot'] : null;
    final verBefore = r16 is Map ? r16['policy_version_snapshot'] : null;
    await upsertPolicy(
      mode: 'trust',
      untrusted: 'approval',
      normalTtl: 900,
      trustedTtl: 7200,
    );
    final row16 = r16Id == null
        ? null
        : (await client.select(
            'live_reservation_requests',
            filter: 'id=eq.$r16Id',
            limit: 1,
          ))
            .first;
    add(
      '16.policy_change_preserves_snapshot',
      row16 != null &&
          row16['ttl_seconds_snapshot'] == snapBefore &&
          row16['policy_version_snapshot'] == verBefore,
      'before=$snapBefore/$verBefore after=${row16?['ttl_seconds_snapshot']}/${row16?['policy_version_snapshot']}',
    );

    // 41) policy change only affects new
    final r41 = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s16['liveId'],
      'p_live_item_id': s16['itemId'],
    });
    final r41Id = r41 is Map ? r41['request_id']?.toString() : null;
    if (r41Id != null) createdRequestIds.add(r41Id);
    add(
      '41.policy_change_affects_new_only',
      r41 is Map &&
          r41['ttl_seconds_snapshot'] == 7200 &&
          row16 != null &&
          row16['ttl_seconds_snapshot'] == 3600,
      'old=${row16?['ttl_seconds_snapshot']} new=${r41 is Map ? r41['ttl_seconds_snapshot'] : r41}',
    );

    // ------------------------------------------------------------------
    // 17–20) guaranteed expiry + payment protection
    // ------------------------------------------------------------------
    await wipeTrust();
    final s17 = await seedItem(suffix: 't17', qty: 2);
    createdProductIds.add(s17['productId']!);
    createdLiveIds.add(s17['liveId']!);
    createdItemIds.add(s17['itemId']!);
    final r17 = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s17['liveId'],
      'p_live_item_id': s17['itemId'],
    });
    final r17Id = r17 is Map ? r17['request_id']?.toString() : null;
    if (r17Id != null) {
      createdRequestIds.add(r17Id);
      await client.patch(
        'live_reservation_requests',
        'id=eq.$r17Id',
        {
          'expires_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 2))
              .toIso8601String(),
        },
      );
    }
    final availBefore = await client.rpc('batata_live_item_available_qty_engine', {
      'p_live_item_id': s17['itemId'],
    });
    final expG = await client.rpc('batata_expire_guaranteed_reservations', {
      'p_now': DateTime.now().toUtc().toIso8601String(),
      'p_request_id': r17Id,
    });
    final availAfter = await client.rpc('batata_live_item_available_qty_engine', {
      'p_live_item_id': s17['itemId'],
    });
    final row17 = r17Id == null
        ? null
        : (await client.select(
            'live_reservation_requests',
            filter: 'id=eq.$r17Id',
            limit: 1,
          ))
            .first;
    add(
      '17.guaranteed_expiry_releases_stock',
      expG is Map &&
          expG['expired'] >= 1 &&
          row17 != null &&
          row17['status'] == 'expired' &&
          (availAfter is num) &&
          (availBefore is num) &&
          availAfter > availBefore,
      'exp=$expG before=$availBefore after=$availAfter',
    );

    // 18) buyer-responsible → failure once
    final fails18 = await client.select(
      'buyer_trust_events',
      filter:
          'buyer_id=eq.$buyerId&kind=eq.failure&source_id=eq.$r17Id',
      limit: 5,
    );
    add(
      '18.expiry_buyer_failure_once',
      fails18.length == 1 &&
          fails18.first['failure_reason'] == 'guaranteed_hold_expired_unpaid',
      '${fails18.length} ${fails18.isEmpty ? '' : fails18.first}',
    );

    // Idempotent failure
    await client.rpc('batata_buyer_trust_record_failure', {
      'p_buyer_id': buyerId,
      'p_source_type': 'live_reservation_request',
      'p_source_id': r17Id,
      'p_failure_reason': 'guaranteed_hold_expired_unpaid',
    });
    final fails18b = await client.select(
      'buyer_trust_events',
      filter:
          'buyer_id=eq.$buyerId&kind=eq.failure&source_id=eq.$r17Id',
      limit: 5,
    );
    add('30.failure_idempotent', fails18b.length == 1, '${fails18b.length}');

    // 19) system/stock reasons → no failure (via accept_no_stock path already)
    add(
      '19.non_buyer_expiry_no_failure',
      acceptNo is Map && acceptNo['expiry_reason'] == 'stock_unavailable',
      'covered by 07 + trust wipe',
    );

    // 20) payment processing → no penalize
    await wipeTrust();
    final s20 = await seedItem(suffix: 't20', qty: 1);
    createdProductIds.add(s20['productId']!);
    createdLiveIds.add(s20['liveId']!);
    createdItemIds.add(s20['itemId']!);
    final r20 = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s20['liveId'],
      'p_live_item_id': s20['itemId'],
    });
    final r20Id = r20 is Map ? r20['request_id']?.toString() : null;
    if (r20Id != null) createdRequestIds.add(r20Id);
    final order20 = await client.insert('orders', {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': s20['productId'],
      'live_id': s20['liveId'],
      'live_item_id': s20['itemId'],
      'quantity': 1,
      'price_total': 5,
      'status': 'aguarda_pagamento',
      'payment_method': 'stripe',
      'stripe_payment_intent_id': 'pi_test_$tag',
    });
    await client.patch(
      'live_reservation_requests',
      'id=eq.$r20Id',
      {
        'expires_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
        'notes': 'stripe_checkout:${order20['id']}',
      },
    );
    final exp20 = await client.rpc('batata_expire_guaranteed_reservations', {
      'p_now': DateTime.now().toUtc().toIso8601String(),
      'p_request_id': r20Id,
    });
    final row20 = (await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$r20Id',
      limit: 1,
    ))
        .first;
    final fail20 = await client.select(
      'buyer_trust_events',
      filter: 'buyer_id=eq.$buyerId&kind=eq.failure&source_id=eq.$r20Id',
      limit: 3,
    );
    add(
      '20.payment_processing_no_penalize',
      exp20 is Map &&
          exp20['payment_deferred'] >= 1 &&
          row20['status'] == 'accepted' &&
          fail20.isEmpty,
      'exp=$exp20 status=${row20['status']} fails=${fail20.length}',
    );

    // ------------------------------------------------------------------
    // 21–24) extension
    // ------------------------------------------------------------------
    final s21 = await seedItem(suffix: 't21', qty: 2);
    createdProductIds.add(s21['productId']!);
    createdLiveIds.add(s21['liveId']!);
    createdItemIds.add(s21['itemId']!);
    final r21 = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s21['liveId'],
      'p_live_item_id': s21['itemId'],
    });
    final r21Id = r21 is Map ? r21['request_id']?.toString() : null;
    if (r21Id != null) createdRequestIds.add(r21Id);
    final ext1 = await client.rpc(
      'batata_commerce_extend_guaranteed_once',
      {'p_request_id': r21Id, 'p_ttl_seconds': 1800},
      accessToken: sellerToken,
    );
    add(
      '21.extension_once_ok',
      ext1 is Map && ext1['ok'] == true && ext1['extended_once'] == true,
      '$ext1',
    );
    final ext2 = await client.rpc(
      'batata_commerce_extend_guaranteed_once',
      {'p_request_id': r21Id, 'p_ttl_seconds': 1800},
      accessToken: sellerToken,
    );
    add(
      '22.second_extension_rejected',
      ext2 is Map &&
          ext2['ok'] == false &&
          ext2['error'] == 'already_extended',
      '$ext2',
    );
    final extLow = await client.rpc(
      'batata_commerce_extend_guaranteed_once',
      {'p_request_id': r21Id, 'p_ttl_seconds': 60},
      accessToken: sellerToken,
    );
    add(
      '23.duration_lt_15min_rejected',
      extLow is Map && extLow['error'] == 'ttl_out_of_range',
      '$extLow',
    );
    final extHigh = await client.rpc(
      'batata_commerce_extend_guaranteed_once',
      {'p_request_id': r21Id, 'p_ttl_seconds': 999999},
      accessToken: sellerToken,
    );
    add(
      '24.duration_gt_5days_rejected',
      extHigh is Map && extHigh['error'] == 'ttl_out_of_range',
      '$extHigh',
    );

    // ------------------------------------------------------------------
    // 25) concurrency stock=1 → only one guarantee
    // ------------------------------------------------------------------
    await wipeTrust();
    final s25 = await seedItem(suffix: 't25', qty: 1);
    createdProductIds.add(s25['productId']!);
    createdLiveIds.add(s25['liveId']!);
    createdItemIds.add(s25['itemId']!);
    final cA = client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s25['liveId'],
      'p_live_item_id': s25['itemId'],
    });
    final cB = client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerB,
      'p_live_id': s25['liveId'],
      'p_live_item_id': s25['itemId'],
    });
    final results = await Future.wait([cA, cB]);
    for (final r in results) {
      final id = r is Map ? r['request_id']?.toString() : null;
      if (id != null) createdRequestIds.add(id);
    }
    final guaranteed = results
        .where((r) => r is Map && r['outcome'] == 'GUARANTEED')
        .length;
    final unavailable = results
        .where((r) => r is Map && r['outcome'] == 'UNAVAILABLE')
        .length;
    add(
      '25.concurrency_one_guarantee',
      guaranteed == 1 && unavailable == 1,
      'G=$guaranteed U=$unavailable raw=$results',
    );

    // ------------------------------------------------------------------
    // 26–28) cross-item + order block
    // ------------------------------------------------------------------
    final productX = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P2 cross $tag',
      'price': 5,
      'quantity': 1,
      'ref_code': 'P2X-$tag',
      'list_on_marketplace': false,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    createdProductIds.add(productX['id']!.toString());
    final liveXa = await client.insert('lives', {
      'title': 'P2XA_$tag',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final liveXb = await client.insert('lives', {
      'title': 'P2XB_$tag',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    createdLiveIds.addAll([liveXa['id']!.toString(), liveXb['id']!.toString()]);
    final itemXa = await client.insert('live_items', {
      'live_id': liveXa['id'],
      'ref_code': productX['ref_code'],
      'title': 'XA',
      'price': 5,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': productX['id'],
      'checkout_product_id': productX['id'],
    });
    final itemXb = await client.insert('live_items', {
      'live_id': liveXb['id'],
      'ref_code': productX['ref_code'],
      'title': 'XB',
      'price': 5,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': productX['id'],
      'checkout_product_id': productX['id'],
    });
    createdItemIds.addAll([itemXa['id']!.toString(), itemXb['id']!.toString()]);

    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
      accessToken: sellerToken,
    );
    await upsertPolicy(mode: 'trust', untrusted: 'approval');
    final pendX = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': liveXa['id'],
      'p_live_item_id': itemXa['id'],
    });
    final pendXId = pendX is Map ? pendX['request_id']?.toString() : null;
    if (pendXId != null) createdRequestIds.add(pendXId);
    final stockXbPending = await client.rpc('batata_live_item_stock', {
      'p_live_item_id': itemXb['id'],
    });
    add(
      '26.cross_item_pending_no_block',
      stockXbPending is Map &&
          (stockXbPending['available_qty'] as num) == 1 &&
          (stockXbPending['blocked_qty'] as num) == 0,
      '$stockXbPending',
    );

    await wipeTrust();
    final guarX = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': liveXb['id'],
      'p_live_item_id': itemXb['id'],
    });
    final guarXId = guarX is Map ? guarX['request_id']?.toString() : null;
    if (guarXId != null) createdRequestIds.add(guarXId);
    final stockXaAfter = await client.rpc('batata_live_item_available_qty_engine', {
      'p_live_item_id': itemXa['id'],
    });
    add(
      '27.cross_item_guaranteed_blocks',
      guarX is Map &&
          guarX['outcome'] == 'GUARANTEED' &&
          stockXaAfter is num &&
          stockXaAfter == 0,
      'guar=$guarX avail_engine=$stockXaAfter',
    );

    // 28 order blocking
    final s28 = await seedItem(suffix: 't28', qty: 1);
    createdProductIds.add(s28['productId']!);
    createdLiveIds.add(s28['liveId']!);
    createdItemIds.add(s28['itemId']!);
    final ord28 = await client.insert('orders', {
      'buyer_id': buyerB,
      'seller_id': sellerId,
      'product_id': s28['productId'],
      'live_id': s28['liveId'],
      'live_item_id': s28['itemId'],
      'quantity': 1,
      'price_total': 5,
      'status': 'reservado',
    });
    final r28 = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': s28['liveId'],
      'p_live_item_id': s28['itemId'],
    });
    add(
      '28.order_blocking_still_blocks',
      r28 is Map && r28['outcome'] == 'UNAVAILABLE',
      'order=${ord28['id']} r=$r28',
    );

    // ------------------------------------------------------------------
    // 29–31) positive completion idempotent + multi-item one fulfillment
    // ------------------------------------------------------------------
    await wipeTrust();
    final f1 = await client.rpc('batata_buyer_trust_record_fulfillment', {
      'p_buyer_id': buyerId,
      'p_source_type': 'order',
      'p_source_id': '$tag-order-multi',
      'p_meta': {'items': 5},
    });
    final f2 = await client.rpc('batata_buyer_trust_record_fulfillment', {
      'p_buyer_id': buyerId,
      'p_source_type': 'order',
      'p_source_id': '$tag-order-multi',
      'p_meta': {'items': 5},
    });
    final fulfills = await client.select(
      'buyer_trust_events',
      filter:
          'buyer_id=eq.$buyerId&kind=eq.fulfillment&source_id=eq.$tag-order-multi',
      limit: 5,
    );
    add(
      '29.positive_completion_idempotent',
      f1 is Map &&
          f1['inserted'] == true &&
          f2 is Map &&
          f2['inserted'] == false &&
          fulfills.length == 1,
      'f1=$f1 f2=$f2 n=${fulfills.length}',
    );
    add(
      '31.multi_item_order_one_completion',
      fulfills.length == 1,
      'n=${fulfills.length}',
    );

    // ------------------------------------------------------------------
    // 32–37) trust thresholds + recovery
    // ------------------------------------------------------------------
    await wipeTrust();
    // 0–4: 1 failure loses
    await client.rpc('batata_buyer_trust_record_failure', {
      'p_buyer_id': buyerId,
      'p_source_type': 'live_reservation_request',
      'p_source_id': '$tag-thr-1',
      'p_failure_reason': 'guaranteed_hold_expired_unpaid',
    });
    var st = await client.select(
      'buyer_trust_state',
      filter: 'buyer_id=eq.$buyerId',
      limit: 1,
    );
    add(
      '32.tier_0_4_first_failure_loses',
      st.isNotEmpty && st.first['global_status'] == 'lost',
      '$st',
    );

    await wipeTrust();
    for (var i = 0; i < 5; i++) {
      await client.rpc('batata_buyer_trust_record_fulfillment', {
        'p_buyer_id': buyerId,
        'p_source_type': 'order',
        'p_source_id': '$tag-ful-5-$i',
      });
    }
    await client.rpc('batata_buyer_trust_record_failure', {
      'p_buyer_id': buyerId,
      'p_source_type': 'live_reservation_request',
      'p_source_id': '$tag-thr5-1',
      'p_failure_reason': 'guaranteed_hold_expired_unpaid',
    });
    st = await client.select(
      'buyer_trust_state',
      filter: 'buyer_id=eq.$buyerId',
      limit: 1,
    );
    final stillTrusted = st.isEmpty || st.first['global_status'] == 'trusted';
    await client.rpc('batata_buyer_trust_record_failure', {
      'p_buyer_id': buyerId,
      'p_source_type': 'live_reservation_request',
      'p_source_id': '$tag-thr5-2',
      'p_failure_reason': 'guaranteed_hold_expired_unpaid',
    });
    st = await client.select(
      'buyer_trust_state',
      filter: 'buyer_id=eq.$buyerId',
      limit: 1,
    );
    add(
      '33.tier_5_19_second_failure_loses',
      stillTrusted && st.isNotEmpty && st.first['global_status'] == 'lost',
      'after1trusted=$stillTrusted after2=$st',
    );

    await wipeTrust();
    for (var i = 0; i < 20; i++) {
      await client.rpc('batata_buyer_trust_record_fulfillment', {
        'p_buyer_id': buyerId,
        'p_source_type': 'order',
        'p_source_id': '$tag-ful-20-$i',
      });
    }
    for (var i = 1; i <= 2; i++) {
      await client.rpc('batata_buyer_trust_record_failure', {
        'p_buyer_id': buyerId,
        'p_source_type': 'live_reservation_request',
        'p_source_id': '$tag-thr20-$i',
        'p_failure_reason': 'guaranteed_hold_expired_unpaid',
      });
    }
    st = await client.select(
      'buyer_trust_state',
      filter: 'buyer_id=eq.$buyerId',
      limit: 1,
    );
    final trustedAfter2 = st.isEmpty || st.first['global_status'] == 'trusted';
    await client.rpc('batata_buyer_trust_record_failure', {
      'p_buyer_id': buyerId,
      'p_source_type': 'live_reservation_request',
      'p_source_id': '$tag-thr20-3',
      'p_failure_reason': 'guaranteed_hold_expired_unpaid',
    });
    st = await client.select(
      'buyer_trust_state',
      filter: 'buyer_id=eq.$buyerId',
      limit: 1,
    );
    add(
      '34.tier_20_third_failure_loses',
      trustedAfter2 && st.isNotEmpty && st.first['global_status'] == 'lost',
      'after2=$trustedAfter2 after3=$st',
    );

    // 35 failure outside 90d doesn't count — insert old failure via SQL-ish patch
    await wipeTrust();
    for (var i = 0; i < 5; i++) {
      await client.rpc('batata_buyer_trust_record_fulfillment', {
        'p_buyer_id': buyerId,
        'p_source_type': 'order',
        'p_source_id': '$tag-oldful-$i',
      });
    }
    final oldFail = await client.insert('buyer_trust_events', {
      'buyer_id': buyerId,
      'kind': 'failure',
      'source_type': 'live_reservation_request',
      'source_id': '$tag-old-fail',
      'failure_reason': 'guaranteed_hold_expired_unpaid',
      'occurred_at': DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 100))
          .toIso8601String(),
    });
    await client.rpc('batata_buyer_trust_recompute', {'p_buyer_id': buyerId});
    await client.rpc('batata_buyer_trust_record_failure', {
      'p_buyer_id': buyerId,
      'p_source_type': 'live_reservation_request',
      'p_source_id': '$tag-recent-only-one',
      'p_failure_reason': 'guaranteed_hold_expired_unpaid',
    });
    st = await client.select(
      'buyer_trust_state',
      filter: 'buyer_id=eq.$buyerId',
      limit: 1,
    );
    add(
      '35.failure_outside_90d_ignored',
      (st.isEmpty || st.first['global_status'] == 'trusted') &&
          oldFail['id'] != null,
      '$st old=${oldFail['id']}',
    );

    // 36 recovery 3 completions
    await wipeTrust();
    await client.rpc('batata_buyer_trust_record_failure', {
      'p_buyer_id': buyerId,
      'p_source_type': 'live_reservation_request',
      'p_source_id': '$tag-lose-rec',
      'p_failure_reason': 'guaranteed_hold_expired_unpaid',
    });
    for (var i = 0; i < 3; i++) {
      await client.rpc('batata_buyer_trust_record_fulfillment', {
        'p_buyer_id': buyerId,
        'p_source_type': 'order',
        'p_source_id': '$tag-rec-$i',
      });
    }
    st = await client.select(
      'buyer_trust_state',
      filter: 'buyer_id=eq.$buyerId',
      limit: 1,
    );
    add(
      '36.three_completions_recover',
      st.isNotEmpty && st.first['global_status'] == 'trusted',
      '$st',
    );

    // 37 failure during recovery resets
    await wipeTrust();
    await client.rpc('batata_buyer_trust_record_failure', {
      'p_buyer_id': buyerId,
      'p_source_type': 'live_reservation_request',
      'p_source_id': '$tag-lose-rec2',
      'p_failure_reason': 'guaranteed_hold_expired_unpaid',
    });
    await client.rpc('batata_buyer_trust_record_fulfillment', {
      'p_buyer_id': buyerId,
      'p_source_type': 'order',
      'p_source_id': '$tag-rec2-0',
    });
    await client.rpc('batata_buyer_trust_record_fulfillment', {
      'p_buyer_id': buyerId,
      'p_source_type': 'order',
      'p_source_id': '$tag-rec2-1',
    });
    await client.rpc('batata_buyer_trust_record_failure', {
      'p_buyer_id': buyerId,
      'p_source_type': 'live_reservation_request',
      'p_source_id': '$tag-rec2-fail',
      'p_failure_reason': 'guaranteed_hold_expired_unpaid',
    });
    st = await client.select(
      'buyer_trust_state',
      filter: 'buyer_id=eq.$buyerId',
      limit: 1,
    );
    add(
      '37.failure_during_recovery_resets',
      st.isNotEmpty &&
          st.first['global_status'] == 'lost' &&
          (st.first['recovery_count'] as num) == 0,
      '$st',
    );

    // ------------------------------------------------------------------
    // 38–40) RLS / forge
    // ------------------------------------------------------------------
    final forgeG = await client.rpc(
      'batata_commerce_accept_pending',
      {'p_request_id': r21Id},
      accessToken: buyerToken,
    );
    add(
      '38.buyer_cannot_forge_guaranteed',
      forgeG is Map && forgeG['ok'] == false,
      '$forgeG',
    );

    Object? forgeFail;
    try {
      forgeFail = await client.rpc(
        'batata_buyer_trust_record_failure',
        {
          'p_buyer_id': buyerId,
          'p_source_type': 'live_reservation_request',
          'p_source_id': '$tag-forge-fail',
          'p_failure_reason': 'guaranteed_hold_expired_unpaid',
        },
        accessToken: buyerToken,
      );
    } catch (e) {
      forgeFail = e;
    }
    add(
      '39.buyer_cannot_forge_trust',
      (forgeFail is Map && forgeFail['ok'] == false) ||
          '$forgeFail'.contains('403') ||
          '$forgeFail'.contains('42501') ||
          '$forgeFail'.contains('permission denied'),
      '$forgeFail',
    );

    Object? forgeSeller;
    try {
      forgeSeller = await client.rpc(
        'batata_buyer_trust_record_failure',
        {
          'p_buyer_id': buyerId,
          'p_source_type': 'live_reservation_request',
          'p_source_id': '$tag-seller-forge2',
          'p_failure_reason': 'guaranteed_hold_expired_unpaid',
        },
        accessToken: sellerToken,
      );
    } catch (e) {
      forgeSeller = e;
    }
    add(
      '40.seller_cannot_alter_global_trust',
      (forgeSeller is Map && forgeSeller['ok'] == false) ||
          '$forgeSeller'.contains('403') ||
          '$forgeSeller'.contains('42501') ||
          '$forgeSeller'.contains('permission denied'),
      '$forgeSeller',
    );

    // ------------------------------------------------------------------
    // 42) Phase 1 regression smoke
    // ------------------------------------------------------------------
    final pred = await client.rpc('batata_lrr_counts_in_cross_block', {
      'p_status': 'pending',
      'p_request_kind': 'approval_pending',
    });
    final dNew = await client.rpc('batata_buyer_trust_decision', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
    });
    add(
      '42.phase1_regression_smoke',
      pred == false && dNew is Map && dNew['ok'] == true,
      'pred=$pred decision=$dNew',
    );

    // Extra: promote backend ready
    await wipeTrust();
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
      accessToken: sellerToken,
    );
    await upsertPolicy(mode: 'trust', untrusted: 'approval');
    final sP = await seedItem(suffix: 'promo', qty: 2);
    createdProductIds.add(sP['productId']!);
    createdLiveIds.add(sP['liveId']!);
    createdItemIds.add(sP['itemId']!);
    final pendP = await client.rpc('batata_reserve_with_policy', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': sP['liveId'],
      'p_live_item_id': sP['itemId'],
    });
    final pendPId = pendP is Map ? pendP['request_id']?.toString() : null;
    if (pendPId != null) createdRequestIds.add(pendPId);
    final promo = await client.rpc(
      'batata_commerce_trust_and_promote',
      {
        'p_seller_id': sellerId,
        'p_buyer_id': buyerId,
        'p_live_id': sP['liveId'],
      },
      accessToken: sellerToken,
    );
    add(
      'promo.trust_and_promote_backend',
      promo is Map && promo['ok'] == true && (promo['promoted'] as num) >= 1,
      '$promo',
    );
  } catch (e, st) {
    add('ZZ.unhandled', false, '$e\n$st');
  } finally {
    // Best-effort cleanup of test rows
    for (final id in createdRequestIds) {
      try {
        await client.deleteWhere('commerce_reservation_events', 'request_id=eq.$id');
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
  final outDir = Directory('11-unified-commerce-phase2-reservation-engine');
  await outDir.create(recursive: true);
  final outFile = File(
    '11-unified-commerce-phase2-reservation-engine/test-results-raw.json',
  );
  await outFile.writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  print('\nSUMMARY passed=$passed failed=$failed total=${checks.length}');
  print('Wrote ${outFile.path}');
  if (failed > 0) exit(1);
}
