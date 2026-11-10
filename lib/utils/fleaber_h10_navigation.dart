import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '/backend/supabase/supabase.dart';
import '/chat_page/chat_page_widget.dart';
import '/chat_session_util.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/lista_conversas_widget.dart';

/// Abre a conversa na interface H10 actual (inbox + painel), não um ecrã legado isolado.
///
/// - **Web (FleaHub):** sempre [ListaConversasWidget] (`#/listaConversas`) —
///   nunca `#/chatPage` isolado (E85.3).
/// - **App nativa:** [ChatPageWidget].
Future<void> openH10Conversation(
  BuildContext context, {
  required String otherUserId,
  String? orderId,
  String? productId,
  String? chatId,
  bool requestCancelOnOpen = false,
}) async {
  final other = otherUserId.trim();
  final oid = (orderId ?? '').trim();
  final pid = (productId ?? '').trim();
  final cid = (chatId ?? '').trim();
  if (other.isEmpty) {
    throw StateError('otherUserId em falta');
  }

  late final ChatsRow chat;
  if (cid.isNotEmpty) {
    final rows = await ChatsTable().queryRows(
      queryFn: (q) => q.eqOrNull('id', cid),
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('chatId inválido');
    }
    chat = rows.first;
  } else if (oid.isNotEmpty) {
    chat = await resolveChatForOrder(
      otherUserId: other,
      orderId: oid,
      productId: pid.isEmpty ? null : pid,
    );
  } else {
    chat = await ensureSellerChat(
      otherUserId: other,
      productId: pid.isEmpty ? null : pid,
      preferNewest: true,
    );
  }

  if (!context.mounted) return;

  final q = <String, String?>{
    'chatId': serializeParam(chat.id, ParamType.String),
    'otherUserId': serializeParam(other, ParamType.String),
    if (oid.isNotEmpty) 'orderId': serializeParam(oid, ParamType.String),
    if (requestCancelOnOpen)
      'requestCancelOnOpen': serializeParam(true, ParamType.bool),
  }.withoutNulls;

  // Hub web: sempre inbox H10 (evita URL legada /chatPage após Stripe).
  if (kIsWeb) {
    context.goNamed(ListaConversasWidget.routeName, queryParameters: q);
    return;
  }

  context.pushNamed(ChatPageWidget.routeName, queryParameters: q);
}

/// Variante com [GoRouter] (ex. resume Stripe sem [BuildContext] de widget).
void openH10ConversationWithRouter(
  GoRouter router, {
  required String otherUserId,
  String? orderId,
  String? productId,
  String? chatId,
}) {
  final other = otherUserId.trim();
  final oid = (orderId ?? '').trim();
  final cid = (chatId ?? '').trim();
  if (other.isEmpty || cid.isEmpty) return;

  final q = <String, String?>{
    'chatId': serializeParam(cid, ParamType.String),
    'otherUserId': serializeParam(other, ParamType.String),
    if (oid.isNotEmpty) 'orderId': serializeParam(oid, ParamType.String),
    if ((productId ?? '').trim().isNotEmpty)
      'productId': serializeParam(productId!.trim(), ParamType.String),
  }.withoutNulls;

  if (kIsWeb) {
    router.goNamed(ListaConversasWidget.routeName, queryParameters: q);
    return;
  }
  router.goNamed(ChatPageWidget.routeName, queryParameters: q);
}
