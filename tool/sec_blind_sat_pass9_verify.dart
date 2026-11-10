import 'dart:convert';
import 'dart:io';

void main() async {
  final env = File('tool/live_ops_staging.env').readAsLinesSync();
  final m = <String, String>{};
  for (final l in env) {
    final t = l.trim();
    if (t.isEmpty || t.startsWith('#') || !t.contains('=')) continue;
    final i = t.indexOf('=');
    m[t.substring(0, i)] = t.substring(i + 1);
  }
  const base = 'https://fxdknzrqjenzqcvnwqqq.supabase.co';
  final anon = m['SUPABASE_ANON_KEY']!;
  final svc = m['SUPABASE_SERVICE_ROLE_KEY']!;
  final http = HttpClient();

  Future<Map<String, dynamic>> req(String method, String url,
      {String? tok, Object? body, String prefer = 'return=representation'}) async {
    final r = await http.openUrl(method, Uri.parse(url));
    final t = tok ?? anon;
    r.headers.set('apikey', t == svc ? svc : anon);
    r.headers.set('Authorization', 'Bearer $t');
    r.headers.set('Content-Type', 'application/json');
    if (prefer.isNotEmpty) r.headers.set('Prefer', prefer);
    if (body != null) r.add(utf8.encode(jsonEncode(body)));
    final res = await r.close();
    final raw = await res.transform(utf8.decoder).join();
    return {'s': res.statusCode, 'raw': raw};
  }

  Future<Map> login(String e, String p) async {
    final r = await req('POST', '$base/auth/v1/token?grant_type=password',
        body: {'email': e, 'password': p}, prefer: '');
    final b = jsonDecode(r['raw'] as String) as Map;
    return {'jwt': b['access_token'], 'id': (b['user'] as Map)['id']};
  }

  final seller = await login(
      m['LIVE_OPS_TEST_SELLER_EMAIL']!, m['LIVE_OPS_TEST_SELLER_PASSWORD']!);
  final leftover = await req('GET',
      '$base/rest/v1/reviews?or=(comment.ilike.*SATB8*,comment.ilike.*SATB7*)&select=id,comment,stars,author_role,order_id',
      tok: svc);
  stdout.writeln('leftover ${leftover['raw']}');
  final parsed = jsonDecode(leftover['raw'] as String);
  if (parsed is List && parsed.isNotEmpty) {
    final id = parsed.first['id'];
    final before = await req('GET', '$base/rest/v1/reviews?id=eq.$id&select=id', tok: svc);
    stdout.writeln('before $before');
    final del = await req('DELETE', '$base/rest/v1/reviews?id=eq.$id',
        tok: seller['jwt'] as String);
    stdout.writeln('seller del ${del['s']} ${del['raw']}');
    final after = await req('GET', '$base/rest/v1/reviews?id=eq.$id&select=id', tok: svc);
    stdout.writeln('after ${after['raw']}');
  } else {
    stdout.writeln('no leftover reviews');
  }
  // leftover reservations
  final res = await req('GET',
      '$base/rest/v1/live_reservation_requests?requested_qty=eq.99&buyer_id=eq.${m['LIVE_OPS_TEST_BUYER_ID'] ?? 'bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96'}&select=id,status,requested_qty',
      tok: svc);
  stdout.writeln('res99 ${res['raw']}');
  http.close(force: true);
}
