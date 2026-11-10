// ignore_for_file: avoid_print
/// Phase 2 — prove backfill of pending+guaranteed → accepted is UNSAFE,
/// and that corrective neutralization is safe for the chain.
///
///   dart run tool/unified_commerce_phase2_backfill_safety_test.dart
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

  final checks = <_Check>[];
  void add(String id, bool ok, [String detail = '']) {
    checks.add((id: id, ok: ok, detail: detail));
    print('${ok ? 'PASS' : 'FAIL'} $id ${detail.isEmpty ? '' : '— $detail'}');
  }

  final tag =
      'p2bf_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  Future<void> upsertTrust(String mode) async {
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': mode},
      accessToken: sellerToken,
    );
  }

  Future<Map<String, String>> seed(String suffix, {int qty = 2}) async {
    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P2BF $tag-$suffix',
      'price': 5,
      'quantity': qty,
      'ref_code': 'P2BF-$tag-$suffix',
      'list_on_marketplace': false,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live = await client.insert('lives', {
      'title': 'P2BF_${tag}_$suffix',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final item = await client.insert('live_items', {
      'live_id': live['id'],
      'ref_code': 'P2BF-$tag-$suffix',
      'title': 'P2BF $suffix',
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

  Future<int> avail(String itemId) async {
    final stock = await client.rpc('batata_live_item_stock', {
      'p_live_item_id': itemId,
    });
    if (stock is Map && stock['ok'] == true) {
      return int.tryParse('${stock['available_qty']}') ?? -1;
    }
    // Fallback engine (service)
    final eng = await client.rpc('batata_live_item_available_qty_engine', {
      'p_live_item_id': itemId,
    });
    if (eng is int) return eng;
    if (eng is num) return eng.toInt();
    return -1;
  }

  Future<Map<String, dynamic>?> row(String id) async {
    final rows = await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$id',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Exact WHERE shape from 20261005150600 §4 (service insert — no engine).
  Future<String> insertHybridMatchingWhere({
    required Map<String, String> s,
    required DateTime expiresAt,
    String? notes,
  }) async {
    final inserted = await client.insert('live_reservation_requests', {
      'live_id': s['liveId'],
      'live_item_id': s['itemId'],
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'requested_qty': 1,
      'source': 'fleaber_live',
      'status': 'pending',
      'request_kind': 'guaranteed',
      'ttl_seconds_snapshot': 3600,
      'policy_mode_snapshot': 'trust',
      'trust_decision_snapshot': 'SELLER_TRUST',
      'expires_at': expiresAt.toUtc().toIso8601String(),
      if (notes != null) 'notes': notes,
    });
    return inserted['id']!.toString();
  }

  /// Reproduce unsafe §4 UPDATE for one id (same predicates).
  Future<void> applyUnsafeRepair(String id) async {
    final r = await row(id);
    if (r == null) return;
    if (r['status'] != 'pending') return;
    if (r['request_kind'] != 'guaranteed') return;
    if (r['ttl_seconds_snapshot'] == null) return;
    if (r['expires_at'] == null) return;
    await client.patch('live_reservation_requests', 'id=eq.$id', {
      'status': 'accepted',
      'notes':
          '${(r['notes'] ?? '').toString()} | repaired_guaranteed_status'.trim(),
    });
  }

  /// Reproduce corrective neutralization for repaired accepted rows.
  Future<void> applyCorrectiveNeutralize(String id) async {
    final r = await row(id);
    if (r == null) return;
    final notes = (r['notes'] ?? '').toString();
    if (!notes.contains('repaired_guaranteed_status')) return;
    if (notes.contains('backfill_repaired_guaranteed_status_reverted')) return;
    if (r['status'] != 'accepted') return;
    await client.patch('live_reservation_requests', 'id=eq.$id', {
      'status': 'expired',
      'expiry_reason': 'backfill_safety_neutralized',
      'notes': '$notes | backfill_repaired_guaranteed_status_reverted',
    });
  }

  await client.patch('profiles', 'id=eq.$sellerId', {'hub_published': true});
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
  }

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
    // 1) New trusted guarantee — must be accepted + block stock (engine)
    // ------------------------------------------------------------------
    await upsertTrust('trusted');
    final s1 = await seed('new', qty: 2);
    track(s1);
    final before1 = await avail(s1['itemId']!);
    final r1 = await client.rpc(
      'batata_reserve_with_policy',
      {
        'p_seller_id': sellerId,
        'p_buyer_id': buyerId,
        'p_live_id': s1['liveId'],
        'p_live_item_id': s1['itemId'],
        'p_qty': 1,
        'p_source': 'fleaber_live',
        'p_guest_session_id': null,
        'p_identity_linked': true,
        'p_notes': null,
      },
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final id1 = r1['request_id']?.toString();
    if (id1 != null) createdRequestIds.add(id1);
    final row1 = id1 == null ? null : await row(id1);
    final after1 = int.tryParse('${r1['available_qty_after']}') ?? await avail(s1['itemId']!);
    add(
      '1.new_guaranteed_accepted_blocks',
      r1['ok'] == true &&
          r1['outcome'] == 'GUARANTEED' &&
          row1?['status'] == 'accepted' &&
          row1?['request_kind'] == 'guaranteed' &&
          !(row1?['notes']?.toString().contains('repaired_guaranteed_status') ??
              false) &&
          after1 == before1 - 1,
      'status=${row1?['status']} avail $before1→$after1',
    );

    // ------------------------------------------------------------------
    // 2) approval_pending does not block
    // ------------------------------------------------------------------
    await upsertTrust('distrusted');
    final s2 = await seed('pend', qty: 1);
    track(s2);
    final r2 = await client.rpc(
      'batata_reserve_with_policy',
      {
        'p_seller_id': sellerId,
        'p_buyer_id': buyerId,
        'p_live_id': s2['liveId'],
        'p_live_item_id': s2['itemId'],
        'p_qty': 1,
        'p_source': 'fleaber_live',
        'p_guest_session_id': null,
        'p_identity_linked': true,
        'p_notes': null,
      },
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final id2 = r2['request_id']?.toString();
    if (id2 != null) createdRequestIds.add(id2);
    final row2 = id2 == null ? null : await row(id2);
    final after2 = int.tryParse('${r2['available_qty_after']}') ?? -1;
    add(
      '2.approval_pending_no_block',
      r2['outcome'] == 'PENDING_APPROVAL' &&
          row2?['status'] == 'pending' &&
          row2?['request_kind'] == 'approval_pending' &&
          after2 == 1,
      'status=${row2?['status']} avail=$after2',
    );

    // ------------------------------------------------------------------
    // 3) Provenance: non-engine writer can match WHERE exactly
    // ------------------------------------------------------------------
    final s3 = await seed('forge', qty: 2);
    track(s3);
    final forgeId = await insertHybridMatchingWhere(
      s: s3,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      notes: 'non_engine_where_match',
    );
    createdRequestIds.add(forgeId);
    final forgeRow = await row(forgeId);
    add(
      '3.non_engine_writer_matches_repair_where',
      forgeRow?['status'] == 'pending' &&
          forgeRow?['request_kind'] == 'guaranteed' &&
          forgeRow?['ttl_seconds_snapshot'] != null &&
          forgeRow?['expires_at'] != null,
      'id=$forgeId row=$forgeRow',
    );
    // Neutralize provenance fixture (same as corrective §B) so it cannot linger
    // as an active hybrid / be promoted by a re-run of the unsafe UPDATE.
    await client.patch('live_reservation_requests', 'id=eq.$forgeId', {
      'status': 'expired',
      'expiry_reason': 'hybrid_guaranteed_pending_neutralized',
      'notes':
          '${forgeRow?['notes'] ?? ''} | hybrid_guaranteed_pending_neutralized',
    });

    // ------------------------------------------------------------------
    // 4) Past expires_at + unsafe repair → stock block + trust failure path
    // ------------------------------------------------------------------
    final s4 = await seed('past', qty: 2);
    track(s4);
    final pastId = await insertHybridMatchingWhere(
      s: s4,
      expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
    );
    createdRequestIds.add(pastId);
    final availBeforeRepair = await client.rpc(
      'batata_live_item_available_qty_engine',
      {'p_live_item_id': s4['itemId']},
    );
    final beforeN = availBeforeRepair is num
        ? availBeforeRepair.toInt()
        : int.tryParse('$availBeforeRepair') ?? -1;
    await applyUnsafeRepair(pastId);
    final repairedPast = await row(pastId);
    final availAfterRepair = await client.rpc(
      'batata_live_item_available_qty_engine',
      {'p_live_item_id': s4['itemId']},
    );
    final afterN = availAfterRepair is num
        ? availAfterRepair.toInt()
        : int.tryParse('$availAfterRepair') ?? -1;
    add(
      '4a.repair_past_expiry_retroactively_blocks_stock',
      repairedPast?['status'] == 'accepted' &&
          (repairedPast?['notes']?.toString().contains('repaired_guaranteed_status') ??
              false) &&
          afterN == beforeN - 1,
      'before=$beforeN after=$afterN status=${repairedPast?['status']}',
    );

    // Count trust failures for this request before expiry cron
    final failsBefore = await client.select(
      'buyer_trust_events',
      filter: 'source_id=eq.$pastId&kind=eq.failure',
      limit: 5,
    );
    final exp = await client.rpc('batata_expire_guaranteed_reservations', {
      'p_now': DateTime.now().toUtc().toIso8601String(),
      'p_request_id': pastId,
    }) as Map<String, dynamic>;
    final failsAfter = await client.select(
      'buyer_trust_events',
      filter: 'source_id=eq.$pastId&kind=eq.failure',
      limit: 5,
    );
    final pastAfterExp = await row(pastId);
    add(
      '4b.repair_past_expiry_can_create_trust_failure',
      exp['ok'] == true &&
          (failsAfter.length > failsBefore.length ||
              (exp['failures_recorded'] is num &&
                  (exp['failures_recorded'] as num) > 0) ||
              pastAfterExp?['status'] == 'expired'),
      'exp=$exp fails ${failsBefore.length}→${failsAfter.length} status=${pastAfterExp?['status']}',
    );
    add(
      '4c.trust_failure_not_historically_justified',
      failsAfter.length > failsBefore.length ||
          (exp['failures_recorded'] is num &&
              (exp['failures_recorded'] as num) > 0),
      'A hold that never existed as accepted can still record buyer-responsible failure after repair — NOT PROVEN legitimate.',
    );

    // ------------------------------------------------------------------
    // 5) Future expires_at + repair → blocks stock; no immediate trust fail
    // ------------------------------------------------------------------
    final s5 = await seed('future', qty: 2);
    track(s5);
    final futId = await insertHybridMatchingWhere(
      s: s5,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
    );
    createdRequestIds.add(futId);
    final b5 = await client.rpc('batata_live_item_available_qty_engine', {
      'p_live_item_id': s5['itemId'],
    });
    final b5n = b5 is num ? b5.toInt() : -1;
    await applyUnsafeRepair(futId);
    final a5 = await client.rpc('batata_live_item_available_qty_engine', {
      'p_live_item_id': s5['itemId'],
    });
    final a5n = a5 is num ? a5.toInt() : -1;
    final futRow = await row(futId);
    final expFut = await client.rpc('batata_expire_guaranteed_reservations', {
      'p_now': DateTime.now().toUtc().toIso8601String(),
      'p_request_id': futId,
    }) as Map<String, dynamic>;
    final futAfter = await row(futId);
    add(
      '5.repair_future_blocks_stock_no_immediate_expire',
      futRow?['status'] == 'accepted' &&
          a5n == b5n - 1 &&
          futAfter?['status'] == 'accepted' &&
          (expFut['expired'] == 0 || expFut['expired'] == null),
      'avail $b5n→$a5n exp=$expFut status=${futAfter?['status']}',
    );

    // ------------------------------------------------------------------
    // 6) Corrective neutralize → no stock block; no further trust from hold
    // ------------------------------------------------------------------
    await applyCorrectiveNeutralize(futId);
    final neut = await row(futId);
    final a5neut = await client.rpc('batata_live_item_available_qty_engine', {
      'p_live_item_id': s5['itemId'],
    });
    final a5nn = a5neut is num ? a5neut.toInt() : -1;
    add(
      '6.corrective_neutralize_releases_stock',
      neut?['status'] == 'expired' &&
          (neut?['notes']?.toString().contains(
                'backfill_repaired_guaranteed_status_reverted',
              ) ??
              false) &&
          a5nn == b5n,
      'status=${neut?['status']} avail=$a5nn expected=$b5n',
    );

    // Pending hybrid (never repaired) must be expired by DB corrective migration
    // Simulate section B of 150700:
    final s6 = await seed('hyb', qty: 1);
    track(s6);
    final hybId = await insertHybridMatchingWhere(
      s: s6,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
    );
    createdRequestIds.add(hybId);
    await client.patch('live_reservation_requests', 'id=eq.$hybId', {
      'status': 'expired',
      'expiry_reason': 'hybrid_guaranteed_pending_neutralized',
      'notes': 'hybrid_guaranteed_pending_neutralized',
    });
    final hyb = await row(hybId);
    final hybAvail = await client.rpc('batata_live_item_available_qty_engine', {
      'p_live_item_id': s6['itemId'],
    });
    final hybN = hybAvail is num ? hybAvail.toInt() : -1;
    add(
      '6b.remaining_hybrid_neutralized_not_promoted',
      hyb?['status'] == 'expired' && hybN == 1,
      'status=${hyb?['status']} avail=$hybN',
    );

    // ------------------------------------------------------------------
    // 7) C20 strengthened: distinguish correct vs promotional hiding
    // ------------------------------------------------------------------
    final hybridsActive = await client.select(
      'live_reservation_requests',
      filter:
          'request_kind=eq.guaranteed&status=eq.pending&ttl_seconds_snapshot=not.is.null',
      limit: 20,
    );
    final repairedStillAccepted = await client.select(
      'live_reservation_requests',
      filter:
          'status=eq.accepted&request_kind=eq.guaranteed&notes=ilike.*repaired_guaranteed_status*',
      limit: 50,
    );
    // Filter out rows that already have revert marker (PostgREST ilike is coarse)
    final unsafePromotions = repairedStillAccepted.where((r) {
      final n = (r['notes'] ?? '').toString();
      return n.contains('repaired_guaranteed_status') &&
          !n.contains('backfill_repaired_guaranteed_status_reverted');
    }).toList();
    add(
      '7.c20_no_active_hybrid_and_no_unreverted_repair_accepted',
      hybridsActive.isEmpty && unsafePromotions.isEmpty,
      'hybrids=${hybridsActive.length} unreverted_accepted=${unsafePromotions.length}',
    );

    // Engine new guarantee must not rely on repair note
    add(
      '7b.new_guarantee_not_via_backfill_note',
      row1 != null &&
          !(row1['notes']?.toString().contains('repaired_guaranteed_status') ??
              false) &&
          row1['status'] == 'accepted',
      'notes=${row1?['notes']}',
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
      } catch (_) {}
      try {
        await client.deleteWhere(
          'buyer_trust_events',
          'source_id=eq.$id',
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
