// ignore_for_file: avoid_print
import 'dart:io';

import 'adapter_auto_mapper.dart';
import 'store.dart';

/// Nível de validação por adapter automated.
class AdapterLevelInfo {
  AdapterLevelInfo({
    required this.id,
    required this.title,
    required this.layer,
    required this.level,
    required this.validations,
    required this.bdFields,
    required this.uiFields,
  });

  final String id;
  final String title;
  final String layer;
  final int level;
  final String validations;
  final String bdFields;
  final String uiFields;
}

AdapterLevelInfo levelForTest(dynamic test) {
  final adapter = test.adapter;
  final type = adapter?.type ?? 'none';
  final entry = adapter?.entry ?? '';

  switch (type) {
    case 'unit':
      return AdapterLevelInfo(
        id: test.id,
        title: test.title,
        layer: 'unit',
        level: 1,
        validations: 'flutter test executa sem erro${entry.isNotEmpty ? " (filtro: $entry)" : ""}',
        bdFields: '—',
        uiFields: '— (lógica Dart isolada)',
      );
    case 'integration':
      final bd = _integrationBd(entry);
      return AdapterLevelInfo(
        id: test.id,
        title: test.title,
        layer: 'integration',
        level: 2,
        validations: 'RPC/insert staging + assert BD ($entry)',
        bdFields: bd,
        uiFields: '—',
      );
    case 'bot':
      return AdapterLevelInfo(
        id: test.id,
        title: test.title,
        layer: 'bot',
        level: 2,
        validations: 'Bot sim $entry + validators BD (stock, reservations, chat, raffles)',
        bdFields: 'live_reservation_requests, live_items, live_messages, live_raffles, orders',
        uiFields: '— (opcional --observe-ui)',
      );
    case 'maestro':
      return AdapterLevelInfo(
        id: test.id,
        title: test.title,
        layer: 'maestro',
        level: 3,
        validations: 'Flow Maestro UI smoke + asserts visuais',
        bdFields: '— (indirecto via app)',
        uiFields: 'login, player, saco, studio, rifa sidebar',
      );
    case 'hybrid':
      return AdapterLevelInfo(
        id: test.id,
        title: test.title,
        layer: 'hybrid',
        level: 3,
        validations: 'Bot seed → Maestro UI → integration BD',
        bdFields: 'reservations, orders, raffles',
        uiFields: 'seller harness, buyer bag/player',
      );
    default:
      return AdapterLevelInfo(
        id: test.id,
        title: test.title,
        layer: type,
        level: 0,
        validations: 'checkpoint manual/guided',
        bdFields: '—',
        uiFields: '—',
      );
  }
}

String _integrationBd(String scenario) => switch (scenario) {
      'cross_pool_rr1' || 'cross_pool_product_sold' || 'cross_pool_sold_dedup' =>
        'batata_live_item_stock: available_qty, sold, sold_converted_qty',
      'blocked_qty' => 'batata_live_item_stock: blocked_qty',
      'cross_reserved' => 'batata_live_item_stock: cross_reserved_qty',
      'reconcile' || 'reconcile_idempotent' =>
        'orders.status, live_reservation_requests.converted',
      'cancel' => 'live_reservation_requests.status=rejected, notes bag_removed',
      'bag_edge' => 'live_reservation_requests multi-ref buyer',
      'stock' => 'batata_live_item_stock: available_qty',
      'logical_item_inherit' || 'logical_item_lineage' =>
        'live_items.logical_item_id',
      'verify_raffle_join' => 'live_raffle_entries',
      'verify_accepted' => 'live_reservation_requests.status=accepted',
      'chat_messages_db' => 'live_messages',
      'price_gate_staging' => 'live_items.price > 0',
      'gravado_sold' || 'marketplace_bridge' => 'orders.product_id, products.quantity',
      _ => 'live_items, live_reservation_requests, orders (smoke)',
    };

String generateAdapterLevelsMarkdown(String repoRoot) {
  final manifest = RegressionStore(RegressionPaths(repoRoot)).loadManifest();
  final automated = manifest.values
      .where((t) {
        final type = t.adapter?.type;
        return type != null &&
            AdapterAutoMapper.isAutomatedType(type);
      })
      .toList()
    ..sort((a, b) => a.id.compareTo(b.id));

  final buf = StringBuffer()
    ..writeln('# Adapter levels — matriz A001–A429')
    ..writeln()
    ..writeln('Total automated: ${automated.length}')
    ..writeln()
    ..writeln('| A### | Nome | Layer | Nível | Validações | Campos BD | Campos UI |')
    ..writeln('|------|------|-------|-------|------------|-----------|-----------|');

  for (final t in automated) {
    final info = levelForTest(t);
    final name = t.title.replaceAll('|', '/');
    buf.writeln(
      '| ${info.id} | $name | ${info.layer} | ${info.level} | ${info.validations} | ${info.bdFields} | ${info.uiFields} |',
    );
  }
  return buf.toString();
}

void main(List<String> args) {
  final root = args.isNotEmpty ? args.first : '.';
  final md = generateAdapterLevelsMarkdown(root);
  final out = '$root/tool/reports/adapter_levels.md';
  File(out).parent.createSync(recursive: true);
  File(out).writeAsStringSync(md);
  print('Wrote $out (${md.split('\n').length} lines)');
}
