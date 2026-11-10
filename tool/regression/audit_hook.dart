// ignore_for_file: avoid_print
/// Pós-teste: recolhe evidência Maestro/logs e corre audit_runner (Cursor = auditor).
import 'dart:io';

import 'models.dart';

class AuditHookResult {
  AuditHookResult({
    required this.conclusion,
    this.probableCause = '',
    this.auditPath = '',
    this.exitCode = 0,
  });

  final String conclusion;
  final String probableCause;
  final String auditPath;
  final int exitCode;
}

class RegressionAuditHook {
  RegressionAuditHook({required this.repoRoot, required this.stamp});

  final String repoRoot;
  final String stamp;

  DateTime? _maestroSweepAfter;

  String get evidenceRoot => '$repoRoot/tool/logs/regression_$stamp';
  String get auditRoot => '$repoRoot/tool/logs/audit_$stamp';
  String get masterLog => '$evidenceRoot/regression_run.log';

  void markMaestroWindow() {
    _maestroSweepAfter = DateTime.now().subtract(const Duration(seconds: 3));
  }

  bool shouldAudit(ManifestTest test, TestRunResult result) {
    const skip = {
      'manual',
      'skip_config_missing',
      'blocked',
      'not_implemented',
    };
    if (skip.contains(result.status)) return false;
    if (result.durationMs <= 0 &&
        result.message != null &&
        result.message!.contains('Dedupe')) {
      return false;
    }

    final adapter = test.adapter;
    if (adapter == null) return false;

    switch (adapter.type) {
      case 'maestro':
      case 'hybrid':
        return true;
      case 'integration':
      case 'bot':
        return true;
      case 'unit':
        return test.priority == 'P0';
      default:
        return false;
    }
  }

  Future<AuditHookResult?> maybeAudit({
    required ManifestTest test,
    required TestRunResult result,
  }) async {
    if (!shouldAudit(test, result)) return null;

    final testDir = Directory('$evidenceRoot/${test.id}');
    testDir.createSync(recursive: true);

    final runLog = File('${testDir.path}/run.log');
    await runLog.writeAsString(
      [
        'id=${test.id}',
        'status=${result.status}',
        'layers=${result.layersRun.join(",")}',
        'duration_ms=${result.durationMs}',
        if (result.message != null && result.message!.isNotEmpty)
          'message=${result.message}',
      ].join('\n'),
      mode: FileMode.append,
    );

    _appendMasterLog(
      '${test.id} harness=${result.status} layers=${result.layersRun.join(",")}',
    );

    final maestroDirs = _collectMaestroDirsSince(_maestroSweepAfter);
    _maestroSweepAfter = null;

    var evidenceDir = testDir.path;
    if (maestroDirs.isNotEmpty) {
      for (var i = 0; i < maestroDirs.length; i++) {
        final src = Directory(maestroDirs[i]);
        final dest = Directory('${testDir.path}/maestro_${i + 1}');
        await _copyTree(src, dest);
      }
      evidenceDir = '${testDir.path}/maestro_${maestroDirs.length}';
    }

    final layer = _auditLayer(test, result);
    final maestroExit = result.status == 'pass' ? 0 : 1;
    final scenario = test.adapter?.entry ?? test.adapter?.path ?? test.id;

    final args = [
      'run',
      'tool/audit/audit_runner.dart',
      '--test-id',
      test.id,
      '--stamp',
      stamp,
      '--maestro-exit',
      '$maestroExit',
      '--layer',
      layer,
      '--scenario',
      scenario,
      '--evidence-dir',
      evidenceDir,
      '--log-path',
      runLog.path,
    ];

    print('  audit: recolha ${test.id} stamp=$stamp layer=$layer');
    final proc = await Process.run(
      'dart',
      args,
      workingDirectory: repoRoot,
      runInShell: Platform.isWindows,
    );

    final parsed = _parseAuditStdout(proc.stdout.toString());
    final conclusion = parsed.$1.isNotEmpty
        ? parsed.$1
        : (proc.exitCode == 0 ? 'PASS' : 'FAIL');
    final cause = parsed.$2;

    _appendMasterLog(
      '  AUDIT ${test.id} => $conclusion${cause.isNotEmpty ? " ($cause)" : ""}',
    );

    return AuditHookResult(
      conclusion: conclusion,
      probableCause: cause,
      auditPath: auditRoot,
      exitCode: proc.exitCode,
    );
  }

  String _auditLayer(ManifestTest test, TestRunResult result) {
    if (result.layersRun.contains('maestro')) {
      return 'UX+Maestro';
    }
    final t = test.adapter?.type ?? test.layer;
    switch (t) {
      case 'maestro':
        return 'UX+Maestro';
      case 'hybrid':
        return 'UX+BD';
      case 'bot':
        return 'BD+bot';
      case 'integration':
        return 'BD+integration';
      default:
        return test.layer;
    }
  }

  void _appendMasterLog(String line) {
    final f = File(masterLog);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(
      '${DateTime.now().toIso8601String()} $line\n',
      mode: FileMode.append,
    );
  }

  List<String> _collectMaestroDirsSince(DateTime? after) {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    if (home.isEmpty) return const [];

    final root = Directory('$home/.maestro/tests');
    if (!root.existsSync()) return const [];

    final cutoff = after ?? DateTime.now().subtract(const Duration(minutes: 5));
    final hits = <Directory>[];

    for (final ent in root.listSync()) {
      if (ent is! Directory) continue;
      try {
        if (ent.statSync().modified.isAfter(cutoff)) {
          hits.add(ent);
        }
      } catch (_) {}
    }

    hits.sort(
      (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
    );
    return hits.map((d) => d.path).toList();
  }

  Future<void> _copyTree(Directory src, Directory dest) async {
    if (!dest.existsSync()) dest.createSync(recursive: true);
    await for (final ent in src.list(recursive: true)) {
      if (ent is! File) continue;
      final rel = ent.path.substring(src.path.length + 1);
      final out = File('${dest.path}/$rel');
      out.parent.createSync(recursive: true);
      await ent.copy(out.path);
    }
  }

  (String, String) _parseAuditStdout(String stdout) {
    var conclusion = '';
    var cause = '';
    for (final line in stdout.split('\n')) {
      final t = line.trim();
      final m = RegExp(r'^AUDIT\s+A\d+\s+=>\s+(\S+)').firstMatch(t);
      if (m != null) conclusion = m.group(1) ?? '';
      final c = RegExp(r'^\s*causa:\s*(.+)$').firstMatch(t);
      if (c != null) cause = c.group(1)?.trim() ?? '';
    }
    return (conclusion, cause);
  }
}

TestRunResult mergeAuditResult(TestRunResult result, AuditHookResult audit) {
  var status = result.status;
  var message = result.message ?? '';

  if (audit.conclusion == 'FAIL' &&
      (status == 'pass' || status == 'pass_com_aviso')) {
    status = 'fail';
    message = message.isEmpty
        ? 'auditoria Cursor FAIL'
        : '$message | auditoria FAIL';
  } else if (audit.conclusion == 'PASS_COM_AVISO' && status == 'pass') {
    message = message.isEmpty
        ? 'auditoria PASS_COM_AVISO'
        : '$message | auditoria PASS_COM_AVISO';
  }

  if (audit.probableCause.isNotEmpty) {
    message = message.isEmpty
        ? audit.probableCause
        : '$message | ${audit.probableCause}';
  }

  return TestRunResult(
    id: result.id,
    name: result.name,
    status: status,
    layersRun: result.layersRun,
    durationMs: result.durationMs,
    message: message,
    auditConclusion: audit.conclusion,
    auditPath: audit.auditPath,
  );
}
