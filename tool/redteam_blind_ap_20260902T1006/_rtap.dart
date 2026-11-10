/// RED TEAM CEGO AP — live/staff pós-AHAM.
/// Staging fxdknzrqjenzqcvnwqqq only. Stripe TEST. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260902T1006';
const prefix = 'RTAP-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

String clip(Object? v, [int n = 360]) {
  if (v is HttpHit) return clip(v.brief, n);
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
  return cur.contains('redteam_blind_ap_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_ap_$stamp';

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

  bool get denied =>
      status == 401 ||
      status == 403 ||
      status == 425 ||
      body.contains('42501') ||
      body.contains('not_allowed') ||
      body.contains('PGRST') ||
      body.contains('convert_requires_paid_order') ||
      body.contains('live_item_') ||
      body.contains('mismatch');
}

class Rtap {
  final String url;
  final String anon;
  final String svc;
  final Map<String, String> env;
  String? buyerJwt;
  String? sellerJwt;
  String? buyer2Jwt;
  String? seller2Jwt;
  String? helperJwt;
  String? buyerId;
  String? sellerId;
  String? buyer2Id;
  String? seller2Id;
  String? helperId;
  final findings = <Map<String, dynamic>>[];
  final notes = <Map<String, dynamic>>[];
  final blocked = <Map<String, dynamic>>[];
  final skipped = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdLiveIds = <String>[];
  final createdItemIds = <String>[];
  final createdResIds = <String>[];
  final createdHelperIds = <String>[];
  final lensesHit = <String>{};
  int _seq = 0;

  Rtap._(this.url, this.anon, this.svc, this.env);

  factory Rtap.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtap._(
      url,
      envRequire(env, 'SUPABASE_ANON_KEY'),
      envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
      env,
    );
  }

  String nextRef([String p = 'AP']) {
    _seq++;
    return '$p${DateTime.now().millisecondsSinceEpoch % 100000}$_seq';
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
        'user_type': userType,
      }, prefer: 'return=minimal');
    }
    return id;
  }

  Future<void> ensureBuyer2() async {
    final email = '${prefix.toLowerCase()}-b2@fleaber.test';
    const pass = 'Rtap1006b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtap1006b2',
      name: '$prefix-B2',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2() async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rtap1006s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtap1006s2',
      name: '$prefix-S2',
      userType: 'vendedor',
    );
    seller2Jwt = await signIn(email, pass);
  }

  Future<void> ensureHelper() async {
    final email = '${prefix.toLowerCase()}-h@fleaber.test';
    const pass = 'Rtap1006h!xK';
    helperId = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtap1006h',
      name: '$prefix-H',
    );
    helperJwt = await signIn(email, pass);
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
    String? title,
  }) async {
    final sid = seller ?? sellerId;
    final h = await rest('POST', 'lives', service: true, body: {
      'seller_id': sid,
      'vendedor_id': sid,
      'title': title ?? '$prefix live',
      'status': status,
      'is_active': active,
    });
    final id = h.firstId;
    if (id != null) createdLiveIds.add(id);
    if (!h.ok) note('live.fail', 'insertLive', h.brief);
    return id;
  }

  Future<HttpHit> insertItem({
    required String liveId,
    String? jwt,
    bool service = false,
    String? productId,
    String? checkoutProductId,
    String kind = 'live_only',
    double price = 9.0,
    int qty = 1,
    String? status,
    bool active = true,
    String? title,
  }) async {
    final h = await rest('POST', 'live_items', jwt: jwt, service: service, body: {
      'live_id': liveId,
      'ref_code': nextRef(),
      'title': title ?? '$prefix item',
      'price': price,
      if (kind == 'live_only') 'quantity': qty,
      'is_active': active,
      'item_kind': kind,
      if (status != null) 'status': status,
      if (productId != null) 'product_id': productId,
      if (checkoutProductId != null) 'checkout_product_id': checkoutProductId,
    });
    final id = h.firstId;
    if (id != null) createdItemIds.add(id);
    return h;
  }

  Future<Map<String, dynamic>?> itemRow(String id) async {
    final h = await rest(
      'GET',
      'live_items?id=eq.$id&select=id,live_id,status,quantity,is_active,item_kind,product_id,checkout_product_id,price,title',
      service: true,
    );
    return h.map;
  }

  Future<HttpHit> insertRes({
    required String liveId,
    required String itemId,
    String? jwt,
    String? buyer,
    String? seller,
    String status = 'pending',
    String source = 'fleaber_live',
    int qty = 1,
    bool service = false,
  }) async {
    final h = await rest(
      'POST',
      'live_reservation_requests',
      jwt: jwt,
      service: service,
      body: {
        'live_id': liveId,
        'live_item_id': itemId,
        'buyer_id': buyer ?? buyerId,
        'seller_id': seller ?? sellerId,
        'status': status,
        'source': source,
        'requested_qty': qty,
      },
    );
    final id = h.firstId;
    if (id != null) createdResIds.add(id);
    return h;
  }

  Future<Map<String, dynamic>?> resRow(String id) async {
    final h = await rest(
      'GET',
      'live_reservation_requests?id=eq.$id&select=id,status,requested_qty,buyer_id,seller_id,live_item_id,live_id,source,processed_by_user_id',
      service: true,
    );
    return h.map;
  }

  Future<HttpHit> processRes(String id, String action, {String? jwt}) {
    return rpc('batata_process_live_reservation_request', {
      'p_request_id': id,
      'p_action': action,
    }, jwt: jwt ?? sellerJwt);
  }

  Future<HttpHit> markSold(String itemId, {String? jwt}) {
    return rpc('batata_mark_live_item_sold', {
      'p_live_item_id': itemId,
    }, jwt: jwt ?? sellerJwt);
  }

  Future<String?> insertPaidOrder({
    required String productId,
    String? buyer,
    String? seller,
    String? liveItemId,
    String? liveId,
    double price = 12.0,
    int qty = 1,
    String pi = 'pi_rtap_fixture',
  }) async {
    final h = await rest('POST', 'orders', service: true, body: {
      'buyer_id': buyer ?? buyerId,
      'seller_id': seller ?? sellerId,
      'product_id': productId,
      'price_total': price,
      'quantity': qty,
      'status': 'pago',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
      'amount_paid_cents': (price * 100).round(),
      'stripe_payment_intent_id': '$pi-${nextRef('PI')}',
      if (liveItemId != null) 'live_item_id': liveItemId,
      if (liveId != null) 'live_id': liveId,
    });
    final id = h.firstId;
    if (id != null) createdOrderIds.add(id);
    if (!h.ok) note('order.paid.fail', 'insertPaidOrder', h.brief);
    return id;
  }

  Future<String?> insertOpenOrder({
    required String productId,
    String? buyer,
    String? seller,
    String? liveItemId,
    String? liveId,
    String? jwt,
    bool service = false,
    double price = 12.0,
    int qty = 1,
    String status = 'reserva_pendente',
  }) async {
    final h = await rest('POST', 'orders', jwt: jwt, service: service, body: {
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
    });
    final id = h.firstId;
    if (id != null) createdOrderIds.add(id);
    return id;
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,stripe_payment_intent_id,live_item_id,live_id,stock_units_applied',
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

  Future<String?> inviteHelper({
    required String helperUserId,
    Map<String, bool> perms = const {},
    String status = 'pending',
    bool active = false,
  }) async {
    final h = await rest('POST', 'seller_helpers', service: true, body: {
      'seller_id': sellerId,
      'helper_user_id': helperUserId,
      'display_name': '$prefix helper',
      'invited_by': sellerId,
      'invitation_status': status,
      'active': active,
      'permissions': perms,
    });
    final id = h.firstId;
    if (id != null) createdHelperIds.add(id);
    if (!h.ok) note('helper.fail', 'inviteHelper', h.brief);
    return id;
  }

  Future<Map<String, dynamic>?> helperRow(String id) async {
    final h = await rest(
      'GET',
      'seller_helpers?id=eq.$id&select=id,seller_id,helper_user_id,invitation_status,active,permissions',
      service: true,
    );
    return h.map;
  }

  Future<void> endLives() async {
    for (final id in createdLiveIds) {
      await rest('PATCH', 'lives?id=eq.$id', service: true, body: {
        'status': 'ended',
        'is_active': false,
      }, prefer: 'return=minimal');
    }
  }

  Future<void> cleanupSoft() async {
    await endLives();
    for (final id in createdResIds) {
      await rest('PATCH', 'live_reservation_requests?id=eq.$id', service: true,
          body: {'status': 'expired'}, prefer: 'return=minimal');
    }
    for (final id in createdOrderIds) {
      await rest('PATCH', 'orders?id=eq.$id', service: true, body: {
        'status': 'cancelado',
      }, prefer: 'return=minimal');
    }
    for (final id in createdProductIds) {
      await rest('PATCH', 'products?id=eq.$id', service: true, body: {
        'is_sold': true,
        'list_on_marketplace': false,
        'quantity': 0,
      }, prefer: 'return=minimal');
    }
    for (final id in createdHelperIds) {
      await rest('DELETE', 'seller_helpers?id=eq.$id', service: true,
          prefer: 'return=minimal');
    }
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

  void judge({
    required String id,
    required String lens,
    required String title,
    required HttpHit hit,
    required bool cracked,
    required String actor,
    required String pre,
    required String repro,
    String severity = 'P1',
    Object? expected,
    Map<String, Object?>? evidence,
  }) {
    if (cracked) {
      hold(
        id: id,
        lens: lens,
        severity: severity,
        title: title,
        actor: actor,
        pre: pre,
        repro: repro,
        expected: expected ?? 'negado',
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
        'helper': helperId,
      },
      'created': {
        'lives': createdLiveIds,
        'items': createdItemIds,
        'orders': createdOrderIds,
        'products': createdProductIds,
        'reservations': createdResIds,
        'helpers': createdHelperIds,
      },
    });
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
