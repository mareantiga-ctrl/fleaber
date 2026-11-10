import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/widgets/home_live_feed_grid.dart';

void main() {
  group('HomeLiveFeedGrid blocking spinner', () {
    test('1.º load sem cards — spinner', () {
      expect(
        HomeLiveFeedGridState.showBlockingSpinner(
          loading: true,
          hasItems: false,
        ),
        isTrue,
      );
    });

    test('refresh com cards já visíveis — sem spinner', () {
      expect(
        HomeLiveFeedGridState.showBlockingSpinner(
          loading: true,
          hasItems: true,
        ),
        isFalse,
      );
    });

    test('idle — sem spinner', () {
      expect(
        HomeLiveFeedGridState.showBlockingSpinner(
          loading: false,
          hasItems: true,
        ),
        isFalse,
      );
    });
  });
}
