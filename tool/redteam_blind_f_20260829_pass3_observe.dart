/// Observe dual-pay after Stripe TEST attempt.
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
  const oa = 'b241022c-2883-42ed-828f-6e68415b72e5';
  const ob = '10c41bc5-fb04-43c0-9810-ef992077bef8';
  const pid = '7c7de7b2-e6d0-4875-8477-471a109b169d';
  final h = {
    'apikey': c.serviceRoleKey,
    'Authorization': 'Bearer ${c.serviceRoleKey}',
  };
  final ords = await http.get(
    Uri.parse(
      '${c.url}/rest/v1/orders?id=in.($oa,$ob)&select=id,status,stock_units_applied,stripe_payment_intent_id,stripe_checkout_session_id,amount_paid_cents,stripe_refund_id,price_total',
    ),
    headers: h,
  );
  final prod = await http.get(
    Uri.parse(
      '${c.url}/rest/v1/products?id=eq.$pid&select=id,quantity,is_sold',
    ),
    headers: h,
  );
  final ev = await http.get(
    Uri.parse(
      '${c.url}/rest/v1/stripe_checkout_events?order_id=in.($oa,$ob)&select=event,order_id,session_id,created_at&order=created_at.desc&limit=20',
    ),
    headers: h,
  );
  final buyer = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final seller = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final w = await http.get(
    Uri.parse(
      '${c.url}/rest/v1/wallets?select=id,balance&id=in.($buyer,$seller)',
    ),
    headers: h,
  );
  final report = {
    'orders': ords.body,
    'product': prod.body,
    'events': ev.body,
    'wallets': w.body,
  };
  File('tool/redteam_blind_f_20260829/pass3_stripe_observe.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}
