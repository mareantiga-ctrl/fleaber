/// HTTP client — staging fxdknzrqjenzqcvnwqqq only. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260901T0657';
const prefix = 'RTS-$stamp';
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
  return cur.contains('redteam_blind_s_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_s_$stamp';

class HttpHit {
  final int status;
  final String body;
  final Object? json;
  final String? location;
  HttpHit(this.status, this.body, this.json, [this.location]);
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

  int get rowCount => list.length;
}

class Rts {
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
  String? buyer2Email;
  String? seller2Email;
  String? buyer2Pass;
  String? seller2Pass;
  final findings = <Map<String, dynamic>>[];
  final notes = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdUserIds = <String>[];

  Rts._(this.url, this.anon, this.svc, this.e2eSecret, this.env);

  factory Rts.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rts._(
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
    List<int>? raw,
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
      if (raw != null) {
        rq.add(raw);
      } else if (body != null) {
        final bytes = utf8.encode(body is String ? body : jsonEncode(body));
        rq.add(bytes);
      }
      final rs = await rq.close();
      final chunks = await rs.fold<List<int>>(<int>[], (a, b) {
        a.addAll(b);
        return a;
      });
      String text;
      try {
        text = utf8.decode(chunks);
      } catch (_) {
        text = '<<binary ${chunks.length} bytes>>';
      }
      Object? parsed;
      try {
        parsed = text.isEmpty || text.startsWith('<<binary')
            ? null
            : jsonDecode(text);
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
    Map<String, String>? extra,
  }) {
    return req(
      method,
      '/rest/v1/$tableQs',
      jwt: jwt,
      body: body,
      extra: {'Prefer': prefer, ...?extra},
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

  Future<HttpHit> storageList(
    String bucket, {
    String prefix = '',
    String? jwt,
    bool service = false,
    int limit = 30,
  }) {
    return req(
      'POST',
      '/storage/v1/object/list/$bucket',
      jwt: jwt,
      service: service,
      body: {
        'prefix': prefix,
        'limit': limit,
        'offset': 0,
      },
    );
  }

  Future<HttpHit> storageGet(
    String bucket,
    String path, {
    String? jwt,
    bool service = false,
    bool publicBucket = false,
  }) {
    final p = publicBucket
        ? '/storage/v1/object/public/$bucket/$path'
        : '/storage/v1/object/$bucket/$path';
    return req('GET', p, jwt: jwt, service: service);
  }

  Future<HttpHit> storageSign(
    String bucket,
    String path, {
    String? jwt,
    bool service = false,
  }) {
    return req(
      'POST',
      '/storage/v1/object/sign/$bucket/$path',
      jwt: jwt,
      service: service,
      body: {'expiresIn': 60},
    );
  }

  /// Minimal JPEG SOI…EOI (image/jpeg for fleaber_private / chat_media).
  static const jpeg1x1 = <int>[
    0xFF, 0xD8, 0xFF, 0xD9,
  ];

  Future<HttpHit> storageUpload(
    String bucket,
    String path, {
    String? jwt,
    bool service = false,
    List<int>? bytes,
    String contentType = 'image/jpeg',
  }) {
    return req(
      'POST',
      '/storage/v1/object/$bucket/$path',
      jwt: jwt,
      service: service,
      extra: {
        'x-upsert': 'true',
        'Content-Type': contentType,
      },
      raw: bytes ?? jpeg1x1,
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
    String? userType,
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
      createdUserIds.add(id);
      final patch = <String, dynamic>{
        'full_name': name,
        'handle': handle,
        'hub_published': false,
        'is_live': false,
      };
      if (userType != null) patch['user_type'] = userType;
      await rest('PATCH', 'profiles?id=eq.$id', service: true, body: patch,
          prefer: 'return=minimal');
    }
    return id;
  }

  Future<void> ensureBuyer2() async {
    buyer2Email = '${prefix.toLowerCase()}-b2@fleaber.test';
    buyer2Pass = 'Rts0657b2!xK';
    buyer2Id = await _ensureUser(
      email: buyer2Email!,
      pass: buyer2Pass!,
      handle: 'rts0657b2',
      name: '$prefix-B2',
    );
    buyer2Jwt = await signIn(buyer2Email!, buyer2Pass!);
  }

  Future<void> ensureSeller2() async {
    seller2Email = '${prefix.toLowerCase()}-s2@fleaber.test';
    seller2Pass = 'Rts0657s2!xK';
    seller2Id = await _ensureUser(
      email: seller2Email!,
      pass: seller2Pass!,
      handle: 'rts0657s2',
      name: '$prefix-S2',
      userType: 'vendedor',
    );
    seller2Jwt = await signIn(seller2Email!, seller2Pass!);
  }

  Future<Map<String, dynamic>?> profileRow(String id, {bool service = true}) async {
    final h = await rest(
      'GET',
      'profiles?id=eq.$id&select=id,full_name,user_type,handle,phone,legal_full_name,iban,mb_way,email,hub_published',
      service: service,
    );
    return h.map;
  }

  Future<String?> createProduct({
    String? seller,
    String title = '$prefix-sku',
    int qty = 3,
    bool listed = true,
    double price = 8.5,
  }) async {
    final h = await rest('POST', 'products', service: true, body: {
      'seller_id': seller ?? sellerId,
      'title': title,
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
    return id;
  }

  Future<HttpHit> e2e(String probe, Map<String, Object?> body) {
    return req(
      'POST',
      '/functions/v1/sec-fase2-e2e-oversell',
      service: true,
      body: {
        'probe': probe,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        ...body,
      },
      extra: e2eSecret.isEmpty ? null : {'x-fleaber-e2e-secret': e2eSecret},
    );
  }

  String? parseE2eOrderId(HttpHit paid) {
    final pm = paid.map ?? {};
    return (pm['order_id'] ??
            (pm['order'] is Map ? (pm['order'] as Map)['id'] : null))
        ?.toString();
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

  void note(String id, String title, Object? ev, {String? lens}) {
    notes.add({
      'id': id,
      if (lens != null) 'lens': lens,
      'title': title,
      'ev': ev is HttpHit ? ev.brief : ev,
    });
    stdout.writeln('NOTE $id ${lens ?? ''} $title ${clip(ev, 240)}');
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

  bool leakedPii(HttpHit h, String victimId) {
    if (!h.ok) return false;
    final s = h.body.toLowerCase();
    if (s.contains(victimId.toLowerCase()) &&
        (s.contains('phone') ||
            s.contains('iban') ||
            s.contains('mb_way') ||
            s.contains('nif') ||
            s.contains('legal_full_name') ||
            s.contains('@'))) {
      final m = h.map ?? {};
      final phone = m['phone']?.toString() ?? '';
      final iban = m['iban']?.toString() ?? '';
      final email = m['email']?.toString() ?? '';
      final legal = m['legal_full_name']?.toString() ?? '';
      return phone.length > 4 ||
          iban.length > 6 ||
          email.contains('@') ||
          legal.length > 2;
    }
    return false;
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
