// ignore_for_file: avoid_print
/// POS_CPCU CV–DA — dart run tool/sec_cvda_20260906_hostile.dart
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
    } else if (method == 'PATCH') {
      r = await client.patch(uri,
          headers: h, body: body == null ? null : jsonEncode(body));
    } else if (method == 'OPTIONS') {
      r = await client.send(http.Request('OPTIONS', uri)..headers.addAll(h))
          .then(http.Response.fromStream);
    } else {
      r = await client.get(uri, headers: h);
    }
    dynamic p;
    try {
      p = r.body.isEmpty ? null : jsonDecode(r.body);
    } catch (_) {
      p = r.body;
    }
    return {
      'http': r.statusCode,
      'body': p,
      'raw': r.body,
      'headers': r.headers,
    };
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
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final stamp = DateTime.now().millisecondsSinceEpoch;

  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SH = {
    'apikey': anon,
    'Authorization': 'Bearer $sellerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
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

  // CV off-platform encodes
  await off('μbway')
      ? pass('cv-off-greek-mu')
      : fail('cv-off-greek-mu', 'false');
  await off('mbԝay')
      ? pass('cv-off-cyr-w')
      : fail('cv-off-cyr-w', 'false');
  await off('ᴍʙᴡᴀʏ')
      ? pass('cv-off-smallcaps')
      : fail('cv-off-smallcaps', 'false');
  await off('mbwa\u0301y')
      ? pass('cv-off-nfd')
      : fail('cv-off-nfd', 'false');

  // DA — https:// not false-positive; concat still deny
  final buyer = buyerId;
  final oid = '00000000-0000-0000-0000-000000000099';
  final clean =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/order_disputes/$buyer/$oid/ok.png';
  final ok = await req(
    'POST',
    '$url/rest/v1/rpc/batata_dispute_proof_url_ok',
    SVC,
    {'p_url': clean, 'p_buyer': buyer, 'p_oid': oid},
  );
  ok['body'] == true
      ? pass('da-clean-https-ok')
      : fail('da-clean-https-ok', '${ok['raw']}');

  final bad = await req(
    'POST',
    '$url/rest/v1/rpc/batata_dispute_proof_url_ok',
    SVC,
    {
      'p_url': '$clean%252f%255cextra/evil.png',
      'p_buyer': buyer,
      'p_oid': oid,
    },
  );
  bad['body'] == false
      ? pass('da-concat-deny')
      : fail('da-concat-deny', '${bad['raw']}');

  // CY — follow published (ensure seller hub_published)
  await req('PATCH', '$url/rest/v1/profiles?id=eq.$sellerId', SVC, {
    'hub_published': true,
  });
  await req(
    'DELETE',
    '$url/rest/v1/follows?follower_id=eq.$buyerId&following_id=eq.$sellerId',
    BH,
  );
  final fol = await req('POST', '$url/rest/v1/follows', BH, {
    'follower_id': buyerId,
    'following_id': sellerId,
  });
  final fh = fol['http'] as int;
  (fh < 300 || fh == 409 || '${fol['raw']}'.contains('23505'))
      ? pass('cy-follow-published')
      : fail('cy-follow-published', '${fol['http']} ${fol['raw']}');

  // CX FOMO + welcome
  final live = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'status': 'live',
    'is_active': true,
    'title': 'cvda-$stamp',
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
        ? pass('cx-welcome')
        : fail('cx-welcome', '${w['raw']}');

    final sumiu = await req(
      'POST',
      '$url/rest/v1/rpc/batata_live_system_message',
      SH,
      {'p_live_id': liveId, 'p_body': 'sumiu tudo'},
    );
    final se = sumiu['body'] is Map
        ? '${(sumiu['body'] as Map)['error']}'
        : '';
    se.contains('purchase_announce')
        ? pass('cx-deny-sumiu')
        : fail('cx-deny-sumiu', se);

    final fire = await req(
      'POST',
      '$url/rest/v1/rpc/batata_live_system_message',
      SH,
      {'p_live_id': liveId, 'p_body': '🔥🔥🔥'},
    );
    final fe =
        fire['body'] is Map ? '${(fire['body'] as Map)['error']}' : '';
    fe.contains('purchase_announce')
        ? pass('cx-deny-fire')
        : fail('cx-deny-fire', fe);

    final morph = await req(
      'POST',
      '$url/rest/v1/rpc/batata_live_system_message',
      SH,
      {'p_live_id': liveId, 'p_body': 'es0aurito'},
    );
    final me =
        morph['body'] is Map ? '${(morph['body'] as Map)['error']}' : '';
    me.contains('purchase_announce')
        ? pass('cx-deny-es0')
        : fail('cx-deny-es0', me);

    await req('PATCH', '$url/rest/v1/lives?id=eq.$liveId', SVC, {
      'status': 'ended',
      'is_active': false,
    });
  }

  // CY CORS — never echo chrome-extension
  final opt = await req(
    'OPTIONS',
    '$url/functions/v1/create-mux-live',
    {
      'Origin': 'chrome-extension://abcdefghijklmnopqrstuvwxyz1234',
      'Access-Control-Request-Method': 'POST',
    },
  );
  final acao = (opt['headers'] as Map)['access-control-allow-origin'] ?? '';
  acao == 'https://fleaber.pt'
      ? pass('cy-cors-ext')
      : fail('cy-cors-ext', 'ACAO=$acao');

  if (exitCode == 0) print('ALL PASS');
}
