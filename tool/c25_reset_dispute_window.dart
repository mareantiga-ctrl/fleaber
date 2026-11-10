// ignore_for_file: avoid_print
/// Repõe janela de disputa C25 em staging: saldo retido + sem auto-feedback.
library;

import 'dart:convert';

import 'live_ops_staging_client.dart';

const _orderId = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';
const _sellerId = '980f4fa1-0004-42f9-abca-69f1a9c29588';

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL')),
    anonKey: envRequire(e, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final before = await c.select('orders', filter: 'id=eq.$_orderId', limit: 1);
  if (before.isEmpty) {
    print('order not found');
    return;
  }

  // 0) Bloquear cron staging antes de limpar reviews (corre ~c/ minuto).
  final now = DateTime.now().toUtc().toIso8601String();
  await c.patch('orders', 'id=eq.$_orderId', {
    'status': 'concluido',
    'wallet_release_processed_at': null,
    'auto_feedback_processed_at': now,
    'completed_at': now,
  });

  // 1) Remover avaliações automáticas (disparam libertação de saldo).
  await c.deleteWhere('reviews', 'order_id=eq.$_orderId');

  // 2) Reverter crédito «venda» ao vendedor desta encomenda.
  final vendaTx = await c.select(
    'wallet_transactions',
    filter: 'order_id=eq.$_orderId&type=eq.venda',
    limit: 5,
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
      final w = wallets.first;
      final bal = (w['balance'] as num?)?.toDouble() ?? 0;
      await c.patch('wallets', 'id=eq.$_sellerId', {
        'balance': bal - reversed,
      });
    }
  }

  // 3) Confirmar janela aberta (patch idempotente).
  await c.patch('orders', 'id=eq.$_orderId', {
    'status': 'concluido',
    'wallet_release_processed_at': null,
    'auto_feedback_processed_at': now,
    'completed_at': now,
  });

  final afterOrder = await c.select('orders', filter: 'id=eq.$_orderId', limit: 1);
  final reviews = await c.select('reviews', filter: 'order_id=eq.$_orderId', limit: 5);
  final disputes = await c.select('order_disputes', filter: 'order_id=eq.$_orderId', limit: 5);

  print(jsonEncode({
    'ok': true,
    'reversed_seller_credit_eur': reversed,
    'order_after': afterOrder.first,
    'reviews_count': reviews.length,
    'disputes_count': disputes.length,
    'hint': 'No Redmi: sai do chat e volta a abrir (ou pull refresh). Devem voltar «Deixar avaliação» + «Tenho um problema».',
  }));
}
