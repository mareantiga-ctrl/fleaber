import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/widgets/live_vendor_ops_ui.dart';
import 'package:fleaber/widgets/fleaber_bag_changed_dialog.dart';

/// Phase 6 contract helpers + Phase 5 regression (local, no staging).
void main() {
  group('Phase 6 event key contract (mirror SQL)', () {
    String eventKey({
      required String liveId,
      String? ocrHash,
      String? commentId,
    }) {
      final cmt = commentId?.trim();
      if (cmt != null && cmt.length >= 4) {
        return 'fb_cmt:$liveId:$cmt';
      }
      final h = ocrHash?.trim();
      if (h != null && h.length >= 8) return 'ocr:$h';
      return '';
    }

    test('comment_id wins over OCR hash', () {
      expect(
        eventKey(
          liveId: 'live-1',
          ocrHash: 'abcdefghij',
          commentId: '999888',
        ),
        'fb_cmt:live-1:999888',
      );
    });

    test('OCR hash used when no comment_id', () {
      expect(
        eventKey(liveId: 'live-1', ocrHash: 'abcdefghij'),
        'ocr:abcdefghij',
      );
    });

    test('different comment ids are not duplicates', () {
      final a = eventKey(liveId: 'L', ocrHash: 'samehash1', commentId: '1111');
      final b = eventKey(liveId: 'L', ocrHash: 'samehash1', commentId: '2222');
      expect(a, isNot(b));
    });

    test('same comment on different lives are not duplicates', () {
      final a = eventKey(liveId: 'L1', commentId: '99999');
      final b = eventKey(liveId: 'L2', commentId: '99999');
      expect(a, isNot(b));
    });

    test('short hash rejected', () {
      expect(eventKey(liveId: 'L', ocrHash: 'short'), '');
    });
  });

  group('Phase 5 regression — bottom actions', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets('no clipped Facebook chip @ ${width.toInt()}px',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 640));
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
        expect(find.text('Reserva Facebook'), findsNothing);
        await tester.tap(find.text('Mais'));
        await tester.pumpAndSettle();
        expect(find.text('Reserva Facebook'), findsOneWidget);
        await tester.tap(find.text('Reserva Facebook'));
        await tester.pumpAndSettle();
        expect(tapped, 'external');
      });
    }

    testWidgets('text scale 1.3 still exposes Mais → Reserva Facebook',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? tapped;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: MaterialApp(
            home: Scaffold(
              body: LiveVendorProductActionsBar(
                onAction: (id) => tapped = id,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mais'), findsOneWidget);
      await tester.tap(find.text('Mais'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reserva Facebook'));
      await tester.pumpAndSettle();
      expect(tapped, 'external');
    });
  });

  group('Phase 5 regression — bag_changed dialog UX', () {
    testWidgets('dialog Continuar / Cancelar present without pay spinner widget',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Column(
                children: [
                  // Simulates Pagar after loading cleared
                  const FilledButton(onPressed: null, child: Text('Pagar')),
                  TextButton(
                    onPressed: () => FleaberBagChangedDialog.show(
                      ctx,
                      unavailableCount: 1,
                      totalCents: 2638,
                    ),
                    child: const Text('open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('O saco mudou'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
