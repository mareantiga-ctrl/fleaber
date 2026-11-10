/// RED TEAM CEGO DO — off-platform / Hub / listagem / hold pós-DHDM.
/// Staging fxdknzrqjenzqcvnwqqq only. Stripe TEST. No production. No Fase 4. No fixes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const stamp = '20260906T1702';
const prefix = 'RTDO-$stamp';
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
  return cur.contains('redteam_blind_do_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_do_$stamp';

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
}

bool denied(HttpHit h) {
  if (h.status == 401 || h.status == 403 || h.status == 409 || h.status == 400) {
    return true;
  }
  final t = h.body.toLowerCase();
  return t.contains('42501') ||
      t.contains('23514') ||
      t.contains('permission denied') ||
      t.contains('not listed') ||
      t.contains('off-platform') ||
      t.contains('qty_exceeds') ||
      t.contains('sem permiss') ||
      t.contains('forbidden') ||
      t.contains('not allowed');
}

class Rtdo {
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
  final createdLiveIds = <String>[];
  final createdLiveItemIds = <String>[];
  final createdResIds = <String>[];
  final createdTipIds = <String>[];
  final createdFollowIds = <String>[];
  final createdFavIds = <String>[];
  final createdDisputeIds = <String>[];
  final createdSessionIds = <String>[];
  final lensesHit = <String>{};
  final wellsTried = <String>{};

  Rtdo._(this.url, this.anon, this.svc, this.env, this.e2eSecret);

  factory Rtdo.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtdo._(
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
    Map<String, String>? extra,
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
      final rs = await rq.close().timeout(const Duration(seconds: 25));
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

  Future<HttpHit> stripeRefunds(String pi) {
    return stripe('GET', '/v1/refunds?payment_intent=$pi&limit=10');
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
    const pass = 'Rtdo1702b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtdo1702b2',
      name: '$prefix-B2',
      userType: 'comprador',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2() async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rtdo1702s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtdo1702s2',
      name: '$prefix-S2',
      userType: 'vendedor',
      hubPublished: false,
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

  Future<String?> createProduct({
    String? seller,
    String? title,
    int qty = 3,
    double price = 12.0,
    bool listed = true,
    bool sold = false,
    bool live = true,
  }) async {
    final h = await rest('POST', 'products', service: true, body: {
      'seller_id': seller ?? sellerId,
      'title': title ?? '$prefix-sku',
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
    if (!h.ok) note('product.fail', 'createProduct', h.brief);
    return id;
  }

  Future<Map<String, dynamic>?> productRow(String id) async {
    final h = await rest(
      'GET',
      'products?id=eq.$id&select=id,seller_id,title,price,quantity,is_sold,list_on_marketplace,available_for_live',
      service: true,
    );
    return h.map;
  }

  Future<String?> insertOrder({
    required String productId,
    String? buyer,
    String? seller,
    String? jwt,
    String status = 'reserva_pendente',
    double price = 12.0,
    int qty = 1,
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
      },
    );
    final id = h.firstId;
    if (id != null) createdOrderIds.add(id);
    if (!h.ok) note('order.fail', 'insertOrder', h.brief);
    return id;
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,shipping_method,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,stock_units_applied,contract_unit_cents,contract_qty',
      service: true,
    );
    return h.map;
  }

  Future<HttpHit> checkout({
    required String orderId,
    String? jwt,
    String? buyer,
    Object? amount = 1,
    Object? currency = 'eur',
    String? productId,
    String? seller,
    String shipping = 'mao',
    int? quantity,
    Map<String, Object?> extra = const {},
  }) {
    return edge('create-payment-intent', {
      'buyer_id': buyer ?? buyerId,
      'order_id': orderId,
      'amount': amount,
      'currency': currency,
      if (productId != null) 'product_id': productId,
      if (seller != null) 'seller_id': seller,
      'shipping_method': shipping,
      if (quantity != null) 'quantity': quantity,
      ...extra,
    }, jwt: jwt ?? buyerJwt);
  }

  Future<HttpHit> checkoutBag({
    required List<Map<String, Object?>> lines,
    String? jwt,
    String? buyer,
    Object? amount = 1,
    String shipping = 'mao',
    String? seller,
  }) {
    final first = lines.isEmpty ? <String, Object?>{} : lines.first;
    return edge(
      'create-payment-intent',
      {
        'buyer_id': buyer ?? buyerId,
        'order_id': first['order_id'],
        'amount': amount,
        'currency': 'eur',
        if (first['product_id'] != null) 'product_id': first['product_id'],
        if (seller != null) 'seller_id': seller,
        'shipping_method': shipping,
        'bag_checkout': true,
        'bag_lines': lines,
      },
      jwt: jwt ?? buyerJwt,
    );
  }

  Future<HttpHit> refund(String orderId, {String? jwt, bool service = false}) {
    return edge('refund-order', {'order_id': orderId},
        jwt: jwt ?? sellerJwt, service: service);
  }

  Future<String?> createLive({
    String? seller,
    String title = '',
    String status = 'live',
    bool active = true,
  }) async {
    final sid = seller ?? sellerId;
    final h = await rest('POST', 'lives', service: true, body: {
      'title': title.isEmpty ? '$prefix live' : title,
      'status': status,
      'seller_id': sid,
      'vendedor_id': sid,
      'is_active': active,
    });
    final id = h.firstId;
    if (id != null) createdLiveIds.add(id);
    if (!h.ok) note('live.fail', 'createLive', h.brief);
    return id;
  }

  Future<String?> createLiveItem({
    required String liveId,
    String? title,
    String? ref,
    String kind = 'live_only',
    String? productId,
    String? checkoutProductId,
    int? quantity,
    String status = 'available',
    bool active = true,
    double price = 12.0,
  }) async {
    final body = <String, Object?>{
      'live_id': liveId,
      'title': title ?? '$prefix item',
      'ref_code': ref ?? 'RTDO-${DateTime.now().millisecondsSinceEpoch}',
      'price': price,
      'is_active': active,
      'status': status,
      'item_kind': kind,
    };
    if (kind == 'marketplace_product') {
      body['product_id'] = productId;
      body['checkout_product_id'] = checkoutProductId ?? productId;
    } else {
      if (productId != null) body['product_id'] = productId;
      if (checkoutProductId != null) {
        body['checkout_product_id'] = checkoutProductId;
      }
      body['quantity'] = quantity ?? 1;
    }
    final h = await rest('POST', 'live_items', service: true, body: body);
    final id = h.firstId;
    if (id != null) createdLiveItemIds.add(id);
    if (!h.ok) note('item.fail', 'createLiveItem $kind', h.brief);
    return id;
  }

  Future<Map<String, dynamic>?> liveItemRow(String id) async {
    final h = await rest(
      'GET',
      'live_items?id=eq.$id&select=id,live_id,product_id,checkout_product_id,quantity,status,is_active,item_kind,title',
      service: true,
    );
    return h.map;
  }

  Future<String?> insertReservation({
    required String liveId,
    required String liveItemId,
    String? buyer,
    String? seller,
    String? jwt,
    bool service = false,
    String status = 'pending',
    int qty = 1,
  }) async {
    final h = await rest(
      'POST',
      'live_reservation_requests',
      jwt: jwt,
      service: service,
      body: {
        'live_id': liveId,
        'live_item_id': liveItemId,
        'seller_id': seller ?? sellerId,
        'buyer_id': buyer ?? buyerId,
        'requested_qty': qty,
        'source': 'fleaber_live',
        'status': status,
      },
    );
    final id = h.firstId;
    if (id != null) createdResIds.add(id);
    if (!h.ok) note('res.fail', 'insertReservation', h.brief);
    return id;
  }

  Future<HttpHit> acceptRes(String resId, {String? jwt}) {
    return rest(
      'PATCH',
      'live_reservation_requests?id=eq.$resId',
      jwt: jwt ?? sellerJwt,
      body: {'status': 'accepted'},
    );
  }

  Future<Map<String, dynamic>?> resRow(String id) async {
    final h = await rest(
      'GET',
      'live_reservation_requests?id=eq.$id&select=id,status,requested_qty,live_item_id,buyer_id',
      service: true,
    );
    return h.map;
  }

  Future<void> endLive(String liveId) async {
    await rest(
      'PATCH',
      'lives?id=eq.$liveId',
      service: true,
      body: {'status': 'ended', 'is_active': false},
      prefer: 'return=minimal',
    );
  }

  Future<void> endAllCreatedLives() async {
    for (final id in createdLiveIds) {
      await endLive(id);
    }
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
    String lens = 'DM3',
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
      hit: paid,
    );
  }

  Future<HttpHit> hubSku(String pid, {String? jwt, bool anon = false}) {
    return rest(
      'GET',
      'hub_products_public?id=eq.$pid&select=id,title,seller_id,is_sold,price',
      jwt: anon ? null : (jwt ?? buyerJwt),
      service: false,
    );
  }

  int hubN(HttpHit h) => h.list.length;

  Future<HttpHit> sqlOff(String method) {
    return rpc('batata_is_off_platform_payment', {'p_method': method},
        service: true);
  }

  Future<HttpHit> hubSellable(String pid) {
    return rpc('batata_product_hub_sellable', {'p_product_id': pid},
        service: true);
  }

  Future<HttpHit> heldQty(String pid) {
    return rpc(
      'batata_product_held_qty',
      {'p_product_id': pid},
      service: true,
    );
  }

  void trackSession(HttpHit h) {
    final sid = h.sessionId;
    if (sid != null && sid.startsWith('cs_')) createdSessionIds.add(sid);
  }

  Future<HttpHit> insertOrderRaw({
    required String productId,
    required Object payment,
    String? buyer,
    String? seller,
    String? jwt,
    bool service = false,
    String status = 'reserva_pendente',
    double price = 12.0,
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
        'seller_id': seller ?? sellerId,
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

  Future<HttpHit> favorite(String productId, {String? jwt, String? user}) {
    return rest('POST', 'favorites', jwt: jwt ?? buyerJwt, body: {
      'user_id': user ?? buyerId,
      'product_id': productId,
    }).then((h) {
      final id = h.firstId;
      if (id != null) createdFavIds.add(id);
      return h;
    });
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
      'auditor': 'REDTEAM_BLIND_DO_PAYMETHOD_HUB_POS_DHDM_v1',
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
        'seller2': seller2Id,
      },
      'created': {
        'orders': createdOrderIds,
        'products': createdProductIds,
        'lives': createdLiveIds,
        'sessions': createdSessionIds,
        'res': createdResIds,
      },
    });
  }

  Future<HttpHit> hubProfile(String id, {bool anon = false}) {
    return rest(
      'GET',
      'hub_profiles_public?id=eq.$id&select=id,handle',
      jwt: anon ? null : buyerJwt,
    );
  }

  Future<HttpHit> hubLives(String liveId, {bool anon = false}) {
    return rest(
      'GET',
      'hub_lives_public?id=eq.$liveId&select=id,title,seller_id',
      jwt: anon ? null : buyerJwt,
    );
  }

  Future<List<Map<String, dynamic>>> chatsForProduct(String pid) async {
    final h = await rest(
      'GET',
      'chats?product_id=eq.$pid&select=id,product_id,user_a,user_b,last_message',
      service: true,
    );
    return h.list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> chatMsgsForOrder(String oid) async {
    final h = await rest(
      'GET',
      'chat_messages?text=ilike.*$oid*&select=id,chat_id,sender_id,text,created_at&limit=20',
      service: true,
    );
    return h.list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<HttpHit> insertDispute({
    required String orderId,
    String? jwt,
    String? buyer,
    String reason = 'danificado',
    String description = 'RTDO disputa composição artigo danificado.',
    List<String>? photos,
  }) {
    return rest('POST', 'order_disputes', jwt: jwt ?? buyerJwt, body: {
      'order_id': orderId,
      'buyer_id': buyer ?? buyerId,
      'reason': reason,
      'description': description,
      'proof_photos': photos ?? <String>[],
      'status': 'aberta',
      'current_turn': 'vendedor',
    }).then((h) {
      final id = h.firstId;
      if (id != null) createdDisputeIds.add(id);
      return h;
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
      'http': http is HttpHit ? http.brief : clip(http, 320),
      'oracles': oracles is String ? oracles : clip(oracles, 360),
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
    bool proven = true,
    bool countExactClosed = false,
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
      'count_exact_closed': countExactClosed,
      'evidence': evidence ?? {},
    });
    stdout.writeln(
      'FINDING $severity $id [$lens]${countExactClosed ? ' EXACTO' : ''} $title',
    );
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
