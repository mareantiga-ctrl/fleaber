// ignore_for_file: avoid_print
import 'adapter_auto_mapper.dart';
import 'store.dart';

void main() {
  final store = RegressionStore(RegressionPaths('.'));
  final manifest = store.loadManifest();
  final c = computeCoverage(manifest);
  print('=== Adapter Coverage ===');
  print('Total: ${c.total}');
  print('Automated: ${c.automated}');
  print('Manual checkpoint: ${c.manual}');
  print('Guided checkpoint: ${c.guided}');
  print('Not implemented: ${c.notImplemented}');
  print('P0 total: ${c.p0Total}');
  print('P0 automated: ${c.p0Automated}');
  print('P0 gaps: ${c.p0Gaps.length}');
  final byType = <String, int>{};
  for (final t in manifest.values) {
    final type = t.adapter?.type ?? 'none';
    byType[type] = (byType[type] ?? 0) + 1;
  }
  print('By adapter type:');
  for (final e in byType.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
    print('  ${e.key}: ${e.value}');
  }
}
