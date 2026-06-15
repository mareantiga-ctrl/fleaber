import 'dart:io';

import '../report/event_logger.dart';
import '../report/validators.dart';

Future<void> writeRunReports({
  required Directory reportDir,
  required EventLogger logger,
  required List<ValidationIssue> issues,
  required Map<String, dynamic> meta,
}) async {
  final errors = logger.errors.length;
  final oks = logger.events.where((e) => e.outcome == BotEventOutcome.ok).length;
  final fails = logger.events.where((e) => e.outcome == BotEventOutcome.fail).length;
  final skips = logger.events.where((e) => e.outcome == BotEventOutcome.skip).length;

  final summary = StringBuffer()
    ..writeln('# Bot Simulator — Summary')
    ..writeln()
    ..writeln('| Campo | Valor |')
    ..writeln('|-------|-------|')
    ..writeln('| Live ID | `${meta['live_id']}` |')
    ..writeln('| Run ID | `${meta['run_id']}` |')
    ..writeln('| Cenários | ${meta['scenarios']} |')
    ..writeln('| Bots | ${meta['bots']} |')
    ..writeln('| Chatters | ${meta['chatters']} |')
    ..writeln('| Duração | ${meta['duration']} |')
    ..writeln('| Demo mode | ${meta['demo_mode']} |')
    ..writeln('| Eventos OK | $oks |')
    ..writeln('| Eventos FAIL | $fails |')
    ..writeln('| Eventos SKIP | $skips |')
    ..writeln('| Erros (errors.jsonl) | $errors |')
    ..writeln('| Validações | ${issues.where((i) => i.severity == 'error').length} erros, '
        '${issues.where((i) => i.severity == 'warn').length} avisos |')
    ..writeln()
    ..writeln('## Relatório')
    ..writeln()
    ..writeln('- Pasta: `${reportDir.path}`')
    ..writeln('- `events.jsonl` — todas as acções')
    ..writeln('- `errors.jsonl` — falhas')
    ..writeln('- `inconsistencies.md` — validações automáticas')
    ..writeln('- `db_snapshot_before.json` / `db_snapshot_after.json`');

  await File('${reportDir.path}/summary.md').writeAsString(summary.toString());

  final inc = StringBuffer()..writeln('# Inconsistências detectadas\n');
  if (issues.isEmpty) {
    inc.writeln('Nenhuma inconsistência automática detectada.');
  } else {
    for (final i in issues) {
      inc.writeln('- **${i.severity.toUpperCase()}**: ${i.message}');
    }
  }
  await File('${reportDir.path}/inconsistencies.md').writeAsString(inc.toString());
}
