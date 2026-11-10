import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';

DateTime _chatRecency(ChatsRow c) =>
    c.lastMessageTime ?? c.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

/// Só texto de preview conta — `last_message_time` sozinho aparece em chats
/// órfãos sem mensagens (CHAT-MULTI).
bool _chatHasPreview(ChatsRow c) => (c.lastMessage ?? '').trim().isNotEmpty;

void _sortByRecency(List<ChatsRow> pool, {required bool newestFirst}) {
  if (pool.length < 2) return;
  pool.sort((a, b) => newestFirst
      ? _chatRecency(b).compareTo(_chatRecency(a))
      : _chatRecency(a).compareTo(_chatRecency(b)));
}

/// Abre ou reutiliza um chat 1:1, com [productId] opcional (estilo Vinted).
/// `productId` null ou vazio → conversa geral (só user_a/user_b, sem artigo).
///
/// Com o mesmo artigo há vários chats (compras / rifas). Por defeito escolhe
/// o **mais recente com preview** — nunca um clone vazio se existir conversa.
///
/// [forceNew]: compra/rifa nova → thread nova (mensagem nova, não misturar
/// com compras anteriores do mesmo artigo).
Future<ChatsRow> ensureSellerChat({
  required String otherUserId,
  String? productId,
  bool preferNewest = true,
  bool forceNew = false,
}) async {
  final bool scoped = productId != null && productId.isNotEmpty;

  if (!forceNew) {
    final rows = await ChatsTable().queryRows(
      queryFn: (q) => q.or(
        'and(user_a.eq.$currentUserUid,user_b.eq.$otherUserId),and(user_a.eq.$otherUserId,user_b.eq.$currentUserUid)',
      ),
      limit: 50,
    );

    final matches = scoped
        ? rows.where((c) => c.productId == productId).toList()
        : rows.where((c) => c.productId == null).toList();

    if (matches.isNotEmpty) {
      final withPreview = matches.where(_chatHasPreview).toList();
      final pool =
          withPreview.isNotEmpty ? withPreview : matches.toList();
      _sortByRecency(pool, newestFirst: preferNewest);
      return pool.first;
    }
  }

  final data = <String, dynamic>{
    'user_a': currentUserUid,
    'user_b': otherUserId,
  };
  if (scoped) {
    data['product_id'] = productId;
  }
  return ChatsTable().insert(data);
}

/// Encontra o chat que contém a encomenda (ex. `raffle_prize_awarded` / pago).
Future<ChatsRow?> findChatForOrderId(String orderId) async {
  final oid = orderId.trim();
  if (oid.isEmpty) return null;

  final messages = await ChatMessagesTable().queryRows(
    queryFn: (q) => q.ilike('text', '%$oid%').order('created_at', ascending: false),
    limit: 30,
  );
  // Preferir card «seguro_fleaber_paid» desta encomenda.
  ChatMessagesRow? paidMsg;
  ChatMessagesRow? anyMsg;
  for (final m in messages) {
    final text = m.text;
    if (!text.contains(oid)) continue;
    anyMsg ??= m;
    if (text.contains('"kind":"seguro_fleaber_paid"') &&
        text.contains('"order_id":"$oid"')) {
      paidMsg = m;
      break;
    }
  }
  final chosen = paidMsg ?? anyMsg;
  if (chosen == null) return null;
  final chatId = chosen.chatId.trim();
  if (chatId.isEmpty) return null;
  final chats = await ChatsTable().queryRows(
    queryFn: (q) => q.eqOrNull('id', chatId),
    limit: 1,
  );
  if (chats.isNotEmpty) return chats.first;
  return null;
}

/// Resolve o chat certo para uma encomenda (abrir a partir de Encomendas, etc.).
Future<ChatsRow> resolveChatForOrder({
  required String otherUserId,
  required String orderId,
  String? productId,
}) async {
  final byOrder = await findChatForOrderId(orderId);
  if (byOrder != null) return byOrder;
  return ensureSellerChat(
    otherUserId: otherUserId,
    productId: productId,
    preferNewest: true,
  );
}
