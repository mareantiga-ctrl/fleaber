/// HTTP client — staging fxdknzrqjenzqcvnwqqq only. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260902T1903';
const prefix = 'RTBN-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

String clip(Object? v, [int n = 360]) {
  String s;
  try {
    if (v is HttpHit) {
      s = v.brief;
    } else if (v is String) {
      s = v;
    } else {
      s = jsonEncode(v);
    }
  } catch (_) {
    s = v.toString();
  }
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
  return cur.contains('redteam_blind_bn_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_bn_$stamp';

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

  bool get rpcOk {
    final m = map;
    if (m == null) return false;
    final ok = m['ok'];
    return ok == true || ok == 'true';
  }

  String? get rpcError => map?['error']?.toString();
}

class Rtbn {
  final String url;
  final String anon;
  final String svc;
  final Map<String, String> env;
  String? buyerJwt;
  String? sellerJwt;
  String? buyer2Jwt;
  String? seller2Jwt;
  String? helperChatJwt;
  String? helperMarkJwt;
  String? helperViewJwt;
  String? buyerId;
  String? sellerId;
  String? buyer2Id;
  String? seller2Id;
  String? helperChatId;
  String? helperMarkId;
  String? helperViewId;
  final findings = <Map<String, dynamic>>[];
  final notes = <Map<String, dynamic>>[];
  final blocked = <Map<String, dynamic>>[];
  final skipped = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdLiveIds = <String>[];
  final createdItemIds = <String>[];
  final createdReqIds = <String>[];
  final createdHelperIds = <String>[];
  final lensesHit = <String>{};

  Rtbn._(this.url, this.anon, this.svc, this.env);

  factory Rtbn.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtbn._(
      url,
      envRequire(env, 'SUPABASE_ANON_KEY'),
      envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
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
    bool service = false,
  }) {
    return req(
      method,
      '/functions/v1/$name',
      jwt: jwt,
      body: body,
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
    const pass = 'Rtbn1903b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtbn1903b2',
      name: '$prefix-B2',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2() async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rtbn1903s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtbn1903s2',
      name: '$prefix-S2',
    );
    if (seller2Id != null) {
      await rest('PATCH', 'profiles?id=eq.$seller2Id', service: true, body: {
        'user_type': 'vendedor',
      }, prefer: 'return=minimal');
    }
    seller2Jwt = await signIn(email, pass);
  }

  Future<Map<String, String?>> ensureNamedHelper({
    required String tag,
    required String pass,
  }) async {
    final email = '${prefix.toLowerCase()}-$tag@fleaber.test';
    final id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtbn1903$tag',
      name: '$prefix-$tag',
    );
    final jwt = await signIn(email, pass);
    return {'id': id, 'jwt': jwt, 'email': email};
  }

  Future<String?> fixtureHelper({
    required String helperUserId,
    required Map<String, Object?> perms,
    String? seller,
  }) async {
    final sid = seller ?? sellerId;
    final h = await rest('POST', 'seller_helpers', service: true, body: {
      'seller_id': sid,
      'helper_user_id': helperUserId,
      'invited_by': sid,
      'display_name': '$prefix helper',
      'invitation_status': 'accepted',
      'active': true,
      'responded_at': DateTime.now().toUtc().toIso8601String(),
      'permissions': perms,
    });
    final id = h.firstId;
    if (id != null) createdHelperIds.add(id);
    if (!h.ok) note('helper.fail', 'fixtureHelper', h.brief);
    return id;
  }

  Future<String?> createProduct({
    String? seller,
    String? title,
    int qty = 3,
    bool listed = true,
    bool live = true,
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

  Future<String?> insertLive({
    String? seller,
    bool active = true,
    String status = 'live',
    String? muxPlayback,
    String? muxLiveId,
    String? muxStreamKey,
  }) async {
    final sid = seller ?? sellerId;
    final h = await rest('POST', 'lives', service: true, body: {
      'seller_id': sid,
      'vendedor_id': sid,
      'title': '$prefix live',
      'status': status,
      'is_active': active,
      if (muxPlayback != null) 'mux_playback_id': muxPlayback,
      if (muxLiveId != null) 'mux_live_id': muxLiveId,
      if (muxStreamKey != null) 'mux_stream_key': muxStreamKey,
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

  Future<String?> insertLiveOnlyItem({
    required String liveId,
    int qty = 1,
    String? ref,
    double price = 9.0,
    String? jwt,
    bool service = false,
    String? checkoutProductId,
    String? status,
    String? productId,
    String? logicalItemId,
  }) async {
    final h = await rest('POST', 'live_items', jwt: jwt, service: service, body: {
      'live_id': liveId,
      'ref_code': ref ?? 'X${DateTime.now().millisecondsSinceEpoch % 100000}',
      'title': '$prefix live_only',
      'price': price,
      'is_active': true,
      'item_kind': 'live_only',
      'quantity': qty,
      if (checkoutProductId != null) 'checkout_product_id': checkoutProductId,
      if (status != null) 'status': status,
      if (productId != null) 'product_id': productId,
      if (logicalItemId != null) 'logical_item_id': logicalItemId,
    });
    final id = h.firstId;
    if (id != null) createdItemIds.add(id);
    if (!h.ok) note('item.fail', 'insertLiveOnlyItem', h.brief);
    return id;
  }

  Future<String?> insertMarketItem({
    required String liveId,
    required String productId,
    String? ref,
    double price = 12.0,
    String? jwt,
    bool service = false,
    int? qty,
    String? checkoutProductId,
  }) async {
    final h = await rest('POST', 'live_items', jwt: jwt, service: service, body: {
      'live_id': liveId,
      'ref_code': ref ?? 'M${DateTime.now().millisecondsSinceEpoch % 100000}',
      'title': '$prefix mkt',
      'price': price,
      'is_active': true,
      'item_kind': 'marketplace_product',
      'product_id': productId,
      if (qty != null) 'quantity': qty,
      if (checkoutProductId != null) 'checkout_product_id': checkoutProductId,
    });
    final id = h.firstId;
    if (id != null) createdItemIds.add(id);
    if (!h.ok) note('item.fail', 'insertMarketItem', h.brief);
    return id;
  }

  Future<Map<String, dynamic>?> itemRow(String id) async {
    final h = await rest(
      'GET',
      'live_items?id=eq.$id&select=id,live_id,product_id,checkout_product_id,item_kind,quantity,status,price,ref_code,is_active,logical_item_id',
      service: true,
    );
    return h.map;
  }

  Future<HttpHit> insertReservation({
    required String liveId,
    String? liveItemId,
    String? seller,
    String? buyer,
    String source = 'fleaber_live',
    String status = 'pending',
    int qty = 1,
    String? notes,
    String? jwt,
    bool service = false,
  }) {
    final body = <String, Object?>{
      'live_id': liveId,
      if (liveItemId != null) 'live_item_id': liveItemId,
      'seller_id': seller ?? sellerId,
      if (buyer != null) 'buyer_id': buyer,
      'source': source,
      'status': status,
      'requested_qty': qty,
      if (notes != null) 'notes': notes,
    };
    return rest(
      'POST',
      'live_reservation_requests',
      jwt: jwt,
      service: service,
      body: body,
    ).then((h) {
      final id = h.firstId;
      if (id != null) createdReqIds.add(id);
      return h;
    });
  }

  Future<HttpHit> markSold(String liveItemId, {String? jwt, bool service = false}) {
    return rpc('batata_mark_live_item_sold', {'p_live_item_id': liveItemId},
        jwt: jwt, service: service);
  }

  Future<HttpHit> stripeConvert(String requestId, {String? orderId, String? jwt}) {
    return rpc('batata_live_reservation_stripe_convert', {
      'p_request_id': requestId,
      if (orderId != null) 'p_order_id': orderId,
    }, jwt: jwt ?? sellerJwt);
  }

  Future<HttpHit> reconcileStripe(String orderId, {String? reqId, String? jwt}) {
    return rpc('batata_live_reconcile_stripe_order', {
      'p_order_id': orderId,
      if (reqId != null) 'p_reservation_request_id': reqId,
    }, jwt: jwt ?? sellerJwt);
  }

  Future<HttpHit> sysMsg(String liveId, String body, {String? jwt, String? label}) {
    return rpc('batata_live_system_message', {
      'p_live_id': liveId,
      'p_body': body,
      if (label != null) 'p_sender_label': label,
    }, jwt: jwt ?? sellerJwt);
  }

  Future<HttpHit> purchaseBroadcast({
    required String liveId,
    required String buyer,
    required String liveItemId,
    String? jwt,
  }) {
    return rpc('batata_live_purchase_broadcast', {
      'p_live_id': liveId,
      'p_buyer_id': buyer,
      'p_live_item_id': liveItemId,
    }, jwt: jwt ?? sellerJwt);
  }

  Future<Map<String, dynamic>?> reqRow(String id) async {
    final h = await rest(
      'GET',
      'live_reservation_requests?id=eq.$id&select=id,live_id,live_item_id,seller_id,buyer_id,source,status,requested_qty,processed_by_user_id,notes',
      service: true,
    );
    return h.map;
  }

  Future<HttpHit> stock(String liveItemId, {String? jwt, bool service = false}) {
    return rpc('batata_live_item_stock', {'p_live_item_id': liveItemId},
        jwt: jwt, service: service);
  }

  Future<List<dynamic>> msgs(String liveId, {int limit = 20}) async {
    final h = await rest(
      'GET',
      'live_messages?live_id=eq.$liveId&select=id,kind,body,user_id,sender_label,created_at&order=created_at.desc&limit=$limit',
      service: true,
    );
    return h.list;
  }

  Future<HttpHit> insertOrder({
    required String productId,
    String? buyer,
    String? seller,
    String? jwt,
    String status = 'reserva_pendente',
    double price = 12.0,
    int qty = 1,
    String? liveItemId,
    String? liveId,
    bool service = false,
    int? amountPaidCents,
    String? pi,
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
        'payment_method': 'Pagamento na app',
        'shipping_method': 'entrega em mão',
        if (liveItemId != null) 'live_item_id': liveItemId,
        if (liveId != null) 'live_id': liveId,
        if (amountPaidCents != null) 'amount_paid_cents': amountPaidCents,
        if (pi != null) 'stripe_payment_intent_id': pi,
      },
    );
    final id = h.firstId;
    if (id != null) createdOrderIds.add(id);
    return h;
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,stripe_payment_intent_id,live_item_id,live_id,stock_units_applied',
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
}

Future<List<HttpHit>> parallel(List<Future<HttpHit>> jobs) => Future.wait(jobs);

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
