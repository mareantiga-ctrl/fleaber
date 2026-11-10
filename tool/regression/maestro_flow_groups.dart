// ignore_for_file: avoid_print
import 'store.dart';

void main() {
  final m = RegressionStore(RegressionPaths('.')).loadManifest(regenerate: true);
  final byFlow = <String, List<String>>{};
  for (final t in m.values) {
    if (t.adapter?.type != 'maestro') continue;
    final flow = t.adapter!.entry ?? t.adapter!.path;
    (byFlow[flow] ??= []).add(t.id);
  }
  final sorted = byFlow.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  var total = 0;
  for (final e in sorted) {
    total += e.value.length;
  }
  print('Maestro UI tests: $total');
  print('Unique YAML flows: ${sorted.length}');
  print('---');
  for (final e in sorted) {
    print('${e.value.length.toString().padLeft(3)}x ${e.key}');
  }
}
