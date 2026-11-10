import 'dart:math';

final _rng = Random();

/// Pausa aleatória entre [minMs] e [maxMs] (inclusive).
Future<void> jitterMs(int minMs, int maxMs) async {
  final lo = minMs < 0 ? 0 : minMs;
  final hi = maxMs < lo ? lo : maxMs;
  final ms = lo + _rng.nextInt(hi - lo + 1);
  await Future<void>.delayed(Duration(milliseconds: ms));
}

int jitterInt(int min, int max) {
  final lo = min;
  final hi = max < lo ? lo : max;
  return lo + _rng.nextInt(hi - lo + 1);
}
