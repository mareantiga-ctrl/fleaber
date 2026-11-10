/// RED TEAM CEGO BA — chat/provas/UI pós-ANAS.
/// Staging fxdknzrqjenzqcvnwqqq only. Stripe TEST. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const stamp = '20260902T1608';
const prefix = 'RTBA-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

/// 1×1 PNG
final pngBytes = Uint8List.fromList(base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
));

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
  return cur.contains('redteam_blind_ba_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_ba_$stamp';

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
      status == 409 ||
      status == 422 ||
      status == 425 ||
      body.contains('42501') ||
      body.contains('23514') ||
      body.contains('PGRST') ||
      body.contains('chat_system_card') ||
      body.contains('chat_inbox') ||
      body.contains('chat_seguro') ||
      body.contains('not_allowed') ||
      body.contains('forbidden') ||
      body.contains('denied');
}

class Rtba {
  final String url;
  final String anon;
  final String svc;
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
  final skipped = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdChatIds = <String>[];
  final createdMsgIds = <String>[];
  final lensesHit = <String>{};
  int _seq = 0;

  Rtba._(this.url, this.anon, this.svc, this.env);

  factory Rtba.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtba._(
      url,
      envRequire(env, 'SUPABASE_ANON_KEY'),
      envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
      env,
    );
  }

  String nextRef([String p = 'BA']) {
    _seq++;
    return '$p${DateTime.now().millisecondsSinceEpoch % 100000}$_seq';
  }

  String jsonCard(Map<String, Object?> payload) =>
      'FLEABER_JSON_V1:${jsonEncode(payload)}';

  Future<HttpHit> req(
    String method,
    String path, {
    String? jwt,
    Object? body,
    Map<String, String>? extra,
    bool service = false,
    List<int>? rawBytes,
    String? contentType,
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
      h['Content-Type'] = contentType ?? 'application/json';
    } else {
      h['Content-Type'] = contentType ?? 'image/png';
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
      final bytes = await rs.fold<List<int>>(<int>[], (a, b) {
        a.addAll(b);
        return a;
      });
      String text;
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        final head = bytes.take(4).toList();
        final png = bytes.length >= 8 &&
            head.length >= 4 &&
            head[0] == 0x89 &&
            head[1] == 0x50 &&
            head[2] == 0x4E &&
            head[3] == 0x47;
        text = png
            ? '<<PNG ${bytes.length} bytes>>'
            : '<<binary ${bytes.length} bytes>>';
      }
      Object? parsed;
      try {
        parsed = text.isEmpty || text.startsWith('<<') ? null : jsonDecode(text);
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
    const pass = 'Rtba1608b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtba1608b2',
      name: '$prefix-B2',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2() async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rtba1608s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtba1608s2',
      name: '$prefix-S2',
      userType: 'vendedor',
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

  Future<String?> insertOrder({
    required String productId,
    String? buyer,
    String? seller,
    String status = 'reserva_pendente',
    double price = 12.0,
    int qty = 1,
    int paidCents = 0,
    String? pi,
    bool service = true,
    String? jwt,
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
      if (paidCents > 0) 'amount_paid_cents': paidCents,
      if (pi != null) 'stripe_payment_intent_id': pi,
    });
    final id = h.firstId;
    if (id != null) createdOrderIds.add(id);
    if (!h.ok) note('order.fail', 'insertOrder $status', h.brief);
    return id;
  }

  Future<String?> getOrCreateChat({
    required String a,
    required String b,
    String? productId,
    String? jwt,
  }) async {
    final q =
        'chats?or=(and(user_a.eq.$a,user_b.eq.$b),and(user_a.eq.$b,user_b.eq.$a))&select=id,user_a,user_b,last_message&limit=1';
    final existing = await rest('GET', q, jwt: jwt, service: jwt == null);
    final id = existing.firstId;
    if (id != null) {
      createdChatIds.add(id);
      return id;
    }
    final h = await rest('POST', 'chats', jwt: jwt, service: jwt == null, body: {
      'user_a': a,
      'user_b': b,
      if (productId != null) 'product_id': productId,
      'last_message': '$prefix hi',
    });
    final nid = h.firstId;
    if (nid != null) createdChatIds.add(nid);
    if (!h.ok) note('chat.fail', 'getOrCreateChat', h.brief);
    return nid;
  }

  Future<HttpHit> insertMsg({
    required String chatId,
    required String text,
    required String jwt,
    String? sender,
    String? receiver,
    String? createdAt,
  }) async {
    final h = await rest('POST', 'chat_messages', jwt: jwt, body: {
      'chat_id': chatId,
      'sender_id': sender ?? buyerId,
      'receiver_id': receiver ?? sellerId,
      'text': text,
      'is_read': false,
      if (createdAt != null) 'created_at': createdAt,
    });
    final id = h.firstId;
    if (id != null) createdMsgIds.add(id);
    return h;
  }

  Future<HttpHit> patchChat(
    String chatId,
    Object body, {
    String? jwt,
    bool service = false,
  }) {
    return rest('PATCH', 'chats?id=eq.$chatId', jwt: jwt, service: service, body: body);
  }

  Future<Map<String, dynamic>?> chatRow(String id) async {
    final h = await rest(
      'GET',
      'chats?id=eq.$id&select=id,user_a,user_b,last_message,last_message_time',
      service: true,
    );
    return h.map;
  }

  Future<Map<String, dynamic>?> msgRow(String id) async {
    final h = await rest(
      'GET',
      'chat_messages?id=eq.$id&select=id,chat_id,sender_id,text,created_at',
      service: true,
    );
    return h.map;
  }

  Future<HttpHit> uploadPrivate(String objectPath, String jwt) {
    final enc = objectPath.split('/').map(Uri.encodeComponent).join('/');
    return req(
      'POST',
      '/storage/v1/object/fleaber_private/$enc',
      jwt: jwt,
      rawBytes: pngBytes,
      extra: {'x-upsert': 'true'},
    );
  }

  Future<HttpHit> signPrivate(String objectPath, String jwt) {
    final enc = objectPath.split('/').map(Uri.encodeComponent).join('/');
    return req(
      'POST',
      '/storage/v1/object/sign/fleaber_private/$enc',
      jwt: jwt,
      body: {'expiresIn': 3600},
    );
  }

  String signedUrlFrom(HttpHit h, String objectPath) {
    final m = h.map;
    final signed = m?['signedURL']?.toString() ?? m?['signedUrl']?.toString();
    if (signed == null || signed.isEmpty) return '';
    if (signed.startsWith('http')) return signed;
    return '$url/storage/v1$signed';
  }

  Future<HttpHit> getObject(String objectPath, String jwt) {
    final enc = objectPath.split('/').map(Uri.encodeComponent).join('/');
    return req(
      'GET',
      '/storage/v1/object/fleaber_private/$enc',
      jwt: jwt,
    );
  }

  Future<void> cleanupSoft() async {
    for (final id in createdMsgIds) {
      await rest('DELETE', 'chat_messages?id=eq.$id', service: true,
          prefer: 'return=minimal');
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
    required HttpHit hit, required bool cracked,
    required String actor,
    required String pre,
    required String repro,
    String severity = 'P2',
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
      'auditor': 'REDTEAM_BLIND_BA_CHAT_POS_ANAS_v1',
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
        'chats': createdChatIds,
        'orders': createdOrderIds,
        'products': createdProductIds,
        'messages': createdMsgIds,
      },
    });
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
