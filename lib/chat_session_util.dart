import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import 'package:collection/collection.dart';

/// Abre ou reutiliza um chat 1:1, com [productId] opcional (estilo Vinted).
/// `productId` null ou vazio → conversa geral (só user_a/user_b, sem artigo).
Future<ChatsRow> ensureSellerChat({
  required String otherUserId,
  String? productId,
}) async {
  final rows = await ChatsTable().queryRows(
    queryFn: (q) => q.or(
      'and(user_a.eq.$currentUserUid,user_b.eq.$otherUserId),and(user_a.eq.$otherUserId,user_b.eq.$currentUserUid)',
    ),
    limit: 50,
  );

  final bool scoped = productId != null && productId.isNotEmpty;
  final ChatsRow? match = scoped
      ? rows.where((c) => c.productId == productId).firstOrNull
      : rows.where((c) => c.productId == null).firstOrNull;

  if (match != null) return match;

  final data = <String, dynamic>{
    'user_a': currentUserUid,
    'user_b': otherUserId,
  };
  if (scoped) {
    data['product_id'] = productId;
  }
  return ChatsTable().insert(data);
}
