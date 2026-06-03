import 'dart:convert';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/batata_bundle_discounts.dart';
import '/chat_session_util.dart';
import '/utils/fee_calculator.dart';

Map<String, dynamic> bundleProposalChatPayload({
  required String bundleId,
  required List<String> productIds,
  required String sellerId,
  required String buyerId,
  required double subtotalEur,
  required double discountPct,
  required double discountEur,
  required double totalEur,
}) =>
    {
      'kind': 'bundle_proposal',
      'bundle_id': bundleId,
      'product_ids': productIds,
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'subtotal_eur': subtotalEur,
      'discount_pct': discountPct,
      'discount_eur': discountEur,
      'total_eur': totalEur,
      'v': 1,
    };

Future<Map<String, dynamic>> createBundleProposal({
  required String sellerId,
  required List<ProductsRow> products,
  required BundleDiscountTiers tiers,
}) async {
  if (currentUserUid.isEmpty) {
    throw Exception('Inicia sessão para criar um conjunto.');
  }
  if (products.length < 2) {
    throw Exception('Escolhe pelo menos 2 artigos.');
  }
  final totals = calculateBundleTotals(products: products, tiers: tiers);
  if (totals.discountPct <= 0) {
    throw Exception('O vendedor não tem descontos de conjunto activos.');
  }

  final productIds = products
      .map((p) => p.id)
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toList();
  final anchorProductId = productIds.first;

  final chat = await ensureSellerChat(
    otherUserId: sellerId,
    productId: anchorProductId,
  );
  final chatId = chat.id;
  if (chatId == null || chatId.isEmpty) {
    throw Exception('Não foi possível abrir a conversa.');
  }

  final bundleRow = await SupaFlow.client
      .from('product_bundles')
      .insert({
        'seller_id': sellerId,
        'buyer_id': currentUserUid,
        'chat_id': chatId,
        'product_ids': productIds,
        'subtotal_eur': totals.subtotal,
        'discount_pct': totals.discountPct,
        'discount_eur': totals.discountEur,
        'total_eur': totals.total,
        'status': 'pending',
      })
      .select()
      .single();

  final bundleId = bundleRow['id']?.toString() ?? '';
  final preview =
      'Conjunto: ${productIds.length} artigos · ${formatEuros(totals.total)}';

  await ChatMessagesTable().insert({
    'sender_id': currentUserUid,
    'receiver_id': sellerId,
    'chat_id': chatId,
    'text': jsonEncode(
      bundleProposalChatPayload(
        bundleId: bundleId,
        productIds: productIds,
        sellerId: sellerId,
        buyerId: currentUserUid,
        subtotalEur: totals.subtotal,
        discountPct: totals.discountPct,
        discountEur: totals.discountEur,
        totalEur: totals.total,
      ),
    ),
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

  try {
    await SupaFlow.client.from('user_notifications').insert({
      'user_id': sellerId,
      'kind': 'bundle_proposal',
      'title': 'Nova proposta de conjunto',
      'body':
          '${productIds.length} artigos · ${formatEuros(totals.total)} (${totals.discountPct.toStringAsFixed(0)}% off)',
      'chat_id': chatId,
      'actor_id': currentUserUid,
    });
  } catch (_) {}

  return {
    'bundle_id': bundleId,
    'chat_id': chatId,
    'seller_id': sellerId,
    ...totals.toJson(),
  };
}

extension on ({double subtotal, double discountPct, double discountEur, double total}) {
  Map<String, double> toJson() => {
        'subtotal_eur': subtotal,
        'discount_pct': discountPct,
        'discount_eur': discountEur,
        'total_eur': total,
      };
}
