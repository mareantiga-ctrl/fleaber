/// REDTEAM_BLIND_INDEP_v4 — cliente HTTP. Staging only. Sem fixes. Sem produção.
library;

import 'dart:convert';
import 'dart:io';

const projectMust = 'fxdknzrqjenzqcvnwqqq';
const stamp = '20260831T1251';
const prefix = 'RTI4-$stamp-';

final _http = HttpClient()..connectionTimeout = const Duration(seconds: 45);

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
  final root = Directory.current.path;
  final merged = <String, String>{};
  merged.addAll(loadEnvFile('$root/tool/live_ops_staging.env'));
  merged.addAll(loadEnvFile('$root/.maestro/.env'));
  merged.addAll(loadEnvFile('$root/supabase/.env'));
  Platform.environment.forEach((k, v) {
    if (v.isNotEmpty) merged[k] = v;
  });
  return merged;
}

String envRequire(Map<String, String> e, String k) {
  final v = (e[k] ?? '').trim();
  if (v.isEmpty) throw StateError('missing $k');
  return v;
}

String normUrl(String raw) {
  var u = raw.trim();
  u = u.replaceAll(RegExp(r'/+$'), '');
  u = u.replaceAll(RegExp(r'/rest/v1$'), '');
  return u;
}

String clip(Object? v, [int n = 400]) {
  final t = '$v'.replaceAll(RegExp(r'\s+'), ' ');
  if (t.length <= n) return t;
  return '${t.substring(0, n)}…';
}

class HttpR {
  HttpR(this.status, this.body, {this.headers = const {}});
  final int status;
  final String body;
  final Map<String, String> headers;

  dynamic get json {
    final t = body.trim();
    if (t.isEmpty) return null;
    try {
      return jsonDecode(t);
    } catch (_) {
      return t;
    }
  }

  Map<String, dynamic>? get map {
    final j = json;
    return j is Map<String, dynamic> ? j : null;
  }

  List<dynamic> get list {
    final j = json;
    if (j is List) return j;
    return const [];
  }

  String get brief {
    final t = body.replaceAll(RegExp(r'\s+'), ' ');
    if (t.length <= 280) return '$status $t';
    return '$status ${t.substring(0, 280)}…';
  }

  bool get ok => status >= 200 && status < 300;
  String? get location => headers['location'];
}

class Rti4 {
  Rti4(this.env)
      : url = normUrl(envRequire(env, 'SUPABASE_URL')),
        anon = envRequire(env, 'SUPABASE_ANON_KEY'),
        svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY') {
    if (!url.contains(projectMust)) {
      throw StateError('refused: not staging $projectMust');
    }
  }

  final Map<String, String> env;
  final String url;
  final String anon;
  final String svc;

  late final String buyerId;
  late final String sellerId;
  late String buyerJwt;
  late String sellerJwt;
  String? freshJwt;
  String? freshId;
  String? e2eSecret;

  final notes = <Map<String, dynamic>>[];
  final findings = <Map<String, dynamic>>[];
  final holds = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdLiveIds = <String>[];

  void note(String id, String title, Object? detail, {String well = ''}) {
    notes.add({
      'id': id,
      'title': title,
      'well': well,
      'detail': detail is HttpR ? detail.brief : detail,
    });
    stdout.writeln('NOTE $id ${detail is HttpR ? detail.brief : detail}');
  }

  void hold(String id, String title, Object? evidence, {String well = ''}) {
    holds.add({
      'id': id,
      'title': title,
      'well': well,
      'evidence': evidence is HttpR ? evidence.brief : evidence,
    });
    stdout.writeln('HOLD $id $title');
  }

  void finding({
    required String id,
    required String title,
    required String actor,
    required String sev,
    required String well,
    required String pre,
    required String request,
    required Object? before,
    required Object? after,
    required String impact,
    required String repro,
  }) {
    final row = {
      'id': id,
      'title': title,
      'actor': actor,
      'sev': sev,
      'well': well,
      'pre': pre,
      'request': request,
      'before': before,
      'after': after,
      'impact': impact,
      'repro': repro,
    };
    findings.add(row);
    stdout.writeln('FINDING $sev $id $title');
  }

  Future<HttpR> call(
    String method,
    String path, {
    String? token,
    bool service = false,
    Object? body,
    Map<String, String>? extra,
    String? prefer,
    String? contentType,
  }) async {
    final uri = Uri.parse(path.startsWith('http') ? path : '$url$path');
    final req = await _http.openUrl(method, uri);
    final key = service ? svc : anon;
    req.headers.set('apikey', key);
    req.headers.set('Authorization', 'Bearer ${service ? svc : (token ?? key)}');
    if (prefer != null) req.headers.set('Prefer', prefer);
    if (extra != null) {
      extra.forEach((k, v) => req.headers.set(k, v));
    }
    if (body != null) {
      req.headers.set('Content-Type', contentType ?? 'application/json');
      if (body is String) {
        req.add(utf8.encode(body));
      } else {
        req.add(utf8.encode(jsonEncode(body)));
      }
    }
    final res = await req.close().timeout(const Duration(seconds: 90));
    final text = await res.transform(utf8.decoder).join();
    final hdrs = <String, String>{};
    res.headers.forEach((n, v) {
      if (v.isNotEmpty) hdrs[n.toLowerCase()] = v.join(', ');
    });
    return HttpR(res.statusCode, text, headers: hdrs);
  }

  Future<HttpR> rest(
    String method,
    String qs, {
    String? token,
    bool service = false,
    Object? body,
    String prefer = 'return=representation',
  }) {
    return call(
      method,
      '/rest/v1/$qs',
      token: token,
      service: service,
      body: body,
      prefer: (method == 'GET' || method == 'HEAD') ? null : prefer,
    );
  }

  Future<HttpR> rpc(
    String fn,
    Map<String, dynamic> args, {
    String? token,
    bool service = false,
  }) {
    return call(
      'POST',
      '/rest/v1/rpc/$fn',
      token: token,
      service: service,
      body: args,
    );
  }

  Future<HttpR> edge(
    String name,
    Object? body, {
    String? token,
    bool service = false,
    String method = 'POST',
    Map<String, String>? extra,
  }) {
    return call(
      method,
      '/functions/v1/$name',
      token: token,
      service: service,
      body: body,
      extra: extra,
    );
  }

  Future<Map<String, String>> login(String email, String password) async {
    final r = await call(
      'POST',
      '/auth/v1/token?grant_type=password',
      body: {'email': email, 'password': password},
    );
    final m = r.map;
    final access = (m?['access_token'] ?? '').toString();
    final uid = ((m?['user'] as Map?)?['id'] ?? '').toString();
    if (access.isEmpty) {
      throw StateError('login failed $email ${r.brief}');
    }
    return {'access': access, 'id': uid};
  }

  Future<Map<String, String>?> signup(String email, String password) async {
    final r = await call(
      'POST',
      '/auth/v1/signup',
      body: {'email': email, 'password': password},
    );
    final m = r.map;
    final access = (m?['access_token'] ?? '').toString();
    final uid = ((m?['user'] as Map?)?['id'] ?? '').toString();
    if (access.isEmpty) {
      note('signup.fail', 'signup', r.brief);
      return null;
    }
    return {'access': access, 'id': uid};
  }

  Future<void> boot() async {
    buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
    sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
    e2eSecret = (env['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
    final b = await login(
      envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
    );
    final s = await login(
      envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
      envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
    );
    buyerJwt = b['access']!;
    sellerJwt = s['access']!;
    if (b['id'] != buyerId) {
      note('boot.buyer.id', 'buyer id mismatch', '${b['id']} vs $buyerId');
      buyerId = b['id']!;
    }
    if (s['id'] != sellerId) {
      note('boot.seller.id', 'seller id mismatch', '${s['id']} vs $sellerId');
      sellerId = s['id']!;
    }
    final freshMail =
        'rti4.${stamp}.${DateTime.now().millisecondsSinceEpoch}@fleaber.test';
    final fresh = await signup(freshMail, 'TesteRti4!2026Aa');
    if (fresh != null) {
      freshJwt = fresh['access'];
      freshId = fresh['id'];
    }
  }

  Future<Map<String, dynamic>?> getOne(
    String table,
    String id, {
    String select = '*',
    bool service = true,
    String? token,
  }) async {
    final r = await rest(
      'GET',
      '$table?id=eq.$id&select=$select&limit=1',
      service: service,
      token: token,
    );
    final rows = r.list;
    if (rows.isEmpty || rows.first is! Map) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  }

  Future<Map<String, dynamic>?> insertProduct({
    required bool listed,
    required bool sold,
    num price = 4.5,
    int qty = 1,
    String? title,
    bool availableForLive = false,
  }) async {
    final t = title ?? '$prefix${listed ? 'L' : 'U'}${sold ? 'S' : 'A'}';
    final r = await rest(
      'POST',
      'products',
      token: sellerJwt,
      body: {
        'seller_id': sellerId,
        'title': t,
        'price': price,
        'quantity': qty,
        'ref_code':
            'RTI4-${DateTime.now().millisecondsSinceEpoch}-${listed ? 1 : 0}',
        'list_on_marketplace': listed,
        'available_for_live': availableForLive,
        'is_sold': sold,
        'image_urls': <String>[],
      },
    );
    if (!r.ok || r.list.isEmpty) {
      note('product.insert.fail', t, r.brief, well: '1');
      return null;
    }
    final row = Map<String, dynamic>.from(r.list.first as Map);
    final id = row['id']?.toString();
    if (id != null) createdProductIds.add(id);
    return row;
  }

  Future<HttpR> insertOrder({
    required String token,
    required String productId,
    String? buyer,
    String? seller,
    String status = 'reserva_pendente',
    int qty = 1,
    num price = 4.5,
    String payment = 'Pagamento na App',
    String? shipping,
    String? liveId,
    String? liveItemId,
    String? liveRaffleId,
    Map<String, dynamic>? extra,
  }) async {
    final body = <String, dynamic>{
      'product_id': productId,
      'buyer_id': buyer ?? buyerId,
      'seller_id': seller ?? sellerId,
      'price_total': price,
      'quantity': qty,
      'status': status,
      'payment_method': payment,
      if (shipping != null) 'shipping_method': shipping,
      if (liveId != null) 'live_id': liveId,
      if (liveItemId != null) 'live_item_id': liveItemId,
      if (liveRaffleId != null) 'live_raffle_id': liveRaffleId,
      ...?extra,
    };
    final r = await rest('POST', 'orders', token: token, body: body);
    final oid = r.list.isNotEmpty
        ? (r.list.first as Map)['id']?.toString()
        : r.map?['id']?.toString();
    if (oid != null && oid.isNotEmpty) createdOrderIds.add(oid);
    return r;
  }

  String? orderIdOf(HttpR r) {
    if (r.list.isNotEmpty && r.list.first is Map) {
      return (r.list.first as Map)['id']?.toString();
    }
    return r.map?['id']?.toString();
  }

  Future<HttpR> checkout({
    required String token,
    required String orderId,
    String? productId,
    String shipping = 'carrier',
    Map<String, dynamic>? extra,
  }) {
    return edge(
      'create-payment-intent',
      {
        'order_id': orderId,
        if (productId != null) 'product_id': productId,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'shipping_method': shipping,
        ...?extra,
      },
      token: token,
    );
  }

  Future<HttpR> e2e(String probe, Map<String, dynamic> body) {
    final secret = e2eSecret ?? '';
    return edge(
      'sec-fase2-e2e-oversell',
      {'probe': probe, ...body},
      extra: secret.isEmpty ? null : {'x-fleaber-e2e-secret': secret},
    );
  }

  Future<void> dump(String name) async {
    final dir = Directory('tool/redteam_blind_indep_$stamp/out');
    dir.createSync(recursive: true);
    File('${dir.path}/$name.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'auditor': 'REDTEAM_BLIND_INDEP_v4',
        'stamp': stamp,
        'project': projectMust,
        'production_touched': false,
        'fase4': false,
        'corrections_applied': false,
        'fresh_id': freshId,
        'findings': findings,
        'holds': holds,
        'notes': notes,
        'created_products': createdProductIds,
        'created_orders': createdOrderIds,
        'created_lives': createdLiveIds,
      }),
    );
  }
}
