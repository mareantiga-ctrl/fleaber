/// RED TEAM CEGO AO — chat / provas / UI pós-AHAM.
/// Staging fxdknzrqjenzqcvnwqqq only. Stripe TEST. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260902T1005';
const prefix = 'RTAO-$stamp';
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
  return cur.contains('redteam_blind_ao_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_ao_$stamp';

String fj(Map<String, dynamic> m) => 'FLEABER_JSON_V1:${jsonEncode(m)}';

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

  String? get err =>
      map?['message']?.toString() ??
      map?['hint']?.toString() ??
      map?['code']?.toString() ??
      snippet;
}

class Rtao {
  final String url;
  final String anon;
  final String svc;
  final Map<String, String> env;
  final String e2eSecret;
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
  final createdMessageIds = <String>[];
  final createdChatIds = <String>[];
  final lensesHit = <String>{};

  Rtao._(this.url, this.anon, this.svc, this.env, this.e2eSecret);

  factory Rtao.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtao._(
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
    List<int>? bytes,
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
    if (bytes == null) {
      h['Content-Type'] = contentType ?? 'application/json';
    } else {
      h['Content-Type'] = contentType ?? 'application/octet-stream';
    }
    final client = HttpClient();
    try {
      final rq = await client.openUrl(method, uri);
      rq.followRedirects = false;
      rq.maxRedirects = 0;
      h.forEach(rq.headers.set);
      if (bytes != null) {
        rq.add(bytes);
      } else if (body != null) {
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

  Future<void> ensureBuyer2() async {
    final email = '${prefix.toLowerCase()}-b2@fleaber.test';
    const pass = 'Rtao1005b2!xK';
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
        'handle': 'rtao1005b2',
        'hub_published': false,
        'is_live': false,
      }, prefer: 'return=minimal');
    }
  }

  Future<Map<String, dynamic>?> orderRow(String id) async {
    final h = await rest(
      'GET',
      'orders?id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,shipping_method,stripe_payment_intent_id,stripe_refund_id,reservation_expires_at,proof_url,is_reservation',
      service: true,
    );
    return h.map;
  }

  Future<num?> walletBal(String? uid) async {
    if (uid == null) return null;
    final h = await rest(
      'GET',
      'wallets?user_id=eq.$uid&select=balance,user_id',
      service: true,
    );
    return numOf(h.map?['balance']);
  }

  Future<Map<String, num?>> wallets() async => {
        'buyer': await walletBal(buyerId),
        'seller': await walletBal(sellerId),
        'buyer2': await walletBal(buyer2Id),
      };

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
    String lens = 'AO8',
    int initialQty = 2,
  }) async {
    final paid = await e2e('setup_paid_order', {'initial_qty': initialQty});
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

  Future<String?> ensureChat({String? a, String? b}) async {
    final ua = a ?? buyerId!;
    final ub = b ?? sellerId!;
    final existing = await rest(
      'GET',
      'chats?or=(and(user_a.eq.$ua,user_b.eq.$ub),and(user_a.eq.$ub,user_b.eq.$ua))&select=id,user_a,user_b,last_message&limit=1',
      service: true,
    );
    if (existing.firstId != null) {
      createdChatIds.add(existing.firstId!);
      return existing.firstId;
    }
    final h = await rest('POST', 'chats', service: true, body: {
      'user_a': ua,
      'user_b': ub,
    });
    if (h.firstId != null) createdChatIds.add(h.firstId!);
    if (!h.ok) note('chat.fail', 'ensureChat', h.brief);
    return h.firstId;
  }

  Future<HttpHit> msg(
    String chatId,
    String text, {
    required String jwt,
    String? sender,
    Object? createdAt,
  }) async {
    final body = <String, Object?>{
      'chat_id': chatId,
      if (sender != null) 'sender_id': sender,
      'text': text,
      if (createdAt != null) 'created_at': createdAt,
    };
    final h = await rest('POST', 'chat_messages', jwt: jwt, body: body);
    if (h.firstId != null) createdMessageIds.add(h.firstId!);
    return h;
  }

  Future<HttpHit> patchChat(
    String chatId,
    Map<String, Object?> body, {
    String? jwt,
    bool service = false,
  }) {
    return rest(
      'PATCH',
      'chats?id=eq.$chatId',
      jwt: jwt,
      service: service,
      body: body,
    );
  }

  Future<HttpHit> storagePut(
    String objectPath,
    List<int> bytes, {
    required String jwt,
    String contentType = 'image/png',
    bool upsert = false,
  }) {
    return req(
      'POST',
      '/storage/v1/object/fleaber_private/${Uri.encodeFull(objectPath)}',
      jwt: jwt,
      bytes: bytes,
      contentType: contentType,
      extra: {
        if (upsert) 'x-upsert': 'true',
      },
    );
  }

  Future<HttpHit> storageSign(String objectPath, {required String jwt}) {
    return req(
      'POST',
      '/storage/v1/object/sign/fleaber_private/${Uri.encodeFull(objectPath)}',
      jwt: jwt,
      body: {'expiresIn': 3600},
    );
  }

  Future<HttpHit> storageSignOther(
    String bucket,
    String objectPath, {
    required String jwt,
  }) {
    return req(
      'POST',
      '/storage/v1/object/sign/$bucket/${Uri.encodeFull(objectPath)}',
      jwt: jwt,
      body: {'expiresIn': 3600},
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

  /// Insert succeeds → finding (UI lie stored). Denied → blocked (defence holds).
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
        evidence: {
          'id': hit.firstId,
          'text': evidence?['text'] ?? '',
          ...?evidence,
        },
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
      'auditor': 'REDTEAM_BLIND_AO_CHAT_POS_AHAM_v1',
      'lenses': lensesHit.toList()..sort(),
      'findings': sanitize(findings),
      'blocked': sanitize(blocked),
      'skipped': sanitize(skipped),
      'notes': sanitize(notes),
      'actors': {
        'buyer': buyerId,
        'seller': sellerId,
        'buyer2': buyer2Id,
      },
      'created': {
        'orders': createdOrderIds,
        'products': createdProductIds,
        'chats': createdChatIds,
        'messages': createdMessageIds,
      },
    });
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
