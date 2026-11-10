import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/backend/supabase/database/tables/orders.dart';
import 'package:fleaber/utils/order_post_purchase_lifecycle.dart';

OrdersRow _order(Map<String, dynamic> data) => OrdersRow(data);

void main() {
  test('formatOrderDeadlinePt DD/MM/AAAA', () {
    final d = DateTime.utc(2030, 1, 15, 18, 0);
    final s = formatOrderDeadlinePt(d.toLocal(), withTime: false);
    expect(s, matches(RegExp(r'^\d{2}/\d{2}/2030$')));
  });

  test('comprador — diferença pendente mostra pagar + 48h', () {
    final view = buildOrderPostPurchaseView(
      order: _order({
        'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'status': 'pago',
        'shipping_method': 'dpd',
        'weight_confirm_status': 'delta_requested',
        'shipping_delta_status': 'pending',
        'ship_by_at': DateTime.utc(2030, 2, 1, 12),
      }),
      isSellerView: false,
      pendingAdjustment: {
        'id': 'adj',
        'amount_charge_cents': 150,
        'expires_at': '2030-01-20T18:00:00.000Z',
      },
    );
    expect(view.phase, OrderPostPurchasePhase.awaitDeltaPayment);
    expect(view.showBuyerPayDelta, isTrue);
    expect(view.extraAmountLabel, contains('1,50'));
    expect(view.payDeadlineLabel, isNotNull);
    expect(view.canGenerateDpdLabel, isFalse);
  });

  test('vendedor — peso pendente ação + bloqueio DPD', () {
    final view = buildOrderPostPurchaseView(
      order: _order({
        'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'status': 'pago',
        'shipping_method': 'dpd',
        'weight_confirm_status': 'pending',
        'shipping_delta_status': 'none',
        'weight_confirm_deadline_at': DateTime.utc(2030, 1, 18, 12),
        'ship_by_at': DateTime.utc(2030, 1, 25, 12),
      }),
      isSellerView: true,
    );
    expect(view.phase, OrderPostPurchasePhase.awaitWeightConfirm);
    expect(view.actionNeeded, isTrue);
    expect(view.showSellerWeightActions, isTrue);
    expect(view.canGenerateDpdLabel, isFalse);
    expect(view.dpdBlockedReason, isNotNull);
  });

  test('vendedor — peso ok → pode gerar DPD', () {
    final view = buildOrderPostPurchaseView(
      order: _order({
        'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'status': 'pago',
        'shipping_method': 'dpd',
        'weight_confirm_status': 'confirmed_same',
        'shipping_delta_status': 'none',
        'ship_by_at': DateTime.utc(2030, 1, 25, 12),
      }),
      isSellerView: true,
    );
    expect(view.canGenerateDpdLabel, isTrue);
    expect(view.actionNeeded, isTrue);
  });

  test('cancelado — reembolso iniciado vs concluído', () {
    final initiated = buildOrderPostPurchaseView(
      order: _order({
        'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'status': 'cancelado',
        'shipping_method': 'dpd',
        'shipping_delta_status': 'expired',
      }),
      isSellerView: false,
    );
    expect(initiated.phase, OrderPostPurchasePhase.cancelled);
    expect(initiated.refundStatus, OrderRefundUiStatus.initiated);
    expect(initiated.cancelReason, contains('portes'));

    // stripe_refund_id sozinho ≠ concluído (selo antecipado C1).
    final idOnly = buildOrderPostPurchaseView(
      order: _order({
        'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'status': 'cancelado',
        'shipping_method': 'dpd',
        'shipping_delta_status': 'expired',
        'stripe_refund_id': 're_123',
      }),
      isSellerView: false,
    );
    expect(idOnly.refundStatus, OrderRefundUiStatus.initiated);

    final done = buildOrderPostPurchaseView(
      order: _order({
        'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'status': 'cancelado',
        'shipping_method': 'dpd',
        'shipping_delta_status': 'expired',
        'stripe_refund_id': 're_123',
        'stripe_refunded_at': DateTime.utc(2030, 1, 21, 10),
      }),
      isSellerView: false,
    );
    expect(done.refundStatus, OrderRefundUiStatus.completed);
  });

  test('tracking DPD URL pública', () {
    expect(
      publicDpdTrackingUrl('ABC123'),
      'https://www.dpd.pt/tracking?parcelNumber=ABC123',
    );
  });
}
