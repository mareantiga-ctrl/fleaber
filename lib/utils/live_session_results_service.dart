import '/backend/supabase/supabase.dart';
import '/order_cancel_eligibility.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_reservation_queue_service.dart';
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
    this.sessionAt,
  });

  final LivesRow live;
  final int articlesSold;
  final int reservationsCount;
  final double revenueEur;
  final int pendingPayments;
  final bool hasAlerts;
  /// Hora mostrada no card (reserva recente, went_live_at ou created_at).
  final DateTime? sessionAt;
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

enum LiveSessionActivityKind {
  info,
  reservation,
  purchase,
  message,
  article,
}

class LiveSessionActivityEntry {
  const LiveSessionActivityEntry({
    required this.id,
    required this.message,
    required this.at,
    this.kind = LiveSessionActivityKind.info,
    this.buyerId,
    this.productId,
    this.orderId,
    this.reservationId,
  });

  final String id;
  final String message;
  final DateTime? at;
  final LiveSessionActivityKind kind;
  final String? buyerId;
  final String? productId;
  final String? orderId;
  final String? reservationId;

  bool get isNavigable =>
      kind == LiveSessionActivityKind.reservation ||
      kind == LiveSessionActivityKind.purchase ||
      kind == LiveSessionActivityKind.message ||
      kind == LiveSessionActivityKind.article;
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
          .select(LivesTable().selectColumns!)
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

  /// Reservas "reais" — exclui linhas canceladas pelo comprador (saco
  /// removido/re-adicionado) para não duplicar a mesma reserva no card.
  static List<LiveReservationRequestsRow> _countableReservations(
    List<LiveReservationRequestsRow> reqs,
  ) {
    return reqs
        .where(
          (r) => !LiveReservationQueueService.isBuyerCancelledReservation(
            status: r.status,
            notes: r.notes,
          ),
        )
        .toList();
  }

  static DateTime _sessionDisplayTime(
    LivesRow live,
    List<LiveReservationRequestsRow> requests,
  ) {
    var best = live.wentLiveAt ?? live.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    for (final r in requests) {
      for (final t in [r.detectedAt, r.updatedAt, r.createdAt]) {
        if (t != null && t.isAfter(best)) best = t;
      }
    }
    return best;
  }

  /// Hora mostrada no card do Centro de resultados.
  static DateTime? sessionCardTimestamp(
    LivesRow live,
    List<LiveReservationRequestsRow> requests,
  ) {
    final fromReqs = requests
        .map((r) => r.detectedAt ?? r.updatedAt ?? r.createdAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (best, t) {
      if (best == null || t.isAfter(best)) return t;
      return best;
    });
    return fromReqs ?? live.wentLiveAt ?? live.createdAt;
  }

  static Future<List<LiveSessionSummary>> summariesForSeller(
    String sellerId,
  ) async {
    final sid = sellerId.trim();
    if (sid.isEmpty) return const [];

    var lives = await _livesForSeller(sid);
    final livesById = <String, LivesRow>{
      for (final l in lives)
        if ((l.id ?? '').trim().isNotEmpty) l.id!.trim(): l,
    };

    // Reservas do vendedor — recupera lives em falta na listagem principal.
    final sellerRequests = await LiveReservationRequestsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('seller_id', sid)
          .order('created_at', ascending: false),
      limit: 5000,
    );

    final missingLiveIds = <String>{};
    for (final r in sellerRequests) {
      final lid = (r.liveId ?? '').trim();
      if (lid.isNotEmpty && !livesById.containsKey(lid)) {
        missingLiveIds.add(lid);
      }
    }

    if (missingLiveIds.isNotEmpty) {
      final extra = await LivesTable().queryRows(
        queryFn: (q) => q.inFilter('id', missingLiveIds.toList()),
        limit: missingLiveIds.length,
      );
      for (final l in extra) {
        final id = (l.id ?? '').trim();
        if (id.isEmpty || !_liveBelongsToSeller(l, sid)) continue;
        livesById[id] = l;
      }
    }

    final byLiveReq = <String, List<LiveReservationRequestsRow>>{};
    for (final r in sellerRequests) {
      final lid = (r.liveId ?? '').trim();
      if (lid.isEmpty || !livesById.containsKey(lid)) continue;
      byLiveReq.putIfAbsent(lid, () => []).add(r);
    }

    lives = livesById.values.toList();
    if (lives.isEmpty) return const [];

    final liveIds = lives.map((l) => l.id).whereType<String>().toList();

    if (liveIds.isNotEmpty) {
      final byLive = await LiveReservationRequestsTable().queryRows(
        queryFn: (q) => q.inFilter('live_id', liveIds),
        limit: 5000,
      );
      for (final r in byLive) {
        final lid = (r.liveId ?? '').trim();
        if (lid.isEmpty) continue;
        final bucket = byLiveReq.putIfAbsent(lid, () => []);
        if (!bucket.any((x) => x.id == r.id)) bucket.add(r);
      }
    }

    lives.sort((a, b) {
      final ta = _sessionDisplayTime(
        a,
        byLiveReq[(a.id ?? '').trim()] ?? const [],
      );
      final tb = _sessionDisplayTime(
        b,
        byLiveReq[(b.id ?? '').trim()] ?? const [],
      );
      return tb.compareTo(ta);
    });

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
          reservationsCount: _countableReservations(reqs).length,
          revenueEur: metrics.revenueEur,
          pendingPayments: metrics.pendingPayments,
          hasAlerts: metrics.hasAlerts,
          sessionAt: sessionCardTimestamp(live, reqs),
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

  static String reservationBuyerLabel(
    LiveReservationRequestsRow r,
    Map<String, String> buyerNames,
  ) {
    final ext = (r.externalDisplayName ?? '').trim();
    if (ext.isNotEmpty) return ext;
    final notes = (r.notes ?? '').trim();
    if (notes.startsWith('manual:')) {
      return notes.substring('manual:'.length).trim();
    }
    final id = (r.buyerId ?? '').trim();
    if (id.isEmpty) {
      if (r.source == 'facebook_manual') return 'Facebook';
      if (r.source == 'helper_manual') return 'Assistente';
      return 'Cliente';
    }
    return buyerNames[id] ?? 'Cliente';
  }

  static Future<Map<String, String>> _resolveBuyerNames(
    Iterable<String> ids,
  ) async {
    final missing = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (missing.isEmpty) return {};
    try {
      final profiles = await ProfilesDirectoryTable().queryRows(
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

    final paidOrders = liveOrders.where(_orderCountsAsSold).toList();
    final paidKeys = _paidBuyerItemKeys(paidOrders);

    var soldQty = 0;
    var revenue = 0.0;
    // Reserva convertida só entra se ainda não houver encomenda paga
    // do mesmo comprador+artigo (senão 2 un. + 13,50 € contam duas vezes).
    for (final r in requests.where((r) => r.status == 'converted')) {
      final iid = (r.liveItemId ?? '').trim();
      final bid = (r.buyerId ?? '').trim();
      if (iid.isNotEmpty &&
          bid.isNotEmpty &&
          paidKeys.contains('$iid|$bid')) {
        continue;
      }
      final q = r.requestedQty < 1 ? 1 : r.requestedQty;
      soldQty += q;
      revenue += _reservationAmountEur(r, items);
    }

    for (final o in paidOrders) {
      final q = o.quantity < 1 ? 1 : o.quantity;
      soldQty += q;
      revenue += o.priceTotal ?? 0;
    }

    var pending = 0;
    // Encomendas em estados de pagamento — dedupe por live_item|buyer
    // (evita 2 linhas Star Wars do mesmo bot contarem 2×).
    final coveredByOrder = <String>{};
    final pendingOrdersByKey = <String, OrdersRow>{};
    for (final o in liveOrders) {
      final key = normalizeOrderStatusKey(o.status);
      if (key != 'pendente' &&
          key != 'reserva_pendente' &&
          key != 'reservado' &&
          key != 'aguarda_confirmacao') {
        continue;
      }
      final iid = (o.liveItemId ?? '').trim();
      final bid = (o.buyerId ?? '').trim();
      final dedupe = (iid.isNotEmpty && bid.isNotEmpty)
          ? '$iid|$bid'
          : 'order:${o.id?.trim() ?? ''}';
      if (dedupe == 'order:') continue;
      final prev = pendingOrdersByKey[dedupe];
      if (prev == null) {
        pendingOrdersByKey[dedupe] = o;
      } else {
        final ta = o.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = prev.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        if (ta.isAfter(tb)) pendingOrdersByKey[dedupe] = o;
      }
      if (iid.isNotEmpty && bid.isNotEmpty) {
        coveredByOrder.add('$iid|$bid');
      }
    }
    pending += pendingOrdersByKey.length;

    // Reservas abertas sem encomenda já contada (Marina sem pagar, etc.).
    for (final r in _countableReservations(requests)) {
      final st = r.status;
      if (st != 'pending' && st != 'accepted') continue;
      final iid = (r.liveItemId ?? '').trim();
      final bid = (r.buyerId ?? '').trim();
      if (iid.isNotEmpty &&
          bid.isNotEmpty &&
          coveredByOrder.contains('$iid|$bid')) {
        continue;
      }
      pending++;
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
    // Mesmo mapping humano que Minhas Encomendas — sem snake_case na UI.
    return orderStatusDisplayPhrase(status);
  }

  static bool _orderCountsAsSold(OrdersRow o) {
    final key = normalizeOrderStatusKey(o.status);
    return key == 'pago' ||
        key == 'premio_rifa' ||
        key == 'enviado' ||
        key == 'concluido';
  }

  static String? _buyerItemKey({String? liveItemId, String? buyerId}) {
    final iid = (liveItemId ?? '').trim();
    final bid = (buyerId ?? '').trim();
    if (iid.isEmpty || bid.isEmpty) return null;
    return '$iid|$bid';
  }

  static Set<String> _paidBuyerItemKeys(Iterable<OrdersRow> orders) {
    final keys = <String>{};
    for (final o in orders.where(_orderCountsAsSold)) {
      final k = _buyerItemKey(liveItemId: o.liveItemId, buyerId: o.buyerId);
      if (k != null) keys.add(k);
    }
    return keys;
  }

  static List<LiveSessionSaleRow> _buildSalesRows({
    required List<LiveReservationRequestsRow> reservations,
    required List<OrdersRow> orders,
    required Map<String, LiveItemsRow> itemsById,
    required Map<String, ProductsRow> productsById,
    required Map<String, String> buyerNames,
  }) {
    final rows = <LiveSessionSaleRow>[];
    final paidKeys = _paidBuyerItemKeys(orders);

    for (final r in reservations.where((r) => r.status == 'converted')) {
      final skipKey = _buyerItemKey(
        liveItemId: r.liveItemId,
        buyerId: r.buyerId,
      );
      if (skipKey != null && paidKeys.contains(skipKey)) continue;
      final buyerId = (r.buyerId ?? '').trim();
      final item = itemsById[(r.liveItemId ?? '').trim()];
      rows.add(
        LiveSessionSaleRow(
          buyerId: buyerId,
          buyerLabel: reservationBuyerLabel(r, buyerNames),
          articleLabel: _refLabel(item),
          amountEur: _reservationAmountEur(r, itemsById.values.toList()),
          statusLabel: LiveVendorSellerCopy.reservationStatus(
            r.status,
            requestKind: r.requestKind,
          ),
          at: r.updatedAt ?? r.createdAt,
          requestId: r.id,
          productId: item?.checkoutProductIdOrPrimary ?? item?.productId,
        ),
      );
    }

    for (final o in orders) {
      final key = normalizeOrderStatusKey(o.status);
      if (key != 'pago' &&
          key != 'premio_rifa' &&
          key != 'enviado' &&
          key != 'concluido') continue;
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

      var revenue = 0.0;
      var fromPaidOrder = false;
      final pid = item.checkoutProductIdOrPrimary ?? item.productId;
      if (pid != null && pid.isNotEmpty) {
        for (final o in orders) {
          if (o.productId != pid) continue;
          if (!_orderCountsAsSold(o)) continue;
          revenue += o.priceTotal ?? 0;
          fromPaidOrder = true;
        }
      }
      if (!fromPaidOrder) {
        revenue = sold * (item.price ?? 0.0);
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
      final buyer = reservationBuyerLabel(r, buyerNames);
      final ref = _refLabel(itemsById[(r.liveItemId ?? '').trim()]);
      final at = r.createdAt;
      final item = itemsById[(r.liveItemId ?? '').trim()];
      final productId =
          item?.checkoutProductIdOrPrimary ?? item?.productId;
      events.add(
        LiveSessionActivityEntry(
          id: 'req-create-$id',
          message: '$buyer reservou $ref',
          at: at,
          kind: LiveSessionActivityKind.reservation,
          buyerId: r.buyerId,
          productId: productId,
          reservationId: id,
        ),
      );
      if (r.status == 'converted') {
        events.add(
          LiveSessionActivityEntry(
            id: 'req-conv-$id',
            message: '$buyer comprou $ref',
            at: r.updatedAt ?? at,
            kind: LiveSessionActivityKind.purchase,
            buyerId: r.buyerId,
            productId: productId,
            reservationId: id,
          ),
        );
      } else if (r.status == 'expired') {
        events.add(
          LiveSessionActivityEntry(
            id: 'req-exp-$id',
            message: 'Reserva expirada · $ref',
            at: r.updatedAt ?? at,
            kind: LiveSessionActivityKind.info,
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
