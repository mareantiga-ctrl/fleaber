// Independent blind Red Team — PASS 1 coverage.
// Staging fxdknzrqjenzqcvnwqqq only. No production. No Fase 4. No fixes.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

const stamp = 'RTI1606';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

late String url;
late String anon;
late String svc;
late String buyerId;
late String sellerId;
late String buyerJwt;
late String sellerJwt;
late String helperId;
late String helperJwt;
late LiveOpsStagingClient admin;

final findings = <Map<String, dynamic>>[];
final matrix = <Map<String, dynamic>>[];
final rpcHits = <Map<String, dynamic>>[];
final tables = <String>[];
final rpcs = <String>[];

void rec(
  String surface,
  String attack,
  String ident,
  String result, {
  String impact = '',
  String sev = 'info',
  Object? evidence,
}) {
  matrix.add({
    'surface': surface,
    'attack': attack,
    'identity': ident,
    'result': result,
    'impact': impact,
    'severity': sev,
    'evidence': _clip(evidence),
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
  String estado = 'OPEN',
}) {
  findings.add({
    'id': id,
    'severity': sev,
    'title': title,
    'actor': actor,
    'preconditions': pre,
    'reproduction': repro,
    'impact': impact,
    'estado': estado,
  });
}

Object? _clip(Object? v) {
  if (v == null) return null;
  final s = v is String ? v : jsonEncode(v);
  if (s.length <= 1800) return v is String ? v : jsonDecode(jsonEncode(v));
  return '${s.substring(0, 1800)}…';
}

Map<String, String> h(String? jwt) {
  final key = jwt == null ? anon : anon;
  final tok = jwt ?? anon;
  return {
    'apikey': key,
    'Authorization': 'Bearer $tok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
}

Future<http.Response> rest(
  String method,
  String path, {
  String? jwt,
  Object? body,
  Map<String, String>? extra,
}) async {
  final headers = h(jwt);
  if (extra != null) headers.addAll(extra);
  final uri = Uri.parse('$url$path');
  final encoded = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'GET':
      return http.get(uri, headers: headers);
    case 'POST':
      return http.post(uri, headers: headers, body: encoded);
    case 'PATCH':
      return http.patch(uri, headers: headers, body: encoded);
    case 'DELETE':
      return http.delete(uri, headers: headers, body: encoded);
    default:
      throw ArgumentError(method);
  }
}

Future<http.Response> rpcRaw(
  String fn,
  Map<String, dynamic> params, {
  String? jwt,
}) {
  return rest('POST', '/rest/v1/rpc/$fn', jwt: jwt, body: params);
}

Future<http.Response> edge(
  String fn, {
  String? jwt,
  Object? body,
  String method = 'POST',
  Map<String, String>? extra,
  String qs = '',
}) async {
  final headers = <String, String>{
    'apikey': anon,
    'Authorization': 'Bearer ${jwt ?? anon}',
    'Content-Type': 'application/json',
  };
  if (extra != null) headers.addAll(extra);
  final uri = Uri.parse('$url/functions/v1/$fn$qs');
  if (method == 'GET') return http.get(uri, headers: headers);
  return http.post(uri, headers: headers, body: body == null ? null : jsonEncode(body));
}

String brief(http.Response r) {
  var b = r.body.replaceAll(RegExp(r'\s+'), ' ');
  if (b.length > 240) b = '${b.substring(0, 240)}…';
  return '${r.statusCode} $b';
}

bool ok2xx(int s) => s >= 200 && s < 300;

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) {
    stderr.writeln('REFUSED: not staging $projectMust');
    exit(2);
  }
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

  final helperEmail = 'rti1606-helper-${DateTime.now().millisecondsSinceEpoch}@fleaber.invalid';
  helperId = await admin.createAdminUser(
    email: helperEmail,
    password: 'Rti1606!Help#x',
    userMetadata: {'display_name': 'RTI1606 helper'},
  );
  try {
    await admin.patch('profiles', 'id=eq.$helperId', {
      'user_type': 'comprador',
    });
  } catch (_) {}
  helperJwt = await admin.signIn(email: helperEmail, password: 'Rti1606!Help#x');

  stdout.writeln('PASS1 signed in buyer=$buyerId seller=$sellerId helper=$helperId');
  Directory('tool/redteam_blind_indep_20260830T1606/out').createSync(recursive: true);

  await inventoryOpenApi();
  await rlsFinancial();
  await rlsPrivacy();
  await rpcPrivileged();
  await orderContractAttacks();
  await offerAttacks();
  await reviewDisputeAttacks();
  await edgeAttacks();
  await storageAttacks();
  await profileAuthority();

  final outDir = Directory('tool/redteam_blind_indep_20260830T1606/out');
  outDir.createSync(recursive: true);
  final payload = {
    'pass': 1,
    'project': projectMust,
    'stamp': stamp,
    'at': DateTime.now().toUtc().toIso8601String(),
    'tables_openapi': tables.length,
    'rpcs_openapi': rpcs.length,
    'rpcs': rpcs,
    'tables_sample': tables.take(80).toList(),
    'rpc_hits': rpcHits,
    'matrix': matrix,
    'findings': findings,
  };
  File('${outDir.path}/pass1.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(payload),
  );
  stdout.writeln(
    'PASS1 done matrix=${matrix.length} findings=${findings.length} rpcs=${rpcs.length}',
  );
}

Future<void> inventoryOpenApi() async {
  final r = await http.get(
    Uri.parse('$url/rest/v1/'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Accept': 'application/openapi+json',
    },
  );
  rec('openapi', 'GET /rest/v1/', 'anon', brief(r));
  if (!ok2xx(r.statusCode)) return;
  final spec = jsonDecode(r.body) as Map<String, dynamic>;
  final paths = spec['paths'] as Map<String, dynamic>? ?? {};
  for (final p in paths.keys) {
    if (p.startsWith('/rpc/')) {
      rpcs.add(p.substring('/rpc/'.length));
    } else if (p.startsWith('/') && p.length > 1) {
      tables.add(p.substring(1).split('?').first);
    }
  }
  rpcs.sort();
  tables.sort();
}

Future<void> tryCrud({
  required String table,
  required String ident,
  required String? jwt,
  Map<String, dynamic>? insertRow,
  String? patchFilter,
  Map<String, dynamic>? patchRow,
  String? deleteFilter,
  String selectFilter = 'select=id&limit=3',
}) async {
  final sel = await rest('GET', '/rest/v1/$table?$selectFilter', jwt: jwt);
  rec(table, 'SELECT', ident, brief(sel));
  if (insertRow != null) {
    final ins = await rest('POST', '/rest/v1/$table', jwt: jwt, body: insertRow);
    rec(table, 'INSERT', ident, brief(ins));
    if (ok2xx(ins.statusCode)) {
      finding(
        id: 'P1-$table-INSERT-$ident',
        sev: 'P2',
        title: 'INSERT $table as $ident succeeded',
        actor: ident,
        pre: 'JWT $ident',
        repro: 'POST /rest/v1/$table ${jsonEncode(insertRow)} → ${ins.statusCode}',
        impact: 'Row created: ${_clip(ins.body)}',
      );
    }
  }
  if (patchFilter != null && patchRow != null) {
    final p = await rest(
      'PATCH',
      '/rest/v1/$table?$patchFilter',
      jwt: jwt,
      body: patchRow,
    );
    rec(table, 'UPDATE $patchFilter', ident, brief(p));
    if (ok2xx(p.statusCode) && p.body.isNotEmpty && p.body != '[]') {
      finding(
        id: 'P1-$table-UPDATE-$ident',
        sev: 'P1',
        title: 'UPDATE $table as $ident persisted',
        actor: ident,
        pre: 'JWT $ident filter $patchFilter',
        repro: 'PATCH body ${jsonEncode(patchRow)} → ${p.body}',
        impact: 'Unauthorized mutation if row not owned',
      );
    }
  }
  if (deleteFilter != null) {
    final d = await rest('DELETE', '/rest/v1/$table?$deleteFilter', jwt: jwt);
    rec(table, 'DELETE $deleteFilter', ident, brief(d));
  }
}

Future<void> rlsFinancial() async {
  // Observe existing rows (service) to pick victim IDs.
  final wallets = await admin.select('wallets', limit: 3);
  final otherWallet = wallets
      .map((w) => w['id']?.toString() ?? '')
      .firstWhere((id) => id.isNotEmpty && id != buyerId && id != sellerId, orElse: () => sellerId);

  for (final e in [
    ['anon', null],
    ['buyer', buyerJwt],
    ['seller', sellerJwt],
    ['helper', helperJwt],
  ]) {
    final ident = e[0] as String;
    final jwt = e[1] as String?;
    await tryCrud(
      table: 'wallets',
      ident: ident,
      jwt: jwt,
      selectFilter: 'select=id,balance,stripe_account_id&limit=20',
      insertRow: {'id': helperId, 'balance': 9999},
      patchFilter: 'id=eq.$otherWallet',
      patchRow: {'balance': 99999.99},
    );
    await tryCrud(
      table: 'wallet_transactions',
      ident: ident,
      jwt: jwt,
      insertRow: {
        'wallet_id': buyerId,
        'amount': 500,
        'type': 'credito',
        'description': 'rti1606',
      },
    );
    await tryCrud(
      table: 'wallet_payout_ledger',
      ident: ident,
      jwt: jwt,
      selectFilter: 'select=id,user_id,amount_cents,status&limit=5',
    );
    await tryCrud(
      table: 'orders',
      ident: ident,
      jwt: jwt,
      selectFilter:
          'select=id,buyer_id,seller_id,status,price_total,amount_paid_cents,stripe_payment_intent_id,stripe_checkout_session_id&limit=5',
    );
    await tryCrud(
      table: 'products',
      ident: ident,
      jwt: jwt,
      selectFilter: 'select=id,seller_id,price,quantity&limit=5',
    );
  }

  // Cross-user order financial patch (buyer patches seller's or other's order).
  final alienOrders = await admin.select(
    'orders',
    filter: 'buyer_id=neq.$buyerId&status=neq.cancelled',
    limit: 3,
  );
  if (alienOrders.isNotEmpty) {
    final oid = alienOrders.first['id'].toString();
    for (final field in [
      {'status': 'pago'},
      {'status': 'concluido'},
      {'price_total': 0.01},
      {'amount_paid_cents': 1},
      {'stripe_payment_intent_id': 'pi_fake_rti1606'},
      {'stripe_refund_id': 're_fake'},
      {'quantity': 99},
      {'contract_unit_cents': 1},
    ]) {
      final p = await rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$oid',
        jwt: buyerJwt,
        body: field,
      );
      rec('orders', 'buyer PATCH alien $field', 'buyer', brief(p));
      final after = await admin.select('orders', filter: 'id=eq.$oid', limit: 1);
      rec('orders', 'observe after $field', 'svc', jsonEncode(after.isEmpty ? {} : {
        'status': after.first['status'],
        'price_total': after.first['price_total'],
        'amount_paid_cents': after.first['amount_paid_cents'],
        'pi': after.first['stripe_payment_intent_id'],
        'qty': after.first['quantity'],
      }));
      if (ok2xx(p.statusCode) && p.body.isNotEmpty && p.body != '[]') {
        finding(
          id: 'P0-ORDER-PATCH-ALIEN',
          sev: 'P0',
          title: 'Buyer patched alien order $field',
          actor: 'buyer',
          pre: 'Valid JWT buyer, known foreign order $oid',
          repro: 'PATCH /orders?id=eq.$oid ${jsonEncode(field)} → ${p.body}',
          impact: 'Financial/state mutation on another party order',
        );
      }
    }
  }

  // Buyer patches OWN order financial fields.
  final own = await admin.insert('products', {
    'seller_id': sellerId,
    'title': '$stamp product rls',
    'price': 12.5,
    'quantity': 3,
    'ref_code': '$stamp-p',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': [],
  });
  final ownOrder = await rest('POST', '/rest/v1/orders', jwt: buyerJwt, body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': own['id'],
    'price_total': 0.50,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
    'contract_unit_cents': 1,
    'amount_paid_cents': 1,
  });
  rec('orders', 'buyer INSERT own with hostile contract', 'buyer', brief(ownOrder));
  Map<String, dynamic>? created;
  if (ok2xx(ownOrder.statusCode)) {
    final parsed = jsonDecode(ownOrder.body);
    if (parsed is List && parsed.isNotEmpty) {
      created = Map<String, dynamic>.from(parsed.first as Map);
    } else if (parsed is Map) {
      created = Map<String, dynamic>.from(parsed);
    }
  }
  if (created != null) {
    rec('orders', 'row after hostile insert', 'buyer', jsonEncode({
      'id': created['id'],
      'price_total': created['price_total'],
      'contract_unit_cents': created['contract_unit_cents'],
      'quantity': created['quantity'],
      'amount_paid_cents': created['amount_paid_cents'],
      'status': created['status'],
    }));
    final oid = created['id'].toString();
    for (final field in [
      {'status': 'pago'},
      {'status': 'concluido'},
      {'price_total': 0.01},
      {'amount_paid_cents': 99999},
      {'stripe_payment_intent_id': 'pi_buyer_set'},
      {'quantity': 50},
    ]) {
      final p = await rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$oid',
        jwt: buyerJwt,
        body: field,
      );
      rec('orders', 'buyer PATCH own $field', 'buyer', brief(p));
      final after = await admin.select('orders', filter: 'id=eq.$oid', limit: 1);
      rec('orders', 'own after $field', 'svc', jsonEncode(after.isEmpty ? {} : {
        'status': after.first['status'],
        'price_total': after.first['price_total'],
        'amount_paid_cents': after.first['amount_paid_cents'],
        'pi': after.first['stripe_payment_intent_id'],
        'qty': after.first['quantity'],
        'contract': after.first['contract_unit_cents'],
      }));
    }
    // Seller patches buyer order to pago.
    final sPatch = await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.$oid',
      jwt: sellerJwt,
      body: {'status': 'pago', 'amount_paid_cents': 1},
    );
    rec('orders', 'seller PATCH status=pago', 'seller', brief(sPatch));
  }

  // Product price/qty of other seller
  final alienProd = await admin.select(
    'products',
    filter: 'seller_id=neq.$sellerId',
    limit: 1,
  );
  if (alienProd.isNotEmpty) {
    final pid = alienProd.first['id'].toString();
    final before = alienProd.first['price'];
    final p = await rest(
      'PATCH',
      '/rest/v1/products?id=eq.$pid',
      jwt: sellerJwt,
      body: {'price': 0.01, 'quantity': 9999},
    );
    rec('products', 'seller PATCH alien product', 'seller', brief(p));
    final after = await admin.select('products', filter: 'id=eq.$pid', limit: 1);
    rec('products', 'alien after', 'svc', jsonEncode({
      'before': before,
      'after_price': after.isEmpty ? null : after.first['price'],
      'after_qty': after.isEmpty ? null : after.first['quantity'],
    }));
    if (after.isNotEmpty && after.first['price'] != before && ok2xx(p.statusCode) && p.body != '[]') {
      finding(
        id: 'P0-PRODUCT-CROSS-PRICE',
        sev: 'P0',
        title: 'Seller changed another seller product price/qty',
        actor: 'seller',
        pre: 'JWT seller, foreign product $pid',
        repro: 'PATCH price=0.01 quantity=9999',
        impact: 'Catalog authority stolen',
      );
    }
  }
}

Future<void> rlsPrivacy() async {
  for (final table in [
    'profiles',
    'chats',
    'chat_messages',
    'messages',
    'order_disputes',
    'reviews',
    'live_tips',
    'live_reservation_requests',
    'lives',
    'seller_device_tokens',
    'ps_pairing_sessions',
    'stripe_checkout_events',
    'anon_rate_limits',
    'fleaber_commissions',
    'payout_logs',
    'notifications',
  ]) {
    for (final e in [
      ['anon', null],
      ['buyer', buyerJwt],
      ['helper', helperJwt],
    ]) {
      final r = await rest(
        'GET',
        '/rest/v1/$table?select=*&limit=5',
        jwt: e[1] as String?,
      );
      rec(table, 'SELECT *', e[0] as String, brief(r));
    }
  }

  // Stream keys
  final livesBuyer = await rest(
    'GET',
    '/rest/v1/lives?select=id,seller_id,mux_stream_key,mux_live_id,status&limit=10',
    jwt: buyerJwt,
  );
  rec('lives', 'SELECT mux_stream_key', 'buyer', brief(livesBuyer));
  if (ok2xx(livesBuyer.statusCode) && livesBuyer.body.contains('mux_stream_key')) {
    final list = jsonDecode(livesBuyer.body);
    if (list is List) {
      final leaked = list.where((e) {
        final k = (e as Map)['mux_stream_key'];
        return k != null && k.toString().isNotEmpty;
      }).toList();
      if (leaked.isNotEmpty) {
        finding(
          id: 'P1-MUX-STREAM-KEY-LEAK',
          sev: 'P1',
          title: 'Buyer JWT can read mux_stream_key of lives',
          actor: 'buyer',
          pre: 'Authenticated buyer',
          repro: 'GET /lives?select=mux_stream_key',
          impact: 'Stream hijack of seller broadcasts',
        );
      }
    }
  }
}

Future<void> rpcPrivileged() async {
  final candidates = <String, Map<String, dynamic>>{
    'batata_wallet_payout_debit': {
      'p_user_id': sellerId,
      'p_amount_cents': 100,
      'p_idempotency_key': 'rti1606-debit-buyer',
    },
    'batata_wallet_payout_finish': {
      'p_idempotency_key': 'rti1606-debit-buyer',
      'p_stripe_transfer_id': 'tr_fake',
      'p_ok': true,
    },
    'batata_credit_wallet_once': {
      'p_wallet_id': buyerId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 50,
      'p_type': 'credito',
      'p_description': 'rti',
    },
    'batata_ensure_wallet': {'p_user_id': sellerId},
    'batata_settle_live_tip_from_stripe': {
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
      'p_stripe_session_id': 'cs_test_fake',
      'p_paid_amount_cents': 50000,
    },
    'batata_finalize_stripe_order_refund': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_refund_id': 're_fake',
      'p_payment_intent_id': 'pi_fake',
      'p_session_id': 'cs_fake',
      'p_amount_cents': 100,
    },
    'batata_release_seller_wallet_for_order': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_refund_buyer_wallet_for_order': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_is_admin': {},
    'batata_find_user_id_by_email': {
      'p_email': envPeekSellerEmail(),
    },
    'batata_get_my_payout_details': {},
    'batata_seller_direct_payment_details': {'p_seller_id': sellerId},
    'batata_convert_live_reservation_to_order': {
      'p_request_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_live_reservation_stripe_convert': {
      'p_request_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_mark_live_item_sold': {
      'p_live_item_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_create_raffle_prize_order': {
      'p_raffle_id': '00000000-0000-0000-0000-000000000001',
      'p_winner_id': buyerId,
    },
    'batata_draw_live_raffle_winners': {
      'p_raffle_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_ps_claim_pairing': {'p_code': '123456', 'p_device_id': 'x'},
    'batata_create_seller_device_token': {'p_seller_id': sellerId},
    'batata_send_live_tip_from_wallet': {
      'p_live_id': '00000000-0000-0000-0000-000000000001',
      'p_seller_id': sellerId,
      'p_amount': 1,
    },
    'batata_order_wallet_reembolso_cents': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_product_held_qty': {
      'p_product_id': '00000000-0000-0000-0000-000000000001',
    },
  };

  // Merge sensitive OpenAPI rpcs (avoid blasting every catalog helper).
  final interesting = RegExp(
    r'(wallet|payout|credit|settle|refund|admin|ensure_wallet|stripe|order|review|dispute|raffle|tip|pairing|device_token|convert|release|finalize|commission|ledger|stock|reservation|offer|bundle)',
    caseSensitive: false,
  );
  for (final name in rpcs) {
    if (interesting.hasMatch(name)) {
      candidates.putIfAbsent(name, () => {});
    }
  }

  for (final ident in [
    ['anon', null],
    ['buyer', buyerJwt],
    ['seller', sellerJwt],
  ]) {
    final label = ident[0] as String;
    final jwt = ident[1] as String?;
    for (final e in candidates.entries) {
      final r = await rpcRaw(e.key, e.value, jwt: jwt);
      final hit = {
        'fn': e.key,
        'ident': label,
        'status': r.statusCode,
        'body': _clip(r.body),
      };
      rpcHits.add(hit);
      final interesting = ok2xx(r.statusCode) ||
          (r.statusCode != 404 &&
              r.statusCode != 401 &&
              r.statusCode != 403 &&
              !r.body.contains('permission denied') &&
              !r.body.contains('PGRST202') &&
              !r.body.contains('not_allowed'));
      if (ok2xx(r.statusCode) || (r.statusCode == 200) || interesting && r.statusCode < 500) {
        rec('rpc/${e.key}', jsonEncode(e.value), label, brief(r),
            sev: ok2xx(r.statusCode) ? 'watch' : 'info');
      }
      // Flag privilege RPCs that JWT executed
      if (ok2xx(r.statusCode) &&
          (e.key.contains('payout') ||
              e.key.contains('credit_wallet') ||
              e.key.contains('settle_live_tip') ||
              e.key.contains('finalize_stripe') ||
              e.key.contains('ensure_wallet') && e.value['p_user_id'] == sellerId && label == 'buyer')) {
        finding(
          id: 'P0-RPC-${e.key}-$label',
          sev: 'P0',
          title: 'JWT $label executed privileged RPC ${e.key}',
          actor: label,
          pre: 'Normal JWT',
          repro: 'POST /rpc/${e.key} ${jsonEncode(e.value)} → ${r.body}',
          impact: 'Privileged financial/state function reachable by attacker JWT',
        );
      }
    }
  }
}

String envPeekSellerEmail() {
  try {
    final env = loadLiveOpsStagingEnv();
    return env['LIVE_OPS_TEST_SELLER_EMAIL'] ?? 'seller@example.com';
  } catch (_) {
    return 'seller@example.com';
  }
}

Future<void> orderContractAttacks() async {
  final prod = await admin.insert('products', {
    'seller_id': sellerId,
    'title': '$stamp contract',
    'price': 40.00,
    'quantity': 2,
    'ref_code': '$stamp-c',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': [],
  });
  final pid = prod['id'].toString();

  final variants = <Map<String, dynamic>>[
    {
      'name': 'price_total 0.50 qty 1',
      'row': {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pid,
        'price_total': 0.50,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'entrega em mão',
      },
    },
    {
      'name': 'contract_unit_cents=1',
      'row': {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pid,
        'price_total': 0.01,
        'quantity': 1,
        'contract_unit_cents': 1,
        'contract_qty': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'entrega em mão',
      },
    },
    {
      'name': 'qty 99 of stock 2',
      'row': {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pid,
        'price_total': 40,
        'quantity': 99,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'entrega em mão',
      },
    },
    {
      'name': 'payment proposta without offer',
      'row': {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pid,
        'price_total': 1.00,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'proposta aceite',
        'shipping_method': 'entrega em mão',
      },
    },
    {
      'name': 'swap buyer_id to helper',
      'row': {
        'buyer_id': helperId,
        'seller_id': sellerId,
        'product_id': pid,
        'price_total': 40,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'entrega em mão',
      },
    },
    {
      'name': 'status pago on insert',
      'row': {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pid,
        'price_total': 40,
        'quantity': 1,
        'status': 'pago',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'entrega em mão',
        'amount_paid_cents': 4000,
      },
    },
    {
      'name': 'swap seller to helper',
      'row': {
        'buyer_id': buyerId,
        'seller_id': helperId,
        'product_id': pid,
        'price_total': 40,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'entrega em mão',
      },
    },
  ];

  for (final v in variants) {
    final r = await rest('POST', '/rest/v1/orders', jwt: buyerJwt, body: v['row']);
    rec('orders', 'INSERT ${v['name']}', 'buyer', brief(r));
    if (ok2xx(r.statusCode)) {
      final parsed = jsonDecode(r.body);
      final row = parsed is List && parsed.isNotEmpty
          ? Map<String, dynamic>.from(parsed.first as Map)
          : parsed is Map
              ? Map<String, dynamic>.from(parsed)
              : <String, dynamic>{};
      rec('orders', 'sealed ${v['name']}', 'buyer', jsonEncode({
        'id': row['id'],
        'price_total': row['price_total'],
        'contract_unit_cents': row['contract_unit_cents'],
        'qty': row['quantity'],
        'status': row['status'],
        'buyer_id': row['buyer_id'],
        'seller_id': row['seller_id'],
        'amount_paid_cents': row['amount_paid_cents'],
      }));
    }
  }

  // Anon insert
  final anonIns = await rest('POST', '/rest/v1/orders', jwt: null, body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'price_total': 1,
    'quantity': 1,
    'status': 'pago',
    'payment_method': 'Pagamento na app',
  });
  rec('orders', 'INSERT anon pago', 'anon', brief(anonIns));
}

Future<void> offerAttacks() async {
  final prod = await admin.insert('products', {
    'seller_id': sellerId,
    'title': '$stamp offer',
    'price': 25.00,
    'quantity': 1,
    'ref_code': '$stamp-o',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': [],
  });
  final pid = prod['id'].toString();

  final ins = await rest('POST', '/rest/v1/product_offers', jwt: buyerJwt, body: {
    'product_id': pid,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 1.00,
    'status': 'accepted',
  });
  rec('product_offers', 'INSERT accepted amount=1', 'buyer', brief(ins));

  final pending = await rest('POST', '/rest/v1/product_offers', jwt: buyerJwt, body: {
    'product_id': pid,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 2.00,
    'status': 'pending',
  });
  rec('product_offers', 'INSERT pending', 'buyer', brief(pending));
  String? offerId;
  if (ok2xx(pending.statusCode)) {
    final parsed = jsonDecode(pending.body);
    final row = parsed is List ? parsed.first : parsed;
    offerId = (row as Map)['id']?.toString();
  }
  if (offerId != null) {
    final selfAccept = await rest(
      'PATCH',
      '/rest/v1/product_offers?id=eq.$offerId',
      jwt: buyerJwt,
      body: {'status': 'accepted', 'amount': 1.00},
    );
    rec('product_offers', 'buyer self-accept', 'buyer', brief(selfAccept));
    final sellerAccept = await rest(
      'PATCH',
      '/rest/v1/product_offers?id=eq.$offerId',
      jwt: sellerJwt,
      body: {'status': 'accepted'},
    );
    rec('product_offers', 'seller accept', 'seller', brief(sellerAccept));
    final mutateAmt = await rest(
      'PATCH',
      '/rest/v1/product_offers?id=eq.$offerId',
      jwt: buyerJwt,
      body: {'amount': 0.50},
    );
    rec('product_offers', 'buyer mutate amount after accept', 'buyer', brief(mutateAmt));
    final after = await admin.select('product_offers', filter: 'id=eq.$offerId', limit: 1);
    rec('product_offers', 'final row', 'svc', jsonEncode(after));

    final order = await rest('POST', '/rest/v1/orders', jwt: buyerJwt, body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'product_offer_id': offerId,
      'price_total': 0.50,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'proposta aceite',
      'shipping_method': 'entrega em mão',
    });
    rec('orders', 'INSERT with offer', 'buyer', brief(order));
    if (ok2xx(order.statusCode)) {
      final parsed = jsonDecode(order.body);
      final row = parsed is List ? parsed.first : parsed;
      rec('orders', 'offer contract', 'buyer', jsonEncode({
        'price_total': (row as Map)['price_total'],
        'contract_unit_cents': row['contract_unit_cents'],
        'product_offer_id': row['product_offer_id'],
      }));
    }
  }
}

Future<void> reviewDisputeAttacks() async {
  // Forge review without order
  final rev = await rest('POST', '/rest/v1/reviews', jwt: buyerJwt, body: {
    'reviewer_id': buyerId,
    'reviewee_id': sellerId,
    'rating': 1,
    'comment': 'rti1606 forge',
    'role': 'buyer',
  });
  rec('reviews', 'INSERT without order', 'buyer', brief(rev));

  final revOther = await rest('POST', '/rest/v1/reviews', jwt: buyerJwt, body: {
    'reviewer_id': helperId,
    'reviewee_id': sellerId,
    'rating': 5,
    'comment': 'rti impersonate',
    'role': 'buyer',
  });
  rec('reviews', 'INSERT as helper identity', 'buyer', brief(revOther));

  final disp = await rest('POST', '/rest/v1/order_disputes', jwt: buyerJwt, body: {
    'order_id': '00000000-0000-0000-0000-000000000001',
    'buyer_id': buyerId,
    'reason': 'em_falta',
    'description': 'rti',
  });
  rec('order_disputes', 'INSERT fake order', 'buyer', brief(disp));
}

Future<void> edgeAttacks() async {
  final edges = [
    'create-payment-intent',
    'refund-order',
    'create-connect-account',
    'create-live-tip-checkout',
    'stripe-webhook',
    'sec-fase2-e2e-oversell',
    'delete-test-account',
    'ingest-ocr-reservation',
    'ps-pairing-claim',
    'create-mux-live',
    'complete-mux-live',
    'livekit-mux-publish',
    'send-sms-bulkgate',
    'meta-data-deletion',
    'resolve-mux-playback',
    'ps-panel-log',
    'ps-heartbeat',
    'livekit-egress-cleanup',
  ];

  for (final fn in edges) {
    final anonR = await edge(fn, jwt: null, body: {});
    rec('edge/$fn', 'POST empty', 'anon', brief(anonR));
    final buyerR = await edge(fn, jwt: buyerJwt, body: {});
    rec('edge/$fn', 'POST empty', 'buyer', brief(buyerR));
  }

  // Hostile payment intent
  final prod = await admin.insert('products', {
    'seller_id': sellerId,
    'title': '$stamp pay',
    'price': 30.00,
    'quantity': 1,
    'ref_code': '$stamp-pay',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': [],
  });
  final orderR = await rest('POST', '/rest/v1/orders', jwt: buyerJwt, body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': prod['id'],
    'price_total': 0.50,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  rec('orders', 'INSERT for checkout', 'buyer', brief(orderR));
  String? oid;
  if (ok2xx(orderR.statusCode)) {
    final parsed = jsonDecode(orderR.body);
    final row = parsed is List ? parsed.first : parsed;
    oid = (row as Map)['id']?.toString();
    rec('orders', 'checkout fixture contract', 'buyer', jsonEncode({
      'id': oid,
      'price_total': row['price_total'],
      'contract_unit_cents': row['contract_unit_cents'],
    }));
  }
  if (oid != null) {
    final pay = await edge('create-payment-intent', jwt: buyerJwt, body: {
      'order_id': oid,
      'amount': 50,
      'quantity': 1,
      'product_id': prod['id'],
      'item_price': 0.5,
    });
    rec('edge/create-payment-intent', 'hostile amount 50 cents', 'buyer', brief(pay));
    File('tool/redteam_blind_indep_20260830T1606/out/pay_hostile.json')
        .writeAsStringSync(pay.body);

    final payOther = await edge('create-payment-intent', jwt: helperJwt, body: {
      'order_id': oid,
    });
    rec('edge/create-payment-intent', 'helper pays buyer order', 'helper', brief(payOther));

    final paySeller = await edge('create-payment-intent', jwt: sellerJwt, body: {
      'order_id': oid,
      'amount': 50,
    });
    rec('edge/create-payment-intent', 'seller checkout buyer order', 'seller', brief(paySeller));
  }

  // Refund as buyer
  final refB = await edge('refund-order', jwt: buyerJwt, body: {'order_id': oid});
  rec('edge/refund-order', 'buyer refund', 'buyer', brief(refB));
  final refS = await edge('refund-order', jwt: sellerJwt, body: {'order_id': oid});
  rec('edge/refund-order', 'seller refund unpaid', 'seller', brief(refS));

  // Payout other user
  final po = await edge('create-connect-account', jwt: buyerJwt, body: {
    'user_id': sellerId,
    'amount': 100,
  });
  rec('edge/create-connect-account', 'buyer payout as seller amount 100c', 'buyer', brief(po));

  final poNeg = await edge('create-connect-account', jwt: sellerJwt, body: {
    'amount': -500,
  });
  rec('edge/create-connect-account', 'negative amount', 'seller', brief(poNeg));

  // Webhook unsigned
  final wh = await edge('stripe-webhook', jwt: anon, body: {
    'type': 'checkout.session.completed',
    'data': {
      'object': {'id': 'cs_test_fake', 'payment_status': 'paid'}
    }
  });
  rec('edge/stripe-webhook', 'unsigned event', 'anon', brief(wh));

  // Settle GET without paid session
  final settle = await edge(
    'create-payment-intent',
    jwt: anon,
    method: 'GET',
    qs: '?checkout_return=success&session_id=cs_test_not_real',
  );
  rec('edge/create-payment-intent', 'GET settle fake session', 'anon', brief(settle));

  // fase2 e2e
  final e2e = await edge('sec-fase2-e2e-oversell', jwt: buyerJwt, body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'probe': 'setup_paid_bag',
  });
  rec('edge/sec-fase2-e2e-oversell', 'buyer JWT setup_paid_bag', 'buyer', brief(e2e));

  // Mux as buyer
  final mux = await edge('create-mux-live', jwt: buyerJwt, body: {
    'title': 'RTI1606 hijack stream',
  });
  rec('edge/create-mux-live', 'buyer create live', 'buyer', brief(mux));

  // Tip with foreign seller/live mismatch later in pass2
  final tip = await edge('create-live-tip-checkout', jwt: buyerJwt, body: {
    'seller_id': sellerId,
    'amount_eur': 1,
    'live_id': '00000000-0000-0000-0000-000000000001',
    'tip_id': '00000000-0000-0000-0000-000000000002',
  });
  rec('edge/create-live-tip-checkout', 'fake live + client tip_id', 'buyer', brief(tip));

  // OCR
  final ocr = await edge('ingest-ocr-reservation', jwt: buyerJwt, body: {
    'live_id': '00000000-0000-0000-0000-000000000001',
    'ocr_line_hash': 'abcdefghijklmnop',
    'requested_qty': 99,
  });
  rec('edge/ingest-ocr-reservation', 'no device token', 'buyer', brief(ocr));

  // Pairing brute one code
  final pair = await edge('ps-pairing-claim', jwt: anon, body: {
    'code': '000000',
    'device_id': 'rti',
  });
  rec('edge/ps-pairing-claim', 'anon code 000000', 'anon', brief(pair));

  // SMS hook
  final sms = await edge('send-sms-bulkgate', jwt: anon, body: {
    'phone': '+351910000000',
    'text': 'hi',
  });
  rec('edge/send-sms-bulkgate', 'anon send', 'anon', brief(sms));

  // delete account
  final nuke = await edge('delete-test-account', jwt: buyerJwt, body: {
    'confirm': 'APAGAR TUDO',
  });
  rec('edge/delete-test-account', 'buyer nuke', 'buyer', brief(nuke));
}

Future<void> storageAttacks() async {
  for (final bucket in ['fleaber_private', 'product_images', 'avatars', 'chat_media']) {
    final r = await http.get(
      Uri.parse('$url/storage/v1/object/list/$bucket'),
      headers: h(buyerJwt),
    );
    rec('storage/$bucket', 'LIST', 'buyer', brief(r));
    final anonL = await http.get(
      Uri.parse('$url/storage/v1/object/list/$bucket'),
      headers: h(null),
    );
    rec('storage/$bucket', 'LIST', 'anon', brief(anonL));
  }

  // Try download a guessed path
  final obj = await http.get(
    Uri.parse('$url/storage/v1/object/fleaber_private/order_proofs/$buyerId/x'),
    headers: h(helperJwt),
  );
  rec('storage/fleaber_private', 'GET foreign proof path', 'helper', brief(obj));
}

Future<void> profileAuthority() async {
  final p = await rest(
    'PATCH',
    '/rest/v1/profiles?id=eq.$buyerId',
    jwt: buyerJwt,
    body: {'user_type': 'admin'},
  );
  rec('profiles', 'buyer self PATCH user_type=admin', 'buyer', brief(p));
  final after = await admin.select('profiles', filter: 'id=eq.$buyerId', limit: 1);
  rec('profiles', 'buyer user_type after', 'svc', jsonEncode({
    'user_type': after.isEmpty ? null : after.first['user_type'],
  }));
  if (after.isNotEmpty &&
      after.first['user_type'].toString().toLowerCase().contains('admin')) {
    finding(
      id: 'P0-PROFILE-ADMIN',
      sev: 'P0',
      title: 'Buyer set user_type=admin',
      actor: 'buyer',
      pre: 'Own profile JWT',
      repro: 'PATCH profiles user_type=admin',
      impact: 'Privilege escalation to admin',
    );
  }

  final other = await rest(
    'PATCH',
    '/rest/v1/profiles?id=eq.$sellerId',
    jwt: buyerJwt,
    body: {'user_type': 'comprador'},
  );
  rec('profiles', 'buyer PATCH seller profile', 'buyer', brief(other));

  // is_admin rpc
  final admB = await rpcRaw('batata_is_admin', {}, jwt: buyerJwt);
  rec('rpc/batata_is_admin', '{}', 'buyer', brief(admB));
  final admS = await rpcRaw('batata_is_admin', {}, jwt: sellerJwt);
  rec('rpc/batata_is_admin', '{}', 'seller', brief(admS));
}
