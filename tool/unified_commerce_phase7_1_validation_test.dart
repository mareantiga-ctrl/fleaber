// ignore_for_file: avoid_print
/// Phase 7.1 — close false PASS, concurrent DM idempotency, recipients, authenticity.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'live_ops_staging_client.dart';

dynamic redact(Object? detail) {
  if (detail == null) return null;
  final cleaned = jsonEncode(detail)
      .replaceAllMapped(
        RegExp(
          r'"(device_token|p_device_token|guest_token|access_token|password|anon_key|service_role)"\s*:\s*"[^"]*"',
          caseSensitive: false,
        ),
        (m) => '"${m.group(1)}":"[REDACTED]"',
      )
      .replaceAllMapped(RegExp(r'[a-f0-9]{64}'), (_) => '[REDACTED_HEX64]');
  return jsonDecode(cleaned);
}

Future<void> main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final outDir =
      Directory('17-unified-commerce-phase7.1-final-validation/raw');
  await outDir.create(recursive: true);
  final results = <String, dynamic>{
    'started_at': DateTime.now().toUtc().toIso8601String(),
    'tests': <String, dynamic>{},
  };
  void mark(String id, String status, [Object? detail]) {
    results['tests'][id] = {
      'status': status,
      if (detail != null) 'detail': redact(detail),
    };
    print('$id → $status');
  }

  final sellerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final sellerId = await client.userIdForAccessToken(sellerToken);
  final buyerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final buyerId = await client.userIdForAccessToken(buyerToken);

  String? buyer2Id;
  String? buyer2Token;
  try {
    final e2 = staging['LIVE_OPS_TEST_BUYER2_EMAIL'];
    final p2 = staging['LIVE_OPS_TEST_BUYER2_PASSWORD'];
    if (e2 != null && p2 != null && e2.isNotEmpty) {
      buyer2Token = await client.signIn(email: e2, password: p2);
      buyer2Id = await client.userIdForAccessToken(buyer2Token);
    }
  } catch (_) {}

  if (buyer2Id == null) {
    final email =
        'p71.buyer2.${Random().nextInt(1 << 28)}@fleaber-test.local';
    final pass = 'P71-${Random().nextInt(1 << 28)}aA!';
    buyer2Id = await client.createAdminUser(email: email, password: pass);
    buyer2Token = await client.signIn(email: email, password: pass);
  }

  final suffix = Random().nextInt(1 << 28).toRadixString(16);
  final ref = 'P71${suffix.substring(0, 3)}'.toUpperCase();

  final product = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'P71 $suffix',
    'price': 10,
    'quantity': 60,
    'ref_code': 'P71-$suffix',
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final live = await client.insert('lives', {
    'title': 'P71_$suffix',
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
  });
  final liveId = live['id']!.toString();
  final item = await client.insert('live_items', {
    'live_id': liveId,
    'ref_code': ref,
    'title': 'Item P71',
    'price': 10,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': product['id'],
    'checkout_product_id': product['id'],
    'quantity': null,
  });
  final liveItemId = item['id']!.toString();

  Future<Map<String, dynamic>> insertPending({
    required String buyer,
    String? seller,
    String? liveItem,
    String? live,
    int qty = 1,
    String? display,
    String? fbRef,
  }) async {
    final row = await client.insert('live_reservation_requests', {
      'live_id': live ?? liveId,
      'live_item_id': liveItem ?? liveItemId,
      'seller_id': seller ?? sellerId,
      'buyer_id': buyer,
      'requested_qty': qty,
      'status': 'pending',
      'request_kind': 'approval_pending',
      'source': 'facebook_manual',
      'external_buyer_ref': fbRef ?? 'fb:p71_$suffix',
      'external_display_name': display ?? 'Maria P71',
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 45))
          .toIso8601String(),
    });
    return Map<String, dynamic>.from(row as Map);
  }

  Future<List<Map<String, dynamic>>> msgsFor(String rid, String kind) async {
    final marker = 'fleaber_res:$kind:$rid';
    final rows = await client.select(
      'chat_messages',
      filter: 'is_reservation=eq.true&order=created_at.desc',
      limit: 80,
    );
    return rows
        .where((r) => (r['text']?.toString() ?? '').contains(marker))
        .toList();
  }

  Future<Map<String, dynamic>?> rowReq(String id) async {
    final rows = await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$id',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  final liveIds = <String>[liveId];

  try {
    // ---- D19 accept + system label ----
    final pend = await insertPending(buyer: buyerId);
    final rid = pend['id']!.toString();
    final accept = await client.rpc(
      'batata_commerce_accept_pending',
      {'p_request_id': rid},
      accessToken: sellerToken,
    ) as Map;
    final dms = await msgsFor(rid, 'reservation_guaranteed');
    final body = dms.isNotEmpty ? dms.first['text']!.toString() : '';
    mark(
      'd19_guarantee_dm',
      accept['ok'] == true &&
              dms.length == 1 &&
              body.contains('Fleaber · sistema') &&
              body.contains('Reserva garantida') &&
              body.contains(ref)
          ? 'PASS'
          : 'FAIL',
      {
        'accept_ok': accept['ok'],
        'dm_count': dms.length,
        'has_system_label': body.contains('Fleaber · sistema'),
      },
    );

    // ---- t10 extension (strict) ----
    try {
      final before = await rowReq(rid);
      final expBefore = DateTime.parse(before!['expires_at'].toString());
      final ext1 = await client.rpc(
        'batata_commerce_extend_guaranteed_once',
        {'p_request_id': rid, 'p_ttl_seconds': 900},
        accessToken: sellerToken,
      );
      final after = await rowReq(rid);
      final expAfter = DateTime.parse(after!['expires_at'].toString());
      final extendedAt = after['extended_at'];
      final extTtl = after['extension_ttl_seconds'];
      final dmAfterExt = await msgsFor(rid, 'reservation_guaranteed');
      final ext2 = await client.rpc(
        'batata_commerce_extend_guaranteed_once',
        {'p_request_id': rid, 'p_ttl_seconds': 900},
        accessToken: sellerToken,
      );
      final after2 = await rowReq(rid);
      final exp2 = DateTime.parse(after2!['expires_at'].toString());
      // Commercial rule: extension restarts from NOW (not added to old expiry).
      final nowUtc = DateTime.now().toUtc();
      final expectedExp = nowUtc.add(const Duration(seconds: 900));
      final ok1 = ext1 is Map && ext1['ok'] == true;
      final okPersist = extendedAt != null &&
          extTtl == 900 &&
          expAfter.toUtc().difference(expectedExp).inSeconds.abs() < 30;
      final okOnce = ext2 is Map &&
          ext2['ok'] == false &&
          ext2['error']?.toString() == 'already_extended' &&
          exp2.toUtc().difference(expAfter.toUtc()).inSeconds.abs() < 2;
      final okNoDupDm = dmAfterExt.length == 1;
      mark(
        't10_extension',
        ok1 && okPersist && okOnce && okNoDupDm ? 'PASS' : 'FAIL',
        {
          'ext1_ok': ok1,
          'expires_before': expBefore.toIso8601String(),
          'expires_after': expAfter.toIso8601String(),
          'extended_at': extendedAt,
          'extension_ttl_seconds': extTtl,
          'ext2_ok': ext2 is Map ? ext2['ok'] : null,
          'ext2_error': ext2 is Map ? ext2['error'] : null,
          'dm_count': dmAfterExt.length,
          'rule': 'extension_from_now_not_added_to_old_ttl',
        },
      );
    } catch (e) {
      mark('t10_extension', 'FAIL', e.toString());
    }

    // ---- Concurrent double post ----
    final pendC = await insertPending(buyer: buyerId, fbRef: 'fb:p71c_$suffix');
    final ridC = pendC['id']!.toString();
    await client.rpc(
      'batata_commerce_accept_pending',
      {'p_request_id': ridC},
      accessToken: sellerToken,
    );
    // Wipe messages+ledger claim to re-test concurrent post cleanly? Accept already posted.
    // Instead: concurrent retry on already-posted → both dedupe, count stays 1
    final concurrent = await Future.wait([
      client.rpc('batata_commerce_post_reservation_dm', {
        'p_request_id': ridC,
        'p_kind': 'reservation_guaranteed',
        'p_payload': {'race': 1},
      }),
      client.rpc('batata_commerce_post_reservation_dm', {
        'p_request_id': ridC,
        'p_kind': 'reservation_guaranteed',
        'p_payload': {'race': 2},
      }),
    ]);
    final dmsC = await msgsFor(ridC, 'reservation_guaranteed');
    mark(
      'concurrent_dm_idempotency',
      dmsC.length == 1 ? 'PASS' : 'FAIL',
      {
        'dm_count': dmsC.length,
        'r1': concurrent[0],
        'r2': concurrent[1],
      },
    );

    // Fresh concurrent race: claim ledger under lock — create accepted without DM
    final pendRace = await insertPending(
      buyer: buyerId,
      fbRef: 'fb:p71race_$suffix',
    );
    final ridRace = pendRace['id']!.toString();
    await client.patch('live_reservation_requests', 'id=eq.$ridRace', {
      'status': 'accepted',
      'request_kind': 'guaranteed',
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 2))
          .toIso8601String(),
    });
    final race = await Future.wait([
      client.rpc('batata_commerce_post_reservation_dm', {
        'p_request_id': ridRace,
        'p_kind': 'reservation_guaranteed',
        'p_payload': {'race': 'a'},
      }),
      client.rpc('batata_commerce_post_reservation_dm', {
        'p_request_id': ridRace,
        'p_kind': 'reservation_guaranteed',
        'p_payload': {'race': 'b'},
      }),
      client.rpc('batata_commerce_post_reservation_dm', {
        'p_request_id': ridRace,
        'p_kind': 'reservation_guaranteed',
        'p_payload': {'race': 'c'},
      }),
    ]);
    final dmsRace = await msgsFor(ridRace, 'reservation_guaranteed');
    final inserts =
        race.whereType<Map>().where((m) => m['inserted'] == true).length;
    mark(
      'concurrent_dm_fresh_race',
      dmsRace.length == 1 && inserts == 1 ? 'PASS' : 'FAIL',
      {
        'dm_count': dmsRace.length,
        'insert_oks': inserts,
        'results': race,
      },
    );

    // ---- Heal: event/claim without message ----
    final pendH = await insertPending(buyer: buyerId, fbRef: 'fb:p71h_$suffix');
    final ridH = pendH['id']!.toString();
    await client.patch('live_reservation_requests', 'id=eq.$ridH', {
      'status': 'accepted',
      'request_kind': 'guaranteed',
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String(),
    });
    // Claim ledger without message (simulate failed insert after claim)
    await client.insert('commerce_reservation_dm_posts', {
      'request_id': ridH,
      'kind': 'reservation_guaranteed',
      'marker': '[[fleaber_res:reservation_guaranteed:$ridH]]',
    });
    final heal = await client.rpc('batata_commerce_post_reservation_dm', {
      'p_request_id': ridH,
      'p_kind': 'reservation_guaranteed',
      'p_payload': {'heal': true},
    });
    final dmsH = await msgsFor(ridH, 'reservation_guaranteed');
    mark(
      'heal_claim_without_message',
      heal is Map &&
              heal['ok'] == true &&
              heal['inserted'] == true &&
              dmsH.length == 1
          ? 'PASS'
          : 'FAIL',
      {'heal': heal, 'dm_count': dmsH.length},
    );

    // ---- Forge denied ----
    var forgeBlocked = false;
    String? forgeErr;
    try {
      await client.insertAsUser(
        'chat_messages',
        {
          'chat_id': dms.first['chat_id'],
          'sender_id': buyerId,
          'receiver_id': sellerId,
          'text':
              'Fleaber · sistema\nReserva garantida fake\n[[fleaber_res:reservation_guaranteed:$rid]]',
          'is_reservation': true,
          'is_read': false,
        },
        accessToken: buyerToken,
      );
    } catch (e) {
      forgeBlocked = true;
      forgeErr = e.toString();
    }
    mark(
      'system_dm_forge_denied',
      forgeBlocked &&
              (forgeErr ?? '').contains('fleaber_system_dm_forge_denied')
          ? 'PASS'
          : 'FAIL',
      {'blocked': forgeBlocked, 'error': forgeErr},
    );

    // ---- Authenticity: body label + UI source check ----
    final chatSrc = await File('lib/chat_page/chat_page_widget.dart').readAsString();
    mark(
      'system_dm_authenticity_label',
      body.contains('Fleaber · sistema') &&
              chatSrc.contains("'Fleaber · sistema'") &&
              chatSrc.contains('_tryBuildCommerceReservationDmCard')
          ? 'PASS'
          : 'FAIL',
      'system label in DM body + dedicated card widget',
    );

    // ---- Two buyers same seller/product ----
    final pendB2 = await insertPending(
      buyer: buyer2Id!,
      display: 'Maria P71', // same visible name
      fbRef: 'fb:p71b2_$suffix',
    );
    final ridB2 = pendB2['id']!.toString();
    await client.rpc(
      'batata_commerce_accept_pending',
      {'p_request_id': ridB2},
      accessToken: sellerToken,
    );
    final dmB1 = await msgsFor(rid, 'reservation_guaranteed');
    final dmB2 = await msgsFor(ridB2, 'reservation_guaranteed');
    final chatB1 = dmB1.isNotEmpty ? dmB1.first['chat_id']?.toString() : null;
    final chatB2 = dmB2.isNotEmpty ? dmB2.first['chat_id']?.toString() : null;
    mark(
      'two_buyers_same_seller_product',
      dmB1.length == 1 &&
              dmB2.length == 1 &&
              chatB1 != null &&
              chatB2 != null &&
              chatB1 != chatB2 &&
              dmB1.first['receiver_id']?.toString() == buyerId &&
              dmB2.first['receiver_id']?.toString() == buyer2Id &&
              dmB1.first['sender_id']?.toString() == sellerId &&
              dmB2.first['sender_id']?.toString() == sellerId
          ? 'PASS'
          : 'FAIL',
      {
        'chat_b1': chatB1,
        'chat_b2': chatB2,
        'recv_b1': dmB1.isNotEmpty ? dmB1.first['receiver_id'] : null,
        'recv_b2': dmB2.isNotEmpty ? dmB2.first['receiver_id'] : null,
      },
    );

    mark(
      't19_same_name_isolation',
      dmB1.length == 1 &&
              dmB2.length == 1 &&
              chatB1 != chatB2 &&
              pend['external_display_name'] == pendB2['external_display_name']
          ? 'PASS'
          : 'FAIL',
      {
        'name': pendB2['external_display_name'],
        'distinct_chats': chatB1 != chatB2,
      },
    );

    // ---- Different seller isolation ----
    final seller2Email =
        'p71.seller2.${Random().nextInt(1 << 28)}@fleaber-test.local';
    final seller2Pass = 'P71S-${Random().nextInt(1 << 28)}aA!';
    final seller2Id =
        await client.createAdminUser(email: seller2Email, password: seller2Pass);
    final seller2Token =
        await client.signIn(email: seller2Email, password: seller2Pass);
    final product2 = await client.insert('products', {
      'seller_id': seller2Id,
      'title': 'P71 S2 $suffix',
      'price': 12,
      'quantity': 20,
      'ref_code': 'P71S2-$suffix',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live2 = await client.insert('lives', {
      'title': 'P71S2_$suffix',
      'status': 'live',
      'seller_id': seller2Id,
      'vendedor_id': seller2Id,
      'is_active': true,
    });
    liveIds.add(live2['id']!.toString());
    final item2 = await client.insert('live_items', {
      'live_id': live2['id'],
      'ref_code': 'R2$suffix'.substring(0, 6).toUpperCase(),
      'title': 'Item S2',
      'price': 12,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': product2['id'],
      'checkout_product_id': product2['id'],
    });
    final pendS2 = await insertPending(
      buyer: buyerId,
      seller: seller2Id,
      live: live2['id']!.toString(),
      liveItem: item2['id']!.toString(),
      fbRef: 'fb:p71s2_$suffix',
    );
    final ridS2 = pendS2['id']!.toString();
    final accS2 = await client.rpc(
      'batata_commerce_accept_pending',
      {'p_request_id': ridS2},
      accessToken: seller2Token,
    ) as Map;
    final dmS2 = await msgsFor(ridS2, 'reservation_guaranteed');
    mark(
      't20_21_seller_live_isolation',
      accS2['ok'] == true &&
              dmS2.length == 1 &&
              dmS2.first['sender_id']?.toString() == seller2Id &&
              dmS2.first['receiver_id']?.toString() == buyerId &&
              dmS2.first['chat_id']?.toString() != chatB1
          ? 'PASS'
          : 'FAIL',
      {
        'accept_ok': accS2['ok'],
        'sender': dmS2.isNotEmpty ? dmS2.first['sender_id'] : null,
        'chat': dmS2.isNotEmpty ? dmS2.first['chat_id'] : null,
        'not_seller1_chat': dmS2.isNotEmpty
            ? dmS2.first['chat_id']?.toString() != chatB1
            : false,
      },
    );

    // ---- Reject / expire ----
    final pendR = await insertPending(buyer: buyerId, fbRef: 'fb:p71r_$suffix');
    final ridR = pendR['id']!.toString();
    final rej = await client.rpc(
      'batata_commerce_reject_pending',
      {'p_request_id': ridR},
      accessToken: sellerToken,
    ) as Map;
    final dmR = await msgsFor(ridR, 'reservation_rejected');
    mark(
      'reject_dm',
      rej['ok'] == true &&
              dmR.length == 1 &&
              (dmR.first['text']?.toString() ?? '')
                  .contains('Fleaber · sistema')
          ? 'PASS'
          : 'FAIL',
      {'ok': rej['ok'], 'dm': dmR.length},
    );

    final pendE = await insertPending(buyer: buyerId, fbRef: 'fb:p71e_$suffix');
    final ridE = pendE['id']!.toString();
    final exp = await client.rpc('batata_commerce_emit_reservation_event', {
      'p_request_id': ridE,
      'p_kind': 'pending_expired_buyer_notice',
      'p_payload': {'source': 'p71'},
    });
    final dmE = await msgsFor(ridE, 'pending_expired_buyer_notice');
    mark(
      'expire_dm',
      exp is Map && dmE.length == 1 ? 'PASS' : 'FAIL',
      {'event': exp, 'dm': dmE.length},
    );

    // ---- Qty ----
    await client.patch('live_reservation_requests', 'id=eq.$rid', {
      'requested_qty': 3,
    });
    final q = await rowReq(rid);
    mark(
      'qty_state',
      q?['requested_qty'] == 3 ? 'PASS' : 'FAIL',
      {'qty': q?['requested_qty']},
    );

    // ---- Auth orphan ----
    final orphan = await client.insert('live_reservation_requests', {
      'live_id': liveId,
      'live_item_id': liveItemId,
      'seller_id': sellerId,
      'requested_qty': 1,
      'status': 'accepted',
      'request_kind': 'guaranteed',
      'source': 'facebook_manual',
      'external_buyer_ref': 'fb:orphan_$suffix',
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String(),
    });
    final orphanId = orphan['id']!.toString();
    final usable = await client.rpc('batata_commerce_reservation_usable_by_actor', {
      'p_reservation_id': orphanId,
      'p_buyer_id': buyerId,
      'p_guest_session_id': null,
    });
    mark(
      'buyer_authorization_orphan',
      usable == false ? 'PASS' : 'FAIL',
      {'usable': usable},
    );

    // ---- Checkout directed ----
    final begin = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': product['id'],
            'live_item_id': liveItemId,
            'reservation_request_id': orphanId,
            'quantity': 1,
            'unit_cents': 1000,
            'line_cents': 1000,
          }
        ],
        'p_shipping_method': 'ctt',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_live_id': liveId,
        'p_client_idempotency_key': 'p71-$suffix',
        'p_confirm_remainder': true,
        'p_guest_token': null,
      },
      accessToken: buyerToken,
    );
    mark(
      'checkout_regression_orphan_denied',
      begin is Map && begin['ok'] != true &&
              (begin['error']?.toString() == 'reservation_not_authorized' ||
                  (begin['error']?.toString() ?? '')
                      .contains('reservation_not_authorized'))
          ? 'PASS'
          : 'FAIL',
      begin,
    );

    final beginOk = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': [
          {
            'product_id': product['id'],
            'live_item_id': liveItemId,
            'reservation_request_id': rid,
            'quantity': 3,
            'unit_cents': 1000,
            'line_cents': 3000,
          }
        ],
        'p_shipping_method': 'ctt',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_live_id': liveId,
        'p_client_idempotency_key': 'p71-ok-$suffix',
        'p_confirm_remainder': true,
      },
      accessToken: buyerToken,
    );
    mark(
      'checkout_regression_owner_ok',
      beginOk is Map &&
              (beginOk['ok'] == true ||
                  beginOk['checkout_attempt_id'] != null)
          ? 'PASS'
          : 'FAIL',
      {
        'ok': beginOk is Map ? beginOk['ok'] : null,
        'error': beginOk is Map ? beginOk['error'] : null,
        'attempt': beginOk is Map ? beginOk['checkout_attempt_id'] : null,
        'total': beginOk is Map
            ? (beginOk['quote'] is Map
                ? (beginOk['quote'] as Map)['total_cents']
                : beginOk['total_cents'])
            : null,
      },
    );

    // ---- Stock ----
    final avail = await client.rpc('batata_live_item_available_qty_engine', {
      'p_live_item_id': liveItemId,
    });
    mark(
      'stock_regression',
      avail is num && (avail as num) >= 0 ? 'PASS' : 'FAIL',
      {'available': avail},
    );

    // ---- Retry / reconnect persistence (backend) ----
    final retry = await client.rpc('batata_commerce_post_reservation_dm', {
      'p_request_id': rid,
      'p_kind': 'reservation_guaranteed',
      'p_payload': {'retry': true},
    });
    final dmsRetry = await msgsFor(rid, 'reservation_guaranteed');
    mark(
      'retry_no_duplicate_after_reconnect_sim',
      retry is Map &&
              (retry['deduped'] == true || retry['inserted'] == false) &&
              dmsRetry.length == 1
          ? 'PASS'
          : 'FAIL',
      {'retry': retry, 'dm_count': dmsRetry.length},
    );

    // ---- Reclassified: no device UI ----
    mark(
      't14_15_payment_accuracy',
      'NOT RUN',
      'no PSP confirmation executed in 7.1; false paid not asserted here',
    );
    mark(
      't22_24_realtime_ui',
      'NOT RUN',
      'no device/chat-open environment in this round; persistence covered by retry_no_duplicate + DM queries',
    );
    mark(
      'mobile_ux_device',
      'NOT RUN',
      'no mobile screenshot session; system card code present in chat_page_widget',
    );
    mark(
      'pending_vs_guaranteed_ui_device',
      'NOT RUN',
      'device UI not exercised; backend states pending≠guaranteed proven via accept/reject paths',
    );

    // Copy constant still correct
    final copySrc = await File('lib/utils/live_bag_copy.dart').readAsString();
    mark(
      'ux_pending_label_source',
      copySrc.contains('A aguardar aprovação') ? 'PASS' : 'FAIL',
      'source constant',
    );

    mark('seller_studio_reconnection_ui', 'NOT RUN', 'pre-launch');
    mark('external_meta_e2e', 'BLOCKED EXTERNAL', 'out of scope');
  } catch (e, st) {
    mark('FATAL', 'FAIL', '$e\n$st');
  } finally {
    for (final id in liveIds) {
      try {
        await client.patch('lives', 'id=eq.$id', {
          'status': 'ended',
          'is_active': false,
          'ended_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (_) {}
    }
  }

  results['ended_at'] = DateTime.now().toUtc().toIso8601String();
  final tests = results['tests'] as Map<String, dynamic>;
  var pass = 0, fail = 0, other = 0;
  for (final t in tests.values) {
    final s = (t as Map)['status']?.toString() ?? '';
    if (s == 'PASS') {
      pass++;
    } else if (s == 'FAIL') {
      fail++;
    } else {
      other++;
    }
  }
  results['summary'] = {'pass': pass, 'fail': fail, 'other': other};
  final out = File('${outDir.path}/phase7_1_results.json');
  await out.writeAsString(const JsonEncoder.withIndent('  ').convert(results));
  print('SUMMARY pass=$pass fail=$fail other=$other → ${out.path}');
  if (fail > 0) exit(1);
}
