/// ZIP 142 — política de taxa Stripe no PI de diferença de portes.
///
/// Tarifas publicadas Stripe PT (lista, sujeitas a alteração):
/// - Cartão EEE padrão: 1,5% + 0,25 €
/// - Cartão EEE premium: 2,8% + 0,25 €
/// - MB WAY: 1,5% + 0,25 € (+ extras internacionais)
///
/// PSD2 / Your Europe: **proibido** surcharge ao consumidor por cartão
/// consumer IFR. Por isso o default [kFleaberShippingDeltaPassStripeFeeDefault]
/// é **false** — o comprador paga só a diferença de portes DPD;
/// a taxa Stripe é absorvida (vendedor/plataforma), sem Proteção Fleaber.
library;

/// Default de produto até GO legal explícito.
const bool kFleaberShippingDeltaPassStripeFeeDefault = false;

/// Lista Stripe PT — cartão EEE padrão / MB WAY doméstico (referência).
const int kFleaberStripePtStandardFeeFixedCents = 25;
const int kFleaberStripePtStandardFeeBps = 150; // 1,5%

/// Resultado do cálculo do montante a cobrar no PI delta.
class FleaberShippingDeltaChargeQuote {
  const FleaberShippingDeltaChargeQuote({
    required this.shippingDeltaCents,
    required this.stripeFeeGrossupCents,
    required this.amountChargeCents,
    required this.passStripeFeeToBuyer,
    required this.feePolicy,
  });

  final int shippingDeltaCents;
  final int stripeFeeGrossupCents;
  final int amountChargeCents;
  final bool passStripeFeeToBuyer;
  final String feePolicy;
}

/// Calcula o charge do PI delta.
///
/// Se [passStripeFeeToBuyer] for false (default conforme): charge = delta.
/// Se true (só com GO legal): gross-up com fixed+bps configuráveis.
FleaberShippingDeltaChargeQuote fleaberShippingDeltaChargeQuote({
  required int shippingDeltaCents,
  bool passStripeFeeToBuyer = kFleaberShippingDeltaPassStripeFeeDefault,
  int feeFixedCents = kFleaberStripePtStandardFeeFixedCents,
  int feeBps = kFleaberStripePtStandardFeeBps,
}) {
  final delta = shippingDeltaCents < 0 ? 0 : shippingDeltaCents;
  if (!passStripeFeeToBuyer) {
    return FleaberShippingDeltaChargeQuote(
      shippingDeltaCents: delta,
      stripeFeeGrossupCents: 0,
      amountChargeCents: delta,
      passStripeFeeToBuyer: false,
      feePolicy: 'absorb_stripe_fee_psd2_safe',
    );
  }
  // charge = ceil((delta + fixed) / (1 - pct))
  final numer = (delta + feeFixedCents) * 10000;
  final denom = 10000 - feeBps;
  final charge = denom <= 0 ? delta : ((numer + denom - 1) ~/ denom);
  final grossup = charge - delta;
  return FleaberShippingDeltaChargeQuote(
    shippingDeltaCents: delta,
    stripeFeeGrossupCents: grossup < 0 ? 0 : grossup,
    amountChargeCents: charge,
    passStripeFeeToBuyer: true,
    feePolicy: 'grossup_list_rate_go_required',
  );
}
