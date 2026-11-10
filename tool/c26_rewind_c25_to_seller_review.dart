// ignore_for_file: avoid_print
/// C26 — rebobina encomenda C25 (já E2E até devolucao_entregue) para o ramo APP-072.
/// Não mexe no reembolso já processado; só repõe estado UI do vendedor a rever devolução.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  const orderId = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';
  const disputeId = '03fa9312-8383-40a9-90d7-bdb19a780ef0';
  const chatId = '5350ea04-b246-4904-8fb7-7d4d53e15187';

  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final beforeOrder =
      (await sb.select('orders', filter: 'id=eq.$orderId', limit: 1)).first;
  final beforeDispute = (await sb.select(
    'order_disputes',
    filter: 'id=eq.$disputeId',
    limit: 1,
  ))
      .first;

  await sb.patch('orders', 'id=eq.$orderId', {
    'status': 'devolucao_entregue',
  });

  final now = DateTime.now().toUtc();
  await sb.patch('order_disputes', 'id=eq.$disputeId', {
    'status': 'aberta',
    'current_turn': 'vendedor',
    'next_deadline': now.add(const Duration(days: 2)).toIso8601String(),
    'seller_return_issue_at': null,
    'admin_resolution': null,
    'admin_resolution_note': null,
  });

  final afterOrder =
      (await sb.select('orders', filter: 'id=eq.$orderId', limit: 1)).first;
  final afterDispute = (await sb.select(
    'order_disputes',
    filter: 'id=eq.$disputeId',
    limit: 1,
  ))
      .first;

  final out = {
    'note':
        'Rewind branch-point only: order had full C25 E2E to devolucao_entregue; reset for APP-072 seller issue UI.',
    'order_id': orderId,
    'dispute_id': disputeId,
    'chat_id': chatId,
    'before': {
      'order_status': beforeOrder['status'],
      'dispute_status': beforeDispute['status'],
      'wallet_refund_processed_at':
          beforeOrder['wallet_refund_processed_at'],
    },
    'after': {
      'order_status': afterOrder['status'],
      'dispute_status': afterDispute['status'],
      'current_turn': afterDispute['current_turn'],
      'return_delivered_at': afterDispute['return_delivered_at'],
      'buyer_decision': afterDispute['buyer_decision'],
      'wallet_refund_processed_at':
          afterOrder['wallet_refund_processed_at'],
    },
  };

  final dir = Directory('tool/reports/battery_c26_2026-08-22/bd');
  await dir.create(recursive: true);
  await File('${dir.path}/c26_rewind_before_072.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
}
