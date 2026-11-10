/// HTTP client — staging fxdknzrqjenzqcvnwqqq only. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260830T1930';
const prefix = 'RTE-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

String clip(Object? v, [int n = 280]) {
  final s = v is String ? v : jsonEncode(v);
  if (s.length <= n) return s;
  return '${s.substring(0, n)}…';
}

Map<String, String> loadEnvFile(String path) {
  final f = File(path);
  if (!f.existsSync()) return {};
  final out = <String, String>{};
  for (final raw in f.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final i = line.indexOf('=');
    if (i <= 0) continue;
    out[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  return out;
}

Map<String, String> loadEnv() {
  final root = Directory.current.path.contains('redteam_blind_e_orbita')
      ? Directory.current.parent.parent.path
      : Directory.current.path;
  final merged = <String, String>{};
  merged.addAll(loadEnvFile('$root/tool/live_ops_staging.env'));
  merged.addAll(loadEnvFile('$root/.maestro/.env'));
  merged.addAll(loadEnvFile('$root/supabase/.env'));
  return merged;
}

String envRequire(Map<String, String> e, String k) {
  final v = (e[k] ?? Platform.environment[k] ?? '').trim();
  if (v.isEmpty) {
    stderr.writeln('missing $k');
    exit(2);
  }
  return v;
}

class HttpHit {
  final int status;
  final String body;
  final Object? json;
  final String? location;
  HttpHit(this.status, this.body, this.json, [this.location]);
  bool get ok => status >= 200 && status < 300;
  String get snippet => clip(body);
}

class Rte {
  final String url;
  final String anon;
  final String svc;
  String? buyerJwt;
  String? sellerJwt;
  String? buyer2Jwt;
  String? buyerId;
  String? sellerId;
  String? buyer2Id;

  Rte._(this.url, this.anon, this.svc);

  factory Rte.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rte._(url, envRequire(env, 'SUPABASE_ANON_KEY'),
        envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'));
  }

  Future<HttpHit> req(
    String method,
    String path, {
    String? jwt,
    Object? body,
    Map<String, String>? extra,
    bool service = false,
  }) async {
    final key = service ? svc : anon;
    final uri = Uri.parse(path.startsWith('http')
        ? path
        : '$url${path.startsWith('/') ? path : '/$path'}');
    final h = <String, String>{
      'apikey': key,
      'Authorization': 'Bearer ${jwt ?? (service ? svc : anon)}',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?extra,
    };
    final client = HttpClient();
    try {
      final rq = await client.openUrl(method, uri);
      rq.followRedirects = false;
      rq.maxRedirects = 0;
      h.forEach(rq.headers.set);
      if (body != null) {
        final bytes = utf8.encode(body is String ? body : jsonEncode(body));
        rq.add(bytes);
      }
      final rs = await rq.close();
      final text = await rs.transform(utf8.decoder).join();
      Object? parsed;
      try {
        parsed = text.isEmpty ? null : jsonDecode(text);
      } catch (_) {
        parsed = null;
      }
      return HttpHit(
        rs.statusCode,
        text,
        parsed,
        rs.headers.value('location'),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpHit> rest(
    String method,
    String tableQs, {
    String? jwt,
    Object? body,
    bool service = false,
    String? prefer,
  }) {
    final extra = <String, String>{};
    if (prefer != null) extra['Prefer'] = prefer;
    if (method == 'GET' || method == 'DELETE') extra['Accept'] = 'application/json';
    return req(method, '/rest/v1/$tableQs',
        jwt: jwt, body: body, extra: extra, service: service);
  }

  Future<HttpHit> rpc(String fn, Object args, {String? jwt, bool service = false}) {
    return req('POST', '/rest/v1/rpc/$fn', jwt: jwt, body: args, service: service);
  }

  Future<HttpHit> edge(String name, Object? body, {String? jwt, String method = 'POST'}) {
    return req(method, '/functions/v1/$name', jwt: jwt, body: body);
  }

  Future<String> signIn(String email, String password) async {
    final h = await req('POST', '/auth/v1/token?grant_type=password', body: {
      'email': email,
      'password': password,
    });
    if (!h.ok || h.json is! Map) {
      throw StateError('login failed $email ${h.status} ${h.snippet}');
    }
    return (h.json as Map)['access_token'] as String;
  }

  Future<void> loginActors(Map<String, String> env) async {
    final be = envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL');
    final bp = envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD');
    final se = envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL');
    final sp = envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD');
    buyerJwt = await signIn(be, bp);
    sellerJwt = await signIn(se, sp);
    buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
    sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  }

  Future<void> ensureBuyer2() async {
    final email = '${prefix.toLowerCase()}-b2@fleaber.test';
    final pass = 'Rte${stamp}b2!x';
    await req('POST', '/auth/v1/admin/users', service: true, body: {
      'email': email,
      'password': pass,
      'email_confirm': true,
    });
    try {
      buyer2Jwt = await signIn(email, pass);
    } catch (_) {
      final created = await req('POST', '/auth/v1/admin/users', service: true, body: {
        'email': email,
        'password': pass,
        'email_confirm': true,
      });
      if (!created.ok) {
        throw StateError('buyer2 create ${created.status} ${created.snippet}');
      }
      buyer2Jwt = await signIn(email, pass);
    }
    final me = await req('GET', '/auth/v1/user', jwt: buyer2Jwt);
    buyer2Id = (me.json is Map) ? (me.json as Map)['id'] as String? : null;
    if (buyer2Id != null) {
      await rest('PATCH', 'profiles?id=eq.$buyer2Id', service: true, body: {
        'full_name': '$prefix-B2',
        'handle': 'rte1930b2',
        'hub_published': false,
        'is_live': false,
      }, prefer: 'return=minimal');
    }
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}

Map<String, dynamic> finding({
  required String id,
  required String lens,
  required String severity,
  required String title,
  required String pre,
  required String repro,
  required bool proven,
  Map<String, Object?>? evidence,
  String? note,
}) {
  return {
    'id': id,
    'lens': lens,
    'severity': severity,
    'title': title,
    'pre': pre,
    'repro': repro,
    'proven': proven,
    'evidence': evidence ?? {},
    if (note != null) 'note': note,
  };
}
