// ignore_for_file: avoid_print
/// Planos de execução Maestro em cadeia (sessão partilhada, fan-out smoke).
library;

import 'models.dart';
import 'store.dart';

/// O que fazer quando um passo falha.
enum MaestroChainOnFail {
  /// Para a cadeia; IDs restantes ficam `blocked`.
  abortChain,

  /// Regista falha e continua (só se o passo seguinte não depende do estado).
  continueChain,
}

enum MaestroChainLogin {
  none,
  sellerCold,
  sellerWarm,
  buyerCold,
  buyerWarm,
}

enum MaestroChainStepKind {
  /// Flow Maestro normal (subflow sem login).
  flow,

  /// Corrida isolada via [AdapterExecutor] (harness, helper).
  isolated,
}

class MaestroChainStep {
  const MaestroChainStep({
    required this.testIds,
    this.flowPath,
    this.kind = MaestroChainStepKind.flow,
    this.onFail = MaestroChainOnFail.abortChain,
    this.login = MaestroChainLogin.none,
    this.resetHome = false,
    this.setupHooks = const [],
    this.label = '',
    this.adbDeepLink,
  });

  final List<String> testIds;
  final String? flowPath;
  final MaestroChainStepKind kind;
  final MaestroChainOnFail onFail;
  final MaestroChainLogin login;
  final bool resetHome;
  final List<String> setupHooks;
  final String label;
  final String? adbDeepLink;
}

class MaestroChainPlan {
  const MaestroChainPlan({
    required this.id,
    required this.deviceRole,
    required this.driverPort,
    required this.steps,
    this.description = '',
  });

  final String id;
  final String deviceRole;
  final int driverPort;
  final List<MaestroChainStep> steps;
  final String description;

  Set<String> get allTestIds => steps.expand((s) => s.testIds).toSet();
}

class MaestroExecutionPlans {
  static const _prepDedicatedOrder = [
    'A002',
    'A001',
    'A017',
    'A031',
    'A004',
    'A035',
    'A008',
    'A019',
    'A022',
    'A032',
  ];

  static const _prepStepFlows = {
    'A001': '.maestro/subflows/prep_a001_steps.yaml',
    'A002': '.maestro/subflows/prep_a002_steps.yaml',
    'A004': '.maestro/subflows/prep_a004_steps.yaml',
    'A008': '.maestro/subflows/prep_a008_steps.yaml',
    'A017': '.maestro/subflows/prep_a017_steps.yaml',
    'A019': '.maestro/subflows/prep_a019_steps.yaml',
    'A022': '.maestro/subflows/prep_a022_steps.yaml',
    'A031': '.maestro/subflows/prep_a031_steps.yaml',
    'A032': '.maestro/subflows/prep_a032_steps.yaml',
    'A035': '.maestro/subflows/prep_a035_steps.yaml',
  };

  static const _prepAdbDeepLinks = {
    'A017': '/prepararDirecto',
  };

  static const _prepOnFail = {
    'A002': MaestroChainOnFail.abortChain,
    'A001': MaestroChainOnFail.abortChain,
    'A031': MaestroChainOnFail.continueChain,
    'A017': MaestroChainOnFail.continueChain,
    'A004': MaestroChainOnFail.continueChain,
    'A035': MaestroChainOnFail.continueChain,
    'A008': MaestroChainOnFail.continueChain,
    'A019': MaestroChainOnFail.continueChain,
    'A022': MaestroChainOnFail.continueChain,
    'A032': MaestroChainOnFail.continueChain,
  };

  static const _smokeStepFlows = {
    'v1_04_seller_preparar_directo.yaml':
        '.maestro/flows/chains/v1_04_seller_prep_steps.yaml',
    'v1_05_seller_live_studio_smoke.yaml':
        '.maestro/flows/chains/v1_05_seller_studio_steps.yaml',
    'v1_01_login_buyer_home.yaml':
        '.maestro/flows/chains/buyer_home_steps.yaml',
    'cross_surface_cs01_buyer_player.yaml':
        '.maestro/flows/chains/cross_surface_buyer_player_steps.yaml',
    'v1_03_buyer_bag_sheet.yaml':
        '.maestro/flows/chains/v1_03_buyer_bag_steps.yaml',
    'v2_buyer_raffle_bag.yaml':
        '.maestro/flows/chains/v2_buyer_raffle_steps.yaml',
  };

  static const _harnessIds = {'A089', 'A090', 'A094'};
  static const _helperIds = {'A387'};

  /// Constrói cadeias para os IDs Maestro seleccionados.
  static List<MaestroChainPlan> build({
    required Set<String> selectedIds,
    required Map<String, ManifestTest> manifest,
  }) {
    final plans = <MaestroChainPlan>[];
    final remaining = selectedIds.toSet();

    final prepIds =
        _prepDedicatedOrder.where(remaining.contains).toList(growable: false);
    if (prepIds.isNotEmpty) {
      plans.add(_sellerPrepChain(prepIds));
      remaining.removeAll(prepIds);
    }

    for (final entry in _groupByFlow(manifest, remaining).entries) {
      final flow = entry.key;
      final ids = entry.value..sort((a, b) => _idNum(a).compareTo(_idNum(b)));
      remaining.removeAll(ids);

      if (_smokeStepFlows.containsKey(flow)) {
        final role = flow.contains('buyer') || flow.contains('cs01')
            ? 'buyer'
            : 'seller';
        plans.add(
          MaestroChainPlan(
            id: 'smoke_$flow',
            deviceRole: role,
            driverPort: role == 'buyer' ? 7002 : 7001,
            description: 'Smoke partilhado: $flow (${ids.length} IDs)',
            steps: [
              MaestroChainStep(
                testIds: ids,
                flowPath: _smokeStepFlows[flow],
                login: role == 'buyer'
                    ? MaestroChainLogin.buyerWarm
                    : MaestroChainLogin.sellerWarm,
                onFail: MaestroChainOnFail.continueChain,
                label: flow,
              ),
            ],
          ),
        );
      }
    }

    final harness =
        _harnessIds.where(remaining.contains).toList()
          ..sort((a, b) => _idNum(a).compareTo(_idNum(b)));
    if (harness.isNotEmpty) {
      remaining.removeAll(harness);
      plans.add(_harnessChain(harness));
    }

    final helpers =
        _helperIds.where(remaining.contains).toList()
          ..sort((a, b) => _idNum(a).compareTo(_idNum(b)));
    if (helpers.isNotEmpty) {
      remaining.removeAll(helpers);
      plans.add(_helperChain(helpers));
    }

    if (remaining.isNotEmpty) {
      plans.add(_fallbackChain(remaining, manifest));
    }

    return plans;
  }

  static MaestroChainPlan _sellerPrepChain(List<String> prepIds) {
    final steps = <MaestroChainStep>[
      const MaestroChainStep(
        testIds: [],
        login: MaestroChainLogin.sellerCold,
        label: 'login_seller',
      ),
    ];

    for (var i = 0; i < prepIds.length; i++) {
      final id = prepIds[i];
      if (i > 0) {
        steps.add(
          const MaestroChainStep(
            testIds: [],
            flowPath: '.maestro/subflows/nav_seller_home.yaml',
            resetHome: true,
            onFail: MaestroChainOnFail.continueChain,
            label: 'nav_seller_home',
          ),
        );
      }
      steps.add(
        MaestroChainStep(
          testIds: [id],
          flowPath: _prepStepFlows[id],
          onFail: _prepOnFail[id] ?? MaestroChainOnFail.continueChain,
          setupHooks: const [],
          label: 'prep_$id',
          adbDeepLink: _prepAdbDeepLinks[id],
        ),
      );
    }

    return MaestroChainPlan(
      id: 'seller_prep',
      deviceRole: 'seller',
      driverPort: 7001,
      description: 'Prep dedicado A001–A035 (${prepIds.length} passos)',
      steps: steps,
    );
  }

  static MaestroChainPlan _harnessChain(List<String> ids) {
    return MaestroChainPlan(
      id: 'seller_harness',
      deviceRole: 'seller',
      driverPort: 7001,
      description: 'Harness seller (login+adb+assert por ID)',
      steps: [
        for (final id in ids)
          MaestroChainStep(
            testIds: [id],
            kind: MaestroChainStepKind.isolated,
            onFail: MaestroChainOnFail.continueChain,
            label: 'harness_$id',
          ),
      ],
    );
  }

  static MaestroChainPlan _helperChain(List<String> ids) {
    return MaestroChainPlan(
      id: 'buyer_helper',
      deviceRole: 'buyer',
      driverPort: 7002,
      description: 'Helper link inválido',
      steps: [
        for (final id in ids)
          MaestroChainStep(
            testIds: [id],
            kind: MaestroChainStepKind.isolated,
            onFail: MaestroChainOnFail.continueChain,
            label: 'helper_$id',
          ),
      ],
    );
  }

  static MaestroChainPlan _fallbackChain(
    Set<String> ids,
    Map<String, ManifestTest> manifest,
  ) {
    return MaestroChainPlan(
      id: 'maestro_fallback',
      deviceRole: 'seller',
      driverPort: 7001,
      description: 'Flows Maestro sem cadeia dedicada',
      steps: [
        for (final id in ids.toList()
          ..sort((a, b) => _idNum(a).compareTo(_idNum(b))))
          MaestroChainStep(
            testIds: [id],
            kind: MaestroChainStepKind.isolated,
            onFail: MaestroChainOnFail.continueChain,
            label: 'isolated_$id',
          ),
      ],
    );
  }

  static Map<String, List<String>> _groupByFlow(
    Map<String, ManifestTest> manifest,
    Set<String> ids,
  ) {
    final byFlow = <String, List<String>>{};
    for (final id in ids) {
      final entry = manifest[id]?.adapter?.entry ?? '';
      if (entry.isEmpty || _prepStepFlows.containsKey(id)) continue;
      if (_harnessIds.contains(id) || _helperIds.contains(id)) continue;
      (byFlow[entry] ??= []).add(id);
    }
    return byFlow;
  }

  static int _idNum(String id) =>
      int.tryParse(id.replaceFirst('A', '')) ?? 9999;
}

void main() {
  final store = RegressionStore(RegressionPaths('.'));
  final manifest = store.loadManifest(regenerate: false);
  final maestroIds = manifest.values
      .where((t) => t.adapter?.type == 'maestro')
      .map((t) => t.id)
      .toSet();
  final plans = MaestroExecutionPlans.build(
    selectedIds: maestroIds,
    manifest: manifest,
  );
  print('Maestro chain plan (${maestroIds.length} testes → ${plans.length} cadeias)');
  for (final p in plans) {
    print('');
    print('${p.id}: ${p.description} [${p.deviceRole}:${p.driverPort}]');
    for (final s in p.steps) {
      final ids = s.testIds.isEmpty ? '—' : s.testIds.join(',');
      print('  • ${s.label} → $ids (${s.onFail.name})');
    }
  }
}
