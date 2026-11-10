// ignore_for_file: avoid_print
/// C25 preflight — devices + ledger para próxima bateria BATATA.
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
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  final outDir = Directory('tool/reports/battery_c25_2026-08-22');
  await outDir.create(recursive: true);

  final orders = await sb.select(
    'orders',
    filter: 'buyer_id=eq.$buyerId&order=created_at.desc',
    limit: 80,
  );
  final disputes = await sb.select(
    'order_disputes',
    filter: 'order=created_at.desc',
    limit: 200,
  );
  final disputeOrderIds =
      disputes.map((d) => d['order_id'].toString()).toSet();

  final byStatus = <String, int>{};
  for (final o in orders) {
    final s = (o['status'] ?? '').toString();
    byStatus[s] = (byStatus[s] ?? 0) + 1;
  }

  final eligible058 = orders.where((o) {
    final s = (o['status'] ?? '').toString();
    if (s != 'concluido' && s != 'entregue') return false;
    return !disputeOrderIds.contains(o['id'].toString());
  }).map((o) {
    return {
      'id': o['id'],
      'status': o['status'],
      'created_at': o['created_at'],
      'seller_id': o['seller_id'],
    };
  }).toList();

  Map<String, dynamic>? chatForOrder(String orderId) {
    for (final o in orders) {
      if (o['id'].toString() == orderId) {
        return {
          'order_id': orderId,
          'buyer_id': o['buyer_id'],
          'seller_id': o['seller_id'],
        };
      }
    }
    return null;
  }

  final pago = orders
      .where((o) => (o['status'] ?? '').toString() == 'pago')
      .map((o) => {'id': o['id'], 'created_at': o['created_at']})
      .toList();
  final enviado = orders
      .where((o) => (o['status'] ?? '').toString() == 'enviado')
      .map((o) => {'id': o['id'], 'created_at': o['created_at']})
      .toList();

  final chats = await sb.select(
    'chats',
    filter:
        'or=(and(user_a.eq.$buyerId,user_b.eq.$sellerId),and(user_a.eq.$sellerId,user_b.eq.$buyerId))&order=last_message_time.desc.nullslast',
    limit: 10,
  );

  final livesActive = await sb.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&is_active=eq.true&order=created_at.desc',
    limit: 10,
  );

  String? nextAction;
  if (livesActive.isNotEmpty) {
    nextAction =
        'Fechar directo activo antes de editar/correr bateria (BATATA).';
  } else if (eligible058.isNotEmpty) {
    nextAction = 'APP-058: reteste UI no Redmi com order ${eligible058.first['id']}.';
  } else if (enviado.isNotEmpty) {
    nextAction =
        'APP-058 prep: B confirma receção em order ${enviado.first['id']} → concluido → reteste disputa.';
  } else if (pago.isNotEmpty) {
    nextAction =
        'APP-058 prep: V envia order ${pago.first['id']} → B confirma receção → reteste disputa.';
  } else {
    nextAction =
        'APP-058 prep: nova compra MB WAY/directo até receção confirmada (ou usar encomenda histórica se existir noutro buyer).';
  }

  final result = {
    'generated_at': DateTime.now().toIso8601String(),
    'devices': {
      'seller_tcl': env['MAESTRO_DEVICE_SELLER'] ?? 'a698f0de',
      'buyer_redmi': env['MAESTRO_DEVICE_BUYER'] ?? 'd6pnqgz5jvnnbm9x',
    },
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'status_counts': byStatus,
    'eligible_058': eligible058,
    'pago_orders': pago,
    'enviado_orders': enviado,
    'recent_chats': chats
        .map((c) => {
              'id': c['id'],
              'user_a': c['user_a'],
              'user_b': c['user_b'],
              'last_message_time': c['last_message_time'],
            })
        .take(8)
        .toList(),
    'active_lives': livesActive
        .map((l) => {
              'id': l['id'],
              'status': l['status'],
              'title': l['title'],
              'is_active': l['is_active'],
            })
        .toList(),
    'next_action': nextAction,
    '058_target': eligible058.isNotEmpty
        ? {
            ...eligible058.first,
            'chat_id': chats.isEmpty ? null : chats.first['id'],
            'chat_hint': chatForOrder(eligible058.first['id'].toString()),
          }
        : (enviado.isNotEmpty
            ? {
                'prep_order_id': enviado.first['id'],
                'chat_id': chats.isEmpty ? null : chats.first['id'],
                'step': 'B confirma receção → concluido',
              }
            : (pago.isNotEmpty
                ? {
                    'prep_order_id': pago.first['id'],
                    'chat_id': chats.isEmpty ? null : chats.first['id'],
                    'step': 'V envia → B confirma receção',
                  }
                : null)),
  };

  final file = File('${outDir.path}/c25_preflight_ledger.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(result));
  print('wrote ${file.path}');
  print('next: $nextAction');

  for (final s in ['concluido', 'entregue', 'enviado']) {
    final rows = await sb.select(
      'orders',
      filter: 'buyer_id=eq.$buyerId&status=eq.$s&order=created_at.desc',
      limit: 5,
    );
    print('$s count=${rows.length}');
    for (final r in rows) {
      print('  ${r['id']} ${r['created_at']}');
    }
  }
}
