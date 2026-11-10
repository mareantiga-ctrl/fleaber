import '/backend/supabase/database/tables/orders.dart';
import '/order_cancel_eligibility.dart';
import '/utils/order_delivery_display.dart';

/// ZIP 145 — estados pós-compra (peso / diferença / envio / cancelamento).
/// Só interpreta campos e RPCs já definidos pelo C1 (ZIPs 142/143) — sem lógica paralela.
enum OrderPostPurchasePhase {
  none,
  awaitWeightConfirm,
  awaitDeltaPayment,
  deltaPaidReadyToShip,
  awaitShipment,
  shipped,
  deliveredOrDone,
  cancelled,
}

enum OrderRefundUiStatus {
  none,
  initiated,
  completed,
}

class OrderPostPurchaseView {
  const OrderPostPurchaseView({
    required this.phase,
    required this.title,
    required this.detailLines,
    required this.actionNeeded,
    required this.showSellerWeightActions,
    required this.showBuyerPayDelta,
    required this.canGenerateDpdLabel,
    required this.dpdBlockedReason,
    required this.carrierLabel,
    required this.trackingCode,
    required this.trackingUrl,
    required this.refundStatus,
    required this.refundLabel,
    required this.cancelReason,
    required this.extraAmountLabel,
    required this.payDeadlineLabel,
    required this.weightDeadlineLabel,
    required this.shipByLabel,
    required this.buyerPaidDelta,
  });

  final OrderPostPurchasePhase phase;
  final String title;
  final List<String> detailLines;
  final bool actionNeeded;
  final bool showSellerWeightActions;
  final bool showBuyerPayDelta;
  final bool canGenerateDpdLabel;
  final String? dpdBlockedReason;
  final String? carrierLabel;
  final String? trackingCode;
  final String? trackingUrl;
  final OrderRefundUiStatus refundStatus;
  final String? refundLabel;
  final String? cancelReason;
  final String? extraAmountLabel;
  final String? payDeadlineLabel;
  final String? weightDeadlineLabel;
  final String? shipByLabel;
  final bool buyerPaidDelta;

  bool get isVisible =>
      phase != OrderPostPurchasePhase.none ||
      (trackingCode ?? '').trim().isNotEmpty ||
      cancelReason != null ||
      refundStatus != OrderRefundUiStatus.none;
}

/// Datas sempre DD/MM/AAAA (opcionalmente HH:MM local do device).
String formatOrderDeadlinePt(DateTime? at, {bool withTime = true}) {
  if (at == null) return '';
  final local = at.toLocal();
  final dd = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final yyyy = local.year.toString();
  if (!withTime) return '$dd/$mm/$yyyy';
  final hh = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$dd/$mm/$yyyy $hh:$min';
}

String? formatOrderDeadlineIsoPt(String? iso, {bool withTime = true}) {
  final s = (iso ?? '').trim();
  if (s.isEmpty) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  final out = formatOrderDeadlinePt(d, withTime: withTime);
  return out.isEmpty ? null : out;
}

String? publicDpdTrackingUrl(String? code) {
  final g = (code ?? '').trim();
  if (g.isEmpty) return null;
  return 'https://www.dpd.pt/tracking?parcelNumber=${Uri.encodeComponent(g)}';
}

OrderPostPurchaseView buildOrderPostPurchaseView({
  required OrdersRow order,
  required bool isSellerView,
  Map<String, dynamic>? pendingAdjustment,
}) {
  final raw = orderStatusRawFromData(order.data);
  final key = normalizeOrderStatusKey(raw);
  final cancelled = orderIsCancelled(raw);
  final weight = (order.weightConfirmStatus ?? '').trim().toLowerCase();
  final delta = (order.shippingDeltaStatus ?? '').trim().toLowerCase();
  final guide = (order.dpdTrackingCode ?? '').trim();
  final hasGuide = guide.isNotEmpty;
  final clockPaused = order.shipClockPausedAt != null;
  final weightDeadline = formatOrderDeadlinePt(order.weightConfirmDeadlineAt);
  final shipBy = formatOrderDeadlinePt(order.shipByAt);
  final payUntil = formatOrderDeadlineIsoPt(
    pendingAdjustment?['expires_at']?.toString(),
  );

  String? extraAmount;
  if (pendingAdjustment != null) {
    final cents = _asInt(pendingAdjustment['amount_charge_cents']);
    if (cents > 0) {
      extraAmount = '${(cents / 100.0).toStringAsFixed(2).replaceAll('.', ',')} €';
    }
  }

  // C1: `stripe_refund_id` sozinho = pedido/selo antecipado (refund-order).
  // Concluído só com `stripe_refunded_at` (finalize / confirmação efectiva).
  OrderRefundUiStatus refund = OrderRefundUiStatus.none;
  String? refundLabel;
  final hasRefundId = (order.stripeRefundId ?? '').trim().isNotEmpty;
  if (order.stripeRefundedAt != null) {
    refund = OrderRefundUiStatus.completed;
    refundLabel = 'Reembolso concluído';
  } else if (cancelled || hasRefundId) {
    refund = OrderRefundUiStatus.initiated;
    refundLabel = 'Reembolso iniciado';
  }

  String? cancelReason;
  if (cancelled) {
    if (delta == 'expired') {
      cancelReason =
          'Diferença de portes não paga no prazo de 48 horas.';
    } else if (key.contains('cancel') || key == 'cancelado') {
      // Prazo de envio / outros — mensagem humana a partir do estado C1.
      if ((order.shipByAt != null) &&
          order.shipByAt!.isBefore(DateTime.now()) &&
          !hasGuide) {
        cancelReason = 'Prazo de envio ultrapassado.';
      } else {
        cancelReason = 'Encomenda cancelada.';
      }
    }
  }

  final hand = _isHand(order.shippingMethod);
  final paidLike = key == 'pago' ||
      key == 'aguarda_confirmacao' ||
      key == 'enviado' ||
      key == 'concluido';

  if (cancelled) {
    return OrderPostPurchaseView(
      phase: OrderPostPurchasePhase.cancelled,
      title: 'Encomenda cancelada',
      detailLines: [
        if (cancelReason != null) cancelReason,
        if (refundLabel != null) refundLabel,
        if (refund == OrderRefundUiStatus.initiated)
          'O valor será devolvido — o prazo depende do teu banco.',
        if (refund == OrderRefundUiStatus.completed)
          'O valor deve aparecer na conta em breve, conforme o banco.',
      ],
      actionNeeded: false,
      showSellerWeightActions: false,
      showBuyerPayDelta: false,
      canGenerateDpdLabel: false,
      dpdBlockedReason: 'Encomenda cancelada — etiqueta DPD indisponível.',
      carrierLabel: hasGuide ? 'DPD' : null,
      trackingCode: hasGuide ? guide : null,
      trackingUrl: publicDpdTrackingUrl(guide),
      refundStatus: refund,
      refundLabel: refundLabel,
      cancelReason: cancelReason,
      extraAmountLabel: null,
      payDeadlineLabel: null,
      weightDeadlineLabel: weightDeadline.isEmpty ? null : weightDeadline,
      shipByLabel: shipBy.isEmpty ? null : shipBy,
      buyerPaidDelta: delta == 'paid' || weight == 'delta_paid',
    );
  }

  if (hand || !paidLike) {
    return OrderPostPurchaseView(
      phase: OrderPostPurchasePhase.none,
      title: '',
      detailLines: const [],
      actionNeeded: false,
      showSellerWeightActions: false,
      showBuyerPayDelta: false,
      canGenerateDpdLabel: false,
      dpdBlockedReason: null,
      carrierLabel: null,
      trackingCode: null,
      trackingUrl: null,
      refundStatus: refund,
      refundLabel: refundLabel,
      cancelReason: null,
      extraAmountLabel: null,
      payDeadlineLabel: null,
      weightDeadlineLabel: null,
      shipByLabel: null,
      buyerPaidDelta: false,
    );
  }

  final weightPending = weight == 'pending' || weight.isEmpty && key == 'pago';
  // C1: pending explícito; vazio em pago tratado como a confirmar se deadline existe.
  final needsWeight = weight == 'pending' ||
      (key == 'pago' &&
          weight != 'confirmed_same' &&
          weight != 'assumed_by_seller' &&
          weight != 'delta_paid' &&
          weight != 'not_required' &&
          (weightPending || order.weightConfirmDeadlineAt != null));

  final deltaPending = delta == 'pending' || pendingAdjustment != null;
  final deltaPaid = delta == 'paid' || weight == 'delta_paid';
  final weightDone = weight == 'confirmed_same' ||
      weight == 'assumed_by_seller' ||
      weight == 'delta_paid' ||
      weight == 'not_required';

  String? dpdBlock;
  var canDpd = false;
  if (hasGuide) {
    dpdBlock = null;
    canDpd = false;
  } else if (deltaPending || clockPaused) {
    dpdBlock =
        'Etiqueta DPD bloqueada enquanto a diferença de portes estiver pendente.';
  } else if (needsWeight && weight != 'not_required') {
    dpdBlock =
        'Confirma o peso (ou assume / pede diferença) antes de gerar a etiqueta DPD.';
  } else if (key == 'pago' && weightDone) {
    canDpd = isSellerView;
    dpdBlock = isSellerView
        ? null
        : 'O vendedor pode gerar a etiqueta DPD quando o peso estiver resolvido.';
  } else if (key == 'pago') {
    dpdBlock = 'Aguarda a confirmação de peso do vendedor.';
  }

  if (key == 'enviado' || hasGuide && (order.dpdAcceptAt != null || key == 'enviado')) {
    return OrderPostPurchaseView(
      phase: OrderPostPurchasePhase.shipped,
      title: order.dpdAcceptAt != null
          ? 'A caminho'
          : 'Expedida — seguimento disponível',
      detailLines: [
        ...orderBuyerDeliveryDetailLines(order),
        if (hasGuide) 'Transportadora: DPD',
        if (hasGuide) 'Código: $guide',
        if (shipBy.isNotEmpty && order.dpdAcceptAt == null)
          'Prazo de envio: $shipBy',
      ],
      actionNeeded: false,
      showSellerWeightActions: false,
      showBuyerPayDelta: false,
      canGenerateDpdLabel: false,
      dpdBlockedReason: null,
      carrierLabel: hasGuide ? 'DPD' : null,
      trackingCode: hasGuide ? guide : null,
      trackingUrl: publicDpdTrackingUrl(guide),
      refundStatus: OrderRefundUiStatus.none,
      refundLabel: null,
      cancelReason: null,
      extraAmountLabel: null,
      payDeadlineLabel: null,
      weightDeadlineLabel: null,
      shipByLabel: shipBy.isEmpty ? null : shipBy,
      buyerPaidDelta: deltaPaid,
    );
  }

  if (deltaPending) {
    final lines = <String>[
      if (extraAmount != null) 'Valor adicional: $extraAmount',
      if (payUntil != null) 'Pagar até: $payUntil (48 horas)',
      if (isSellerView)
        'O comprador ainda não pagou a diferença. O prazo de envio está pausado.'
      else
        'Paga a diferença para o vendedor poder expedir.',
      'Sem Proteção Fleaber adicional neste pagamento.',
    ];
    return OrderPostPurchaseView(
      phase: OrderPostPurchasePhase.awaitDeltaPayment,
      title: isSellerView
          ? 'Aguarda pagamento da diferença de portes'
          : 'Aguarda o teu pagamento da diferença de portes',
      detailLines: lines,
      actionNeeded: !isSellerView,
      showSellerWeightActions: false,
      showBuyerPayDelta: !isSellerView,
      canGenerateDpdLabel: false,
      dpdBlockedReason: dpdBlock,
      carrierLabel: null,
      trackingCode: null,
      trackingUrl: null,
      refundStatus: OrderRefundUiStatus.none,
      refundLabel: null,
      cancelReason: null,
      extraAmountLabel: extraAmount,
      payDeadlineLabel: payUntil,
      weightDeadlineLabel: weightDeadline.isEmpty ? null : weightDeadline,
      shipByLabel: shipBy.isEmpty ? null : shipBy,
      buyerPaidDelta: false,
    );
  }

  if (needsWeight && weight != 'not_required') {
    final lines = <String>[
      ...orderBuyerDeliveryDetailLines(order),
      if (weightDeadline.isNotEmpty)
        'Confirmar peso até: $weightDeadline',
      if (isSellerView)
        'Podes confirmar o mesmo escalão, assumir a diferença ou pedir diferença ao comprador (48 h).'
      else
        'O vendedor está a confirmar o peso do envio.',
      if (shipBy.isNotEmpty) 'Prazo para expedir: $shipBy',
    ];
    return OrderPostPurchaseView(
      phase: OrderPostPurchasePhase.awaitWeightConfirm,
      title: isSellerView
          ? 'Ação necessária: confirmar peso'
          : 'Aguarda confirmação de peso',
      detailLines: lines,
      actionNeeded: isSellerView,
      showSellerWeightActions: isSellerView,
      showBuyerPayDelta: false,
      canGenerateDpdLabel: false,
      dpdBlockedReason: dpdBlock,
      carrierLabel: null,
      trackingCode: null,
      trackingUrl: null,
      refundStatus: OrderRefundUiStatus.none,
      refundLabel: null,
      cancelReason: null,
      extraAmountLabel: null,
      payDeadlineLabel: null,
      weightDeadlineLabel: weightDeadline.isEmpty ? null : weightDeadline,
      shipByLabel: shipBy.isEmpty ? null : shipBy,
      buyerPaidDelta: false,
    );
  }

  if (deltaPaid || weightDone) {
    final lines = <String>[
      ...orderBuyerDeliveryDetailLines(order),
      if (deltaPaid && isSellerView) 'O comprador já pagou a diferença de portes.',
      if (deltaPaid && !isSellerView) 'Diferença de portes paga.',
      if (weight == 'assumed_by_seller')
        'Diferença de portes assumida pelo vendedor.',
      if (shipBy.isNotEmpty) 'Expedir até: $shipBy',
      if (canDpd && isSellerView)
        'Podes gerar a etiqueta DPD agora.'
      else if (dpdBlock != null)
        dpdBlock,
    ];
    return OrderPostPurchaseView(
      phase: deltaPaid
          ? OrderPostPurchasePhase.deltaPaidReadyToShip
          : OrderPostPurchasePhase.awaitShipment,
      title: isSellerView
          ? (canDpd
              ? 'Pronta para etiqueta DPD'
              : 'Aguarda expedição')
          : 'Aguarda expedição',
      detailLines: lines,
      actionNeeded: isSellerView && canDpd,
      showSellerWeightActions: false,
      showBuyerPayDelta: false,
      canGenerateDpdLabel: canDpd && isSellerView,
      dpdBlockedReason: canDpd ? null : dpdBlock,
      carrierLabel: hasGuide ? 'DPD' : null,
      trackingCode: hasGuide ? guide : null,
      trackingUrl: publicDpdTrackingUrl(guide),
      refundStatus: OrderRefundUiStatus.none,
      refundLabel: null,
      cancelReason: null,
      extraAmountLabel: null,
      payDeadlineLabel: null,
      weightDeadlineLabel: null,
      shipByLabel: shipBy.isEmpty ? null : shipBy,
      buyerPaidDelta: deltaPaid,
    );
  }

  return OrderPostPurchaseView(
    phase: OrderPostPurchasePhase.none,
    title: '',
    detailLines: const [],
    actionNeeded: false,
    showSellerWeightActions: false,
    showBuyerPayDelta: false,
    canGenerateDpdLabel: false,
    dpdBlockedReason: null,
    carrierLabel: hasGuide ? 'DPD' : null,
    trackingCode: hasGuide ? guide : null,
    trackingUrl: publicDpdTrackingUrl(guide),
    refundStatus: refund,
    refundLabel: refundLabel,
    cancelReason: null,
    extraAmountLabel: null,
    payDeadlineLabel: null,
    weightDeadlineLabel: null,
    shipByLabel: shipBy.isEmpty ? null : shipBy,
    buyerPaidDelta: false,
  );
}

bool _isHand(String? method) {
  final sm = (method ?? '').trim().toLowerCase();
  return sm == 'hand' ||
      sm.contains('entrega em mao') ||
      sm.contains('entrega em mão') ||
      sm.contains('mão') ||
      sm.contains('mao');
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}
