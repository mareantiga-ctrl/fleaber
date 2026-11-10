/// Tarifas DPD ao comprador (proposta Célia) + helpers de peso.
/// Cobrança real gated por [kFleaberDpdShippingRatesLive] / flag BD
/// `dpd_shipping_rates_live`.
library;

/// Legado 3,50 € (só quando ratesLive=false). Evita import circular com fee_calculator.
const double _kLegacyCarrierEur = 3.5;

/// Tarifas Célia activas no cliente (ZIP 136). Create comercial continua OFF.
const bool kFleaberDpdShippingRatesLive = true;

/// Shop→Home activo — prémio Home (combustível+porta) embutido na tabela Célia.
const bool kFleaberDpdHomeChargesEnabled = true;

const double kFleaberDpdMaxKg = 10;

enum FleaberDpdModality { shopToShop, shopToHome }

enum FleaberDpdWeightBand {
  upTo3('0_3', 3),
  from3To6('3_6', 6),
  from6To10('6_10', 10);

  const FleaberDpdWeightBand(this.code, this.maxKg);
  final String code;
  final double maxKg;

  static FleaberDpdWeightBand? fromCode(String? raw) {
    final c = (raw ?? '').trim();
    for (final b in FleaberDpdWeightBand.values) {
      if (b.code == c) return b;
    }
    return null;
  }

  static FleaberDpdWeightBand? fromKg(double kg) {
    if (kg <= 0) return null;
    if (kg <= 3) return upTo3;
    if (kg <= 6) return from3To6;
    if (kg <= 10) return from6To10;
    return null;
  }

  String get labelPt {
    switch (this) {
      case upTo3:
        return 'Até 3 kg';
      case from3To6:
        return '3–6 kg';
      case from6To10:
        return '6–10 kg';
    }
  }
}

/// Tabela Célia (IVA incl.) — espelho da BD `dpd_shipping_rates`.
double fleaberDpdTablePriceEur({
  required FleaberDpdModality modality,
  required FleaberDpdWeightBand band,
}) {
  switch (modality) {
    case FleaberDpdModality.shopToShop:
      switch (band) {
        case FleaberDpdWeightBand.upTo3:
          return 2.99;
        case FleaberDpdWeightBand.from3To6:
          return 3.49;
        case FleaberDpdWeightBand.from6To10:
          return 4.99;
      }
    case FleaberDpdModality.shopToHome:
      switch (band) {
        case FleaberDpdWeightBand.upTo3:
          return 4.49;
        case FleaberDpdWeightBand.from3To6:
          return 5.99;
        case FleaberDpdWeightBand.from6To10:
          return 8.99;
      }
  }
}

/// Peso efectivo: kg exacto, senão teto do escalão.
double? fleaberDpdEffectiveWeightKg({
  double? weightKg,
  FleaberDpdWeightBand? band,
}) {
  if (weightKg != null && weightKg > 0) {
    return weightKg > kFleaberDpdMaxKg ? weightKg : weightKg;
  }
  return band?.maxKg;
}

/// Portes a cobrar ao comprador. Respeita flags e envio grátis.
///
/// Enquanto [kFleaberDpdShippingRatesLive] for false → legado 3,50 € (carrier).
class FleaberDpdShippingQuote {
  const FleaberDpdShippingQuote({
    required this.ok,
    required this.priceEur,
    this.error,
    this.message,
    this.legacy = false,
    this.weightKg,
    this.band,
    this.modality,
  });

  final bool ok;
  final double priceEur;
  final String? error;
  final String? message;
  final bool legacy;
  final double? weightKg;
  final FleaberDpdWeightBand? band;
  final FleaberDpdModality? modality;
}

FleaberDpdShippingQuote fleaberQuoteDpdShipping({
  required FleaberDpdModality modality,
  double? weightKg,
  FleaberDpdWeightBand? band,
  bool freeBySeller = false,
  bool ratesLive = kFleaberDpdShippingRatesLive,
  bool homeChargesEnabled = kFleaberDpdHomeChargesEnabled,
}) {
  if (freeBySeller) {
    return FleaberDpdShippingQuote(
      ok: true,
      priceEur: 0,
      modality: modality,
      weightKg: fleaberDpdEffectiveWeightKg(weightKg: weightKg, band: band),
      band: band,
    );
  }

  final kg = fleaberDpdEffectiveWeightKg(weightKg: weightKg, band: band);
  if (kg == null) {
    return const FleaberDpdShippingQuote(
      ok: false,
      priceEur: 0,
      error: 'weight_required',
      message: 'Indica o peso aproximado ou um escalão (máx. 10 kg).',
    );
  }
  if (kg > kFleaberDpdMaxKg) {
    return const FleaberDpdShippingQuote(
      ok: false,
      priceEur: 0,
      error: 'over_10kg',
      message:
          'Envio DPD indisponível acima de 10 kg por expedição (incluindo embalagem).',
    );
  }
  final resolvedBand = FleaberDpdWeightBand.fromKg(kg);
  if (resolvedBand == null) {
    return const FleaberDpdShippingQuote(
      ok: false,
      priceEur: 0,
      error: 'over_10kg',
      message:
          'Envio DPD indisponível acima de 10 kg por expedição (incluindo embalagem).',
    );
  }

  if (!ratesLive) {
    return FleaberDpdShippingQuote(
      ok: true,
      priceEur: _kLegacyCarrierEur,
      legacy: true,
      weightKg: kg,
      band: resolvedBand,
      modality: modality,
    );
  }

  if (modality == FleaberDpdModality.shopToHome && !homeChargesEnabled) {
    return const FleaberDpdShippingQuote(
      ok: false,
      priceEur: 0,
      error: 'home_charges_disabled',
      message:
          'Entrega ao domicílio DPD ainda não está activa (validação combustível).',
    );
  }

  final price = fleaberDpdTablePriceEur(modality: modality, band: resolvedBand);
  return FleaberDpdShippingQuote(
    ok: true,
    priceEur: price,
    weightKg: kg,
    band: resolvedBand,
    modality: modality,
  );
}

/// Portes de checkout DPD: Pickup → Shop2Shop, morada → Shop2Home.
/// Sem [weightKg] nem [band] → erro `weight_required` (não inventar 0–3 kg).
FleaberDpdShippingQuote fleaberCheckoutDpdQuote({
  required bool pickup,
  double? weightKg,
  FleaberDpdWeightBand? band,
  bool freeBySeller = false,
}) {
  return fleaberQuoteDpdShipping(
    modality: pickup
        ? FleaberDpdModality.shopToShop
        : FleaberDpdModality.shopToHome,
    weightKg: weightKg,
    band: band,
    freeBySeller: freeBySeller,
  );
}

/// Euros a cobrar no checkout (0 se envio mão / grátis / erro → throw).
double fleaberCheckoutDpdShippingEur({
  required bool pickup,
  double? weightKg,
  FleaberDpdWeightBand? band,
  bool freeBySeller = false,
}) {
  final q = fleaberCheckoutDpdQuote(
    pickup: pickup,
    weightKg: weightKg,
    band: band,
    freeBySeller: freeBySeller,
  );
  if (!q.ok) {
    throw FormatException(q.message ?? q.error ?? 'Portes DPD indisponíveis.');
  }
  return q.priceEur;
}

/// Aviso obrigatório no anúncio / termos (diferença de peso = vendedor).
const String kFleaberDpdWeightSellerResponsibilityNotice =
    'O vendedor é responsável por diferenças entre o peso declarado e o peso '
    'real. Custos DPD por excesso (incluindo 3,00 € + IVA por kg adicional '
    'quando aplicável) correm por conta do vendedor. Acima de 10 kg por '
    'expedição o envio DPD não está disponível neste lançamento.';
