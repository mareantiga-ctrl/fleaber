// ignore_for_file: avoid_print
/// Encontrar threads com cards reservation_order_shipped / completed.
library;

import 'dart:convert';
import 'dart:io';
import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final msgs = await sb.select(
    'chat_messages',
    filter: 'text=like.FLEABER_JSON_V1%25&order=created_at.desc',
    limit: 200,
  );

  const prefix = 'FLEABER_JSON_V1:';
  for (final m in msgs) {
    final text = m['text'] as String? ?? '';
    if (!text.startsWith(prefix)) continue;
    try {
      final decoded = jsonDecode(text.substring(prefix.length));
      if (decoded is Map) {
        final kind = decoded['kind'] as String? ?? '';
        if (kind == 'reservation_order_shipped' || kind == 'reservation_order_completed') {
          print('kind=$kind chat_id=${m['chat_id']} id=${m['id']} created=${m['created_at']}');
        }
      }
    } catch (_) {}
  }
}
