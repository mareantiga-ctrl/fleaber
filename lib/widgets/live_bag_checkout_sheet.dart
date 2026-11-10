import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/hub/hub_bag_pay_diag.dart';
import '/utils/dpd_pudo_service.dart';
import '/utils/dpd_shipping_rates.dart';
import '/utils/fee_calculator.dart';
import '/utils/fleaber_radius.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_in_stream_checkout.dart';
import '/utils/live_item_price_gate.dart';
import '/utils/live_reservation_queue_service.dart';
import '/utils/order_shipment_weight.dart';
import '/utils/profile_shipping_requirements.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/dpd_pickup_picker_sheet.dart';
import '/widgets/live_vendor_ops_ui.dart';
import '/widgets/fleaber_checkout_ui.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/seller_consumer_rights_notice.dart';
import '/utils/seller_professional.dart';

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
    this.fleahubChrome = false,
  });

  final List<LiveReservationRequestsRow> rows;
  final Map<String, LiveItemsRow> catalogByItemId;
  final Future<ProductsRow?> Function(LiveItemsRow? item) resolveProduct;
  final String liveId;
  final String? playbackId;
  final bool isLive;
  final String? liveSellerId;
  final VoidCallback? onPaymentStarted;

  /// Hub FleaHub (fundo claro) — mesmo host visual do checkout marketplace.
  final bool fleahubChrome;

  /// Uma linha de pagamento por artigo live (agrega vários pedidos da mesma ref.).
  static List<LiveReservationRequestsRow> mergePayableByLiveItem(
    List<LiveReservationRequestsRow> rows,
  ) {
    final payable = rows
        .where(
          (r) => LiveReservationQueueService.buyerCanPayBagReservation(r.status, notes: r.notes, requestKind: r.requestKind),
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
    bool fleahubChrome = false,
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
    final freshCatalog = await LiveCatalogStockService.refreshCatalogByItemIds(
      catalogByItemId,
      itemIds,
    );
    for (final itemId in itemIds) {
      final stock = await LiveCatalogStockService.fetch(itemId);
      final itemRow = freshCatalog[itemId];
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

    Widget sheet(BuildContext ctx) => LiveBagCheckoutSheet(
          rows: payable,
          catalogByItemId: freshCatalog,
          resolveProduct: resolveProduct,
          liveId: liveId,
          playbackId: playbackId,
          isLive: isLive,
          liveSellerId: liveSellerId,
          onPaymentStarted: onPaymentStarted,
          fleahubChrome: fleahubChrome,
        );

    if (fleahubChrome) {
      return FleaberCheckoutUi.showHost<void>(
        context: context,
        builder: sheet,
      );
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.transparent,
      backgroundColor: const Color(0xFF11181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: sheet,
    );
  }

  @override
  State<LiveBagCheckoutSheet> createState() => _LiveBagCheckoutSheetState();
}

class _LiveBagCheckoutSheetState extends State<LiveBagCheckoutSheet> {
  final _notesController = TextEditingController();
  final Set<String> _selectedIds = {};
  final Map<String, int> _payQtyByRequestId = {};
  late List<LiveReservationRequestsRow> _rows;
  bool _paying = false;
  String _shippingMethod = LiveInStreamCheckout.shippingCarrier;
  /// Domicílio vs loja Pickup (só com envio DPD / carrier) — ZIP 130.
  String _deliveryMode = 'home'; // home | pickup
  DpdPudoPoint? _selectedPudo;
  FleaberDpdWeightBand? _checkoutWeightBand;
  String _paymentMethod = LiveInStreamCheckout.paymentInApp;
  bool _sellerAllowsDirectPayment = false;
  bool _sellerPaymentFlagsLoaded = false;
  ProfilesRow? _buyerProfile;

  @override
  void initState() {
    super.initState();
    _rows = List<LiveReservationRequestsRow>.from(widget.rows);
    for (final r in _rows) {
      final id = r.id?.trim() ?? '';
      if (id.isEmpty) continue;
      _selectedIds.add(id);
      _payQtyByRequestId[id] = r.requestedQty < 1 ? 1 : r.requestedQty;
    }
    unawaited(_loadSellerPaymentFlags());
    unawaited(_loadBuyerProfile());
    unawaited(_refreshBagWeight());
  }

  Future<void> _refreshBagWeight() async {
    final inputs = <FleaberShipmentWeightInput>[];
    for (final r in _rows) {
      final id = r.id?.trim() ?? '';
      if (id.isEmpty || !_selectedIds.contains(id)) continue;
      final itemRow = widget.catalogByItemId[(r.liveItemId ?? '').trim()];
      final product = await widget.resolveProduct(itemRow);
      if (product == null) continue;
      final qty = (_payQtyByRequestId[id] ?? 1).clamp(1, 99);
      inputs.add(
        FleaberShipmentWeightInput.fromProduct(product, quantity: qty),
      );
    }
    if (!mounted) return;
    if (inputs.isEmpty) {
      setState(() => _checkoutWeightBand = null);
      return;
    }
    final agg = fleaberAggregateShipmentWeight(inputs);
    setState(() {
      _checkoutWeightBand = agg.ok ? agg.band : null;
    });
  }

  Future<void> _loadBuyerProfile() async {
    try {
      final p = await ProfileShippingRequirements.fetchCurrentProfile();
      if (!mounted) return;
      setState(() => _buyerProfile = p);
    } catch (_) {}
  }

  /// Phase 4 bag_changed → Continuar: drop unavailable lines from checkout UI.
  void _applyRemainderLines(List<LiveBagCheckoutPayLine> remaining) {
    final next = <LiveReservationRequestsRow>[
      for (final line in remaining) line.request,
    ];
    final nextSelected = <String>{};
    final nextQty = <String, int>{};
    for (final line in remaining) {
      final id = line.request.id?.trim() ?? '';
      if (id.isEmpty) continue;
      nextSelected.add(id);
      nextQty[id] = line.payQty < 1 ? 1 : line.payQty;
    }
    setState(() {
      _rows = next;
      _selectedIds
        ..clear()
        ..addAll(nextSelected);
      _payQtyByRequestId
        ..clear()
        ..addAll(nextQty);
    });
  }

  Future<void> _loadSellerPaymentFlags() async {
    final sellerId = widget.liveSellerId?.trim() ?? '';
    if (sellerId.isEmpty) {
      if (mounted) setState(() => _sellerPaymentFlagsLoaded = true);
      return;
    }
    try {
      final rows = await ProfilesDirectoryTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', sellerId),
        limit: 1,
      );
      final allows =
          rows.isNotEmpty && rows.first.externalPaymentsEnabled;
      if (!mounted) return;
      setState(() {
        _sellerAllowsDirectPayment = allows;
        _sellerPaymentFlagsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _sellerPaymentFlagsLoaded = true);
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

  bool _selectionHasPayablePrice() {
    if (_selectedIds.isEmpty) return false;
    for (final r in _rows) {
      final id = r.id?.trim() ?? '';
      if (id.isEmpty || !_selectedIds.contains(id)) continue;
      final itemRow = widget.catalogByItemId[(r.liveItemId ?? '').trim()];
      if (!LiveItemPriceGate.hasPayableUnitPrice(liveItemPrice: itemRow?.price)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _showPayErrorDialog(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pagamento não avançou'),
        content: SingleChildScrollView(
          child: Text(message),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPay() async {
    if (_paying || _selectedIds.isEmpty) return;
    setState(() => _paying = true);
    final notes = _notesController.text.trim();
    final notesOrNull = notes.isEmpty ? null : notes;
    final isDirect =
        _paymentMethod == LiveInStreamCheckout.paymentDirect;
    HubBagPayDiag.log('confirm_pay_start', {
      'live_id': widget.liveId,
      'seller_id': widget.liveSellerId,
      'selected': _selectedIds.length,
      'payment': _paymentMethod,
      'shipping': _shippingMethod,
      'is_live': widget.isLive,
      'uid': currentUserUid,
    });
    try {
      final toPay = <LiveReservationRequestsRow>[];
      for (final r in _rows) {
        final id = r.id?.trim() ?? '';
        if (id.isEmpty || !_selectedIds.contains(id)) continue;
        toPay.add(r);
      }
      if (toPay.isEmpty) {
        HubBagPayDiag.log('confirm_pay_empty_selection');
        return;
      }

      if (ProfileShippingRequirements.checkoutNeedsCompleteProfile(
        shippingMethod: _shippingMethod,
        paymentMethod: _paymentMethod,
      )) {
        HubBagPayDiag.log('confirm_pay_profile_check');
        final ready =
            await ProfileShippingRequirements.ensureCheckoutReady(context);
        if (!ready) {
          HubBagPayDiag.log('confirm_pay_profile_blocked');
          return;
        }
      }

      if (_shippingMethod == LiveInStreamCheckout.shippingCarrier &&
          _deliveryMode == 'pickup' &&
          _selectedPudo == null) {
        HubBagPayDiag.log('confirm_pay_pickup_missing');
        if (mounted) {
          await _showPayErrorDialog(
            'Escolhe uma loja Pickup DPD para continuar.',
          );
        }
        return;
      }
      if (_shippingMethod == LiveInStreamCheckout.shippingCarrier &&
          _checkoutWeightBand == null) {
        HubBagPayDiag.log('confirm_pay_weight_missing');
        if (mounted) {
          await _showPayErrorDialog(
            kFleaberBuyerWeightMissingMessage,
          );
        }
        return;
      }

      if (!mounted) return;

      final payLines = <LiveBagCheckoutPayLine>[];
      for (final r in toPay) {
        final itemId = (r.liveItemId ?? '').trim();
        var itemRow = widget.catalogByItemId[itemId];
        if (itemId.isNotEmpty) {
          itemRow =
              await LiveCatalogStockService.fetchLiveItemById(itemId) ?? itemRow;
        }
        final product = await LiveItemPriceGate.resolveProductForCheckout(
          itemRow: itemRow,
          sellerId: widget.liveSellerId,
          liveId: widget.liveId,
          resolveProduct: (row) => widget.resolveProduct(row),
        );
        final unit = await LiveItemPriceGate.resolveFreshUnitPrice(
          liveItemId: itemId,
          fallbackLiveItemPrice: itemRow?.price,
          productPrice: product?.price,
          sellerId: widget.liveSellerId,
          liveId: widget.liveId,
          itemRow: itemRow,
        );
        if (product == null || unit == null) {
          LiveItemPriceGate.logCheckoutGate(
            'bag_confirm_pay_blocked',
            liveId: widget.liveId,
            sellerId: widget.liveSellerId,
            liveItemId: itemId,
            requestId: r.id,
            productId: product?.id,
            unit: unit,
            liveItemPrice: itemRow?.price,
            productPrice: product?.price,
            reason: product == null ? 'product_null' : 'unit_null',
          );
          HubBagPayDiag.log('confirm_pay_price_blocked', {
            'live_item_id': itemId,
            'reason': product == null ? 'product_null' : 'unit_null',
          });
          if (mounted) {
            await _showPayErrorDialog(LiveItemPriceGate.pendingPriceLabel);
          }
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

      HubBagPayDiag.log('confirm_pay_lines_ready', {
        'line_count': payLines.length,
        'qtys': payLines.map((l) => l.payQty).toList(),
        'product_ids': payLines.map((l) => l.product.id).toList(),
      });

      if (!isDirect && payLines.length > 1 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'A pagar ${payLines.length} artigos num único checkout Stripe.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      final ok = await LiveInStreamCheckout.payBagLines(
        context: context,
        lines: payLines,
        liveId: widget.liveId,
        playbackId: widget.playbackId,
        isLive: widget.isLive,
        liveSellerId: widget.liveSellerId,
        shippingMethod: _shippingMethod,
        paymentMethod: _paymentMethod,
        checkoutNotes: notesOrNull,
        shippingWeightBand: _checkoutWeightBand,
        pickupPoint: _shippingMethod == LiveInStreamCheckout.shippingCarrier &&
                _deliveryMode == 'pickup'
            ? _selectedPudo
            : null,
        deliveryHome: _shippingMethod == LiveInStreamCheckout.shippingCarrier &&
            _deliveryMode == 'home',
        onPaymentStarted: widget.onPaymentStarted,
        onAwaitingBuyerConfirm: () {
          if (!mounted) return;
          // Clear spinner before bag_changed dialog paints.
          _paying = false;
          setState(() {});
        },
        onRemainderAccepted: (remaining) {
          if (!mounted) return;
          _applyRemainderLines(remaining);
        },
      );
      HubBagPayDiag.log('confirm_pay_done', {'ok': ok});
      if (ok && mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      HubBagPayDiag.fail('confirm_pay_catch', e, {
        'live_id': widget.liveId,
      });
      if (mounted) {
        await _showPayErrorDialog(
          'Não foi possível confirmar: '
          '${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  double _itemsSubtotalForSelection() {
    var sum = 0.0;
    for (final r in _rows) {
      final id = r.id?.trim() ?? '';
      if (id.isEmpty || !_selectedIds.contains(id)) continue;
      final itemRow = widget.catalogByItemId[(r.liveItemId ?? '').trim()];
      final unit = LiveItemPriceGate.effectiveUnitPrice(
            liveItemPrice: itemRow?.price,
          ) ??
          0.0;
      final qty = (_payQtyByRequestId[id] ?? 1).clamp(1, 99);
      sum += unit * qty;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = mq.padding.bottom;
    // Windows taskbar / browser chrome: SafeArea no web costuma ser 0.
    final webClearance = kIsWeb ? 56.0 : 0.0;
    final itemsSubtotal = _itemsSubtotalForSelection();
    // ZIP 140: sem peso nos artigos → comprador escolhe escalão (não assumir 0–3).
    final bagBand = _checkoutWeightBand;
    final shippingEur = _shippingMethod == LiveInStreamCheckout.shippingHand
        ? 0.0
        : (bagBand == null
            ? 0.0
            : LiveInStreamCheckout.shippingCostForMethod(
                _shippingMethod,
                pickup: _deliveryMode == 'pickup',
                band: bagBand,
              ));
    final isDirect =
        _paymentMethod == LiveInStreamCheckout.paymentDirect;
    final protectionEur = isDirect
        ? 0.0
        : calculateFleaberProtectionFee(
            itemsSubtotal,
            shippingEur: shippingEur,
          );
    final totalEur = isDirect
        ? itemsSubtotal + shippingEur
        : calculateFleaberBuyerTotal(
            itemPriceEur: itemsSubtotal,
            shippingEur: shippingEur,
            includeProtectionFee: true,
          );
    final selectedCount = _selectedIds.length;
    final sheetH = (mq.size.height * 0.92).clamp(320.0, mq.size.height);
    final light = widget.fleahubChrome;
    final titleColor = light ? FleaberCheckoutUi.ink : Colors.white;
    final mutedColor = light ? FleaberCheckoutUi.muted : Colors.white70;
    final softMuted = light ? FleaberCheckoutUi.muted : Colors.white54;
    final cardColor = light
        ? FleaberCheckoutUi.cardBg
        : Colors.white.withValues(alpha: 0.06);
    final fieldFill = light
        ? const Color(0xFFF0F4F5)
        : Colors.white.withValues(alpha: 0.08);
    final dropdownBg =
        light ? Colors.white : const Color(0xFF1A2228);
    final fieldStyle = GoogleFonts.inter(
      color: titleColor,
      fontSize: 13,
    );

    Widget body = Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            light ? 8 : 14,
            16,
            12 + bottom + (light ? 8 : webClearance),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (light) const FleaberCheckoutHandle(),
              Text(
                'Finalizar compra',
                style: GoogleFonts.inter(
                  color: titleColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _sellerAllowsDirectPayment
                    ? 'Escolhe o que pagar e como: cartão na app ou MB WAY / transferência ao vendedor.'
                    : 'Escolhe o que queres pagar agora. Pagamento na app (cartão).',
                style: GoogleFonts.inter(color: mutedColor, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final r = _rows[i];
                          final id = r.id?.trim() ?? '';
                          final itemRow = widget
                              .catalogByItemId[(r.liveItemId ?? '').trim()];
                          final name = LiveVendorRefDisplay.itemDisplayName(
                            title: itemRow?.title,
                            refCode: itemRow?.refCode,
                          );
                          final selected = _selectedIds.contains(id);
                          final maxQ = _maxQtyFor(r);
                          final qty =
                              (_payQtyByRequestId[id] ?? 1).clamp(1, maxQ);
                          return Material(
                            color: cardColor,
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
                                      unawaited(_refreshBagWeight());
                                    },
                                  ),
                                  if (itemRow?.photoUrl?.trim().isNotEmpty ==
                                      true) ...[
                                    ClipRRect(
                                      borderRadius: FleaberRadius.circularSm,
                                      child: SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: BatataCachedNetworkImage(
                                          imageUrl: itemRow!.photoUrl!.trim(),
                                          fit: BoxFit.cover,
                                          placeholderColor:
                                              const Color(0xFF222222),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: GoogleFonts.inter(
                                            color: titleColor,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (r.queuePosition != null)
                                          Text(
                                            'Fila #${r.queuePosition}',
                                            style: GoogleFonts.inter(
                                              color: softMuted,
                                              fontSize: 11,
                                            ),
                                          ),
                                        Row(
                                          children: [
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                              onPressed: qty <= 1
                                                  ? null
                                                  : () {
                                                      setState(() {
                                                        _payQtyByRequestId[
                                                            id] = qty - 1;
                                                      });
                                                      unawaited(
                                                          _refreshBagWeight());
                                                    },
                                              icon: Icon(
                                                Icons.remove_circle_outline,
                                                color: mutedColor,
                                                size: 20,
                                              ),
                                            ),
                                            Text(
                                              '$qty',
                                              style: GoogleFonts.inter(
                                                color: titleColor,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                              onPressed: qty >= maxQ
                                                  ? null
                                                  : () {
                                                      setState(() {
                                                        _payQtyByRequestId[
                                                            id] = qty + 1;
                                                      });
                                                      unawaited(
                                                          _refreshBagWeight());
                                                    },
                                              icon: Icon(
                                                Icons.add_circle_outline,
                                                color: mutedColor,
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
                      const SizedBox(height: 10),
                      Text(
                        'Envio',
                        style: GoogleFonts.inter(
                          color: softMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // 3 modalidades ao mesmo nível (alinhado marketplace).
                      _BagDeliveryChoice(
                        selected: _shippingMethod ==
                                LiveInStreamCheckout.shippingCarrier &&
                            _deliveryMode == 'home',
                        title: 'Entrega em casa',
                        subtitle: 'DPD para a tua morada',
                        light: light,
                        onTap: () => setState(() {
                          _shippingMethod =
                              LiveInStreamCheckout.shippingCarrier;
                          _deliveryMode = 'home';
                          _selectedPudo = null;
                        }),
                      ),
                      const SizedBox(height: 6),
                      _BagDeliveryChoice(
                        selected: _shippingMethod ==
                                LiveInStreamCheckout.shippingCarrier &&
                            _deliveryMode == 'pickup',
                        title: 'Levantar numa loja Pickup',
                        subtitle: _selectedPudo == null
                            ? 'Escolhe o ponto na rede DPD'
                            : _selectedPudo!.name,
                        light: light,
                        onTap: () async {
                          final zip =
                              (_buyerProfile?.shippingPostalCode ?? '')
                                  .trim();
                          final city =
                              (_buyerProfile?.shippingCity ?? '').trim();
                          final picked = await showDpdPickupPickerSheet(
                            context,
                            initialZip: zip,
                            initialCity: city,
                          );
                          if (!mounted) return;
                          setState(() {
                            _shippingMethod =
                                LiveInStreamCheckout.shippingCarrier;
                            _deliveryMode = 'pickup';
                            if (picked != null) _selectedPudo = picked;
                          });
                        },
                      ),
                      const SizedBox(height: 6),
                      _BagDeliveryChoice(
                        selected: _shippingMethod ==
                            LiveInStreamCheckout.shippingHand,
                        title: LiveInStreamCheckout.shippingHandLabel,
                        subtitle: 'Combinas o encontro com o vendedor',
                        light: light,
                        onTap: () => setState(() {
                          _shippingMethod =
                              LiveInStreamCheckout.shippingHand;
                          _deliveryMode = 'home';
                          _selectedPudo = null;
                        }),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _paymentMethod,
                        dropdownColor: dropdownBg,
                        style: fieldStyle,
                        decoration: InputDecoration(
                          labelText: 'Pagamento',
                          labelStyle: GoogleFonts.inter(
                            color: softMuted,
                            fontSize: 12,
                          ),
                          filled: true,
                          fillColor: fieldFill,
                          border: OutlineInputBorder(
                            borderRadius: FleaberRadius.circularMd,
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: LiveInStreamCheckout.paymentInApp,
                            child: Text(LiveInStreamCheckout.paymentInApp),
                          ),
                          if (_sellerAllowsDirectPayment)
                            const DropdownMenuItem(
                              value: LiveInStreamCheckout.paymentDirect,
                              child:
                                  Text(LiveInStreamCheckout.paymentDirect),
                            ),
                        ],
                        onChanged: !_sellerPaymentFlagsLoaded
                            ? null
                            : (v) {
                                if (v != null) {
                                  setState(() => _paymentMethod = v);
                                }
                              },
                      ),
                      if (!_sellerAllowsDirectPayment &&
                          _sellerPaymentFlagsLoaded) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Este vendedor só aceita pagamento na app (cartão).',
                          style: GoogleFonts.inter(
                            color: softMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        isDirect
                            ? 'Portes DPD (Pickup/casa, IVA incl.) ou 0,00 € em mão. Sem seguro Fleaber no pagamento directo.'
                            : 'Portes DPD (Pickup/casa, IVA incl.) ou 0,00 € em mão. Seguro: 0,65 € + 5% sobre artigo + portes.',
                        style: GoogleFonts.inter(
                          color: softMuted,
                          fontSize: 10,
                        ),
                      ),
                      if (_shippingMethod ==
                          LiveInStreamCheckout.shippingCarrier) ...[
                        const SizedBox(height: 6),
                        Text(
                          kFleaberCheckoutShippingDeltaNotice,
                          style: GoogleFonts.inter(
                            color: softMuted,
                            fontSize: 10,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (_checkoutWeightBand == null)
                          Text(
                            kFleaberBuyerWeightMissingMessage,
                            style: GoogleFonts.inter(
                              color: const Color(0xFFB45309),
                              fontSize: 11,
                              height: 1.35,
                            ),
                          )
                        else
                          Text(
                            'Portes calculados automaticamente',
                            style: GoogleFonts.inter(
                              color: softMuted,
                              fontSize: 10,
                            ),
                          ),
                      ],
                      if (selectedCount > 0) ...[
                        const SizedBox(height: 10),
                        if (isDirect)
                          Text(
                            'Total a pagar ao vendedor: ${formatEuros(totalEur)}',
                            style: GoogleFonts.inter(
                              color: titleColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          )
                        else
                          Theme(
                            data: light
                                ? ThemeData.light()
                                : ThemeData.dark(),
                            child: LiveInStreamCheckout.checkoutTotalsBreakdown(
                              itemsSubtotalEur: itemsSubtotal,
                              shippingEur: shippingEur,
                              protectionEur: protectionEur,
                              totalEur: totalEur,
                              lineCount: selectedCount,
                            ),
                          ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: _notesController,
                        maxLines: 2,
                        style: fieldStyle,
                        decoration: InputDecoration(
                          hintText: 'Notas para o vendedor (opcional)',
                          hintStyle: GoogleFonts.inter(color: softMuted),
                          filled: true,
                          fillColor: fieldFill,
                          border: OutlineInputBorder(
                            borderRadius: FleaberRadius.circularMd,
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<Map<String, SellerTradePublicInfo>>(
                        future: SellerProfessionalCache.warm([
                          if ((widget.liveSellerId ?? '').trim().isNotEmpty)
                            widget.liveSellerId!.trim(),
                        ]),
                        builder: (context, snap) {
                          final sid = (widget.liveSellerId ?? '').trim();
                          final info = snap.data?[sid] ??
                              SellerTradePublicInfo.particular(
                                sid.isEmpty ? 'unknown' : sid,
                              );
                          return Theme(
                            data: ThemeData.light(),
                            child: SellerConsumerRightsNotice(info: info),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FleaberPrimaryButton(
                label: _paying
                    ? (isDirect ? 'A registar…' : 'A abrir pagamento…')
                    : (isDirect
                        ? 'Confirmar (MB WAY / transf.)'
                        : 'Pagar'),
                loading: _paying,
                onPressed: _selectedIds.isEmpty ||
                        _paying ||
                        !_selectionHasPayablePrice()
                    ? null
                    : _confirmPay,
              ),
            ],
          ),
        );

    if (light) {
      return SafeArea(top: false, child: body);
    }
    return SafeArea(
      top: false,
      child: SizedBox(height: sheetH, child: body),
    );
  }
}

class _BagDeliveryChoice extends StatelessWidget {
  const _BagDeliveryChoice({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.light,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final bool light;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? const Color(0xFF007782)
        : (light ? const Color(0xFFE0E3E7) : const Color(0xFF3A4550));
    final fill = selected
        ? (light
            ? const Color(0xFFE6F5F6)
            : const Color(0xFF007782).withValues(alpha: 0.18))
        : (light ? const Color(0xFFF5F7F8) : const Color(0xFF1A2228));
    final titleColor =
        light ? const Color(0xFF101518) : const Color(0xFFF1F4F8);
    final subColor =
        light ? const Color(0xFF57636C) : const Color(0xFF9AA5B1);
    return Material(
      color: fill,
      borderRadius: FleaberRadius.circularMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: FleaberRadius.circularMd,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: FleaberRadius.circularMd,
            border: Border.all(color: border, width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 20,
                color: selected
                    ? const Color(0xFF007782)
                    : subColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: subColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
