import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/widgets/batata_cached_image.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/batata_bundle_actions.dart';
import '/batata_reservation_actions.dart';
import '/chat_session_util.dart';
import '/hub/hub_bag_pay_diag.dart';
import '/order_cancel_eligibility.dart';
import '/utils/dpd_pudo_service.dart';
import '/utils/dpd_shipping_rates.dart';
import '/utils/fee_calculator.dart';
import '/utils/order_shipment_weight.dart';
import '/utils/fleaber_commerce_checkout.dart';
import '/utils/fleaber_logger.dart';
import '/utils/fleaber_radius.dart';
import '/utils/fleaber_stripe_checkout_context.dart';
import '/utils/fleaber_stripe_launch.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_item_price_gate.dart';
import '/utils/live_reservation_queue_service.dart';
import '/utils/live_system_chat_humanizer.dart';
import '/utils/profile_shipping_requirements.dart';
import '/widgets/fleaber_bag_changed_dialog.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/live_vendor_ops_ui.dart';

/// Linha do saco pronta para pagamento (checkout multi-artigo).
class LiveBagCheckoutPayLine {
  const LiveBagCheckoutPayLine({
    required this.product,
    required this.itemRow,
    required this.request,
    required this.payQty,
  });

  final ProductsRow product;
  final LiveItemsRow? itemRow;
  final LiveReservationRequestsRow request;
  final int payQty;
}

/// Phase 4 — after bag_changed, keep only lines the server still accepts.
///
/// Matches `available_lines` from `batata_commerce_checkout_revalidate` /
/// `bag_changed_confirmation_required` by reservation → live_item → product.
List<LiveBagCheckoutPayLine> filterBagPayLinesByAvailableLines({
  required List<LiveBagCheckoutPayLine> lines,
  required List<dynamic> availableLines,
}) {
  final byRid = <String>{};
  final byLiid = <String>{};
  final byPid = <String>{};
  for (final raw in availableLines) {
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    final rid = m['reservation_request_id']?.toString().trim() ?? '';
    final liid = m['live_item_id']?.toString().trim() ?? '';
    final pid = m['product_id']?.toString().trim() ?? '';
    if (rid.isNotEmpty) byRid.add(rid);
    if (liid.isNotEmpty) byLiid.add(liid);
    if (pid.isNotEmpty) byPid.add(pid);
  }
  if (byRid.isEmpty && byLiid.isEmpty && byPid.isEmpty) {
    return const [];
  }
  return lines.where((line) {
    final rid = line.request.id?.trim() ?? '';
    final liid = (line.itemRow?.id ?? line.request.liveItemId)?.trim() ?? '';
    final pid = line.product.id?.trim() ?? '';
    if (rid.isNotEmpty && byRid.contains(rid)) return true;
    if (liid.isNotEmpty && byLiid.contains(liid)) return true;
    if (pid.isNotEmpty && byPid.contains(pid)) return true;
    return false;
  }).toList(growable: false);
}

/// Checkout Stripe no player live (sem navegar para a página do artigo).
abstract final class LiveInStreamCheckout {
  /// Valor enviado ao Edge (allowlist). Texto UI: [shippingCarrierLabel].
  static const shippingCarrier = kFleaberShippingCarrierMethod;
  static const shippingHand = kFleaberShippingHandMethod;
  static const shippingCarrierLabel = kFleaberShippingCarrierLabel;
  static const shippingHandLabel = kFleaberShippingHandLabel;
  static const double shippingCarrierEur = kFleaberCarrierShippingEur;
  static const paymentInApp = 'Pagamento na app';
  static const paymentDirect =
      'Pagamento Direto ao Vendedor (MB WAY/Transf)';

  /// D2: impede double-tap / duas coroutines a criar encomenda+CPI em paralelo.
  static bool _submitLocked = false;

  static int euroCents(double value) => (value * 100).round();

  /// Após fechar o browser Stripe: settle na edge + reconciliar reservas/encomendas.
  /// Nunca bloqueia o UI do saco mais de ~20s (quota/rede lenta).
  static Future<void> afterStripeBrowserClosed({
    required String liveId,
    String? checkoutSessionId,
  }) async {
    try {
      await _afterStripeBrowserClosedBody(
        liveId: liveId,
        checkoutSessionId: checkoutSessionId,
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      unawaited(
        FleaberLogger.instance.logStripe(
          'browser_closed_timeout',
          data: {
            'live_id': liveId.trim(),
            'session_id': checkoutSessionId?.trim(),
            'error': e.toString(),
          },
        ),
      );
    }
  }

  static Future<void> _afterStripeBrowserClosedBody({
    required String liveId,
    String? checkoutSessionId,
  }) async {
    final sid = checkoutSessionId?.trim() ?? '';
    if (sid.isNotEmpty) {
      await FleaberStripeCheckoutContext.settleCheckoutSession(sid);
    }
    final pending = await FleaberStripeCheckoutContext.peek();
    if (pending == null) return;
    final lid = liveId.trim();
    if (lid.isEmpty) return;
    final orderId = pending['order_id']?.toString().trim() ?? '';
    if (orderId.isEmpty) return;
    final status = await FleaberStripeCheckoutContext.orderStatus(orderId);
    await FleaberLogger.instance.logStripe(
      'browser_closed',
      data: {
        'live_id': lid,
        'order_id': orderId,
        'status': status,
        'session_id': sid.isEmpty ? null : sid,
      },
    );
    if (status == 'pago') {
      await FleaberStripeCheckoutContext.reconcilePendingBagOrders(
        pending,
        liveId: lid,
      );
    }
  }

  /// B3: portes DPD Célia (Pickup vs Home) ou mão. Exige peso/escalão.
  static double shippingCostForMethod(
    String method, {
    bool pickup = false,
    double? weightKg,
    FleaberDpdWeightBand? band,
  }) {
    final m = method.trim().toLowerCase();
    if (m == shippingHand ||
        m.contains('mão') ||
        m.contains('mao') ||
        m == 'hand') {
      return 0.0;
    }
    return fleaberCheckoutDpdShippingEur(
      pickup: pickup,
      weightKg: weightKg,
      band: band,
    );
  }

  /// Bloqueia checkout quando a quantidade pedida excede stock disponível
  /// (reserva ainda não aceite pela vendedora).
  static bool checkoutQtyExceedsAvailable({
    required int selectedQuantity,
    required LiveCatalogStockSnapshot? liveStock,
    String? reservationStatus,
  }) {
    if (liveStock == null) return false;
    if (reservationStatus == 'accepted') return false;
    final sel = selectedQuantity < 1 ? 1 : selectedQuantity;
    if (liveStock.canDirectPayWithoutApproval(sel)) return false;
    return liveStock.requestExceedsSellableCapacity(
      sel,
      restorePendingQty: sel,
    );
  }

  /// Snapshot da pilha de navegação/modais (diagnóstico C8B — cinzento no web).
  static Map<String, dynamic> c8bUiStackSnapshot(BuildContext context) {
    try {
      final localNav = Navigator.of(context);
      final rootNav = Navigator.of(context, rootNavigator: true);
      final modal = ModalRoute.of(context);
      return {
        'is_web': kIsWeb,
        'local_can_pop': localNav.canPop(),
        'root_can_pop': rootNav.canPop(),
        'modal_is_current': modal?.isCurrent,
        'modal_barrier_dismissible': modal?.barrierDismissible,
        'modal_barrier_color': modal?.barrierColor?.toString(),
      };
    } catch (e) {
      return {'is_web': kIsWeb, 'snapshot_error': e.toString()};
    }
  }

  static Future<bool> showQtyNeedsSellerConfirmationDialog({
    required BuildContext context,
    required int availableQty,
    required int requestedQty,
    String trigger = 'unknown',
  }) async {
    final avail = availableQty < 0 ? 0 : availableQty;
    final req = requestedQty < 1 ? 1 : requestedQty;
    // Overlay sem ModalBarrier — no web o barrier do showDialog deixa cinzento
    // por cima do HtmlElementView do vídeo.
    unawaited(
      FleaberLogger.instance.event('live.player.c8b_overlay', {
        'phase': 'open',
        'trigger': trigger,
        'available_qty': avail,
        'requested_qty': req,
        ...c8bUiStackSnapshot(context),
      }),
    );
    final overlay = Overlay.of(context, rootOverlay: true);
    final closed = Completer<void>();

    late OverlayEntry entry;
    void dismiss() {
      if (!closed.isCompleted) {
        entry.remove();
        unawaited(
          FleaberLogger.instance.event('live.player.c8b_overlay', {
            'phase': 'dismiss',
            'trigger': trigger,
            ...c8bUiStackSnapshot(context),
          }),
        );
        closed.complete();
      }
    }

    entry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: dismiss,
              behavior: HitTestBehavior.translucent,
            ),
          ),
          Center(
            child: Material(
              color: const Color(0xFF1A2329),
              borderRadius: BorderRadius.circular(16),
              elevation: 8,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Quantidade a confirmar',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'O teu pedido de $req unidade${req == 1 ? '' : 's'} foi '
                        'enviado à vendedora para confirmar a quantidade. Neste '
                        'momento só há $avail unidade${avail == 1 ? '' : 's'} '
                        'disponível${avail == 1 ? '' : 'eis'} na live — não podes '
                        'seguir para o pagamento até ela aceitar.',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: dismiss,
                          child: Text(
                            'Percebi',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF00A3AD),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(entry);
    await closed.future;
    if (context.mounted) {
      unawaited(
        FleaberLogger.instance.event('live.player.c8b_overlay', {
          'phase': 'closed',
          'trigger': trigger,
          ...c8bUiStackSnapshot(context),
        }),
      );
    }
    return false;
  }

  static Future<void> notifySellerQtyConfirmationNeeded({
    required String liveId,
    required String liveItemId,
    required String reservationRequestId,
    required int requestedQty,
    required int availableQty,
    String? refLabel,
    BuildContext? snackbarContext,
  }) async {
    final lid = liveId.trim();
    final iid = liveItemId.trim();
    final rid = reservationRequestId.trim();
    if (lid.isEmpty || iid.isEmpty || rid.isEmpty) return;
    final req = requestedQty < 1 ? 1 : requestedQty;
    final avail = availableQty < 0 ? 0 : availableQty;
    try {
      await LiveReservationQueueService().updateBagRequestQty(
        requestId: rid,
        qty: req,
      );
      var marked = false;
      try {
        marked = await LiveReservationQueueService().markQtyConfirmNeeded(
          requestId: rid,
        );
      } catch (_) {}
      unawaited(
        FleaberLogger.instance.event('live.checkout.qty_confirm', {
          'live_id': lid,
          'live_item_id': iid,
          'request_id': rid,
          'requested_qty': req,
          'available_qty': avail,
          'marked_ok': marked,
        }),
      );
    } catch (_) {}
    final itemLabel = (refLabel ?? '').trim();
    final labelBit = itemLabel.isEmpty ? '' : ' · $itemLabel';
    await LiveReservationQueueService().postSystemMessage(
      liveId: lid,
      body:
          '📋 Pedido de $req un.$labelBit — só $avail disponível${avail == 1 ? '' : 'eis'}; aguarda confirmação',
      senderLabel: 'Sistema',
    );
    final parsed = LiveSystemChatHumanizer.parse(
      '📋 Pedido de $req un.$labelBit — só $avail disponível; aguarda confirmação',
    );
    final snack = parsed.snackbarLine?.trim() ?? '';
    final ctx = snackbarContext;
    if (snack.isNotEmpty && ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(snack), duration: const Duration(seconds: 4)),
      );
    }
  }

  /// Portes: 3,50 € transportadora ou 0 € entrega em mão. Seguro: 0,65 € + 5% sobre artigo + portes.
  static Widget checkoutTotalsBreakdown({
    required double itemsSubtotalEur,
    required double shippingEur,
    required double protectionEur,
    required double totalEur,
    int lineCount = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _totalLine('Artigos ($lineCount)', itemsSubtotalEur),
        _totalLine(
          shippingEur > 0 ? 'Portes (transportadora)' : 'Portes (entrega em mão)',
          shippingEur,
        ),
        if (protectionEur > 0)
          _totalLine('Seguro Fleaber', protectionEur),
        const Divider(height: 16, color: Colors.white24),
        Row(
          children: [
            Text(
              'Total',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            Text(
              formatEuros(totalEur),
              style: GoogleFonts.inter(
                color: const Color(0xFF6ED8DE),
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _totalLine(String label, double eur) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
            ),
          ),
          Text(
            formatEuros(eur),
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> show({
    required BuildContext context,
    required ProductsRow product,
    required String liveId,
    required String? liveItemId,
    required String? playbackId,
    required bool isLive,
    required String? liveSellerId,
    String? reservationRequestId,
    String? reservationStatus,
    int? initialPayQty,
    double? overrideItemPriceEur,
    String? checkoutNotes,
    String? productPhotoUrl,
    VoidCallback? onPaymentStarted,
  }) async {
    if (currentUserUid.isEmpty) return;

    final itemIdForPrice = liveItemId?.trim() ?? '';
    var unitOverride = overrideItemPriceEur;
    if (unitOverride == null || unitOverride <= 0) {
      unitOverride = await LiveItemPriceGate.resolveFreshUnitPrice(
        liveItemId: itemIdForPrice,
        productPrice: product.price,
      );
    }
    if (unitOverride == null || unitOverride <= 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(LiveItemPriceGate.pendingPriceLabel),
          ),
        );
      }
      return;
    }
    if (itemIdForPrice.isNotEmpty) {
      await LiveCatalogStockService.ensureCheckoutProduct(itemIdForPrice);
    }

    var resStatus = reservationStatus?.trim();
    final reqId = reservationRequestId?.trim() ?? '';
    var reservedRequestedQty = initialPayQty;
    if (reqId.isNotEmpty) {
      try {
        final reqRows = await LiveReservationRequestsTable().queryRows(
          queryFn: (q) => q.eqOrNull('id', reqId),
          limit: 1,
        );
        if (reqRows.isNotEmpty) {
          resStatus ??= reqRows.first.status;
          final rq = reqRows.first.requestedQty;
          if (rq > 0) reservedRequestedQty = rq;
        }
      } catch (_) {}
    }

    const paymentInApp = 'Pagamento na app';
    const paymentDirect = 'Pagamento Direto ao Vendedor (MB WAY/Transf)';

    var sellerAllowsDirectPayment = false;
    final sellerId = product.sellerId;
    if (sellerId != null && sellerId.isNotEmpty) {
      final sellerRows = await ProfilesDirectoryTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', sellerId),
        limit: 1,
      );
      if (sellerRows.isNotEmpty) {
        sellerAllowsDirectPayment =
            sellerRows.first.externalPaymentsEnabled;
      }
    }

    var selectedShipping = shippingCarrier;
    var selectedPayment = paymentInApp;
    LiveCatalogStockSnapshot? liveStock;
    final itemId = liveItemId?.trim() ?? '';
    if (itemId.isNotEmpty) {
      liveStock = await LiveCatalogStockService.fetch(itemId);
    }

    var maxQuantity = product.quantity.clamp(1, 99);
    final payQtyHint = (reservedRequestedQty ?? initialPayQty ?? 1).clamp(1, 99);
    if (liveStock != null) {
      final totalCap = liveStock.totalQty.clamp(1, 99);
      final availCap = liveStock.availableQty.clamp(1, 99);
      if (resStatus == 'accepted') {
        // Aceite (incl. over-stock): quantidade acordada = pedido, não stock restante.
        maxQuantity = payQtyHint;
      } else if (reqId.isNotEmpty) {
        // Pendente: permitir pedir acima do disponível; bloqueio só ao pagar.
        maxQuantity = totalCap;
      } else {
        maxQuantity = availCap;
      }
    } else if (payQtyHint > 0) {
      maxQuantity = payQtyHint;
    }

    var selectedQuantity = payQtyHint.clamp(1, maxQuantity);

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.transparent,
      backgroundColor: const Color(0xFF11181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        var checkoutProcessing = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            final weightAgg = fleaberAggregateShipmentWeight([
              FleaberShipmentWeightInput.fromProduct(
                product,
                quantity: selectedQuantity,
              ),
            ]);
            final effectiveBand =
                weightAgg.ok ? weightAgg.band : null;
            final shippingCost = selectedShipping == shippingHand
                ? 0.0
                : (effectiveBand == null
                    ? 0.0
                    : shippingCostForMethod(
                        selectedShipping,
                        weightKg: weightAgg.totalKg,
                        band: effectiveBand,
                      ));
            final unitPrice =
                overrideItemPriceEur ?? product.price ?? 0.0;
            final productPrice = unitPrice * selectedQuantity;
            final isDirect = selectedPayment == paymentDirect;
            final protectionFee = isDirect
                ? 0.0
                : calculateFleaberProtectionFee(
                    productPrice,
                    shippingEur: shippingCost,
                  );
            // B2: directo = artigos + portes (sem Seguro); nunca só productPrice.
            final total = calculateFleaberBuyerTotal(
              itemPriceEur: productPrice,
              shippingEur: shippingCost,
              includeProtectionFee: !isDirect,
            );

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  12 + MediaQuery.paddingOf(context).bottom,
                ),
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
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (productPhotoUrl?.trim().isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: BatataCachedNetworkImage(
                                  imageUrl: productPhotoUrl!.trim(),
                                  fit: BoxFit.cover,
                                  placeholderColor: const Color(0xFF222222),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            product.title?.trim().isNotEmpty == true
                                ? product.title!.trim()
                                : 'Artigo',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Portes DPD conforme peso e Pickup/casa (IVA incl.). '
                      'Seguro Fleaber: 0,65 € + 5% do valor protegido.',
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 10,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        IconButton(
                          onPressed: selectedQuantity <= 1
                              ? null
                              : () => setModalState(() => selectedQuantity--),
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Colors.white70),
                        ),
                        Text(
                          '$selectedQuantity',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        IconButton(
                          onPressed: selectedQuantity >= maxQuantity
                              ? null
                              : () => setModalState(() => selectedQuantity++),
                          icon: const Icon(Icons.add_circle_outline,
                              color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedShipping,
                      dropdownColor: const Color(0xFF1A2228),
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                      decoration: _fieldDecoration('Envio'),
                      items: const [
                        DropdownMenuItem(
                          value: shippingCarrier,
                          child: Text(shippingCarrierLabel),
                        ),
                        DropdownMenuItem(
                          value: shippingHand,
                          child: Text(shippingHandLabel),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setModalState(() => selectedShipping = v);
                      },
                    ),
                    if (selectedShipping == shippingCarrier) ...[
                      const SizedBox(height: 8),
                      Text(
                        kFleaberCheckoutShippingDeltaNotice,
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 10,
                          height: 1.3,
                        ),
                      ),
                      if (!weightAgg.ok || weightAgg.needsBuyerBandChoice) ...[
                        const SizedBox(height: 6),
                        Text(
                          kFleaberBuyerWeightMissingMessage,
                          style: GoogleFonts.inter(
                            color: const Color(0xFFFFB74D),
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ] else if (effectiveBand != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Portes calculados automaticamente'
                          '${weightAgg.totalKg != null ? ' · ~${weightAgg.totalKg!.toStringAsFixed(1)} kg' : ''}',
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedPayment,
                      dropdownColor: const Color(0xFF1A2228),
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                      decoration: _fieldDecoration('Pagamento'),
                      items: [
                        const DropdownMenuItem(
                          value: paymentInApp,
                          child: Text(paymentInApp),
                        ),
                        if (sellerAllowsDirectPayment)
                          const DropdownMenuItem(
                            value: paymentDirect,
                            child: Text(paymentDirect),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setModalState(() => selectedPayment = v);
                      },
                    ),
                    if (!isDirect) ...[
                      const SizedBox(height: 12),
                      checkoutTotalsBreakdown(
                        itemsSubtotalEur: productPrice,
                        shippingEur: shippingCost,
                        protectionEur: protectionFee,
                        totalEur: total,
                      ),
                    ],
                    const SizedBox(height: 14),
                    FleaberPrimaryButton(
                      label: checkoutProcessing
                          ? 'A processar…'
                          : (isDirect ? 'Confirmar reserva' : 'Pagar'),
                      loading: checkoutProcessing,
                      onPressed: checkoutProcessing
                          ? null
                          : () async {
                              // D2: lock UI ANTES de qualquer await / pop
                              // (marketplace já fazia isto; live fazia pop primeiro).
                              setModalState(() => checkoutProcessing = true);
                              void unlockSheet() {
                                if (ctx.mounted) {
                                  setModalState(
                                      () => checkoutProcessing = false);
                                }
                              }

                              if (total <= 0 || total.isNaN) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Preço inválido'),
                                  ),
                                );
                                unlockSheet();
                                return;
                              }
                              var payResStatus = resStatus;
                              if (reqId.isNotEmpty) {
                                payResStatus =
                                    await LiveReservationQueueService
                                            .fetchRequestStatus(reqId) ??
                                        payResStatus;
                              }
                              if (checkoutQtyExceedsAvailable(
                                selectedQuantity: selectedQuantity,
                                liveStock: liveStock,
                                reservationStatus: payResStatus,
                              )) {
                                final iid = liveItemId?.trim() ?? '';
                                if (reqId.isNotEmpty &&
                                    iid.isNotEmpty &&
                                    payResStatus != 'accepted') {
                                  await notifySellerQtyConfirmationNeeded(
                                    liveId: liveId,
                                    liveItemId: iid,
                                    reservationRequestId: reqId,
                                    requestedQty: selectedQuantity,
                                    availableQty: liveStock!.availableQty,
                                    refLabel: LiveVendorRefDisplay.itemDisplayName(
                                      title: product.title,
                                      refCode: product.refCode,
                                    ),
                                    snackbarContext: ctx,
                                  );
                                }
                                if (!ctx.mounted) return;
                                await showQtyNeedsSellerConfirmationDialog(
                                  context: ctx,
                                  availableQty: liveStock!.availableQty,
                                  requestedQty: selectedQuantity,
                                  trigger: 'checkout_single_pay',
                                );
                                unlockSheet();
                                return;
                              }
                              if (ProfileShippingRequirements
                                  .checkoutNeedsCompleteProfile(
                                shippingMethod: selectedShipping,
                                paymentMethod: selectedPayment,
                              )) {
                                final ready =
                                    await ProfileShippingRequirements
                                        .ensureCheckoutReady(context);
                                if (!ready) {
                                  unlockSheet();
                                  return;
                                }
                              }
                              if (selectedShipping == shippingCarrier &&
                                  effectiveBand == null) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      kFleaberBuyerWeightMissingMessage,
                                    ),
                                  ),
                                );
                                unlockSheet();
                                return;
                              }
                              onPaymentStarted?.call();
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (!context.mounted) return;
                              final ok = await _submit(
                                context: context,
                                product: product,
                                quantity: selectedQuantity,
                                shippingMethod: selectedShipping,
                                paymentMethod: selectedPayment,
                                total: total,
                                itemPrice: unitPrice,
                                shippingCost: shippingCost,
                                protectionFee: protectionFee,
                                liveId: liveId,
                                liveItemId: liveItemId,
                                playbackId: playbackId,
                                isLive: isLive,
                                liveSellerId: liveSellerId,
                                reservationRequestId: reservationRequestId,
                                reservationStatus: payResStatus,
                                checkoutNotes: checkoutNotes,
                                shippingWeightKg: weightAgg.totalKg,
                                shippingWeightBand: effectiveBand,
                              );
                              if (!ok) {
                                // Sheet já fechado — lock estático cobre reentrada.
                                unlockSheet();
                              }
                            },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      border: OutlineInputBorder(
        borderRadius: FleaberRadius.circularMd,
        borderSide: BorderSide.none,
      ),
    );
  }

  static Future<bool> _submit({
    required BuildContext context,
    required ProductsRow product,
    required int quantity,
    required String shippingMethod,
    required String paymentMethod,
    required double total,
    required double itemPrice,
    required double shippingCost,
    required double protectionFee,
    required String liveId,
    required String? liveItemId,
    required String? playbackId,
    required bool isLive,
    required String? liveSellerId,
    String? reservationRequestId,
    String? reservationStatus,
    String? checkoutNotes,
    double? shippingWeightKg,
    FleaberDpdWeightBand? shippingWeightBand,
  }) async {
    if (_submitLocked) {
      unawaited(
        FleaberLogger.instance.logStripe(
          'live_submit_rejected_inflight',
          data: {
            'live_id': liveId.trim(),
            'product_id': product.id,
          },
        ),
      );
      return false;
    }
    _submitLocked = true;
    try {
      return await _submitBody(
        context: context,
        product: product,
        quantity: quantity,
        shippingMethod: shippingMethod,
        paymentMethod: paymentMethod,
        total: total,
        itemPrice: itemPrice,
        shippingCost: shippingCost,
        protectionFee: protectionFee,
        liveId: liveId,
        liveItemId: liveItemId,
        playbackId: playbackId,
        isLive: isLive,
        liveSellerId: liveSellerId,
        reservationRequestId: reservationRequestId,
        reservationStatus: reservationStatus,
        checkoutNotes: checkoutNotes,
        shippingWeightKg: shippingWeightKg,
        shippingWeightBand: shippingWeightBand,
      );
    } finally {
      _submitLocked = false;
    }
  }

  static Future<bool> _submitBody({
    required BuildContext context,
    required ProductsRow product,
    required int quantity,
    required String shippingMethod,
    required String paymentMethod,
    required double total,
    required double itemPrice,
    required double shippingCost,
    required double protectionFee,
    required String liveId,
    required String? liveItemId,
    required String? playbackId,
    required bool isLive,
    required String? liveSellerId,
    String? reservationRequestId,
    String? reservationStatus,
    String? checkoutNotes,
    double? shippingWeightKg,
    FleaberDpdWeightBand? shippingWeightBand,
  }) async {
    final productId = product.id;
    final sellerId = product.sellerId;
    if (productId == null ||
        productId.isEmpty ||
        sellerId == null ||
        sellerId.isEmpty) {
      return false;
    }

    final liveFields = <String, String>{};
    final lid = liveId.trim();
    final liid = liveItemId?.trim() ?? '';
    if (lid.isNotEmpty) liveFields['live_id'] = lid;
    if (liid.isNotEmpty) liveFields['live_item_id'] = liid;
    final isHand = shippingMethod == shippingHand ||
        shippingMethod.toLowerCase().contains('mão') ||
        shippingMethod.toLowerCase().contains('mao');
    final seal = fleaberOrderShippingSealFields(
      handDelivery: isHand,
      weightKg: shippingWeightKg,
      band: shippingWeightBand,
      pickup: false,
      shippingEurCharged: shippingCost,
    );

    try {
      if (paymentMethod.contains('Direto')) {
        // Pagamento fora da app: SEMPRE card de aceite da vendedora
        // (Mensagens / chat). Não saltar só porque a reserva live já está
        // «accepted» nas ops — senão o saco e o chat ficam dessincronizados.
        final order = await OrdersTable().insert({
          'product_id': productId,
          'buyer_id': currentUserUid,
          'seller_id': sellerId,
          'price_total': total,
          'shipping_method': shippingMethod,
          'payment_method': paymentMethod,
          'status': 'reserva_pendente',
          'is_reservation': true,
          'quantity': quantity < 1 ? 1 : quantity,
          ...seal,
          ...liveFields,
        });
        final orderId = order.id?.trim() ?? '';
        if (orderId.isNotEmpty) {
          final chat = await ensureSellerChat(
            otherUserId: sellerId,
            productId: productId,
            forceNew: true,
          );
          final chatId = chat.id?.trim() ?? '';
          if (chatId.isNotEmpty) {
            await insertReservationRequestMessage(
              orderId: orderId,
              chatId: chatId,
              sellerId: sellerId,
              buyerId: currentUserUid,
              productId: productId,
              total: total,
              expiresAt: DateTime.now().toUtc().add(const Duration(days: 5)),
            );
          }
        }
        if (!context.mounted) return true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pedido enviado à vendedora. Assim que aceitar, vês os dados de pagamento em Mensagens.',
            ),
          ),
        );
        return true;
      }

      final holdRows = await OrdersTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('product_id', productId)
            .eqOrNull('buyer_id', currentUserUid)
            .inFilter('status', ['reserva_pendente', 'reservado']),
        limit: 5,
      );
      String? orderId;
      if (holdRows.isNotEmpty) {
        holdRows.sort((a, b) {
          final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta);
        });
        orderId = holdRows.first.id;
        final holdKey = normalizeOrderStatusKey(holdRows.first.status);
        await OrdersTable().update(
          data: {
            'price_total': total,
            'shipping_method': shippingMethod,
            'payment_method': paymentMethod,
            'status': holdKey == 'reservado' ? 'reservado' : 'reserva_pendente',
            'is_reservation': holdKey != 'reservado',
            'quantity': quantity < 1 ? 1 : quantity,
            ...seal,
            ...liveFields,
          },
          matchingRows: (rows) => rows.eqOrNull('id', orderId),
        );
      } else {
        final order = await OrdersTable().insert({
          'product_id': productId,
          'buyer_id': currentUserUid,
          'seller_id': sellerId,
          'price_total': total,
          'shipping_method': shippingMethod,
          'payment_method': paymentMethod,
          'status': 'reserva_pendente',
          'is_reservation': false,
          'quantity': quantity < 1 ? 1 : quantity,
          ...seal,
          ...liveFields,
        });
        orderId = order.id;
      }

      if (orderId == null || orderId.isEmpty) {
        throw Exception('Não foi possível criar a encomenda.');
      }

      final sid = liveSellerId?.trim() ?? sellerId;
      if (lid.isNotEmpty && liid.isNotEmpty && sid.isNotEmpty) {
        await LiveReservationQueueService().ensureStripeCheckoutHold(
          liveId: lid,
          liveItemId: liid,
          sellerId: sid,
          buyerId: currentUserUid,
          orderId: orderId,
          reservationRequestId: reservationRequestId,
          tagAllActionableForItem: true,
        );
      }

      final rid = reservationRequestId?.trim() ?? '';
      if (rid.isNotEmpty && checkoutNotes != null) {
        final rows = await LiveReservationRequestsTable().querySingleRow(
          queryFn: (q) => q.eqOrNull('id', rid),
        );
        if (rows.isNotEmpty) {
          final prev = (rows.first.notes ?? '').trim();
          final tag = 'bag_notes:${checkoutNotes.trim()}';
          if (!prev.contains(tag)) {
            await LiveReservationRequestsTable().update(
              data: {
                'notes': prev.isEmpty ? tag : '$prev | $tag',
              },
              matchingRows: (q) => q.eqOrNull('id', rid),
            );
          }
        }
      }

      final result = await fleaberInvokeCreatePaymentIntent(
        body: {
          'amount': euroCents(total),
          'currency': 'eur',
          'product_id': productId,
          'buyer_id': currentUserUid,
          'seller_id': sellerId,
          'order_id': orderId,
          'quantity': quantity < 1 ? 1 : quantity,
          'item_price': euroCents(itemPrice * quantity),
          'shipping': euroCents(shippingCost),
          'protection_fee': euroCents(protectionFee),
          'shipping_method': shippingMethod,
          if (shippingWeightKg != null) 'shipping_weight_kg': shippingWeightKg,
          if (shippingWeightBand != null)
            'shipping_weight_band': shippingWeightBand.code,
          'shipping_modality': isHand ? 'hand' : 'shop_to_home',
          if (lid.isNotEmpty) 'live_id': lid,
          if (playbackId != null && playbackId.trim().isNotEmpty)
            'playback_id': playbackId.trim(),
          'is_live': isLive,
          if (sid.isNotEmpty) 'live_seller_id': sid,
          if (liid.isNotEmpty) 'live_item_id': liid,
          if (rid.isNotEmpty) 'reservation_request_id': rid,
        },
        logContext: {'source': 'live_single_checkout'},
      );

      await FleaberStripeCheckoutContext.save(
        orderId: orderId,
        productId: productId,
        liveId: lid.isNotEmpty ? lid : null,
        playbackId: playbackId,
        isLive: isLive,
        sellerId: sid,
        liveItemId: liid.isNotEmpty ? liid : null,
        reservationRequestId: rid.isNotEmpty ? rid : null,
        checkoutSessionId: result.checkoutSessionId,
      );
      unawaited(
        FleaberLogger.instance.logStripe(
          'open_browser_live',
          data: {
            'order_id': orderId,
            'live_id': lid,
            'live_item_id': liid,
            'quantity': quantity,
            'session_id': result.checkoutSessionId,
          },
        ),
      );

      final opened = await fleaberLaunchStripeCheckout(
        result.checkoutUrl,
        context: {
          'order_id': orderId,
          'session_id': result.checkoutSessionId,
          'source': 'live_single_checkout',
        },
      );
      if (!opened) {
        await FleaberStripeCheckoutContext.clear();
        throw Exception('Não foi possível abrir o checkout Stripe.');
      }
      await afterStripeBrowserClosed(
        liveId: lid,
        checkoutSessionId: result.checkoutSessionId,
      );
      return true;
    } catch (e, st) {
      unawaited(
        FleaberLogger.instance.logStripe(
          'checkout_catch',
          data: {'source': 'live_single_checkout'},
          error: e,
          stackTrace: st,
        ),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
      return false;
    }
  }

  static Future<void> _applyBagDeliveryPoints({
    required List<String> orderIds,
    DpdPudoPoint? pickupPoint,
    bool deliveryHome = false,
  }) async {
    if (orderIds.isEmpty) return;
    if (pickupPoint == null && !deliveryHome) return;
    for (final oid in orderIds) {
      final id = oid.trim();
      if (id.isEmpty) continue;
      try {
        if (pickupPoint != null) {
          await DpdPudoService.attachPickupToOrder(
            orderId: id,
            point: pickupPoint,
          );
        } else if (deliveryHome) {
          await DpdPudoService.attachHomeToOrder(id);
        }
      } catch (e) {
        debugPrint('DPD_BAG_DELIVERY_POINT_ERR $id $e');
      }
    }
  }

  /// MB WAY / transferência: cria encomendas sem abrir Stripe.
  static Future<bool> _payBagLinesDirect({
    required BuildContext context,
    required List<LiveBagCheckoutPayLine> lines,
    required String liveId,
    required String? liveSellerId,
    required String shippingMethod,
    String? checkoutNotes,
    DpdPudoPoint? pickupPoint,
    bool deliveryHome = false,
    FleaberDpdWeightBand? shippingWeightBand,
    double? shippingWeightKg,
  }) async {
    final lid = liveId.trim();
    if (lid.isEmpty || lines.isEmpty) return false;

    if (ProfileShippingRequirements.checkoutNeedsCompleteProfile(
      shippingMethod: shippingMethod,
      paymentMethod: paymentDirect,
    )) {
      final ready =
          await ProfileShippingRequirements.ensureCheckoutReady(context);
      if (!ready) return false;
    }

    final isHand = shippingMethod == shippingHand ||
        shippingMethod.toLowerCase().contains('mão') ||
        shippingMethod.toLowerCase().contains('mao');
    final shippingCost = shippingCostForMethod(
      shippingMethod,
      pickup: pickupPoint != null,
      weightKg: shippingWeightKg,
      band: shippingWeightBand,
    );
    final seal = fleaberOrderShippingSealFields(
      handDelivery: isHand,
      weightKg: shippingWeightKg,
      band: shippingWeightBand,
      pickup: pickupPoint != null,
      shippingEurCharged: shippingCost,
    );
    var shippingLeft = shippingCost;
    var created = 0;
    var pendingAccept = 0;
    String? sharedChatId;
    String? sharedSellerId;
    final createdOrderIds = <String>[];

    try {
      for (final line in lines) {
        final liid = line.itemRow?.id?.trim() ??
            (line.request.liveItemId ?? '').trim();
        var itemRow = line.itemRow;
        if (liid.isNotEmpty) {
          itemRow =
              await LiveCatalogStockService.fetchLiveItemById(liid) ?? itemRow;
        }
        final product = await LiveItemPriceGate.resolveProductForCheckout(
              itemRow: itemRow,
              sellerId: liveSellerId,
              liveId: lid,
            ) ??
            line.product;
        final productId = product.id;
        final sellerId = product.sellerId;
        if (productId == null ||
            productId.isEmpty ||
            sellerId == null ||
            sellerId.isEmpty) {
          throw Exception('Artigo sem produto associado.');
        }
        final qty = line.payQty < 1 ? 1 : line.payQty;
        final unit = await LiveItemPriceGate.resolveFreshUnitPrice(
              liveItemId: liid,
              fallbackLiveItemPrice: itemRow?.price,
              productPrice: product.price,
              sellerId: liveSellerId,
              liveId: lid,
              itemRow: itemRow,
            ) ??
            0.0;
        if (unit <= 0) {
          throw Exception('Artigo sem preço definido.');
        }
        final lineItem = unit * qty;
        final shipThis = shippingLeft;
        shippingLeft = 0;
        final total = lineItem + shipThis;

        final liveFields = <String, String>{
          'live_id': lid,
          if (liid.isNotEmpty) 'live_item_id': liid,
        };

        // Pagamento fora da app: SEMPRE reserva_pendente + card de aceite
        // (igual ao checkout single). Não saltar se a reserva live já está
        // «accepted» — senão Confirmar no saco parece não fazer nada / sem Pagar.
        final rid = line.request.id?.trim() ?? '';

        final order = await OrdersTable().insert({
          'product_id': productId,
          'buyer_id': currentUserUid,
          'seller_id': sellerId,
          'price_total': total,
          'shipping_method': shippingMethod,
          'payment_method': paymentDirect,
          'status': 'reserva_pendente',
          'is_reservation': true,
          'quantity': qty,
          ...seal,
          ...liveFields,
        });
        final orderId = order.id?.trim() ?? '';
        if (orderId.isEmpty) {
          throw Exception('Não foi possível criar encomenda.');
        }
        created++;
        pendingAccept++;
        createdOrderIds.add(orderId);

        // Um chat por vendedor nesta sessão de saco (evita misturar rifa antiga).
        String chatId = sharedChatId ?? '';
        if (chatId.isEmpty || sharedSellerId != sellerId) {
          final chat = await ensureSellerChat(
            otherUserId: sellerId,
            productId: productId,
            forceNew: true,
          );
          chatId = chat.id?.trim() ?? '';
          sharedChatId = chatId;
          sharedSellerId = sellerId;
        }
        if (chatId.isNotEmpty) {
          await insertReservationRequestMessage(
            orderId: orderId,
            chatId: chatId,
            sellerId: sellerId,
            buyerId: currentUserUid,
            productId: productId,
            total: total,
            expiresAt: DateTime.now().toUtc().add(const Duration(days: 5)),
          );
        }

        if (rid.isNotEmpty && checkoutNotes != null) {
          final prev = (line.request.notes ?? '').trim();
          final tag = 'bag_notes:${checkoutNotes.trim()}';
          if (!prev.contains(tag)) {
            await LiveReservationRequestsTable().update(
              data: {'notes': prev.isEmpty ? tag : '$prev | $tag'},
              matchingRows: (q) => q.eqOrNull('id', rid),
            );
          }
        }
      }

      await _applyBagDeliveryPoints(
        orderIds: createdOrderIds,
        pickupPoint: pickupPoint,
        deliveryHome: deliveryHome,
      );

      if (context.mounted) {
        final message = pendingAccept == 1
            ? 'Pedido enviado à vendedora. Assim que aceitar, vês os dados de pagamento em Mensagens.'
            : '$pendingAccept pedidos enviados à vendedora. Assim que aceitar, vês os dados de pagamento em Mensagens.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível registar o pagamento directo: '
              '${e.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
      return false;
    }
  }

  /// Um único checkout para várias referências no saco.
  /// [paymentMethod]: [paymentInApp] (Stripe) ou [paymentDirect] (MB WAY/transf).
  static Future<bool> payBagLines({
    required BuildContext context,
    required List<LiveBagCheckoutPayLine> lines,
    required String liveId,
    required String? playbackId,
    required bool isLive,
    required String? liveSellerId,
    required String shippingMethod,
    String paymentMethod = paymentInApp,
    String? checkoutNotes,
    DpdPudoPoint? pickupPoint,
    bool deliveryHome = false,
    FleaberDpdWeightBand? shippingWeightBand,
    double? shippingWeightKg,
    VoidCallback? onPaymentStarted,
    /// Clears sheet loading before bag_changed (or similar) buyer dialogs.
    VoidCallback? onAwaitingBuyerConfirm,
    /// Called when buyer accepts remainder after bag_changed — sheet must
    /// rebuild exclusively from these lines before any further payment.
    ValueChanged<List<LiveBagCheckoutPayLine>>? onRemainderAccepted,
  }) async {
    if (lines.isEmpty) return false;
    onPaymentStarted?.call();
    final lid = liveId.trim();
    if (lid.isEmpty) return false;

    HubBagPayDiag.log('pay_bag_lines_enter', {
      'live_id': lid,
      'line_count': lines.length,
      'payment': paymentMethod,
      'shipping': shippingMethod,
      'is_live': isLive,
      'seller_id': liveSellerId,
      'uid': currentUserUid,
      'delivery_mode': pickupPoint != null
          ? 'pickup'
          : (deliveryHome ? 'home' : null),
    });

    if (paymentMethod.contains('Direto')) {
      return _payBagLinesDirect(
        context: context,
        lines: lines,
        liveId: lid,
        liveSellerId: liveSellerId,
        shippingMethod: shippingMethod,
        checkoutNotes: checkoutNotes,
        pickupPoint: pickupPoint,
        deliveryHome: deliveryHome,
        shippingWeightBand: shippingWeightBand,
        shippingWeightKg: shippingWeightKg,
      );
    }

    LiveItemPriceGate.logCheckoutGate(
      'pay_bag_lines_start',
      liveId: lid,
      sellerId: liveSellerId,
      reason: 'line_count_${lines.length}',
    );

    for (final line in lines) {
      final liid = line.itemRow?.id?.trim() ?? '';
      var itemRow = line.itemRow;
      if (liid.isNotEmpty) {
        itemRow =
            await LiveCatalogStockService.fetchLiveItemById(liid) ?? itemRow;
      }
      final product = await LiveItemPriceGate.resolveProductForCheckout(
            itemRow: itemRow,
            sellerId: liveSellerId,
            liveId: lid,
          ) ??
          line.product;
      final unit = await LiveItemPriceGate.resolveFreshUnitPrice(
        liveItemId: liid,
        fallbackLiveItemPrice: itemRow?.price,
        productPrice: product.price,
        sellerId: liveSellerId,
        liveId: lid,
        itemRow: itemRow,
      );
      if (unit == null) {
        LiveItemPriceGate.logCheckoutGate(
          'pay_bag_lines_blocked',
          liveId: lid,
          sellerId: liveSellerId,
          liveItemId: liid,
          requestId: line.request.id,
          productId: product.id,
          liveItemPrice: itemRow?.price,
          productPrice: product.price,
          reason: 'unit_null',
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(LiveItemPriceGate.pendingPriceLabel),
            ),
          );
        }
        return false;
      }
      if (liid.isEmpty) continue;
      final snap = await LiveCatalogStockService.fetch(liid);
      final rid = line.request.id?.trim() ?? '';
      var resStatus = line.request.status?.trim();
      if (rid.isNotEmpty) {
        resStatus =
            await LiveReservationQueueService.fetchRequestStatus(rid) ??
                resStatus;
      }
      if (checkoutQtyExceedsAvailable(
        selectedQuantity: line.payQty,
        liveStock: snap,
        reservationStatus: resStatus,
      )) {
        final availNow = snap?.availableQty ?? 0;
        // Multi-line bag + stock gone: let begin return
        // bag_changed_confirmation_required → FleaberBagChangedDialog.
        // C8B «Quantidade a confirmar» is for single-line qty approval, not
        // mid-checkout prune when an article disappeared.
        if (lines.length > 1 && availNow <= 0) {
          continue;
        }
        if (rid.isNotEmpty && resStatus != 'accepted') {
          await notifySellerQtyConfirmationNeeded(
            liveId: lid,
            liveItemId: liid,
            reservationRequestId: rid,
            requestedQty: line.payQty,
            availableQty: availNow,
            refLabel: LiveVendorRefDisplay.itemDisplayName(
              title: line.itemRow?.title,
              refCode: line.itemRow?.refCode,
            ),
            snackbarContext: context,
          );
        }
        if (context.mounted) {
          await showQtyNeedsSellerConfirmationDialog(
            context: context,
            availableQty: availNow,
            requestedQty: line.payQty,
            trigger: 'bag_checkout_line',
          );
        }
        return false;
      }
    }

    // Server quote authority (Phase 4 begin); method validated via shippingMethod string.
    final shippingMethodTrim = shippingMethod.trim();
    if (shippingMethodTrim.isEmpty) return false;
    final sid = liveSellerId?.trim() ?? lines.first.product.sellerId?.trim() ?? '';
    final createdOrderIds = <String>[];

    try {
      // keep allowlist fail-closed before RPC (ZIP 140: exige peso/escalão)
      final shipPreview = shippingCostForMethod(
        shippingMethod,
        pickup: pickupPoint != null,
        weightKg: shippingWeightKg,
        band: shippingWeightBand,
      );
      final sellerIds = lines
          .map((l) => l.product.sellerId?.trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
      if (sellerIds.length > 1) {
        throw Exception(
          'O saco tem vendedores diferentes — paga um de cada vez.',
        );
      }

      final resolvedLines = <Map<String, dynamic>>[];

      for (final line in lines) {
        final liid = line.itemRow?.id?.trim() ?? '';
        var itemRow = line.itemRow;
        if (liid.isNotEmpty) {
          itemRow =
              await LiveCatalogStockService.fetchLiveItemById(liid) ?? itemRow;
        }
        final product = await LiveItemPriceGate.resolveProductForCheckout(
              itemRow: itemRow,
              sellerId: liveSellerId,
              liveId: lid,
            ) ??
            line.product;
        final productId = product.id;
        final sellerId = product.sellerId;
        if (productId == null || sellerId == null) {
          throw Exception('Artigo sem produto associado.');
        }
        final qty = line.payQty < 1 ? 1 : line.payQty;
        final unit = await LiveItemPriceGate.resolveFreshUnitPrice(
              liveItemId: liid,
              fallbackLiveItemPrice: itemRow?.price,
              productPrice: product.price,
              sellerId: liveSellerId,
              liveId: lid,
              itemRow: itemRow,
            ) ??
            0.0;
        if (unit <= 0) {
          throw Exception('Artigo sem preço definido.');
        }
        resolvedLines.add({
          'line': line,
          'product': product,
          'itemRow': itemRow,
          'liid': liid,
          'productId': productId,
          'sellerId': sellerId,
          'qty': qty,
          'lineItem': unit * qty,
        });
      }

      final linePayloads = <Map<String, dynamic>>[];
      for (final row in resolvedLines) {
        final line = row['line'] as LiveBagCheckoutPayLine;
        final liid = row['liid'] as String;
        final productId = row['productId'] as String;
        final qty = row['qty'] as int;
        final rid = line.request.id?.trim() ?? '';
        linePayloads.add(
          FleaberCommerceCheckout.linePayload(
            productId: productId,
            liveItemId: liid,
            reservationRequestId: rid.isEmpty ? null : rid,
            quantity: qty,
          ),
        );
      }

      final idemKey =
          'bag_${lid}_${currentUserUid}_${linePayloads.length}_${DateTime.now().millisecondsSinceEpoch ~/ 5000}';

      Future<Map<String, dynamic>> runBegin({required bool confirm}) {
        return FleaberCommerceCheckout.begin(
          lines: linePayloads,
          shippingMethod: shippingMethod,
          paymentRail: 'stripe',
          liveId: lid,
          clientIdempotencyKey: idemKey,
          confirmRemainder: confirm,
          delivery: <String, dynamic>{
            if (shippingWeightKg != null) 'shipping_weight_kg': shippingWeightKg,
            if (shippingWeightBand != null)
              'shipping_weight_band': shippingWeightBand.code,
            'shipping_modality': pickupPoint != null
                ? 'shop_to_shop'
                : 'shop_to_home',
            'shipping_cents_hint': (shipPreview * 100).round(),
          },
        );
      }

      var begin = await runBegin(confirm: false);
      if (begin['error']?.toString() == 'bag_changed_confirmation_required') {
        final reval = begin['revalidation'];
        final quote = reval is Map ? reval['quote'] : null;
        final unavailable = reval is Map ? reval['unavailable_lines'] : null;
        final available = reval is Map ? reval['available_lines'] : null;
        final totalCents = quote is Map
            ? (quote['total_cents'] as num?)?.toInt() ?? 0
            : 0;
        final unavailCount =
            unavailable is List ? unavailable.length : 0;
        if (!context.mounted) return false;
        // End Pagar loading before dialog — spinner must not sit behind overlay.
        onAwaitingBuyerConfirm?.call();
        await Future<void>.delayed(Duration.zero);
        if (context.mounted) {
          await WidgetsBinding.instance.endOfFrame;
        }
        if (!context.mounted) return false;
        final cont = await FleaberBagChangedDialog.show(
          context,
          unavailableCount: unavailCount,
          totalCents: totalCents,
        );
        if (cont != true) return false;

        final availList = available is List ? available : const <dynamic>[];
        final keptPayLines = filterBagPayLinesByAvailableLines(
          lines: lines,
          availableLines: availList,
        );
        if (keptPayLines.isEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Já não há artigos disponíveis neste saco.'),
              ),
            );
          }
          return false;
        }

        // Rebuild checkout exclusively from server-accepted lines, then stop
        // so the sheet shows Artigos(N) + Pagar before the next pay attempt.
        onRemainderAccepted?.call(keptPayLines);
        await Future<void>.delayed(Duration.zero);
        if (context.mounted) {
          await WidgetsBinding.instance.endOfFrame;
        }
        HubBagPayDiag.log('pay_bag_remainder_accepted', {
          'live_id': lid,
          'kept': keptPayLines.length,
          'dropped': lines.length - keptPayLines.length,
          'quote_total_cents': totalCents,
        });
        return false;
      }

      if (!FleaberCommerceCheckout.isOk(begin)) {
        final err = begin['error']?.toString() ?? 'checkout_begin_failed';
        if (err == 'all_unavailable') {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Já não há artigos disponíveis neste saco.'),
              ),
            );
          }
          return false;
        }
        throw Exception(err);
      }

      final attemptId = begin['checkout_attempt_id']?.toString() ?? '';
      final orderIds = (begin['order_ids'] is List)
          ? (begin['order_ids'] as List).map((e) => e.toString()).toList()
          : <String>[];
      createdOrderIds.addAll(orderIds);
      await _applyBagDeliveryPoints(
        orderIds: orderIds,
        pickupPoint: pickupPoint,
        deliveryHome: deliveryHome,
      );
      // ZIP 140: selar peso/escalão cobrado nas encomendas do saco (CPI autoridade).
      final bagSeal = fleaberOrderShippingSealFields(
        handDelivery: shippingMethod == shippingHand ||
            shippingMethod.toLowerCase().contains('mão') ||
            shippingMethod.toLowerCase().contains('mao'),
        weightKg: shippingWeightKg,
        band: shippingWeightBand,
        pickup: pickupPoint != null,
        shippingEurCharged: shipPreview,
      );
      for (final oid in orderIds) {
        if (oid.trim().isEmpty) continue;
        await OrdersTable().update(
          data: bagSeal,
          matchingRows: (rows) => rows.eqOrNull('id', oid),
        );
      }
      final quote = begin['quote'] is Map
          ? Map<String, dynamic>.from(begin['quote'] as Map)
          : <String, dynamic>{};
      final itemsCents = (quote['items_cents'] as num?)?.toInt() ?? 0;
      // Portes servidor CPI (selo) — não confiar no legado 3,50 do begin.
      final shipCents = (shipPreview * 100).round();
      final protCents = calculateFleaberProtectionFee(
            itemsCents / 100.0,
            shippingEur: shipPreview,
          );
      final protCentsInt = (protCents * 100).round();
      final totalCents = itemsCents + shipCents + protCentsInt;

      final bagPayload = <Map<String, dynamic>>[];
      for (var i = 0; i < orderIds.length && i < resolvedLines.length; i++) {
        final row = resolvedLines[i];
        final line = row['line'] as LiveBagCheckoutPayLine;
        final itemRow = row['itemRow'] as LiveItemsRow?;
        final liid = row['liid'] as String;
        final productId = row['productId'] as String;
        final sellerId = row['sellerId'] as String;
        final qty = row['qty'] as int;
        final rid = line.request.id?.trim() ?? '';
        final label = LiveVendorRefDisplay.itemDisplayName(
          title: itemRow?.title ?? line.itemRow?.title,
          refCode: itemRow?.refCode ?? line.itemRow?.refCode,
        );
        bagPayload.add({
          'order_id': orderIds[i],
          'product_id': productId,
          'seller_id': sellerId,
          'quantity': qty,
          'line_total_cents': 0,
          if (liid.isNotEmpty) 'live_item_id': liid,
          if (rid.isNotEmpty) 'reservation_request_id': rid,
          'item_label': label,
        });
      }

      // If bag_changed dropped lines, bagPayload may be shorter than resolvedLines —
      // rebuild from begin order ids only (server is authority).
      if (orderIds.isNotEmpty && bagPayload.length != orderIds.length) {
        bagPayload.clear();
        for (final oid in orderIds) {
          bagPayload.add({
            'order_id': oid,
            'product_id': resolvedLines.first['productId'],
            'seller_id': resolvedLines.first['sellerId'],
            'quantity': 1,
            'line_total_cents': 0,
          });
        }
      }

      HubBagPayDiag.log('pay_bag_invoke_stripe', {
        'live_id': lid,
        'line_count': bagPayload.length,
        'amount_cents': totalCents,
        'checkout_attempt_id': attemptId,
        'order_ids': orderIds,
      });

      final first = bagPayload.first;
      final result = await fleaberInvokeCreatePaymentIntent(
        body: {
          'amount': totalCents,
          'currency': 'eur',
          'product_id': first['product_id'],
          'buyer_id': currentUserUid,
          'seller_id': first['seller_id'],
          'order_id': first['order_id'],
          'quantity': 1,
          'item_price': itemsCents,
          'shipping': shipCents,
          'protection_fee': protCentsInt,
          'shipping_method': shippingMethod,
          if (shippingWeightKg != null) 'shipping_weight_kg': shippingWeightKg,
          if (shippingWeightBand != null)
            'shipping_weight_band': shippingWeightBand.code,
          'shipping_modality': pickupPoint != null
              ? 'shop_to_shop'
              : 'shop_to_home',
          'live_id': lid,
          if (playbackId != null && playbackId.trim().isNotEmpty)
            'playback_id': playbackId.trim(),
          'is_live': isLive,
          if (sid.isNotEmpty) 'live_seller_id': sid,
          'bag_checkout': true,
          'bag_lines': bagPayload,
          if (attemptId.isNotEmpty) 'checkout_attempt_id': attemptId,
        },
        logContext: {'source': 'live_bag_checkout'},
      );

      HubBagPayDiag.log('pay_bag_invoke_ok', {
        'session_id': result.checkoutSessionId,
        'has_url': result.checkoutUrl.isNotEmpty,
        'url_host': Uri.tryParse(result.checkoutUrl)?.host,
      });

      unawaited(
        FleaberLogger.instance.logStripe(
          'open_browser_live_bag',
          data: {
            'live_id': lid,
            'line_count': bagPayload.length,
            'order_ids': bagPayload.map((e) => e['order_id']).toList(),
            'session_id': result.checkoutSessionId,
          },
        ),
      );

      await FleaberStripeCheckoutContext.save(
        orderId: first['order_id'] as String,
        productId: first['product_id'] as String,
        liveId: lid,
        playbackId: playbackId,
        isLive: isLive,
        sellerId: sid,
        liveItemId: first['live_item_id']?.toString(),
        reservationRequestId:
            first['reservation_request_id']?.toString(),
        checkoutSessionId: result.checkoutSessionId,
        bagOrdersJson: jsonEncode(bagPayload),
      );

      final opened = await fleaberLaunchStripeCheckout(
        result.checkoutUrl,
        context: {
          'order_id': first['order_id'],
          'session_id': result.checkoutSessionId,
          'source': 'live_bag_checkout',
        },
      );
      HubBagPayDiag.log('pay_bag_launch_result', {'opened': opened});
      if (!opened) {
        await FleaberStripeCheckoutContext.clear();
        throw Exception('Não foi possível abrir o checkout Stripe.');
      }
      // Web: location.assign sai da página — não esperar settle aqui.
      if (!kIsWeb) {
        await afterStripeBrowserClosed(
          liveId: lid,
          checkoutSessionId: result.checkoutSessionId,
        );
      }
      return true;
    } catch (e, st) {
      HubBagPayDiag.fail('pay_bag_catch', e, {
        'live_id': lid,
        'uid': currentUserUid,
        'created_order_ids': createdOrderIds,
      });
      // Não deixar holds fantasma a bloquear o próximo Pagar.
      for (final oid in createdOrderIds) {
        try {
          await OrdersTable().update(
            data: {'status': 'cancelado'},
            matchingRows: (q) => q.eqOrNull('id', oid),
          );
        } catch (_) {}
      }
      unawaited(
        FleaberLogger.instance.logStripe(
          'checkout_catch',
          data: {
            'source': 'live_bag_checkout',
            'created_order_ids': createdOrderIds,
          },
          error: e,
          stackTrace: st,
        ),
      );
      if (context.mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Pagamento não avançou'),
            content: SingleChildScrollView(child: Text(msg)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return false;
    }
  }
}
