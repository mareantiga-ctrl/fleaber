/// HTTP client — staging fxdknzrqjenzqcvnwqqq only. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260831T1802';
const prefix = 'RTM-$stamp';
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

String repoRoot() {
  return Directory.current.path.contains('redteam_blind_m_')
      ? Directory.current.parent.parent.path
      : Directory.current.path;
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

class HttpHit {
  final int status;
  final String body;
  final Object? json;
  final String? location;
  final String? acao;
  final Map<String, List<String>> headers;
  HttpHit(
    this.status,
    this.body,
    this.json, [
    this.location,
    this.acao,
    this.headers = const {},
  ]);
  bool get ok => status >= 200 && status < 300;
  String get snippet => clip(body);
  String get brief => '$status loc=${clip(location, 80)} acao=$acao ${clip(body, 160)}';
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

  bool get hasCheckout {
    return body.contains('cs_test') ||
        (map?['url']?.toString().contains('checkout.stripe.com') ?? false) ||
        (map?['checkoutUrl']?.toString().contains('checkout.stripe.com') ??
            false);
  }
}

class Rtm {
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
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdLiveIds = <String>[];
  final createdLiveItemIds = <String>[];

  Rtm._(this.url, this.anon, this.svc, this.env);

  factory Rtm.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtm._(
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
      final raw = await rs.fold<List<int>>(<int>[], (p, e) => p..addAll(e));
      final text = utf8.decode(raw, allowMalformed: true);
      Object? parsed;
      try {
        parsed = text.isEmpty ? null : jsonDecode(text);
      } catch (_) {
        parsed = null;
      }
      final hdrs = <String, List<String>>{};
      rs.headers.forEach((k, v) => hdrs[k.toLowerCase()] = v);
      hdrs['x-rtm-bytes'] = ['${raw.length}'];
      return HttpHit(
        rs.statusCode,
        raw.length > 4000 && !text.trim().startsWith('{') && !text.trim().startsWith('[')
            ? 'binary:${raw.length} ct=${rs.headers.contentType}'
            : text,
        parsed,
        rs.headers.value('location'),
        rs.headers.value('access-control-allow-origin'),
        hdrs,
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
    String name, {
    Object? body,
    String? jwt,
    String method = 'POST',
    Map<String, String>? extra,
    bool service = false,
    String qs = '',
  }) {
    return req(
      method,
      '/functions/v1/$name$qs',
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
    required String userType,
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
    const pass = 'Rtm1802b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtm1802b2',
      name: '$prefix-B2',
      userType: 'comprador',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2() async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rtm1802s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtm1802s2',
      name: 'RtmSlug1802',
      userType: 'vendedor',
      hubPublished: false,
    );
    seller2Jwt = await signIn(email, pass);
  }

  Future<String?> insertProduct({
    required String title,
    String? seller,
    bool listed = true,
    bool sold = false,
    int qty = 2,
    double price = 8.5,
    bool live = false,
    List<String>? images,
  }) async {
    final h = await rest('POST', 'products', service: true, body: {
      'seller_id': seller ?? sellerId,
      'title': title,
      'price': price,
      'quantity': qty,
      'is_sold': sold,
      'list_on_marketplace': listed,
      'available_for_live': live,
      'description': prefix,
      'image_urls': images ?? <String>[],
    });
    final id = h.firstId;
    if (id != null) createdProductIds.add(id);
    return id;
  }

  Future<String?> insertLive({
    bool active = false,
    String? seller,
    String status = 'ended',
    String? muxPlayback,
    String? muxLiveId,
    String? muxVod,
    String? streamKey,
  }) async {
    final sid = seller ?? sellerId;
    final body = <String, dynamic>{
      'seller_id': sid,
      'vendedor_id': sid,
      'title': '$prefix live $status',
      'status': active ? 'live' : status,
      'is_active': active,
    };
    if (muxPlayback != null) {
      body['mux_playback_id'] = muxPlayback;
      body['playback_id'] = muxPlayback;
    }
    if (muxLiveId != null) body['mux_live_id'] = muxLiveId;
    if (muxVod != null) body['mux_vod_playback_id'] = muxVod;
    if (streamKey != null) {
      body['mux_stream_key'] = streamKey;
      body['stream_key'] = streamKey;
    }
    final h = await rest('POST', 'lives', service: true, body: body);
    final id = h.firstId;
    if (id != null) createdLiveIds.add(id);
    return id;
  }

  Future<String?> insertLiveItem({
    required String liveId,
    required String title,
    String status = 'available',
    bool active = true,
    int qty = 3,
    double price = 12,
  }) async {
    final h = await rest('POST', 'live_items', service: true, body: {
      'live_id': liveId,
      'title': title,
      'status': status,
      'is_active': active,
      'price': price,
      'quantity': qty,
      'ref_code': 'RTM${createdLiveItemIds.length + 1}',
    });
    final id = h.firstId;
    if (id != null) createdLiveItemIds.add(id);
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

  void note(String id, String title, Object? ev, {String? lens}) {
    notes.add({
      'id': id,
      if (lens != null) 'lens': lens,
      'title': title,
      'ev': ev is HttpHit ? ev.brief : ev,
    });
    stdout.writeln('NOTE $id ${lens ?? ''} $title ${clip(ev, 220)}');
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
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
