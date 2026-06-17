// Heurísticas visuais / textuais sobre evidência Maestro.
import 'models.dart';
import 'ui_extractor.dart';

final _technicalPatterns = [
  RegExp(r'\bRPC\b', caseSensitive: false),
  RegExp(r'\bUUID\b', caseSensitive: false),
  RegExp(r'\blive_item_id\b', caseSensitive: false),
  RegExp(r'\bnull\b', caseSensitive: false),
  RegExp(r'Failed assertion', caseSensitive: false),
  RegExp(r'Exception', caseSensitive: false),
  RegExp(r'\bERP\b', caseSensitive: false),
  RegExp(r'maestro', caseSensitive: false),
  RegExp(r'batata_', caseSensitive: false),
];

final _legacyLabels = [
  RegExp(r'A tratar', caseSensitive: false),
  RegExp(r'Utilizador\b', caseSensitive: false),
  RegExp(r'Preço pendente', caseSensitive: false),
];

final _incoherentNumber = RegExp(r'\b(\d+)\s*/\s*(\d+)\b');

class VisualHeuristics {
  static List<VisualWarning> analyze({
    required List<String> texts,
    required List<String> failedAsserts,
    required List<String> warnedAsserts,
    List<String> screenshots = const [],
    String sellerTexts = '',
    String buyerTexts = '',
  }) {
    final warnings = <VisualWarning>[];
    final shot = screenshots.isNotEmpty ? screenshots.first : '';

    for (final t in texts) {
      if (t.startsWith(r'${') || t.contains('MAESTRO_')) continue;
      for (final p in _technicalPatterns) {
        if (p.hasMatch(t)) {
          warnings.add(VisualWarning(
            category: 'technical_text',
            message: 'Texto técnico visível: "$t"',
            screenshot: shot,
            snippet: t,
          ));
          break;
        }
      }
      for (final p in _legacyLabels) {
        if (p.hasMatch(t)) {
          warnings.add(VisualWarning(
            category: 'legacy_label',
            message: 'Label possivelmente antiga: "$t"',
            screenshot: shot,
            snippet: t,
          ));
          break;
        }
      }
      final inc = _incoherentNumber.firstMatch(t);
      if (inc != null) {
        warnings.add(VisualWarning(
          category: 'incoherent_numbers',
          message: 'Rácio numérico suspeito: "$t"',
          screenshot: shot,
          snippet: t,
        ));
      }
    }

    for (final f in failedAsserts) {
      warnings.add(VisualWarning(
        category: 'maestro_assert_fail',
        message: f,
        screenshot: shot,
      ));
    }
    for (final w in warnedAsserts) {
      warnings.add(VisualWarning(
        category: 'maestro_assert_warn',
        message: w,
        screenshot: shot,
      ));
    }

    if (sellerTexts.isNotEmpty &&
        buyerTexts.isNotEmpty &&
        sellerTexts != buyerTexts) {
      final sellerNums = _extractAllNumbers(sellerTexts);
      final buyerNums = _extractAllNumbers(buyerTexts);
      for (final n in sellerNums) {
        if (buyerNums.isNotEmpty && !buyerNums.contains(n)) {
          warnings.add(VisualWarning(
            category: 'seller_buyer_mismatch',
            message:
                'Número $n aparece no seller mas não no buyer (possível desalinhamento)',
            screenshot: shot,
          ));
          break;
        }
      }
    }

    return warnings;
  }

  static List<int> _extractAllNumbers(String text) {
    return RegExp(r'\b(\d+)\b')
        .allMatches(text)
        .map((m) => int.tryParse(m.group(1) ?? ''))
        .whereType<int>()
        .toList();
  }

  static List<VisualWarning> fromExtractors({
    required UiExtractor seller,
    required UiExtractor buyer,
    required UiExtractor generic,
    List<String> screenshots = const [],
  }) {
    final allTexts = [
      ...seller.allTexts,
      ...buyer.allTexts,
      ...generic.allTexts,
    ];
    return analyze(
      texts: allTexts,
      failedAsserts: [
        ...seller.failedAsserts,
        ...buyer.failedAsserts,
        ...generic.failedAsserts,
      ],
      warnedAsserts: [
        ...seller.warnedAsserts,
        ...buyer.warnedAsserts,
        ...generic.warnedAsserts,
      ],
      screenshots: screenshots,
      sellerTexts: seller.allTexts.join(' | '),
      buyerTexts: buyer.allTexts.join(' | '),
    );
  }
}
