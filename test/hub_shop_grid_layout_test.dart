import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/hub/theme/hub_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpWidth(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(width, 900)),
        child: const SizedBox(),
      ),
    );
  }

  testWidgets('shop grid: mobile keeps 2 cols', (tester) async {
    await pumpWidth(tester, 390);
    final ctx = tester.element(find.byType(SizedBox));
    expect(HubTheme.shopGridCrossAxisCount(ctx), 2);
    expect(HubTheme.shopContentMaxWidthFor(ctx), HubTheme.maxContentWidth);
  });

  testWidgets('shop grid: 768 keeps 2 cols', (tester) async {
    await pumpWidth(tester, 768);
    final ctx = tester.element(find.byType(SizedBox));
    expect(HubTheme.shopGridCrossAxisCount(ctx), 2);
  });

  testWidgets('shop grid: 1024 aims 4 cols', (tester) async {
    await pumpWidth(tester, 1024);
    final ctx = tester.element(find.byType(SizedBox));
    expect(HubTheme.shopGridCrossAxisCount(ctx), 4);
  });

  testWidgets('shop grid: 1280 aims 5 cols', (tester) async {
    await pumpWidth(tester, 1280);
    final ctx = tester.element(find.byType(SizedBox));
    expect(HubTheme.shopGridCrossAxisCount(ctx), 5);
  });

  testWidgets('shop grid: 1440 aims 6 cols', (tester) async {
    await pumpWidth(tester, 1440);
    final ctx = tester.element(find.byType(SizedBox));
    expect(HubTheme.shopGridCrossAxisCount(ctx), 6);
    expect(HubTheme.shopContentMaxWidthFor(ctx), greaterThan(1000));
  });

  testWidgets('shop grid: 1920 aims 7 cols', (tester) async {
    await pumpWidth(tester, 1920);
    final ctx = tester.element(find.byType(SizedBox));
    expect(HubTheme.shopGridCrossAxisCount(ctx), 7);
    expect(HubTheme.shopContentMaxWidthFor(ctx), HubTheme.shopMaxContentWidth);
  });
}
