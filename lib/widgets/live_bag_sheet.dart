import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/batata_bundle_actions.dart';
import '/order_cancel_eligibility.dart';
import '/utils/fleaber_radius.dart';
import '/utils/live_bag_copy.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_in_stream_checkout.dart';
import '/utils/live_item_price_gate.dart';
import '/utils/live_reservation_queue_service.dart';
import '/hub/hub_qa_diag.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/bundle_direct_payment_sheet.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/live_bag_checkout_sheet.dart';
import '/widgets/live_vendor_ops_ui.dart';
import '/widgets/order_direct_payment_proof_sheet.dart';

const Color _kLiveBagBg = Color(0xFF11181C);
const Color _kLiveBagTeal = Color(0xFF00A3AD);
const Color _kLiveBagGreen = Color(0xFF4CAF50);
const Color _kLiveBagAmber = Color(0xFFFFB74D);
const Color _kLiveBagMuted = Color(0xFF8A9BA8);

/// UX do «Saco da live» (comprador). Não altera fila, RPCs, stock nem checkout.
class LiveBagSheet {
  LiveBagSheet._();

  static Future<void> show({
    required BuildContext context,
    required String liveId,
    required String buyerId,
    required Map<String, LiveItemsRow> catalogByItemId,
    required Future<List<LiveReservationRequestsRow>> Function() loadRows,
    Future<Map<String, dynamic>?> Function()? loadSellerBagMeta,
    required Future<LiveCatalogStockSnapshot?> Function(LiveItemsRow item)
        fetchStock,
    required Future<ProductsRow?> Function(LiveItemsRow item) resolveProduct,
    required Future<void> Function(
      ProductsRow product, {
      String? liveItemId,
      String? reservationRequestId,
      int payQty,
    }) openSingleCheckout,
    required Future<void> Function(List<LiveReservationRequestsRow> rows)
        openMultiCheckout,
    String? playbackId,
    required bool isLive,
    String? liveSellerId,
    VoidCallback? onBagChanged,
    String? focusReservationRequestId,
    bool fleahubChrome = false,
  }) {
    final body = _LiveBagSheetBody(
      liveId: liveId,
      buyerId: buyerId,
      catalogByItemId: catalogByItemId,
      loadRows: loadRows,
      loadSellerBagMeta: loadSellerBagMeta,
      fetchStock: fetchStock,
      resolveProduct: resolveProduct,
      openSingleCheckout: openSingleCheckout,
      openMultiCheckout: openMultiCheckout,
      playbackId: playbackId,
      isLive: isLive,
      liveSellerId: liveSellerId,
      onBagChanged: onBagChanged,
      focusReservationRequestId: focusReservationRequestId,
      fleahubChrome: fleahubChrome,
    );
    final wide = fleahubChrome && MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      return showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Fechar saco',
        barrierColor: const Color(0x59000000),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (ctx, a1, a2) {
          return Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.white,
              elevation: 12,
              child: SizedBox(
                width: (MediaQuery.sizeOf(ctx).width * 0.42).clamp(420.0, 480.0),
                height: MediaQuery.sizeOf(ctx).height,
                child: body,
              ),
            ),
          );
        },
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: fleahubChrome
          ? const Color(0x59000000)
          : Colors.transparent,
      backgroundColor: fleahubChrome ? Colors.white : _kLiveBagBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => body,
    );
  }

  /// QA / embed: same buyer bag body without modal chrome.
  static Widget embed({
    required String liveId,
    required String buyerId,
    required Map<String, LiveItemsRow> catalogByItemId,
    required Future<List<LiveReservationRequestsRow>> Function() loadRows,
    Future<Map<String, dynamic>?> Function()? loadSellerBagMeta,
    required Future<LiveCatalogStockSnapshot?> Function(LiveItemsRow item)
        fetchStock,
    required Future<ProductsRow?> Function(LiveItemsRow item) resolveProduct,
    required Future<void> Function(
      ProductsRow product, {
      String? liveItemId,
      String? reservationRequestId,
      int payQty,
    }) openSingleCheckout,
    required Future<void> Function(List<LiveReservationRequestsRow> rows)
        openMultiCheckout,
    String? playbackId,
    required bool isLive,
    String? liveSellerId,
    VoidCallback? onBagChanged,
    String? focusReservationRequestId,
  }) {
    return ColoredBox(
      color: _kLiveBagBg,
      child: SafeArea(
        child: _LiveBagSheetBody(
          liveId: liveId,
          buyerId: buyerId,
          catalogByItemId: catalogByItemId,
          loadRows: loadRows,
          loadSellerBagMeta: loadSellerBagMeta,
          fetchStock: fetchStock,
          resolveProduct: resolveProduct,
          openSingleCheckout: openSingleCheckout,
          openMultiCheckout: openMultiCheckout,
          playbackId: playbackId,
          isLive: isLive,
          liveSellerId: liveSellerId,
          onBagChanged: onBagChanged,
          focusReservationRequestId: focusReservationRequestId,
        ),
      ),
    );
  }
}

enum _LiveBagSection { inBag, waitlist, purchased, cancelled }

class _LiveBagItemGroup {
  const _LiveBagItemGroup({
    required this.liveItemId,
    required this.catalogRow,
    required this.reservations,
  });

  final String liveItemId;
  final LiveItemsRow? catalogRow;
  final List<LiveReservationRequestsRow> reservations;
}

class _LiveBagSheetBody extends StatefulWidget {
  const _LiveBagSheetBody({
    required this.liveId,
    required this.buyerId,
    required this.catalogByItemId,
    required this.loadRows,
    this.loadSellerBagMeta,
    required this.fetchStock,
    required this.resolveProduct,
    required this.openSingleCheckout,
    required this.openMultiCheckout,
    this.playbackId,
    required this.isLive,
    this.liveSellerId,
    this.onBagChanged,
    this.focusReservationRequestId,
    this.fleahubChrome = false,
  });

  final String liveId;
  final String buyerId;
  final Map<String, LiveItemsRow> catalogByItemId;
  final Future<List<LiveReservationRequestsRow>> Function() loadRows;
  final Future<Map<String, dynamic>?> Function()? loadSellerBagMeta;
  final Future<LiveCatalogStockSnapshot?> Function(LiveItemsRow item)
      fetchStock;
  final Future<ProductsRow?> Function(LiveItemsRow item) resolveProduct;
  final Future<void> Function(
    ProductsRow product, {
    String? liveItemId,
    String? reservationRequestId,
    int payQty,
  }) openSingleCheckout;
  final Future<void> Function(List<LiveReservationRequestsRow> rows)
      openMultiCheckout;
  final String? playbackId;
  final bool isLive;
  final String? liveSellerId;
  final VoidCallback? onBagChanged;
  final String? focusReservationRequestId;
  final bool fleahubChrome;

  @override
  State<_LiveBagSheetBody> createState() => _LiveBagSheetBodyState();
}

class _LiveBagSheetBodyState extends State<_LiveBagSheetBody> {
  List<LiveReservationRequestsRow> _rows = const [];
  List<Map<String, dynamic>> _marketplaceLines = const [];
  /// request_id → seller-bag line meta (line_state / unavailable).
  Map<String, Map<String, dynamic>> _lrrLineMetaById = const {};
  bool _loading = true;
  bool _cancelledExpanded = false;
  final Map<String, LiveCatalogStockSnapshot?> _stockByItemId = {};
  late Map<String, LiveItemsRow> _catalogByItemId;
  String? _scrollFocusReservationId;
  final GlobalKey _focusCardKey = GlobalKey();
  late final ScrollController _scrollController;

  Timer? _refreshTimer;

  /// Encomendas MB WAY / transferência já criadas nesta live (por live_item_id).
  Map<String, OrdersRow> _pendingDirectByLiveItemId = {};

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _catalogByItemId = Map<String, LiveItemsRow>.from(widget.catalogByItemId);
    unawaited(_reload());
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) unawaited(_reload(silent: true));
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _reload({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final next = await widget.loadRows();
    var mpLines = const <Map<String, dynamic>>[];
    var lrrMeta = <String, Map<String, dynamic>>{};
    final metaLoader = widget.loadSellerBagMeta;
    if (metaLoader != null) {
      try {
        final meta = await metaLoader();
        final raw = meta?['marketplace_adapter_lines'];
        if (raw is List) {
          mpLines = raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        final lrrRaw = meta?['lrr_lines'];
        if (lrrRaw is List) {
          for (final e in lrrRaw.whereType<Map>()) {
            final m = Map<String, dynamic>.from(e);
            final id = m['id']?.toString().trim() ?? '';
            if (id.isNotEmpty) lrrMeta[id] = m;
          }
        }
        // Ignore unused: keep marketplace + lrr meta for buyer chips.
      } catch (_) {}
    }
    // Hydrate catalog (incl. reserved_full oculto por RLS → RPC bag-safe).
    for (final r in next) {
      final id = (r.liveItemId ?? '').trim();
      if (id.isEmpty) continue;
      final existing = _catalogByItemId[id];
      final existingPrice = existing?.price;
      if (existing != null && existingPrice != null && existingPrice > 0) {
        continue;
      }
      try {
        final fetched = await LiveCatalogStockService.fetchLiveItemById(id);
        if (fetched != null) {
          _catalogByItemId[id] = fetched;
        }
      } catch (_) {}
    }
    final itemIds = next
        .map((r) => (r.liveItemId ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    for (final id in itemIds) {
      final row = _catalogByItemId[id] ?? widget.catalogByItemId[id];
      if (row != null) {
        _stockByItemId[id] = await widget.fetchStock(row);
      }
    }
    final pendingDirect = await _loadPendingDirectOrders();
    if (!mounted) return;
    setState(() {
      _rows = next;
      _marketplaceLines = mpLines;
      _lrrLineMetaById = lrrMeta;
      _pendingDirectByLiveItemId = pendingDirect;
      _loading = false;
      _scrollFocusReservationId = _resolveScrollFocusId(next);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final grouped = _grouped();
      final inBag = grouped[_LiveBagSection.inBag] ?? const [];
      final lineCount = _countReservations(inBag);
      final unitCount = inBag.fold<int>(
        0,
        (a, g) =>
            a +
            g.reservations.fold<int>(
              0,
              (a2, r) => a2 + HubQaDiag.unitQty(r),
            ),
      );
      HubQaDiag.logC1(
        source: 'live_bag_sheet',
        liveId: widget.liveId,
        rows: next,
        bagSheetLineCount: lineCount,
        bagSheetUnitCount: unitCount,
      );
    });
    if (!silent && _scrollFocusReservationId != null) {
      _scrollToFocusedCard();
    }
  }

  Future<Map<String, OrdersRow>> _loadPendingDirectOrders() async {
    final lid = widget.liveId.trim();
    final buyer = widget.buyerId.trim();
    if (lid.isEmpty || buyer.isEmpty) return {};
    try {
      final rows = await OrdersTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('live_id', lid)
            .eqOrNull('buyer_id', buyer)
            .inFilter('status', [
              'reserva_pendente',
              'reservado',
              'aguarda_confirmacao',
            ]),
        limit: 40,
      );
      final map = <String, OrdersRow>{};
      for (final o in rows) {
        if (!bundlePaymentMethodIsDirect(o.paymentMethod)) continue;
        final iid = (o.liveItemId ?? '').trim();
        if (iid.isEmpty) continue;
        final prev = map[iid];
        if (prev == null) {
          map[iid] = o;
          continue;
        }
        final ta = o.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = prev.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        if (ta.isAfter(tb)) map[iid] = o;
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  OrdersRow? _pendingDirectForGroup(_LiveBagItemGroup group) {
    final iid = group.liveItemId.trim();
    if (iid.isEmpty) return null;
    return _pendingDirectByLiveItemId[iid];
  }

  Future<void> _showDirectPaymentDetails(OrdersRow order) async {
    final oid = order.id?.trim() ?? '';
    final sellerId = order.sellerId?.trim() ?? '';
    if (oid.isEmpty || sellerId.isEmpty) return;
    try {
      final details = await buildOrderDirectPaymentDetails(
        orderId: oid,
        sellerId: sellerId,
        amountEur: order.priceTotal ?? 0,
      );
      if (!mounted) return;
      await showBundleDirectPaymentDetailsSheet(context, details: details);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _confirmDirectPayment(OrdersRow order) async {
    final ok = await showOrderDirectPaymentProofSheet(context, order: order);
    if (ok && mounted) await _reload();
  }

  String? _resolveScrollFocusId(List<LiveReservationRequestsRow> rows) {
    final requested = widget.focusReservationRequestId?.trim();
    if (requested != null && requested.isNotEmpty) {
      for (final r in rows) {
        if (r.id == requested &&
            LiveReservationQueueService.buyerBagIsActionable(r.status ?? '')) {
          return requested;
        }
      }
    }
    for (final r in rows) {
      final status = r.status ?? '';
      if (!LiveReservationQueueService.isBuyerCancelledReservation(
        status: status,
        notes: r.notes,
      )) {
        if (LiveReservationQueueService.buyerBagIsActionable(status)) {
          return r.id;
        }
      }
    }
    return null;
  }

  void _scrollToFocusedCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _focusCardKey.currentContext;
      if (ctx == null) return;
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          alignment: 0.06,
        ),
      );
    });
  }

  static _LiveBagSection _sectionFor(
    LiveReservationRequestsRow r,
    LiveCatalogStockSnapshot? stock,
  ) {
    final status = r.status ?? '';
    if (status == 'converted') return _LiveBagSection.purchased;
    if (LiveReservationQueueService.isBuyerCancelledReservation(
      status: status,
      notes: r.notes,
    )) {
      return _LiveBagSection.cancelled;
    }
    if (status == 'rejected' || status == 'expired') {
      return _LiveBagSection.cancelled;
    }
    if (status == 'pending' || status == 'accepted') {
      return _LiveBagSection.inBag;
    }
    return _LiveBagSection.cancelled;
  }

  Map<_LiveBagSection, List<_LiveBagItemGroup>> _grouped() {
    final bySection = <_LiveBagSection, Map<String, List<LiveReservationRequestsRow>>>{
      _LiveBagSection.inBag: {},
      _LiveBagSection.waitlist: {},
      _LiveBagSection.purchased: {},
      _LiveBagSection.cancelled: {},
    };
    for (final r in _rows) {
      final itemId = (r.liveItemId ?? '').trim();
      if (itemId.isEmpty) continue;
      final stock = _stockByItemId[itemId];
      final section = _sectionFor(r, stock);
      bySection[section]!.putIfAbsent(itemId, () => []).add(r);
    }

    Map<_LiveBagSection, List<_LiveBagItemGroup>> out = {};
    for (final entry in bySection.entries) {
      final groups = <_LiveBagItemGroup>[];
      for (final e in entry.value.entries) {
        final list = List<LiveReservationRequestsRow>.from(e.value)
          ..sort(
            (a, b) =>
                (a.queuePosition ?? 9999).compareTo(b.queuePosition ?? 9999),
          );
        groups.add(
          _LiveBagItemGroup(
            liveItemId: e.key,
            catalogRow: _catalogByItemId[e.key],
            reservations: list,
          ),
        );
      }
      groups.sort((a, b) {
        final pa = a.reservations.first.queuePosition ?? 9999;
        final pb = b.reservations.first.queuePosition ?? 9999;
        return pa.compareTo(pb);
      });
      out[entry.key] = groups;
    }
    return out;
  }

  int _countReservations(List<_LiveBagItemGroup> groups) =>
      groups.fold<int>(0, (a, g) => a + g.reservations.length);

  int _countArticles(List<_LiveBagItemGroup> groups) => groups.length;

  int _countUnits(List<_LiveBagItemGroup> groups) => groups.fold<int>(
        0,
        (a, g) =>
            a +
            g.reservations.fold<int>(
              0,
              (a2, r) => a2 + HubQaDiag.unitQty(r),
            ),
      );

  Future<void> _afterMutation() async {
    widget.onBagChanged?.call();
    await _reload();
  }

  Future<void> _updateReservationQty(
    String requestId,
    int qty, {
    String? liveItemId,
  }) async {
    try {
      await LiveReservationQueueService().updateBagRequestQty(
        requestId: requestId,
        qty: qty,
        liveItemId: liveItemId,
      );
      await _afterMutation();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível alterar a quantidade: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped();
    final inBag = grouped[_LiveBagSection.inBag] ?? const [];
    final cancelled = grouped[_LiveBagSection.cancelled] ?? const [];
    final purchased = grouped[_LiveBagSection.purchased] ?? const [];

    final inBagArticles = _countArticles(inBag);
    final inBagUnits = _countUnits(inBag);
    final cancelN = _countReservations(cancelled);

    // Reservar espaço para o CTA sticky + safe area (evita Finalizar sob a nav).
    final viewH = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final maxH = (viewH * 0.62).clamp(220.0, viewH - 200 - bottomInset);

    final light = widget.fleahubChrome;
    final titleFg = light ? const Color(0xFF101518) : Colors.white;
    final mutedFg = light ? const Color(0xFF57636C) : _kLiveBagMuted;
    final iconFg = light ? const Color(0xFF57636C) : Colors.white70;
    // Secções / cancelados: no chrome Hub usam texto escuro.

    return SafeArea(
      top: false,
      child: ColoredBox(
        color: light ? Colors.white : Colors.transparent,
        child: Padding(
        // SafeArea already applies padding.bottom — only add spacing, not inset again.
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.arrow_back_rounded, color: iconFg),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'O teu saco',
                        style: GoogleFonts.inter(
                          color: titleFg,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        LiveBagCopy.headerSubtitle(
                          articleCount: inBagArticles,
                          unitCount: inBagUnits,
                          cancelledCount: cancelN,
                        ),
                        style: GoogleFonts.inter(
                          color: mutedFg,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.shopping_bag_outlined, color: _kLiveBagTeal, size: 22),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_rows.isEmpty && _marketplaceLines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Ainda não tens artigos no saco.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: mutedFg),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (inBag.isNotEmpty) ...[
                        _sectionHeader(
                          'No saco',
                          LiveBagCopy.sectionCount(
                            articleCount: inBagArticles + _marketplaceLines.length,
                            unitCount: inBagUnits +
                                _marketplaceLines.fold<int>(
                                  0,
                                  (a, m) =>
                                      a +
                                      ((m['requested_qty'] as num?)?.toInt() ??
                                          1),
                                ),
                          ),
                        ),
                        for (final g in inBag)
                          _LiveBagItemCard(
                            lightChrome: widget.fleahubChrome,
                            key: _scrollFocusReservationId != null &&
                                    g.reservations.any(
                                      (r) =>
                                          r.id == _scrollFocusReservationId,
                                    )
                                ? _focusCardKey
                                : null,
                            group: g,
                            stock: _stockByItemId[g.liveItemId],
                            lrrLineMetaById: _lrrLineMetaById,
                            highlighted: _scrollFocusReservationId != null &&
                                g.reservations.any(
                                  (r) => r.id == _scrollFocusReservationId,
                                ),
                            resolveProduct: widget.resolveProduct,
                            pendingDirectOrder: _pendingDirectForGroup(g),
                            onPay: () => _openPayPicker(g),
                            onShowPaymentDetails: () {
                              final o = _pendingDirectForGroup(g);
                              if (o != null) {
                                unawaited(_showDirectPaymentDetails(o));
                              }
                            },
                            onConfirmPayment: () {
                              final o = _pendingDirectForGroup(g);
                              if (o != null) {
                                unawaited(_confirmDirectPayment(o));
                              }
                            },
                            onChangePaymentMethod: () => _openPayPicker(g),
                            onManage: () => _openManageSheet(g),
                            onUpdateQty: (requestId, qty) => _updateReservationQty(
                              requestId,
                              qty,
                              liveItemId: g.liveItemId,
                            ),
                          ),
                        for (final mp in _marketplaceLines)
                          _MarketplaceBagLineCard(
                            line: mp,
                            lightChrome: widget.fleahubChrome,
                          ),
                      ],
                      if (inBag.isEmpty && _marketplaceLines.isNotEmpty) ...[
                        _sectionHeader(
                          'No saco',
                          LiveBagCopy.sectionCount(
                            articleCount: _marketplaceLines.length,
                            unitCount: _marketplaceLines.fold<int>(
                              0,
                              (a, m) =>
                                  a +
                                  ((m['requested_qty'] as num?)?.toInt() ?? 1),
                            ),
                          ),
                        ),
                        for (final mp in _marketplaceLines)
                          _MarketplaceBagLineCard(
                            line: mp,
                            lightChrome: widget.fleahubChrome,
                          ),
                      ],
                      if (purchased.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _sectionHeader(
                          '✓ Comprados',
                          LiveBagCopy.sectionCount(
                            articleCount: _countArticles(purchased),
                            unitCount: _countUnits(purchased),
                          ),
                        ),
                        for (final g in purchased)
                          _LiveBagItemCard(
                            lightChrome: widget.fleahubChrome,
                            group: g,
                            stock: _stockByItemId[g.liveItemId],
                            resolveProduct: widget.resolveProduct,
                            onPay: null,
                            onManage: null,
                            isPurchased: true,
                          ),
                      ],
                      if (cancelled.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () => setState(
                            () => _cancelledExpanded = !_cancelledExpanded,
                          ),
                          borderRadius: FleaberRadius.circularSm,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Text(
                                  'Cancelados ($cancelN)',
                                  style: GoogleFonts.inter(
                                    color: light
                                        ? const Color(0xFF57636C)
                                        : Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  _cancelledExpanded
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  color: light
                                      ? const Color(0xFF57636C)
                                      : Colors.white54,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_cancelledExpanded)
                          for (final g in cancelled)
                            _LiveBagItemCard(
                            lightChrome: widget.fleahubChrome,
                              group: g,
                              stock: _stockByItemId[g.liveItemId],
                              resolveProduct: widget.resolveProduct,
                              onPay: null,
                              onManage: null,
                              isCancelled: true,
                            ),
                      ],
                    ],
                  ),
                ),
              ),
            // Sticky checkout CTA — fora do scroll, acima da barra de sistema.
            if (!_loading && _rows.isNotEmpty) ...[
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  final stillNeedCheckout = _rows.any((r) {
                    if (!LiveReservationQueueService.buyerCanPayBagReservation(r.status, notes: r.notes, requestKind: r.requestKind)) {
                      return false;
                    }
                    final iid = (r.liveItemId ?? '').trim();
                    return iid.isEmpty ||
                        !_pendingDirectByLiveItemId.containsKey(iid);
                  });
                  if (!stillNeedCheckout) {
                    return Text(
                      'Já escolheste pagamento directo. Usa «Ver dados» e '
                      '«Confirmar pagamento» em cada artigo, ou altera o método.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: light
                            ? const Color(0xFF57636C)
                            : Colors.white60,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    );
                  }
                  return Semantics(
                    button: true,
                    label: 'Finalizar compra',
                    child: FleaberPrimaryButton(
                      label: 'Finalizar compra',
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      onPressed: () async {
                        Navigator.pop(context);
                        final payRows = _rows.where((r) {
                          if (!LiveReservationQueueService
                              .buyerCanPayBagReservation(r.status, notes: r.notes, requestKind: r.requestKind)) {
                            return false;
                          }
                          final iid = (r.liveItemId ?? '').trim();
                          return iid.isEmpty ||
                              !_pendingDirectByLiveItemId.containsKey(iid);
                        }).toList();
                        await widget.openMultiCheckout(
                          payRows.isEmpty ? _rows : payRows,
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  Widget _sectionHeader(String title, String countLabel) {
    final light = widget.fleahubChrome;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Text(
        '$title ($countLabel)',
        style: GoogleFonts.inter(
          color: light ? const Color(0xFF101518) : Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Future<void> _openPayPicker(_LiveBagItemGroup group) async {
    final itemId = group.liveItemId.trim();
    var row = group.catalogRow;
    if (row == null && itemId.isEmpty) return;
    if (itemId.isNotEmpty) {
      row = await LiveCatalogStockService.fetchLiveItemById(itemId) ?? row;
      if (row != null) _catalogByItemId[itemId] = row;
    }
    if (row == null) return;
    final product = await LiveItemPriceGate.resolveProductForCheckout(
      itemRow: row,
      sellerId: widget.liveSellerId,
      liveId: widget.liveId,
      resolveProduct: widget.resolveProduct,
    );
    if (product == null ||
        !await LiveItemPriceGate.hasFreshPayableUnitPrice(
          liveItemId: itemId,
          fallbackLiveItemPrice: row.price,
          productPrice: product?.price,
          sellerId: widget.liveSellerId,
          liveId: widget.liveId,
          itemRow: row,
        )) {
      LiveItemPriceGate.logCheckoutGate(
        'bag_card_pay_blocked',
        liveId: widget.liveId,
        sellerId: widget.liveSellerId,
        liveItemId: itemId,
        productId: product?.id,
        liveItemPrice: row.price,
        productPrice: product?.price,
        reason: product == null ? 'product_null' : 'unit_null',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(LiveItemPriceGate.pendingPriceLabel),
        ),
      );
      return;
    }

    final candidates = group.reservations
        .where(
          (r) => LiveReservationQueueService.buyerCanPayBagReservation(r.status, notes: r.notes, requestKind: r.requestKind),
        )
        .toList();
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma reserva deste artigo está pronta para pagar.'),
        ),
      );
      return;
    }

    final stock = _stockByItemId[group.liveItemId];
    if (!mounted) return;
    final pendingPay =
        LiveReservationQueueService.buyerBagPendingPayRows(candidates);
    final canPay = pendingPay.isEmpty
        ? true
        : await LiveReservationQueueService.gateBagPayQtyOrPrompt(
            context: context,
            liveId: widget.liveId,
            liveItemId: group.liveItemId,
            payRows: pendingPay,
            stock: stock,
            refLabel: LiveVendorRefDisplay.itemDisplayName(
              title: row.title,
              refCode: row.refCode,
            ),
          );
    if (!canPay || !mounted) return;

    final selected = await showModalBottomSheet<List<LiveReservationRequestsRow>>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.transparent,
      backgroundColor: _kLiveBagBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _LiveBagPayPickerSheet(
        group: group,
        reservations: candidates,
        stockByItemId: _stockByItemId,
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    Navigator.pop(context);
    if (selected.length == 1) {
      final r = selected.first;
      await widget.openSingleCheckout(
        product,
        liveItemId: group.liveItemId,
        reservationRequestId: r.id,
        payQty: r.requestedQty < 1 ? 1 : r.requestedQty,
      );
      return;
    }

    final payLines = <LiveBagCheckoutPayLine>[];
    for (final r in selected) {
      payLines.add(
        LiveBagCheckoutPayLine(
          product: product,
          itemRow: row,
          request: r,
          payQty: r.requestedQty < 1 ? 1 : r.requestedQty,
        ),
      );
    }
    await LiveInStreamCheckout.payBagLines(
      context: context,
      lines: payLines,
      liveId: widget.liveId,
      playbackId: widget.playbackId,
      isLive: widget.isLive,
      liveSellerId: widget.liveSellerId,
      shippingMethod: LiveInStreamCheckout.shippingCarrier,
    );
  }

  Future<void> _openManageSheet(_LiveBagItemGroup group) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.transparent,
      backgroundColor: _kLiveBagBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _LiveBagManageSheet(
        group: group,
        stock: _stockByItemId[group.liveItemId],
        liveId: widget.liveId,
        buyerId: widget.buyerId,
        loadRows: widget.loadRows,
        onChanged: _afterMutation,
      ),
    );
  }
}

/// Banner destacado quando a vendedora aceitou (P13).
class _LiveBagAcceptedBanner extends StatelessWidget {
  const _LiveBagAcceptedBanner({
    required this.reservations,
    this.awaitingSellerPrice = false,
    this.directPayPhase,
    this.lightChrome = false,
  });

  final List<LiveReservationRequestsRow> reservations;
  final bool awaitingSellerPrice;
  /// `null` = ainda sem checkout · `reservado` · `aguarda_confirmacao`
  final String? directPayPhase;
  final bool lightChrome;

  @override
  Widget build(BuildContext context) {
    final qty = reservations.fold<int>(
      0,
      (a, r) => a + (r.requestedQty < 1 ? 1 : r.requestedQty),
    );
    final String message;
    if (awaitingSellerPrice) {
      message =
          'Reserva aceite · $qty un. · aguarda que a vendedora defina o preço';
    } else if (directPayPhase == 'aguarda_confirmacao') {
      message = 'Prova enviada · $qty un. · aguarda o vendedor';
    } else if (directPayPhase == 'reservado') {
      message =
          'Venda aceite · $qty un. · vê os dados e confirma o pagamento';
    } else if (directPayPhase == 'reserva_pendente') {
      message =
          'Pedido enviado · $qty un. · aguarda a vendedora aceitar';
    } else {
      message = 'Reserva aceite · $qty un. · tens 5 dias para pagar';
    }
    final fg = lightChrome ? const Color(0xFF007782) : _kLiveBagTeal;
    final bg = lightChrome
        ? const Color(0xFFE0F4F5)
        : _kLiveBagTeal.withValues(alpha: 0.18);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: fg, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBagItemCard extends StatelessWidget {
  const _LiveBagItemCard({
    super.key,
    required this.group,
    required this.stock,
    required this.resolveProduct,
    this.lrrLineMetaById = const {},
    this.pendingDirectOrder,
    this.onPay,
    this.onShowPaymentDetails,
    this.onConfirmPayment,
    this.onChangePaymentMethod,
    this.onManage,
    this.onUpdateQty,
    this.isPurchased = false,
    this.isCancelled = false,
    this.highlighted = false,
    this.lightChrome = false,
  });

  final _LiveBagItemGroup group;
  final LiveCatalogStockSnapshot? stock;
  final Map<String, Map<String, dynamic>> lrrLineMetaById;
  final Future<ProductsRow?> Function(LiveItemsRow item) resolveProduct;
  final OrdersRow? pendingDirectOrder;
  final VoidCallback? onPay;
  final VoidCallback? onShowPaymentDetails;
  final VoidCallback? onConfirmPayment;
  final VoidCallback? onChangePaymentMethod;
  final VoidCallback? onManage;
  final Future<void> Function(String requestId, int qty)? onUpdateQty;
  final bool isPurchased;
  final bool isCancelled;
  final bool highlighted;
  final bool lightChrome;

  LiveReservationRequestsRow? get _editableReservation {
    if (isCancelled || isPurchased || onUpdateQty == null) return null;
    final list = group.reservations.where((r) {
      final st = r.status ?? '';
      final kind = r.requestKindOrDefault;
      // Guaranteed qty is engine-owned — bag stepper must not offer edits.
      if (st == 'accepted' && kind == 'guaranteed') return false;
      return LiveReservationQueueService.buyerBagIsActionable(st) &&
          !LiveReservationQueueService.isBuyerCancelledReservation(
            status: st,
            notes: r.notes,
          );
    }).toList();
    if (list.isEmpty) return null;
    list.sort((a, b) {
      int rank(String? st) => st == 'pending' ? 0 : 1;
      final ra = rank(a.status);
      final rb = rank(b.status);
      if (ra != rb) return ra.compareTo(rb);
      final pa = a.queuePosition ?? 9999;
      final pb = b.queuePosition ?? 9999;
      if (pa != pb) return pa.compareTo(pb);
      final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ta.compareTo(tb);
    });
    return list.first;
  }

  @override
  Widget build(BuildContext context) {
    final light = lightChrome;
    final cardBg = light ? const Color(0xFFF7FAFB) : const Color(0xFF1A2228);
    final titleC = light ? const Color(0xFF101518) : Colors.white;
    final mutedC = light ? const Color(0xFF57636C) : Colors.white70;
    final row = group.catalogRow;
    final title = row == null
        ? 'Artigo live'
        : LiveVendorRefDisplay.itemDisplayName(
            title: row.title,
            refCode: row.refCode,
          );
    final ref = row?.refCode?.trim();
    final price = row?.price;
    final hasPayablePrice = LiveItemPriceGate.hasPayableUnitPrice(
      liveItemPrice: price,
    );
    final acceptedReservations =
        LiveReservationQueueService.buyerBagAcceptedRows(
      group.reservations,
    );
    final awaitingSellerPrice = !hasPayablePrice &&
        acceptedReservations.isNotEmpty &&
        !isCancelled &&
        !isPurchased;
    final priceLabel = hasPayablePrice
        ? '${price!.toStringAsFixed(2).replaceAll('.', ',')} €'
        : awaitingSellerPrice
            ? LiveItemPriceGate.awaitingSellerPriceLabel
            : LiveItemPriceGate.pendingPriceLabel;
    final size = row?.clothingSize?.trim();
    final color = row?.gender?.trim();
    final qtyTotal = group.reservations.fold<int>(
      0,
      (a, r) => a + (r.requestedQty < 1 ? 1 : r.requestedQty),
    );
    final availQty = stock?.availableQty ?? 0;

    final accent = isCancelled
        ? _kLiveBagMuted
        : isPurchased
            ? _kLiveBagTeal
            : _kLiveBagGreen;

    final payCandidates = group.reservations
        .where(
          (r) => LiveReservationQueueService.buyerCanPayBagReservation(r.status, notes: r.notes, requestKind: r.requestKind),
        )
        .toList();
    final directPhase = pendingDirectOrder == null
        ? null
        : normalizeOrderStatusKey(pendingDirectOrder!.status);
    final hasDirectPending = directPhase == 'reservado' ||
        directPhase == 'aguarda_confirmacao';
    final awaitingSellerAccept = directPhase == 'reserva_pendente';
    final showPay = onPay != null &&
        !isCancelled &&
        !isPurchased &&
        hasPayablePrice &&
        payCandidates.isNotEmpty &&
        !hasDirectPending &&
        !awaitingSellerAccept;
    final showDirectPayActions = hasDirectPending &&
        !isCancelled &&
        !isPurchased &&
        onShowPaymentDetails != null &&
        onConfirmPayment != null;
    final showManage = onManage != null &&
        !isCancelled &&
        !isPurchased &&
        group.reservations.any((r) {
          final st = r.status ?? '';
          return LiveReservationQueueService.buyerBagIsActionable(st) &&
              !LiveReservationQueueService.isBuyerCancelledReservation(
                status: st,
                notes: r.notes,
              );
        });

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: highlighted
            ? _kLiveBagTeal.withValues(alpha: light ? 0.12 : 0.12)
            : (light ? cardBg : Colors.white.withValues(alpha: 0.06)),
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(
          color: highlighted
              ? _kLiveBagTeal
              : (light
                  ? const Color(0xFFD5DDE3)
                  : accent.withValues(alpha: 0.35)),
          width: highlighted ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (acceptedReservations.isNotEmpty && !isCancelled && !isPurchased)
            _LiveBagAcceptedBanner(
              reservations: acceptedReservations,
              awaitingSellerPrice: awaitingSellerPrice,
              directPayPhase: directPhase,
              lightChrome: light,
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: FleaberRadius.circularSm,
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: row?.photoUrl?.trim().isNotEmpty == true
                      ? BatataCachedNetworkImage(
                          imageUrl: row!.photoUrl!.trim(),
                          fit: BoxFit.cover,
                          placeholderColor: light
                              ? const Color(0xFFE8EDF2)
                              : const Color(0xFF222222),
                        )
                      : ColoredBox(
                          color: light
                              ? const Color(0xFFE8EDF2)
                              : const Color(0xFF1E262C),
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: mutedC,
                            size: 22,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: titleC,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      priceLabel,
                      style: GoogleFonts.inter(
                        color: hasPayablePrice
                            ? (light
                                ? const Color(0xFF007782)
                                : accent)
                            : mutedC,
                        fontWeight: FontWeight.w800,
                        fontSize: hasPayablePrice ? 13 : 11,
                      ),
                    ),
                    if (color != null && color.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Cor: $color',
                        style: GoogleFonts.inter(color: mutedC, fontSize: 11),
                      ),
                    ],
                    if (size != null && size.isNotEmpty) ...[
                      Text(
                        'Tam: $size',
                        style: GoogleFonts.inter(color: mutedC, fontSize: 11),
                      ),
                    ],
                    if (ref != null && ref.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _refChip(ref, light: light),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: light
                      ? const Color(0xFFE0F4F5)
                      : accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${group.reservations.length} reserva${group.reservations.length == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                    color: light ? const Color(0xFF007782) : accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Estado',
                style: GoogleFonts.inter(
                  color: light ? mutedC : Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_editableReservation != null && onUpdateQty != null)
                _BagQtyStepper(
                  lightChrome: light,
                  qty: _editableReservation!.requestedQty < 1
                      ? 1
                      : _editableReservation!.requestedQty,
                  // Pending / unguaranteed do not hold stock — ceiling is
                  // canonical available_qty (NOT total, NOT avail+current).
                  maxQty: (() {
                    final avail = (stock?.availableQty ?? 0).clamp(0, 99);
                    final cur = _editableReservation!.requestedQty < 1
                        ? 1
                        : _editableReservation!.requestedQty;
                    final ceiling = avail < 1 ? cur : avail;
                    return ceiling.clamp(1, 99);
                  })(),
                  onChanged: (q) => onUpdateQty!(
                    _editableReservation!.id ?? '',
                    q,
                  ),
                )
              else
                Text(
                  'Qty $qtyTotal',
                  style: GoogleFonts.inter(
                    color: light ? titleC : Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final r in group.reservations)
                ..._statusChipsForReservation(r, availQty, light: light),
            ],
          ),
          if (!isCancelled && !isPurchased && availQty > 0) ...[
            const SizedBox(height: 4),
            Text(
              '$availQty un. disponíveis na live',
              style: GoogleFonts.inter(
                color: light
                    ? mutedC
                    : Colors.white.withValues(alpha: 0.55),
                fontSize: 10,
              ),
            ),
          ],
          if (showPay || showManage || showDirectPayActions || awaitingSellerAccept) ...[
            const SizedBox(height: 10),
            if (awaitingSellerAccept) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: _kLiveBagAmber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _kLiveBagAmber.withValues(alpha: 0.55),
                  ),
                ),
                child: Text(
                  'Aguarda a vendedora aceitar o pedido. Depois aparecem os dados de pagamento aqui.',
                  style: GoogleFonts.inter(
                    color: light
                        ? const Color(0xFF7A4E00)
                        : _kLiveBagAmber,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
              if (showManage) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: onManage,
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        light ? const Color(0xFF101518) : Colors.white70,
                    side: BorderSide(
                      color: light
                          ? const Color(0xFFD5DDE3)
                          : Colors.white.withValues(alpha: 0.25),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(
                    'Gerir reservas',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ] else if (showDirectPayActions) ...[
              FleaberPrimaryButton(
                label: 'Ver dados de pagamento',
                height: 40,
                borderRadius: 12,
                onPressed: onShowPaymentDetails,
              ),
              if (directPhase == 'reservado') ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: onConfirmPayment,
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: Text(
                      'Confirmar pagamento',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kLiveBagTeal,
                      side: const BorderSide(color: _kLiveBagTeal),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
              ],
              if (onChangePaymentMethod != null) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: onChangePaymentMethod,
                  child: Text(
                    'Alterar método de pagamento',
                    style: GoogleFonts.inter(
                      color: light
                          ? const Color(0xFF007782)
                          : Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              if (showManage) ...[
                const SizedBox(height: 4),
                OutlinedButton(
                  onPressed: onManage,
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        light ? const Color(0xFF101518) : Colors.white70,
                    side: BorderSide(
                      color: light
                          ? const Color(0xFFD5DDE3)
                          : Colors.white.withValues(alpha: 0.25),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(
                    'Gerir reservas',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ] else
              Row(
                children: [
                  if (showManage)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onManage,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: light
                              ? const Color(0xFF101518)
                              : Colors.white70,
                          side: BorderSide(
                            color: light
                                ? const Color(0xFFD5DDE3)
                                : Colors.white.withValues(alpha: 0.25),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text(
                          'Gerir reservas',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  if (showManage && showPay) const SizedBox(width: 8),
                  if (showPay)
                    Expanded(
                      child: FleaberPrimaryButton(
                        label: 'Pagar',
                        height: 40,
                        borderRadius: 12,
                        onPressed: onPay,
                      ),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _refChip(String ref, {required bool light}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: light
            ? const Color(0xFFEEF2F4)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Ref. ${LiveVendorRefDisplay.formatRef(ref)}',
        style: GoogleFonts.inter(
          color: light ? const Color(0xFF57636C) : Colors.white54,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<Widget> _statusChipsForReservation(
    LiveReservationRequestsRow r,
    int availableQty, {
    required bool light,
  }) {
    final st = r.status ?? '';
    final rid = r.id?.trim() ?? '';
    final meta = rid.isEmpty ? null : lrrLineMetaById[rid];
    final kind = r.requestKindOrDefault;
    final need = r.requestedQty < 1 ? 1 : r.requestedQty;
    final metaAvail = (meta?['available_qty'] as num?)?.toInt();
    final unavailableByMetaStock =
        metaAvail != null && metaAvail < need && st == 'pending';
    final unavailableByLocalStock = metaAvail == null &&
        stock != null &&
        availableQty < need &&
        st == 'pending' &&
        (kind == 'bag_hold_none' || kind == 'approval_pending');
    final unavailable = _metaMarksUnavailable(meta) ||
        unavailableByMetaStock ||
        unavailableByLocalStock;

    if (unavailable) {
      return [
        LiveBagBuyerStateChip(
          label: LiveBagBuyerStateCopy.unavailable,
          color: const Color(0xFFE57373),
          onLightBackground: light,
        ),
      ];
    }

    if (st == 'pending' &&
        LiveReservationQueueService.notesNeedQtyConfirm(r.notes)) {
      return [
        LiveBagBuyerStateChip(
          label: LiveBagBuyerStateCopy.approvalPending,
          color: _kLiveBagAmber,
          infoText: LiveBagBuyerStateCopy.approvalPendingInfo,
          onLightBackground: light,
        ),
      ];
    }
    if (st == 'rejected' &&
        LiveReservationQueueService.notesNeedQtyConfirm(r.notes) &&
        !(r.notes ?? '').contains('superseded')) {
      return [
        LiveBagBuyerStateChip(
          label: 'Quantidade não aceite',
          color: _kLiveBagMuted,
          onLightBackground: light,
        ),
      ];
    }
    if (st == 'accepted') {
      if (kind == 'guaranteed') {
        final reservedLabel = LiveReservationQueueService.buyerBagStatusLabel(
          st,
          requestKind: kind,
          expiresAt: r.expiresAt,
          notes: r.notes,
        );
        return [
          LiveBagBuyerStateChip(
            label: reservedLabel,
            color: _kLiveBagGreen,
            onLightBackground: light,
          ),
        ];
      }
      final hasDirect = pendingDirectOrder != null;
      final directPhase = hasDirect
          ? normalizeOrderStatusKey(pendingDirectOrder!.status)
          : null;
      final chipLabel = !LiveItemPriceGate.hasPayableUnitPrice(
        liveItemPrice: group.catalogRow?.price,
      )
          ? LiveItemPriceGate.acceptedAwaitingPriceChip
          : directPhase == 'aguarda_confirmacao'
              ? 'Prova enviada'
              : directPhase == 'reserva_pendente'
                  ? 'Aguarda aceite'
                  : hasDirect
                      ? 'Confirma o pagamento'
                      : LiveItemPriceGate.acceptedReadyToPayChip;
      return [
        LiveBagBuyerStateChip(
          label: chipLabel,
          color: _kLiveBagTeal,
          fontSize: 10,
          onLightBackground: light,
        ),
      ];
    }
    if (st == 'pending') {
      final semantic = LiveReservationQueueService.buyerBagStatusLabel(
        st,
        requestKind: kind,
        notes: r.notes,
        expiresAt: r.expiresAt,
      );
      final lineState = LiveReservationQueueService.commercialLineState(
        status: st,
        requestKind: kind,
      );
      final color =
          kind == 'bag_hold_none' ? _kLiveBagAmber : const Color(0xFFFF9800);
      return [
        LiveBagBuyerStateChip(
          label: semantic,
          color: color,
          infoText: LiveBagBuyerStateCopy.infoTextForLineState(lineState),
          onLightBackground: light,
        ),
      ];
    }
    // Terminal / other — label only, never queue rank chips.
    final label = LiveReservationQueueService.buyerBagStatusLabel(
      st,
      notes: r.notes,
      requestKind: r.requestKind,
      expiresAt: r.expiresAt,
    );
    return [
      LiveBagBuyerStateChip(
        label: label,
        color: _kLiveBagMuted,
        onLightBackground: light,
      ),
    ];
  }

  static bool _metaMarksUnavailable(Map<String, dynamic>? meta) {
    if (meta == null) return false;
    final lineState = meta['line_state']?.toString().trim().toLowerCase();
    if (lineState == 'unavailable') return true;
    final u = meta['unavailable'];
    if (u == true || u == 1) return true;
    final s = u?.toString().trim().toLowerCase();
    return s == 'true' || s == 't' || s == '1';
  }
}

class _BagQtyStepper extends StatelessWidget {
  const _BagQtyStepper({
    required this.qty,
    required this.maxQty,
    required this.onChanged,
    this.lightChrome = false,
  });

  final int qty;
  final int maxQty;
  final ValueChanged<int> onChanged;
  final bool lightChrome;

  @override
  Widget build(BuildContext context) {
    final active = lightChrome ? const Color(0xFF007782) : Colors.white70;
    final disabled =
        lightChrome ? const Color(0xFFB0BEC5) : Colors.white24;
    final qtyFg = lightChrome ? const Color(0xFF101518) : Colors.white;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: qty <= 1 ? null : () => onChanged(qty - 1),
          icon: Icon(
            Icons.remove_circle_outline,
            color: qty <= 1 ? disabled : active,
            size: 20,
          ),
        ),
        Text(
          '$qty',
          style: GoogleFonts.inter(
            color: qtyFg,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: qty >= maxQty ? null : () => onChanged(qty + 1),
          icon: Icon(
            Icons.add_circle_outline,
            color: qty >= maxQty ? disabled : active,
            size: 20,
          ),
        ),
      ],
    );
  }
}

class _LiveBagPayPickerSheet extends StatefulWidget {
  const _LiveBagPayPickerSheet({
    required this.group,
    required this.reservations,
    required this.stockByItemId,
  });

  final _LiveBagItemGroup group;
  final List<LiveReservationRequestsRow> reservations;
  final Map<String, LiveCatalogStockSnapshot?> stockByItemId;

  @override
  State<_LiveBagPayPickerSheet> createState() => _LiveBagPayPickerSheetState();
}

class _LiveBagPayPickerSheetState extends State<_LiveBagPayPickerSheet> {
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    for (final r in widget.reservations) {
      final id = r.id?.trim() ?? '';
      if (id.isNotEmpty) _selected.add(id);
    }
  }

  bool _isWaitlist(LiveReservationRequestsRow r) {
    final stock = widget.stockByItemId[widget.group.liveItemId];
    return LiveReservationQueueService.isWaitlistPosition(
      queuePosition: r.queuePosition,
      stock: stock,
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.group.catalogRow;
    final title = row == null
        ? 'Artigo'
        : LiveVendorRefDisplay.itemDisplayName(
            title: row.title,
            refCode: row.refCode,
          );
    final bottom = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 12 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Escolhe as reservas que pretendes pagar',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            for (final r in widget.reservations) ...[
              _payPickerRow(r),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 8),
            FleaberPrimaryButton(
              label: 'Continuar pagamento (${_selected.length})',
              onPressed: _selected.isEmpty
                  ? null
                  : () {
                      final out = widget.reservations
                          .where((r) => _selected.contains(r.id?.trim() ?? ''))
                          .toList();
                      Navigator.pop(context, out);
                    },
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancelar',
                style: GoogleFonts.inter(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _payPickerRow(LiveReservationRequestsRow r) {
    final id = r.id?.trim() ?? '';
    final wait = _isWaitlist(r);
    final checked = _selected.contains(id);
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: FleaberRadius.circularSm,
      child: InkWell(
        onTap: id.isEmpty
            ? null
            : () => setState(() {
                  if (checked) {
                    _selected.remove(id);
                  } else {
                    _selected.add(id);
                  }
                }),
        borderRadius: FleaberRadius.circularSm,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Checkbox(
                value: checked,
                activeColor: FleaberPrimaryButton.kTeal,
                onChanged: id.isEmpty
                    ? null
                    : (v) => setState(() {
                          if (v == true) {
                            _selected.add(id);
                          } else {
                            _selected.remove(id);
                          }
                        }),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fila #${r.queuePosition ?? '—'}',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    if (r.createdAt != null)
                      Text(
                        LiveVendorSellerCopy.formatTime(r.createdAt),
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                wait ? 'Em espera' : 'Disponível',
                style: GoogleFonts.inter(
                  color: wait ? _kLiveBagAmber : _kLiveBagGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveBagManageSheet extends StatelessWidget {
  const _LiveBagManageSheet({
    required this.group,
    required this.stock,
    required this.liveId,
    required this.buyerId,
    required this.loadRows,
    required this.onChanged,
  });

  final _LiveBagItemGroup group;
  final LiveCatalogStockSnapshot? stock;
  final String liveId;
  final String buyerId;
  final Future<List<LiveReservationRequestsRow>> Function() loadRows;
  final Future<void> Function() onChanged;

  String _cancelledSubtitle(LiveReservationRequestsRow r) {
    final st = r.status ?? '';
    final n = (r.notes ?? '').toLowerCase();
    if (LiveReservationQueueService.isBuyerCancelledReservation(
      status: st,
      notes: r.notes,
    )) {
      return 'Cancelado por ti';
    }
    if (st == 'expired') return 'Expirado';
    if (st == 'rejected' && !n.contains('bag_removed')) {
      return 'Recusado pela vendedora';
    }
    return LiveReservationQueueService.buyerBagStatusLabel(
      st,
      notes: r.notes,
      queuePosition: r.queuePosition,
      requestKind: r.requestKind,
      expiresAt: r.expiresAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = group.catalogRow;
    final title = row == null
        ? 'Artigo'
        : LiveVendorRefDisplay.itemDisplayName(
            title: row.title,
            refCode: row.refCode,
          );
    final bottom = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 12 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Gerir reservas · $title',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            for (final r in group.reservations) ...[
              _manageRow(context, r),
              const SizedBox(height: 8),
            ],
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Fechar',
                style: GoogleFonts.inter(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _manageRow(BuildContext context, LiveReservationRequestsRow r) {
    final st = r.status ?? '';
    final actionable = LiveReservationQueueService.buyerBagIsActionable(st) &&
        !LiveReservationQueueService.isBuyerCancelledReservation(
          status: st,
          notes: r.notes,
        );
    final statusLabel = actionable
        ? LiveReservationQueueService.buyerBagStatusLabel(
            st,
            notes: r.notes,
            requestKind: r.requestKind,
            expiresAt: r.expiresAt,
          )
        : _cancelledSubtitle(r);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: FleaberRadius.circularSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusLabel,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Qty ${r.requestedQty < 1 ? 1 : r.requestedQty}',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ),
          if (actionable)
            TextButton(
              onPressed: () async {
                final isGuaranteed = st == 'accepted' &&
                    r.requestKindOrDefault == 'guaranteed';
                if (isGuaranteed) {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF1A2228),
                      title: Text(
                        'Cancelar reserva?',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      content: Text(
                        'Libertas o stock imediatamente. Isto não conta como falha de confiança.',
                        style: GoogleFonts.inter(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Manter'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(
                            'Cancelar reserva',
                            style: GoogleFonts.inter(
                              color: const Color(0xFFE57373),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                  try {
                    await LiveReservationQueueService()
                        .cancelGuaranteedReservation(requestId: r.id ?? '');
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    await onChanged();
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Não foi possível cancelar a reserva: $e'),
                      ),
                    );
                  }
                  return;
                }
                try {
                  await LiveReservationQueueService().removeFromLiveBag(
                    requestId: r.id ?? '',
                    liveItemId: group.liveItemId,
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  await onChanged();
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Não foi possível remover: $e'),
                    ),
                  );
                }
              },
              child: Text(
                st == 'accepted' && r.requestKindOrDefault == 'guaranteed'
                    ? 'Cancelar reserva'
                    : 'Remover',
              ),
            ),
        ],
      ),
    );
  }
}

class _MarketplaceBagLineCard extends StatelessWidget {
  const _MarketplaceBagLineCard({
    required this.line,
    this.lightChrome = false,
  });

  final Map<String, dynamic> line;
  final bool lightChrome;

  @override
  Widget build(BuildContext context) {
    final state = line['line_state']?.toString() ?? 'approval_pending';
    final qty = (line['requested_qty'] as num?)?.toInt() ?? 1;
    final expiresRaw = line['expires_at']?.toString();
    DateTime? expiresAt;
    if (expiresRaw != null && expiresRaw.isNotEmpty) {
      expiresAt = DateTime.tryParse(expiresRaw);
    }
    final label = switch (state) {
      'guaranteed' => expiresAt != null
          ? LiveBagBuyerStateCopy.guaranteedUntil(expiresAt)
          : LiveBagBuyerStateCopy.guaranteedFallback,
      'approval_pending' => LiveBagBuyerStateCopy.approvalPending,
      'unavailable' => LiveBagBuyerStateCopy.unavailable,
      _ => LiveBagBuyerStateCopy.immediatePayment,
    };
    final color = switch (state) {
      'guaranteed' => _kLiveBagGreen,
      'unavailable' => const Color(0xFFE57373),
      'approval_pending' => const Color(0xFFFF9800),
      _ => _kLiveBagAmber,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: lightChrome
            ? const Color(0xFFF7FAFB)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(
          color: lightChrome
              ? const Color(0xFFD5DDE3)
              : color.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LiveBagBuyerStateChip(
                  label: label,
                  color: color,
                  infoText: LiveBagBuyerStateCopy.infoTextForLineState(state),
                  fontSize: 10,
                  onLightBackground: lightChrome,
                ),
                const SizedBox(height: 4),
                Text(
                  'Origem: Marketplace · qty $qty',
                  style: GoogleFonts.inter(
                    color: lightChrome
                        ? const Color(0xFF57636C)
                        : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
