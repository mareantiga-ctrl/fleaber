// ignore_for_file: avoid_print
import 'dart:convert';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  final oid = args.isEmpty ? 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae' : args.first;
  final e = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL')),
    anonKey: envRequire(e, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final reviews = await c.select('reviews', filter: 'order_id=eq.$oid', limit: 10);
  final tx = await c.select('wallet_transactions', filter: 'order_id=eq.$oid', limit: 10);
  print(jsonEncode({'reviews': reviews, 'wallet_tx': tx}));
}
