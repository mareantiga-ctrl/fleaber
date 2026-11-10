// ignore_for_file: avoid_print
/// T1651 residual P2 pairing — dart run tool/sec_t1651_pairing_hostile.dart
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

Map<String, dynamic>? asMap(dynamic b) {
  if (b is Map) return Map<String, dynamic>.from(b);
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
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
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

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final lives = await req(
    'GET',
    '$url/rest/v1/lives?or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&select=id,is_active,status,ended_at&order=created_at.desc&limit=5',
    SVC,
  );
  Map<String, dynamic>? live;
  if (lives['body'] is List) {
    for (final row in lives['body'] as List) {
      if (row is Map) {
        live = Map<String, dynamic>.from(row);
        break;
      }
    }
  }
  final liveId = live == null ? null : '${live['id']}'.trim();
  add('fixture_live', liveId != null && liveId.isNotEmpty, live);

  if (liveId != null) {
    final a = await req(
      'POST',
      '$url/rest/v1/rpc/batata_ps_create_pairing',
      SH,
      {'p_live_id': liveId, 'p_device_id_hint': 't1651-a'},
    );
    final am = asMap(a['body']);
    final ttl = am?['ttl_seconds'];
    final code1 = '${am?['code'] ?? ''}';
    add(
      'P2_ttl_2min',
      am?['ok'] == true && (ttl == 120 || ttl == '120'),
      {'http': a['http'], 'ttl': ttl, 'ok': am?['ok'], 'body': a['body']},
    );

    final b = await req(
      'POST',
      '$url/rest/v1/rpc/batata_ps_create_pairing',
      SH,
      {'p_live_id': liveId, 'p_device_id_hint': 't1651-b'},
    );
    final bm = asMap(b['body']);
    final code2 = '${bm?['code'] ?? ''}';

    // Observar se código A expirou na BD
    final sess = await req(
      'GET',
      '$url/rest/v1/ps_pairing_sessions?live_id=eq.$liveId&order=expires_at.desc&limit=5&select=code,expires_at,claimed_at',
      SVC,
    );
    var aExpired = false;
    if (sess['body'] is List && code1.isNotEmpty) {
      for (final row in sess['body'] as List) {
        if (row is Map && '${row['code']}' == code1) {
          final exp = DateTime.tryParse('${row['expires_at']}');
          aExpired = exp != null && exp.isBefore(DateTime.now().toUtc());
        }
      }
    }
    add('P2_one_open_code_invalidates_prior', aExpired || code1 != code2, {
      'code1': code1,
      'code2': code2,
      'aExpired': aExpired,
      'sessions': sess['body'],
    });
  }

  final failed = results.where((r) => r['ok'] != true).length;
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final out = 'tool/reports/sec_t1651_pairing_hostile_$stamp.json';
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
