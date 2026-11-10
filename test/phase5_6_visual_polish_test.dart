import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/fee_calculator.dart';
import 'package:fleaber/utils/live_in_stream_checkout.dart';
import 'package:fleaber/widgets/live_vendor_ops_ui.dart';

void main() {
  group('Phase 5.6 visual polish', () {
    test('checkout money uses pt_PT commas via formatEuros', () {
      expect(formatEuros(24.5), contains('24,50'));
      expect(formatEuros(24.5), isNot(contains('24.50')));
      expect(formatEuros(0), contains('0,00'));
      expect(formatEuros(1.88), contains('1,88'));
      expect(formatEuros(26.38), contains('26,38'));
    });

    testWidgets('checkout totals breakdown uses comma money', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveInStreamCheckout.checkoutTotalsBreakdown(
              itemsSubtotalEur: 24.5,
              shippingEur: 0,
              protectionEur: 1.88,
              totalEur: 26.38,
              lineCount: 1,
            ),
          ),
        ),
      );
      expect(find.textContaining('24,50'), findsOneWidget);
      expect(find.textContaining('0,00'), findsOneWidget);
      expect(find.textContaining('1,88'), findsOneWidget);
      expect(find.textContaining('26,38'), findsOneWidget);
      expect(find.textContaining('24.50'), findsNothing);
    });

    testWidgets('bottom actions bar has no clipped Facebook chip',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveVendorProductActionsBar(
              onAction: (id) => tapped = id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mostrar'), findsOneWidget);
      expect(find.text('Esgotado'), findsOneWidget);
      expect(find.text('Última'), findsOneWidget);
      expect(find.text('+Stock'), findsOneWidget);
      expect(find.text('Mais'), findsOneWidget);
      // Full Facebook label not in primary row (avoids clip).
      expect(find.text('Reserva Facebook'), findsNothing);
      await tester.tap(find.text('Mais'));
      await tester.pumpAndSettle();
      expect(find.text('Reserva Facebook'), findsOneWidget);
      await tester.tap(find.text('Reserva Facebook'));
      await tester.pumpAndSettle();
      expect(tapped, 'external');
    });
  });
}
