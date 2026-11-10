// ignore_for_file: avoid_print
/// C26 — regressão títulos disputa (aberta / análise / fechada) + restore.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  const disputeId = '03fa9312-8383-40a9-90d7-bdb19a780ef0';
  const orderId = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';
  final mode = args.isEmpty ? 'escalada' : args.first;

  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  Map<String, dynamic> patch;
  switch (mode) {
    case 'aberta':
      patch = {
        'status': 'aberta',
        'current_turn': 'vendedor',
      };
      break;
    case 'fechada':
      patch = {
        'status': 'resolvida',
        'current_turn': 'administracao',
      };
      break;
    case 'escalada':
    default:
      patch = {
        'status': 'escalada_fleaber',
        'current_turn': 'administracao',
      };
      // keep order as disputa_devolucao_vendedor for 072
      break;
  }

  await sb.patch('order_disputes', 'id=eq.$disputeId', patch);
  if (mode == 'escalada') {
    await sb.patch('orders', 'id=eq.$orderId', {
      'status': 'disputa_devolucao_vendedor',
    });
  }

  final d =
      (await sb.select('order_disputes', filter: 'id=eq.$disputeId', limit: 1))
          .first;
  final o =
      (await sb.select('orders', filter: 'id=eq.$orderId', limit: 1)).first;
  print(jsonEncode({
    'mode': mode,
    'dispute_status': d['status'],
    'current_turn': d['current_turn'],
    'order_status': o['status'],
  }));
}
