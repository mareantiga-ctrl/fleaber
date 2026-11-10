// ignore_for_file: avoid_print
/// AG pass4 — fake pago → enviado / concluido. dart run tool/redteam_blind_ag_20260901T1916_pass4.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(String method, String u, Map<String, String> h, [Object? body]) async {
  final encoded = body == null ? null : jsonEncode(body);
  final r = method == 'POST'
      ? await http.post(Uri.parse(u), headers: h, body: encoded)
      : method == 'PATCH'
          ? await http.patch(Uri.parse(u), headers: h, body: encoded)
          : await http.get(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p};
}

Map<String, dynamic>? firstMap(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
  return null;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final SH = {
    'apikey': anon,
    'Authorization': 'Bearer $sellerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  const oid = 'db2da223-4245-44ec-bcf3-9ce95a9860c0';
  final probes = <Map<String, dynamic>>[];
  void probe(String id, Map<String, dynamic> d) {
    probes.add({'id': id, ...d});
    print('PROBE $id ${jsonEncode(d)}');
  }

  final envio = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {'status': 'enviado'});
  probe('AG8-fake-pago-to-enviado', {
    'http': envio['http'],
    'body': firstMap(envio['body'])?['status'] ?? envio['body'],
  });
  final rec = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {'status': 'entregue'});
  probe('AG8-buyer-entregue-on-fake-pago', {
    'http': rec['http'],
    'body': rec['body'],
  });
  final conc = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {'status': 'concluido'});
  probe('AG8-seller-concluido-fake-pago', {
    'http': conc['http'],
    'body': conc['body'],
  });
  final after = firstMap(
    (await req('GET', '$url/rest/v1/orders?id=eq.$oid&select=status,amount_paid_cents,shipped_at', SVC))['body'],
  );
  final wal = firstMap(
    (await req('GET', '$url/rest/v1/wallets?id=eq.${envRequire(e, 'LIVE_OPS_TEST_SELLER_ID')}&select=id,balance', SVC))['body'],
  );
  probe('AG8-after-ship-chain', {'order': after, 'wallet': wal});
  File('tool/redteam_blind_ag_20260901T1916/probes_pass4.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({'probes': probes}));
}
