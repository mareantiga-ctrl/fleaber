/// PASS 3c — credit_wallet_once with real signature + observe dual-pay.
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
  final sellerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  Future<Map<String, dynamic>> call(
    String tok,
    String who,
    Map<String, dynamic> params,
  ) async {
    final r = await http.post(
      Uri.parse('${c.url}/rest/v1/rpc/batata_credit_wallet_once'),
      headers: {
        'apikey': c.anonKey,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(params),
    );
    return {'who': who, 'http': r.statusCode, 'body': r.body, 'params': params};
  }

  final wBefore = await http.get(
    Uri.parse('${c.url}/rest/v1/wallets?select=id,balance&id=in.($buyerId,$sellerId)'),
    headers: {
      'apikey': c.serviceRoleKey,
      'Authorization': 'Bearer ${c.serviceRoleKey}',
    },
  );

  final tries = <Map<String, dynamic>>[];
  for (final who in [
    ['buyer', buyerTok, buyerId],
    ['buyer_credit_seller', buyerTok, sellerId],
    ['seller', sellerTok, sellerId],
  ]) {
    tries.add(
      await call(who[1] as String, who[0] as String, {
        'p_wallet_id': who[2],
        'p_amount': 1.0,
        'p_description': 'rtf3c',
        'p_order_id': null,
        'p_type': 'credit',
      }),
    );
  }

  // debit
  final debit = await http.post(
    Uri.parse('${c.url}/rest/v1/rpc/batata_debit_wallet_once'),
    headers: {
      'apikey': c.anonKey,
      'Authorization': 'Bearer $buyerTok',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'p_wallet_id': sellerId,
      'p_amount': 0.01,
      'p_description': 'rtf3c',
      'p_order_id': null,
      'p_type': 'debit',
    }),
  );

  final wAfter = await http.get(
    Uri.parse('${c.url}/rest/v1/wallets?select=id,balance&id=in.($buyerId,$sellerId)'),
    headers: {
      'apikey': c.serviceRoleKey,
      'Authorization': 'Bearer ${c.serviceRoleKey}',
    },
  );

  // draw ACTIVE raffle of seller as buyer
  const activeRaffle = '6264a19e-eebe-4f6e-a0dc-aa4947d75a2c';
  final drawActive = await http.post(
    Uri.parse('${c.url}/rest/v1/rpc/batata_draw_live_raffle_winners'),
    headers: {
      'apikey': c.anonKey,
      'Authorization': 'Bearer $buyerTok',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'p_raffle_id': activeRaffle}),
  );

  final report = {
    'w_before': wBefore.body,
    'credit_tries': tries,
    'debit_buyer_on_seller': {'http': debit.statusCode, 'body': debit.body},
    'w_after': wAfter.body,
    'draw_active_raffle_as_buyer': {
      'http': drawActive.statusCode,
      'body': drawActive.body,
    },
  };
  File('tool/redteam_blind_f_20260829/pass3c_credit.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}
