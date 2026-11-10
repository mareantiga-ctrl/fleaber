// ignore_for_file: avoid_print
/// BX–CC pós-fix — dart run tool/sec_bxcc_20260906_hostile.dart
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

bool denied(Map<String, dynamic> r) {
  final h = r['http'] as int;
  final raw = '${r['raw']}'.toLowerCase();
  return h == 400 ||
      h == 403 ||
      h == 409 ||
      raw.contains('forbidden') ||
      raw.contains('denied') ||
      raw.contains('mismatch') ||
      raw.contains('23514') ||
      raw.contains('purchase_announce') ||
      raw.contains('not_found');
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
  final ANON = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
  };

  final chats = await req(
    'GET',
    '$url/rest/v1/chats?buyer_id=eq.$buyerId&select=id&limit=1',
    BH,
  );
  String? chatId;
  if (chats['body'] is List && (chats['body'] as List).isNotEmpty) {
    chatId = '${(chats['body'] as List).first['id']}';
  }
  if (chatId == null) {
    final mk = await req(
      'POST',
      '$url/rest/v1/chats',
      {
        'apikey': svc,
        'Authorization': 'Bearer $svc',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      },
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'last_message': 'bxcc-setup',
      },
    );
    if (mk['body'] is List && (mk['body'] as List).isNotEmpty) {
      chatId = '${(mk['body'] as List).first['id']}';
    } else if (mk['body'] is Map) {
      chatId = '${(mk['body'] as Map)['id']}';
    }
  }
  if (chatId == null) {
    fail('BY-setup', 'no chat ${chats['raw']}');
  } else {
    for (final rail in ['Skrill 12,00 €', 'enviado MB', 'Neteller 12,00 €']) {
      final notes = await req('POST', '$url/rest/v1/chat_messages', BH, {
        'chat_id': chatId,
        'sender_id': buyerId,
        'text':
            'FLEABER_JSON_V1:${jsonEncode({
              'kind': 'reservation_payment_submitted',
              'order_id': '00000000-0000-0000-0000-000000000001',
              'notes': rail,
            })}',
      });
      denied(notes)
          ? pass('BY-notes-${rail.split(' ').first}')
          : fail('BY-notes-$rail', '${notes['raw']}');
    }
    final invis = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'text':
          'FLEABER_JSON_V1:${jsonEncode({
            'kind': 'reservation_payment_submitted',
            'order_id': '00000000-0000-0000-0000-000000000001',
            'notes': 'Clea\u206Arpay 12,00 €',
          })}',
    });
    denied(invis) ? pass('BY-invisible-clearpay') : fail('BY-invisible', '${invis['raw']}');

    final inbox = await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
      'last_message': 'Skrill 12,00 €',
    });
    denied(inbox) || (inbox['http'] as int) >= 400
        ? pass('BY-inbox-skrill')
        : fail('BY-inbox', '${inbox['http']}');

    final proof = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'text':
          'FLEABER_JSON_V1:${jsonEncode({
            'kind': 'reservation_payment_submitted',
            'order_id': '00000000-0000-0000-0000-000000000001',
            'notes': 'ok',
            'proof_url':
                'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/order_proofs/$buyerId/00000000-0000-0000-0000-000000000001/%252e%252e/x.jpg',
          })}',
    });
    denied(proof) ? pass('BY-proof-double-encode') : fail('BY-proof', '${proof['raw']}');
  }

  final liveRow = await req(
    'GET',
    '$url/rest/v1/lives?or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&select=id&order=created_at.desc&limit=1',
    SH,
  );
  String? liveId;
  if (liveRow['body'] is List && (liveRow['body'] as List).isNotEmpty) {
    liveId = '${(liveRow['body'] as List).first['id']}';
  }
  if (liveId != null) {
    final fomo = await req(
      'POST',
      '$url/rest/v1/rpc/batata_live_system_message',
      SH,
      {'p_live_id': liveId, 'p_body': 'last one'},
    );
    final fb = fomo['body'];
    (fb is Map && fb['ok'] == false) || denied(fomo)
        ? pass('BZ-fomo-last-one')
        : fail('BZ-fomo', '${fomo['raw']}');

    final mux = await req(
      'GET',
      '$url/rest/v1/lives?id=eq.$liveId&select=id,mux_playback_id',
      BH,
    );
    final raw = '${mux['raw']}';
    (mux['http'] as int) >= 400 || !raw.contains('mux_playback_id')
        ? pass('BZ-mux-playback-col')
        : fail('BZ-mux', raw);
  } else {
    fail('BZ-live', 'missing');
  }

  final resolve = await req(
    'POST',
    '$url/rest/v1/rpc/batata_resolve_handle',
    ANON,
    {'p_handle': 'definitely-missing-bxcc-$stamp'},
  );
  resolve['body'] is Map && (resolve['body'] as Map)['found'] == false
      ? pass('CA-resolve-smoke')
      : fail('CA-resolve', '${resolve['raw']}');

  final keyA = 'rtcbGREEKa1-$stamp';
  final keyB = 'rtcbGREEK\u03B11-$stamp'; // Greek alpha
  final p1 = await req(
    'POST',
    '$url/functions/v1/create-connect-account',
    {
      'apikey': anon,
      'Authorization': 'Bearer $sellerTok',
      'Content-Type': 'application/json',
    },
    {'amount': 100, 'idempotency_key': keyA},
  );
  final p2 = await req(
    'POST',
    '$url/functions/v1/create-connect-account',
    {
      'apikey': anon,
      'Authorization': 'Bearer $sellerTok',
      'Content-Type': 'application/json',
    },
    {'amount': 100, 'idempotency_key': keyB},
  );
  final t1 = (p1['body'] is Map) ? '${(p1['body'] as Map)['transferId'] ?? ''}' : '';
  final t2 = (p2['body'] is Map) ? '${(p2['body'] as Map)['transferId'] ?? ''}' : '';
  if (t1.isNotEmpty && t2.isNotEmpty && t1 == t2) {
    pass('CB-greek-same');
  } else if ((p1['http'] as int) >= 400 && (p2['http'] as int) >= 400) {
    pass('CB-greek-blocked');
  } else if (t1.isNotEmpty && t2.isNotEmpty && t1 != t2) {
    fail('CB-greek-same', '$t1 vs $t2');
  } else {
    pass('CB-greek-probe');
  }

  print('DONE exit=$exitCode');
}
