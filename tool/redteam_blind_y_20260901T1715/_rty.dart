/// HTTP client — staging fxdknzrqjenzqcvnwqqq only. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260901T1715';
const prefix = 'RTY-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

String clip(Object? v, [int n = 360]) {
  if (v is HttpHit) return clip(v.brief, n);
  if (v is Set) return clip(v.toList(), n);
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

String repoRoot() {
  final cur = Directory.current.path;
  return cur.contains('redteam_blind_y_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_y_$stamp';

Map<String, String> loadEnv() {
  final root = repoRoot();
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
  HttpHit(this.status, this.body, this.json);
  bool get ok => status >= 200 && status < 300;
  String get snippet => clip(body);
  String get brief => '$status ${clip(body, 220)}';
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

class Rty {
  final String url;
  final String anon;
  final String svc;
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
  final holds = <Map<String, dynamic>>[];
  final closed = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdBundleIds = <String>[];

  Rty._(this.url, this.anon, this.svc, this.env);

  factory Rty.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rty._(
      url,
      envRequire(env, 'SUPABASE_ANON_KEY'),
      envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
      env,
    );
  }

  String? get stripeSk {
    final v = (env['STRIPE_SECRET_KEY'] ??
            Platform.environment['STRIPE_SECRET_KEY'] ??
            '')
        .trim();
    if (v.startsWith('sk_test_')) return v;
    return null;
  }

  String? get crashSecret {
    final v = (env['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
    return v.length >= 16 ? v : null;
  }

  Future<HttpHit> stripeForm(
    String method,
    String path, [
    Map<String, String>? form,
  ]) async {
    final sk = stripeSk;
    if (sk == null) {
      return HttpHit(0, 'no_sk_test', {'error': 'no_sk_test'});
    }
    final uri = Uri.parse(path.startsWith('http')
        ? path
        : 'https://api.stripe.com/v1/${path.replaceFirst(RegExp(r'^/'), '')}');
    final client = HttpClient();
    try {
      final rq = await client.openUrl(method, uri);
      rq.headers.set('Authorization',
          'Basic ${base64Encode(utf8.encode('$sk:'))}');
      if (form != null) {
        rq.headers.set('Content-Type', 'application/x-www-form-urlencoded');
        rq.add(utf8.encode(form.entries
            .map((e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
            .join('&')));
      }
      final rs = await rq.close();
      final text = utf8.decode(
        await rs.fold<List<int>>(<int>[], (p, e) => p..addAll(e)),
        allowMalformed: true,
      );
      Object? parsed;
      try {
        parsed = jsonDecode(text);
      } catch (_) {
        parsed = null;
      }
      return HttpHit(rs.statusCode, clip(text, 800), parsed);
    } finally {
      client.close(force: true);
    }
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
      final raw = await rs.fold<List<int>>(<int>[], (p, e) => p..addAll(e));
      final text = utf8.decode(raw, allowMalformed: true);
      Object? parsed;
      try {
        parsed = text.isEmpty ? null : jsonDecode(text);
      } catch (_) {
        parsed = null;
      }
      return HttpHit(
        rs.statusCode,
        raw.length > 8000 &&
                !text.trim().startsWith('{') &&
                !text.trim().startsWith('[')
            ? 'binary:${raw.length}'
            : text,
        parsed,
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
    String name, {
    Object? body,
    String? jwt,
    String method = 'POST',
    Map<String, String>? extra,
    bool service = false,
    String qs = '',
  }) {
    return req(
      method,
      '/functions/v1/$name$qs',
      jwt: jwt,
      body: body,
      extra: extra,
      service: service,
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
    required String userType,
    bool hubPublished = false,
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
        'hub_published': hubPublished,
        'is_live': false,
        'user_type': userType,
      }, prefer: 'return=minimal');
    }
    return id;
  }

  Future<void> ensureBuyer2() async {
    final email = '${prefix.toLowerCase()}-b2@fleaber.test';
    const pass = 'Rty1715b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rty1715b2',
      name: '$prefix-B2',
      userType: 'comprador',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2() async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rty1715s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rty1715s2',
      name: '$prefix-S2',
      userType: 'vendedor',
      hubPublished: true,
    );
    seller2Jwt = await signIn(email, pass);
  }

  Future<String?> insertProduct({
    required String title,
    String? seller,
    int qty = 5,
    double price = 12,
  }) async {
    final h = await rest('POST', 'products', service: true, body: {
      'seller_id': seller ?? sellerId,
      'title': title,
      'price': price,
      'quantity': qty,
      'is_sold': false,
      'list_on_marketplace': true,
      'available_for_live': false,
      'description': prefix,
      'image_urls': <String>[],
    });
    final id = h.firstId;
    if (id != null) createdProductIds.add(id);
    if (!h.ok) stdout.writeln('insertProduct fail ${h.brief}');
    return id;
  }

  Future<String?> insertOrder({
    required String productId,
    String? buyer,
    String? seller,
    String? jwt,
    int qty = 1,
    String shipping = 'mao',
    String payment = 'Pagamento na app',
    String? bundleId,
    String? offerId,
    bool service = false,
  }) async {
    final body = <String, dynamic>{
      'buyer_id': buyer ?? buyerId,
      'seller_id': seller ?? sellerId,
      'product_id': productId,
      'quantity': qty,
      'status': 'reserva_pendente',
      'payment_method': payment,
      'shipping_method': shipping,
    };
    if (bundleId != null) body['bundle_id'] = bundleId;
    if (offerId != null) body['product_offer_id'] = offerId;
    final h = await rest(
      'POST',
      'orders',
      jwt: service ? null : (jwt ?? buyerJwt),
      service: service,
      body: body,
    );
    final id = h.firstId;
    if (id != null) createdOrderIds.add(id);
    if (!h.ok) stdout.writeln('insertOrder fail ${h.brief}');
    return id;
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,shipping_method,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,stock_units_applied,shipped_at,bundle_id,contract_unit_cents,contract_qty,product_offer_id',
      service: true,
    );
    return h.map;
  }

  Future<num?> walletBal(String uid) async {
    final h = await rest(
      'GET',
      'wallets?id=eq.$uid&select=balance',
      service: true,
    );
    final b = h.map?['balance'];
    if (b is num) return b;
    return num.tryParse('$b');
  }

  Future<HttpHit> setupPaidOrder({
    int qty = 2,
    String shipping = 'mao',
  }) {
    return edge(
      'sec-fase2-e2e-oversell',
      service: true,
      extra: {
        if (crashSecret != null) 'x-fleaber-e2e-secret': crashSecret!,
      },
      body: {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'probe': 'setup_paid_order',
        'initial_qty': qty,
        'shipping_method': shipping,
      },
    );
  }

  Future<HttpHit> refundOrder(String orderId, {String? jwt}) {
    return edge('refund-order', jwt: jwt ?? sellerJwt, body: {
      'order_id': orderId,
    });
  }

  Future<HttpHit> checkout({
    String? orderId,
    bool bag = false,
    List<Map<String, dynamic>>? bagLines,
    String shipping = 'mao',
    String? jwt,
    String? buyer,
  }) {
    final body = <String, dynamic>{
      'buyer_id': buyer ?? buyerId,
      'shipping_method': shipping,
    };
    if (bag) {
      body['bag_checkout'] = true;
      body['bag_lines'] = bagLines;
      if (bagLines != null && bagLines.isNotEmpty) {
        body['order_id'] = bagLines.first['order_id'];
      }
    } else {
      body['order_id'] = orderId;
    }
    return edge('create-payment-intent', jwt: jwt ?? buyerJwt, body: body);
  }

  void note(String id, String title, Object? ev, {String? lens}) {
    notes.add({
      'id': id,
      if (lens != null) 'lens': lens,
      'title': title,
      'ev': ev is HttpHit ? ev.brief : ev,
    });
    stdout.writeln('NOTE $id ${lens ?? ''} $title ${clip(ev, 220)}');
  }

  void closedPath(String id, String title, Object? ev, {String? lens}) {
    closed.add({
      'id': id,
      if (lens != null) 'lens': lens,
      'title': title,
      'ev': ev is HttpHit ? ev.brief : ev,
    });
    stdout.writeln('CLOSED $id ${lens ?? ''} $title ${clip(ev, 180)}');
  }

  void finding({
    required String id,
    required String lens,
    required String severity,
    required String title,
    required String actor,
    required String pre,
    required String repro,
    required Object? expected,
    required Object? obtained,
    Map<String, Object?>? evidence,
    String? impact,
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
      'obtained': obtained is HttpHit ? obtained.brief : obtained,
      if (impact != null) 'impact': impact,
      'evidence': evidence ?? {},
    };
    findings.add(row);
    stdout.writeln('FINDING $severity $id [$lens] $title');
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
