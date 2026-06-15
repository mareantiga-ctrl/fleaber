/// Linha compacta de atributos (tamanho / cor) nos cards de catálogo live.
abstract final class LiveCatalogItemAttributes {
  static String? subtitle({
    String? clothingSize,
    String? color,
  }) {
    final parts = <String>[];
    final size = clothingSize?.trim();
    final col = color?.trim();
    if (size != null && size.isNotEmpty) parts.add('Tam. $size');
    if (col != null && col.isNotEmpty) parts.add('Cor $col');
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
