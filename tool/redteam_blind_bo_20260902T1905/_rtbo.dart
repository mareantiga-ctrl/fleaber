/// RED TEAM CEGO BO — Hub / Edge / Mux / tip pós-BFBK.
/// Staging fxdknzrqjenzqcvnwqqq only. Stripe TEST. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260902T1905';
const prefix = 'RTBO-$stamp';
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
  return cur.contains('redteam_blind_bo_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_bo_$stamp';

class HttpHit {
  final int status;
  final String body;
  final Object? json;
  final String? location;
  final String? acao;
  final String? acah;
  final String? vary;
  HttpHit(
    this.status,
    this.body,
    this.json, [
    this.location,
    this.acao,
    this.acah,
    this.vary,
  ]);
  bool get ok => status >= 200 && status < 300;
  bool get denied => status >= 400;
  String get snippet => clip(body);
  String get brief => '$status ${clip(body, 240)} loc=${clip(location, 80)} acao=$acao';
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
      map?['error']?.toString() ??
      map?['code']?.toString() ??
      snippet;

  bool get rpcOk {
    final m = map;
    if (m == null) return ok && json == true;
    if (m['ok'] == true) return true;
    if (m['ok'] == false) return false;
    return ok;
  }

  String? get playbackId {
    final m = map;
    return (m?['mux_vod_playback_id'] ??
            m?['mux_playback_id'] ??
            m?['playback_id'])
        ?.toString();
  }
}

class Rtbo {
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
  final createdLiveIds = <String>[];
  final createdProductIds = <String>[];
  final createdItemIds = <String>[];
  final createdTipIds = <String>[];
  final lensesHit = <String>{};
  String? plantedPlaybackId;

  Rtbo._(this.url, this.anon, this.svc, this.env);

  factory Rtbo.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtbo._(
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
    List<int>? bodyBytes,
    Map<String, String>? extra,
    bool service = false,
    bool noAuth = false,
  }) async {
    final key = service ? svc : anon;
    final uri = Uri.parse(path.startsWith('http')
        ? path
        : '$url${path.startsWith('/') ? path : '/$path'}');
    final h = <String, String>{
      if (!noAuth) 'apikey': key,
      if (!noAuth) 'Authorization': 'Bearer ${jwt ?? (service ? svc : anon)}',
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
      if (bodyBytes != null) {
        rq.add(bodyBytes);
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
      return HttpHit(
        rs.statusCode,
        text,
        parsed,
        rs.headers.value('location'),
        rs.headers.value('access-control-allow-origin'),
        rs.headers.value('access-control-allow-headers'),
        rs.headers.value('vary'),
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
      jwt: service ? null : jwt,
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
    Map<String, String>? extra,
    String qs = '',
    String method = 'POST',
  }) {
    final q = qs.isEmpty ? '' : (qs.startsWith('?') ? qs : '?$qs');
    return req(
      method,
      '/functions/v1/$name$q',
      jwt: jwt,
      body: method == 'GET' ? null : body,
      extra: extra,
      service: service,
    );
  }

  Future<HttpHit> muxCdn(String playbackId) {
    return req(
      'GET',
      'https://stream.mux.com/$playbackId.m3u8',
      noAuth: true,
    );
  }

  Future<HttpHit> muxEmbed(String playbackId) {
    return req(
      'GET',
      'https://player.mux.com/$playbackId',
      noAuth: true,
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

  Future<({String jwt, String id})?> adminUser(
    String email,
    String pass, {
    String userType = 'comprador',
    String? handle,
    String? handleSuggested,
    bool hubPublished = false,
  }) async {
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
        if (handle != null) 'handle': handle,
        if (handleSuggested != null) 'handle_suggested': handleSuggested,
        'hub_published': hubPublished,
        'is_live': false,
        'user_type': userType,
      }, prefer: 'return=minimal');
      return (jwt: jwt, id: id);
    } catch (e) {
      note('adminUser.err', email, '$e');
      return null;
    }
  }

  Future<void> ensureBuyer2() async {
    final u = await adminUser(
        '${prefix.toLowerCase()}-b2@fleaber.test', 'Rtbo1905b2!xK');
    if (u == null) return;
    buyer2Jwt = u.jwt;
    buyer2Id = u.id;
  }

  Future<void> ensureSeller2Unpublished() async {
    final u = await adminUser(
      '${prefix.toLowerCase()}-s2@fleaber.test',
      'Rtbo1905s2!xK',
      userType: 'vendedor',
      handle: null,
      handleSuggested: 'rtbo1905s2sug',
      hubPublished: false,
    );
    if (u == null) return;
    seller2Jwt = u.jwt;
    seller2Id = u.id;
    await rest('PATCH', 'profiles?id=eq.$seller2Id', service: true, body: {
      'handle': null,
      'handle_suggested': 'rtbo1905s2sug',
      'hub_published': false,
      'full_name': 'Rtbo S2 Hidden',
    }, prefer: 'return=minimal');
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

  Future<String?> insertLive({
    String? seller,
    String status = 'live',
    bool active = true,
    String? title,
    String? muxLiveId,
    String? muxPlaybackId,
    String? muxVodPlaybackId,
    String? streamKey,
    bool publishedSeller = true,
  }) async {
    final sid = seller ?? sellerId;
    final h = await rest('POST', 'lives', service: true, body: {
      'seller_id': sid,
      'vendedor_id': sid,
      'title': title ?? '$prefix-live',
      'status': status,
      'is_active': active,
      if (muxLiveId != null) 'mux_live_id': muxLiveId,
      if (muxPlaybackId != null) 'mux_playback_id': muxPlaybackId,
      if (muxPlaybackId != null) 'playback_id': muxPlaybackId,
      if (muxVodPlaybackId != null) 'mux_vod_playback_id': muxVodPlaybackId,
      if (streamKey != null) 'mux_stream_key': streamKey,
      if (streamKey != null) 'stream_key': streamKey,
    });
    final id = h.firstId;
    if (id != null) createdLiveIds.add(id);
    if (!h.ok) note('live.fail', 'insertLive $status', h.brief);
    return id;
  }

  Future<String?> insertLiveItem({
    required String liveId,
    int qty = 2,
    double price = 12.5,
    String? title,
  }) async {
    final h = await rest('POST', 'live_items', service: true, body: {
      'live_id': liveId,
      'item_kind': 'live_only',
      'title': title ?? '$prefix-item',
      'ref_code': 'BO${DateTime.now().microsecondsSinceEpoch % 1000000}',
      'price': price,
      'is_active': true,
      'status': 'available',
      'quantity': qty,
    });
    final id = h.firstId;
    if (id != null) createdItemIds.add(id);
    if (!h.ok) note('item.fail', 'insertLiveItem', h.brief);
    return id;
  }

  Future<void> pickPlantedPlayback() async {
    final existing = await rest(
      'GET',
      'lives?mux_vod_playback_id=not.is.null&select=mux_vod_playback_id,mux_playback_id,status&limit=5',
      service: true,
    );
    for (final row in existing.list) {
      if (row is Map) {
        final vod = '${row['mux_vod_playback_id'] ?? ''}'.trim();
        if (vod.isNotEmpty) {
          plantedPlaybackId = vod;
          break;
        }
      }
    }
    plantedPlaybackId ??=
        'jl01M1gnQOchF2x3mhb34NZ01kvcJqjpY01cHiDXSXHpz00';
    note('plant.vod', 'playback plantado', plantedPlaybackId, lens: 'BO1');
  }

  Future<Map<String, dynamic>?> liveRow(String id) async {
    final h = await rest(
      'GET',
      'lives?id=eq.$id&select=id,status,is_active,seller_id,vendedor_id,mux_live_id,mux_stream_key,stream_key,mux_playback_id,mux_vod_playback_id,mux_asset_id',
      service: true,
    );
    return h.map;
  }

  Future<Map<String, dynamic>?> tipRow(String id) async {
    final h = await rest(
      'GET',
      'live_tips?id=eq.$id&select=id,status,buyer_id,seller_id,amount,stripe_session_id,live_id',
      service: true,
    );
    return h.map;
  }

  Future<void> endAllLives() async {
    for (final id in createdLiveIds) {
      await rest(
        'PATCH',
        'lives?id=eq.$id',
        service: true,
        body: {'status': 'ended', 'is_active': false},
        prefer: 'return=minimal',
      );
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
    bool count = true,
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
      'count': count,
      'evidence': evidence ?? {},
    });
    stdout.writeln(
        '${count ? "FINDING" : "HOLD-EXACT"} $severity $id [$lens] $title');
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
    bool Function(HttpHit hit)? openIf,
    bool count = true,
  }) async {
    bool defaultOpen(HttpHit h) {
      if (!h.ok) return false;
      if (h.json == false) return false;
      if (h.map != null && h.map!['ok'] == false) return false;
      if (h.json is List && h.list.isEmpty) return false;
      return true;
    }

    final opened = openIf != null ? openIf(hit) : defaultOpen(hit);
    if (opened) {
      hold(
        id: id,
        lens: lens,
        severity: severityIfOpen,
        title: title,
        actor: actor,
        pre: pre,
        repro: repro,
        expected: 'denied',
        obtained: hit.brief,
        count: count,
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
      'auditor': 'REDTEAM_BLIND_BO_HUB_EDGE_POS_BFBK_v1',
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
        'lives': createdLiveIds,
        'items': createdItemIds,
        'tips': createdTipIds,
        'products': createdProductIds,
      },
      'plantedPlaybackId': plantedPlaybackId,
    });
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
