// ignore_for_file: avoid_print
/// Fleaber Regression Runner — orquestrador único da matriz A001–A429.
///
/// Uso:
///   dart run tool/fleaber_regression_runner.dart --full
///   dart run tool/fleaber_regression_runner.dart --range A190-A230
///   dart run tool/fleaber_regression_runner.dart --self-test
library;

import 'dart:io';

import 'regression/models.dart';
import 'regression/runner.dart';

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final code = await RegressionRunner(options).run();
  if (code != 0) {
    exit(code);
  }
}

RunnerOptions _parseArgs(List<String> args) {
  var full = false;
  var failedOnly = false;
  var retestRequired = false;
  var regenerateManifest = false;
  var selfTest = false;
  var guided = false;
  var skipAudit = false;
  var maestroChains = true;
  String? range;
  String? priority;
  String? area;
  String? id;
  String? recordManual;
  String? suggestChanged;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--full':
        full = true;
        break;
      case '--failed-only':
        failedOnly = true;
        break;
      case '--retest-required':
        retestRequired = true;
        break;
      case '--regenerate-manifest':
        regenerateManifest = true;
        break;
      case '--self-test':
        selfTest = true;
        break;
      case '--guided':
        guided = true;
        break;
      case '--skip-audit':
        skipAudit = true;
        break;
      case '--no-maestro-chains':
        maestroChains = false;
        break;
      case '--maestro-chains':
        maestroChains = true;
        break;
      case '--range':
        range = _nextArg(args, ++i, a);
        break;
      case '--priority':
        priority = _nextArg(args, ++i, a);
        break;
      case '--area':
        area = _nextArg(args, ++i, a);
        break;
      case '--id':
        id = _nextArg(args, ++i, a);
        break;
      case '--record-manual':
        recordManual = _nextArg(args, ++i, a);
        break;
      case '--suggest-retest':
        // --suggest-retest --changed <path>
        break;
      case '--changed':
        suggestChanged = _nextArg(args, ++i, a);
        break;
      case '--help':
      case '-h':
        _printHelp();
        exit(0);
      default:
        if (a.startsWith('--record-manual=')) {
          recordManual = a.substring('--record-manual='.length);
        } else if (a.startsWith('--')) {
          print('Flag desconhecida: $a (use --help)');
          exit(2);
        }
    }
  }

  if (suggestChanged == null && args.contains('--suggest-retest')) {
    final idx = args.indexOf('--changed');
    if (idx >= 0 && idx + 1 < args.length) {
      suggestChanged = args[idx + 1];
    } else {
      print('Use: --suggest-retest --changed <path>');
      exit(2);
    }
  }

  if (recordManual != null && recordManual.contains(' ')) {
    // --record-manual A205 pass
    final parts = recordManual.trim().split(RegExp(r'\s+'));
    if (parts.length == 2) {
      recordManual = '${parts[0]}=${parts[1]}';
    }
  }

  return RunnerOptions(
    full: full,
    failedOnly: failedOnly,
    retestRequired: retestRequired,
    range: range,
    priority: priority,
    area: area,
    id: id,
    recordManual: recordManual,
    suggestRetestChanged: suggestChanged,
    regenerateManifest: regenerateManifest,
    selfTest: selfTest,
    guided: guided,
    skipAudit: skipAudit,
    maestroChains: maestroChains,
  );
}

String _nextArg(List<String> args, int i, String flag) {
  if (i >= args.length) {
    print('Valor em falta para $flag');
    exit(2);
  }
  return args[i];
}

void _printHelp() {
  print('''
Fleaber Regression Runner — matriz A001–A429

Comandos:
  --full                    Corre todos os testes (filtro = universo)
  --full --guided           Com prompts para live_id / UI real
  --failed-only             Só fail/flaky no state
  --retest-required         Só retest_required no state
  --range A190-A230         Subconjunto por ID
  --priority P0             Filtrar prioridade
  --area checkout           Filtrar área (sinónimos: rifa, gravado, ...)
  --id A209                 Um teste
  --record-manual A205=pass Registar resultado manual
  --suggest-retest --changed lib/widgets/live_vendor_studio_panel.dart
  --regenerate-manifest     Re-parse docs → manifest + risk_graph
  --self-test               Smoke da infraestrutura
  --skip-audit              Não corre auditoria Cursor pós-teste
  --no-maestro-chains       Maestro: 1 flow por ID (legado, mais lento)
  --maestro-chains          Maestro: sessões em cadeia (defeito ON)

Auditoria (por defeito ON): tool/logs/regression_<stamp>/ + tool/logs/audit_<stamp>/
Relatórios: tool/reports/regression_<timestamp>/
Estado: test/regression/state.json
''');
}
