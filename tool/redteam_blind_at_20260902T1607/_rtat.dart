/// RED TEAM CEGO AT — marketplace / checkout pós-ANAS.
/// Staging fxdknzrqjenzqcvnwqqq only. Stripe TEST. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260902T1607';
const prefix = 'RTAT-$stamp';
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

int protectionCents(int itemsCents, [int shippingCents = 0]) {
  final baseEur = (itemsCents + shippingCents) / 100.0;
  if (!(baseEur > 0)) return 0;
  final feeEur =
      (((0.65 + baseEur * 0.05) * 100).round()) / 100.0;
  return (feeEur * 100).round();
}

int expectedBagTotal(int itemsCents, {int shippingCents = 0}) =>
    itemsCents + shippingCents + protectionCents(itemsCents, shippingCents);

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
  return cur.contains('redteam_blind_at_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_at_$stamp';

class HttpHit {
  final int status;
  final String body;
  final Object? json;
  final String? location;
  HttpHit(this.status, this.body, this.json, [this.location]);
  bool get ok => status >= 200 && status < 300;
  bool get denied => status >= 400;
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

  int? get serverAmount {
    final m = map ?? {};
    return numOf(m['server_amount_cents'] ?? m['amount_total'] ?? m['amount'])
        ?.round();
  }

  String? get checkoutSessionId =>
      map?['checkoutSessionId']?.toString() ??
      map?['checkout_session_id']?.toString();

  String? get checkoutUrl =>
      map?['checkoutUrl']?.toString() ?? map?['url']?.toString();

  bool get reused => map?['reused_session'] == true;

  String? get err =>
      map?['message']?.toString() ??
      map?['hint']?.toString() ??
      map?['error']?.toString() ??
      map?['code']?.toString() ??
      snippet;
}

class Rtat {
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
  final createdBundleIds = <String>[];
  final createdOfferIds = <String>[];
  final lensesHit = <String>{};

  Rtat._(this.url, this.anon, this.svc, this.env, this.e2eSecret);

  factory Rtat.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtat._(
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
    bool service = false,
  }) {
    return req(
      'POST',
      '/functions/v1/$name',
      jwt: jwt,
      body: body,
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

  Future<({String jwt, String id})?> adminUser(String email, String pass) async {
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
        'handle': email.split('@').first.replaceAll(RegExp(r'[^a-z0-9]'), ''),
        'hub_published': false,
        'is_live': false,
      }, prefer: 'return=minimal');
      return (jwt: jwt, id: id);
    } catch (e) {
      note('adminUser.err', email, '$e');
      return null;
    }
  }

  Future<void> ensureBuyer2() async {
    final u = await adminUser(
        '${prefix.toLowerCase()}-b2@fleaber.test', 'Rtat1607b2!xK');
    if (u == null) return;
    buyer2Jwt = u.jwt;
    buyer2Id = u.id;
  }

  Future<void> ensureSeller2() async {
    final u = await adminUser(
        '${prefix.toLowerCase()}-s2@fleaber.test', 'Rtat1607s2!xK');
    if (u == null) return;
    seller2Jwt = u.jwt;
    seller2Id = u.id;
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,shipping_method,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,contract_unit_cents,contract_qty,bundle_id,product_offer_id,stock_units_applied',
      service: true,
    );
    return h.map;
  }

  Future<num?> walletBal(String? uid) async {
    if (uid == null) return null;
    final h = await rest(
      'GET',
      'wallets?id=eq.$uid&select=balance,id',
      service: true,
    );
    return numOf(h.map?['balance']);
  }

  Future<Map<String, num?>> wallets() async => {
        'buyer': await walletBal(buyerId),
        'seller': await walletBal(sellerId),
        'buyer2': await walletBal(buyer2Id),
        'seller2': await walletBal(seller2Id),
      };

  Future<int?> productQty(String pid) async {
    final h = await rest(
      'GET',
      'products?id=eq.$pid&select=id,quantity,is_sold,price',
      service: true,
    );
    return numOf(h.map?['quantity'])?.round();
  }

  Future<String?> insertProduct({
    required double price,
    int qty = 3,
    String? seller,
    String? title,
  }) async {
    final h = await rest('POST', 'products', service: true, body: {
      'seller_id': seller ?? sellerId,
      'title': title ?? '$prefix-${DateTime.now().microsecondsSinceEpoch}',
      'price': price,
      'quantity': qty,
      'ref_code': 'RTAT-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final id = h.firstId;
    if (id != null) createdProductIds.add(id);
    if (!h.ok) note('product.fail', 'insertProduct', h.brief);
    return id;
  }

  Future<String?> insertOrder({
    required String productId,
    String? jwt,
    String? buyer,
    String? seller,
    int qty = 1,
    double? priceTotal,
    String? offerId,
    String? bundleId,
    String shipping = 'entrega em mão',
    String payment = 'Pagamento na app',
    Map<String, Object?> extra = const {},
  }) async {
    final body = <String, Object?>{
      'buyer_id': buyer ?? buyerId,
      'seller_id': seller ?? sellerId,
      'product_id': productId,
      'quantity': qty,
      'status': 'reserva_pendente',
      'payment_method': payment,
      'shipping_method': shipping,
      if (priceTotal != null) 'price_total': priceTotal,
      if (offerId != null) 'product_offer_id': offerId,
      if (bundleId != null) 'bundle_id': bundleId,
      ...extra,
    };
    final h = await rest('POST', 'orders', jwt: jwt ?? buyerJwt, body: body);
    final id = h.firstId;
    if (id != null) createdOrderIds.add(id);
    if (!h.ok) note('order.fail', 'insertOrder', h.brief);
    return id;
  }

  Future<HttpHit> cpi(Object body, {String? jwt}) =>
      edge('create-payment-intent', body, jwt: jwt ?? buyerJwt);

  Future<HttpHit> bagCpi(
    List<Map<String, Object?>> lines, {
    String? jwt,
    String shipping = 'entrega em mão',
    Map<String, Object?> extra = const {},
  }) {
    return cpi({
      'bag_checkout': true,
      'bag_lines': lines,
      'shipping_method': shipping,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      ...extra,
    }, jwt: jwt);
  }

  Future<HttpHit> singleCpi(
    String orderId, {
    String? jwt,
    String shipping = 'entrega em mão',
    Map<String, Object?> extra = const {},
  }) {
    return cpi({
      'order_id': orderId,
      'shipping_method': shipping,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      ...extra,
    }, jwt: jwt);
  }

  Future<String?> checkoutAlive(String? url) async {
    if (url == null || url.isEmpty) return 'no-url';
    final client = HttpClient();
    try {
      var uri = Uri.parse(url);
      for (var i = 0; i < 6; i++) {
        final rq = await client.getUrl(uri);
        rq.followRedirects = false;
        final rs = await rq.close();
        final loc = rs.headers.value('location');
        final raw = await rs.fold<List<int>>(<int>[], (a, b) {
          a.addAll(b);
          return a;
        });
        String text;
        try {
          text = utf8.decode(raw);
        } catch (_) {
          text = '';
        }
        if (rs.statusCode >= 300 && rs.statusCode < 400 && loc != null) {
          uri = uri.resolve(loc);
          continue;
        }
        final low = text.toLowerCase();
        if (rs.statusCode >= 400) return 'http-${rs.statusCode}';
        if (low.contains('this checkout session has expired') ||
            low.contains('this payment page has expired') ||
            low.contains('checkout session has expired')) {
          return 'expired';
        }
        return 'alive-http-${rs.statusCode}';
      }
      return 'redirect-loop';
    } catch (e) {
      return 'err:$e';
    } finally {
      client.close(force: true);
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

  Future<void> expectDenied({
    required String id,
    required String lens,
    required String title,
    required HttpHit hit,
    required String actor,
    required String pre,
    required String repro,
    String severityIfOpen = 'P2',
    Map<String, Object?>? evidence,
  }) async {
    if (hit.ok) {
      hold(
        id: id,
        lens: lens,
        severity: severityIfOpen,
        title: title,
        actor: actor,
        pre: pre,
        repro: repro,
        expected: '4xx',
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
      'auditor': 'REDTEAM_BLIND_AT_MARKETPLACE_POS_ANAS_v1',
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
        'orders': createdOrderIds,
        'products': createdProductIds,
        'bundles': createdBundleIds,
        'offers': createdOfferIds,
      },
    });
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
