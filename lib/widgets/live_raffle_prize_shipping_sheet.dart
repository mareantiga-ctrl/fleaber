import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/fee_calculator.dart';
import '/utils/fleaber_logger.dart';
import '/utils/fleaber_radius.dart';
import '/utils/fleaber_stripe_checkout_context.dart';
import '/utils/fleaber_stripe_launch.dart';
import '/utils/live_raffle_prize_copy.dart';
import '/widgets/fleaber_primary_button.dart';

/// Resultado do sheet de portes do Prémio da Rifa.
enum LiveRafflePrizeShippingResult {
  paidStripeOpened,
  handConfirmed,
  browseSeller,
  cancelled,
}

/// Sheet: pagar envio do prémio + incentivo a comprar mais do mesmo vendedor.
class LiveRafflePrizeShippingSheet extends StatefulWidget {
  const LiveRafflePrizeShippingSheet({
    super.key,
    required this.order,
    required this.product,
    this.sellerDisplayName,
  });

  final OrdersRow order;
  final ProductsRow product;
  final String? sellerDisplayName;

  static Future<LiveRafflePrizeShippingResult?> show({
    required BuildContext context,
    required OrdersRow order,
    required ProductsRow product,
    String? sellerDisplayName,
  }) {
    return showModalBottomSheet<LiveRafflePrizeShippingResult>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: const Color(0xFF101518),
      shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularLg),
      builder: (ctx) => LiveRafflePrizeShippingSheet(
        order: order,
        product: product,
        sellerDisplayName: sellerDisplayName,
      ),
    );
  }

  @override
  State<LiveRafflePrizeShippingSheet> createState() =>
      _LiveRafflePrizeShippingSheetState();
}

class _LiveRafflePrizeShippingSheetState
    extends State<LiveRafflePrizeShippingSheet> {
  static const _carrierMethod = kFleaberShippingCarrierMethod;
  static const _handMethod = kFleaberShippingHandMethod;
  static const _carrierLabel = kFleaberShippingCarrierLabel;
  static const _handLabel = kFleaberShippingHandLabel;
  static const _paymentInApp = 'Pagamento na app';

  bool _carrier = true;
  bool _busy = false;
  String? _error;

  double get _shippingEur =>
      fleaberShippingEurFromMethod(_carrier ? _carrierMethod : _handMethod);
  double get _protectionEur => _carrier
      ? calculateFleaberProtectionFee(0, shippingEur: _shippingEur)
      : 0;
  double get _totalEur => calculateFleaberBuyerTotal(
        itemPriceEur: 0,
        shippingEur: _shippingEur,
        includeProtectionFee: _carrier,
      );

  String get _sellerLabel {
    final n = widget.sellerDisplayName?.trim() ?? '';
    if (n.isNotEmpty) return n;
    return 'esta vendedora';
  }

  int _euroCents(double value) => (value * 100).round();

  Future<void> _payCarrier() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final orderId = widget.order.id?.trim() ?? '';
      final productId = widget.product.id?.trim() ?? '';
      final sellerId = widget.product.sellerId?.trim() ??
          widget.order.sellerId?.trim() ??
          '';
      if (orderId.isEmpty || productId.isEmpty || sellerId.isEmpty) {
        throw Exception('Encomenda incompleta.');
      }

      await OrdersTable().update(
        data: {
          'price_total': _totalEur,
          'shipping_method': _carrierMethod,
          'payment_method': _paymentInApp,
        },
        matchingRows: (q) => q.eqOrNull('id', orderId),
      );

      final result = await fleaberInvokeCreatePaymentIntent(
        body: {
          'amount': _euroCents(_totalEur),
          'currency': 'eur',
          'product_id': productId,
          'buyer_id': currentUserUid,
          'seller_id': sellerId,
          'order_id': orderId,
          'quantity': 1,
          'item_price': 0,
          'shipping': _euroCents(_shippingEur),
          'protection_fee': _euroCents(_protectionEur),
          'shipping_method': _carrierMethod,
          'prize_shipping': true,
          if ((widget.order.liveId ?? '').trim().isNotEmpty)
            'live_id': widget.order.liveId!.trim(),
          if ((widget.order.liveItemId ?? '').trim().isNotEmpty)
            'live_item_id': widget.order.liveItemId!.trim(),
        },
        logContext: {'source': 'raffle_prize_shipping'},
      );

      await FleaberStripeCheckoutContext.save(
        orderId: orderId,
        productId: productId,
        liveId: widget.order.liveId,
        liveItemId: widget.order.liveItemId,
        sellerId: sellerId,
        checkoutSessionId: result.checkoutSessionId,
      );
      unawaited(
        FleaberLogger.instance.logStripe(
          'raffle_prize_shipping_open',
          data: {
            'order_id': orderId,
            'total': _totalEur,
            'session_id': result.checkoutSessionId,
          },
        ),
      );

      final opened = await fleaberLaunchStripeCheckout(
        result.checkoutUrl,
        context: {
          'order_id': orderId,
          'session_id': result.checkoutSessionId,
          'source': 'raffle_prize_shipping',
        },
      );
      if (!opened) {
        await FleaberStripeCheckoutContext.clear();
        throw Exception('Não foi possível abrir o checkout.');
      }
      if (!mounted) return;
      Navigator.of(context).pop(LiveRafflePrizeShippingResult.paidStripeOpened);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _confirmHand() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final orderId = widget.order.id?.trim() ?? '';
      if (orderId.isEmpty) throw Exception('Encomenda incompleta.');
      await OrdersTable().update(
        data: {
          'price_total': 0,
          'shipping_method': _handMethod,
          'payment_method': LiveRafflePrizeCopy.paymentMethod,
          'status': 'pago',
        },
        matchingRows: (q) => q.eqOrNull('id', orderId),
      );
      // Addon «Mesmo envio do Prémio» herda mão — senão o sticky do V mostra etiqueta.
      final bundleId = widget.order.bundleId?.trim() ?? '';
      if (bundleId.isNotEmpty) {
        final siblings = await OrdersTable().queryRows(
          queryFn: (q) => q.eqOrNull('bundle_id', bundleId),
          limit: 20,
        );
        for (final sib in siblings) {
          final sid = sib.id?.trim() ?? '';
          if (sid.isEmpty || sid == orderId) continue;
          final sm = (sib.shippingMethod ?? '').toLowerCase();
          if (!sm.contains('mesmo envio')) continue;
          await OrdersTable().update(
            data: {'shipping_method': _handMethod},
            matchingRows: (q) => q.eqOrNull('id', sid),
          );
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(LiveRafflePrizeShippingResult.handConfirmed);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final title = widget.product.title?.trim().isNotEmpty == true
        ? widget.product.title!.trim()
        : 'Prémio da Rifa';

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Enviar o teu prémio',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: GoogleFonts.inter(
                color: const Color(0xFFFFD54F),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              LiveRafflePrizeCopy.shippingSheetIntro,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            _optionTile(
              selected: _carrier,
              title: 'Envio por transportadora',
              subtitle: '3,50 € + Seguro Fleaber',
              onTap: () => setState(() => _carrier = true),
            ),
            const SizedBox(height: 8),
            _optionTile(
              selected: !_carrier,
              title: 'Entrega em mão',
              subtitle: 'Grátis — combinas com $_sellerLabel',
              onTap: () => setState(() => _carrier = false),
            ),
            if (_carrier) ...[
              const SizedBox(height: 12),
              _breakdownRow('Portes', formatEuros(_shippingEur)),
              _breakdownRow('Seguro Fleaber', formatEuros(_protectionEur)),
              const Divider(color: Colors.white24, height: 20),
              _breakdownRow('Total a pagar', formatEuros(_totalEur), bold: true),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF00A3AD).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF00A3AD).withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                LiveRafflePrizeCopy.shippingBundleHint(_sellerLabel),
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: GoogleFonts.inter(
                  color: const Color(0xFFFF8A80),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FleaberPrimaryButton(
              label: _carrier
                  ? 'Pagar envio · ${formatEuros(_totalEur)}'
                  : 'Confirmar entrega em mão',
              loading: _busy,
              onPressed: _busy
                  ? null
                  : () {
                      if (_carrier) {
                        unawaited(_payCarrier());
                      } else {
                        unawaited(_confirmHand());
                      }
                    },
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context)
                      .pop(LiveRafflePrizeShippingResult.browseSeller),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Ver loja de $_sellerLabel',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context)
                      .pop(LiveRafflePrizeShippingResult.cancelled),
              child: Text(
                'Mais tarde',
                style: GoogleFonts.inter(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionTile({
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? const Color(0xFF00A3AD).withValues(alpha: 0.18)
          : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF00A3AD)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? const Color(0xFF00A3AD) : Colors.white54,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 12,
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

  Widget _breakdownRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                fontSize: bold ? 14 : 13,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: bold ? 15 : 13,
            ),
          ),
        ],
      ),
    );
  }
}
