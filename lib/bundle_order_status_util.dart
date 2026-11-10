import 'package:flutter/material.dart';

import '/backend/supabase/supabase.dart';
import '/order_cancel_eligibility.dart';
import '/utils/fleaber_colors.dart';

int bundleTotalItemCountFromOrders(List<OrdersRow> orders) {
  return orders.fold<int>(0, (sum, o) => sum + (o.quantity ?? 1));
}

String _orderStatusKey(OrdersRow order) =>
    normalizeOrderStatusKey(orderStatusRawFromData(order.data));

/// Estado agregado visível no card conjunto colapsado (paridade chat + encomendas).
String bundleGroupAggregatedStatusPhrase(List<OrdersRow> orders) {
  if (orders.isEmpty) return '—';
  final active = orders.where((o) => !orderIsCancelled(_orderStatusKey(o))).toList();
  if (active.isEmpty) return 'Cancelado';

  String phraseFor(OrdersRow order) {
    final raw = orderStatusRawFromData(order.data).trim();
    if (orderIsCancelled(raw)) return 'Cancelado';
    return orderStatusDisplayPhrase(
      raw,
      shippingMethod: order.shippingMethod,
      paymentMethod: order.paymentMethod,
    );
  }

  final firstPhrase = phraseFor(active.first);
  if (active.every((o) => phraseFor(o) == firstPhrase)) {
    return firstPhrase;
  }

  if (active.every((o) {
    final st = _orderStatusKey(o);
    return st == 'enviado' || st == 'concluido';
  })) {
    if (active.every((o) => _orderStatusKey(o) == 'concluido')) {
      return 'Concluída';
    }
    return 'Artigo Enviado';
  }
  if (active.every((o) => _orderStatusKey(o) == 'pago')) {
    return 'Pago';
  }
  if (active.every((o) => _orderStatusKey(o) == 'premio_rifa')) {
    return 'Prémio da Rifa · Envio a pagar';
  }
  return phraseFor(active.first);
}

/// Sub-linha dentro de conjunto — estado real de cada linha (coerente com o badge).
String bundleSubRowStatusPhrase(OrdersRow order, List<OrdersRow> groupOrders) {
  return bundleGroupAggregatedStatusPhrase([order]);
}

/// Cor/ícone do selo agregado no card conjunto fechado.
({Color color, IconData icon}) bundleGroupAggregatedStatusVisual(
  List<OrdersRow> orders,
) {
  final phrase = bundleGroupAggregatedStatusPhrase(orders);
  switch (phrase) {
    case 'Cancelado':
      return (color: FleaberColors.danger, icon: Icons.cancel_rounded);
    case 'Pedido de Reserva':
      return (
        color: const Color(0xFFD97706),
        icon: Icons.schedule_rounded,
      );
    case 'Reservado (Aguardando Pagamento)':
      return (
        color: const Color(0xFF007782),
        icon: Icons.bookmark_added_rounded,
      );
    case 'Pagamento pendente':
      return (
        color: const Color(0xFFE65100),
        icon: Icons.payments_outlined,
      );
    case 'Pagamento em Verificação':
      return (
        color: const Color(0xFF1565C0),
        icon: Icons.fact_check_rounded,
      );
    case 'Pago':
      return (
        color: const Color(0xFF2E7D32),
        icon: Icons.check_circle_rounded,
      );
    case 'Prémio da Rifa':
    case 'Prémio da Rifa · Envio a pagar':
      return (
        color: const Color(0xFFC9A227),
        icon: Icons.emoji_events_rounded,
      );
    case 'Artigo Enviado':
      return (
        color: const Color(0xFF3949AB),
        icon: Icons.local_shipping_rounded,
      );
    case 'Concluída':
      return (
        color: const Color(0xFF007782),
        icon: Icons.check_circle_outline_rounded,
      );
    case 'Pedido de Devolução':
    case 'Problema com a devolução':
      return (
        color: const Color(0xFFB45309),
        icon: Icons.report_problem_rounded,
      );
    case 'Em Devolução':
    case 'Devolução entregue':
      return (
        color: const Color(0xFF7B1FA2),
        icon: Icons.assignment_return_rounded,
      );
    case 'Devolvida / Reembolsada':
      return (
        color: const Color(0xFF007782),
        icon: Icons.keyboard_return_rounded,
      );
    default:
      return (
        color: const Color(0xFF57636C),
        icon: Icons.receipt_long_rounded,
      );
  }
}

({Color color, IconData icon}) bundleSubRowStatusVisual(
  OrdersRow order,
  List<OrdersRow> groupOrders,
) {
  return bundleGroupAggregatedStatusVisual([order]);
}
