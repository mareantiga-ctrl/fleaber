import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/utils/fleaber_radius.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_in_stream_checkout.dart';
import '/utils/live_item_price_gate.dart';
import '/utils/live_reservation_queue_service.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/live_bag_checkout_sheet.dart';
import '/widgets/live_vendor_ops_ui.dart';

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
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.transparent,
      backgroundColor: _kLiveBagBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => _LiveBagSheetBody(
        liveId: liveId,
        buyerId: buyerId,
        catalogByItemId: catalogByItemId,
        loadRows: loadRows,
        fetchStock: fetchStock,
        resolveProduct: resolveProduct,
        openSingleCheckout: openSingleCheckout,
        openMultiCheckout: openMultiCheckout,
        playbackId: playbackId,
        isLive: isLive,
        liveSellerId: liveSellerId,
        onBagChanged: onBagChanged,
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

/// Uma unidade no ranking global do saco (qty>1 → várias posições).
class _SacoUnitSlot {
  const _SacoUnitSlot({
    required this.reservation,
    required this.unitIndex,
    required this.globalRank,
  });

  final LiveReservationRequestsRow reservation;
  final int unitIndex;
  final int globalRank;
}

class _LiveBagSheetBody extends StatefulWidget {
  const _LiveBagSheetBody({
    required this.liveId,
    required this.buyerId,
    required this.catalogByItemId,
    required this.loadRows,
    required this.fetchStock,
    required this.resolveProduct,
    required this.openSingleCheckout,
    required this.openMultiCheckout,
    this.playbackId,
    required this.isLive,
    this.liveSellerId,
    this.onBagChanged,
  });

  final String liveId;
  final String buyerId;
  final Map<String, LiveItemsRow> catalogByItemId;
  final Future<List<LiveReservationRequestsRow>> Function() loadRows;
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

  @override
  State<_LiveBagSheetBody> createState() => _LiveBagSheetBodyState();
}

class _LiveBagSheetBodyState extends State<_LiveBagSheetBody> {
  List<LiveReservationRequestsRow> _rows = const [];
  bool _loading = true;
  bool _cancelledExpanded = false;
  final Map<String, LiveCatalogStockSnapshot?> _stockByItemId = {};
  late Map<String, LiveItemsRow> _catalogByItemId;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _catalogByItemId = Map<String, LiveItemsRow>.from(widget.catalogByItemId);
    unawaited(_reload());
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) unawaited(_reload(silent: true));
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _reload({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final next = await widget.loadRows();
    final itemIds = next
        .map((r) => (r.liveItemId ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    for (final id in itemIds) {
      final row = widget.catalogByItemId[id];
      if (row != null) {
        _stockByItemId[id] = await widget.fetchStock(row);
      }
    }
    if (!mounted) return;
    setState(() {
      _rows = next;
      _loading = false;
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

    final inBagN = _countReservations(inBag);
    final cancelN = _countReservations(cancelled);

    final maxH = MediaQuery.sizeOf(context).height * 0.72;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Saco da live',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$inBagN no saco · $cancelN cancelados',
                        style: GoogleFonts.inter(
                          color: _kLiveBagMuted,
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
            else if (_rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Ainda não tens artigos no saco.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.white70),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (inBag.isNotEmpty) ...[
                        _sectionHeader('No saco', inBagN),
                        for (final g in inBag)
                          _LiveBagItemCard(
                            group: g,
                            stock: _stockByItemId[g.liveItemId],
                            sacoUnitSlots: _sacoUnitSlotsForGroup(g),
                            resolveProduct: widget.resolveProduct,
                            onPay: () => _openPayPicker(g),
                            onManage: () => _openManageSheet(g),
                            onUpdateQty: (requestId, qty) => _updateReservationQty(
                              requestId,
                              qty,
                              liveItemId: g.liveItemId,
                            ),
                          ),
                      ],
                      if (purchased.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _sectionHeader(
                          '✓ Comprados',
                          _countReservations(purchased),
                        ),
                        for (final g in purchased)
                          _LiveBagItemCard(
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
                                  '⚫ Cancelados ($cancelN)',
                                  style: GoogleFonts.inter(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  _cancelledExpanded
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_cancelledExpanded)
                          for (final g in cancelled)
                            _LiveBagItemCard(
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
            if (!_loading && _rows.isNotEmpty) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await widget.openMultiCheckout(_rows);
                },
                child: Text(
                  'Finalizar compra (vários artigos)',
                  style: GoogleFonts.inter(
                    color: _kLiveBagTeal,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Ranking por artigo: cada unidade pendente (#1, #2, #3…) na fila desse item.
  List<_SacoUnitSlot> _sacoUnitSlotsForGroup(_LiveBagItemGroup group) {
    final pending = group.reservations
        .where((r) => (r.status ?? '') == 'pending')
        .toList()
      ..sort((a, b) {
        final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return ta.compareTo(tb);
      });
    final out = <_SacoUnitSlot>[];
    var rank = 0;
    for (final r in pending) {
      final qty = r.requestedQty < 1 ? 1 : r.requestedQty;
      for (var u = 1; u <= qty; u++) {
        rank++;
        out.add(_SacoUnitSlot(
          reservation: r,
          unitIndex: rank,
          globalRank: rank,
        ));
      }
    }
    return out;
  }

  Widget _sectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Text(
        '$title ($count)',
        style: GoogleFonts.inter(
          color: Colors.white,
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
          (r) => LiveReservationQueueService.buyerCanPayBagReservation(
            r.status,
            notes: r.notes,
          ),
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

void _showWaitlistInfoDialog(BuildContext context, int availableQty) {
  final avail = availableQty < 0 ? 0 : availableQty;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A2329),
      title: Text(
        'Posição na fila',
        style: GoogleFonts.inter(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
      content: Text(
        avail <= 0
            ? 'Neste momento não há unidades confirmadas disponíveis. '
                'O número da tua posição indica a ordem dos pedidos; '
                'quando a vendedora confirmar stock, os primeiros da fila '
                'podem ser aceites e pagos.'
            : 'Há mais pedidos na fila do que unidades disponíveis ($avail '
                'confirmada${avail == 1 ? '' : 's'} neste momento). '
                'O número a laranja mostra a tua ordem — à medida que vão '
                'saindo pedidos à tua frente, a tua vez aproxima-se. '
                'Quando chegares à frente e houver stock, a vendedora pode '
                'aceitar e podes pagar.',
        style: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.88),
          fontSize: 13,
          height: 1.45,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            'Percebi',
            style: GoogleFonts.inter(
              color: _kLiveBagTeal,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Banner destacado quando a vendedora aceitou (P13).
class _LiveBagAcceptedBanner extends StatelessWidget {
  const _LiveBagAcceptedBanner({
    required this.reservations,
    this.awaitingSellerPrice = false,
  });

  final List<LiveReservationRequestsRow> reservations;
  final bool awaitingSellerPrice;

  @override
  Widget build(BuildContext context) {
    final qty = reservations.fold<int>(
      0,
      (a, r) => a + (r.requestedQty < 1 ? 1 : r.requestedQty),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _kLiveBagTeal.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kLiveBagTeal.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: _kLiveBagTeal, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              awaitingSellerPrice
                  ? 'Reserva aceite · $qty un. · aguarda que a vendedora defina o preço'
                  : 'Reserva aceite pela vendedora · $qty un. · tens 5 dias para pagar',
              style: GoogleFonts.inter(
                color: _kLiveBagTeal,
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
    required this.group,
    required this.stock,
    required this.resolveProduct,
    this.sacoUnitSlots = const [],
    this.onPay,
    this.onManage,
    this.onUpdateQty,
    this.isPurchased = false,
    this.isCancelled = false,
  });

  final _LiveBagItemGroup group;
  final LiveCatalogStockSnapshot? stock;
  final List<_SacoUnitSlot> sacoUnitSlots;
  final Future<ProductsRow?> Function(LiveItemsRow item) resolveProduct;
  final VoidCallback? onPay;
  final VoidCallback? onManage;
  final Future<void> Function(String requestId, int qty)? onUpdateQty;
  final bool isPurchased;
  final bool isCancelled;

  LiveReservationRequestsRow? get _editableReservation {
    if (isCancelled || isPurchased || onUpdateQty == null) return null;
    final list = group.reservations.where((r) {
      final st = r.status ?? '';
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
    final unitSlotsForGroup = _unitSlotsForGroup();
    var hasWaitlist = false;
    for (final slot in unitSlotsForGroup) {
      if (LiveReservationQueueService.isWaitlistUnit(
        unitIndex: slot.unitIndex,
        stock: stock,
      )) {
        hasWaitlist = true;
        break;
      }
    }

    final accent = isCancelled
        ? _kLiveBagMuted
        : isPurchased
            ? _kLiveBagTeal
            : _kLiveBagGreen;

    final payCandidates = group.reservations
        .where(
          (r) => LiveReservationQueueService.buyerCanPayBagReservation(
            r.status,
            notes: r.notes,
          ),
        )
        .toList();
    final showPay = onPay != null &&
        !isCancelled &&
        !isPurchased &&
        hasPayablePrice &&
        payCandidates.isNotEmpty;
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
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (acceptedReservations.isNotEmpty && !isCancelled && !isPurchased)
            _LiveBagAcceptedBanner(
              reservations: acceptedReservations,
              awaitingSellerPrice: awaitingSellerPrice,
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
                          placeholderColor: const Color(0xFF222222),
                        )
                      : const ColoredBox(color: Color(0xFF1E262C)),
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
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      priceLabel,
                      style: GoogleFonts.inter(
                        color: hasPayablePrice
                            ? accent
                            : Colors.white.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w800,
                        fontSize: hasPayablePrice ? 13 : 11,
                      ),
                    ),
                    if (color != null && color.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Cor: $color',
                        style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                    if (size != null && size.isNotEmpty) ...[
                      Text(
                        'Tam: $size',
                        style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                    if (ref != null && ref.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _refChip(ref),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${group.reservations.length} reserva${group.reservations.length == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                    color: accent,
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
                'As tuas posições',
                style: GoogleFonts.inter(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (hasWaitlist && !isCancelled && !isPurchased) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _showWaitlistInfoDialog(context, availQty),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: _kLiveBagAmber.withValues(alpha: 0.95),
                  ),
                ),
              ],
              const Spacer(),
              if (_editableReservation != null && onUpdateQty != null)
                _BagQtyStepper(
                  qty: _editableReservation!.requestedQty < 1
                      ? 1
                      : _editableReservation!.requestedQty,
                  maxQty: (stock?.totalQty ?? 99).clamp(1, 99),
                  onChanged: (q) => onUpdateQty!(
                    _editableReservation!.id ?? '',
                    q,
                  ),
                )
              else
                Text(
                  'Qty $qtyTotal',
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final r in group.reservations)
                ..._statusChipsForReservation(r, availQty),
            ],
          ),
          if (!isCancelled && !isPurchased && availQty > 0) ...[
            const SizedBox(height: 4),
            Text(
              '$availQty un. disponíveis na live',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 10,
              ),
            ),
          ],
          if (showPay || showManage) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (showManage)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onManage,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
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

  Widget _refChip(String ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Ref. ${LiveVendorRefDisplay.formatRef(ref)}',
        style: GoogleFonts.inter(
          color: Colors.white54,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<_SacoUnitSlot> _unitSlotsForGroup() {
    final ids = group.reservations
        .map((r) => r.id?.trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();
    return sacoUnitSlots
        .where((s) => ids.contains(s.reservation.id?.trim() ?? ''))
        .toList();
  }

  List<Widget> _statusChipsForReservation(
    LiveReservationRequestsRow r,
    int availableQty,
  ) {
    final st = r.status ?? '';
    if (st == 'pending' &&
        LiveReservationQueueService.notesNeedQtyConfirm(r.notes)) {
      return [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kLiveBagAmber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border:
                    Border.all(color: _kLiveBagAmber.withValues(alpha: 0.55)),
              ),
              child: Text(
                'Aguarda confirmação da vendedora',
                style: GoogleFonts.inter(
                  color: _kLiveBagAmber,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ..._positionChipsForReservation(r),
          ],
        ),
      ];
    }
    if (st == 'rejected' &&
        LiveReservationQueueService.notesNeedQtyConfirm(r.notes) &&
        !(r.notes ?? '').contains('superseded')) {
      return [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _kLiveBagMuted.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Quantidade não aceite',
            style: GoogleFonts.inter(
              color: _kLiveBagMuted,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ];
    }
    if (st == 'accepted') {
      return [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kLiveBagTeal.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kLiveBagTeal.withValues(alpha: 0.55)),
              ),
              child: Text(
                'Aceite · pronto a pagar',
                style: GoogleFonts.inter(
                  color: _kLiveBagTeal,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ];
    }
    return _positionChipsForReservation(r);
  }

  List<Widget> _positionChipsForReservation(LiveReservationRequestsRow r) {
    final st = r.status ?? '';
    if (st != 'pending') return const [];
    final rid = r.id?.trim() ?? '';
    final slots = sacoUnitSlots
        .where((s) => (s.reservation.id?.trim() ?? '') == rid)
        .toList();
    if (slots.isEmpty) {
      final qty = r.requestedQty < 1 ? 1 : r.requestedQty;
      return [
        for (var u = 1; u <= qty; u++) _positionChipForUnit(u, u),
      ];
    }
    return [
      for (final slot in slots)
        _positionChipForUnit(slot.globalRank, slot.unitIndex),
    ];
  }

  Widget _positionChipForUnit(int globalRank, int unitIndex) {
    if (globalRank < 1 || unitIndex < 1) return const SizedBox.shrink();
    final wait = LiveReservationQueueService.isWaitlistUnit(
      unitIndex: unitIndex,
      stock: stock,
    );
    final color = wait ? _kLiveBagAmber : _kLiveBagGreen;
    final label = wait ? 'Espera #$globalRank' : '#$globalRank';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _BagQtyStepper extends StatelessWidget {
  const _BagQtyStepper({
    required this.qty,
    required this.maxQty,
    required this.onChanged,
  });

  final int qty;
  final int maxQty;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: qty <= 1 ? null : () => onChanged(qty - 1),
          icon: const Icon(Icons.remove_circle_outline,
              color: Colors.white70, size: 20),
        ),
        Text(
          '$qty',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: qty >= maxQty ? null : () => onChanged(qty + 1),
          icon: const Icon(Icons.add_circle_outline,
              color: Colors.white70, size: 20),
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
    final wait = st == 'pending' &&
        LiveReservationQueueService.isWaitlistPosition(
          queuePosition: r.queuePosition,
          stock: stock,
        );

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
                  'Fila #${r.queuePosition ?? '—'}',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  actionable
                      ? (wait
                          ? 'Lista de espera · sem stock confirmado'
                          : 'No saco')
                      : _cancelledSubtitle(r),
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
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
                      content: Text('Não foi possível cancelar: $e'),
                    ),
                  );
                }
              },
              child: const Text('Cancelar'),
            ),
        ],
      ),
    );
  }
}
