// Escreve relatórios de auditoria agregados.
import 'dart:convert';
import 'dart:io';

import 'models.dart';

class ReportWriter {
  ReportWriter(this.auditRoot);

  final String auditRoot;

  File get resultsFile => File('$auditRoot/audit_results.json');
  File get summaryFile => File('$auditRoot/audit_summary.md');
  File get warningsFile => File('$auditRoot/audit_warnings.md');
  File get failuresFile => File('$auditRoot/audit_failures.md');

  Future<void> appendVerdict(AuditVerdict v) async {
    Directory(auditRoot).createSync(recursive: true);
    final list = await _loadResults();
    list.removeWhere((e) => e['testId'] == v.testId);
    list.add(v.toJson());
    await resultsFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
            'updatedAt': DateTime.now().toIso8601String(),
            'verdicts': list,
          })}\n',
    );
    await _rewriteSummaries(list);
  }

  Future<List<Map<String, dynamic>>> _loadResults() async {
    if (!resultsFile.existsSync()) return [];
    try {
      final map = jsonDecode(await resultsFile.readAsString()) as Map;
      final list = map['verdicts'];
      if (list is List) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _rewriteSummaries(List<Map<String, dynamic>> list) async {
    final pass = list.where((v) => v['conclusion'] == 'PASS').length;
    final aviso = list
        .where((v) =>
            v['conclusion'] == 'PASS_COM_AVISO' ||
            v['conclusion'] == 'PASS_COM_AVISO_DEEPLINK')
        .length;
    final fail = list.where((v) => v['conclusion'] == 'FAIL').length;

    final sb = StringBuffer()
      ..writeln('# Auditoria Cursor — Resumo')
      ..writeln('')
      ..writeln('Actualizado: ${DateTime.now().toIso8601String()}')
      ..writeln('')
      ..writeln('| Resultado | Qtd |')
      ..writeln('|-----------|-----|')
      ..writeln('| PASS | $pass |')
      ..writeln('| PASS COM AVISO / DEEPLINK | $aviso |')
      ..writeln('| FAIL | $fail |')
      ..writeln('| **Total auditado** | **${list.length}** |')
      ..writeln('')
      ..writeln('| ID | Conclusão | Tipo | Deep link | Maestro |')
      ..writeln('|----|-----------|------|-----------|---------|');

    final warnSb = StringBuffer()
      ..writeln('# Auditoria — Avisos')
      ..writeln('');
    final failSb = StringBuffer()
      ..writeln('# Auditoria — Falhas')
      ..writeln('');

    for (final v in list) {
      final id = v['testId'];
      final c = v['conclusion'];
      final t = v['validationType'];
      final dl = v['usedDeepLink'] == true ? 'sim' : 'não';
      final me = v['maestroExitCode'];
      sb.writeln('| $id | $c | $t | $dl | $me |');

      final warnings = v['warnings'] as List? ?? [];
      if (warnings.isNotEmpty &&
          (c == 'PASS_COM_AVISO' || c == 'PASS_COM_AVISO_DEEPLINK')) {
        warnSb.writeln('## $id ($c)');
        for (final w in warnings) {
          if (w is Map) {
            warnSb.writeln('- **${w['category']}**: ${w['message']}');
          }
        }
        warnSb.writeln('');
      }

      if (c == 'FAIL') {
        failSb.writeln('## $id');
        failSb.writeln('- **Causa provável**: ${v['probableCause']}');
        final mismatches = v['stockMismatches'] as List? ?? [];
        for (final m in mismatches) {
          if (m is Map) {
            failSb.writeln(
              '- **${m['field']}**: esperado ${m['expected']} encontrado ${m['found']} (${m['sourceB']})',
            );
          }
        }
        final failures = v['failures'] as List? ?? [];
        for (final f in failures) {
          failSb.writeln('- $f');
        }
        failSb.writeln('');
      }
    }

    await summaryFile.writeAsString(sb.toString());
    await warningsFile.writeAsString(warnSb.toString());
    await failuresFile.writeAsString(failSb.toString());
  }
}
