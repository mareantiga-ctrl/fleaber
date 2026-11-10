/// Pass 3 — oráculo bancário: relação mínima.
import 'dart:convert';
import 'dart:io';

const base = 'https://fxdknzrqjenzqcvnwqqq.supabase.co';
const sellerId = '980f4fa1-0004-42f9-abca-69f1a9c29588';
const prod = '7c468319-a043-43bf-b7c9-f6aaea7c286e'; // listed marketplace
final http = HttpClient();

Future<Map<String, dynamic>> call(String jwt, String anon, String method, String path, [Object? body]) async {
  final fn = !path.startsWith('rpc/') && !path.contains('?') && !path.startsWith('orders') && !path.startsWith('products');
  final uri = Uri.parse(path.startsWith('http') ? path : (path.contains('functions') ? path : '$base/rest/v1/$path'));
  final r = await http.openUrl(method, uri);
  r.headers.set('apikey', anon);
  r.headers.set('Authorization', 'Bearer $jwt');
  r.headers.set('Prefer', 'return=representation');
  if (body != null) {
    r.headers.set('Content-Type', 'application/json');
    r.add(utf8.encode(jsonEncode(body)));
  }
  final resp = await r.close();
  final txt = await utf8.decodeStream(resp);
  return {'status': resp.statusCode, 'raw': txt};
}

Future<({String jwt, String uid})> signup(String anon, String email) async {
  final r = await http.postUrl(Uri.parse('$base/auth/v1/signup'));
  r.headers.set('apikey', anon);
  r.headers.set('Authorization', 'Bearer $anon');
  r.headers.set('Content-Type', 'application/json');
  r.add(utf8.encode(jsonEncode({'email': email, 'password': 'testeteste123'})));
  final resp = await r.close();
  final j = jsonDecode(await utf8.decodeStream(resp)) as Map<String, dynamic>;
  return (jwt: j['access_token'] as String, uid: (j['user'] as Map)['id'] as String);
}

Future<void> main() async {
  final env = <String, String>{};
  for (final line in File('tool/live_ops_staging.env').readAsLinesSync()) {
    if (!line.contains('=') || line.trim().startsWith('#')) continue;
    final i = line.indexOf('=');
    env[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  final anon = env['SUPABASE_ANON_KEY']!;
  final email = 'c2p3${DateTime.now().millisecondsSinceEpoch}@axinoquaa.pt';
  final acc = await signup(anon, email);
  final jwt = acc.jwt;
  stdout.writeln('signed $email uid=${acc.uid}');

  Future<Map<String, dynamic>> bank() => call(jwt, anon, 'POST', 'rpc/batata_seller_direct_payment_details', {'p_seller_id': sellerId});

  final t0 = await bank();
  stdout.writeln('T0_NO_ORDER ${t0['status']} ${t0['raw']}');

  final seguro = await call(jwt, anon, 'POST', 'orders', {
    'product_id': prod,
    'buyer_id': acc.uid,
    'seller_id': sellerId,
    'price_total': 80,
    'shipping_method': 'Entrega em mão (€0.00)',
    'payment_method': 'Seguro Fleaber',
    'status': 'reserva_pendente',
    'quantity': 1,
  });
  stdout.writeln('INS_SEGURO ${seguro['status']} ${seguro['raw'].toString().substring(0, 180)}');
  final t1 = await bank();
  stdout.writeln('T1_AFTER_SEGURO ${t1['status']} ${t1['raw']}');

  File('tool/reports/REDTEAM_C2_BLIND_20260829_PASS3.json').writeAsStringSync(jsonEncode({
    'email': email,
    't0': t0,
    'insert_seguro': {'status': seguro['status'], 'raw': seguro['raw']},
    't1': t1,
  }));
}
