// ignore_for_file: avoid_print
import 'dart:convert';
import 'live_ops_staging_client.dart';

const _orderId = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';
const _buyerId = '7848848c-92df-4341-ad2a-7a5c24f1c250';

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL')),
    anonKey: envRequire(e, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final txs = await c.select(
    'wallet_transactions',
    filter: 'order_id=eq.$_orderId',
    limit: 20,
  );
  final w = await c.select('wallets', filter: 'id=eq.$_buyerId', limit: 1);
  print(jsonEncode({'wallet_transactions': txs, 'buyer_wallet': w}));
}
