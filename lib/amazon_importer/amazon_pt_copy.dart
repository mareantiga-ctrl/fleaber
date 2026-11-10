/// Geração de títulos e descrições comerciais em português de Portugal.
/// Não inventa especificações: só reorganiza o que já veio no texto de origem.
library;

final _stop = {
  'the',
  'and',
  'with',
  'for',
  'de',
  'da',
  'do',
  'das',
  'dos',
  'e',
  'em',
  'para',
  'com',
  'um',
  'uma',
  'o',
  'a',
  'os',
  'as',
  'di',
  'il',
  'la',
  'le',
  'un',
  'une',
  'des',
  'du',
  'der',
  'die',
  'und',
  'für',
  'mit',
  'amazon',
};

String _clean(String raw) {
  var s = raw
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'&[#a-zA-Z0-9]+;'), ' ')
      .replaceAll(RegExp(r'\s*[|:].*Amazon.*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return s;
}

/// Extrai marca aproximada (primeira palavra capitalizada / token conhecido).
String? extractBrand(String source) {
  final s = _clean(source);
  if (s.isEmpty) return null;
  final first = s.split(RegExp(r'[\s\-—,|]')).firstWhere(
        (e) => e.trim().length >= 2,
        orElse: () => '',
      );
  if (first.isEmpty) return null;
  return first.trim();
}

/// Título comercial PT-PT (curto, natural).
/// Ordem comercial: **produto primeiro, marca depois** (ex. «Candeeiro … Velamp …»).
String buildCommercialTitlePt({
  required String sourceTitle,
  String? brandHint,
  String? modelHint,
}) {
  final clean = _clean(sourceTitle);
  if (clean.isEmpty) return 'Artigo sem título';

  final brand = (brandHint ?? extractBrand(clean) ?? '').trim();
  var rest = clean;
  if (brand.isNotEmpty &&
      rest.toLowerCase().startsWith(brand.toLowerCase())) {
    rest = rest.substring(brand.length).replaceFirst(RegExp(r'^[\s\-—,|:]+'), '');
  }

  // Remover marketing inglês genérico óbvio.
  rest = rest
      .replaceAll(
        RegExp(
          r'\b(Handheld|Steam Cleaner|Compact|Powerful|Chemical Free|Cleaning|Professional|Premium)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // Dimensões / modelos curtos a preservar.
  final dims = RegExp(
    r'(\d+(?:[.,]\d+)?\s*(?:cm|mm|m|L|W|ml|Ø|ø)|\bSC\s*\d+\b|\bGF\d+\w*\b)',
    caseSensitive: false,
  ).allMatches(clean).map((m) => m.group(0)!.trim()).toSet().take(3).toList();

  final kind = _guessKindPt(clean);
  final model = (modelHint ?? '').trim();
  final productCore = <String>[
    if (kind != null) kind,
    if (model.isNotEmpty) model,
    if (dims.isNotEmpty) dims.first,
  ].where((e) => e.trim().isNotEmpty).toList();

  String headline;
  if (productCore.isNotEmpty) {
    final product = productCore.join(' ');
    headline = brand.isNotEmpty ? '$product $brand' : product;
  } else if (brand.isNotEmpty) {
    final tail = _shortPtTail(rest);
    headline = tail.isEmpty ? brand : '$tail $brand';
  } else {
    headline = _shortPtTail(rest);
  }

  headline = headline.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (headline.length > 90) {
    headline = '${headline.substring(0, 87).trimRight()}…';
  }
  return headline.isEmpty ? clean : headline;
}

bool _hasWord(String haystackLower, String needle) {
  return RegExp(
    '\\b${RegExp.escape(needle)}\\b',
    caseSensitive: false,
  ).hasMatch(haystackLower);
}

String? _guessKindPt(String s) {
  final l = s.toLowerCase();
  if (_hasWord(l, 'steam') ||
      _hasWord(l, 'vapor') ||
      l.contains('pulitore a vapore') ||
      l.contains('steam cleaner')) {
    return 'Máquina de limpeza a vapor compacta';
  }
  // Word-boundary: evita falso positivo «candle» dentro de «Charleston».
  if (_hasWord(l, 'candle') ||
      _hasWord(l, 'candela') ||
      _hasWord(l, 'vela') ||
      _hasWord(l, 'candles')) {
    return 'Vela perfumada';
  }
  if (_hasWord(l, 'cocotte') || _hasWord(l, 'casserole')) {
    return 'Caçarola de ferro fundido';
  }
  if (_hasWord(l, 'padella') ||
      _hasWord(l, 'sartén') ||
      l.contains('frying pan')) {
    return 'Frigideira antiaderente';
  }
  if (_hasWord(l, 'specchio') ||
      _hasWord(l, 'espejo') ||
      _hasWord(l, 'mirror')) {
    return 'Espelho de maquilhagem com luz';
  }
  // lamp / lampada / lámpara — «lamp» com boundary evita lixo; desk lamp OK.
  if (_hasWord(l, 'lamp') ||
      _hasWord(l, 'lamps') ||
      _hasWord(l, 'lampada') ||
      _hasWord(l, 'lámpara') ||
      _hasWord(l, 'lampe') ||
      l.contains('desk lamp') ||
      l.contains('table lamp')) {
    return 'Candeeiro';
  }
  if (_hasWord(l, 'ginocchiere') ||
      _hasWord(l, 'rodillera') ||
      _hasWord(l, 'knee')) {
    return 'Joelheiras de compressão';
  }
  if (_hasWord(l, 'cuscino') ||
      _hasWord(l, 'cojín') ||
      _hasWord(l, 'cushion')) {
    return 'Almofada para cadeira';
  }
  if (_hasWord(l, 'spalla') ||
      _hasWord(l, 'hombro') ||
      _hasWord(l, 'shoulder')) {
    return 'Suporte para ombro';
  }
  if (_hasWord(l, 'gioielli') ||
      _hasWord(l, 'jewelry') ||
      _hasWord(l, 'joyas')) {
    return 'Organizadores para joias';
  }
  if (_hasWord(l, 'tenda') ||
      _hasWord(l, 'cortina') ||
      _hasWord(l, 'curtain')) {
    return 'Cortina para porta';
  }
  if (_hasWord(l, 'storage') ||
      _hasWord(l, 'scatole') ||
      _hasWord(l, 'cestas')) {
    return 'Conjunto de caixas de arrumação';
  }
  if (_hasWord(l, 'pancera') ||
      _hasWord(l, 'lumbar') ||
      _hasWord(l, 'belly')) {
    return 'Cinta térmica lombar';
  }
  if (_hasWord(l, 'pendelleuchte') ||
      _hasWord(l, 'colgante') ||
      _hasWord(l, 'pendant')) {
    return 'Candeeiro de suspensão';
  }
  return null;
}

String _shortPtTail(String rest) {
  if (rest.isEmpty) return '';
  // Evitar inglês puro: se parece marketing EN longo, encurtar aos primeiros tokens úteis.
  final parts = rest
      .split(RegExp(r'[\-—,|:]'))
      .map((e) => e.trim())
      .where((e) => e.length > 2)
      .toList();
  if (parts.isEmpty) return rest.length > 48 ? '${rest.substring(0, 45)}…' : rest;
  var t = parts.first;
  if (t.length > 55) t = '${t.substring(0, 52)}…';
  return t;
}

/// Descrição comercial PT-PT curta, só com factos presentes no texto de origem.
String buildCommercialDescriptionPt({
  required String sourceTitle,
  String? sourceDescription,
  String? brand,
  String? conditionNote,
}) {
  final title = _clean(sourceTitle);
  final desc = _clean(sourceDescription ?? '');
  final b = (brand ?? extractBrand(title) ?? '').trim();
  final kind = _guessKindPt('$title $desc') ?? 'artigo';
  final dims = RegExp(
    r'\d+(?:[.,]\d+)?\s*(?:cm|mm|m|L|W|ml)',
    caseSensitive: false,
  ).allMatches('$title $desc').map((m) => m.group(0)!.trim()).toSet().take(4);

  final buf = StringBuffer();
  if (b.isNotEmpty) {
    buf.writeln('$b — $kind para uso doméstico.');
  } else {
    buf.writeln('${kind[0].toUpperCase()}${kind.substring(1)} para uso doméstico.');
  }
  if (dims.isNotEmpty) {
    buf.writeln('Características indicadas: ${dims.join(', ')}.');
  }
  // Frase com palavras relevantes do título (sem inventar).
  final tokens = title
      .split(RegExp(r'[^A-Za-zÀ-ÿ0-9]+'))
      .where((t) => t.length >= 4 && !_stop.contains(t.toLowerCase()))
      .take(8)
      .toList();
  if (tokens.isNotEmpty) {
    buf.writeln('Referência do fabricante / modelo: ${tokens.take(5).join(' ')}.');
  }
  if ((conditionNote ?? '').trim().isNotEmpty) {
    buf.writeln(
      'Nota de stock: a unidade no nosso inventário pode ter condição '
      'diferente da listagem Amazon (${conditionNote!.trim()}).',
    );
  }
  buf.writeln(
    'Confirme dimensões, acessórios e estado antes de publicar. '
    'Não incluímos garantias ou especificações não confirmadas.',
  );
  return buf.toString().trim();
}

/// Condição de venda Fleaber para artigos importados Amazon.
/// Decisão comercial: sempre **Novo** (o CONDITION do manifesto fica só
/// como nota interna / inventário — não define o estado de venda).
String saleConditionFromManifest(String? conditionCode) {
  // conditionCode mantido na assinatura para compatibilidade / auditoria.
  // ignore: unused_local_variable
  final _ = (conditionCode ?? '').trim();
  return 'Novo';
}

/// Nota interna do manifesto (não usar como estado de venda no Marketplace).
String manifestConditionNote(String? conditionCode) {
  final c = (conditionCode ?? '').trim();
  if (c.isEmpty) return '';
  return c;
}
