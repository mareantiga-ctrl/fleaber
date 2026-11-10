// ignore_for_file: avoid_print
/// Snapshot BD APP-095 — order + chat messages para auditoria.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  final orderId = args.isNotEmpty ? args.first : '';
  if (orderId.isEmpty) {
    stderr.writeln('usage: dart run tool/app095_bd_snapshot.dart <order_id>');
    exit(1);
  }
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final orders = await sb.select('orders', filter: 'id=eq.$orderId', limit: 1);
  if (orders.isEmpty) exit(2);
  final o = orders.first;
  final productId = o['product_id']?.toString() ?? '';
  final buyerId = o['buyer_id']?.toString() ?? '';
  final sellerId = o['seller_id']?.toString() ?? '';
  final chats = await sb.select(
    'chats',
    filter:
        'product_id=eq.$productId&or=(and(user_a.eq.$buyerId,user_b.eq.$sellerId),and(user_a.eq.$sellerId,user_b.eq.$buyerId))',
    limit: 3,
  );
  final chatId = chats.isEmpty ? '' : chats.first['id'].toString();
  List<Map<String, dynamic>> msgs = [];
  if (chatId.isNotEmpty) {
    msgs = await sb.select(
      'chat_messages',
      filter: 'chat_id=eq.$chatId&order=id.asc',
      limit: 80,
    );
  }
  final out = {
    'order': o,
    'chat_id': chatId,
    'messages': msgs.map((m) => {
          'id': m['id'],
          'text': m['text'],
          'created_at': m['created_at'],
          'is_reservation': m['is_reservation'],
        }).toList(),
  };
  final dir = Directory('tool/reports/battery_fail_2026-08-23/bd');
  await dir.create(recursive: true);
  final label = args.length > 1 ? args[1] : 'after';
  final path = '${dir.path}/app095_${label}.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode({'path': path, 'status': o['status'], 'msg_count': msgs.length}));
}
