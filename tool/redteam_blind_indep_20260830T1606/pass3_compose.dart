// Independent blind Red Team — PASS 3 composition / races / pairing / capture.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

const stamp = 'RTI1606P3';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

late String url, anon, svc, buyerId, sellerId, buyerJwt, sellerJwt, helperId, helperJwt;
late LiveOpsStagingClient admin;
final matrix = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];
final races = <Map<String, dynamic>>[];
final stripe = <Map<String, dynamic>>[];

void rec(String surface, String attack, String ident, String result) {
  matrix.add({
    'surface': surface,
    'attack': attack,
    'identity': ident,
    'result': result.length > 2200 ? '${result.substring(0, 2200)}…' : result,
  });
}

void finding({
  required String id,
  required String sev,
  required String title,
  required String actor,
  required String pre,
  required String repro,
  required String impact,
}) {
  findings.add({
    'id': id,
    'severity': sev,
    'title': title,
    'actor': actor,
    'preconditions': pre,
    'reproduction': repro,
    'impact': impact,
    'estado': 'OPEN',
  });
}

Map<String, String> h(String? jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer ${jwt ?? anon}',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Future<http.Response> rest(String method, String path, {String? jwt, Object? body}) async {
  final uri = Uri.parse('$url$path');
  final headers = h(jwt);
  final enc = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'GET':
      return http.get(uri, headers: headers);
    case 'POST':
      return http.post(uri, headers: headers, body: enc);
    case 'PATCH':
      return http.patch(uri, headers: headers, body: enc);
    default:
      throw ArgumentError(method);
  }
}

Future<http.Response> rpc(String fn, Map<String, dynamic> p, {String? jwt}) =>
    rest('POST', '/rest/v1/rpc/$fn', jwt: jwt, body: p);

Future<http.Response> edge(String fn, {String? jwt, Object? body, String qs = '', String method = 'POST'}) async {
  final uri = Uri.parse('$url/functions/v1/$fn$qs');
  if (method == 'GET') return http.get(uri, headers: h(jwt));
  return http.post(uri, headers: h(jwt), body: body == null ? null : jsonEncode(body));
}

String brief(http.Response r) {
  var b = r.body.replaceAll(RegExp(r'\s+'), ' ');
  if (b.length > 320) b = '${b.substring(0, 320)}…';
  return '${r.statusCode} $b';
}

bool ok2(int s) => s >= 200 && s < 300;

Map<String, dynamic>? rowOf(http.Response r) {
  if (!ok2(r.statusCode) || r.body.isEmpty || r.body == '[]') return null;
  final p = jsonDecode(r.body);
  if (p is List && p.isNotEmpty) return Map<String, dynamic>.from(p.first as Map);
  if (p is Map) return Map<String, dynamic>.from(p);
  return null;
}

Future<Map<String, dynamic>> observeOrder(String id) async {
  final rows = await admin.select('orders', filter: 'id=eq.$id', limit: 1);
  if (rows.isEmpty) return {};
  final o = rows.first;
  return {
    'id': o['id'],
    'status': o['status'],
    'price_total': o['price_total'],
    'qty': o['quantity'],
    'contract_unit_cents': o['contract_unit_cents'],
    'amount_paid_cents': o['amount_paid_cents'],
    'pi': o['stripe_payment_intent_id'],
    'cs': o['stripe_checkout_session_id'],
    'refund': o['stripe_refund_id'],
    'pm': o['payment_method'],
    'wallet_release': o['wallet_release_processed_at'],
    'wallet_refund': o['wallet_refund_processed_at'],
  };
}

Future<Map<String, dynamic>> observeProduct(String id) async {
  final rows = await admin.select('products', filter: 'id=eq.$id', limit: 1);
  if (rows.isEmpty) return {};
  final p = rows.first;
  return {'qty': p['quantity'], 'price': p['price'], 'sold': p['is_sold']};
}

Future<num> walletOf(String uid) async {
  final rows = await admin.select('wallets', filter: 'id=eq.$uid', limit: 1);
  if (rows.isEmpty) return 0;
  return num.tryParse('${rows.first['balance']}') ?? 0;
}

Future<Map<String, dynamic>> insertProduct({required num price, required int qty}) {
  return admin.insert('products', {
    'seller_id': sellerId,
    'title': '$stamp ${DateTime.now().millisecondsSinceEpoch}',
    'price': price,
    'quantity': qty,
    'ref_code': '$stamp-${Random().nextInt(1 << 20)}',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': [],
  });
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) exit(2);
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  admin = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  buyerJwt = await admin.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  sellerJwt = await admin.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final helperEmail = 'rti1606p3-${DateTime.now().millisecondsSinceEpoch}@fleaber.invalid';
  helperId = await admin.createAdminUser(email: helperEmail, password: 'Rti1606!Help#x');
  helperJwt = await admin.signIn(email: helperEmail, password: 'Rti1606!Help#x');
  Directory('tool/redteam_blind_indep_20260830T1606/out').createSync(recursive: true);

  await staffAndPairing();
  await catalogAfterContract();
  await dualSessionCapturePrep();
  await privilegedRpcs();
  await liveFlows();
  await walletTip();
  await storageDeep();
  await refundUnpaidAndPaid();
  await waitlistQueue();

  File('tool/redteam_blind_indep_20260830T1606/out/pass3.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'pass': 3,
      'project': projectMust,
      'at': DateTime.now().toUtc().toIso8601String(),
      'matrix': matrix,
      'findings': findings,
      'races': races,
      'stripe': stripe,
    }),
  );
  stdout.writeln('PASS3 done matrix=${matrix.length} findings=${findings.length}');
}

Future<void> staffAndPairing() async {
  for (final table in [
    'seller_staff',
    'live_staff',
    'seller_helpers',
    'staff_members',
    'seller_team',
  ]) {
    final r = await rest('GET', '/rest/v1/$table?select=*&limit=5', jwt: buyerJwt);
    rec(table, 'SELECT buyer', 'buyer', brief(r));
    final s = await admin.select(table, limit: 5).catchError((e) {
      rec(table, 'svc select', 'svc', '$e');
      return <Map<String, dynamic>>[];
    });
    rec(table, 'svc', 'svc', jsonEncode(s.take(5).toList()));
  }

  final lives = await admin.select('lives', filter: 'seller_id=eq.$sellerId', limit: 2);
  if (lives.isEmpty) return;
  final liveId = lives.first['id'].toString();

  final pairH = await rpc('batata_ps_create_pairing', {
    'p_live_id': liveId,
    'p_device_id_hint': 'rti-helper-pc',
  }, jwt: helperJwt);
  rec('rpc/batata_ps_create_pairing', 'helper on seller live', 'helper', brief(pairH));
  if (ok2(pairH.statusCode) && pairH.body.contains('"ok": true')) {
    finding(
      id: 'P1-PS-PAIRING-CROSS-USER',
      sev: 'P1',
      title: 'Unaffiliated helper created PS pairing on seller live',
      actor: 'helper',
      pre: 'Fresh user, known live_id of seller',
      repro: 'batata_ps_create_pairing → ${pairH.body}',
      impact: 'Device token for seller live; OCR ingest hijack',
    );
    try {
      final m = jsonDecode(pairH.body) as Map;
      final code = m['code']?.toString();
      if (code != null) {
        final claim = await edge('ps-pairing-claim', jwt: anon, body: {
          'code': code,
          'device_id': 'rti-attacker',
        });
        rec('edge/ps-pairing-claim', 'anon claim helper code', 'anon', brief(claim));
        Map<String, dynamic>? cm;
        try {
          cm = jsonDecode(claim.body) as Map<String, dynamic>;
        } catch (_) {}
        final token = cm?['device_token']?.toString() ?? cm?['token']?.toString();
        if (token != null && token.isNotEmpty) {
          final items = await admin.select('live_items', filter: 'live_id=eq.$liveId', limit: 1);
          final ingest = await http.post(
            Uri.parse('$url/functions/v1/ingest-ocr-reservation'),
            headers: {
              'apikey': anon,
              'Authorization': 'Bearer $anon',
              'Content-Type': 'application/json',
              'x-device-token': token,
            },
            body: jsonEncode({
              'live_id': liveId,
              'ocr_line_hash': 'rti1606hashxxxx',
              'detected_at': DateTime.now().toUtc().toIso8601String(),
              'ref_number': 1,
              'requested_qty': 1,
              'external_display_name': 'Attacker',
              'ocr_raw_line': '1 Attacker',
            }),
          );
          rec('edge/ingest-ocr-reservation', 'stolen token ingest', 'anon', brief(ingest));
        }
      }
    } catch (e) {
      rec('pairing', 'claim/ingest error', 'anon', '$e');
    }
  }

  final pairB = await rpc('batata_ps_create_pairing', {
    'p_live_id': liveId,
  }, jwt: buyerJwt);
  rec('rpc/batata_ps_create_pairing', 'buyer on seller live', 'buyer', brief(pairB));

  final tok = await rpc('batata_create_seller_device_token', {
    'p_seller_id': sellerId,
  }, jwt: helperJwt);
  rec('rpc/batata_create_seller_device_token', 'helper for seller', 'helper', brief(tok));
}

Future<void> catalogAfterContract() async {
  final prod = await insertProduct(price: 20, qty: 2);
  final pid = prod['id'].toString();
  final o = await rest('POST', '/rest/v1/orders', jwt: buyerJwt, body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'price_total': 20,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  rec('orders', 'INSERT before catalog drop', 'buyer', brief(o));
  final oid = rowOf(o)?['id']?.toString();
  if (oid == null) return;
  rec('orders', 'contract before drop', 'svc', jsonEncode(await observeOrder(oid)));
  await admin.patch('products', 'id=eq.$pid', {'price': 1.00});
  rec('products', 'seller catalog to 1€', 'svc', jsonEncode(await observeProduct(pid)));
  final pay = await edge('create-payment-intent', jwt: buyerJwt, body: {
    'order_id': oid,
    'buyer_id': buyerId,
    'shipping_method': 'entrega em mão',
  });
  rec('edge/create-payment-intent', 'after catalog 1€', 'buyer', brief(pay));
  try {
    final m = jsonDecode(pay.body) as Map;
    stripe.add({
      'label': 'catalog_drop',
      'amount_total': m['amount_total'] ?? m['server_amount_cents'],
      'session': m['checkoutSessionId'],
    });
    final amt = m['amount_total'] ?? m['server_amount_cents'];
    if (amt is num && amt < 1500) {
      finding(
        id: 'P1-CATALOG-RETRO-PRICE',
        sev: 'P1',
        title: 'Checkout used post-accept catalog price',
        actor: 'seller collusion / catalog race',
        pre: 'Order sealed at 20€ then product.price=1',
        repro: 'create-payment-intent amount=$amt (expect ~2000+fees of original)',
        impact: 'Contract K broken: later catalog change alters charge',
      );
    }
  } catch (_) {}
}

Future<void> dualSessionCapturePrep() async {
  final prod = await insertProduct(price: 8.5, qty: 1);
  final o = await rest('POST', '/rest/v1/orders', jwt: buyerJwt, body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': prod['id'],
    'price_total': 8.5,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  final oid = rowOf(o)?['id']?.toString();
  if (oid == null) return;
  final body = {
    'order_id': oid,
    'buyer_id': buyerId,
    'shipping_method': 'entrega em mão',
  };
  final rs = await Future.wait([
    edge('create-payment-intent', jwt: buyerJwt, body: body),
    edge('create-payment-intent', jwt: buyerJwt, body: body),
  ]);
  rec('edge/create-payment-intent', 'parallel A', 'buyer', brief(rs[0]));
  rec('edge/create-payment-intent', 'parallel B', 'buyer', brief(rs[1]));
  String? ua, ub, sa, sb;
  try {
    final ma = jsonDecode(rs[0].body) as Map;
    final mb = jsonDecode(rs[1].body) as Map;
    ua = ma['checkoutUrl']?.toString();
    ub = mb['checkoutUrl']?.toString();
    sa = ma['checkoutSessionId']?.toString();
    sb = mb['checkoutSessionId']?.toString();
  } catch (_) {}
  File('tool/redteam_blind_indep_20260830T1606/out/dual_sessions.json').writeAsStringSync(
    jsonEncode({
      'order_id': oid,
      'product_id': prod['id'],
      'session_a': sa,
      'session_b': sb,
      'url_a': ua,
      'url_b': ub,
      'same': sa == sb,
    }),
  );
  rec('stripe', 'dual session file', 'buyer', 'same=${sa == sb} a=$sa b=$sb');
  races.add({'name': 'dual_parallel_session', 'same': sa == sb, 'a': sa, 'b': sb, 'order': oid});
}

Future<void> privilegedRpcs() async {
  final attempts = <String, Map<String, dynamic>>{
    'batata_clawback_seller_wallet_for_order': {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    'batata_debit_wallet_once': {
      'p_wallet_id': sellerId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 1,
      'p_type': 'debito',
      'p_description': 'x',
    },
    'batata_admin_resolve_dispute': {
      'p_dispute_id': '00000000-0000-0000-0000-000000000001',
      'p_action': 'refund',
    },
    'batata_claim_external_reservations': {'p_live_id': '00000000-0000-0000-0000-000000000001'},
    'batata_confirm_ps_reservation': {'p_reservation_id': '00000000-0000-0000-0000-000000000001'},
    'batata_award_live_raffle_tickets': {
      'p_raffle_id': '00000000-0000-0000-0000-000000000001',
      'p_buyer_id': buyerId,
      'p_tickets': 10,
    },
    'batata_create_raffle_prize_order': {'p_raffle_id': '00000000-0000-0000-0000-000000000001'},
    'batata_draw_live_raffle_winners': {'p_raffle_id': '00000000-0000-0000-0000-000000000001'},
    'batata_ensure_wallet': {'p_user_id': helperId},
    'batata_send_live_tip_from_wallet': {
      'p_live_id': '00000000-0000-0000-0000-000000000001',
      'p_seller_id': sellerId,
      'p_amount': 1,
    },
  };
  for (final e in attempts.entries) {
    rec('rpc/${e.key}', jsonEncode(e.value), 'buyer', brief(await rpc(e.key, e.value, jwt: buyerJwt)));
    rec('rpc/${e.key}', jsonEncode(e.value), 'seller', brief(await rpc(e.key, e.value, jwt: sellerJwt)));
  }
}

Future<void> liveFlows() async {
  final lives = await admin.select('lives', filter: 'seller_id=eq.$sellerId', limit: 1);
  if (lives.isEmpty) return;
  final liveId = lives.first['id'].toString();
  final items = await admin.select('live_items', filter: 'live_id=eq.$liveId', limit: 3);
  if (items.isEmpty) return;
  final li = items.first;

  for (final fn in [
    'batata_live_bag_add_item',
    'batata_add_live_bag_item',
    'batata_live_reservation_add',
    'batata_request_live_reservation',
  ]) {
    rec('rpc/$fn', 'probe', 'buyer', brief(await rpc(fn, {
      'p_live_item_id': li['id'],
      'p_qty': 1,
    }, jwt: buyerJwt)));
  }

  final req = await rest('POST', '/rest/v1/live_reservation_requests', jwt: buyerJwt, body: {
    'live_id': liveId,
    'live_item_id': li['id'],
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'requested_qty': 1,
    'status': 'pending',
  });
  rec('live_reservation_requests', 'INSERT', 'buyer', brief(req));
  final rid = rowOf(req)?['id']?.toString();
  if (rid != null) {
    final accH = await rpc('batata_process_live_reservation_request', {
      'p_request_id': rid,
      'p_action': 'accept',
    }, jwt: helperJwt);
    rec('rpc/batata_process_live_reservation_request', 'helper accept', 'helper', brief(accH));
    final accS = await rpc('batata_process_live_reservation_request', {
      'p_request_id': rid,
      'p_action': 'accept',
    }, jwt: sellerJwt);
    rec('rpc/batata_process_live_reservation_request', 'seller accept', 'seller', brief(accS));
  }

  final raffle = await rpc('batata_create_live_raffle', {
    'p_live_id': liveId,
    'p_prize_live_item_id': li['id'],
  }, jwt: helperJwt);
  rec('rpc/batata_create_live_raffle', 'helper', 'helper', brief(raffle));
  final raffleB = await rpc('batata_create_live_raffle', {
    'p_live_id': liveId,
    'p_prize_live_item_id': li['id'],
  }, jwt: buyerJwt);
  rec('rpc/batata_create_live_raffle', 'buyer', 'buyer', brief(raffleB));
}

Future<void> walletTip() async {
  final lives = await admin.select('lives', filter: 'seller_id=eq.$sellerId', limit: 1);
  if (lives.isEmpty) return;
  final liveId = lives.first['id'].toString();
  final w0b = await walletOf(buyerId);
  final w0s = await walletOf(sellerId);
  final tip = await rpc('batata_send_live_tip_from_wallet', {
    'p_live_id': liveId,
    'p_seller_id': sellerId,
    'p_amount': 1,
  }, jwt: buyerJwt);
  rec('rpc/batata_send_live_tip_from_wallet', '1€', 'buyer', brief(tip));
  rec('wallets', 'after tip', 'svc', jsonEncode({
    'buyer0': w0b,
    'buyer1': await walletOf(buyerId),
    'seller0': w0s,
    'seller1': await walletOf(sellerId),
  }));
  final self = await rpc('batata_send_live_tip_from_wallet', {
    'p_live_id': liveId,
    'p_seller_id': buyerId,
    'p_amount': 1,
  }, jwt: buyerJwt);
  rec('rpc/batata_send_live_tip_from_wallet', 'self seller', 'buyer', brief(self));
  final wrong = await rpc('batata_send_live_tip_from_wallet', {
    'p_live_id': liveId,
    'p_seller_id': helperId,
    'p_amount': 1,
  }, jwt: buyerJwt);
  rec('rpc/batata_send_live_tip_from_wallet', 'wrong seller', 'buyer', brief(wrong));
}

Future<void> storageDeep() async {
  final listed = await http.post(
    Uri.parse('$url/storage/v1/object/list/fleaber_private'),
    headers: h(buyerJwt),
    body: jsonEncode({'prefix': 'order_proofs/', 'limit': 20}),
  );
  rec('storage/fleaber_private', 'list order_proofs buyer', 'buyer', brief(listed));
  final listedH = await http.post(
    Uri.parse('$url/storage/v1/object/list/fleaber_private'),
    headers: h(helperJwt),
    body: jsonEncode({'prefix': 'order_proofs/', 'limit': 20}),
  );
  rec('storage/fleaber_private', 'list order_proofs helper', 'helper', brief(listedH));
  final disp = await http.post(
    Uri.parse('$url/storage/v1/object/list/fleaber_private'),
    headers: h(helperJwt),
    body: jsonEncode({'prefix': 'order_disputes/', 'limit': 20}),
  );
  rec('storage/fleaber_private', 'list disputes helper', 'helper', brief(disp));

  // Try download known-looking path from pass1 dispute
  final guess = await http.get(
    Uri.parse(
      '$url/storage/v1/object/fleaber_private/order_disputes/$buyerId/test',
    ),
    headers: h(helperJwt),
  );
  rec('storage/fleaber_private', 'GET dispute guess helper', 'helper', brief(guess));
}

Future<void> refundUnpaidAndPaid() async {
  final ref = await edge('refund-order', jwt: sellerJwt, body: {
    'order_id': '00000000-0000-0000-0000-000000000001',
  });
  rec('edge/refund-order', 'seller fake id', 'seller', brief(ref));
  final refB = await edge('refund-order', jwt: buyerJwt, body: {
    'order_id': '52e7bcbb-3026-4012-ab4d-2e973e45d56b',
  });
  rec('edge/refund-order', 'buyer MB WAY concluido', 'buyer', brief(refB));
}

Future<void> waitlistQueue() async {
  for (final table in ['live_waitlist', 'waitlist', 'live_item_queue', 'reservation_queue']) {
    rec(table, 'SELECT', 'buyer', brief(await rest('GET', '/rest/v1/$table?select=*&limit=3', jwt: buyerJwt)));
  }
}
