import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/utils/live_catalog_sync.dart';

void main() {
  group('LiveCatalogSync allow-list (APP-200)', () {
    test('resolveAllowedMarketplaceProductIds prefere selecção prep', () async {
      final allowed = await LiveCatalogSync.resolveAllowedMarketplaceProductIds(
        sellerId: 'seller-1',
        liveId: 'live-1',
        existing: [],
        readPrepSelected: () async => {'p-selected'},
        findDraftLiveId: (_) async => 'draft-1',
        productIdsOnLive: (_) async => {'p-draft', 'p-live'},
      );
      expect(allowed, {'p-selected'});
    });

    test('resolveAllowedMarketplaceProductIds cai no draft se pref vazia', () async {
      final allowed = await LiveCatalogSync.resolveAllowedMarketplaceProductIds(
        sellerId: 'seller-1',
        liveId: 'live-1',
        existing: [],
        readPrepSelected: () async => {},
        findDraftLiveId: (_) async => 'draft-1',
        productIdsOnLive: (liveId) async {
          if (liveId == 'draft-1') return {'p-draft-a', 'p-draft-b'};
          return {'p-live'};
        },
      );
      expect(allowed, {'p-draft-a', 'p-draft-b'});
    });

    test('resolveAllowedMarketplaceProductIds prep/draft vazios → allow-list vazia', () async {
      var liveQueried = false;
      final allowed = await LiveCatalogSync.resolveAllowedMarketplaceProductIds(
        sellerId: 'seller-1',
        liveId: 'live-1',
        existing: [],
        readPrepSelected: () async => {},
        findDraftLiveId: (_) async => null,
        productIdsOnLive: (liveId) async {
          liveQueried = true;
          return {'p-on-live'};
        },
      );
      expect(allowed, isEmpty);
      expect(liveQueried, isFalse);
    });

    test('shouldPruneLiveOnlyRef: allow-list vazia NÃO apaga (Studio FX manuais)', () {
      expect(
        LiveCatalogSync.shouldPruneLiveOnlyRef(
          refNorm: 'FX1',
          allowedRefs: {},
        ),
        isFalse,
      );
    });

    test('shouldPruneLiveOnlyRef: fora da allow-list → apaga', () {
      expect(
        LiveCatalogSync.shouldPruneLiveOnlyRef(
          refNorm: 'FX2',
          allowedRefs: {'FX1'},
        ),
        isTrue,
      );
      expect(
        LiveCatalogSync.shouldPruneLiveOnlyRef(
          refNorm: 'FX1',
          allowedRefs: {'FX1', 'FX2'},
        ),
        isFalse,
      );
    });

    test('shouldPruneMarketplaceProduct com allow-list explícita', () {
      expect(
        LiveCatalogSync.shouldPruneMarketplaceProduct(
          productId: 'p-1',
          allowedProductIds: {'p-1'},
          availableForLive: true,
        ),
        isFalse,
      );
      expect(
        LiveCatalogSync.shouldPruneMarketplaceProduct(
          productId: 'p-junk',
          allowedProductIds: {'p-1'},
          availableForLive: true,
        ),
        isTrue,
      );
    });

    test('shouldPruneMarketplaceProduct allow-list vazia remove marketplace ON', () {
      expect(
        LiveCatalogSync.shouldPruneMarketplaceProduct(
          productId: 'p-off',
          allowedProductIds: {},
          availableForLive: false,
        ),
        isTrue,
      );
      expect(
        LiveCatalogSync.shouldPruneMarketplaceProduct(
          productId: 'p-on',
          allowedProductIds: {},
          availableForLive: true,
        ),
        isTrue,
      );
    });
  });
}
