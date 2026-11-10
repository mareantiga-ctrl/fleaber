/// Modelos para apresentar artigos Amazon preparados num directo (ZIP 183).
library;

class LiveAmazonPresentItem {
  const LiveAmazonPresentItem({
    required this.asin,
    required this.titlePt,
    required this.fleaberPriceEur,
    this.ean,
    this.lpn,
    this.flbReference,
    this.imageUrl,
    this.amazonRefPriceEur,
    this.amazonRefMarket,
    this.amazonRefFetchedAt,
    this.discountPct = 50,
    this.availableQty = 0,
    this.unitCount = 1,
    this.fleaberProductId,
    this.catalogProductId,
    this.unitId,
    this.saleCondition = 'Novo',
    this.companyKey = 'mare_antiga',
    this.needsReview = false,
  });

  final String asin;
  final String? ean;
  final String? lpn;
  final String? flbReference;
  final String titlePt;
  final String? imageUrl;
  final double? amazonRefPriceEur;
  final String? amazonRefMarket;
  final DateTime? amazonRefFetchedAt;
  final double fleaberPriceEur;
  final double discountPct;
  final int availableQty;
  final int unitCount;
  final String? fleaberProductId;
  final String? catalogProductId;
  final String? unitId;
  final String saleCondition;
  final String companyKey;
  final bool needsReview;

  bool get isSellableNow => availableQty > 0 && fleaberPriceEur > 0;

  String get refLabel {
    final l = (lpn ?? '').trim();
    if (l.isNotEmpty) return l;
    final f = (flbReference ?? '').trim();
    if (f.isNotEmpty) return f;
    return 'AMZ-$asin';
  }

  Map<String, dynamic> toJson() => {
        'asin': asin,
        'ean': ean,
        'lpn': lpn,
        'flb_reference': flbReference,
        'title_pt': titlePt,
        'image_url': imageUrl,
        'amazon_ref_price_eur': amazonRefPriceEur,
        'amazon_ref_market': amazonRefMarket,
        'amazon_ref_fetched_at': amazonRefFetchedAt?.toIso8601String(),
        'fleaber_price_eur': fleaberPriceEur,
        'discount_pct': discountPct,
        'available_qty': availableQty,
        'unit_count': unitCount,
        'fleaber_product_id': fleaberProductId,
        'catalog_product_id': catalogProductId,
        'unit_id': unitId,
        'sale_condition': saleCondition,
        'company_key': companyKey,
        'needs_review': needsReview,
      };

  factory LiveAmazonPresentItem.fromJson(Map<String, dynamic> j) {
    return LiveAmazonPresentItem(
      asin: j['asin']?.toString() ?? '',
      ean: j['ean']?.toString(),
      lpn: j['lpn']?.toString(),
      flbReference: j['flb_reference']?.toString(),
      titlePt: j['title_pt']?.toString() ?? '',
      imageUrl: j['image_url']?.toString(),
      amazonRefPriceEur: (j['amazon_ref_price_eur'] as num?)?.toDouble(),
      amazonRefMarket: j['amazon_ref_market']?.toString(),
      amazonRefFetchedAt:
          DateTime.tryParse(j['amazon_ref_fetched_at']?.toString() ?? ''),
      fleaberPriceEur: (j['fleaber_price_eur'] as num?)?.toDouble() ?? 0,
      discountPct: (j['discount_pct'] as num?)?.toDouble() ?? 50,
      availableQty: (j['available_qty'] as num?)?.toInt() ?? 0,
      unitCount: (j['unit_count'] as num?)?.toInt() ?? 1,
      fleaberProductId: j['fleaber_product_id']?.toString(),
      catalogProductId: j['catalog_product_id']?.toString(),
      unitId: j['unit_id']?.toString(),
      saleCondition: j['sale_condition']?.toString() ?? 'Novo',
      companyKey: j['company_key']?.toString() ?? 'mare_antiga',
      needsReview: j['needs_review'] == true,
    );
  }
}

/// Resultado de leitura de código no directo.
class LiveAmazonLookupResult {
  const LiveAmazonLookupResult({
    required this.query,
    required this.hits,
    this.notFound = false,
  });

  final String query;
  final List<LiveAmazonPresentItem> hits;
  final bool notFound;

  bool get found => hits.isNotEmpty;
}
