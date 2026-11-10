import 'package:flutter/foundation.dart';

import '/backend/supabase/supabase.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_prep_ref_details.dart';

/// Cursor estável (não depende de `available_for_live`).
class LivePrepCatalogCursor {
  const LivePrepCatalogCursor({
    required this.createdAt,
    required this.id,
  });

  final DateTime createdAt;
  final String id;
}

/// Página de catálogo para preparação de directo (server-side).
class LivePrepCatalogPage {
  const LivePrepCatalogPage({
    required this.rows,
    required this.qtyByProductId,
    required this.hasMore,
    required this.nextCursor,
    required this.fetchedRawCount,
    required this.elapsedMs,
  });

  final List<ProductsRow> rows;
  final Map<String, int> qtyByProductId;
  final bool hasMore;

  /// Próximo cursor keyset (`created_at`+`id` do último raw da página).
  final LivePrepCatalogCursor? nextCursor;
  final int fetchedRawCount;
  final int elapsedMs;
}

class LivePrepSelectedIdsResult {
  const LivePrepSelectedIdsResult({
    required this.ids,
    required this.complete,
    required this.pagesFetched,
  });

  final List<String> ids;

  /// `false` só se bater no teto de segurança (não truncar em silêncio).
  final bool complete;
  final int pagesFetched;
}

class LivePrepSelectedRefsResult {
  const LivePrepSelectedRefsResult({
    required this.keys,
    required this.complete,
    required this.pagesFetched,
  });

  final Set<String> keys;
  final bool complete;
  final int pagesFetched;
}

/// Carregamento paginado + pesquisa server-side do catálogo de prep.
///
/// Ordenação estável: `created_at DESC, id DESC` — **não** usa
/// `available_for_live` (muda ao seleccionar → omitiria/repetiria com offset).
abstract final class LivePrepCatalogLoader {
  static const pageSize = 40;
  static const selectedPageSize = 1000;

  /// Teto de segurança; se atingido, `complete=false` (nunca truncar sem flag).
  static const selectedHardCap = 100000;

  /// Escape mínimo para filtros `ilike` / `or` do PostgREST.
  static String sanitizeSearch(String raw) {
    return raw
        .trim()
        .replaceAll(',', ' ')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_')
        .replaceAll('(', ' ')
        .replaceAll(')', ' ');
  }

  /// Expressões `or=(...)` PostgREST acumuladas (AND entre grupos).
  ///
  /// postgrest-dart `appendSearchParams` **acrescenta** valores à mesma key
  /// (`queryParametersAll`), não substitui. Dois `.or()` ⇒
  /// `seller_id AND is_sold AND (título|ref) AND (cursor)`.
  static List<String> buildOrFilterExpressions({
    String searchQuery = '',
    LivePrepCatalogCursor? after,
  }) {
    final out = <String>[];
    final q = sanitizeSearch(searchQuery);
    if (q.isNotEmpty) {
      out.add('title.ilike.%$q%,ref_code.ilike.%$q%');
    }
    if (after != null) {
      final ts = after.createdAt.toUtc().toIso8601String();
      final id = after.id;
      out.add('created_at.lt.$ts,and(created_at.eq.$ts,id.lt.$id)');
    }
    return out;
  }

  static Future<LivePrepCatalogPage> fetchPage({
    required String sellerId,
    LivePrepCatalogCursor? after,
    String searchQuery = '',
    int limit = pageSize,
  }) async {
    final sw = Stopwatch()..start();
    final sid = sellerId.trim();
    if (sid.isEmpty) {
      return const LivePrepCatalogPage(
        rows: [],
        qtyByProductId: {},
        hasMore: false,
        nextCursor: null,
        fetchedRawCount: 0,
        elapsedMs: 0,
      );
    }

    var filter = SupaFlow.client
        .from('products')
        .select()
        .eq('seller_id', sid)
        .eq('is_sold', false)
        .eq('is_draft', false);

    for (final expr in buildOrFilterExpressions(
      searchQuery: searchQuery,
      after: after,
    )) {
      filter = filter.or(expr);
    }

    final raw = await filter
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);

    final rows = (raw as List<dynamic>)
        .map((e) => ProductsRow(Map<String, dynamic>.from(e as Map)))
        .toList();

    final ids = rows
        .map((r) => r.id?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    final snaps =
        await LiveCatalogStockService.fetchForMarketplaceProductsBatch(ids);

    final qtyById = <String, int>{};
    final kept = <ProductsRow>[];
    for (final row in rows) {
      final pid = row.id?.trim() ?? '';
      if (pid.isEmpty) continue;
      final snap = snaps[pid];
      final avail = snap?.availableQty ?? row.quantity;
      if (avail < 1 || row.isSold) continue;
      qtyById[pid] = avail;
      kept.add(row);
    }

    LivePrepCatalogCursor? nextCursor;
    if (rows.isNotEmpty) {
      final last = rows.last;
      final lastId = last.id?.trim() ?? '';
      final lastAt = last.createdAt;
      if (lastId.isNotEmpty && lastAt != null) {
        nextCursor = LivePrepCatalogCursor(createdAt: lastAt, id: lastId);
      }
    }

    sw.stop();
    final hasMore = rows.length >= limit && nextCursor != null;
    if (kDebugMode) {
      debugPrint(
        '[LivePrepCatalog] cursor=${after?.id ?? "start"} '
        'ors=${buildOrFilterExpressions(searchQuery: searchQuery, after: after).length} '
        'raw=${rows.length} kept=${kept.length} hasMore=$hasMore '
        'ms=${sw.elapsedMilliseconds}',
      );
    }

    return LivePrepCatalogPage(
      rows: kept,
      qtyByProductId: qtyById,
      hasMore: hasMore,
      nextCursor: hasMore ? nextCursor : null,
      fetchedRawCount: rows.length,
      elapsedMs: sw.elapsedMilliseconds,
    );
  }

  /// Todos os IDs `available_for_live` (paginado). Nunca trunca sem `complete=false`.
  static Future<LivePrepSelectedIdsResult> fetchSelectedProductIds({
    required String sellerId,
  }) async {
    final sid = sellerId.trim();
    if (sid.isEmpty) {
      return const LivePrepSelectedIdsResult(
        ids: [],
        complete: true,
        pagesFetched: 0,
      );
    }

    final all = <String>[];
    var offset = 0;
    var pages = 0;
    while (true) {
      final to = offset + selectedPageSize - 1;
      final raw = await SupaFlow.client
          .from('products')
          .select('id')
          .eq('seller_id', sid)
          .eq('is_sold', false)
          .eq('available_for_live', true)
          .eq('is_draft', false)
          .order('id', ascending: true)
          .range(offset, to);
      pages++;
      final batch = (raw as List<dynamic>)
          .map((e) => (e as Map)['id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      all.addAll(batch);
      if (batch.length < selectedPageSize) {
        return LivePrepSelectedIdsResult(
          ids: all,
          complete: true,
          pagesFetched: pages,
        );
      }
      offset += batch.length;
      if (all.length >= selectedHardCap) {
        debugPrint(
          '[LivePrepCatalog] selected IDs hit hard cap $selectedHardCap — incomplete',
        );
        return LivePrepSelectedIdsResult(
          ids: all,
          complete: false,
          pagesFetched: pages,
        );
      }
    }
  }

  /// REF normalizadas dos seleccionados. Incompleto ⇒ `complete=false` (nunca silencioso).
  static Future<LivePrepSelectedRefsResult> fetchSelectedNormalizedRefKeys({
    required String sellerId,
  }) async {
    final sid = sellerId.trim();
    if (sid.isEmpty) {
      return const LivePrepSelectedRefsResult(
        keys: {},
        complete: true,
        pagesFetched: 0,
      );
    }

    final keys = <String>{};
    var offset = 0;
    var pages = 0;
    while (true) {
      final to = offset + selectedPageSize - 1;
      final raw = await SupaFlow.client
          .from('products')
          .select('id,ref_code')
          .eq('seller_id', sid)
          .eq('is_sold', false)
          .eq('available_for_live', true)
          .eq('is_draft', false)
          .order('id', ascending: true)
          .range(offset, to);
      pages++;
      final batch = raw as List<dynamic>;
      for (final e in batch) {
        final m = Map<String, dynamic>.from(e as Map);
        final ref = LivePrepRefDetails.normalizeRefKey(
          m['ref_code']?.toString() ?? '',
        );
        if (ref.isNotEmpty) keys.add(ref);
      }
      if (batch.length < selectedPageSize) {
        return LivePrepSelectedRefsResult(
          keys: keys,
          complete: true,
          pagesFetched: pages,
        );
      }
      offset += batch.length;
      if (offset >= selectedHardCap) {
        debugPrint(
          '[LivePrepCatalog] selected refs hit hard cap — incomplete',
        );
        return LivePrepSelectedRefsResult(
          keys: keys,
          complete: false,
          pagesFetched: pages,
        );
      }
    }
  }
}
