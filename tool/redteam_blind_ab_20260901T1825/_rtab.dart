/// RED TEAM CEGO AB — marketplace/checkout. Staging fxdknzrqjenzqcvnwqqq only.
/// Não corrige. Sem produção. Sem Fase 4. service_role só fixture/observação/cleanup.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260901T1825';
const prefix = 'RTAB-$stamp';
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
  return cur.contains('redteam_blind_ab_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_ab_$stamp';

class HttpHit {
  final int status;
  final String body;
  final Object? json;
  HttpHit(this.status, this.body, this.json);
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

  int? get serverAmount {
    final m = map;
    if (m == null) return null;
    return numOf(m['server_amount_cents'] ?? m['amount_total'])?.round();
  }

  String? get checkoutSessionId =>
      map?['checkoutSessionId']?.toString() ??
      map?['checkout_session_id']?.toString();

  String? get checkoutUrl => map?['checkoutUrl']?.toString();
}

class Rtab {
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
  final createdBundleIds = <String>[];
  final createdChatIds = <String>[];
  final lensesHit = <String>{};

  Rtab._(this.url, this.anon, this.svc, this.e2eSecret, this.env);

  factory Rtab.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtab._(
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
      return HttpHit(rs.statusCode, text, parsed);
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
    const pass = 'Rtab1825b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtab1825b2',
      name: '$prefix-B2',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2() async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rtab1825s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtab1825s2',
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
  }) async {
    final h = await rest('POST', 'products', service: true, body: {
      'seller_id': seller ?? sellerId,
      'title': title ?? '$prefix-sku',
      'price': price,
      'quantity': qty,
      'is_sold': false,
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

  Future<Map<String, dynamic>?> productRow(String id) async {
    final h = await rest(
      'GET',
      'products?id=eq.$id&select=id,seller_id,title,price,quantity,is_sold,list_on_marketplace',
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
    double? price,
    int qty = 1,
    String payment = 'Pagamento na app',
    String shipping = 'entrega em mão',
    String? bundleId,
    bool service = false,
    int? contractQty,
    int? contractUnitCents,
  }) async {
    final body = <String, Object?>{
      'buyer_id': buyer ?? buyerId,
      'seller_id': seller ?? sellerId,
      'product_id': productId,
      if (price != null) 'price_total': price,
      'quantity': qty,
      'status': status,
      'payment_method': payment,
      'shipping_method': shipping,
      if (bundleId != null) 'bundle_id': bundleId,
      if (contractQty != null) 'contract_qty': contractQty,
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
    if (!h.ok) {
      note('order.fail', 'insertOrder ${h.brief}', {
        'product': productId,
        'qty': qty,
      });
    }
    return id;
  }

  Future<HttpHit> checkout({
    required String orderId,
    String? jwt,
    String? buyer,
    num amount = 50,
    String? productId,
    String? seller,
    String shipping = 'mao',
    int? quantity,
    String? currency,
    bool prize = false,
  }) {
    return edge('create-payment-intent', {
      'buyer_id': buyer ?? buyerId,
      'order_id': orderId,
      'amount': amount,
      if (productId != null) 'product_id': productId,
      if (seller != null) 'seller_id': seller,
      'shipping_method': shipping,
      if (quantity != null) 'quantity': quantity,
      if (currency != null) 'currency': currency,
      if (prize) 'prize_shipping': true,
    }, jwt: jwt ?? buyerJwt);
  }

  Future<HttpHit> checkoutBag({
    required List<Map<String, Object?>> lines,
    String? jwt,
    String? buyer,
    num amount = 50,
    String shipping = 'mao',
    String? seller,
    String? currency,
  }) {
    final first = lines.isEmpty ? <String, Object?>{} : lines.first;
    return edge('create-payment-intent', {
      'buyer_id': buyer ?? buyerId,
      'order_id': first['order_id'],
      'amount': amount,
      if (first['product_id'] != null) 'product_id': first['product_id'],
      if (seller != null) 'seller_id': seller,
      'shipping_method': shipping,
      'bag_checkout': true,
      'bag_lines': lines,
      if (currency != null) 'currency': currency,
    }, jwt: jwt ?? buyerJwt);
  }

  Future<String?> ensureChat(String productId, {String? buyer, String? seller}) async {
    final b = buyer ?? buyerId;
    final s = seller ?? sellerId;
    final existing = await rest(
      'GET',
      'chats?product_id=eq.$productId&or=(and(user_a.eq.$b,user_b.eq.$s),and(user_a.eq.$s,user_b.eq.$b))&select=id&limit=1',
      service: true,
    );
    if (existing.firstId != null) return existing.firstId;
    final h = await rest('POST', 'chats', service: true, body: {
      'user_a': b,
      'user_b': s,
      'product_id': productId,
    });
    final id = h.firstId;
    if (id != null) createdChatIds.add(id);
    return id;
  }

  Future<String?> createBundle({
    required List<String> productIds,
    String? buyer,
    String? seller,
    String? jwt,
    String? chatId,
    num? discountPct,
  }) async {
    final h = await rest('POST', 'product_bundles', jwt: jwt ?? buyerJwt, body: {
      'buyer_id': buyer ?? buyerId,
      'seller_id': seller ?? sellerId,
      'product_ids': productIds,
      'subtotal_eur': 1,
      'discount_pct': discountPct ?? 0,
      'discount_eur': 0,
      'total_eur': 1,
      'status': 'pending',
      if (chatId != null) 'chat_id': chatId,
    });
    final id = h.firstId;
    if (id != null) createdBundleIds.add(id);
    if (!h.ok) note('bundle.fail', 'createBundle', h.brief);
    return id;
  }

  Future<HttpHit> acceptBundle(String id, {String? jwt, num? discountPct}) {
    return rest('PATCH', 'product_bundles?id=eq.$id', jwt: jwt ?? sellerJwt, body: {
      'status': 'accepted',
      if (discountPct != null) 'discount_pct': discountPct,
    });
  }

  Future<Map<String, dynamic>?> bundleRow(String id) async {
    final h = await rest(
      'GET',
      'product_bundles?id=eq.$id&select=id,status,total_eur,subtotal_eur,discount_pct,product_ids,buyer_id,seller_id',
      service: true,
    );
    return h.map;
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,shipping_method,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,stock_units_applied,completed_at,contract_unit_cents,contract_qty,product_offer_id,bundle_id,shipped_at',
      service: true,
    );
    return h.map;
  }

  Future<num> walletBal(String? id) async {
    if (id == null) return 0;
    final h = await rest(
      'GET',
      'wallets?id=eq.$id&select=balance',
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

  Future<({String oid, String pid, String? pi})?> payToPago({
    String lens = 'AB8',
    String? seller,
    String? buyer,
    int initialQty = 2,
  }) async {
    final paid = await e2e('setup_paid_order', {'initial_qty': initialQty},
        seller: seller, buyer: buyer);
    note('fixture.paid', 'setup_paid_order Stripe TEST', paid.brief, lens: lens);
    final oid = parseE2eOrderId(paid);
    final pid = paid.map?['product_id']?.toString();
    if (pid != null) createdProductIds.add(pid);
    if (oid == null || pid == null) return null;
    createdOrderIds.add(oid);
    final row = await orderRow(oid);
    return (oid: oid, pid: pid, pi: row?['stripe_payment_intent_id']?.toString());
  }

  Future<String> peekCheckoutPage(String checkoutUrl) async {
    final client = HttpClient();
    try {
      var uri = Uri.parse(checkoutUrl);
      for (var i = 0; i < 4; i++) {
        final rq = await client.getUrl(uri);
        rq.followRedirects = false;
        final rs = await rq.close();
        final loc = rs.headers.value('location');
        final text = await rs.transform(utf8.decoder).join();
        if (rs.statusCode >= 300 && rs.statusCode < 400 && loc != null) {
          uri = uri.resolve(loc);
          continue;
        }
        return text;
      }
      return '';
    } catch (e) {
      return 'peek_err:$e';
    } finally {
      client.close(force: true);
    }
  }

  Map<String, Object?> currencyHints(String html) {
    final lower = html.toLowerCase();
    return {
      'len': html.length,
      'has_usd': lower.contains('"currency":"usd"') ||
          lower.contains('currency": "usd"') ||
          RegExp(r'\busd\b').hasMatch(lower) && lower.contains('stripe'),
      'has_eur': lower.contains('"currency":"eur"') ||
          lower.contains('currency": "eur"'),
      'has_jpy': lower.contains('"currency":"jpy"'),
      'snippet': clip(html.replaceAll(RegExp(r'\s+'), ' '), 280),
    };
  }

  Future<void> cleanup() async {
    for (final oid in createdOrderIds) {
      final row = await orderRow(oid);
      final paid = (numOf(row?['amount_paid_cents']) ?? 0) > 0 ||
          '${row?['stripe_payment_intent_id'] ?? ''}'.isNotEmpty;
      if (paid) continue;
      await rest('PATCH', 'orders?id=eq.$oid', service: true, body: {
        'status': 'cancelado',
      }, prefer: 'return=minimal');
    }
    for (final bid in createdBundleIds) {
      await rest('PATCH', 'product_bundles?id=eq.$bid', service: true, body: {
        'status': 'cancelled',
      }, prefer: 'return=minimal');
    }
    for (final pid in createdProductIds) {
      await rest('PATCH', 'products?id=eq.$pid', service: true, body: {
        'list_on_marketplace': false,
        'quantity': 0,
      }, prefer: 'return=minimal');
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
    stdout.writeln('NOTE $id ${lens ?? ''} $title ${clip(ev is HttpHit ? ev.brief : ev, 240)}');
  }

  void block(String id, String lens, String title, Object? ev) {
    lensesHit.add(lens);
    blocked.add({
      'id': id,
      'lens': lens,
      'title': title,
      'ev': ev is HttpHit ? ev.brief : ev,
    });
    stdout.writeln('BLOCKED $id [$lens] $title ${clip(ev is HttpHit ? ev.brief : ev, 180)}');
  }

  void closedPath(String id, String title, Object? ev, {required String lens}) {
    lensesHit.add(lens);
    notes.add({
      'id': id,
      'lens': lens,
      'closed': true,
      'title': title,
      'ev': ev is HttpHit ? ev.brief : ev,
    });
    stdout.writeln('CLOSED $id [$lens] $title ${clip(ev is HttpHit ? ev.brief : ev, 180)}');
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
