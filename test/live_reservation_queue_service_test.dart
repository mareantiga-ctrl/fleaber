import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/utils/live_catalog_stock_service.dart';
import 'package:fleaber/utils/live_reservation_queue_service.dart';

void main() {
  group('LiveReservationQueueService helpers', () {
    test('isBuyerCancelled detects bag_removed in notes', () {
      expect(
        LiveReservationQueueService.isBuyerCancelledReservation(
          status: 'rejected',
          notes: 'bag_removed',
        ),
        isTrue,
      );
      expect(
        LiveReservationQueueService.isBuyerCancelledReservation(
          status: 'pending',
          notes: 'foo | bag_removed',
        ),
        isTrue,
      );
    });

    test('sellerCanActOnReservation only for pending non-cancelled', () {
      expect(
        LiveReservationQueueService.sellerCanActOnReservation(
          status: 'pending',
          notes: null,
        ),
        isTrue,
      );
      expect(
        LiveReservationQueueService.sellerCanActOnReservation(
          status: 'pending',
          notes: 'bag_removed',
        ),
        isFalse,
      );
      expect(
        LiveReservationQueueService.sellerCanActOnReservation(
          status: 'accepted',
          notes: null,
        ),
        isFalse,
      );
    });

    test('buyerBagStatusLabel Phase 3 copy (sem fila à buyer)', () {
      // Canónico na app: LiveBagBuyerStateCopy.approvalPending
      expect(
        LiveReservationQueueService.buyerBagStatusLabel(
          'pending',
          requestKind: 'approval_pending',
          queuePosition: 3,
        ),
        'A aguardar aprovação',
      );
      expect(
        LiveReservationQueueService.buyerBagStatusLabel(
          'pending',
          requestKind: 'bag_hold_none',
          queuePosition: 2,
        ),
        'Pagamento imediato',
      );
      expect(
        LiveReservationQueueService.buyerBagStatusLabel(
          'accepted',
          requestKind: 'guaranteed',
          expiresAt: DateTime(2026, 10, 5, 18, 42),
        ),
        'Reservado até às 18:42',
      );
      expect(
        LiveReservationQueueService.buyerBagStatusLabel(
          'pending',
          unavailable: true,
        ),
        'Indisponível',
      );
      // Legacy pending sem kind = approval_pending copy (sem fila).
      expect(
        LiveReservationQueueService.buyerBagStatusLabel(
          'pending',
          queuePosition: 9,
        ),
        'A aguardar aprovação',
      );
    });

    test('buyerBagIsActionable includes pending (entra no saco)', () {
      expect(LiveReservationQueueService.buyerBagIsActionable('pending'), isTrue);
      expect(
        LiveReservationQueueService.buyerBagIsActionable('accepted'),
        isTrue,
      );
      expect(
        LiveReservationQueueService.buyerBagIsActionable('rejected'),
        isFalse,
      );
    });

    test('stripeCheckoutOrderIdFromNotes parses uuid', () {
      const oid = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
      expect(
        LiveReservationQueueService.stripeCheckoutOrderIdFromNotes(
          'stripe_checkout:$oid',
        ),
        oid,
      );
    });

    test('buyerBagRejectedLabel for bag_removed', () {
      expect(
        LiveReservationQueueService.buyerBagRejectedLabel('bag_removed'),
        'Cancelado',
      );
      expect(
        LiveReservationQueueService.buyerBagRejectedLabel('bag_cancelled'),
        'Cancelado',
      );
    });

    test('isBuyerCancelled via notes or rejected+label', () {
      expect(
        LiveReservationQueueService.isBuyerCancelledReservation(
          status: 'rejected',
          notes: 'bag_removed',
        ),
        isTrue,
      );
      expect(
        LiveReservationQueueService.isBuyerCancelledReservation(
          status: 'pending',
          notes: 'bag_cancelled',
        ),
        isTrue,
      );
    });

    test('isOpenSellerTreatReservation excludes cancelados e convertidos', () {
      expect(
        LiveReservationQueueService.isOpenSellerTreatReservation(
          status: 'pending',
          notes: null,
        ),
        isTrue,
      );
      expect(
        LiveReservationQueueService.isOpenSellerTreatReservation(
          status: 'accepted',
          notes: null,
        ),
        isTrue,
      );
      expect(
        LiveReservationQueueService.isOpenSellerTreatReservation(
          status: 'pending',
          notes: 'bag_removed',
        ),
        isFalse,
      );
      expect(
        LiveReservationQueueService.isOpenSellerTreatReservation(
          status: 'converted',
          notes: null,
        ),
        isFalse,
      );
    });

    test('isActiveSellerReservation', () {
      expect(
        LiveReservationQueueService.isActiveSellerReservation(
          status: 'pending',
          notes: null,
        ),
        isTrue,
      );
      expect(
        LiveReservationQueueService.isActiveSellerReservation(
          status: 'rejected',
          notes: 'bag_removed',
        ),
        isFalse,
      );
      expect(
        LiveReservationQueueService.isActiveSellerReservation(
          status: 'converted',
          notes: null,
        ),
        isTrue,
      );
    });

    test('isAcceptedAwaitingPayment', () {
      expect(
        LiveReservationQueueService.isAcceptedAwaitingPayment(
          status: 'accepted',
          notes: null,
        ),
        isTrue,
      );
      expect(
        LiveReservationQueueService.isAcceptedAwaitingPayment(
          status: 'accepted',
          notes: 'bag_removed',
        ),
        isFalse,
      );
    });

    test('needsUrgentQtyConfirmCard só com stock insuficiente', () {
      const stockOk = LiveCatalogStockSnapshot(
        liveItemId: 'i1',
        liveId: 'l1',
        itemKind: 'live_only',
        totalQty: 5,
        blockedQty: 0,
        reservedAcceptedQty: 0,
        pendingBagQty: 1,
        soldConvertedQty: 0,
        availableQty: 4,
      );
      expect(
        LiveReservationQueueService.needsUrgentQtyConfirmCard(
          requestedQty: 1,
          stock: stockOk,
          notesNeedQtyConfirm: true,
        ),
        isFalse,
      );
      const stockTight = LiveCatalogStockSnapshot(
        liveItemId: 'i2',
        liveId: 'l1',
        itemKind: 'live_only',
        totalQty: 2,
        blockedQty: 0,
        reservedAcceptedQty: 0,
        pendingBagQty: 3,
        soldConvertedQty: 0,
        availableQty: 0,
      );
      expect(
        LiveReservationQueueService.needsUrgentQtyConfirmCard(
          requestedQty: 3,
          stock: stockTight,
          notesNeedQtyConfirm: true,
        ),
        isTrue,
      );
      expect(
        LiveReservationQueueService.needsUrgentQtyConfirmCard(
          requestedQty: 2,
          stock: stockTight,
          notesNeedQtyConfirm: false,
        ),
        isFalse,
      );
    });

    test('buyerBagIsPending', () {
      expect(LiveReservationQueueService.buyerBagIsPending('pending'), isTrue);
      expect(LiveReservationQueueService.buyerBagIsPending('accepted'), isFalse);
    });
  });
}
