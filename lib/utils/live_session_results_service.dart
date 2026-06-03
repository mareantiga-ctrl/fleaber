import '/backend/supabase/supabase.dart';
import '/order_cancel_eligibility.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/seller_staff_service.dart';
import '/widgets/live_vendor_ops_ui.dart';

String liveSessionSafeDisplayText(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final buffer = StringBuffer();
  for (final rune in raw.runes) {
    if (rune >= 0xD800 && rune <= 0xDFFF) continue;
    buffer.writeCharCode(rune);
  }
  return buffer.toString().trim();
}

/// Resumo agregado de uma sessão live (lista de cards).
class LiveSessionSummary {
  const LiveSessionSummary({
    required this.live,
    required this.articlesSold,
    required this.reservationsCount,
    required this.revenueEur,
    required this.pendingPayments,
    required this.hasAlerts,
  });

  final LivesRow live;
  final int articlesSold;
  final int reservationsCount;
  final double revenueEur;
  final int pendingPayments;
  final bool hasAlerts;
}

/// Linha de venda unificada (reserva convertida ou encomenda paga).
class LiveSessionSaleRow {
  const LiveSessionSaleRow({
    required this.buyerId,
    required this.buyerLabel,
    required this.articleLabel,
    required this.amountEur,
    required this.statusLabel,
    required this.at,
    this.orderId,
    this.requestId,
    this.productId,
  });

  final String buyerId;
  final String buyerLabel;
  final String articleLabel;
  final double amountEur;
  final String statusLabel;
  final DateTime? at;
  final String? orderId;
  final String? requestId;
  final String? productId;
}

/// Resumo comercial por referência no catálogo da live.
class LiveSessionArticleSummary {
  const LiveSessionArticleSummary({
    required this.liveItem,
    required this.refLabel,
    required this.initialQty,
    required this.soldQty,
    required this.reservedQty,
    required this.availableQty,
    required this.revenueEur,
    this.stockSnapshot,
  });

  final LiveItemsRow liveItem;
  final String refLabel;
  final int initialQty;
  final int soldQty;
  final int reservedQty;
  final int availableQty;
  final double revenueEur;
  final LiveCatalogStockSnapshot? stockSnapshot;
}

class LiveSessionActivityEntry {
  const LiveSessionActivityEntry({
    required this.id,
    required this.message,
    required this.at,
  });

  final String id;
  final String message;
  final DateTime? at;
}

class LiveSessionStats {
  const LiveSessionStats({
    required this.totalRevenueEur,
    required this.articlesSold,
    required this.avgTicketEur,
    this.topSoldRef,
    this.topReservedRef,
    this.peakSalesHour,
    this.peakActivityHour,
    required this.uniqueBuyers,
    required this.repeatBuyers,
    required this.reservationConversionRate,
    required this.soldOutCount,
  });

  final double totalRevenueEur;
  final int articlesSold;
  final double avgTicketEur;
  final String? topSoldRef;
  final String? topReservedRef;
  final int? peakSalesHour;
  final int? peakActivityHour;
  final int uniqueBuyers;
  final int repeatBuyers;
  final double reservationConversionRate;
  final int soldOutCount;
}

class LiveSessionDetailPayload {
  const LiveSessionDetailPayload({
    required this.live,
    required this.reservations,
    required this.orders,
    required this.items,
    required this.itemsById,
    required this.productsById,
    required this.buyerNames,
    required this.sales,
    required this.articles,
    required this.activity,
    required this.stats,
  });

  final LivesRow live;
  final List<LiveReservationRequestsRow> reservations;
  final List<OrdersRow> orders;
  final List<LiveItemsRow> items;
  final Map<String, LiveItemsRow> itemsById;
  final Map<String, ProductsRow> productsById;
  final Map<String, String> buyerNames;
  final List<LiveSessionSaleRow> sales;
  final List<LiveSessionArticleSummary> articles;
  final List<LiveSessionActivityEntry> activity;
  final LiveSessionStats stats;
}

/// Agrega resultados pós-live a partir de tabelas existentes (sem schema novo).
abstract final class LiveSessionResultsService {
  /// Lives do vendedor (`seller_id` ou legado `vendedor_id`).
  static Future<List<LivesRow>> _livesForSeller(String sellerId) async {
    final sid = sellerId.trim();
    if (sid.isEmpty) return const [];
    try {
      final rows = await SupaFlow.client
          .from('lives')
          .select()
          .or('seller_id.eq.$sid,vendedor_id.eq.$sid')
          .order('created_at', ascending: false)
          .limit(80);
      return [
        for (final raw in rows as List)
          LivesRow(Map<String, dynamic>.from(raw as Map)),
      ];
    } catch (_) {
      final rows = await LivesTable().queryRows(
        queryFn: (q) => q.eqOrNull('seller_id', sid).order('created_at', ascending: false),
        limit: 80,
      );
      if (rows.isNotEmpty) return rows;
      return LivesTable().queryRows(
        queryFn: (q) => q.eqOrNull('vendedor_id', sid).order('created_at', ascending: false),
        limit: 80,
      );
    }
  }

  static bool _liveBelongsToSeller(LivesRow live, String sellerId) {
    final sid = sellerId.trim();
    if (sid.isEmpty) return false;
    final s = (live.sellerId ?? '').trim();
    if (s == sid) return true;
    return (live.vendedorId ?? '').trim() == sid;
  }

  static Future<List<LiveSessionSummary>> summariesForSeller(
    String sellerId,
  ) async {
    final sid = sellerId.trim();
    if (sid.isEmpty) return const [];

    final lives = await _livesForSeller(sid);
    if (lives.isEmpty) return const [];

    final requests = await LiveReservationRequestsTable().queryRows(
      queryFn: (q) => q.eqOrNull('seller_id', sid).order('created_at', ascending: false),
      limit: 2000,
    );
    final byLiveReq = <String, List<LiveReservationRequestsRow>>{};
    for (final r in requests) {
      final lid = r.liveId ?? '';
      if (lid.isEmpty) continue;
      byLiveReq.putIfAbsent(lid, () => []).add(r);
    }

    final liveIds = lives.map((l) => l.id).whereType<String>().toList();
    final itemsByLive = await _itemsGroupedByLive(liveIds);
    final orders = await OrdersTable().queryRows(
      queryFn: (q) => q.eqOrNull('seller_id', sid).order('created_at', ascending: false),
      limit: 1500,
    );

    final out = <LiveSessionSummary>[];
    for (final live in lives) {
      final lid = live.id?.trim() ?? '';
      if (lid.isEmpty) continue;
      final reqs = byLiveReq[lid] ?? const [];
      final items = itemsByLive[lid] ?? const [];
      final metrics = _computeMetrics(
        live: live,
        requests: reqs,
        items: items,
        orders: orders,
      );
      out.add(
        LiveSessionSummary(
          live: live,
          articlesSold: metrics.articlesSold,
          reservationsCount: reqs.length,
          revenueEur: metrics.revenueEur,
          pendingPayments: metrics.pendingPayments,
          hasAlerts: metrics.hasAlerts,
        ),
      );
    }
    return out;
  }

  static Future<LiveSessionDetailPayload?> detailForLive({
    required String liveId,
    required String sellerId,
  }) async {
    final lid = liveId.trim();
    final sid = sellerId.trim();
    if (lid.isEmpty || sid.isEmpty) return null;

    final liveRows = await LivesTable().querySingleRow(
      queryFn: (q) => q.eqOrNull('id', lid),
    );
    if (liveRows.isEmpty) return null;
    final live = liveRows.first;
    if (!_liveBelongsToSeller(live, sid)) return null;

    final reservations = await LiveReservationRequestsTable().queryRows(
      queryFn: (q) => q.eqOrNull('live_id', lid).order('created_at', ascending: false),
      limit: 2000,
    );
    final items = await LiveItemsTable().queryRows(
      queryFn: (q) => q.eqOrNull('live_id', lid).order('created_at', ascending: true),
      limit: 500,
    );
    final itemsById = {
      for (final i in items)
        if ((i.id ?? '').trim().isNotEmpty) i.id!.trim(): i,
    };

    final productIds = <String>{
      for (final i in items) ...[
        if ((i.productId ?? '').trim().isNotEmpty) i.productId!.trim(),
        if ((i.checkoutProductId ?? '').trim().isNotEmpty)
          i.checkoutProductId!.trim(),
      ],
    };
    final productsById = await _productsById(productIds.toList());

    final directOrders = await OrdersTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('live_id', lid)
          .eqOrNull('seller_id', sid)
          .order('created_at', ascending: false),
      limit: 800,
    );
    final legacyCandidates = productIds.isEmpty
        ? const <OrdersRow>[]
        : await OrdersTable().queryRows(
            queryFn: (q) => q
                .eqOrNull('seller_id', sid)
                .inFilter('product_id', productIds.toList())
                .order('created_at', ascending: false),
            limit: 800,
          );
    final liveOrders = _ordersForLive(
      live: live,
      orders: [...directOrders, ...legacyCandidates],
      items: items,
    );

    final buyerIds = <String>{
      ...reservations.map((r) => r.buyerId ?? '').where((id) => id.isNotEmpty),
      ...liveOrders.map((o) => o.buyerId ?? '').where((id) => id.isNotEmpty),
    };
    final buyerNames = await _resolveBuyerNames(buyerIds);

    final stockSnaps = await LiveCatalogStockService.fetchMany(
      items.map((i) => i.id ?? '').where((id) => id.isNotEmpty),
    );

    final metrics = _computeMetrics(
      live: live,
      requests: reservations,
      items: items,
      orders: liveOrders,
    );

    final sales = _buildSalesRows(
      reservations: reservations,
      orders: liveOrders,
      itemsById: itemsById,
      productsById: productsById,
      buyerNames: buyerNames,
    );

    final articles = _buildArticleSummaries(
      items: items,
      reservations: reservations,
      orders: liveOrders,
      stockSnaps: stockSnaps,
    );

    final activity = await _buildActivityTimeline(
      liveId: lid,
      sellerId: sid,
      reservations: reservations,
      itemsById: itemsById,
      buyerNames: buyerNames,
    );

    final stats = _buildStats(
      reservations: reservations,
      items: items,
      sales: sales,
      activity: activity,
      metrics: metrics,
      stockSnaps: stockSnaps,
    );

    return LiveSessionDetailPayload(
      live: live,
      reservations: reservations,
      orders: liveOrders,
      items: items,
      itemsById: itemsById,
      productsById: productsById,
      buyerNames: buyerNames,
      sales: sales,
      articles: articles,
      activity: activity,
      stats: stats,
    );
  }

  static Future<Map<String, List<LiveItemsRow>>> _itemsGroupedByLive(
    List<String> liveIds,
  ) async {
    if (liveIds.isEmpty) return {};
    final rows = await LiveItemsTable().queryRows(
      queryFn: (q) => q.inFilter('live_id', liveIds),
      limit: 4000,
    );
    final out = <String, List<LiveItemsRow>>{};
    for (final row in rows) {
      final lid = row.liveId ?? '';
      if (lid.isEmpty) continue;
      out.putIfAbsent(lid, () => []).add(row);
    }
    return out;
  }

  static Future<Map<String, ProductsRow>> _productsById(List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await ProductsTable().queryRows(
      queryFn: (q) => q.inFilter('id', ids),
      limit: ids.length,
    );
    return {for (final p in rows) if (p.id != null) p.id!: p};
  }

  static Future<Map<String, String>> _resolveBuyerNames(
    Iterable<String> ids,
  ) async {
    final missing = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (missing.isEmpty) return {};
    try {
      final profiles = await ProfilesTable().queryRows(
        queryFn: (q) => q.inFilter('id', missing.toList()),
        limit: missing.length,
      );
      return {
        for (final p in profiles)
          if (p.id != null)
            p.id!: (p.fullName?.trim().isNotEmpty ?? false)
                ? p.fullName!.trim()
                : 'Cliente',
      };
    } catch (_) {
      return {};
    }
  }

  static ({
    int articlesSold,
    double revenueEur,
    int pendingPayments,
    bool hasAlerts,
  }) _computeMetrics({
    required LivesRow live,
    required List<LiveReservationRequestsRow> requests,
    required List<LiveItemsRow> items,
    required List<OrdersRow> orders,
  }) {
    final liveOrders = _ordersForLive(live: live, orders: orders, items: items);

    var soldQty = 0;
    var revenue = 0.0;
    for (final r in requests.where((r) => r.status == 'converted')) {
      final q = r.requestedQty < 1 ? 1 : r.requestedQty;
      soldQty += q;
      revenue += _reservationAmountEur(r, items);
    }

    for (final o in liveOrders) {
      final key = normalizeOrderStatusKey(o.status);
      if (key != 'pago' && key != 'enviado' && key != 'concluido') continue;
      final q = o.quantity < 1 ? 1 : o.quantity;
      soldQty += q;
      revenue += o.priceTotal ?? 0;
    }

    var pending = 0;
    for (final r in requests) {
      final st = r.status;
      if (st == 'pending' || st == 'accepted') pending++;
    }
    for (final o in liveOrders) {
      final key = normalizeOrderStatusKey(o.status);
      if (key == 'pendente' ||
          key == 'reserva_pendente' ||
          key == 'reservado' ||
          key == 'aguarda_confirmacao') {
        pending++;
      }
    }

    final conflicts = requests
        .where((r) => r.status == 'rejected' || r.status == 'expired')
        .length;

    return (
      articlesSold: soldQty,
      revenueEur: revenue,
      pendingPayments: pending,
      hasAlerts: pending > 0 || conflicts > 0,
    );
  }

  static List<OrdersRow> _ordersForLive({
    required LivesRow live,
    required List<OrdersRow> orders,
    required List<LiveItemsRow> items,
  }) {
    final lid = (live.id ?? '').trim();
    if (lid.isEmpty) return const [];

    final seen = <String>{};
    final out = <OrdersRow>[];

    // Fonte principal: ligação directa gravada na encomenda.
    for (final o in orders) {
      if ((o.liveId ?? '').trim() != lid) continue;
      final id = o.id?.trim() ?? '';
      if (id.isEmpty || !seen.add(id)) continue;
      out.add(o);
    }

    // legacy fallback — encomendas antigas sem orders.live_id
    for (final o in orders) {
      if ((o.liveId ?? '').trim().isNotEmpty) continue;
      if (!_legacyTemporalOrderMatch(o, live, items)) continue;
      final id = o.id?.trim() ?? '';
      if (id.isEmpty || !seen.add(id)) continue;
      out.add(o);
    }

    return out;
  }

  /// legacy fallback — só encomendas sem `live_id` (pré-migração).
  static bool _legacyTemporalOrderMatch(
    OrdersRow o,
    LivesRow live,
    List<LiveItemsRow> items,
  ) {
    final productIds = <String>{
      for (final i in items) ...[
        if ((i.productId ?? '').trim().isNotEmpty) i.productId!.trim(),
        if ((i.checkoutProductId ?? '').trim().isNotEmpty)
          i.checkoutProductId!.trim(),
      ],
    };
    if (productIds.isEmpty) return false;

    final pid = o.productId ?? '';
    if (!productIds.contains(pid)) return false;

    final start = live.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final end = start.add(const Duration(days: 14));
    final at = o.createdAt;
    if (at == null) return true;
    return !at.isBefore(start.subtract(const Duration(hours: 2))) &&
        !at.isAfter(end);
  }

  static double _reservationAmountEur(
    LiveReservationRequestsRow r,
    List<LiveItemsRow> items,
  ) {
    final itemId = (r.liveItemId ?? '').trim();
    LiveItemsRow? item;
    for (final i in items) {
      if ((i.id ?? '').trim() == itemId) {
        item = i;
        break;
      }
    }
    final unit = item?.price ?? 0;
    final q = r.requestedQty < 1 ? 1 : r.requestedQty;
    return unit * q;
  }

  static String _refLabel(LiveItemsRow? item) {
    if (item == null) return '—';
    final label = LiveVendorRefDisplay.refLabel(item.refCode);
    return label == '—' ? (item.title ?? 'Artigo') : label;
  }

  static String _orderStatusLabel(String? status) {
    final key = normalizeOrderStatusKey(status);
    return switch (key) {
      'pago' => 'Pago',
      'pendente' => 'Pagamento pendente',
      'reserva_pendente' => 'Reserva pendente',
      'reservado' => 'Reservado',
      'enviado' => 'Enviado',
      'concluido' => 'Concluído',
      'aguarda_confirmacao' => 'Aguarda confirmação',
      _ => key.isEmpty ? '—' : key,
    };
  }

  static List<LiveSessionSaleRow> _buildSalesRows({
    required List<LiveReservationRequestsRow> reservations,
    required List<OrdersRow> orders,
    required Map<String, LiveItemsRow> itemsById,
    required Map<String, ProductsRow> productsById,
    required Map<String, String> buyerNames,
  }) {
    final rows = <LiveSessionSaleRow>[];

    for (final r in reservations.where((r) => r.status == 'converted')) {
      final buyerId = (r.buyerId ?? '').trim();
      final item = itemsById[(r.liveItemId ?? '').trim()];
      rows.add(
        LiveSessionSaleRow(
          buyerId: buyerId,
          buyerLabel: buyerNames[buyerId] ?? 'Cliente',
          articleLabel: _refLabel(item),
          amountEur: _reservationAmountEur(r, itemsById.values.toList()),
          statusLabel: LiveVendorSellerCopy.reservationStatus(r.status),
          at: r.updatedAt ?? r.createdAt,
          requestId: r.id,
          productId: item?.checkoutProductIdOrPrimary ?? item?.productId,
        ),
      );
    }

    for (final o in orders) {
      final key = normalizeOrderStatusKey(o.status);
      if (key != 'pago' && key != 'enviado' && key != 'concluido') continue;
      final buyerId = (o.buyerId ?? '').trim();
      final product = productsById[o.productId ?? ''];
      rows.add(
        LiveSessionSaleRow(
          buyerId: buyerId,
          buyerLabel: buyerNames[buyerId] ?? 'Cliente',
          articleLabel: product?.title ?? 'Artigo',
          amountEur: o.priceTotal ?? 0,
          statusLabel: _orderStatusLabel(o.status),
          at: o.createdAt,
          orderId: o.id,
          productId: o.productId,
        ),
      );
    }

    rows.sort((a, b) {
      final ta = a.at ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.at ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return rows;
  }

  static List<LiveSessionArticleSummary> _buildArticleSummaries({
    required List<LiveItemsRow> items,
    required List<LiveReservationRequestsRow> reservations,
    required List<OrdersRow> orders,
    required Map<String, LiveCatalogStockSnapshot> stockSnaps,
  }) {
    final out = <LiveSessionArticleSummary>[];
    for (final item in items) {
      final id = (item.id ?? '').trim();
      if (id.isEmpty) continue;
      final snap = stockSnaps[id];
      final itemRes = reservations.where((r) => (r.liveItemId ?? '').trim() == id);

      var sold = snap?.soldConvertedQty ?? 0;
      if (sold == 0) {
        sold = itemRes
            .where((r) => r.status == 'converted')
            .fold<int>(0, (a, r) => a + (r.requestedQty < 1 ? 1 : r.requestedQty));
      }

      var reserved = snap != null
          ? snap.pendingBagQty + snap.reservedAcceptedQty
          : itemRes
              .where((r) => r.status == 'pending' || r.status == 'accepted')
              .fold<int>(0, (a, r) => a + (r.requestedQty < 1 ? 1 : r.requestedQty));

      final initial = snap?.totalQty ?? item.quantity ?? 1;
      final available = snap?.availableQty ??
          (initial - sold - reserved).clamp(0, 9999).toInt();

      var revenue = sold * (item.price ?? 0.0);
      final pid = item.checkoutProductIdOrPrimary ?? item.productId;
      if (pid != null && pid.isNotEmpty) {
        for (final o in orders) {
          if (o.productId != pid) continue;
          if (normalizeOrderStatusKey(o.status) != 'pago') continue;
          revenue += o.priceTotal ?? 0;
        }
      }

      out.add(
        LiveSessionArticleSummary(
          liveItem: item,
          refLabel: _refLabel(item),
          initialQty: initial,
          soldQty: sold,
          reservedQty: reserved,
          availableQty: available,
          revenueEur: revenue,
          stockSnapshot: snap,
        ),
      );
    }
    out.sort((a, b) => a.refLabel.compareTo(b.refLabel));
    return out;
  }

  static Future<List<LiveSessionActivityEntry>> _buildActivityTimeline({
    required String liveId,
    required String sellerId,
    required List<LiveReservationRequestsRow> reservations,
    required Map<String, LiveItemsRow> itemsById,
    required Map<String, String> buyerNames,
  }) async {
    final events = <LiveSessionActivityEntry>[];

    for (final r in reservations) {
      final id = (r.id ?? '').trim();
      if (id.isEmpty) continue;
      final buyer = buyerNames[(r.buyerId ?? '').trim()] ?? 'Cliente';
      final ref = _refLabel(itemsById[(r.liveItemId ?? '').trim()]);
      final at = r.createdAt;
      events.add(
        LiveSessionActivityEntry(
          id: 'req-create-$id',
          message: '$buyer reservou $ref',
          at: at,
        ),
      );
      if (r.status == 'converted') {
        events.add(
          LiveSessionActivityEntry(
            id: 'req-conv-$id',
            message: '$buyer comprou $ref',
            at: r.updatedAt ?? at,
          ),
        );
      } else if (r.status == 'expired') {
        events.add(
          LiveSessionActivityEntry(
            id: 'req-exp-$id',
            message: 'Reserva expirada · $ref',
            at: r.updatedAt ?? at,
          ),
        );
      }
    }

    try {
      final logs = await StaffActionLog.forSeller(sellerId, limit: 400);
      for (final log in logs) {
        final meta = log.metadataRaw;
        final metaLive = (meta['live_id'] ?? '').toString().trim();
        if (metaLive != liveId) continue;
        final action = (log.actionType ?? '').trim();
        final ref = LiveVendorRefDisplay.refLabel(meta['ref_code']?.toString());
        final actorId = (log.performedByUserId ?? '').trim();
        final isSeller = actorId == sellerId.trim();
        final actorName = isSeller
            ? 'Vendedora'
            : (meta['display_name']?.toString().trim() ?? 'Equipa');
        final msg = switch (action) {
          'live_reservation_accept' || 'reservation_accepted' =>
            '$actorName aceitou reserva · $ref',
          'mark_item_sold' || 'live_item_sold' || 'item_marked_sold' =>
            '$actorName marcou vendido · $ref',
          _ => null,
        };
        if (msg == null) continue;
        events.add(
          LiveSessionActivityEntry(
            id: 'staff-${log.id}',
            message: liveSessionSafeDisplayText(msg),
            at: log.createdAt,
          ),
        );
      }
    } catch (_) {}

    try {
      final rows = await SupaFlow.client
          .from('live_messages')
          .select('id, body, created_at, kind')
          .eq('live_id', liveId)
          .order('created_at', ascending: false)
          .limit(120);
      for (final raw in rows as List) {
        final map = Map<String, dynamic>.from(raw);
        final body = (map['body'] ?? '').toString().trim();
        if (body.isEmpty) continue;
        if (body.contains('comprou') ||
            body.contains('esgotado') ||
            body.contains('Restam')) {
          events.add(
            LiveSessionActivityEntry(
              id: 'msg-${map['id']}',
              message: liveSessionSafeDisplayText(
                body.replaceFirst(RegExp(r'^[✅💳🔴📦]\s*'), ''),
              ),
              at: DateTime.tryParse(map['created_at']?.toString() ?? ''),
            ),
          );
        }
      }
    } catch (_) {}

    try {
      final rows = await SupaFlow.client
          .from('live_vendor_studio_logs')
          .select('id, event, detail, created_at, status')
          .eq('live_id', liveId)
          .order('created_at', ascending: false)
          .limit(80);
      for (final raw in rows as List) {
        final map = Map<String, dynamic>.from(raw);
        final event = (map['event'] ?? '').toString();
        if (!event.contains('stock') && event != 'item.mark_sold') continue;
        final detail = map['detail'];
        final label = event.contains('stock')
            ? 'Stock atualizado'
            : 'Produto marcado como vendido';
        events.add(
          LiveSessionActivityEntry(
            id: 'studio-${map['id']}',
            message: detail is Map && detail['ref'] != null
                ? '$label · ${detail['ref']}'
                : label,
            at: DateTime.tryParse(map['created_at']?.toString() ?? ''),
          ),
        );
      }
    } catch (_) {}

    events.sort((a, b) {
      final ta = a.at ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.at ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return events;
  }

  static LiveSessionStats _buildStats({
    required List<LiveReservationRequestsRow> reservations,
    required List<LiveItemsRow> items,
    required List<LiveSessionSaleRow> sales,
    required List<LiveSessionActivityEntry> activity,
    required ({
      int articlesSold,
      double revenueEur,
      int pendingPayments,
      bool hasAlerts,
    }) metrics,
    required Map<String, LiveCatalogStockSnapshot> stockSnaps,
  }) {
    final soldByRef = <String, int>{};
    final reservedByRef = <String, int>{};
    for (final a in _buildArticleSummaries(
      items: items,
      reservations: reservations,
      orders: const [],
      stockSnaps: stockSnaps,
    )) {
      soldByRef[a.refLabel] = a.soldQty;
      reservedByRef[a.refLabel] = a.reservedQty;
    }

    String? topSold;
    var topSoldQty = 0;
    soldByRef.forEach((ref, qty) {
      if (qty > topSoldQty) {
        topSoldQty = qty;
        topSold = ref;
      }
    });

    String? topReserved;
    var topReservedQty = 0;
    reservedByRef.forEach((ref, qty) {
      if (qty > topReservedQty) {
        topReservedQty = qty;
        topReserved = ref;
      }
    });

    final salesHours = <int, int>{};
    for (final s in sales) {
      final h = s.at?.toLocal().hour;
      if (h == null) continue;
      salesHours[h] = (salesHours[h] ?? 0) + 1;
    }
    int? peakSalesHour;
    var peakSalesCount = 0;
    salesHours.forEach((h, c) {
      if (c > peakSalesCount) {
        peakSalesCount = c;
        peakSalesHour = h;
      }
    });

    final activityHours = <int, int>{};
    for (final e in activity) {
      final h = e.at?.toLocal().hour;
      if (h == null) continue;
      activityHours[h] = (activityHours[h] ?? 0) + 1;
    }
    int? peakActivityHour;
    var peakActivityCount = 0;
    activityHours.forEach((h, c) {
      if (c > peakActivityCount) {
        peakActivityCount = c;
        peakActivityHour = h;
      }
    });

    final buyerCounts = <String, int>{};
    for (final s in sales) {
      if (s.buyerId.isEmpty) continue;
      buyerCounts[s.buyerId] = (buyerCounts[s.buyerId] ?? 0) + 1;
    }
    final uniqueBuyers = buyerCounts.length;
    final repeatBuyers =
        buyerCounts.values.where((c) => c > 1).length;

    final converted =
        reservations.where((r) => r.status == 'converted').length;
    final lost = reservations
        .where((r) => r.status == 'expired' || r.status == 'rejected')
        .length;
    final conversionDenom = converted + lost;
    final conversionRate =
        conversionDenom == 0 ? 0.0 : converted / conversionDenom;

    var soldOut = 0;
    for (final item in items) {
      final st = (item.status ?? '').trim().toLowerCase();
      final snap = stockSnaps[(item.id ?? '').trim()];
      if (st == 'sold' ||
          st == 'reserved_full' ||
          (snap != null && snap.availableQty <= 0)) {
        soldOut++;
      }
    }

    final saleCount = sales.length;
    final avgTicket =
        saleCount == 0 ? 0.0 : metrics.revenueEur / saleCount;

    return LiveSessionStats(
      totalRevenueEur: metrics.revenueEur,
      articlesSold: metrics.articlesSold,
      avgTicketEur: avgTicket,
      topSoldRef: topSold,
      topReservedRef: topReserved,
      peakSalesHour: peakSalesHour,
      peakActivityHour: peakActivityHour,
      uniqueBuyers: uniqueBuyers,
      repeatBuyers: repeatBuyers,
      reservationConversionRate: conversionRate,
      soldOutCount: soldOut,
    );
  }
}

extension on LiveItemsRow {
  String? get checkoutProductIdOrPrimary =>
      isMarketplaceProduct ? productId : (checkoutProductId ?? productId);
}
