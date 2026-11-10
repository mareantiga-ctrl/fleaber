// ignore_for_file: avoid_print
/// Anula feedback automático + repõe janela disputa/avaliação numa encomenda concluida.
library;

import 'dart:convert';

import 'live_ops_staging_client.dart';

const _orderId = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';
const _chatId = '5350ea04-b246-4904-8fb7-7d4d53e15187';
const _sellerId = '980f4fa1-0004-42f9-abca-69f1a9c29588';

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
  final completedAt = before.first['completed_at']?.toString();

  // 1) Reviews automáticas/manuais desta encomenda.
  await c.deleteWhere('reviews', 'order_id=eq.$orderId');

  // 2) Card «feedback automático» no chat (se existir).
  final msgs = await c.select(
    'chat_messages',
    filter: 'chat_id=eq.$_chatId',
    limit: 200,
  );
  for (final m in msgs) {
    final text = (m['text'] ?? '').toString();
    if (text.contains('auto_feedback_generated') &&
        text.contains(orderId)) {
      final id = m['id']?.toString();
      if (id != null && id.isNotEmpty) {
        await c.deleteWhere('chat_messages', 'id=eq.$id');
      }
    }
  }

  // 3) Reverter crédito «venda» ao vendedor.
  final vendaTx = await c.select(
    'wallet_transactions',
    filter: 'order_id=eq.$orderId&type=eq.venda',
    limit: 10,
  );
  var reversed = 0.0;
  for (final tx in vendaTx) {
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    reversed += amount;
    final id = tx['id']?.toString();
    if (id != null && id.isNotEmpty) {
      await c.deleteWhere('wallet_transactions', 'id=eq.$id');
    }
  }
  if (reversed > 0) {
    final wallets = await c.select('wallets', filter: 'id=eq.$_sellerId', limit: 1);
    if (wallets.isNotEmpty) {
      final bal = (wallets.first['balance'] as num?)?.toDouble() ?? 0;
      await c.patch('wallets', 'id=eq.$_sellerId', {'balance': bal - reversed});
    }
  }

  // 4) Repor encomenda: concluida, saldo retido, sem marcar auto-feedback como processado.
  await c.patch('orders', 'id=eq.$orderId', {
    'status': 'concluido',
    'wallet_release_processed_at': null,
    'auto_feedback_processed_at': null,
    if (completedAt != null && completedAt.isNotEmpty)
      'completed_at': completedAt,
  });

  // 5) Prova: RPC não deve gerar feedback (48h BATATA).
  var rpcInserted = -1;
  try {
    final raw = await c.rpc('batata_generate_auto_feedback', {});
    rpcInserted = raw is num ? raw.toInt() : int.tryParse('$raw') ?? -1;
  } catch (err) {
    rpcInserted = -1;
  }

  final afterOrder = await c.select('orders', filter: 'id=eq.$orderId', limit: 1);
  final reviews = await c.select('reviews', filter: 'order_id=eq.$orderId', limit: 5);

  print(jsonEncode({
    'ok': true,
    'order_id': orderId,
    'chat_id': _chatId,
    'reversed_seller_credit_eur': reversed,
    'batata_generate_auto_feedback_inserted': rpcInserted,
    'order_after': afterOrder.first,
    'reviews_count': reviews.length,
    'next': 'Redmi: sair do chat e reabrir. Devem aparecer «Deixar avaliação» + «Tenho um problema».',
  }));
}
