// ignore_for_file: avoid_print
import 'models.dart';
import 'automation_policy.dart';

/// Mapeamento automático A### → adapter quando não há override explícito.
class AdapterAutoMapper {
  static RegressionAdapter map(ManifestTest test) {
    if (isGuidedCheckpoint(test.id)) {
      return _guided(test);
    }
    if (isManualCheckpoint(test.id)) {
      return _manual(test);
    }

    switch (test.layer) {
      case 'unit':
        return _unitFor(test);
      case 'integration':
        return _integrationFor(test);
      case 'bot':
        return _botFor(test);
      case 'maestro':
        return _maestroFor(test);
      case 'hybrid':
        return _hybridFor(test);
      case 'manual':
        return _automateFormerManual(test);
      default:
        return _fallbackFor(test);
    }
  }

  /// Docs marcados «Manual» passam a ter robô (Maestro/bot/dados) salvo allowlist.
  static RegressionAdapter _automateFormerManual(ManifestTest test) {
    if (test.area == 'prep') return _maestroFor(test);
    if (test.area == 'publish') return _maestroFor(test);
    return _fallbackFor(test);
  }

  static bool isAutomatedType(String type) {
    return const {'unit', 'integration', 'bot', 'maestro', 'hybrid'}.contains(type);
  }

  static bool _needsGuided(ManifestTest test) => isGuidedCheckpoint(test.id);

  static RegressionAdapter _manual(ManifestTest test) => RegressionAdapter(
        type: 'manual_checkpoint',
        path: test.sourceDoc,
        entry: 'Validação manual documentada',
        dedupeKey: 'manual:${test.area}',
      );

  static RegressionAdapter _guided(ManifestTest test) => RegressionAdapter(
        type: 'guided_checkpoint',
        path: test.sourceDoc,
        entry: _guidedPrompt(test),
        requiresGuided: true,
        dedupeKey: 'guided:${test.area}:${test.id}',
      );

  static String _guidedPrompt(ManifestTest test) {
    return switch (test.area) {
      'publish' => 'Inicia/prepara directo; confirma publish/Mux; ENTER=pass',
      'checkout' => 'Abre checkout/Stripe sandbox; ENTER=pass',
      'buyer_player' => 'Confirma player comprador; ENTER=pass',
      _ => 'Passos manuais: ${test.title}; ENTER=pass',
    };
  }

  static RegressionAdapter _unitFor(ManifestTest test) {
    final file = _unitFile(test.area);
    return RegressionAdapter(
      type: 'unit',
      path: file,
      entry: _unitNameHint(test),
      dedupeKey: 'auto:unit:$file',
    );
  }

  static String _unitFile(String area) => switch (area) {
        'prep' => 'test/live_ref_lineage_preview_service_test.dart',
        'publish' => 'test/live_start_open_reservations_service_test.dart',
        'seller_ops' || 'catalog' || 'buyer_player' || 'sync' =>
          'test/live_reservation_queue_service_test.dart',
        'checkout' => 'test/live_item_price_gate_test.dart',
        'payments' => 'test/fee_calculator_test.dart',
        'raffle' => 'test/live_raffle_service_test.dart',
        'messages' => 'test/live_public_chat_line_test.dart',
        'gravado' || 'cross_pool' || 'errors' => 'test/order_status_test.dart',
        'marketplace' => 'test/live_ref_lineage_preview_service_test.dart',
        'helpers' => 'test/live_reservation_queue_service_test.dart',
        _ => 'test/widget_test.dart',
      };

  static String? _unitNameHint(ManifestTest test) {
    final t = test.title.toLowerCase();
    if (test.area != 'messages') return null;
    if (t.contains('reserva')) return 'reserva';
    if (t.contains('aceite')) return 'aceite';
    if (t.contains('compra') || t.contains('comprou')) return 'compra';
    if (t.contains('preço')) return 'preço';
    if (t.contains('gorjeta')) return 'gorjeta';
    if (t.contains('esgot')) return 'esgotado';
    if (t.contains('erp') || t.contains('compact')) return 'compactFromBody';
    return null;
  }

  static RegressionAdapter _integrationFor(ManifestTest test) {
    final scenario = _integrationScenario(test);
    return RegressionAdapter(
      type: 'integration',
      path: 'tool/regression_integration.dart',
      entry: scenario,
      requiresStaging: true,
      dedupeKey: 'auto:integration:$scenario',
    );
  }

  static String _integrationScenario(ManifestTest test) {
    final n = int.tryParse(test.id.replaceFirst('A', '')) ?? 0;
    final t = test.title.toLowerCase();

    if (test.area == 'cross_pool' || (n >= 340 && n <= 349)) {
      if (t.contains('blocked')) return 'blocked_qty';
      if (t.contains('cross') && t.contains('reserv')) return 'cross_reserved';
      if (t.contains('product_id')) return 'cross_pool_product_sold';
      if (t.contains('dedup') || t.contains('órfão')) return 'cross_pool_sold_dedup';
      if (t.contains('logical') || t.contains('linhagem')) return 'logical_item_inherit';
      return 'cross_pool_rr1';
    }

    if (test.area == 'checkout' || test.area == 'payments' || (n >= 190 && n <= 249)) {
      if (t.contains('cancel') || t.contains('bag_removed')) return 'cancel';
      if (t.contains('reconcile') || t.contains('stripe') || t.contains('convert')) {
        return 'reconcile';
      }
      if (t.contains('bag') || t.contains('settle')) return 'bag_edge';
      if (t.contains('preço') || t.contains('price') || t.contains('gate')) {
        return 'price_gate_staging';
      }
      return 'reconcile';
    }

    if (test.area == 'prep' || n <= 49) {
      if (t.contains('linhagem') || t.contains('histórico')) return 'logical_item_lineage';
      return 'logical_item_inherit';
    }

    if (test.area == 'gravado' || test.area == 'marketplace' || (n >= 295 && n <= 369)) {
      if (t.contains('marketplace')) return 'marketplace_bridge';
      if (t.contains('gravado') || t.contains('vod')) return 'gravado_sold';
      return 'cross_pool_product_sold';
    }

    if (test.area == 'seller_ops' || test.area == 'catalog') {
      if (t.contains('aceit')) return 'verify_accepted';
      if (t.contains('reserv')) return 'reservations_pending';
      return 'stock';
    }

    if (test.area == 'raffle') return 'verify_raffle_join';
    if (test.area == 'messages') return 'chat_messages_db';
    if (test.area == 'helpers') return 'helper_seller_exists';
    if (test.area == 'sync') return 'reconcile_idempotent';
    if (test.area == 'errors') return 'reservations_pending';
    if (test.area == 'publish') return 'draft_live_fixture';
    return 'stock';
  }

  static RegressionAdapter _botFor(ManifestTest test) {
    final scenario = _botScenario(test);
    return RegressionAdapter(
      type: 'bot',
      path: 'tool/fleaber_bot_simulator.dart',
      entry: scenario,
      args: _botArgs(scenario),
      requiresLiveId: true,
      requiresStaging: true,
      dedupeKey: 'auto:bot:$scenario',
    );
  }

  static String _botScenario(ManifestTest test) {
    final t = test.title.toLowerCase();
    if (test.area == 'messages' || t.contains('chat')) return 'chat';
    if (test.area == 'raffle' || t.contains('rifa')) return 'raffles';
    if (t.contains('follow') || t.contains('seguir')) return 'follows';
    if (t.contains('viewer') || t.contains('espectador')) return 'viewers';
    if (t.contains('preço') || t.contains('price')) return 'price_pending';
    if (test.area == 'errors' || test.area == 'sync') return 'full';
    if (test.area == 'publish') return 'viewers';
    return 'reservations';
  }

  static List<String> _botArgs(String scenario) => [
        '--bots',
        switch (scenario) {
          'full' => '15',
          'viewers' => '20',
          'chat' => '5',
          'price_pending' => '5',
          _ => '10',
        },
        '--duration',
        '30s',
        '--cleanup',
      ];

  static RegressionAdapter _maestroFor(ManifestTest test) {
    final flow = _maestroFlow(test);
    return RegressionAdapter(
      type: 'maestro',
      path: flow.startsWith('../') ? flow : '.maestro/flows/$flow',
      entry: flow,
      requiresMaestro: true,
      requiresStaging: true,
      requiresGuided: _needsGuided(test),
      dedupeKey: 'auto:maestro:${test.id}',
    );
  }

  static const _prepMaestroFlows = {
    'A001': 'prep/a001_sheet_novo_direto.yaml',
    'A002': 'prep/a002_empty_catalog.yaml',
    'A004': 'prep/a004_ref_l1.yaml',
    'A008': 'prep/a008_lineage_cancel.yaml',
    'A019': 'prep/a019_to_criar.yaml',
    'A022': 'prep/a022_back_nav.yaml',
    'A031': 'prep/a031_tabs.yaml',
    'A032': 'prep/a032_title_criar.yaml',
    'A035': 'prep/a035_remove_ref.yaml',
  };

  static String _maestroFlow(ManifestTest test) {
    final prepFlow = _prepMaestroFlows[test.id];
    if (prepFlow != null) return prepFlow;

    final n = int.tryParse(test.id.replaceFirst('A', '')) ?? 0;
    final t = test.title.toLowerCase();

    if (test.area == 'prep' || (n >= 1 && n <= 49)) {
      return 'v1_04_seller_preparar_directo.yaml';
    }
    if (test.area == 'publish' || (n >= 50 && n <= 79)) {
      return 'v1_05_seller_live_studio_smoke.yaml';
    }
    if (t.contains('cancel') && t.contains('saco')) {
      return 'doc_04_buyer_cancel_bag.yaml';
    }
    if (test.area == 'raffle' || t.contains('rifa')) {
      return 'v2_buyer_raffle_bag.yaml';
    }
    if (test.area == 'catalog' ||
        t.contains('stock') ||
        t.contains('catálogo') ||
        t.contains('catalogo')) {
      return 'v2_seller_automation_chain.yaml';
    }
    if (t.contains('aceitar') ||
        test.area == 'seller_ops' ||
        t.contains('operação') ||
        t.contains('operacao')) {
      return 'v2_seller_automation_chain.yaml';
    }
    if (test.area == 'checkout' || t.contains('saco') || t.contains('pagar')) {
      return 'v1_03_buyer_bag_sheet.yaml';
    }
    if (test.area == 'buyer_player') {
      return 'cross_surface_cs01_buyer_player.yaml';
    }
    if (test.area == 'helpers') return 'open_seller_studio_nav.yaml';
    return 'v1_01_login_buyer_home.yaml';
  }

  static RegressionAdapter _hybridFor(ManifestTest test) {
    final steps = _hybridSteps(test);
    return RegressionAdapter(
      type: 'hybrid',
      path: 'tool/regression/hybrid_runner.dart',
      entry: 'auto:${test.area}',
      requiresLiveId: true,
      requiresStaging: true,
      requiresMaestro: steps.any((s) => s.type == 'maestro'),
      requiresGuided: false,
      dedupeKey: 'auto:hybrid:${test.area}',
      steps: steps,
    );
  }

  static List<HybridStep> _hybridSteps(ManifestTest test) => switch (test.area) {
        'checkout' || 'seller_ops' => [
            const HybridStep(type: 'bot', scenario: 'reservations'),
            const HybridStep(type: 'maestro', flow: 'v2_seller_automation_chain.yaml'),
            const HybridStep(type: 'integration', scenario: 'verify_accepted'),
            const HybridStep(type: 'maestro', flow: 'v1_03_buyer_bag_sheet.yaml'),
          ],
        'raffle' => [
            const HybridStep(type: 'bot', scenario: 'raffles'),
            const HybridStep(type: 'maestro', flow: 'v2_buyer_raffle_bag.yaml'),
            const HybridStep(type: 'integration', scenario: 'verify_raffle_join'),
          ],
        'cross_pool' || 'marketplace' || 'gravado' => [
            const HybridStep(type: 'integration', scenario: 'cross_pool_rr1'),
            const HybridStep(type: 'bot', scenario: 'reservations'),
            const HybridStep(type: 'integration', scenario: 'cross_reserved'),
          ],
        'messages' => [
            const HybridStep(type: 'bot', scenario: 'chat'),
            const HybridStep(type: 'integration', scenario: 'chat_messages_db'),
          ],
        _ => [
            const HybridStep(type: 'bot', scenario: 'reservations'),
            const HybridStep(type: 'integration', scenario: 'stock'),
          ],
      };

  static RegressionAdapter _fallbackFor(ManifestTest test) {
    final n = int.tryParse(test.id.replaceFirst('A', '')) ?? 0;
    if (test.area == 'prep' || (n >= 1 && n <= 49)) {
      return _maestroFor(test);
    }
    if (test.area == 'publish' || (n >= 50 && n <= 79)) {
      return _maestroFor(test);
    }
    if (test.priority == 'P0' || test.priority == 'P1') {
      if (const {'checkout', 'payments', 'cross_pool', 'seller_ops', 'catalog'}
          .contains(test.area)) {
        return _integrationFor(test);
      }
      if (const {'buyer_player', 'messages', 'raffle'}.contains(test.area)) {
        return _botFor(test);
      }
    }
    if (test.priority == 'P2') return _unitFor(test);
    return _unitFor(test);
  }
}

class AdapterCoverageStats {
  AdapterCoverageStats({
    required this.total,
    required this.automated,
    required this.manual,
    required this.guided,
    required this.notImplemented,
    required this.p0Total,
    required this.p0Automated,
    required this.p0Gaps,
  });

  final int total;
  final int automated;
  final int manual;
  final int guided;
  final int notImplemented;
  final int p0Total;
  final int p0Automated;
  final List<String> p0Gaps;
}

AdapterCoverageStats computeCoverage(Map<String, ManifestTest> manifest) {
  var automated = 0, manual = 0, guided = 0, notImpl = 0;
  var p0Total = 0, p0Auto = 0;
  final p0Gaps = <String>[];

  for (final t in manifest.values) {
    final a = t.adapter;
    if (a == null) {
      notImpl++;
      if (t.priority == 'P0') {
        p0Total++;
        p0Gaps.add('${t.id} sem adapter');
      }
      continue;
    }
    if (a.type == 'manual_checkpoint') {
      manual++;
    } else if (a.type == 'guided_checkpoint') {
      guided++;
    } else if (AdapterAutoMapper.isAutomatedType(a.type)) {
      automated++;
    }
    if (t.priority == 'P0') {
      p0Total++;
      if (a.type == 'manual_checkpoint' ||
          a.type == 'guided_checkpoint' ||
          !AdapterAutoMapper.isAutomatedType(a.type)) {
        p0Gaps.add('${t.id} [${a.type}] ${t.title}');
      } else {
        p0Auto++;
      }
    }
  }

  return AdapterCoverageStats(
    total: manifest.length,
    automated: automated,
    manual: manual,
    guided: guided,
    notImplemented: notImpl,
    p0Total: p0Total,
    p0Automated: p0Auto,
    p0Gaps: p0Gaps,
  );
}
