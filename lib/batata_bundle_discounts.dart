import '/backend/supabase/supabase.dart';

/// Uma regra: a partir de [minItems] artigos, aplica [pct]% de desconto.
class BundleDiscountRule {
  const BundleDiscountRule({required this.minItems, required this.pct});

  final int minItems;
  final double pct;

  Map<String, dynamic> toJson() => {
        'min_items': minItems,
        'pct': pct,
      };

  static BundleDiscountRule? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final min = raw['min_items'];
    final pct = raw['pct'];
    final minItems = min is int ? min : int.tryParse('$min');
    final pctVal = pct is num
        ? pct.toDouble()
        : double.tryParse('$pct');
    if (minItems == null || minItems < 2 || pctVal == null) return null;
    if (pctVal < 0 || pctVal > 50) return null;
    return BundleDiscountRule(minItems: minItems, pct: pctVal);
  }
}

/// Percentagem de desconto para N artigos (escalões + regras personalizadas).
class BundleDiscountTiers {
  const BundleDiscountTiers({
    this.enabled = false,
    this.tier2Pct,
    this.tier3Pct,
    this.tier5Pct,
    this.customRules = const [],
  });

  final bool enabled;
  final double? tier2Pct;
  final double? tier3Pct;
  final double? tier5Pct;
  final List<BundleDiscountRule> customRules;

  List<BundleDiscountRule> get allRules {
    final rules = <BundleDiscountRule>[];
    void addPreset(int min, double? pct) {
      if (pct != null && pct > 0) {
        rules.add(BundleDiscountRule(minItems: min, pct: pct));
      }
    }

    addPreset(2, tier2Pct);
    addPreset(3, tier3Pct);
    addPreset(5, tier5Pct);
    rules.addAll(customRules);
    return rules;
  }

  double? percentForCount(int count) {
    if (!enabled || count < 2) return null;
    final rules = allRules;
    if (rules.isEmpty) return null;
    rules.sort((a, b) => b.minItems.compareTo(a.minItems));
    for (final r in rules) {
      if (count >= r.minItems) return r.pct;
    }
    return null;
  }
}

List<BundleDiscountRule> _parseCustomTiers(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .map(BundleDiscountRule.fromJson)
      .whereType<BundleDiscountRule>()
      .toList();
}

Future<BundleDiscountTiers> fetchSellerBundleDiscounts(String sellerId) async {
  if (sellerId.isEmpty) {
    return const BundleDiscountTiers();
  }
  try {
    final rows = await SupaFlow.client
        .from('seller_bundle_discounts')
        .select()
        .eq('seller_id', sellerId)
        .limit(1);
    if (rows.isEmpty) {
      return const BundleDiscountTiers();
    }
    final m = Map<String, dynamic>.from(rows.first as Map);
    double? pct(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return BundleDiscountTiers(
      enabled: m['enabled'] == true,
      tier2Pct: pct(m['tier_2_pct']),
      tier3Pct: pct(m['tier_3_pct']),
      tier5Pct: pct(m['tier_5_pct']),
      customRules: _parseCustomTiers(m['custom_tiers']),
    );
  } catch (_) {
    return const BundleDiscountTiers();
  }
}

Future<void> saveSellerBundleDiscounts({
  required String sellerId,
  required bool enabled,
  double? tier2Pct,
  double? tier3Pct,
  double? tier5Pct,
  List<BundleDiscountRule> customRules = const [],
}) async {
  final payload = <String, dynamic>{
    'seller_id': sellerId,
    'enabled': enabled,
    'tier_2_pct': tier2Pct,
    'tier_3_pct': tier3Pct,
    'tier_5_pct': tier5Pct,
    'custom_tiers': customRules.map((r) => r.toJson()).toList(),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
  await SupaFlow.client.from('seller_bundle_discounts').upsert(payload);
}

double bundleSubtotal(List<ProductsRow> products) {
  var sum = 0.0;
  for (final p in products) {
    sum += p.price ?? 0;
  }
  return sum;
}

({double subtotal, double discountPct, double discountEur, double total})
    calculateBundleTotals({
  required List<ProductsRow> products,
  required BundleDiscountTiers tiers,
}) {
  final subtotal = bundleSubtotal(products);
  final pct = tiers.percentForCount(products.length) ?? 0;
  final discountEur = (subtotal * pct / 100);
  final total = (subtotal - discountEur).clamp(0.0, double.infinity).toDouble();
  return (
    subtotal: subtotal,
    discountPct: pct,
    discountEur: discountEur,
    total: total,
  );
}

int? maxDiscountPercent(BundleDiscountTiers tiers) {
  if (!tiers.enabled) return null;
  final vals = tiers.allRules.map((r) => r.pct).toList();
  if (vals.isEmpty) return null;
  vals.sort();
  return vals.last.round();
}
