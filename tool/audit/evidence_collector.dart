// Recolhe evidência de uma pasta de teste (screenshots, logs, JSON).
import 'dart:convert';
import 'dart:io';

import 'models.dart';

class EvidenceCollector {
  static AuditEvidence collect({
    required String testId,
    required String scenario,
    required String stamp,
    required String evidenceDir,
    List<String> extraEvidenceDirs = const [],
    int maestroExitCode = 0,
    List<String> extraLogPaths = const [],
    List<String> flowPaths = const [],
    String layer = '',
    String liveId = '',
    String sellerId = '',
  }) {
    final dirs = <String>[
      if (evidenceDir.isNotEmpty) evidenceDir,
      ...extraEvidenceDirs.where((d) => d.isNotEmpty),
    ];
    final logs = <String>[...extraLogPaths];
    final shots = <String>[];
    final commands = <String>[];

    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      for (final ent in dir.listSync(recursive: true)) {
        if (ent is! File) continue;
        final p = ent.path;
        final lower = p.toLowerCase();
        if (lower.endsWith('.png') || lower.endsWith('.jpg')) {
          shots.add(p);
        } else if (lower.contains('commands-') && lower.endsWith('.json')) {
          commands.add(p);
        } else if (lower.endsWith('.log') || lower.endsWith('.txt')) {
          logs.add(p);
        }
      }
    }

    return AuditEvidence(
      testId: testId,
      scenario: scenario,
      stamp: stamp,
      maestroExitCode: maestroExitCode,
      logPaths: logs,
      screenshotPaths: shots,
      commandsJsonPaths: commands,
      evidenceDir: evidenceDir,
      liveId: liveId,
      sellerId: sellerId,
      flowPaths: flowPaths,
      layer: layer,
      maestroOnlyPass: maestroExitCode == 0,
    );
  }

  static String bundleDir(String root, String stamp, String testId) {
    return '$root/tool/logs/audit_$stamp/$testId';
  }

  static Future<String> persistBundle(
    AuditEvidence evidence,
    String projectRoot,
  ) async {
    final out = Directory(
      bundleDir(projectRoot, evidence.stamp, evidence.testId),
    );
    out.createSync(recursive: true);

    final meta = File('${out.path}/evidence_manifest.json');
    await meta.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(evidence.toJson())}\n',
    );

    for (final src in evidence.screenshotPaths) {
      final f = File(src);
      if (!f.existsSync()) continue;
      final dest = File('${out.path}/${f.uri.pathSegments.last}');
      await f.copy(dest.path);
    }
    for (final src in evidence.commandsJsonPaths) {
      final f = File(src);
      if (!f.existsSync()) continue;
      final dest = File('${out.path}/${f.uri.pathSegments.last}');
      await f.copy(dest.path);
    }
    for (final src in evidence.logPaths) {
      final f = File(src);
      if (!f.existsSync()) continue;
      final dest = File('${out.path}/${f.uri.pathSegments.last}');
      if (!dest.existsSync()) await f.copy(dest.path);
    }
    return out.path;
  }
}
