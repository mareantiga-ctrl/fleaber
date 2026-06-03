import 'dart:async';

import 'package:flutter/foundation.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/order_cancel_eligibility.dart';
import '/utils/fleaber_logger.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/seller_staff_service.dart';

enum LiveReservationSource { fleaberLive, facebookManual, helperManual }

extension on LiveReservationSource {
  String get value => switch (this) {
        LiveReservationSource.fleaberLive => 'fleaber_live',
        LiveReservationSource.facebookManual => 'facebook_manual',
        LiveReservationSource.helperManual => 'helper_manual',
      };
}

class LiveReservationQueueService {
  Future<LiveReservationRequestsRow?> createRequest({
    required String liveId,
    required String liveItemId,
    required String sellerId,
    String? buyerId,
    int requestedQty = 1,
    LiveReservationSource source = LiveReservationSource.fleaberLive,
    String? notes,
  }) async {
    final uid = currentUserUid.trim();
    if (uid.isEmpty) return null;

    final bid = (buyerId ?? uid).trim();

    var qty = requestedQty.clamp(1, 9999);
    final snap = await LiveCatalogStockService.fetch(liveItemId);
    if (snap != null && qty > snap.totalQty) {
      qty = snap.totalQty.clamp(1, 9999);
    }

    try {
      await LiveReservationRequestsTable().insert({
        'live_id': liveId,
        'live_item_id': liveItemId,
        'seller_id': sellerId,
        'buyer_id': bid,
        'requested_qty': qty,
        'source': source.value,
        'status': 'pending',
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      });
    } catch (e) {
      unawaited(
        FleaberLogger.instance.event('live.bag.create_request', {
          'live_id': liveId,
          'live_item_id': liveItemId,
          'requested_qty': qty,
          'total_qty': snap?.totalQty,
          'available_qty': snap?.availableQty,
          'ok': false,
          'error': e.toString(),
        }),
      );
      rethrow;
    }

    unawaited(
      FleaberLogger.instance.event('live.bag.create_request', {
        'live_id': liveId,
        'live_item_id': liveItemId,
        'requested_qty': qty,
        'total_qty': snap?.totalQty,
        'available_qty': snap?.availableQty,
        'ok': true,
      }),
    );

    final rows = await LiveReservationRequestsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('live_id', liveId)
          .eqOrNull('live_item_id', liveItemId)
          .eqOrNull('buyer_id', buyerId ?? uid)
          .order('created_at', ascending: false),
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>> processRequest({
    required String requestId,
    required String action, // accept/reject/skip/expire/convert
    String? notes,
  }) async {
    final res = await SupaFlow.client.rpc(
      'batata_process_live_reservation_request',
      params: {
        'p_request_id': requestId,
        'p_action': action,
        'p_processed_by': currentUserUid,
        'p_notes': notes,
      },
    );
    return Map<String, dynamic>.from(res as Map? ?? {});
  }

  Future<List<LiveReservationRequestsRow>> queueForLive({
    required String liveId,
    String? liveItemId,
    bool includeHistory = true,
  }) async {
    final trimmedLiveId = liveId.trim();
    if (trimmedLiveId.isEmpty) return const [];

    try {
      final res = await SupaFlow.client.rpc(
        'batata_live_reservation_queue_for_live',
        params: {
          'p_live_id': trimmedLiveId,
          'p_include_history': includeHistory,
        },
      );
      if (res is List) {
        final table = LiveReservationRequestsTable();
        var rows = res
            .map(
              (e) => table.createRow(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
        if (liveItemId != null && liveItemId.isNotEmpty) {
          final itemFilter = liveItemId.trim();
          rows = rows
              .where((r) => (r.liveItemId ?? '').trim() == itemFilter)
              .toList();
        }
        return rows;
      }
    } catch (e) {
      debugLog('queueForLive rpc fallback: $e');
    }

    return LiveReservationRequestsTable().queryRows(
      queryFn: (q) {
        var qq = q.eqOrNull('live_id', trimmedLiveId);
        if (liveItemId != null && liveItemId.isNotEmpty) {
          qq = qq.eqOrNull('live_item_id', liveItemId);
        }
        if (!includeHistory) {
          qq = qq.eqOrNull('status', 'pending');
        }
        return qq.order('created_at', ascending: true);
      },
      limit: 400,
    );
  }

  Future<List<LiveReservationRequestsRow>> buyerRequests({
    required String buyerId,
    int limit = 80,
  }) {
    return LiveReservationRequestsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('buyer_id', buyerId)
          .order('created_at', ascending: false),
      limit: limit,
    );
  }

  Future<List<LiveReservationRequestsRow>> liveBagRequests({
    required String liveId,
    required String buyerId,
    int limit = 120,
  }) {
    return LiveReservationRequestsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('live_id', liveId)
          .eqOrNull('buyer_id', buyerId)
          .eqOrNull('source', 'fleaber_live')
          .eqOrNull('status', 'pending')
          .order('created_at', ascending: false),
      limit: limit,
    );
  }

  /// Histórico completo do saco nesta live (sem janela temporal).
  /// Enquanto o directo/gravado existir, o comprador vê reservas e compras.
  Future<List<LiveReservationRequestsRow>> liveBagDisplayRequests({
    required String liveId,
    required String buyerId,
    int limit = 500,
  }) {
    return LiveReservationRequestsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('live_id', liveId)
          .eqOrNull('buyer_id', buyerId)
          .eqOrNull('source', 'fleaber_live')
          .order('created_at', ascending: false),
      limit: limit,
    );
  }

  /// Pedidos activos do comprador no mesmo artigo (pendente ou aceite).
  Future<int> countBuyerOpenReservationsOnItem({
    required String liveId,
    required String liveItemId,
    required String buyerId,
  }) async {
    final lid = liveId.trim();
    final iid = liveItemId.trim();
    final bid = buyerId.trim();
    if (lid.isEmpty || iid.isEmpty || bid.isEmpty) return 0;

    final rows = await LiveReservationRequestsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('live_id', lid)
          .eqOrNull('live_item_id', iid)
          .eqOrNull('buyer_id', bid)
          .inFilter('status', ['pending', 'accepted']),
      limit: 50,
    );
    return rows.length;
  }

  /// Posição na fila quando não há stock suficiente para esta posição.
  static bool isWaitlistPosition({
    required int? queuePosition,
    int? availableQty,
  }) {
    final pos = queuePosition;
    if (pos == null || pos < 1) return false;
    final avail = availableQty;
    if (avail == null) return pos > 1;
    if (avail < 1) return pos > 1;
    return pos > avail;
  }

  static String buyerReserveSnackMessage({
    required int priorOpenCount,
    required int? queuePosition,
    required bool waitlist,
    required bool othersWantItem,
  }) {
    final parts = <String>[];
    if (priorOpenCount > 0) {
      parts.add(
        'Já tinhas $priorOpenCount pedido(s) de reserva neste artigo.',
      );
    }
    final pos = queuePosition;
    if (waitlist && pos != null && pos > 0) {
      parts.add('Na lista de espera — posição $pos.');
    } else if (pos != null && pos > 0) {
      parts.add('Pedido enviado · posição $pos na fila.');
    } else {
      parts.add('Pedido de reserva enviado.');
    }
    if (othersWantItem) {
      parts.add('Mais pessoas também querem este artigo.');
    }
    return parts.join(' ');
  }

  static String buyerBagStatusLabel(
    String status, {
    String? notes,
    int? queuePosition,
    bool waitlist = false,
  }) {
    if (status == 'pending') {
      if (waitlist && queuePosition != null && queuePosition > 0) {
        return 'Lista de espera · posição $queuePosition';
      }
      if (queuePosition != null && queuePosition > 0) {
        return 'No saco · fila #$queuePosition';
      }
      return 'No saco';
    }
    return switch (status) {
      'converted' => 'Comprado ✓',
      'accepted' => 'Aceite · reservado 5 dias',
      'rejected' => buyerBagRejectedLabel(notes),
      'expired' => 'Expirado',
      _ => status,
    };
  }

  static String buyerBagRejectedLabel(String? notes) {
    final n = (notes ?? '').toLowerCase();
    if (n.contains('bag_removed') ||
        n.contains('bag_cancelled') ||
        n.contains('skip:')) {
      return 'Cancelado';
    }
    return 'Cancelado';
  }

  static bool buyerBagIsPending(String status) => status == 'pending';

  /// Reserva activa no saco (pendente ou já aceite pelo vendedor).
  static bool buyerBagIsActionable(String status) =>
      status == 'pending' || status == 'accepted';

  static bool isBuyerCancelledReservation({
    required String? status,
    String? notes,
  }) {
    final n = (notes ?? '').toLowerCase();
    if (n.contains('bag_removed') || n.contains('bag_cancelled')) {
      return true;
    }
    if (status != 'rejected') return false;
    return buyerBagRejectedLabel(notes) == 'Cancelado';
  }

  /// Vendedora pode aceitar/recusar (fila activa).
  static bool sellerCanActOnReservation({
    required String? status,
    String? notes,
  }) {
    if (isBuyerCancelledReservation(status: status, notes: notes)) {
      return false;
    }
    if (status == 'rejected' || status == 'expired' || status == 'converted') {
      return false;
    }
    return status == 'pending';
  }

  /// Reserva activa no painel do vendedor (exclui cancelamentos do comprador).
  static bool isActiveSellerReservation({
    required String? status,
    String? notes,
  }) {
    if (isBuyerCancelledReservation(status: status, notes: notes)) {
      return false;
    }
    return status == 'pending' ||
        status == 'accepted' ||
        status == 'converted';
  }

  static bool isAcceptedAwaitingPayment({
    required String? status,
    String? notes,
  }) =>
      status == 'accepted' &&
      !isBuyerCancelledReservation(status: status, notes: notes);

  /// Fila «a tratar» / pagamentos pendentes do vendedor (exclui cancelamentos).
  static bool isOpenSellerTreatReservation({
    required String? status,
    String? notes,
  }) {
    if (isBuyerCancelledReservation(status: status, notes: notes)) {
      return false;
    }
    if (status == 'rejected' || status == 'expired' || status == 'converted') {
      return false;
    }
    return status == 'pending' || isAcceptedAwaitingPayment(status: status, notes: notes);
  }

  /// Liga a encomenda Stripe a uma linha do saco (sem auto-aceitar — aceite é acção da vendedora).
  Future<void> ensureStripeCheckoutHold({
    required String liveId,
    required String liveItemId,
    required String sellerId,
    required String buyerId,
    required String orderId,
    String? reservationRequestId,
    bool tagAllActionableForItem = false,
  }) async {
    final lid = liveId.trim();
    final iid = liveItemId.trim();
    final sid = sellerId.trim();
    final bid = buyerId.trim();
    final oid = orderId.trim();
    final rid = reservationRequestId?.trim() ?? '';
    if (lid.isEmpty || iid.isEmpty || sid.isEmpty || bid.isEmpty) return;

    Future<void> tagCheckoutOrder(LiveReservationRequestsRow row) async {
      final id = row.id?.trim() ?? '';
      if (id.isEmpty) return;
      final noteTag = 'stripe_checkout:$oid';
      final notes = (row.notes ?? '').trim();
      if (!notes.contains(noteTag)) {
        await LiveReservationRequestsTable().update(
          data: {
            'notes': notes.isEmpty ? noteTag : '$notes | $noteTag',
          },
          matchingRows: (q) => q.eqOrNull('id', id),
        );
      }
    }

    Future<void> tagAllActionableRows() async {
      final rows = await LiveReservationRequestsTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('live_id', lid)
            .eqOrNull('live_item_id', iid)
            .eqOrNull('buyer_id', bid)
            .inFilter('status', ['pending', 'accepted'])
            .order('queue_position', ascending: true),
        limit: 30,
      );
      for (final row in rows) {
        if (LiveReservationQueueService.buyerBagIsActionable(row.status ?? '')) {
          await tagCheckoutOrder(row);
        }
      }
    }

    if (rid.isNotEmpty) {
      final rows = await LiveReservationRequestsTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', rid),
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final row = rows.first;
        if ((row.buyerId ?? '').trim() == bid &&
            (row.liveId ?? '').trim() == lid &&
            (row.liveItemId ?? '').trim() == iid &&
            LiveReservationQueueService.buyerBagIsActionable(row.status ?? '')) {
          await tagCheckoutOrder(row);
        }
      }
      if (tagAllActionableForItem) {
        await tagAllActionableRows();
      }
      return;
    }

    final byOrder = await LiveReservationRequestsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('live_id', lid)
          .eqOrNull('live_item_id', iid)
          .eqOrNull('buyer_id', bid)
          .inFilter('status', ['pending', 'accepted'])
          .order('queue_position', ascending: true),
      limit: 20,
    );
    final linked = byOrder
        .where((r) => (r.notes ?? '').contains('stripe_checkout:$oid'))
        .toList();
    if (linked.isNotEmpty) {
      if (tagAllActionableForItem) {
        await tagAllActionableRows();
      } else {
        await tagCheckoutOrder(linked.first);
      }
      return;
    }

    await createRequest(
      liveId: lid,
      liveItemId: iid,
      sellerId: sid,
      buyerId: bid,
      notes: 'stripe_checkout:$oid',
    );
  }

  /// Pagamento no saco: pendente ou aceite (aceite = reserva 5 dias pelo vendedor).
  static bool buyerCanPayBagReservation(String? status) =>
      buyerBagIsActionable(status ?? '');

  /// Converte a reserva ligada à encomenda Stripe (fallback se a edge não o fez).
  Future<Map<String, dynamic>> reconcileStripePaidOrder({
    required String orderId,
    String? reservationRequestId,
  }) async {
    final oid = orderId.trim();
    if (oid.isEmpty) return const {'ok': false, 'error': 'missing_order_id'};

    try {
      final params = <String, dynamic>{'p_order_id': oid};
      final rid = reservationRequestId?.trim() ?? '';
      if (rid.isNotEmpty) {
        params['p_reservation_request_id'] = rid;
      }
      final res = await SupaFlow.client.rpc(
        'batata_live_reconcile_stripe_order',
        params: params,
      );
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return {'ok': res == true};
    } catch (e) {
      debugPrint('[LiveReservation] reconcileStripePaidOrder: $e');
      return {'ok': false, 'error': e.toString()};
    }
  }

  static String? stripeCheckoutOrderIdFromNotes(String? notes) {
    final n = notes ?? '';
    final match = RegExp(
      r'stripe_checkout:([0-9a-fA-F-]{36})',
    ).firstMatch(n);
    return match?.group(1)?.trim();
  }

  /// Corrige reservas com checkout Stripe já pago mas ainda pending/accepted.
  Future<int> reconcileStalePaidReservationsForLive(String liveId) async {
    final lid = liveId.trim();
    if (lid.isEmpty) return 0;

    final rows = await LiveReservationRequestsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('live_id', lid)
          .inFilter('status', ['pending', 'accepted'])
          .like('notes', '%stripe_checkout:%'),
      limit: 80,
    );
    var fixed = 0;
    for (final r in rows) {
      final orderId = stripeCheckoutOrderIdFromNotes(r.notes);
      if (orderId == null || orderId.isEmpty) continue;
      final orders = await OrdersTable().querySingleRow(
        queryFn: (q) => q.eqOrNull('id', orderId),
      );
      if (orders.isEmpty) continue;
      if (normalizeOrderStatusKey(orders.first.status) != 'pago') continue;
      final res = await reconcileStripePaidOrder(
        orderId: orderId,
        reservationRequestId: r.id,
      );
      if (res['ok'] == true) fixed++;
    }
    return fixed;
  }

  Future<void> announcePurchaseBroadcast({
    required String liveId,
    required String buyerId,
    required String liveItemId,
  }) async {
    if (liveId.trim().isEmpty ||
        buyerId.trim().isEmpty ||
        liveItemId.trim().isEmpty) {
      return;
    }
    try {
      await SupaFlow.client.rpc(
        'batata_live_purchase_broadcast',
        params: {
          'p_live_id': liveId.trim(),
          'p_buyer_id': buyerId.trim(),
          'p_live_item_id': liveItemId.trim(),
        },
      );
    } catch (e) {
      debugPrint('[LiveReservation] announcePurchaseBroadcast: $e');
    }
  }

  Future<void> removeFromLiveBag({
    required String requestId,
  }) async {
    final res = await SupaFlow.client.rpc(
      'batata_live_bag_remove_request',
      params: {'p_request_id': requestId},
    );
    unawaited(
      FleaberLogger.instance.event('live.bag.remove_request', {
        'request_id': requestId,
        'result': res,
      }),
    );
  }

  Future<void> postSystemMessage({
    required String liveId,
    required String body,
    String? senderLabel,
  }) async {
    if (liveId.trim().isEmpty || body.trim().isEmpty) return;
    await SupaFlow.client.rpc(
      'batata_live_system_message',
      params: {
        'p_live_id': liveId,
        'p_body': body.trim(),
        'p_sender_label': senderLabel?.trim(),
      },
    );
  }

  Future<void> addManualRequest({
    required String liveId,
    required String liveItemId,
    required String sellerId,
    required String buyerLabel,
    required LiveReservationSource source,
    int qty = 1,
  }) async {
    final canManage = await SellerStaffContext.instance
        .serverCan('can_manage_reservations', sellerId: sellerId);
    if (!canManage && sellerId != currentUserUid) {
      throw Exception('Sem permissão para gerir reservas.');
    }
    await createRequest(
      liveId: liveId,
      liveItemId: liveItemId,
      sellerId: sellerId,
      buyerId: sellerId,
      requestedQty: qty,
      source: source,
      notes: 'manual:$buyerLabel',
    );
  }

  static String sourceLabel(String source) => switch (source) {
        'fleaber_live' => 'Fleaber',
        'facebook_manual' => 'Facebook',
        'helper_manual' => 'Helper',
        _ => source,
      };

  static String statusLabel(String status) => switch (status) {
        'pending' => 'Pendente',
        'accepted' => 'Aceite',
        'rejected' => 'Rejeitada',
        'expired' => 'Expirada',
        'converted' => 'Convertida',
        _ => status,
      };

  static bool statusIsFinal(String status) =>
      status == 'rejected' ||
      status == 'expired' ||
      status == 'converted';

  static void debugLog(String msg) {
    debugPrint('[LiveReservationQueue] $msg');
  }
}
