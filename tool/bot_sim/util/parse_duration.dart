Duration parseBotSimDuration(String raw) {
  final t = raw.trim().toLowerCase();
  if (t.isEmpty) return const Duration(minutes: 10);
  final m = RegExp(r'^(\d+)(s|m|h|min|sec|hour|hours|minutes?|seconds?)?$')
      .firstMatch(t);
  if (m == null) {
    throw FormatException('Duração inválida: $raw (ex: 10m, 30s, 1h)');
  }
  final n = int.parse(m.group(1)!);
  final unit = m.group(2) ?? 'm';
  return switch (unit) {
    's' || 'sec' || 'second' || 'seconds' => Duration(seconds: n),
    'h' || 'hour' || 'hours' => Duration(hours: n),
    _ => Duration(minutes: n),
  };
}
