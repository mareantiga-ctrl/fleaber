/// REDTEAM_BLIND_E_ORBITA_v1 — helpers. Staging only. No production. No fixes.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

const projectMust = 'fxdknzrqjenzqcvnwqqq';
const prefix = 'RTE-20260830T1810';

final matrix = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];
final gaps = <String>[];
final cleanup = <String, List<String>>{};

void rec({
  required String lens,
  required String surface,
  required String attack,
  required String identity,
  required String result,
  String impact = '',
  String severity = '',
  Object? evidence,
}) {
  matrix.add({
    'lens': lens,
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

Future<http.Response> req(
  String url,
  String method,
  String path, {
  required Map<String, String> headers,
  Object? body,
}) {
  final u = Uri.parse(path.startsWith('http') ? path : '$url$path');
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

Future<http.Response> rest(
  String url,
  String method,
  String table, {
  required Map<String, String> headers,
  Object? body,
  String qs = '',
}) {
  final q = qs.isEmpty ? '' : (qs.startsWith('?') ? qs : '?$qs');
  return req(url, method, '/rest/v1/$table$q', headers: headers, body: body);
}

Future<http.Response> rpc(
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

final _noFollow = http.Client();

Future<http.Response> edge(
  String url,
  String fn, {
  required String anon,
  String? jwt,
  Object? body,
  String method = 'POST',
  String qs = '',
  Map<String, String>? extra,
}) async {
  final headers = {
    'apikey': anon,
    'Authorization': 'Bearer ${jwt ?? anon}',
    'Content-Type': 'application/json',
    ...?extra,
  };
  final u = Uri.parse('$url/functions/v1/$fn$qs');
  final rq = http.Request(method, u);
  rq.headers.addAll(headers);
  if (method != 'GET' && body != null) {
    rq.body = jsonEncode(body);
  }
  rq.followRedirects = false;
  rq.maxRedirects = 0;
  final streamed = await _noFollow.send(rq);
  return http.Response.fromStream(streamed);
}

String brief(http.Response r, [int max = 480]) {
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
          b.contains('privilege') ||
          b.contains('jwt') ||
          b.contains('unauthorized') ||
          b.contains('invalid user') ||
          b.contains('cannot create another'));
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
    required this.buyer2Id,
    required this.buyer2Jwt,
    required this.client,
  });

  final String url;
  final String anon;
  final String svc;
  final String buyerId;
  final String sellerId;
  final String buyerJwt;
  final String sellerJwt;
  final String buyer2Id;
  final String buyer2Jwt;
  final LiveOpsStagingClient client;

  Map<String, String> get anonH => hAnon(anon);
  Map<String, String> get buyerH => hJwt(anon, buyerJwt);
  Map<String, String> get sellerH => hJwt(anon, sellerJwt);
  Map<String, String> get buyer2H => hJwt(anon, buyer2Jwt);
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
  final client = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  final ts = DateTime.now().toUtc().millisecondsSinceEpoch;
  final b2email = 'rte-e-b2-$ts@staging.fleaber.bot';
  const b2pass = 'RteE-orbit-1810!';
  final buyer2Id = await client.createAdminUser(
    email: b2email,
    password: b2pass,
    userMetadata: {'full_name': '$prefix-b2'},
  );
  await rest(
    url,
    'POST',
    'profiles',
    headers: hSvc(svc),
    body: {
      'id': buyer2Id,
      'full_name': '$prefix-b2',
      'user_type': 'comprador',
    },
  );
  final buyer2Jwt = await client.signIn(email: b2email, password: b2pass);
  cleanup['auth_users'] = [buyer2Id];

  return Ctx(
    url: url,
    anon: anon,
    svc: svc,
    buyerId: buyerId,
    sellerId: sellerId,
    buyerJwt: buyerJwt,
    sellerJwt: sellerJwt,
    buyer2Id: buyer2Id,
    buyer2Jwt: buyer2Jwt,
    client: client,
  );
}
