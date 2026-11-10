import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:fleaber/utils/seller_reservation_policy_service.dart';
import 'package:fleaber/widgets/live_vendor_ops_ui.dart';
import 'package:fleaber/utils/live_reservation_queue_service.dart';
import 'package:fleaber/widgets/fleaber_bag_changed_dialog.dart';
import 'package:fleaber/widgets/fleaber_primary_button.dart';
import 'package:fleaber/widgets/seller_reservation_policy_sheet.dart';

void main() {
  group('F5 seller copy + policy helpers', () {
    test('F5-15 pending never labelled as reserved', () {
      expect(
        LiveVendorSellerCopy.reservationStatus(
          'pending',
          requestKind: 'approval_pending',
        ),
        contains('Pediu'),
      );
      expect(
        LiveVendorSellerCopy.reservationStatus(
          'pending',
          requestKind: 'approval_pending',
        ).toLowerCase(),
        isNot(contains('reserv')),
      );
    });

    test('F5-07 bag_hold_none seller label is not request nor reserved', () {
      final label = LiveVendorSellerCopy.reservationStatus(
        'pending',
        requestKind: 'bag_hold_none',
      );
      expect(label.toLowerCase(), contains('saco'));
      expect(label.toLowerCase(), isNot(contains('pediu')));
      expect(label.toLowerCase(), isNot(contains('reservado')));
    });

    test('F5-accepted guaranteed uses reserved language', () {
      expect(
        LiveVendorSellerCopy.reservationStatus(
          'accepted',
          requestKind: 'guaranteed',
        ),
        'Reservado',
      );
    });

    test('F5 cancelled / unavailable / rejected labels PT-PT', () {
      expect(
        LiveVendorSellerCopy.reservationStatus('cancelled'),
        'Cancelado',
      );
      expect(
        LiveVendorSellerCopy.reservationStatus('unavailable'),
        'Indisponível',
      );
      expect(
        LiveVendorSellerCopy.reservationStatus('rejected'),
        'Recusado',
      );
      expect(
        LiveVendorSellerCopy.reservationStatus('expired'),
        'Expirado',
      );
      expect(
        LiveVendorSellerCopy.reservationStatus('converted'),
        'Pago',
      );
    });

    test('F5-16 sellerCanAct only on approval_pending', () {
      expect(
        LiveReservationQueueService.sellerCanActOnReservation(
          status: 'pending',
          requestKind: 'approval_pending',
        ),
        isTrue,
      );
      expect(
        LiveReservationQueueService.sellerCanActOnReservation(
          status: 'pending',
          requestKind: 'bag_hold_none',
        ),
        isFalse,
      );
      expect(
        LiveReservationQueueService.sellerCanActOnReservation(
          status: 'accepted',
          requestKind: 'guaranteed',
        ),
        isFalse,
      );
    });

    test('F5 ttl clamp 15m–5d', () {
      expect(SellerReservationPolicyService.clampTtl(60), 900);
      expect(SellerReservationPolicyService.clampTtl(999999), 432000);
      expect(SellerReservationPolicyService.clampTtl(3600), 3600);
    });

    test('F5 formatTtl PT-PT', () {
      expect(SellerReservationPolicyService.formatTtl(900), '15 minutos');
      expect(SellerReservationPolicyService.formatTtl(86400), '1 dia');
      expect(SellerReservationPolicyService.formatTtl(432000), '5 dias');
    });

    test('F5-23 no technical enums in seller-facing status labels', () {
      for (final kind in ['approval_pending', 'bag_hold_none', 'guaranteed']) {
        for (final st in [
          'pending',
          'accepted',
          'rejected',
          'expired',
          'cancelled',
          'converted',
        ]) {
          final label =
              LiveVendorSellerCopy.reservationStatus(st, requestKind: kind);
          expect(label.contains('_'), isFalse, reason: '$st/$kind → $label');
          expect(label.toLowerCase(), isNot(contains('approval')));
          expect(label.toLowerCase(), isNot(contains('guaranteed')));
          expect(label.toLowerCase(), isNot(contains('bag_hold')));
        }
      }
    });
  });

  testWidgets('F5-01 policy sheet gate copy is PT-PT and complete',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SellerReservationPolicySheet(
            requireSaveToDismiss: true,
            title: 'Antes do primeiro direto',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Antes do primeiro direto'), findsOneWidget);
    expect(find.textContaining('autorização'), findsWidgets);
    expect(find.textContaining('pagamento'), findsWidgets);
    expect(find.textContaining('confiança'), findsWidgets);
    // No internal enum leakage
    expect(find.textContaining('approval_pending'), findsNothing);
    expect(find.textContaining('bag_hold_none'), findsNothing);
    expect(find.textContaining('GUARANTEED'), findsNothing);
  });

  testWidgets('F5-24 Continuar button is content-sized not full-width',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FleaberBagChangedDialog(
                unavailableCount: 1,
                totalCents: 1236,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final btn = tester.widget<FleaberPrimaryButton>(
      find.widgetWithText(FleaberPrimaryButton, 'Continuar'),
    );
    expect(btn.width, isNull);
    expect(btn.height, 48);
    expect(btn.padding, const EdgeInsets.symmetric(horizontal: 24));
    final size =
        tester.getSize(find.widgetWithText(FleaberPrimaryButton, 'Continuar'));
    expect(size.width, lessThan(220));
  });
}
