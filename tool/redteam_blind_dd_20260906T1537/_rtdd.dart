/// HTTP client — staging fxdknzrqjenzqcvnwqqq only. No production. No Fase 4. No fixes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const stamp = '20260906T1537';
const prefix = 'RTDD-$stamp';
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
  return cur.contains('redteam_blind_dd_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_dd_$stamp';

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
}

class Rtdd {
  final String url;
  final String anon;
  final String svc;
  final Map<String, String> env;
  String? buyerJwt;
  String? sellerJwt;
  String? buyer2Jwt;
  String? seller2Jwt;
  String? helperJwt;
  String? helperNoneJwt;
  String? helperSoldJwt;
  String? buyerId;
  String? sellerId;
  String? buyer2Id;
  String? seller2Id;
  String? helperId;
  String? helperNoneId;
  String? helperSoldId;
  final findings = <Map<String, dynamic>>[];
  final notes = <Map<String, dynamic>>[];
  final blocked = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdLiveIds = <String>[];
  final createdLiveItemIds = <String>[];
  final createdResIds = <String>[];
  final createdOrderIds = <String>[];
  final createdHelperIds = <String>[];
  final lensesHit = <String>{};

  final probes = <Map<String, dynamic>>[];

  Rtdd._(this.url, this.anon, this.svc, this.env);

  factory Rtdd.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtdd._(
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
      final text = await rs.transform(utf8.decoder).join();
      Object? parsed;
      try {
        parsed = text.isEmpty ? null : jsonDecode(text);
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
    const pass = 'Rtdd1537b2!xK';
    buyer2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'Rtdd1537b2',
      name: '$prefix-B2',
    );
    buyer2Jwt = await signIn(email, pass);
  }

  Future<void> ensureSeller2({bool hubPublished = false}) async {
    final email = '${prefix.toLowerCase()}-s2@fleaber.test';
    const pass = 'Rtdd1537s2!xK';
    seller2Id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'Rtdd1537s2',
      name: '$prefix-S2',
      userType: 'vendedor',
      hubPublished: hubPublished,
    );
    seller2Jwt = await signIn(email, pass);
  }

  Future<Map<String, String?>> ensureHelper({
    required String tag,
    required String pass,
    required Map<String, bool> perms,
  }) async {
    final email = '${prefix.toLowerCase()}-$tag@fleaber.test';
    final id = await _ensureUser(
      email: email,
      pass: pass,
      handle: 'Rtdd1537$tag',
      name: '$prefix-$tag',
    );
    final jwt = await signIn(email, pass);
    final existing = await rest(
      'GET',
      'seller_helpers?seller_id=eq.$sellerId&helper_user_id=eq.$id&select=id&limit=1',
      service: true,
    );
    if (existing.firstId != null) {
      createdHelperIds.add(existing.firstId!);
      await rest(
        'PATCH',
        'seller_helpers?id=eq.${existing.firstId}',
        service: true,
        body: {
          'active': true,
          'invitation_status': 'accepted',
          'permissions': perms,
        },
        prefer: 'return=minimal',
      );
    } else {
      final h = await rest('POST', 'seller_helpers', service: true, body: {
        'seller_id': sellerId,
        'helper_user_id': id,
        'display_name': '$prefix helper $tag',
        'active': true,
        'invitation_status': 'accepted',
        'permissions': perms,
      });
      if (h.firstId != null) createdHelperIds.add(h.firstId!);
      if (!h.ok) note('helper.fail.$tag', 'seller_helpers insert', h.brief);
    }
    return {'id': id, 'jwt': jwt};
  }

  Future<void> ensureHelperChatOnly() async {
    final r = await ensureHelper(
      tag: 'h1',
      pass: 'Rtdd1537h1!xK',
      perms: {
        'can_manage_chat': true,
        'can_manage_reservations': false,
        'can_mark_items_sold': false,
      },
    );
    helperId = r['id'];
    helperJwt = r['jwt'];
  }

  Future<void> ensureHelperNone() async {
    final r = await ensureHelper(
      tag: 'h0',
      pass: 'Rtdd1537h0!xK',
      perms: {
        'can_manage_chat': false,
        'can_manage_reservations': false,
        'can_mark_items_sold': false,
      },
    );
    helperNoneId = r['id'];
    helperNoneJwt = r['jwt'];
  }

  Future<void> ensureHelperSold() async {
    final r = await ensureHelper(
      tag: 'hs',
      pass: 'Rtdd1537hs!xK',
      perms: {
        'can_manage_chat': false,
        'can_manage_reservations': false,
        'can_mark_items_sold': true,
      },
    );
    helperSoldId = r['id'];
    helperSoldJwt = r['jwt'];
  }

  Future<String?> createProduct({
    String? seller,
    String? title,
    int qty = 1,
    double price = 9.0,
    bool live = false,
  }) async {
    final h = await rest('POST', 'products', service: true, body: {
      'seller_id': seller ?? sellerId,
      'title': title ?? '$prefix-sku',
      'price': price,
      'quantity': qty,
      'is_sold': false,
      'list_on_marketplace': !live,
      'available_for_live': true,
      'description': prefix,
      'image_urls': <String>[],
    });
    final id = h.firstId;
    if (id != null) createdProductIds.add(id);
    if (!h.ok) note('product.fail', 'createProduct', h.brief);
    return id;
  }

  Future<String?> createLive({
    String? seller,
    String title = '',
    String status = 'live',
    bool active = true,
    Map<String, Object?> extra = const {},
  }) async {
    final sid = seller ?? sellerId;
    final h = await rest('POST', 'lives', service: true, body: {
      'title': title.isEmpty ? '$prefix live' : title,
      'status': status,
      'seller_id': sid,
      'vendedor_id': sid,
      'is_active': active,
      ...extra,
    });
    final id = h.firstId;
    if (id != null) createdLiveIds.add(id);
    if (!h.ok) note('live.fail', 'createLive', h.brief);
    return id;
  }

  Future<String?> createLiveItem({
    required String liveId,
    String? title,
    String? ref,
    String kind = 'live_only',
    String? productId,
    String? checkoutProductId,
    String? logicalItemId,
    int? quantity,
    String status = 'available',
    bool active = true,
    double price = 9.0,
  }) async {
    final body = <String, Object?>{
      'live_id': liveId,
      'title': title ?? '$prefix item',
      'ref_code': ref ?? 'RTDD-${DateTime.now().millisecondsSinceEpoch}',
      'price': price,
      'is_active': active,
      'status': status,
      'item_kind': kind,
    };
    if (kind == 'marketplace_product') {
      body['product_id'] = productId;
      body['checkout_product_id'] = checkoutProductId ?? productId;
    } else {
      if (productId != null) body['product_id'] = productId;
      if (checkoutProductId != null) {
        body['checkout_product_id'] = checkoutProductId;
      }
      body['quantity'] = quantity ?? 1;
      if (logicalItemId != null) body['logical_item_id'] = logicalItemId;
    }
    final h = await rest('POST', 'live_items', service: true, body: body);
    final id = h.firstId;
    if (id != null) createdLiveItemIds.add(id);
    if (!h.ok) note('item.fail', 'createLiveItem $kind', h.brief);
    return id;
  }

  Future<String?> insertReservation({
    required String liveId,
    required String liveItemId,
    String? buyer,
    String? seller,
    String? jwt,
    bool service = false,
    String status = 'pending',
    int qty = 1,
    String source = 'fleaber_live',
  }) async {
    final h = await rest(
      'POST',
      'live_reservation_requests',
      jwt: jwt,
      service: service,
      body: {
        'live_id': liveId,
        'live_item_id': liveItemId,
        'seller_id': seller ?? sellerId,
        'buyer_id': buyer ?? buyerId,
        'requested_qty': qty,
        'source': source,
        'status': status,
      },
    );
    final id = h.firstId;
    if (id != null) createdResIds.add(id);
    if (!h.ok) {
      note('res.fail', 'insertReservation ${h.brief}', {
        'live': liveId,
        'item': liveItemId,
        'status': status,
        'source': source,
        'qty': qty,
      });
    }
    return id;
  }

  Future<Map<String, dynamic>?> stock(String liveItemId, {String? jwt}) async {
    final h = await rpc(
      'batata_live_item_stock',
      {'p_live_item_id': liveItemId},
      jwt: jwt ?? sellerJwt,
    );
    return h.map;
  }

  Future<void> endLive(String liveId) async {
    await rest(
      'PATCH',
      'lives?id=eq.$liveId',
      service: true,
      body: {'status': 'ended', 'is_active': false},
      prefer: 'return=minimal',
    );
  }

  Future<void> endAllCreatedLives() async {
    for (final id in createdLiveIds) {
      await endLive(id);
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

  void probe({
    required String id,
    required String lens,
    required String payload,
    required String http,
    required String verdict,
    Object? extra,
  }) {
    lensesHit.add(lens);
    probes.add({
      'id': id,
      'lens': lens,
      'payload': payload,
      'http': http,
      'verdict': verdict,
      if (extra != null) 'extra': extra,
    });
    stdout.writeln('PROBE $verdict $id [$lens] $payload → $http');
  }

  /// Subscribe to postgres_changes on public.lives and PATCH playback fields.
  /// Returns decoded realtime frames that mention playback / mux / livekit.
  Future<Map<String, dynamic>> probeRealtimeLivesPlayback({
    required String liveId,
    required String jwt,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final wsUrl =
        '${url.replaceFirst('https://', 'wss://')}/realtime/v1/websocket'
        '?apikey=${Uri.encodeQueryComponent(anon)}&vsn=1.0.0';
    WebSocket? ws;
    final frames = <String>[];
    final hits = <String>[];
    String? joinAck;
    try {
      ws = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 6));
      ws.add(jsonEncode({
        'topic': 'realtime:public:lives',
        'event': 'phx_join',
        'payload': {
          'config': {
            'broadcast': {'ack': false, 'self': true},
            'presence': {'key': ''},
            'postgres_changes': [
              {
                'event': '*',
                'schema': 'public',
                'table': 'lives',
                'filter': 'id=eq.$liveId',
              }
            ],
          },
          'access_token': jwt,
        },
        'ref': '1',
        'join_ref': '1',
      }));
      final done = Completer<void>();
      ws.listen(
        (raw) {
          final s = raw.toString();
          frames.add(clip(s, 1200));
          final low = s.toLowerCase();
          if (low.contains('phx_reply') && joinAck == null) {
            joinAck = clip(s, 400);
          }
          for (final needle in [
            'playback',
            'mux_',
            'livekit',
            'stream_key',
            'RTDDPB',
            'RTDDMUX',
            'RTDDROOM',
          ]) {
            if (low.contains(needle)) {
              hits.add(needle);
            }
          }
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (_) {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await rest(
        'PATCH',
        'lives?id=eq.$liveId',
        service: true,
        body: {
          'playback_id': 'RTDDPB1537plain0001',
          'mux_playback_id': 'RTDDMUX1537fake0001',
          'livekit_room_name': 'RTDDROOM1537livekit',
          'viewer_count': 7,
        },
        prefer: 'return=minimal',
      );
      await Future.any([
        done.future,
        Future<void>.delayed(timeout),
      ]);
    } catch (e) {
      return {
        'ok': false,
        'error': '$e',
        'frames': frames,
        'hits': hits,
        'joinAck': joinAck,
      };
    } finally {
      await ws?.close();
    }
    return {
      'ok': true,
      'n_frames': frames.length,
      'frames': frames,
      'hits': hits.toSet().toList(),
      'joinAck': joinAck,
    };
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
