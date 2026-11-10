// ignore_for_file: avoid_print
import 'adapter_auto_mapper.dart';
import 'models.dart';

/// Overrides explícitos A### → adapter (prioridade sobre auto-mapper).
final Map<String, RegressionAdapter> adapterRegistryOverrides = {
  ..._unitAdapters,
  ..._integrationAdapters,
  ..._botAdapters,
  ..._maestroAdapters,
  ..._hybridAdapters,
};

/// Registry completo: overrides + auto-map para cada A### do manifest.
Map<String, RegressionAdapter> buildFullAdapterRegistry(Map<String, ManifestTest> manifest) {
  final out = <String, RegressionAdapter>{};
  for (final test in manifest.values) {
    out[test.id] = adapterRegistryOverrides[test.id] ?? AdapterAutoMapper.map(test);
  }
  return out;
}

ManifestTest applyAdapterRegistry(ManifestTest test) {
  final adapter = adapterRegistryOverrides[test.id] ?? AdapterAutoMapper.map(test);

  final layer = switch (adapter.type) {
    'unit' => 'unit',
    'integration' => 'integration',
    'bot' => 'bot',
    'maestro' => 'maestro',
    'hybrid' => 'hybrid',
    'manual_checkpoint' => 'manual',
    'guided_checkpoint' => 'manual',
    _ => test.layer,
  };

  final status = switch (adapter.type) {
    'manual_checkpoint' => 'manual',
    _ => 'automated',
  };

  return ManifestTest(
    id: test.id,
    title: test.title,
    area: test.area,
    priority: test.priority,
    layer: layer,
    status: status,
    adapter: adapter,
    dependencies: test.dependencies,
    riskEdges: test.riskEdges,
    sourceDoc: test.sourceDoc,
    components: test.components,
  );
}

Map<String, ManifestTest> applyRegistryToManifest(Map<String, ManifestTest> manifest) {
  return manifest.map((k, v) => MapEntry(k, applyAdapterRegistry(v)));
}

int countExplicitOverrides() => adapterRegistryOverrides.length;

Map<String, RegressionAdapter> get adapterRegistry => adapterRegistryOverrides;

// ─── Unit overrides ─────────────────────────────────────────────────────────

RegressionAdapter _u(
  String path, {
  String? name,
  String? dedupe,
}) =>
    RegressionAdapter(
      type: 'unit',
      path: path,
      entry: name,
      dedupeKey: dedupe ?? path,
    );

final Map<String, RegressionAdapter> _unitAdapters = {
  'A005': _u('test/live_ref_lineage_sheet_test.dart'),
  'A016': _u('test/live_ref_lineage_preview_service_test.dart', dedupe: 'unit:lineage_preview'),
  'A027': _u('test/live_ref_lineage_preview_service_test.dart', dedupe: 'unit:lineage_preview'),
  'A023': _u('test/live_ref_lineage_preview_service_test.dart', dedupe: 'unit:lineage_preview'),
  'A046': _u('test/live_item_price_gate_test.dart', dedupe: 'unit:price_gate'),
  'A047': _u('test/live_item_price_gate_test.dart', dedupe: 'unit:price_gate'),
  'A049': _u('test/live_item_price_gate_test.dart', dedupe: 'unit:price_gate'),
  'A055': _u('test/live_start_open_reservations_service_test.dart', dedupe: 'unit:open_res'),
  'A056': _u('test/live_start_open_reservations_service_test.dart', dedupe: 'unit:open_res'),
  'A081': _u('test/live_reservation_queue_service_test.dart', dedupe: 'unit:res_queue'),
  'A082': _u('test/live_reservation_queue_service_test.dart', dedupe: 'unit:res_queue'),
  'A083': _u('test/live_reservation_queue_service_test.dart', dedupe: 'unit:res_queue'),
  'A088': _u('test/live_reservation_queue_service_test.dart', dedupe: 'unit:res_queue'),
  'A097': _u('test/live_reservation_queue_service_test.dart', dedupe: 'unit:res_queue'),
  'A126': _u('test/live_reservation_queue_service_test.dart', dedupe: 'unit:res_queue'),
  'A128': _u('test/live_public_chat_line_test.dart', dedupe: 'unit:public_chat'),
  'A166': _u('test/live_checkout_fees_test.dart', dedupe: 'unit:checkout_fees'),
  'A167': _u('test/live_checkout_fees_test.dart', dedupe: 'unit:checkout_fees'),
  'A194': _u('test/order_status_test.dart', name: 'variantes cancelado', dedupe: 'unit:order_status'),
  'A199': _u('test/live_checkout_fees_test.dart', dedupe: 'unit:checkout_fees'),
  'A201': _u('test/fee_calculator_test.dart', dedupe: 'unit:fee_calc'),
  'A202': _u('test/live_item_price_gate_test.dart', dedupe: 'unit:price_gate'),
  'A214': _u('test/fee_calculator_test.dart', dedupe: 'unit:fee_calc'),
  'A227': _u('test/live_item_price_gate_test.dart', dedupe: 'unit:price_gate'),
  // Mensagens A280–A294 + A307/A309
  'A280': _u('test/live_public_chat_line_test.dart', name: 'reserva mantém', dedupe: 'unit:chat:A280'),
  'A281': _u('test/live_public_chat_line_test.dart', name: 'reserva aceite pública', dedupe: 'unit:chat:A281'),
  'A282': _u('test/live_public_chat_line_test.dart', name: 'compra mantém', dedupe: 'unit:chat:A282'),
  'A283': _u('test/live_public_chat_line_test.dart', name: 'preço definido', dedupe: 'unit:chat:A283'),
  'A284': _u('test/live_public_chat_line_test.dart', name: 'última unidade', dedupe: 'unit:chat:A284'),
  'A285': _u('test/live_public_chat_line_test.dart', name: 'esgotado', dedupe: 'unit:chat:A285'),
  'A286': _u('test/live_public_chat_line_test.dart', name: 'gorjeta com nome', dedupe: 'unit:chat:A286'),
  'A287': _u('test/live_public_chat_line_test.dart', name: 'cancelamento', dedupe: 'unit:chat:A287'),
  'A288': _u('test/live_public_chat_line_test.dart', name: 'rejeição vendedora', dedupe: 'unit:chat:A288'),
  'A289': _u('test/live_public_chat_line_test.dart', name: 'dedupe compra', dedupe: 'unit:chat:A289'),
  'A290': _u('test/live_public_chat_line_test.dart', name: 'prazo 5 dias', dedupe: 'unit:chat:A290'),
  'A292': _u('test/live_public_chat_line_test.dart', name: 'adicionou ao saco', dedupe: 'unit:chat:A292'),
  'A293': _u('test/live_public_chat_line_test.dart', name: 'adicionou ao saco', dedupe: 'unit:chat:A293'),
  'A294': _u('test/live_public_chat_line_test.dart', name: 'pedido acima stock', dedupe: 'unit:chat:A294'),
  'A307': _u('test/live_public_chat_line_test.dart', name: 'compra com preço', dedupe: 'unit:chat:A307'),
  'A309': _u('test/live_public_chat_line_test.dart', name: 'compactFromBody', dedupe: 'unit:chat:A309'),
  // Rifas unit
  'A250': _u('test/live_raffle_service_test.dart', name: 'rifa activa', dedupe: 'unit:raffle:A250'),
  'A251': _u('test/live_raffle_service_test.dart', name: 'bonus flags', dedupe: 'unit:raffle:A251'),
  'A252': _u('test/live_raffle_service_test.dart', name: 'leaderboard', dedupe: 'unit:raffle:A252'),
  'A253': _u('test/live_raffle_service_test.dart', name: 'mm:ss', dedupe: 'unit:raffle:A253'),
  'A254': _u('test/live_raffle_service_test.dart', name: 'horas quando', dedupe: 'unit:raffle:A254'),
  'A255': _u('test/live_raffle_service_test.dart', name: 'sem rifa', dedupe: 'unit:raffle:A255'),
  'A256': _u('test/live_raffle_service_test.dart', name: 'rifa sem timer', dedupe: 'unit:raffle:A256'),
  'A257': _u('test/live_raffle_service_test.dart', name: 'ok com duplicate', dedupe: 'unit:raffle:A257'),
  'A278': _u('test/live_raffle_service_test.dart', dedupe: 'unit:raffle:full'),
};

// ─── Integration (staging BD/RPC) ─────────────────────────────────────────

RegressionAdapter _i(String scenario, {String? dedupe}) => RegressionAdapter(
      type: 'integration',
      path: 'tool/regression_integration.dart',
      entry: scenario,
      requiresStaging: true,
      dedupeKey: dedupe ?? 'integration:$scenario',
    );

final Map<String, RegressionAdapter> _integrationAdapters = {
  'A144': _i('stock'),
  'A198': _i('bag_edge'),
  'A206': _i('reconcile'),
  'A208': _i('bag_edge'),
  'A209': _i('reconcile'),
  'A230': _i('cancel'),
  'A340': _i('cross_pool_rr1'),
  'A341': _i('blocked_qty'),
  'A342': _i('cross_reserved'),
  'A343': _i('cross_pool_product_sold'),
  'A344': _i('cross_pool_sold_dedup'),
  'A355': _i('logical_item_inherit'),
};

// ─── Bot Simulator ──────────────────────────────────────────────────────────

RegressionAdapter _b(
  String scenario, {
  String? dedupe,
  int bots = 10,
  bool guided = false,
}) =>
    RegressionAdapter(
      type: 'bot',
      path: 'tool/fleaber_bot_simulator.dart',
      entry: scenario,
      args: ['--bots', '$bots', '--duration', '30s', '--cleanup'],
      requiresLiveId: true,
      requiresStaging: true,
      requiresGuided: guided,
      dedupeKey: dedupe ?? 'bot:$scenario',
    );

final Map<String, RegressionAdapter> _botAdapters = {
  'A020': _b('price_pending', bots: 5, dedupe: 'bot:price_pending'),
  'A080': _b('reservations', dedupe: 'bot:reservations'),
  'A148': _b('reservations', dedupe: 'bot:reservations'),
  'A149': _b('reservations', dedupe: 'bot:reservations'),
  'A156': _b('viewers', dedupe: 'bot:viewers'),
  'A161': _b('chat', bots: 5, dedupe: 'bot:chat'),
  'A192': _b('reservations', dedupe: 'bot:reservations'),
  'A258': _b('raffles', dedupe: 'bot:raffles'),
  'A259': _b('raffles', dedupe: 'bot:raffles'),
  'A260': _b('raffles', dedupe: 'bot:raffles'),
  'A261': _b('raffles', dedupe: 'bot:raffles'),
  'A262': _b('raffles', dedupe: 'bot:raffles'),
  'A263': _b('raffles', dedupe: 'bot:raffles'),
  'A264': _b('raffles', dedupe: 'bot:raffles'),
  'A265': _b('raffles', dedupe: 'bot:raffles'),
  'A266': _b('raffles', dedupe: 'bot:raffles'),
  'A267': _b('raffles', dedupe: 'bot:raffles'),
  'A268': _b('raffles', dedupe: 'bot:raffles'),
  'A269': _b('raffles', dedupe: 'bot:raffles'),
  'A270': _b('raffles', dedupe: 'bot:raffles'),
  'A273': _b('raffles', dedupe: 'bot:raffles'),
  'A274': _b('raffles', dedupe: 'bot:raffles'),
  'A275': _b('raffles', dedupe: 'bot:raffles'),
  'A276': _b('raffles', dedupe: 'bot:raffles'),
  'A251': _b('follows', dedupe: 'bot:follows'),
  'A277': _b('full', bots: 20, dedupe: 'bot:full'),
};

// ─── Maestro UI smoke ───────────────────────────────────────────────────────

RegressionAdapter _m(String flow, {String? dedupe, bool guided = false}) =>
    RegressionAdapter(
      type: 'maestro',
      path: '.maestro/flows/$flow',
      entry: flow,
      requiresMaestro: true,
      requiresStaging: true,
      requiresGuided: guided,
      dedupeKey: dedupe ?? 'maestro:$flow',
    );

final Map<String, RegressionAdapter> _maestroAdapters = {
  'A001': _m('prep/a001_sheet_novo_direto.yaml', dedupe: 'maestro:A001'),
  'A002': _m('prep/a002_empty_catalog.yaml', dedupe: 'maestro:A002'),
  'A004': _m('prep/a004_ref_l1.yaml', dedupe: 'maestro:A004'),
  'A008': _m('prep/a008_lineage_cancel.yaml', dedupe: 'maestro:A008'),
  'A019': _m('prep/a019_to_criar.yaml', dedupe: 'maestro:A019'),
  'A022': _m('prep/a022_back_nav.yaml', dedupe: 'maestro:A022'),
  'A031': _m('prep/a031_tabs.yaml', dedupe: 'maestro:A031'),
  'A032': _m('prep/a032_title_criar.yaml', dedupe: 'maestro:A032'),
  'A035': _m('prep/a035_remove_ref.yaml', dedupe: 'maestro:A035'),
  'A071': _m('v1_05_seller_live_studio_smoke.yaml', dedupe: 'maestro:seller_studio'),
  'A145': _m('cross_surface_cs01_buyer_player.yaml', dedupe: 'maestro:buyer_player'),
  'A190': _m('v1_03_buyer_bag_sheet.yaml', dedupe: 'maestro:buyer_bag'),
  'A271': _m('v2_buyer_raffle_bag.yaml', dedupe: 'maestro:buyer_raffle'),
  'A017': _m('prep/a017_deep_link_prep.yaml', dedupe: 'maestro:A017'),
  'A050': _m('v1_01_login_buyer_home.yaml', dedupe: 'maestro:login_buyer'),
  'A089': _m('v2_seller_harness_assert_pending.yaml', dedupe: 'maestro:seller_harness_pending'),
  'A090': _m('v2_seller_harness_assert_accepted.yaml', dedupe: 'maestro:seller_harness_accepted'),
  'A094': _m('v2_seller_harness_assert_cancelled.yaml', dedupe: 'maestro:seller_harness_cancelled'),
  'A387': _m('helper_link_invalid.yaml', dedupe: 'maestro:helper_link_invalid'),
};

// ─── Hybrid Bot + Maestro + Integration ─────────────────────────────────────

final Map<String, RegressionAdapter> _hybridAdapters = {
  'A279': RegressionAdapter(
    type: 'hybrid',
    path: 'tool/regression/hybrid_runner.dart',
    entry: 'raffle_e2e',
    requiresLiveId: true,
    requiresStaging: true,
    requiresMaestro: true,
    requiresGuided: false,
    dedupeKey: 'hybrid:raffle_e2e',
    steps: [
      HybridStep(type: 'bot', scenario: 'raffles'),
      HybridStep(type: 'bot', scenario: 'follows'),
      HybridStep(type: 'maestro', flow: 'v2_buyer_raffle_bag.yaml'),
      HybridStep(type: 'integration', scenario: 'verify_raffle_join'),
    ],
  ),
  'A095': RegressionAdapter(
    type: 'hybrid',
    path: 'tool/regression/hybrid_runner.dart',
    entry: 'reserve_accept_bag',
    requiresLiveId: true,
    requiresStaging: true,
    requiresMaestro: true,
    requiresGuided: false,
    dedupeKey: 'hybrid:reserve_accept',
    steps: [
      HybridStep(type: 'bot', scenario: 'reservations'),
      HybridStep(type: 'maestro', flow: 'v2_seller_automation_chain.yaml'),
      HybridStep(type: 'maestro', flow: 'v1_03_buyer_bag_sheet.yaml'),
      HybridStep(type: 'integration', scenario: 'verify_accepted'),
    ],
  ),
  'A151': RegressionAdapter(
    type: 'hybrid',
    path: 'tool/regression/hybrid_runner.dart',
    entry: 'reserve_accept_bag',
    requiresLiveId: true,
    requiresStaging: true,
    requiresMaestro: true,
    requiresGuided: false,
    dedupeKey: 'hybrid:reserve_accept',
    steps: [
      HybridStep(type: 'bot', scenario: 'reservations'),
      HybridStep(type: 'maestro', flow: 'v2_seller_automation_chain.yaml'),
      HybridStep(type: 'integration', scenario: 'verify_accepted'),
    ],
  ),
  'A398': RegressionAdapter(
    type: 'hybrid',
    path: 'tool/regression/hybrid_runner.dart',
    entry: 'h07_pipeline',
    requiresLiveId: true,
    requiresStaging: true,
    requiresMaestro: true,
    requiresGuided: false,
    dedupeKey: 'hybrid:h07',
    steps: [
      HybridStep(type: 'bot', scenario: 'full'),
      HybridStep(type: 'maestro', flow: 'v2_seller_automation_chain.yaml'),
      HybridStep(type: 'integration', scenario: 'verify_accepted'),
    ],
  ),
};

