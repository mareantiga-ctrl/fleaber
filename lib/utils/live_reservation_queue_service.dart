import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/order_cancel_eligibility.dart';
import '/utils/fleaber_logger.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_in_stream_checkout.dart';
import '/utils/seller_staff_service.dart';
import '/widgets/live_vendor_ops_ui.dart';

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

    final qty = requestedQty.clamp(1, 9999);
    final snap = await LiveCatalogStockService.fetch(liveItemId);

    // Uma linha pendente por comprador/artigo: 2.ª reserva incrementa qty (R6).
    if (source == LiveReservationSource.fleaberLive) {
      final existing = await LiveReservationRequestsTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('live_id', liveId)
            .eqOrNull('live_item_id', liveItemId)
            .eqOrNull('buyer_id', bid)
            .eqOrNull('source', 'fleaber_live')
            .eqOrNull('status', 'pending'),
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final row = existing.first;
        final rid = row.id?.trim() ?? '';
        if (rid.isNotEmpty) {
          final nextQty = (row.requestedQty < 1 ? 1 : row.requestedQty) + qty;
          await updateBagRequestQty(requestId: rid, qty: nextQty);
          unawaited(
            FleaberLogger.instance.logLiveVendorStudio(
              'reservation.increment',
              liveId: liveId,
              sellerId: sellerId,
              liveItemId: liveItemId,
              requestId: rid,
              data: {
                'requested_qty': nextQty,
                'added_qty': qty,
                'available_qty': snap?.availableQty,
              },
            ),
          );
          final refreshed = await LiveReservationRequestsTable().queryRows(
            queryFn: (q) => q.eqOrNull('id', rid),
            limit: 1,
          );
          return refreshed.isEmpty ? row : refreshed.first;
        }
      }
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
    final created = rows.isEmpty ? null : rows.first;
    if (created != null) {
      unawaited(
        FleaberLogger.instance.logLiveVendorStudio(
          'reservation.create',
          liveId: liveId,
          sellerId: sellerId,
          liveItemId: liveItemId,
          requestId: created.id,
          data: {
            'requested_qty': created.requestedQty,
            'status': created.status,
            'queue_position': created.queuePosition,
            'available_qty': snap?.availableQty,
          },
        ),
      );
    }
    final itemId = liveItemId.trim();
    if (itemId.isNotEmpty) {
      try {
        await SupaFlow.client.rpc(
          'batata_recompact_reservation_queue',
          params: {'p_live_item_id': itemId},
        );
      } catch (_) {}
    }
    return created;
  }

  /// Marca reserva quando o comprador pede quantidade acima do stock (card urgente vendedora).
  static const qtyConfirmNeededNoteTag = 'qty_confirm_needed';

  static bool notesNeedQtyConfirm(String? notes) =>
      (notes ?? '').contains(qtyConfirmNeededNoteTag);

  /// Card vermelho vendedora: só quando qty pedida excede stock físico na live.
  static bool needsUrgentQtyConfirmCard({
    required int requestedQty,
    required LiveCatalogStockSnapshot? stock,
    required bool notesNeedQtyConfirm,
  }) {
    if (!notesNeedQtyConfirm || stock == null) return false;
    return stock.requestExceedsSellableCapacity(
      requestedQty,
      restorePendingQty: requestedQty,
    );
  }

  /// Persiste tag `qty_confirm_needed` via RPC (comprador não tem RLS de update directo).
  Future<bool> markQtyConfirmNeeded({required String requestId}) async {
    final id = requestId.trim();
    if (id.isEmpty) return false;
    try {
      final res = await SupaFlow.client.rpc(
        'batata_live_mark_qty_confirm_needed',
        params: {'p_request_id': id},
      );
      final map = res is Map ? Map<String, dynamic>.from(res) : null;
      return map != null && map['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> updateBagRequestQty({
    required String requestId,
    required int qty,
    String? liveItemId,
  }) async {
    final id = requestId.trim();
    if (id.isEmpty) return;
    final clamped = qty.clamp(1, 9999);
    final res = await SupaFlow.client.rpc(
      'batata_live_bag_update_qty',
      params: {'p_request_id': id, 'p_qty': clamped},
    );
    final map = res is Map ? Map<String, dynamic>.from(res) : null;
    if (map != null && map['ok'] != true) {
      throw StateError(map['error']?.toString() ?? 'bag_update_qty_failed');
    }
  }

  /// Soma `requested_qty` das linhas a pagar do mesmo artigo.
  static int sumPayQty(Iterable<LiveReservationRequestsRow> rows) {
    var total = 0;
    for (final r in rows) {
      total += r.requestedQty < 1 ? 1 : r.requestedQty;
    }
    return total < 1 ? 1 : total;
  }

  /// Reservas já aceites pela vendedora (prontas a pagar).
  static List<LiveReservationRequestsRow> buyerBagAcceptedRows(
    Iterable<LiveReservationRequestsRow> rows,
  ) {
    return rows
        .where(
          (r) =>
              (r.status ?? '') == 'accepted' &&
              !isBuyerCancelledReservation(
                status: r.status,
                notes: r.notes,
              ),
        )
        .toList();
  }

  /// Pedidos pendentes ainda não aceites (só estes contam para R6 no Pagar).
  static List<LiveReservationRequestsRow> buyerBagPendingPayRows(
    Iterable<LiveReservationRequestsRow> rows,
  ) {
    return rows
        .where(
          (r) =>
              (r.status ?? '') == 'pending' &&
              !isBuyerCancelledReservation(
                status: r.status,
                notes: r.notes,
              ),
        )
        .toList();
  }

  /// Bloqueia pagamento e mostra card urgente à vendedora só ao carregar em Pagar.
  static Future<bool> gateBagPayQtyOrPrompt({
    required BuildContext context,
    required String liveId,
    required String liveItemId,
    required List<LiveReservationRequestsRow> payRows,
    required LiveCatalogStockSnapshot? stock,
    String? refLabel,
  }) async {
    if (stock == null) return true;
    final pending = buyerBagPendingPayRows(payRows);
    if (pending.isEmpty) return true;
    final payQty = sumPayQty(pending);
    if (stock.canDirectPayWithoutApproval(
      payQty,
      restorePendingQty: payQty,
    )) {
      return true;
    }
    if (!stock.requestExceedsSellableCapacity(
      payQty,
      restorePendingQty: payQty,
    )) {
      return true;
    }

    final target = pending.isNotEmpty ? pending.first : payRows.first;
    final rid = target.id?.trim() ?? '';
    final lid = liveId.trim();
    final iid = liveItemId.trim();
    if (rid.isNotEmpty && lid.isNotEmpty && iid.isNotEmpty) {
      unawaited(
        FleaberLogger.instance.logLiveVendorStudio(
          'checkout.pay_qty_gate',
          liveId: lid,
          sellerId: pending.first.sellerId,
          liveItemId: iid,
          requestId: rid,
          data: {
            'pay_qty': payQty,
            'available_qty': stock.availableQty,
            'pending_rows': pending.length,
          },
        ),
      );
      await LiveInStreamCheckout.notifySellerQtyConfirmationNeeded(
        liveId: lid,
        liveItemId: iid,
        reservationRequestId: rid,
        requestedQty: payQty,
        availableQty: stock.availableQty,
        refLabel: refLabel,
        snackbarContext: context,
      );
    }
    if (!context.mounted) return false;
    unawaited(
      FleaberLogger.instance.event('live.player.c8b_gate', {
        'phase': 'pre_pop',
        'pay_qty': payQty,
        'available_qty': stock.availableQty,
        ...LiveInStreamCheckout.c8bUiStackSnapshot(context),
      }),
    );
    // Fechar só overlay (saco/sheet/dialog), nunca a rota do player.
    final localNav = Navigator.of(context);
    final rootCtx = Navigator.of(context, rootNavigator: true).context;
    final overlayRoute = ModalRoute.of(context);
    final didPop = localNav.canPop() && overlayRoute is PopupRoute;
    if (didPop) {
      localNav.pop();
      await Future<void>.delayed(Duration.zero);
    }
    if (context.mounted) {
      unawaited(
        FleaberLogger.instance.event('live.player.c8b_gate', {
          'phase': 'post_pop',
          'did_pop_sheet': didPop,
          'pay_qty': payQty,
          ...LiveInStreamCheckout.c8bUiStackSnapshot(context),
        }),
      );
    }
    final dialogCtx = rootCtx.mounted ? rootCtx : context;
    if (!dialogCtx.mounted) return false;
    await LiveInStreamCheckout.showQtyNeedsSellerConfirmationDialog(
      context: dialogCtx,
      availableQty: stock.availableQty,
      requestedQty: payQty,
      trigger: 'bag_pay_gate',
    );
    if (dialogCtx.mounted) {
      unawaited(
        FleaberLogger.instance.event('live.player.c8b_gate', {
          'phase': 'post_dialog',
          'pay_qty': payQty,
          ...LiveInStreamCheckout.c8bUiStackSnapshot(dialogCtx),
        }),
      );
    }
    return false;
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

  /// Slots físicos na fila (total − vendido − bloqueado − aceite). Não soma pending.
  static int grossAvailForUnitRanking(LiveCatalogStockSnapshot? stock) {
    if (stock == null) return 0;
    final gross = stock.totalQty -
        stock.blockedQty -
        stock.reservedAcceptedQty -
        stock.soldConvertedQty;
    return gross < 0 ? 0 : gross;
  }

  /// Unidade N deste artigo está em lista de espera (verde se N ≤ stock bruto).
  static bool isWaitlistUnit({
    required int unitIndex,
    LiveCatalogStockSnapshot? stock,
  }) {
    if (unitIndex < 1) return false;
    final gross = grossAvailForUnitRanking(stock);
    if (gross < 1) return true;
    return unitIndex > gross;
  }

  /// Posição na fila quando não há stock suficiente para esta posição.
  static bool isWaitlistPosition({
    required int? queuePosition,
    int? availableQty,
    LiveCatalogStockSnapshot? stock,
  }) {
    final pos = queuePosition;
    if (pos == null || pos < 1) return false;
    if (stock != null) {
      return isWaitlistUnit(unitIndex: pos, stock: stock);
    }
    final avail = availableQty;
    if (avail == null) return pos > 1;
    if (avail < 1) return true;
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
      'accepted' => 'Aceite · pronto a pagar',
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

  /// Pagamento no saco: pendente ou aceite (bloqueio qty_confirm é no checkout, não aqui).
  static bool buyerCanPayBagReservation(String? status, {String? notes}) {
    if (isBuyerCancelledReservation(status: status, notes: notes)) {
      return false;
    }
    return buyerBagIsActionable(status ?? '');
  }

  static Future<String?> fetchRequestStatus(String requestId) async {
    final id = requestId.trim();
    if (id.isEmpty) return null;
    try {
      final rows = await LiveReservationRequestsTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', id),
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first.status?.trim();
    } catch (_) {
      return null;
    }
  }

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
    String? liveItemId,
  }) async {
    final res = await SupaFlow.client.rpc(
      'batata_live_bag_remove_request',
      params: {'p_request_id': requestId},
    );
    final map = res is Map ? Map<String, dynamic>.from(res) : null;
    if (map != null && map['ok'] != true) {
      throw StateError(map['error']?.toString() ?? 'bag_remove_failed');
    }
    final itemId =
        liveItemId?.trim() ?? map?['live_item_id']?.toString().trim() ?? '';
    if (itemId.isNotEmpty) {
      try {
        await SupaFlow.client.rpc(
          'batata_recompact_reservation_queue',
          params: {'p_live_item_id': itemId},
        );
      } catch (_) {}
    }
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
