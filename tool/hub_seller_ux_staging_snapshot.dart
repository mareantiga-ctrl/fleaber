// ignore_for_file: avoid_print
/// Snapshot BD staging Hub seller — evidência para auditoria UX #21d.
/// Uso: dart run tool/hub_seller_ux_staging_snapshot.dart
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _reportDir = 'tool/reports';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final sellerId =
      env['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '980f4fa1-0004-42f9-abca-69f1a9c29588';
  final started = DateTime.now().toUtc();
  final report = <String, dynamic>{
    'started_utc': started.toIso8601String(),
    'seller_id': sellerId,
    'checks': <Map<String, dynamic>>[],
  };

  Future<void> check(String name, Future<dynamic> Function() fn) async {
    try {
      final result = await fn();
      (report['checks'] as List).add({'name': name, 'ok': true, 'result': result});
      print('OK  $name');
    } catch (e) {
      (report['checks'] as List).add({
        'name': name,
        'ok': false,
        'error': e.toString(),
      });
      print('FAIL $name: $e');
    }
  }

  List<Map<String, dynamic>> profileRows = const [];
  await check('profiles_hub_columns', () async {
    profileRows = await client.select(
      'profiles',
      filter:
          'id=eq.$sellerId&select=id,full_name,handle,handle_suggested,hub_published,phone_verified_at',
      limit: 1,
    );
    return profileRows;
  });

  await check('batata_resolve_handle', () async {
    final handle = profileRows.isEmpty
        ? null
        : profileRows.first['handle']?.toString().trim();
    if (handle == null || handle.isEmpty) {
      return {'skipped': true, 'reason': 'no handle on profile'};
    }
    return client.rpc('batata_resolve_handle', {'p_handle': handle});
  });

  await check('hub_profiles_public', () async {
    final handle = profileRows.isEmpty
        ? null
        : profileRows.first['handle']?.toString().trim();
    if (handle == null || handle.isEmpty) {
      return {'skipped': true};
    }
    return client.select(
      'hub_profiles_public',
      filter: 'handle=eq.$handle',
      limit: 1,
    );
  });

  await check('batata_suggest_handles', () async {
    return client.rpc('batata_suggest_handles', {
      'p_seed': profileRows.isEmpty
          ? 'axinoquaa'
          : profileRows.first['full_name']?.toString(),
      'p_profile_id': sellerId,
      'p_limit': 3,
    });
  });

  report['finished_utc'] = DateTime.now().toUtc().toIso8601String();
  Directory(_reportDir).createSync(recursive: true);
  final stamp = started.toIso8601String().replaceAll(':', '-');
  final jsonPath = '$_reportDir/hub_seller_ux_staging_$stamp.json';
  File(jsonPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  print('Report: $jsonPath');
}
