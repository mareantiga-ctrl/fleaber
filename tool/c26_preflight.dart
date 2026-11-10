// ignore_for_file: avoid_print
/// C26 preflight — encomendas B↔V úteis para APP-072.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final buyer = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final seller = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  final orders = await sb.select(
    'orders',
    filter:
        'buyer_id=eq.$buyer&seller_id=eq.$seller&order=created_at.desc',
    limit: 60,
  );
  final disputes = await sb.select(
    'order_disputes',
    filter: 'buyer_id=eq.$buyer&order=created_at.desc',
    limit: 80,
  );
  final byOrder = <String, Map<String, dynamic>>{};
  for (final d in disputes) {
    byOrder[d['order_id'].toString()] = d;
  }

  final buckets = <String, List<Map<String, dynamic>>>{
    'devolucao_entregue': [],
    'em_devolucao': [],
    'pedido_devolucao': [],
    'entregue_concluido_sem_disputa': [],
    'enviado': [],
    'pago': [],
  };

  for (final o in orders) {
    final id = o['id'].toString();
    final st = (o['status'] ?? '').toString();
    final row = {
      'id': id,
      'status': st,
      'price_total': o['price_total'],
      'product_id': o['product_id'],
      'created_at': o['created_at'],
      'dispute': byOrder[id] == null
          ? null
          : {
              'id': byOrder[id]!['id'],
              'status': byOrder[id]!['status'],
              'buyer_decision': byOrder[id]!['buyer_decision'],
              'return_delivered_at': byOrder[id]!['return_delivered_at'],
              'seller_return_issue_at': byOrder[id]!['seller_return_issue_at'],
            },
    };
    if (st == 'devolucao_entregue') {
      buckets['devolucao_entregue']!.add(row);
    } else if (st == 'em_devolucao') {
      buckets['em_devolucao']!.add(row);
    } else if (st == 'pedido_devolucao') {
      buckets['pedido_devolucao']!.add(row);
    } else if ((st == 'entregue' || st == 'concluido') &&
        byOrder[id] == null) {
      buckets['entregue_concluido_sem_disputa']!.add(row);
    } else if (st == 'enviado') {
      buckets['enviado']!.add(row);
    } else if (st == 'pago') {
      buckets['pago']!.add(row);
    }
  }

  final chats = await sb.select(
    'chats',
    filter:
        'or=(and(user_a.eq.$buyer,user_b.eq.$seller),and(user_a.eq.$seller,user_b.eq.$buyer))&order=last_message_time.desc.nullslast',
    limit: 5,
  );

  final out = {
    'buyer': buyer,
    'seller': seller,
    'chat_id': chats.isEmpty ? null : chats.first['id'],
    'buckets': buckets,
    'pick': buckets['devolucao_entregue']!.isNotEmpty
        ? {'path': 'seller_issue_now', 'order': buckets['devolucao_entregue']!.first}
        : buckets['em_devolucao']!.isNotEmpty
            ? {'path': 'buyer_label_then_seller_issue', 'order': buckets['em_devolucao']!.first}
            : buckets['pedido_devolucao']!.isNotEmpty
                ? {'path': 'seller_offer_then_buyer_accept', 'order': buckets['pedido_devolucao']!.first}
                : buckets['entregue_concluido_sem_disputa']!.isNotEmpty
                    ? {
                        'path': 'open_dispute_full',
                        'order': buckets['entregue_concluido_sem_disputa']!.first
                      }
                    : buckets['enviado']!.isNotEmpty
                        ? {'path': 'confirm_reception', 'order': buckets['enviado']!.first}
                        : buckets['pago']!.isNotEmpty
                            ? {'path': 'ship_then_confirm', 'order': buckets['pago']!.first}
                            : {'path': 'need_new_purchase', 'order': null},
  };

  final dir = Directory('tool/reports/battery_c26_2026-08-22/bd');
  await dir.create(recursive: true);
  final f = File('${dir.path}/c26_preflight.json');
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out['pick']));
  print('wrote ${f.path}');
}
