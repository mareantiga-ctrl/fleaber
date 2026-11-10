import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/utils/live_bag_copy.dart';
import 'package:fleaber/widgets/live_vendor_ops_ui.dart';

void main() {
  group('LiveBagCopy', () {
    test('C6 saco: 2 artigos distintos · 3 unidades', () {
      expect(
        LiveBagCopy.headerSubtitle(articleCount: 2, unitCount: 3),
        '2 artigos · 3 unidades',
      );
    });

    test('singular', () {
      expect(
        LiveBagCopy.headerSubtitle(articleCount: 1, unitCount: 1),
        '1 artigo · 1 unidade',
      );
    });

    test('com cancelados', () {
      expect(
        LiveBagCopy.headerSubtitle(
          articleCount: 2,
          unitCount: 3,
          cancelledCount: 1,
        ),
        '2 artigos · 3 unidades · 1 cancelado',
      );
    });
  });

  group('LiveVendorSellerCopy — marcar como esgotado', () {
    test('selo operacional não diz VENDIDO', () {
      expect(LiveVendorSellerCopy.soldOutBadge('sold'), 'ESGOTADO');
      expect(LiveVendorSellerCopy.soldOutBadge('reserved_full'), 'ESGOTADO');
      expect(LiveVendorSellerCopy.liveCatalogUnavailableActionLabel('sold'),
          'Esgotado');
    });

    test('status interno sold continua a ser o marcador manual', () {
      expect(LiveVendorSellerCopy.isMarkedSold('sold'), isTrue);
      expect(LiveVendorSellerCopy.isMarkedSold('available'), isFalse);
    });

    test('card da vitrine não esconde esgotado só porque ainda há stock', () {
      expect(
        LiveVendorSellerCopy.displayItemStatus(
          rowStatus: 'sold',
          hasStock: true,
        ),
        'sold',
      );
      expect(
        LiveVendorSellerCopy.isSoldOut('sold', const LiveItemOpsSnapshot(sold: 0, available: 5)),
        isTrue,
      );
      expect(
        LiveVendorSellerCopy.soldOutBadge('sold'),
        'ESGOTADO',
      );
    });
  });
}
