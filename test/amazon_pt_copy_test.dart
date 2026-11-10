import 'package:fleaber/amazon_importer/amazon_pt_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('title puts product before brand', () {
    final t = buildCommercialTitlePt(
      sourceTitle: 'Velamp Charleston LED Desk Lamp Flexible Arm',
      brandHint: 'Velamp',
    );
    expect(t.toLowerCase(), contains('candeeiro'));
    expect(t.toLowerCase().startsWith('vela'), isFalse);
    expect(
      t.toLowerCase().indexOf('candeeiro'),
      lessThan(t.toLowerCase().indexOf('velamp')),
    );
  });

  test('sale condition always Novo for Amazon imports', () {
    expect(saleConditionFromManifest('Customer Damage'), 'Novo');
    expect(saleConditionFromManifest('Warehouse Damage'), 'Novo');
    expect(saleConditionFromManifest('New'), 'Novo');
    expect(saleConditionFromManifest(null), 'Novo');
  });

  test('manifest note preserves original code', () {
    expect(manifestConditionNote('Customer Damage'), 'Customer Damage');
    expect(manifestConditionNote(''), '');
  });
}
