import 'package:flutter_test/flutter_test.dart';

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

    test('buyerCanPayBagReservation allows pending and accepted', () {
      expect(
        LiveReservationQueueService.buyerCanPayBagReservation('pending'),
        isTrue,
      );
      expect(
        LiveReservationQueueService.buyerCanPayBagReservation('accepted'),
        isTrue,
      );
      expect(
        LiveReservationQueueService.buyerCanPayBagReservation('converted'),
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

    test('buyerBagIsPending', () {
      expect(LiveReservationQueueService.buyerBagIsPending('pending'), isTrue);
      expect(LiveReservationQueueService.buyerBagIsPending('accepted'), isFalse);
    });
  });
}
