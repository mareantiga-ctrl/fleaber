/// Esquema de referências para o directo (ex.: numéricas 1–100, C1–C500, XRO1–XRO50).
class LiveRefScheme {
  const LiveRefScheme({
    this.prefix = '',
    required this.from,
    required this.to,
    this.exclude = const [],
  });

  final String prefix;
  final int from;
  final int to;
  final List<int> exclude;

  factory LiveRefScheme.fromJson(Map<String, dynamic> json) {
    final exRaw = json['exclude'];
    final exclude = <int>[];
    if (exRaw is List) {
      for (final e in exRaw) {
        final n = int.tryParse(e.toString());
        if (n != null) exclude.add(n);
      }
    }
    return LiveRefScheme(
      prefix: (json['prefix'] ?? '').toString().trim(),
      from: int.tryParse(json['from']?.toString() ?? '') ?? 0,
      to: int.tryParse(json['to']?.toString() ?? '') ?? 0,
      exclude: exclude,
    );
  }

  Map<String, dynamic> toJson() => {
        'prefix': prefix.trim(),
        'from': from,
        'to': to,
        'exclude': exclude,
      };

  String get normalizedPrefix {
    final raw = prefix.trim().toUpperCase();
    return raw.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  int get spanCount {
    if (from <= 0 || to <= 0 || to < from) return 0;
    return (to - from + 1) - exclude.toSet().length;
  }

  /// Etiqueta legível (ex.: «1 a 100» ou «C1 a C500 (exc. 24, 25)»).
  String displayLabel() {
    final p = normalizedPrefix;
    final range = p.isEmpty ? '$from a $to' : '$p$from a $p$to';
    if (exclude.isEmpty) return range;
    final ex = exclude.toSet().toList()..sort();
    return '$range (exc. ${ex.join(', ')})';
  }

  /// Código no card do carrossel.
  String refCodeForCard() {
    final p = normalizedPrefix;
    if (p.isEmpty) return '#$from-$to';
    return '#$p$from-$p$to';
  }

  String formatRef(int n) {
    final p = normalizedPrefix;
    if (p.isEmpty) return '#$n';
    return '#$p$n';
  }

  /// Expande referências individuais (limitado para não sobrecarregar a BD).
  List<String> expandRefs({int max = 200}) {
    if (from <= 0 || to <= 0 || to < from) return const [];
    final skip = exclude.toSet();
    final out = <String>[];
    for (var i = from; i <= to; i++) {
      if (skip.contains(i)) continue;
      out.add(formatRef(i));
      if (out.length >= max) break;
    }
    return out;
  }

  static LiveRefScheme? tryParse({
    required String prefixRaw,
    required String fromRaw,
    required String toRaw,
    required String excludeRaw,
  }) {
    final from = int.tryParse(fromRaw.trim());
    final to = int.tryParse(toRaw.trim());
    if (from == null || to == null || from < 1 || to < from) return null;

    final exclude = <int>[];
    for (final part in excludeRaw.split(RegExp(r'[,;\s]+'))) {
      final t = part.trim();
      if (t.isEmpty) continue;
      final n = int.tryParse(t);
      if (n != null) exclude.add(n);
    }

    return LiveRefScheme(
      prefix: prefixRaw.trim(),
      from: from,
      to: to,
      exclude: exclude,
    );
  }
}
