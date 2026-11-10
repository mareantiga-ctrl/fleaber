import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/utils/live_in_stream_checkout.dart';

void main() {
  test('D2 euroCents estável (sem regressão financeira)', () {
    expect(LiveInStreamCheckout.euroCents(10.5), 1050);
    expect(LiveInStreamCheckout.euroCents(3.5), 350);
  });
}
