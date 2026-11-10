// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final chatId = '8751ec5b-fad4-456a-8526-5662a859ec06';
  final orderId = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final msgs = await sb.select(
    'chat_messages',
    filter: 'chat_id=eq.$chatId&order=created_at.desc',
    limit: 40,
  );
  final orderMsgs = msgs.where((m) {
    final t = (m['text'] ?? '').toString();
    return t.contains(orderId) || t.contains('FLEABER_JSON');
  }).take(15).toList();
  print(jsonEncode({
    'order_status': (await sb.select('orders', filter: 'id=eq.$orderId', limit: 1)).firstOrNull,
    'recent_messages': msgs.take(8).map((m) => {
          'created_at': m['created_at'],
          'text': (m['text'] ?? '').toString().substring(0, (m['text'] ?? '').toString().length.clamp(0, 120)),
        }).toList(),
    'order_related': orderMsgs,
  }));
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
