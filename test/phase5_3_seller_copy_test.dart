import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/widgets/live_vendor_ops_ui.dart';
import 'package:fleaber/widgets/fleaber_bag_changed_dialog.dart';
import 'package:fleaber/utils/fee_calculator.dart';
import 'package:flutter/material.dart';

void main() {
  group('LiveVendorSellerCopy Phase 5.3', () {
    test('reservas ativas singular/plural', () {
      expect(LiveVendorSellerCopy.reservasAtivas(1), '1 reserva ativa');
      expect(LiveVendorSellerCopy.reservasAtivas(2), '2 reservas ativas');
      expect(LiveVendorSellerCopy.reservasAtivas(1).contains('(s)'), isFalse);
    });

    test('artigos indisponíveis singular/plural', () {
      expect(
        LiveVendorSellerCopy.artigosIndisponiveis(1),
        '1 artigo já não está disponível.',
      );
      expect(
        LiveVendorSellerCopy.artigosIndisponiveis(3),
        '3 artigos já não estão disponíveis.',
      );
      expect(
        LiveVendorSellerCopy.artigosIndisponiveis(2).contains('(s)'),
        isFalse,
      );
    });

    test('qty label nunca Qty/qty', () {
      expect(LiveVendorSellerCopy.qtyLabel(1), '1 un.');
      expect(LiveVendorSellerCopy.qtyLabel(2), '2 un.');
      expect(LiveVendorSellerCopy.qtySegment(1), '');
      expect(LiveVendorSellerCopy.qtySegment(2), ' · 2 un.');
      expect(LiveVendorSellerCopy.qtyLabel(1).toLowerCase().contains('qty'), isFalse);
    });

    test('deadline natural PT', () {
      final now = DateTime(2026, 10, 7, 12, 0);
      final sameDay = DateTime(2026, 10, 7, 22, 27);
      final otherDay = DateTime(2026, 10, 10, 22, 27);
      expect(
        LiveVendorSellerCopy.deadlineUntil(sameDay, now: now),
        ' · até às 22:27',
      );
      expect(
        LiveVendorSellerCopy.deadlineUntil(otherDay, now: now),
        ' · até 10/10 às 22:27',
      );
      expect(
        LiveVendorSellerCopy.deadlineUntil(sameDay, now: now).contains('Prazo:'),
        isFalse,
      );
    });

    test('moeda PT formatEuros', () {
      expect(formatEuros(12.36), contains('12,36'));
      expect(formatEuros(12.36), contains('€'));
      expect(formatEuros(12.36).contains('12.36'), isFalse);
    });

    test('shipping labels PT + legado', () {
      expect(fleaberShippingEurFromMethod(kFleaberShippingHandLabel), 0);
      expect(fleaberShippingEurFromMethod(kFleaberShippingCarrierLabel), 3.5);
      expect(fleaberShippingEurFromMethod('Entrega em Mão (€0.00)'), 0);
      expect(kFleaberShippingHandLabel.contains('0,00'), isTrue);
      expect(kFleaberShippingHandLabel.contains('€0.'), isFalse);
    });
  });

  testWidgets('O saco mudou — plural + moeda + Continuar padding', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => FleaberBagChangedDialog.show(
                ctx,
                unavailableCount: 2,
                totalCents: 1236,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 artigos já não estão disponíveis'), findsOneWidget);
    expect(find.textContaining('12,36'), findsOneWidget);
    expect(find.textContaining('12.36'), findsNothing);
    expect(find.text('Continuar'), findsOneWidget);
    final btn = tester.getSize(find.text('Continuar'));
    // Texto + padding ~24*2 → largura confortável (> 90).
    expect(btn.width, greaterThan(70));
  });
}
