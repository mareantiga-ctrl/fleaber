// ignore_for_file: avoid_print
/// Teste funcional Hub publish em staging (#19b) — uma seller real de teste.
/// Uso: dart run tool/hub_publish_staging_functional.dart
///
/// Não aplica backfill global. Grava relatório em tool/reports/.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const _testHandle = 'hub-staging-axinoquaa';
const _reportDir = 'tool/reports';
const _forbiddenKeys = {
  'phone',
  'legal_full_name',
  'iban',
  'mb_way',
  'shipping_line1',
  'shipping_line2',
  'shipping_postal_code',
  'shipping_city',
  'shipping_country',
  'user_type',
  'email',
  'mux_stream_key',
  'stream_key',
  'mux_live_id',
  'livekit_room_name',
  'livekit_egress_id',
  'mux_asset_id',
  'buyer_id',
  'order_id',
  'user_id',
  'tip_id',
};

const _allowedProfileCols = {
  'id',
  'handle',
  'full_name',
  'photo_url',
  'location',
  'is_live',
  'next_live',
  'last_live',
  'total_lives',
  'vacation_mode',
  'phone_verified',
  'external_payments_enabled',
};

void main() async {
  final started = DateTime.now().toUtc();
  final log = StringBuffer()
    ..writeln('# Hub publish functional — staging')
    ..writeln('started_utc: $started')
    ..writeln('project: fxdknzrqjenzqcvnwqqq')
    ..writeln('');

  final steps = <Map<String, dynamic>>[];
  var failed = 0;

  void step(
    int n,
    String name,
    bool ok, {
    String? query,
    Object? result,
    String? error,
  }) {
    steps.add({
      'step': n,
      'name': name,
      'ok': ok,
      if (query != null) 'query': query,
      if (result != null) 'result': result,
      if (error != null) 'error': error,
    });
    log.writeln('## Step $n — $name');
    log.writeln('result: ${ok ? 'PASS' : 'FAIL'}');
    if (query != null) log.writeln('query: `$query`');
    if (result != null) {
      log.writeln('output:');
      log.writeln('```json');
      log.writeln(const JsonEncoder.withIndent('  ').convert(result));
      log.writeln('```');
    }
    if (error != null) log.writeln('error: $error');
    log.writeln('');
    if (!ok) failed++;
  }

  LiveOpsStagingClient? client;
  String? sellerId;
  String? sellerToken;
  String? testProductId;
  bool? productMktBefore;
  String? testLiveId;
  String? testLiveWithMsgsId;

  try {
    final env = loadLiveOpsStagingEnv();
    client = LiveOpsStagingClient(
      url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
      anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
      serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
    );
    sellerId = env['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
    final sellerEmail = envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL');
    final sellerPassword = envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD');

    log.writeln('seller_email: $sellerEmail');
    log.writeln('seller_id_env: $sellerId');
    log.writeln('test_handle: $_testHandle');
    log.writeln('');

    sellerToken = await client.signIn(
      email: sellerEmail,
      password: sellerPassword,
    );
    if (!isUuid(sellerId)) {
      sellerId = await client.userIdForAccessToken(sellerToken);
    }

    // --- Setup (não é backfill global) ---
    log.writeln('### Setup');
    final profileRows = await client.select(
      'profiles',
      filter: 'id=eq.$sellerId',
      limit: 1,
    );
    final profile = profileRows.isEmpty ? <String, dynamic>{} : profileRows.first;
    if (profile['phone_verified_at'] == null) {
      await client.patch(
        'profiles',
        'id=eq.$sellerId',
        {'phone_verified_at': DateTime.now().toUtc().toIso8601String()},
      );
      log.writeln(
        'setup: phone_verified_at definido na conta de teste (única seller)',
      );
    } else {
      log.writeln('setup: phone_verified_at já presente');
    }

    if (profile['hub_published'] == true) {
      await client.rpc(
        'batata_publish_hub',
        {'p_publish': false},
        accessToken: sellerToken,
      );
      log.writeln('setup: hub_published reposto para false');
    }

    final products = await client.select(
      'products',
      filter: 'seller_id=eq.$sellerId&is_sold=eq.false',
      limit: 5,
    );
    if (products.isNotEmpty) {
      testProductId = products.first['id']?.toString();
      productMktBefore = products.first['list_on_marketplace'] == true;
      if (productMktBefore != true) {
        await client.patch(
          'products',
          'id=eq.$testProductId',
          {'list_on_marketplace': true},
        );
        log.writeln(
          'setup: list_on_marketplace=true em product $testProductId (revert no fim)',
        );
      }
    }

    final lives = await client.select(
      'lives',
      filter: 'seller_id=eq.$sellerId&status=in.(ended,live,scheduled)',
      limit: 30,
    );
    for (final l in lives) {
      final lid = l['id']?.toString() ?? '';
      if (lid.isEmpty) continue;
      final items = await client.select(
        'live_items',
        filter: 'live_id=eq.$lid',
        limit: 1,
      );
      if (items.isNotEmpty) {
        testLiveId = lid;
        break;
      }
    }

    for (final l in lives) {
      final lid = l['id']?.toString() ?? '';
      final msgs = await client.select(
        'live_messages',
        filter: 'live_id=eq.$lid',
        limit: 1,
      );
      if (msgs.isNotEmpty) {
        testLiveWithMsgsId = lid;
        break;
      }
    }

    log.writeln('setup: test_live_id=$testLiveId');
    log.writeln('setup: test_live_msgs_id=$testLiveWithMsgsId');
    log.writeln('setup: test_product_id=$testProductId');
    log.writeln('');

    // --- Step 1 claim_handle ---
    Object? claimResult;
    var claimOk = false;
    try {
      final currentHandle = profile['handle']?.toString();
      if (currentHandle != null && currentHandle.isNotEmpty) {
        claimResult = {
          'skipped': true,
          'reason': 'handle_already_set',
          'handle': currentHandle,
        };
        claimOk = currentHandle == _testHandle;
      } else {
        claimResult = await client.rpc(
          'batata_claim_handle',
          {'p_handle': _testHandle},
          accessToken: sellerToken,
        );
        claimOk = claimResult is Map &&
            claimResult['ok'] == true &&
            claimResult['handle'] == _testHandle;
      }
    } catch (e) {
      claimOk = false;
      claimResult = {'exception': e.toString()};
    }
    step(
      1,
      'claim_handle',
      claimOk,
      query: "rpc batata_claim_handle('$_testHandle') as seller JWT",
      result: claimResult,
    );

    // --- Step 2 publish_hub(true) ---
    Object? publishResult;
    var publishOk = false;
    try {
      publishResult = await client.rpc(
        'batata_publish_hub',
        {'p_publish': true},
        accessToken: sellerToken,
      );
      publishOk = publishResult is Map &&
          publishResult['ok'] == true &&
          publishResult['hub_published'] == true;
    } catch (e) {
      publishResult = {'exception': e.toString()};
    }
    step(
      2,
      'publish_hub(true)',
      publishOk,
      query: 'rpc batata_publish_hub(true) as seller JWT',
      result: publishResult,
    );

    if (!publishOk) {
      throw StateError('publish_hub falhou — abortar verificações públicas');
    }

    // --- Step 3 resolve_handle ---
    Object? resolveResult;
    var resolveOk = false;
    try {
      resolveResult = await client.rpc(
        'batata_resolve_handle',
        {'p_handle': _testHandle},
      );
      resolveOk = resolveResult is Map &&
          resolveResult['found'] == true &&
          resolveResult['http_status'] == 200 &&
          resolveResult['hub_published'] == true &&
          resolveResult['handle'] == _testHandle;
    } catch (e) {
      resolveResult = {'exception': e.toString()};
    }
    step(
      3,
      'batata_resolve_handle(handle)',
      resolveOk,
      query: "rpc batata_resolve_handle('$_testHandle') as anon",
      result: resolveResult,
    );

    // --- Steps 4-9 public views (anon) ---
    Future<void> checkView(
      int n,
      String name,
      String table,
      String filter, {
      required Set<String> allowedCols,
      String? extraCheck,
    }) async {
      try {
        final rows = await _selectAnon(
          client!,
          table,
          filter: filter,
          limit: 5,
        );
        final leaks = <String>[];
        for (final row in rows) {
          for (final k in row.keys) {
            if (_forbiddenKeys.contains(k.toLowerCase())) {
              leaks.add(k);
            }
          }
          if (allowedCols.isNotEmpty) {
            for (final k in row.keys) {
              if (!allowedCols.contains(k)) {
                leaks.add('unexpected:$k');
              }
            }
          }
        }
        final ok = rows.isNotEmpty && leaks.isEmpty;
        step(
          n,
          name,
          ok,
          query: 'GET /rest/v1/$table?$filter (anon key)',
          result: {
            'row_count': rows.length,
            'columns': rows.isEmpty ? [] : rows.first.keys.toList(),
            'sample': rows.isEmpty ? null : rows.first,
            if (leaks.isNotEmpty) 'leaks': leaks.toSet().toList(),
            if (extraCheck != null) 'note': extraCheck,
          },
          error: rows.isEmpty
              ? 'sem linhas — seller publicada mas view vazia'
              : (leaks.isNotEmpty ? 'colunas proibidas/inesperadas' : null),
        );
      } catch (e) {
        step(
          n,
          name,
          false,
          query: 'GET /rest/v1/$table (anon)',
          error: e.toString(),
        );
      }
    }

    await checkView(
      4,
      'hub_profiles_public campos públicos',
      'hub_profiles_public',
      'handle=eq.$_testHandle',
      allowedCols: _allowedProfileCols,
    );

    await checkView(
      5,
      'hub_lives_public playback sem stream keys',
      'hub_lives_public',
      'seller_id=eq.$sellerId',
      allowedCols: {
        'id',
        'seller_id',
        'seller_handle',
        'title',
        'status',
        'is_active',
        'mux_playback_id',
        'mux_vod_playback_id',
        'viewer_count',
        'went_live_at',
        'created_at',
        'publish_backend',
      },
    );

    await checkView(
      6,
      'hub_products_public marketplace',
      'hub_products_public',
      'seller_id=eq.$sellerId',
      allowedCols: {
        'id',
        'seller_id',
        'seller_handle',
        'title',
        'price',
        'image_urls',
        'category',
        'state',
        'description',
        'ref_code',
        'clothing_size',
        'gender',
        'created_at',
        'is_sold',
      },
    );

    await checkView(
      7,
      'hub_live_items_public catálogo',
      'hub_live_items_public',
      'seller_id=eq.$sellerId',
      allowedCols: {
        'id',
        'live_id',
        'seller_id',
        'seller_handle',
        'ref_code',
        'title',
        'photo_url',
        'price',
        'is_active',
        'status',
        'item_kind',
        'clothing_size',
        'gender',
        'created_at',
      },
    );

    if (testLiveWithMsgsId == null) {
      step(
        8,
        'hub_live_messages_public chat seguro',
        false,
        error: 'nenhuma live com mensagens para esta seller',
      );
    } else {
      await checkView(
        8,
        'hub_live_messages_public chat seguro',
        'hub_live_messages_public',
        'live_id=eq.$testLiveWithMsgsId',
        allowedCols: {
          'id',
          'live_id',
          'kind',
          'body',
          'sender_label',
          'tip_amount',
          'created_at',
        },
      );
    }

    // Step 9 FOMO
    Object? fomoResult;
    var fomoOk = false;
    final fomoLiveId = testLiveId ?? testLiveWithMsgsId;
    try {
      fomoResult = await client.rpc(
        'batata_hub_live_fomo_snapshot',
        {'p_live_id': fomoLiveId},
      );
      final jsonStr = jsonEncode(fomoResult);
      fomoOk = fomoResult is Map &&
          fomoResult['ok'] == true &&
          !jsonStr.contains('buyer_id') &&
          !jsonStr.contains('external_buyer_ref');
    } catch (e) {
      fomoResult = {'exception': e.toString()};
    }
    step(
      9,
      'batata_hub_live_fomo_snapshot agregados',
      fomoOk,
      query: 'rpc batata_hub_live_fomo_snapshot(live_id) as anon',
      result: fomoResult,
    );

    // --- Step 10 unpublish ---
    Object? unpublishResult;
    var unpublishOk = false;
    try {
      unpublishResult = await client.rpc(
        'batata_publish_hub',
        {'p_publish': false},
        accessToken: sellerToken,
      );
      unpublishOk = unpublishResult is Map &&
          unpublishResult['ok'] == true &&
          unpublishResult['hub_published'] == false;
    } catch (e) {
      unpublishResult = {'exception': e.toString()};
    }
    step(
      10,
      'publish_hub(false) remove vitrine',
      unpublishOk,
      query: 'rpc batata_publish_hub(false) as seller JWT',
      result: unpublishResult,
    );

    // Verify views empty after unpublish
    final afterProfile = await _selectAnon(
      client,
      'hub_profiles_public',
      filter: 'handle=eq.$_testHandle',
      limit: 1,
    );
    final afterResolve = await client.rpc(
      'batata_resolve_handle',
      {'p_handle': _testHandle},
    );
    final viewsEmptyOk = afterProfile.isEmpty &&
        afterResolve is Map &&
        afterResolve['found'] == false;
    step(
      11,
      'views públicas vazias após unpublish',
      viewsEmptyOk,
      query:
          "hub_profiles_public handle=$_testHandle + resolve_handle → 404",
      result: {
        'hub_profiles_rows': afterProfile.length,
        'resolve': afterResolve,
      },
    );

    // --- Teardown setup reversível ---
    if (testProductId != null && productMktBefore == false) {
      await client.patch(
        'products',
        'id=eq.$testProductId',
        {'list_on_marketplace': false},
      );
      log.writeln('teardown: list_on_marketplace revertido em $testProductId');
    }
  } catch (e, st) {
    log.writeln('FATAL: $e');
    log.writeln(st);
    failed++;
  }

  log.writeln('---');
  log.writeln('summary: ${failed == 0 ? 'ALL PASS' : '$failed FAIL(s)'}');
  log.writeln('finished_utc: ${DateTime.now().toUtc()}');

  Directory(_reportDir).createSync(recursive: true);
  final stamp = started.toIso8601String().replaceAll(':', '-');
  final mdPath = '$_reportDir/hub_publish_staging_functional_$stamp.md';
  final jsonPath = '$_reportDir/hub_publish_staging_functional_$stamp.json';
  File(mdPath).writeAsStringSync(log.toString());
  File(jsonPath).writeAsStringSync(
    jsonEncode({
      'started_utc': started.toIso8601String(),
      'finished_utc': DateTime.now().toUtc().toIso8601String(),
      'seller_id': sellerId,
      'test_handle': _testHandle,
      'failed_count': failed,
      'steps': steps,
    }),
  );

  print('Relatório: $mdPath');
  print('JSON: $jsonPath');
  print('---');
  for (final s in steps) {
    print('${s['ok'] == true ? 'PASS' : 'FAIL'}  Step ${s['step']}: ${s['name']}');
  }
  if (failed > 0) exitCode = 1;
}

Future<List<Map<String, dynamic>>> _selectAnon(
  LiveOpsStagingClient client,
  String table, {
  String? filter,
  int limit = 10,
}) async {
  var path = '${client.url}/rest/v1/$table?select=*';
  if (filter != null && filter.isNotEmpty) {
    path += '&$filter';
  }
  path += '&limit=$limit';
  final res = await http.get(
    Uri.parse(path),
    headers: {
      'apikey': client.anonKey,
      'Authorization': 'Bearer ${client.anonKey}',
    },
  );
  if (res.statusCode >= 400) {
    throw HttpException('anon select $table ${res.statusCode}: ${res.body}');
  }
  final list = jsonDecode(res.body);
  if (list is! List) return [];
  return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}
