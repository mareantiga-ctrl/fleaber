import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

const projectMust = 'fxdknzrqjenzqcvnwqqq';
const prefix = 'RTE-20260830T1859';
const outDir = 'tool/redteam_blind_e_orbita_20260830T1859/out';

class Hit {
  Hit(this.status, this.body, {this.headers = const {}});
  final int status;
  final String body;
  final Map<String, String> headers;

  dynamic get json {
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  String get snippet {
    final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= 320) return t;
    return '${t.substring(0, 320)}…';
  }

  bool get ok => status >= 200 && status < 300;
}

class ProbeCtx {
  ProbeCtx({
    required this.url,
    required this.anon,
    required this.svc,
    required this.buyerId,
    required this.sellerId,
    required this.buyerJwt,
    required this.sellerJwt,
  });

  final String url;
  final String anon;
  final String svc;
  final String buyerId;
  final String sellerId;
  final String buyerJwt;
  final String sellerJwt;

  String? buyer2Id;
  String? buyer2Jwt;

  late final LiveOpsStagingClient admin = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );

  Map<String, String> headers({String? jwt, bool service = false}) {
    final token = service ? svc : (jwt ?? anon);
    return {
      'apikey': service ? svc : anon,
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
  }

  Future<Hit> rest(
    String method,
    String path, {
    String? jwt,
    bool service = false,
    Object? body,
    Map<String, String>? extra,
  }) async {
    final uri = Uri.parse(
      path.startsWith('http')
          ? path
          : '$url${path.startsWith('/') ? path : '/$path'}',
    );
    final h = headers(jwt: jwt, service: service);
    if (extra != null) h.addAll(extra);
    final encoded = body == null
        ? null
        : (body is String ? body : jsonEncode(body));
    final req = http.Request(method.toUpperCase(), uri);
    req.followRedirects = false;
    req.headers.addAll(h);
    if (encoded != null && method.toUpperCase() != 'GET' && method.toUpperCase() != 'HEAD') {
      req.body = encoded;
    }
    final streamed = await http.Client().send(req);
    final r = await http.Response.fromStream(streamed);
    return Hit(r.statusCode, r.body, headers: r.headers);
  }

  Future<Hit> rpc(
    String fn,
    Map<String, dynamic> params, {
    String? jwt,
    bool service = false,
  }) {
    return rest(
      'POST',
      '/rest/v1/rpc/$fn',
      jwt: jwt,
      service: service,
      body: params,
    );
  }

  Future<Hit> edge(
    String fn,
    Object? body, {
    String? jwt,
    String method = 'POST',
    Map<String, String>? extra,
    String query = '',
  }) {
    final q = query.isEmpty ? '' : (query.startsWith('?') ? query : '?$query');
    return rest(
      method,
      '/functions/v1/$fn$q',
      jwt: jwt,
      body: body,
      extra: extra,
    );
  }

  Future<Hit> select(
    String table, {
    String? jwt,
    bool service = false,
    String select = '*',
    String? filter,
    int limit = 8,
  }) {
    var path = '/rest/v1/$table?select=$select&limit=$limit';
    if (filter != null && filter.isNotEmpty) path += '&$filter';
    return rest('GET', path, jwt: jwt, service: service);
  }
}

Future<ProbeCtx> boot() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) {
    throw StateError('recusado: não é staging $projectMust');
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final tmp = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerJwt = await tmp.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await tmp.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  return ProbeCtx(
    url: url,
    anon: anon,
    svc: svc,
    buyerId: buyerId,
    sellerId: sellerId,
    buyerJwt: buyerJwt,
    sellerJwt: sellerJwt,
  );
}

void stamp(Map<String, dynamic> out) {
  out['auditor'] = 'REDTEAM_BLIND_E_ORBITA_v1';
  out['frozen_at'] = DateTime.now().toUtc().toIso8601String();
  out['project'] = projectMust;
  out['production_touched'] = false;
  out['fase4'] = false;
  out['corrections_applied'] = false;
  out['prefix'] = prefix;
}

Future<void> writeOut(String name, Map<String, dynamic> data) async {
  stamp(data);
  final dir = Directory(outDir);
  dir.createSync(recursive: true);
  final f = File('${dir.path}/$name');
  f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  stdout.writeln('wrote ${f.path}');
}

String clip(Object? v, [int n = 220]) {
  final t = '$v'.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length <= n) return t;
  return '${t.substring(0, n)}…';
}
