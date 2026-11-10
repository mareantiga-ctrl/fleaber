/// HTTP client — staging fxdknzrqjenzqcvnwqqq only. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260831T2019';
const prefix = 'RTN-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

const secretCols = [
  'mux_stream_key',
  'stream_key',
  'mux_live_id',
  'livekit_egress_id',
  'livekit_room_name',
  'mux_asset_id',
];

String clip(Object? v, [int n = 360]) {
  final s = v is String ? v : jsonEncode(v);
  if (s.length <= n) return s;
  return '${s.substring(0, n)}…';
}

String redactSecrets(Object? v) {
  if (v is Map) {
    final m = <String, Object?>{};
    v.forEach((k, val) {
      final key = k.toString();
      if (secretCols.contains(key) && val != null && val.toString().isNotEmpty) {
        final s = val.toString();
        m[key] = s.length <= 8 ? '***' : '${s.substring(0, 6)}…(len=${s.length})';
      } else {
        m[key] = val is Map || val is List ? jsonDecode(redactSecrets(val)) : val;
      }
    });
    return jsonEncode(m);
  }
  if (v is List) {
    return jsonEncode(v.map((e) => jsonDecode(redactSecrets(e))).toList());
  }
  return jsonEncode(v);
}

Map<String, Object?> secretHits(Object? json) {
  final hits = <String, Object?>{};
  void walk(Object? n, [String path = '']) {
    if (n is Map) {
      n.forEach((k, val) {
        final p = path.isEmpty ? k.toString() : '$path.$k';
        if (secretCols.contains(k.toString()) &&
            val != null &&
            val.toString().trim().isNotEmpty) {
          hits[p] = val.toString().length;
        }
        walk(val, p);
      });
    } else if (n is List) {
      for (var i = 0; i < n.length && i < 8; i++) {
        walk(n[i], '$path[$i]');
      }
    }
  }

  walk(json);
  return hits;
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
  return cur.contains('redteam_blind_n_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_n_$stamp';

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
  final Map<String, List<String>> headers;
  HttpHit(
    this.status,
    this.body,
    this.json, [
    this.location,
    this.headers = const {},
  ]);
  bool get ok => status >= 200 && status < 300;
  String get snippet => clip(body);
  String get brief => '$status ${clip(body, 180)}';
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

  Map<String, Object?> get secrets => secretHits(json);
}

class Rtn {
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
  final holds = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdLiveIds = <String>[];
  final createdLiveItemIds = <String>[];
  final createdRaffleIds = <String>[];
  final createdRequestIds = <String>[];

  Rtn._(this.url, this.anon, this.svc, this.env);

  factory Rtn.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtn._(
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
      return HttpHit(
        rs.statusCode,
        raw.length > 5000 &&
                !text.trim().startsWith('{') &&
                !text.trim().startsWith('[')
            ? 'binary:${raw.length}'
            : text,
        parsed,
        rs.headers.value('location'),
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
    const pass = 'Rtn2019b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtn2019b2',
      name: '$prefix-B2',
      userType: 'comprador',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2() async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rtn2019s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtn2019s2',
      name: '$prefix-S2',
      userType: 'vendedor',
      hubPublished: true,
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
    bool live = true,
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
      'image_urls': <String>[],
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
    String? egressId,
    String? roomName,
    int viewerCount = 0,
  }) async {
    final sid = seller ?? sellerId;
    final body = <String, dynamic>{
      'seller_id': sid,
      'vendedor_id': sid,
      'title': '$prefix live $status',
      'status': active ? 'live' : status,
      'is_active': active,
      'viewer_count': viewerCount,
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
    if (egressId != null) body['livekit_egress_id'] = egressId;
    if (roomName != null) body['livekit_room_name'] = roomName;
    final h = await rest('POST', 'lives', service: true, body: body);
    final id = h.firstId;
    if (id != null) createdLiveIds.add(id);
    if (!h.ok) {
      stdout.writeln('insertLive fail ${h.brief}');
    }
    return id;
  }

  Future<String?> insertLiveItem({
    required String liveId,
    required String title,
    String status = 'available',
    bool active = true,
    int qty = 3,
    double price = 12,
    String? productId,
  }) async {
    final body = <String, dynamic>{
      'live_id': liveId,
      'title': title,
      'status': status,
      'is_active': active,
      'price': price,
      'quantity': qty,
      'ref_code': 'RTN${createdLiveItemIds.length + 1}',
    };
    if (productId != null) body['product_id'] = productId;
    final h = await rest('POST', 'live_items', service: true, body: body);
    final id = h.firstId;
    if (id != null) createdLiveItemIds.add(id);
    return id;
  }

  Future<String?> insertRaffle({
    required String liveId,
    String? seller,
    String status = 'active',
    String? liveItemId,
  }) async {
    final body = <String, dynamic>{
      'live_id': liveId,
      'seller_id': seller ?? sellerId,
      'title': '$prefix rifa',
      'status': status,
      'winner_count': 1,
      'show_public_leaderboard': true,
    };
    if (liveItemId != null) body['live_item_id'] = liveItemId;
    final h = await rest('POST', 'live_raffles', service: true, body: body);
    final id = h.firstId;
    if (id != null) createdRaffleIds.add(id);
    if (!h.ok) stdout.writeln('insertRaffle fail ${h.brief}');
    return id;
  }

  Future<String?> insertReservation({
    required String liveId,
    required String liveItemId,
    String? buyer,
    int qty = 1,
    String status = 'pending',
  }) async {
    final h = await rest('POST', 'live_reservation_requests', service: true, body: {
      'live_id': liveId,
      'live_item_id': liveItemId,
      'buyer_id': buyer ?? buyerId,
      'requested_qty': qty,
      'status': status,
      'source': 'fleaber_live',
    });
    final id = h.firstId;
    if (id != null) createdRequestIds.add(id);
    if (!h.ok) stdout.writeln('insertReservation fail ${h.brief}');
    return id;
  }

  Future<void> endLives() async {
    for (final id in createdLiveIds) {
      await rest('PATCH', 'lives?id=eq.$id', service: true, body: {
        'is_active': false,
        'status': 'ended',
        'livekit_egress_id': null,
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
    stdout.writeln('NOTE $id ${lens ?? ''} $title ${clip(ev, 200)}');
  }

  void hold({
    required String id,
    required String lens,
    required String title,
    required String actor,
    required Object? obtained,
  }) {
    holds.add({
      'id': id,
      'lens': lens,
      'title': title,
      'actor': actor,
      'obtained': obtained is HttpHit ? obtained.brief : obtained,
    });
    stdout.writeln('HOLD $id [$lens] $title');
  }

  void finding({
    required String id,
    required String lens,
    required String severity,
    required String title,
    required String actor,
    required String pre,
    required String repro,
    required Object? expected,
    required Object? obtained,
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
      'obtained': obtained is HttpHit ? obtained.brief : obtained,
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
