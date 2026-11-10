/// RED TEAM CEGO CY — Hub / follow / favorite / tip / Mux pós-CPCU.
/// Staging only. NÃO corrigir. NÃO produção. NÃO Fase 4.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260906T1450';
const prefix = 'RTCY-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

String clip(Object? v, [int n = 360]) {
  String s;
  try {
    if (v is HttpHit) {
      s = v.brief;
    } else if (v is String) {
      s = v;
    } else {
      s = jsonEncode(v);
    }
  } catch (_) {
    s = v.toString();
  }
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
  return cur.contains('redteam_blind_cy_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_cy_$stamp';

class HttpHit {
  final int status;
  final String body;
  final Object? json;
  final String? location;
  final String? acao;
  final String? acah;
  final String? vary;
  final int? elapsedMs;
  HttpHit(
    this.status,
    this.body,
    this.json, [
    this.location,
    this.acao,
    this.acah,
    this.vary,
    this.elapsedMs,
  ]);
  bool get ok => status >= 200 && status < 300;
  String get snippet => clip(body);
  String get brief {
    final loc = location == null ? '' : ' loc=$location';
    final cors = acao == null ? '' : ' acao=$acao';
    final ms = elapsedMs == null ? '' : ' ${elapsedMs}ms';
    return '$status$loc$cors$ms ${clip(body, 220)}';
  }

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
}

class Rtcy {
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
  final probes = <Map<String, dynamic>>[];
  final createdLiveIds = <String>[];
  final createdItemIds = <String>[];
  final createdTipIds = <String>[];
  final createdProductIds = <String>[];
  final createdReviewIds = <String>[];
  final createdRaffleIds = <String>[];
  final createdFollowIds = <String>[];
  final createdMuxLiveIds = <String>[];
  final lensesHit = <String>{};

  Rtcy._(this.url, this.anon, this.svc, this.env);

  factory Rtcy.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtcy._(
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
    bool auth = true,
  }) async {
    final key = service ? svc : anon;
    final uri = Uri.parse(path.startsWith('http')
        ? path
        : '$url${path.startsWith('/') ? path : '/$path'}');
    final h = <String, String>{
      if (auth) 'apikey': key,
      if (auth) 'Authorization': 'Bearer ${jwt ?? (service ? svc : anon)}',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?extra,
    };
    final client = HttpClient();
    final sw = Stopwatch()..start();
    try {
      final rq = await client.openUrl(method, uri);
      rq.followRedirects = false;
      rq.maxRedirects = 0;
      h.forEach(rq.headers.set);
      if (body != null) {
        final bytes = utf8.encode(body is String ? body : jsonEncode(body));
        rq.add(bytes);
      }
      final rs = await rq.close().timeout(const Duration(seconds: 25));
      final text = await rs.transform(utf8.decoder).join();
      sw.stop();
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
        rs.headers.value('access-control-allow-origin'),
        rs.headers.value('access-control-allow-headers'),
        rs.headers.value('vary'),
        sw.elapsedMilliseconds,
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
    bool service = false,
    String? qs,
    Map<String, String>? extra,
  }) {
    final path = qs == null || qs.isEmpty
        ? '/functions/v1/$name'
        : '/functions/v1/$name?$qs';
    return req(
      method,
      path,
      jwt: jwt,
      body: body,
      extra: extra,
      service: service,
    );
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
      final rs = await rq.close().timeout(const Duration(seconds: 25));
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
    const pass = 'Rtcy1450b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtcy1450b2',
      name: '$prefix-B2',
      userType: 'comprador',
      hubPublished: false,
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2() async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rtcy1450s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'rtcy1450s2',
      name: '$prefix-S2',
      userType: 'vendedor',
      hubPublished: false,
    );
    seller2Jwt = await signIn(email, pass);
  }

  Future<Map<String, dynamic>?> profile(String id) async {
    final h = await rest(
      'GET',
      'profiles?id=eq.$id&select=id,handle,handle_suggested,hub_published,user_type,full_name,is_live,photo_url',
      service: true,
    );
    return h.map;
  }

  Future<String?> insertLive({
    String? seller,
    bool active = true,
    String status = 'live',
    String? muxPlayback,
    String? muxVod,
    String? muxLiveId,
    String? muxStreamKey,
    String? muxAssetId,
    String? playbackId,
    String? title,
    int viewers = 0,
  }) async {
    final sid = seller ?? sellerId;
    final body = <String, dynamic>{
      'seller_id': sid,
      'vendedor_id': sid,
      'title': title ?? '$prefix live',
      'status': status,
      'is_active': active,
      'viewer_count': viewers,
      if (muxPlayback != null) 'mux_playback_id': muxPlayback,
      if (muxVod != null) 'mux_vod_playback_id': muxVod,
      if (muxLiveId != null) 'mux_live_id': muxLiveId,
      if (muxStreamKey != null) 'mux_stream_key': muxStreamKey,
      if (muxAssetId != null) 'mux_asset_id': muxAssetId,
    };
    final pb = playbackId ?? muxPlayback;
    if (pb != null) body['playback_id'] = pb;
    var h = await rest('POST', 'lives', service: true, body: body);
    if (!h.ok && pb != null) {
      body.remove('playback_id');
      h = await rest('POST', 'lives', service: true, body: body);
    }
    final id = h.firstId;
    if (id != null) createdLiveIds.add(id);
    if (!h.ok) note('live.fail', 'insertLive', h.brief);
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

  Future<String?> insertLiveOnlyItem({
    required String liveId,
    int qty = 2,
    double price = 9.0,
    bool active = true,
    String? title,
  }) async {
    final h = await rest('POST', 'live_items', service: true, body: {
      'live_id': liveId,
      'ref_code': 'CY${DateTime.now().millisecondsSinceEpoch % 100000}',
      'title': title ?? '$prefix item',
      'price': price,
      'is_active': active,
      'item_kind': 'live_only',
      'quantity': qty,
      'status': 'available',
    });
    final id = h.firstId;
    if (id != null) createdItemIds.add(id);
    return id;
  }

  Future<String?> createProduct({
    String? seller,
    String? title,
    int qty = 3,
    double price = 12.0,
    bool listed = true,
    bool sold = false,
  }) async {
    final h = await rest('POST', 'products', service: true, body: {
      'seller_id': seller ?? sellerId,
      'title': title ?? '$prefix-sku',
      'price': price,
      'quantity': qty,
      'is_sold': sold,
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

  void probe({
    required String id,
    required String poco,
    required String payload,
    required Object http,
    Object? bd,
    required String result,
    String? lens,
    bool residual = false,
    bool countFinding = false,
  }) {
    if (lens != null) lensesHit.add(lens);
    probes.add({
      'probe_id': id,
      'poco': poco,
      'payload': payload,
      'http': http is HttpHit ? http.brief : clip(http, 280),
      'bd': bd == null ? '' : clip(bd, 220),
      'result': result,
      if (lens != null) 'lens': lens,
      'residual': residual,
      'count_finding': countFinding,
    });
    stdout.writeln(
      'PROBE $id [$poco] $result ${residual ? 'RESIDUAL ' : ''}${clip(http, 160)}',
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
    bool countExactClosed = false,
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
      'count_exact_closed': countExactClosed,
      'evidence': evidence ?? {},
    });
    stdout.writeln(
      'FINDING $severity $id [$lens]${countExactClosed ? ' EXACTO' : ''} $title',
    );
  }
  Future<void> setHub(String id, bool published) async {
    await rest('PATCH', 'profiles?id=eq.$id', service: true, body: {
      'hub_published': published,
    }, prefer: 'return=minimal');
  }

  Future<void> restoreSeller1Published() async {
    if (sellerId == null) return;
    await rest('PATCH', 'profiles?id=eq.$sellerId', service: true, body: {
      'hub_published': true,
    }, prefer: 'return=minimal');
  }

  Future<int> raffleTickets(String raffleId, String userId) async {
    final ent = await rest(
      'GET',
      'live_raffle_entries?raffle_id=eq.$raffleId&user_id=eq.$userId&select=id,ticket_balance',
      service: true,
    );
    final tb = ent.map?['ticket_balance'];
    if (tb is num) return tb.toInt();
    return 0;
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}

String? col(Map<String, dynamic>? m, String k) {
  if (m == null) return null;
  final v = m[k];
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

bool leakRow(HttpHit h) => h.ok && h.list.isNotEmpty;

bool denied(HttpHit h) {
  if (h.status == 401 || h.status == 403 || h.status == 409) return true;
  final t = h.body.toLowerCase();
  return t.contains('42501') ||
      t.contains('23514') ||
      t.contains('23503') ||
      t.contains('permission denied') ||
      t.contains('violat') ||
      t.contains('rls') ||
      t.contains('new row violates') ||
      t.contains('not allowed') ||
      t.contains('forbidden');
}
