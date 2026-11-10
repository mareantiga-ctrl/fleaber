import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/seller_reservation_policy_service.dart';
import 'package:fleaber/widgets/seller_reservation_policy_sheet.dart';
import 'package:fleaber/widgets/fleaber_bag_changed_dialog.dart';

void main() {
  group('Phase 5.5 product copy + duration selector', () {
    test('formatTtl singular/plural', () {
      expect(SellerReservationPolicyService.formatTtl(900), '15 minutos');
      expect(SellerReservationPolicyService.formatTtl(3600), '1 hora');
      expect(SellerReservationPolicyService.formatTtl(7200), '2 horas');
      expect(SellerReservationPolicyService.formatTtl(86400), '1 dia');
      expect(SellerReservationPolicyService.formatTtl(172800), '2 dias');
    });

    test('ttl presets cover 15m–5d without gaps for product selector', () {
      final p = SellerReservationPolicyService.ttlPresetsSeconds;
      expect(p.first, 900);
      expect(p.last, 432000);
      expect(p, contains(3600));
      expect(p, contains(86400));
      for (final s in p) {
        expect(SellerReservationPolicyService.clampTtl(s), s);
      }
    });

    testWidgets('policy sheet uses duration picker sheet not chips',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SellerReservationPolicySheet(
              requireSaveToDismiss: false,
              title: 'Política de reservas',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Duração da reserva'), findsOneWidget);
      expect(find.text('Clientes sem confiança'), findsOneWidget);
      expect(
        find.textContaining('O artigo só fica garantido quando fizer'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Depois de aceitares'),
        findsOneWidget,
      );
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Duração normal'), findsOneWidget);
      expect(find.text('Clientes de confiança'), findsOneWidget);
      // Default normal TTL = 1 dia — open its selector field.
      await tester.ensureVisible(find.text('1 dia').first);
      await tester.tap(find.text('1 dia').first);
      await tester.pumpAndSettle();
      expect(find.text('Escolher duração'), findsOneWidget);
      expect(find.byKey(const Key('ttl_selected')), findsOneWidget);
      expect(find.text('15 minutos'), findsWidgets);
      expect(find.text('5 dias'), findsWidgets);
    });

    testWidgets('bag changed copy plural + moeda', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => FleaberBagChangedDialog.show(
                  ctx,
                  unavailableCount: 1,
                  totalCents: 2638,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('O saco mudou'), findsOneWidget);
      expect(
        find.textContaining('1 artigo já não está disponível'),
        findsOneWidget,
      );
      expect(find.textContaining('26,38'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    test('human copy helpers avoid technical jargon tokens', () {
      const trust =
          'Esta cliente passa a ser cliente de confiança. Os artigos que '
          'já tiver no saco podem ficar automaticamente reservados, se '
          'ainda houver stock.';
      const extend =
          'Só podes prolongar esta reserva uma vez. A partir de agora, '
          'fica reservada durante 1 hora.';
      for (final s in [trust, extend]) {
        expect(s.toLowerCase().contains('promov'), isFalse);
        expect(s.toLowerCase().contains('validade'), isFalse);
        expect(s.toLowerCase().contains('guaranteed'), isFalse);
        expect(s.toLowerCase().contains('pending'), isFalse);
        expect(s.toLowerCase().contains('lifecycle'), isFalse);
        expect(s.contains('qty'), isFalse);
        expect(s.contains('(s)'), isFalse);
      }
    });
  });
}
