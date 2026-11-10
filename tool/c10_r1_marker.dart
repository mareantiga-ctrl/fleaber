// ignore_for_file: avoid_print
library;

import 'dart:io';

import 'live_ops_staging_client.dart';

const _id = 'e6411e97-c9f1-4a6c-99fd-ee79d5e3caee';
const _original = 'C8 Taça Cerâmica U';
const _marker = 'C10 R1 Taca U';

/// R1: estado conhecido na BD para o pull-to-refresh mostrar título novo.
void main(List<String> args) async {
  final restore = args.contains('--restore');
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final title = restore ? _original : _marker;
  await client.patch('products', 'id=eq.$_id', {'title': title});
  final rows = await client.select('products', filter: 'id=eq.$_id', limit: 1);
  stdout.writeln(rows.isEmpty ? 'missing' : 'title=${rows.first['title']}');
}
