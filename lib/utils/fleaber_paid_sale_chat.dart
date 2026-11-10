import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/batata_reservation_actions.dart';
import '/chat_session_util.dart';
import '/utils/fee_calculator.dart';
import '/utils/fleaber_logger.dart';
import '/utils/fleaber_notify_emit.dart';

const String kSeguroFleaberPaidChatKind = 'seguro_fleaber_paid';

/// Mensagem chat de compra paga (JSON) — card bonito, 1 por encomenda.
String fleaberSeguroFleaberPaidChatText({
  required String orderId,
  double? totalEur,
  String? productLabel,
}) {
  return fleaberChatJsonEncode({
    'kind': kSeguroFleaberPaidChatKind,
    'order_id': orderId,
    'total': totalEur,
    if (productLabel != null && productLabel.trim().isNotEmpty)
      'label': productLabel.trim(),
    'v': 1,
  });
}

void _chatMultiLog(String step, Map<String, dynamic> data) {
  final payload = <String, dynamic>{'step': step, ...data};
  FleaberLogger.instance.logStripe('chat_multi_$step', data: payload);
  if (kDebugMode) {
    debugPrint('CHAT_MULTI $step ${jsonEncode(payload)}');
  }
}

/// Garante thread **nova** + mensagem «Comprado!» (idempotente **por encomenda**).
///
/// CHAT-MULTI: compra diferente → chat + mensagem diferentes. Nunca acrescentar
/// o card desta encomenda a uma thread de compra/reserva anterior.
Future<String?> ensureSeguroFleaberPaidSaleChat({
  required String orderId,
  String? sellerId,
  String? productId,
  double? totalEur,
  bool notifySeller = true,
}) async {
  final oid = orderId.trim();
  if (oid.isEmpty || currentUserUid.isEmpty) {
    _chatMultiLog('skip_empty', {'order_id': oid, 'uid_empty': currentUserUid.isEmpty});
    return null;
  }

  String? sid = sellerId?.trim();
  String? pid = productId?.trim();
  double? total = totalEur;

  if (sid == null ||
      sid.isEmpty ||
      pid == null ||
      pid.isEmpty ||
      total == null) {
    try {
      final rows = await OrdersTable().querySingleRow(
        queryFn: (q) => q.eqOrNull('id', oid),
      );
      if (rows.isEmpty) {
        _chatMultiLog('order_missing', {'order_id': oid});
        return null;
      }
      final o = rows.first;
      sid = (sid == null || sid.isEmpty) ? o.sellerId?.trim() : sid;
      pid = (pid == null || pid.isEmpty) ? o.productId?.trim() : pid;
      total ??= o.priceTotal;
    } catch (e) {
      _chatMultiLog('order_load_error', {'order_id': oid, 'error': e.toString()});
      return null;
    }
  }

  if (sid == null || sid.isEmpty || pid == null || pid.isEmpty) {
    _chatMultiLog('skip_ids', {'order_id': oid, 'seller': sid, 'product': pid});
    return null;
  }
  if (sid == currentUserUid) {
    _chatMultiLog('skip_self', {'order_id': oid});
    return null;
  }

  try {
    // Já existe card «seguro_fleaber_paid» desta encomenda? Abrir ESSE chat.
    final existingForOrder = await findChatForOrderId(oid);
    if (existingForOrder != null) {
      final cid = existingForOrder.id;
      if (cid != null && cid.isNotEmpty) {
        final msgs = await ChatMessagesTable().queryRows(
          queryFn: (q) => q
              .eqOrNull('chat_id', cid)
              .ilike('text', '%$oid%')
              .order('created_at', ascending: false),
          limit: 10,
        );
        final hasPaidCard = msgs.any((m) {
          final t = m.text;
          return t.contains('"kind":"$kSeguroFleaberPaidChatKind"') &&
              t.contains('"order_id":"$oid"');
        });
        if (hasPaidCard) {
          await touchChatLastMessage(
            chatId: cid,
            preview: 'Compra paga pelo Seguro Fleaber',
          );
          _chatMultiLog('reuse_existing_message', {
            'order_id': oid,
            'chat_id': cid,
            'product_id': pid,
          });
          return cid;
        }
      }
    }

    // Compra nova → thread nova + mensagem nova (não misturar com anteriores).
    final chat = await ensureSellerChat(
      otherUserId: sid,
      productId: pid,
      forceNew: true,
    );
    final chatId = chat.id;
    if (chatId == null || chatId.isEmpty) {
      _chatMultiLog('chat_insert_failed', {'order_id': oid, 'product_id': pid});
      return null;
    }

    final existing = await ChatMessagesTable().queryRows(
      queryFn: (q) => q.like('text', '%$oid%'),
      limit: 20,
    );
    final already = existing.any((m) {
      final t = m.text;
      if (t.contains('[order:$oid]')) return true;
      if (!t.startsWith(kFleaberChatJsonPrefix)) return false;
      try {
        final decoded =
            jsonDecode(t.substring(kFleaberChatJsonPrefix.length));
        if (decoded is! Map) return false;
        return decoded['kind']?.toString() == kSeguroFleaberPaidChatKind &&
            decoded['order_id']?.toString() == oid;
      } catch (_) {
        return false;
      }
    });

    if (!already) {
      await ChatMessagesTable().insert({
        'sender_id': currentUserUid,
        'receiver_id': sid,
        'chat_id': chatId,
        'text': fleaberSeguroFleaberPaidChatText(
          orderId: oid,
          totalEur: total,
        ),
        'is_read': false,
        'is_reservation': true,
      });
      _chatMultiLog('inserted_new_message', {
        'order_id': oid,
        'chat_id': chatId,
        'product_id': pid,
        'total': total,
      });
    } else {
      _chatMultiLog('message_already_elsewhere', {
        'order_id': oid,
        'new_chat_id': chatId,
        'existing_chat_id': existing.first.chatId,
      });
      // Mensagem já noutro chat (edge ganhou a corrida) — navegar para lá.
      final byOrder = await findChatForOrderId(oid);
      final realId = byOrder?.id;
      if (realId != null && realId.isNotEmpty) {
        await touchChatLastMessage(
          chatId: realId,
          preview: 'Compra paga pelo Seguro Fleaber',
        );
        return realId;
      }
    }

    await touchChatLastMessage(
      chatId: chatId,
      preview: 'Compra paga pelo Seguro Fleaber',
    );

    if (notifySeller) {
      try {
        final nid = await FleaberNotifyEmit.emit(
          recipientId: sid,
          kind: 'seguro_fleaber_paid',
          title: 'Compra paga (Seguro Fleaber)',
          body: total != null && total > 0
              ? 'Nova venda protegida · ${formatEuros(total)}'
              : 'Nova venda protegida na Fleaber',
          chatId: chatId,
          actorId: currentUserUid,
          orderId: oid.isEmpty ? null : oid,
          dedupeKey: oid.isEmpty
              ? 'seguro_paid_chat:$chatId'
              : 'seguro_paid:$oid:seller',
        );
        unawaited(FleaberNotifyEmit.requestDispatch(nid));
      } catch (_) {}
    }

    return chatId;
  } catch (e, st) {
    _chatMultiLog('error', {
      'order_id': oid,
      'error': e.toString(),
      'stack': st.toString().substring(0, 400),
    });
    return null;
  }
}
