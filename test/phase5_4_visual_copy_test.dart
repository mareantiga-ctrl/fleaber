import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/widgets/live_vendor_ops_ui.dart';

void main() {
  group('Phase 5.4 visual copy helpers', () {
    test('tech/fixture refs hidden; commercial refs kept', () {
      expect(
        LiveVendorRefDisplay.looksLikeTechRef(
          'P52-p52_n2_1791353049001',
        ),
        isTrue,
      );
      expect(LiveVendorRefDisplay.formatRef('P52-p52_n2_1791353049001'), '');
      expect(LiveVendorRefDisplay.formatRef('CB01'), 'CB01');
      expect(LiveVendorRefDisplay.refLabel('CB01'), 'Ref CB01');
      expect(LiveVendorRefDisplay.refLabel('P52-p52_n2_1791353049001'), '—');
    });

    test('item display prefers human title', () {
      expect(
        LiveVendorRefDisplay.itemDisplayName(
          title: 'Casaco bege',
          refCode: 'CB01',
        ),
        'Casaco bege',
      );
    });

    test('no qty / (s) leftovers in seller copy', () {
      expect(LiveVendorSellerCopy.qtyLabel(2).toLowerCase().contains('qty'), isFalse);
      expect(LiveVendorSellerCopy.artigosIndisponiveis(2).contains('(s)'), isFalse);
    });
  });
}
