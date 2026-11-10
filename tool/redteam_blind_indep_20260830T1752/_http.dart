/// Shared HTTP helpers for blind independent red-team 20260830T1752.
/// Staging only. No production. No Fase 4. No fixes.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

const projectMust = 'fxdknzrqjenzqcvnwqqq';
const prefix = 'RT1752';

final matrix = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];
final gaps = <String>[];

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

Object? clip(Object? v) {
  if (v == null) return null;
  final s = v is String ? v : jsonEncode(v);
  if (s.length <= 1600) {
    if (v is String) return v;
    try {
      return jsonDecode(jsonEncode(v));
    } catch (_) {
      return s;
    }
  }
  return '${s.substring(0, 1600)}…';
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

Future<http.Response> rpcRaw(
  String url,
  String fn,
  Map<String, dynamic> params, {
  required Map<String, String> headers,
}) {
  return http.post(
    Uri.parse('$url/rest/v1/rpc/$fn'),
    headers: headers,
    body: jsonEncode(params),
  );
}

Future<http.Response> edge(
  String url,
  String fn,
  Object? body, {
  required String anon,
  String? jwt,
  Map<String, String>? extra,
  String method = 'POST',
}) {
  final headers = {
    'apikey': anon,
    'Authorization': 'Bearer ${jwt ?? anon}',
    'Content-Type': 'application/json',
    ...?extra,
  };
  final u = Uri.parse('$url/functions/v1/$fn');
  if (method == 'GET') return http.get(u, headers: headers);
  return http.post(u, headers: headers, body: body == null ? null : jsonEncode(body));
}

String brief(http.Response r, [int max = 420]) {
  var b = r.body;
  if (b.length > max) b = '${b.substring(0, max)}…';
  return '${r.statusCode} $b';
}

bool looksDenied(http.Response r) {
  if (r.statusCode == 401 || r.statusCode == 403 || r.statusCode == 425) {
    return true;
  }
  final b = r.body.toLowerCase();
  return r.statusCode >= 400 &&
      (b.contains('row-level security') ||
          b.contains('permission') ||
          b.contains('not allowed') ||
          b.contains('not_allowed') ||
          b.contains('42501') ||
          b.contains('42514') ||
          b.contains('jwt') ||
          b.contains('privilege') ||
          b.contains('sem permissão') ||
          b.contains('invalid checkout') ||
          b.contains('invalid user') ||
          b.contains('service_role'));
}

bool looksOk(http.Response r) => r.statusCode >= 200 && r.statusCode < 300;

dynamic tryJson(http.Response r) {
  try {
    return jsonDecode(r.body);
  } catch (_) {
    return r.body;
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
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
    this.crashSecret = '',
  });

  final String url;
  final String anon;
  final String svc;
  final String buyerId;
  final String sellerId;
  final String buyerJwt;
  final String sellerJwt;
  final String crashSecret;

  Map<String, String> get anonH => hAnon(anon);
  Map<String, String> get buyerH => hJwt(anon, buyerJwt);
  Map<String, String> get sellerH => hJwt(anon, sellerJwt);
  Map<String, String> get svcH => hSvc(svc);
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
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerJwt = await LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  ).signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  ).signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  return Ctx(
    url: url,
    anon: anon,
    svc: svc,
    buyerId: buyerId,
    sellerId: sellerId,
    buyerJwt: buyerJwt,
    sellerJwt: sellerJwt,
    crashSecret: (env['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim(),
  );
}
