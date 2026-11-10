import 'package:intl/intl.dart';

import '/utils/dpd_shipping_rates.dart';

const double fleaberProtectionFixedFeeEur = 0.65;
const double fleaberProtectionPercentage = 0.05;

/// Legado / encomendas antigas seladas a 3,50 € (não usar em checkout DPD novo).
const double kFleaberCarrierShippingEur = 3.5;

/// Método canónico enviado ao Edge / BD (allowlist estável em produção).
/// UI mostra [kFleaberShippingCarrierLabel] (DPD) — nunca CTT como opção activa.
const String kFleaberShippingCarrierMethod = 'carrier';
const String kFleaberShippingCarrierLabel = 'Envio DPD';
const String kFleaberShippingHandLabel = 'Entrega em mão (0,00 €)';
const String kFleaberShippingHandMethod = 'hand';

double _roundEuroCents(double value) => (value * 100).roundToDouble() / 100;

/// Portes em **euros** a partir do método de envio.
///
/// Allowlist exacta (case-insensitive trim). Desconhecido → [FormatException]
/// (fail-closed; o Edge também rejeita garbage).
/// Com [kFleaberDpdShippingRatesLive], `carrier`/`dpd` usam tabela Célia
/// (default Shop2Shop 0–3 kg). Checkouts com Pickup/Home devem preferir
/// [fleaberCheckoutDpdShippingEur].
double fleaberShippingEurFromMethod(String? shippingMethod) {
  final m = (shippingMethod ?? '').trim().toLowerCase();
  if (m.isEmpty) {
    throw FormatException('Portes inválidos: método vazio.');
  }
  const hand = {
    'hand',
    'mao',
    'mão',
    'pickup',
    'entrega_mao',
    'entrega_mão',
    'entrega em mao',
    'entrega em mão',
    'levantamento',
    'entrega em mão (€0.00)',
    'entrega em mao (€0.00)',
    'entrega em mão (0,00 €)',
    'entrega em mao (0,00 €)',
  };
  const carrier = {
    'carrier',
    'transportadora',
    'dpd',
    'envio dpd',
    'envio dpd (3,50 €)',
    'envio dpd (€3.50)',
    'envio dpd (€3,50)',
    // Legado (encomendas antigas) — não usar em UI nova
    'ctt',
    'correios',
    'envio transportadora (€3.50)',
    'envio transportadora (€3,50)',
    'envio transportadora (3,50 €)',
  };
  // Normalize UI constants (already lowercased above).
  if (hand.contains(m)) return 0.0;
  if (carrier.contains(m)) {
    if (!kFleaberDpdShippingRatesLive) {
      return kFleaberCarrierShippingEur;
    }
    // Tarifas live: exige peso/escalão via fleaberCheckoutDpdShippingEur.
    throw FormatException(
      'Portes DPD: indica peso ou escalão (não usar carrier sem quote).',
    );
  }
  throw FormatException('Portes inválidos: "$shippingMethod".');
}

/// Versão tolerante para displays legados: mão/€0 → 0; resto conhecido → 3,50;
/// lixo → 3,50 só se parecer transportadora, senão 0. Preferir [fleaberShippingEurFromMethod]
/// em checkout novo.
double fleaberShippingEurFromMethodLenient(String? shippingMethod) {
  try {
    return fleaberShippingEurFromMethod(shippingMethod);
  } on FormatException {
    final sm = (shippingMethod ?? '').toLowerCase();
    if (sm.contains('mão') ||
        sm.contains('mao') ||
        sm.contains('0.00') ||
        sm.contains('0,00') ||
        sm.contains('pickup') ||
        sm.contains('levantamento')) {
      return 0.0;
    }
    if (sm.contains('transportadora') ||
        sm.contains('ctt') ||
        sm.contains('carrier') ||
        sm.contains('3.50') ||
        sm.contains('3,50')) {
      return kFleaberCarrierShippingEur;
    }
    // Legado ambíguo: não inventar portes.
    return 0.0;
  }
}

double calculateFleaberProtectionFee(
  double itemPriceEur, {
  double shippingEur = 0,
}) {
  final protectedAmount = itemPriceEur + shippingEur;
  if (protectedAmount <= 0 || protectedAmount.isNaN) return 0;
  return _roundEuroCents(
    fleaberProtectionFixedFeeEur +
        (protectedAmount * fleaberProtectionPercentage),
  );
}

double calculateFleaberBuyerTotal({
  required double itemPriceEur,
  double shippingEur = 0,
  bool includeProtectionFee = true,
}) {
  final fee = includeProtectionFee
      ? calculateFleaberProtectionFee(
          itemPriceEur,
          shippingEur: shippingEur,
        )
      : 0.0;
  return _roundEuroCents(itemPriceEur + shippingEur + fee);
}

/// Ganhos do vendedor para uma encomenda live.
///
/// **Directo:** artigos + portes (sem protecção comprador).
/// **Pagamento na app:** artigos + portes — nunca inclui a taxa Seguro Fleaber.
double liveSellerEarningsEur({
  required double storedPriceTotal,
  required bool isDirectPayment,
  double lineItemEur = 0,
  double shippingEur = 0,
}) {
  if (isDirectPayment) {
    if (storedPriceTotal > 0.009) {
      return _roundEuroCents(storedPriceTotal);
    }
    if (lineItemEur <= 0 || lineItemEur.isNaN) return 0;
    return _roundEuroCents(lineItemEur + shippingEur);
  }
  if (lineItemEur > 0 && !lineItemEur.isNaN) {
    return _roundEuroCents(lineItemEur + shippingEur);
  }
  if (storedPriceTotal > 0.009) {
    return _roundEuroCents(storedPriceTotal);
  }
  return 0;
}

/// Total comprador saco live Stripe — alinhado ao sheet `checkoutTotalsBreakdown`.
double liveBagBuyerTotalEur({
  required double itemsSubtotalEur,
  required double shippingEur,
}) {
  return calculateFleaberBuyerTotal(
    itemPriceEur: itemsSubtotalEur,
    shippingEur: shippingEur,
    includeProtectionFee: true,
  );
}

/// Reparte [buyerTotalEur] por linhas (soma exacta ao cêntimo).
List<double> allocateLiveBagBuyerTotals({
  required List<double> lineItemsEur,
  required double buyerTotalEur,
}) {
  if (lineItemsEur.isEmpty) return const [];
  if (lineItemsEur.length == 1) {
    return [_roundEuroCents(buyerTotalEur)];
  }
  final subtotal = lineItemsEur.fold<double>(0, (a, b) => a + b);
  if (subtotal <= 0) {
    final each = _roundEuroCents(buyerTotalEur / lineItemsEur.length);
    return List<double>.filled(lineItemsEur.length, each);
  }
  final out = <double>[];
  var allocated = 0.0;
  for (var i = 0; i < lineItemsEur.length; i++) {
    if (i == lineItemsEur.length - 1) {
      out.add(_roundEuroCents(buyerTotalEur - allocated));
    } else {
      final share =
          _roundEuroCents(buyerTotalEur * (lineItemsEur[i] / subtotal));
      out.add(share);
      allocated += share;
    }
  }
  return out;
}

/// Fallback só com o catálogo (reserva convertida, ainda sem total de encomenda).
/// Artigos apenas — não inventa portes nem protecção.
double liveSellerEarningsEstimateFromCatalog(double lineItemEur) {
  if (lineItemEur <= 0 || lineItemEur.isNaN) return 0;
  return _roundEuroCents(lineItemEur);
}

String formatFleaberProtectionFee(
  double itemPriceEur, {
  double shippingEur = 0,
}) {
  return formatEuros(
    calculateFleaberProtectionFee(
      itemPriceEur,
      shippingEur: shippingEur,
    ),
  );
}

String formatFleaberBuyerTotal({
  required double itemPriceEur,
  double shippingEur = 0,
  bool includeProtectionFee = true,
}) {
  return formatEuros(
    calculateFleaberBuyerTotal(
      itemPriceEur: itemPriceEur,
      shippingEur: shippingEur,
      includeProtectionFee: includeProtectionFee,
    ),
  );
}

String formatEuros(double value) {
  final safeValue = value.isNaN ? 0.0 : value;
  return NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(safeValue);
}
