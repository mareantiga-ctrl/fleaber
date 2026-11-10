import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/batata_bundle_discounts.dart';
import '/batata_reservation_actions.dart';
import '/chat_session_util.dart';
import '/marketplace_feed_refresh.dart';
import '/order_cancel_apply.dart';
import '/order_cancel_eligibility.dart';
import '/utils/dpd_shipping_rates.dart';
import '/utils/fee_calculator.dart';
import '/utils/order_shipment_weight.dart';
import '/utils/fleaber_notify_emit.dart';
import '/utils/fleaber_stripe_checkout_context.dart';
import '/utils/fleaber_stripe_launch.dart';
import '/utils/live_raffle_prize_copy.dart';

const kBundleCounterRlsUserMessage =
    'Sem permissão para contrapropor neste conjunto. Atualiza o chat e tenta novamente.';

class BundleProposalPermissionException implements Exception {
  const BundleProposalPermissionException(this.message);
  final String message;
  @override
  String toString() => message;
}

int _euroCents(double value) => (value * 100).round();

/// Arredonda a 2 casas — alinhar com `numeric(12,2)` do trigger BD.
double _bundleMoney(num? value, [double fallback = 0]) {
  final v = (value ?? fallback).toDouble();
  return double.parse(v.toStringAsFixed(2));
}

/// Expande `product_ids` pela quantidade (1 entrada por unidade) para o
/// subtotal de catálogo na BD contar unidades, não só SKUs distintos.
List<String> expandBundleProductIdsForCatalog(
  List<String> uniqueProductIds,
  BundleProductQuantities quantities,
) {
  final out = <String>[];
  for (final id in uniqueProductIds) {
    if (id.isEmpty) continue;
    final qty = (quantities[id] ?? 1).clamp(1, 999);
    for (var i = 0; i < qty; i++) {
      out.add(id);
    }
  }
  return out;
}

Map<String, dynamic> bundleProposalChatPayload({
  required String bundleId,
  required List<String> productIds,
  required String sellerId,
  required String buyerId,
  required double subtotalEur,
  required double discountPct,
  required double discountEur,
  required double totalEur,
  String requestMode = 'discount',
  BundleProductQuantities? productQuantities,
  String? prizeOrderId,
}) =>
    {
      'kind': 'bundle_proposal',
      'bundle_id': bundleId,
      'product_ids': productIds,
      if (productQuantities != null && productQuantities.isNotEmpty)
        'product_quantities': productQuantities,
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'subtotal_eur': _bundleMoney(subtotalEur),
      'discount_pct': _bundleMoney(discountPct),
      'discount_eur': _bundleMoney(discountEur),
      'total_eur': _bundleMoney(totalEur),
      'request_mode': requestMode,
      if (prizeOrderId != null && prizeOrderId.trim().isNotEmpty)
        'prize_order_id': prizeOrderId.trim(),
      'v': 1,
    };

Map<String, dynamic>? tryParseBundleProposalChatPayload(String text) {
  if (text.startsWith(kFleaberChatJsonPrefix)) {
    try {
      final decoded =
          jsonDecode(text.substring(kFleaberChatJsonPrefix.length));
      if (decoded is Map &&
          decoded['kind']?.toString() == 'bundle_proposal') {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
  }
  if (text.trim().startsWith('{')) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['kind']?.toString() == 'bundle_proposal') {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
  }
  return null;
}

Future<Map<String, dynamic>?> fetchLatestOperationalBundleForChat(
  String chatId,
) async {
  if (chatId.isEmpty) return null;
  try {
    final rows = await SupaFlow.client
        .from('product_bundles')
        .select()
        .eq('chat_id', chatId)
        .inFilter('status', ['pending', 'awaiting_payment', 'accepted'])
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  } catch (_) {
    return null;
  }
}

/// Último conjunto do chat (qualquer estado) — header após recusa/cancelamento.
Future<Map<String, dynamic>?> fetchLatestBundleMetaForChat(
  String chatId,
) async {
  if (chatId.isEmpty) return null;
  try {
    final rows = await SupaFlow.client
        .from('product_bundles')
        .select()
        .eq('chat_id', chatId)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  } catch (_) {
    return null;
  }
}

void _logBundleProposal(String message, {Object? error, StackTrace? stack}) {
  final line = 'BATATA_BUNDLE_PROPOSAL $message';
  debugPrint(line);
  if (error != null) debugPrint('BATATA_BUNDLE_PROPOSAL error=$error');
  if (stack != null) debugPrint('BATATA_BUNDLE_PROPOSAL stack=$stack');
}

bool _isBundleProposalRlsDenied(Object error) {
  if (error is PostgrestException) {
    return error.code == '42501';
  }
  final s = error.toString();
  return s.contains('42501') ||
      s.contains('codex42501') ||
      s.contains('permission denied');
}

void _logBundleProposalRls({
  required String phase,
  required Object error,
  StackTrace? stack,
  String? bundleId,
  String? sellerId,
  String? buyerId,
  String? chatId,
}) {
  var code = '';
  var message = error.toString();
  if (error is PostgrestException) {
    code = error.code ?? '';
    message = error.message;
  }
  _logBundleProposal(
    'RLS phase=$phase bundle_id=$bundleId seller_id=$sellerId '
    'buyer_id=$buyerId chat_id=$chatId code=$code message=$message',
    error: error,
    stack: stack,
  );
}

Future<Map<String, dynamic>?> fetchProductBundle(String bundleId) async {
  if (bundleId.isEmpty) return null;
  try {
    final row = await SupaFlow.client
        .from('product_bundles')
        .select()
        .eq('id', bundleId)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  } catch (_) {
    return null;
  }
}

Future<String> _buyerFirstNameForChat() async {
  if (currentUserUid.isEmpty) return 'Comprador';
  try {
    final rows = await ProfilesTable().queryRows(
      queryFn: (q) => q.eqOrNull('id', currentUserUid),
      limit: 1,
    );
    if (rows.isEmpty) return 'Comprador';
    final full = rows.first.fullName?.trim() ?? '';
    if (full.isEmpty) return 'Comprador';
    return full.split(RegExp(r'\s+')).first;
  } catch (_) {
    return 'Comprador';
  }
}

List<double> allocateBundleLinePrices({
  required List<ProductsRow> products,
  required double totalEur,
  BundleProductQuantities? quantitiesByProductId,
}) {
  if (products.isEmpty) return const [];
  final quantities =
      quantitiesByProductId ?? defaultBundleQuantities(products);
  final subtotal = bundleSubtotal(
    products,
    quantitiesByProductId: quantities,
  );
  if (subtotal <= 0) {
    final each = totalEur / products.length;
    return List<double>.generate(products.length, (_) => each);
  }
  final weights = products
      .map(
        (p) => (p.price ?? 0.0) * bundleQuantityForProduct(quantities, p),
      )
      .toList();
  var allocated = 0.0;
  final out = <double>[];
  for (var i = 0; i < products.length; i++) {
    if (i == products.length - 1) {
      out.add((totalEur - allocated).clamp(0.0, double.infinity));
    } else {
      final share = double.parse(
        (totalEur * (weights[i] / subtotal)).toStringAsFixed(2),
      );
      out.add(share);
      allocated += share;
    }
  }
  return out;
}

Future<BundleProductQuantities> _loadBundleQuantitiesForBundle({
  required String bundleId,
  String? chatId,
  required List<ProductsRow> products,
}) async {
  if (chatId != null && chatId.isNotEmpty) {
    try {
      final messages = await ChatMessagesTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('chat_id', chatId)
            .order('created_at', ascending: false),
        limit: 80,
      );
      for (final message in messages) {
        final payload = tryParseBundleProposalChatPayload(message.text ?? '');
        if (payload == null) continue;
        if (payload['bundle_id']?.toString() != bundleId) continue;
        return parseBundleQuantitiesFromPayload(
          payload['product_quantities'],
          products,
        );
      }
    } catch (_) {}
  }
  return defaultBundleQuantities(products);
}

/// Normaliza `product_ids` vindos do PostgREST (List, string JSON, ou `{uuid,uuid}`).
List<String> parseBundleProductIds(dynamic rawIds) {
  if (rawIds == null) return const [];
  if (rawIds is List) {
    return rawIds
        .map((e) => e.toString().trim())
        .where((id) => id.isNotEmpty)
        .toList();
  }
  final s = rawIds.toString().trim();
  if (s.isEmpty) return const [];
  if (s.startsWith('[')) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim())
            .where((id) => id.isNotEmpty)
            .toList();
      }
    } catch (_) {}
  }
  // Postgres array textual: {uuid,uuid}
  if (s.startsWith('{') && s.endsWith('}')) {
    return s
        .substring(1, s.length - 1)
        .split(',')
        .map((e) => e.trim().replaceAll('"', ''))
        .where((id) => id.isNotEmpty)
        .toList();
  }
  return s
      .split(RegExp(r'[\s,]+'))
      .map((e) => e.trim())
      .where((id) => id.isNotEmpty)
      .toList();
}

/// Fallback H10: último `bundle_proposal` no chat → linhas de header.
Future<List<OrdersRow>> buildBundleDisplayOrdersFromLatestChatMessage(
  String chatId,
) async {
  if (chatId.isEmpty) return const [];
  try {
    final messages = await ChatMessagesTable().queryRows(
      queryFn: (q) =>
          q.eqOrNull('chat_id', chatId).order('created_at', ascending: false),
      limit: 40,
    );
    for (final message in messages) {
      final payload = tryParseBundleProposalChatPayload(message.text ?? '');
      if (payload == null) continue;
      final productIds = parseBundleProductIds(payload['product_ids']);
      if (productIds.length < 2) continue;
      final bundleId = payload['bundle_id']?.toString().trim() ?? '';
      final meta = <String, dynamic>{
        'id': bundleId,
        'chat_id': chatId,
        'product_ids': productIds,
        'total_eur': payload['total_eur'],
        'status': 'pending',
      };
      // Quantidades já no payload — injectar via meta + mensagem.
      final orders = await buildBundleDisplayOrdersFromMeta(meta);
      if (orders.length >= 2) return orders;
    }
  } catch (_) {}
  return const [];
}

/// Linhas de exibição para header chat (pending sem encomendas ou fallback).
Future<List<OrdersRow>> buildBundleDisplayOrdersFromMeta(
  Map<String, dynamic> bundle,
) async {
  final bundleId = bundle['id']?.toString().trim() ?? '';
  final rawProductIds = parseBundleProductIds(bundle['product_ids']);
  if (rawProductIds.isEmpty) return const [];
  // Deduplicar SKUs (array BD pode repetir uuid por qty).
  final productIds = <String>[];
  final seenIds = <String>{};
  for (final id in rawProductIds) {
    if (seenIds.add(id)) productIds.add(id);
  }

  final products = await _loadBundleProducts(productIds);
  if (products.isEmpty) return const [];

  final quantities = await _loadBundleQuantitiesForBundle(
    bundleId: bundleId,
    chatId: bundle['chat_id']?.toString(),
    products: products,
  );
  final totalEur = (bundle['total_eur'] as num?)?.toDouble() ??
      bundleSubtotal(products, quantitiesByProductId: quantities);
  final linePrices = allocateBundleLinePrices(
    products: products,
    totalEur: totalEur,
    quantitiesByProductId: quantities,
  );
  final bundleStatus = bundle['status']?.toString() ?? 'pending';
  // Quote-before-pay: sem hold — não marcar como «reservado» na UI.
  final orderStatus = bundleStatus == 'accepted'
      ? 'reservado'
      : (bundleStatus == 'awaiting_payment' || bundleStatus == 'pending')
          ? 'pedido_conjunto'
          : 'reserva_pendente';

  final out = <OrdersRow>[];
  for (var i = 0; i < products.length; i++) {
    final product = products[i];
    final pid = product.id ?? '';
    if (pid.isEmpty) continue;
    out.add(OrdersRow({
      'product_id': pid,
      'quantity': bundleQuantityForProduct(quantities, product),
      'price_total': linePrices[i],
      'status': orderStatus,
      'bundle_id': bundleId.isEmpty ? null : bundleId,
    }));
  }
  return out;
}

double bundleCheckoutGrandTotalEur(
  double itemsTotalEur, {
  bool pickup = false,
  FleaberDpdWeightBand? band,
  double? weightKg,
}) {
  final shipping = fleaberCheckoutDpdShippingEur(
    pickup: pickup,
    band: band,
    weightKg: weightKg,
  );
  final protection =
      calculateFleaberProtectionFee(itemsTotalEur, shippingEur: shipping);
  return itemsTotalEur + protection + shipping;
}

bool bundlePaymentMethodIsDirect(String? paymentMethod) {
  return (paymentMethod ?? '').toLowerCase().contains('direto');
}

bool bundleOrdersAwaitingCheckoutChoice(List<OrdersRow> orders) {
  if (orders.isEmpty) return false;
  for (final o in orders) {
    final pm = (o.paymentMethod ?? '').toLowerCase();
    if (pm.contains('conjunto aceite')) return true;
  }
  return false;
}

bool bundleOrdersDirectPaymentPending(List<OrdersRow> orders) {
  if (orders.isEmpty || bundleOrdersAwaitingCheckoutChoice(orders)) {
    return false;
  }
  for (final o in orders) {
    final st = normalizeOrderStatusKey(o.status);
    if (st == 'reservado' && bundlePaymentMethodIsDirect(o.paymentMethod)) {
      return true;
    }
  }
  return false;
}

/// B3: display/legado — mesma regra canónica leniente que fee_calculator.
/// Checkout novo / Edge usam allowlist exacta ([fleaberShippingEurFromMethod]).
double bundleShippingEurFromMethod(String? shippingMethod) =>
    fleaberShippingEurFromMethodLenient(shippingMethod);

double bundleDirectPaymentAmountEur({
  required double itemsTotalEur,
  required String? shippingMethod,
}) {
  return itemsTotalEur + bundleShippingEurFromMethod(shippingMethod);
}

Map<String, dynamic>? tryParseBundleDirectPaymentPayload(String text) {
  if (text.startsWith(kFleaberChatJsonPrefix)) {
    try {
      final decoded =
          jsonDecode(text.substring(kFleaberChatJsonPrefix.length));
      if (decoded is Map) {
        final kind = decoded['kind']?.toString();
        if (kind == 'bundle_direct_payment_details' ||
            kind == 'order_direct_payment_details') {
          return Map<String, dynamic>.from(decoded);
        }
      }
    } catch (_) {}
  }
  return null;
}

Future<Map<String, dynamic>> buildOrderDirectPaymentDetails({
  required String orderId,
  required String sellerId,
  required double amountEur,
  double? itemsEur,
  double? shippingEur,
}) async {
  var mbWay = '';
  var iban = '';
  if (sellerId.isNotEmpty) {
    final payout = await SupaFlow.client.rpc(
      'batata_seller_direct_payment_details',
      params: {'p_seller_id': sellerId},
    );
    if (payout is List && payout.isNotEmpty) {
      final row = Map<String, dynamic>.from(payout.first as Map);
      mbWay = row['mb_way']?.toString().trim() ?? '';
      iban = row['iban']?.toString().trim() ?? '';
    }
  }
  return {
    'kind': 'order_direct_payment_details',
    'order_id': orderId,
    'amount_eur': amountEur,
    if (itemsEur != null) 'items_eur': itemsEur,
    if (shippingEur != null) 'shipping_eur': shippingEur,
    'mb_way': mbWay,
    'iban': iban,
    'v': 1,
  };
}

/// Payload mínimo no chat (sem MB WAY/IBAN — só no sheet).
Map<String, dynamic> orderDirectPaymentChatPayload({
  required String orderId,
  required double amountEur,
}) =>
    {
      'kind': 'order_direct_payment_details',
      'order_id': orderId,
      'amount_eur': amountEur,
      'v': 1,
    };

Future<void> insertOrderDirectPaymentDetailsMessage({
  required String orderId,
  required String chatId,
  required String sellerId,
  required String buyerId,
  required double amountEur,
}) async {
  await ChatMessagesTable().insert({
    'sender_id': buyerId,
    'receiver_id': sellerId,
    'is_read': false,
    'text': fleaberChatJsonEncode(
      orderDirectPaymentChatPayload(
        orderId: orderId,
        amountEur: amountEur,
      ),
    ),
    'chat_id': chatId,
    'is_reservation': true,
  });
}

Future<Map<String, dynamic>> buildBundleDirectPaymentDetails({
  required String bundleId,
}) async {
  final bundle = await fetchProductBundle(bundleId);
  if (bundle == null) throw Exception('Conjunto não encontrado.');

  final orders = await OrdersTable().queryRows(
    queryFn: (q) => q.eqOrNull('bundle_id', bundleId),
    limit: 20,
  );
  if (orders.isEmpty) throw Exception('Encomendas do conjunto não encontradas.');

  final itemsTotal = (bundle['total_eur'] as num?)?.toDouble() ??
      orders.fold<double>(0, (s, o) => s + (o.priceTotal ?? 0));
  final shippingMethod = orders.first.shippingMethod;
  final shippingEur = bundleShippingEurFromMethod(shippingMethod);
  final amount = itemsTotal + shippingEur;

  final sellerId = bundle['seller_id']?.toString() ?? orders.first.sellerId ?? '';
  var mbWay = '';
  var iban = '';
  if (sellerId.isNotEmpty) {
    final payout = await SupaFlow.client.rpc(
      'batata_seller_direct_payment_details',
      params: {'p_seller_id': sellerId},
    );
    if (payout is List && payout.isNotEmpty) {
      final row = Map<String, dynamic>.from(payout.first as Map);
      mbWay = row['mb_way']?.toString().trim() ?? '';
      iban = row['iban']?.toString().trim() ?? '';
    }
  }

  return {
    'kind': 'bundle_direct_payment_details',
    'bundle_id': bundleId,
    'amount_eur': amount,
    'items_eur': itemsTotal,
    'shipping_eur': shippingEur,
    'mb_way': mbWay,
    'iban': iban,
    'v': 1,
  };
}

/// Payload mínimo para mensagem no chat (sem MB WAY/IBAN — só no sheet).
Map<String, dynamic> bundleDirectPaymentChatPayload({
  required String bundleId,
  required double amountEur,
}) =>
    {
      'kind': 'bundle_direct_payment_details',
      'bundle_id': bundleId,
      'amount_eur': amountEur,
      'v': 2,
    };

Future<void> insertBundleDirectPaymentDetailsMessage({
  required String bundleId,
  required String chatId,
  required String sellerId,
  required String buyerId,
  required String shippingMethod,
}) async {
  final details = await buildBundleDirectPaymentDetails(bundleId: bundleId);
  final amount = (details['amount_eur'] as num?)?.toDouble() ?? 0.0;

  await ChatMessagesTable().insert({
    'sender_id': buyerId,
    'receiver_id': sellerId,
    'is_read': false,
    'text': fleaberChatJsonEncode(
      bundleDirectPaymentChatPayload(
        bundleId: bundleId,
        amountEur: amount,
      ),
    ),
    'chat_id': chatId,
    'is_reservation': true,
  });
}

bool bundleAllOrdersPaidOrBeyond(List<OrdersRow> orders) {
  if (orders.length < 2) return false;
  var hasPaidLine = false;
  for (final o in orders) {
    if (orderIsCancelled(o.status)) continue;
    final s = normalizeOrderStatusKey(o.status);
    if (s == 'pago' || s == 'enviado' || s == 'concluido') {
      hasPaidLine = true;
      continue;
    }
    if (s == 'premio_rifa') {
      hasPaidLine = true;
      continue;
    }
    return false;
  }
  return hasPaidLine;
}

bool bundleOrdersAwaitingSellerPaymentConfirm(List<OrdersRow> orders) {
  if (orders.length < 2) return false;
  return orders.any(
    (o) => normalizeOrderStatusKey(o.status) == 'aguarda_confirmacao',
  );
}

bool bundleUsesCarrierShipping(List<OrdersRow> orders) {
  if (orders.isEmpty) return true;
  // Qualquer linha em mão (prémio ou venda normal) → pacote em mão.
  if (orders.any(
    (o) => LiveRafflePrizeCopy.isHandShippingMethod(o.shippingMethod),
  )) {
    return false;
  }
  var sawCarrier = false;
  var sawSameAsPrize = false;
  for (final o in orders) {
    final sm = (o.shippingMethod ?? '').toLowerCase();
    if (sm.contains('mesmo envio')) {
      sawSameAsPrize = true;
      continue;
    }
    if (sm.contains('mão') || sm.contains('mao') || sm.contains('0.00')) {
      return false;
    }
    if (sm.contains('transportadora') || sm.contains('3.50')) {
      sawCarrier = true;
    }
  }
  // Addon «Mesmo envio do Prémio» sem transportadora explícita → herda mão
  // (não mostrar «Descarregar etiqueta»).
  if (sawSameAsPrize && !sawCarrier) return false;
  if (sawCarrier) return true;
  // Vendas clássicas sem label claro: manter etiqueta (comportamento anterior).
  return true;
}

String bundleSellerShipButtonLabel(List<OrdersRow> orders) {
  if (bundleUsesCarrierShipping(orders)) {
    return 'Descarregar etiqueta de envio';
  }
  final hand = orders.any(
    (o) => LiveRafflePrizeCopy.isHandShippingMethod(o.shippingMethod),
  );
  return hand ? 'Confirmei entrega em mão' : 'Confirmar envio';
}

/// Vendedor confirma MB WAY/transferência de conjunto aceite → todas as linhas `pago`.
/// Stock decrementado pelo trigger SQL (quantity por linha). Sem card de artigo único.
Future<void> confirmSellerBundleDirectPayment({
  required String bundleId,
}) async {
  if (currentUserUid.isEmpty) {
    throw Exception('Inicia sessão para confirmar o pagamento.');
  }
  if (bundleId.isEmpty) throw Exception('Conjunto inválido.');

  final bundle = await fetchProductBundle(bundleId);
  if (bundle == null) throw Exception('Conjunto não encontrado.');
  if (bundle['seller_id']?.toString() != currentUserUid) {
    throw Exception('Apenas o vendedor pode confirmar este pagamento.');
  }

  final orders = await OrdersTable().queryRows(
    queryFn: (q) => q.eqOrNull('bundle_id', bundleId),
    limit: 20,
  );
  if (orders.length < 2) {
    throw Exception('Encomendas do conjunto incompletas.');
  }

  final awaiting = orders.where((o) {
    final s = normalizeOrderStatusKey(o.status);
    return s == 'aguarda_confirmacao' || s == 'reservado';
  }).toList();
  if (awaiting.isEmpty) {
    throw Exception('Não há pagamentos deste conjunto a confirmar.');
  }

  for (final o in awaiting) {
    final oid = o.id?.trim() ?? '';
    if (oid.isEmpty) continue;
    await OrdersTable().update(
      data: {'status': 'pago'},
      matchingRows: (rows) => rows.eqOrNull('id', oid),
    );
    await batataSyncLiveCatalogForOrder(oid);
    print(
      'BATATA_BUNDLE_CONFIRM product=${o.productId} order=$oid '
      'qty=${o.quantity ?? 1} → pago',
    );
  }

  await SupaFlow.client.from('product_bundles').update({
    'status': 'purchased',
  }).eq('id', bundleId);

  final chatId = bundle['chat_id']?.toString();
  if (chatId != null && chatId.isNotEmpty) {
    await touchChatLastMessage(
      chatId: chatId,
      preview: 'Conjunto pago — envia os artigos',
    );
  }

  requestMarketplaceFeedRefresh();
  requestOrdersListRefresh();
  pingBatataReservationForNotificationBell();
}

void _assertBundleStockAvailable(
  List<ProductsRow> products,
  BundleProductQuantities quantities,
) {
  for (final product in products) {
    final pid = product.id ?? '';
    if (pid.isEmpty) continue;
    final requested = bundleQuantityForProduct(quantities, product);
    final available = product.quantity ?? 1;
    if (requested > available) {
      throw Exception(
        'Stock insuficiente para «${product.title ?? 'artigo'}» '
        '(pediste $requested, disponível $available).',
      );
    }
  }
}

Future<List<ProductsRow>> _loadBundleProducts(List<String> productIds) async {
  if (productIds.isEmpty) return const [];
  final rows = await ProductsTable().queryRows(
    queryFn: (q) => q.inFilter('id', productIds),
    limit: productIds.length,
  );
  final byId = {for (final p in rows) if (p.id != null) p.id!: p};
  return productIds.map((id) => byId[id]).whereType<ProductsRow>().toList();
}

/// Cancela linhas reservado/aguarda_confirmacao e repõe stock no marketplace.
Future<void> releaseBundleReservationOrdersStock({
  required String bundleId,
  required String sellerUserId,
}) async {
  if (bundleId.isEmpty || sellerUserId.isEmpty) return;
  final orders = await OrdersTable().queryRows(
    queryFn: (q) => q.eqOrNull('bundle_id', bundleId),
    limit: 20,
  );
  for (final o in orders) {
    final st = normalizeOrderStatusKey(o.status);
    if (st != 'reservado' && st != 'aguarda_confirmacao') continue;
    final oid = o.id?.trim() ?? '';
    if (oid.isEmpty) continue;
    await applyOrderCancelAndRelist(
      orderId: oid,
      sellerUserId: sellerUserId,
    );
    await batataSyncLiveCatalogForOrder(oid);
  }
}

Future<Map<String, dynamic>> _persistBundleProposal({
  required String sellerId,
  required List<ProductsRow> products,
  required double subtotal,
  required double discountPct,
  required double discountEur,
  required double total,
  required String requestMode,
  BundleProductQuantities? productQuantities,
  String? buyerIdOverride,
  String? senderIdOverride,
  String? receiverIdOverride,
  String? chatIdOverride,
  bool skipSupersede = false,
  int minProducts = 2,
  String? prizeOrderId,
}) async {
  _logBundleProposal('start seller=$sellerId products=${products.length}');
  try {
  final productIds = products
      .map((p) => p.id)
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toList();
  if (productIds.length < minProducts) {
    throw Exception(
      minProducts <= 1
          ? 'Escolhe pelo menos 1 artigo.'
          : 'Escolhe pelo menos 2 artigos.',
    );
  }
  final quantities = productQuantities ?? defaultBundleQuantities(products);
  _assertBundleStockAvailable(products, quantities);

  // Trigger BD `batata_product_bundles_guard_write` recalcula total via
  // `batata_product_bundles_catalog_subtotal(product_ids)`. Com unnest, cada
  // ocorrência conta — expandir IDs pela qty (paridade multi-unidade Android).
  final productIdsForDb = expandBundleProductIdsForCatalog(productIds, quantities);
  final subMoney = _bundleMoney(subtotal);
  final discPctMoney = _bundleMoney(discountPct);
  final discEurMoney = _bundleMoney(discountEur);
  final totalMoney = _bundleMoney(total);

  final buyerId = buyerIdOverride ?? currentUserUid;
  String? chatId = chatIdOverride?.trim();
  if (chatId == null || chatId.isEmpty) {
    final otherUserId =
        currentUserUid == sellerId ? buyerId : sellerId;
    // CHAT-MULTI (mesmo contrato que compra/rifa paga): pedido de conjunto
    // NOVO → thread nova. Não reutilizar o chat do 1.º productId (misturava
    // pedidos distintos). Respostas na mesma conversa passam chatIdOverride.
    final chat = await ensureSellerChat(
      otherUserId: otherUserId,
      productId: productIds.first,
      forceNew: true,
    );
    chatId = chat.id;
  }
  if (chatId == null || chatId.isEmpty) {
    throw Exception('Não foi possível abrir a conversa.');
  }

  final senderId = senderIdOverride ?? currentUserUid;
  final receiverId = receiverIdOverride ??
      (senderId == sellerId ? buyerId : sellerId);

  if (!skipSupersede) {
    await supersedeStaleOperationalBundlesForNewProposal(chatId);
  }

  late final Map<String, dynamic> bundleRow;
  try {
    bundleRow = Map<String, dynamic>.from(
      await SupaFlow.client
          .from('product_bundles')
          .insert({
            'seller_id': sellerId,
            'buyer_id': buyerId,
            'chat_id': chatId,
            'product_ids': productIdsForDb,
            'subtotal_eur': subMoney,
            'discount_pct': discPctMoney,
            'discount_eur': discEurMoney,
            'total_eur': totalMoney,
            'status': 'pending',
          })
          .select()
          .single() as Map,
    );
  } catch (e, st) {
    if (_isBundleProposalRlsDenied(e)) {
      _logBundleProposalRls(
        phase: 'insert_$requestMode',
        error: e,
        stack: st,
        sellerId: sellerId,
        buyerId: buyerId,
        chatId: chatId,
      );
      throw const BundleProposalPermissionException(kBundleCounterRlsUserMessage);
    }
    rethrow;
  }

  final bundleId = bundleRow['id']?.toString() ?? '';
  // Obrigatório: a mensagem tem de usar o total persistido na BD (após trigger).
  // Senão: chat_system_card_bundle_total_mismatch (23514).
  final persistedSubtotal =
      _bundleMoney(bundleRow['subtotal_eur'], subMoney);
  final persistedDiscountPct =
      _bundleMoney(bundleRow['discount_pct'], discPctMoney);
  final persistedDiscountEur =
      _bundleMoney(bundleRow['discount_eur'], discEurMoney);
  final persistedTotal = _bundleMoney(bundleRow['total_eur'], totalMoney);

  final preview = requestMode == 'prize_addon'
      ? 'Juntar peças ao prémio · ${bundleTotalItemCount(products, quantities)} artigos · ${formatEuros(persistedTotal)}'
      : requestMode == 'purchase_request'
          ? 'Pedido de compra em conjunto · ${bundleTotalItemCount(products, quantities)} artigos'
          : requestMode == 'seller_counter'
              ? 'Contraproposta de conjunto · ${formatEuros(persistedTotal)}'
              : 'Conjunto: ${bundleTotalItemCount(products, quantities)} artigos · ${formatEuros(persistedTotal)}';

  await ChatMessagesTable().insert({
    'sender_id': senderId,
    'receiver_id': receiverId,
    'chat_id': chatId,
    'text': fleaberChatJsonEncode(
      bundleProposalChatPayload(
        bundleId: bundleId,
        // Mesmo array que product_bundles.product_ids (incl. repetições qty)
        // — senão chat_system_card_bundle_products_mismatch.
        productIds: productIdsForDb,
        sellerId: sellerId,
        buyerId: buyerId,
        subtotalEur: persistedSubtotal,
        discountPct: persistedDiscountPct,
        discountEur: persistedDiscountEur,
        totalEur: persistedTotal,
        requestMode: requestMode,
        productQuantities: quantities,
        prizeOrderId: prizeOrderId,
      )..['proposal_ts'] = DateTime.now().toUtc().toIso8601String(),
    ),
    'is_read': false,
    'is_reservation': false,
  });

  // A mensagem já ficou gravada — falha de preview na inbox não deve
  // abortar «Enviar mensagem» (mesmo contrato que notificações).
  try {
    await touchChatLastMessage(chatId: chatId, preview: preview);
  } catch (e, st) {
    _logBundleProposal(
      'touchChatLastMessage soft-fail chat=$chatId',
      error: e,
      stack: st,
    );
  }

  try {
    final buyerName = await _buyerFirstNameForChat();
    final notifyUserId =
        requestMode == 'seller_counter' ? buyerId : sellerId;
    final kind = requestMode == 'purchase_request'
        ? 'bundle_purchase_request'
        : requestMode == 'seller_counter'
            ? 'bundle_proposal_counter'
            : 'bundle_proposal';
    final title = requestMode == 'purchase_request'
        ? 'Novo pedido de conjunto'
        : requestMode == 'seller_counter'
            ? 'Contraproposta de conjunto'
            : 'Nova proposta de conjunto';
    final body = requestMode == 'purchase_request'
        ? '$buyerName · ${bundleTotalItemCount(products, quantities)} artigos · sem reserva — confirma portes em 48h'
        : '${bundleTotalItemCount(products, quantities)} artigos · ${formatEuros(persistedTotal)} (${persistedDiscountPct.toStringAsFixed(0)}% off)';
    final nid = await FleaberNotifyEmit.emit(
      recipientId: notifyUserId,
      kind: kind,
      title: title,
      body: body,
      chatId: chatId,
      actorId: currentUserUid,
      dedupeKey: 'bundle:$bundleId:$kind',
    );
    unawaited(FleaberNotifyEmit.requestDispatch(nid));
  } catch (_) {}

  _logBundleProposal(
    'end bundle_id=$bundleId chat_id=$chatId total=${formatEuros(persistedTotal)} '
    'client_total=${formatEuros(totalMoney)}',
  );
  return {
    'bundle_id': bundleId,
    'chat_id': chatId,
    'seller_id': sellerId,
    'mode': requestMode,
    'subtotal_eur': persistedSubtotal,
    'discount_pct': persistedDiscountPct,
    'discount_eur': persistedDiscountEur,
    'total_eur': persistedTotal,
  };
  } catch (e, st) {
    _logBundleProposal('FAIL', error: e, stack: st);
    rethrow;
  }
}

/// Vencedor da rifa: pedir juntar artigos da loja ao mesmo envio do prémio.
/// Reutiliza o pipeline de conjunto no **mesmo chat** do prémio (sem supersede).
Future<Map<String, dynamic>> createPrizeAddonBundleRequest({
  required String sellerId,
  required String chatId,
  required String prizeOrderId,
  required List<ProductsRow> products,
  BundleProductQuantities? productQuantities,
}) async {
  if (currentUserUid.isEmpty) {
    throw Exception('Inicia sessão para juntar peças ao prémio.');
  }
  final cid = chatId.trim();
  final oid = prizeOrderId.trim();
  if (cid.isEmpty || oid.isEmpty) {
    throw Exception('Chat ou encomenda do prémio em falta.');
  }
  if (products.isEmpty) {
    throw Exception('Escolhe pelo menos 1 artigo.');
  }
  final quantities = productQuantities ?? defaultBundleQuantities(products);
  final tiers = await fetchSellerBundleDiscounts(sellerId);
  final totals = calculateBundleTotals(
    products: products,
    tiers: tiers,
    quantitiesByProductId: quantities,
  );
  return _persistBundleProposal(
    sellerId: sellerId,
    products: products,
    subtotal: totals.subtotal,
    discountPct: totals.discountPct,
    discountEur: totals.discountEur,
    total: totals.total,
    requestMode: 'prize_addon',
    productQuantities: quantities,
    chatIdOverride: cid,
    skipSupersede: true,
    minProducts: 1,
    prizeOrderId: oid,
  );
}

/// Liga a encomenda do prémio ao bundle aceite (mesmo pacote / mesmo envio).
Future<void> linkPrizeOrderToBundle({
  required String bundleId,
  required String prizeOrderId,
}) async {
  final bid = bundleId.trim();
  final oid = prizeOrderId.trim();
  if (bid.isEmpty || oid.isEmpty) return;
  await OrdersTable().update(
    data: {'bundle_id': bid},
    matchingRows: (q) => q.eqOrNull('id', oid),
  );
}

/// Aceitar pedido «juntar ao prémio» + ligar a encomenda do prémio.
Future<void> acceptPrizeAddonBundleProposal({
  required String bundleId,
  required String prizeOrderId,
  bool buyerAccepts = false,
}) async {
  var prizeOid = prizeOrderId.trim();
  await fulfillAcceptedBundle(
    bundleId,
    buyerAccepts: buyerAccepts,
    minProducts: 1,
  );
  // Payload antigo sem prize_order_id: procurar premio_rifa no mesmo chat.
  if (prizeOid.isEmpty) {
    prizeOid = await _resolvePrizeOrderIdForBundle(bundleId) ?? '';
  }
  if (prizeOid.isNotEmpty) {
    await linkPrizeOrderToBundle(
      bundleId: bundleId,
      prizeOrderId: prizeOid,
    );
  }
}

Future<String?> _resolvePrizeOrderIdForBundle(String bundleId) async {
  final bundle = await fetchProductBundle(bundleId);
  if (bundle == null) return null;
  final chatId = bundle['chat_id']?.toString().trim() ?? '';
  final buyerId = bundle['buyer_id']?.toString().trim() ?? '';
  final sellerId = bundle['seller_id']?.toString().trim() ?? '';
  if (buyerId.isEmpty || sellerId.isEmpty) return null;

  final orders = await OrdersTable().queryRows(
    queryFn: (q) => q
        .eqOrNull('buyer_id', buyerId)
        .eqOrNull('seller_id', sellerId)
        .eqOrNull('status', 'premio_rifa')
        .order('created_at', ascending: false),
    limit: 5,
  );
  if (orders.isEmpty) return null;
  // Preferir a mais recente; se o chat tiver product_id, alinhar.
  if (chatId.isNotEmpty) {
    try {
      final chatRows = await ChatsTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', chatId),
        limit: 1,
      );
      final pid = chatRows.isEmpty ? null : chatRows.first.productId?.trim();
      if (pid != null && pid.isNotEmpty) {
        final match = orders.where((o) => o.productId == pid).toList();
        if (match.isNotEmpty) return match.first.id?.trim();
      }
    } catch (_) {}
  }
  return orders.first.id?.trim();
}

Future<Map<String, dynamic>> createBundlePurchaseRequest({
  required String sellerId,
  required List<ProductsRow> products,
  BundleProductQuantities? productQuantities,
}) async {
  if (currentUserUid.isEmpty) {
    throw Exception('Inicia sessão para enviar o pedido.');
  }
  if (products.length < 2) {
    throw Exception('Escolhe pelo menos 2 artigos.');
  }
  final quantities = productQuantities ?? defaultBundleQuantities(products);
  final subtotal = bundleSubtotal(
    products,
    quantitiesByProductId: quantities,
  );
  return _persistBundleProposal(
    sellerId: sellerId,
    products: products,
    subtotal: subtotal,
    discountPct: 0,
    discountEur: 0,
    total: subtotal,
    requestMode: 'purchase_request',
    productQuantities: quantities,
  );
}

/// Proposta de preço do comprador para o conjunto (valor editável no chat).
///
/// Reutiliza o mesmo pipeline `product_bundles` → card no chat → aceite do
/// vendedor cria encomendas com `bundle_id` ([fulfillAcceptedBundle]).
Future<Map<String, dynamic>> createBundlePriceProposal({
  required String sellerId,
  required List<ProductsRow> products,
  required double offeredTotalEur,
  BundleProductQuantities? productQuantities,
  String? chatIdOverride,
  bool skipSupersede = false,
  int minProducts = 2,
  String? prizeOrderId,
  String requestMode = 'price_proposal',
}) async {
  _logBundleProposal(
    'createBundlePriceProposal start seller=$sellerId offered=$offeredTotalEur',
  );
  try {
  if (currentUserUid.isEmpty) {
    throw Exception('Inicia sessão para enviar a proposta.');
  }
  if (products.length < minProducts) {
    throw Exception(
      minProducts <= 1
          ? 'Escolhe pelo menos 1 artigo.'
          : 'Escolhe pelo menos 2 artigos.',
    );
  }
  final quantities = productQuantities ?? defaultBundleQuantities(products);
  final subtotal = bundleSubtotal(
    products,
    quantitiesByProductId: quantities,
  );
  final total = offeredTotalEur <= 0 ? subtotal : offeredTotalEur;
  final discountEur = (subtotal - total).clamp(0.0, double.infinity).toDouble();
  final discountPct = subtotal > 0 ? (discountEur / subtotal) * 100 : 0.0;
  return _persistBundleProposal(
    sellerId: sellerId,
    products: products,
    subtotal: subtotal,
    discountPct: discountPct,
    discountEur: discountEur,
    total: total,
    requestMode: requestMode,
    productQuantities: quantities,
    chatIdOverride: chatIdOverride,
    skipSupersede: skipSupersede,
    minProducts: minProducts,
    prizeOrderId: prizeOrderId,
  );
  } catch (e, st) {
    _logBundleProposal('createBundlePriceProposal FAIL', error: e, stack: st);
    rethrow;
  }
}

Future<Map<String, dynamic>> createBundleProposal({
  required String sellerId,
  required List<ProductsRow> products,
  required BundleDiscountTiers tiers,
  BundleProductQuantities? productQuantities,
}) async {
  if (currentUserUid.isEmpty) {
    throw Exception('Inicia sessão para criar um conjunto.');
  }
  if (products.length < 2) {
    throw Exception('Escolhe pelo menos 2 artigos.');
  }

  final quantities = productQuantities ?? defaultBundleQuantities(products);
  final totals = calculateBundleTotals(
    products: products,
    tiers: tiers,
    quantitiesByProductId: quantities,
  );
  if (tiers.enabled && totals.discountPct > 0) {
    return _persistBundleProposal(
      sellerId: sellerId,
      products: products,
      subtotal: totals.subtotal,
      discountPct: totals.discountPct,
      discountEur: totals.discountEur,
      total: totals.total,
      requestMode: 'discount',
      productQuantities: quantities,
    );
  }

  return createBundlePurchaseRequest(
    sellerId: sellerId,
    products: products,
    productQuantities: quantities,
  );
}

/// True se [a] e [b] têm os mesmos IDs com as mesmas multiplicidades (ordem irrelevante).
bool _sameProductIdMultiset(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  final ca = <String, int>{};
  for (final x in a) {
    final id = x.trim();
    if (id.isEmpty) continue;
    ca[id] = (ca[id] ?? 0) + 1;
  }
  final cb = <String, int>{};
  for (final x in b) {
    final id = x.trim();
    if (id.isEmpty) continue;
    cb[id] = (cb[id] ?? 0) + 1;
  }
  if (ca.length != cb.length) return false;
  for (final e in ca.entries) {
    if (cb[e.key] != e.value) return false;
  }
  return true;
}

List<String> _parseBundleProductIds(dynamic raw) {
  final out = <String>[];
  if (raw is! List) return out;
  for (final x in raw) {
    final s = x?.toString().trim() ?? '';
    if (s.isNotEmpty) out.add(s);
  }
  return out;
}

/// Reutiliza proposta `pending` do comprador com os mesmos artigos (multiset),
/// em vez de cancelar + INSERT (E85.4). O trigger BD já zera desconto hostil
/// no INSERT da proposta — o total persistido é o de catálogo / lista.
Future<String?> _reusePendingBundleForListPriceBuy({
  required String sellerId,
  required List<String> productIdsForDb,
}) async {
  if (currentUserUid.isEmpty || sellerId.isEmpty || productIdsForDb.isEmpty) {
    return null;
  }
  try {
    final rows = await SupaFlow.client
        .from('product_bundles')
        .select('id, status, product_ids, created_at')
        .eq('buyer_id', currentUserUid)
        .eq('seller_id', sellerId)
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .limit(20);
    for (final row in rows) {
      final bid = row['id']?.toString() ?? '';
      if (bid.isEmpty) continue;
      final ids = _parseBundleProductIds(row['product_ids']);
      if (_sameProductIdMultiset(ids, productIdsForDb)) {
        _logBundleProposal(
          'payBundleNow REUSE pending bundle_id=$bid '
          'products=${productIdsForDb.length}',
        );
        return bid;
      }
    }
  } catch (e, st) {
    _logBundleProposal('reuse pending WARN', error: e, stack: st);
  }
  return null;
}

/// «Comprar agora» no conjunto: pagamento **único combinado** (Stripe bag
/// checkout já em produção).
///
/// E85.4: se existir proposta `pending` com os mesmos artigos, **reutiliza**
/// esse `product_bundles` (sem novo INSERT). Caso contrário INSERT só
/// `pending` (guard `bundle_status_pending_only`). Depois das encomendas →
/// `purchased`. Devolve o `bundle_id`.
Future<String> payBundleNow({
  required String sellerId,
  required List<ProductsRow> products,
  required BundleDiscountTiers tiers,
  BundleProductQuantities? productQuantities,
  int minProducts = 2,
  String? chatId,
  String? prizeOrderId,
  double? shippingEurOverride,
  String? shippingMethodOverride,
}) async {
  if (currentUserUid.isEmpty) {
    throw Exception('Inicia sessão para comprar o conjunto.');
  }
  if (sellerId == currentUserUid) {
    throw Exception('Não podes comprar o teu próprio conjunto.');
  }
  final productIds = products
      .map((p) => p.id)
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toList();
  if (productIds.length < minProducts) {
    throw Exception(
      minProducts <= 1
          ? 'Escolhe pelo menos 1 artigo.'
          : 'Escolhe pelo menos 2 artigos.',
    );
  }

  // Disponibilidade fresca de cada artigo.
  final fresh = await _loadBundleProducts(productIds);
  if (fresh.length != productIds.length) {
    throw Exception('Um ou mais artigos já não estão disponíveis.');
  }
  for (final p in fresh) {
    if (p.isSold || p.sellerId != sellerId) {
      throw Exception('Um dos artigos já não está disponível.');
    }
    final pid = p.id ?? '';
    if (pid.isNotEmpty &&
        await _anotherBuyerBlocksProduct(
          productId: pid,
          buyerId: currentUserUid,
        )) {
      throw Exception(
        'Um dos artigos está reservado ou em compra por outro utilizador.',
      );
    }
  }

  final quantities = productQuantities ?? defaultBundleQuantities(fresh);
  _assertBundleStockAvailable(fresh, quantities);

  final totals = calculateBundleTotals(
    products: fresh,
    tiers: tiers,
    quantitiesByProductId: quantities,
  );
  final itemsTotal = totals.total;
  // ZIP 140: agregar peso dos artigos; sem peso → exige override explícito.
  double shipping;
  if (shippingEurOverride != null) {
    shipping = shippingEurOverride;
  } else {
    final agg = fleaberAggregateShipmentWeight([
      for (final p in fresh)
        FleaberShipmentWeightInput.fromProduct(
          p,
          quantity: quantities[p.id] ?? 1,
        ),
    ]);
    if (!agg.ok || agg.band == null) {
      throw Exception(
        agg.message ??
            'Indica o peso ou escalão dos artigos para calcular portes DPD.',
      );
    }
    shipping = fleaberCheckoutDpdShippingEur(
      pickup: false,
      weightKg: agg.totalKg,
      band: agg.band,
    );
  }
  final protection =
      calculateFleaberProtectionFee(itemsTotal, shippingEur: shipping);

  // Cada encomenda guarda o seu custo total ao comprador (item + parte
  // proporcional de proteção + envio), tal como uma venda individual. Assim a
  // soma das linhas == total pago e a lista de Encomendas mostra o valor certo.
  final extras = protection + shipping;
  final itemShares = allocateBundleLinePrices(
    products: fresh,
    totalEur: itemsTotal,
    quantitiesByProductId: quantities,
  );
  final lineTotals = <double>[];
  var allocatedExtra = 0.0;
  for (var i = 0; i < fresh.length; i++) {
    double extraShare;
    if (i == fresh.length - 1) {
      extraShare = extras - allocatedExtra;
    } else {
      extraShare = itemsTotal > 0
          ? double.parse(
              (extras * (itemShares[i] / itemsTotal)).toStringAsFixed(2),
            )
          : double.parse((extras / fresh.length).toStringAsFixed(2));
      allocatedExtra += extraShare;
    }
    lineTotals.add(itemShares[i] + extraShare);
  }

  final productIdsForDb =
      expandBundleProductIdsForCatalog(productIds, quantities);

  // E85.4: reutilizar proposta pending com os mesmos artigos (evita INSERT
  // após «Fazer proposta»). Cancela só os outros conjuntos sobrepostos.
  var bundleId = await _reusePendingBundleForListPriceBuy(
        sellerId: sellerId,
        productIdsForDb: productIdsForDb,
      ) ??
      '';
  await supersedeBuyerPendingBundlesForProducts(
    sellerId: sellerId,
    productIds: productIds,
    excludeBundleId: bundleId.isEmpty ? null : bundleId,
  );

  if (bundleId.isEmpty) {
    // Guard BD: INSERT só `pending` — nunca `purchased` (`bundle_status_pending_only`).
    final chatTrim = chatId?.trim() ?? '';
    _logBundleProposal(
      'payBundleNow INSERT pending seller=$sellerId '
      'products=${productIdsForDb.length}',
    );
    try {
      final bundleRow = await SupaFlow.client
          .from('product_bundles')
          .insert({
            'seller_id': sellerId,
            'buyer_id': currentUserUid,
            if (chatTrim.isNotEmpty) 'chat_id': chatTrim,
            'product_ids': productIdsForDb,
            'subtotal_eur': totals.subtotal,
            'discount_pct': totals.discountPct,
            'discount_eur': totals.discountEur,
            'total_eur': itemsTotal,
            'status': 'pending',
          })
          .select()
          .single();
      bundleId = bundleRow['id']?.toString() ?? '';
    } catch (e, st) {
      _logBundleProposal(
        'payBundleNow INSERT FAIL',
        error: e,
        stack: st,
      );
      final msg = e.toString();
      if (msg.contains('bundle_status_pending_only')) {
        throw Exception(
          'Não foi possível iniciar a compra do conjunto (estado inválido). '
          'Atualiza a página e tenta «Comprar agora» de novo.',
        );
      }
      rethrow;
    }
  }
  if (bundleId.isEmpty) {
    throw Exception('Não foi possível criar o conjunto.');
  }

  final prizeOid = prizeOrderId?.trim() ?? '';
  if (prizeOid.isNotEmpty) {
    await linkPrizeOrderToBundle(bundleId: bundleId, prizeOrderId: prizeOid);
  }

  // Evitar encomendas duplicadas se reutilizamos um bundle de um checkout abortado.
  final priorOrders = await OrdersTable().queryRows(
    queryFn: (q) => q.eqOrNull('bundle_id', bundleId),
    limit: 20,
  );
  for (final o in priorOrders) {
    final st = normalizeOrderStatusKey(o.status);
    if (st == 'pago' || st == 'enviado' || st == 'concluido') {
      throw Exception(
        'Este conjunto já tem uma encomenda paga. Abre Mensagens ou Encomendas.',
      );
    }
    if (orderIsCancelled(o.status)) continue;
    final oid = o.id?.trim() ?? '';
    if (oid.isEmpty) continue;
    if (st == 'reservado' || st == 'aguarda_confirmacao') {
      await applyOrderCancelAndRelist(
        orderId: oid,
        sellerUserId: sellerId,
      );
      await batataSyncLiveCatalogForOrder(oid);
    } else if (st == 'reserva_pendente') {
      await OrdersTable().update(
        data: {'status': 'cancelado'},
        matchingRows: (rows) => rows.eqOrNull('id', oid),
      );
    }
  }

  final shippingMethod =
      shippingMethodOverride ?? 'Envio Transportadora (€3.50)';
  final weightAggForSeal = fleaberAggregateShipmentWeight([
    for (final p in fresh)
      FleaberShipmentWeightInput.fromProduct(
        p,
        quantity: quantities[p.id] ?? 1,
      ),
  ]);
  final sealFields = fleaberOrderShippingSealFields(
    handDelivery: shippingMethod.toLowerCase().contains('mão') ||
        shippingMethod.toLowerCase().contains('mao') ||
        shippingMethod.toLowerCase().contains('hand'),
    weightKg: weightAggForSeal.totalKg,
    band: weightAggForSeal.band,
    pickup: false,
    shippingEurCharged: shipping,
  );
  final bagLines = <Map<String, dynamic>>[];
  for (var i = 0; i < fresh.length; i++) {
    final product = fresh[i];
    final pid = product.id ?? '';
    final lineQty = bundleQuantityForProduct(quantities, product);
    final order = await OrdersTable().insert({
      'product_id': pid,
      'buyer_id': currentUserUid,
      'seller_id': sellerId,
      'price_total': lineTotals[i],
      'shipping_method': shippingMethod,
      'payment_method': 'Pagamento na App',
      'status': 'reserva_pendente',
      'is_reservation': false,
      'quantity': lineQty,
      'bundle_id': bundleId,
      ...sealFields,
    });
    final orderId = order.id?.trim() ?? '';
    if (orderId.isEmpty) {
      throw Exception('Não foi possível criar a encomenda do conjunto.');
    }
    bagLines.add({
      'order_id': orderId,
      'product_id': pid,
      'seller_id': sellerId,
      'quantity': lineQty,
      'line_total_cents': _euroCents(lineTotals[i]),
      'item_label': (product.title ?? 'Artigo Fleaber').trim(),
    });
  }

  // BUG-QA-021: rasto do stock antes de abrir o checkout do conjunto.
  for (final product in fresh) {
    final lineQty = bundleQuantityForProduct(quantities, product);
    print(
      'BATATA_STOCK payBundleNow product=${product.id} '
      'title="${product.title}" qty_atual=${product.quantity} '
      'unidades_a_vender=$lineQty (esgota só quando qty=0)',
    );
  }

  // Encomendas criadas → marcar conjunto purchased. Se o UPDATE falhar
  // (rede/RLS), o checkout continua: o bundle fica `pending` até o pagamento
  // e NÃO bloqueia com `bundle_status_pending_only` (só no INSERT).
  try {
    await SupaFlow.client.from('product_bundles').update({
      'status': 'purchased',
    }).eq('id', bundleId);
  } catch (e, st) {
    _logBundleProposal(
      'payBundleNow mark_purchased WARN bundle_id=$bundleId',
      error: e,
      stack: st,
    );
  }

  final grandTotal = itemsTotal + protection + shipping;
  final first = bagLines.first;
  final result = await fleaberInvokeCreatePaymentIntent(
    body: {
      'amount': _euroCents(grandTotal),
      'currency': 'eur',
      'product_id': first['product_id'],
      'buyer_id': currentUserUid,
      'seller_id': sellerId,
      'order_id': first['order_id'],
      'quantity': 1,
      // Envio e proteção já estão incluídos em cada linha (line_total_cents).
      'item_price': _euroCents(grandTotal),
      'shipping': 0,
      'protection_fee': 0,
      'shipping_method': shippingMethod,
      'bag_checkout': true,
      'bag_lines': bagLines,
    },
    logContext: {'source': 'pay_bundle_now'},
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
      'source': 'pay_bundle_now',
    },
  );
  if (!opened) {
    await FleaberStripeCheckoutContext.clear();
    throw Exception('Não foi possível abrir o checkout Stripe.');
  }

  requestMarketplaceFeedRefresh();
  requestOrdersListRefresh();
  return bundleId;
}

Future<bool> _anotherBuyerBlocksProduct({
  required String productId,
  required String buyerId,
}) async {
  final productRows = await ProductsTable().querySingleRow(
    queryFn: (q) => q.eqOrNull('id', productId),
  );
  final product = productRows.isEmpty ? null : productRows.first;
  final stockLeft = product?.quantity ?? 0;
  final listingSold = product?.isSold == true || stockLeft <= 0;

  final orders = await OrdersTable().queryRows(
    queryFn: (q) => q.eqOrNull('product_id', productId),
    limit: 80,
  );
  for (final o in orders) {
    if (orderIsCancelled(o.status)) continue;
    if (o.buyerId == buyerId) continue;
    if (!orderStatusBlocksOtherBuyers(o.status)) continue;
    if (!listingSold &&
        stockLeft > 0 &&
        orderStatusAlreadyConsumedStock(o.status)) {
      continue;
    }
    return true;
  }
  return false;
}

/// Vendedor aceita pedido/proposta de conjunto → encomendas `reservado` (pipeline BATATA).
Future<List<OrdersRow>> fulfillAcceptedBundle(
  String bundleId, {
  bool buyerAccepts = false,
  int minProducts = 2,
}) async {
  final bundle = await fetchProductBundle(bundleId);
  if (bundle == null) throw Exception('Conjunto não encontrado.');
  if (bundle['status']?.toString() != 'pending') {
    throw Exception('Este conjunto já foi respondido.');
  }

  final sellerId = bundle['seller_id']?.toString() ?? '';
  final buyerId = bundle['buyer_id']?.toString() ?? '';
  if (buyerAccepts) {
    if (buyerId != currentUserUid) {
      throw Exception('Apenas o comprador pode aceitar esta contraproposta.');
    }
  } else if (sellerId != currentUserUid) {
    throw Exception('Apenas o vendedor pode aceitar este conjunto.');
  }

  final rawIds = bundle['product_ids'];
  final productIds = rawIds is List
      ? rawIds.map((e) => e.toString()).where((id) => id.isNotEmpty).toList()
      : <String>[];
  if (productIds.length < minProducts) {
    throw Exception('Conjunto inválido.');
  }

  final products = await _loadBundleProducts(productIds);
  if (products.length < minProducts) {
    throw Exception('Um ou mais artigos já não estão disponíveis.');
  }
  for (final p in products) {
    if (p.isSold) {
      throw Exception('Um dos artigos já foi vendido.');
    }
    final pid = p.id ?? '';
    if (pid.isNotEmpty &&
        await _anotherBuyerBlocksProduct(productId: pid, buyerId: buyerId)) {
      throw Exception(
        'Um dos artigos está reservado ou em compra por outro utilizador.',
      );
    }
  }

  final totalEur = (bundle['total_eur'] as num?)?.toDouble() ??
      bundleSubtotal(products);
  final quantities = await _loadBundleQuantitiesForBundle(
    bundleId: bundleId,
    chatId: bundle['chat_id']?.toString(),
    products: products,
  );
  _assertBundleStockAvailable(products, quantities);
  final linePrices = allocateBundleLinePrices(
    products: products,
    totalEur: totalEur,
    quantitiesByProductId: quantities,
  );
  final expiresAt = DateTime.now().toUtc().add(const Duration(days: 5));
  final orders = <OrdersRow>[];
  final createdOrderIds = <String>[];

  try {
  for (var i = 0; i < products.length; i++) {
    final product = products[i];
    final pid = product.id?.toString().trim() ?? '';
    if (pid.isEmpty) continue;
    final lineQty = bundleQuantityForProduct(quantities, product);

    final existing = await OrdersTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('product_id', pid)
          .eqOrNull('buyer_id', buyerId)
          .inFilter('status', ['reserva_pendente', 'reservado']),
      limit: 3,
    );
    String? oid;
    if (existing.isNotEmpty && (existing.first.id ?? '').trim().isNotEmpty) {
      oid = existing.first.id!.trim();
      await OrdersTable().update(
        data: {
          'price_total': linePrices[i],
          'status': 'reservado',
          'reservation_expires_at': expiresAt.toIso8601String(),
          'is_reservation': true,
          'payment_method': 'Compra em conjunto aceite',
          'bundle_id': bundleId,
          'quantity': lineQty,
        },
        matchingRows: (rows) => rows.eqOrNull('id', oid),
      );
    } else {
      final inserted = await SupaFlow.client
          .from('orders')
          .insert({
            'product_id': pid,
            'buyer_id': buyerId,
            'seller_id': sellerId,
            'price_total': linePrices[i],
            'status': 'reservado',
            'reservation_expires_at': expiresAt.toIso8601String(),
            'is_reservation': true,
            'payment_method': 'Compra em conjunto aceite',
            'bundle_id': bundleId,
            'quantity': lineQty,
          })
          .select('id')
          .limit(1)
          .maybeSingle();
      oid = inserted?['id']?.toString().trim();
      if (oid == null || oid.isEmpty) {
        throw Exception('Não foi possível criar a encomenda do conjunto.');
      }
    }
    final refreshed = await OrdersTable().queryRows(
      queryFn: (q) => q.eqOrNull('id', oid),
      limit: 1,
    );
    if (refreshed.isEmpty) {
      throw Exception('Encomenda do conjunto não encontrada após criar.');
    }
    orders.add(refreshed.first);
    createdOrderIds.add(oid);
    await batataSyncLiveCatalogForOrder(oid);
  }

  await SupaFlow.client.from('product_bundles').update({
    'status': 'accepted',
    'responded_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', bundleId);

  final chatId = bundle['chat_id']?.toString();
  if (chatId != null && chatId.isNotEmpty) {
    await touchChatLastMessage(
      chatId: chatId,
      preview: 'Compra em conjunto aceite',
    );
  }

  requestMarketplaceFeedRefresh();
  requestOrdersListRefresh();
  pingBatataReservationForNotificationBell();
  return orders;
  } catch (e) {
    for (final oid in createdOrderIds) {
      try {
        await applyOrderCancelAndRelist(
          orderId: oid,
          sellerUserId: sellerId,
        );
        await batataSyncLiveCatalogForOrder(oid);
      } catch (_) {}
    }
    try {
      await SupaFlow.client.from('product_bundles').update({
        'status': 'cancelled',
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', bundleId);
    } catch (_) {}
    requestMarketplaceFeedRefresh();
    rethrow;
  }
}

/// Cancela propostas/conjuntos pendentes (ou aceites pré-pagamento) do comprador
/// que partilham artigos com [productIds] — para poder comprar ao preço anunciado
/// sem esperar resposta do vendedor.
///
/// [excludeBundleId]: não cancelar este id (ex. proposta reutilizada no E85.4).
Future<void> supersedeBuyerPendingBundlesForProducts({
  required String sellerId,
  required List<String> productIds,
  String? excludeBundleId,
}) async {
  if (currentUserUid.isEmpty || sellerId.isEmpty || productIds.isEmpty) return;
  final wanted = productIds.where((id) => id.isNotEmpty).toSet();
  if (wanted.isEmpty) return;
  final exclude = (excludeBundleId ?? '').trim();
  try {
    final rows = await SupaFlow.client
        .from('product_bundles')
        .select('id, status, product_ids')
        .eq('buyer_id', currentUserUid)
        .eq('seller_id', sellerId)
        .inFilter('status', ['pending', 'accepted']);
    for (final row in rows) {
      final bid = row['id']?.toString() ?? '';
      if (bid.isEmpty) continue;
      if (exclude.isNotEmpty && bid == exclude) continue;
      final rawIds = row['product_ids'];
      final ids = <String>{};
      if (rawIds is List) {
        for (final x in rawIds) {
          final s = x?.toString().trim() ?? '';
          if (s.isNotEmpty) ids.add(s);
        }
      }
      if (ids.isEmpty || ids.intersection(wanted).isEmpty) continue;
      final status = row['status']?.toString() ?? '';
      if (status == 'pending') {
        await SupaFlow.client.from('product_bundles').update({
          'status': 'cancelled',
          'responded_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', bid);
        continue;
      }
      if (status != 'accepted') continue;
      final orders = await OrdersTable().queryRows(
        queryFn: (q) => q.eqOrNull('bundle_id', bid),
        limit: 20,
      );
      final anyPostPaid = orders.any((o) {
        final s = normalizeOrderStatusKey(o.status);
        return s == 'pago' || s == 'enviado' || s == 'concluido';
      });
      if (anyPostPaid) continue;
      if (orders.isNotEmpty) {
        await releaseBundleReservationOrdersStock(
          bundleId: bid,
          sellerUserId: sellerId,
        );
      }
      await SupaFlow.client.from('product_bundles').update({
        'status': 'cancelled',
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', bid);
    }
  } catch (e, st) {
    _logBundleProposal('supersede buyer products WARN', error: e, stack: st);
  }
}

/// Antes de nova proposta: cancela pendentes e aceites pré-pagamento no mesmo chat.
Future<void> supersedeStaleOperationalBundlesForNewProposal(
  String chatId,
) async {
  if (chatId.isEmpty || currentUserUid.isEmpty) return;
  var relisted = false;
  try {
    final rows = await SupaFlow.client
        .from('product_bundles')
        .select('id, status')
        .eq('chat_id', chatId)
        .eq('buyer_id', currentUserUid)
        .inFilter('status', ['pending', 'accepted']);
    for (final row in rows) {
      final bid = row['id']?.toString() ?? '';
      if (bid.isEmpty) continue;
      final status = row['status']?.toString() ?? '';
      if (status == 'pending') {
        await SupaFlow.client.from('product_bundles').update({
          'status': 'cancelled',
          'responded_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', bid);
        continue;
      }
      if (status != 'accepted') continue;
      final orders = await OrdersTable().queryRows(
        queryFn: (q) => q.eqOrNull('bundle_id', bid),
        limit: 20,
      );
      final anyPostPaid = orders.any((o) {
        final s = normalizeOrderStatusKey(o.status);
        return s == 'pago' || s == 'enviado' || s == 'concluido';
      });
      if (anyPostPaid) continue;
      final sellerId = orders.first.sellerId?.trim() ?? '';
      if (sellerId.isNotEmpty) {
        await releaseBundleReservationOrdersStock(
          bundleId: bid,
          sellerUserId: sellerId,
        );
        relisted = true;
      }
      await SupaFlow.client.from('product_bundles').update({
        'status': 'cancelled',
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', bid);
    }
    if (relisted) requestMarketplaceFeedRefresh();
  } catch (e, st) {
    _logBundleProposal('supersede stale WARN', error: e, stack: st);
  }
}

/// Vendedor cancela reserva de conjunto **já aceite** (todas as linhas + bundle).
Future<void> cancelSellerAcceptedBundleReservation({
  required String bundleId,
  required String chatId,
  required String buyerId,
}) async {
  if (currentUserUid.isEmpty) {
    throw Exception('Inicia sessão.');
  }
  final bundle = await fetchProductBundle(bundleId);
  if (bundle == null) throw Exception('Conjunto não encontrado.');
  if (bundle['status']?.toString() != 'accepted') {
    throw Exception('Este conjunto já não está activo.');
  }
  final sellerId = bundle['seller_id']?.toString() ?? '';
  if (sellerId != currentUserUid) {
    throw Exception('Sem permissão.');
  }

  final orders = await OrdersTable().queryRows(
    queryFn: (q) => q.eqOrNull('bundle_id', bundleId),
    limit: 20,
  );
  if (orders.length < 2) {
    throw Exception('Encomendas do conjunto incompletas.');
  }

  await releaseBundleReservationOrdersStock(
    bundleId: bundleId,
    sellerUserId: currentUserUid,
  );

  await SupaFlow.client.from('product_bundles').update({
    'status': 'cancelled',
    'responded_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', bundleId);

  if (chatId.isNotEmpty && buyerId.isNotEmpty) {
    await ChatMessagesTable().insert({
      'sender_id': currentUserUid,
      'receiver_id': buyerId,
      'is_read': false,
      'text': fleaberChatJsonEncode({
        'kind': 'bundle_reservation_cancelled_by_seller',
        'bundle_id': bundleId,
        'v': 1,
      }),
      'chat_id': chatId,
      'is_reservation': true,
    });
    await touchChatLastMessage(
      chatId: chatId,
      preview: 'Reserva do conjunto cancelada',
    );
  }

  requestMarketplaceFeedRefresh();
  requestOrdersListRefresh();
}

Future<void> rejectBundleProposal({required String bundleId}) async {
  final bundle = await fetchProductBundle(bundleId);
  if (bundle == null) throw Exception('Conjunto não encontrado.');
  if (bundle['status']?.toString() != 'pending') {
    throw Exception('Este conjunto já foi respondido.');
  }

  final sellerId = bundle['seller_id']?.toString() ?? '';
  final buyerId = bundle['buyer_id']?.toString() ?? '';
  final actorIsSeller = sellerId == currentUserUid;
  final actorIsBuyer = buyerId == currentUserUid;
  if (!actorIsSeller && !actorIsBuyer) {
    throw Exception('Sem permissão.');
  }
  if (actorIsBuyer && !actorIsSeller) {
    throw Exception('Apenas o vendedor pode recusar este pedido.');
  }

  await SupaFlow.client.from('product_bundles').update({
    'status': 'cancelled',
    'responded_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', bundleId);

  final chatId = bundle['chat_id']?.toString();
  if (chatId != null && chatId.isNotEmpty) {
    await touchChatLastMessage(
      chatId: chatId,
      preview: 'Pedido de conjunto recusado',
    );
  }
}

/// Vendedor envia contraproposta (nova mensagem + novo bundle_id).
Future<void> sellerCounterBundleProposal({
  required String bundleId,
  required double counterTotalEur,
}) async {
  if (currentUserUid.isEmpty) {
    throw Exception('Inicia sessão.');
  }
  final bundle = await fetchProductBundle(bundleId);
  if (bundle == null) throw Exception('Conjunto não encontrado.');
  if (bundle['status']?.toString() != 'pending') {
    throw Exception('Este conjunto já foi respondido.');
  }
  final sellerId = bundle['seller_id']?.toString() ?? '';
  final buyerId = bundle['buyer_id']?.toString() ?? '';
  final chatId = bundle['chat_id']?.toString() ?? '';
  if (sellerId != currentUserUid) {
    throw Exception('Apenas o vendedor pode contrapropor.');
  }
  if (buyerId.isEmpty) throw Exception('Comprador inválido.');

  final rawIds = bundle['product_ids'];
  final productIds = rawIds is List
      ? rawIds.map((e) => e.toString()).where((id) => id.isNotEmpty).toList()
      : <String>[];
  final products = await _loadBundleProducts(productIds);
  if (products.length < 2) {
    throw Exception('Conjunto inválido.');
  }
  final quantities = await _loadBundleQuantitiesForBundle(
    bundleId: bundleId,
    chatId: chatId,
    products: products,
  );
  final subtotal = bundleSubtotal(
    products,
    quantitiesByProductId: quantities,
  );
  final total = counterTotalEur <= 0 ? subtotal : counterTotalEur;
  final discountEur = (subtotal - total).clamp(0.0, double.infinity).toDouble();
  final discountPct = subtotal > 0 ? (discountEur / subtotal) * 100 : 0.0;

  try {
    await _persistBundleProposal(
      sellerId: sellerId,
      products: products,
      subtotal: subtotal,
      discountPct: discountPct,
      discountEur: discountEur,
      total: total,
      requestMode: 'seller_counter',
      productQuantities: quantities,
      buyerIdOverride: buyerId,
      senderIdOverride: sellerId,
      receiverIdOverride: buyerId,
      chatIdOverride: chatId,
      skipSupersede: true,
    );
  } catch (e, st) {
    if (e is! BundleProposalPermissionException) {
      _logBundleProposalRls(
        phase: 'seller_counter_persist',
        error: e,
        stack: st,
        bundleId: bundleId,
        sellerId: sellerId,
        buyerId: buyerId,
        chatId: chatId,
      );
    }
    rethrow;
  }

  // Só cancela a proposta anterior depois do novo bundle + mensagem existirem.
  try {
    await SupaFlow.client.from('product_bundles').update({
      'status': 'cancelled',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', bundleId);
  } catch (e, st) {
    _logBundleProposal(
      'seller_counter cancel_previous FAIL bundle_id=$bundleId',
      error: e,
      stack: st,
    );
    rethrow;
  }
}

Future<void> acceptBundleProposal({required String bundleId}) async {
  final bundle = await fetchProductBundle(bundleId);
  if (bundle != null &&
      ((bundle['rule_version']?.toString() ?? '') == 'quote_before_pay_v1' ||
          (bundle['seller_confirm_expires_at']?.toString() ?? '')
              .trim()
              .isNotEmpty)) {
    throw Exception(
      'bundle_use_confirm_quote_rpc: usa a confirmação de portes (cotação) '
      'em vez de aceitar com reserva.',
    );
  }
  await fulfillAcceptedBundle(bundleId);
}

Future<void> buyerAcceptBundleProposal({required String bundleId}) async {
  final bundle = await fetchProductBundle(bundleId);
  if (bundle != null &&
      ((bundle['rule_version']?.toString() ?? '') == 'quote_before_pay_v1' ||
          (bundle['seller_confirm_expires_at']?.toString() ?? '')
              .trim()
              .isNotEmpty ||
          bundle['status']?.toString() == 'awaiting_payment')) {
    throw Exception(
      'Neste fluxo a compradora paga a cotação confirmada — não «aceita» com reserva.',
    );
  }
  await fulfillAcceptedBundle(bundleId, buyerAccepts: true);
}

/// Checkout Stripe para conjunto **já aceite** (encomendas `reservado` existentes).
Future<void> payAcceptedBundleProposalCheckout({
  required String bundleId,
  FleaberDpdWeightBand? shippingWeightBand,
  double? shippingEur,
  bool pickup = false,
}) async {
  if (currentUserUid.isEmpty) {
    throw Exception('Inicia sessão para concluir a compra.');
  }
  final bundle = await fetchProductBundle(bundleId);
  if (bundle == null) throw Exception('Conjunto não encontrado.');
  if (bundle['status']?.toString() != 'accepted') {
    throw Exception('Este conjunto ainda não foi aceite pelo vendedor.');
  }
  final sellerId = bundle['seller_id']?.toString() ?? '';
  if (sellerId.isEmpty) throw Exception('Conjunto inválido.');
  if (bundle['buyer_id']?.toString() != currentUserUid) {
    throw Exception('Apenas o comprador pode pagar este conjunto.');
  }

  final orders = await OrdersTable().queryRows(
    queryFn: (q) => q.eqOrNull('bundle_id', bundleId),
    limit: 20,
  );
  // Só linhas a pagar (exclui prémio da rifa já ligado ao bundle).
  final payable = orders.where((o) {
    if (orderIsCancelled(o.status)) return false;
    final s = normalizeOrderStatusKey(o.status);
    return s == 'reservado' || s == 'aguarda_confirmacao';
  }).toList();
  if (payable.isEmpty) {
    throw Exception('Encomendas do conjunto incompletas.');
  }

  final productIds = payable
      .map((o) => o.productId)
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toList();
  final products = await _loadBundleProducts(productIds);
  if (products.isEmpty) {
    throw Exception('Um ou mais artigos já não estão disponíveis.');
  }

  var grandTotalCents = 0;
  final bagLines = <Map<String, dynamic>>[];
  for (final o in payable) {
    final oid = o.id?.trim() ?? '';
    final pid = o.productId?.trim() ?? '';
    if (oid.isEmpty || pid.isEmpty) continue;
    final lineTotal = o.priceTotal ?? 0;
    grandTotalCents += _euroCents(lineTotal);
    ProductsRow? product;
    for (final p in products) {
      if (p.id == pid) {
        product = p;
        break;
      }
    }
    bagLines.add({
      'order_id': oid,
      'product_id': pid,
      'seller_id': sellerId,
      'quantity': o.quantity,
      'line_total_cents': _euroCents(lineTotal),
      'item_label': (product?.title ?? 'Artigo Fleaber').trim(),
    });
  }
  if (bagLines.isEmpty || grandTotalCents <= 0) {
    throw Exception('Não foi possível preparar o checkout do conjunto.');
  }

  final first = bagLines.first;
  final shipMethod =
      payable.first.shippingMethod ?? 'Envio Transportadora (€3.50)';
  final result = await fleaberInvokeCreatePaymentIntent(
    body: {
      'amount': grandTotalCents,
      'currency': 'eur',
      'product_id': first['product_id'],
      'buyer_id': currentUserUid,
      'seller_id': sellerId,
      'order_id': first['order_id'],
      'quantity': 1,
      'item_price': grandTotalCents,
      'shipping': shippingEur == null ? 0 : _euroCents(shippingEur),
      'protection_fee': 0,
      'shipping_method': shipMethod,
      if (shippingWeightBand != null)
        'shipping_weight_band': shippingWeightBand.code,
      'shipping_modality': pickup ? 'shop_to_shop' : 'shop_to_home',
      'bag_checkout': true,
      'bag_lines': bagLines,
    },
    logContext: {'source': 'pay_accepted_bundle'},
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
      'source': 'pay_accepted_bundle',
    },
  );
  if (!opened) {
    await FleaberStripeCheckoutContext.clear();
    throw Exception('Não foi possível abrir o checkout Stripe.');
  }

  requestMarketplaceFeedRefresh();
  requestOrdersListRefresh();
}

/// MB WAY / transferência directa para conjunto aceite (encomendas `reservado`).
Future<void> payAcceptedBundleProposalDirect({
  required String bundleId,
  required String paymentMethod,
  required String shippingMethod,
}) async {
  if (currentUserUid.isEmpty) {
    throw Exception('Inicia sessão para concluir a compra.');
  }
  final bundle = await fetchProductBundle(bundleId);
  if (bundle == null) throw Exception('Conjunto não encontrado.');
  if (bundle['status']?.toString() != 'accepted') {
    throw Exception('Este conjunto ainda não foi aceite pelo vendedor.');
  }
  if (bundle['buyer_id']?.toString() != currentUserUid) {
    throw Exception('Apenas o comprador pode pagar este conjunto.');
  }

  final orders = await OrdersTable().queryRows(
    queryFn: (q) => q.eqOrNull('bundle_id', bundleId),
    limit: 20,
  );
  final payable = orders.where((o) {
    if (orderIsCancelled(o.status)) return false;
    final s = normalizeOrderStatusKey(o.status);
    // Nunca reescrever o prémio da rifa.
    if (s == 'premio_rifa') return false;
    if (s == 'pago' &&
        LiveRafflePrizeCopy.isPrizePaymentMethod(o.paymentMethod)) {
      return false;
    }
    return s == 'reservado' || s == 'aguarda_confirmacao';
  }).toList();
  if (payable.isEmpty) {
    throw Exception('Encomendas do conjunto incompletas.');
  }

  for (final o in payable) {
    final oid = o.id;
    if (oid == null || oid.isEmpty) continue;
    await OrdersTable().update(
      data: {
        'payment_method': paymentMethod,
        'shipping_method': shippingMethod,
        'status': 'reservado',
        'is_reservation': true,
      },
      matchingRows: (rows) => rows.eqOrNull('id', oid),
    );
  }

  final chatId = bundle['chat_id']?.toString();
  final sellerId = bundle['seller_id']?.toString() ?? '';
  final buyerId = bundle['buyer_id']?.toString() ?? currentUserUid;
  if (chatId != null &&
      chatId.isNotEmpty &&
      sellerId.isNotEmpty &&
      buyerId.isNotEmpty) {
    await insertBundleDirectPaymentDetailsMessage(
      bundleId: bundleId,
      chatId: chatId,
      sellerId: sellerId,
      buyerId: buyerId,
      shippingMethod: shippingMethod,
    );
    await touchChatLastMessage(
      chatId: chatId,
      preview: 'Dados de pagamento do conjunto',
    );
  }

  requestMarketplaceFeedRefresh();
  requestOrdersListRefresh();
  pingBatataReservationForNotificationBell();
}

String formatBundlePurchaseRequestText({
  required String buyerName,
  required List<ProductsRow> products,
}) {
  final buf = StringBuffer()
    ..writeln('$buyerName pretende comprar estes artigos em conjunto.')
    ..writeln();
  for (final p in products) {
    final title = (p.title ?? 'Artigo').trim();
    buf.writeln('• $title');
  }
  return buf.toString().trimRight();
}
