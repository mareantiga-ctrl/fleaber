// ignore_for_file: avoid_print
/// Snapshot C18: mensagens de chat por tipo FLEABER_JSON_V1.
library;

import 'dart:convert';
import 'dart:io';
import 'live_ops_staging_client.dart';

void main(List<String> args) async {
  final staging = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  // Get recent chat messages with FLEABER_JSON_V1 prefix
  final msgs = await sb.select(
    'chat_messages',
    filter: 'text=like.FLEABER_JSON_V1%25&order=created_at.desc',
    limit: 100,
  );

  const prefix = 'FLEABER_JSON_V1:';
  final Map<String, List<Map>> byKind = {};
  for (final m in msgs) {
    final text = m['text'] as String? ?? '';
    if (!text.startsWith(prefix)) continue;
    try {
      final decoded = jsonDecode(text.substring(prefix.length));
      if (decoded is Map) {
        final kind = (decoded['kind'] ?? 'unknown') as String;
        byKind.putIfAbsent(kind, () => []).add(m);
      }
    } catch (_) {}
  }

  print('=== FLEABER_JSON_V1 BY KIND ===');
  for (final entry in byKind.entries) {
    print('${entry.key}: ${entry.value.length}');
    if (entry.value.isNotEmpty) {
      final m = entry.value.first;
      print('  thread_id=${m['thread_id']} created=${m['created_at']}');
    }
  }

  // Also get chat threads for the seller
  final sellerId = staging['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  final threads = await sb.select(
    'chat_threads',
    filter: 'order=updated_at.desc',
    limit: 20,
  );

  print('\n=== RECENT THREADS ===');
  for (final t in threads.take(10)) {
    print('  id=${t['id']} seller=${t['seller_id']} buyer=${t['buyer_id']} last=${t['last_message_at']}');
  }

  final outDir = Directory('tool/reports/battery_c18_2026-08-19/bd');
  await outDir.create(recursive: true);
  final outFile = File('tool/reports/battery_c18_2026-08-19/bd/c18_chat_pre.json');
  await outFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert({'msgs_by_kind': byKind, 'threads': threads}),
  );
  print('\nwrote ${outFile.path}');
}
