import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/hub/pages/how_it_works_body.dart';

void main() {
  test('Como funciona — 4 passos de lançamento em PT-PT', () {
    expect(HowItWorksBody.steps.length, 4);
    expect(HowItWorksBody.title, 'Como funciona');
    expect(HowItWorksBody.subtitle.toLowerCase(), contains('fleaber'));
    expect(HowItWorksBody.steps.first.$1, 'Descobre');
    expect(HowItWorksBody.steps.last.$1, 'Compra com segurança');
    // Sem inglês solto / termos de staging.
    final blob =
        '${HowItWorksBody.subtitle} ${HowItWorksBody.steps.map((s) => '${s.$1} ${s.$2}').join(' ')}';
    expect(blob.toLowerCase().contains('staging'), isFalse);
    expect(blob.contains('checkout'), isFalse);
  });
}
