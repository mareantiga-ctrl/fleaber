import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/dpd_shipping_rates.dart';
import '/utils/fleaber_stripe_checkout_context.dart';
import '/utils/fleaber_stripe_launch.dart';
import '/marketplace_feed_refresh.dart';

/// ZIP 149 / 149.1 — conjuntos cotação antes de pagar (sem reserva pré-pagamento).
bool isQuoteBeforePayBundle(Map<String, dynamic>? bundle) {
  if (bundle == null) return false;
  final status = (bundle['status']?.toString() ?? '').trim();
  if (status == 'awaiting_payment') return true;
  final rule = (bundle['rule_version']?.toString() ?? '').trim();
  if (rule == 'quote_before_pay_v1') return true;
  final expires = (bundle['seller_confirm_expires_at']?.toString() ?? '').trim();
  return expires.isNotEmpty;
}

DateTime? parseBundleDeadlineUtc(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw.toUtc();
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toUtc();
}

/// Prazo do servidor em PT-PT (ex. «até 06/11/2026, 15:30»). Null se em falta.
String? formatBundleDeadlinePt(dynamic raw) {
  final dt = parseBundleDeadlineUtc(raw);
  if (dt == null) return null;
  final local = dt.toLocal();
  return DateFormat("dd/MM/yyyy, HH:mm").format(local);
}

String bundleBuyerStatusHeadline(Map<String, dynamic> bundle) {
  switch ((bundle['status']?.toString() ?? '').trim()) {
    case 'pending':
      return 'Pedido enviado à vendedora';
    case 'awaiting_payment':
      return 'Portes confirmados — já podes pagar';
    case 'expired':
      return 'O pedido expirou. Não foste cobrada.';
    case 'cancelled':
      return 'Pedido de conjunto cancelado';
    case 'purchased':
      return 'Conjunto pago';
    default:
      return 'Pedido de conjunto';
  }
}

String bundleBuyerStatusBody(Map<String, dynamic> bundle) {
  final status = (bundle['status']?.toString() ?? '').trim();
  switch (status) {
    case 'pending':
      final until = formatBundleDeadlinePt(bundle['seller_confirm_expires_at']);
      final prazo = until == null
          ? 'A vendedora tem 48 horas para confirmar os portes.'
          : 'A vendedora tem de confirmar os portes até $until.';
      return '$prazo Os artigos não ficam reservados — continuam à venda.';
    case 'awaiting_payment':
      final until = formatBundleDeadlinePt(bundle['pay_expires_at']);
      final prazo = until == null
          ? 'Tens 48 horas para concluir a compra.'
          : 'Tens até $until para concluir a compra.';
      return '$prazo Podes desistir livremente. Os artigos só ficam teus após o pagamento.';
    case 'expired':
      return 'O prazo acabou sem confirmação ou pagamento. Podes pedir um novo conjunto.';
    default:
      return '';
  }
}

String bundleSellerStatusHeadline(Map<String, dynamic> bundle) {
  switch ((bundle['status']?.toString() ?? '').trim()) {
    case 'pending':
      return 'Novo pedido de conjunto';
    case 'awaiting_payment':
      return 'À espera do pagamento da compradora';
    case 'expired':
      return 'Pedido de conjunto expirado';
    case 'cancelled':
      return 'Pedido de conjunto cancelado';
    case 'purchased':
      return 'Conjunto pago';
    default:
      return 'Pedido de conjunto';
  }
}

String bundleSellerStatusBody(Map<String, dynamic> bundle) {
  final status = (bundle['status']?.toString() ?? '').trim();
  switch (status) {
    case 'pending':
      final until = formatBundleDeadlinePt(bundle['seller_confirm_expires_at']);
      final prazo = until == null
          ? 'Tens 48 horas para confirmar o peso e os portes.'
          : 'Confirma o peso e os portes até $until.';
      return '$prazo Os artigos continuam disponíveis para venda.';
    case 'awaiting_payment':
      final until = formatBundleDeadlinePt(bundle['pay_expires_at']);
      if (until != null) {
        return 'Cotação enviada. A compradora pode pagar até $until.';
      }
      return 'Cotação enviada. A compradora pode pagar quando quiser (prazo activo no servidor).';
    default:
      return '';
  }
}

double centsToEur(num? cents) => ((cents ?? 0).toInt()) / 100.0;

String formatBundleEur(num euros) {
  final v = euros.toDouble();
  final s = v.toStringAsFixed(2).replaceAll('.', ',');
  return '$s €';
}

Map<String, dynamic> _asMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return <String, dynamic>{};
}

Future<Map<String, dynamic>> batataBundleTouchExpiry(String? bundleId) async {
  final id = (bundleId ?? '').trim();
  final res = await SupaFlow.client.rpc(
    'batata_bundle_touch_expiry',
    params: id.isEmpty
        ? <String, dynamic>{}
        : <String, dynamic>{'p_bundle_id': id},
  );
  return _asMap(res);
}

Future<Map<String, dynamic>> batataBundleSellerConfirmQuote({
  required String bundleId,
  required double weightKg,
  String? weightBand,
  String shippingModality = 'shop_to_shop',
  String shippingMethod = 'Envio Transportadora (DPD)',
  String? deliveryPointRef,
}) async {
  final res = await SupaFlow.client.rpc(
    'batata_bundle_seller_confirm_quote',
    params: {
      'p_bundle_id': bundleId,
      'p_weight_kg': weightKg,
      'p_weight_band': weightBand,
      'p_shipping_modality': shippingModality,
      'p_shipping_method': shippingMethod,
      'p_delivery_point_ref': deliveryPointRef,
    },
  );
  return _asMap(res);
}

Future<Map<String, dynamic>> batataBundleAbandon({
  required String bundleId,
  String reason = 'buyer_abandon',
}) async {
  final res = await SupaFlow.client.rpc(
    'batata_bundle_abandon',
    params: {
      'p_bundle_id': bundleId,
      'p_reason': reason,
    },
  );
  return _asMap(res);
}

Future<Map<String, dynamic>> batataBundleCheckoutBegin({
  required String bundleId,
  String? idempotencyKey,
  Map<String, dynamic>? delivery,
}) async {
  final res = await SupaFlow.client.rpc(
    'batata_bundle_checkout_begin',
    params: {
      'p_bundle_id': bundleId,
      'p_client_idempotency_key':
          idempotencyKey ?? 'bundle_pay:${bundleId}:${DateTime.now().millisecondsSinceEpoch}',
      'p_delivery': delivery ?? <String, dynamic>{},
    },
  );
  return _asMap(res);
}

String humanizeBundleQuoteError(Map<String, dynamic> res) {
  final err = (res['error']?.toString() ?? '').trim();
  switch (err) {
    case 'expired':
      return 'Este pedido expirou.';
    case 'article_unavailable':
    case 'quote_invalid':
    case 'stock_unavailable':
    case 'price_changed':
      return 'Este conjunto já não está disponível nas condições anteriores.';
    case 'not_awaiting_payment':
      return 'Ainda não podes pagar — aguarda a confirmação dos portes.';
    case 'weight_invalid':
      return 'Indica um peso válido (até 10 kg).';
    case 'forbidden':
      return 'Sem permissão para esta acção.';
    case 'flag_disabled':
      return 'Fluxo de conjuntos temporariamente indisponível.';
    default:
      final msg = (res['message']?.toString() ?? '').trim();
      if (msg.isNotEmpty) return msg;
      if (err.isNotEmpty) return 'Não foi possível concluir ($err).';
      return 'Não foi possível concluir. Tenta outra vez.';
  }
}

/// Pagar cotação selada: begin (hold) + Stripe Checkout único.
Future<void> payQuotedBundleCheckout({
  required String bundleId,
  String? deliveryPointRef,
}) async {
  if (currentUserUid.isEmpty) {
    throw Exception('Inicia sessão para concluir a compra.');
  }
  await batataBundleTouchExpiry(bundleId);
  final bundle = await SupaFlow.client
      .from('product_bundles')
      .select()
      .eq('id', bundleId)
      .maybeSingle();
  if (bundle == null) throw Exception('Conjunto não encontrado.');
  final map = Map<String, dynamic>.from(bundle as Map);
  if (map['status']?.toString() != 'awaiting_payment') {
    throw Exception(humanizeBundleQuoteError({'error': 'not_awaiting_payment'}));
  }
  if (map['buyer_id']?.toString() != currentUserUid) {
    throw Exception('Apenas a compradora pode pagar este conjunto.');
  }

  final begin = await batataBundleCheckoutBegin(
    bundleId: bundleId,
    delivery: {
      if ((deliveryPointRef ?? '').trim().isNotEmpty)
        'delivery_point_ref': deliveryPointRef!.trim(),
    },
  );
  if (begin['ok'] != true) {
    throw Exception(humanizeBundleQuoteError(begin));
  }

  final attemptId = (begin['checkout_attempt_id']?.toString() ?? '').trim();
  final orderIds = begin['order_ids'] is List
      ? (begin['order_ids'] as List)
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList()
      : <String>[];
  if (attemptId.isEmpty || orderIds.isEmpty) {
    throw Exception('Não foi possível preparar o checkout do conjunto.');
  }

  final articles = (begin['articles_cents'] as num?)?.toInt() ??
      (map['articles_cents'] as num?)?.toInt() ??
      0;
  final shipping = (begin['shipping_cents'] as num?)?.toInt() ??
      (map['shipping_cents'] as num?)?.toInt() ??
      0;
  final protection = (begin['protection_cents'] as num?)?.toInt() ??
      (map['protection_cents'] as num?)?.toInt() ??
      0;
  final total = (begin['total_cents'] as num?)?.toInt() ??
      (map['grand_total_cents'] as num?)?.toInt() ??
      (articles + shipping + protection);
  if (total < 50) {
    throw Exception('Total inválido para pagamento.');
  }

  final sellerId = map['seller_id']?.toString() ?? '';
  final rawIds = map['product_ids'];
  final productIds = rawIds is List
      ? rawIds.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
      : <String>[];

  final bagLines = <Map<String, dynamic>>[];
  for (var i = 0; i < orderIds.length; i++) {
    final pid = i < productIds.length ? productIds[i] : (productIds.isNotEmpty ? productIds.first : '');
    bagLines.add({
      'order_id': orderIds[i],
      'product_id': pid,
      'seller_id': sellerId,
      'quantity': 1,
      'line_total_cents': 0,
      'item_label': 'Artigo do conjunto',
    });
  }

  final first = bagLines.first;
  final shipMethod =
      (map['quote_shipping_method']?.toString() ?? '').trim().isNotEmpty
          ? map['quote_shipping_method'].toString()
          : 'Envio Transportadora (DPD)';
  final modality =
      (map['quote_shipping_modality']?.toString() ?? 'shop_to_shop').trim();
  final band = (map['quote_weight_band']?.toString() ?? '').trim();

  final result = await fleaberInvokeCreatePaymentIntent(
    body: {
      'amount': total,
      'currency': 'eur',
      'product_id': first['product_id'],
      'buyer_id': currentUserUid,
      'seller_id': sellerId,
      'order_id': first['order_id'],
      'quantity': 1,
      'item_price': articles,
      'shipping': shipping,
      'protection_fee': protection,
      'shipping_method': shipMethod,
      if (band.isNotEmpty) 'shipping_weight_band': band,
      'shipping_modality': modality,
      'bag_checkout': true,
      'bag_lines': bagLines,
      'checkout_attempt_id': attemptId,
    },
    logContext: {'source': 'pay_quoted_bundle'},
  );

  await FleaberStripeCheckoutContext.save(
    orderId: first['order_id'] as String,
    productId: first['product_id'] as String,
    sellerId: sellerId,
    checkoutSessionId: result.checkoutSessionId,
    bagOrdersJson: jsonEncode(bagLines),
  );

  final opened = await fleaberLaunchStripeCheckout(
    result.checkoutUrl,
    context: {
      'order_id': first['order_id'],
      'session_id': result.checkoutSessionId,
      'source': 'pay_quoted_bundle',
      'bundle_id': bundleId,
    },
  );
  if (!opened) {
    await FleaberStripeCheckoutContext.clear();
    throw Exception('Não foi possível abrir o checkout Stripe.');
  }

  requestMarketplaceFeedRefresh();
  requestOrdersListRefresh();
  if (kDebugMode) {
    debugPrint('BATATA_BUNDLE_QUOTE pay begin ok bundle=$bundleId attempt=$attemptId');
  }
}

FleaberDpdWeightBand? bandFromKg(double kg) => FleaberDpdWeightBand.fromKg(kg);
