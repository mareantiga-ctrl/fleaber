// ignore_for_file: avoid_print
/// Phase 2 — canonical legacy-compatibility matrix + GUARANTEED persists as accepted.
///
///   dart run tool/unified_commerce_phase2_legacy_compat_matrix_test.dart
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
      'p2lc_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  Future<void> upsertPolicy({
    required String seller,
    String mode = 'trust',
    String untrusted = 'approval',
  }) async {
    final existing = await client.select(
      'seller_reservation_settings',
      filter: 'seller_id=eq.$seller',
      limit: 1,
    );
    final body = {
      'policy_mode': mode,
      'untrusted_mode': untrusted,
      'normal_ttl_seconds': 1800,
      'trusted_ttl_seconds': 3600,
      'accept_fleaber_global_trust': true,
    };
    if (existing.isEmpty) {
      await client.insert('seller_reservation_settings', {
        'seller_id': seller,
        ...body,
      });
    } else {
      await client.patch(
        'seller_reservation_settings',
        'seller_id=eq.$seller',
        body,
      );
    }
  }

  Future<Map<String, String>> seed({
    required String suffix,
    required String owner,
    int qty = 2,
  }) async {
    final product = await client.insert('products', {
      'seller_id': owner,
      'title': 'P2LC $tag-$suffix',
      'price': 5,
      'quantity': qty,
      'ref_code': 'P2LC-$tag-$suffix',
      'list_on_marketplace': false,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live = await client.insert('lives', {
      'title': 'P2LC_${tag}_$suffix',
      'status': 'live',
      'seller_id': owner,
      'vendedor_id': owner,
      'is_active': true,
    });
    final item = await client.insert('live_items', {
      'live_id': live['id'],
      'ref_code': 'P2LC-$tag-$suffix',
      'title': 'P2LC $suffix',
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

  Future<Map<String, dynamic>> reserve({
    required Map<String, String> s,
    required String seller,
    int qty = 1,
    String? accessToken,
  }) async {
    return await client.rpc(
      'batata_reserve_with_policy',
      {
        'p_seller_id': seller,
        'p_buyer_id': buyerId,
        'p_live_id': s['liveId'],
        'p_live_item_id': s['itemId'],
        'p_qty': qty,
        'p_source': 'fleaber_live',
        'p_guest_session_id': null,
        'p_identity_linked': true,
        'p_notes': null,
      },
      accessToken: accessToken ?? buyerToken,
    ) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> row(String? id) async {
    if (id == null) return null;
    final rows = await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$id',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> available(String itemId) async {
    final stock = await client.rpc('batata_live_item_stock', {
      'p_live_item_id': itemId,
    });
    if (stock is Map) {
      return int.tryParse('${stock['available_qty']}') ?? -1;
    }
    return -1;
  }

  await client.patch('profiles', 'id=eq.$sellerId', {'hub_published': true});
  await upsertPolicy(seller: sellerId);
  await upsertPolicy(seller: sellerBId);

  final createdRequestIds = <String>[];
  final createdItemIds = <String>[];
  final createdLiveIds = <String>[];
  final createdProductIds = <String>[];

  void track(Map<String, String> s) {
    createdProductIds.add(s['productId']!);
    createdLiveIds.add(s['liveId']!);
    createdItemIds.add(s['itemId']!);
  }

  try {
    // ------------------------------------------------------------------
    // C1 — stock=2 trusted guarantee qty=1 → accepted + available=1
    // ------------------------------------------------------------------
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'trusted'},
      accessToken: sellerToken,
    );
    final s1 = await seed(suffix: 'C1', owner: sellerId, qty: 2);
    track(s1);
    final r1 = await reserve(s: s1, seller: sellerId);
    final id1 = r1['request_id']?.toString();
    if (id1 != null) createdRequestIds.add(id1);
    final row1 = await row(id1);
    final avail1 = await available(s1['itemId']!);
    add(
      'C1.guaranteed_persists_accepted_blocks_stock',
      r1['ok'] == true &&
          r1['outcome'] == 'GUARANTEED' &&
          row1?['status'] == 'accepted' &&
          row1?['request_kind'] == 'guaranteed' &&
          avail1 == 1,
      'rpc_status=${r1['status']} db_status=${row1?['status']} kind=${row1?['request_kind']} avail=$avail1',
    );

    // ------------------------------------------------------------------
    // C2 — stock=1 approval pending → pending + available=1
    // ------------------------------------------------------------------
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
      accessToken: sellerToken,
    );
    await upsertPolicy(seller: sellerId, mode: 'trust', untrusted: 'approval');
    final s2 = await seed(suffix: 'C2', owner: sellerId, qty: 1);
    track(s2);
    final r2 = await reserve(s: s2, seller: sellerId);
    final id2 = r2['request_id']?.toString();
    if (id2 != null) createdRequestIds.add(id2);
    final row2 = await row(id2);
    final avail2 = await available(s2['itemId']!);
    add(
      'C2.approval_pending_no_stock_block',
      r2['ok'] == true &&
          r2['outcome'] == 'PENDING_APPROVAL' &&
          row2?['status'] == 'pending' &&
          row2?['request_kind'] == 'approval_pending' &&
          avail2 == 1,
      'status=${row2?['status']} kind=${row2?['request_kind']} avail=$avail2',
    );

    // ------------------------------------------------------------------
    // C3 — stock=1 pending A + guaranteed B (re-trust buyer on new item)
    // Use two buyers: pending from buyer (distrusted), then promote trust
    // and second reserve... Actually same buyer: first pending on item,
    // then seller trusts and second call on SAME item with stock 1 while
    // pending exists — decide may still create pending. Better: seed stock=1,
    // leave pending from C2, trust buyer, try reserve on same item → should
    // get GUARANTEED and close pending OR unavailable depending on close.
    // Spec: pending A, guaranteed B → B accepted, available=0, A no priority.
    // ------------------------------------------------------------------
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'trusted'},
      accessToken: sellerToken,
    );
    final s3 = await seed(suffix: 'C3', owner: sellerId, qty: 1);
    track(s3);
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
      accessToken: sellerToken,
    );
    final pend3 = await reserve(s: s3, seller: sellerId);
    final pend3Id = pend3['request_id']?.toString();
    if (pend3Id != null) createdRequestIds.add(pend3Id);
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'trusted'},
      accessToken: sellerToken,
    );
    // Same buyer already has pending — second reserve as trusted may supersede
    // or create guaranteed. Engine path: decide GUARANTEED then insert.
    final guar3 = await reserve(s: s3, seller: sellerId);
    final guar3Id = guar3['request_id']?.toString();
    if (guar3Id != null) createdRequestIds.add(guar3Id);
    final rowG3 = await row(guar3Id);
    final rowP3 = await row(pend3Id);
    final avail3 = await available(s3['itemId']!);
    add(
      'C3.guaranteed_over_pending_blocks_stock',
      guar3['ok'] == true &&
          guar3['outcome'] == 'GUARANTEED' &&
          rowG3?['status'] == 'accepted' &&
          rowG3?['request_kind'] == 'guaranteed' &&
          avail3 == 0 &&
          (rowP3 == null ||
              rowP3['status'] != 'accepted' ||
              rowP3['id'] == rowG3?['id']),
      'guar=${guar3['outcome']} g_status=${rowG3?['status']} p_status=${rowP3?['status']} avail=$avail3',
    );

    // ------------------------------------------------------------------
    // C4 — stock=0 → UNAVAILABLE
    // ------------------------------------------------------------------
    final s4 = await seed(suffix: 'C4', owner: sellerId, qty: 0);
    track(s4);
    await client.patch('products', 'id=eq.${s4['productId']}', {'quantity': 0});
    final r4 = await reserve(s: s4, seller: sellerId);
    final pendingAfter4 = await client.select(
      'live_reservation_requests',
      filter: 'live_item_id=eq.${s4['itemId']}&status=eq.pending',
      limit: 5,
    );
    add(
      'C4.zero_stock_unavailable_no_pending',
      r4['ok'] == true &&
          r4['outcome'] == 'UNAVAILABLE' &&
          r4['request_id'] == null &&
          pendingAfter4.isEmpty,
      jsonEncode(r4),
    );

    // ------------------------------------------------------------------
    // C5 — stock=0 pay_only / bag → UNAVAILABLE
    // ------------------------------------------------------------------
    await upsertPolicy(
      seller: sellerId,
      mode: 'pay_only',
      untrusted: 'pay_required',
    );
    final s5 = await seed(suffix: 'C5', owner: sellerId, qty: 0);
    track(s5);
    await client.patch('products', 'id=eq.${s5['productId']}', {'quantity': 0});
    final r5 = await reserve(s: s5, seller: sellerId);
    final bags5 = await client.select(
      'live_reservation_requests',
      filter: 'live_item_id=eq.${s5['itemId']}&request_kind=eq.bag_hold_none',
      limit: 5,
    );
    add(
      'C5.zero_stock_pay_only_no_bag',
      r5['ok'] == true &&
          r5['outcome'] == 'UNAVAILABLE' &&
          bags5.isEmpty,
      jsonEncode(r5),
    );
    await upsertPolicy(seller: sellerId, mode: 'trust', untrusted: 'approval');

    // ------------------------------------------------------------------
    // C6 — seller accepts pending with stock → accepted/guaranteed
    // ------------------------------------------------------------------
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
      accessToken: sellerToken,
    );
    final s6 = await seed(suffix: 'C6', owner: sellerId, qty: 1);
    track(s6);
    final pend6 = await reserve(s: s6, seller: sellerId);
    final pend6Id = pend6['request_id']?.toString();
    if (pend6Id != null) createdRequestIds.add(pend6Id);
    final accept6 = await client.rpc(
      'batata_commerce_accept_pending',
      {'p_request_id': pend6Id},
      accessToken: sellerToken,
    ) as Map<String, dynamic>;
    final row6 = await row(pend6Id);
    final avail6Rpc = int.tryParse('${accept6['available_qty_after']}') ?? -1;
    add(
      'C6.accept_pending_to_guaranteed',
      accept6['ok'] == true &&
          row6?['status'] == 'accepted' &&
          row6?['request_kind'] == 'guaranteed' &&
          avail6Rpc == 0,
      'accept=$accept6 status=${row6?['status']} avail_after=$avail6Rpc',
    );

    // ------------------------------------------------------------------
    // C7 — accept pending without stock → not accepted
    // ------------------------------------------------------------------
    final s7 = await seed(suffix: 'C7', owner: sellerId, qty: 1);
    track(s7);
    final pend7 = await reserve(s: s7, seller: sellerId);
    final pend7Id = pend7['request_id']?.toString();
    if (pend7Id != null) createdRequestIds.add(pend7Id);
    // Consume stock with trusted guarantee from same buyer after trust flip
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'trusted'},
      accessToken: sellerToken,
    );
    // Close stock via product qty 0 + recompute path: accept should fail
    await client.patch('products', 'id=eq.${s7['productId']}', {'quantity': 0});
    final accept7 = await client.rpc(
      'batata_commerce_accept_pending',
      {'p_request_id': pend7Id},
      accessToken: sellerToken,
    ) as Map<String, dynamic>;
    final row7 = await row(pend7Id);
    add(
      'C7.accept_without_stock_blocked',
      accept7['ok'] == false ||
          row7?['status'] != 'accepted',
      'accept=$accept7 status=${row7?['status']}',
    );

    // ------------------------------------------------------------------
    // C15 / C16 — live/item and seller spoof
    // ------------------------------------------------------------------
    final a = await seed(suffix: 'A', owner: sellerId, qty: 2);
    final b = await seed(suffix: 'B', owner: sellerBId, qty: 2);
    track(a);
    track(b);
    final spoofLive = await client.rpc(
      'batata_reserve_with_policy',
      {
        'p_seller_id': sellerId,
        'p_buyer_id': buyerId,
        'p_live_id': a['liveId'],
        'p_live_item_id': b['itemId'],
        'p_qty': 1,
        'p_source': 'fleaber_live',
        'p_guest_session_id': null,
        'p_identity_linked': true,
        'p_notes': null,
      },
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'C15.live_item_live_mismatch',
      spoofLive['ok'] == false && spoofLive['error'] == 'live_item_live_mismatch',
      jsonEncode(spoofLive),
    );
    final spoofSeller = await client.rpc(
      'batata_reserve_with_policy',
      {
        'p_seller_id': sellerId,
        'p_buyer_id': buyerId,
        'p_live_id': null,
        'p_live_item_id': b['itemId'],
        'p_qty': 1,
        'p_source': 'fleaber_live',
        'p_guest_session_id': null,
        'p_identity_linked': true,
        'p_notes': null,
      },
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    add(
      'C16.seller_mismatch',
      spoofSeller['ok'] == false && spoofSeller['error'] == 'seller_mismatch',
      jsonEncode(spoofSeller),
    );

    // ------------------------------------------------------------------
    // C17 — buyer cannot forge accepted via direct insert (no GUC)
    // ------------------------------------------------------------------
    final s17 = await seed(suffix: 'C17', owner: sellerId, qty: 2);
    track(s17);
    Map<String, dynamic>? forged;
    try {
      forged = await client.insertAsUser(
        'live_reservation_requests',
        {
          'live_id': s17['liveId'],
          'live_item_id': s17['itemId'],
          'seller_id': sellerId,
          'buyer_id': buyerId,
          'requested_qty': 1,
          'source': 'fleaber_live',
          'status': 'accepted',
          'request_kind': 'guaranteed',
        },
        accessToken: buyerToken,
      );
    } catch (e) {
      forged = {'error': e.toString()};
    }
    final forgedStatus = forged?['status']?.toString();
    add(
      'C17.direct_insert_cannot_forge_accepted',
      forgedStatus == 'pending' &&
          (forged?['request_kind'] == null ||
              forged?['request_kind'] == 'approval_pending' ||
              forged?['error'] != null),
      'status=$forgedStatus kind=${forged?['request_kind']} raw=$forged',
    );
    if (forged?['id'] != null) {
      createdRequestIds.add(forged!['id'].toString());
    }

    // ------------------------------------------------------------------
    // C19 — extend once then reject second
    // ------------------------------------------------------------------
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'trusted'},
      accessToken: sellerToken,
    );
    final s19 = await seed(suffix: 'C19', owner: sellerId, qty: 1);
    track(s19);
    final r19 = await reserve(s: s19, seller: sellerId);
    final id19 = r19['request_id']?.toString();
    if (id19 != null) createdRequestIds.add(id19);
    final ext1 = await client.rpc(
      'batata_commerce_extend_guaranteed_once',
      {'p_request_id': id19, 'p_ttl_seconds': 1800},
      accessToken: sellerToken,
    ) as Map<String, dynamic>;
    final ext2 = await client.rpc(
      'batata_commerce_extend_guaranteed_once',
      {'p_request_id': id19, 'p_ttl_seconds': 1800},
      accessToken: sellerToken,
    ) as Map<String, dynamic>;
    add(
      'C19.extend_once_then_reject',
      ext1['ok'] == true &&
          (ext2['ok'] == false || ext2['error'] == 'already_extended'),
      'ext1=$ext1 ext2=$ext2',
    );

    // ------------------------------------------------------------------
    // C20 — no active hybrid guaranteed+pending (lifecycle)
    // ------------------------------------------------------------------
    final hybridsActive = await client.select(
      'live_reservation_requests',
      filter:
          'request_kind=eq.guaranteed&status=eq.pending&ttl_seconds_snapshot=not.is.null&expires_at=not.is.null',
      limit: 20,
    );
    final repairedCandidates = await client.select(
      'live_reservation_requests',
      filter: 'status=eq.accepted&request_kind=eq.guaranteed&notes=ilike.*repaired_guaranteed_status*',
      limit: 50,
    );
    // Distinguish: hybrid gone because engine writes accepted correctly
    // vs hybrid hidden by unreverted promotional repair.
    final unrevertedRepairAccepted = repairedCandidates.where((r) {
      final n = (r['notes'] ?? '').toString();
      return n.contains('repaired_guaranteed_status') &&
          !n.contains('backfill_repaired_guaranteed_status_reverted');
    }).toList();
    add(
      'C20.hybrid_absent_and_not_hidden_by_unsafe_promotion',
      hybridsActive.isEmpty && unrevertedRepairAccepted.isEmpty,
      'active_hybrids=${hybridsActive.length} unreverted_repair_accepted=${unrevertedRepairAccepted.length}',
    );

    // ------------------------------------------------------------------
    // C18 — policy snapshot preserved after policy change
    // ------------------------------------------------------------------
    final s18 = await seed(suffix: 'C18', owner: sellerId, qty: 1);
    track(s18);
    final r18 = await reserve(s: s18, seller: sellerId);
    final id18 = r18['request_id']?.toString();
    if (id18 != null) createdRequestIds.add(id18);
    final before18 = await row(id18);
    await upsertPolicy(
      seller: sellerId,
      mode: 'pay_only',
      untrusted: 'pay_required',
    );
    final after18 = await row(id18);
    add(
      'C18.policy_snapshot_immutable',
      before18?['policy_mode_snapshot'] == after18?['policy_mode_snapshot'] &&
          before18?['ttl_seconds_snapshot'] == after18?['ttl_seconds_snapshot'],
      'before=${before18?['policy_mode_snapshot']} after=${after18?['policy_mode_snapshot']}',
    );
    await upsertPolicy(seller: sellerId, mode: 'trust', untrusted: 'approval');

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

  final failed = checks.where((c) => !c.ok).length;
  print('');
  print('SUMMARY: ${checks.length - failed}/${checks.length} PASS');
  stdout.writeln(jsonEncode({
    'passed': checks.where((c) => c.ok).map((c) => c.id).toList(),
    'failed': checks.where((c) => !c.ok).map((c) => {'id': c.id, 'detail': c.detail}).toList(),
  }));
  if (failed > 0) exit(1);
}
