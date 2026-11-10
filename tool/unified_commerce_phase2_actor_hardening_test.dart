// ignore_for_file: avoid_print
/// Phase 2 final hardening — authenticated cannot spoof processed_by_user_id.
///
///   dart run tool/unified_commerce_phase2_actor_hardening_test.dart
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
  // Buyer UUID used as spoof target / alternate "seller B" identity
  final spoofTarget = buyerId;

  final checks = <_Check>[];
  void add(String id, bool ok, [String detail = '']) {
    checks.add((id: id, ok: ok, detail: detail));
    print('${ok ? 'PASS' : 'FAIL'} $id ${detail.isEmpty ? '' : '— $detail'}');
  }

  final tag =
      'p2ah_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  Future<void> upsertPolicy() async {
    final existing = await client.select(
      'seller_reservation_settings',
      filter: 'seller_id=eq.$sellerId',
      limit: 1,
    );
    if (existing.isEmpty) {
      await client.insert('seller_reservation_settings', {
        'seller_id': sellerId,
        'policy_mode': 'trust',
        'untrusted_mode': 'approval',
        'normal_ttl_seconds': 1800,
        'trusted_ttl_seconds': 3600,
        'accept_fleaber_global_trust': true,
      });
    } else {
      await client.patch(
        'seller_reservation_settings',
        'seller_id=eq.$sellerId',
        {
          'policy_mode': 'trust',
          'untrusted_mode': 'approval',
        },
      );
    }
  }

  Future<Map<String, String>> seedItem(String suffix) async {
    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P2AH $tag-$suffix',
      'price': 5,
      'quantity': 2,
      'ref_code': 'P2AH-$tag-$suffix',
      'list_on_marketplace': false,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live = await client.insert('lives', {
      'title': 'P2AH_${tag}_$suffix',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final item = await client.insert('live_items', {
      'live_id': live['id'],
      'ref_code': 'P2AH-$tag-$suffix',
      'title': 'P2AH $suffix',
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

  Future<String> insertPending({
    required Map<String, String> s,
    required String seller,
    required String buyer,
  }) async {
    final row = await client.insert('live_reservation_requests', {
      'live_id': s['liveId'],
      'live_item_id': s['itemId'],
      'seller_id': seller,
      'buyer_id': buyer,
      'requested_qty': 1,
      'status': 'pending',
      'source': 'fleaber_live',
      'request_kind': 'approval_pending',
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 45))
          .toIso8601String(),
    });
    return row['id']!.toString();
  }

  await client.patch('profiles', 'id=eq.$sellerId', {'hub_published': true});
  await upsertPolicy();
  await client.rpc(
    'batata_seller_buyer_trust_set',
    {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
    accessToken: sellerToken,
  );

  final createdRequestIds = <String>[];
  final createdItemIds = <String>[];
  final createdLiveIds = <String>[];
  final createdProductIds = <String>[];

  try {
    // ------------------------------------------------------------------
    // 1) Accept with spoofed p_processed_by → must record seller A
    // ------------------------------------------------------------------
    final s1 = await seedItem('accept');
    createdProductIds.add(s1['productId']!);
    createdLiveIds.add(s1['liveId']!);
    createdItemIds.add(s1['itemId']!);
    final pend1 = await insertPending(
      s: s1,
      seller: sellerId,
      buyer: buyerId,
    );
    createdRequestIds.add(pend1);

    final accept1 = await client.rpc(
      'batata_commerce_accept_pending',
      {
        'p_request_id': pend1,
        'p_processed_by': spoofTarget, // pretend buyer did it
      },
      accessToken: sellerToken,
    );
    final row1 = (await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$pend1',
      limit: 1,
    )).first;
    add(
      '1.accept_spoof_blocked_actor_is_seller',
      accept1 is Map &&
          accept1['ok'] == true &&
          accept1['outcome'] == 'GUARANTEED' &&
          row1['processed_by_user_id'] == sellerId &&
          row1['processed_by_user_id'] != spoofTarget &&
          (accept1['processed_by_user_id'] == null ||
              accept1['processed_by_user_id'] == sellerId),
      'rpc=$accept1 db_actor=${row1['processed_by_user_id']} seller=$sellerId spoof=$spoofTarget',
    );

    // ------------------------------------------------------------------
    // 2) Reject with spoof → must record seller A
    // ------------------------------------------------------------------
    final s2 = await seedItem('reject');
    createdProductIds.add(s2['productId']!);
    createdLiveIds.add(s2['liveId']!);
    createdItemIds.add(s2['itemId']!);
    final pend2 = await insertPending(
      s: s2,
      seller: sellerId,
      buyer: buyerId,
    );
    createdRequestIds.add(pend2);

    final reject2 = await client.rpc(
      'batata_commerce_reject_pending',
      {
        'p_request_id': pend2,
        'p_processed_by': spoofTarget,
        'p_notes': 'spoof_attempt',
      },
      accessToken: sellerToken,
    );
    final row2 = (await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$pend2',
      limit: 1,
    )).first;
    add(
      '2.reject_spoof_blocked_actor_is_seller',
      reject2 is Map &&
          reject2['ok'] == true &&
          reject2['outcome'] == 'REJECTED' &&
          row2['processed_by_user_id'] == sellerId &&
          row2['processed_by_user_id'] != spoofTarget,
      'rpc=$reject2 db_actor=${row2['processed_by_user_id']}',
    );

    // ------------------------------------------------------------------
    // 3) Seller A cannot manage seller B (buyer as alternate seller)
    // ------------------------------------------------------------------
    final s3 = await seedItem('cross');
    createdProductIds.add(s3['productId']!);
    createdLiveIds.add(s3['liveId']!);
    createdItemIds.add(s3['itemId']!);
    // Pending owned by buyerId as seller (cross-seller target)
    final pend3 = await insertPending(
      s: s3,
      seller: buyerId,
      buyer: sellerId,
    );
    createdRequestIds.add(pend3);

    final crossAccept = await client.rpc(
      'batata_commerce_accept_pending',
      {'p_request_id': pend3, 'p_processed_by': sellerId},
      accessToken: sellerToken,
    );
    final crossReject = await client.rpc(
      'batata_commerce_reject_pending',
      {'p_request_id': pend3},
      accessToken: sellerToken,
    );
    final row3 = (await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$pend3',
      limit: 1,
    )).first;
    add(
      '3.cross_seller_access_blocked',
      crossAccept is Map &&
          crossAccept['ok'] == false &&
          crossAccept['error'] == 'seller_only' &&
          crossReject is Map &&
          crossReject['ok'] == false &&
          crossReject['error'] == 'seller_only' &&
          row3['status'] == 'pending',
      'accept=$crossAccept reject=$crossReject status=${row3['status']}',
    );

    // ------------------------------------------------------------------
    // 4) Buyer cannot accept/reject
    // ------------------------------------------------------------------
    final s4 = await seedItem('buyer');
    createdProductIds.add(s4['productId']!);
    createdLiveIds.add(s4['liveId']!);
    createdItemIds.add(s4['itemId']!);
    final pend4 = await insertPending(
      s: s4,
      seller: sellerId,
      buyer: buyerId,
    );
    createdRequestIds.add(pend4);

    final buyerAccept = await client.rpc(
      'batata_commerce_accept_pending',
      {'p_request_id': pend4},
      accessToken: buyerToken,
    );
    final buyerReject = await client.rpc(
      'batata_commerce_reject_pending',
      {'p_request_id': pend4},
      accessToken: buyerToken,
    );
    final row4 = (await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$pend4',
      limit: 1,
    )).first;
    add(
      '4.buyer_accept_reject_blocked',
      buyerAccept is Map &&
          buyerAccept['ok'] == false &&
          buyerAccept['error'] == 'seller_only' &&
          buyerReject is Map &&
          buyerReject['ok'] == false &&
          buyerReject['error'] == 'seller_only' &&
          row4['status'] == 'pending',
      'accept=$buyerAccept reject=$buyerReject',
    );

    // ------------------------------------------------------------------
    // 5) service_role can set legitimate actor via p_processed_by
    // ------------------------------------------------------------------
    final s5 = await seedItem('svc');
    createdProductIds.add(s5['productId']!);
    createdLiveIds.add(s5['liveId']!);
    createdItemIds.add(s5['itemId']!);
    final pend5 = await insertPending(
      s: s5,
      seller: sellerId,
      buyer: buyerId,
    );
    createdRequestIds.add(pend5);

    final svcAccept = await client.rpc(
      'batata_commerce_accept_pending',
      {
        'p_request_id': pend5,
        'p_processed_by': sellerId, // backend records seller as actor
      },
    );
    final row5 = (await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$pend5',
      limit: 1,
    )).first;
    add(
      '5.service_role_actor_honoured',
      svcAccept is Map &&
          svcAccept['ok'] == true &&
          svcAccept['outcome'] == 'GUARANTEED' &&
          row5['processed_by_user_id'] == sellerId,
      'rpc=$svcAccept actor=${row5['processed_by_user_id']}',
    );

    // service_role reject with explicit actor
    final s5b = await seedItem('svc2');
    createdProductIds.add(s5b['productId']!);
    createdLiveIds.add(s5b['liveId']!);
    createdItemIds.add(s5b['itemId']!);
    final pend5b = await insertPending(
      s: s5b,
      seller: sellerId,
      buyer: buyerId,
    );
    createdRequestIds.add(pend5b);
    final svcReject = await client.rpc(
      'batata_commerce_reject_pending',
      {
        'p_request_id': pend5b,
        'p_processed_by': sellerId,
        'p_notes': 'backend_reject',
      },
    );
    final row5b = (await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$pend5b',
      limit: 1,
    )).first;
    add(
      '5b.service_role_reject_actor_honoured',
      svcReject is Map &&
          svcReject['ok'] == true &&
          row5b['processed_by_user_id'] == sellerId,
      'rpc=$svcReject actor=${row5b['processed_by_user_id']}',
    );
  } catch (e, st) {
    add('ZZ.unhandled', false, '$e\n$st');
  } finally {
    for (final id in createdRequestIds) {
      try {
        await client.deleteWhere(
          'commerce_reservation_events',
          'request_id=eq.$id',
        );
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
  final outDir = Directory('11-unified-commerce-phase2-actor-hardening');
  await outDir.create(recursive: true);
  final outFile = File(
    '11-unified-commerce-phase2-actor-hardening/test-results-raw.json',
  );
  await outFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  print('\nSUMMARY passed=$passed failed=$failed total=${checks.length}');
  print('Wrote ${outFile.path}');
  if (failed > 0) exit(1);
}
