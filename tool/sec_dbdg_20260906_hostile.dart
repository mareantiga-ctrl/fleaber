// ignore_for_file: avoid_print
/// POS_CVDA DB–DG — dart run tool/sec_dbdg_20260906_hostile.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
]) async {
  final client = http.Client();
  try {
    late http.Response r;
    final uri = Uri.parse(u);
    if (method == 'POST') {
      r = await client.post(uri,
          headers: h, body: body == null ? null : jsonEncode(body));
    } else {
      r = await client.get(uri, headers: h);
    }
    dynamic p;
    try {
      p = r.body.isEmpty ? null : jsonDecode(r.body);
    } catch (_) {
      p = r.body;
    }
    return {'http': r.statusCode, 'body': p, 'raw': r.body};
  } finally {
    client.close();
  }
}

void pass(String id) => print('PASS $id');
void fail(String id, String why) {
  print('FAIL $id: $why');
  exitCode = 1;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final stamp = DateTime.now().millisecondsSinceEpoch;

  final SH = {
    'apikey': anon,
    'Authorization': 'Bearer $sellerTok',
    'Content-Type': 'application/json',
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  Future<bool> off(String pm) async {
    final r = await req(
      'POST',
      '$url/rest/v1/rpc/batata_is_off_platform_payment',
      SVC,
      {'p_method': pm},
    );
    return r['body'] == true;
  }

  await off('mbωay') ? pass('db-off-omega') : fail('db-off-omega', 'false');
  await off('ⲙbway') ? pass('db-off-coptic') : fail('db-off-coptic', 'false');
  await off('𝗺𝗯𝘄𝗮𝘆') ? pass('db-off-math') : fail('db-off-math', 'false');
  await off('mb way') ? pass('db-off-exact') : fail('db-off-exact', 'false');
  await off('transferência')
      ? pass('db-off-transferencia')
      : fail('db-off-transferencia', 'false');

  // FOMO allowlist
  final live = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'status': 'live',
    'is_active': true,
    'title': 'dbdg-$stamp',
  });
  String? liveId;
  if (live['body'] is List && (live['body'] as List).isNotEmpty) {
    liveId = '${(live['body'] as List).first['id']}';
  } else if (live['body'] is Map) {
    liveId = '${(live['body'] as Map)['id']}';
  }
  if (liveId != null) {
    final w = await req(
      'POST',
      '$url/rest/v1/rpc/batata_live_system_message',
      SH,
      {'p_live_id': liveId, 'p_body': 'Bem-vindos ao directo!'},
    );
    (w['body'] is Map && (w['body'] as Map)['ok'] == true)
        ? pass('dd-welcome')
        : fail('dd-welcome', '${w['raw']}');

    for (final bad in ['voou tudo', 'running out', '💨💨💨', 'ѕold', 'knapp']) {
      final r = await req(
        'POST',
        '$url/rest/v1/rpc/batata_live_system_message',
        SH,
        {'p_live_id': liveId, 'p_body': bad},
      );
      final err =
          r['body'] is Map ? '${(r['body'] as Map)['error']}' : '';
      err.contains('purchase_announce')
          ? pass('dd-deny-${bad.hashCode}')
          : fail('dd-deny-$bad', err);
    }

    await req('PATCH', '$url/rest/v1/lives?id=eq.$liveId', SVC, {
      'status': 'ended',
      'is_active': false,
    });
  }

  // Label concat deny
  final oid = '00000000-0000-0000-0000-000000000099';
  final clean =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/order_disputes/$buyerId/$oid/ok.png';
  final ok = await req(
    'POST',
    '$url/rest/v1/rpc/batata_dispute_proof_url_ok',
    SVC,
    {'p_url': clean, 'p_buyer': buyerId, 'p_oid': oid},
  );
  ok['body'] == true
      ? pass('dg-clean-ok')
      : fail('dg-clean-ok', '${ok['raw']}');

  final concat = await req(
    'POST',
    '$url/rest/v1/rpc/batata_dispute_proof_url_ok',
    SVC,
    {
      'p_url': '$clean%252forder_disputes/other/oid/x.png',
      'p_buyer': buyerId,
      'p_oid': oid,
    },
  );
  concat['body'] == false
      ? pass('dg-label-concat-deny')
      : fail('dg-label-concat-deny', '${concat['raw']}');

  if (exitCode == 0) print('ALL PASS');
}
