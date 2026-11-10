/// Títulos / textos de seed QA → apresentação comercial (H11 visual).
/// Não altera a BD; só a camada de UI.
String fleaberCommercialTitle(String? raw) {
  var t = (raw ?? '').trim();
  if (t.isEmpty) return 'Artigo';

  t = t
      .replaceAll(RegExp(r'\[H10_TESTE[^\]]*\]\s*'), '')
      .replaceAll(RegExp(r'H10_TESTE_COMPLETO_\d+\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'\[E63[^\]]*\]\s*', caseSensitive: false), '')
      .replaceAll(
          RegExp(r'^E63\s+TEST\s+PRODUCT(?:\s+B)?\s*(?:\[[^\]]*\])?\s*',
              caseSensitive: false),
          '')
      .replaceAll(
          RegExp(r'^E63\s+TEST\s+ITEM\s*(?:\[[^\]]*\])?\s*',
              caseSensitive: false),
          '')
      .replaceAll(
          RegExp(r'^E63\s+TRUST\s+ITEM\s*(?:\[[^\]]*\])?\s*',
              caseSensitive: false),
          '')
      .replaceAll(RegExp(r'^TEST\s+PRODUCT\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*—\s*TESTE\s*\d+\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\[E63\s+DONE\]\s*', caseSensitive: false), '')
      .trim();

  final lower = t.toLowerCase();
  if (lower.contains('artigo historico') ||
      lower.contains('artigo histórico') ||
      lower == 'estados' ||
      lower.startsWith('artigo historico')) {
    return 'Peça vintage seleccionada';
  }
  if (t.isEmpty ||
      lower == 'e63 test item' ||
      lower == 'e63 trust item' ||
      lower == 'test item') {
    return 'Artigo de amostra';
  }
  return t;
}

/// Mensagens de actividade / refs técnicas → texto legível.
String fleaberCommercialLine(String? raw) {
  var t = fleaberCommercialTitle(raw);
  t = t
      .replaceAll(RegExp(r'\bRef\s+[A-Za-z0-9_-]+\b'), 'Artigo')
      .replaceAll(RegExp(r'\bRef\s+\d+\b'), 'Artigo')
      .trim();
  if (t.isEmpty) return 'Actualização';
  return t;
}
