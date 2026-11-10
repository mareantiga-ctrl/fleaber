// ignore_for_file: avoid_print
/// Phase 1 stock correction — pending must NOT cross-block.
///
///   dart run tool/unified_commerce_phase1_stock_correction_test.dart
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
  // Need a second buyer for guaranteed hold — reuse seller as "buyer B" only if
  // distinct; create via second login if available, else use sellerId carefully.
  // Prefer buyer as A and a synthetic second identity: use seller account as B
  // for reservation rows (seller can hold accepted on own catalog in staging).
  final buyerA = await client.userIdForAccessToken(buyerToken);
  final buyerB = sellerId; // staging: seller acts as second buyer for hold race

  final checks = <_Check>[];
  void add(String id, bool ok, [String detail = '']) {
    checks.add((id: id, ok: ok, detail: detail));
    print('${ok ? 'PASS' : 'FAIL'} $id ${detail.isEmpty ? '' : '— $detail'}');
  }

  final tag =
      'p1sc_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  // Predicate unit checks
  final pApproval = await client.rpc('batata_lrr_counts_in_cross_block', {
    'p_status': 'pending',
    'p_request_kind': 'approval_pending',
  });
  final pBag = await client.rpc('batata_lrr_counts_in_cross_block', {
    'p_status': 'pending',
    'p_request_kind': 'bag_hold_none',
  });
  final pAccepted = await client.rpc('batata_lrr_counts_in_cross_block', {
    'p_status': 'accepted',
    'p_request_kind': 'approval_pending',
  });
  add('pred.approval_pending_no_block', pApproval == false, '$pApproval');
  add('pred.bag_hold_none_no_block', pBag == false, '$pBag');
  add('pred.accepted_blocks', pAccepted == true, '$pAccepted');

  await client.patch('profiles', 'id=eq.$sellerId', {'hub_published': true});

  String? liveAId;
  String? liveBId;
  String? productId;
  String? itemAId;
  String? itemBId;
  String? pendingAId;
  String? acceptedBId;
  String? orderHoldId;

  try {
    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P1SC product $tag',
      'price': 4,
      'quantity': 1,
      'ref_code': 'P1SC-$tag',
      'list_on_marketplace': false,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    productId = product['id']!.toString();

    // Two lives → two live_items sharing same product_id (unique is per live)
    final liveA = await client.insert('lives', {
      'title': 'P1SC_A_$tag',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    liveAId = liveA['id']!.toString();
    final liveB = await client.insert('lives', {
      'title': 'P1SC_B_$tag',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    liveBId = liveB['id']!.toString();

    final itemA = await client.insert('live_items', {
      'live_id': liveAId,
      'ref_code': product['ref_code'],
      'title': 'P1SC item A',
      'price': 4,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': productId,
      'checkout_product_id': productId,
    });
    itemAId = itemA['id']!.toString();
    final itemB = await client.insert('live_items', {
      'live_id': liveBId,
      'ref_code': product['ref_code'],
      'title': 'P1SC item B',
      'price': 4,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': productId,
      'checkout_product_id': productId,
    });
    itemBId = itemB['id']!.toString();

    // Buyer A → approval_pending on A (stock total = 1)
    final pendingA = await client.insert('live_reservation_requests', {
      'live_id': liveAId,
      'live_item_id': itemAId,
      'seller_id': sellerId,
      'buyer_id': buyerA,
      'requested_qty': 1,
      'status': 'pending',
      'source': 'fleaber_live',
      'request_kind': 'approval_pending',
    });
    pendingAId = pendingA['id']?.toString();

    final stockA1 = await client.rpc('batata_live_item_stock', {
      'p_live_item_id': itemAId,
    });
    final stockB1 = await client.rpc('batata_live_item_stock', {
      'p_live_item_id': itemBId,
    });
    add(
      'cross.pending_A_available_A',
      stockA1 is Map &&
          stockA1['ok'] == true &&
          (stockA1['available_qty'] as num) == 1,
      '$stockA1',
    );
    add(
      'cross.pending_A_available_B',
      stockB1 is Map &&
          stockB1['ok'] == true &&
          (stockB1['available_qty'] as num) == 1 &&
          (stockB1['blocked_qty'] as num) == 0,
      '$stockB1',
    );

    // bag_hold_none on A (replace pending) still no cross-block on B
    await client.patch(
      'live_reservation_requests',
      'id=eq.$pendingAId',
      {'request_kind': 'bag_hold_none'},
    );
    final stockBBag = await client.rpc('batata_live_item_stock', {
      'p_live_item_id': itemBId,
    });
    add(
      'cross.bag_hold_none_no_block_B',
      stockBBag is Map &&
          stockBBag['ok'] == true &&
          (stockBBag['available_qty'] as num) == 1 &&
          (stockBBag['blocked_qty'] as num) == 0,
      '$stockBBag',
    );

    // Restore approval_pending, then buyer B takes guaranteed hold on B
    await client.patch(
      'live_reservation_requests',
      'id=eq.$pendingAId',
      {'request_kind': 'approval_pending'},
    );
    final acceptedB = await client.insert('live_reservation_requests', {
      'live_id': liveBId,
      'live_item_id': itemBId,
      'seller_id': sellerId,
      'buyer_id': buyerB,
      'requested_qty': 1,
      'status': 'accepted',
      'source': 'fleaber_live',
      'request_kind': 'guaranteed',
    });
    acceptedBId = acceptedB['id']?.toString();

    final stockA2 = await client.rpc('batata_live_item_stock', {
      'p_live_item_id': itemAId,
    });
    final stockB2 = await client.rpc('batata_live_item_stock', {
      'p_live_item_id': itemBId,
    });
    add(
      'cross.accepted_B_blocks_A',
      stockA2 is Map &&
          stockA2['ok'] == true &&
          (stockA2['available_qty'] as num) == 0,
      '$stockA2',
    );
    add(
      'cross.accepted_B_blocks_B',
      stockB2 is Map &&
          stockB2['ok'] == true &&
          (stockB2['available_qty'] as num) == 0 &&
          (stockB2['reserved_accepted_qty'] as num) >= 1,
      '$stockB2',
    );
    add(
      'cross.pending_A_no_priority',
      pendingAId != null &&
          stockA2 is Map &&
          (stockA2['available_qty'] as num) == 0,
      'pending still open but stock gone — no hold for A',
    );

    // Order blocking path preserved: cancel accepted B, create reservado order
    await client.patch(
      'live_reservation_requests',
      'id=eq.$acceptedBId',
      {'status': 'expired', 'expiry_reason': 'seller_cancelled'},
    );
    final order = await client.insert('orders', {
      'buyer_id': buyerB,
      'seller_id': sellerId,
      'product_id': productId,
      'price_total': 4,
      'quantity': 1,
      'status': 'reservado',
      'is_reservation': true,
    });
    orderHoldId = order['id']?.toString();
    final stockA3 = await client.rpc('batata_live_item_stock', {
      'p_live_item_id': itemAId,
    });
    add(
      'order.reservado_still_blocks',
      stockA3 is Map &&
          stockA3['ok'] == true &&
          (stockA3['available_qty'] as num) == 0 &&
          (stockA3['blocked_qty'] as num) >= 1,
      '$stockA3',
    );
  } catch (e, st) {
    add('fixture_error', false, '$e');
    print(st);
  } finally {
    if (pendingAId != null) {
      await client.deleteWhere('live_reservation_requests', 'id=eq.$pendingAId');
    }
    if (acceptedBId != null) {
      await client.deleteWhere('live_reservation_requests', 'id=eq.$acceptedBId');
    }
    if (liveAId != null) {
      await client.deleteWhere('live_reservation_requests', 'live_id=eq.$liveAId');
      await client.deleteWhere('live_items', 'live_id=eq.$liveAId');
      await client.deleteWhere('lives', 'id=eq.$liveAId');
    }
    if (liveBId != null) {
      await client.deleteWhere('live_reservation_requests', 'live_id=eq.$liveBId');
      await client.deleteWhere('live_items', 'live_id=eq.$liveBId');
      await client.deleteWhere('lives', 'id=eq.$liveBId');
    }
    if (orderHoldId != null) {
      await client.deleteWhere('orders', 'id=eq.$orderHoldId');
    }
    if (productId != null) {
      await client.deleteWhere('products', 'id=eq.$productId');
    }
  }

  final failed = checks.where((c) => !c.ok).toList();
  final report = {
    'passed': checks.where((c) => c.ok).length,
    'failed': failed.length,
    'total': checks.length,
    'failures': failed.map((f) => {'id': f.id, 'detail': f.detail}).toList(),
  };
  final outDir = Directory('10-unified-commerce-phase1-stock-correction');
  await outDir.create(recursive: true);
  await File('${outDir.path}/TEST-RESULTS.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  print('\nSUMMARY ${report['passed']}/${report['total']} passed');
  if (failed.isNotEmpty) exitCode = 1;
}
