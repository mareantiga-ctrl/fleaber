import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/backend/supabase/supabase.dart';
import '/utils/live_bag_copy.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_item_price_gate.dart';
import '/utils/live_reservation_queue_service.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/live_bag_checkout_sheet.dart';
import '/widgets/live_vendor_ops_ui.dart';

import '../data/hub_models.dart';
import '../hub_actions.dart';
import '../hub_live_reservation_ui.dart';
import '../theme/hub_theme.dart';
import 'hub_facebook_recover_cta.dart';

/// Saco / reservas da compradora nesta live Hub — sheet modal, sem página autónoma.
abstract final class HubLiveBagSheet {
  static Future<void> show(
    BuildContext context, {
    required String liveId,
    required String sellerId,
    required Map<String, HubLiveItem> itemsById,
    required Future<List<LiveReservationRequestsRow>> Function() loadRows,
    Future<Map<String, dynamic>?> Function()? loadSellerBagMeta,
    HubReservationSummary? summary,
    bool psDemo = false,
    bool needsFacebookLogin = false,
    VoidCallback? onContinueWithFacebook,
    VoidCallback? onChanged,
  }) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = _HubLiveBagSheetBody(
      liveId: liveId,
      sellerId: sellerId,
      itemsById: itemsById,
      loadRows: loadRows,
      loadSellerBagMeta: loadSellerBagMeta,
      summary: summary,
      psDemo: psDemo,
      needsFacebookLogin: needsFacebookLogin,
      onContinueWithFacebook: onContinueWithFacebook,
      onChanged: onChanged,
      lightChrome: true,
      sidePanel: wide,
    );
    if (wide) {
      return showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Fechar saco',
        barrierColor: Colors.black.withValues(alpha: 0.35),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (ctx, anim, secondary) {
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => body,
    );
  }
}

class _HubLiveBagSheetBody extends StatefulWidget {
  const _HubLiveBagSheetBody({
    required this.liveId,
    required this.sellerId,
    required this.itemsById,
    required this.loadRows,
    this.loadSellerBagMeta,
    this.summary,
    this.psDemo = false,
    this.needsFacebookLogin = false,
    this.onContinueWithFacebook,
    this.onChanged,
    this.lightChrome = false,
    this.sidePanel = false,
  });

  final String liveId;
  final String sellerId;
  final Map<String, HubLiveItem> itemsById;
  final Future<List<LiveReservationRequestsRow>> Function() loadRows;
  final Future<Map<String, dynamic>?> Function()? loadSellerBagMeta;
  final HubReservationSummary? summary;
  final bool psDemo;
  final bool needsFacebookLogin;
  final VoidCallback? onContinueWithFacebook;
  final VoidCallback? onChanged;
  final bool lightChrome;
  final bool sidePanel;

  @override
  State<_HubLiveBagSheetBody> createState() => _HubLiveBagSheetBodyState();
}

class _HubLiveBagSheetBodyState extends State<_HubLiveBagSheetBody> {
  List<LiveReservationRequestsRow> _rows = const [];
  List<Map<String, dynamic>> _marketplaceLines = const [];
  /// Catálogo hidratado (RPC) quando o item já não está no bundle Hub.
  final Map<String, HubLiveItem> _hydratedItems = {};
  bool _loading = true;
  Timer? _refreshTimer;
  Timer? _countdownTimer;

  HubReservationSummary get _summary =>
      widget.summary ?? HubReservationSummary.fromRows(_rows);

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) unawaited(_reload(silent: true));
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _rows.any((r) => r.expiresAt != null)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _reload({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final next = await widget.loadRows();
      var mp = const <Map<String, dynamic>>[];
      final metaFn = widget.loadSellerBagMeta;
      if (metaFn != null) {
        try {
          final meta = await metaFn();
          final raw = meta?['marketplace_adapter_lines'];
          if (raw is List) {
            mp = raw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        } catch (_) {}
      }
      // Hidratar artigos aceites/ocultos por RLS (preço no saco).
      for (final r in next) {
        final id = (r.liveItemId ?? '').trim();
        if (id.isEmpty) continue;
        final known = widget.itemsById[id] ?? _hydratedItems[id];
        if (known != null && known.price != null && known.price! > 0) continue;
        final row = await LiveCatalogStockService.fetchLiveItemById(id);
        if (row == null) continue;
        final seed = widget.itemsById.values.isNotEmpty
            ? widget.itemsById.values.first
            : null;
        _hydratedItems[id] = HubLiveItem(
          id: id,
          liveId: (row.liveId ?? widget.liveId).trim(),
          sellerId: widget.sellerId.trim(),
          sellerHandle: seed?.sellerHandle ?? '',
          refCode: row.refCode,
          title: row.title,
          photoUrl: row.photoUrl,
          price: row.price,
          itemKind: row.itemKind,
        );
      }
      if (!mounted) return;
      setState(() {
        _rows = next;
        _marketplaceLines = mp;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _cancelGuarantee(LiveReservationRequestsRow row) async {
    final id = row.id?.trim() ?? '';
    if (id.isEmpty) return;
    final light = widget.lightChrome;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: light ? Colors.white : const Color(0xFF1A2228),
        title: Text(
          'Cancelar reserva?',
          style: GoogleFonts.inter(
            color: light ? const Color(0xFF101518) : Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'Libertas o stock imediatamente. Isto não conta como falha de confiança.',
          style: GoogleFonts.inter(
            color: light ? const Color(0xFF57636C) : Colors.white70,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Manter',
              style: GoogleFonts.inter(
                color: light ? const Color(0xFF101518) : null,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Cancelar reserva',
              style: GoogleFonts.inter(
                color: const Color(0xFFB71C1C),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await LiveReservationQueueService().cancelGuaranteedReservation(
        requestId: id,
      );
      widget.onChanged?.call();
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível cancelar: $e')),
      );
    }
  }

  HubLiveItem? _itemFor(LiveReservationRequestsRow row) {
    final id = row.liveItemId?.trim() ?? '';
    if (id.isEmpty) return null;
    return widget.itemsById[id] ?? _hydratedItems[id];
  }

  Map<String, LiveItemsRow> _catalogForCheckout(
    Iterable<LiveReservationRequestsRow> payRows,
  ) {
    final out = <String, LiveItemsRow>{};
    for (final r in payRows) {
      final id = (r.liveItemId ?? '').trim();
      if (id.isEmpty || out.containsKey(id)) continue;
      final hub = widget.itemsById[id] ?? _hydratedItems[id];
      if (hub == null) continue;
      out[id] = LiveItemsRow({
        'id': hub.id,
        'live_id': hub.liveId,
        'ref_code': hub.refCode,
        'title': hub.title,
        'photo_url': hub.photoUrl,
        'price': hub.price,
        'seller_id': hub.sellerId,
      });
    }
    return out;
  }

  Future<void> _openPay() async {
    final payable = _displayRows
        .where(
          (r) => LiveReservationQueueService.buyerCanPayBagReservation(r.status, notes: r.notes, requestKind: r.requestKind),
        )
        .toList();
    if (payable.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ainda não há reservas aceites prontas a pagar. '
            'Espera a vendedora aceitar.',
          ),
        ),
      );
      return;
    }

    final baseCatalog = _catalogForCheckout(payable);
    final catalog = await LiveCatalogStockService.refreshCatalogByItemIds(
      baseCatalog,
      payable.map((r) => (r.liveItemId ?? '').trim()),
    );
    await LiveBagCheckoutSheet.show(
      context: context,
      rows: payable,
      catalogByItemId: catalog,
      resolveProduct: (item) => LiveItemPriceGate.resolveProductForCheckout(
        itemRow: item,
        sellerId: widget.sellerId,
        liveId: widget.liveId,
      ),
      liveId: widget.liveId,
      isLive: true,
      liveSellerId: widget.sellerId,
      onPaymentStarted: widget.onChanged,
      fleahubChrome: true,
    );
    widget.onChanged?.call();
    if (mounted) await _reload(silent: true);
  }

  static String _expiresLabel(DateTime? expiresAt) {
    if (expiresAt == null) return '';
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return 'Expirado';
    if (diff.inHours >= 1) {
      return 'Expira em ${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    }
    if (diff.inMinutes >= 1) {
      return 'Expira em ${diff.inMinutes}m';
    }
    return 'Expira em ${diff.inSeconds}s';
  }

  List<LiveReservationRequestsRow> get _displayRows => _rows.where((r) {
        final s = r.status ?? '';
        if (LiveReservationQueueService.isBuyerCancelledReservation(
          status: s,
          notes: r.notes,
        )) {
          return false;
        }
        return LiveReservationQueueService.buyerBagIsActionable(s) ||
            s == 'converted' ||
            s == 'rejected' ||
            s == 'expired';
      }).toList();

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final summary = _summary;
    final rows = _displayRows;
    final light = widget.lightChrome;
    final titleFg = light ? const Color(0xFF101518) : Colors.white;
    final mutedFg = light ? const Color(0xFF57636C) : Colors.white70;
    final handleFg = light ? const Color(0xFFD5DDE3) : Colors.white24;
    final sheetBg = light ? Colors.white : const Color(0xFF11181C);

    Widget sheet(ScrollController? scrollController) {
        return ColoredBox(
          color: sheetBg,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            if (!widget.sidePanel)
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: handleFg,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'O teu saco',
                          style: GoogleFonts.interTight(
                            color: titleFg,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (summary.hasAny) ...[
                          const SizedBox(height: 4),
                          Text(
                            summary.headline,
                            style: GoogleFonts.inter(
                              color: titleFg,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (summary.subline.isNotEmpty)
                            Text(
                              summary.subline,
                              style: GoogleFonts.inter(
                                color: mutedFg,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: mutedFg),
                  ),
                ],
              ),
            ),
            if (summary.hasAny)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (summary.confirmed > 0)
                      _SummaryChip(
                        label: '${summary.confirmed} confirm.',
                        color: HubReservationStatusUi.green,
                      ),
                    if (summary.inQueue > 0)
                      _SummaryChip(
                        label: '${summary.inQueue} em fila',
                        color: HubReservationStatusUi.yellow,
                      ),
                    if (summary.pendingAwaiting > 0)
                      _SummaryChip(
                        label: '${summary.pendingAwaiting} pend.',
                        color: HubReservationStatusUi.orange,
                      ),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: HubTheme.teal),
                    )
                  : (rows.isEmpty && _marketplaceLines.isEmpty)
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: widget.needsFacebookLogin &&
                                    widget.onContinueWithFacebook != null
                                ? HubFacebookRecoverCta(
                                    mode: HubFacebookRecoverMode
                                        .needsFacebookLogin,
                                    compact: false,
                                    onPressed: widget.onContinueWithFacebook,
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        widget.sellerId.trim().isEmpty
                                            ? 'Ainda não tens artigos no saco.'
                                            : 'Ainda não tens artigos no saco desta vendedora.',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                          color: mutedFg,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      OutlinedButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              const Color(0xFF007782),
                                          side: const BorderSide(
                                            color: Color(0xFF007782),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                        ),
                                        child: Text(
                                          'Continuar a explorar',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 16),
                          itemCount: rows.length + _marketplaceLines.length,
                          itemBuilder: (context, i) {
                            if (i < rows.length) {
                              final row = rows[i];
                              return _ReservationTile(
                                row: row,
                                item: _itemFor(row),
                                expiresLabel: _expiresLabel(row.expiresAt),
                                psDemo: widget.psDemo,
                                onCancelGuarantee: row.status == 'accepted' &&
                                        row.requestKindOrDefault ==
                                            'guaranteed'
                                    ? () => unawaited(
                                          _cancelGuarantee(row),
                                        )
                                    : null,
                              );
                            }
                            final mp = _marketplaceLines[i - rows.length];
                            return _HubMarketplaceLineTile(line: mp);
                          },
                        ),
            ),
            if (rows.any(
              (r) => LiveReservationQueueService.buyerCanPayBagReservation(r.status, notes: r.notes, requestKind: r.requestKind),
            ))
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 12),
                child: FleaberPrimaryButton(
                  label: 'Pagar',
                  height: 44,
                  onPressed: () => unawaited(_openPay()),
                ),
              ),
            if (rows.any((r) => (r.status ?? '') == 'accepted') &&
                !rows.any(
                  (r) => LiveReservationQueueService.buyerCanPayBagReservation(r.status, notes: r.notes, requestKind: r.requestKind),
                ))
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 12),
                child: FleaberPrimaryButton(
                  label: 'Checkout completo na app',
                  height: 44,
                  onPressed: () => HubActions.openInstallApp(),
                ),
              ),
          ],
        ),
        );
    }

    if (widget.sidePanel) {
      return sheet(null);
    }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) => sheet(scrollController),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = color == HubReservationStatusUi.green
        ? const Color(0xFF1B5E20)
        : color == HubReservationStatusUi.red
            ? const Color(0xFF7F1D1D)
            : const Color(0xFF7A4E00);
    final bg = color == HubReservationStatusUi.green
        ? const Color(0xFFE8F5E9)
        : color == HubReservationStatusUi.red
            ? const Color(0xFFFFEBEE)
            : const Color(0xFFFFF3E0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: text,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ReservationTile extends StatelessWidget {
  const _ReservationTile({
    required this.row,
    required this.item,
    required this.expiresLabel,
    this.psDemo = false,
    this.onCancelGuarantee,
  });

  final LiveReservationRequestsRow row;
  final HubLiveItem? item;
  final String expiresLabel;
  final bool psDemo;
  final VoidCallback? onCancelGuarantee;

  @override
  Widget build(BuildContext context) {
    final status = row.status ?? '';
    final qty = row.requestedQty < 1 ? 1 : row.requestedQty;
    final ref = item?.refCode?.trim();
    final title = item?.title?.trim();
    final price = item?.price;
    final priceLabel = price != null
        ? NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(price)
        : null;
    final source = row.source;
    final sourceLabel = HubReservationStatusUi.sourceBadge(
      source,
      psDemo: psDemo,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD5DDE3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 56,
              height: 56,
              child: item?.photoUrl?.trim().isNotEmpty == true
                  ? BatataCachedNetworkImage(
                      imageUrl: item!.photoUrl!.trim(),
                      fit: BoxFit.cover,
                    )
                  : const ColoredBox(
                      color: Color(0xFFE8EEF1),
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: Color(0xFF57636C),
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
                HubReservationStatusUi.statusChip(
                  status,
                  notes: row.notes,
                  queuePosition: row.queuePosition,
                  requestKind: row.requestKind,
                  expiresAt: row.expiresAt,
                  lightChrome: true,
                ),
                const SizedBox(height: 4),
                Text(
                  LiveVendorRefDisplay.itemDisplayName(
                    title: title,
                    refCode: ref,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF101518),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (priceLabel != null)
                      Text(
                        priceLabel,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF007782),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    if (source != 'fleaber_live' && sourceLabel.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        sourceLabel,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF0D47A1),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (expiresLabel.isNotEmpty &&
                        LiveReservationQueueService.buyerBagIsActionable(
                            status)) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          expiresLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: const Color(0xFF7A4E00),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (onCancelGuarantee != null)
                  TextButton(
                    onPressed: onCancelGuarantee,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB71C1C),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 26),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Cancelar reserva',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '×$qty',
            style: GoogleFonts.inter(
              color: const Color(0xFF101518),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _HubMarketplaceLineTile extends StatelessWidget {
  const _HubMarketplaceLineTile({required this.line});

  final Map<String, dynamic> line;

  @override
  Widget build(BuildContext context) {
    final state = line['line_state']?.toString() ?? 'approval_pending';
    final qty = (line['requested_qty'] as num?)?.toInt() ?? 1;
    final label = switch (state) {
      'guaranteed' => LiveBagBuyerStateCopy.guaranteedFallback,
      'approval_pending' => LiveBagBuyerStateCopy.approvalPending,
      'unavailable' => LiveBagBuyerStateCopy.unavailable,
      _ => LiveBagBuyerStateCopy.immediatePayment,
    };
    final color = switch (state) {
      'guaranteed' => HubReservationStatusUi.green,
      'unavailable' => HubReservationStatusUi.red,
      'approval_pending' => HubReservationStatusUi.orange,
      _ => HubReservationStatusUi.yellow,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD5DDE3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: state == 'guaranteed'
                        ? const Color(0xFFE8F5E9)
                        : state == 'unavailable'
                            ? const Color(0xFFFFEBEE)
                            : const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withValues(alpha: 0.55)),
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      color: state == 'guaranteed'
                          ? const Color(0xFF1B5E20)
                          : state == 'unavailable'
                              ? const Color(0xFF7F1D1D)
                              : const Color(0xFF7A4E00),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Origem: Marketplace',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF57636C),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '×$qty',
            style: GoogleFonts.inter(
              color: const Color(0xFF101518),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
