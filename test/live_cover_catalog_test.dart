import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/live_cover_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('provisionalCoverId is stable per liveId', () {
    const a = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    const b = 'ffffffff-1111-2222-3333-444444444444';
    expect(LiveCoverCatalog.provisionalCoverId(a),
        LiveCoverCatalog.provisionalCoverId(a));
    expect(LiveCoverCatalog.provisionalCoverId(a),
        isNot(LiveCoverCatalog.provisionalCoverId(b)));
  });

  test('decorrelateProvisional avoids consecutive duplicates', () {
    // Force same hash bucket by repeating same id — then shift.
    final ids = List.generate(8, (_) => 'same-live-id');
    final covers = LiveCoverCatalog.decorrelateProvisional(ids);
    expect(covers.length, 8);
    for (var i = 1; i < covers.length; i++) {
      expect(covers[i], isNot(covers[i - 1]));
    }
  });

  test('catalog JSON loads 60 covers', () async {
    await LiveCoverCatalog.ensureLoaded();
    expect(LiveCoverCatalog.allCoverIds.length, 60);
    expect(
      LiveCoverCatalog.categoriesFor('fleaber_capa_04'),
      contains('Calçado'),
    );
    expect(
      LiveCoverCatalog.assetPath('fleaber_capa_01'),
      'assets/live_covers/fleaber_capa_01.webp',
    );
  });
}
