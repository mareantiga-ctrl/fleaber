// ignore_for_file: avoid_print
import 'dart:io';

import 'adapter_auto_mapper.dart';
import 'automation_policy.dart';
import 'store.dart';

void main() {
  final store = RegressionStore(RegressionPaths('.'));
  final manifest = store.loadManifest(regenerate: true);
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

  final errors = <String>[];
  if (c.total != kTotalTests) {
    errors.add('Total ${c.total} != $kTotalTests');
  }
  if (c.automated != kExpectedAutomated) {
    errors.add('Automated ${c.automated} != $kExpectedAutomated');
  }
  if (c.manual != kExpectedManual) {
    errors.add('Manual ${c.manual} != $kExpectedManual');
  }
  if (c.guided != kExpectedGuided) {
    errors.add('Guided ${c.guided} != $kExpectedGuided');
  }
  if (c.notImplemented != 0) {
    errors.add('Not implemented: ${c.notImplemented}');
  }
  for (final t in manifest.values) {
    if (isHumanOnlyCheckpoint(t.id)) continue;
    final type = t.adapter?.type ?? 'none';
    if (!AdapterAutoMapper.isAutomatedType(type)) {
      errors.add('${t.id} deveria ser automático mas tem $type');
    }
  }
  if (errors.isNotEmpty) {
    print('');
    print('POLICY FAIL:');
    for (final e in errors) print('  - $e');
    exit(1);
  }
  print('');
  print('OK: 405 automáticos, 24 manuais/guiados, 0 sem adapter.');
}
