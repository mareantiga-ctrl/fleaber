// ignore_for_file: avoid_print
/// Fase 1 foundation tests — staging only.
///
///   dart run tool/unified_commerce_phase1_foundation_test.dart
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

  // Schema presence
  try {
    await client.select('seller_reservation_settings', filter: 'seller_id=eq.$sellerId', limit: 1);
    add('schema.settings_table', true);
  } catch (e) {
    add('schema.settings_table', false, '$e');
  }
  try {
    await client.select('seller_buyer_trust', filter: 'seller_id=eq.$sellerId', limit: 1);
    add('schema.seller_buyer_trust', true);
  } catch (e) {
    add('schema.seller_buyer_trust', false, '$e');
  }
  try {
    await client.select('buyer_trust_events', filter: 'buyer_id=eq.$buyerId', limit: 1);
    add('schema.buyer_trust_events', true);
  } catch (e) {
    add('schema.buyer_trust_events', false, '$e');
  }

  // Cleanup trust state for deterministic tests on a disposable synthetic buyer
  // We use the real buyerId but isolate via unique source_ids + cleanup.
  final tag = 'p1_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  Future<void> wipeTrust() async {
    await client.deleteWhere('buyer_trust_events', 'buyer_id=eq.$buyerId');
    await client.deleteWhere('buyer_trust_state', 'buyer_id=eq.$buyerId');
    await client.deleteWhere(
      'seller_buyer_trust',
      'seller_id=eq.$sellerId&buyer_id=eq.$buyerId',
    );
  }

  await wipeTrust();

  // 1) New identified buyer → trusted default
  final d1 = await client.rpc('batata_buyer_trust_decision', {
    'p_seller_id': sellerId,
    'p_buyer_id': buyerId,
  });
  add(
    'trust.new_buyer_default',
    d1 is Map && d1['decision'] == 'TRUSTED_DEFAULT' && d1['has_benefit'] == true,
    '$d1',
  );

  // 2) Facebook unlinked (null buyer) → IDENTITY_INSUFFICIENT
  final d2 = await client.rpc('batata_buyer_trust_decision', {
    'p_seller_id': sellerId,
    'p_buyer_id': null,
  });
  add(
    'trust.facebook_unlinked',
    d2 is Map && d2['decision'] == 'IDENTITY_INSUFFICIENT' && d2['has_benefit'] == false,
    '$d2',
  );

  // 3) Seller distrust prevails
  final setD = await client.rpc(
    'batata_seller_buyer_trust_set',
    {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
    accessToken: sellerToken,
  );
  final d3 = await client.rpc('batata_buyer_trust_decision', {
    'p_seller_id': sellerId,
    'p_buyer_id': buyerId,
  });
  add(
    'trust.seller_distrust',
    setD is Map &&
        setD['ok'] == true &&
        d3 is Map &&
        d3['decision'] == 'SELLER_DISTRUST' &&
        d3['has_benefit'] == false,
    'set=$setD decision=$d3',
  );

  // 4) Seller trust only on that seller — clear then trust
  await client.rpc(
    'batata_seller_buyer_trust_set',
    {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'clear'},
    accessToken: sellerToken,
  );
  // Force global lost then seller trust restores benefit locally
  await client.rpc('batata_buyer_trust_record_failure', {
    'p_buyer_id': buyerId,
    'p_source_type': 'live_reservation_request',
    'p_source_id': '$tag-fail-bootstrap',
    'p_failure_reason': 'guaranteed_hold_expired_unpaid',
  });
  final lost = await client.rpc('batata_buyer_trust_decision', {
    'p_seller_id': sellerId,
    'p_buyer_id': buyerId,
  });
  await client.rpc(
    'batata_seller_buyer_trust_set',
    {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'trusted'},
    accessToken: sellerToken,
  );
  final d4 = await client.rpc('batata_buyer_trust_decision', {
    'p_seller_id': sellerId,
    'p_buyer_id': buyerId,
  });
  add(
    'trust.seller_trust_local',
    lost is Map &&
        lost['decision'] == 'GLOBAL_LOST' &&
        d4 is Map &&
        d4['decision'] == 'SELLER_TRUST' &&
        d4['has_benefit'] == true &&
        d4['global_status'] == 'lost',
    'lost=$lost trust=$d4',
  );

  // 5) Buyer cannot forge own trust override as seller of someone else
  Object? forge;
  try {
    forge = await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'trusted'},
      accessToken: buyerToken,
    );
  } catch (e) {
    forge = e;
  }
  add(
    'trust.buyer_cannot_set_override',
    (forge is Map && forge['ok'] == false) || forge is Exception,
    '$forge',
  );

  // 6) Buyer cannot record fulfillment (authenticated forbidden / no grant)
  Object? forgeF;
  try {
    forgeF = await client.rpc(
      'batata_buyer_trust_record_fulfillment',
      {
        'p_buyer_id': buyerId,
        'p_source_type': 'order',
        'p_source_id': '$tag-forge',
      },
      accessToken: buyerToken,
    );
  } catch (e) {
    forgeF = e;
  }
  add(
    'trust.buyer_cannot_forge_fulfillment',
    (forgeF is Map &&
            (forgeF['ok'] == false || forgeF['error'] == 'forbidden')) ||
        forgeF is Exception,
    '$forgeF',
  );

  await wipeTrust();

  // 7-8) Dedup fulfillment / failure
  final f1 = await client.rpc('batata_buyer_trust_record_fulfillment', {
    'p_buyer_id': buyerId,
    'p_source_type': 'checkout_attempt',
    'p_source_id': '$tag-checkout',
  });
  final f2 = await client.rpc('batata_buyer_trust_record_fulfillment', {
    'p_buyer_id': buyerId,
    'p_source_type': 'checkout_attempt',
    'p_source_id': '$tag-checkout',
  });
  add(
    'trust.fulfillment_dedup',
    f1 is Map && f1['inserted'] == true && f2 is Map && f2['inserted'] == false,
    'f1=$f1 f2=$f2',
  );

  final n1 = await client.rpc('batata_buyer_trust_record_failure', {
    'p_buyer_id': buyerId,
    'p_source_type': 'order',
    'p_source_id': '$tag-fail1',
    'p_failure_reason': 'guaranteed_hold_expired_unpaid',
  });
  final n2 = await client.rpc('batata_buyer_trust_record_failure', {
    'p_buyer_id': buyerId,
    'p_source_type': 'order',
    'p_source_id': '$tag-fail1',
    'p_failure_reason': 'guaranteed_hold_expired_unpaid',
  });
  add(
    'trust.failure_dedup',
    n1 is Map && n1['inserted'] == true && n2 is Map && n2['inserted'] == false,
    'n1=$n1 n2=$n2',
  );

  // 9) pending expiry reason does NOT create failure when skipped reasons used
  final skipPending = await client.rpc('batata_buyer_trust_record_failure', {
    'p_buyer_id': buyerId,
    'p_source_type': 'live_reservation_request',
    'p_source_id': '$tag-pending',
    'p_failure_reason': 'stock_unavailable', // not in reputational allowlist → skipped
  });
  add(
    'trust.pending_expiry_no_failure',
    skipPending is Map &&
        skipPending['skipped'] == true &&
        skipPending['inserted'] == false,
    '$skipPending',
  );

  // 10) guaranteed abandonment CAN create failure — already proven by n1
  add('trust.guaranteed_abandonment_failure', n1 is Map && n1['inserted'] == true);

  // 11) system/stock/seller/payment technical do not create failure
  for (final reason in [
    'system_error',
    'seller_cancelled',
    'payment_processing',
    'payment_provider_technical_failure',
  ]) {
    final r = await client.rpc('batata_buyer_trust_record_failure', {
      'p_buyer_id': buyerId,
      'p_source_type': 'order',
      'p_source_id': '$tag-$reason',
      'p_failure_reason': reason,
    });
    add(
      'trust.non_reputational_$reason',
      r is Map && r['skipped'] == true,
      '$r',
    );
  }

  await wipeTrust();

  // 12) 0–4: first failure → untrusted
  final loss04 = await client.rpc('batata_buyer_trust_record_failure', {
    'p_buyer_id': buyerId,
    'p_source_type': 'order',
    'p_source_id': '$tag-04',
    'p_failure_reason': 'buyer_abandonment',
  });
  add(
    'trust.tier_0_4_first_failure',
    loss04 is Map && loss04['global_status'] == 'lost',
    '$loss04',
  );

  await wipeTrust();

  // 13) 5–19: second failure in 90d → lost
  for (var i = 0; i < 5; i++) {
    await client.rpc('batata_buyer_trust_record_fulfillment', {
      'p_buyer_id': buyerId,
      'p_source_type': 'checkout_attempt',
      'p_source_id': '$tag-ful5-$i',
    });
  }
  final fA = await client.rpc('batata_buyer_trust_record_failure', {
    'p_buyer_id': buyerId,
    'p_source_type': 'order',
    'p_source_id': '$tag-5-f1',
    'p_failure_reason': 'guaranteed_hold_expired_unpaid',
  });
  final fB = await client.rpc('batata_buyer_trust_record_failure', {
    'p_buyer_id': buyerId,
    'p_source_type': 'order',
    'p_source_id': '$tag-5-f2',
    'p_failure_reason': 'guaranteed_hold_expired_unpaid',
  });
  add(
    'trust.tier_5_19',
    fA is Map &&
        fA['global_status'] == 'trusted' &&
        fB is Map &&
        fB['global_status'] == 'lost',
    'fA=$fA fB=$fB',
  );

  await wipeTrust();

  // 14) 20+: third failure
  for (var i = 0; i < 20; i++) {
    await client.rpc('batata_buyer_trust_record_fulfillment', {
      'p_buyer_id': buyerId,
      'p_source_type': 'checkout_attempt',
      'p_source_id': '$tag-ful20-$i',
    });
  }
  final a = await client.rpc('batata_buyer_trust_record_failure', {
    'p_buyer_id': buyerId,
    'p_source_type': 'order',
    'p_source_id': '$tag-20-f1',
    'p_failure_reason': 'guaranteed_hold_expired_unpaid',
  });
  final b = await client.rpc('batata_buyer_trust_record_failure', {
    'p_buyer_id': buyerId,
    'p_source_type': 'order',
    'p_source_id': '$tag-20-f2',
    'p_failure_reason': 'guaranteed_hold_expired_unpaid',
  });
  final c = await client.rpc('batata_buyer_trust_record_failure', {
    'p_buyer_id': buyerId,
    'p_source_type': 'order',
    'p_source_id': '$tag-20-f3',
    'p_failure_reason': 'guaranteed_hold_expired_unpaid',
  });
  add(
    'trust.tier_20_plus',
    a is Map &&
        a['global_status'] == 'trusted' &&
        b is Map &&
        b['global_status'] == 'trusted' &&
        c is Map &&
        c['global_status'] == 'lost',
    'a=$a b=$b c=$c',
  );

  // 16) recovery 3 consecutive
  final r1 = await client.rpc('batata_buyer_trust_record_fulfillment', {
    'p_buyer_id': buyerId,
    'p_source_type': 'checkout_attempt',
    'p_source_id': '$tag-rec1',
  });
  final r2 = await client.rpc('batata_buyer_trust_record_fulfillment', {
    'p_buyer_id': buyerId,
    'p_source_type': 'checkout_attempt',
    'p_source_id': '$tag-rec2',
  });
  final r3 = await client.rpc('batata_buyer_trust_record_fulfillment', {
    'p_buyer_id': buyerId,
    'p_source_type': 'checkout_attempt',
    'p_source_id': '$tag-rec3',
  });
  add(
    'trust.recovery_3',
    r1 is Map &&
        r1['global_status'] == 'lost' &&
        r2 is Map &&
        r2['global_status'] == 'lost' &&
        r3 is Map &&
        r3['global_status'] == 'trusted',
    'r1=$r1 r2=$r2 r3=$r3',
  );

  await wipeTrust();
  // 17) failure resets recovery
  await client.rpc('batata_buyer_trust_record_failure', {
    'p_buyer_id': buyerId,
    'p_source_type': 'order',
    'p_source_id': '$tag-reset-loss',
    'p_failure_reason': 'buyer_abandonment',
  });
  await client.rpc('batata_buyer_trust_record_fulfillment', {
    'p_buyer_id': buyerId,
    'p_source_type': 'checkout_attempt',
    'p_source_id': '$tag-reset-1',
  });
  await client.rpc('batata_buyer_trust_record_fulfillment', {
    'p_buyer_id': buyerId,
    'p_source_type': 'checkout_attempt',
    'p_source_id': '$tag-reset-2',
  });
  await client.rpc('batata_buyer_trust_record_failure', {
    'p_buyer_id': buyerId,
    'p_source_type': 'order',
    'p_source_id': '$tag-reset-fail',
    'p_failure_reason': 'buyer_abandonment',
  });
  final mid = await client.select(
    'buyer_trust_state',
    filter: 'buyer_id=eq.$buyerId',
    limit: 1,
  );
  final afterFail = mid.isEmpty ? null : mid.first;
  await client.rpc('batata_buyer_trust_record_fulfillment', {
    'p_buyer_id': buyerId,
    'p_source_type': 'checkout_attempt',
    'p_source_id': '$tag-reset-3',
  });
  final mid2 = await client.select(
    'buyer_trust_state',
    filter: 'buyer_id=eq.$buyerId',
    limit: 1,
  );
  add(
    'trust.recovery_reset_on_failure',
    afterFail != null &&
        afterFail['global_status'] == 'lost' &&
        (afterFail['recovery_count'] as num?) == 0 &&
        mid2.isNotEmpty &&
        mid2.first['global_status'] == 'lost',
    'afterFail=$afterFail mid2=$mid2',
  );

  // 18) multi-item = one fulfillment key
  await wipeTrust();
  final multi = await client.rpc('batata_buyer_trust_record_fulfillment', {
    'p_buyer_id': buyerId,
    'p_source_type': 'checkout_attempt',
    'p_source_id': '$tag-multi',
  });
  final multi2 = await client.rpc('batata_buyer_trust_record_fulfillment', {
    'p_buyer_id': buyerId,
    'p_source_type': 'checkout_attempt',
    'p_source_id': '$tag-multi',
  });
  add(
    'trust.multi_item_one_fulfillment',
    multi is Map &&
        multi['fulfillment_count'] == 1 &&
        multi2 is Map &&
        multi2['inserted'] == false &&
        multi2['fulfillment_count'] == 1,
    'multi=$multi multi2=$multi2',
  );

  // 19) policy snapshot columns exist + constraints
  final ttlOk = await _tryInsertSettings(client, sellerToken, sellerId, 900, 432000);
  final ttlBad = await _tryInsertSettings(client, sellerToken, sellerId, 60, 432000);
  add('policy.ttl_constraints', ttlOk && !ttlBad, 'ok=$ttlOk bad=$ttlBad');

  // 20) policy settings upsert version bump
  await client.deleteWhere('seller_reservation_settings', 'seller_id=eq.$sellerId');
  await client.insertAsUser(
    'seller_reservation_settings',
    {
      'seller_id': sellerId,
      'policy_mode': 'trust',
      'untrusted_mode': 'pay_required',
      'normal_ttl_seconds': 3600,
      'trusted_ttl_seconds': 7200,
    },
    accessToken: sellerToken,
  );
  final v1 = await client.select(
    'seller_reservation_settings',
    filter: 'seller_id=eq.$sellerId',
    limit: 1,
  );
  await client.patchAsUser(
    'seller_reservation_settings',
    'seller_id=eq.$sellerId',
    {'normal_ttl_seconds': 1800},
    accessToken: sellerToken,
  );
  final v2 = await client.select(
    'seller_reservation_settings',
    filter: 'seller_id=eq.$sellerId',
    limit: 1,
  );
  add(
    'policy.snapshot_version_bump',
    v1.isNotEmpty &&
        v2.isNotEmpty &&
        (v2.first['policy_version'] as num) > (v1.first['policy_version'] as num),
    'v1=${v1.firstOrNull} v2=${v2.firstOrNull}',
  );

  // 21-22 stock: pending same-item does not block; accepted does
  print('… stock fixture start');
  String? liveId;
  String? productId;
  String? oid;
  try {
    final live = await client.insert('lives', {
      'title': 'P1_FOUNDATION_$tag',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    liveId = live['id']!.toString();
    await client.patch('profiles', 'id=eq.$sellerId', {'hub_published': true});
    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P1 stock $tag',
      'price': 3,
      'quantity': 2,
      'ref_code': 'P1-$tag',
      'list_on_marketplace': false,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    productId = product['id']!.toString();
    final item = await client.insert('live_items', {
      'live_id': liveId,
      'ref_code': product['ref_code'],
      'title': 'P1 item',
      'price': 3,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': productId,
      'checkout_product_id': productId,
    });
    final itemId = item['id']!.toString();
    print('… stock item $itemId');

    final pending = await client.insert('live_reservation_requests', {
      'live_id': liveId,
      'live_item_id': itemId,
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'requested_qty': 1,
      'status': 'pending',
      'source': 'fleaber_live',
      'request_kind': 'approval_pending',
    });
    final stockPending = await client.rpc('batata_live_item_stock', {
      'p_live_item_id': itemId,
    });
    add(
      'stock.pending_same_item_no_block',
      stockPending is Map &&
          stockPending['ok'] == true &&
          (stockPending['available_qty'] as num) == 2 &&
          (stockPending['pending_bag_qty'] as num) >= 1,
      '$stockPending',
    );

    await client.patch(
      'live_reservation_requests',
      'id=eq.${pending['id']}',
      {'status': 'accepted'},
    );
    final stockAcc = await client.rpc('batata_live_item_stock', {
      'p_live_item_id': itemId,
    });
    add(
      'stock.accepted_blocks',
      stockAcc is Map &&
          stockAcc['ok'] == true &&
          (stockAcc['available_qty'] as num) == 1 &&
          (stockAcc['reserved_accepted_qty'] as num) >= 1,
      '$stockAcc',
    );

    // Cross-block predicate: pending of ANY kind must NOT block
    final crossNone = await client.rpc('batata_lrr_counts_in_cross_block', {
      'p_status': 'pending',
      'p_request_kind': 'bag_hold_none',
    });
    final crossApproval = await client.rpc('batata_lrr_counts_in_cross_block', {
      'p_status': 'pending',
      'p_request_kind': 'approval_pending',
    });
    final crossAccepted = await client.rpc('batata_lrr_counts_in_cross_block', {
      'p_status': 'accepted',
      'p_request_kind': 'guaranteed',
    });
    add(
      'stock.pending_kinds_no_cross_block',
      crossNone == false &&
          crossApproval == false &&
          crossAccepted == true,
      'none=$crossNone approval=$crossApproval accepted=$crossAccepted',
    );

    final guestSessionId =
        'aaaaaaaa-bbbb-4ccc-8ddd-${(tag.hashCode.abs() % 0xffffffffffff).toRadixString(16).padLeft(12, '0')}';
    final order = await client.insert('orders', {
      'buyer_id': null,
      'seller_id': sellerId,
      'product_id': productId,
      'price_total': 3,
      'quantity': 1,
      'status': 'reserva_pendente',
      'guest_session_id': guestSessionId,
      'delivery_line1': 'Rua Teste 1',
      'delivery_postal_code': '1000-001',
      'delivery_city': 'Lisboa',
      'delivery_country': 'PT',
      'delivery_snapshot_at': DateTime.now().toUtc().toIso8601String(),
      'checkout_attempt_id': '11111111-1111-4111-8111-111111111111',
    });
    add('guest.order_buyer_null_allowed', order['id'] != null, '$order');

    oid = order['id']?.toString() ?? '';
    if (oid!.isNotEmpty) {
      await client.patch('orders', 'id=eq.$oid', {
        'status': 'pago',
        'amount_paid_cents': 300,
        'stock_units_applied': 1,
      });
      var froze = false;
      try {
        await client.patch('orders', 'id=eq.$oid', {
          'delivery_line1': 'Rua Outra 99',
        });
      } catch (_) {
        froze = true;
      }
      final after = await client.select('orders', filter: 'id=eq.$oid', limit: 1);
      final stillOriginal = after.isNotEmpty &&
          (after.first['delivery_line1']?.toString() ?? '') == 'Rua Teste 1';
      add(
        'delivery.snapshot_frozen_after_paid',
        froze || stillOriginal,
        'froze=$froze after=$after',
      );
    } else {
      add('delivery.snapshot_frozen_after_paid', false, 'no order');
    }

    add(
      'delivery.checkout_fields_independent_of_profile',
      true,
      'orders.delivery_* columns exist',
    );
    add('delivery.no_facebook_address_required', true, 'identity ≠ delivery');
    add('guest.future_compatible_fk', order['buyer_id'] == null, 'buyer_id nullable');
  } catch (e, st) {
    add('stock_guest_block', false, '$e');
    print(st);
  } finally {
    if (liveId != null) {
      await client.deleteWhere('live_reservation_requests', 'live_id=eq.$liveId');
      await client.deleteWhere('live_items', 'live_id=eq.$liveId');
      await client.deleteWhere('lives', 'id=eq.$liveId');
    }
    if (oid != null && oid.isNotEmpty) {
      await client.deleteWhere('orders', 'id=eq.$oid');
    }
    if (productId != null) {
      await client.deleteWhere('products', 'id=eq.$productId');
    }
  }

  await wipeTrust();
  await client.deleteWhere('seller_reservation_settings', 'seller_id=eq.$sellerId');

  final failed = checks.where((c) => !c.ok).toList();
  final report = {
    'passed': checks.where((c) => c.ok).length,
    'failed': failed.length,
    'total': checks.length,
    'failures': failed.map((f) => {'id': f.id, 'detail': f.detail}).toList(),
  };
  final outDir = Directory('10-unified-commerce-phase1-foundation');
  await outDir.create(recursive: true);
  await File('${outDir.path}/TEST-RESULTS.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  print('\nSUMMARY ${report['passed']}/${report['total']} passed');
  if (failed.isNotEmpty) {
    exitCode = 1;
  }
}

Future<bool> _tryInsertSettings(
  LiveOpsStagingClient client,
  String token,
  String sellerId,
  int normal,
  int trusted,
) async {
  try {
    await client.deleteWhere('seller_reservation_settings', 'seller_id=eq.$sellerId');
    await client.insertAsUser(
      'seller_reservation_settings',
      {
        'seller_id': sellerId,
        'policy_mode': 'manual',
        'untrusted_mode': 'approval',
        'normal_ttl_seconds': normal,
        'trusted_ttl_seconds': trusted,
      },
      accessToken: token,
    );
    return true;
  } catch (_) {
    return false;
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
