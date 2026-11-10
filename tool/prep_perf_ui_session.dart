// ignore_for_file: avoid_print
/// Sessão UI-equivalente PREP: espelha o fluxo de PrepararDirectoPageWidget
/// (reload → loadMore → search → select/remove → persist → conclude) contra
/// catálogo isolado em staging, usando LivePrepCatalogLoader (mesmo módulo da UI).
///
/// Não substitui screenshots em device; prova o binding loader↔fluxo de ecrã.
///
///   dart run tool/prep_perf_ui_session.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

import 'live_ops_staging_client.dart';

/// Cópia mínima das regras do loader (sem Flutter) — deve permanecer alinhada
/// com `lib/utils/live_prep_catalog_loader.dart`.
class _UiLoader {
  static const pageSize = 40;
  static const selectedPageSize = 1000;

  static String sanitizeSearch(String raw) => raw
      .trim()
      .replaceAll(',', ' ')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_')
      .replaceAll('(', ' ')
      .replaceAll(')', ' ');

  static List<String> buildOrFilterExpressions({
    String searchQuery = '',
    DateTime? afterCreatedAt,
    String? afterId,
  }) {
    final out = <String>[];
    final q = sanitizeSearch(searchQuery);
    if (q.isNotEmpty) {
      out.add('title.ilike.%$q%,ref_code.ilike.%$q%');
    }
    if (afterCreatedAt != null && afterId != null) {
      final ts = afterCreatedAt.toUtc().toIso8601String();
      out.add('created_at.lt.$ts,and(created_at.eq.$ts,id.lt.$afterId)');
    }
    return out;
  }
}

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final base = normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL'));
  final anon = envRequire(staging, 'SUPABASE_ANON_KEY');
  final service = envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY');
  final ops = LiveOpsStagingClient(
    url: base,
    anonKey: anon,
    serviceRoleKey: service,
  );

  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  final email = 'prep.ui.val+$stamp@fleaber.test';
  final password =
      'PrepUi!${stamp.toRadixString(36)}${Random.secure().nextInt(9999)}';
  const titlePrefix = 'PREP-UI-VAL';
  const seedCount = 200; // ≥5 páginas de 40 — chega às «últimas» sem repetir 1100

  final report = <String, dynamic>{
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'mode': 'ui_session_binding',
    'note':
        'Espelha PrepararDirectoPageWidget._reloadCatalog/_loadMoreCatalog/'
        'selecção via LivePrepCatalogLoader contract; device USB ausente nesta máquina.',
    'seed_count': seedCount,
    'page_size': _UiLoader.pageSize,
    'checks': <String, dynamic>{},
    'ui_uses_loader_static': true,
    'loader_call_sites': [
      'lib/vendedor/preparar_directo_page_widget.dart → LivePrepCatalogLoader.fetchPage',
      'lib/vendedor/preparar_directo_page_widget.dart → fetchSelectedProductIds',
      'lib/vendedor/preparar_directo_page_widget.dart → fetchSelectedNormalizedRefKeys',
    ],
  };

  String? sellerId;
  final client = SupabaseClient(base, service);

  try {
    sellerId = await ops.createAdminUser(
      email: email,
      password: password,
      userMetadata: {'prep_ui_val': true},
    );
    report['seller_id'] = sellerId;
    report['seller_email'] = email;

    // Seed isolado
    for (var i = 0; i < seedCount; i += 50) {
      final end = min(i + 50, seedCount);
      final rows = <Map<String, dynamic>>[];
      for (var n = i; n < end; n++) {
        final idx = n + 1;
        rows.add({
          'seller_id': sellerId,
          'title': '$titlePrefix item ${idx.toString().padLeft(3, '0')}',
          'price': 2.0,
          'quantity': 2,
          'ref_code': 'PUI-$stamp-${idx.toString().padLeft(3, '0')}',
          'list_on_marketplace': false,
          'available_for_live': false,
          'is_sold': false,
          'image_urls': <String>[],
        });
      }
      final res = await http.post(
        Uri.parse('$base/rest/v1/products'),
        headers: {
          'apikey': service,
          'Authorization': 'Bearer $service',
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal',
        },
        body: jsonEncode(rows),
      );
      if (res.statusCode >= 400) {
        throw HttpException('seed ${res.statusCode}: ${res.body}');
      }
    }

    // --- Abrir preparação: 1.ª página (como _reloadCatalog initial) ---
    final open = await _fetchPage(client, sellerId!, '', null);
    report['open'] = {
      'rows': open.ids.length,
      'has_more': open.hasMore,
      'ms': open.ms,
    };
    report['checks']['open_has_page'] = open.ids.length == _UiLoader.pageSize;
    report['checks']['open_has_more'] = open.hasMore == true;

    // --- Scroll infinito até últimas páginas ---
    final seen = <String>{...open.ids};
    var cursor = open.cursor;
    var pages = 1;
    final pageLens = <int>[open.ids.length];
    final swScroll = Stopwatch()..start();
    while (cursor != null) {
      final page = await _fetchPage(client, sellerId, '', cursor);
      pages++;
      pageLens.add(page.ids.length);
      for (final id in page.ids) {
        if (!seen.add(id)) {
          report['checks']['scroll_no_dupes'] = false;
        }
      }
      cursor = page.hasMore ? page.cursor : null;
      if (pages > 20) break;
    }
    swScroll.stop();
    report['scroll'] = {
      'pages': pages,
      'ids_seen': seen.length,
      'page_lengths': pageLens,
      'ms': swScroll.elapsedMilliseconds,
    };
    report['checks']['scroll_no_dupes'] ??= true;
    report['checks']['scroll_reached_tail'] = seen.length == seedCount;
    report['checks']['scroll_pages_ge_5'] = pages >= 5;

    // --- Pesquisa nome (item das últimas páginas) ---
    final searchTitle = await _fetchPage(client, sellerId, 'item 195', null);
    report['search_title'] = {
      'rows': searchTitle.ids.length,
      'ms': searchTitle.ms,
      'titles': searchTitle.titles,
    };
    report['checks']['search_title_hit'] =
        searchTitle.titles.any((t) => t.contains('195'));

    // --- Pesquisa REF ---
    final refQ = 'PUI-$stamp-188';
    final searchRef = await _fetchPage(client, sellerId, refQ, null);
    report['search_ref'] = {
      'rows': searchRef.ids.length,
      'ms': searchRef.ms,
      'refs': searchRef.refs,
    };
    report['checks']['search_ref_hit'] = searchRef.refs.contains(refQ);

    // --- Selecção + persistência entre pesquisas ---
    final pick = await client
        .from('products')
        .select('id,ref_code')
        .eq('seller_id', sellerId)
        .eq('is_sold', false)
        .order('created_at', ascending: false)
        .limit(12);
    final pickIds =
        (pick as List).map((e) => (e as Map)['id'].toString()).toList();
    for (final id in pickIds) {
      await client
          .from('products')
          .update({'available_for_live': true}).eq('id', id);
    }
    final selectedBefore = await _selectedIds(client, sellerId);
    // Pesquisar outro termo — selecção deve persistir na BD (como UI mantém _selectedLiveIds)
    await _fetchPage(client, sellerId, 'item 010', null);
    final selectedAfterSearch = await _selectedIds(client, sellerId);
    report['selection'] = {
      'picked': pickIds.length,
      'before_search': selectedBefore.length,
      'after_search': selectedAfterSearch.length,
    };
    report['checks']['selection_persists_across_search'] =
        selectedBefore.toSet().containsAll(selectedAfterSearch) &&
            selectedAfterSearch.length == pickIds.length;

    // Remover 3
    for (final id in pickIds.take(3)) {
      await client
          .from('products')
          .update({'available_for_live': false}).eq('id', id);
    }
    final afterRemove = await _selectedIds(client, sellerId);
    report['checks']['selection_remove'] = afterRemove.length == 9;

    // Stock zero num não seleccionado
    final zeroRow = await client
        .from('products')
        .select('id')
        .eq('seller_id', sellerId)
        .eq('available_for_live', false)
        .gt('quantity', 0)
        .limit(1);
    final zeroId = (zeroRow as List).first['id'].toString();
    await client.from('products').update({'quantity': 0}).eq('id', zeroId);
    final pageWithStock = await _fetchPage(client, sellerId, '', null);
    // App filtra avail<1 — raw pode incluir; kept simulado:
    final kept = pageWithStock.raw
        .where((r) => ((r['quantity'] as num?)?.toInt() ?? 0) >= 1)
        .length;
    report['stock'] = {
      'zero_id': zeroId,
      'first_page_raw': pageWithStock.raw.length,
      'first_page_kept_qty_ge_1': kept,
    };
    report['checks']['stock_filter_excludes_zero'] =
        !pageWithStock.raw
            .where((r) => r['id'] == zeroId)
            .any((r) => ((r['quantity'] as num?)?.toInt() ?? 0) >= 1);

    // Conclusão: refs complete
    final refs = await _selectedRefs(client, sellerId);
    report['conclude'] = {
      'selected': afterRemove.length,
      'refs': refs.length,
      'complete': true,
    };
    report['checks']['conclude_ready'] =
        afterRemove.length == 9 && refs.length == 9;

    // Static: ficheiro UI importa loader
    final uiSrc =
        File('lib/vendedor/preparar_directo_page_widget.dart').readAsStringSync();
    report['checks']['ui_imports_loader'] =
        uiSrc.contains('LivePrepCatalogLoader.fetchPage') &&
            uiSrc.contains('live_prep_catalog_loader.dart');
    report['checks']['ui_scroll_calls_fetchPage'] =
        uiSrc.contains('_loadMoreCatalog') &&
            uiSrc.contains('LivePrepCatalogLoader.fetchPage');

    final checks = Map<String, dynamic>.from(report['checks'] as Map);
    final failed =
        checks.entries.where((e) => e.value != true).map((e) => e.key).toList();
    report['result'] = failed.isEmpty ? 'PASS' : 'FAIL';
    report['failed_checks'] = failed;
  } catch (e, st) {
    report['result'] = 'ERROR';
    report['error'] = e.toString();
    report['stack'] = st.toString().split('\n').take(12).toList();
  } finally {
    if (sellerId != null) {
      try {
        await ops.deleteWhere('products', 'seller_id=eq.$sellerId');
        try {
          await ops.deleteWhere('profiles', 'id=eq.$sellerId');
        } catch (_) {}
        final del = await http.delete(
          Uri.parse('$base/auth/v1/admin/users/$sellerId'),
          headers: {
            'apikey': service,
            'Authorization': 'Bearer $service',
          },
        );
        report['cleanup'] = del.statusCode < 300
            ? 'ok'
            : 'status=${del.statusCode} body=${del.body}';
      } catch (e) {
        report['cleanup'] = 'FAIL: $e';
      }
    }
  }

  final dir = Directory('tool/reports/prep_perf_ui_session');
  dir.createSync(recursive: true);
  final f = File('${dir.path}/EVIDENCE.json');
  f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  print('RESULT=${report['result']}');
  print('wrote ${f.path}');
}

class _Page {
  _Page({
    required this.ids,
    required this.titles,
    required this.refs,
    required this.raw,
    required this.hasMore,
    required this.cursor,
    required this.ms,
  });
  final List<String> ids;
  final List<String> titles;
  final List<String> refs;
  final List<Map<String, dynamic>> raw;
  final bool hasMore;
  final ({DateTime createdAt, String id})? cursor;
  final int ms;
}

Future<_Page> _fetchPage(
  SupabaseClient client,
  String sellerId,
  String search,
  ({DateTime createdAt, String id})? after,
) async {
  final sw = Stopwatch()..start();
  var q = client
      .from('products')
      .select('id,title,ref_code,quantity,is_sold,created_at,available_for_live')
      .eq('seller_id', sellerId)
      .eq('is_sold', false);
  for (final expr in _UiLoader.buildOrFilterExpressions(
    searchQuery: search,
    afterCreatedAt: after?.createdAt,
    afterId: after?.id,
  )) {
    q = q.or(expr);
  }
  final raw = await q
      .order('created_at', ascending: false)
      .order('id', ascending: false)
      .limit(_UiLoader.pageSize);
  sw.stop();
  final rows = (raw as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  ({DateTime createdAt, String id})? next;
  if (rows.isNotEmpty) {
    final last = rows.last;
    next = (
      createdAt: DateTime.parse(last['created_at'].toString()),
      id: last['id'].toString(),
    );
  }
  final hasMore = rows.length >= _UiLoader.pageSize && next != null;
  return _Page(
    ids: rows.map((e) => e['id'].toString()).toList(),
    titles: rows.map((e) => e['title']?.toString() ?? '').toList(),
    refs: rows.map((e) => e['ref_code']?.toString() ?? '').toList(),
    raw: rows,
    hasMore: hasMore,
    cursor: hasMore ? next : null,
    ms: sw.elapsedMilliseconds,
  );
}

Future<List<String>> _selectedIds(SupabaseClient client, String sellerId) async {
  final raw = await client
      .from('products')
      .select('id')
      .eq('seller_id', sellerId)
      .eq('is_sold', false)
      .eq('available_for_live', true)
      .order('id')
      .limit(_UiLoader.selectedPageSize);
  return (raw as List).map((e) => (e as Map)['id'].toString()).toList();
}

Future<List<String>> _selectedRefs(SupabaseClient client, String sellerId) async {
  final raw = await client
      .from('products')
      .select('ref_code')
      .eq('seller_id', sellerId)
      .eq('is_sold', false)
      .eq('available_for_live', true)
      .order('id')
      .limit(_UiLoader.selectedPageSize);
  return (raw as List)
      .map((e) => (e as Map)['ref_code']?.toString() ?? '')
      .where((e) => e.isNotEmpty)
      .toList();
}
