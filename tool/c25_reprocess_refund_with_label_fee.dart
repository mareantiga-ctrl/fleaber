// ignore_for_file: avoid_print
/// Reprocessa reembolso C25 após fix abate etiqueta 3,50 €.
/// 1) Remove tx reembolso +5 antiga 2) ajusta saldo 3) limpa wallet_refund_processed_at
/// 4) chama batata_refund_buyer_wallet_for_order
library;

import 'dart:convert';

import 'live_ops_staging_client.dart';

const _orderId = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';
const _buyerId = '7848848c-92df-4341-ad2a-7a5c24f1c250';
const _oldRefundId = '49dc67d1-d6d4-4bd0-a00e-01ade1db00d7';

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL')),
    anonKey: envRequire(e, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final beforeWallet =
      (await c.select('wallets', filter: 'id=eq.$_buyerId', limit: 1)).first;
  final beforeBal = (beforeWallet['balance'] as num?)?.toDouble() ?? 0;

  final oldTx = await c.select(
    'wallet_transactions',
    filter: 'id=eq.$_oldRefundId',
    limit: 1,
  );
  var reversed = 0.0;
  if (oldTx.isNotEmpty) {
    reversed = (oldTx.first['amount'] as num?)?.toDouble() ?? 0;
    await c.deleteWhere('wallet_transactions', 'id=eq.$_oldRefundId');
    await c.patch('wallets', 'id=eq.$_buyerId', {
      'balance': beforeBal - reversed,
    });
  }

  await c.patch('orders', 'id=eq.$_orderId', {
    'wallet_refund_processed_at': null,
    'status': 'devolvida',
  });

  final afterUndoBal =
      ((await c.select('wallets', filter: 'id=eq.$_buyerId', limit: 1)).first
          ['balance'] as num?)
          ?.toDouble();

  dynamic rpcResult;
  try {
    rpcResult = await c.rpc(
      'batata_refund_buyer_wallet_for_order',
      {'p_order_id': _orderId},
    );
  } catch (err) {
    rpcResult = {'error': err.toString()};
  }

  final afterOrder =
      (await c.select('orders', filter: 'id=eq.$_orderId', limit: 1)).first;
  final afterWallet =
      (await c.select('wallets', filter: 'id=eq.$_buyerId', limit: 1)).first;
  final txs = await c.select(
    'wallet_transactions',
    filter: 'order_id=eq.$_orderId',
    limit: 20,
  );

  print(jsonEncode({
    'balance_before_undo': beforeBal,
    'reversed_old_refund': reversed,
    'balance_after_undo_before_new_refund': afterUndoBal,
    'rpc_result': rpcResult,
    'order_after': {
      'status': afterOrder['status'],
      'wallet_refund_processed_at': afterOrder['wallet_refund_processed_at'],
    },
    'buyer_wallet_after': afterWallet,
    'txs_order': txs,
    'expected_new_refund': 1.5,
  }));
}
