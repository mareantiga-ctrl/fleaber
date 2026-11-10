/// RED TEAM CEGO BJ — payout / wallet / refund pós-ATBE.
/// Staging fxdknzrqjenzqcvnwqqq only. Stripe TEST. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260902T1822';
const prefix = 'RTBJ-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

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

String repoRoot() {
  final cur = Directory.current.path;
  return cur.contains('redteam_blind_bj_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_bj_$stamp';

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
  final String? location;
  HttpHit(this.status, this.body, this.json, [this.location]);
  bool get ok => status >= 200 && status < 300;
  bool get denied => status >= 400;
  /// PostgREST 200 + [] = RLS filtrou, sem mutação.
  bool get mutated =>
      ok && body.trim() != '[]' && (list.isNotEmpty || (json is Map));
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

  String? get transferId =>
      map?['transferId']?.toString() ?? map?['stripe_transfer_id']?.toString();

  String? get err =>
      map?['message']?.toString() ??
      map?['hint']?.toString() ??
      map?['error']?.toString() ??
      map?['code']?.toString() ??
      snippet;
}

class Rtbj {
  final String url;
  final String anon;
  final String svc;
  final Map<String, String> env;
  final String e2eSecret;
  final String crashSecret;
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
  final lensesHit = <String>{};

  Rtbj._(this.url, this.anon, this.svc, this.env, this.e2eSecret, this.crashSecret);

  factory Rtbj.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtbj._(
      url,
      envRequire(env, 'SUPABASE_ANON_KEY'),
      envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
      env,
      (env['FLEABER_E2E_SECRET'] ??
              Platform.environment['FLEABER_E2E_SECRET'] ??
              env['FLEABER_STAGING_CRASH_INJECT_SECRET'] ??
              '')
          .trim(),
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
    String name, {
    Object? body,
    String? jwt,
    bool service = false,
    String method = 'POST',
    Map<String, String>? extra,
    String qs = '',
  }) {
    final path = qs.isEmpty
        ? '/functions/v1/$name'
        : '/functions/v1/$name$qs';
    return req(
      method,
      path,
      jwt: jwt,
      body: body,
      extra: extra,
      service: service,
    );
  }

  Future<HttpHit> connect(
    Object? body, {
    String? jwt,
    String method = 'POST',
    Map<String, String>? extra,
  }) {
    return edge(
      'create-connect-account',
      body: body,
      jwt: jwt ?? sellerJwt,
      method: method,
      extra: extra,
    );
  }

  Future<HttpHit> refundOrder(
    String orderId, {
    String? jwt,
    Object? extraBody,
    Map<String, String>? extra,
  }) {
    final body = <String, Object?>{
      'order_id': orderId,
      if (extraBody is Map) ...Map<String, Object?>.from(extraBody as Map),
    };
    return edge(
      'refund-order',
      body: body,
      jwt: jwt ?? sellerJwt,
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
        '${prefix.toLowerCase()}-b2@fleaber.test', 'Rtbj1822b2!xK');
    if (u == null) return;
    buyer2Jwt = u.jwt;
    buyer2Id = u.id;
  }

  Future<void> ensureSeller2() async {
    final u = await adminUser(
        '${prefix.toLowerCase()}-s2@fleaber.test', 'Rtbj1822s2!xK');
    if (u == null) return;
    seller2Jwt = u.jwt;
    seller2Id = u.id;
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,shipping_method,shipped_at,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,stock_units_applied',
      service: true,
    );
    return h.map;
  }

  Future<Map<String, dynamic>?> walletRow(String? id) async {
    if (id == null) return null;
    final h = await rest(
      'GET',
      'wallets?id=eq.$id&select=id,balance,stripe_account_id,updated_at',
      service: true,
    );
    return h.map;
  }

  Future<num> walletBal(String? id) async {
    final row = await walletRow(id);
    return numOf(row?['balance']) ?? 0;
  }

  Future<Map<String, num>> wallets() async => {
        'buyer': await walletBal(buyerId),
        'seller': await walletBal(sellerId),
        'buyer2': await walletBal(buyer2Id),
        'seller2': await walletBal(seller2Id),
      };

  Future<List<dynamic>> walletTxns({
    String? walletId,
    String? orderId,
    int limit = 20,
  }) async {
    final parts = <String>[];
    if (walletId != null) parts.add('wallet_id=eq.$walletId');
    if (orderId != null) parts.add('order_id=eq.$orderId');
    final qs = parts.isEmpty ? '' : '${parts.join('&')}&';
    final h = await rest(
      'GET',
      'wallet_transactions?${qs}select=id,wallet_id,amount,type,description,order_id,created_at&order=created_at.desc&limit=$limit',
      service: true,
    );
    return h.list;
  }

  Future<List<dynamic>> payoutLedger({String? userId, int limit = 12}) async {
    final q = userId == null ? '' : 'user_id=eq.$userId&';
    final h = await rest(
      'GET',
      'wallet_payout_ledger?${q}select=idempotency_key,user_id,amount_cents,amount_eur,status,stripe_transfer_id,balance_after,created_at,updated_at&order=created_at.desc&limit=$limit',
      service: true,
    );
    return h.list;
  }

  Future<String?> insertProduct({
    required double price,
    int qty = 3,
    String? seller,
    String? title,
  }) async {
    final h = await rest('POST', 'products', service: true, body: {
      'seller_id': seller ?? sellerId,
      'title': title ?? '$prefix-${DateTime.now().microsecondsSinceEpoch}',
      'price': price,
      'quantity': qty,
      'ref_code': 'RTBJ-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final id = h.firstId;
    if (id != null) createdProductIds.add(id);
    if (!h.ok) note('product.fail', 'insertProduct', h.brief);
    return id;
  }

  Future<String?> insertOrder({
    required String productId,
    String? jwt,
    String? buyer,
    String? seller,
    int qty = 1,
    double? priceTotal,
    String shipping = 'entrega em mão',
    String payment = 'Pagamento na app',
    Map<String, Object?> extra = const {},
  }) async {
    final body = <String, Object?>{
      'buyer_id': buyer ?? buyerId,
      'seller_id': seller ?? sellerId,
      'product_id': productId,
      'quantity': qty,
      'status': 'reserva_pendente',
      'payment_method': payment,
      'shipping_method': shipping,
      if (priceTotal != null) 'price_total': priceTotal,
      ...extra,
    };
    final h = await rest('POST', 'orders', jwt: jwt ?? buyerJwt, body: body);
    final id = h.firstId;
    if (id != null) createdOrderIds.add(id);
    if (!h.ok) note('order.fail', 'insertOrder', h.brief);
    return id;
  }

  String? parseE2eOrderId(HttpHit paid) {
    final pm = paid.map ?? {};
    final oid = (pm['order_id'] ??
            (pm['order'] is Map ? (pm['order'] as Map)['id'] : null))
        ?.toString();
    return oid;
  }

  String? parseE2eProductId(HttpHit paid) {
    return paid.map?['product_id']?.toString();
  }

  Future<String?> payOrder({String lens = 'BJ3'}) async {
    final paid = await e2e('setup_paid_order', {'initial_qty': 2});
    note('fixture.paid', 'setup_paid_order', paid.brief, lens: lens);
    final oid = parseE2eOrderId(paid);
    final pid = parseE2eProductId(paid);
    if (pid != null) createdProductIds.add(pid);
    if (oid == null) return null;
    createdOrderIds.add(oid);
    return oid;
  }

  Future<HttpHit> tryRelease(String oid, {String? jwt, bool service = false}) {
    return rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oid},
      jwt: jwt,
      service: service,
    );
  }

  Future<void> fixtureCreditSeller(num eur) async {
    final cur = await walletBal(sellerId);
    final hit = await rest(
      'PATCH',
      'wallets?id=eq.$sellerId',
      service: true,
      body: {'balance': (cur + eur).toDouble()},
    );
    note('fixture.credit', 'service_role PATCH wallets.balance +$eur', hit.brief);
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

  Future<void> expectDenied({
    required String id,
    required String lens,
    required String title,
    required HttpHit hit,
    required String actor,
    required String pre,
    required String repro,
    String severityIfOpen = 'P2',
    bool Function(HttpHit hit)? isSuccess,
  }) async {
    final success = isSuccess != null ? isSuccess(hit) : hit.ok;
    if (success) {
      hold(
        id: id,
        lens: lens,
        severity: severityIfOpen,
        title: title,
        actor: actor,
        pre: pre,
        repro: repro,
        expected: '4xx/denied',
        obtained: hit.brief,
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
      if (v is Set) return v.map(sanitize).toList();
      if (v is List) return v.map(sanitize).toList();
      return v ?? '';
    }

    await dumpJson('${outDir()}/$file', {
      'stamp': stamp,
      'prefix': prefix,
      'auditor': 'REDTEAM_BLIND_BJ_PAYOUT_POS_ATBE_v1',
      'lenses': lensesHit.toList()..sort(),
      'findings': sanitize(findings),
      'blocked': sanitize(blocked),
      'skipped': sanitize(skipped),
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
      },
    });
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
