// ignore_for_file: avoid_print
/// Integração real PREP-PERF em staging (catálogo isolado ≥1000).
///
/// Espelha os filtros PostgREST de `LivePrepCatalogLoader` (dois `.or()` AND +
/// keyset `created_at`+`id` DESC). Não toca em contas de clientes.
///
///   dart run tool/prep_perf_staging_integration.dart
///
/// Cleanup: apaga produtos com title prefix + user admin criado nesta corrida.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const _titlePrefix = 'PREP-PERF-VAL';
const _targetCount = 1100;
const _pageSize = 40;
const _selectedPageSize = 1000;
const _selectedHardCap = 100000;

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  final email = 'prep.perf.val+$stamp@fleaber.test';
  final password =
      'PrepVal!${stamp.toRadixString(36)}${Random.secure().nextInt(9999)}';

  final report = <String, dynamic>{
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'project': client.url,
    'isolated': true,
    'title_prefix': _titlePrefix,
    'target_count': _targetCount,
    'page_size': _pageSize,
    'checks': <String, dynamic>{},
    'timings_ms': <String, dynamic>{},
    'request_counts': <String, int>{},
  };

  String? sellerId;
  var seeded = 0;

  try {
    final swCreate = Stopwatch()..start();
    sellerId = await client.createAdminUser(
      email: email,
      password: password,
      userMetadata: {'prep_perf_val': true, 'stamp': stamp},
    );
    swCreate.stop();
    report['seller_id'] = sellerId;
    report['seller_email'] = email;
    report['timings_ms']['create_user'] = swCreate.elapsedMilliseconds;

    // Seed em lotes via REST (service_role).
    final swSeed = Stopwatch()..start();
    var reqSeed = 0;
    for (var i = 0; i < _targetCount; i += 100) {
      final end = min(i + 100, _targetCount);
      final rows = <Map<String, dynamic>>[];
      for (var n = i; n < end; n++) {
        final idx = n + 1;
        rows.add({
          'seller_id': sellerId,
          'title': '$_titlePrefix item ${idx.toString().padLeft(4, '0')}',
          'price': 1.0 + (idx % 50) * 0.1,
          'quantity': 1 + (idx % 5),
          'ref_code': 'PPV-$stamp-${idx.toString().padLeft(4, '0')}',
          'list_on_marketplace': false,
          'available_for_live': false,
          'is_sold': false,
          'image_urls': <String>[],
          'description': 'isolado prep-perf validacao',
        });
      }
      await _insertBatch(client, rows);
      reqSeed++;
      seeded += rows.length;
      if (seeded % 300 == 0 || seeded == _targetCount) {
        print('seeded $seeded/$_targetCount');
      }
    }
    swSeed.stop();
    report['seeded'] = seeded;
    report['timings_ms']['seed'] = swSeed.elapsedMilliseconds;
    report['request_counts']['seed_batches'] = reqSeed;

    // Contagem BD
    final dbCount = await client.countRows(
      'products',
      filter: 'seller_id=eq.$sellerId&is_sold=eq.false',
    );
    report['db_unsold_count'] = dbCount;
    report['checks']['seed_count_ok'] = dbCount == seeded;

    // --- A) Full catalog walk (keyset + dual or) ---
    final walk = await _walkCatalog(
      client: client,
      sellerId: sellerId!,
      searchQuery: '',
    );
    report['timings_ms']['full_walk'] = walk['elapsed_ms'];
    report['request_counts']['full_walk_pages'] = walk['pages'];
    report['full_walk'] = {
      'ids_seen': walk['ids_seen'],
      'pages': walk['pages'],
      'dupes': walk['dupes'],
      'page_ms': walk['page_ms'],
    };
    report['checks']['full_walk_no_dupes'] = (walk['dupes'] as int) == 0;
    report['checks']['full_walk_covers_all'] =
        (walk['ids_seen'] as int) == dbCount;

    // --- B) Search by title for item near the end (likely unloaded) ---
    final lateTitle = '$_titlePrefix item 1095';
    final searchTitle = await _walkCatalog(
      client: client,
      sellerId: sellerId,
      searchQuery: 'item 1095',
    );
    report['timings_ms']['search_title'] = searchTitle['elapsed_ms'];
    report['request_counts']['search_title_pages'] = searchTitle['pages'];
    report['search_title'] = searchTitle;
    final titleHit = await client.select(
      'products',
      filter:
          'seller_id=eq.$sellerId&is_sold=eq.false&title=ilike.*item 1095*&select=id,title,ref_code',
      limit: 5,
    );
    report['checks']['search_title_finds_unloaded'] =
        (searchTitle['ids_seen'] as int) >= 1 && titleHit.isNotEmpty;

    // --- C) Search by ref_code ---
    final lateRef = 'PPV-$stamp-1088';
    final searchRef = await _walkCatalog(
      client: client,
      sellerId: sellerId,
      searchQuery: lateRef,
    );
    report['timings_ms']['search_ref'] = searchRef['elapsed_ms'];
    report['request_counts']['search_ref_pages'] = searchRef['pages'];
    report['search_ref'] = searchRef;
    report['checks']['search_ref_finds_unloaded'] =
        (searchRef['ids_seen'] as int) == 1;

    // --- D) Dual .or() + keyset: first page then second with search ---
    final page1 = await _fetchPage(
      client: client,
      sellerId: sellerId,
      searchQuery: _titlePrefix,
      after: null,
    );
    final page2 = await _fetchPage(
      client: client,
      sellerId: sellerId,
      searchQuery: _titlePrefix,
      after: page1['next_cursor'] as Map<String, String>?,
    );
    final overlap = (page1['ids'] as List).toSet().intersection(
      (page2['ids'] as List).toSet(),
    );
    report['dual_or_keyset'] = {
      'page1_count': (page1['ids'] as List).length,
      'page2_count': (page2['ids'] as List).length,
      'overlap': overlap.length,
      'page1_ms': page1['elapsed_ms'],
      'page2_ms': page2['elapsed_ms'],
      'page1_url_ors': page1['or_count'],
      'page2_url_ors': page2['or_count'],
    };
    report['checks']['dual_or_keyset_no_overlap'] = overlap.isEmpty;
    report['checks']['dual_or_keyset_page2_has_rows'] =
        (page2['ids'] as List).isNotEmpty;

    // --- E) Selection + persistence + refs complete ---
    final pick = await client.select(
      'products',
      filter:
          'seller_id=eq.$sellerId&is_sold=eq.false&order=created_at.desc&select=id,ref_code',
      limit: 25,
    );
    final pickIds = pick.map((e) => e['id'].toString()).toList();
    final swSel = Stopwatch()..start();
    for (final id in pickIds) {
      await client.patch('products', 'id=eq.$id', {'available_for_live': true});
    }
    swSel.stop();
    report['timings_ms']['select_25'] = swSel.elapsedMilliseconds;
    report['request_counts']['select_patches'] = pickIds.length;

    final selected = await _fetchSelectedIds(client, sellerId);
    report['selected_ids'] = selected;
    report['checks']['selected_count_25'] = selected['ids_count'] == 25;
    report['checks']['selected_complete'] = selected['complete'] == true;

    final refs = await _fetchSelectedRefs(client, sellerId);
    report['selected_refs'] = refs;
    report['checks']['selected_refs_complete'] = refs['complete'] == true;
    report['checks']['selected_refs_count_25'] = refs['keys_count'] == 25;

    // Remove 5 during "search context"
    final removeIds = pickIds.take(5).toList();
    for (final id in removeIds) {
      await client.patch('products', 'id=eq.$id', {'available_for_live': false});
    }
    final afterRemove = await _fetchSelectedIds(client, sellerId);
    report['after_remove'] = afterRemove;
    report['checks']['after_remove_20'] = afterRemove['ids_count'] == 20;

    // Persist: re-read
    final persist = await _fetchSelectedIds(client, sellerId);
    report['checks']['selection_persisted'] =
        persist['ids_count'] == 20 &&
        (persist['ids'] as List).toSet().intersection(removeIds.toSet()).isEmpty;

    // --- F) Stock filter: qty 0 on a non-selected product (não alterar seleção) ---
    final zeroCandidates = await client.select(
      'products',
      filter:
          'seller_id=eq.$sellerId&is_sold=eq.false&available_for_live=eq.false&quantity=gt.0&order=created_at.asc&select=id',
      limit: 1,
    );
    final zeroId = zeroCandidates.first['id'].toString();
    await client.patch('products', 'id=eq.$zeroId', {
      'quantity': 0,
      'available_for_live': false,
    });
    final zeroPage = await _fetchPage(
      client: client,
      sellerId: sellerId,
      searchQuery: '',
      after: null,
      preferSelect: 'id,title,quantity,is_sold,created_at',
    );
    final zeroInRaw = (zeroPage['raw'] as List).any(
      (e) => (e as Map)['id']?.toString() == zeroId,
    );
    // May or may not be on first page; verify via direct filter + document app rule.
    final zeroRow = await client.select(
      'products',
      filter: 'id=eq.$zeroId&select=id,quantity,is_sold',
      limit: 1,
    );
    report['stock_zero'] = {
      'product_id': zeroId,
      'quantity': zeroRow.first['quantity'],
      'note':
          'LivePrepCatalogLoader keep filter: avail<1 || isSold → omit from kept; cursor uses raw last.',
      'zero_in_first_page_raw': zeroInRaw,
    };
    report['checks']['stock_zero_row_updated'] = zeroRow.first['quantity'] == 0;

    // --- G) Out-of-order responses simulation (two pages concurrent) ---
    final swOoo = Stopwatch()..start();
    final fA = _fetchPage(
      client: client,
      sellerId: sellerId,
      searchQuery: '',
      after: null,
    );
    final fB = _fetchPage(
      client: client,
      sellerId: sellerId,
      searchQuery: 'PPV-$stamp-0500',
      after: null,
    );
    final results = await Future.wait([fA, fB]);
    swOoo.stop();
    report['timings_ms']['ooo_parallel'] = swOoo.elapsedMilliseconds;
    report['ooo'] = {
      'page_browse_count': (results[0]['ids'] as List).length,
      'page_search_count': (results[1]['ids'] as List).length,
      'note':
          'API aceita pedidos paralelos; UI deve descartar respostas stale por geração — ver widget.',
    };
    report['checks']['ooo_parallel_ok'] =
        (results[0]['ids'] as List).isNotEmpty &&
        (results[1]['ids'] as List).length == 1;

    // Conclude prep: ensure selected still complete after mutations
    final concludeIds = await _fetchSelectedIds(client, sellerId);
    final concludeRefs = await _fetchSelectedRefs(client, sellerId);
    report['conclude'] = {
      'selected_ids': concludeIds['ids_count'],
      'selected_complete': concludeIds['complete'],
      'refs_complete': concludeRefs['complete'],
      'refs_count': concludeRefs['keys_count'],
    };
    report['checks']['conclude_ready'] =
        concludeIds['complete'] == true &&
        concludeRefs['complete'] == true &&
        (concludeIds['ids_count'] as int) == 20;

    // Aggregate pass
    final checks = Map<String, dynamic>.from(report['checks'] as Map);
    final failed = checks.entries.where((e) => e.value != true).toList();
    report['result'] = failed.isEmpty ? 'PASS' : 'FAIL';
    report['failed_checks'] = failed.map((e) => e.key).toList();
  } catch (e, st) {
    report['result'] = 'ERROR';
    report['error'] = e.toString();
    report['stack'] = st.toString().split('\n').take(12).toList();
  } finally {
    // Cleanup isolado
    if (sellerId != null) {
      try {
        final swClean = Stopwatch()..start();
        await client.deleteWhere('products', 'seller_id=eq.$sellerId');
        try {
          await client.deleteWhere('profiles', 'id=eq.$sellerId');
        } catch (_) {
          // profiles pode não existir / RLS — continuar
        }
        await _deleteAdminUser(client, sellerId);
        swClean.stop();
        report['timings_ms']['cleanup'] = swClean.elapsedMilliseconds;
        report['cleanup'] = 'ok';
      } catch (e) {
        report['cleanup'] = 'FAIL: $e';
      }
    }
  }

  final outDir = Directory('tool/reports/prep_perf_staging_integration');
  outDir.createSync(recursive: true);
  final outFile = File('${outDir.path}/EVIDENCE.json');
  outFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  print('RESULT=${report['result']}');
  print('wrote ${outFile.path}');
  if (report['failed_checks'] != null) {
    print('failed_checks=${jsonEncode(report['failed_checks'])}');
  }
}

Future<void> _insertBatch(
  LiveOpsStagingClient client,
  List<Map<String, dynamic>> rows,
) async {
  final res = await http.post(
    Uri.parse('${client.url}/rest/v1/products'),
    headers: {
      'apikey': client.serviceRoleKey,
      'Authorization': 'Bearer ${client.serviceRoleKey}',
      'Content-Type': 'application/json',
      'Prefer': 'return=minimal',
    },
    body: jsonEncode(rows),
  );
  if (res.statusCode >= 400) {
    throw HttpException('insert batch ${res.statusCode}: ${res.body}');
  }
}

Future<void> _deleteAdminUser(LiveOpsStagingClient client, String id) async {
  final res = await http.delete(
    Uri.parse('${client.url}/auth/v1/admin/users/$id'),
    headers: {
      'apikey': client.serviceRoleKey,
      'Authorization': 'Bearer ${client.serviceRoleKey}',
    },
  );
  if (res.statusCode >= 400) {
    throw HttpException('deleteAdminUser ${res.statusCode}: ${res.body}');
  }
}

List<String> _buildOrExprs({
  required String searchQuery,
  Map<String, String>? after,
}) {
  final out = <String>[];
  final q = searchQuery
      .trim()
      .replaceAll(',', ' ')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_')
      .replaceAll('(', ' ')
      .replaceAll(')', ' ');
  if (q.isNotEmpty) {
    out.add('title.ilike.*$q*,ref_code.ilike.*$q*');
  }
  if (after != null) {
    final ts = after['created_at']!;
    final id = after['id']!;
    out.add('created_at.lt.$ts,and(created_at.eq.$ts,id.lt.$id)');
  }
  return out;
}

Future<Map<String, dynamic>> _fetchPage({
  required LiveOpsStagingClient client,
  required String sellerId,
  required String searchQuery,
  Map<String, String>? after,
  String preferSelect = 'id,title,ref_code,quantity,is_sold,created_at',
}) async {
  final sw = Stopwatch()..start();
  final ors = _buildOrExprs(searchQuery: searchQuery, after: after);
  final qp = <String, String>{
    'select': preferSelect,
    'seller_id': 'eq.$sellerId',
    'is_sold': 'eq.false',
    'order': 'created_at.desc,id.desc',
    'limit': '$_pageSize',
  };
  // Dois `or` na query string (AND) — espelha postgrest-dart appendSearchParams.
  final parts = <String>[];
  qp.forEach((k, v) => parts.add('$k=${Uri.encodeQueryComponent(v)}'));
  for (final expr in ors) {
    parts.add('or=${Uri.encodeQueryComponent('($expr)')}');
  }
  final uri = Uri.parse('${client.url}/rest/v1/products?${parts.join('&')}');
  final res = await http.get(
    uri,
    headers: {
      'apikey': client.serviceRoleKey,
      'Authorization': 'Bearer ${client.serviceRoleKey}',
    },
  );
  sw.stop();
  if (res.statusCode >= 400) {
    throw HttpException('fetchPage ${res.statusCode}: ${res.body}');
  }
  final raw = (jsonDecode(res.body) as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  final ids = raw.map((e) => e['id'].toString()).toList();
  Map<String, String>? next;
  if (raw.isNotEmpty) {
    final last = raw.last;
    next = {
      'created_at': DateTime.parse(
        last['created_at'].toString(),
      ).toUtc().toIso8601String(),
      'id': last['id'].toString(),
    };
  }
  final hasMore = raw.length >= _pageSize && next != null;
  return {
    'ids': ids,
    'raw': raw,
    'next_cursor': hasMore ? next : null,
    'has_more': hasMore,
    'elapsed_ms': sw.elapsedMilliseconds,
    'or_count': ors.length,
    'request_url_or_params': ors.length,
  };
}

Future<Map<String, dynamic>> _walkCatalog({
  required LiveOpsStagingClient client,
  required String sellerId,
  required String searchQuery,
}) async {
  final sw = Stopwatch()..start();
  final seen = <String>{};
  var dupes = 0;
  var pages = 0;
  final pageMs = <int>[];
  Map<String, String>? cursor;
  while (true) {
    final page = await _fetchPage(
      client: client,
      sellerId: sellerId,
      searchQuery: searchQuery,
      after: cursor,
    );
    pages++;
    pageMs.add(page['elapsed_ms'] as int);
    for (final id in page['ids'] as List) {
      final s = id.toString();
      if (!seen.add(s)) dupes++;
    }
    if (page['has_more'] != true) break;
    cursor = page['next_cursor'] as Map<String, String>?;
    if (cursor == null) break;
    if (pages > 200) {
      break; // safety
    }
  }
  sw.stop();
  return {
    'ids_seen': seen.length,
    'dupes': dupes,
    'pages': pages,
    'elapsed_ms': sw.elapsedMilliseconds,
    'page_ms': pageMs,
    'avg_page_ms': pageMs.isEmpty
        ? 0
        : (pageMs.reduce((a, b) => a + b) / pageMs.length).round(),
    'max_page_ms': pageMs.isEmpty ? 0 : pageMs.reduce(max),
  };
}

Future<Map<String, dynamic>> _fetchSelectedIds(
  LiveOpsStagingClient client,
  String sellerId,
) async {
  final all = <String>[];
  var offset = 0;
  var pages = 0;
  while (true) {
    final to = offset + _selectedPageSize - 1;
    final res = await http.get(
      Uri.parse(
        '${client.url}/rest/v1/products?select=id&seller_id=eq.$sellerId&is_sold=eq.false&available_for_live=eq.true&order=id.asc&offset=$offset&limit=$_selectedPageSize',
      ),
      headers: {
        'apikey': client.serviceRoleKey,
        'Authorization': 'Bearer ${client.serviceRoleKey}',
        'Range': '$offset-$to',
      },
    );
    pages++;
    if (res.statusCode >= 400) {
      throw HttpException('selected ids ${res.statusCode}: ${res.body}');
    }
    final batch = (jsonDecode(res.body) as List)
        .map((e) => (e as Map)['id'].toString())
        .toList();
    all.addAll(batch);
    if (batch.length < _selectedPageSize) {
      return {
        'ids': all,
        'ids_count': all.length,
        'complete': true,
        'pages': pages,
      };
    }
    offset += batch.length;
    if (all.length >= _selectedHardCap) {
      return {
        'ids': all,
        'ids_count': all.length,
        'complete': false,
        'pages': pages,
      };
    }
  }
}

Future<Map<String, dynamic>> _fetchSelectedRefs(
  LiveOpsStagingClient client,
  String sellerId,
) async {
  final keys = <String>{};
  var offset = 0;
  var pages = 0;
  while (true) {
    final to = offset + _selectedPageSize - 1;
    final res = await http.get(
      Uri.parse(
        '${client.url}/rest/v1/products?select=id,ref_code&seller_id=eq.$sellerId&is_sold=eq.false&available_for_live=eq.true&order=id.asc&offset=$offset&limit=$_selectedPageSize',
      ),
      headers: {
        'apikey': client.serviceRoleKey,
        'Authorization': 'Bearer ${client.serviceRoleKey}',
        'Range': '$offset-$to',
      },
    );
    pages++;
    if (res.statusCode >= 400) {
      throw HttpException('selected refs ${res.statusCode}: ${res.body}');
    }
    final batch = jsonDecode(res.body) as List;
    for (final e in batch) {
      final ref = ((e as Map)['ref_code']?.toString() ?? '')
          .trim()
          .toUpperCase();
      if (ref.isNotEmpty) keys.add(ref);
    }
    if (batch.length < _selectedPageSize) {
      return {
        'keys_count': keys.length,
        'complete': true,
        'pages': pages,
      };
    }
    offset += batch.length;
    if (offset >= _selectedHardCap) {
      return {
        'keys_count': keys.length,
        'complete': false,
        'pages': pages,
      };
    }
  }
}
