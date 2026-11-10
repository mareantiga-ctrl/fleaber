/// Pass 2 — anti-falso-positivo + hipóteses extra (auditoria cega C).
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stagingRef = 'fxdknzrqjenzqcvnwqqq';
const otherSeller = '69104e91-6a00-40d9-a7c9-b1571422ae43';

void main() async {
  Directory.current = File(Platform.script.toFilePath()).parent.parent.path;
  final env = loadLiveOpsStagingEnv();
  final base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  if (!base.contains(stagingRef)) {
    stderr.writeln('abort');
    exit(2);
  }
  final sb = LiveOpsStagingClient(
    url: base,
    anonKey: anon,
    serviceRoleKey: service,
  );
  final buyerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerId = await sb.userIdForAccessToken(buyerJwt);
  final sellerId = await sb.userIdForAccessToken(sellerJwt);
  final buyerEmail = envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final sellerEmail = envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL');

  Map<String, String> h(String jwt) => {
        'apikey': anon,
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  Map<String, String> ha() => {
        'apikey': anon,
        'Authorization': 'Bearer $anon',
        'Content-Type': 'application/json',
      };
  Map<String, String> hs() => {
        'apikey': service,
        'Authorization': 'Bearer $service',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Future<http.Response> rpc(String fn, Map body, String jwt) => http.post(
        Uri.parse('$base/rest/v1/rpc/$fn'),
        headers: h(jwt),
        body: jsonEncode(body),
      );

  final log = <String, dynamic>{};

  // 1) payout details: own seller, other seller, random, anon
  log['payout_test_seller'] = (await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': sellerId},
    buyerJwt,
  )).body;
  log['payout_other_seller'] = (await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': otherSeller},
    buyerJwt,
  )).body;
  log['payout_random'] = (await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'},
    buyerJwt,
  )).body;
  log['payout_anon'] = (await http.post(
    Uri.parse('$base/rest/v1/rpc/batata_seller_direct_payment_details'),
    headers: ha(),
    body: jsonEncode({'p_seller_id': sellerId}),
  )).body;
  log['payout_as_seller_self'] = (await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': sellerId},
    sellerJwt,
  )).body;

  // 2) stripe events cross-user
  final evAll = await http.get(
    Uri.parse('$base/rest/v1/stripe_checkout_events?select=id,buyer_id,session_id,order_id,event&limit=20'),
    headers: h(buyerJwt),
  );
  log['stripe_evt_http'] = evAll.statusCode;
  log['stripe_evt_sample'] = evAll.body.substring(0, evAll.body.length.clamp(0, 1200));
  List evRows = [];
  try {
    evRows = jsonDecode(evAll.body) as List;
  } catch (_) {}
  final foreign = evRows.where((e) {
    if (e is! Map) return false;
    final bid = e['buyer_id']?.toString();
    return bid != null && bid.isNotEmpty && bid != buyerId;
  }).toList();
  log['stripe_evt_foreign_count'] = foreign.length;
  log['stripe_evt_foreign'] = jsonEncode(foreign.take(3).toList());
  final withSession = evRows.where((e) {
    if (e is! Map) return false;
    final s = e['session_id']?.toString() ?? '';
    return s.startsWith('cs_');
  }).toList();
  log['stripe_evt_with_session'] = withSession.length;

  // 3) email oracle
  log['email_seller'] = (await rpc(
    'batata_find_user_id_by_email',
    {'p_email': sellerEmail},
    buyerJwt,
  )).body;
  log['email_buyer'] = (await rpc(
    'batata_find_user_id_by_email',
    {'p_email': buyerEmail},
    buyerJwt,
  )).body;
  log['email_unknown'] = (await rpc(
    'batata_find_user_id_by_email',
    {'p_email': 'nobody-cego-c@example.invalid'},
    buyerJwt,
  )).body;
  log['email_as_seller_of_buyer'] = (await rpc(
    'batata_find_user_id_by_email',
    {'p_email': buyerEmail},
    sellerJwt,
  )).body;

  // 4) refund real seller order as buyer
  final paid = await http.get(
    Uri.parse(
      '$base/rest/v1/orders?select=id,status,seller_id,buyer_id&seller_id=eq.$sellerId&status=eq.pago&limit=1',
    ),
    headers: hs(),
  );
  String? paidId;
  try {
    final d = jsonDecode(paid.body);
    if (d is List && d.isNotEmpty) paidId = d[0]['id']?.toString();
  } catch (_) {}
  if (paidId != null) {
    final ref = await http.post(
      Uri.parse('$base/functions/v1/refund-order'),
      headers: h(buyerJwt),
      body: jsonEncode({'order_id': paidId}),
    );
    log['refund_buyer_on_seller_order'] = '${ref.statusCode} ${ref.body}';
  } else {
    log['refund_buyer_on_seller_order'] = 'no paid order';
  }

  // 5) anon select orders / wallets
  log['anon_orders'] = (await http.get(
    Uri.parse('$base/rest/v1/orders?select=id&limit=3'),
    headers: ha(),
  )).body;
  log['anon_wallets'] = (await http.get(
    Uri.parse('$base/rest/v1/wallets?select=id,balance&limit=3'),
    headers: ha(),
  )).body;
  log['anon_products'] = (await http.get(
    Uri.parse('$base/rest/v1/products?select=id,price&limit=2'),
    headers: ha(),
  )).statusCode.toString();

  // 6) claim external with live_id of seller
  final lives = await http.get(
    Uri.parse(
      '$base/rest/v1/lives?select=id,seller_id&seller_id=eq.$sellerId&limit=1',
    ),
    headers: hs(),
  );
  String? liveId;
  try {
    final d = jsonDecode(lives.body);
    if (d is List && d.isNotEmpty) liveId = d[0]['id']?.toString();
  } catch (_) {}
  if (liveId != null) {
    log['claim_ext'] = (await rpc(
      'batata_claim_external_reservations',
      {'p_live_id': liveId},
      buyerJwt,
    )).body;
  } else {
    log['claim_ext'] = 'no live';
  }

  // 7) prize order overloads — try names from hint
  for (final fn in [
    'batata_create_raffle_prize_order',
    'batata_create_raffle_prize_orders',
  ]) {
    final r = await rpc(fn, {'p_raffle_id': '2e71ebba-3f7b-420f-a5fb-bea2e4fc59a4'}, buyerJwt);
    log['prize_$fn'] = '${r.statusCode} ${r.body.substring(0, r.body.length.clamp(0, 250))}';
  }

  // 8) schema dump via service run_sql_string variants
  for (final name in ['run_sql_string', 'run_sql', 'exec_sql']) {
    final r = await http.post(
      Uri.parse('$base/rest/v1/rpc/$name'),
      headers: hs(),
      body: jsonEncode({'sql': 'select 1 as x'}),
    );
    log['svc_$name'] = '${r.statusCode} ${r.body.substring(0, r.body.length.clamp(0, 180))}';
  }

  // 9) storage buckets as service (auditor) vs buyer
  log['buckets_svc'] = (await http.get(
    Uri.parse('$base/storage/v1/bucket'),
    headers: hs(),
  )).body.clampLen();
  log['buckets_buyer'] = (await http.get(
    Uri.parse('$base/storage/v1/bucket'),
    headers: h(buyerJwt),
  )).body;

  // 10) cleanup leftover reserva_pendente from pass1 with price_total 0.01 / 0.5
  final leftovers = await http.get(
    Uri.parse(
      '$base/rest/v1/orders?select=id,status,price_total,created_at&buyer_id=eq.$buyerId&status=eq.reserva_pendente&created_at=gte.2026-08-29T12:30:00Z',
    ),
    headers: hs(),
  );
  log['leftovers'] = leftovers.body;
  try {
    final d = jsonDecode(leftovers.body);
    if (d is List) {
      for (final e in d) {
        final id = e['id'];
        await http.patch(
          Uri.parse('$base/rest/v1/orders?id=eq.$id'),
          headers: hs(),
          body: jsonEncode({'status': 'cancelado', 'is_reservation': false}),
        );
      }
      log['leftovers_cancelled'] = d.length;
    }
  } catch (_) {}

  // 11) pending tip created in pass1
  final tips = await http.get(
    Uri.parse(
      '$base/rest/v1/live_tips?select=id,status,amount,buyer_id&buyer_id=eq.$buyerId&status=eq.pending&order=created_at.desc&limit=5',
    ),
    headers: hs(),
  );
  log['pending_tips'] = tips.body;

  // 12) SELECT reservations of others
  final resv = await http.get(
    Uri.parse(
      '$base/rest/v1/live_reservation_requests?select=id,buyer_id,status&buyer_id=neq.$buyerId&limit=5',
    ),
    headers: h(buyerJwt),
  );
  log['resv_others'] = '${resv.statusCode} ${resv.body.substring(0, resv.body.length.clamp(0, 400))}';

  // 13) profiles of others
  final prof = await http.get(
    Uri.parse(
      '$base/rest/v1/profiles?select=id,full_name,phone,email,user_type&id=eq.$sellerId',
    ),
    headers: h(buyerJwt),
  );
  log['profile_seller'] = '${prof.statusCode} ${prof.body}';

  final out = File('tool/reports/redteam_cego_c_20260829/pass2.json');
  out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(log));
  stdout.writeln(out.path);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(log));
}

extension on String {
  String clampLen([int n = 800]) => length <= n ? this : substring(0, n);
}
