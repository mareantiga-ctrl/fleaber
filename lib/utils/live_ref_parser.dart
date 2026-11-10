/// Converte texto livre (ex.: «b1 a b100 excluindo 24,25,28») em lista de referências.
abstract final class LiveRefParser {
  /// Entrada do vendedor → códigos normalizados (ex. `#B001`).
  static List<String> parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const [];

    final lower = text.toLowerCase();
    final exclude = <int>{};
    final exMatch = RegExp(
      r'(?:excluindo|exceto|except|excluding)\s+([^\n]+)',
      caseSensitive: false,
    ).firstMatch(lower);
    if (exMatch != null) {
      for (final n in _numbersIn(exMatch.group(1)!)) {
        exclude.add(n);
      }
    }

    String? prefix;
  int? start;
  int? end;

    final rangeRe = RegExp(
      r'([a-zA-Z]+)?\s*(\d+)\s*(?:a|até|ate|to|-|–)\s*([a-zA-Z]+)?\s*(\d+)',
      caseSensitive: false,
    );
    final range = rangeRe.firstMatch(text);
    if (range != null) {
      prefix = (range.group(1) ?? range.group(3))?.trim();
      start = int.tryParse(range.group(2)!);
      end = int.tryParse(range.group(4)!);
    }

    if (start == null || end == null) {
      // Lista simples: B1, B2, 24, #010 …
      final out = <String>[];
      for (final token in text.split(RegExp(r'[,;\s]+'))) {
        final t = token.trim();
        if (t.isEmpty) continue;
        if (RegExp(r'^(excluindo|exceto)', caseSensitive: false).hasMatch(t)) {
          continue;
        }
        final n = _parseRefToken(t, prefixHint: prefix);
        if (n != null) out.add(n);
      }
      final unique = out.toSet().toList();
      unique.sort();
      return unique;
    }

    if (start > end) {
      final t = start;
      start = end;
      end = t;
    }

    final p = (prefix ?? '').toUpperCase();
    final width = end.toString().length;
    final refs = <String>[];
    for (var i = start; i <= end; i++) {
      if (exclude.contains(i)) continue;
      final core = p.isEmpty ? i.toString() : '$p$i';
      refs.add(_normalizeRef(core, padWidth: width));
    }
    return refs;
  }

  static Iterable<int> _numbersIn(String chunk) {
    return RegExp(r'\d+')
        .allMatches(chunk)
        .map((m) => int.tryParse(m.group(0)!))
        .whereType<int>();
  }

  static String? _parseRefToken(String token, {String? prefixHint}) {
    final t = token.trim();
    if (t.isEmpty) return null;
    final m = RegExp(r'^#?([a-zA-Z]*)(\d+)$').firstMatch(t);
    if (m != null) {
      final letters = m.group(1) ?? prefixHint ?? '';
      return _normalizeRef('${letters}${m.group(2)}');
    }
    if (RegExp(r'^\d+$').hasMatch(t)) {
      final p = prefixHint ?? '';
      return _normalizeRef('$p$t');
    }
    return _normalizeRef(t.replaceFirst(RegExp(r'^#'), ''));
  }

  static String _normalizeRef(String core, {int? padWidth}) {
    final m = RegExp(r'^([a-zA-Z]*)(\d+)$').firstMatch(core.trim());
    if (m != null) {
      final letters = (m.group(1) ?? '').toUpperCase();
      var num = m.group(2)!;
      if (padWidth != null && padWidth > num.length) {
        num = num.padLeft(padWidth, '0');
      }
      return '#$letters$num';
    }
    final c = core.trim().toUpperCase();
    return c.startsWith('#') ? c : '#$c';
  }
}
