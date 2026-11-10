/// HTTP client — staging fxdknzrqjenzqcvnwqqq only. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260901T1915';
const prefix = 'RTAF-$stamp';
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
  return cur.contains('redteam_blind_af_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_af_$stamp';

String fj(Map<String, dynamic> m) => 'FLEABER_JSON_V1:${jsonEncode(m)}';

class HttpHit {
  final int status;
  final String body;
  final Object? json;
  final String? location;
  HttpHit(this.status, this.body, this.json, [this.location]);
  bool get ok => status >= 200 && status < 300;
  bool get denied => status == 401 || status == 403 || status == 409;
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

  String? get pgCode {
    final m = json is Map ? Map<String, dynamic>.from(json as Map) : null;
    return m?['code']?.toString();
  }

  String? get pgMsg {
    final m = json is Map ? Map<String, dynamic>.from(json as Map) : null;
    return (m?['message'] ?? m?['hint'] ?? m?['details'])?.toString();
  }
}

class Rtaf {
  final String url;
  final String anon;
  final String svc;
  final Map<String, String> env;
  String? buyerJwt;
  String? sellerJwt;
  String? buyer2Jwt;
  String? buyerId;
  String? sellerId;
  String? buyer2Id;
  final findings = <Map<String, dynamic>>[];
  final notes = <Map<String, dynamic>>[];
  final blocked = <Map<String, dynamic>>[];
  final skipped = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdChatIds = <String>[];
  final createdMsgIds = <String>[];
  final createdOfferIds = <String>[];
  final lensesHit = <String>{};

  Rtaf._(this.url, this.anon, this.svc, this.env);

  factory Rtaf.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtaf._(
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
    List<int>? rawBytes,
    String? rawContentType,
  }) async {
    final key = service ? svc : anon;
    final uri = Uri.parse(path.startsWith('http')
        ? path
        : '$url${path.startsWith('/') ? path : '/$path'}');
    final h = <String, String>{
      'apikey': key,
      'Authorization': 'Bearer ${jwt ?? (service ? svc : anon)}',
      'Accept': 'application/json',
      ...?extra,
    };
    if (rawBytes == null) {
      h['Content-Type'] = extra?['Content-Type'] ?? 'application/json';
    } else {
      h['Content-Type'] = rawContentType ?? 'application/octet-stream';
    }
    final client = HttpClient();
    try {
      final rq = await client.openUrl(method, uri);
      rq.followRedirects = false;
      rq.maxRedirects = 0;
      h.forEach(rq.headers.set);
      if (rawBytes != null) {
        rq.add(rawBytes);
      } else if (body != null) {
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

  Future<HttpHit> edge(
    String name,
    Object? body, {
    String? jwt,
    String method = 'POST',
  }) {
    return req(method, '/functions/v1/$name', jwt: jwt, body: body);
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

  Future<void> ensureBuyer2() async {
    final email = '${prefix.toLowerCase()}-b2@fleaber.test';
    const pass = 'Rtaf1915b2!xK';
    await req('POST', '/auth/v1/admin/users', service: true, body: {
      'email': email,
      'password': pass,
      'email_confirm': true,
    });
    buyer2Jwt = await signIn(email, pass);
    final me = await req('GET', '/auth/v1/user', jwt: buyer2Jwt);
    buyer2Id = (me.json is Map) ? (me.json as Map)['id'] as String? : null;
    if (buyer2Id != null) {
      await rest('PATCH', 'profiles?id=eq.$buyer2Id', service: true, body: {
        'full_name': '$prefix-B2',
        'handle': 'rtaf1915b2',
        'hub_published': false,
        'is_live': false,
      }, prefer: 'return=minimal');
    }
  }

  Future<String?> createProduct({
    String? title,
    int qty = 3,
    double price = 12.0,
  }) async {
    final h = await rest('POST', 'products', service: true, body: {
      'seller_id': sellerId,
      'title': title ?? '$prefix-sku',
      'price': price,
      'quantity': qty,
      'is_sold': false,
      'list_on_marketplace': true,
      'available_for_live': false,
      'description': prefix,
      'image_urls': <String>[],
    });
    final id = h.firstId;
    if (id != null) createdProductIds.add(id);
    if (!h.ok) note('product.fail', 'createProduct', h.brief);
    return id;
  }

  Future<String?> insertOrder({
    required String productId,
    String status = 'reservado',
    double price = 12.0,
    int qty = 1,
    int? paidCents,
    String? pi,
    String? expiresAt,
    String? jwt,
    bool service = true,
  }) async {
    final body = <String, Object?>{
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': productId,
      'price_total': price,
      'quantity': qty,
      'status': status,
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
      if (paidCents != null) 'amount_paid_cents': paidCents,
      if (pi != null) 'stripe_payment_intent_id': pi,
      if (expiresAt != null) 'reservation_expires_at': expiresAt,
    };
    final h = await rest('POST', 'orders', jwt: jwt, service: service, body: body);
    final id = h.firstId;
    if (id != null) createdOrderIds.add(id);
    if (!h.ok) note('order.fail', 'insertOrder $status', h.brief);
    return id;
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,stripe_payment_intent_id,stripe_refund_id,proof_url,reservation_expires_at',
      service: true,
    );
    return h.map;
  }

  Future<String?> ensureChat({String? productId, String? lastMessage}) async {
    final exist = await rest(
      'GET',
      'chats?or=(and(user_a.eq.$buyerId,user_b.eq.$sellerId),and(user_a.eq.$sellerId,user_b.eq.$buyerId))&select=id,user_a,user_b,product_id,last_message&limit=20',
      jwt: buyerJwt,
    );
    if (productId != null) {
      for (final row in exist.list) {
        if (row is Map && row['product_id']?.toString() == productId) {
          return row['id']?.toString();
        }
      }
    }
    final h = await rest('POST', 'chats', jwt: buyerJwt, body: {
      'user_a': buyerId,
      'user_b': sellerId,
      if (productId != null) 'product_id': productId,
      if (lastMessage != null) 'last_message': lastMessage,
    });
    final id = h.firstId;
    if (id != null) createdChatIds.add(id);
    if (!h.ok) note('chat.fail', 'ensureChat', h.brief);
    return id;
  }

  Future<HttpHit> postMsg({
    required String chatId,
    required String text,
    required String jwt,
  }) async {
    final h = await rest('POST', 'chat_messages', jwt: jwt, body: {
      'chat_id': chatId,
      'sender_id': '00000000-0000-0000-0000-000000000000',
      'text': text,
    });
    final id = h.firstId;
    if (id != null) createdMsgIds.add(id);
    return h;
  }

  Future<Map<String, dynamic>?> msgRow(String id) async {
    final h = await rest(
      'GET',
      'chat_messages?id=eq.$id&select=id,chat_id,sender_id,text,created_at',
      service: true,
    );
    return h.map;
  }

  Future<String?> insertOffer({
    required String productId,
    double amount = 9.5,
    String status = 'pending',
  }) async {
    final h = await rest('POST', 'product_offers', service: true, body: {
      'product_id': productId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': amount,
      'status': status,
      'offered_by': 'buyer',
    });
    final id = h.firstId;
    if (id != null) createdOfferIds.add(id);
    if (!h.ok) note('offer.fail', 'insertOffer', h.brief);
    return id;
  }

  bool flutterWouldParseBundleRaw(String text) {
    final t = text.trim();
    if (t.startsWith('{')) {
      try {
        final decoded = jsonDecode(t);
        return decoded is Map && decoded['kind']?.toString() == 'bundle_proposal';
      } catch (_) {}
    }
    return false;
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
      },
      'created': {
        'orders': createdOrderIds,
        'products': createdProductIds,
        'chats': createdChatIds,
        'msgs': createdMsgIds,
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
