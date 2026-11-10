/// RED TEAM CEGO ER — bag∥avulso reteste GATE FASE 4.
/// Staging fxdknzrqjenzqcvnwqqq only. Stripe TEST. No production. No Fase 4. No fixes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const stamp = '20260907T0744';
const prefix = 'RTER-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';
const claimTtlMs = 120000;

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
  return cur.contains('redteam_blind_er_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_er_$stamp';

class HttpHit {
  final int status;
  final String body;
  final Object? json;
  final String? location;
  HttpHit(this.status, this.body, this.json, [this.location]);
  bool get ok => status >= 200 && status < 300;
  String get snippet => clip(body);
  String get brief => '$status ${clip(body, 280)}';
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
  String? get checkoutUrl => map?['checkoutUrl']?.toString();
  bool get reused => map?['reused_session'] == true;
}

class Rtdb {
  final String url;
  final String anon;
  final String svc;
  final Map<String, String> env;
  final String e2eSecret;
  String? buyerJwt;
  String? sellerJwt;
  String? buyer2Jwt;
  String? seller2Jwt;
  String? buyer3Jwt;
  String? buyerId;
  String? sellerId;
  String? buyer2Id;
  String? seller2Id;
  String? buyer3Id;
  final findings = <Map<String, dynamic>>[];
  final notes = <Map<String, dynamic>>[];
  final blocked = <Map<String, dynamic>>[];
  final skipped = <Map<String, dynamic>>[];
  final probes = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdBundleIds = <String>[];
  final createdOfferIds = <String>[];
  final createdSessionIds = <String>[];
  final lensesHit = <String>{};
  final wellsTried = <String>{};

  Rtdb._(this.url, this.anon, this.svc, this.env, this.e2eSecret);

  factory Rtdb.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtdb._(
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
    client.idleTimeout = const Duration(seconds: 90);
    if (timeout != null) {
      client.connectionTimeout = timeout;
    }
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
    Map<String, String>? extra,
    bool service = false,
    String qs = '',
    Duration? timeout,
  }) {
    final q = qs.isEmpty ? '' : (qs.startsWith('?') ? qs : '?$qs');
    return req(
      method,
      '/functions/v1/$name$q',
      jwt: jwt,
      body: body,
      extra: extra,
      service: service,
      timeout: timeout,
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
    const pass = 'Rter0744b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rter0744b2',
      name: '$prefix-B2',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2() async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rter0744s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rter0744s2',
      name: '$prefix-S2',
    );
    seller2Jwt = await signIn(email, pass);
  }

  Future<void> ensureBuyer3() async {
    final email = '${prefix.toLowerCase()}-b3@fleaber.test';
    const pass = 'Rter0744b3!xK';
    buyer3Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rter0744b3',
      name: '$prefix-B3',
    );
    buyer3Jwt = await signIn(email, pass);
  }

  Future<String?> ensureNamed({
    required String email,
    required String pass,
    required String handle,
    required String name,
  }) {
    return _ensureUser(
      email: email,
      pass: pass,
      handle: handle,
      name: name,
    );
  }

  /// Comprador JWT sem checkout prévio — cada corrida A1–A6 precisa disto.
  Future<({String id, String jwt})> mintBuyer(String tag) async {
    final email = '${prefix.toLowerCase()}-$tag@fleaber.test';
    final pass = 'Rter0744$tag!xK9';
    final id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rter0744$tag',
      name: '$prefix-$tag',
    );
    if (id == null) {
      throw StateError('mintBuyer $tag failed');
    }
    final jwt = await signIn(email, pass);
    note('actor.mint', tag, id, lens: 'ER-A', well: 'ER-A');
    return (id: id, jwt: jwt);
  }

  Future<String?> createProduct({
    String? seller,
    String? title,
    int qty = 3,
    bool listed = true,
    double price = 12.0,
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
    String? bundleId,
    String? offerId,
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
        if (bundleId != null) 'bundle_id': bundleId,
        if (offerId != null) 'product_offer_id': offerId,
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
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,shipping_method,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,stock_units_applied,contract_unit_cents,contract_qty,bundle_id,product_offer_id,proof_url',
      service: true,
    );
    return h.map;
  }

  Future<HttpHit> checkout({
    required String orderId,
    String? jwt,
    String? buyer,
    Object? amount = 1,
    Object? currency,
    String? productId,
    String? seller,
    String shipping = 'mao',
    int? quantity,
    bool includeCurrency = true,
    Map<String, Object?> extra = const {},
    Duration? timeout,
  }) {
    final body = <String, Object?>{
      'buyer_id': buyer ?? buyerId,
      'order_id': orderId,
      'amount': amount,
      if (productId != null) 'product_id': productId,
      if (seller != null) 'seller_id': seller,
      'shipping_method': shipping,
      if (quantity != null) 'quantity': quantity,
      ...extra,
    };
    if (includeCurrency) body['currency'] = currency ?? 'eur';
    return edge('create-payment-intent', body,
        jwt: jwt ?? buyerJwt, timeout: timeout ?? const Duration(seconds: 45));
  }

  Future<HttpHit> checkoutBag({
    required List<Map<String, Object?>> lines,
    String? jwt,
    String? buyer,
    Object? amount = 1,
    Object? currency = 'eur',
    String shipping = 'mao',
    String? seller,
    String? orderId,
    Map<String, Object?> extra = const {},
    Duration? timeout,
  }) {
    final first = lines.isEmpty ? <String, Object?>{} : lines.first;
    return edge(
      'create-payment-intent',
      {
        'buyer_id': buyer ?? buyerId,
        'order_id': orderId ?? first['order_id'],
        'amount': amount,
        'currency': currency,
        if (first['product_id'] != null) 'product_id': first['product_id'],
        if (seller != null) 'seller_id': seller,
        'shipping_method': shipping,
        'bag_checkout': true,
        'bag_lines': lines,
        ...extra,
      },
      jwt: jwt ?? buyerJwt,
      timeout: timeout ?? const Duration(seconds: 45),
    );
  }

  Future<HttpHit> settleGet(String sessionId, {String extraQs = ''}) {
    final extra = extraQs.isEmpty
        ? ''
        : (extraQs.startsWith('&') ? extraQs : '&$extraQs');
    return edge(
      'create-payment-intent',
      null,
      method: 'GET',
      qs: 'checkout_return=success&session_id=$sessionId$extra',
    );
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

  Future<HttpHit> stripeSession(String sid, {bool expandPi = false}) {
    final q = expandPi ? '?expand[]=payment_intent' : '';
    return stripe('GET', '/v1/checkout/sessions/$sid$q');
  }

  Future<HttpHit> stripeExpire(String sid) {
    return stripe('POST', '/v1/checkout/sessions/$sid/expire');
  }

  Future<HttpHit> stripeListSessions({int limit = 30}) {
    return stripe('GET', '/v1/checkout/sessions?limit=$limit');
  }

  Future<HttpHit> stripeForm(
    String method,
    String path, {
    Map<String, String>? fields,
    String? bearer,
  }) async {
    final key = (bearer ?? stripeTestKey ?? '').trim();
    if (key.isEmpty) {
      return HttpHit(0, 'no_stripe_key', {'error': 'no_stripe_key'});
    }
    final uri = Uri.parse(
      path.startsWith('http') ? path : 'https://api.stripe.com$path',
    );
    final client = HttpClient();
    try {
      final rq = await client.openUrl(method, uri);
      rq.headers.set('Authorization', 'Bearer $key');
      rq.headers.set('User-Agent', 'FleaberRedTeamER/1.0');
      if (fields != null && fields.isNotEmpty) {
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

  String? extractPk(String html) {
    return RegExp(r'pk_test_[A-Za-z0-9]+').firstMatch(html)?.group(0);
  }

  String? extractPi(String raw) {
    return RegExp(r'pi_[A-Za-z0-9]+').firstMatch(raw)?.group(0);
  }

  String? extractSecret(String raw) {
    return RegExp(r'pi_[A-Za-z0-9]+_secret_[A-Za-z0-9]+')
        .firstMatch(raw)
        ?.group(0);
  }

  /// GET cru (Checkout Stripe URL) — sem headers Supabase.
  Future<HttpHit> rawGet(String url) async {
    final uri = Uri.parse(url);
    final client = HttpClient();
    client.idleTimeout = const Duration(seconds: 20);
    try {
      final rq = await client.getUrl(uri);
      rq.followRedirects = true;
      rq.maxRedirects = 5;
      rq.headers.set('User-Agent', 'FleaberRedTeamER/1.0');
      final rs = await rq.close().timeout(const Duration(seconds: 15));
      final text = await rs.transform(utf8.decoder).join();
      return HttpHit(rs.statusCode, text, null);
    } on TimeoutException {
      return HttpHit(598, 'client_timeout', {'error': 'client_timeout'});
    } on SocketException catch (e) {
      return HttpHit(599, 'socket $e', {'error': '$e'});
    } finally {
      client.close(force: true);
    }
  }

  /// Paga uma Checkout Session TEST (4242 / pm_card_visa / tok_visa).
  Future<Map<String, Object?>> payCheckout4242(
    String sid, {
    String? checkoutUrl,
  }) async {
    final out = <String, Object?>{
      'sid': sid,
      'paid': false,
      'via': 'none',
    };
    if (!sid.startsWith('cs_')) {
      out['via'] = 'not_cs';
      return out;
    }

    Future<void> markPaid(String via, HttpHit hit, {String? pi}) async {
      final st = '${hit.map?['status'] ?? ''}';
      final pay = '${hit.map?['payment_status'] ?? ''}';
      final ok = hit.ok &&
          (st == 'succeeded' ||
              st == 'complete' ||
              pay == 'paid' ||
              pay == 'no_payment_required');
      out['via'] = via;
      out['confirm'] = hit.brief;
      if (pi != null) out['pi'] = pi;
      if (ok) out['paid'] = true;
    }

    if (stripeTestKey != null) {
      final sess = await stripeSession(sid, expandPi: true);
      out['retrieve'] = sess.brief;
      final piRaw = sess.map?['payment_intent'];
      String? pi;
      String? piStatus;
      if (piRaw is String && piRaw.startsWith('pi_')) {
        pi = piRaw;
      } else if (piRaw is Map) {
        pi = piRaw['id']?.toString();
        piStatus = piRaw['status']?.toString();
      }
      out['pi'] = pi;
      out['pi_status'] = piStatus;
      out['cs_status'] = sess.map?['status'];
      out['payment_status'] = sess.map?['payment_status'];
      if ('${sess.map?['payment_status']}' == 'paid' ||
          '${sess.map?['status']}' == 'complete') {
        out['paid'] = true;
        out['via'] = 'already_paid';
      } else if (pi != null && pi.startsWith('pi_')) {
        final confirm = await stripe(
          'POST',
          '/v1/payment_intents/$pi/confirm',
          fields: {'payment_method': 'pm_card_visa'},
        );
        await markPaid('sk_pm_card_visa', confirm, pi: pi);
        if (out['paid'] != true) {
          final tok = await stripe(
            'POST',
            '/v1/payment_intents/$pi/confirm',
            fields: {
              'payment_method_data[type]': 'card',
              'payment_method_data[card][token]': 'tok_visa',
            },
          );
          await markPaid('sk_tok_visa', tok, pi: pi);
        }
      }
    }

    if (out['paid'] != true) {
      final url = (checkoutUrl ?? '').trim().isEmpty
          ? 'https://checkout.stripe.com/c/pay/$sid'
          : checkoutUrl!.trim();
      final page = await rawGet(url);
      out['page_http'] = page.status;
      out['page_len'] = page.body.length;
      final pk = extractPk(page.body);
      out['pk'] = pk == null ? null : '${pk.substring(0, 12)}…';
      final htmlPi = extractPi(page.body);
      final htmlSec = extractSecret(page.body);
      if (htmlPi != null) out['html_pi'] = htmlPi;
      if (pk != null) {
        final init = await stripeForm(
          'POST',
          '/v1/payment_pages/$sid/init',
          bearer: pk,
          fields: {'key': pk},
        );
        out['pp_init'] = init.brief;
        var pi = init.map?['payment_intent'] is Map
            ? (init.map!['payment_intent'] as Map)['id']?.toString()
            : init.map?['payment_intent']?.toString();
        var secret = init.map?['payment_intent'] is Map
            ? (init.map!['payment_intent'] as Map)['client_secret']
                ?.toString()
            : init.map?['client_secret']?.toString();
        pi ??= extractPi(init.body) ?? htmlPi;
        secret ??= extractSecret(init.body) ?? htmlSec;
        out['pi'] ??= pi;
        if (pi != null && pi.startsWith('pi_')) {
          final fields = <String, String>{
            'payment_method_data[type]': 'card',
            'payment_method_data[card][token]': 'tok_visa',
            'return_url': 'https://fleaber.pt',
          };
          if (secret != null && secret.contains('secret')) {
            fields['client_secret'] = secret;
          }
          final confirm = await stripeForm(
            'POST',
            '/v1/payment_intents/$pi/confirm',
            bearer: pk,
            fields: fields,
          );
          await markPaid('pk_tok_visa', confirm, pi: pi);
          if (out['paid'] != true) {
            final card = await stripeForm(
              'POST',
              '/v1/payment_intents/$pi/confirm',
              bearer: pk,
              fields: {
                'payment_method_data[type]': 'card',
                'payment_method_data[card][number]': '4242424242424242',
                'payment_method_data[card][exp_month]': '12',
                'payment_method_data[card][exp_year]': '2030',
                'payment_method_data[card][cvc]': '123',
                'return_url': 'https://fleaber.pt',
                if (secret != null) 'client_secret': secret,
              },
            );
            await markPaid('pk_card_4242', card, pi: pi);
          }
        }
      }
    }

    await Future<void>.delayed(const Duration(seconds: 2));
    final settle = await settleGet(sid);
    out['settle'] = settle.brief;
    if (settle.ok) {
      out['settle_ok'] = true;
      final st = '${settle.map?['status'] ?? ''}'.toLowerCase();
      if (st.contains('pago') ||
          st.contains('paid') ||
          st.contains('complete')) {
        out['paid'] = true;
        out['via'] = '${out['via']}+settle';
      }
    }

    if (stripeTestKey != null) {
      final after = await stripeSession(sid, expandPi: true);
      out['after'] = {
        'status': after.map?['status'],
        'payment_status': after.map?['payment_status'],
      };
      if ('${after.map?['payment_status']}' == 'paid') {
        out['paid'] = true;
      }
    }
    return out;
  }

  /// Oráculo Session: status=open + payment_status unpaid + url.
  /// Sem sk_test_ → GET checkout URL (expired vs form) + settle.
  Future<Map<String, Object?>> sessionOracle(
    String sid, {
    String? checkoutUrl,
  }) async {
    if (!sid.startsWith('cs_')) {
      return {'sid': sid, 'open_payable': false, 'via': 'not_cs'};
    }
    final native = await stripeSession(sid);
    if (native.status != 0) {
      final st = '${native.map?['status'] ?? ''}';
      final pay = '${native.map?['payment_status'] ?? ''}';
      final url = native.map?['url'];
      final open = st == 'open' && pay != 'paid' && url != null;
      return {
        'sid': sid,
        'open_payable': open,
        'via': 'stripe_retrieve',
        'status': st,
        'payment_status': pay,
        'http': native.status,
      };
    }
    final url = (checkoutUrl ?? '').trim().isEmpty
        ? 'https://checkout.stripe.com/c/pay/$sid'
        : checkoutUrl!.trim();
    final page = await rawGet(url);
    final body = page.body.toLowerCase();
    final expired = body.contains('expired') ||
        body.contains('expirou') ||
        body.contains('this session has expired') ||
        body.contains('checkout session has expired') ||
        page.status == 404 ||
        page.status == 410;
    final settle = await settleGet(sid);
    final settlePayable = settle.status == 402 || settle.ok;
    final open = !expired && settlePayable;
    return {
      'sid': sid,
      'open_payable': open,
      'via': 'checkout_url+settle',
      'page_http': page.status,
      'expired_copy': expired,
      'settle': settle.status,
      'url_host': Uri.tryParse(url)?.host,
    };
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
      'buyer3': await walletBal(buyer3Id),
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
    String lens = 'ER-C',
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

  void trackSession(HttpHit h) {
    final sid = h.sessionId;
    if (sid != null && sid.startsWith('cs_')) createdSessionIds.add(sid);
  }

  void note(String id, String title, Object? ev, {String? lens, String? well}) {
    if (lens != null) lensesHit.add(lens);
    if (well != null) wellsTried.add(well);
    notes.add({
      'id': id,
      if (lens != null) 'lens': lens,
      if (well != null) 'well': well,
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

  String claimToken({int ageMs = 0, String tail = 'aabbccddeeff0011'}) {
    final ms = DateTime.now().millisecondsSinceEpoch - ageMs;
    return 'claiming:$ms:$tail';
  }

  Future<HttpHit> plantClaim(String orderId, String token) {
    return rest(
      'PATCH',
      'orders?id=eq.$orderId',
      service: true,
      body: {'stripe_checkout_session_id': token},
      prefer: 'return=representation',
    );
  }

  Future<HttpHit> mutexPeek({String? jwt, bool service = false}) {
    return rest(
      'GET',
      'batata_checkout_mutex?buyer_id=eq.$buyerId&select=buyer_id,claim_token,order_ids,expires_at',
      jwt: jwt,
      service: service,
    );
  }

  void probe({
    required String id,
    required String poco,
    required String payload,
    required Object? http,
    required Object? bd,
    required String verdict,
    String? lens,
    bool classeNova = false,
  }) {
    if (lens != null) lensesHit.add(lens);
    wellsTried.add(poco);
    probes.add({
      'probe_id': id,
      'poco': poco,
      'payload': payload,
      'http_rpc': http is HttpHit ? http.brief : http,
      'bd_stripe': bd,
      'verdict': verdict,
      'classe_nova': classeNova ? 'SIM' : 'NÃO',
      if (lens != null) 'lens': lens,
    });
    stdout.writeln(
      'PROBE $id [$poco] $verdict classe_nova=${classeNova ? 'SIM' : 'NÃO'} ${clip(payload, 120)}',
    );
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
      'wells': wellsTried.toList()..sort(),
      'findings': sanitize(findings),
      'blocked': sanitize(blocked),
      'skipped': sanitize(skipped),
      'probes': sanitize(probes),
      'notes': sanitize(notes),
      'actors': {
        'buyer': buyerId,
        'seller': sellerId,
        'buyer2': buyer2Id,
        'seller2': seller2Id,
        'buyer3': buyer3Id,
      },
      'created': {
        'orders': createdOrderIds,
        'products': createdProductIds,
        'bundles': createdBundleIds,
        'offers': createdOfferIds,
        'sessions': createdSessionIds,
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
