// ignore_for_file: avoid_print
library;

import 'dart:convert';

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const buyer = '7848848c-92df-4341-ad2a-7a5c24f1c250';
  final msgs = await client.select(
    'chat_messages',
    filter: 'sender_id=eq.$buyer&order=created_at.desc',
    limit: 8,
  );
  print('--- last buyer messages ---');
  print(const JsonEncoder.withIndent('  ').convert(msgs.map((m) {
        final t = (m['text'] ?? '').toString();
        return {
          'id': m['id'],
          'created_at': m['created_at'],
          'preview': t.length > 180 ? '${t.substring(0, 180)}…' : t,
          'is_image': t.contains('chat_image'),
        };
      }).toList()));

  final orders = await client.select(
    'orders',
    filter:
        'or=(buyer_id.eq.$buyer,seller_id.eq.980f4fa1-0004-42f9-abca-69f1a9c29588)&order=created_at.desc',
    limit: 12,
  );
  print('--- recent orders ---');
  print(const JsonEncoder.withIndent('  ').convert(orders.map((o) {
        return {
          'id': o['id'],
          'status': o['status'],
          'total': o['total'] ?? o['amount'] ?? o['total_eur'],
          'created_at': o['created_at'],
        };
      }).toList()));
}
