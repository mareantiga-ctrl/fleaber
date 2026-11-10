// ignore_for_file: avoid_print
/// Auditoria Projecto H v1 — dados staging antes de preview visual.
/// Uso: dart run tool/hub_h_v1_staging_audit.dart
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _reportRoot = 'tool/reports';
const _defaultHandle = 'hub-staging-axinoquaa';

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
  final stamp = started.toIso8601String().replaceAll(':', '-');
  final reportDir = '$_reportRoot/h_v1_staging_audit_$stamp';
  Directory(reportDir).createSync(recursive: true);

  final report = <String, dynamic>{
    'started_utc': started.toIso8601String(),
    'seller_id': sellerId,
    'checks': <Map<String, dynamic>>[],
  };

  Future<Map<String, dynamic>> record(
    String name,
    Future<dynamic> Function() fn,
  ) async {
    try {
      final result = await fn();
      final entry = {'name': name, 'ok': true, 'result': result};
      (report['checks'] as List).add(entry);
      print('OK   $name');
      return entry;
    } catch (e) {
      final entry = {'name': name, 'ok': false, 'error': e.toString()};
      (report['checks'] as List).add(entry);
      print('FAIL $name: $e');
      return entry;
    }
  }

  // 1) SQL v1 — colunas follower_count + hub_bio
  await record('sql_v1_hub_profiles_columns', () async {
    try {
      await client.select(
        'profiles',
        filter: 'id=eq.$sellerId&select=hub_bio',
        limit: 1,
      );
    } catch (e) {
      return {
        'applied': false,
        'profiles_hub_bio': false,
        'error': e.toString(),
        'migration': 'supabase/sql/hub_public_views_h_v1_batata.sql',
      };
    }
    try {
      final rows = await client.select(
        'hub_profiles_public',
        filter: 'handle=eq.$_defaultHandle',
        limit: 1,
      );
      final row = rows.isEmpty ? null : rows.first;
      final hasFollowers = row?.containsKey('follower_count') == true;
      return {
        'applied': hasFollowers,
        'profiles_hub_bio_column': true,
        'view_has_follower_count': hasFollowers,
        'view_has_hub_bio_key': row?.containsKey('hub_bio') == true,
        'migration': hasFollowers
            ? null
            : 'supabase/sql/hub_public_views_h_v1_batata.sql',
      };
    } catch (e) {
      return {
        'applied': false,
        'profiles_hub_bio_column': true,
        'view_error': e.toString(),
        'migration': 'supabase/sql/hub_public_views_h_v1_batata.sql',
      };
    }
  });

  // 2) Seller profiles row
  List<Map<String, dynamic>> profileRows = const [];
  await record('profiles_seller', () async {
    profileRows = await client.select(
      'profiles',
      filter:
          'id=eq.$sellerId&select=id,full_name,photo_url,location,handle,hub_published,phone_verified_at,hub_bio',
      limit: 1,
    );
    if (profileRows.isEmpty) {
      throw StateError('Perfil seller não encontrado: $sellerId');
    }
    return profileRows.first;
  });

  final handle =
      profileRows.isEmpty ? _defaultHandle : profileRows.first['handle']?.toString().trim() ?? _defaultHandle;
  report['handle'] = handle;

  // 3) batata_resolve_handle (anon via service — RPC público)
  await record('batata_resolve_handle', () async {
    final raw = await client.rpc('batata_resolve_handle', {'p_handle': handle});
    if (raw is! Map) throw StateError('Resposta inválida: $raw');
    final found = raw['found'] == true;
    if (!found) {
      throw StateError('found=false: $raw');
    }
    return raw;
  });

  // 4) hub_profiles_public
  List<Map<String, dynamic>> hubProfileRows = const [];
  await record('hub_profiles_public', () async {
    hubProfileRows = await client.select(
      'hub_profiles_public',
      filter: 'handle=eq.$handle',
      limit: 1,
    );
    if (hubProfileRows.isEmpty) {
      throw StateError('Nenhuma linha em hub_profiles_public para handle=$handle');
    }
    return hubProfileRows.first;
  });

  final hubProfile = hubProfileRows.isEmpty ? null : hubProfileRows.first;
  final profileId = hubProfile?['id']?.toString() ?? sellerId;

  // 5) Dados mínimos
  await record('data_minimum_profile', () async {
    if (hubProfile == null) throw StateError('hub profile em falta');
    final fullName = hubProfile['full_name']?.toString().trim() ?? '';
    final photo = hubProfile['photo_url']?.toString().trim() ?? '';
    final location = hubProfile['location']?.toString().trim() ?? '';
    final followers = hubProfile['follower_count'];
    final gaps = <String>[];
    if (fullName.isEmpty) gaps.add('full_name');
    if (photo.isEmpty) gaps.add('photo_url');
    if (location.isEmpty) gaps.add('location');
    if (followers == null) gaps.add('follower_count (coluna SQL v1?)');
    return {
      'full_name': fullName.isEmpty ? null : fullName,
      'photo_url': photo.isEmpty ? null : photo,
      'location': location.isEmpty ? null : location,
      'follower_count': followers,
      'hub_bio': hubProfile['hub_bio'],
      'hub_published_profiles': profileRows.isEmpty
          ? null
          : profileRows.first['hub_published'],
      'gaps': gaps,
      'ready_for_visual': gaps.isEmpty,
    };
  });

  await record('hub_lives_public', () async {
    final rows = await client.select(
      'hub_lives_public',
      filter: 'seller_id=eq.$profileId&select=id,title,status,is_active,mux_playback_id,mux_vod_playback_id',
      limit: 12,
    );
    final liveNow = rows.where((r) => r['is_active'] == true || r['status'] == 'live').length;
    final ended = rows.where((r) => r['status'] == 'ended').length;
    return {
      'count': rows.length,
      'live_now': liveNow,
      'ended_gravados': ended,
      'rows': rows,
    };
  });

  await record('hub_products_public', () async {
    final rows = await client.select(
      'hub_products_public',
      filter:
          'seller_id=eq.$profileId&is_sold=eq.false&select=id,title,price,image_urls',
      limit: 12,
    );
    return {'count': rows.length, 'rows': rows};
  });

  await record('hub_reviews_public', () async {
    final rows = await client.select(
      'hub_reviews_public',
      filter: 'target_id=eq.$profileId&select=id,stars,comment,author_display',
      limit: 12,
    );
    return {'count': rows.length, 'rows': rows};
  });

  report['finished_utc'] = DateTime.now().toUtc().toIso8601String();

  final sqlOk = (report['checks'] as List)
      .any((c) => c['name'] == 'sql_v1_hub_profiles_columns' && c['ok'] == true);
  final sqlApplied = sqlOk &&
      ((report['checks'] as List).firstWhere(
            (c) => c['name'] == 'sql_v1_hub_profiles_columns',
          )['result'] as Map)['applied'] ==
          true;

  final allOk = (report['checks'] as List).every((c) => c['ok'] == true);
  Map<String, dynamic>? dataCheck;
  for (final c in (report['checks'] as List).cast<Map<String, dynamic>>()) {
    if (c['name'] == 'data_minimum_profile') {
      dataCheck = c['result'] as Map<String, dynamic>?;
    }
  }
  final visualReady = allOk && (dataCheck?['ready_for_visual'] == true);

  report['summary'] = {
    'sql_v1_applied': sqlApplied,
    'all_checks_ok': allOk,
    'ready_for_flutter_preview': visualReady,
    'handle': handle,
    'report_dir': reportDir,
  };

  final jsonPath = '$reportDir/audit.json';
  File(jsonPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
  );

  File('$reportDir/README.md').writeAsStringSync('''
# H-v1 staging audit

Gerado: ${report['finished_utc']}

Handle: `$handle`

| Item | Estado |
|------|--------|
| SQL v1 (follower_count, hub_bio) | ${sqlApplied ? 'OK' : 'FALTA aplicar'} |
| Todos os checks | ${allOk ? 'OK' : 'FALHAS — ver audit.json'} |
| Pronto preview visual | ${visualReady ? 'SIM' : 'NÃO'} |

Ficheiro completo: `audit.json`

SQL pendente (se aplicável): `supabase/sql/hub_public_views_h_v1_batata.sql`
''');

  print('');
  print('=== RESUMO ===');
  print('SQL v1 aplicado: $sqlApplied');
  print('Checks OK: $allOk');
  print('Pronto preview: $visualReady');
  print('Pasta: $reportDir');
  print('JSON: $jsonPath');

  exit(visualReady ? 0 : 1);
}
