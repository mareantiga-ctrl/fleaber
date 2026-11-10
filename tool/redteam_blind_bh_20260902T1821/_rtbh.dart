/// RED TEAM CEGO BH — live / staff / broadcast pós-ATBE.
/// Staging fxdknzrqjenzqcvnwqqq only. Stripe TEST. No production. No Fase 4. No fixes.
library;

import 'dart:convert';
import 'dart:io';

const stamp = '20260902T1821';
const prefix = 'RTBH-$stamp';
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
  return cur.contains('redteam_blind_bh_')
      ? Directory.current.parent.parent.path
      : cur;
}

String outDir() => '${repoRoot()}/tool/redteam_blind_bh_$stamp';

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
}

class Rtbh {
  final String url;
  final String anon;
  final String svc;
  final Map<String, String> env;
  String? buyerJwt;
  String? sellerJwt;
  String? buyer2Jwt;
  String? seller2Jwt;
  String? helperChatJwt;
  String? helperMarkJwt;
  String? helperViewJwt;
  String? helperResJwt;
  String? buyerId;
  String? sellerId;
  String? buyer2Id;
  String? seller2Id;
  String? helperChatId;
  String? helperMarkId;
  String? helperViewId;
  String? helperResId;
  final findings = <Map<String, dynamic>>[];
  final notes = <Map<String, dynamic>>[];
  final blocked = <Map<String, dynamic>>[];
  final skipped = <Map<String, dynamic>>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdLiveIds = <String>[];
  final createdItemIds = <String>[];
  final createdResIds = <String>[];
  final createdHelperRowIds = <String>[];
  final lensesHit = <String>{};

  Rtbh._(this.url, this.anon, this.svc, this.env);

  factory Rtbh.fromEnv(Map<String, String> env) {
    var url = envRequire(env, 'SUPABASE_URL').replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    if (!url.contains(projectMust)) {
      stderr.writeln('refusing non-staging url');
      exit(3);
    }
    return Rtbh._(
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
  }) {
    return req(
      'POST',
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

  Future<({String jwt, String id})?> adminUser(
    String email,
    String pass, {
    String userType = 'comprador',
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
        'handle': email.split('@').first.replaceAll(RegExp(r'[^a-z0-9]'), ''),
        'hub_published': false,
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
        '${prefix.toLowerCase()}-b2@fleaber.test', 'Rtbh1821b2!xK');
    if (u == null) return;
    buyer2Jwt = u.jwt;
    buyer2Id = u.id;
  }

  Future<void> ensureSeller2() async {
    final u = await adminUser(
      '${prefix.toLowerCase()}-s2@fleaber.test',
      'Rtbh1821s2!xK',
      userType: 'vendedor',
    );
    if (u == null) return;
    seller2Jwt = u.jwt;
    seller2Id = u.id;
  }

  Future<String?> _helper(
    String tag,
    Map<String, bool> perms,
  ) async {
    final u = await adminUser(
      '${prefix.toLowerCase()}-$tag@fleaber.test',
      'Rtbh1821$tag!xK',
    );
    if (u == null || sellerId == null) return null;
    final row = await rest('POST', 'seller_helpers', service: true, body: {
      'seller_id': sellerId,
      'helper_user_id': u.id,
      'display_name': '$prefix-$tag',
      'active': true,
      'invitation_status': 'accepted',
      'permissions': perms,
      'invited_by': sellerId,
    });
    final hid = row.firstId;
    if (hid != null) createdHelperRowIds.add(hid);
    if (!row.ok && row.status != 409) {
      note('helper.fail', tag, row.brief);
      return null;
    }
    switch (tag) {
      case 'hchat':
        helperChatJwt = u.jwt;
        helperChatId = u.id;
        break;
      case 'hmark':
        helperMarkJwt = u.jwt;
        helperMarkId = u.id;
        break;
      case 'hview':
        helperViewJwt = u.jwt;
        helperViewId = u.id;
        break;
      case 'hres':
        helperResJwt = u.jwt;
        helperResId = u.id;
        break;
    }
    return u.id;
  }

  Future<void> ensureHelpers() async {
    await _helper('hchat', {
      'can_manage_chat': true,
      'can_mark_items_sold': false,
      'can_manage_reservations': false,
      'can_view_live_dashboard': true,
      'can_change_current_item': false,
    });
    await _helper('hmark', {
      'can_manage_chat': false,
      'can_mark_items_sold': true,
      'can_manage_reservations': false,
      'can_view_live_dashboard': true,
      'can_change_current_item': false,
    });
    await _helper('hview', {
      'can_manage_chat': false,
      'can_mark_items_sold': false,
      'can_manage_reservations': false,
      'can_view_live_dashboard': true,
      'can_change_current_item': true,
    });
    await _helper('hres', {
      'can_manage_chat': false,
      'can_mark_items_sold': false,
      'can_manage_reservations': true,
      'can_view_live_dashboard': true,
      'can_change_current_item': false,
    });
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

  Future<Map<String, num?>> wallets() async => {
        'buyer': await walletBal(buyerId),
        'seller': await walletBal(sellerId),
        'buyer2': await walletBal(buyer2Id),
        'seller2': await walletBal(seller2Id),
      };

  Future<Map<String, dynamic>?> productRow(String id) async {
    final h = await rest(
      'GET',
      'products?id=eq.$id&select=id,quantity,is_sold,list_on_marketplace,price,seller_id,title',
      service: true,
    );
    return h.map;
  }

  Future<String?> insertProduct({
    required double price,
    int qty = 3,
    String? seller,
    String? title,
    bool live = false,
  }) async {
    final h = await rest('POST', 'products', service: true, body: {
      'seller_id': seller ?? sellerId,
      'title': title ?? '$prefix-${DateTime.now().microsecondsSinceEpoch}',
      'price': price,
      'quantity': qty,
      'ref_code': 'RTBH-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final id = h.firstId;
    if (id != null) createdProductIds.add(id);
    if (!h.ok) note('product.fail', 'insertProduct', h.brief);
    return id;
  }

  Future<String?> insertLive({
    String? seller,
    String status = 'live',
    bool active = true,
    String? title,
    String? muxLiveId,
    String? muxPlaybackId,
    String? streamKey,
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
      if (streamKey != null) 'mux_stream_key': streamKey,
      if (streamKey != null) 'stream_key': streamKey,
    });
    final id = h.firstId;
    if (id != null) createdLiveIds.add(id);
    if (!h.ok) note('live.fail', 'insertLive', h.brief);
    return id;
  }

  Future<String?> insertLiveItem({
    required String liveId,
    String kind = 'live_only',
    int qty = 2,
    String? productId,
    String? checkoutProductId,
    String status = 'available',
    bool active = true,
    double price = 12.5,
    String? title,
  }) async {
    final body = <String, Object?>{
      'live_id': liveId,
      'item_kind': kind,
      'title': title ?? '$prefix-item',
      'ref_code': 'BH${DateTime.now().microsecondsSinceEpoch % 1000000}',
      'price': price,
      'is_active': active,
      'status': status,
      if (kind == 'live_only') 'quantity': qty,
      if (kind == 'marketplace_product') 'product_id': productId,
      if (checkoutProductId != null) 'checkout_product_id': checkoutProductId,
    };
    final h = await rest('POST', 'live_items', service: true, body: body);
    final id = h.firstId;
    if (id != null) createdItemIds.add(id);
    if (!h.ok) note('item.fail', 'insertLiveItem', h.brief);
    return id;
  }

  Future<HttpHit> buyerReserve(
    String itemId, {
    String? jwt,
    int qty = 1,
    String source = 'fleaber_live',
    String? liveId,
  }) {
    return rest('POST', 'live_reservation_requests', jwt: jwt ?? buyerJwt, body: {
      'live_item_id': itemId,
      if (liveId != null) 'live_id': liveId,
      'requested_qty': qty,
      'source': source,
      'status': 'pending',
    });
  }

  Future<HttpHit> patchRes(
    String id,
    Map<String, Object?> body, {
    String? jwt,
    bool service = false,
  }) {
    return rest(
      'PATCH',
      'live_reservation_requests?id=eq.$id',
      jwt: jwt ?? sellerJwt,
      body: body,
      service: service,
    );
  }

  Future<HttpHit> endLive(String liveId, {String? jwt, bool service = false}) {
    return rest(
      'PATCH',
      'lives?id=eq.$liveId',
      jwt: jwt ?? sellerJwt,
      body: {'status': 'ended', 'is_active': false},
      service: service,
    );
  }

  Future<HttpHit> reopenLive(String liveId, {String? jwt}) {
    return rest(
      'PATCH',
      'lives?id=eq.$liveId',
      jwt: jwt ?? sellerJwt,
      body: {'status': 'live', 'is_active': true},
    );
  }

  Future<HttpHit> markSold(String itemId, {String? jwt}) {
    return rpc('batata_mark_live_item_sold', {'p_live_item_id': itemId},
        jwt: jwt ?? sellerJwt);
  }

  Future<Map<String, dynamic>?> liveRow(String id) async {
    final h = await rest(
      'GET',
      'lives?id=eq.$id&select=id,status,is_active,seller_id,vendedor_id,mux_live_id,mux_stream_key,stream_key,mux_playback_id,mux_vod_playback_id',
      service: true,
    );
    return h.map;
  }

  Future<Map<String, dynamic>?> itemRow(String id) async {
    final h = await rest(
      'GET',
      'live_items?id=eq.$id&select=id,live_id,status,quantity,item_kind,product_id,checkout_product_id,is_active,title',
      service: true,
    );
    return h.map;
  }

  Future<Map<String, dynamic>?> resRow(String id) async {
    final h = await rest(
      'GET',
      'live_reservation_requests?id=eq.$id&select=id,status,requested_qty,source,live_id,live_item_id,buyer_id,seller_id,notes',
      service: true,
    );
    return h.map;
  }

  Future<List<dynamic>> messages(String liveId) async {
    final h = await rest(
      'GET',
      'live_messages?live_id=eq.$liveId&select=id,kind,body,sender_label,user_id,created_at&order=created_at.desc&limit=20',
      service: true,
    );
    return h.list;
  }

  Future<HttpHit> sysMsg(String liveId, String body, {String? jwt, String? label}) {
    return rpc('batata_live_system_message', {
      'p_live_id': liveId,
      'p_body': body,
      if (label != null) 'p_sender_label': label,
    }, jwt: jwt ?? sellerJwt);
  }

  Future<HttpHit> purchaseBc({
    required String liveId,
    required String buyer,
    required String itemId,
    String? jwt,
  }) {
    return rpc('batata_live_purchase_broadcast', {
      'p_live_id': liveId,
      'p_buyer_id': buyer,
      'p_live_item_id': itemId,
    }, jwt: jwt ?? sellerJwt);
  }

  void trackRes(HttpHit h) {
    final id = h.firstId;
    if (id != null) createdResIds.add(id);
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
  }) async {
    bool defaultOpen(HttpHit h) {
      if (!h.ok) return false;
      if (h.json == false) return false;
      if (h.map != null && h.map!['ok'] == false) return false;
      // PostgREST PATCH/DELETE 200 [] = RLS filtrou 0 rows
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
      'auditor': 'REDTEAM_BLIND_BH_LIVE_POS_ATBE_v1',
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
        'helperChat': helperChatId,
        'helperMark': helperMarkId,
        'helperView': helperViewId,
        'helperRes': helperResId,
      },
      'created': {
        'orders': createdOrderIds,
        'products': createdProductIds,
        'lives': createdLiveIds,
        'items': createdItemIds,
        'reservations': createdResIds,
        'helpers': createdHelperRowIds,
      },
    });
  }
}

Future<void> dumpJson(String path, Object data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
