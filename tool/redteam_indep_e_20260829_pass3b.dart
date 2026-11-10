import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

void main() async {
  final env = loadLiveOpsStagingEnv();
  final base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final c = LiveOpsStagingClient(url: base, anonKey: anon, serviceRoleKey: service);
  final buyer = await c.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'));
  Map<String, String> h(String jwt) => {
        'apikey': anon,
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
      };
  final hs = {
    'apikey': service,
    'Authorization': 'Bearer $service',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  Future<Map> rpc(String fn, Map p, {String? jwt}) async {
    final r = await http.post(Uri.parse('$base/rest/v1/rpc/$fn'),
        headers: jwt == null ? hs : h(jwt), body: jsonEncode(p));
    return {'http': r.statusCode, 'raw': r.body.length > 400 ? r.body.substring(0, 400) : r.body};
  }

  Future<Map> get(String path) async {
    final r = await http.get(Uri.parse('$base/rest/v1/$path'), headers: hs);
    return {'http': r.statusCode, 'raw': r.body.length > 500 ? r.body.substring(0, 500) : r.body};
  }

  final out = <String, dynamic>{};

  out['nuke'] = await rpc('staging_restore_stock_before_nuke', {'p_user_id': sellerId}, jwt: buyer);
  out['nuke_self'] = await rpc('staging_restore_stock_before_nuke', {'p_user_id': buyerId}, jwt: buyer);
  out['debit'] = await rpc('batata_debit_wallet_once', {
    'p_wallet_id': sellerId,
    'p_amount': 1,
    'p_description': 'x',
    'p_order_id': null,
  }, jwt: buyer);
  out['tip_mint'] = await rpc('batata_wallet_apply_tip_once', {
    'p_wallet_id': sellerId,
    'p_amount': 10,
    'p_description': 'x',
    'p_tip_id': '00000000-0000-0000-0000-000000000001',
    'p_type': 'venda',
  }, jwt: buyer);
  out['admin_dispute'] = await rpc('batata_admin_resolve_dispute', {
    'p_dispute_id': '00000000-0000-0000-0000-000000000001',
    'p_note': 'x',
    'p_resolution': 'refund',
  }, jwt: buyer);

  // Observe stock1 product + orders before pay
  out['product'] = await get(
      'products?id=eq.8905c9c1-7af0-4a38-ac71-8f2968347743&select=id,quantity,is_sold,price');
  out['orders'] = await get(
      'orders?id=in.(f0fd22c3-ff21-40d3-93a6-e3a2910e696c,039f016f-b62a-40d2-95c8-1a17cd6bbc77)&select=id,status,buyer_id,quantity,amount_paid_cents,stripe_checkout_session_id,stripe_refund_id,stock_units_applied');
  out['wallet_seller'] = await get('wallets?id=eq.$sellerId&select=id,balance');

  File('tool/redteam_indep_e_20260829/pass3b_rpc.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
