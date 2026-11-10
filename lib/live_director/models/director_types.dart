class PreflightIssue {
  const PreflightIssue({
    required this.level,
    required this.code,
    required this.message,
    this.beatId,
  });

  final String level; // error | warning | info
  final String code;
  final String message;
  final String? beatId;
}

class PreflightSummary {
  const PreflightSummary({
    this.totalBeats = 0,
    this.messages = 0,
    this.likes = 0,
    this.enters = 0,
    this.exits = 0,
    this.reservations = 0,
    this.purchases = 0,
    this.raffleJoins = 0,
    this.productsAffected = const [],
    this.stockBefore = const {},
    this.stockAfterProjected = const {},
    this.paymentsProjected = const {},
    this.risks = const [],
  });

  final int totalBeats;
  final int messages;
  final int likes;
  final int enters;
  final int exits;
  final int reservations;
  final int purchases;
  final int raffleJoins;
  final List<String> productsAffected;
  final Map<String, int> stockBefore;
  final Map<String, int> stockAfterProjected;
  final Map<String, String> paymentsProjected;
  final List<String> risks;
}

class PreflightResult {
  const PreflightResult({
    required this.passed,
    required this.issues,
    required this.summary,
    this.validationToken,
    this.checksum,
  });

  final bool passed;
  final List<PreflightIssue> issues;
  final PreflightSummary summary;
  final String? validationToken;
  final String? checksum;

  List<PreflightIssue> get errors =>
      issues.where((i) => i.level == 'error').toList();

  List<PreflightIssue> get warnings =>
      issues.where((i) => i.level == 'warning').toList();
}

class PreviewLine {
  const PreviewLine({
    required this.offsetSec,
    required this.label,
    this.beatId,
    this.confidence = 1.0,
  });

  final int offsetSec;
  final String label;
  final String? beatId;
  final double confidence;
}

class DryRunBeatResult {
  const DryRunBeatResult({
    required this.beatId,
    required this.status,
    this.reason,
  });

  final String beatId;
  final String status; // executable | blocked | skipped
  final String? reason;
}

class DryRunResult {
  const DryRunResult({
    required this.passed,
    required this.beats,
    required this.issues,
  });

  final bool passed;
  final List<DryRunBeatResult> beats;
  final List<PreflightIssue> issues;
}

class HeatMapSegment {
  const HeatMapSegment({
    required this.startMin,
    required this.endMin,
    required this.level, // green | yellow | red
    required this.activityCount,
    required this.label,
  });

  final int startMin;
  final int endMin;
  final String level;
  final int activityCount;
  final String label;
}

class ConsoleBeatState {
  const ConsoleBeatState({
    required this.beatId,
    required this.status,
    this.scheduledAt,
    this.actionLabel,
    this.actorTag,
    this.confidence = 1.0,
    this.reason,
  });

  final String beatId;
  final String status;
  final DateTime? scheduledAt;
  final String? actionLabel;
  final String? actorTag;
  final double confidence;
  final String? reason;
}

class DirectorConsoleState {
  const DirectorConsoleState({
    this.viewersTotal = 0,
    this.botsOnline = 0,
    this.botsSilent = 0,
    this.sellerMode = 'open',
    this.raffleActive = false,
    this.executed = const [],
    this.pending = const [],
    this.delayed = const [],
    this.blocked = const [],
    this.nextBeat,
    this.secondsToNext,
    this.stockByItem = const {},
    this.progressPct = 0,
    this.heatMap = const [],
    this.recentErrors = const [],
    this.killActive = false,
    this.directorPaused = false,
  });

  final int viewersTotal;
  final int botsOnline;
  final int botsSilent;
  final String sellerMode;
  final bool raffleActive;
  final List<ConsoleBeatState> executed;
  final List<ConsoleBeatState> pending;
  final List<ConsoleBeatState> delayed;
  final List<ConsoleBeatState> blocked;
  final ConsoleBeatState? nextBeat;
  final int? secondsToNext;
  final Map<String, int> stockByItem;
  final double progressPct;
  final List<HeatMapSegment> heatMap;
  final List<String> recentErrors;
  final bool killActive;
  final bool directorPaused;
}
