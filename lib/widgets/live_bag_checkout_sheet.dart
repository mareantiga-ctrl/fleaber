import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/utils/fee_calculator.dart';
import '/utils/fleaber_radius.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_in_stream_checkout.dart';
import '/utils/live_reservation_queue_service.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/live_vendor_ops_ui.dart';
import '/widgets/fleaber_primary_button.dart';

/// Checkout do saco live: escolher linhas a pagar + notas (estilo loja online).
class LiveBagCheckoutSheet extends StatefulWidget {
  const LiveBagCheckoutSheet({
    super.key,
    required this.rows,
    required this.catalogByItemId,
    required this.resolveProduct,
    required this.liveId,
    required this.playbackId,
    required this.isLive,
    required this.liveSellerId,
    this.onPaymentStarted,
  });

  final List<LiveReservationRequestsRow> rows;
  final Map<String, LiveItemsRow> catalogByItemId;
  final Future<ProductsRow?> Function(LiveItemsRow? item) resolveProduct;
  final String liveId;
  final String? playbackId;
  final bool isLive;
  final String? liveSellerId;
  final VoidCallback? onPaymentStarted;

  /// Uma linha de pagamento por artigo live (agrega vários pedidos da mesma ref.).
  static List<LiveReservationRequestsRow> mergePayableByLiveItem(
    List<LiveReservationRequestsRow> rows,
  ) {
    final payable = rows
        .where(
          (r) => LiveReservationQueueService.buyerCanPayBagReservation(
            r.status,
            notes: r.notes,
          ),
        )
        .toList();
    final byItem = <String, List<LiveReservationRequestsRow>>{};
    for (final r in payable) {
      final key = (r.liveItemId ?? '').trim();
      byItem.putIfAbsent(key.isEmpty ? '_' : key, () => []).add(r);
    }
    final merged = <LiveReservationRequestsRow>[];
    for (final list in byItem.values) {
      list.sort((a, b) {
        int rank(String? st) => st == 'accepted' ? 0 : 1;
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
      final primary = list.first;
      var qty = 0;
      for (final r in list) {
        qty += r.requestedQty < 1 ? 1 : r.requestedQty;
      }
      final data = Map<String, dynamic>.from(primary.data);
      data['requested_qty'] = qty;
      merged.add(LiveReservationRequestsRow(data));
    }
    merged.sort((a, b) {
      final pa = a.queuePosition ?? 9999;
      final pb = b.queuePosition ?? 9999;
      return pa.compareTo(pb);
    });
    return merged;
  }

  static Future<void> show({
    required BuildContext context,
    required List<LiveReservationRequestsRow> rows,
    required Map<String, LiveItemsRow> catalogByItemId,
    required Future<ProductsRow?> Function(LiveItemsRow? item) resolveProduct,
    required String liveId,
    String? playbackId,
    required bool isLive,
    String? liveSellerId,
    VoidCallback? onPaymentStarted,
  }) async {
    final payable = mergePayableByLiveItem(rows);
    if (payable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não há artigos prontos para pagar no saco.'),
        ),
      );
      return;
    }

    final itemIds = <String>{
      for (final r in payable)
        if ((r.liveItemId ?? '').trim().isNotEmpty)
          (r.liveItemId ?? '').trim(),
    };
    for (final itemId in itemIds) {
      final stock = await LiveCatalogStockService.fetch(itemId);
      final itemRow = catalogByItemId[itemId];
      final pendingForItem = LiveReservationQueueService.buyerBagPendingPayRows(
        rows.where((x) => (x.liveItemId ?? '').trim() == itemId),
      );
      if (pendingForItem.isEmpty) continue;
      final ok = await LiveReservationQueueService.gateBagPayQtyOrPrompt(
        context: context,
        liveId: liveId,
        liveItemId: itemId,
        payRows: pendingForItem,
        stock: stock,
        refLabel: LiveVendorRefDisplay.itemDisplayName(
          title: itemRow?.title,
          refCode: itemRow?.refCode,
        ),
      );
      if (!ok) return;
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.transparent,
      backgroundColor: const Color(0xFF11181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => LiveBagCheckoutSheet(
        rows: payable,
        catalogByItemId: catalogByItemId,
        resolveProduct: resolveProduct,
        liveId: liveId,
        playbackId: playbackId,
        isLive: isLive,
        liveSellerId: liveSellerId,
        onPaymentStarted: onPaymentStarted,
      ),
    );
  }

  @override
  State<LiveBagCheckoutSheet> createState() => _LiveBagCheckoutSheetState();
}

class _LiveBagCheckoutSheetState extends State<LiveBagCheckoutSheet> {
  final _notesController = TextEditingController();
  final Set<String> _selectedIds = {};
  final Map<String, int> _payQtyByRequestId = {};
  bool _paying = false;
  String _shippingMethod = LiveInStreamCheckout.shippingCarrier;

  @override
  void initState() {
    super.initState();
    for (final r in widget.rows) {
      final id = r.id?.trim() ?? '';
      if (id.isEmpty) continue;
      _selectedIds.add(id);
      _payQtyByRequestId[id] = r.requestedQty < 1 ? 1 : r.requestedQty;
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  int _maxQtyFor(LiveReservationRequestsRow r) {
    return r.requestedQty < 1 ? 1 : r.requestedQty;
  }

  Future<void> _confirmPay() async {
    if (_paying || _selectedIds.isEmpty) return;
    setState(() => _paying = true);
    final notes = _notesController.text.trim();
    final notesOrNull = notes.isEmpty ? null : notes;
    try {
      final toPay = <LiveReservationRequestsRow>[];
      for (final r in widget.rows) {
        final id = r.id?.trim() ?? '';
        if (id.isEmpty || !_selectedIds.contains(id)) continue;
        toPay.add(r);
      }
      if (toPay.isEmpty) return;

      if (!mounted) return;
      final hostCtx = Navigator.of(context, rootNavigator: true).context;
      Navigator.pop(context);

      final payLines = <LiveBagCheckoutPayLine>[];
      for (final r in toPay) {
        final itemRow = widget.catalogByItemId[(r.liveItemId ?? '').trim()];
        final product = await widget.resolveProduct(itemRow);
        if (product == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Sem preço para ${LiveVendorRefDisplay.itemDisplayName(
                  title: itemRow?.title,
                  refCode: itemRow?.refCode,
                )}.',
              ),
            ),
          );
          return;
        }
        final id = r.id?.trim() ?? '';
        payLines.add(
          LiveBagCheckoutPayLine(
            product: product,
            itemRow: itemRow,
            request: r,
            payQty: _payQtyByRequestId[id] ?? 1,
          ),
        );
      }

      if (payLines.length > 1 && hostCtx.mounted) {
        ScaffoldMessenger.of(hostCtx).showSnackBar(
          SnackBar(
            content: Text(
              'A pagar ${payLines.length} artigos num único checkout Stripe.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      await LiveInStreamCheckout.payBagLines(
        context: hostCtx,
        lines: payLines,
        liveId: widget.liveId,
        playbackId: widget.playbackId,
        isLive: widget.isLive,
        liveSellerId: widget.liveSellerId,
        shippingMethod: _shippingMethod,
        checkoutNotes: notesOrNull,
        onPaymentStarted: widget.onPaymentStarted,
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  double _itemsSubtotalForSelection() {
    var sum = 0.0;
    for (final r in widget.rows) {
      final id = r.id?.trim() ?? '';
      if (id.isEmpty || !_selectedIds.contains(id)) continue;
      final itemRow = widget.catalogByItemId[(r.liveItemId ?? '').trim()];
      final unit = itemRow?.price ?? 0.0;
      final qty = (_payQtyByRequestId[id] ?? 1).clamp(1, 99);
      sum += unit * qty;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final itemsSubtotal = _itemsSubtotalForSelection();
    final shippingEur =
        LiveInStreamCheckout.shippingCostForMethod(_shippingMethod);
    final protectionEur = calculateFleaberProtectionFee(
      itemsSubtotal,
      shippingEur: shippingEur,
    );
    final totalEur = calculateFleaberBuyerTotal(
      itemPriceEur: itemsSubtotal,
      shippingEur: shippingEur,
      includeProtectionFee: true,
    );
    final selectedCount = _selectedIds.length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 12 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Finalizar compra',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Escolhe o que queres pagar agora. Vários artigos = um único pagamento Stripe.',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.42,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final r = widget.rows[i];
                  final id = r.id?.trim() ?? '';
                  final itemRow =
                      widget.catalogByItemId[(r.liveItemId ?? '').trim()];
                  final name = LiveVendorRefDisplay.itemDisplayName(
                    title: itemRow?.title,
                    refCode: itemRow?.refCode,
                  );
                  final selected = _selectedIds.contains(id);
                  final maxQ = _maxQtyFor(r);
                  final qty = (_payQtyByRequestId[id] ?? 1).clamp(1, maxQ);
                  return Material(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: FleaberRadius.circularMd,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: selected,
                            activeColor: FleaberPrimaryButton.kTeal,
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selectedIds.add(id);
                                } else {
                                  _selectedIds.remove(id);
                                }
                              });
                            },
                          ),
                          if (itemRow?.photoUrl?.trim().isNotEmpty == true) ...[
                            ClipRRect(
                              borderRadius: FleaberRadius.circularSm,
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: BatataCachedNetworkImage(
                                  imageUrl: itemRow!.photoUrl!.trim(),
                                  fit: BoxFit.cover,
                                  placeholderColor: const Color(0xFF222222),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                if (r.queuePosition != null)
                                  Text(
                                    'Fila #${r.queuePosition}',
                                    style: GoogleFonts.inter(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                Row(
                                  children: [
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      onPressed: qty <= 1
                                          ? null
                                          : () => setState(() {
                                                _payQtyByRequestId[id] =
                                                    qty - 1;
                                              }),
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                        color: Colors.white70,
                                        size: 20,
                                      ),
                                    ),
                                    Text(
                                      '$qty',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      onPressed: qty >= maxQ
                                          ? null
                                          : () => setState(() {
                                                _payQtyByRequestId[id] =
                                                    qty + 1;
                                              }),
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                        color: Colors.white70,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _shippingMethod,
              dropdownColor: const Color(0xFF1A2228),
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Envio',
                labelStyle: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: FleaberRadius.circularMd,
                  borderSide: BorderSide.none,
                ),
              ),
              items: const [
                DropdownMenuItem(
                  value: LiveInStreamCheckout.shippingCarrier,
                  child: Text(LiveInStreamCheckout.shippingCarrier),
                ),
                DropdownMenuItem(
                  value: LiveInStreamCheckout.shippingHand,
                  child: Text(LiveInStreamCheckout.shippingHand),
                ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _shippingMethod = v);
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Portes: 3,50 € (transportadora) ou 0 € (mão). Seguro: 0,65 € + 5% sobre artigo+portes.',
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 10),
            ),
            if (selectedCount > 0) ...[
              const SizedBox(height: 10),
              LiveInStreamCheckout.checkoutTotalsBreakdown(
                itemsSubtotalEur: itemsSubtotal,
                shippingEur: shippingEur,
                protectionEur: protectionEur,
                totalEur: totalEur,
                lineCount: selectedCount,
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _notesController,
              maxLines: 2,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Notas para o vendedor (opcional)',
                hintStyle: GoogleFonts.inter(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: FleaberRadius.circularMd,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FleaberPrimaryButton(
              label: _paying ? 'A abrir pagamento…' : 'Pagar',
              loading: _paying,
              onPressed:
                  _selectedIds.isEmpty || _paying ? null : _confirmPay,
            ),
          ],
        ),
      ),
    );
  }
}
