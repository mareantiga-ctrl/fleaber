// ignore_for_file: avoid_print
/// Reset / restore FleaHub seller staging — **só QA manual** (screenshot 04).
/// O fluxo Criar FleaHub valida-se em `test/hub_seller_fleahub_flow_test.dart`.
///
/// Uso:
///   dart run tool/fleahub_staging_create_flow_reset.dart backup
///   dart run tool/fleahub_staging_create_flow_reset.dart clear
///   dart run tool/fleahub_staging_create_flow_reset.dart restore
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _backupPath = 'tool/reports/fleahub_create_flow_staging_backup.json';
const _rpc = 'batata_staging_set_fleahub_test_state';

Future<void> main(List<String> args) async {
  final mode = args.isEmpty ? 'backup' : args.first.trim().toLowerCase();
  if (!{'backup', 'clear', 'restore'}.contains(mode)) {
    stderr.writeln('Modos: backup | clear | restore');
    exit(2);
  }

  final env = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final sellerId =
      env['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '980f4fa1-0004-42f9-abca-69f1a9c29588';

  final rows = await client.select(
    'profiles',
    filter:
        'id=eq.$sellerId&select=id,handle,hub_published,handle_suggested,full_name',
    limit: 1,
  );
  if (rows.isEmpty) {
    stderr.writeln('Perfil não encontrado: $sellerId');
    exit(1);
  }
  final profile = rows.first;

  Future<Map<String, dynamic>> apply({
    String? handle,
    bool? hubPublished,
    String? handleSuggested,
  }) async {
    try {
      final raw = await client.rpc(_rpc, {
        'p_profile_id': sellerId,
        'p_handle': handle,
        'p_hub_published': hubPublished ?? false,
        'p_handle_suggested': handleSuggested,
      });
      if (raw is! Map) {
        throw StateError('Resposta inválida: $raw');
      }
      final map = Map<String, dynamic>.from(raw);
      if (map['ok'] != true) {
        throw StateError(map['error']?.toString() ?? 'rpc_failed');
      }
      return map;
    } on HttpException catch (e) {
      if (e.message.contains('404') || e.message.contains('PGRST202')) {
        stderr.writeln(
          'RPC $_rpc em falta. Aplica tool/sql/fleahub_staging_reset_fleahub_for_test.sql em staging.',
        );
      }
      rethrow;
    }
  }

  if (mode == 'backup') {
    final backup = {
      'saved_utc': DateTime.now().toUtc().toIso8601String(),
      'seller_id': sellerId,
      'handle': profile['handle'],
      'hub_published': profile['hub_published'] == true,
      'handle_suggested': profile['handle_suggested'],
    };
    File(_backupPath).parent.createSync(recursive: true);
    File(_backupPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(backup),
    );
    print('Backup: $_backupPath');
    print(jsonEncode(backup));
    return;
  }

  if (mode == 'clear') {
    if (!File(_backupPath).existsSync()) {
      await main(['backup']);
    }
    final result = await apply(
      handle: '',
      hubPublished: false,
      handleSuggested: profile['handle_suggested']?.toString() ??
          profile['full_name']?.toString(),
    );
    print('CLEAR OK: ${jsonEncode(result)}');
    return;
  }

  if (!File(_backupPath).existsSync()) {
    stderr.writeln('Backup em falta: $_backupPath — corre backup primeiro.');
    exit(1);
  }
  final backup =
      jsonDecode(File(_backupPath).readAsStringSync()) as Map<String, dynamic>;
  final result = await apply(
    handle: backup['handle']?.toString(),
    hubPublished: backup['hub_published'] == true,
    handleSuggested: backup['handle_suggested']?.toString(),
  );
  print('RESTORE OK: ${jsonEncode(result)}');
}
