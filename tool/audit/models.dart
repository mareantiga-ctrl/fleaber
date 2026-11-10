// Modelos partilhados da camada de auditoria Cursor.
library;

class AuditEvidence {
  AuditEvidence({
    required this.testId,
    required this.scenario,
    required this.stamp,
    this.maestroExitCode = 0,
    this.logPaths = const [],
    this.screenshotPaths = const [],
    this.commandsJsonPaths = const [],
    this.evidenceDir = '',
    this.liveId = '',
    this.sellerId = '',
    this.flowPaths = const [],
    this.layer = '',
    this.maestroOnlyPass = false,
  });

  final String testId;
  final String scenario;
  final String stamp;
  final int maestroExitCode;
  final List<String> logPaths;
  final List<String> screenshotPaths;
  final List<String> commandsJsonPaths;
  final String evidenceDir;
  final String liveId;
  final String sellerId;
  final List<String> flowPaths;
  final String layer;
  final bool maestroOnlyPass;

  Map<String, dynamic> toJson() => {
        'testId': testId,
        'scenario': scenario,
        'stamp': stamp,
        'maestroExitCode': maestroExitCode,
        'logPaths': logPaths,
        'screenshotPaths': screenshotPaths,
        'commandsJsonPaths': commandsJsonPaths,
        'evidenceDir': evidenceDir,
        'liveId': liveId,
        'sellerId': sellerId,
        'flowPaths': flowPaths,
        'layer': layer,
        'maestroOnlyPass': maestroOnlyPass,
      };
}

class QtySnapshot {
  QtySnapshot({
    this.totalQty,
    this.availableQty,
    this.reservedQty,
    this.soldQty,
    this.blockedQty,
    this.crossReservedQty,
    this.soldConvertedQty,
    this.source = '',
    this.liveItemId = '',
    this.raw = const {},
  });

  final int? totalQty;
  final int? availableQty;
  final int? reservedQty;
  final int? soldQty;
  final int? blockedQty;
  final int? crossReservedQty;
  final int? soldConvertedQty;
  final String source;
  final String liveItemId;
  final Map<String, dynamic> raw;

  Map<String, dynamic> toJson() => {
        'source': source,
        'liveItemId': liveItemId,
        'total_qty': totalQty,
        'available_qty': availableQty,
        'reserved_qty': reservedQty,
        'sold_qty': soldQty,
        'blocked_qty': blockedQty,
        'cross_reserved_qty': crossReservedQty,
        'sold_converted_qty': soldConvertedQty,
        'raw': raw,
      };
}

class StockMismatch {
  StockMismatch({
    required this.field,
    required this.expected,
    required this.found,
    required this.sourceA,
    required this.sourceB,
    this.query = '',
    this.screenshot = '',
    this.probableCause = '',
  });

  final String field;
  final dynamic expected;
  final dynamic found;
  final String sourceA;
  final String sourceB;
  final String query;
  final String screenshot;
  final String probableCause;

  Map<String, dynamic> toJson() => {
        'field': field,
        'expected': expected,
        'found': found,
        'sourceA': sourceA,
        'sourceB': sourceB,
        'query': query,
        'screenshot': screenshot,
        'probableCause': probableCause,
      };
}

class VisualWarning {
  VisualWarning({
    required this.category,
    required this.message,
    this.screenshot = '',
    this.snippet = '',
  });

  final String category;
  final String message;
  final String screenshot;
  final String snippet;

  Map<String, dynamic> toJson() => {
        'category': category,
        'message': message,
        'screenshot': screenshot,
        'snippet': snippet,
      };
}

/// PASS | PASS_COM_AVISO | PASS_COM_AVISO_DEEPLINK | FAIL
class AuditVerdict {
  AuditVerdict({
    required this.testId,
    required this.conclusion,
    required this.validationType,
    required this.evidenceUsed,
    this.screenshotsAnalyzed = const [],
    this.bdSnapshotPath = '',
    this.expected = const {},
    this.found = const {},
    this.warnings = const [],
    this.failures = const [],
    this.stockMismatches = const [],
    this.maestroExitCode = 0,
    this.usedDeepLink = false,
    this.probableCause = '',
    this.auditedAt = '',
  });

  final String testId;
  final String conclusion;
  final String validationType;
  final List<String> evidenceUsed;
  final List<String> screenshotsAnalyzed;
  final String bdSnapshotPath;
  final Map<String, dynamic> expected;
  final Map<String, dynamic> found;
  final List<VisualWarning> warnings;
  final List<String> failures;
  final List<StockMismatch> stockMismatches;
  final int maestroExitCode;
  final bool usedDeepLink;
  final String probableCause;
  final String auditedAt;

  Map<String, dynamic> toJson() => {
        'testId': testId,
        'conclusion': conclusion,
        'validationType': validationType,
        'evidenceUsed': evidenceUsed,
        'screenshotsAnalyzed': screenshotsAnalyzed,
        'bdSnapshotPath': bdSnapshotPath,
        'expected': expected,
        'found': found,
        'warnings': warnings.map((w) => w.toJson()).toList(),
        'failures': failures,
        'stockMismatches': stockMismatches.map((m) => m.toJson()).toList(),
        'maestroExitCode': maestroExitCode,
        'usedDeepLink': usedDeepLink,
        'probableCause': probableCause,
        'auditedAt': auditedAt,
      };
}
