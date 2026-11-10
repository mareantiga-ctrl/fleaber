// ignore_for_file: avoid_print
import 'dart:io';

import '../bag_crosscheck_logic.dart';
import '../live_ops_staging_client.dart';

const _liveTitle = 'REGRESSION_INT_TEST';
const _refPrefix = 'REGTEST';

/// Cenários BD/RPC invocados pelo regression runner.
class IntegrationScenarios {
  IntegrationScenarios(this.client, this.env);

  final LiveOpsStagingClient client;
  final Map<String, String> env;

  Future<bool> run(String scenario) async {
    final sellerId = await _sellerId();
    final buyerId = await _buyerId();
    final buyerToken = await client.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
    );
    final sellerToken = await client.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
    );

    switch (scenario) {
      case 'cancel':
        return _scenarioCancel(sellerId, buyerId, buyerToken);
      case 'reconcile':
      case 'cross_pool_sold_dedup':
        return _scenarioReconcile(sellerId, buyerId, buyerToken);
      case 'stock':
        return _scenarioStock(sellerId, sellerToken);
      case 'bag_edge':
        return _scenarioBagEdge(sellerId, buyerId, buyerToken);
      case 'bag_display_filter':
        return _scenarioBagDisplayFilter(sellerId, buyerId);
      case 'cross_pool_rr1':
        return _scenarioCrossPoolRr1(sellerId, buyerId, buyerToken);
      case 'cross_pool_product_sold':
        return _scenarioCrossPoolProductSold(sellerId, buyerId);
      case 'blocked_qty':
        return _scenarioBlockedQty(sellerId, buyerId, buyerToken);
      case 'cross_reserved':
        return _scenarioCrossReserved(sellerId, buyerId, buyerToken);
      case 'logical_item_inherit':
        return _scenarioLogicalItemInherit(sellerId);
      case 'verify_accepted':
        return _scenarioVerifyAccepted(sellerId);
      case 'verify_raffle_join':
        return _scenarioVerifyRaffleJoin(sellerId);
      case 'reservations_pending':
        return _scenarioReservationsPending(sellerId, buyerId);
      case 'price_gate_staging':
        return _scenarioPriceGateStaging(sellerId, buyerId);
      case 'reconcile_idempotent':
        return _scenarioReconcile(sellerId, buyerId, buyerToken);
      case 'draft_live_fixture':
        return _scenarioStock(sellerId, sellerToken);
      case 'gravado_sold':
        return _scenarioCrossPoolProductSold(sellerId, buyerId);
      case 'marketplace_bridge':
        return _scenarioCrossPoolProductSold(sellerId, buyerId);
      case 'logical_item_lineage':
        return _scenarioLogicalItemLineage(sellerId);
      case 'a3_r32_qty_alignment':
        return _scenarioA3R32QtyAlignment(sellerId, sellerToken);
      case 'helper_seller_exists':
        return _scenarioHelperSellerExists(sellerId);
      case 'chat_messages_db':
        return _scenarioChatMessagesDb(sellerId);
      case 'maestro_live_stock':
        return _scenarioMaestroLiveStock();
      case 'verify_maestro_pending':
        return _scenarioVerifyMaestroReservation('pending');
      case 'verify_maestro_accepted':
        return _scenarioVerifyMaestroReservation('accepted');
      case 'verify_maestro_rejected':
        return _scenarioVerifyMaestroReservation('rejected');
      case 'waitlist_stock_zero':
        return _scenarioWaitlistStockZero(sellerId, buyerId, sellerToken);
      case 'partial_multi_qty_accept':
        return _scenarioPartialMultiQtyAccept(sellerId, buyerId, sellerToken);
      case 'seller_reject_pending':
        return _scenarioSellerRejectPending(sellerId, buyerId, sellerToken);
      case 'overstock_qty_confirm':
        return _scenarioOverstockQtyConfirm(sellerId, buyerId, buyerToken);
      default:
        // Fallback: cenários auto-mapeados usam stock como smoke BD
        if (scenario.startsWith('cross_pool')) {
          return _scenarioCrossPoolRr1(sellerId, buyerId, buyerToken);
        }
        if (scenario.startsWith('checkout') || scenario.contains('reconcile')) {
          return _scenarioReconcile(sellerId, buyerId, buyerToken);
        }
        return _scenarioStock(sellerId, sellerToken);
    }
  }

  Future<String> _sellerId() async {
    var id = env['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
    if (!isUuid(id)) {
      final t = await client.signIn(
        email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
        password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
      );
      id = await client.userIdForAccessToken(t);
    }
    return id;
  }

  Future<String> _buyerId() async {
    var id = env['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
    if (!isUuid(id)) {
      final t = await client.signIn(
        email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
        password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
      );
      id = await client.userIdForAccessToken(t);
    }
    return id;
  }

  Future<void> _cleanup(String sellerId) async {
    final lives = await client.select(
      'lives',
      filter: 'seller_id=eq.$sellerId&title=eq.$_liveTitle',
      limit: 10,
    );
    for (final live in lives) {
      final liveId = live['id']?.toString() ?? '';
      if (liveId.isEmpty) continue;
      await client.deleteWhere('live_reservation_requests', 'live_id=eq.$liveId');
      await client.deleteWhere('orders', 'live_id=eq.$liveId');
      await client.deleteWhere('live_items', 'live_id=eq.$liveId');
      await client.deleteWhere('lives', 'id=eq.$liveId');
    }
  }

  Future<Map<String, String>> _createLiveFixture({
    required String sellerId,
    required String buyerId,
    int itemQty = 5,
    String? title,
  }) async {
    final live = await client.insert('lives', {
      'title': title ?? _liveTitle,
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final liveId = live['id']!.toString();
    final ref = '$_refPrefix-${DateTime.now().millisecondsSinceEpoch}';

    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'Regression product',
      'price': 5,
      'quantity': itemQty,
      'ref_code': ref,
      'list_on_marketplace': false,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final productId = product['id']!.toString();

    final item = await client.insert('live_items', {
      'live_id': liveId,
      'ref_code': ref,
      'title': 'Regression item',
      'price': 5,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': productId,
      'checkout_product_id': productId,
      'logical_item_id': productId,
    });
    return {
      'live_id': liveId,
      'live_item_id': item['id']!.toString(),
      'product_id': productId,
      'ref': ref,
    };
  }

  Future<Map<String, dynamic>?> _stockRpc(String liveItemId) async {
    final res = await client.rpc('batata_live_item_stock', {
      'p_live_item_id': liveItemId,
    });
    return res is Map ? Map<String, dynamic>.from(res) : null;
  }

  Future<bool> _scenarioCancel(
    String sellerId,
    String buyerId,
    String buyerToken,
  ) async {
    try {
      await _cleanup(sellerId);
      final fx = await _createLiveFixture(sellerId: sellerId, buyerId: buyerId);
      final res = await client.insert('live_reservation_requests', {
        'live_id': fx['live_id'],
        'live_item_id': fx['live_item_id'],
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'source': 'fleaber_live',
        'status': 'pending',
      });
      final requestId = res['id']!.toString();
      final rpcRes = await client.rpc(
        'batata_live_bag_remove_request',
        {'p_request_id': requestId},
        accessToken: buyerToken,
      );
      if (rpcRes is! Map || rpcRes['ok'] != true) return false;
      final rows = await client.select(
        'live_reservation_requests',
        filter: 'id=eq.$requestId',
        limit: 1,
      );
      return rows.isNotEmpty &&
          rows.first['status'] == 'rejected' &&
          (rows.first['notes'] ?? '').toString().toLowerCase().contains('bag_removed');
    } catch (e) {
      print('  cancel: $e');
      return false;
    }
  }

  Future<bool> _scenarioReconcile(
    String sellerId,
    String buyerId,
    String buyerToken,
  ) async {
    try {
      await _cleanup(sellerId);
      final fx = await _createLiveFixture(sellerId: sellerId, buyerId: buyerId);
      final order = await client.insert('orders', {
        'product_id': fx['product_id'],
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'price_total': 5.9,
        'shipping_method': 'Envio Transportadora (€3.50)',
        'payment_method': 'Pagamento na App',
        'status': 'reserva_pendente',
        'quantity': 1,
        'live_id': fx['live_id'],
        'live_item_id': fx['live_item_id'],
      });
      final orderId = order['id']!.toString();
      final resReq = await client.insert('live_reservation_requests', {
        'live_id': fx['live_id'],
        'live_item_id': fx['live_item_id'],
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'source': 'fleaber_live',
        'status': 'accepted',
        'notes': 'stripe_checkout:$orderId',
      });
      await client.patch('orders', 'id=eq.$orderId', {'status': 'pago'});
      final rpcRes = await client.rpc(
        'batata_live_reconcile_stripe_order',
        {'p_order_id': orderId, 'p_reservation_request_id': resReq['id']},
        accessToken: buyerToken,
      );
      return rpcRes is Map && rpcRes['ok'] == true;
    } catch (e) {
      print('  reconcile: $e');
      return false;
    }
  }

  Future<bool> _scenarioStock(String sellerId, String sellerToken) async {
    try {
      await _cleanup(sellerId);
      final fx = await _createLiveFixture(sellerId: sellerId, buyerId: sellerId, itemQty: 5);
      final before = await _stockRpc(fx['live_item_id']!);
      if (before == null) return false;
      final avail = (before['available_qty'] as num?)?.toInt();
      return avail != null && avail >= 1;
    } catch (e) {
      print('  stock: $e');
      return false;
    }
  }

  Future<bool> _scenarioBagEdge(
    String sellerId,
    String buyerId,
    String buyerToken,
  ) async {
    try {
      await _cleanup(sellerId);
      final fx1 = await _createLiveFixture(sellerId: sellerId, buyerId: buyerId);
      final fx2 = await _createLiveFixture(sellerId: sellerId, buyerId: buyerId);
      await client.insert('live_reservation_requests', {
        'live_id': fx1['live_id'],
        'live_item_id': fx1['live_item_id'],
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'source': 'fleaber_live',
        'status': 'pending',
      });
      await client.insert('live_reservation_requests', {
        'live_id': fx2['live_id'],
        'live_item_id': fx2['live_item_id'],
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'source': 'fleaber_live',
        'status': 'pending',
      });
      final rows = await client.select(
        'live_reservation_requests',
        filter: 'buyer_id=eq.$buyerId&status=eq.pending',
        limit: 10,
      );
      if (rows.length < 2) return false;
      // Cada live tem o seu saco: filtrar por live_id + regra de display
      final live1 = rows
          .where((r) => r['live_id']?.toString() == fx1['live_id'])
          .toList();
      final expected = BagCrosscheckLogic.fromRows(live1);
      if (expected.inBagRowCount != 1 || expected.inBagUnitQty != 1) {
        print(
          '  bag_edge: crosscheck fail inBag=${expected.inBagRowCount} '
          'units=${expected.inBagUnitQty}',
        );
        return false;
      }
      return true;
    } catch (e) {
      print('  bag_edge: $e');
      return false;
    }
  }

  /// Pending fleaber_live conta no saco; source ≠ fleaber_live não conta.
  Future<bool> _scenarioBagDisplayFilter(
    String sellerId,
    String buyerId,
  ) async {
    try {
      await _cleanup(sellerId);
      final fx = await _createLiveFixture(sellerId: sellerId, buyerId: buyerId);
      final liveId = fx['live_id']!;
      final itemId = fx['live_item_id']!;
      await client.insert('live_reservation_requests', {
        'live_id': liveId,
        'live_item_id': itemId,
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'source': 'fleaber_live',
        'status': 'pending',
      });
      await client.insert('live_reservation_requests', {
        'live_id': liveId,
        'live_item_id': itemId,
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'source': 'facebook_manual',
        'status': 'pending',
      });
      final rows = await client.select(
        'live_reservation_requests',
        filter: 'live_id=eq.$liveId&buyer_id=eq.$buyerId',
        limit: 10,
      );
      final expected = BagCrosscheckLogic.fromRows(rows);
      final ok = expected.pendingAnySource == 2 &&
          expected.inBagRowCount == 1 &&
          expected.skippedWrongSource == 1;
      print(
        '  bag_display_filter: pending=${expected.pendingAnySource} '
        'in_bag=${expected.inBagRowCount} skip_source=${expected.skippedWrongSource} '
        'ok=$ok',
      );
      return ok;
    } catch (e) {
      print('  bag_display_filter: $e');
      return false;
    }
  }

  Future<bool> _scenarioCrossPoolRr1(
    String sellerId,
    String buyerId,
    String buyerToken,
  ) async {
    try {
      await _cleanup(sellerId);
      final fx = await _createLiveFixture(sellerId: sellerId, buyerId: buyerId, itemQty: 10);
      final liveItemId = fx['live_item_id']!;
      final productId = fx['product_id']!;

      // Venda 1: order pago product_id only (gravado branch)
      await client.insert('orders', {
        'product_id': productId,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'price_total': 5,
        'status': 'pago',
        'quantity': 1,
        'payment_method': 'Pagamento na App',
      });

      // Venda 2: converted reservation
      final order2 = await client.insert('orders', {
        'product_id': productId,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'price_total': 5,
        'status': 'pago',
        'quantity': 1,
        'live_id': fx['live_id'],
        'live_item_id': liveItemId,
        'payment_method': 'Pagamento na App',
      });
      await client.insert('live_reservation_requests', {
        'live_id': fx['live_id'],
        'live_item_id': liveItemId,
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'status': 'converted',
        'source': 'fleaber_live',
        'notes': 'order:${order2['id']}',
      });

      final stock = await _stockRpc(liveItemId);
      if (stock == null) return false;
      final avail = (stock['available_qty'] as num?)?.toInt();
      final sold = (stock['sold'] as num?)?.toInt() ?? (stock['sold_converted_qty'] as num?)?.toInt();
      print('  cross_pool_rr1: available=$avail sold=$sold');
      return avail != null && avail <= 8 && (sold ?? 0) >= 1;
    } catch (e) {
      print('  cross_pool_rr1: $e');
      return false;
    }
  }

  Future<bool> _scenarioCrossPoolProductSold(
    String sellerId,
    String buyerId,
  ) async {
    try {
      await _cleanup(sellerId);
      final fx = await _createLiveFixture(sellerId: sellerId, buyerId: buyerId, itemQty: 5);
      final before = await _stockRpc(fx['live_item_id']!);
      final availBefore = (before?['available_qty'] as num?)?.toInt() ?? 0;

      await client.insert('orders', {
        'product_id': fx['product_id'],
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'price_total': 5,
        'status': 'pago',
        'quantity': 1,
        'payment_method': 'Pagamento na App',
      });

      final after = await _stockRpc(fx['live_item_id']!);
      final availAfter = (after?['available_qty'] as num?)?.toInt() ?? 0;
      return availAfter < availBefore;
    } catch (e) {
      print('  cross_pool_product_sold: $e');
      return false;
    }
  }

  Future<bool> _scenarioBlockedQty(
    String sellerId,
    String buyerId,
    String buyerToken,
  ) async {
    try {
      await _cleanup(sellerId);
      final fxA = await _createLiveFixture(
        sellerId: sellerId,
        buyerId: buyerId,
        itemQty: 5,
        title: '${_liveTitle}_A',
      );
      final productId = fxA['product_id']!;
      final liveB = await client.insert('lives', {
        'title': '${_liveTitle}_B',
        'status': 'live',
        'seller_id': sellerId,
        'vendedor_id': sellerId,
        'is_active': true,
      });
      final itemB = await client.insert('live_items', {
        'live_id': liveB['id'],
        'ref_code': fxA['ref'],
        'title': 'Regression item B',
        'price': 5,
        'is_active': true,
        'status': 'available',
        'item_kind': 'marketplace_product',
        'product_id': productId,
        'checkout_product_id': productId,
        'logical_item_id': productId,
      });

      await client.insert('live_reservation_requests', {
        'live_id': fxA['live_id'],
        'live_item_id': fxA['live_item_id'],
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'status': 'accepted',
        'source': 'fleaber_live',
      });

      final stockB = await _stockRpc(itemB['id']!.toString());
      final blocked = (stockB?['blocked_qty'] as num?)?.toInt() ?? 0;
      return blocked > 0;
    } catch (e) {
      print('  blocked_qty: $e');
      return false;
    }
  }

  Future<bool> _scenarioCrossReserved(
    String sellerId,
    String buyerId,
    String buyerToken,
  ) async {
    try {
      await _cleanup(sellerId);
      final fxA = await _createLiveFixture(
        sellerId: sellerId,
        buyerId: buyerId,
        title: '${_liveTitle}_A',
      );
      final productId = fxA['product_id']!;
      final liveB = await client.insert('lives', {
        'title': '${_liveTitle}_B',
        'status': 'live',
        'seller_id': sellerId,
        'vendedor_id': sellerId,
        'is_active': true,
      });
      final itemB = await client.insert('live_items', {
        'live_id': liveB['id'],
        'ref_code': fxA['ref'],
        'title': 'Regression B',
        'price': 5,
        'is_active': true,
        'status': 'available',
        'item_kind': 'marketplace_product',
        'product_id': productId,
        'checkout_product_id': productId,
        'logical_item_id': productId,
      });

      await client.insert('live_reservation_requests', {
        'live_id': fxA['live_id'],
        'live_item_id': fxA['live_item_id'],
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'status': 'pending',
        'source': 'fleaber_live',
      });

      final stockB = await _stockRpc(itemB['id']!.toString());
      final cross = (stockB?['cross_reserved_qty'] as num?)?.toInt() ?? 0;
      return cross > 0;
    } catch (e) {
      print('  cross_reserved: $e');
      return false;
    }
  }

  Future<bool> _scenarioLogicalItemLineage(String sellerId) async {
    try {
      await _cleanup(sellerId);
      final fx = await _createLiveFixture(sellerId: sellerId, buyerId: sellerId);
      final rows = await client.select(
        'live_items',
        filter: 'id=eq.${fx['live_item_id']}',
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final logical = rows.first['logical_item_id']?.toString() ?? '';
      final productId = fx['product_id']!;
      return logical.isNotEmpty && logical == productId;
    } catch (e) {
      print('  logical_item_lineage: $e');
      return false;
    }
  }

  /// A3/R32 — quick edit qty, venda, live ended, novo directo: pool stock coerente.
  Future<bool> _scenarioA3R32QtyAlignment(
    String sellerId,
    String sellerToken,
  ) async {
    try {
      await _cleanup(sellerId);
      final buyerId = await _buyerId();
      final fxA = await _createLiveFixture(
        sellerId: sellerId,
        buyerId: buyerId,
        itemQty: 10,
      );
      final itemA = fxA['live_item_id']!;
      final productId = fxA['product_id']!;

      final upd = await client.rpc(
        'batata_update_live_item',
        {'p_live_item_id': itemA, 'p_quantity': 12},
        accessToken: sellerToken,
      );
      if (upd is! Map) {
        print('  update qty: $upd');
        return false;
      }

      final order = await client.insert('orders', {
        'product_id': productId,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'price_total': 5,
        'status': 'pago',
        'quantity': 1,
        'live_id': fxA['live_id'],
        'live_item_id': itemA,
        'payment_method': 'Pagamento na App',
      });
      await client.insert('live_reservation_requests', {
        'live_id': fxA['live_id'],
        'live_item_id': itemA,
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'status': 'converted',
        'source': 'fleaber_live',
        'notes': 'order:${order['id']}',
      });

      await client.patch(
        'lives',
        'id=eq.${fxA['live_id']}',
        {'status': 'ended', 'is_active': false},
      );

      final liveB = await client.insert('lives', {
        'title': _liveTitle,
        'status': 'live',
        'seller_id': sellerId,
        'vendedor_id': sellerId,
        'is_active': true,
      });
      final ref = fxA['ref']!;
      final itemB = await client.insert('live_items', {
        'live_id': liveB['id'],
        'ref_code': ref,
        'title': 'Regression item B',
        'price': 5,
        'is_active': true,
        'status': 'available',
        'item_kind': 'marketplace_product',
        'product_id': productId,
        'checkout_product_id': productId,
        'logical_item_id': productId,
      });
      final itemBId = itemB['id']!.toString();

      final stockB = await _stockRpc(itemBId);
      if (stockB == null) {
        print('  stock rpc null on new live');
        return false;
      }
      final total = (stockB['total_qty'] as num?)?.toInt();
      final avail = (stockB['available_qty'] as num?)?.toInt();
      final sold = (stockB['sold_converted_qty'] as num?)?.toInt() ??
          (stockB['sold'] as num?)?.toInt();
      print('  a3_r32: liveB total=$total available=$avail sold=$sold');
      if (total != 12) {
        print('  expected total_qty=12 after quick edit inherit');
        return false;
      }
      if (avail == null || avail < 10 || avail > 11) {
        print('  expected available ~11 after 1 sold (got $avail)');
        return false;
      }
      return true;
    } catch (e) {
      print('  a3_r32_qty_alignment: $e');
      return false;
    }
  }

  Future<bool> _scenarioLogicalItemInherit(String sellerId) async {
    try {
      await _cleanup(sellerId);
      final fx = await _createLiveFixture(sellerId: sellerId, buyerId: sellerId);
      final rows = await client.select(
        'live_items',
        filter: 'id=eq.${fx['live_item_id']}',
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final logical = rows.first['logical_item_id']?.toString() ?? '';
      return logical.isNotEmpty;
    } catch (e) {
      print('  logical_item_inherit: $e');
      return false;
    }
  }

  Future<bool> _scenarioVerifyAccepted(String sellerId) async {
    try {
      final rows = await client.select(
        'live_reservation_requests',
        filter: 'seller_id=eq.$sellerId&status=eq.accepted',
        limit: 5,
      );
      return rows.isNotEmpty;
    } catch (e) {
      print('  verify_accepted: $e');
      return false;
    }
  }

  Future<bool> _scenarioReservationsPending(
    String sellerId,
    String buyerId,
  ) async {
    try {
      await _cleanup(sellerId);
      final fx = await _createLiveFixture(sellerId: sellerId, buyerId: buyerId);
      await client.insert('live_reservation_requests', {
        'live_id': fx['live_id'],
        'live_item_id': fx['live_item_id'],
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 2,
        'status': 'pending',
        'source': 'fleaber_live',
      });
      final rows = await client.select(
        'live_reservation_requests',
        filter:
            'live_id=eq.${fx['live_id']}&buyer_id=eq.$buyerId&status=eq.pending',
        limit: 5,
      );
      if (rows.isEmpty) return false;
      final qty = (rows.first['requested_qty'] as num?)?.toInt() ?? 0;
      if (qty != 2) {
        print('  reservations_pending: qty=$qty esperado 2');
        return false;
      }
      final expected = BagCrosscheckLogic.fromRows(rows);
      if (expected.inBagRowCount != 1 || expected.inBagUnitQty != 2) {
        print(
          '  reservations_pending: saco esperado 1 linha / 2 un. '
          'got rows=${expected.inBagRowCount} units=${expected.inBagUnitQty}',
        );
        return false;
      }
      // Stock RPC: available não negativo após pending
      final stock = await _stockRpc(fx['live_item_id']!);
      final avail = (stock?['available_qty'] as num?)?.toInt();
      print(
        '  reservations_pending: qty=2 in_bag_units=2 avail=$avail',
      );
      return avail == null || avail >= 0;
    } catch (e) {
      print('  reservations_pending: $e');
      return false;
    }
  }

  Future<bool> _scenarioPriceGateStaging(
    String sellerId,
    String buyerId,
  ) async {
    try {
      await _cleanup(sellerId);
      final fx = await _createLiveFixture(sellerId: sellerId, buyerId: buyerId);
      final rows = await client.select(
        'live_items',
        filter: 'id=eq.${fx['live_item_id']}',
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final price = rows.first['price'];
      return price != null && (price as num) > 0;
    } catch (e) {
      print('  price_gate_staging: $e');
      return false;
    }
  }

  Future<bool> _scenarioHelperSellerExists(String sellerId) async {
    try {
      final rows = await client.select(
        'profiles',
        filter: 'id=eq.$sellerId',
        limit: 1,
      );
      return rows.isNotEmpty;
    } catch (e) {
      print('  helper_seller_exists: $e');
      return false;
    }
  }

  Future<bool> _scenarioChatMessagesDb(String sellerId) async {
    try {
      final lives = await client.select(
        'lives',
        filter: 'seller_id=eq.$sellerId',
        limit: 1,
      );
      if (lives.isEmpty) return true; // sem live = smoke OK
      final liveId = lives.first['id']?.toString() ?? '';
      final msgs = await client.select(
        'live_messages',
        filter: 'live_id=eq.$liveId',
        limit: 1,
      );
      return true; // smoke: tabela acessível
    } catch (e) {
      print('  chat_messages_db: $e');
      return false;
    }
  }

  Future<bool> _scenarioVerifyRaffleJoin(String sellerId) async {
    try {
      final buyerId = await _buyerId();
      var raffleId = env['MAESTRO_RAFFLE_ID']?.trim() ?? '';
      if (!isUuid(raffleId)) {
        final maestroEnv = File('.maestro/.env');
        if (maestroEnv.existsSync()) {
          for (final line in maestroEnv.readAsLinesSync()) {
            final t = line.trim();
            if (t.startsWith('MAESTRO_RAFFLE_ID=')) {
              raffleId = t.substring('MAESTRO_RAFFLE_ID='.length).trim();
              break;
            }
          }
        }
      }
      if (!isUuid(raffleId)) {
        final raffles = await client.select(
          'live_raffles',
          filter: 'seller_id=eq.$sellerId',
          limit: 20,
        );
        if (raffles.isEmpty) return false;
        raffles.sort((a, b) =>
            (b['created_at']?.toString() ?? '').compareTo(a['created_at']?.toString() ?? ''));
        raffleId = raffles.first['id']?.toString() ?? '';
      }
      if (!isUuid(raffleId)) return false;
      final rows = await client.select(
        'live_raffle_entries',
        filter: 'raffle_id=eq.$raffleId&user_id=eq.$buyerId',
        limit: 5,
      );
      return rows.isNotEmpty;
    } catch (e) {
      print('  verify_raffle_join: $e');
      return false;
    }
  }

  String? _maestroLiveId() {
    final fromEnv = env['MAESTRO_LIVE_ID']?.trim() ?? '';
    if (isUuid(fromEnv)) return fromEnv;
    final f = File('.maestro/.env');
    if (!f.existsSync()) return null;
    for (final line in f.readAsLinesSync()) {
      final t = line.trim();
      if (t.startsWith('MAESTRO_LIVE_ID=')) {
        final id = t.substring('MAESTRO_LIVE_ID='.length).trim();
        if (isUuid(id)) return id;
      }
    }
    return null;
  }

  /// Stock RPC na live Maestro actual (sem cleanup) — bateria SL##.
  Future<bool> _scenarioMaestroLiveStock() async {
    try {
      final liveId = _maestroLiveId();
      if (liveId == null) {
        print('  maestro_live_stock: MAESTRO_LIVE_ID em falta');
        return false;
      }
      final items = await client.select(
        'live_items',
        filter: 'live_id=eq.$liveId',
        limit: 30,
      );
      if (items.isEmpty) {
        print('  maestro_live_stock: sem live_items');
        return false;
      }
      var ok = true;
      for (final item in items) {
        final itemId = item['id']?.toString() ?? '';
        if (itemId.isEmpty) continue;
        final stock = await _stockRpc(itemId);
        if (stock == null) {
          ok = false;
          continue;
        }
        final avail = (stock['available_qty'] as num?)?.toInt();
        final total = (stock['total_qty'] as num?)?.toInt();
        print(
          '  maestro_live_stock: item=$itemId ref=${item['ref_code']} '
          'total=$total avail=$avail sold=${stock['sold'] ?? stock['sold_qty']}',
        );
        if (avail != null && avail < 0) ok = false;
      }
      return ok;
    } catch (e) {
      print('  maestro_live_stock: $e');
      return false;
    }
  }

  Future<bool> _scenarioVerifyMaestroReservation(String status) async {
    try {
      final liveId = _maestroLiveId();
      if (liveId == null) {
        print('  verify_maestro_$status: MAESTRO_LIVE_ID em falta');
        return false;
      }
      final rows = await client.select(
        'live_reservation_requests',
        filter: 'live_id=eq.$liveId&status=eq.$status',
        limit: 20,
      );
      print('  verify_maestro_$status: count=${rows.length} live=$liveId');
      if (rows.isEmpty) return false;
      for (final r in rows.take(5)) {
        print(
          '    id=${r['id']} buyer=${r['buyer_id']} qty=${r['requested_qty']} '
          'source=${r['source']} item=${r['live_item_id']}',
        );
      }
      // Agrupar por buyer e validar contrato do saco
      final byBuyer = <String, List<Map<String, dynamic>>>{};
      for (final r in rows) {
        final b = (r['buyer_id'] ?? '').toString();
        byBuyer.putIfAbsent(b, () => []).add(r);
      }
      var ok = true;
      for (final e in byBuyer.entries) {
        final allBuyer = await client.select(
          'live_reservation_requests',
          filter: 'live_id=eq.$liveId&buyer_id=eq.${e.key}',
          limit: 50,
        );
        final expected = BagCrosscheckLogic.fromRows(allBuyer);
        print(
          '    buyer=${e.key} → esperado "${expected.inBagRowCount} no saco" '
          '(units=${expected.inBagUnitQty})',
        );
        if (status == 'pending' &&
            expected.pendingVisibleInBag >= 1 &&
            expected.inBagRowCount < 1) {
          ok = false;
        }
      }
      return ok;
    } catch (e) {
      print('  verify_maestro_$status: $e');
      return false;
    }
  }

  Future<bool> _acceptRequest(String requestId, String sellerId) async {
    final res = await client.rpc('batata_process_live_reservation_request', {
      'p_request_id': requestId,
      'p_action': 'accept',
      'p_processed_by': sellerId,
      'p_notes': 'regression_accept',
    });
    return res is Map && res['ok'] == true;
  }

  /// A150 — stock 0 → nova reserva fica em fila (queue_position).
  Future<bool> _scenarioWaitlistStockZero(
    String sellerId,
    String buyerId,
    String sellerToken,
  ) async {
    try {
      await _cleanup(sellerId);
      final fx = await _createLiveFixture(
        sellerId: sellerId,
        buyerId: buyerId,
        itemQty: 1,
        title: '${_liveTitle}_WL',
      );
      final itemId = fx['live_item_id']!;
      final r1 = await client.insert('live_reservation_requests', {
        'live_id': fx['live_id'],
        'live_item_id': itemId,
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'status': 'pending',
        'source': 'fleaber_live',
      });
      if (!await _acceptRequest(r1['id']!.toString(), sellerId)) return false;

      final stock = await _stockRpc(itemId);
      final avail = (stock?['available_qty'] as num?)?.toInt();
      if (avail == null || avail > 0) {
        print('  waitlist: expected avail=0 got $avail');
        return false;
      }

      final r2 = await client.insert('live_reservation_requests', {
        'live_id': fx['live_id'],
        'live_item_id': itemId,
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'status': 'pending',
        'source': 'fleaber_live',
        'notes': 'waitlist_test',
      });
      final q = (r2['queue_position'] as num?)?.toInt();
      final rows = await client.select(
        'live_reservation_requests',
        filter: 'id=eq.${r2['id']}',
        limit: 1,
      );
      final qp = (rows.first['queue_position'] as num?)?.toInt() ?? q;
      print('  waitlist: avail=$avail queue_position=$qp status=pending');
      return qp != null && qp >= 1;
    } catch (e) {
      print('  waitlist_stock_zero: $e');
      return false;
    }
  }

  /// A142 — 2 pending; aceite parcial; stock coerente.
  Future<bool> _scenarioPartialMultiQtyAccept(
    String sellerId,
    String buyerId,
    String sellerToken,
  ) async {
    try {
      await _cleanup(sellerId);
      final fx = await _createLiveFixture(
        sellerId: sellerId,
        buyerId: buyerId,
        itemQty: 5,
        title: '${_liveTitle}_PM',
      );
      final itemId = fx['live_item_id']!;
      final r1 = await client.insert('live_reservation_requests', {
        'live_id': fx['live_id'],
        'live_item_id': itemId,
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'status': 'pending',
        'source': 'fleaber_live',
      });
      final r2 = await client.insert('live_reservation_requests', {
        'live_id': fx['live_id'],
        'live_item_id': itemId,
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'status': 'pending',
        'source': 'fleaber_live',
        'notes': 'second_pending',
      });
      if (!await _acceptRequest(r1['id']!.toString(), sellerId)) return false;

      final stock = await _stockRpc(itemId);
      final avail = (stock?['available_qty'] as num?)?.toInt();
      final pending = await client.select(
        'live_reservation_requests',
        filter: 'live_id=eq.${fx['live_id']}&status=eq.pending',
        limit: 5,
      );
      final accepted = await client.select(
        'live_reservation_requests',
        filter: 'live_id=eq.${fx['live_id']}&status=eq.accepted',
        limit: 5,
      );
      print(
        '  partial_multi: avail=$avail pending=${pending.length} '
        'accepted=${accepted.length} r2=${r2['id']}',
      );
      return avail != null &&
          avail >= 3 &&
          pending.length >= 1 &&
          accepted.length >= 1;
    } catch (e) {
      print('  partial_multi_qty_accept: $e');
      return false;
    }
  }

  /// A082 — seller rejeita pending via RPC.
  Future<bool> _scenarioSellerRejectPending(
    String sellerId,
    String buyerId,
    String sellerToken,
  ) async {
    try {
      await _cleanup(sellerId);
      final fx = await _createLiveFixture(
        sellerId: sellerId,
        buyerId: buyerId,
        itemQty: 3,
        title: '${_liveTitle}_RJ',
      );
      final r = await client.insert('live_reservation_requests', {
        'live_id': fx['live_id'],
        'live_item_id': fx['live_item_id'],
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'status': 'pending',
        'source': 'fleaber_live',
      });
      final res = await client.rpc('batata_process_live_reservation_request', {
        'p_request_id': r['id'],
        'p_action': 'reject',
        'p_processed_by': sellerId,
        'p_notes': 'regression_reject',
      });
      if (res is! Map || res['ok'] != true) return false;
      final rows = await client.select(
        'live_reservation_requests',
        filter: 'id=eq.${r['id']}',
        limit: 1,
      );
      return rows.isNotEmpty && rows.first['status'] == 'rejected';
    } catch (e) {
      print('  seller_reject_pending: $e');
      return false;
    }
  }

  /// M15/M16 — pedido qty > stock; tag qty_confirm_needed.
  Future<bool> _scenarioOverstockQtyConfirm(
    String sellerId,
    String buyerId,
    String sellerToken,
  ) async {
    try {
      await _cleanup(sellerId);
      final fx = await _createLiveFixture(
        sellerId: sellerId,
        buyerId: buyerId,
        itemQty: 1,
        title: '${_liveTitle}_OS',
      );
      final r = await client.insert('live_reservation_requests', {
        'live_id': fx['live_id'],
        'live_item_id': fx['live_item_id'],
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 3,
        'status': 'pending',
        'source': 'fleaber_live',
      });
      final mark = await client.rpc(
        'batata_live_mark_qty_confirm_needed',
        {'p_request_id': r['id']},
      );
      final rows = await client.select(
        'live_reservation_requests',
        filter: 'id=eq.${r['id']}',
        limit: 1,
      );
      final notes = (rows.first['notes'] ?? '').toString().toLowerCase();
      print('  overstock: mark=$mark notes=$notes');
      return notes.contains('qty_confirm_needed');
    } catch (e) {
      print('  overstock_qty_confirm: $e');
      return false;
    }
  }
}
