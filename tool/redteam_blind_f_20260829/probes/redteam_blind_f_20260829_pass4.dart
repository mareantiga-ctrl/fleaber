/// PASS 4 — variantes da classe settle-quote-fail-closed vs oversell refund.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const oa = 'b241022c-2883-42ed-828f-6e68415b72e5';
const ob = '10c41bc5-fb04-43c0-9810-ef992077bef8';
const pid = '7c7de7b2-e6d0-4875-8477-471a109b169d';
const sessB =
    'cs_test_a1XKZ38IARekmVOMlG01klhh5s3dBM4HcXRu62Obcs58MOiTSVTr2nKclT';

Future<Map<String, dynamic>> snap(http.Response r) async => {
      'status': r.statusCode,
      'body': r.body.length > 2500 ? r.body.substring(0, 2500) : r.body,
    };

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final c = LiveOpsStagingClient(
    url: url,
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final svc = {
    'apikey': c.serviceRoleKey,
    'Authorization': 'Bearer ${c.serviceRoleKey}',
    'Content-Type': 'application/json',
  };
  final buyerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final buyerH = {
    'apikey': c.anonKey,
    'Authorization': 'Bearer $buyerTok',
    'Content-Type': 'application/json',
  };

  final out = <String, dynamic>{};

  Future<void> dumpState(String label) async {
    final ords = await http.get(
      Uri.parse(
        '${c.url}/rest/v1/orders?id=in.($oa,$ob)&select=id,status,stock_units_applied,stripe_payment_intent_id,stripe_checkout_session_id,amount_paid_cents,stripe_refund_id,stripe_refunded_at,price_total,buyer_id',
      ),
      headers: svc,
    );
    final prod = await http.get(
      Uri.parse(
        '${c.url}/rest/v1/products?id=eq.$pid&select=id,quantity,is_sold',
      ),
      headers: svc,
    );
    final ev = await http.get(
      Uri.parse(
        '${c.url}/rest/v1/stripe_checkout_events?or=(order_id.in.($oa,$ob),session_id.eq.$sessB)&select=event,order_id,session_id,detail,created_at&order=created_at.desc&limit=40',
      ),
      headers: svc,
    );
    out[label] = {
      'orders': ords.body,
      'product': prod.body,
      'events': ev.body,
    };
  }

  await dumpState('before_retry');

  // Re-hit GET return as anon (browser-like) and as buyer JWT.
  final settleUrl = Uri.parse(
      '${c.url}/functions/v1/create-payment-intent?checkout_return=success&session_id=$sessB');
  final anonRetry = await http.get(
    settleUrl,
    headers: {
      'apikey': c.anonKey,
      'Authorization': 'Bearer ${c.anonKey}',
    },
  );
  out['retry_anon'] = await snap(anonRetry);

  final buyerRetry = await http.get(
    settleUrl,
    headers: buyerH,
  );
  out['retry_buyer'] = await snap(buyerRetry);

  // Duplicate session on ALREADY paid order A (should refund extra PI, not second sale).
  final dupBody = jsonEncode({
    'order_id': oa,
    'buyer_id': envRequire(env, 'LIVE_OPS_TEST_BUYER_ID'),
    'shipping_method': 'hand',
  });
  final dupSess = await http.post(
    Uri.parse('${c.url}/functions/v1/create-payment-intent'),
    headers: buyerH,
    body: dupBody,
  );
  out['dup_session_on_paid_order'] = await snap(dupSess);

  // Ledger RPC with only p_order_id as buyer.
  final ledger = await http.post(
    Uri.parse('${c.url}/rest/v1/rpc/batata_record_buyer_purchase_ledger'),
    headers: buyerH,
    body: jsonEncode({'p_order_id': oa}),
  );
  out['ledger_p_order_id'] = await snap(ledger);

  // Active raffle join.
  final raffles = await http.get(
    Uri.parse(
      '${c.url}/rest/v1/live_raffles?select=id,status,is_active,seller_id&is_active=eq.true&limit=5',
    ),
    headers: svc,
  );
  out['active_raffles'] = {
    'status': raffles.statusCode,
    'body': raffles.body.length > 2000
        ? raffles.body.substring(0, 2000)
        : raffles.body,
  };
  List<dynamic> raffleRows = [];
  try {
    raffleRows = jsonDecode(raffles.body) as List<dynamic>;
  } catch (_) {}
  if (raffleRows.isNotEmpty) {
    final rid = (raffleRows.first as Map)['id'];
    final join = await http.post(
      Uri.parse('${c.url}/rest/v1/rpc/batata_join_live_raffle'),
      headers: buyerH,
      body: jsonEncode({'p_raffle_id': rid}),
    );
    out['raffle_join'] = await snap(join);
    final join2 = await http.post(
      Uri.parse('${c.url}/rest/v1/rpc/batata_join_live_raffle'),
      headers: buyerH,
      body: jsonEncode({'p_raffle_id': rid}),
    );
    out['raffle_join_dup'] = await snap(join2);
  }

  await dumpState('after_retry');

  File('tool/redteam_blind_f_20260829/pass4_raw.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'retry_anon_status': out['retry_anon']?['status'],
    'retry_buyer_status': out['retry_buyer']?['status'],
    'dup_session_status': out['dup_session_on_paid_order']?['status'],
    'ledger_status': out['ledger_p_order_id']?['status'],
    'after_orders': out['after_retry']?['orders'],
    'after_events_head': (() {
      final e = out['after_retry']?['events'] as String? ?? '';
      return e.length > 1800 ? e.substring(0, 1800) : e;
    })(),
  }));
}
