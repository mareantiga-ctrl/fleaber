import 'dart:convert';
import 'dart:io';

const base = 'https://fxdknzrqjenzqcvnwqqq.supabase.co';
late String anon, svc, buyerJwt, sellerJwt, buyerId, sellerId, e2e;
final http = HttpClient();
final notes = <String>[];
final findings = <Map<String, dynamic>>[];

Future<Map<String, dynamic>> req(String method, String url, {String? tok, Object? body}) async {
  final r = await http.openUrl(method, Uri.parse(url));
  final t = tok ?? anon;
  r.headers.set('apikey', t == svc ? svc : anon);
  r.headers.set('Authorization', 'Bearer $t');
  r.headers.set('Content-Type', 'application/json');
  r.headers.set('Prefer', 'return=representation');
  if (body != null) r.add(utf8.encode(jsonEncode(body)));
  final res = await r.close();
  final raw = await res.transform(utf8.decoder).join();
  return {'s': res.statusCode, 'raw': raw, 'body': () { try { return jsonDecode(raw); } catch (_) { return raw; } }()};
}

void main() async {
  final map = <String, String>{};
  for (final l in File('tool/live_ops_staging.env').readAsLinesSync()) {
    final t = l.trim();
    if (t.isEmpty || t.startsWith('#') || !t.contains('=')) continue;
    final i = t.indexOf('=');
    map[t.substring(0, i)] = t.substring(i + 1);
  }
  anon = map['SUPABASE_ANON_KEY']!;
  svc = map['SUPABASE_SERVICE_ROLE_KEY']!;
  e2e = map['FLEABER_STAGING_CRASH_INJECT_SECRET']!;
  Future<Map> login(String e, String p) async {
    final r = await req('POST', '$base/auth/v1/token?grant_type=password',
        body: {'email': e, 'password': p});
    final b = r['body'] as Map;
    return {'jwt': b['access_token'], 'id': (b['user'] as Map)['id']};
  }
  final b = await login(map['LIVE_OPS_TEST_BUYER_EMAIL']!, map['LIVE_OPS_TEST_BUYER_PASSWORD']!);
  buyerJwt = b['jwt'] as String; buyerId = b['id'] as String;
  final s = await login(map['LIVE_OPS_TEST_SELLER_EMAIL']!, map['LIVE_OPS_TEST_SELLER_PASSWORD']!);
  sellerJwt = s['jwt'] as String; sellerId = s['id'] as String;

  // join ACTIVE raffle (not first drawn)
  final join = await req('POST', '$base/rest/v1/rpc/batata_join_live_raffle', tok: buyerJwt, body: {
    'p_raffle_id': '6264a19e-eebe-4f6e-a0dc-aa4947d75a2c',
  });
  notes.add('join active ${join['s']} ${join['raw']}');
  final close = await req('POST', '$base/rest/v1/rpc/batata_close_live_raffle', tok: buyerJwt, body: {
    'p_raffle_id': '6264a19e-eebe-4f6e-a0dc-aa4947d75a2c',
  });
  notes.add('close active as buyer ${close['s']} ${close['raw']}');

  Future<Map<String, dynamic>> e2ereq() async {
    final r = await http.openUrl('POST', Uri.parse('$base/functions/v1/sec-fase2-e2e-oversell'));
    r.headers.set('apikey', anon);
    r.headers.set('Authorization', 'Bearer $anon');
    r.headers.set('x-fleaber-e2e-secret', e2e);
    r.headers.set('Content-Type', 'application/json');
    r.add(utf8.encode(jsonEncode({
      'probe': 'setup_paid_order', 'buyer_id': buyerId, 'seller_id': sellerId, 'initial_qty': 1,
    })));
    final res = await r.close();
    final raw = await res.transform(utf8.decoder).join();
    return jsonDecode(raw) as Map<String, dynamic>;
  }
  final paid = await e2ereq();
  notes.add('paid ${paid['order_id']} ${paid['ok']}');
  final oid = paid['order_id']?.toString();
  final pid = paid['product_id']?.toString();
  if (oid != null) {
    await req('PATCH', '$base/rest/v1/orders?id=eq.$oid', tok: buyerJwt, body: {'status': 'concluido'});
    final ins = await req('POST', '$base/rest/v1/reviews', tok: buyerJwt, body: {
      'order_id': oid, 'buyer_id': buyerId, 'target_id': sellerId, 'stars': 5, 'comment': 'SATB9del', 'author_role': 'comprador',
    });
    notes.add('ins review ${ins['s']} ${ins['raw']}');
    String? rid;
    if (ins['body'] is List && (ins['body'] as List).isNotEmpty) {
      rid = ((ins['body'] as List).first as Map)['id']?.toString();
    }
    if (rid != null) {
      final del = await req('DELETE', '$base/rest/v1/reviews?id=eq.$rid', tok: sellerJwt);
      notes.add('seller delete ${del['s']} ${del['raw']}');
      final still = await req('GET', '$base/rest/v1/reviews?id=eq.$rid&select=id', tok: svc);
      notes.add('still ${still['raw']}');
      if (still['body'] is List && (still['body'] as List).isEmpty) {
        findings.add({'id': 'SATB-REV-DEL', 'sev': 'P1', 'impact': 'Seller apagou review do comprador.'});
        stderr.writeln('FINDING P1 SATB-REV-DEL');
      }
      // cleanup
      await req('DELETE', '$base/rest/v1/reviews?id=eq.$rid', tok: svc);
    }
    await req('DELETE', '$base/rest/v1/orders?id=eq.$oid', tok: svc);
  }
  if (pid != null) await req('DELETE', '$base/rest/v1/products?id=eq.$pid', tok: svc);
  http.close(force: true);

  File('tool/reports/SATB_20260827_PASS9.json').writeAsStringSync(JsonEncoder.withIndent('  ').convert({
    'findings': findings, 'notes': notes,
  }));
  stdout.writeln(jsonEncode({'findings': findings, 'notes': notes}));
}
