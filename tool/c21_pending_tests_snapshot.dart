// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final outDir = Directory('tool/reports/battery_c21_2026-08-19/bd');
  await outDir.create(recursive: true);

  final orders = await sb.select('orders', filter: 'order=created_at.desc', limit: 500);
  final statusTargets = [
    'reservado', // APP-061
    'pedido_devolucao', // APP-069
    'em_devolucao', // APP-070
    'devolucao_entregue', // APP-071
    'disputa_devolucao_vendedor', // APP-072
    'devolvida', // APP-073 and APP-146
  ];
  final statusRows = <String, List<Map<String, dynamic>>>{};
  for (final s in statusTargets) {
    final rows = orders
        .where((o) => (o['status'] ?? '').toString().trim().toLowerCase() == s)
        .take(20)
        .map((o) => {
              'id': o['id'],
              'status': o['status'],
              'created_at': o['created_at'],
              'buyer_id': o['buyer_id'],
              'seller_id': o['seller_id'],
              'product_id': o['product_id'],
              'live_id': o['live_id'],
              'live_item_id': o['live_item_id'],
            })
        .toList();
    statusRows[s] = rows;
  }

  final msgs = await sb.select(
    'chat_messages',
    filter: 'text=like.FLEABER_JSON_V1%25&order=created_at.desc',
    limit: 500,
  );
  const prefix = 'FLEABER_JSON_V1:';
  final byKind = <String, List<Map<String, dynamic>>>{};
  for (final m in msgs) {
    final text = (m['text'] ?? '').toString();
    if (!text.startsWith(prefix)) continue;
    try {
      final payload = jsonDecode(text.substring(prefix.length));
      if (payload is! Map) continue;
      final kind = (payload['kind'] ?? '').toString();
      byKind.putIfAbsent(kind, () => []);
      byKind[kind]!.add({
        'id': m['id'],
        'chat_id': m['chat_id'],
        'created_at': m['created_at'],
        'payload': payload,
      });
    } catch (_) {}
  }

  final targetKinds = [
    'bundle_proposal_outcome', // APP-084
    'order_dispute_opened', // APP-093
  ];

  final result = {
    'generated_at': DateTime.now().toIso8601String(),
    'orders_status_counts': {
      for (final s in statusTargets) s: (statusRows[s] ?? const []).length,
    },
    'orders_status_samples': statusRows,
    'chat_kind_counts': {
      for (final k in targetKinds) k: (byKind[k] ?? const []).length,
    },
    'chat_kind_samples': {
      for (final k in targetKinds) k: (byKind[k] ?? const []).take(10).toList(),
    },
  };

  final file = File('${outDir.path}/c21_pending_snapshot.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(result));
  print('wrote ${file.path}');
}
