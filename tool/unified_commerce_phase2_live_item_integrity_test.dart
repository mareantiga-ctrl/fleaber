// ignore_for_file: avoid_print
/// Phase 2 — canonical live_item → live → seller integrity on batata_reserve_with_policy.
///
///   dart run tool/unified_commerce_phase2_live_item_integrity_test.dart
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
  final sellerBId = buyerId;

  final checks = <_Check>[];
  void add(String id, bool ok, [String detail = '']) {
    checks.add((id: id, ok: ok, detail: detail));
    print('${ok ? 'PASS' : 'FAIL'} $id ${detail.isEmpty ? '' : '— $detail'}');
  }

  final tag =
      'p2li_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  Future<void> upsertPolicy(String seller) async {
    final existing = await client.select(
      'seller_reservation_settings',
      filter: 'seller_id=eq.$seller',
      limit: 1,
    );
    if (existing.isEmpty) {
      await client.insert('seller_reservation_settings', {
        'seller_id': seller,
        'policy_mode': 'trust',
        'untrusted_mode': 'approval',
        'normal_ttl_seconds': 1800,
        'trusted_ttl_seconds': 3600,
        'accept_fleaber_global_trust': true,
      });
    } else {
      await client.patch(
        'seller_reservation_settings',
        'seller_id=eq.$seller',
        {
          'policy_mode': 'trust',
          'untrusted_mode': 'approval',
        },
      );
    }
  }

  Future<Map<String, String>> seedBundle({
    required String suffix,
    required String ownerSellerId,
    int qty = 2,
  }) async {
    final product = await client.insert('products', {
      'seller_id': ownerSellerId,
      'title': 'P2LI $tag-$suffix',
      'price': 5,
      'quantity': qty,
      'ref_code': 'P2LI-$tag-$suffix',
      'list_on_marketplace': false,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live = await client.insert('lives', {
      'title': 'P2LI_${tag}_$suffix',
      'status': 'live',
      'seller_id': ownerSellerId,
      'vendedor_id': ownerSellerId,
      'is_active': true,
    });
    final item = await client.insert('live_items', {
      'live_id': live['id'],
      'ref_code': 'P2LI-$tag-$suffix',
      'title': 'P2LI $suffix',
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
      'sellerId': ownerSellerId,
    };
  }

  Future<Map<String, dynamic>> reserve({
    required String? liveId,
    required String itemId,
    required String seller,
    String? accessToken,
  }) async {
    final params = <String, dynamic>{
      'p_seller_id': seller,
      'p_buyer_id': buyerId,
      'p_live_id': liveId,
      'p_live_item_id': itemId,
      'p_qty': 1,
      'p_source': 'fleaber_live',
      'p_guest_session_id': null,
      'p_identity_linked': true,
      'p_notes': null,
    };
    return await client.rpc(
      'batata_reserve_with_policy',
      params,
      accessToken: accessToken ?? buyerToken,
    ) as Map<String, dynamic>;
  }

  bool rpcErr(dynamic r, String code) =>
      r is Map && r['ok'] == false && r['error'] == code;

  await client.patch('profiles', 'id=eq.$sellerId', {'hub_published': true});
  await upsertPolicy(sellerId);
  await upsertPolicy(sellerBId);
  await client.rpc(
    'batata_seller_buyer_trust_set',
    {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'trusted'},
    accessToken: sellerToken,
  );

  final createdRequestIds = <String>[];
  final createdItemIds = <String>[];
  final createdLiveIds = <String>[];
  final createdProductIds = <String>[];

  try {
    final bundleA = await seedBundle(suffix: 'A', ownerSellerId: sellerId);
    final bundleB = await seedBundle(suffix: 'B', ownerSellerId: sellerBId);
    for (final b in [bundleA, bundleB]) {
      createdProductIds.add(b['productId']!);
      createdLiveIds.add(b['liveId']!);
      createdItemIds.add(b['itemId']!);
    }

    // A — live A + item A + seller A
    final rA = await reserve(
      liveId: bundleA['liveId'],
      itemId: bundleA['itemId']!,
      seller: sellerId,
    );
    final reqA = rA['request_id']?.toString();
    if (reqA != null) createdRequestIds.add(reqA);
    Map<String, dynamic>? rowA;
    if (reqA != null) {
      rowA = (await client.select(
        'live_reservation_requests',
        filter: 'id=eq.$reqA',
        limit: 1,
      )).firstOrNull;
    }
    add(
      'A.valid_live_item_seller',
      rA['ok'] == true &&
          rA['outcome'] != null &&
          rA['outcome'] != 'UNAVAILABLE' &&
          rowA != null &&
          rowA['live_id'] == bundleA['liveId'] &&
          rowA['seller_id'] == sellerId,
      'rpc=$rA live_id=${rowA?['live_id']} seller=${rowA?['seller_id']}',
    );

    // B — live A + item B (live B) + seller A → mismatch
    final rB = await reserve(
      liveId: bundleA['liveId'],
      itemId: bundleB['itemId']!,
      seller: sellerId,
    );
    add(
      'B.spoof_live_id_wrong_item',
      rpcErr(rB, 'live_item_live_mismatch'),
      jsonEncode(rB),
    );

    // C — live A seller A + item live B (seller B)
    final rC = await reserve(
      liveId: bundleA['liveId'],
      itemId: bundleB['itemId']!,
      seller: sellerId,
    );
    add(
      'C.cross_live_item_with_live_a',
      rpcErr(rC, 'live_item_live_mismatch'),
      jsonEncode(rC),
    );

    // D — seller A for item belonging to seller B (null live_id → seller_mismatch)
    final rD = await reserve(
      liveId: null,
      itemId: bundleB['itemId']!,
      seller: sellerId,
    );
    add(
      'D.spoof_seller_for_other_item',
      rpcErr(rD, 'seller_mismatch'),
      jsonEncode(rD),
    );

    // E — p_live_id NULL + valid item → canonical live on row
    final bundleE = await seedBundle(suffix: 'E', ownerSellerId: sellerId);
    createdProductIds.add(bundleE['productId']!);
    createdLiveIds.add(bundleE['liveId']!);
    createdItemIds.add(bundleE['itemId']!);
    final rE = await reserve(
      liveId: null,
      itemId: bundleE['itemId']!,
      seller: sellerId,
    );
    final reqE = rE['request_id']?.toString();
    if (reqE != null) createdRequestIds.add(reqE);
    final rowE = reqE == null
        ? null
        : (await client.select(
            'live_reservation_requests',
            filter: 'id=eq.$reqE',
            limit: 1,
          )).firstOrNull;
    add(
      'E.null_live_id_derives_canonical',
      rE['ok'] == true &&
          rowE != null &&
          rowE['live_id'] == bundleE['liveId'] &&
          rowE['seller_id'] == sellerId,
      'rpc live omitted row_live=${rowE?['live_id']} expected=${bundleE['liveId']}',
    );

    // F — spoof p_live_id must not persist wrong live_id (regression of insert path)
    final bundleF = await seedBundle(suffix: 'F', ownerSellerId: sellerId);
    createdProductIds.add(bundleF['productId']!);
    createdLiveIds.add(bundleF['liveId']!);
    createdItemIds.add(bundleF['itemId']!);
    final rF = await reserve(
      liveId: bundleB['liveId'],
      itemId: bundleF['itemId']!,
      seller: sellerId,
    );
    add(
      'F.live_id_spoof_blocked_no_row',
      rpcErr(rF, 'live_item_live_mismatch') &&
          (rF['request_id'] == null || rF['request_id'].toString().isEmpty),
      jsonEncode(rF),
    );
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

  final failed = checks.where((c) => !c.ok).length;
  print('');
  print('SUMMARY: ${checks.length - failed}/${checks.length} PASS');
  if (failed > 0) {
    exit(1);
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
