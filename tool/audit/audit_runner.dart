// ignore_for_file: avoid_print
/// Auditoria automática pós-teste (Cursor = auditor final).
///
/// Uso:
///   dart run tool/audit/audit_runner.dart --test-id T07c --stamp 20260616_142156 \
///     --evidence-dir tool/logs/screenshots_20260616_142156/01_maestro_automation \
///     --maestro-exit 0 --layer UX --scenario maestro_buyer
///
///   dart run tool/audit/audit_runner.dart --batch-stamp 20260616_142156
///   dart run tool/audit/audit_runner.dart --reclassify-registry
library;

import 'dart:convert';
import 'dart:io';

import '../live_ops_staging_client.dart';
import 'audit_engine.dart';
import 'deeplink_detector.dart';
import 'evidence_collector.dart';
import 'report_writer.dart';

Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);
  final root = Directory.current.path;

  if (opts['reclassify-registry'] == 'true') {
    await _reclassifyRegistry(root);
    return;
  }

  if (opts['batch-stamp'] != null && opts['batch-stamp']!.isNotEmpty) {
    await _batchAudit(root, opts['batch-stamp']!);
    return;
  }

  final testId = opts['test-id'];
  if (testId == null || testId.isEmpty) {
    print('Use --test-id ou --batch-stamp ou --reclassify-registry');
    exit(2);
  }

  final stamp = opts['stamp'] ?? '';
  final evidenceDirRaw = opts['evidence-dir'] ?? '';
  final evidenceParts = evidenceDirRaw
      .split(';')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final maestroExit = int.tryParse(opts['maestro-exit'] ?? '0') ?? 0;
  final layer = opts['layer'] ?? '';
  final scenario = opts['scenario'] ?? testId;
  final logPath = opts['log-path'] ?? '';

  final evidence = EvidenceCollector.collect(
    testId: testId,
    scenario: scenario,
    stamp: stamp,
    evidenceDir: evidenceParts.isNotEmpty ? evidenceParts.first : '',
    extraEvidenceDirs:
        evidenceParts.length > 1 ? evidenceParts.sublist(1) : const [],
    maestroExitCode: maestroExit,
    extraLogPaths: logPath.isNotEmpty ? [logPath] : [],
    layer: layer,
    liveId: _readMaestroEnv(root, 'MAESTRO_LIVE_ID'),
    sellerId: _readMaestroEnv(root, 'MAESTRO_SELLER_ID'),
  );

  final verdict = await _runAudit(root, stamp, evidence);
  print('AUDIT ${verdict.testId} => ${verdict.conclusion}');
  if (verdict.probableCause.isNotEmpty) {
    print('  causa: ${verdict.probableCause}');
  }
  exit(verdict.conclusion == 'FAIL' ? 1 : 0);
}

Future<dynamic> _runAudit(
  String root,
  String stamp,
  dynamic evidence,
) async {
  LiveOpsStagingClient? client;
  try {
    final env = loadLiveOpsStagingEnv();
    client = LiveOpsStagingClient(
      url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
      anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
      serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
    );
  } catch (e) {
    print('AVISO: BD indisponível para auditoria ($e)');
  }

  final auditRoot = '$root/tool/logs/audit_$stamp';
  final engine = AuditEngine(
    projectRoot: root,
    client: client,
    writer: ReportWriter(auditRoot),
  );
  return engine.audit(evidence);
}

Future<void> _batchAudit(String root, String stamp) async {
  final logsDir = Directory('$root/tool/logs');
  final jobs = <Map<String, dynamic>>[];

  // Regression matrix — pastas A### por teste
  final regRoot = Directory('$root/tool/logs/regression_$stamp');
  if (regRoot.existsSync()) {
    for (final ent in regRoot.listSync()) {
      if (ent is! Directory) continue;
      final name = ent.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!RegExp(r'^A\d{3}$').hasMatch(name)) continue;
      var maestroExit = 0;
      final runLog = File('${ent.path}/run.log');
      if (runLog.existsSync()) {
        final content = runLog.readAsStringSync();
        if (content.contains('status=fail')) maestroExit = 1;
      }
      jobs.add({
        'testId': name,
        'evidenceDir': ent.path,
        'layer': 'UX+BD',
        'scenario': name,
        'maestroExit': maestroExit,
        'logPath': runLog.path,
      });
    }
  }

  // Battery screenshots folders
  final shotRoot = Directory('$root/tool/logs/screenshots_$stamp');
  if (shotRoot.existsSync()) {
    final mapping = {
      '01_maestro_automation': 'T07c',
      '02_doc_apk_buyer': 'T08b',
      '03_seller_stock': 'T09',
    };
    for (final ent in shotRoot.listSync()) {
      if (ent is! Directory) continue;
      final name = ent.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final testId = mapping[name] ?? name;
      jobs.add({
        'testId': testId,
        'evidenceDir': ent.path,
        'layer': 'UX',
        'scenario': name,
        'maestroExit': 0,
      });
    }
  }

  // Cross-surface — agrupar CSnn_seller / CSnn_buyer por cenário
  final csRoot = Directory('$root/tool/logs/cross_surface_$stamp');
  if (csRoot.existsSync()) {
    final grouped = <String, List<String>>{};
    for (final ent in csRoot.listSync()) {
      if (ent is! Directory) continue;
      final name = ent.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final m = RegExp(r'^CS(\d+)', caseSensitive: false).firstMatch(name);
      if (m == null) continue;
      final csId = 'CS${m.group(1)}';
      grouped.putIfAbsent(csId, () => []).add(ent.path);
    }
    for (final e in grouped.entries) {
      final csId = e.key;
      final num = int.tryParse(csId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final testId = 'T${(10 + num).toString().padLeft(2, '0')}';
      jobs.add({
        'testId': testId,
        'evidenceDir': e.value.first,
        'extraEvidenceDirs': e.value.skip(1).toList(),
        'layer': 'UX+BD',
        'scenario': csId,
        'maestroExit': 0,
        'logPath': '$root/tool/logs/cross_surface_$stamp/${csId}_seller_run.log',
      });
    }
  }

  // BD-only steps from battery log presence
  for (final t in ['T01', 'T02', 'T03', 'T04', 'T05', 'T06']) {
    final log = File('$root/tool/logs/${stamp}_.log');
    jobs.add({
      'testId': t,
      'evidenceDir': shotRoot.existsSync() ? shotRoot.path : logsDir.path,
      'layer': 'BD',
      'scenario': t,
      'maestroExit': 0,
      'logPath': log.existsSync() ? log.path : '',
    });
  }

  print('Batch audit stamp=$stamp jobs=${jobs.length}');
  for (final j in jobs) {
    final evidence = EvidenceCollector.collect(
      testId: j['testId'] as String,
      scenario: j['scenario'] as String,
      stamp: stamp,
      evidenceDir: j['evidenceDir'] as String,
      extraEvidenceDirs:
          (j['extraEvidenceDirs'] as List?)?.cast<String>() ?? const [],
      maestroExitCode: j['maestroExit'] as int,
      extraLogPaths: [
        if ((j['logPath'] as String?)?.isNotEmpty == true)
          j['logPath'] as String,
      ],
      layer: j['layer'] as String,
      liveId: _readMaestroEnv(root, 'MAESTRO_LIVE_ID'),
    );
    final v = await _runAudit(root, stamp, evidence);
    print('  ${v.testId} => ${v.conclusion}');
  }

  await _writeDeeplinkInventory(root, stamp);
}

Future<void> _reclassifyRegistry(String root) async {
  final registryPath = '$root/tool/test_battery_registry.json';
  final f = File(registryPath);
  if (!f.existsSync()) {
    print('Sem registry');
    exit(1);
  }
  final reg = jsonDecode(await f.readAsString()) as Map;
  final results = (reg['results'] as List?) ?? [];
  final deepFlows = DeeplinkDetector.listDeepLinkFlows('$root/.maestro');

  for (final r in results) {
    if (r is! Map) continue;
    final status = r['status']?.toString() ?? '';
    if (status != 'PASS') continue;
    final id = r['id']?.toString() ?? '';
    final layer = r['layer']?.toString() ?? '';
    if (!layer.contains('UX')) continue;

    // UX PASS → downgrade if likely deeplink-era
    final stamp = r['stamp']?.toString() ?? '';
    final auditFile = File('$root/tool/logs/audit_$stamp/audit_results.json');
    var audited = '';
    if (auditFile.existsSync()) {
      try {
        final audit = jsonDecode(await auditFile.readAsString()) as Map;
        final verdicts = audit['verdicts'] as List? ?? [];
        for (final v in verdicts) {
          if (v is Map && v['testId'] == id) {
            audited = v['conclusion']?.toString() ?? '';
            break;
          }
        }
      } catch (_) {}
    }

    if (audited.isNotEmpty) {
      r['auditConclusion'] = audited;
      r['status'] = _mapAuditToRegistry(audited);
    } else if (status == 'PASS' && layer.contains('UX')) {
      r['auditConclusion'] = 'PASS_COM_AVISO_DEEPLINK';
      r['status'] = 'PASS_COM_AVISO_DEEPLINK';
      final note = r['uxNote']?.toString() ?? '';
      r['uxNote'] =
          '$note | reclassificado: provável deep link (sem auditoria)'.trim();
    }
  }

  reg['updatedAt'] = DateTime.now().toIso8601String();
  reg['auditNote'] =
      'Reclassificado ${DateTime.now().toIso8601String()}; deep link flows: ${deepFlows.length}';
  await f.writeAsString('${const JsonEncoder.withIndent('  ').convert(reg)}\n');

  // Refresh LIVE md via ps script if present
  print('Registry reclassificado: $registryPath');
  print('Deep link flows encontrados: ${deepFlows.length}');
}

String _mapAuditToRegistry(String conclusion) {
  switch (conclusion) {
    case 'PASS':
      return 'PASS';
    case 'PASS_COM_AVISO':
      return 'PASS_COM_AVISO';
    case 'PASS_COM_AVISO_DEEPLINK':
      return 'PASS_COM_AVISO_DEEPLINK';
    default:
      return 'FAIL';
  }
}

Future<void> _writeDeeplinkInventory(String root, String stamp) async {
  final flows = DeeplinkDetector.listDeepLinkFlows('$root/.maestro');
  final out = File('$root/tool/logs/audit_$stamp/deeplink_flows.json');
  out.parent.createSync(recursive: true);
  await out.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({
          'count': flows.length,
          'flows': flows,
        })}\n',
  );
}

Map<String, String?> _parseArgs(List<String> args) {
  final m = <String, String?>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--reclassify-registry') {
      m['reclassify-registry'] = 'true';
    } else if (a.startsWith('--') && i + 1 < args.length) {
      m[a.substring(2)] = args[++i];
    }
  }
  return m;
}

String _readMaestroEnv(String root, String key) {
  final f = File('$root/.maestro/.env');
  if (!f.existsSync()) return '';
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (t.startsWith('$key=')) return t.substring(key.length + 1).trim();
  }
  return '';
}
