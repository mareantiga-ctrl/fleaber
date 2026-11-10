/// PASS 3d — debit signature + purchase ledger execute.
library;

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final c = LiveOpsStagingClient(
    url: url,
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );

  Future<Map<String, dynamic>> post(String fn, Map<String, dynamic> p) async {
    final r = await http.post(
      Uri.parse('${c.url}/rest/v1/rpc/$fn'),
      headers: {
        'apikey': c.anonKey,
        'Authorization': 'Bearer $buyerTok',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(p),
    );
    return {'fn': fn, 'http': r.statusCode, 'body': r.body};
  }

  final debit = await post('batata_debit_wallet_once', {
    'p_wallet_id': sellerId,
    'p_amount': 0.01,
    'p_description': 'rtf3d',
    'p_order_id': null,
  });
  final debitSelf = await post('batata_debit_wallet_once', {
    'p_wallet_id': buyerId,
    'p_amount': 0.01,
    'p_description': 'rtf3d',
    'p_order_id': null,
  });
  final ledger = await post('batata_record_buyer_purchase_ledger', {
    'p_order_id': 'bb56dbbf-589f-4a5b-ba2d-81526e87cc33',
    'p_buyer_id': buyerId,
    'p_amount': 18,
  });

  final wt = await http.get(
    Uri.parse(
      '${c.url}/rest/v1/wallet_transactions?select=*&wallet_id=eq.$buyerId&order=created_at.desc&limit=5',
    ),
    headers: {
      'apikey': c.serviceRoleKey,
      'Authorization': 'Bearer ${c.serviceRoleKey}',
    },
  );
  final w = await http.get(
    Uri.parse('${c.url}/rest/v1/wallets?select=id,balance&id=in.($buyerId,$sellerId)'),
    headers: {
      'apikey': c.serviceRoleKey,
      'Authorization': 'Bearer ${c.serviceRoleKey}',
    },
  );

  final report = {
    'debit_seller': debit,
    'debit_self': debitSelf,
    'ledger': ledger,
    'wallet_tx': wt.body,
    'wallets': w.body,
  };
  File('tool/redteam_blind_f_20260829/pass3d_ledger.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln(jsonEncode(report));
}
