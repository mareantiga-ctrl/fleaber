/// HTTP client — staging fxdknzrqjenzqcvnwqqq only. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260831T1253';
const prefix = 'RTG-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

String clip(Object? v, [int n = 360]) {
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
  final root = Directory.current.path.contains('redteam_blind_g_')
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
  String get brief => '$status ${clip(body, 180)}';
  List<dynamic> get list => json is List ? json as List : const [];
  Map<String, dynamic>? get map {
    if (json is Map<String, dynamic>) return json as Map<String, dynamic>;
    if (json is Map) return Map<String, dynamic>.from(json as Map);
    if (list.isNotEmpty && list.first is Map) {
      return Map<String, dynamic>.from(list.first as Map);
    }
    return null;
  }

  String? get firstId {
    final m = map;
    return m?['id']?.toString();
  }
}

class Rtg {
  final String url;
  final String anon;
  final String svc;
  final String e2eSecret;
  final Map<String, String> env;
  String? buyerJwt;
  String? sellerJwt;
  String? buyer2Jwt;
  String? seller2Jwt;
  String? buyerId;
  String? sellerId;
  String? buyer2Id;
  String? seller2Id;
  final findings = <Map<String, dynamic>>[];
  final notes = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdLiveIds = <String>[];

  Rtg._(this.url, this.anon, this.svc, this.e2eSecret, this.env);

  factory Rtg.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtg._(
      url,
      envRequire(env, 'SUPABASE_ANON_KEY'),
      envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
      (env['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim(),
      env,
    );
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
    String prefer = 'return=representation',
  }) {
    return req(
      method,
      '/rest/v1/$tableQs',
      jwt: jwt,
      body: body,
      extra: {'Prefer': prefer},
      service: service,
    );
  }

  Future<HttpHit> rpc(
    String fn,
    Object args, {
    String? jwt,
    bool service = false,
  }) {
    return req('POST', '/rest/v1/rpc/$fn',
        jwt: jwt, body: args, service: service);
  }

  Future<HttpHit> edge(
    String name,
    Object? body, {
    String? jwt,
    String method = 'POST',
    Map<String, String>? extra,
    bool service = false,
  }) {
    return req(
      method,
      '/functions/v1/$name',
      jwt: jwt,
      body: body,
      extra: extra,
      service: service,
    );
  }

  Future<HttpHit> e2e(String probe, Map<String, Object?> body) {
    return req(
      'POST',
      '/functions/v1/sec-fase2-e2e-oversell',
      service: true,
      body: {
        'probe': probe,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        ...body,
      },
      extra: e2eSecret.isEmpty
          ? null
          : {'x-fleaber-e2e-secret': e2eSecret},
    );
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

  Future<void> loginActors() async {
    final be = envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL');
    final bp = envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD');
    final se = envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL');
    final sp = envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD');
    buyerJwt = await signIn(be, bp);
    sellerJwt = await signIn(se, sp);
    buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
    sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  }

  Future<String?> _ensureUser({
    required String email,
    required String pass,
    required String handle,
    required String name,
  }) async {
    await req('POST', '/auth/v1/admin/users', service: true, body: {
      'email': email,
      'password': pass,
      'email_confirm': true,
    });
    final jwt = await signIn(email, pass);
    final me = await req('GET', '/auth/v1/user', jwt: jwt);
    final id = (me.json is Map) ? (me.json as Map)['id'] as String? : null;
    if (id != null) {
      await rest('PATCH', 'profiles?id=eq.$id', service: true, body: {
        'full_name': name,
        'handle': handle,
        'hub_published': false,
        'is_live': false,
      }, prefer: 'return=minimal');
    }
    return id;
  }

  Future<void> ensureBuyer2() async {
    final email = '${prefix.toLowerCase()}-b2@fleaber.test';
    const pass = 'Rtg1253b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtg1253b2',
      name: '$prefix-B2',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2() async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rtg1253s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtg1253s2',
      name: '$prefix-S2',
    );
    seller2Jwt = await signIn(email, pass);
  }

  Future<String?> insertProduct({
    required String title,
    String? seller,
    bool listed = true,
    bool sold = false,
    int qty = 2,
    double price = 8.5,
    bool live = false,
  }) async {
    final h = await rest('POST', 'products', service: true, body: {
      'seller_id': seller ?? sellerId,
      'title': title,
      'price': price,
      'quantity': qty,
      'is_sold': sold,
      'list_on_marketplace': listed,
      'available_for_live': live,
      'description': prefix,
      'image_urls': <String>[],
    });
    final id = h.firstId;
    if (id != null) createdProductIds.add(id);
    return id;
  }

  Future<String?> insertOrder({
    required String productId,
    String? buyer,
    String? seller,
    String? jwt,
    String status = 'reserva_pendente',
    double price = 8.5,
    int qty = 1,
    String payment = 'Pagamento na app',
    String shipping = 'entrega em mão',
    bool service = false,
  }) async {
    final h = await rest('POST', 'orders', jwt: jwt, service: service, body: {
      'buyer_id': buyer ?? buyerId,
      'seller_id': seller ?? sellerId,
      'product_id': productId,
      'price_total': price,
      'quantity': qty,
      'status': status,
      'payment_method': payment,
      'shipping_method': shipping,
    });
    final id = h.firstId;
    if (id != null) createdOrderIds.add(id);
    return id;
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,shipping_method,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,stock_units_applied,completed_at,auto_feedback_processed_at,bundle_id',
      service: true,
    );
    return h.map;
  }

  Future<Map<String, dynamic>?> productRow(String id) async {
    final h = await rest(
      'GET',
      'products?id=eq.$id&select=id,title,price,quantity,is_sold,list_on_marketplace,seller_id',
      service: true,
    );
    return h.map;
  }

  Future<Map<String, num>> wallets() async {
    Future<num> bal(String? id) async {
      if (id == null) return 0;
      final h = await rest(
        'GET',
        'wallets?id=eq.$id&select=id,balance',
        service: true,
      );
      final b = h.map?['balance'];
      if (b is num) return b;
      return num.tryParse('$b') ?? 0;
    }

    return {
      'buyer': await bal(buyerId),
      'seller': await bal(sellerId),
      'buyer2': await bal(buyer2Id),
      'seller2': await bal(seller2Id),
    };
  }

  Future<String?> insertLive({bool active = false}) async {
    final h = await rest('POST', 'lives', service: true, body: {
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'title': '$prefix live',
      'status': active ? 'live' : 'ended',
      'is_active': active,
    });
    final id = h.firstId;
    if (id != null) createdLiveIds.add(id);
    return id;
  }

  Future<void> endLives() async {
    for (final id in createdLiveIds) {
      await rest('PATCH', 'lives?id=eq.$id', service: true, body: {
        'is_active': false,
        'status': 'ended',
      }, prefer: 'return=minimal');
    }
  }

  void note(String id, String title, Object? ev, {String? lens}) {
    notes.add({
      'id': id,
      if (lens != null) 'lens': lens,
      'title': title,
      'ev': ev is HttpHit ? ev.brief : ev,
    });
    stdout.writeln('NOTE $id ${lens ?? ''} $title ${clip(ev, 200)}');
  }

  void hold({
    required String id,
    required String lens,
    required String severity,
    required String title,
    required String actor,
    required String pre,
    required String repro,
    required Object? expected,
    required Object? obtained,
    bool proven = true,
    Map<String, Object?>? evidence,
  }) {
    final row = {
      'id': id,
      'lens': lens,
      'severity': severity,
      'title': title,
      'actor': actor,
      'pre': pre,
      'repro': repro,
      'expected': expected,
      'obtained': obtained,
      'proven': proven,
      'evidence': evidence ?? {},
    };
    findings.add(row);
    stdout.writeln('FINDING $severity $id [$lens] $title');
  }
}

Future<List<HttpHit>> parallel(List<Future<HttpHit>> jobs) => Future.wait(jobs);

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
