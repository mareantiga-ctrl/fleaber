import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/live_bag_copy.dart';
import 'package:fleaber/utils/live_reservation_queue_service.dart';

void main() {
  group('Phase 3 buyer bag copy', () {
    test('COPY-01 guaranteed → Reservado até às [hora], sem info', () {
      final label = LiveReservationQueueService.buyerBagStatusLabel(
        'accepted',
        requestKind: 'guaranteed',
        expiresAt: DateTime(2026, 10, 5, 18, 42),
      );
      expect(label, 'Reservado até às 18:42');
      expect(
        LiveBagBuyerStateCopy.infoTextForLineState('guaranteed'),
        isNull,
      );
      expect(LiveBagBuyerStateCopy.showsInfoIcon('guaranteed'), isFalse);
    });

    test('COPY-02 approval_pending → A aguardar confirmação + ⓘ, sem fila', () {
      final label = LiveReservationQueueService.buyerBagStatusLabel(
        'pending',
        requestKind: 'approval_pending',
        queuePosition: 7,
      );
      expect(label, 'A aguardar confirmação');
      expect(label.toLowerCase(), isNot(contains('espera')));
      expect(label.toLowerCase(), isNot(contains('fila')));
      expect(label.toLowerCase(), isNot(contains('posição')));
      expect(label.contains('#'), isFalse);
      expect(
        LiveBagBuyerStateCopy.showsInfoIcon('approval_pending'),
        isTrue,
      );
    });

    test('COPY-03 approval_pending info text', () {
      expect(
        LiveBagBuyerStateCopy.infoTextForLineState('approval_pending'),
        LiveBagBuyerStateCopy.approvalPendingInfo,
      );
      expect(
        LiveBagBuyerStateCopy.approvalPendingInfo,
        contains('enviado à vendedora'),
      );
      expect(
        LiveBagBuyerStateCopy.approvalPendingInfo,
        contains('continua disponível'),
      );
    });

    test('COPY-04 bag_hold_none → Pagamento imediato + ⓘ, sem fila', () {
      final label = LiveReservationQueueService.buyerBagStatusLabel(
        'pending',
        requestKind: 'bag_hold_none',
        queuePosition: 4,
      );
      expect(label, 'Pagamento imediato');
      expect(label.toLowerCase(), isNot(contains('saco')));
      expect(label.toLowerCase(), isNot(contains('fila')));
      expect(label.contains('#'), isFalse);
      expect(
        LiveBagBuyerStateCopy.showsInfoIcon('bag_hold_none'),
        isTrue,
      );
      expect(
        LiveBagBuyerStateCopy.showsInfoIcon('bag_unguaranteed'),
        isTrue,
      );
    });

    test('COPY-05 immediate payment info text', () {
      expect(
        LiveBagBuyerStateCopy.infoTextForLineState('bag_unguaranteed'),
        LiveBagBuyerStateCopy.immediatePaymentInfo,
      );
      expect(
        LiveBagBuyerStateCopy.immediatePaymentInfo,
        contains('não fica reservado'),
      );
      expect(
        LiveBagBuyerStateCopy.immediatePaymentInfo,
        contains('Clientes de confiança'),
      );
      // Policy explanation only — no trust activation CTA in copy.
      expect(
        LiveBagBuyerStateCopy.immediatePaymentInfo.toLowerCase(),
        isNot(contains('pedir confiança')),
      );
    });

    test('COPY-06 unavailable → Indisponível, sem ⓘ', () {
      expect(
        LiveReservationQueueService.buyerBagStatusLabel(
          'pending',
          unavailable: true,
        ),
        'Indisponível',
      );
      expect(LiveBagBuyerStateCopy.showsInfoIcon('unavailable'), isFalse);
    });

    test('COPY-08 never shows queue phrases for pending kinds', () {
      for (final kind in ['approval_pending', 'bag_hold_none', null]) {
        final label = LiveReservationQueueService.buyerBagStatusLabel(
          'pending',
          requestKind: kind,
          queuePosition: 3,
          waitlist: true,
        );
        expect(label, isNot(contains('Espera #')));
        expect(label.toLowerCase(), isNot(contains('na fila')));
        expect(label, isNot(contains('Posição')));
        expect(label, isNot(contains('fila #')));
      }
    });
  });

  testWidgets('COPY-03/05 info icons open dialogs on tap (mobile-first)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              LiveBagBuyerStateChip(
                label: LiveBagBuyerStateCopy.approvalPending,
                color: const Color(0xFFFF9800),
                infoText: LiveBagBuyerStateCopy.approvalPendingInfo,
              ),
              LiveBagBuyerStateChip(
                label: LiveBagBuyerStateCopy.immediatePayment,
                color: const Color(0xFFFFB74D),
                infoText: LiveBagBuyerStateCopy.immediatePaymentInfo,
              ),
              LiveBagBuyerStateChip(
                label: 'Reservado até às 18:42',
                color: const Color(0xFF4CAF50),
              ),
              LiveBagBuyerStateChip(
                label: LiveBagBuyerStateCopy.unavailable,
                color: const Color(0xFFE57373),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('A aguardar confirmação'), findsOneWidget);
    expect(find.text('Pagamento imediato'), findsOneWidget);
    expect(find.text('Reservado até às 18:42'), findsOneWidget);
    expect(find.text('Indisponível'), findsOneWidget);
    // Only two info icons (approval + immediate).
    expect(find.byIcon(Icons.info_outline_rounded), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.info_outline_rounded).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('enviado à vendedora'), findsOneWidget);
    await tester.tap(find.text('Percebi'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.info_outline_rounded).last);
    await tester.pumpAndSettle();
    expect(find.textContaining('não fica reservado'), findsOneWidget);
    await tester.tap(find.text('Percebi'));
    await tester.pumpAndSettle();
  });

  testWidgets('COPY-07 mixed bag chips fit at 390px without queue copy',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  LiveBagBuyerStateChip(
                    label: 'Reservado até às 18:42',
                    color: const Color(0xFF4CAF50),
                  ),
                  LiveBagBuyerStateChip(
                    label: LiveBagBuyerStateCopy.approvalPending,
                    color: const Color(0xFFFF9800),
                    infoText: LiveBagBuyerStateCopy.approvalPendingInfo,
                  ),
                  LiveBagBuyerStateChip(
                    label: LiveBagBuyerStateCopy.immediatePayment,
                    color: const Color(0xFFFFB74D),
                    infoText: LiveBagBuyerStateCopy.immediatePaymentInfo,
                  ),
                  LiveBagBuyerStateChip(
                    label: LiveBagBuyerStateCopy.unavailable,
                    color: const Color(0xFFE57373),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Espera #'), findsNothing);
    expect(find.textContaining('fila #'), findsNothing);
    expect(find.text('A aguardar confirmação'), findsOneWidget);
    expect(find.text('Pagamento imediato'), findsOneWidget);
    expect(find.text('Indisponível'), findsOneWidget);
    expect(find.text('Reservado até às 18:42'), findsOneWidget);
  });
}
