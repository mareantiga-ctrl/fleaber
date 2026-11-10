import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/dpd_shipping_rates.dart';
import '/utils/fleaber_stripe_checkout_context.dart';
import '/utils/fleaber_stripe_launch.dart';

/// ZIP 140 — confirmação de peso / diferença portes (RPC + CPI delta).
class OrderShippingOpsService {
  OrderShippingOpsService._();

  static Future<Map<String, dynamic>> sellerConfirmWeight({
    required String orderId,
    double? actualKg,
    FleaberDpdWeightBand? actualBand,
    required String action, // confirm | assume | request_delta
  }) async {
    final res = await SupaFlow.client.rpc(
      'batata_seller_confirm_shipping_weight',
      params: {
        'p_order_id': orderId,
        'p_actual_kg': actualKg,
        'p_actual_band': actualBand?.code,
        'p_action': action,
      },
    );
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'ok': false, 'error': 'invalid_response'};
  }

  /// Comprador paga diferença — PI separado (mode shipping_delta).
  static Future<bool> buyerPayShippingDelta({
    required String orderId,
    required String adjustmentId,
  }) async {
    if (currentUserUid.isEmpty) {
      throw Exception('Inicia sessão para pagar a diferença de portes.');
    }
    final result = await fleaberInvokeCreatePaymentIntent(
      body: {
        'mode': 'shipping_delta',
        'order_id': orderId,
        'adjustment_id': adjustmentId,
        'buyer_id': currentUserUid,
        'currency': 'eur',
      },
      logContext: {'source': 'shipping_delta'},
    );
    await FleaberStripeCheckoutContext.save(
      orderId: orderId,
      productId: 'shipping_delta',
      checkoutSessionId: result.checkoutSessionId,
    );
    final opened = await fleaberLaunchStripeCheckout(
      result.checkoutUrl,
      context: {
        'order_id': orderId,
        'adjustment_id': adjustmentId,
        'session_id': result.checkoutSessionId,
        'source': 'shipping_delta',
      },
    );
    if (!opened) {
      await FleaberStripeCheckoutContext.clear();
      throw Exception('Não foi possível abrir o pagamento da diferença.');
    }
    return true;
  }

  static Future<Map<String, dynamic>?> fetchPendingAdjustment(String orderId) async {
    final rows = await SupaFlow.client
        .from('order_shipping_adjustments')
        .select()
        .eq('order_id', orderId)
        .eq('status', 'pending')
        .limit(1);
    if (rows is! List || rows.isEmpty) return null;
    final first = rows.first;
    if (first is Map<String, dynamic>) return first;
    if (first is Map) return Map<String, dynamic>.from(first);
    return null;
  }
}
