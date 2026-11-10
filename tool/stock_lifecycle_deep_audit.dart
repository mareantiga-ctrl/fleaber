// ignore_for_file: avoid_print
/// Auditoria holística da pasta de evidências SL (prints + logs + BD snapshots).
///
/// Uso: dart run tool/stock_lifecycle_deep_audit.dart --evidence-dir tool/logs/stock_lifecycle_STAMP
library;

import 'dart:convert';
import 'dart:io';

import 'audit/audit_engine.dart';
import 'audit/models.dart';
import 'audit/report_writer.dart';
import 'audit/ui_extractor.dart';
import 'audit/visual_heuristics.dart';
import 'live_ops_staging_client.dart';
import 'regression/staging_guard.dart';

Future<void> main(List<String> args) async {
  var evidenceDir = '';
  var stamp = '';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--evidence-dir' && i + 1 < args.length) {
      evidenceDir = args[++i];
    } else if (args[i] == '--stamp' && i + 1 < args.length) {
      stamp = args[++i];
    }
  }

  if (evidenceDir.isEmpty) {
    print('Use: --evidence-dir <path> [--stamp yyyyMMdd_HHmmss]');
    exit(2);
  }

  final dir = Directory(evidenceDir);
  if (!dir.existsSync()) {
    print('FAIL: pasta inexistente $evidenceDir');
    exit(1);
  }

  final projectRoot = Directory.current.path;
  final screenshots = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) {
        final n = f.path.toLowerCase();
        return n.endsWith('.png') || n.endsWith('.jpg');
      })
      .map((f) => f.path)
      .toList();

  final commandJsons = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.contains('commands-') && f.path.endsWith('.json'))
      .map((f) => f.path)
      .toList();

  final logs = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.log'))
      .map((f) => f.path)
      .toList();

  final seller = UiExtractor(surface: 'seller_ui');
  final buyer = UiExtractor(surface: 'buyer_ui');
  final generic = UiExtractor(surface: 'ui');

  for (final p in commandJsons) {
    final lower = p.toLowerCase();
    if (lower.contains('buyer')) {
      buyer.extractTextsFromJsonFile(p);
    } else if (lower.contains('seller')) {
      seller.extractTextsFromJsonFile(p);
    } else {
      generic.extractTextsFromJsonFile(p);
    }
  }

  final warnings = VisualHeuristics.fromExtractors(
    seller: seller,
    buyer: buyer,
    generic: generic,
    screenshots: screenshots,
  );

  // Contradições de pagamento / preço (bugs conhecidos)
  final allText = [
    ...seller.allTexts,
    ...buyer.allTexts,
    ...generic.allTexts,
  ].join(' ').toLowerCase();

  final hasPagar = allText.contains('pagar') || allText.contains('pronto a pagar');
  final hasAwaitPrice = allText.contains('aguarda') &&
      (allText.contains('preço') || allText.contains('preco'));
  if (hasPagar && hasAwaitPrice) {
    warnings.add(VisualWarning(
      category: 'contradictory_payment_labels',
      message: 'UI mostra Pagar/pronto a pagar E aguarda preço no mesmo checkpoint',
      screenshot: screenshots.isNotEmpty ? screenshots.first : '',
    ));
  }

  LiveOpsStagingClient? client;
  try {
    final env = loadLiveOpsStagingEnv();
    final guard = RegressionStagingGuard.check(env);
    if (guard.ok) {
      client = LiveOpsStagingClient(
        url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
        anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
        serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
      );
    }
  } catch (_) {}

  final liveId = _readMaestroEnvKey('MAESTRO_LIVE_ID') ?? '';
  final engine = AuditEngine(
    projectRoot: projectRoot,
    client: client,
    writer: ReportWriter('$evidenceDir/deep_audit${stamp.isNotEmpty ? '_$stamp' : ''}'),
  );

  final evidence = AuditEvidence(
    testId: 'SL-DEEP',
    stamp: stamp.isNotEmpty ? stamp : 'deep',
    liveId: liveId,
    layer: 'UX+BD+MSG',
    scenario: 'stock_lifecycle',
    maestroExitCode: 0,
    screenshotPaths: screenshots,
    commandsJsonPaths: commandJsons,
    logPaths: logs,
    flowPaths: const [],
  );

  final verdict = await engine.audit(evidence);
  final allWarnings = [...verdict.warnings, ...warnings];

  final outFile = File('$evidenceDir/deep_audit_summary.json');
  outFile.writeAsStringSync(jsonEncode({
    'conclusion': verdict.conclusion,
    'failures': verdict.failures,
    'warnings': allWarnings.map((w) => w.toJson()).toList(),
    'screenshots': screenshots.length,
    'commands_json': commandJsons.length,
    'stock_mismatches': verdict.stockMismatches.map((m) => m.toJson()).toList(),
  }));

  print('=== DEEP AUDIT ===');
  print('Conclusion: ${verdict.conclusion}');
  print('Failures: ${verdict.failures.length}');
  print('Warnings: ${allWarnings.length}');
  print('Screenshots: ${screenshots.length}');
  print('Wrote ${outFile.path}');

  exit(verdict.conclusion == 'FAIL' ? 1 : 0);
}

String? _readMaestroEnvKey(String key) {
  final f = File('.maestro/.env');
  if (!f.existsSync()) return null;
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (t.startsWith('$key=')) return t.substring(key.length + 1).trim();
  }
  return null;
}
