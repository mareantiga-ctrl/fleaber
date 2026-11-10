// ignore_for_file: avoid_print
/// Phase 6.2 staging validation: last-comment-wins, guaranteed qty, identity, concurrency.
library;

import 'dart:async';
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
  final outDir =
      Directory('15-unified-commerce-phase6.2-final/raw');
  await outDir.create(recursive: true);
  final results = <String, dynamic>{
    'started_at': DateTime.now().toUtc().toIso8601String(),
    'tests': <String, dynamic>{},
  };
  void mark(String id, String status, [Object? detail]) {
    results['tests'][id] = {
      'status': status,
      if (detail != null) 'detail': detail,
    };
    print('$id → $status');
  }

  final sellerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final sellerId = await client.userIdForAccessToken(sellerToken);
  await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final suffix = Random().nextInt(1 << 28).toRadixString(16);
  final ref = 'R62${suffix.substring(0, 3)}'.toUpperCase();

  final product = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'P62 $suffix',
    'price': 10,
    'quantity': 20,
    'ref_code': 'P62-$suffix',
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final live = await client.insert('lives', {
    'title': 'P62_$suffix',
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
  });
  final liveId = live['id']!.toString();
  final item = await client.insert('live_items', {
    'live_id': liveId,
    'ref_code': ref,
    'title': 'Item P62',
    'price': 10,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': product['id'],
    'checkout_product_id': product['id'],
    'quantity': null,
  });
  final liveItemId = item['id']!.toString();

  try {
    await client.patch(
      'seller_reservation_settings',
      'seller_id=eq.$sellerId',
      {
        'policy_mode': 'manual',
        'untrusted_mode': 'approval',
        'normal_ttl_seconds': 2700,
        'trusted_ttl_seconds': 7200,
      },
    );
  } catch (_) {
    await client.insert('seller_reservation_settings', {
      'seller_id': sellerId,
      'policy_mode': 'manual',
      'untrusted_mode': 'approval',
      'normal_ttl_seconds': 2700,
      'trusted_ttl_seconds': 7200,
      'policy_version': 1,
    });
  }

  String? deviceToken;
  try {
    final pair = await client.rpc(
      'batata_ps_create_pairing',
      {'p_live_id': liveId, 'p_device_id_hint': 'p62-$suffix'},
      accessToken: sellerToken,
    );
    final pm = Map<String, dynamic>.from(pair as Map);
    final pairCode = pm['code']?.toString();
    final claim = await client.rpc('batata_ps_claim_pairing', {
      'p_code': pairCode,
      'p_device_id': 'p62-$suffix',
      'p_app_version': 'phase6.2',
      'p_client_ip': '127.0.0.1',
    });
    final cm = Map<String, dynamic>.from(claim as Map);
    deviceToken = cm['device_token']?.toString();
    mark(
      'setup_pairing',
      deviceToken != null && deviceToken!.isNotEmpty ? 'PASS' : 'FAIL',
      {'ok': cm['ok'], 'has_token': deviceToken != null},
    );
  } catch (e) {
    mark('setup_pairing', 'FAIL', e.toString());
  }

  Future<Map<String, dynamic>> ingest({
    required String hash,
    required int qty,
    String intent = 'reserve',
    String? commentId,
    String buyerRef = 'fb:62000000001',
    String display = 'Maria Silva',
    DateTime? detectedAt,
  }) async {
    try {
      final raw = await client.rpc('batata_ingest_ocr_reservation_v2', {
        'p_device_token': deviceToken,
        'p_live_id': liveId,
        'p_external_display_name': display,
        'p_external_buyer_ref': buyerRef,
        'p_ocr_raw_line': 'quero $qty $ref',
        'p_ocr_line_hash': hash,
        'p_detected_at':
            (detectedAt ?? DateTime.now().toUtc()).toIso8601String(),
        'p_ref_slug': ref,
        'p_requested_qty': qty,
        'p_parser_intent': intent,
        'p_ocr_confidence': 0.95,
        'p_parser_confidence': 0.95,
        'p_identity_confidence': 0.9,
        'p_comment_id': commentId,
        'p_event_channel': 'extension',
      });
      return Map<String, dynamic>.from(raw as Map);
    } catch (e) {
      return {'ok': false, 'error': e.toString(), 'action': 'exception'};
    }
  }

  Future<Map<String, dynamic>?> row(String id) async {
    final rows = await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$id',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<int> availQty() async {
    try {
      final a = await client.rpc('batata_live_item_available_qty_engine', {
        'p_live_item_id': liveItemId,
      });
      if (a is num) return a.toInt();
      if (a is String) return int.tryParse(a) ?? -1;
      return -1;
    } catch (_) {
      return -1;
    }
  }

  if (deviceToken == null) {
    mark('ALL', 'FAIL', 'no device token');
  } else {
    // ========== LAST COMMENT WINS (pending) ==========
    final t0 = DateTime.now().toUtc();
    final c1 = await ingest(
      hash: 'p62lc${suffix}01',
      qty: 1,
      commentId: 'cmt-lc-1-$suffix',
      detectedAt: t0,
    );
    final rid = c1['request_id']?.toString();
    mark(
      'lc_pending_create_qty1',
      c1['ok'] == true && rid != null ? 'PASS' : 'FAIL',
      c1,
    );
    final before1 = rid != null ? await row(rid) : null;
    final exp1 = before1?['expires_at'];

    final c3 = await ingest(
      hash: 'p62lc${suffix}02',
      qty: 3,
      commentId: 'cmt-lc-2-$suffix',
      detectedAt: t0.add(const Duration(seconds: 2)),
    );
    final after3 = rid != null ? await row(rid) : null;
    mark(
      'lc_pending_replace_to_3',
      c3['action'] == 'superseded' &&
              after3?['requested_qty'] == 3 &&
              after3?['expires_at'] == exp1
          ? 'PASS'
          : 'FAIL',
      {
        'action': c3['action'],
        'qty': after3?['requested_qty'],
        'exp_before': exp1,
        'exp_after': after3?['expires_at'],
        'ttl_unchanged': c3['ttl_unchanged'],
      },
    );

    final c2 = await ingest(
      hash: 'p62lc${suffix}03',
      qty: 2,
      commentId: 'cmt-lc-3-$suffix',
      detectedAt: t0.add(const Duration(seconds: 4)),
    );
    final after2 = rid != null ? await row(rid) : null;
    mark(
      'lc_pending_replace_to_2',
      c2['action'] == 'superseded' && after2?['requested_qty'] == 2
          ? 'PASS'
          : 'FAIL',
      {'action': c2['action'], 'qty': after2?['requested_qty']},
    );

    final c4 = await ingest(
      hash: 'p62lc${suffix}04',
      qty: 4,
      commentId: 'cmt-lc-4-$suffix',
      detectedAt: t0.add(const Duration(seconds: 6)),
    );
    final after4 = rid != null ? await row(rid) : null;
    mark(
      'lc_pending_replace_to_4_not_sum',
      c4['action'] == 'superseded' &&
              after4?['requested_qty'] == 4 &&
              after4?['expires_at'] == exp1
          ? 'PASS'
          : 'FAIL',
      {
        'action': c4['action'],
        'qty': after4?['requested_qty'],
        'would_be_sum_if_buggy': 1 + 3 + 2 + 4,
        'exp_preserved': after4?['expires_at'] == exp1,
      },
    );

    // Retry same comment
    final c4dup = await ingest(
      hash: 'p62lc${suffix}04',
      qty: 4,
      commentId: 'cmt-lc-4-$suffix',
      detectedAt: t0.add(const Duration(seconds: 6)),
    );
    mark(
      'lc_same_comment_idempotent',
      (c4dup['duplicate'] == true ||
              c4dup['action'] == 'duplicate' ||
              c4dup['action'] == 'duplicate_qty_event' ||
              c4dup['action'] == 'duplicate_inflight') &&
          (await row(rid!))?['requested_qty'] == 4
          ? 'PASS'
          : 'FAIL',
      c4dup,
    );

    // Out-of-order: older detected_at after newer applied
    final ooo = await ingest(
      hash: 'p62lc${suffix}05',
      qty: 9,
      commentId: 'cmt-lc-ooo-$suffix',
      detectedAt: t0.add(const Duration(seconds: 1)), // older than last
    );
    final afterOoo = rid != null ? await row(rid) : null;
    mark(
      'lc_out_of_order_ignored',
      ooo['action'] == 'out_of_order_ignored' &&
              afterOoo?['requested_qty'] == 4
          ? 'PASS'
          : 'FAIL',
      {'action': ooo['action'], 'qty': afterOoo?['requested_qty']},
    );

    // Qty events history
    if (rid != null) {
      final hist = await client.select(
        'commerce_ps_qty_events',
        filter: 'reservation_id=eq.$rid&order=created_at.asc',
        limit: 20,
      );
      mark(
        'lc_qty_event_history',
        hist.length >= 3 ? 'PASS' : 'FAIL',
        {
          'count': hist.length,
          'outcomes': hist.map((h) => h['outcome']).toList(),
          'qty_before': hist.map((h) => h['qty_before']).toList(),
          'qty_after': hist.map((h) => h['qty_after']).toList(),
        },
      );
    }

    // ========== SAME-NAME ISOLATION ==========
    final aCreate = await ingest(
      hash: 'p62nm${suffix}A1',
      qty: 2,
      buyerRef: 'fb:FB_A_$suffix',
      display: 'Maria Silva',
      commentId: 'cmt-A1-$suffix',
    );
    final ridA = aCreate['request_id']?.toString();
    final bCreate = await ingest(
      hash: 'p62nm${suffix}B1',
      qty: 5,
      buyerRef: 'fb:FB_B_$suffix',
      display: 'Maria Silva',
      commentId: 'cmt-B1-$suffix',
    );
    final ridB = bCreate['request_id']?.toString();
    final rowA = ridA != null ? await row(ridA) : null;
    final rowB = ridB != null ? await row(ridB) : null;
    mark(
      'name_collision_separate_rows',
      ridA != null &&
              ridB != null &&
              ridA != ridB &&
              rowA?['requested_qty'] == 2 &&
              rowB?['requested_qty'] == 5
          ? 'PASS'
          : 'FAIL',
      {
        'ridA': ridA,
        'ridB': ridB,
        'qtyA': rowA?['requested_qty'],
        'qtyB': rowB?['requested_qty'],
        'b_action': bCreate['action'],
        'name_collision_isolated': bCreate['name_collision_isolated'],
      },
    );

    final bUp = await ingest(
      hash: 'p62nm${suffix}B2',
      qty: 7,
      buyerRef: 'fb:FB_B_$suffix',
      display: 'Maria Silva',
      commentId: 'cmt-B2-$suffix',
    );
    final rowA2 = ridA != null ? await row(ridA) : null;
    final rowB2 = ridB != null ? await row(ridB) : null;
    mark(
      'name_collision_B_does_not_touch_A',
      rowA2?['requested_qty'] == 2 &&
              rowB2?['requested_qty'] == 7 &&
              bUp['action'] == 'superseded'
          ? 'PASS'
          : 'FAIL',
      {
        'qtyA': rowA2?['requested_qty'],
        'qtyB': rowB2?['requested_qty'],
        'b_action': bUp['action'],
      },
    );

    // ========== GUARANTEED QTY CHANGE ==========
    final gCreate = await ingest(
      hash: 'p62g${suffix}01',
      qty: 3,
      buyerRef: 'fb:62000000099',
      display: 'Guaranteed Buyer',
      commentId: 'cmt-g0-$suffix',
    );
    final gRid = gCreate['request_id']?.toString();
    if (gRid != null) {
      // Force guaranteed + lock stock via engine path approximation:
      // patch to accepted/guaranteed and set reserved units on item if needed.
      final gExp = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 2))
          .toIso8601String();
      await client.patch('live_reservation_requests', 'id=eq.$gRid', {
        'status': 'accepted',
        'request_kind': 'guaranteed',
        'expires_at': gExp,
        'notes': 'p62:forced_guaranteed',
      });
      // Ensure stock accounting sees the hold — recompute
      try {
        await client.rpc('batata_recompute_live_item_status', {
          'p_live_item_id': liveItemId,
        });
      } catch (_) {}

      final gBefore = await row(gRid);
      final availBeforeDec = await availQty();

      // Example A: reduce 3 → 2
      final gDec = await ingest(
        hash: 'p62g${suffix}02',
        qty: 2,
        buyerRef: 'fb:62000000099',
        display: 'Guaranteed Buyer',
        commentId: 'cmt-g-dec-$suffix',
        detectedAt: DateTime.now().toUtc(),
      );
      final gAfterDec = await row(gRid);
      mark(
        'guaranteed_qty_decrease_3_to_2',
        (gDec['action'] == 'qty_decrease_ok' ||
                gDec['action'] == 'superseded') &&
                gAfterDec?['requested_qty'] == 2 &&
                gAfterDec?['expires_at'] == gBefore?['expires_at']
            ? 'PASS'
            : 'FAIL',
        {
          'action': gDec['action'],
          'qty_before': gBefore?['requested_qty'],
          'qty_after': gAfterDec?['requested_qty'],
          'exp_before': gBefore?['expires_at'],
          'exp_after': gAfterDec?['expires_at'],
          'avail_before': availBeforeDec,
          'avail_after': await availQty(),
        },
      );

      // Example C: reduce 2 → 1
      final gDec2 = await ingest(
        hash: 'p62g${suffix}03',
        qty: 1,
        buyerRef: 'fb:62000000099',
        display: 'Guaranteed Buyer',
        commentId: 'cmt-g-dec2-$suffix',
      );
      final gAfterDec2 = await row(gRid);
      mark(
        'guaranteed_qty_decrease_2_to_1',
        gDec2['action'] == 'qty_decrease_ok' &&
                gAfterDec2?['requested_qty'] == 1 &&
                gAfterDec2?['expires_at'] == gBefore?['expires_at']
            ? 'PASS'
            : 'FAIL',
        {
          'action': gDec2['action'],
          'qty': gAfterDec2?['requested_qty'],
        },
      );

      // Example B: increase 1 → 4 (need +3 stock)
      final availBeforeInc = await availQty();
      final gInc = await ingest(
        hash: 'p62g${suffix}04',
        qty: 4,
        buyerRef: 'fb:62000000099',
        display: 'Guaranteed Buyer',
        commentId: 'cmt-g-inc-$suffix',
      );
      final gAfterInc = await row(gRid);
      mark(
        'guaranteed_qty_increase_1_to_4',
        gInc['action'] == 'qty_increase_ok' &&
                gAfterInc?['requested_qty'] == 4 &&
                gAfterInc?['expires_at'] == gBefore?['expires_at']
            ? 'PASS'
            : 'FAIL',
        {
          'action': gInc['action'],
          'qty': gAfterInc?['requested_qty'],
          'avail_before': availBeforeInc,
          'avail_after': await availQty(),
          'stock_added': gInc['stock_added'],
        },
      );

      // Stock denied: drain product then try increase
      await client.patch('products', 'id=eq.${product['id']}', {
        'quantity': 0,
      });
      try {
        await client.rpc('batata_recompute_live_item_status', {
          'p_live_item_id': liveItemId,
        });
      } catch (_) {}
      final gDenied = await ingest(
        hash: 'p62g${suffix}05',
        qty: 10,
        buyerRef: 'fb:62000000099',
        display: 'Guaranteed Buyer',
        commentId: 'cmt-g-deny-$suffix',
      );
      final gAfterDeny = await row(gRid);
      mark(
        'guaranteed_increase_stock_denied_preserves',
        gDenied['action'] == 'qty_increase_stock_denied' &&
                gAfterDeny?['requested_qty'] == 4
            ? 'PASS'
            : 'FAIL',
        {
          'action': gDenied['action'],
          'qty_preserved': gAfterDeny?['requested_qty'],
        },
      );
      // restore stock + sellable status for later tests
      await client.patch('products', 'id=eq.${product['id']}', {
        'quantity': 20,
      });
      await client.patch('live_items', 'id=eq.$liveItemId', {
        'status': 'available',
        'is_active': true,
      });
      try {
        await client.rpc('batata_recompute_live_item_status', {
          'p_live_item_id': liveItemId,
        });
      } catch (_) {}
    } else {
      mark('guaranteed_qty_decrease_3_to_2', 'FAIL', gCreate);
      mark('guaranteed_qty_decrease_2_to_1', 'FAIL', 'no rid');
      mark('guaranteed_qty_increase_1_to_4', 'FAIL', 'no rid');
      mark('guaranteed_increase_stock_denied_preserves', 'FAIL', 'no rid');
    }

    // ========== CHECKOUT STATE SAFETY ==========
    final chk = await ingest(
      hash: 'p62chk${suffix}01',
      qty: 1,
      buyerRef: 'fb:62000000777',
      display: 'Checkout Buyer',
      commentId: 'cmt-chk0-$suffix',
    );
    final chkRid = chk['request_id']?.toString();
    if (chkRid != null) {
      await client.patch('live_reservation_requests', 'id=eq.$chkRid', {
        'status': 'accepted',
        'request_kind': 'guaranteed',
        'buyer_id': (await client.userIdForAccessToken(
          await client.signIn(
            email: envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
            password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
          ),
        )),
      });
      final buyerId = (await row(chkRid))?['buyer_id'];
      // Insert open checkout attempt if table exists
      try {
        await client.insert('commerce_checkout_attempts', {
          'live_id': liveId,
          'buyer_id': buyerId,
          'status': 'open',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        final blocked = await ingest(
          hash: 'p62chk${suffix}02',
          qty: 3,
          buyerRef: 'fb:62000000777',
          display: 'Checkout Buyer',
          commentId: 'cmt-chk1-$suffix',
        );
        final chkAfter = await row(chkRid);
        // Finder should skip → create new OR return no_supersede / blocked
        mark(
          'checkout_open_qty_not_mutated',
          chkAfter?['requested_qty'] == 1 &&
                  blocked['action'] != 'qty_decrease_ok' &&
                  blocked['action'] != 'qty_increase_ok' &&
                  blocked['action'] != 'superseded'
              ? 'PASS'
              : 'FAIL',
          {
            'action': blocked['action'],
            'qty': chkAfter?['requested_qty'],
          },
        );
      } catch (e) {
        // Phase 6.3: never PASS on setup exception (false-positive fix)
        mark(
          'checkout_open_qty_not_mutated',
          'FAIL',
          {
            'note': 'checkout setup threw — see Phase 6.3 for valid attempt fixture',
            'error': e.toString(),
          },
        );
      }
    } else {
      mark('checkout_open_qty_not_mutated', 'FAIL', chk);
    }

    // ========== CONCURRENCY ==========
    // A: two different comments same buyer simultaneous
    final barrierA = Completer<void>();
    final fA = <Future<Map<String, dynamic>>>[];
    for (final entry in [
      {'hash': 'p62ca${suffix}a', 'qty': 2, 'cmt': 'ca-a-$suffix'},
      {'hash': 'p62ca${suffix}b', 'qty': 5, 'cmt': 'ca-b-$suffix'},
    ]) {
      fA.add(() async {
        await barrierA.future;
        return ingest(
          hash: entry['hash'] as String,
          qty: entry['qty'] as int,
          buyerRef: 'fb:62000000888',
          display: 'ConcSame',
          commentId: entry['cmt'] as String,
          detectedAt: DateTime.now().toUtc(),
        );
      }());
    }
    // seed first
    final seedA = await ingest(
      hash: 'p62ca${suffix}0',
      qty: 1,
      buyerRef: 'fb:62000000888',
      display: 'ConcSame',
      commentId: 'ca-0-$suffix',
    );
    final ridConc = seedA['request_id']?.toString();
    barrierA.complete();
    final resA = await Future.wait(fA);
    final afterConc = ridConc != null ? await row(ridConc) : null;
    final qtysOk = afterConc?['requested_qty'] == 2 ||
        afterConc?['requested_qty'] == 5;
    mark(
      'conc_two_comments_same_buyer',
      qtysOk && ridConc != null ? 'PASS' : 'FAIL',
      {
        'final_qty': afterConc?['requested_qty'],
        'results': resA.map((r) => r['action']).toList(),
      },
    );

    // E: retry simultaneous same comment
    final barrierE = Completer<void>();
    final fE = <Future<Map<String, dynamic>>>[];
    for (var i = 0; i < 8; i++) {
      fE.add(() async {
        await barrierE.future;
        return ingest(
          hash: 'p62ce${suffix}xx',
          qty: 3,
          buyerRef: 'fb:62000000999',
          display: 'RetryBuyer',
          commentId: 'ce-$suffix',
        );
      }());
    }
    barrierE.complete();
    final resE = await Future.wait(fE);
    final idsE = resE
        .map((r) => r['request_id']?.toString())
        .whereType<String>()
        .toSet();
    final dupsE = resE
        .where((r) =>
            r['duplicate'] == true ||
            (r['action']?.toString().contains('duplicate') ?? false))
        .length;
    mark(
      'conc_retry_same_comment_x8',
      idsE.length <= 1 && dupsE >= 5 ? 'PASS' : 'FAIL',
      {
        'unique_ids': idsE.length,
        'dups': dupsE,
        'actions': resE.map((r) => r['action']).toList(),
      },
    );

    // C: reduce guaranteed while other buyer grabs freed stock
    final productRace = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P62 race $suffix',
      'price': 5,
      'quantity': 3,
      'ref_code': 'P62R-$suffix',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final refRace = 'X62${suffix.substring(0, 3)}'.toUpperCase();
    final itemRace = await client.insert('live_items', {
      'live_id': liveId,
      'ref_code': refRace,
      'title': 'Race Item',
      'price': 5,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': productRace['id'],
      'checkout_product_id': productRace['id'],
      'quantity': null,
    });
    final liveItemRace = itemRace['id']!.toString();

    Future<Map<String, dynamic>> ingestRace({
      required String hash,
      required int qty,
      required String buyerRef,
      String? commentId,
      String display = 'Race',
    }) async {
      try {
        final raw = await client.rpc('batata_ingest_ocr_reservation_v2', {
          'p_device_token': deviceToken,
          'p_live_id': liveId,
          'p_external_display_name': display,
          'p_external_buyer_ref': buyerRef,
          'p_ocr_raw_line': 'quero $qty $refRace',
          'p_ocr_line_hash': hash,
          'p_detected_at': DateTime.now().toUtc().toIso8601String(),
          'p_ref_slug': refRace,
          'p_requested_qty': qty,
          'p_parser_intent': 'reserve',
          'p_ocr_confidence': 0.95,
          'p_parser_confidence': 0.95,
          'p_identity_confidence': 0.9,
          'p_comment_id': commentId,
          'p_event_channel': 'extension',
        });
        return Map<String, dynamic>.from(raw as Map);
      } catch (e) {
        return {'ok': false, 'error': e.toString(), 'action': 'exception'};
      }
    }

    final gRace = await ingestRace(
      hash: 'p62race${suffix}g0',
      qty: 3,
      buyerRef: 'fb:62000000111',
      commentId: 'race-g0-$suffix',
      display: 'Race G',
    );
    final gRaceRid = gRace['request_id']?.toString();
    if (gRaceRid != null) {
      await client.patch('live_reservation_requests', 'id=eq.$gRaceRid', {
        'status': 'accepted',
        'request_kind': 'guaranteed',
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      });
      // Switch policy to auto so competing create can guarantee
      try {
        await client.patch(
          'seller_reservation_settings',
          'seller_id=eq.$sellerId',
          {'policy_mode': 'auto', 'untrusted_mode': 'auto_guarantee'},
        );
      } catch (_) {}

      final barrierC = Completer<void>();
      final futDec = () async {
        await barrierC.future;
        return ingestRace(
          hash: 'p62race${suffix}g1',
          qty: 1,
          buyerRef: 'fb:62000000111',
          commentId: 'race-g1-$suffix',
          display: 'Race G',
        );
      }();
      final futOther = () async {
        await barrierC.future;
        return ingestRace(
          hash: 'p62race${suffix}o1',
          qty: 2,
          buyerRef: 'fb:62000000222',
          commentId: 'race-o1-$suffix',
          display: 'Race Other',
        );
      }();
      barrierC.complete();
      final decR = await futDec;
      final othR = await futOther;
      final gFinal = await row(gRaceRid);
      final otherRid = othR['request_id']?.toString();
      final otherRow = otherRid != null ? await row(otherRid) : null;
      // No oversell: product qty 3; G holds 1 after reduce; other can take ≤2
      final totalHeld = (gFinal?['requested_qty'] as num? ?? 0).toInt() +
          ((otherRow?['status'] == 'accepted' &&
                  otherRow?['request_kind'] == 'guaranteed')
              ? (otherRow?['requested_qty'] as num? ?? 0).toInt()
              : 0);
      mark(
        'conc_reduce_while_other_grabs',
        gFinal?['requested_qty'] == 1 &&
                (decR['action'] == 'qty_decrease_ok') &&
                totalHeld <= 3
            ? 'PASS'
            : 'FAIL',
        {
          'dec_action': decR['action'],
          'g_qty': gFinal?['requested_qty'],
          'other_action': othR['action'],
          'other_qty': otherRow?['requested_qty'],
          'other_kind': otherRow?['request_kind'],
          'total_held_guaranteed': totalHeld,
          'live_item': liveItemRace,
        },
      );
      // restore policy
      try {
        await client.patch(
          'seller_reservation_settings',
          'seller_id=eq.$sellerId',
          {'policy_mode': 'manual', 'untrusted_mode': 'approval'},
        );
      } catch (_) {}
    } else {
      mark('conc_reduce_while_other_grabs', 'FAIL', gRace);
    }

    // D: increase while other disputes last unit — product qty 1 item
    final productLast = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P62 last $suffix',
      'price': 3,
      'quantity': 2,
      'ref_code': 'P62L-$suffix',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final refLast = 'L62${suffix.substring(0, 3)}'.toUpperCase();
    await client.insert('live_items', {
      'live_id': liveId,
      'ref_code': refLast,
      'title': 'Last Unit',
      'price': 3,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': productLast['id'],
      'checkout_product_id': productLast['id'],
      'quantity': null,
    });

    Future<Map<String, dynamic>> ingestLast({
      required String hash,
      required int qty,
      required String buyerRef,
      String? commentId,
    }) async {
      try {
        final raw = await client.rpc('batata_ingest_ocr_reservation_v2', {
          'p_device_token': deviceToken,
          'p_live_id': liveId,
          'p_external_display_name': 'LastRace',
          'p_external_buyer_ref': buyerRef,
          'p_ocr_raw_line': 'quero $qty $refLast',
          'p_ocr_line_hash': hash,
          'p_detected_at': DateTime.now().toUtc().toIso8601String(),
          'p_ref_slug': refLast,
          'p_requested_qty': qty,
          'p_parser_intent': 'reserve',
          'p_ocr_confidence': 0.95,
          'p_parser_confidence': 0.95,
          'p_identity_confidence': 0.9,
          'p_comment_id': commentId,
          'p_event_channel': 'extension',
        });
        return Map<String, dynamic>.from(raw as Map);
      } catch (e) {
        return {'ok': false, 'error': e.toString(), 'action': 'exception'};
      }
    }

    final gLast = await ingestLast(
      hash: 'p62last${suffix}0',
      qty: 1,
      buyerRef: 'fb:62000000333',
      commentId: 'last-g0-$suffix',
    );
    final gLastRid = gLast['request_id']?.toString();
    if (gLastRid != null) {
      await client.patch('live_reservation_requests', 'id=eq.$gLastRid', {
        'status': 'accepted',
        'request_kind': 'guaranteed',
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      });
      try {
        await client.patch(
          'seller_reservation_settings',
          'seller_id=eq.$sellerId',
          {'policy_mode': 'auto', 'untrusted_mode': 'auto_guarantee'},
        );
      } catch (_) {}
      final barrierD = Completer<void>();
      final futInc = () async {
        await barrierD.future;
        return ingestLast(
          hash: 'p62last${suffix}1',
          qty: 2,
          buyerRef: 'fb:62000000333',
          commentId: 'last-inc-$suffix',
        );
      }();
      final futRival = () async {
        await barrierD.future;
        return ingestLast(
          hash: 'p62last${suffix}2',
          qty: 1,
          buyerRef: 'fb:62000000444',
          commentId: 'last-riv-$suffix',
        );
      }();
      barrierD.complete();
      final incR = await futInc;
      final rivR = await futRival;
      final gLastFinal = await row(gLastRid);
      // Original guarantee never lost below 1
      mark(
        'conc_increase_vs_rival_last_unit',
        (gLastFinal?['requested_qty'] as num? ?? 0) >= 1 &&
                (incR['action'] == 'qty_increase_ok' ||
                    incR['action'] == 'qty_increase_stock_denied')
            ? 'PASS'
            : 'FAIL',
        {
          'inc_action': incR['action'],
          'g_qty': gLastFinal?['requested_qty'],
          'rival_action': rivR['action'],
          'rival_rid': rivR['request_id'],
        },
      );
      try {
        await client.patch(
          'seller_reservation_settings',
          'seller_id=eq.$sellerId',
          {'policy_mode': 'manual', 'untrusted_mode': 'approval'},
        );
      } catch (_) {}
    } else {
      mark('conc_increase_vs_rival_last_unit', 'FAIL', gLast);
    }

    // Identity insufficient without fb ref
    final noRef = await client.rpc('batata_commerce_ps_try_supersede_qty', {
      'p_live_id': liveId,
      'p_live_item_id': liveItemId,
      'p_external_buyer_ref': null,
      'p_external_display_name': 'Maria Silva',
      'p_qty': 2,
      'p_idempotency_key': 'ocr:noref${suffix}xxxxxxxxxx',
      'p_ocr_raw_line': 'quero 2 $ref',
      'p_detected_at': DateTime.now().toUtc().toIso8601String(),
    });
    final noRefM = Map<String, dynamic>.from(noRef as Map);
    mark(
      'identity_no_ref_no_supersede',
      noRefM['action'] == 'no_supersede_target' ||
              noRefM['action'] == 'identity_insufficient_no_supersede'
          ? 'PASS'
          : 'FAIL',
      noRefM,
    );

    // same_buyer helper unit
    final same = await client.rpc('batata_commerce_ps_same_buyer', {
      'p_row_ref': 'fb:A',
      'p_row_name': 'Maria',
      'p_event_ref': 'fb:B',
      'p_event_name': 'Maria',
    });
    mark(
      'same_buyer_ref_neq_false',
      same == false ? 'PASS' : 'FAIL',
      same,
    );
    final same2 = await client.rpc('batata_commerce_ps_same_buyer', {
      'p_row_ref': 'fb:A',
      'p_row_name': 'Maria',
      'p_event_ref': 'fb:A',
      'p_event_name': 'Other',
    });
    mark(
      'same_buyer_ref_eq_true',
      same2 == true ? 'PASS' : 'FAIL',
      same2,
    );
  }

  // End live
  await client.patch('lives', 'id=eq.$liveId', {
    'status': 'ended',
    'is_active': false,
    'ended_at': DateTime.now().toUtc().toIso8601String(),
  });

  results['ended_at'] = DateTime.now().toUtc().toIso8601String();
  final pass = (results['tests'] as Map)
      .values
      .where((v) => (v as Map)['status'] == 'PASS')
      .length;
  final fail = (results['tests'] as Map)
      .values
      .where((v) => (v as Map)['status'] == 'FAIL')
      .length;
  results['summary'] = {'pass': pass, 'fail': fail};
  final outFile = File('${outDir.path}/phase6_2_results.json');
  await outFile.writeAsString(const JsonEncoder.withIndent('  ').convert(results));
  print('SUMMARY pass=$pass fail=$fail → ${outFile.path}');
  if (fail > 0) exitCode = 1;
}
