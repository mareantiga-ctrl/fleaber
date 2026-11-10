// ignore_for_file: avoid_print
/// Pass 6 — observar tip/wallet, B2 pairing, bag reserva_pendente. Sem correcções.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../live_ops_staging_client.dart';

const stamp = '20260830T1605';
const projectMust = 'fxdknzrqjenzqcvnwqqq';
final matrix = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];
final notes = <String>[];

void row(String surface, String attack, String identity, String result, String impact, String severity, [Object? evidence]) {
  matrix.add({
    'surface': surface,
    'attack': attack,
    'identity': identity,
    'result': result,
    'impact': impact,
    'severity': severity,
    'evidence': evidence,
  });
}

String clip(Object? v, [int n = 400]) {
  final s = v is String ? v : jsonEncode(v);
  return s.length <= n ? s : '${s.substring(0, n)}…';
}

Future<Map<String, dynamic>> req(String method, String u, Map<String, String> h, [Object? body]) async {
  late http.Response r;
  switch (method) {
    case 'POST':
      r = await http.post(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body));
      break;
    case 'GET':
      r = await http.get(Uri.parse(u), headers: h);
      break;
    default:
      r = await http.patch(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body));
  }
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body};
}

Map<String, String> hdr(String k, String b) => {
      'apikey': k,
      'Authorization': 'Bearer $b',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) exit(2);
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final c = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerJwt = await c.signIn(email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'), password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'));
  final sellerJwt = await c.signIn(email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'), password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'));
  final bUid = await c.userIdForAccessToken(buyerJwt);
  final sUid = await c.userIdForAccessToken(sellerJwt);
  final buyH = hdr(anon, buyerJwt);
  final selH = hdr(anon, sellerJwt);
  final svcH = hdr(svc, svc);
  String? b2Jwt;
  try {
    b2Jwt = await c.signIn(email: 'rt1605-b2-$stamp@staging.fleaber.invalid', password: 'Rt1605!pass');
  } catch (_) {}
  final b2H = b2Jwt == null ? null : hdr(anon, b2Jwt);

  final tip = await req('GET', '$url/rest/v1/live_tips?id=eq.900dbf33-8ad3-4101-a852-d5d3eafa51d4&select=id,live_id,buyer_id,seller_id,amount,seller_amount,processing_fee,payment_source,status', svcH);
  final wb = await req('GET', '$url/rest/v1/wallets?id=eq.$bUid&select=id,balance', svcH);
  final ws = await req('GET', '$url/rest/v1/wallets?id=eq.$sUid&select=id,balance', svcH);
  final tx = await req('GET', '$url/rest/v1/wallet_transactions?tip_id=eq.900dbf33-8ad3-4101-a852-d5d3eafa51d4&select=id,wallet_id,amount,type,description', svcH);
  row('TIPS', 'observe wallet tip 900dbf33', 'service_observe', 'tip=${clip(tip['body'], 200)} wb=${clip(wb['body'], 80)} ws=${clip(ws['body'], 80)} tx=${clip(tx['body'], 200)}', 'débito+crédito?', 'info', {
    'tip': tip['body'],
    'buyer_wallet': wb['body'],
    'seller_wallet': ws['body'],
    'txs': tx['body'],
  });

  if (b2H != null) {
    final pair = await req('POST', '$url/rest/v1/rpc/batata_ps_create_pairing', b2H, {
      'p_live_id': '336d37ad-23b5-4f19-8545-7b1a1805b9eb',
    });
    row('LIVE', 'B2 ps_create_pairing live alheia', 'buyer2', 'http=${pair['http']} ${clip(pair['text'], 180)}', pair['text'].toString().contains('583096') || pair['text'].toString().contains('"ok": true') ? 'pairing alheio' : 'bloqueado', 'info', pair['body']);
    if (pair['http'] == 200 && '${pair['text']}'.contains('"ok": true')) {
      findings.add({
        'id': 'P1-PS-PAIRING-FOREIGN',
        'severity': 'P1',
        'title': 'Buyer2 criou pairing PS em live alheia',
        'actor': 'buyer2',
        'preconditions': 'live uuid conhecido',
        'reproduction': 'rpc batata_ps_create_pairing',
        'impact': 'device token seller via claim',
        'state': 'ABERTO',
        'evidence': pair['body'],
      });
    }
  }

  // Claim helper pairing code from pass5 as anon
  final claim = await req('POST', '$url/functions/v1/ps-pairing-claim', hdr(anon, anon), {
    'code': '583096',
    'device_id': 'hostile-b2',
  });
  row('PS/OCR', 'anon claim code 583096', 'anon', 'http=${claim['http']} ${clip(claim['text'], 220)}', 'device_token?', 'info', claim['body']);

  // Bag reserva_pendente
  final prod = await req('POST', '$url/rest/v1/products', selH, {
    'seller_id': sUid,
    'title': 'RT1605bag $stamp',
    'price': 11.00,
    'quantity': 5,
    'list_on_marketplace': true,
    'image_urls': <dynamic>[],
  });
  final pid = prod['body'] is List ? '${(prod['body'] as List).first['id']}' : null;
  if (pid != null) {
    final o1 = await req('POST', '$url/rest/v1/orders', buyH, {
      'buyer_id': bUid,
      'seller_id': sUid,
      'product_id': pid,
      'quantity': 1,
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
      'status': 'reserva_pendente',
    });
    final o2 = await req('POST', '$url/rest/v1/orders', buyH, {
      'buyer_id': bUid,
      'seller_id': sUid,
      'product_id': pid,
      'quantity': 1,
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
      'status': 'reserva_pendente',
    });
    String? idOf(dynamic b) {
      if (b is List && b.isNotEmpty) return '${b.first['id']}';
      return null;
    }
    final id1 = idOf(o1['body']);
    final id2 = idOf(o2['body']);
    if (id1 != null && id2 != null) {
      final bag = await req('POST', '$url/functions/v1/create-payment-intent', buyH, {
        'buyer_id': bUid,
        'bag_checkout': true,
        'shipping_method': 'hand',
        'amount': 50,
        'bag_lines': [
          {'order_id': id1, 'line_total_cents': 1, 'quantity': 9},
          {'order_id': id2, 'line_total_cents': 1},
        ],
      });
      row('BAG / CART', 'bag 2x reserva_pendente amount=50', 'buyer', 'http=${bag['http']} ${clip(bag['text'], 280)}', 'server amount', 'info', bag['body']);
      notes.add('bag keys=${bag['body'] is Map ? (bag['body'] as Map).keys.toList() : bag['http']} amt=${bag['body'] is Map ? bag['body']['server_amount_cents'] : null}');
    }
  }

  // Ensure live still ended
  final live = await req('GET', '$url/rest/v1/lives?id=eq.336d37ad-23b5-4f19-8545-7b1a1805b9eb&select=id,status,is_active', svcH);
  row('LIVE', 'confirm ended', 'service_observe', clip(live['body'], 120), 'cleanup', 'info');

  File('tool/redteam_cega_indep_20260830T1605/out/pass6.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'FROZEN_AT': DateTime.now().toUtc().toIso8601String(),
    'pass': 6,
    'findings': findings,
    'matrix': matrix,
    'notes': notes,
  }));
  stdout.writeln('PASS6 findings=${findings.length}');
  for (final f in findings) {
    stdout.writeln('${f['severity']} ${f['id']} ${f['title']}');
  }
}
