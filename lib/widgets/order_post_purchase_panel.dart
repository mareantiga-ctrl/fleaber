import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '/backend/supabase/database/tables/orders.dart';
import '/utils/dpd_expedition_service.dart';
import '/utils/fleaber_colors.dart';
import '/utils/order_post_purchase_lifecycle.dart';
import '/utils/order_shipping_ops_service.dart';
import '/widgets/dpd_seller_dropoff_sheet.dart';
import '/widgets/dpd_tracking_sheet.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/order_weight_confirm_sheet.dart';

/// Painel pós-compra (Minhas Encomendas) — Hub-like, reutiliza sheets C1.
class OrderPostPurchasePanel extends StatefulWidget {
  const OrderPostPurchasePanel({
    super.key,
    required this.order,
    required this.isSellerView,
    this.onChanged,
  });

  final OrdersRow order;
  final bool isSellerView;
  final VoidCallback? onChanged;

  @override
  State<OrderPostPurchasePanel> createState() => _OrderPostPurchasePanelState();
}

class _OrderPostPurchasePanelState extends State<OrderPostPurchasePanel> {
  Map<String, dynamic>? _pendingAdj;
  bool _loadingAdj = true;
  bool _dpdBusy = false;
  bool _dpdCreateDisabled = false;

  @override
  void initState() {
    super.initState();
    _loadAdj();
  }

  @override
  void didUpdateWidget(covariant OrderPostPurchasePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.id != widget.order.id ||
        oldWidget.order.shippingDeltaStatus !=
            widget.order.shippingDeltaStatus) {
      _loadAdj();
    }
  }

  Future<void> _loadAdj() async {
    final oid = (widget.order.id ?? '').trim();
    if (oid.isEmpty) {
      if (mounted) setState(() => _loadingAdj = false);
      return;
    }
    setState(() => _loadingAdj = true);
    try {
      final adj =
          await OrderShippingOpsService.fetchPendingAdjustment(oid);
      if (!mounted) return;
      setState(() {
        _pendingAdj = adj;
        _loadingAdj = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pendingAdj = null;
        _loadingAdj = false;
      });
    }
  }

  Future<void> _openWeightSheet() async {
    final oid = (widget.order.id ?? '').trim();
    if (oid.isEmpty) return;
    await showOrderWeightConfirmSheet(
      context: context,
      orderId: oid,
      chargedBand: widget.order.shippingWeightChargedBand ??
          widget.order.shippingWeightBand,
    );
    widget.onChanged?.call();
    await _loadAdj();
  }

  Future<void> _openPayDelta() async {
    final oid = (widget.order.id ?? '').trim();
    if (oid.isEmpty) return;
    await showOrderShippingDeltaPaySheet(
      context: context,
      orderId: oid,
    );
    widget.onChanged?.call();
    await _loadAdj();
  }

  Future<void> _obtainDpd() async {
    final oid = (widget.order.id ?? '').trim();
    if (oid.isEmpty || _dpdBusy || _dpdCreateDisabled) return;
    setState(() => _dpdBusy = true);
    try {
      final res = await DpdExpeditionService.obtainLabel(orderId: oid);
      if (!mounted) return;
      if (res.createDisabled) {
        setState(() => _dpdCreateDisabled = true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.userMessage)),
      );
      if (res.ok) {
        widget.onChanged?.call();
        final label = (res.labelUrl ?? '').trim();
        // Abrir PDF Fleaber no telemóvel (não o link privado DPD).
        if (label.isNotEmpty && !_isDpdPrivateApiUrl(label)) {
          await _openTrackingUrl(label);
        }
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Etiqueta temporariamente indisponível.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _dpdBusy = false);
    }
  }

  bool _isDpdPrivateApiUrl(String url) {
    final u = url.toLowerCase();
    return u.contains('dpd.pt/') && u.contains('etiquetaapi');
  }

  Future<void> _openTrackingUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingAdj) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(
          minHeight: 2,
          color: Color(0xFF007782),
        ),
      );
    }

    final view = buildOrderPostPurchaseView(
      order: widget.order,
      isSellerView: widget.isSellerView,
      pendingAdjustment: _pendingAdj,
    );
    if (!view.isVisible) return const SizedBox.shrink();

    final accent = view.actionNeeded
        ? const Color(0xFFE65100)
        : view.phase == OrderPostPurchasePhase.cancelled
            ? FleaberColors.danger
            : const Color(0xFF007782);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: view.actionNeeded
                ? accent.withValues(alpha: 0.45)
                : const Color(0xFFE0E5EA),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    view.actionNeeded
                        ? Icons.priority_high_rounded
                        : Icons.local_shipping_outlined,
                    size: 18,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      view.title.isEmpty ? 'Envio' : view.title,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF101518),
                      ),
                    ),
                  ),
                  if (view.actionNeeded)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Ação',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                ],
              ),
              for (final line in view.detailLines) ...[
                const SizedBox(height: 6),
                Text(
                  line,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.35,
                    color: const Color(0xFF57636C),
                  ),
                ),
              ],
              if ((view.trackingCode ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Transportadora: ${view.carrierLabel ?? 'DPD'}',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF101518),
                  ),
                ),
                Text(
                  'Código: ${view.trackingCode}',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: const Color(0xFF57636C),
                  ),
                ),
                if ((view.trackingCode ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        final oid = (widget.order.id ?? '').trim();
                        if (oid.isEmpty) return;
                        // Folha in-app (API QA) — evita browser DPD em branco
                        // quando a guia ainda não tem eventos na rede.
                        showDpdTrackingSheet(
                          context,
                          orderId: oid,
                          knownGuide: view.trackingCode,
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF007782),
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Ver seguimento DPD',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
              if (view.dpdBlockedReason != null &&
                  !view.canGenerateDpdLabel &&
                  view.phase != OrderPostPurchasePhase.cancelled) ...[
                const SizedBox(height: 6),
                Text(
                  view.dpdBlockedReason!,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: const Color(0xFF8A949E),
                    height: 1.3,
                  ),
                ),
              ],
              if (view.showBuyerPayDelta) ...[
                const SizedBox(height: 10),
                FleaberPrimaryButton(
                  label: view.extraAmountLabel == null
                      ? 'Pagar diferença'
                      : 'Pagar diferença (${view.extraAmountLabel})',
                  onPressed: _openPayDelta,
                  height: 44,
                  borderRadius: 12,
                ),
              ],
              if (view.showSellerWeightActions) ...[
                const SizedBox(height: 10),
                FleaberPrimaryButton(
                  label: 'Confirmar peso / diferença',
                  onPressed: _openWeightSheet,
                  height: 44,
                  borderRadius: 12,
                ),
              ],
              if (view.canGenerateDpdLabel && !_dpdCreateDisabled) ...[
                const SizedBox(height: 10),
                FleaberPrimaryButton(
                  label: _dpdBusy ? 'A gerar…' : 'Gerar etiqueta DPD',
                  onPressed: _dpdBusy ? null : _obtainDpd,
                  height: 44,
                  borderRadius: 12,
                ),
              ],
              if (view.canGenerateDpdLabel && _dpdCreateDisabled) ...[
                const SizedBox(height: 10),
                Text(
                  'A criação de etiquetas DPD está temporariamente desligada.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.35,
                    color: const Color(0xFF8A949E),
                  ),
                ),
              ],
              if (((widget.order.dpdLabelUrl ?? '').trim().isNotEmpty) &&
                  widget.isSellerView) ...[
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () =>
                      _openTrackingUrl(widget.order.dpdLabelUrl!.trim()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF007782),
                    side: const BorderSide(color: Color(0xFF007782)),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Ver / imprimir etiqueta DPD',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
              if (widget.isSellerView &&
                  (view.canGenerateDpdLabel ||
                      (widget.order.dpdLabelUrl ?? '').trim().isNotEmpty ||
                      view.phase == OrderPostPurchasePhase.awaitShipment ||
                      view.phase ==
                          OrderPostPurchasePhase.deltaPaidReadyToShip ||
                      view.phase == OrderPostPurchasePhase.awaitWeightConfirm ||
                      view.phase == OrderPostPurchasePhase.shipped)) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => showDpdSellerDropoffSheet(context),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF007782),
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                  ),
                  child: Text(
                    'Onde posso entregar as minhas encomendas?',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
