// ignore_for_file: avoid_print
/// C26 — reproduz APP-072 como o vendedor autenticado (para ver erro RLS/constraint).
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  const orderId = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';
  const disputeId = '03fa9312-8383-40a9-90d7-bdb19a780ef0';
  final env = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final email = envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL');
  final password = envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD');
  final token = await c.signIn(email: email, password: password);
  final uid = await c.userIdForAccessToken(token);
  print('seller uid=$uid');

  final now = DateTime.now().toUtc().toIso8601String();
  try {
    await c.patchAsUser(
      token,
      'order_disputes',
      'id=eq.$disputeId',
      {
        'status': 'escalada_fleaber',
        'current_turn': 'administracao',
        'seller_return_issue_at': now,
        'next_deadline': now,
      },
    );
    print('dispute patch OK');
  } catch (e) {
    print('dispute patch FAIL: $e');
  }

  try {
    await c.patchAsUser(
      token,
      'orders',
      'id=eq.$orderId',
      {'status': 'disputa_devolucao_vendedor'},
    );
    print('order patch OK');
  } catch (e) {
    print('order patch FAIL: $e');
  }

  try {
    await c.insertAsUser(token, 'order_dispute_replies', {
      'dispute_id': disputeId,
      'sender_id': uid,
      'message':
          'O vendedor reportou problema com a devolução. A disputa foi enviada para o Fleaber decidir.',
      'proof_photos': <String>[],
    });
    print('reply insert OK');
  } catch (e) {
    print('reply insert FAIL: $e');
  }

  final snap = await c.select('orders', filter: 'id=eq.$orderId', limit: 1);
  final d = await c.select('order_disputes', filter: 'id=eq.$disputeId', limit: 1);
  print(jsonEncode({
    'order_status': snap.first['status'],
    'dispute_status': d.first['status'],
    'seller_return_issue_at': d.first['seller_return_issue_at'],
  }));
}
