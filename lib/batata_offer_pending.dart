import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';

/// Chats onde o utilizador actual tem uma proposta pendente à sua espera.
Future<Set<String>> fetchChatIdsWithPendingOfferForMe() async {
  if (currentUserUid.isEmpty) return const {};

  try {
    final uid = currentUserUid;
    final rows = await ProductOffersTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('status', 'pending')
          .or('seller_id.eq.$uid,buyer_id.eq.$uid'),
      limit: 200,
    );
    return rows
        .where(
          (r) =>
              (r.sellerId == uid && r.offeredBy == 'buyer') ||
              (r.buyerId == uid && r.offeredBy == 'seller'),
        )
        .map((r) => r.chatId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
  } catch (_) {
    return const {};
  }
}

bool chatHasPendingOfferForMe(Set<String> pendingChatIds, String? chatId) {
  if (chatId == null || chatId.isEmpty) return false;
  return pendingChatIds.contains(chatId);
}
