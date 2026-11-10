import '/backend/supabase/supabase.dart';
import '/batata_bundle_actions.dart';
import '/order_cancel_eligibility.dart';
import '/utils/fee_calculator.dart';

/// Papel na superfície de preço (estilo Vinted).
enum BundlePriceAudience { seller, buyer }

/// Vista unificada: legenda + valor principal + subtítulo opcional.
class BundlePriceView {
  const BundlePriceView({
    required this.primaryCaption,
    required this.primaryAmount,
    this.subtitle,
  });

  final String primaryCaption;
  final String primaryAmount;
  final String? subtitle;
}

/// Helper central — preços de conjunto coerentes entre chat, encomendas e cards.
class BundlePriceDisplay {
  BundlePriceDisplay._();

  static double itemsTotalFromBundleMeta(Map<String, dynamic>? meta) {
    return (meta?['total_eur'] as num?)?.toDouble() ?? 0.0;
  }

  static double receivableFromOrders(List<OrdersRow> orders) {
    var sum = 0.0;
    for (final o in orders) {
      if (orderIsCancelled(o.status)) continue;
      sum += o.priceTotal ?? 0;
    }
    return sum;
  }

  static bool isPrePaymentPhase(
    List<OrdersRow> orders, {
    String? bundleStatus,
  }) {
    if (bundleStatus == 'pending' || bundleStatus == 'accepted') {
      return true;
    }
    for (final o in orders) {
      final s = normalizeOrderStatusKey(o.status);
      if (s == 'reservado' ||
          s == 'reserva_pendente' ||
          s == 'aguarda_confirmacao') {
        return true;
      }
    }
    return false;
  }

  /// Header chat / resumo expandível do conjunto.
  static BundlePriceView forChatHeader({
    required BundlePriceAudience audience,
    required List<OrdersRow> orders,
    Map<String, dynamic>? bundleMeta,
    String? bundleStatus,
  }) {
    final negotiated = _negotiatedItemsTotal(orders, bundleMeta);
    final prePay = isPrePaymentPhase(orders, bundleStatus: bundleStatus);
    final receivable = receivableFromOrders(orders);

    if (audience == BundlePriceAudience.seller) {
      final amount = prePay
          ? negotiated
          : (receivable > 0 ? receivable : negotiated);
      return BundlePriceView(
        primaryCaption: 'A receber',
        primaryAmount: formatEuros(amount),
      );
    }

    if (!prePay && receivable > 0) {
      return BundlePriceView(
        primaryCaption: 'Total pago',
        primaryAmount: formatEuros(receivable),
      );
    }

    return BundlePriceView(
      primaryCaption: 'Total negociado',
      primaryAmount: formatEuros(negotiated),
      subtitle: _buyerPrePaymentSubtitle(orders, negotiated),
    );
  }

  /// Card agrupado em Minhas encomendas.
  static BundlePriceView forOrdersListBundle({
    required bool isSellerTab,
    required List<OrdersRow> orders,
  }) {
    final receivable = receivableFromOrders(orders);
    if (isSellerTab) {
      return BundlePriceView(
        primaryCaption: 'A receber',
        primaryAmount: formatEuros(receivable),
      );
    }

    if (bundleOrdersDirectPaymentPending(orders)) {
      final shipping = bundleShippingEurFromMethod(orders.first.shippingMethod);
      return BundlePriceView(
        primaryCaption: 'A transferir',
        primaryAmount: formatEuros(receivable + shipping),
        subtitle: 'pagamento directo (sem protecção Fleaber)',
      );
    }

    final prePay = isPrePaymentPhase(orders);
    if (prePay) {
      return BundlePriceView(
        primaryCaption: 'Total negociado',
        primaryAmount: formatEuros(receivable),
        subtitle: _buyerPrePaymentSubtitle(orders, receivable),
      );
    }

    return BundlePriceView(
      primaryCaption: 'Total pago',
      primaryAmount: formatEuros(receivable),
      subtitle: 'artigos do conjunto',
    );
  }

  /// Card de proposta no chat (valor negociado, sem taxas).
  static BundlePriceView forProposalCard({
    required double totalEur,
    required double discountEur,
  }) {
    if (discountEur > 0.009) {
      return BundlePriceView(
        primaryCaption: 'Total negociado',
        primaryAmount: formatEuros(totalEur),
        subtitle: 'desconto de conjunto: − ${formatEuros(discountEur)}',
      );
    }
    return BundlePriceView(
      primaryCaption: 'Total negociado',
      primaryAmount: formatEuros(totalEur),
    );
  }

  static double _negotiatedItemsTotal(
    List<OrdersRow> orders,
    Map<String, dynamic>? bundleMeta,
  ) {
    final fromMeta = itemsTotalFromBundleMeta(bundleMeta);
    if (fromMeta > 0) return fromMeta;
    if (orders.isEmpty) return 0.0;
    return orders.fold<double>(0, (s, o) => s + (o.priceTotal ?? 0));
  }

  static String? _buyerPrePaymentSubtitle(
    List<OrdersRow> orders,
    double itemsTotal,
  ) {
    if (itemsTotal <= 0) return null;
    if (bundleOrdersDirectPaymentPending(orders)) {
      final shipping = bundleShippingEurFromMethod(orders.first.shippingMethod);
      return 'com envio: ${formatEuros(itemsTotal + shipping)} (pagamento directo)';
    }
    if (bundleOrdersAwaitingCheckoutChoice(orders)) {
      return 'com envio e protecção: '
          '${formatEuros(bundleCheckoutGrandTotalEur(itemsTotal))} '
          '(estimativa Seguro Fleaber)';
    }
    return 'com envio e protecção: '
        '${formatEuros(bundleCheckoutGrandTotalEur(itemsTotal))}';
  }
}
