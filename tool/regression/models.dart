// ignore_for_file: avoid_print
/// Modelos partilhados do Fleaber Regression Runner.
library;

class ManifestTest {
  ManifestTest({
    required this.id,
    required this.title,
    required this.area,
    required this.priority,
    required this.layer,
    required this.status,
    this.adapter,
    this.dependencies = const [],
    this.riskEdges = const [],
    this.sourceDoc = '',
    this.components = const [],
  });

  final String id;
  final String title;
  final String area;
  final String priority;
  final String layer;
  final String status;
  final RegressionAdapter? adapter;
  final List<String> dependencies;
  final List<String> riskEdges;
  final String sourceDoc;
  final List<String> components;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'area': area,
        'priority': priority,
        'layer': layer,
        'status': status,
        'adapter': adapter?.toJson(),
        'dependencies': dependencies,
        'risk_edges': riskEdges,
        'source_doc': sourceDoc,
        'components': components,
      };

  factory ManifestTest.fromJson(Map<String, dynamic> json) {
    final adapterRaw = json['adapter'];
    return ManifestTest(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      area: json['area']?.toString() ?? 'unknown',
      priority: json['priority']?.toString() ?? 'P2',
      layer: json['layer']?.toString() ?? 'not_implemented',
      status: json['status']?.toString() ?? 'not_implemented',
      adapter: adapterRaw is Map<String, dynamic>
          ? RegressionAdapter.fromJson(adapterRaw)
          : null,
      dependencies: _stringList(json['dependencies']),
      riskEdges: _stringList(json['risk_edges']),
      sourceDoc: json['source_doc']?.toString() ?? '',
      components: _stringList(json['components']),
    );
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }
}

class RegressionAdapter {
  RegressionAdapter({
    required this.type,
    required this.path,
    this.entry,
    this.args = const [],
    this.requiresLiveId = false,
    this.requiresStaging = false,
    this.requiresMaestro = false,
    this.requiresGuided = false,
    this.dedupeKey,
    this.steps = const [],
  });

  final String type;
  final String path;
  final String? entry;
  final List<String> args;
  final bool requiresLiveId;
  final bool requiresStaging;
  final bool requiresMaestro;
  final bool requiresGuided;
  final String? dedupeKey;
  final List<HybridStep> steps;

  Map<String, dynamic> toJson() => {
        'type': type,
        'path': path,
        if (entry != null) 'entry': entry,
        if (args.isNotEmpty) 'args': args,
        if (requiresLiveId) 'requires_live_id': true,
        if (requiresStaging) 'requires_staging': true,
        if (requiresMaestro) 'requires_maestro': true,
        if (requiresGuided) 'requires_guided': true,
        if (dedupeKey != null) 'dedupe_key': dedupeKey,
        if (steps.isNotEmpty) 'steps': steps.map((s) => s.toJson()).toList(),
      };

  factory RegressionAdapter.fromJson(Map<String, dynamic> json) {
    final stepsRaw = json['steps'];
    return RegressionAdapter(
      type: json['type']?.toString() ?? 'stub',
      path: json['path']?.toString() ?? '',
      entry: json['entry']?.toString(),
      args: ManifestTest._stringList(json['args']),
      requiresLiveId: json['requires_live_id'] == true,
      requiresStaging: json['requires_staging'] == true,
      requiresMaestro: json['requires_maestro'] == true,
      requiresGuided: json['requires_guided'] == true,
      dedupeKey: json['dedupe_key']?.toString(),
      steps: stepsRaw is List
          ? stepsRaw
              .whereType<Map>()
              .map((e) => HybridStep.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

class HybridStep {
  const HybridStep({required this.type, this.scenario, this.flow, this.path});

  final String type;
  final String? scenario;
  final String? flow;
  final String? path;

  Map<String, dynamic> toJson() => {
        'type': type,
        if (scenario != null) 'scenario': scenario,
        if (flow != null) 'flow': flow,
        if (path != null) 'path': path,
      };

  factory HybridStep.fromJson(Map<String, dynamic> json) {
    return HybridStep(
      type: json['type']?.toString() ?? '',
      scenario: json['scenario']?.toString(),
      flow: json['flow']?.toString(),
      path: json['path']?.toString(),
    );
  }
}

class TestState {
  TestState({
    required this.status,
    this.lastRun,
    this.message,
    this.lastDurationMs,
  });

  String status;
  String? lastRun;
  String? message;
  int? lastDurationMs;

  Map<String, dynamic> toJson() => {
        'status': status,
        'last_run': lastRun,
        'message': message,
        'last_duration_ms': lastDurationMs,
      };

  factory TestState.fromJson(Map<String, dynamic> json) {
    return TestState(
      status: json['status']?.toString() ?? 'not_implemented',
      lastRun: json['last_run']?.toString(),
      message: json['message']?.toString(),
      lastDurationMs: json['last_duration_ms'] as int?,
    );
  }
}

class TestRunResult {
  TestRunResult({
    required this.id,
    required this.name,
    required this.status,
    this.layersRun = const [],
    this.durationMs = 0,
    this.message,
    this.auditConclusion,
    this.auditPath,
  });

  final String id;
  final String name;
  final String status;
  final List<String> layersRun;
  final int durationMs;
  final String? message;
  final String? auditConclusion;
  final String? auditPath;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status,
        'layers_run': layersRun,
        'duration_ms': durationMs,
        'message': message,
        if (auditConclusion != null) 'audit_conclusion': auditConclusion,
        if (auditPath != null) 'audit_path': auditPath,
      };
}

class RunnerOptions {
  RunnerOptions({
    this.full = false,
    this.failedOnly = false,
    this.retestRequired = false,
    this.range,
    this.priority,
    this.area,
    this.id,
    this.recordManual,
    this.suggestRetestChanged,
    this.regenerateManifest = false,
    this.selfTest = false,
    this.guided = false,
    this.skipAudit = false,
    this.maestroChains = true,
    this.repoRoot,
  });

  final bool full;
  final bool failedOnly;
  final bool retestRequired;
  final bool skipAudit;
  final bool maestroChains;
  final String? range;
  final String? priority;
  final String? area;
  final String? id;
  final String? recordManual;
  final String? suggestRetestChanged;
  final bool regenerateManifest;
  final bool selfTest;
  final bool guided;
  final String? repoRoot;
}
