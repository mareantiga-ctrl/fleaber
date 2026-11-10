/// RED TEAM CEGO AE — marketplace/checkout pós-ABACAD.
/// Staging fxdknzrqjenzqcvnwqqq only. Stripe TEST. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260901T1915';
const prefix = 'RTAE-$stamp';
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

int euroToCents(num eur) => (eur * 100).round();

int protectionFeeCents(int itemsCents, int shippingCents) {
  final baseEur = (itemsCents + shippingCents) / 100;
  if (!(baseEur > 0)) return 0;
  final feeEur = ((0.65 + baseEur * 0.05) * 100).round() / 100;
  return euroToCents(feeEur);
}

int expectedQuoteCents({
  required num unitEur,
  int qty = 1,
  int shipCents = 0,
}) {
  final items = euroToCents(unitEur * qty);
  final prot = protectionFeeCents(items, shipCents);
  return items + shipCents + prot;
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
  return cur.contains('redteam_blind_ae_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_ae_$stamp';

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

  int? get amountTotal {
    final m = map;
    if (m == null) return null;
    return numOf(m['amount_total'] ?? m['server_amount_cents'])?.round();
  }

  String? get sessionId => map?['checkoutSessionId']?.toString();
  bool get reused => map?['reused_session'] == true;
}

class Rtae {
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
  final createdLiveIds = <String>[];
  final createdItemIds = <String>[];
  final createdBundleIds = <String>[];
  final lensesHit = <String>{};

  Rtae._(this.url, this.anon, this.svc, this.env, this.e2eSecret);

  factory Rtae.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtae._(
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
      }, prefer: 'return=minimal');
    }
    return id;
  }

  Future<void> ensureBuyer2() async {
    final email = '${prefix.toLowerCase()}-b2@fleaber.test';
    const pass = 'Rtae1915b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtae1915b2',
      name: '$prefix-B2',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2() async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rtae1915s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtae1915s2',
      name: '$prefix-S2',
    );
    seller2Jwt = await signIn(email, pass);
  }

  Future<String?> createProduct({
    String? seller,
    String? title,
    int qty = 3,
    bool listed = true,
    double price = 12.0,
    bool sold = false,
  }) async {
    final h = await rest('POST', 'products', service: true, body: {
      'seller_id': seller ?? sellerId,
      'title': title ?? '$prefix-sku',
      'price': price,
      'quantity': qty,
      'is_sold': sold,
      'list_on_marketplace': listed,
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

  Future<String?> insertLive({
    String? seller,
    bool active = true,
    String status = 'live',
  }) async {
    final sid = seller ?? sellerId;
    final h = await rest('POST', 'lives', service: true, body: {
      'seller_id': sid,
      'vendedor_id': sid,
      'title': '$prefix live',
      'status': status,
      'is_active': active,
    });
    final id = h.firstId;
    if (id != null) createdLiveIds.add(id);
    return id;
  }

  Future<String?> insertMarketItem({
    required String liveId,
    required String productId,
    double price = 5.0,
    String? jwt,
    bool service = false,
  }) async {
    final h = await rest('POST', 'live_items', jwt: jwt, service: service, body: {
      'live_id': liveId,
      'ref_code': 'AE${DateTime.now().millisecondsSinceEpoch % 100000}',
      'title': '$prefix mkt',
      'price': price,
      'is_active': true,
      'item_kind': 'marketplace_product',
      'product_id': productId,
    });
    final id = h.firstId;
    if (id != null) createdItemIds.add(id);
    return id;
  }

  Future<String?> insertOrder({
    required String productId,
    String? buyer,
    String? seller,
    String? jwt,
    String status = 'reserva_pendente',
    double price = 12.0,
    int qty = 1,
    String? liveItemId,
    String? liveId,
    String? bundleId,
    String? offerId,
    int? contractUnitCents,
    String shipping = 'entrega em mão',
    String payment = 'Pagamento na app',
    bool service = false,
  }) async {
    final body = <String, Object?>{
      'buyer_id': buyer ?? buyerId,
      'seller_id': seller ?? sellerId,
      'product_id': productId,
      'price_total': price,
      'quantity': qty,
      'status': status,
      'payment_method': payment,
      'shipping_method': shipping,
      if (liveItemId != null) 'live_item_id': liveItemId,
      if (liveId != null) 'live_id': liveId,
      if (bundleId != null) 'bundle_id': bundleId,
      if (offerId != null) 'product_offer_id': offerId,
      if (contractUnitCents != null) 'contract_unit_cents': contractUnitCents,
    };
    final h = await rest(
      'POST',
      'orders',
      jwt: jwt,
      service: service,
      body: body,
    );
    final id = h.firstId;
    if (id != null) createdOrderIds.add(id);
    return id;
  }

  Future<HttpHit> insertOrderHit({
    required String productId,
    String? buyer,
    String? seller,
    String? jwt,
    String status = 'reserva_pendente',
    double price = 12.0,
    int qty = 1,
    String? liveItemId,
    String? liveId,
    String? bundleId,
    int? contractUnitCents,
    String shipping = 'entrega em mão',
    String payment = 'Pagamento na app',
    bool service = false,
  }) async {
    final h = await rest(
      'POST',
      'orders',
      jwt: jwt,
      service: service,
      body: {
        'buyer_id': buyer ?? buyerId,
        'seller_id': seller ?? sellerId,
        'product_id': productId,
        'price_total': price,
        'quantity': qty,
        'status': status,
        'payment_method': payment,
        'shipping_method': shipping,
        if (liveItemId != null) 'live_item_id': liveItemId,
        if (liveId != null) 'live_id': liveId,
        if (bundleId != null) 'bundle_id': bundleId,
        if (contractUnitCents != null) 'contract_unit_cents': contractUnitCents,
      },
    );
    final id = h.firstId;
    if (id != null) createdOrderIds.add(id);
    return h;
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,shipping_method,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,live_item_id,live_id,stock_units_applied,contract_unit_cents,contract_qty,bundle_id,product_offer_id',
      service: true,
    );
    return h.map;
  }

  Future<HttpHit> checkout({
    required String orderId,
    String? jwt,
    String? buyer,
    Object? amount = 50,
    Object? currency,
    String? productId,
    String? seller,
    String shipping = 'mao',
    int? quantity,
    bool prize = false,
    bool includeCurrency = true,
  }) {
    final body = <String, Object?>{
      'buyer_id': buyer ?? buyerId,
      'order_id': orderId,
      'amount': amount,
      if (productId != null) 'product_id': productId,
      if (seller != null) 'seller_id': seller,
      'shipping_method': shipping,
      if (quantity != null) 'quantity': quantity,
      if (prize) 'prize_shipping': true,
    };
    if (includeCurrency) body['currency'] = currency ?? 'eur';
    return edge('create-payment-intent', body, jwt: jwt ?? buyerJwt);
  }

  Future<HttpHit> checkoutBag({
    required List<Map<String, Object?>> lines,
    String? jwt,
    String? buyer,
    Object? amount = 50,
    Object? currency = 'eur',
    String shipping = 'mao',
    String? seller,
    String? orderId,
  }) {
    final first = lines.isEmpty ? <String, Object?>{} : lines.first;
    return edge('create-payment-intent', {
      'buyer_id': buyer ?? buyerId,
      'order_id': orderId ?? first['order_id'],
      'amount': amount,
      'currency': currency,
      if (first['product_id'] != null) 'product_id': first['product_id'],
      if (seller != null) 'seller_id': seller,
      'shipping_method': shipping,
      'bag_checkout': true,
      'bag_lines': lines,
    }, jwt: jwt ?? buyerJwt);
  }

  Future<HttpHit> refund(String orderId, {String? jwt, bool service = false}) {
    return edge('refund-order', {'order_id': orderId},
        jwt: jwt, service: service);
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
    final uri = Uri.parse(path.startsWith('http')
        ? path
        : 'https://api.stripe.com$path');
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

  Future<HttpHit> stripeSession(String sid) {
    return stripe('GET', '/v1/checkout/sessions/$sid');
  }

  Future<HttpHit> stripeConfirmPi(String pi) {
    return stripe('POST', '/v1/payment_intents/$pi/confirm', fields: {
      'payment_method': 'pm_card_visa',
    });
  }

  Future<HttpHit> settleGet(String sessionId) {
    return edge(
      'create-payment-intent',
      null,
      method: 'GET',
      qs: 'checkout_return=success&session_id=$sessionId',
    );
  }

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
    String lens = 'AE4',
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

  Future<HttpHit> stockCheck(String productId,
      {String? exclude, int need = 1}) {
    return rpc('batata_product_checkout_available', {
      'p_product_id': productId,
      if (exclude != null) 'p_exclude_order_id': exclude,
      'p_need_qty': need,
    }, jwt: buyerJwt);
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
        'lives': createdLiveIds,
        'items': createdItemIds,
        'orders': createdOrderIds,
        'products': createdProductIds,
        'bundles': createdBundleIds,
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
