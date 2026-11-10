// ignore_for_file: avoid_print
/// Indep 1837 P3 — dart run tool/sec_indep_1837_hostile.dart
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
  final r = method == 'POST'
      ? await http.post(
          Uri.parse(u),
          headers: h,
          body: body == null ? null : jsonEncode(body),
        )
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
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
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

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;

  final lives = await req(
    'GET',
    '$url/rest/v1/lives?or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&select=id&order=created_at.desc&limit=1',
    SVC,
  );
  final liveId = firstMap(lives['body'])?['id']?.toString();
  add('fixture_live', liveId != null && liveId!.isNotEmpty, {'id': liveId});

  if (liveId != null) {
    final tip = await req(
      'POST',
      '$url/rest/v1/rpc/batata_create_live_tip_pending',
      BH,
      {
        'p_live_id': liveId,
        'p_seller_id': sellerId,
        'p_amount': 1.0,
        'p_message': 'RT1837 $stamp',
        'p_stripe_session_id': 'cs_fake_RT1837_$stamp',
      },
    );
    final tipId = '${tip['body'] ?? ''}'.trim();
    add('tip_create_http', tip['http'] == 200 && tipId.isNotEmpty, {
      'http': tip['http'],
      'tip_id': tipId,
      'body': tip['body'],
    });

    if (tipId.isNotEmpty && tipId != 'null') {
      final row = await req(
        'GET',
        '$url/rest/v1/live_tips?id=eq.$tipId&select=id,status,stripe_session_id,amount',
        SVC,
      );
      final m = firstMap(row['body']);
      final sid = m?['stripe_session_id'];
      add(
        'P3_tip_session_id_ignored',
        sid == null || '$sid'.trim().isEmpty || '$sid' == 'null',
        {'stripe_session_id': sid, 'status': m?['status']},
      );
      await req('DELETE', '$url/rest/v1/live_tips?id=eq.$tipId', SVC);
    } else {
      add('P3_tip_session_id_ignored', false, tip);
    }
  }

  final failed = results.where((r) => r['ok'] != true).length;
  final out = 'tool/reports/sec_indep_1837_hostile_$stamp.json';
  await File(out).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'stamp': stamp,
      'pass': results.length - failed,
      'fail': failed,
      'results': results,
    }),
  );
  stdout.writeln('Wrote $out (${results.length - failed}/${results.length})');
  exit(failed == 0 ? 0 : 1);
}
