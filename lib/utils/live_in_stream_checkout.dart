import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/order_cancel_eligibility.dart';
import '/utils/fee_calculator.dart';
import '/utils/fleaber_logger.dart';
import '/utils/fleaber_radius.dart';
import '/utils/fleaber_stripe_checkout_context.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_reservation_queue_service.dart';
import '/utils/profile_shipping_requirements.dart';
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

/// Checkout Stripe no player live (sem navegar para a página do artigo).
abstract final class LiveInStreamCheckout {
  static const shippingCarrier = 'Envio Transportadora (€3.50)';
  static const shippingHand = 'Entrega em Mão (€0.00)';
  static const double shippingCarrierEur = 3.5;

  static int euroCents(double value) => (value * 100).round();

  /// Após fechar o browser Stripe: settle na edge + reconciliar reservas/encomendas.
  static Future<void> afterStripeBrowserClosed({
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

  static double shippingCostForMethod(String method) =>
      method == shippingCarrier ? shippingCarrierEur : 0.0;

  /// Portes: 3,50 € transportadora ou 0 € entrega em mão. Seguro: 0,65 € + 5% sobre (artigo+portes).
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
              '${totalEur.toStringAsFixed(2)} €',
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
            '${eur.toStringAsFixed(2)} €',
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
    int? initialPayQty,
    double? overrideItemPriceEur,
    String? checkoutNotes,
  }) async {
    if (currentUserUid.isEmpty) return;

    const paymentInApp = 'Pagamento na App';
    const paymentDirect = 'Pagamento Direto ao Vendedor (MB WAY/Transf)';

    var sellerAllowsDirectPayment = false;
    final sellerId = product.sellerId;
    if (sellerId != null && sellerId.isNotEmpty) {
      final sellerRows = await ProfilesTable().queryRows(
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
    if (liveStock != null) {
      if (reservationRequestId != null &&
          initialPayQty != null &&
          initialPayQty > 0) {
        maxQuantity = initialPayQty.clamp(1, liveStock.availableQty.clamp(1, 99));
      } else {
        maxQuantity = liveStock.availableQty.clamp(1, 99);
      }
    } else if (initialPayQty != null && initialPayQty > 0) {
      maxQuantity = initialPayQty.clamp(1, 99);
    }

    var selectedQuantity = initialPayQty != null && initialPayQty > 0
        ? initialPayQty.clamp(1, maxQuantity)
        : 1;

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF11181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        var checkoutProcessing = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            final shippingCost = shippingCostForMethod(selectedShipping);
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
            final total = isDirect
                ? productPrice
                : calculateFleaberBuyerTotal(
                    itemPriceEur: productPrice,
                    shippingEur: shippingCost,
                    includeProtectionFee: true,
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
                    Text(
                      'Portes: 3,50 € com transportadora · 0 € em entrega em mão. '
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
                          child: Text(shippingCarrier),
                        ),
                        DropdownMenuItem(
                          value: shippingHand,
                          child: Text(shippingHand),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setModalState(() => selectedShipping = v);
                      },
                    ),
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
                              if (total <= 0 || total.isNaN) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Preço inválido'),
                                  ),
                                );
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
                                if (!ready) return;
                              }
                              setModalState(() => checkoutProcessing = true);
                              final ok = await _submit(
                                context: ctx,
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
                                checkoutNotes: checkoutNotes,
                              );
                              if (!ctx.mounted) return;
                              if (ok) {
                                Navigator.pop(ctx);
                              } else {
                                setModalState(
                                    () => checkoutProcessing = false);
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
    String? checkoutNotes,
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

    try {
      if (paymentMethod.contains('Direto')) {
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
          ...liveFields,
        });
        if (!context.mounted) return true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reserva registada (${order.id?.substring(0, 8) ?? ''}).',
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

      final response = await SupaFlow.client.functions.invoke(
        'create-payment-intent',
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
          if (lid.isNotEmpty) 'live_id': lid,
          if (playbackId != null && playbackId.trim().isNotEmpty)
            'playback_id': playbackId.trim(),
          'is_live': isLive,
          if (sid.isNotEmpty) 'live_seller_id': sid,
          if (liid.isNotEmpty) 'live_item_id': liid,
          if (rid.isNotEmpty) 'reservation_request_id': rid,
        },
      );

      if (response.status >= 400) {
        final data = response.data;
        final error = data is Map ? data['error']?.toString() : null;
        throw Exception(
          error == null || error.isEmpty
              ? 'Checkout Stripe falhou (${response.status}).'
              : 'Stripe: $error',
        );
      }

      final data = response.data;
      final checkoutUrl =
          data is Map ? data['checkoutUrl']?.toString() : null;
      final checkoutSessionId =
          data is Map ? data['checkoutSessionId']?.toString() : null;
      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        final error = data is Map ? data['error']?.toString() : null;
        throw Exception(
          error == null || error.isEmpty
              ? 'Stripe não devolveu link de checkout.'
              : 'Stripe: $error',
        );
      }

      await FleaberStripeCheckoutContext.save(
        orderId: orderId,
        productId: productId,
        liveId: lid.isNotEmpty ? lid : null,
        playbackId: playbackId,
        isLive: isLive,
        sellerId: sid,
        liveItemId: liid.isNotEmpty ? liid : null,
        reservationRequestId: rid.isNotEmpty ? rid : null,
        checkoutSessionId: checkoutSessionId,
      );
      unawaited(
        FleaberLogger.instance.logStripe(
          'open_browser_live',
          data: {
            'order_id': orderId,
            'live_id': lid,
            'live_item_id': liid,
            'quantity': quantity,
          },
        ),
      );

      final opened = await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.inAppBrowserView,
        webViewConfiguration: const WebViewConfiguration(
          enableDomStorage: true,
        ),
      );
      if (!opened) {
        await FleaberStripeCheckoutContext.clear();
        throw Exception('Não foi possível abrir o checkout Stripe.');
      }
      await afterStripeBrowserClosed(
        liveId: lid,
        checkoutSessionId: checkoutSessionId,
      );
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
      return false;
    }
  }

  /// Um único Stripe para várias referências no saco.
  static Future<bool> payBagLines({
    required BuildContext context,
    required List<LiveBagCheckoutPayLine> lines,
    required String liveId,
    required String? playbackId,
    required bool isLive,
    required String? liveSellerId,
    required String shippingMethod,
    String? checkoutNotes,
  }) async {
    if (lines.isEmpty) return false;
    final lid = liveId.trim();
    if (lid.isEmpty) return false;

    final shippingCost = shippingCostForMethod(shippingMethod);
    final sid = liveSellerId?.trim() ?? lines.first.product.sellerId?.trim() ?? '';

    try {
      final sellerIds = lines
          .map((l) => l.product.sellerId?.trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
      if (sellerIds.length > 1) {
        throw Exception(
          'O saco tem vendedores diferentes — paga um de cada vez.',
        );
      }

      final bagPayload = <Map<String, dynamic>>[];
      var totalEur = 0.0;

      for (final line in lines) {
        final product = line.product;
        final productId = product.id;
        final sellerId = product.sellerId;
        if (productId == null || sellerId == null) {
          throw Exception('Artigo sem produto associado.');
        }
        final liid = line.itemRow?.id?.trim() ?? '';
        final qty = line.payQty < 1 ? 1 : line.payQty;
        final unit = product.price ?? line.itemRow?.price ?? 0.0;
        final lineItem = unit * qty;
        final lineTotal = calculateFleaberBuyerTotal(
          itemPriceEur: lineItem,
          shippingEur: 0,
          includeProtectionFee: true,
        );
        totalEur += lineTotal;

        final liveFields = <String, String>{
          'live_id': lid,
          if (liid.isNotEmpty) 'live_item_id': liid,
        };

        final order = await OrdersTable().insert({
          'product_id': productId,
          'buyer_id': currentUserUid,
          'seller_id': sellerId,
          'price_total': lineTotal,
          'shipping_method': shippingMethod,
          'payment_method': 'Pagamento na App',
          'status': 'reserva_pendente',
          'is_reservation': false,
          'quantity': qty,
          ...liveFields,
        });
        final orderId = order.id?.trim() ?? '';
        if (orderId.isEmpty) {
          throw Exception('Não foi possível criar encomenda.');
        }

        final rid = line.request.id?.trim() ?? '';
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

        if (liid.isNotEmpty && sid.isNotEmpty) {
          await LiveReservationQueueService().ensureStripeCheckoutHold(
            liveId: lid,
            liveItemId: liid,
            sellerId: sid,
            buyerId: currentUserUid,
            orderId: orderId,
            reservationRequestId: rid.isNotEmpty ? rid : null,
            tagAllActionableForItem: true,
          );
        }

        final label = LiveVendorRefDisplay.itemDisplayName(
          title: line.itemRow?.title,
          refCode: line.itemRow?.refCode,
        );

        bagPayload.add({
          'order_id': orderId,
          'product_id': productId,
          'seller_id': sellerId,
          'quantity': qty,
          'line_total_cents': euroCents(lineTotal),
          if (liid.isNotEmpty) 'live_item_id': liid,
          if (rid.isNotEmpty) 'reservation_request_id': rid,
          'item_label': label,
        });

      }

      totalEur += shippingCost;

      final first = bagPayload.first;
      final response = await SupaFlow.client.functions.invoke(
        'create-payment-intent',
        body: {
          'amount': euroCents(totalEur),
          'currency': 'eur',
          'product_id': first['product_id'],
          'buyer_id': currentUserUid,
          'seller_id': first['seller_id'],
          'order_id': first['order_id'],
          'quantity': 1,
          'item_price': euroCents(totalEur - shippingCost),
          'shipping': euroCents(shippingCost),
          'protection_fee': 0,
          'shipping_method': shippingMethod,
          'live_id': lid,
          if (playbackId != null && playbackId.trim().isNotEmpty)
            'playback_id': playbackId.trim(),
          'is_live': isLive,
          if (sid.isNotEmpty) 'live_seller_id': sid,
          'bag_checkout': true,
          'bag_lines': bagPayload,
        },
      );

      if (response.status >= 400) {
        final data = response.data;
        final error = data is Map ? data['error']?.toString() : null;
        throw Exception(
          error == null || error.isEmpty
              ? 'Checkout Stripe falhou (${response.status}).'
              : 'Stripe: $error',
        );
      }

      final data = response.data;
      final checkoutUrl =
          data is Map ? data['checkoutUrl']?.toString() : null;
      final checkoutSessionId =
          data is Map ? data['checkoutSessionId']?.toString() : null;
      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        final error = data is Map ? data['error']?.toString() : null;
        throw Exception(
          error == null || error.isEmpty
              ? 'Stripe não devolveu link de checkout.'
              : 'Stripe: $error',
        );
      }

      unawaited(
        FleaberLogger.instance.logStripe(
          'open_browser_live_bag',
          data: {
            'live_id': lid,
            'line_count': bagPayload.length,
            'order_ids': bagPayload.map((e) => e['order_id']).toList(),
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
        checkoutSessionId: checkoutSessionId,
        bagOrdersJson: jsonEncode(bagPayload),
      );

      final opened = await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.inAppBrowserView,
        webViewConfiguration: const WebViewConfiguration(
          enableDomStorage: true,
        ),
      );
      if (!opened) {
        await FleaberStripeCheckoutContext.clear();
        throw Exception('Não foi possível abrir o checkout Stripe.');
      }
      await afterStripeBrowserClosed(
        liveId: lid,
        checkoutSessionId: checkoutSessionId,
      );
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
      return false;
    }
  }
}
