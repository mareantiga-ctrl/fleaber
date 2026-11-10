import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/live_prep_catalog_loader.dart';

void main() {
  test('sanitizeSearch removes PostgREST or-breakers', () {
    expect(
      LivePrepCatalogLoader.sanitizeSearch('  camisa, 100% algodão (M) '),
      isNot(contains(',')),
    );
    expect(
      LivePrepCatalogLoader.sanitizeSearch('a%b_c'),
      contains(r'\%'),
    );
    expect(LivePrepCatalogLoader.pageSize, 40);
  });

  test('selected hard cap is explicit (not silent 5000)', () {
    expect(LivePrepCatalogLoader.selectedPageSize, 1000);
    expect(LivePrepCatalogLoader.selectedHardCap, greaterThan(5000));
  });

  test('buildOrFilterExpressions: search + cursor are separate AND groups', () {
    final cursor = LivePrepCatalogCursor(
      createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      id: 'uuid-1',
    );
    final exprs = LivePrepCatalogLoader.buildOrFilterExpressions(
      searchQuery: 'camisa',
      after: cursor,
    );
    expect(exprs, hasLength(2));
    expect(exprs[0], contains('title.ilike'));
    expect(exprs[0], contains('ref_code.ilike'));
    expect(exprs[1], contains('created_at.lt.'));
    expect(exprs[1], contains('id.lt.uuid-1'));
  });

  test('buildOrFilterExpressions: empty search skips search or-group', () {
    expect(
      LivePrepCatalogLoader.buildOrFilterExpressions(searchQuery: '  '),
      isEmpty,
    );
    final onlyCursor = LivePrepCatalogLoader.buildOrFilterExpressions(
      after: LivePrepCatalogCursor(
        createdAt: DateTime.utc(2026, 5, 1),
        id: 'z',
      ),
    );
    expect(onlyCursor, hasLength(1));
  });
}
