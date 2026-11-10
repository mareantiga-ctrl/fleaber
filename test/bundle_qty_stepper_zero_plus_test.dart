import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/widgets/bundle_product_qty_stepper.dart';

/// 32.9 — após qty 0 o `+` tem de continuar a funcionar (enabled com stock).
void main() {
  testWidgets('plus from zero re-adds when enabled with allowZero',
      (tester) async {
    var qty = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return BundleProductQtyStepper(
                quantity: qty,
                maxQuantity: 2,
                allowZero: true,
                enabled: true,
                onChanged: (v) => setState(() => qty = v),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(qty, 1);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(qty, 2);

    // Max stock → + disabled (no change)
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(qty, 2);

    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pumpAndSettle();
    expect(qty, 1);

    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pumpAndSettle();
    expect(qty, 0);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(qty, 1);
  });

  testWidgets('plus ignored when enabled false (regressão pré-32.9)',
      (tester) async {
    var qty = 0;
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BundleProductQtyStepper(
            quantity: 0,
            maxQuantity: 2,
            allowZero: true,
            enabled: false,
            onChanged: (v) {
              calls++;
              qty = v;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(qty, 0);
  });
}
