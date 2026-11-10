// ignore_for_file: avoid_print
/// V/W/X — dart run tool/sec_vwx_20260901_hostile.dart
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
      ? await http.post(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body))
      : method == 'DELETE'
          ? await http.delete(Uri.parse(u), headers: h)
          : method == 'PATCH'
              ? await http.patch(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body))
              : await http.get(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p};
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

String? orderIdFromE2E(dynamic body) {
  if (body is Map) {
    final m = Map<String, dynamic>.from(body);
    final direct = '${m['order_id'] ?? ''}'.trim();
    if (direct.isNotEmpty && direct != 'null') return direct;
  }
  return idOf(body);
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
  final crashSecret = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

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
  final E2E = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    if (crashSecret.length >= 16) 'x-fleaber-e2e-secret': crashSecret,
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, [Object? d]) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    print('${ok ? 'PASS' : 'FAIL'} $id ${d ?? ''}');
  }

  // V-P0 hop unship
  final paid = await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', E2E, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'probe': 'setup_paid_order',
    'initial_qty': 2,
    'shipping_method': 'mao',
  });
  final oid = orderIdFromE2E(paid['body']);
  if (oid != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SVC, {
      'shipping_method': 'mao',
      'payment_method': 'pagamento na app',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {'status': 'enviado'});
    final hop1 = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {
      'status': 'reserva_pendente',
    });
    final hop2 = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {'status': 'pago'});
    final afterHop = firstMap(
      (await req('GET', '$url/rest/v1/orders?id=eq.$oid&select=status,shipped_at', SVC))['body'],
    );
    add(
      'V_hop_unship_blocked',
      '${afterHop?['status']}' == 'enviado' &&
          afterHop?['shipped_at'] != null &&
          (hop2['http'] as int) >= 400,
      {'hop1': hop1['http'], 'hop2': hop2['http'], 'after': afterHop},
    );
  } else {
    add('V_hop_unship_blocked', false, 'no order');
  }

  // W-P0 delete system card
  final chat = await req('POST', '$url/rest/v1/chats', SVC, {
    'user_a': buyerId,
    'user_b': sellerId,
  });
  final chatId = idOf(chat['body']);
  if (chatId != null && oid != null) {
    final msg = await req('POST', '$url/rest/v1/chat_messages', SVC, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'text':
          'FLEABER_JSON_V1:${jsonEncode({'kind': 'seguro_fleaber_paid', 'order_id': oid, 'total': '5.90', 'label': 'probe'})}',
    });
    final msgId = idOf(msg['body']);
    if (msgId != null) {
      final del = await req('DELETE', '$url/rest/v1/chat_messages?id=eq.$msgId', BH);
      final still = await req('GET', '$url/rest/v1/chat_messages?id=eq.$msgId', SVC);
      add(
        'W_json_delete_blocked',
        (del['http'] as int) >= 400 && still['body'] is List && (still['body'] as List).isNotEmpty,
        {'del_http': del['http']},
      );
    } else {
      add('W_json_delete_blocked', false, 'no msg');
    }
  } else {
    add('W_json_delete_blocked', false, 'no chat');
  }

  final fails = results.where((r) => r['ok'] != true).length;
  print('--- VWX hostile ${results.length - fails}/${results.length} PASS ---');
  exit(fails > 0 ? 1 : 0);
}
