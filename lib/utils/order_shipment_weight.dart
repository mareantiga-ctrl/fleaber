/// Agregação de peso / escalão para portes DPD (ZIP 140).
/// Não assume silenciosamente 0–3 kg quando falta peso.
library;

import '/backend/supabase/database/tables/products.dart';
import '/utils/dpd_shipping_rates.dart';

class FleaberShipmentWeightInput {
  const FleaberShipmentWeightInput({
    this.weightKg,
    this.band,
    this.quantity = 1,
  });

  final double? weightKg;
  final FleaberDpdWeightBand? band;
  final int quantity;

  factory FleaberShipmentWeightInput.fromProduct(
    ProductsRow product, {
    int quantity = 1,
  }) {
    final qty = quantity < 1 ? 1 : quantity;
    final kg = product.shippingWeightKg;
    final band = FleaberDpdWeightBand.fromCode(product.shippingWeightBand);
    return FleaberShipmentWeightInput(
      weightKg: kg,
      band: band,
      quantity: qty,
    );
  }
}

class FleaberShipmentWeightAggregate {
  const FleaberShipmentWeightAggregate({
    required this.ok,
    this.totalKg,
    this.band,
    this.error,
    this.message,
    this.needsBuyerBandChoice = false,
  });

  final bool ok;
  final double? totalKg;
  final FleaberDpdWeightBand? band;
  final String? error;
  final String? message;
  final bool needsBuyerBandChoice;
}

/// Consolida vários artigos num único envio.
/// - Se todos têm kg → soma (× qty); escalão = fromKg(total).
/// - Se misturam band-only → usa o escalão **máximo** (mais caro / mais pesado).
/// - Se algum artigo não tem kg nem band → bloqueia (peso é do vendedor; o
///   comprador **não** escolhe escalão).
FleaberShipmentWeightAggregate fleaberAggregateShipmentWeight(
  List<FleaberShipmentWeightInput> lines,
) {
  if (lines.isEmpty) {
    return const FleaberShipmentWeightAggregate(
      ok: false,
      error: 'empty',
      message: 'Sem artigos para calcular o peso do envio.',
      needsBuyerBandChoice: true,
    );
  }

  var anyMissing = false;
  var allHaveKg = true;
  var sumKg = 0.0;
  FleaberDpdWeightBand? maxBand;

  for (final line in lines) {
    final qty = line.quantity < 1 ? 1 : line.quantity;
    final kg = line.weightKg;
    final band = line.band;
    if (kg != null && kg > 0) {
      sumKg += kg * qty;
      final b = FleaberDpdWeightBand.fromKg(kg * qty) ??
          FleaberDpdWeightBand.fromKg(kg);
      if (b != null) {
        maxBand = _heavierBand(maxBand, b);
      }
    } else if (band != null) {
      allHaveKg = false;
      maxBand = _heavierBand(maxBand, band);
      // band-only: usa maxKg do escalão × qty (conservador)
      sumKg += band.maxKg * qty;
    } else {
      anyMissing = true;
      allHaveKg = false;
    }
  }

  if (anyMissing) {
    return const FleaberShipmentWeightAggregate(
      ok: false,
      error: 'weight_required',
      message:
          'Este envio ainda não tem peso definido pelo vendedor. '
          'Sem peso não calculamos portes — pede ao vendedor para indicar '
          'o peso (ou escalão) no anúncio.',
      needsBuyerBandChoice: true,
    );
  }

  if (sumKg > kFleaberDpdMaxKg) {
    return const FleaberShipmentWeightAggregate(
      ok: false,
      error: 'over_10kg',
      message:
          'Envio DPD indisponível acima de 10 kg por expedição (incluindo embalagem).',
    );
  }

  final resolved = allHaveKg
      ? FleaberDpdWeightBand.fromKg(sumKg)
      : (maxBand ?? FleaberDpdWeightBand.fromKg(sumKg));

  if (resolved == null) {
    return const FleaberShipmentWeightAggregate(
      ok: false,
      error: 'over_10kg',
      message:
          'Envio DPD indisponível acima de 10 kg por expedição (incluindo embalagem).',
    );
  }

  return FleaberShipmentWeightAggregate(
    ok: true,
    totalKg: sumKg,
    band: resolved,
  );
}

FleaberDpdWeightBand _heavierBand(
  FleaberDpdWeightBand? a,
  FleaberDpdWeightBand b,
) {
  if (a == null) return b;
  return a.maxKg >= b.maxKg ? a : b;
}

const String kFleaberCheckoutShippingDeltaNotice =
    'Os portes usam o peso indicado pelo vendedor. Se o peso real for superior, '
    'o vendedor pode assumir a diferença ou pedir-te o pagamento extra '
    '(48 horas). O prazo de envio fica pausado até resolveres.';

/// Mensagem curta quando falta peso/escalão do vendedor (checkout comprador).
const String kFleaberBuyerWeightMissingMessage =
    'Este anúncio ainda não tem peso nem escalão de envio. '
    'O vendedor tem de os indicar no anúncio — no checkout não podes escolher.';

/// Campos a gravar na encomenda (selo de portes cobrados) — reconciliação ZIP 140.
Map<String, dynamic> fleaberOrderShippingSealFields({
  required bool handDelivery,
  double? weightKg,
  FleaberDpdWeightBand? band,
  required bool pickup,
  double? shippingEurCharged,
}) {
  if (handDelivery) {
    return {
      'shipping_modality': 'hand',
      'shipping_cents_charged': 0,
      'shipping_weight_kg': null,
      'shipping_weight_band': null,
      'shipping_weight_charged_kg': null,
      'shipping_weight_charged_band': null,
    };
  }
  final resolved = band ??
      (weightKg != null && weightKg > 0
          ? FleaberDpdWeightBand.fromKg(weightKg)
          : null);
  final modality =
      pickup ? FleaberDpdModality.shopToShop : FleaberDpdModality.shopToHome;
  final cents = shippingEurCharged == null
      ? null
      : (shippingEurCharged * 100).round();
  return {
    'shipping_modality': modality == FleaberDpdModality.shopToShop
        ? 'shop_to_shop'
        : 'shop_to_home',
    'dpd_service': modality == FleaberDpdModality.shopToShop
        ? 'shop_to_shop'
        : 'shop_to_home',
    if (weightKg != null && weightKg > 0) 'shipping_weight_kg': weightKg,
    if (resolved != null) 'shipping_weight_band': resolved.code,
    if (weightKg != null && weightKg > 0)
      'shipping_weight_charged_kg': weightKg,
    if (resolved != null) 'shipping_weight_charged_band': resolved.code,
    if (cents != null) 'shipping_cents_charged': cents,
  };
}
