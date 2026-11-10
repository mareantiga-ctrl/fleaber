/// RED TEAM CEGO EH — paymethod / off-platform / App pós-OPEN MVP.
/// Staging fxdknzrqjenzqcvnwqqq only. Stripe TEST. No production. No Fase 4. No fixes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const stamp = '20260906T1908';
const prefix = 'RTEH-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

String clip(Object? v, [int n = 360]) {
  if (v is HttpHit) return clip(v.brief, n);
  final s = v is String ? v : jsonEncode(v);
  if (s.length <= n) return s;
  return '${s.substring(0, n)}…';
}

num? numOf(dynamic v) {
  if (v is num) return v;
  return num.tryParse('$v');
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

String repoRoot() {
  final cur = Directory.current.path;
  return cur.contains('redteam_blind_eh_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_eh_$stamp';

class HttpHit {
  final int status;
  final String body;
  final Object? json;
  final String? location;
  HttpHit(this.status, this.body, this.json, [this.location]);
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

  String? get sessionId {
    final m = map;
    if (m == null) return null;
    return (m['checkoutSessionId'] ??
            m['sessionId'] ??
            m['checkout_session_id'] ??
            m['id'])
        ?.toString();
  }

  bool? get asBool {
    if (json is bool) return json as bool;
    final t = body.trim().toLowerCase();
    if (t == 'true') return true;
    if (t == 'false') return false;
    return null;
  }
}

bool offDenied(HttpHit h) {
  final raw = h.body.toLowerCase();
  return h.status == 400 &&
      (raw.contains('off-platform') || raw.contains('off platform'));
}

bool opened(HttpHit h) {
  final sid = h.sessionId ?? '';
  return h.ok && sid.startsWith('cs_');
}

bool belongDenied(HttpHit h) {
  final t = h.body.toLowerCase();
  return !h.ok &&
      (t.contains('does not belong') ||
          t.contains('not found') ||
          t.contains('forbidden') ||
          h.status == 401 ||
          h.status == 403);
}

class Rteh {
  final String url;
  final String anon;
  final String svc;
  final Map<String, String> env;
  final String e2eSecret;
  String? buyerJwt;
  String? sellerJwt;
  String? buyer2Jwt;
  String? buyerId;
  String? sellerId;
  String? buyer2Id;
  final findings = <Map<String, dynamic>>[];
  final notes = <Map<String, dynamic>>[];
  final blocked = <Map<String, dynamic>>[];
  final skipped = <Map<String, dynamic>>[];
  final probes = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdSessionIds = <String>[];
  final lensesHit = <String>{};
  final wellsTried = <String>{};

  Rteh._(this.url, this.anon, this.svc, this.env, this.e2eSecret);

  factory Rteh.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rteh._(
      url,
      envRequire(env, 'SUPABASE_ANON_KEY'),
      envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
      env,
      (env['FLEABER_STAGING_CRASH_INJECT_SECRET'] ??
              Platform.environment['FLEABER_STAGING_CRASH_INJECT_SECRET'] ??
              '')
          .trim(),
    );
  }

  Future<HttpHit> req(
    String method,
    String path, {
    String? jwt,
    Object? body,
    Map<String, String>? extra,
    bool service = false,
    Duration? timeout,
    bool auth = true,
  }) async {
    final key = service ? svc : anon;
    final uri = Uri.parse(path.startsWith('http')
        ? path
        : '$url${path.startsWith('/') ? path : '/$path'}');
    final h = <String, String>{
      if (auth) 'apikey': key,
      if (auth) 'Authorization': 'Bearer ${jwt ?? (service ? svc : anon)}',
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
      final rs = timeout == null
          ? await rq.close()
          : await rq.close().timeout(timeout);
      final text = await rs.transform(utf8.decoder).join();
      Object? parsed;
      try {
        parsed = text.isEmpty ? null : jsonDecode(text);
      } catch (_) {
        parsed = null;
      }
      return HttpHit(rs.statusCode, text, parsed, rs.headers.value('location'));
    } on TimeoutException {
      return HttpHit(598, 'client_timeout', {'error': 'client_timeout'});
    } on SocketException catch (e) {
      return HttpHit(599, 'socket $e', {'error': '$e'});
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
    bool service = false,
    String qs = '',
  }) {
    final q = qs.isEmpty ? '' : (qs.startsWith('?') ? qs : '?$qs');
    return req(
      method,
      '/functions/v1/$name$q',
      jwt: jwt,
      body: body,
      service: service,
    );
  }

  Future<HttpHit> e2e(
    String probe,
    Map<String, Object?> body, {
    String? seller,
    String? buyer,
  }) {
    return req(
      'POST',
      '/functions/v1/sec-fase2-e2e-oversell',
      service: true,
      body: {
        'probe': probe,
        'buyer_id': buyer ?? buyerId,
        'seller_id': seller ?? sellerId,
        ...body,
      },
      extra: e2eSecret.isEmpty ? null : {'x-fleaber-e2e-secret': e2eSecret},
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

  Future<void> ensureBuyer2() async {
    final email = '${prefix.toLowerCase()}-b2@fleaber.test';
    const pass = 'Rteh1908b2!xK';
    await req('POST', '/auth/v1/admin/users', service: true, body: {
      'email': email,
      'password': pass,
      'email_confirm': true,
    });
    buyer2Jwt = await signIn(email, pass);
    final me = await req('GET', '/auth/v1/user', jwt: buyer2Jwt);
    buyer2Id = (me.json is Map) ? (me.json as Map)['id'] as String? : null;
    if (buyer2Id != null) {
      await rest('PATCH', 'profiles?id=eq.$buyer2Id', service: true, body: {
        'full_name': '$prefix-B2',
        'handle': 'rteh1908b2',
        'hub_published': false,
        'is_live': false,
        'user_type': 'comprador',
      }, prefer: 'return=minimal');
    }
  }

  Future<String?> createProduct({
    String? title,
    int qty = 3,
    double price = 5.9,
  }) async {
    final h = await rest('POST', 'products', service: true, body: {
      'seller_id': sellerId,
      'title': title ?? '$prefix-sku',
      'price': price,
      'quantity': qty,
      'is_sold': false,
      'list_on_marketplace': true,
      'available_for_live': true,
      'description': prefix,
      'image_urls': <String>[],
    });
    final id = h.firstId;
    if (id != null) createdProductIds.add(id);
    if (!h.ok) note('product.fail', 'createProduct', h.brief);
    return id;
  }

  Future<Map<String, dynamic>?> productRow(String id) async {
    final h = await rest(
      'GET',
      'products?id=eq.$id&select=id,seller_id,title,price,quantity,is_sold,list_on_marketplace',
      service: true,
    );
    return h.map;
  }

  Future<String?> insertOrder({
    required String productId,
    String? buyer,
    String? jwt,
    String status = 'reserva_pendente',
    double price = 5.9,
    int qty = 1,
    String payment = 'Pagamento na App',
    bool service = false,
  }) async {
    final h = await rest(
      'POST',
      'orders',
      jwt: jwt,
      service: service,
      body: {
        'buyer_id': buyer ?? buyerId,
        'seller_id': sellerId,
        'product_id': productId,
        'price_total': price,
        'quantity': qty,
        'status': status,
        'payment_method': payment,
        'shipping_method': 'entrega em mão',
      },
    );
    final id = h.firstId;
    if (id != null) createdOrderIds.add(id);
    if (!h.ok) note('order.fail', 'insertOrder', h.brief);
    return id;
  }

  Future<HttpHit> insertOrderRaw({
    required String productId,
    required Object? payment,
    String? buyer,
    String? jwt,
    bool service = false,
    String status = 'reserva_pendente',
    double price = 5.9,
    int qty = 1,
    Map<String, Object?> extra = const {},
  }) {
    return rest(
      'POST',
      'orders',
      jwt: jwt,
      service: service,
      body: {
        'buyer_id': buyer ?? buyerId,
        'seller_id': sellerId,
        'product_id': productId,
        'price_total': price,
        'quantity': qty,
        'status': status,
        'payment_method': payment,
        'shipping_method': 'entrega em mão',
        ...extra,
      },
    ).then((h) {
      final id = h.firstId;
      if (id != null) createdOrderIds.add(id);
      if (!h.ok) note('order.raw.fail', 'insertOrderRaw', h.brief);
      return h;
    });
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,shipping_method,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,stock_units_applied,contract_unit_cents,contract_qty',
      service: true,
    );
    return h.map;
  }

  Future<HttpHit> patchOrder(
    String id,
    Map<String, Object?> body, {
    String? jwt,
    bool service = false,
  }) {
    return rest(
      'PATCH',
      'orders?id=eq.$id',
      jwt: jwt,
      service: service,
      body: body,
    );
  }

  Future<HttpHit> checkout({
    required String orderId,
    String? jwt,
    String? buyer,
    Object? amount = 590,
    String? productId,
    Map<String, Object?> extra = const {},
  }) {
    return edge('create-payment-intent', {
      'buyer_id': buyer ?? buyerId,
      'order_id': orderId,
      'amount': amount,
      'currency': 'eur',
      if (productId != null) 'product_id': productId,
      'shipping_method': 'mao',
      ...extra,
    }, jwt: jwt ?? buyerJwt);
  }

  Future<HttpHit> cpiOnce(Future<HttpHit> Function() fn) async {
    var h = await fn();
    if (h.status == 429) {
      await Future<void>.delayed(const Duration(seconds: 2));
      h = await fn();
    }
    trackSession(h);
    return h;
  }

  void trackSession(HttpHit h) {
    final sid = h.sessionId;
    if (sid != null && sid.startsWith('cs_')) createdSessionIds.add(sid);
  }

  Future<HttpHit> sqlOff(String method) {
    return rpc('batata_is_off_platform_payment', {'p_method': method},
        service: true);
  }

  Future<bool?> sqlOffBool(String method) async {
    final h = await sqlOff(method);
    return h.asBool;
  }

  String? parseE2eOrderId(HttpHit paid) {
    final pm = paid.map ?? {};
    return (pm['order_id'] ??
            (pm['order'] is Map ? (pm['order'] as Map)['id'] : null))
        ?.toString();
  }

  String? parseE2eProductId(HttpHit paid) {
    return paid.map?['product_id']?.toString();
  }

  Future<({String oid, String pid, String? pi, HttpHit hit})?> payToPago({
    String lens = 'EH-B',
    int initialQty = 2,
  }) async {
    final paid = await e2e('setup_paid_order', {'initial_qty': initialQty});
    note('fixture.paid', 'setup_paid_order Stripe TEST', paid.brief, lens: lens);
    final oid = parseE2eOrderId(paid);
    final pid = parseE2eProductId(paid);
    if (pid != null) createdProductIds.add(pid);
    if (oid == null || pid == null) return null;
    createdOrderIds.add(oid);
    final row = await orderRow(oid);
    return (
      oid: oid,
      pid: pid,
      pi: row?['stripe_payment_intent_id']?.toString(),
      hit: paid,
    );
  }

  Future<void> cancelOrders(Iterable<String> ids) async {
    for (final id in ids) {
      await rest(
        'PATCH',
        'orders?id=eq.$id',
        service: true,
        body: {'status': 'cancelado'},
        prefer: 'return=minimal',
      );
    }
  }

  Future<void> dumpAll([String file = 'pass1.json']) async {
    Object sanitize(Object? v) {
      if (v is HttpHit) return v.brief;
      if (v is Map) {
        return v.map((k, val) => MapEntry('$k', sanitize(val)));
      }
      if (v is List) return v.map(sanitize).toList();
      return v ?? '';
    }

    await dumpJson('${outDir()}/$file', {
      'stamp': stamp,
      'prefix': prefix,
      'auditor': 'REDTEAM_BLIND_EH_PAYMETHOD_POS_OPEN_v1',
      'lenses': lensesHit.toList()..sort(),
      'wells': wellsTried.toList()..sort(),
      'findings': sanitize(findings),
      'blocked': sanitize(blocked),
      'skipped': sanitize(skipped),
      'probes': sanitize(probes),
      'notes': sanitize(notes),
      'n_probes': probes.length,
      'n_classe_nova': probes.where((p) => p['classe_nova'] == true).length,
      'actors': {
        'buyer': buyerId,
        'seller': sellerId,
        'buyer2': buyer2Id,
      },
      'created': {
        'orders': createdOrderIds,
        'products': createdProductIds,
        'sessions': createdSessionIds,
      },
    });
  }

  void probe({
    required String id,
    required String surfaces,
    required String action,
    required Object http,
    required Object oracles,
    required String result,
    String? lens,
    String? poco,
    bool residual = false,
    bool countFinding = false,
    bool classeNova = false,
  }) {
    if (lens != null) lensesHit.add(lens);
    if (poco != null) wellsTried.add(poco);
    probes.add({
      'probe_id': id,
      'poco': poco ?? surfaces,
      'surfaces': surfaces,
      'action': action,
      'http': http is HttpHit ? http.brief : clip(http, 420),
      'oracles': oracles is String ? oracles : clip(oracles, 480),
      'result': result,
      if (lens != null) 'lens': lens,
      'residual': residual,
      'count_finding': countFinding,
      'classe_nova': classeNova,
    });
    stdout.writeln(
      'PROBE $id [$surfaces] $result classe_nova=${classeNova ? 'SIM' : 'NAO'} '
      '${residual ? 'RESIDUAL ' : ''}${clip(http, 140)}',
    );
  }

  void note(String id, String title, Object? ev, {String? lens}) {
    if (lens != null) lensesHit.add(lens);
    notes.add({
      'id': id,
      if (lens != null) 'lens': lens,
      'title': title,
      'ev': ev is HttpHit ? ev.brief : ev,
    });
    stdout.writeln('NOTE $id ${lens ?? ''} $title ${clip(ev, 240)}');
  }

  void skip(String id, String lens, String title, Object? ev) {
    lensesHit.add(lens);
    skipped.add({
      'id': id,
      'lens': lens,
      'title': title,
      'ev': ev is HttpHit ? ev.brief : ev,
    });
    stdout.writeln('SKIP $id [$lens] $title ${clip(ev, 180)}');
  }

  void block(String id, String lens, String title, Object? ev) {
    lensesHit.add(lens);
    blocked.add({
      'id': id,
      'lens': lens,
      'title': title,
      'ev': ev is HttpHit ? ev.brief : ev,
    });
    stdout.writeln('BLOCKED $id [$lens] $title ${clip(ev, 180)}');
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
  }) {
    lensesHit.add(lens);
    findings.add({
      'id': id,
      'lens': lens,
      'severity': severity,
      'title': title,
      'actor': actor,
      'pre': pre,
      'repro': repro,
      'expected': expected,
      'obtained': obtained,
      'proven': true,
    });
    stdout.writeln('FINDING $severity $id [$lens] $title');
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}

String sidOf(HttpHit h, [Map<String, dynamic>? row]) {
  final a = h.sessionId ?? '';
  if (a.startsWith('cs_')) return a;
  final b = '${row?['stripe_checkout_session_id'] ?? ''}';
  return b.startsWith('cs_') ? b : a;
}
