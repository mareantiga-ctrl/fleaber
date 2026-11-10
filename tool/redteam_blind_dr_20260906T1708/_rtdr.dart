/// RED TEAM CEGO DR — tip / rifa / convert / Edge live money pós-DHDM.
/// Staging fxdknzrqjenzqcvnwqqq only. Stripe TEST. No production. No Fase 4. No fixes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const stamp = '20260906T1708';
const prefix = 'RTDR-$stamp';
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

String repoRoot() {
  final cur = Directory.current.path;
  return cur.contains('redteam_blind_dr_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_dr_$stamp';

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

  String? get sessionId =>
      map?['checkoutSessionId']?.toString() ??
      map?['sessionId']?.toString() ??
      map?['checkout_session_id']?.toString();

  String? get tipId =>
      map?['tipId']?.toString() ?? map?['tip_id']?.toString();

  bool get rpcOk {
    if (!ok) return false;
    final m = map;
    if (m == null) return true;
    if (m['ok'] == false) return false;
    if (m['error'] != null) return false;
    return true;
  }
}

class Rtdr {
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
  final probes = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdLiveIds = <String>[];
  final createdLiveItemIds = <String>[];
  final createdResIds = <String>[];
  final createdOrderIds = <String>[];
  final createdRaffleIds = <String>[];
  final createdTipIds = <String>[];
  final lensesHit = <String>{};

  Rtdr._(this.url, this.anon, this.svc, this.env, this.crashSecret);

  factory Rtdr.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtdr._(
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
    int retries429 = 4,
  }) async {
    final path = qs == null || qs.isEmpty
        ? '/functions/v1/$name'
        : '/functions/v1/$name?$qs';
    HttpHit? last;
    for (var i = 0; i <= retries429; i++) {
      last = await req(
        method,
        path,
        jwt: jwt,
        body: body,
        service: service,
      );
      if (last.status != 429) return last;
      final wait = 12 + i * 8;
      stdout.writeln('RATE 429 $name; sleep ${wait}s');
      await Future<void>.delayed(Duration(seconds: wait));
    }
    return last!;
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
    const pass = 'Rtdr1708b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'Rtdr1708b2',
      name: '$prefix-B2',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2({bool hubPublished = true}) async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rtdr1708s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'Rtdr1708s2',
      name: '$prefix-S2',
      userType: 'vendedor',
      hubPublished: hubPublished,
    );
    seller2Jwt = await signIn(email, pass);
  }

  Future<String?> createProduct({
    String? seller,
    String? title,
    int qty = 1,
    double price = 9.0,
    bool live = false,
  }) async {
    final h = await rest('POST', 'products', service: true, body: {
      'seller_id': seller ?? sellerId,
      'title': title ?? '$prefix-sku',
      'price': price,
      'quantity': qty,
      'is_sold': false,
      'list_on_marketplace': !live,
      'available_for_live': true,
      'description': prefix,
      'image_urls': <String>[],
    });
    final id = h.firstId;
    if (id != null) createdProductIds.add(id);
    if (!h.ok) note('product.fail', 'createProduct', h.brief);
    return id;
  }

  Future<String?> createLive({
    String? seller,
    String title = '',
    String status = 'live',
    bool active = true,
    Map<String, Object?> extra = const {},
  }) async {
    final sid = seller ?? sellerId;
    final h = await rest('POST', 'lives', service: true, body: {
      'title': title.isEmpty ? '$prefix live' : title,
      'status': status,
      'seller_id': sid,
      'vendedor_id': sid,
      'is_active': active,
      ...extra,
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
    double price = 9.0,
  }) async {
    final body = <String, Object?>{
      'live_id': liveId,
      'title': title ?? '$prefix item',
      'ref_code': ref ?? 'RTDR-${DateTime.now().millisecondsSinceEpoch}',
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

  Future<String?> insertReservation({
    required String liveId,
    required String liveItemId,
    String? buyer,
    String? seller,
    String? jwt,
    bool service = false,
    String status = 'pending',
    int qty = 1,
    String source = 'fleaber_live',
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
        'source': source,
        'status': status,
      },
    );
    final id = h.firstId;
    if (id != null) createdResIds.add(id);
    if (!h.ok) {
      note('res.fail', 'insertReservation ${h.brief}', {
        'live': liveId,
        'item': liveItemId,
        'status': status,
      });
    }
    return id;
  }

  Future<HttpHit> accept(String rid, {String? jwt}) => rest(
        'PATCH',
        'live_reservation_requests?id=eq.$rid',
        jwt: jwt ?? sellerJwt,
        body: {'status': 'accepted'},
      );

  Future<Map<String, dynamic>?> resRow(String id) async {
    final h = await rest(
      'GET',
      'live_reservation_requests?id=eq.$id&select=id,status,requested_qty,buyer_id,live_id,live_item_id',
      service: true,
    );
    return h.map;
  }

  Future<Map<String, dynamic>?> stock(String liveItemId) async {
    final h = await rpc(
      'batata_live_item_stock',
      {'p_live_item_id': liveItemId},
      jwt: sellerJwt,
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

  Future<void> setHub(String id, bool published) async {
    await rest('PATCH', 'profiles?id=eq.$id', service: true, body: {
      'hub_published': published,
    }, prefer: 'return=minimal');
  }

  Future<void> restoreSeller1Published() async {
    if (sellerId == null) return;
    await setHub(sellerId!, true);
  }

  Future<int> raffleTickets(String raffleId, String userId) async {
    final ent = await rest(
      'GET',
      'live_raffle_entries?raffle_id=eq.$raffleId&user_id=eq.$userId&select=id,ticket_balance,is_eligible',
      service: true,
    );
    final tb = ent.map?['ticket_balance'];
    if (tb is num) return tb.toInt();
    return 0;
  }

  Future<int> winnerCount(String raffleId) async {
    final h = await rest(
      'GET',
      'live_raffle_winners?raffle_id=eq.$raffleId&select=id,user_id,rank',
      service: true,
    );
    return h.list.length;
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

  Future<Map<String, dynamic>?> productQty(String productId) async {
    final h = await rest(
      'GET',
      'products?id=eq.$productId&select=id,quantity,is_sold',
      service: true,
    );
    return h.map;
  }

  Future<Map<String, dynamic>?> tipRow(String id) async {
    final h = await rest(
      'GET',
      'live_tips?id=eq.$id&select=id,status,amount,buyer_id,seller_id,live_id,stripe_session_id',
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
    double price = 9.0,
    int qty = 1,
    String shipping = 'entrega em mão',
    String payment = 'Pagamento na app',
    bool service = false,
    String? liveId,
    String? liveItemId,
    String? reservationRequestId,
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
        if (liveId != null) 'live_id': liveId,
        if (liveItemId != null) 'live_item_id': liveItemId,
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
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,stripe_payment_intent_id,stripe_checkout_session_id,live_id,live_item_id,live_raffle_id',
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
    int? quantity,
    Map<String, Object?> extra = const {},
  }) {
    return edge(
      'create-payment-intent',
      body: {
        'buyer_id': buyer ?? buyerId,
        'order_id': orderId,
        'amount': amount,
        'currency': 'eur',
        if (productId != null) 'product_id': productId,
        if (seller != null) 'seller_id': seller,
        'shipping_method': 'mao',
        if (quantity != null) 'quantity': quantity,
        ...extra,
      },
      jwt: jwt ?? buyerJwt,
    );
  }

  Future<HttpHit> tipCheckout({
    required String liveId,
    required String seller,
    Object? amountEur = 2,
    String? jwt,
    Map<String, Object?> extra = const {},
  }) {
    return edge(
      'create-live-tip-checkout',
      jwt: jwt ?? buyerJwt,
      body: {
        'live_id': liveId,
        'seller_id': seller,
        'amount_eur': amountEur,
        ...extra,
      },
    );
  }

  Future<HttpHit> tipSettle(String sessionId) {
    return edge(
      'create-live-tip-checkout',
      method: 'GET',
      qs: 'checkout_return=success&session_id=$sessionId',
    );
  }

  Future<HttpHit> convertRpc(String rid, {String? jwt, String? orderId}) {
    return rpc(
      'batata_live_reservation_stripe_convert',
      {
        'p_request_id': rid,
        if (orderId != null) 'p_order_id': orderId,
      },
      jwt: jwt ?? sellerJwt,
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

  void probe({
    required String id,
    required String poco,
    required String payload,
    required Object http,
    Object? bd,
    required String result,
    String? lens,
    bool residual = false,
    bool classeNova = false,
    bool race = false,
    bool countFinding = false,
    Object? extra,
  }) {
    if (lens != null) lensesHit.add(lens);
    probes.add({
      'probe_id': id,
      'poco': poco,
      'payload': payload,
      'http': http is HttpHit ? http.brief : clip(http, 280),
      'bd': bd == null ? '' : clip(bd, 320),
      'result': result,
      if (lens != null) 'lens': lens,
      'residual': residual,
      'classe_nova': classeNova,
      'race': race,
      'count_finding': countFinding,
      if (extra != null) 'extra': extra,
    });
    stdout.writeln(
      'PROBE $id [$poco] $result '
      '${classeNova ? 'NOVA ' : ''}${race ? 'RACE ' : ''}${residual ? 'RESIDUAL ' : ''}'
      '${http is HttpHit ? http.brief : clip(http, 160)}',
    );
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
