// ignore_for_file: avoid_print
/// Remove disputa C25 acidental + repõe encomenda concluida (janela disputa/avaliacao).
library;

import 'dart:convert';

import 'live_ops_staging_client.dart';

const _orderId = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';
const _chatId = '5350ea04-b246-4904-8fb7-7d4d53e15187';

Future<void> main(List<String> args) async {
  final orderId = args.isEmpty ? _orderId : args.first;
  final e = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL')),
    anonKey: envRequire(e, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final before = await c.select('orders', filter: 'id=eq.$orderId', limit: 1);
  if (before.isEmpty) {
    print(jsonEncode({'ok': false, 'error': 'order not found'}));
    return;
  }
  final completedAt = before.first['completed_at']?.toString() ??
      '2026-08-22T15:41:13.964453+00:00';

  final disputes = await c.select(
    'order_disputes',
    filter: 'order_id=eq.$orderId',
    limit: 10,
  );
  var deletedDisputes = 0;
  for (final d in disputes) {
    final id = d['id']?.toString();
    if (id == null || id.isEmpty) continue;
    await c.deleteWhere('order_dispute_replies', 'dispute_id=eq.$id');
    await c.deleteWhere('order_disputes', 'id=eq.$id');
    deletedDisputes++;
  }

  var deletedChatMsgs = 0;
  final msgs = await c.select(
    'chat_messages',
    filter: 'chat_id=eq.$_chatId',
    limit: 300,
  );
  for (final m in msgs) {
    final text = (m['text'] ?? '').toString();
    if (text.contains('order_dispute_opened') && text.contains(orderId)) {
      final id = m['id']?.toString();
      if (id != null && id.isNotEmpty) {
        await c.deleteWhere('chat_messages', 'id=eq.$id');
        deletedChatMsgs++;
      }
    }
  }

  await c.patch('orders', 'id=eq.$orderId', {
    'status': 'concluido',
    'completed_at': completedAt,
    'wallet_release_processed_at': null,
    'auto_feedback_processed_at': null,
  });

  await c.patch('chats', 'id=eq.$_chatId', {
    'last_message': 'Venda concluída. Obrigado!',
  });

  final afterOrder = await c.select('orders', filter: 'id=eq.$orderId', limit: 1);
  final afterDisputes = await c.select(
    'order_disputes',
    filter: 'order_id=eq.$orderId',
    limit: 5,
  );

  print(jsonEncode({
    'ok': true,
    'order_id': orderId,
    'chat_id': _chatId,
    'deleted_disputes': deletedDisputes,
    'deleted_chat_messages': deletedChatMsgs,
    'order_after': afterOrder.first,
    'disputes_remaining': afterDisputes.length,
    'next':
        'Redmi: sai do chat e reabre. Devem voltar «Deixar avaliação» + «Tenho um problema».',
  }));
}
