/// HTTP client — staging fxdknzrqjenzqcvnwqqq only. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260901T1715';
const prefix = 'RTAA-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

String clip(Object? v, [int n = 360]) {
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
  return cur.contains('redteam_blind_aa_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_aa_$stamp';

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

class Rtaa {
  final String url;
  final String anon;
  final String svc;
  final Map<String, String> env;
  String? buyerJwt;
  String? sellerJwt;
  String? buyer2Jwt;
  String? seller2Jwt;
  String? helperJwt;
  String? viewJwt;
  String? buyerId;
  String? sellerId;
  String? buyer2Id;
  String? seller2Id;
  String? helperId;
  String? viewId;
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

  Rtaa._(this.url, this.anon, this.svc, this.env);

  factory Rtaa.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtaa._(
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
    const pass = 'Rtaa1715b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtaa1715b2',
      name: '$prefix-B2',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2() async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rtaa1715s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtaa1715s2',
      name: '$prefix-S2',
    );
    seller2Jwt = await signIn(email, pass);
  }

  Future<void> ensureHelper() async {
    final email = '${prefix.toLowerCase()}-h1@fleaber.test';
    const pass = 'Rtaa1715h1!xK';
    helperId = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtaa1715h1',
      name: '$prefix-H1',
    );
    helperJwt = await signIn(email, pass);
  }

  Future<void> ensureViewHelper() async {
    final email = '${prefix.toLowerCase()}-hv@fleaber.test';
    const pass = 'Rtaa1715hv!xK';
    viewId = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtaa1715hv',
      name: '$prefix-HV',
    );
    viewJwt = await signIn(email, pass);
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
  }) async {
    final h = await rest('POST', 'live_items', jwt: jwt, service: service, body: {
      'live_id': liveId,
      'ref_code': ref ?? 'X${DateTime.now().millisecondsSinceEpoch % 100000}',
      'title': '$prefix live_only',
      'price': price,
      'is_active': true,
      'item_kind': 'live_only',
      'quantity': qty,
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
  }) async {
    final h = await rest('POST', 'live_items', jwt: jwt, service: service, body: {
      'live_id': liveId,
      'ref_code': ref ?? 'M${DateTime.now().millisecondsSinceEpoch % 100000}',
      'title': '$prefix mkt',
      'price': price,
      'is_active': true,
      'item_kind': 'marketplace_product',
      'product_id': productId,
    });
    final id = h.firstId;
    if (id != null) createdItemIds.add(id);
    if (!h.ok) note('item.fail', 'insertMarketItem', h.brief);
    return id;
  }

  Future<Map<String, dynamic>?> itemRow(String id) async {
    final h = await rest(
      'GET',
      'live_items?id=eq.$id&select=id,live_id,product_id,item_kind,quantity,status,price,ref_code',
      service: true,
    );
    return h.map;
  }

  Future<HttpHit> insertReservation({
    required String liveId,
    String? liveItemId,
    String? seller,
    String? buyer,
    String source = 'facebook_manual',
    String status = 'pending',
    int qty = 1,
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
    };
    return rest(
      'POST',
      'live_reservation_requests',
      jwt: jwt,
      service: service,
      body: body,
    );
  }

  Future<Map<String, dynamic>?> reqRow(String id) async {
    final h = await rest(
      'GET',
      'live_reservation_requests?id=eq.$id&select=id,live_id,live_item_id,seller_id,buyer_id,source,status,requested_qty,processed_by_user_id,notes',
      service: true,
    );
    return h.map;
  }

  Future<HttpHit> processReservation(
    String id,
    String action, {
    String? jwt,
    String? processedBy,
    String? notes,
  }) {
    return rpc('batata_process_live_reservation_request', {
      'p_request_id': id,
      'p_action': action,
      if (processedBy != null) 'p_processed_by': processedBy,
      if (notes != null) 'p_notes': notes,
    }, jwt: jwt ?? sellerJwt);
  }

  Future<HttpHit> stock(String liveItemId, {String? jwt}) {
    return rpc('batata_live_item_stock', {'p_live_item_id': liveItemId},
        jwt: jwt ?? sellerJwt);
  }

  Future<String?> inviteHelper({
    required String helperUserId,
    required String helperEmail,
    Map<String, Object?> perms = const {
      'can_manage_reservations': true,
      'can_view_live_dashboard': true,
    },
    String? seller,
    String? jwt,
  }) async {
    final sid = seller ?? sellerId;
    final h = await rest('POST', 'seller_helpers', jwt: jwt ?? sellerJwt, body: {
      'seller_id': sid,
      'helper_user_id': helperUserId,
      'invited_by': sid,
      'invited_email': helperEmail,
      'display_name': '$prefix helper',
      'invitation_status': 'pending',
      'active': false,
      'permissions': perms,
    });
    final id = h.firstId;
    if (id != null) createdHelperIds.add(id);
    return id;
  }

  Future<HttpHit> acceptInvite(String helperRowId, {String? jwt}) {
    return rest('PATCH', 'seller_helpers?id=eq.$helperRowId', jwt: jwt, body: {
      'invitation_status': 'accepted',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<HttpHit> activateHelper(String helperRowId, {String? jwt}) {
    return rest('PATCH', 'seller_helpers?id=eq.$helperRowId',
        jwt: jwt ?? sellerJwt, body: {
      'active': true,
      'invitation_status': 'accepted',
    });
  }

  Future<Map<String, dynamic>?> hubItem(String id) async {
    final h = await rest(
      'GET',
      'hub_live_items_public?id=eq.$id&select=id,title,is_active,status,item_kind',
      service: true,
    );
    return h.map;
  }

  Future<HttpHit> markSold(String liveItemId, {String? jwt}) {
    return rpc('batata_mark_live_item_sold', {'p_live_item_id': liveItemId},
        jwt: jwt ?? sellerJwt);
  }

  Future<Map<String, dynamic>?> helperRow(String id) async {
    final h = await rest(
      'GET',
      'seller_helpers?id=eq.$id&select=id,seller_id,helper_user_id,active,invitation_status,permissions',
      service: true,
    );
    return h.map;
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
      'helper': await walletBal(helperId),
    };
  }

  Future<List<dynamic>> ordersForItem(String liveItemId) async {
    final h = await rest(
      'GET',
      'orders?live_item_id=eq.$liveItemId&select=id,status,buyer_id,amount_paid_cents,stripe_payment_intent_id,quantity',
      service: true,
    );
    return h.list;
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

  Future<void> dumpAll([String file = 'findings.json']) async {
    await dumpJson('${outDir()}/$file', {
      'stamp': stamp,
      'prefix': prefix,
      'lenses': lensesHit.toList()..sort(),
      'findings': findings,
      'blocked': blocked,
      'skipped': skipped,
      'notes': notes,
      'actors': {
        'buyer': buyerId,
        'seller': sellerId,
        'buyer2': buyer2Id,
        'seller2': seller2Id,
        'helper': helperId,
        'view': viewId,
      },
      'created': {
        'lives': createdLiveIds,
        'items': createdItemIds,
        'reqs': createdReqIds,
        'orders': createdOrderIds,
        'products': createdProductIds,
        'helpers': createdHelperIds,
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
