// ignore_for_file: avoid_print
library;

import 'dart:convert';

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final rows = await client.select(
    'chat_messages',
    filter: 'text=ilike.*ola C8*&order=created_at.desc',
    limit: 5,
  );
  print(const JsonEncoder.withIndent('  ').convert(rows.map((m) {
        return {
          'id': m['id'],
          'text': m['content'] ?? m['text'] ?? m['message'],
          'kind': m['kind'] ?? m['type'],
          'created_at': m['created_at'],
        };
      }).toList()));
}
