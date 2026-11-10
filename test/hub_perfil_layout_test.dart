import 'package:fleaber/hub/theme/hub_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('P11 perfil desktop breakpoint e largura (E27)', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: Builder(
          builder: (context) {
            expect(HubTheme.useProfileDesktopLayout(context), isFalse);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(768, 1024)),
        child: Builder(
          builder: (context) {
            expect(HubTheme.useProfileDesktopLayout(context), isTrue);
            final w = HubTheme.profileContentMaxWidthFor(context);
            expect(w, lessThanOrEqualTo(760));
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
            expect(HubTheme.useProfileDesktopLayout(context), isTrue);
            expect(
              HubTheme.profileContentMaxWidthFor(context),
              HubTheme.profileMaxContentWidth,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}
