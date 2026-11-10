/// Peso do manifesto Amazon → peso de expedição Fleaber (ZIP 162).
///
/// Contrato C1/DPD: o campo efectivo no cálculo de portes é
/// `products.shipping_weight_kg` (kg). Não altera checkout/Edges.
///
/// Idempotência: a margem de embalagem aplica-se **sempre** sobre o peso
/// original do manifesto (`manifest_weight_kg`), nunca sobre um valor já
/// majorado.
class AmazonWeight {
  AmazonWeight._();

  static const packagingPct = 10.0;

  /// Converte peso do manifesto para kg. [uom] tipicamente `GR` / `KG` / `LB`.
  /// Devolve null se valor inválido ou unidade desconhecida (não inventa).
  static double? toKg(num? raw, String? uom) {
    if (raw == null) return null;
    final v = raw.toDouble();
    if (v <= 0 || v.isNaN || v.isInfinite) return null;
    final u = (uom ?? '').trim().toUpperCase();
    if (u.isEmpty || u.startsWith('GR') || u == 'G' || u == 'GRAM') {
      return v / 1000.0;
    }
    if (u.startsWith('KG') || u == 'KGS' || u == 'KILO') {
      return v;
    }
    if (u.startsWith('LB') || u == 'LBS' || u == 'POUND') {
      return v * 0.45359237;
    }
    if (u.startsWith('OZ')) {
      return v * 0.0283495231;
    }
    return null;
  }

  /// Peso de expedição = original × (1 + margem/100). Arredonda a 3 casas.
  static double shippingKgFromManifest(double manifestKg, {double pct = packagingPct}) {
    final out = manifestKg * (1.0 + pct / 100.0);
    return double.parse(out.toStringAsFixed(3));
  }

  /// UI: «Peso por definir» quando não há manifesto fiável.
  static String formatManifestLabel(double? kg) {
    if (kg == null || kg <= 0) return 'Peso por definir';
    return '${kg.toStringAsFixed(kg >= 10 ? 1 : 2).replaceAll('.', ',')} kg';
  }

  static String formatShippingLabel(double? kg) {
    if (kg == null || kg <= 0) return 'Peso por definir';
    return '${kg.toStringAsFixed(kg >= 10 ? 1 : 2).replaceAll('.', ',')} kg (+${packagingPct.toStringAsFixed(0)}% embalagem)';
  }
}
