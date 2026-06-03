import 'dart:convert';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/batata_reservation_actions.dart';
import '/chat_session_util.dart';
import '/marketplace_feed_refresh.dart';
import '/order_cancel_eligibility.dart';
import '/utils/fee_calculator.dart';

const Duration kOfferDefaultTtl = Duration(hours: 48);

Map<String, dynamic> priceOfferChatPayload(ProductOffersRow offer) => {
      'kind': 'price_offer',
      'offer_id': offer.id,
      'product_id': offer.productId,
      'buyer_id': offer.buyerId,
      'seller_id': offer.sellerId,
      'amount': offer.amount,
      'list_price': offer.listPrice,
      'offered_by': offer.offeredBy,
      'expires_at': offer.expiresAt?.toUtc().toIso8601String(),
      'v': 1,
    };

Map<String, dynamic> priceOfferOutcomeChatPayload({
  required ProductOffersRow offer,
  required String outcome,
}) =>
    {
      'kind': 'price_offer_outcome',
      'offer_id': offer.id,
      'product_id': offer.productId,
      'buyer_id': offer.buyerId,
      'seller_id': offer.sellerId,
      'amount': offer.amount,
      'outcome': outcome,
      'offered_by': offer.offeredBy,
      'v': 1,
    };

Future<ProductOffersRow?> fetchProductOffer(String offerId) async {
  final rows = await ProductOffersTable().queryRows(
    queryFn: (q) => q.eqOrNull('id', offerId),
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

Future<ProductOffersRow?> fetchPendingOfferForProductBuyer({
  required String productId,
  required String buyerId,
}) async {
  final rows = await ProductOffersTable().queryRows(
    queryFn: (q) => q
        .eqOrNull('product_id', productId)
        .eqOrNull('buyer_id', buyerId)
        .eqOrNull('status', 'pending')
        .order('created_at', ascending: false),
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

Future<void> _supersedePendingOffers({
  required String productId,
  required String buyerId,
}) async {
  await SupaFlow.client
      .from('product_offers')
      .update({
        'status': 'superseded',
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('product_id', productId)
      .eq('buyer_id', buyerId)
      .eq('status', 'pending');
}

/// Anula todas as propostas pendentes do artigo (ex.: após aceitar uma).
Future<void> _supersedeAllPendingOffersForProduct(String productId) async {
  if (productId.isEmpty) return;
  await SupaFlow.client
      .from('product_offers')
      .update({
        'status': 'superseded',
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('product_id', productId)
      .eq('status', 'pending');
}

Future<bool> _anotherBuyerBlocksOffers({
  required String productId,
  required String buyerId,
}) async {
  final orders = await OrdersTable().queryRows(
    queryFn: (q) => q.eqOrNull('product_id', productId),
    limit: 80,
  );
  for (final o in orders) {
    if (orderIsCancelled(o.status)) continue;
    if (o.buyerId == buyerId) continue;
    if (orderStatusBlocksOtherBuyers(o.status)) return true;
  }
  return false;
}

Future<void> _insertOfferChatMessage({
  required ProductOffersRow offer,
  required String senderId,
  required String receiverId,
}) async {
  final chatId = offer.chatId;
  if (chatId == null || chatId.isEmpty) return;

  final amount = offer.amount ?? 0;
  final preview = offer.offeredBy == 'seller'
      ? 'Contra-proposta: ${formatEuros(amount)}'
      : 'Proposta: ${formatEuros(amount)}';

  await ChatMessagesTable().insert({
    'sender_id': senderId,
    'receiver_id': receiverId,
    'chat_id': chatId,
    'text': fleaberChatJsonEncode(priceOfferChatPayload(offer)),
    'is_read': false,
    'is_reservation': false,
  });

  await ChatsTable().update(
    data: {
      'last_message': preview,
      'last_message_time': DateTime.now().toUtc().toIso8601String(),
    },
    matchingRows: (rows) => rows.eqOrNull('id', chatId),
  );
}

Future<void> _insertOutcomeChatMessage({
  required ProductOffersRow offer,
  required String outcome,
  required String senderId,
  required String receiverId,
}) async {
  final chatId = offer.chatId;
  if (chatId == null || chatId.isEmpty) return;

  final label = outcome == 'accepted'
      ? 'Proposta aceite (${formatEuros(offer.amount ?? 0)})'
      : 'Proposta recusada';

  await ChatMessagesTable().insert({
    'sender_id': senderId,
    'receiver_id': receiverId,
    'chat_id': chatId,
    'text': fleaberChatJsonEncode(
      priceOfferOutcomeChatPayload(offer: offer, outcome: outcome),
    ),
    'is_read': false,
    'is_reservation': false,
  });

  await ChatsTable().update(
    data: {
      'last_message': label,
      'last_message_time': DateTime.now().toUtc().toIso8601String(),
    },
    matchingRows: (rows) => rows.eqOrNull('id', chatId),
  );
}

/// Comprador envia proposta inicial ou nova proposta após recusa.
Future<ProductOffersRow> createBuyerPriceOffer({
  required ProductsRow product,
  required double amountEur,
}) async {
  final productId = product.id;
  final sellerId = product.sellerId;
  if (productId == null ||
      productId.isEmpty ||
      sellerId == null ||
      sellerId.isEmpty) {
    throw Exception('Artigo inválido.');
  }
  if (currentUserUid.isEmpty) {
    throw Exception('Inicia sessão para fazer uma proposta.');
  }
  if (sellerId == currentUserUid) {
    throw Exception('Não podes fazer proposta no teu próprio anúncio.');
  }
  if (product.isSold) {
    throw Exception('Este artigo já foi vendido.');
  }
  if (await _anotherBuyerBlocksOffers(
    productId: productId,
    buyerId: currentUserUid,
  )) {
    throw Exception(
      'Este artigo está reservado ou em processo de compra por outro utilizador.',
    );
  }

  final listPrice = product.price ?? 0;
  if (amountEur <= 0) {
    throw Exception('Introduz um valor válido.');
  }
  if (listPrice > 0 && amountEur >= listPrice) {
    throw Exception(
      'A proposta deve ser inferior ao preço de ${formatEuros(listPrice)}.',
    );
  }

  await _supersedePendingOffers(
    productId: productId,
    buyerId: currentUserUid,
  );

  final chat = await ensureSellerChat(
    otherUserId: sellerId,
    productId: productId,
  );
  final chatId = chat.id;
  if (chatId == null || chatId.isEmpty) {
    throw Exception('Não foi possível abrir a conversa.');
  }

  final expiresAt = DateTime.now().toUtc().add(kOfferDefaultTtl);
  final offer = await ProductOffersTable().insert({
    'product_id': productId,
    'chat_id': chatId,
    'buyer_id': currentUserUid,
    'seller_id': sellerId,
    'amount': amountEur,
    'list_price': listPrice > 0 ? listPrice : null,
    'offered_by': 'buyer',
    'status': 'pending',
    'expires_at': expiresAt.toIso8601String(),
  });

  await _insertOfferChatMessage(
    offer: offer,
    senderId: currentUserUid,
    receiverId: sellerId,
  );

  return offer;
}

/// Contra-proposta (vendedor ou comprador, conforme [offeredBy]).
Future<ProductOffersRow> createCounterPriceOffer({
  required ProductOffersRow previous,
  required double amountEur,
  required String offeredBy,
}) async {
  final offerId = previous.id;
  if (offerId == null || offerId.isEmpty) {
    throw Exception('Proposta inválida.');
  }
  if (previous.status != 'pending') {
    throw Exception('Esta proposta já não está activa.');
  }

  final exp = previous.expiresAt;
  if (exp != null && exp.toUtc().isBefore(DateTime.now().toUtc())) {
    await ProductOffersTable().update(
      data: {'status': 'expired', 'responded_at': DateTime.now().toUtc().toIso8601String()},
      matchingRows: (rows) => rows.eqOrNull('id', offerId),
    );
    throw Exception('Esta proposta expirou.');
  }

  if (offeredBy == 'seller' && currentUserUid != previous.sellerId) {
    throw Exception('Apenas o vendedor pode enviar esta contra-proposta.');
  }
  if (offeredBy == 'buyer' && currentUserUid != previous.buyerId) {
    throw Exception('Apenas o comprador pode enviar esta contra-proposta.');
  }

  final productId = previous.productId ?? '';
  if (offeredBy == 'buyer' && productId.isNotEmpty) {
    await _supersedePendingOffers(
      productId: productId,
      buyerId: previous.buyerId ?? '',
    );
  }

  final listPrice = previous.listPrice ?? 0;
  if (amountEur <= 0) {
    throw Exception('Introduz um valor válido.');
  }
  if (listPrice > 0 && amountEur >= listPrice) {
    throw Exception(
      'O valor deve ser inferior ao preço de ${formatEuros(listPrice)}.',
    );
  }

  await ProductOffersTable().update(
    data: {
      'status': 'superseded',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    },
    matchingRows: (rows) => rows.eqOrNull('id', offerId),
  );

  final expiresAt = DateTime.now().toUtc().add(kOfferDefaultTtl);
  final offer = await ProductOffersTable().insert({
    'product_id': previous.productId,
    'chat_id': previous.chatId,
    'buyer_id': previous.buyerId,
    'seller_id': previous.sellerId,
    'amount': amountEur,
    'list_price': previous.listPrice,
    'offered_by': offeredBy,
    'status': 'pending',
    'parent_offer_id': offerId,
    'expires_at': expiresAt.toIso8601String(),
  });

  final senderId = currentUserUid;
  final receiverId = offeredBy == 'seller'
      ? (previous.buyerId ?? '')
      : (previous.sellerId ?? '');

  await _insertOfferChatMessage(
    offer: offer,
    senderId: senderId,
    receiverId: receiverId,
  );

  return offer;
}

/// Cria/atualiza encomenda `reservado` após aceitar proposta (pagamento pendente).
Future<OrdersRow> fulfillAcceptedPriceOffer(ProductOffersRow offer) async {
  final productId = offer.productId;
  final buyerId = offer.buyerId;
  final sellerId = offer.sellerId;
  final offerId = offer.id;
  final amount = offer.amount ?? 0;

  if (productId == null ||
      productId.isEmpty ||
      buyerId == null ||
      buyerId.isEmpty ||
      sellerId == null ||
      sellerId.isEmpty ||
      offerId == null ||
      offerId.isEmpty) {
    throw Exception('Proposta incompleta.');
  }
  if (amount <= 0) {
    throw Exception('Valor da proposta inválido.');
  }

  final productRows = await ProductsTable().querySingleRow(
    queryFn: (q) => q.eqOrNull('id', productId),
  );
  if (productRows.isEmpty) {
    throw Exception('Artigo já não está disponível.');
  }
  if (productRows.first.isSold) {
    throw Exception('Este artigo já foi vendido.');
  }

  final orderRows = await OrdersTable().queryRows(
    queryFn: (q) => q.eqOrNull('product_id', productId),
    limit: 80,
  );

  for (final o in orderRows) {
    if (orderIsCancelled(o.status)) continue;
    if (o.buyerId == buyerId) continue;
    if (orderStatusBlocksOtherBuyers(o.status)) {
      throw Exception(
        'Já existe outra encomenda activa neste artigo. '
        'Não é possível aceitar esta proposta.',
      );
    }
  }

  final expiresAt = DateTime.now().toUtc().add(const Duration(days: 5));
  OrdersRow? buyerOrder;
  for (final o in orderRows) {
    if (orderIsCancelled(o.status)) continue;
    if (o.buyerId != buyerId) continue;
    final s = normalizeOrderStatusKey(o.status);
    if (s == 'reserva_pendente' || s == 'reservado') {
      buyerOrder = o;
      break;
    }
  }

  final orderPatch = <String, dynamic>{
    'price_total': amount,
    'status': 'reservado',
    'reservation_expires_at': expiresAt.toIso8601String(),
    'is_reservation': true,
    'payment_method': 'Proposta de preço aceite',
    'product_offer_id': offerId,
  };

  late final OrdersRow order;
  if (buyerOrder?.id != null && buyerOrder!.id!.isNotEmpty) {
    await OrdersTable().update(
      data: orderPatch,
      matchingRows: (rows) => rows.eqOrNull('id', buyerOrder!.id),
    );
    final refreshed = await OrdersTable().queryRows(
      queryFn: (q) => q.eqOrNull('id', buyerOrder!.id),
      limit: 1,
    );
    order = refreshed.isNotEmpty ? refreshed.first : buyerOrder;
  } else {
    order = await OrdersTable().insert({
      'product_id': productId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      ...orderPatch,
    });
  }

  await _supersedeAllPendingOffersForProduct(productId);

  final chatId = offer.chatId;
  if (chatId != null && chatId.isNotEmpty) {
    await insertSellerReservationOutcomeMessages(
      chatId: chatId,
      buyerId: buyerId,
      orderId: order.id ?? '',
      outcome: 'accepted',
      expiresAtUtc: expiresAt,
    );
    await touchChatLastMessage(
      chatId: chatId,
      preview: 'Proposta aceite — artigo reservado',
    );
  }

  requestMarketplaceFeedRefresh();
  requestOrdersListRefresh();
  pingBatataReservationForNotificationBell();

  return order;
}

Future<ProductOffersRow> acceptPriceOffer({
  required String offerId,
}) async {
  final offer = await fetchProductOffer(offerId);
  if (offer == null) throw Exception('Proposta não encontrada.');
  if (offer.status != 'pending') {
    throw Exception('Esta proposta já foi respondida.');
  }

  final exp = offer.expiresAt;
  if (exp != null && exp.toUtc().isBefore(DateTime.now().toUtc())) {
    await ProductOffersTable().update(
      data: {
        'status': 'expired',
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      },
      matchingRows: (rows) => rows.eqOrNull('id', offerId),
    );
    throw Exception('Esta proposta expirou.');
  }

  final offeredBy = offer.offeredBy;
  if (offeredBy == 'buyer' && currentUserUid != offer.sellerId) {
    throw Exception('Apenas o vendedor pode aceitar esta proposta.');
  }
  if (offeredBy == 'seller' && currentUserUid != offer.buyerId) {
    throw Exception('Apenas o comprador pode aceitar esta proposta.');
  }

  await ProductOffersTable().update(
    data: {
      'status': 'accepted',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    },
    matchingRows: (rows) => rows.eqOrNull('id', offerId),
  );

  final updated = (await fetchProductOffer(offerId)) ?? offer;
  final senderId = currentUserUid;
  final receiverId = senderId == offer.buyerId
      ? (offer.sellerId ?? '')
      : (offer.buyerId ?? '');

  await _insertOutcomeChatMessage(
    offer: updated,
    outcome: 'accepted',
    senderId: senderId,
    receiverId: receiverId,
  );

  await fulfillAcceptedPriceOffer(updated);

  return updated;
}

Future<ProductOffersRow> rejectPriceOffer({
  required String offerId,
}) async {
  final offer = await fetchProductOffer(offerId);
  if (offer == null) throw Exception('Proposta não encontrada.');
  if (offer.status != 'pending') {
    throw Exception('Esta proposta já foi respondida.');
  }

  final offeredBy = offer.offeredBy;
  if (offeredBy == 'buyer' && currentUserUid != offer.sellerId) {
    throw Exception('Apenas o vendedor pode recusar esta proposta.');
  }
  if (offeredBy == 'seller' && currentUserUid != offer.buyerId) {
    throw Exception('Apenas o comprador pode recusar esta proposta.');
  }

  await ProductOffersTable().update(
    data: {
      'status': 'rejected',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    },
    matchingRows: (rows) => rows.eqOrNull('id', offerId),
  );

  final updated = (await fetchProductOffer(offerId)) ?? offer;
  final senderId = currentUserUid;
  final receiverId = senderId == offer.buyerId
      ? (offer.sellerId ?? '')
      : (offer.buyerId ?? '');

  await _insertOutcomeChatMessage(
    offer: updated,
    outcome: 'rejected',
    senderId: senderId,
    receiverId: receiverId,
  );

  return updated;
}

bool offerOutcomeExistsAfterMessages({
  required List<ChatMessagesRow> messages,
  required String? afterMessageId,
  required String offerId,
}) {
  var seenRequest = afterMessageId == null;
  for (final m in messages) {
    if (!seenRequest) {
      if (m.id.toString() == afterMessageId) seenRequest = true;
      continue;
    }
    final p = tryParseFleaberChatJson(m.text);
    if (p == null || p['kind'] != 'price_offer_outcome') continue;
    if (p['offer_id']?.toString() == offerId) return true;
  }
  return false;
}

Map<String, dynamic>? tryParseFleaberChatJson(String text) {
  const prefix = kFleaberChatJsonPrefix;
  if (!text.startsWith(prefix)) return null;
  try {
    final raw = text.substring(prefix.length);
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {}
  return null;
}
