class AmazonScanHit {
  const AmazonScanHit({
    required this.catalogProductId,
    required this.asin,
    this.unitId,
    this.ean,
    this.lpn,
    this.title,
    this.imageUrl,
    this.saleEur,
    this.manifestKg,
    this.shippingKg,
    this.qty,
    this.condition,
    this.storageLocation,
    this.fleaberProductId,
  });

  final String catalogProductId;
  final String asin;
  final String? unitId;
  final String? ean;
  final String? lpn;
  final String? title;
  final String? imageUrl;
  final double? saleEur;
  final double? manifestKg;
  final double? shippingKg;
  final int? qty;
  final String? condition;
  final String? storageLocation;
  final String? fleaberProductId;
}
