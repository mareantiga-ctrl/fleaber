// Motor de auditoria: BD + UI + visual + deep link.
import 'dart:io';

import '../live_ops_staging_client.dart';
import 'bd_stock_snapshot.dart';
import 'deeplink_detector.dart';
import 'evidence_collector.dart';
import 'models.dart';
import 'report_writer.dart';
import 'stock_alignment.dart';
import 'ui_extractor.dart';
import 'visual_heuristics.dart';

class AuditEngine {
  AuditEngine({
    required this.projectRoot,
    required this.client,
    required this.writer,
  });

  final String projectRoot;
  final LiveOpsStagingClient? client;
  final ReportWriter writer;

  Future<AuditVerdict> audit(AuditEvidence evidence) async {
    final bundlePath =
        await EvidenceCollector.persistBundle(evidence, projectRoot);
    final evidenceUsed = <String>[
      'bundle:$bundlePath',
      ...evidence.logPaths.map((p) => 'log:$p'),
      ...evidence.screenshotPaths.map((p) => 'screenshot:$p'),
    ];

    final seller = UiExtractor(surface: 'seller_ui');
    final buyer = UiExtractor(surface: 'buyer_ui');
    final generic = UiExtractor(surface: 'ui');

    for (final p in evidence.commandsJsonPaths) {
      final lower = p.toLowerCase();
      if (lower.contains('buyer')) {
        buyer.extractTextsFromJsonFile(p);
      } else if (lower.contains('seller') || lower.contains('harness')) {
        seller.extractTextsFromJsonFile(p);
      } else {
        generic.extractTextsFromJsonFile(p);
      }
    }

    // Also scan bundle dir for commands JSON only (not logs with stale deeplink refs)
    final bundleDir = Directory(bundlePath);
    if (bundleDir.existsSync()) {
      for (final f in bundleDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.contains('commands-') && f.path.endsWith('.json'))) {
        generic.extractTextsFromJsonFile(f.path);
      }
    }

    final usedDeepLink = (evidence.layer.contains('UX') ||
            evidence.layer.contains('Maestro')) &&
        (DeeplinkDetector.scanFiles(evidence.flowPaths) ||
            DeeplinkDetector.scanFiles(evidence.commandsJsonPaths
                .where((p) => p.toLowerCase().endsWith('.yaml'))
                .toList()) ||
            DeeplinkDetector.scanFiles(evidence.logPaths
                .where((p) {
                  final l = p.toLowerCase();
                  return l.contains('adb') || l.contains('deeplink');
                })
                .toList()));

    final warnings = VisualHeuristics.fromExtractors(
      seller: seller,
      buyer: buyer,
      generic: generic,
      screenshots: evidence.screenshotPaths,
    );

    final failures = <String>[];
    if (evidence.maestroExitCode != 0) {
      failures.add('Maestro exit=${evidence.maestroExitCode}');
    }
    failures.addAll(seller.failedAsserts);
    failures.addAll(buyer.failedAsserts);
    failures.addAll(generic.failedAsserts);

    var bdSnapshots = <QtySnapshot>[];
    var bdPath = '';
    final liveId = evidence.liveId.isNotEmpty
        ? evidence.liveId
        : _readMaestroEnv('MAESTRO_LIVE_ID');

    if (client != null && liveId.isNotEmpty) {
      try {
        bdPath = await BdStockSnapshot(client!).writeSnapshot(
          liveId: liveId,
          outDir: Directory('$bundlePath/bd'),
        );
        evidenceUsed.add('bd:$bdPath');
        final raw = await BdStockSnapshot(client!).capture(liveId: liveId);
        final stockMap = raw['stock_rpc_by_live_item_id'] as Map? ?? {};
        for (final entry in stockMap.entries) {
          if (entry.value is! Map) continue;
          bdSnapshots.add(BdStockSnapshot.fromRpcMap(
            Map<String, dynamic>.from(entry.value as Map),
            source: 'bd_rpc',
            liveItemId: entry.key.toString(),
          ));
        }
      } catch (e) {
        failures.add('BD snapshot falhou: $e');
      }
    }

    final stockMismatches = <StockMismatch>[];
    final needsStock = StockAlignment.requiresStockAudit(
      evidence.testId,
      evidence.scenario,
      evidence.layer,
    );
    if (needsStock && bdSnapshots.isNotEmpty) {
      stockMismatches.addAll(StockAlignment.compare(
        bdSnapshots: bdSnapshots,
        sellerUi: seller.extractQtySnapshots(),
        buyerUi: buyer.extractQtySnapshots(),
        screenshot: _pickStockScreenshot(evidence.screenshotPaths),
        scenario: evidence.scenario.isNotEmpty
            ? evidence.scenario
            : evidence.testId,
        sellerTexts: seller.allTexts,
      ));
    }

    for (final m in stockMismatches) {
      failures.add(
        '${m.field}: BD=${m.expected} vs ${m.sourceB}=${m.found}',
      );
    }

    String conclusion;
    String probableCause = '';
    String validationType = evidence.layer.isNotEmpty
        ? evidence.layer
        : 'ux_maestro';

    if (failures.isNotEmpty || stockMismatches.isNotEmpty) {
      conclusion = 'FAIL';
      probableCause = failures.isNotEmpty
          ? failures.first
          : stockMismatches.first.probableCause;
    } else if (usedDeepLink) {
      conclusion = 'PASS_COM_AVISO_DEEPLINK';
      probableCause =
          'Navegação via deep link — não valida UX real de botões';
      warnings.add(VisualWarning(
        category: 'deeplink_navigation',
        message:
            'Teste usou deep link/adb URI; PASS de navegação não é fiável',
      ));
    } else if (warnings.isNotEmpty) {
      conclusion = 'PASS_COM_AVISO';
    } else if (evidence.maestroExitCode == 0) {
      conclusion = 'PASS';
    } else {
      conclusion = 'FAIL';
      probableCause = 'Sem evidência suficiente e Maestro não OK';
    }

    // Maestro-only pass without screenshots on UX tests = warning minimum
    if (conclusion == 'PASS' &&
        evidence.layer.contains('UX') &&
        evidence.screenshotPaths.isEmpty &&
        evidence.commandsJsonPaths.isEmpty) {
      conclusion = 'PASS_COM_AVISO';
      warnings.add(VisualWarning(
        category: 'missing_evidence',
        message: 'PASS Maestro sem screenshots nem commands JSON para auditar',
      ));
    }

    final verdict = AuditVerdict(
      testId: evidence.testId,
      conclusion: conclusion,
      validationType: validationType,
      evidenceUsed: evidenceUsed,
      screenshotsAnalyzed: evidence.screenshotPaths,
      bdSnapshotPath: bdPath,
      expected: {
        if (bdSnapshots.isNotEmpty) 'bd_stock': bdSnapshots.first.toJson(),
      },
      found: {
        'seller_ui_texts': seller.allTexts.take(30).toList(),
        'buyer_ui_texts': buyer.allTexts.take(30).toList(),
        'seller_qty': seller.extractQtySnapshots().map((s) => s.toJson()).toList(),
        'buyer_qty': buyer.extractQtySnapshots().map((s) => s.toJson()).toList(),
      },
      warnings: warnings,
      failures: failures,
      stockMismatches: stockMismatches,
      maestroExitCode: evidence.maestroExitCode,
      usedDeepLink: usedDeepLink,
      probableCause: probableCause,
      auditedAt: DateTime.now().toUtc().toIso8601String(),
    );

    await writer.appendVerdict(verdict);
    return verdict;
  }

  String _readMaestroEnv(String key) {
    final f = File('$projectRoot/.maestro/.env');
    if (!f.existsSync()) return '';
    for (final line in f.readAsLinesSync()) {
      final t = line.trim();
      if (t.startsWith('$key=')) return t.substring(key.length + 1).trim();
    }
    return '';
  }

  static String _pickStockScreenshot(List<String> paths) {
    if (paths.isEmpty) return '';
    final after = paths.where((p) => p.toLowerCase().contains('after')).toList();
    if (after.isNotEmpty) return after.last;
    return paths.last;
  }
}
