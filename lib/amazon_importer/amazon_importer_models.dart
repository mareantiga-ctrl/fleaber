/// Modelos e helpers do Importador Amazon (fase 1).

const kAmazonManifestRequiredColumns = <String>[
  'ASIN',
  'LPN',
  'CONDITION',
  'EAN',
  'UPC',
  'QTY',
  'COST',
  'Item Desc',
  'CURRENCY CODE',
];

const kAmazonManifestOptionalColumns = <String>[
  'FNSku',
  'FCSku',
  'CATEGORY',
  'SUBCATEGORY',
  'ItemPkgWeight',
  'ItemPkgWeightUOM',
  'TOTAL RETAIL',
  'UNIT RETAIL',
  'DEPARTMENT',
];

/// Ordem de prioridade Amazon (não usar o menor preço entre países).
const kAmazonMarketPriority = <String>['es', 'it', 'de', 'fr'];

/// Preço de manifesto ≠ custo real de aquisição do lote.
double? parseManifestMoney(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim().replaceAll(' ', '').replaceAll(',', '.');
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

bool isOfferAvailabilitySellable(String? availability) {
  final a = (availability ?? '').trim().toLowerCase();
  if (a.isEmpty) return true; // desconhecido → não bloquear só por isso
  if (a.contains('unavailable') ||
      a.contains('no disponible') ||
      a.contains('non disponibile') ||
      a.contains('nicht verfügbar') ||
      a.contains('indisponible') ||
      a.contains('currently unavailable') ||
      a == 'none') {
    return false;
  }
  return true;
}

/// Oferta Amazon válida para referência: status ok, EUR numérico, disponível.
bool isValidAmazonReferenceOffer(AmazonOfferView o) {
  if (o.status != 'ok') return false;
  if (o.priceAmount == null || o.priceAmount! <= 0) return false;
  if ((o.currency ?? 'EUR').toUpperCase() != 'EUR') return false;
  if (o.marketplace.toLowerCase() == 'manual') return false;
  if (!kAmazonMarketPriority.contains(o.marketplace.toLowerCase())) {
    return false;
  }
  if (!isOfferAvailabilitySellable(o.availability)) return false;
  return true;
}

/// Primeiro preço válido na ordem ES → IT → DE → FR (nunca o mínimo).
AmazonOfferView? pickAmazonReferenceOffer(List<AmazonOfferView> offers) {
  final byMarket = <String, AmazonOfferView>{};
  for (final o in offers) {
    if (!isValidAmazonReferenceOffer(o)) continue;
    final m = o.marketplace.toLowerCase();
    final prev = byMarket[m];
    if (prev == null) {
      byMarket[m] = o;
      continue;
    }
    // Preferir a consulta mais recente no mesmo mercado.
    final a = o.fetchedAt;
    final b = prev.fetchedAt;
    if (a != null && (b == null || a.isAfter(b))) {
      byMarket[m] = o;
    }
  }
  for (final m in kAmazonMarketPriority) {
    final hit = byMarket[m];
    if (hit != null) return hit;
  }
  return null;
}

/// Preço sugerido = desconto % sobre a referência válida (Amazon prioritária).
double? suggestedSaleFromOffers({
  required List<AmazonOfferView> offers,
  required double discountPct,
}) {
  final ref = pickAmazonReferenceOffer(offers);
  if (ref?.priceAmount == null) return null;
  final pct = discountPct.clamp(0, 95);
  return double.parse(
    (ref!.priceAmount! * (1 - pct / 100)).toStringAsFixed(2),
  );
}

/// Dispersão anormal entre mercados disponíveis → «Por confirmar».
bool hasSuspiciousAmazonPriceSpread(
  List<AmazonOfferView> offers, {
  double maxRatio = 2.5,
}) {
  final prices = offers
      .where(isValidAmazonReferenceOffer)
      .map((o) => o.priceAmount!)
      .toList();
  if (prices.length < 2) return false;
  prices.sort();
  if (prices.first <= 0) return false;
  return prices.last / prices.first > maxRatio;
}

class AmazonOfferView {
  const AmazonOfferView({
    required this.marketplace,
    required this.status,
    this.priceAmount,
    this.currency,
    this.title,
    this.sourceUrl,
    this.fetchedAt,
    this.availability,
  });

  final String marketplace;
  final String status;
  final double? priceAmount;
  final String? currency;
  final String? title;
  final String? sourceUrl;
  final DateTime? fetchedAt;
  final String? availability;

  bool get isAmazonMarket =>
      kAmazonMarketPriority.contains(marketplace.toLowerCase());

  bool get isExternalOrManual => marketplace.toLowerCase() == 'manual';

  factory AmazonOfferView.fromRow(Map<String, dynamic> row) {
    return AmazonOfferView(
      marketplace: row['marketplace']?.toString() ?? '',
      status: row['status']?.toString() ?? 'pending',
      priceAmount: (row['price_amount'] as num?)?.toDouble(),
      currency: row['currency']?.toString(),
      title: row['title']?.toString(),
      sourceUrl: row['source_url']?.toString(),
      fetchedAt: DateTime.tryParse(row['fetched_at']?.toString() ?? ''),
      availability: row['availability']?.toString(),
    );
  }
}

class AmazonExternalCandidate {
  const AmazonExternalCandidate({
    required this.storeName,
    required this.url,
    this.priceAmount,
    this.currency,
    this.title,
    this.snippet,
    this.fetchedAt,
  });

  final String storeName;
  final String url;
  final double? priceAmount;
  final String? currency;
  final String? title;
  final String? snippet;
  final DateTime? fetchedAt;

  factory AmazonExternalCandidate.fromJson(Map<String, dynamic> row) {
    return AmazonExternalCandidate(
      storeName: row['store_name']?.toString() ??
          row['store']?.toString() ??
          'Loja',
      url: row['url']?.toString() ?? row['source_url']?.toString() ?? '',
      priceAmount: (row['price_amount'] as num?)?.toDouble() ??
          (row['price'] as num?)?.toDouble(),
      currency: row['currency']?.toString() ?? 'EUR',
      title: row['title']?.toString(),
      snippet: row['snippet']?.toString(),
      fetchedAt: DateTime.tryParse(row['fetched_at']?.toString() ?? ''),
    );
  }
}

class AmazonManifestPreview {
  const AmazonManifestPreview({
    required this.headers,
    required this.sampleRows,
    required this.totalRows,
    required this.distinctAsin,
    required this.missingRequired,
    required this.hasLpn,
    required this.hasAsin,
    this.rowsMissingLpn = 0,
    this.rowsMissingAsin = 0,
    this.duplicateLpnCount = 0,
  });

  final List<String> headers;
  final List<Map<String, String>> sampleRows;
  final int totalRows;
  final int distinctAsin;
  final List<String> missingRequired;
  final bool hasLpn;
  final bool hasAsin;
  /// Linhas com ASIN mas LPN vazio (bloqueiam importação dessa linha).
  final int rowsMissingLpn;
  final int rowsMissingAsin;
  final int duplicateLpnCount;

  bool get isValid =>
      missingRequired.isEmpty &&
      hasLpn &&
      hasAsin &&
      totalRows > 0 &&
      rowsMissingLpn == 0 &&
      rowsMissingAsin == 0 &&
      duplicateLpnCount == 0;
}
