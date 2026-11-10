// ignore_for_file: avoid_print
/// SEC-025 — seed numa thread com uma só encomenda (evita _orderForChat errado).
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

// Chat único do produto C27 B (d275213c) — order enviado 9b65a63d
const _orderId = '9b65a63d-f0e0-4fe3-b1dd-9aee73247c06';
const _chatId = '7b913a51-69af-474e-a9ef-0aac45bfee63';
const _reportDir = 'tool/reports/battery_aviso_sec025_2026-08-23/bd';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  // Restaurar seed anterior (0f632c04) para não deixar lixo
  try {
    await sb.deleteWhere(
      'order_disputes',
      'order_id=eq.0f632c04-b3c5-4074-8957-892e258f7f92',
    );
    await sb.patch(
      'orders',
      'id=eq.0f632c04-b3c5-4074-8957-892e258f7f92',
      {'status': 'pago'},
    );
    print('restored previous seed order 0f632c04 → pago');
  } catch (e) {
    print('restore warn: $e');
  }

  final orders = await sb.select('orders', filter: 'id=eq.$_orderId', limit: 1);
  if (orders.isEmpty) {
    stderr.writeln('FAIL order');
    exit(1);
  }
  final prevStatus = orders.first['status']?.toString() ?? '';

  final existing =
      await sb.select('order_disputes', filter: 'order_id=eq.$_orderId', limit: 5);
  for (final d in existing) {
    await sb.deleteWhere('order_disputes', 'id=eq.${d['id']}');
  }

  final deadline =
      DateTime.now().toUtc().add(const Duration(days: 2)).toIso8601String();
  final dispute = await sb.insert('order_disputes', {
    'order_id': _orderId,
    'buyer_id': buyerId,
    'reason': 'outro',
    'description': 'SEC025 seed — artigo com defeito menor, proponho acordo parcial',
    'proof_photos': <String>[],
    'status': 'respondida_vendedor',
    'current_turn': 'comprador',
    'next_deadline': deadline,
    'seller_offer_type': 'partial_refund',
    'seller_pays_return_shipping': false,
    'seller_refund_percent': 40,
    'buyer_decision': null,
  });

  await sb.patch('orders', 'id=eq.$_orderId', {
    'status': 'pedido_devolucao',
    // Permitir re-testar Aceitar (RPC bloqueia se já processou wallet).
    'wallet_release_processed_at': null,
    'wallet_refund_processed_at': null,
  });

  final cardText = 'FLEABER_JSON_V1:${jsonEncode({
        'kind': 'order_dispute_opened',
        'order_id': _orderId,
        'reason': 'outro',
        'description': 'SEC025 seed — artigo com defeito menor',
        'proof_photos': [],
        'v': 1,
      })}';
  await sb.insert('chat_messages', {
    'chat_id': _chatId,
    'sender_id': buyerId,
    'receiver_id': sellerId,
    'text': cardText,
    'is_read': false,
    'is_reservation': true,
  });

  final payload = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'order_id': _orderId,
    'chat_id': _chatId,
    'dispute_id': dispute['id'],
    'prev_order_status': prevStatus,
    'seller_offer_type': 'partial_refund',
    'seller_refund_percent': 40,
    'note': 'thread exclusiva produto d275213c (sem irmão concluido)',
  };
  final outDir = Directory(_reportDir);
  await outDir.create(recursive: true);
  await File('${outDir.path}/sec025_seed.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  await File('${outDir.path}/sec025.env').writeAsString([
    'AVISO_SEC025_CHAT_ID=$_chatId',
    'AVISO_SEC025_ORDER_ID=$_orderId',
    'AVISO_SEC025_DISPUTE_ID=${dispute['id']}',
  ].join('\n'));
  print(jsonEncode(payload));
}
