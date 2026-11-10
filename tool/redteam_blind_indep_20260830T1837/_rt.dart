/// Blind independent red-team 20260830T1837 — shared helpers.
/// Staging fxdknzrqjenzqcvnwqqq only. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

const projectMust = 'fxdknzrqjenzqcvnwqqq';
const prefix = 'RT1837';

final matrix = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];
final gaps = <String>[];
final invariants = <Map<String, dynamic>>[];

void rec({
  required String surface,
  required String attack,
  required String identity,
  required String result,
  String impact = '',
  String severity = '',
  Object? evidence,
}) {
  matrix.add({
    'surface': surface,
    'attack': attack,
    'identity': identity,
    'result': result,
    'impact': impact,
    'severity': severity,
    'evidence': clip(evidence),
  });
}

void finding({
  required String id,
  required String severity,
  required String title,
  required String actor,
  required String pre,
  required String repro,
  required String impact,
  String estado = 'ABERTO',
  Object? evidence,
}) {
  findings.add({
    'id': id,
    'severity': severity,
    'title': title,
    'actor': actor,
    'pre': pre,
    'repro': repro,
    'impact': impact,
    'estado': estado,
    'evidence': clip(evidence),
  });
}

void inv({
  required String id,
  required String claim,
  required String result,
  String notes = '',
}) {
  invariants.add({'id': id, 'claim': claim, 'result': result, 'notes': notes});
}

Object? clip(Object? v) {
  if (v == null) return null;
  final s = v is String ? v : jsonEncode(v);
  if (s.length <= 1800) {
    if (v is String) return v;
    try {
      return jsonDecode(jsonEncode(v));
    } catch (_) {
      return s;
    }
  }
  return '${s.substring(0, 1800)}…';
}

String briefBody(http.Response r) {
  var b = r.body;
  if (b.length > 500) b = '${b.substring(0, 500)}…';
  return '${r.statusCode} $b';
}

Map<String, String> hAnon(String anon) => {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Map<String, String> hJwt(String anon, String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Map<String, String> hSvc(String svc) => {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Future<http.Response> rest(
  String url,
  String method,
  String path, {
  required Map<String, String> headers,
  Object? body,
}) {
  final u = Uri.parse('$url/rest/v1/$path');
  final b = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'GET':
      return http.get(u, headers: headers);
    case 'POST':
      return http.post(u, headers: headers, body: b);
    case 'PATCH':
      return http.patch(u, headers: headers, body: b);
    case 'DELETE':
      return http.delete(u, headers: headers, body: b);
    default:
      throw ArgumentError(method);
  }
}

Future<http.Response> rpc(
  String url,
  String fn,
  Object? args, {
  required Map<String, String> headers,
}) {
  return http.post(
    Uri.parse('$url/rest/v1/rpc/$fn'),
    headers: headers,
    body: jsonEncode(args ?? <String, dynamic>{}),
  );
}

Future<http.Response> edge(
  String url,
  String fn,
  Object? body, {
  required Map<String, String> headers,
  String method = 'POST',
  Map<String, String>? extraHeaders,
  Map<String, String>? query,
}) {
  var u = Uri.parse('$url/functions/v1/$fn');
  if (query != null && query.isNotEmpty) {
    u = u.replace(queryParameters: {...u.queryParameters, ...query});
  }
  final h = {...headers, ...?extraHeaders};
  final b = body == null ? null : jsonEncode(body);
  if (method == 'GET') return http.get(u, headers: h);
  return http.post(u, headers: h, body: b);
}

dynamic decode(http.Response r) {
  if (r.body.isEmpty) return null;
  try {
    return jsonDecode(r.body);
  } catch (_) {
    return r.body;
  }
}

List<Map<String, dynamic>> asMaps(dynamic v) {
  if (v is List) {
    return v
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  if (v is Map) return [Map<String, dynamic>.from(v)];
  return [];
}

class Ctx {
  Ctx({
    required this.url,
    required this.anon,
    required this.svc,
    required this.buyerId,
    required this.sellerId,
    required this.buyerJwt,
    required this.sellerJwt,
    required this.crashSecret,
    required this.buyerEmail,
    required this.sellerEmail,
  });

  final String url;
  final String anon;
  final String svc;
  final String buyerId;
  final String sellerId;
  final String buyerJwt;
  final String sellerJwt;
  final String crashSecret;
  final String buyerEmail;
  final String sellerEmail;

  Map<String, String> get anonH => hAnon(anon);
  Map<String, String> get buyerH => hJwt(anon, buyerJwt);
  Map<String, String> get sellerH => hJwt(anon, sellerJwt);
  Map<String, String> get svcH => hSvc(svc);

  LiveOpsStagingClient get admin => LiveOpsStagingClient(
        url: url,
        anonKey: anon,
        serviceRoleKey: svc,
      );
}

Future<Ctx> boot() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) {
    stderr.writeln('REFUSED: not staging $projectMust');
    exit(2);
  }
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final client = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  return Ctx(
    url: url,
    anon: anon,
    svc: svc,
    buyerId: envRequire(env, 'LIVE_OPS_TEST_BUYER_ID'),
    sellerId: envRequire(env, 'LIVE_OPS_TEST_SELLER_ID'),
    buyerJwt: buyerJwt,
    sellerJwt: sellerJwt,
    crashSecret: (env['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim(),
    buyerEmail: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    sellerEmail: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
  );
}

Future<void> dumpJson(String name, Object data) async {
  final dir = Directory('tool/redteam_blind_indep_20260830T1837/out');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File('${dir.path}/$name.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(data),
  );
}

String tag() =>
    '$prefix-${DateTime.now().toUtc().millisecondsSinceEpoch}';
