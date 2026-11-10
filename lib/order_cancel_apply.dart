import '/backend/supabase/supabase.dart';
import '/batata_reservation_actions.dart';
import '/order_cancel_eligibility.dart';
import '/utils/fleaber_stripe_refund.dart';

/// Anula a encomenda e repõe stock (trigger SQL).
/// Só o `sellerId` da encomenda pode executar.
///
/// Seguro Fleaber pago: autoridade = Edge `refund-order`
/// (Stripe refund + `cancelado` + restock via trigger) — sem PATCH JWT prévio.
Future<OrderCancelApplyResult> applyOrderCancelAndRelist({
  required String orderId,
  required String sellerUserId,
}) async {
  final orderRows = await OrdersTable().querySingleRow(
    queryFn: (q) => q.eqOrNull('id', orderId),
  );
  if (orderRows.isEmpty) {
    throw Exception('Encomenda não encontrada.');
  }

  final order = orderRows.first;
  if (order.sellerId != sellerUserId) {
    throw Exception('Sem permissão.');
  }

  if (orderIsCancelled(order.status)) {
    if (orderNeedsSeguroFleaberStripeRefund(
      status: order.status,
      paymentMethod: order.paymentMethod,
    )) {
      return requestSeguroFleaberStripeRefund(orderId: orderId);
    }
    throw Exception('Esta encomenda já está cancelada.');
  }

  final needsStripeRefund = orderNeedsSeguroFleaberStripeRefund(
    status: order.status,
    paymentMethod: order.paymentMethod,
  );

  if (normalizeOrderStatusKey(order.status) == 'reserva_pendente') {
    print('BATATA_CANCEL_RELIST reserva_pendente -> cancelado order=$orderId');
    await batataPatchOrderById(
      orderId: orderId,
      patch: {'status': 'cancelado'},
      requireStatusKey: 'reserva_pendente',
    );
    await assertOrderCancelled(orderId);
    return const OrderCancelApplyResult();
  }

  // Pós-pago Seguro Fleaber: NÃO PATCH cancelado via JWT (trigger bloqueia).
  // refund-order (service_role) faz refund + status=cancelado.
  if (needsStripeRefund) {
    print('BATATA_STRIPE_REFUND_FIRST order=$orderId');
    final refund = await requestSeguroFleaberStripeRefund(orderId: orderId);
    if (!refund.stripeRefundSucceeded) {
      throw Exception(
        refund.stripeRefundError ??
            'Não foi possível reembolsar no Stripe. A encomenda mantém-se activa.',
      );
    }
    // Confirmar cancelado (Edge deve ter aplicado).
    try {
      await assertOrderCancelled(orderId);
    } catch (_) {
      // already_refunded path may have just set it; re-read once
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await assertOrderCancelled(orderId);
    }
    return refund;
  }

  print(
    'BATATA_CANCEL_RELIST cancel+restore order=$orderId '
    'product=${order.productId} qty=${order.quantity ?? 1}',
  );
  await batataPatchOrderById(
    orderId: orderId,
    patch: {'status': 'cancelado'},
  );
  await assertOrderCancelled(orderId);
  return const OrderCancelApplyResult();
}
