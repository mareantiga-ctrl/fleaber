/// RED TEAM CEGO DF — payout charset allowlist pós-CVDA.
/// Staging fxdknzrqjenzqcvnwqqq only. Stripe TEST. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260906T1538';
const prefix = 'RTDF-$stamp';
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
  return cur.contains('redteam_blind_df_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_df_$stamp';

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
  String get snippet => clip(body);
  String get brief =>
      '$status ${clip(body, 220)} loc=${clip(location, 80)}';
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
      map?['transferId']?.toString() ??
      map?['stripe_transfer_id']?.toString() ??
      map?['id']?.toString();

  String? get err =>
      map?['message']?.toString() ??
      map?['hint']?.toString() ??
      map?['error']?.toString() ??
      map?['code']?.toString() ??
      snippet;

  bool get payoutOk =>
      ok && (map?['success'] == true || (map?['transferId'] != null));

  bool get crashInjected =>
      status == 500 && body.contains('crash_inject');
}

class Rtdf {
  final String url;
  final String anon;
  final String svc;
  final Map<String, String> env;
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
  final probes = <Map<String, dynamic>>[];

  Rtdf._(this.url, this.anon, this.svc, this.env, this.crashSecret);

  factory Rtdf.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtdf._(
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
    bool noAuth = false,
  }) async {
    final key = service ? svc : anon;
    final uri = Uri.parse(path.startsWith('http')
        ? path
        : '$url${path.startsWith('/') ? path : '/$path'}');
    final h = <String, String>{
      if (!noAuth) 'apikey': key,
      if (!noAuth) 'Authorization': 'Bearer ${jwt ?? (service ? svc : anon)}',
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
      jwt: service ? null : jwt,
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
    final q = qs.isEmpty ? '' : (qs.startsWith('?') ? qs : '?$qs');
    return req(
      method,
      '/functions/v1/$name$q',
      jwt: jwt,
      body: method == 'GET' ? null : body,
      extra: extra,
      service: service,
    );
  }

  Future<HttpHit> connect(
    Object body, {
    String? jwt,
    String method = 'POST',
    Map<String, String>? extra,
    String qs = '',
  }) async {
    HttpHit? last;
    for (var i = 0; i < 10; i++) {
      last = await edge(
        'create-connect-account',
        body: body,
        jwt: jwt ?? sellerJwt,
        method: method,
        extra: extra,
        qs: qs,
      );
      if (last.status != 429) return last;
      final wait = 20 + i * 12;
      stdout.writeln('RATE 429 connect; sleep ${wait}s');
      await Future<void>.delayed(Duration(seconds: wait));
    }
    return last!;
  }

  Future<HttpHit> refundOrder(
    String orderId, {
    String? jwt,
    Map<String, Object?> extraBody = const {},
    Map<String, String>? extra,
  }) {
    return edge(
      'refund-order',
      body: {'order_id': orderId, ...extraBody},
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
      extra: crashSecret.isEmpty
          ? null
          : {'x-fleaber-e2e-secret': crashSecret},
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

  Future<({String jwt, String id})?> adminUser(
    String email,
    String pass, {
    String userType = 'comprador',
  }) async {
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
        'user_type': userType,
      }, prefer: 'return=minimal');
      return (jwt: jwt, id: id);
    } catch (e) {
      note('adminUser.err', email, '$e');
      return null;
    }
  }

  Future<void> ensureBuyer2() async {
    final u = await adminUser(
        '${prefix.toLowerCase()}-b2@fleaber.test', 'Rtdf1538b2!xK');
    if (u == null) return;
    buyer2Jwt = u.jwt;
    buyer2Id = u.id;
  }

  Future<void> ensureSeller2() async {
    final u = await adminUser(
      '${prefix.toLowerCase()}-s2@fleaber.test',
      'Rtdf1538s2!xK',
      userType: 'vendedor',
    );
    if (u == null) return;
    seller2Jwt = u.jwt;
    seller2Id = u.id;
  }

  Future<num> walletBal(String? id) async {
    if (id == null) return 0;
    final h = await rest(
      'GET',
      'wallets?id=eq.$id&select=id,balance,stripe_account_id',
      service: true,
    );
    return numOf(h.map?['balance']) ?? 0;
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

  Future<void> ensureWalletBalance(String uid, num minEur) async {
    final row = await walletRow(uid);
    final bal = numOf(row?['balance']) ?? 0;
    if (bal >= minEur) return;
    final need = minEur - bal;
    if (row == null) {
      await rest('POST', 'wallets', service: true, body: {
        'id': uid,
        'balance': minEur,
      });
      return;
    }
    await rest(
      'PATCH',
      'wallets?id=eq.$uid',
      service: true,
      body: {'balance': bal + need},
      prefer: 'return=minimal',
    );
  }

  Future<List<Map<String, dynamic>>> payoutLogs({int limit = 8}) async {
    final h = await rest(
      'GET',
      'app_logs?category=eq.wallet_payout&select=error_message,device_info,created_at&order=created_at.desc&limit=$limit',
      service: true,
    );
    return h.list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> otherConnectAccounts(String uid) async {
    final h = await rest(
      'GET',
      'wallets?stripe_account_id=not.is.null&select=id,stripe_account_id,balance&limit=20',
      service: true,
    );
    return h.list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => '${e['id']}' != uid)
        .toList();
  }

  Future<List<Map<String, dynamic>>> payoutLedger(String uid, {int limit = 30}) async {
    final h = await rest(
      'GET',
      'wallet_payout_ledger?user_id=eq.$uid&select=idempotency_key,user_id,amount_cents,amount_eur,status,stripe_transfer_id,balance_after,created_at,updated_at&order=created_at.desc&limit=$limit',
      service: true,
    );
    return h.list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,shipping_method,shipped_at,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,stock_units_applied,completed_at',
      service: true,
    );
    return h.map;
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
    String lens = 'DF5',
    String? seller,
    String? buyer,
    int initialQty = 2,
  }) async {
    final paid = await e2e('setup_paid_order', {'initial_qty': initialQty},
        seller: seller, buyer: buyer);
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
    );
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

  Future<HttpHit> tryRelease(String oid, {String? jwt, bool service = false}) {
    return rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oid},
      jwt: jwt,
      service: service,
    );
  }

  void probe({
    required String id,
    required String payload,
    required Object httpBd,
    required String result,
    String? lens,
  }) {
    if (lens != null) lensesHit.add(lens);
    probes.add({
      'id': id,
      if (lens != null) 'lens': lens,
      'payload': payload,
      'http_bd': httpBd is HttpHit ? httpBd.brief : httpBd,
      'result': result,
    });
    stdout.writeln('PROBE $id [$result] ${clip(payload, 80)} ${clip(httpBd, 160)}');
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
    bool count = true,
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
      'count': count,
      'evidence': evidence ?? {},
    });
    stdout.writeln(
        '${count ? "FINDING" : "HOLD-EXACT/DESIGN"} $severity $id [$lens] $title');
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
    bool Function(HttpHit hit)? openIf,
    bool count = true,
  }) async {
    bool defaultOpen(HttpHit h) {
      if (h.payoutOk) return true;
      if (!h.ok) return false;
      if (h.json == false) return false;
      if (h.map != null && h.map!['ok'] == false) return false;
      if (h.map != null && h.map!['success'] == false) return false;
      return h.map?['url'] != null || h.map?['transferId'] != null;
    }

    final opened = openIf != null ? openIf(hit) : defaultOpen(hit);
    if (opened) {
      hold(
        id: id,
        lens: lens,
        severity: severityIfOpen,
        title: title,
        actor: actor,
        pre: pre,
        repro: repro,
        expected: 'denied',
        obtained: hit.brief,
        count: count,
      );
    } else {
      block(id, lens, title, hit);
    }
  }

  Future<Map<String, Object?>> pairPayout(
    String id,
    String keyA,
    String keyB, {
    String lens = 'DF4',
    int amount = 100,
  }) async {
    await ensureWalletBalance(sellerId!, 20);
    final before = await walletBal(sellerId);
    final ledBefore = await payoutLedger(sellerId!);
    final tidsBefore = ledBefore
        .map((r) => '${r['stripe_transfer_id']}')
        .where((s) => s.startsWith('tr_'))
        .toSet();
    final a = await connect({'amount': amount, 'idempotency_key': keyA});
    final b = await connect({'amount': amount, 'idempotency_key': keyB});
    final after = await walletBal(sellerId);
    final ledAfter = await payoutLedger(sellerId!);
    final tidsAfter = ledAfter
        .map((r) => '${r['stripe_transfer_id']}')
        .where((s) => s.startsWith('tr_'))
        .toSet();
    final newTids = tidsAfter.difference(tidsBefore);
    final ev = <String, Object?>{
      'keyA': keyA,
      'keyB': keyB,
      'keyA_units': keyA.codeUnits.toList(),
      'keyB_units': keyB.codeUnits.toList(),
      'hitA': a.brief,
      'hitB': b.brief,
      'tidA': a.transferId,
      'tidB': b.transferId,
      'new_transfer_ids': newTids.toList(),
      'new_transfer_count': newTids.length,
      'wallet_before': before,
      'wallet_after': after,
      'delta_eur': after - before,
      'payoutOkA': a.payoutOk,
      'payoutOkB': b.payoutOk,
      'idempotentB': b.map?['idempotent'] == true,
    };
    note('pair.$id', 'pair $id', ev, lens: lens);
    return ev;
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
      'auditor': 'REDTEAM_BLIND_DF_PAYOUT_POS_CVDA_v1',
      'lenses': lensesHit.toList()..sort(),
      'probes': sanitize(probes),
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
