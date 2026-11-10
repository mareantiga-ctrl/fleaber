/// RED TEAM CEGO DL — Edge settle / tip / refund / webhook pós-DBDG.
/// Staging fxdknzrqjenzqcvnwqqq only. Stripe TEST. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260906T1612';
const prefix = 'RTDL-$stamp';
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
  return cur.contains('redteam_blind_dl_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_dl_$stamp';

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
  String get snippet => clip(body);
  String get brief =>
      '$status ${clip(body, 240)} loc=${clip(location, 80)}';
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

  String? get sessionId =>
      map?['checkoutSessionId']?.toString() ??
      map?['sessionId']?.toString() ??
      map?['checkout_session_id']?.toString();

  String? get tipId =>
      map?['tipId']?.toString() ?? map?['tip_id']?.toString();

  String? get transferId =>
      map?['transferId']?.toString() ??
      map?['stripe_transfer_id']?.toString();

  bool get payoutOk =>
      ok && (map?['success'] == true || map?['transferId'] != null);
}

class Rtdl {
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
  final probes = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdLiveIds = <String>[];
  final createdTipIds = <String>[];
  final lensesHit = <String>{};

  Rtdl._(this.url, this.anon, this.svc, this.env, this.crashSecret);

  factory Rtdl.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtdl._(
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
        rq.add(utf8.encode(body is String ? body : jsonEncode(body)));
      }
      final rs = await rq.close().timeout(const Duration(seconds: 45));
      final text = await rs.transform(utf8.decoder).join();
      Object? parsed;
      try {
        parsed = text.isEmpty ? null : jsonDecode(text);
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
    String method = 'POST',
    bool service = false,
    String? qs,
    Map<String, String>? extra,
  }) {
    final path = qs == null || qs.isEmpty
        ? '/functions/v1/$name'
        : '/functions/v1/$name?$qs';
    return req(
      method,
      path,
      jwt: jwt,
      body: method == 'GET' ? null : body,
      extra: extra,
      service: service,
    );
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
      final rs = await rq.close().timeout(const Duration(seconds: 45));
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

  Future<HttpHit> stripeSession(String sid, {bool expandPi = false}) {
    final q = expandPi ? '?expand[]=payment_intent' : '';
    return stripe('GET', '/v1/checkout/sessions/$sid$q');
  }

  Future<HttpHit> stripeExpire(String sid) {
    return stripe('POST', '/v1/checkout/sessions/$sid/expire');
  }

  Future<HttpHit> stripePatchSessionMeta(
    String sid,
    Map<String, String> meta,
  ) {
    final fields = <String, String>{};
    meta.forEach((k, v) => fields['metadata[$k]'] = v);
    return stripe('POST', '/v1/checkout/sessions/$sid', fields: fields);
  }

  Future<HttpHit> stripeConfirmPi(String pi) {
    return stripe('POST', '/v1/payment_intents/$pi/confirm', fields: {
      'payment_method': 'pm_card_visa',
    });
  }

  String? piFromSession(HttpHit sess) {
    final pi = sess.map?['payment_intent'];
    if (pi is String && pi.startsWith('pi_')) return pi;
    if (pi is Map && pi['id'] is String) return pi['id'] as String;
    return null;
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
    String userType = 'comprador',
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
    const pass = 'Rtdl1612b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtdl1612b2',
      name: '$prefix-B2',
      userType: 'comprador',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2() async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rtdl1612s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtdl1612s2',
      name: '$prefix-S2',
      userType: 'vendedor',
    );
    seller2Jwt = await signIn(email, pass);
  }

  Future<Map<String, dynamic>?> profile(String id) async {
    final h = await rest(
      'GET',
      'profiles?id=eq.$id&select=id,handle,hub_published,user_type,full_name,is_live',
      service: true,
    );
    return h.map;
  }

  Future<void> setHub(String id, bool published) async {
    await rest('PATCH', 'profiles?id=eq.$id', service: true, body: {
      'hub_published': published,
    }, prefer: 'return=minimal');
  }

  Future<void> restoreSeller1Published() async {
    if (sellerId == null) return;
    await rest('PATCH', 'profiles?id=eq.$sellerId', service: true, body: {
      'hub_published': true,
    }, prefer: 'return=minimal');
  }

  Future<String?> insertLive({
    String? seller,
    bool active = true,
    String status = 'live',
    String? title,
  }) async {
    final sid = seller ?? sellerId;
    final h = await rest('POST', 'lives', service: true, body: {
      'seller_id': sid,
      'vendedor_id': sid,
      'title': title ?? '$prefix live',
      'status': status,
      'is_active': active,
      'viewer_count': 0,
    });
    final id = h.firstId;
    if (id != null) createdLiveIds.add(id);
    if (!h.ok) note('live.fail', 'insertLive', h.brief);
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

  Future<String?> createProduct({
    String? seller,
    String? title,
    int qty = 3,
    double price = 12.0,
    bool listed = true,
    bool sold = false,
  }) async {
    final h = await rest('POST', 'products', service: true, body: {
      'seller_id': seller ?? sellerId,
      'title': title ?? '$prefix-sku',
      'price': price,
      'quantity': qty,
      'is_sold': sold,
      'list_on_marketplace': listed,
      'available_for_live': false,
      'description': prefix,
      'image_urls': <String>[],
    });
    final id = h.firstId;
    if (id != null) createdProductIds.add(id);
    if (!h.ok) note('product.fail', 'createProduct', h.brief);
    return id;
  }

  Future<String?> insertOrder({
    required String productId,
    String? buyer,
    String? seller,
    double price = 12.0,
    int qty = 1,
    String status = 'reserva_pendente',
    String shipping = 'entrega em mão',
    String payment = 'Pagamento na app',
  }) async {
    final h = await rest('POST', 'orders', service: true, body: {
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
    if (!h.ok) note('order.fail', 'insertOrder', h.brief);
    return id;
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,shipping_method,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,stock_units_applied,completed_at',
      service: true,
    );
    return h.map;
  }

  Future<HttpHit> checkout({
    required String orderId,
    String? jwt,
    String? buyer,
    Object? amount = 1,
    String? productId,
    String? seller,
    String shipping = 'mao',
    Map<String, Object?> extra = const {},
  }) {
    return edge(
      'create-payment-intent',
      jwt: jwt ?? buyerJwt,
      body: {
        'buyer_id': buyer ?? buyerId,
        'order_id': orderId,
        'amount': amount,
        if (productId != null) 'product_id': productId,
        if (seller != null) 'seller_id': seller,
        'shipping_method': shipping,
        'currency': 'eur',
        ...extra,
      },
    );
  }

  Future<HttpHit> settleGet(String sessionId, {String extraQs = ''}) {
    final extra = extraQs.isEmpty
        ? ''
        : (extraQs.startsWith('&') ? extraQs : '&$extraQs');
    return edge(
      'create-payment-intent',
      method: 'GET',
      qs: 'checkout_return=success&session_id=$sessionId$extra',
    );
  }

  Future<HttpHit> tipCheckout({
    required String liveId,
    required String seller,
    Object amountEur = 2,
    String? jwt,
    Map<String, Object?> extra = const {},
  }) {
    return edge(
      'create-live-tip-checkout',
      jwt: jwt ?? buyer2Jwt ?? buyerJwt,
      body: {
        'live_id': liveId,
        'seller_id': seller,
        'amount_eur': amountEur,
        ...extra,
      },
    );
  }

  Future<HttpHit> tipSettleGet(String sessionId, {String? jwt}) {
    return edge(
      'create-live-tip-checkout',
      method: 'GET',
      jwt: jwt,
      qs: 'checkout_return=success&session_id=$sessionId',
    );
  }

  Future<HttpHit> refundOrder(String orderId, {String? jwt}) {
    return edge('refund-order', body: {'order_id': orderId}, jwt: jwt ?? sellerJwt);
  }

  Future<HttpHit> tryRelease(String oid, {String? jwt, bool service = false}) {
    return rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oid},
      jwt: jwt,
      service: service,
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

  Future<({String oid, String pid, String? pi})?> payToPago({
    String lens = 'DL3',
    String? seller,
    String? buyer,
    int initialQty = 2,
  }) async {
    final paid = await e2e('setup_paid_order', {'initial_qty': initialQty},
        seller: seller, buyer: buyer);
    note('fixture.paid', 'setup_paid_order Stripe TEST', paid.brief, lens: lens);
    final pm = paid.map ?? {};
    final oid = (pm['order_id'] ??
            (pm['order'] is Map ? (pm['order'] as Map)['id'] : null))
        ?.toString();
    final pid = pm['product_id']?.toString();
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

  Future<HttpHit> connect(
    Object body, {
    String? jwt,
  }) async {
    HttpHit? last;
    for (var i = 0; i < 8; i++) {
      last = await edge(
        'create-connect-account',
        body: body,
        jwt: jwt ?? sellerJwt,
      );
      if (last.status != 429) return last;
      final wait = 15 + i * 10;
      stdout.writeln('RATE 429 connect; sleep ${wait}s');
      await Future<void>.delayed(Duration(seconds: wait));
    }
    return last!;
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

  Future<List<Map<String, dynamic>>> payoutLedger(String uid,
      {int limit = 30}) async {
    final h = await rest(
      'GET',
      'wallet_payout_ledger?user_id=eq.$uid&select=idempotency_key,user_id,amount_cents,amount_eur,status,stripe_transfer_id,balance_after,created_at&order=created_at.desc&limit=$limit',
      service: true,
    );
    return h.list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Set<String>> transferIds(String uid) async {
    final led = await payoutLedger(uid);
    return led
        .map((r) => '${r['stripe_transfer_id']}')
        .where((s) => s.startsWith('tr_'))
        .toSet();
  }

  void probe({
    required String id,
    required String edgeRpc,
    required String payload,
    required Object http,
    Object? stripeBd,
    required String result,
    String? lens,
    bool countFinding = false,
  }) {
    if (lens != null) lensesHit.add(lens);
    probes.add({
      'probe_id': id,
      'edge_rpc': edgeRpc,
      'payload': payload,
      'http': http is HttpHit ? http.brief : clip(http, 320),
      'stripe_bd': stripeBd == null ? '' : clip(stripeBd, 280),
      'result': result,
      if (lens != null) 'lens': lens,
      'count_finding': countFinding,
    });
    stdout.writeln('PROBE $id [$result] ${clip(payload, 90)} ${clip(http, 140)}');
  }

  void note(String id, String title, Object? ev, {String? lens}) {
    if (lens != null) lensesHit.add(lens);
    notes.add({
      'id': id,
      if (lens != null) 'lens': lens,
      'title': title,
      'ev': ev is HttpHit ? ev.brief : ev,
    });
    stdout.writeln('NOTE $id ${lens ?? ''} $title ${clip(ev, 220)}');
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
    bool count = true,
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
      'count': count,
    });
    stdout.writeln(
        '${count ? "FINDING" : "HOLD"} $severity $id [$lens] $title');
  }

  bool orderPaid(Map<String, dynamic>? row) {
    final st = '${row?['status'] ?? ''}'.toLowerCase();
    return st == 'pago' ||
        st == 'enviado' ||
        st == 'entregue' ||
        st == 'concluido';
  }

  bool tipCredited(String status, num delta) {
    final st = status.toLowerCase();
    return st == 'paid' || st == 'settled' || delta > 0;
  }

  Future<void> dumpAll(String file) async {
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
      'auditor': 'REDTEAM_BLIND_DL_EDGE_SETTLE_POS_DBDG_v1',
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
        'lives': createdLiveIds,
        'tips': createdTipIds,
      },
      'has_sk_test': stripeTestKey != null,
    });
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
