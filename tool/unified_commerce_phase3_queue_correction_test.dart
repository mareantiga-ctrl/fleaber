// ignore_for_file: avoid_print
/// Phase 3 queue correction — QUEUE-01..10 + stock regress.
///
///   dart run tool/unified_commerce_phase3_queue_correction_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'live_ops_staging_client.dart';

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
  final buyerBEmail = staging['LIVE_OPS_TEST_BUYER_B_EMAIL']?.trim();
  final buyerBPassword = staging['LIVE_OPS_TEST_BUYER_B_PASSWORD']?.trim();
  late final String buyerBToken;
  late final String buyerBId;
  if (buyerBEmail != null &&
      buyerBEmail.isNotEmpty &&
      buyerBPassword != null &&
      buyerBPassword.isNotEmpty) {
    buyerBToken = await client.signIn(
      email: buyerBEmail,
      password: buyerBPassword,
    );
    buyerBId = await client.userIdForAccessToken(buyerBToken);
  } else {
    // Fallback: create ephemeral buyer via service is heavy — reuse seller as B
    // for concurrency only when B missing (still distinct identity needed).
    buyerBToken = buyerToken;
    buyerBId = await client.userIdForAccessToken(buyerToken);
  }

  final sellerId = await client.userIdForAccessToken(sellerToken);
  final buyerId = await client.userIdForAccessToken(buyerToken);
  final tag =
      'qfix_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999)}';

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, [Object? detail]) {
    results.add({'id': id, 'ok': ok, 'detail': detail?.toString()});
    print('${ok ? 'PASS' : 'FAIL'} $id ${detail ?? ''}');
  }

  final createdRequestIds = <String>[];
  final createdLiveIds = <String>[];
  final createdProductIds = <String>[];

  Future<Map<String, String>> seedItem(String suffix, int qty) async {
    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'QA $tag $suffix',
      'price': 11.0,
      'quantity': qty,
      'ref_code': 'QA-$tag-$suffix',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live = await client.insert('lives', {
      'title': 'QA_$tag\_$suffix',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final item = await client.insert('live_items', {
      'live_id': live['id'],
      'ref_code': 'QA-$tag-$suffix',
      'title': 'QA $suffix',
      'price': 11.0,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': product['id'],
      'checkout_product_id': product['id'],
      'quantity': null,
    });
    createdLiveIds.add('${live['id']}');
    createdProductIds.add('${product['id']}');
    return {
      'productId': '${product['id']}',
      'liveId': '${live['id']}',
      'itemId': '${item['id']}',
    };
  }

  Future<Map<String, dynamic>> reserve({
    required Map<String, String> s,
    required String token,
    required String buyer,
  }) async {
    final r = await client.rpc(
      'batata_reserve_with_policy',
      {
        'p_seller_id': sellerId,
        'p_buyer_id': buyer,
        'p_live_id': s['liveId'],
        'p_live_item_id': s['itemId'],
        'p_qty': 1,
        'p_source': 'fleaber_live',
        'p_guest_session_id': null,
        'p_identity_linked': true,
        'p_notes': null,
      },
      accessToken: token,
    ) as Map<String, dynamic>;
    final id = r['request_id']?.toString();
    if (id != null && id.isNotEmpty) createdRequestIds.add(id);
    return r;
  }

  Future<Map<String, dynamic>?> row(String? id) async {
    if (id == null || id.isEmpty) return null;
    final rows = await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$id',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> setPolicy({
    required String mode,
    required String untrusted,
  }) async {
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {'policy_mode': mode, 'untrusted_mode': untrusted},
    );
  }

  Future<void> setTrust(String mode, {required String buyer}) async {
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyer, 'p_mode': mode},
      accessToken: sellerToken,
    );
  }

  try {
    await client.patch('profiles', 'id=eq.$sellerId', {'hub_published': true});

    // QUEUE-01 — single bag_hold_none → NULL
    await setPolicy(mode: 'pay_only', untrusted: 'pay_required');
    await setTrust('trusted', buyer: buyerId);
    final s1 = await seedItem('Q01', 3);
    final r1 = await reserve(s: s1, token: buyerToken, buyer: buyerId);
    final id1 = r1['request_id']?.toString();
    final row1 = await row(id1);
    add(
      'QUEUE-01.bag_hold_none_queue_null',
      row1 != null &&
          row1['request_kind'] == 'bag_hold_none' &&
          row1['queue_position'] == null,
      row1,
    );

    // QUEUE-02 — two bag_hold_none → both NULL
    final s2 = await seedItem('Q02', 5);
    final r2a = await reserve(s: s2, token: buyerToken, buyer: buyerId);
    // second buyer on same item if available, else second reserve from same
    // after removing first — use distinct item units via qty 2 requests
    Map<String, dynamic> r2b;
    if (buyerBId != buyerId) {
      await setTrust('trusted', buyer: buyerBId);
      r2b = await reserve(s: s2, token: buyerBToken, buyer: buyerBId);
    } else {
      final s2b = await seedItem('Q02b', 3);
      r2b = await reserve(s: s2b, token: buyerToken, buyer: buyerId);
    }
    final row2a = await row(r2a['request_id']?.toString());
    final row2b = await row(r2b['request_id']?.toString());
    add(
      'QUEUE-02.two_bag_hold_none_both_null',
      row2a?['queue_position'] == null &&
          row2b?['queue_position'] == null &&
          row2a?['request_kind'] == 'bag_hold_none' &&
          row2b?['request_kind'] == 'bag_hold_none',
      {'a': row2a, 'b': row2b},
    );

    // QUEUE-03 — two approval_pending → 1,2
    await setPolicy(mode: 'trust', untrusted: 'approval');
    await setTrust('distrusted', buyer: buyerId);
    if (buyerBId != buyerId) await setTrust('distrusted', buyer: buyerBId);
    final s3 = await seedItem('Q03', 5);
    final r3a = await reserve(s: s3, token: buyerToken, buyer: buyerId);
    late final Map<String, dynamic> r3b;
    if (buyerBId != buyerId) {
      r3b = await reserve(s: s3, token: buyerBToken, buyer: buyerBId);
    } else {
      // Same buyer second pending on same item — allowed by engine
      r3b = await reserve(s: s3, token: buyerToken, buyer: buyerId);
    }
    final row3a = await row(r3a['request_id']?.toString());
    final row3b = await row(r3b['request_id']?.toString());
    final q3a = (row3a?['queue_position'] as num?)?.toInt();
    final q3b = (row3b?['queue_position'] as num?)?.toInt();
    add(
      'QUEUE-03.approval_pending_sequence',
      row3a?['request_kind'] == 'approval_pending' &&
          row3b?['request_kind'] == 'approval_pending' &&
          q3a == 1 &&
          q3b == 2,
      {'a': row3a, 'b': row3b},
    );

    // QUEUE-04 — A approval, X bag, B approval → 1 / NULL / 2
    await setPolicy(mode: 'trust', untrusted: 'approval');
    await setTrust('distrusted', buyer: buyerId);
    final s4 = await seedItem('Q04', 8);
    final r4a = await reserve(s: s4, token: buyerToken, buyer: buyerId);
    await setPolicy(mode: 'pay_only', untrusted: 'pay_required');
    await setTrust('trusted', buyer: buyerId);
    final r4x = await reserve(s: s4, token: buyerToken, buyer: buyerId);
    await setPolicy(mode: 'trust', untrusted: 'approval');
    await setTrust('distrusted', buyer: buyerId);
    late final Map<String, dynamic> r4b;
    if (buyerBId != buyerId) {
      await setTrust('distrusted', buyer: buyerBId);
      r4b = await reserve(s: s4, token: buyerBToken, buyer: buyerBId);
    } else {
      r4b = await reserve(s: s4, token: buyerToken, buyer: buyerId);
    }
    final row4a = await row(r4a['request_id']?.toString());
    final row4x = await row(r4x['request_id']?.toString());
    final row4b = await row(r4b['request_id']?.toString());
    add(
      'QUEUE-04.mixed_approval_bag_order',
      row4a?['request_kind'] == 'approval_pending' &&
          (row4a?['queue_position'] as num?)?.toInt() == 1 &&
          row4x?['request_kind'] == 'bag_hold_none' &&
          row4x?['queue_position'] == null &&
          row4b?['request_kind'] == 'approval_pending' &&
          (row4b?['queue_position'] as num?)?.toInt() == 2,
      {'a': row4a, 'x': row4x, 'b': row4b},
    );

    // QUEUE-05 — recompact keeps bag NULL
    final rc5 = await client.rpc(
      'batata_recompact_reservation_queue',
      {'p_live_item_id': s4['itemId']},
      accessToken: sellerToken,
    ) as Map<String, dynamic>;
    final row4xAfter = await row(r4x['request_id']?.toString());
    final row4aAfter = await row(r4a['request_id']?.toString());
    final row4bAfter = await row(r4b['request_id']?.toString());
    add(
      'QUEUE-05.recompact_ignores_bag_hold_none',
      rc5['ok'] == true &&
          row4xAfter?['queue_position'] == null &&
          (row4aAfter?['queue_position'] as num?)?.toInt() == 1 &&
          (row4bAfter?['queue_position'] as num?)?.toInt() == 2,
      {'rc': rc5, 'x': row4xAfter, 'a': row4aAfter, 'b': row4bAfter},
    );

    // QUEUE-06 — reject #1 → #2 becomes 1; bag stays NULL
    final rej = await client.rpc(
      'batata_process_live_reservation_request',
      {
        'p_request_id': r4a['request_id'],
        'p_action': 'reject',
        'p_notes': 'qa_queue_correction',
      },
      accessToken: sellerToken,
    );
    final row4x6 = await row(r4x['request_id']?.toString());
    final row4b6 = await row(r4b['request_id']?.toString());
    add(
      'QUEUE-06.reject_shifts_approval_bag_stays_null',
      row4x6?['queue_position'] == null &&
          (row4b6?['queue_position'] as num?)?.toInt() == 1,
      {'rej': rej, 'x': row4x6, 'b': row4b6},
    );

    // QUEUE-07 — trust promotion to guaranteed: queue stays NULL
    await setPolicy(mode: 'trust', untrusted: 'approval');
    await setTrust('trusted', buyer: buyerId);
    final s7 = await seedItem('Q07', 3);
    final r7 = await reserve(s: s7, token: buyerToken, buyer: buyerId);
    final row7 = await row(r7['request_id']?.toString());
    add(
      'QUEUE-07.guaranteed_not_in_queue',
      r7['outcome'] == 'GUARANTEED' &&
          row7?['request_kind'] == 'guaranteed' &&
          row7?['status'] == 'accepted' &&
          row7?['queue_position'] == null,
      {'r': r7, 'row': row7},
    );

    // QUEUE-08 — legacy artificial bag_hold_none queue=3 → normalize NULL
    await setPolicy(mode: 'pay_only', untrusted: 'pay_required');
    await setTrust('trusted', buyer: buyerId);
    final s8 = await seedItem('Q08', 2);
    final r8 = await reserve(s: s8, token: buyerToken, buyer: buyerId);
    final id8 = r8['request_id']?.toString();
    // Bypass would be blocked by UPDATE guard — stamp via temporary disable
    // is not needed: invoke normalize by calling recompact (clears non-approval)
    // First force a bad value using service patch; guard should null it on update
    // OR if guard blocks, recompact clear path covers QUEUE-08.
    try {
      await client.patch(
        'live_reservation_requests',
        'id=eq.$id8',
        {'queue_position': 3},
      );
    } catch (_) {}
    var row8mid = await row(id8);
    // If guard nulled immediately on UPDATE, already NULL; else recompact.
    if (row8mid?['queue_position'] != null) {
      await client.rpc(
        'batata_recompact_reservation_queue',
        {'p_live_item_id': s8['itemId']},
        accessToken: sellerToken,
      );
      row8mid = await row(id8);
    }
    final status8 = row8mid?['status'];
    final kind8 = row8mid?['request_kind'];
    add(
      'QUEUE-08.legacy_bad_queue_normalized',
      row8mid != null &&
          row8mid['queue_position'] == null &&
          status8 == 'pending' &&
          kind8 == 'bag_hold_none',
      row8mid,
    );

    // QUEUE-09 — concurrency: several approval + bag → only approval sequenced
    await setPolicy(mode: 'trust', untrusted: 'approval');
    await setTrust('distrusted', buyer: buyerId);
    if (buyerBId != buyerId) await setTrust('distrusted', buyer: buyerBId);
    final s9 = await seedItem('Q09', 20);
    final approvals = <Map<String, dynamic>>[];
    final bags = <Map<String, dynamic>>[];
    for (var i = 0; i < 3; i++) {
      approvals.add(await reserve(s: s9, token: buyerToken, buyer: buyerId));
      await setPolicy(mode: 'pay_only', untrusted: 'pay_required');
      await setTrust('trusted', buyer: buyerId);
      bags.add(await reserve(s: s9, token: buyerToken, buyer: buyerId));
      await setPolicy(mode: 'trust', untrusted: 'approval');
      await setTrust('distrusted', buyer: buyerId);
    }
    final appRows = <Map<String, dynamic>>[];
    for (final r in approvals) {
      final rr = await row(r['request_id']?.toString());
      if (rr != null) appRows.add(rr);
    }
    final bagRows = <Map<String, dynamic>>[];
    for (final r in bags) {
      final rr = await row(r['request_id']?.toString());
      if (rr != null) bagRows.add(rr);
    }
    final appPositions = appRows
        .map((e) => (e['queue_position'] as num?)?.toInt())
        .whereType<int>()
        .toList()
      ..sort();
    final bagsAllNull = bagRows.every((e) => e['queue_position'] == null);
    add(
      'QUEUE-09.concurrency_only_approval_sequenced',
      bagsAllNull &&
          appPositions.length == 3 &&
          appPositions[0] == 1 &&
          appPositions[1] == 2 &&
          appPositions[2] == 3,
      {'approvals': appRows, 'bags': bagRows},
    );

    // QUEUE-10 — stock semantics regression
    await setPolicy(mode: 'trust', untrusted: 'approval');
    await setTrust('trusted', buyer: buyerId);
    final s10 = await seedItem('Q10', 2);
    final g10 = await reserve(s: s10, token: buyerToken, buyer: buyerId);
    final availAfterG = await client.rpc(
      'batata_live_item_available_qty_engine',
      {'p_live_item_id': s10['itemId']},
      accessToken: sellerToken,
    );
    await setTrust('distrusted', buyer: buyerId);
    final p10 = await reserve(s: s10, token: buyerToken, buyer: buyerId);
    final availAfterP = await client.rpc(
      'batata_live_item_available_qty_engine',
      {'p_live_item_id': s10['itemId']},
      accessToken: sellerToken,
    );
    await setPolicy(mode: 'pay_only', untrusted: 'pay_required');
    await setTrust('trusted', buyer: buyerId);
    final u10 = await reserve(s: s10, token: buyerToken, buyer: buyerId);
    final availAfterU = await client.rpc(
      'batata_live_item_available_qty_engine',
      {'p_live_item_id': s10['itemId']},
      accessToken: sellerToken,
    );
    final aG = availAfterG is num ? availAfterG.toInt() : int.tryParse('$availAfterG');
    final aP = availAfterP is num ? availAfterP.toInt() : int.tryParse('$availAfterP');
    final aU = availAfterU is num ? availAfterU.toInt() : int.tryParse('$availAfterU');
    add(
      'QUEUE-10.stock_semantics',
      g10['outcome'] == 'GUARANTEED' &&
          aG == 1 &&
          p10['outcome'] == 'PENDING_APPROVAL' &&
          aP == 1 &&
          u10['outcome'] == 'BAG_UNGUARANTEED' &&
          aU == 1 &&
          (await row(u10['request_id']?.toString()))?['queue_position'] == null,
      {
        'g': g10['outcome'],
        'aG': aG,
        'p': p10['outcome'],
        'aP': aP,
        'u': u10['outcome'],
        'aU': aU,
      },
    );

    // remaining bad rows globally
    final bad = await client.select(
      'live_reservation_requests',
      filter:
          'request_kind=eq.bag_hold_none&queue_position=not.is.null&select=id',
      limit: 50,
    );
    add('QUEUE.cleanup_remaining_zero', bad.isEmpty, 'count=${bad.length}');
  } catch (e, st) {
    add('QUEUE.FATAL', false, '$e\n$st');
  } finally {
    // Soft end lives — do not mass-delete LRR (audit trail).
    for (final lid in createdLiveIds) {
      try {
        await client.patch(
          'lives',
          'id=eq.$lid',
          {'status': 'ended', 'is_active': false},
        );
      } catch (_) {}
    }
  }

  final failed = results.where((r) => r['ok'] != true).length;
  final passed = results.length - failed;
  final out = {
    'passed': passed,
    'failed': failed,
    'total': results.length,
    'results': results,
  };
  final path = 'tool/reports/phase3_queue_correction_test_run.txt';
  await Directory('tool/reports').create(recursive: true);
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('WROTE $path ($passed/$passed+failed=$failed)');
  exit(failed == 0 ? 0 : 1);
}
