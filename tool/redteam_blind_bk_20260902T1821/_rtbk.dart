/// RED TEAM CEGO BK — disputa / envio / devolução pós-ATBE.
/// Staging fxdknzrqjenzqcvnwqqq only. Stripe TEST. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260902T1821';
const prefix = 'RTBK-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

const orderSelect =
    'id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,'
    'payment_method,shipping_method,stripe_payment_intent_id,stripe_checkout_session_id,'
    'stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,'
    'stock_units_applied,completed_at,shipped_at,returned_at,proof_url';

const disputeSelect =
    'id,order_id,buyer_id,status,proof_photos,return_label_url,'
    'seller_refund_percent,seller_offer_type,seller_offer_set_by,seller_offer_set_at,'
    'buyer_decision,current_turn,created_at';

String clip(Object? v, [int n = 360]) {
  if (v is HttpHit) return clip(v.brief, n);
  Object enc(Object? x) {
    if (x is HttpHit) return x.brief;
    if (x is Set) return x.map(enc).toList();
    if (x is Map) return x.map((k, val) => MapEntry('$k', enc(val)));
    if (x is Iterable && x is! String && x is! List) {
      return x.map(enc).toList();
    }
    return x ?? '';
  }

  final s = v is String ? v : jsonEncode(enc(v));
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
  return cur.contains('redteam_blind_bk_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_bk_$stamp';

class HttpHit {
  final int status;
  final String body;
  final Object? json;
  final String? location;
  HttpHit(this.status, this.body, this.json, [this.location]);
  bool get ok => status >= 200 && status < 300;
  bool get denied => status >= 400;
  bool get noop => ok && (json is List && (json as List).isEmpty);
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

  String? get err =>
      map?['message']?.toString() ??
      map?['hint']?.toString() ??
      map?['error']?.toString() ??
      map?['code']?.toString() ??
      snippet;
}

class Rtbk {
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
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdDisputeIds = <String>[];
  final lensesHit = <String>{};
  /// Exact AY/BE residuals — documented, not counted in P0–P3.
  final residuals = <Map<String, dynamic>>[];

  Rtbk._(this.url, this.anon, this.svc, this.env, this.e2eSecret);

  factory Rtbk.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtbk._(
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

  String get storageBase =>
      'https://$projectMust.supabase.co/storage/v1/object/authenticated/fleaber_private';

  String needle(String? buyer, String oid) =>
      'order_disputes/${buyer ?? buyerId}/$oid';

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
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      ...?extra,
    };
    final client = HttpClient();
    try {
      final rq = await client.openUrl(method, uri);
      rq.followRedirects = false;
      rq.maxRedirects = 0;
      h.forEach(rq.headers.set);
      if (body != null) {
        rq.add(utf8.encode(body is String ? body : jsonEncode(body)));
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
    bool service = false,
    Map<String, String>? extra,
  }) {
    return req(
      'POST',
      '/functions/v1/$name',
      jwt: jwt,
      body: body,
      service: service,
      extra: extra,
    );
  }

  Future<HttpHit> e2e(String probe, Map<String, Object?> body,
      {String? seller, String? buyer}) {
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

  Future<({String jwt, String id})?> adminUser(String email, String pass) async {
    await req('POST', '/auth/v1/admin/users', service: true, body: {
      'email': email,
      'password': pass,
      'email_confirm': true,
    });
    try {
      final jwt = await signIn(email, pass);
      final me = await req('GET', '/auth/v1/user', jwt: jwt);
      final id = (me.json is Map) ? (me.json as Map)['id'] as String? : null;
      if (id == null) return null;
      await rest('PATCH', 'profiles?id=eq.$id', service: true, body: {
        'full_name': email.split('@').first,
        'handle': email.split('@').first.replaceAll(RegExp(r'[^a-z0-9]'), ''),
        'hub_published': false,
        'is_live': false,
      }, prefer: 'return=minimal');
      return (jwt: jwt, id: id);
    } catch (e) {
      note('adminUser.err', email, '$e');
      return null;
    }
  }

  Future<void> ensureBuyer2() async {
    final u = await adminUser(
        '${prefix.toLowerCase()}-b2@fleaber.test', 'Rtbk1821b2!xK');
    if (u == null) return;
    buyer2Jwt = u.jwt;
    buyer2Id = u.id;
  }

  Future<void> ensureSeller2() async {
    final u = await adminUser(
        '${prefix.toLowerCase()}-s2@fleaber.test', 'Rtbk1821s2!xK');
    if (u == null) return;
    seller2Jwt = u.jwt;
    seller2Id = u.id;
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=$orderSelect',
      service: true,
    );
    return h.map;
  }

  Future<Map<String, dynamic>?> disputeByOrder(String oid) async {
    final h = await rest(
      'GET',
      'order_disputes?order_id=eq.$oid&select=$disputeSelect&order=created_at.desc',
      service: true,
    );
    return h.map;
  }

  Future<num?> walletBal(String? uid) async {
    if (uid == null) return null;
    final h = await rest(
      'GET',
      'wallets?id=eq.$uid&select=balance,id',
      service: true,
    );
    return numOf(h.map?['balance']);
  }

  Future<Map<String, num?>> wallets() async => {
        'buyer': await walletBal(buyerId),
        'seller': await walletBal(sellerId),
        'buyer2': await walletBal(buyer2Id),
        'seller2': await walletBal(seller2Id),
      };

  Future<int?> productQty(String pid) async {
    final h = await rest(
      'GET',
      'products?id=eq.$pid&select=id,quantity,is_sold,price',
      service: true,
    );
    return numOf(h.map?['quantity'])?.round();
  }

  Future<HttpHit> patchOrder(String oid, Map<String, Object?> body,
      {String? jwt, bool service = false}) {
    return rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: jwt,
      body: body,
      service: service,
    );
  }

  Future<HttpHit> openDispute(String oid,
      {String? jwt, String? buyer, Map<String, Object?> extra = const {}}) async {
    final h = await rest('POST', 'order_disputes', jwt: jwt ?? buyerJwt, body: {
      'order_id': oid,
      'buyer_id': buyer ?? buyerId,
      'reason': extra['reason'] ?? 'danificado',
      'status': extra['status'] ?? 'aberta',
      ...extra,
    });
    final id = h.firstId;
    if (id != null) createdDisputeIds.add(id);
    return h;
  }

  Future<HttpHit> patchDispute(String did, Map<String, Object?> body,
      {String? jwt}) {
    return rest('PATCH', 'order_disputes?id=eq.$did', jwt: jwt, body: body);
  }

  /// Stripe TEST captured order (status=pago).
  Future<Map<String, dynamic>?> setupPaid(
      {int initialQty = 2, String? buyer, String? seller}) async {
    final h = await e2e('setup_paid_order', {'initial_qty': initialQty},
        buyer: buyer, seller: seller);
    note('setup_paid', 'setup_paid_order', h.brief);
    final m = h.map;
    final oid = m?['order_id']?.toString();
    if (oid != null) createdOrderIds.add(oid);
    final pid = m?['product_id']?.toString();
    if (pid != null) createdProductIds.add(pid);
    if (h.ok && oid != null) return m;
    return null;
  }

  Future<bool> toConcluido(String oid, {String? jwt}) async {
    await patchOrder(oid, {'shipping_method': 'entrega em mão'}, service: true);
    final h = await patchOrder(oid, {'status': 'concluido'}, jwt: jwt ?? buyerJwt);
    final row = await orderRow(oid);
    final st = '${row?['status']}'.toLowerCase();
    note('toConcluido', oid, {'patch': h.brief, 'status': st});
    return st == 'concluido';
  }

  Future<bool> toEnviado(String oid, {String? jwt}) async {
    final h = await patchOrder(oid, {'status': 'enviado'}, jwt: jwt ?? sellerJwt);
    final row = await orderRow(oid);
    note('toEnviado', oid, {'patch': h.brief, 'status': row?['status']});
    return '${row?['status']}'.toLowerCase() == 'enviado';
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

  void residual(String id, String title, Object? ev) {
    residuals.add({
      'id': id,
      'title': title,
      'ev': ev is HttpHit ? ev.brief : ev,
      'note': 'exacto AY/BE — não conta',
    });
    stdout.writeln('RESIDUAL AY/BE $id $title ${clip(ev, 180)}');
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

  Future<void> expectDenied({
    required String id,
    required String lens,
    required String title,
    required HttpHit hit,
    required String actor,
    required String pre,
    required String repro,
    String severityIfOpen = 'P2',
    bool treatNoopAsDenied = true,
    Map<String, Object?>? evidence,
  }) async {
    final persisted = hit.ok && !hit.noop;
    if (persisted) {
      hold(
        id: id,
        lens: lens,
        severity: severityIfOpen,
        title: title,
        actor: actor,
        pre: pre,
        repro: repro,
        expected: '4xx ou 200 []',
        obtained: hit.brief,
        evidence: evidence,
      );
    } else {
      block(id, lens, title, hit);
    }
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
      'auditor': 'REDTEAM_BLIND_BK_DISPUTA_POS_ATBE_v1',
      'production_touched': false,
      'fase4': false,
      'corrections_applied': false,
      'lenses': lensesHit.toList()..sort(),
      'findings': sanitize(findings),
      'blocked': sanitize(blocked),
      'skipped': sanitize(skipped),
      'residuals_ay_be': sanitize(residuals),
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

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
