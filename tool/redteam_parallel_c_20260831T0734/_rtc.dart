/// Parallel C Deep Cash — HTTP client. Staging fxdknzrqjenzqcvnwqqq only.
/// service_role: fixture / observe / cleanup. Actor = JWT / anon.
library;

import 'dart:convert';
import 'dart:io';

const projectMust = 'fxdknzrqjenzqcvnwqqq';
const stamp = '20260831T0734';
const prefix = 'RTC-$stamp';

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
  final root = Directory.current.path;
  final merged = <String, String>{};
  merged.addAll(Platform.environment);
  merged.addAll(loadEnvFile('$root/tool/live_ops_staging.env'));
  merged.addAll(loadEnvFile('$root/.maestro/.env'));
  merged.addAll(loadEnvFile('$root/supabase/.env'));
  return merged;
}

String clip(String s, [int n = 280]) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length <= n) return t;
  return '${t.substring(0, n)}…';
}

num? asNum(Object? v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse('$v');
}

class Hit {
  final String id;
  final String surface;
  final String attack;
  final String identity;
  final int http;
  final String result;
  final String impact;
  final String sev;
  final String evidence;
  Hit({
    required this.id,
    required this.surface,
    required this.attack,
    required this.identity,
    required this.http,
    required this.result,
    required this.impact,
    required this.sev,
    required this.evidence,
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'surface': surface,
        'attack': attack,
        'identity': identity,
        'http': http,
        'result': result,
        'impact': impact,
        'sev': sev,
        'evidence': evidence,
      };
}

class Finding {
  final String id;
  final String sev;
  final String title;
  final String actor;
  final String pre;
  final String repro;
  final String impact;
  final String estado;
  Finding({
    required this.id,
    required this.sev,
    required this.title,
    required this.actor,
    required this.pre,
    required this.repro,
    required this.impact,
    this.estado = 'ABERTO',
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'sev': sev,
        'title': title,
        'actor': actor,
        'pre': pre,
        'repro': repro,
        'impact': impact,
        'estado': estado,
      };
}

class Rtc {
  final String url;
  final String anon;
  final String svc;
  final String e2eSecret;
  final String buyerEmail;
  final String buyerPass;
  final String sellerEmail;
  final String sellerPass;
  final String labBuyerId;
  final String labSellerId;
  final HttpClient http = HttpClient();

  String? buyerJwt;
  String? sellerJwt;
  String? buyerId;
  String? sellerId;
  String? freshJwt;
  String? freshId;
  String? freshEmail;

  final hits = <Hit>[];
  final findings = <Finding>[];
  final gaps = <String>[];
  final notes = <String>[];
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  final createdUserIds = <String>[];

  Rtc(Map<String, String> env)
      : url = (env['SUPABASE_URL'] ?? 'https://fxdknzrqjenzqcvnwqqq.supabase.co')
            .replaceAll('/rest/v1/', '')
            .replaceAll(RegExp(r'/$'), ''),
        anon = env['SUPABASE_ANON_KEY'] ?? '',
        svc = env['SUPABASE_SERVICE_ROLE_KEY'] ?? '',
        e2eSecret = (env['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim(),
        buyerEmail = env['LIVE_OPS_TEST_BUYER_EMAIL'] ??
            env['MAESTRO_BUYER_EMAIL'] ??
            '',
        buyerPass = env['LIVE_OPS_TEST_BUYER_PASSWORD'] ??
            env['MAESTRO_BUYER_PASSWORD'] ??
            '',
        sellerEmail = env['LIVE_OPS_TEST_SELLER_EMAIL'] ??
            env['MAESTRO_SELLER_EMAIL'] ??
            '',
        sellerPass = env['LIVE_OPS_TEST_SELLER_PASSWORD'] ??
            env['MAESTRO_SELLER_PASSWORD'] ??
            '',
        labBuyerId = env['LIVE_OPS_TEST_BUYER_ID'] ?? '',
        labSellerId = env['LIVE_OPS_TEST_SELLER_ID'] ?? '' {
    if (!url.contains(projectMust)) {
      throw StateError('Recusado: URL não é staging $projectMust');
    }
    if (anon.isEmpty || svc.isEmpty) {
      throw StateError('Faltam anon/service_role');
    }
  }

  void rec({
    required String id,
    required String surface,
    required String attack,
    required String identity,
    required int httpCode,
    required String result,
    required String impact,
    String sev = '—',
    required String evidence,
  }) {
    hits.add(Hit(
      id: id,
      surface: surface,
      attack: attack,
      identity: identity,
      http: httpCode,
      result: result,
      impact: impact,
      sev: sev,
      evidence: evidence,
    ));
  }

  void finding(Finding f) => findings.add(f);

  Future<Map<String, dynamic>> req({
    required String method,
    required Uri uri,
    String? bearer,
    String? apikey,
    Object? body,
    Map<String, String>? extraHeaders,
    bool followRedirects = false,
  }) async {
    final r = await http.openUrl(method, uri);
    r.followRedirects = followRedirects;
    r.headers.set('apikey', apikey ?? anon);
    if (bearer != null && bearer.isNotEmpty) {
      r.headers.set('Authorization', 'Bearer $bearer');
    }
    r.headers.set('Accept', 'application/json');
    extraHeaders?.forEach(r.headers.set);
    if (body != null) {
      r.headers.contentType = ContentType.json;
      r.add(utf8.encode(body is String ? body : jsonEncode(body)));
    }
    final res = await r.close();
    final raw = await res.transform(utf8.decoder).join();
    Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (_) {
      parsed = raw;
    }
    return {
      'http': res.statusCode,
      'raw': raw,
      'json': parsed,
      'location': res.headers.value('location'),
    };
  }

  Future<Map<String, dynamic>> rest(
    String method,
    String path, {
    String? token,
    String? prefer,
    Object? body,
    String? query,
    bool service = false,
  }) {
    final q = (query == null || query.isEmpty) ? '' : '?$query';
    final headers = <String, String>{};
    if (prefer != null) headers['Prefer'] = prefer;
    return req(
      method: method,
      uri: Uri.parse('$url/rest/v1/$path$q'),
      bearer: service ? svc : (token ?? anon),
      apikey: service ? svc : anon,
      body: body,
      extraHeaders: headers.isEmpty ? null : headers,
    );
  }

  Future<Map<String, dynamic>> rpc(
    String name,
    Object? args, {
    String? token,
    bool service = false,
  }) {
    return req(
      method: 'POST',
      uri: Uri.parse('$url/rest/v1/rpc/$name'),
      bearer: service ? svc : (token ?? anon),
      apikey: service ? svc : anon,
      body: args ?? {},
    );
  }

  Future<Map<String, dynamic>> edge(
    String name, {
    Object? body,
    String? token,
    String query = '',
    String method = 'POST',
    Map<String, String>? extraHeaders,
    bool service = false,
  }) {
    final q = query.isEmpty ? '' : (query.startsWith('?') ? query : '?$query');
    return req(
      method: method,
      uri: Uri.parse('$url/functions/v1/$name$q'),
      bearer: service ? svc : (token ?? ''),
      apikey: service ? svc : anon,
      body: body,
      extraHeaders: extraHeaders,
    );
  }

  Future<Map<String, dynamic>> e2e(Object body) {
    return req(
      method: 'POST',
      uri: Uri.parse('$url/functions/v1/sec-fase2-e2e-oversell'),
      bearer: svc,
      apikey: svc,
      body: body,
      extraHeaders: {'x-fleaber-e2e-secret': e2eSecret},
    );
  }

  Future<String> signIn(String email, String password) async {
    final r = await req(
      method: 'POST',
      uri: Uri.parse('$url/auth/v1/token?grant_type=password'),
      bearer: anon,
      body: {'email': email, 'password': password},
    );
    final j = r['json'];
    if (r['http'] != 200 || j is! Map || j['access_token'] == null) {
      throw StateError(
          'login falhou $email http=${r['http']} ${clip('${r['raw']}')}');
    }
    return j['access_token'] as String;
  }

  Future<Map<String, String>> signUp(String email, String password) async {
    final r = await req(
      method: 'POST',
      uri: Uri.parse('$url/auth/v1/signup'),
      bearer: anon,
      body: {'email': email, 'password': password},
    );
    final j = r['json'];
    if (j is! Map) {
      throw StateError(
          'signup $email http=${r['http']} ${clip('${r['raw']}')}');
    }
    final token = (j['access_token'] ?? '').toString();
    final uid = ((j['user'] as Map?)?['id'] ?? j['id'] ?? '').toString();
    if (token.isEmpty || uid.isEmpty) {
      throw StateError(
          'signup sem token $email http=${r['http']} ${clip('${r['raw']}')}');
    }
    createdUserIds.add(uid);
    return {'jwt': token, 'id': uid, 'email': email};
  }

  Future<void> boot() async {
    buyerJwt = await signIn(buyerEmail, buyerPass);
    sellerJwt = await signIn(sellerEmail, sellerPass);
    final bu = await req(
      method: 'GET',
      uri: Uri.parse('$url/auth/v1/user'),
      bearer: buyerJwt,
    );
    final su = await req(
      method: 'GET',
      uri: Uri.parse('$url/auth/v1/user'),
      bearer: sellerJwt,
    );
    buyerId = ((bu['json'] as Map?)?['id'] ?? labBuyerId).toString();
    sellerId = ((su['json'] as Map?)?['id'] ?? labSellerId).toString();
    notes.add('buyer=$buyerId seller=$sellerId');
    try {
      freshEmail =
          'rtc.$stamp.${DateTime.now().millisecondsSinceEpoch}@fleaber.test';
      final f = await signUp(freshEmail!, 'RtcTest1234!');
      freshJwt = f['jwt'];
      freshId = f['id'];
      notes.add('fresh=$freshId $freshEmail');
    } catch (e) {
      gaps.add('signup fresh falhou: $e');
    }
  }

  String? _idFrom(Map<String, dynamic> r) {
    final j = r['json'];
    if (j is List && j.isNotEmpty && j.first is Map) {
      return j.first['id']?.toString();
    }
    if (j is Map) return j['id']?.toString();
    return null;
  }

  Future<String?> createProduct({
    required String token,
    required String seller,
    required String title,
    required num price,
    required int qty,
    bool listed = true,
    bool sold = false,
  }) async {
    final r = await rest(
      'POST',
      'products',
      token: token,
      prefer: 'return=representation',
      body: {
        'seller_id': seller,
        'title': title,
        'price': price,
        'quantity': qty,
        'ref_code': '$prefix-${DateTime.now().millisecondsSinceEpoch}',
        'list_on_marketplace': listed,
        'available_for_live': false,
        'is_sold': sold,
        'image_urls': <String>[],
      },
    );
    final id = _idFrom(r);
    if (id != null && id.isNotEmpty) {
      createdProductIds.add(id);
      return id;
    }
    notes.add('createProduct fail http=${r['http']} ${clip('${r['raw']}')}');
    return null;
  }

  Future<Map<String, dynamic>> createOrder({
    required String token,
    required String buyer,
    required String seller,
    required String productId,
    int qty = 1,
    String status = 'reserva_pendente',
    String payment = 'Pagamento na app',
    String shipping = 'entrega em mão',
    Object? extra,
  }) async {
    final body = <String, dynamic>{
      'buyer_id': buyer,
      'seller_id': seller,
      'product_id': productId,
      'quantity': qty,
      'status': status,
      'payment_method': payment,
      'shipping_method': shipping,
    };
    if (extra is Map) body.addAll(Map<String, dynamic>.from(extra));
    final r = await rest(
      'POST',
      'orders',
      token: token,
      prefer: 'return=representation',
      body: body,
    );
    final id = _idFrom(r);
    if (id != null && id.isNotEmpty) createdOrderIds.add(id);
    return r;
  }

  Future<Map<String, dynamic>> observeOrder(String id) async {
    final r = await rest(
      'GET',
      'orders',
      service: true,
      query:
          'id=eq.$id&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,contract_unit_cents,contract_qty,payment_method,shipping_method,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,stock_units_applied,product_offer_id,bundle_id,live_id,live_item_id',
    );
    final j = r['json'];
    if (j is List && j.isNotEmpty && j.first is Map) {
      return Map<String, dynamic>.from(j.first as Map);
    }
    return {'http': r['http'], 'raw': clip('${r['raw']}', 200)};
  }

  Future<Map<String, dynamic>> observeProduct(String id) async {
    final r = await rest(
      'GET',
      'products',
      service: true,
      query:
          'id=eq.$id&select=id,price,quantity,is_sold,list_on_marketplace,seller_id,title,ref_code',
    );
    final j = r['json'];
    if (j is List && j.isNotEmpty && j.first is Map) {
      return Map<String, dynamic>.from(j.first as Map);
    }
    return {'http': r['http'], 'raw': clip('${r['raw']}', 200)};
  }

  Future<num?> walletBalance(String uid) async {
    final r = await rest(
      'GET',
      'wallets',
      service: true,
      query: 'id=eq.$uid&select=id,balance',
    );
    final j = r['json'];
    if (j is List && j.isNotEmpty && j.first is Map) {
      return asNum(j.first['balance']);
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> walletTx({String? orderId, String? walletId}) async {
    var q =
        'select=id,wallet_id,amount,type,description,order_id,created_at&order=created_at.desc&limit=30';
    if (orderId != null) q = 'order_id=eq.$orderId&$q';
    if (walletId != null) q = 'wallet_id=eq.$walletId&$q';
    final r = await rest('GET', 'wallet_transactions', service: true, query: q);
    final j = r['json'];
    if (j is List) {
      return j.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> checkout({
    required String token,
    required String buyer,
    String? orderId,
    Object? extra,
  }) {
    final body = <String, dynamic>{
      'buyer_id': buyer,
      if (orderId != null) 'order_id': orderId,
      'currency': 'eur',
      'shipping_method': 'hand',
    };
    if (extra is Map) body.addAll(Map<String, dynamic>.from(extra));
    return edge('create-payment-intent', token: token, body: body);
  }

  String? sessionId(Map<String, dynamic> ck) {
    final j = ck['json'];
    if (j is Map) {
      return (j['sessionId'] ??
              j['session_id'] ??
              j['checkout_session_id'] ??
              j['id'])
          ?.toString();
    }
    return null;
  }

  int? serverAmount(Map<String, dynamic> ck) {
    final j = ck['json'];
    if (j is Map) {
      return asNum(j['server_amount_cents'] ??
              j['amount'] ??
              j['amount_cents'] ??
              (j['quote'] is Map ? (j['quote'] as Map)['amountCents'] : null))
          ?.round();
    }
    return null;
  }

  Future<void> dump(String path) async {
    final out = {
      'auditor': 'PARALLEL_C_DEEP_CASH',
      'stamp': stamp,
      'project': projectMust,
      'production_touched': false,
      'fase4': false,
      'corrections_applied': false,
      'notes': notes,
      'gaps': gaps,
      'hits': hits.map((e) => e.toJson()).toList(),
      'findings': findings.map((e) => e.toJson()).toList(),
      'created': {
        'products': createdProductIds,
        'orders': createdOrderIds,
        'users': createdUserIds,
      },
    };
    File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  }
}
