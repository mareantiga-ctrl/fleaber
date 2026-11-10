import 'dart:convert';

import '/backend/supabase/supabase.dart';
import '/order_cancel_eligibility.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

/// Resultado do cancelamento (+ refund Stripe se Seguro Fleaber).
class OrderCancelApplyResult {
  const OrderCancelApplyResult({
    this.stripeRefundAttempted = false,
    this.stripeRefundOk = false,
    this.stripeRefundSkipped = false,
    this.stripeRefundAlready = false,
    this.stripeRefundNeedsReconcile = false,
    this.stripeRefundError,
    this.stripeRefundId,
  });

  final bool stripeRefundAttempted;
  final bool stripeRefundOk;
  final bool stripeRefundSkipped;
  final bool stripeRefundAlready;
  /// Stripe já reembolsou mas o estado interno ainda não fechou — retry idempotente.
  final bool stripeRefundNeedsReconcile;
  final String? stripeRefundError;
  final String? stripeRefundId;

  bool get stripeRefundSucceeded =>
      stripeRefundOk || stripeRefundAlready || stripeRefundSkipped;
}

/// Pagamento protegido na app (Stripe / Seguro Fleaber), não MB WAY.
bool orderIsSeguroFleaberPayment(String? paymentMethod) {
  final pm = (paymentMethod ?? '').trim().toLowerCase();
  if (pm.isEmpty) return false;
  if (pm.contains('direto') ||
      pm.contains('mb way') ||
      pm.contains('mbway') ||
      pm.contains('transfer')) {
    return false;
  }
  return pm.contains('pagamento na app') ||
      pm.contains('seguro fleaber') ||
      pm.contains('stripe');
}

Map<String, dynamic>? _asStringKeyMap(Object? data) {
  if (data is Map) {
    return Map<String, dynamic>.from(data);
  }
  if (data is String) {
    final t = data.trim();
    if (t.startsWith('{')) {
      try {
        final decoded = jsonDecode(t);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
  }
  return null;
}

OrderCancelApplyResult _resultFromRefundMap(Map<String, dynamic> map) {
  if (map['skipped'] == true) {
    return const OrderCancelApplyResult(
      stripeRefundAttempted: true,
      stripeRefundSkipped: true,
      stripeRefundOk: true,
    );
  }
  if (map['already_refunded'] == true) {
    return OrderCancelApplyResult(
      stripeRefundAttempted: true,
      stripeRefundAlready: true,
      stripeRefundOk: true,
      stripeRefundId: map['refund_id']?.toString(),
    );
  }
  if (map['ok'] == true) {
    return OrderCancelApplyResult(
      stripeRefundAttempted: true,
      stripeRefundOk: true,
      stripeRefundId: map['refund_id']?.toString(),
    );
  }
  final needsReconcile = map['needs_reconcile'] == true ||
      map['code']?.toString() == 'refund_pending_reconcile';
  return OrderCancelApplyResult(
    stripeRefundAttempted: true,
    stripeRefundNeedsReconcile: needsReconcile,
    stripeRefundId: map['refund_id']?.toString(),
    stripeRefundError: map['error']?.toString() ?? 'Reembolso falhou',
  );
}

/// Chama a edge `refund-order` (idempotente). Em `needs_reconcile`, faz 1 retry.
Future<OrderCancelApplyResult> requestSeguroFleaberStripeRefund({
  required String orderId,
}) async {
  final oid = orderId.trim();
  if (oid.isEmpty) {
    return const OrderCancelApplyResult(
      stripeRefundAttempted: true,
      stripeRefundError: 'order_id vazio',
    );
  }

  Future<OrderCancelApplyResult> once() async {
    try {
      final response = await SupaFlow.client.functions.invoke(
        'refund-order',
        body: {'order_id': oid},
      );
      final map = _asStringKeyMap(response.data);
      if (map == null) {
        return const OrderCancelApplyResult(
          stripeRefundAttempted: true,
          stripeRefundError: 'Resposta inválida do reembolso',
        );
      }
      return _resultFromRefundMap(map);
    } on FunctionException catch (e) {
      print('BATATA_STRIPE_REFUND FunctionException order=$oid: $e');
      final map = _asStringKeyMap(e.details);
      if (map != null) return _resultFromRefundMap(map);
      return OrderCancelApplyResult(
        stripeRefundAttempted: true,
        stripeRefundError: e.toString(),
      );
    } catch (e) {
      print('BATATA_STRIPE_REFUND ERRO order=$oid: $e');
      return OrderCancelApplyResult(
        stripeRefundAttempted: true,
        stripeRefundError: e.toString(),
      );
    }
  }

  final first = await once();
  if (first.stripeRefundSucceeded) return first;
  if (!first.stripeRefundNeedsReconcile) return first;

  print('BATATA_STRIPE_REFUND retry needs_reconcile order=$oid');
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final second = await once();
  if (second.stripeRefundSucceeded) return second;
  return OrderCancelApplyResult(
    stripeRefundAttempted: true,
    stripeRefundNeedsReconcile: true,
    stripeRefundId: second.stripeRefundId ?? first.stripeRefundId,
    stripeRefundError: second.stripeRefundError ??
        first.stripeRefundError ??
        'Reembolso Stripe feito; encomenda ainda a sincronizar. Tenta outra vez.',
  );
}

/// True se a encomenda paga com Seguro Fleaber deve tentar refund Stripe ao anular.
bool orderNeedsSeguroFleaberStripeRefund({
  required String? status,
  required String? paymentMethod,
}) {
  if (!orderIsSeguroFleaberPayment(paymentMethod)) return false;
  final s = normalizeOrderStatusKey(status);
  // Inclui cancelado: pode ter sido anulado na app antes do refund (retry).
  return s == 'pago' || s == 'cancelado';
}
