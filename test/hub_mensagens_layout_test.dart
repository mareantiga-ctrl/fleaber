import 'package:fleaber/hub/theme/hub_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('P10 split breakpoint e largura do painel (E26)', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: Builder(
          builder: (context) {
            expect(HubTheme.useMessagesDesktopSplit(context), isFalse);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1024, 768)),
        child: Builder(
          builder: (context) {
            expect(HubTheme.useMessagesDesktopSplit(context), isTrue);
            final w = HubTheme.messagesListPaneWidthFor(context);
            expect(w, greaterThanOrEqualTo(HubTheme.messagesListPaneMinWidth));
            expect(w, lessThanOrEqualTo(400));
            expect(w, closeTo(1024 * 0.36, 1));
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1280, 800)),
        child: Builder(
          builder: (context) {
            final w = HubTheme.messagesListPaneWidthFor(context);
            expect(w, inInclusiveRange(360, 440));
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1440, 900)),
        child: Builder(
          builder: (context) {
            final w = HubTheme.messagesListPaneWidthFor(context);
            expect(w, inInclusiveRange(360, 460));
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1920, 1080)),
        child: Builder(
          builder: (context) {
            expect(HubTheme.useMessagesDesktopSplit(context), isTrue);
            expect(
              HubTheme.messagesListPaneWidthFor(context),
              HubTheme.messagesListPaneMaxWidth,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}
