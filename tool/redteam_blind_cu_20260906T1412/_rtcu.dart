/// RED TEAM CEGO CU — disputa / provas / path pós-allowlist.
/// Staging fxdknzrqjenzqcvnwqqq only. Stripe TEST. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260906T1412';
const prefix = 'RTCU-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';
const storageHost =
    'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1';

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
  return cur.contains('redteam_blind_cu_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_cu_$stamp';

class HttpHit {
  final int status;
  final String body;
  final Object? json;
  final String? location;
  HttpHit(this.status, this.body, this.json, [this.location]);
  bool get ok => status >= 200 && status < 300;
  String get snippet => clip(body);
  String get brief => '$status ${clip(body, 240)}';
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

class Rtci {
  final String url;
  final String anon;
  final String svc;
  final Map<String, String> env;
  final String e2eSecret;
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
  final blocked = <Map<String, dynamic>>[];
  final skipped = <Map<String, dynamic>>[];
  final probes = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdDisputeIds = <String>[];
  final lensesHit = <String>{};
  final wellsTried = <String>{};

  Rtci._(this.url, this.anon, this.svc, this.env, this.e2eSecret);

  factory Rtci.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtci._(
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
        if (body is List<int>) {
          rq.add(body);
        } else {
          final bytes = utf8.encode(body is String ? body : jsonEncode(body));
          rq.add(bytes);
        }
      }
      final rs = await rq.close();
      final raw = await rs.fold<List<int>>(<int>[], (a, b) {
        a.addAll(b);
        return a;
      });
      String text;
      try {
        text = utf8.decode(raw);
      } catch (_) {
        text = 'binary:${raw.length}b';
      }
      Object? parsed;
      try {
        parsed = text.isEmpty || text.startsWith('binary:')
            ? null
            : jsonDecode(text);
      } catch (_) {
        parsed = null;
      }
      return HttpHit(rs.statusCode, text, parsed, rs.headers.value('location'));
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
    String qs = '',
  }) {
    final q = qs.isEmpty ? '' : (qs.startsWith('?') ? qs : '?$qs');
    return req(
      method,
      '/functions/v1/$name$q',
      jwt: jwt,
      body: body,
      extra: extra,
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
        'user_type': 'comprador',
      }, prefer: 'return=minimal');
    }
    return id;
  }

  Future<void> ensureBuyer2() async {
    final email = '${prefix.toLowerCase()}-b2@fleaber.test';
    const pass = 'Rtcu1412b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtcu1412b2',
      name: '$prefix-B2',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2() async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rtcu1412s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtcu1412s2',
      name: '$prefix-S2',
    );
    if (seller2Id != null) {
      await rest('PATCH', 'profiles?id=eq.$seller2Id', service: true, body: {
        'user_type': 'vendedor',
      }, prefer: 'return=minimal');
    }
    seller2Jwt = await signIn(email, pass);
  }

  Future<Map<String, dynamic>?> productRow(String id) async {
    final h = await rest(
      'GET',
      'products?id=eq.$id&select=id,seller_id,title,price,quantity,is_sold,list_on_marketplace',
      service: true,
    );
    return h.map;
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,shipping_method,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,stock_units_applied,shipped_at,wallet_release_processed_at,wallet_refund_processed_at,completed_at,returned_at,proof_url',
      service: true,
    );
    return h.map;
  }

  Future<Map<String, dynamic>?> disputeRow(String id) async {
    final h = await rest(
      'GET',
      'order_disputes?id=eq.$id&select=id,order_id,buyer_id,status,proof_photos,return_label_url,current_turn,reason,seller_refund_percent,seller_offer_type,seller_offer_set_by,description',
      service: true,
    );
    return h.map;
  }

  Future<HttpHit> insertDispute({
    required String orderId,
    String? jwt,
    String? buyer,
    String status = 'aberta',
    String reason = 'danificado',
    String description = 'RTCU prova disputa artigo danificado no envio.',
    List<String>? photos,
    Map<String, Object?> extra = const {},
  }) {
    return rest('POST', 'order_disputes', jwt: jwt ?? buyerJwt, body: {
      'order_id': orderId,
      'buyer_id': buyer ?? buyerId,
      'reason': reason,
      'description': description,
      'proof_photos': photos ?? <String>[],
      'status': status,
      'current_turn': 'vendedor',
      ...extra,
    }).then((h) {
      final id = h.firstId;
      if (id != null) createdDisputeIds.add(id);
      return h;
    });
  }

  Future<HttpHit> patchDispute(
    String id,
    Map<String, Object?> body, {
    String? jwt,
    bool service = false,
  }) {
    return rest('PATCH', 'order_disputes?id=eq.$id',
        jwt: jwt, service: service, body: body);
  }

  Future<HttpHit> insertReply({
    required String disputeId,
    String? jwt,
    String? sender,
    String message = 'RTCU reply',
    List<String>? photos,
  }) {
    return rest('POST', 'order_dispute_replies', jwt: jwt ?? buyerJwt, body: {
      'dispute_id': disputeId,
      'sender_id': sender ?? buyerId,
      'message': message,
      'proof_photos': photos ?? <String>[],
    });
  }

  Future<HttpHit> patchOrder(
    String id,
    Map<String, Object?> body, {
    String? jwt,
    bool service = false,
  }) {
    return rest('PATCH', 'orders?id=eq.$id',
        jwt: jwt, service: service, body: body);
  }

  Future<HttpHit> refund(
    String orderId, {
    String? jwt,
    bool service = false,
    Map<String, Object?> extra = const {},
  }) {
    return edge(
      'refund-order',
      {'order_id': orderId, ...extra},
      jwt: jwt ?? sellerJwt,
      service: service,
    );
  }

  Future<HttpHit> storage(
    String method,
    String objectPath, {
    String? jwt,
    List<int>? bytes,
    String contentType = 'application/octet-stream',
    bool service = false,
    Object? jsonBody,
    Map<String, String>? extra,
  }) {
    return req(
      method,
      objectPath.startsWith('/storage') ? objectPath : '/storage/v1/$objectPath',
      jwt: jwt,
      service: service,
      body: jsonBody ?? (bytes == null ? null : bytes),
      extra: {
        if (bytes != null) 'Content-Type': contentType,
        if (jsonBody != null) 'Content-Type': 'application/json',
        ...?extra,
      },
    );
  }

  String disputeObj(String uid, String oid, String file) =>
      'order_disputes/$uid/$oid/$file';

  Future<HttpHit> storageUpload({
    required String objectName,
    required List<int> bytes,
    String? jwt,
    String contentType = 'image/png',
  }) {
    return storage(
      'POST',
      'object/fleaber_private/$objectName',
      jwt: jwt,
      bytes: bytes,
      contentType: contentType,
      extra: {'x-upsert': 'true'},
    );
  }

  Future<HttpHit> storageList({
    required String prefix,
    String? jwt,
    int limit = 100,
  }) {
    return storage(
      'POST',
      'object/list/fleaber_private',
      jwt: jwt,
      jsonBody: {'prefix': prefix, 'limit': limit},
    );
  }

  Future<HttpHit> storageGet(String objectName, {String? jwt}) {
    return storage(
      'GET',
      'object/authenticated/fleaber_private/$objectName',
      jwt: jwt,
    );
  }

  Future<String?> signObject(String objectName, {String? jwt}) async {
    final h = await storage(
      'POST',
      'object/sign/fleaber_private/$objectName',
      jwt: jwt,
      jsonBody: {'expiresIn': 3600},
    );
    final signed = h.map?['signedURL']?.toString() ??
        h.map?['signedUrl']?.toString();
    if (signed == null || signed.isEmpty) return null;
    if (signed.startsWith('http')) return signed;
    return '$storageHost$signed';
  }

  String? get stripeTestKey {
    final v = (env['STRIPE_SECRET_KEY'] ??
            Platform.environment['STRIPE_SECRET_KEY'] ??
            '')
        .trim();
    if (v.startsWith('sk_test_')) return v;
    return null;
  }

  Future<HttpHit> stripe(
    String method,
    String path, {
    Map<String, String>? fields,
  }) async {
    final sk = stripeTestKey;
    if (sk == null) return HttpHit(0, 'no_sk_test', {'error': 'no_sk_test'});
    final uri = Uri.parse(
        path.startsWith('http') ? path : 'https://api.stripe.com$path');
    final client = HttpClient();
    try {
      final rq = await client.openUrl(method, uri);
      rq.headers.set('Authorization', 'Bearer $sk');
      if (fields != null) {
        rq.headers.contentType =
            ContentType('application', 'x-www-form-urlencoded');
        rq.add(utf8.encode(fields.entries
            .map((e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
            .join('&')));
      }
      final rs = await rq.close();
      final text = await rs.transform(utf8.decoder).join();
      Object? parsed;
      try {
        parsed = text.isEmpty ? null : jsonDecode(text);
      } catch (_) {
        parsed = null;
      }
      return HttpHit(rs.statusCode, text, parsed);
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpHit> stripePi(String pi) =>
      stripe('GET', '/v1/payment_intents/$pi?expand[]=latest_charge');

  Future<HttpHit> stripeRefunds(String pi) =>
      stripe('GET', '/v1/refunds?payment_intent=$pi&limit=10');

  Future<num> walletBal(String? id) async {
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

  Future<Map<String, num>> wallets() async {
    return {
      'buyer': await walletBal(buyerId),
      'seller': await walletBal(sellerId),
      'buyer2': await walletBal(buyer2Id),
      'seller2': await walletBal(seller2Id),
    };
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

  Future<({String oid, String pid, String? pi})?> payToPago({
    String lens = 'CO1',
    String? seller,
    String? buyer,
    int initialQty = 2,
  }) async {
    final paid = await e2e('setup_paid_order', {'initial_qty': initialQty},
        seller: seller, buyer: buyer);
    note('fixture.paid', 'setup_paid_order Stripe TEST', paid.brief, lens: lens.isEmpty ? 'CU7' : lens);
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
    );
  }

  Future<bool> toEnviado(String oid, {String? jwt}) async {
    final h = await patchOrder(oid, {'status': 'enviado'}, jwt: jwt ?? sellerJwt);
    final row = await orderRow(oid);
    note('fsm.enviado', 'seller → enviado', {
      'hit': h.brief,
      'status': row?['status'],
      'shipped_at': row?['shipped_at'],
    }, lens: 'CU5');
    return row?['status']?.toString() == 'enviado';
  }

  Future<bool> toConcluido(String oid, {String? jwt}) async {
    final h =
        await patchOrder(oid, {'status': 'concluido'}, jwt: jwt ?? buyerJwt);
    final row = await orderRow(oid);
    note('fsm.concluido', 'buyer → concluido', {
      'hit': h.brief,
      'status': row?['status'],
    }, lens: 'CU5');
    return row?['status']?.toString() == 'concluido';
  }

  Future<HttpHit> stockCheck(String productId,
      {String? exclude, int need = 1}) {
    return rpc('batata_product_checkout_available', {
      'p_product_id': productId,
      if (exclude != null) 'p_exclude_order_id': exclude,
      'p_need_qty': need,
    }, jwt: buyerJwt);
  }

  void well(String w) => wellsTried.add(w);

  void probe({
    required String id,
    required String matrix,
    required String payload,
    required String http,
    String? bd,
    required String result,
  }) {
    probes.add({
      'id': id,
      'matrix': matrix,
      'payload': payload,
      'http': http,
      'bd': bd ?? '',
      'result': result,
    });
    stdout.writeln('PROBE $result $id [$matrix] $http');
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
    bool proven = true,
    Map<String, Object?>? evidence,
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
      'proven': proven,
      'evidence': evidence ?? {},
    });
    stdout.writeln('FINDING $severity $id [$lens] $title');
  }

  Future<void> dumpAll([String file = 'findings.json']) async {
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
      'lenses': lensesHit.toList()..sort(),
      'wells': wellsTried.toList()..sort(),
      'findings': sanitize(findings),
      'blocked': sanitize(blocked),
      'skipped': sanitize(skipped),
      'probes': sanitize(probes),
      'notes': sanitize(notes),
      'actors': {
        'buyer': buyerId,
        'seller': sellerId,
        'buyer2': buyer2Id,
        'seller2': seller2Id,
      },
      'created': {
        'orders': createdOrderIds,
        'products': createdProductIds,
        'disputes': createdDisputeIds,
      },
    });
  }
}

Future<List<HttpHit>> parallel(List<Future<HttpHit>> jobs) => Future.wait(jobs);

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
