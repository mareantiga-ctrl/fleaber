/// HTTP client — staging fxdknzrqjenzqcvnwqqq only. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260901T1302';
const prefix = 'RTV-$stamp';
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
  return cur.contains('redteam_blind_v_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_v_$stamp';

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

  int? get amountCents {
    final m = map ?? {};
    final a = m['server_amount_cents'] ?? m['amount_total'] ?? m['amount'];
    if (a is num) return a.round();
    return int.tryParse('$a');
  }
}

class Rtv {
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
  final blocked = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdLiveIds = <String>[];
  final createdLiveItemIds = <String>[];
  final createdReservationIds = <String>[];
  final createdDisputeIds = <String>[];
  final createdBundleIds = <String>[];
  final createdOfferIds = <String>[];

  Rtv._(this.url, this.anon, this.svc, this.e2eSecret, this.env);

  factory Rtv.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtv._(
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
    const pass = 'Rtv1302b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtv1302b2',
      name: '$prefix-B2',
      userType: 'comprador',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2() async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rtv1302s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtv1302s2',
      name: '$prefix-S2',
      userType: 'vendedor',
      hubPublished: true,
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
    bool live = true,
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
    if (!h.ok) stdout.writeln('insertProduct fail ${h.brief}');
    return id;
  }

  Future<String?> insertLive({
    bool active = true,
    String? seller,
    String status = 'live',
  }) async {
    final sid = seller ?? sellerId;
    final h = await rest('POST', 'lives', service: true, body: {
      'seller_id': sid,
      'vendedor_id': sid,
      'title': '$prefix live $status',
      'status': active ? 'live' : status,
      'is_active': active,
      'viewer_count': 3,
    });
    final id = h.firstId;
    if (id != null) createdLiveIds.add(id);
    if (!h.ok) stdout.writeln('insertLive fail ${h.brief}');
    return id;
  }

  Future<void> endLives() async {
    for (final id in createdLiveIds) {
      await rest('PATCH', 'lives?id=eq.$id', service: true, body: {
        'status': 'ended',
        'is_active': false,
      }, prefer: 'return=minimal');
    }
  }

  Future<String?> insertLiveItem({
    required String liveId,
    required String title,
    String status = 'available',
    bool active = true,
    int qty = 3,
    double price = 12,
    String? productId,
    String? seller,
    String kind = 'live_only',
  }) async {
    final body = <String, dynamic>{
      'live_id': liveId,
      'title': title,
      'status': status,
      'is_active': active,
      'price': price,
      'ref_code': 'RTV${createdLiveItemIds.length + 1}',
      'item_kind': productId != null ? 'marketplace_product' : kind,
    };
    if (productId != null) {
      body['product_id'] = productId;
    } else {
      body['quantity'] = qty;
    }
    if (seller != null) body['seller_id'] = seller;
    final h = await rest('POST', 'live_items', jwt: sellerJwt, body: body);
    final id = h.firstId;
    if (id != null) createdLiveItemIds.add(id);
    if (!h.ok) {
      final h2 = await rest('POST', 'live_items', service: true, body: body);
      final id2 = h2.firstId;
      if (id2 != null) createdLiveItemIds.add(id2);
      if (!h2.ok) stdout.writeln('insertLiveItem fail ${h.brief} / ${h2.brief}');
      return id2;
    }
    return id;
  }

  Future<String?> insertReservation({
    required String liveId,
    String? liveItemId,
    String? buyer,
    String? seller,
    String? jwt,
    bool service = false,
    String status = 'pending',
    int qty = 1,
    String source = 'fleaber_live',
  }) async {
    final body = <String, dynamic>{
      'live_id': liveId,
      'buyer_id': buyer ?? buyerId,
      'seller_id': seller ?? sellerId,
      'requested_qty': qty,
      'source': source,
      'status': status,
    };
    if (liveItemId != null) body['live_item_id'] = liveItemId;
    final h = await rest(
      'POST',
      'live_reservation_requests',
      jwt: jwt,
      service: service,
      body: body,
    );
    final id = h.firstId;
    if (id != null) createdReservationIds.add(id);
    return id;
  }

  Future<Map<String, dynamic>?> liveItemRow(String id) async {
    final h = await rest(
      'GET',
      'live_items?id=eq.$id&select=id,live_id,product_id,seller_id,quantity,status,item_kind,price',
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
    String? liveId,
    String? liveItemId,
    String? offerId,
    String? bundleId,
  }) async {
    final body = <String, dynamic>{
      'buyer_id': buyer ?? buyerId,
      'seller_id': seller ?? sellerId,
      'product_id': productId,
      'price_total': price,
      'quantity': qty,
      'status': status,
      'payment_method': payment,
      'shipping_method': shipping,
    };
    if (liveId != null) body['live_id'] = liveId;
    if (liveItemId != null) body['live_item_id'] = liveItemId;
    if (offerId != null) body['product_offer_id'] = offerId;
    if (bundleId != null) body['bundle_id'] = bundleId;
    final h = await rest('POST', 'orders', jwt: jwt, service: service, body: body);
    final id = h.firstId;
    if (id != null) createdOrderIds.add(id);
    if (!h.ok) stdout.writeln('insertOrder fail ${h.brief}');
    return id;
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,shipping_method,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,stock_units_applied,completed_at,live_id,live_item_id,proof_url,product_offer_id,bundle_id,contract_unit_cents,contract_qty',
      service: true,
    );
    return h.map;
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

  String? parseE2eOrderId(HttpHit paid) {
    final pm = paid.map ?? {};
    return (pm['order_id'] ??
            (pm['order'] is Map ? (pm['order'] as Map)['id'] : null))
        ?.toString();
  }

  String? parseE2eProductId(HttpHit paid) {
    return paid.map?['product_id']?.toString();
  }

  Future<Map<String, String?>> setupPaidStripe() async {
    final paid = await e2e('setup_paid_order', {'initial_qty': 2});
    note('fixture.paid', 'setup_paid_order Stripe TEST', paid.brief, lens: 'V2');
    final oid = parseE2eOrderId(paid);
    final pid = parseE2eProductId(paid);
    if (pid != null) createdProductIds.add(pid);
    if (oid != null) createdOrderIds.add(oid);
    return {
      'order_id': oid,
      'product_id': pid,
      'pi': paid.map?['payment_intent_id']?.toString(),
    };
  }

  Future<HttpHit> checkoutBag({
    required List<Map<String, Object?>> lines,
    String? jwt,
    String? buyer,
    num amount = 50,
    String shipping = 'entrega em mão',
  }) {
    final first = lines.isEmpty ? <String, Object?>{} : lines.first;
    return edge('create-payment-intent', {
      'buyer_id': buyer ?? buyerId,
      'order_id': first['order_id'],
      'amount': amount,
      if (first['product_id'] != null) 'product_id': first['product_id'],
      'shipping_method': shipping,
      'bag_checkout': true,
      'bag_lines': lines,
    }, jwt: jwt ?? buyerJwt);
  }

  Future<HttpHit> checkoutSingle({
    required String orderId,
    String? productId,
    String? jwt,
    String? buyer,
    num amount = 50,
    String shipping = 'entrega em mão',
  }) {
    return edge('create-payment-intent', {
      'buyer_id': buyer ?? buyerId,
      'order_id': orderId,
      'amount': amount,
      if (productId != null) 'product_id': productId,
      'shipping_method': shipping,
    }, jwt: jwt ?? buyerJwt);
  }

  Future<HttpHit> refundOrder(String orderId, {String? jwt}) {
    return edge('refund-order', {'order_id': orderId}, jwt: jwt ?? sellerJwt);
  }

  Future<HttpHit> insertDispute({
    required String orderId,
    String? jwt,
    String? buyer,
    String reason = 'nao_corresponde',
    String description = 'RTV disputa',
  }) {
    return rest(
      'POST',
      'order_disputes',
      jwt: jwt ?? buyerJwt,
      body: {
        'order_id': orderId,
        'buyer_id': buyer ?? buyerId,
        'reason': reason,
        'description': description,
        'status': 'aberta',
      },
    );
  }

  void note(String id, String title, Object? ev, {String? lens}) {
    notes.add({
      'id': id,
      if (lens != null) 'lens': lens,
      'title': title,
      'ev': ev is HttpHit ? ev.brief : ev,
    });
    stdout.writeln('NOTE $id ${lens ?? ''} $title ${clip(ev, 280)}');
  }

  void closed(String id, String title, Object? ev, {String? lens}) {
    blocked.add({
      'id': id,
      if (lens != null) 'lens': lens,
      'title': title,
      'ev': ev is HttpHit ? ev.brief : ev,
    });
    stdout.writeln('CLOSED $id ${lens ?? ''} $title ${clip(ev, 220)}');
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
