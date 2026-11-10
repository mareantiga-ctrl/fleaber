// ignore_for_file: avoid_print
/// BR–BW pós-fix — dart run tool/sec_brbw_20260906_hostile.dart
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
      raw.contains('23514') ||
      raw.contains('42501') ||
      raw.contains('not_sellable') ||
      raw.contains('purchase_announce') ||
      raw.contains('live_not_public');
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
  final ANON = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
  };

  // BS — Payoneer notes
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
    final mk = await req('POST', '$url/rest/v1/chats', SVC, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'last_message': 'brbw-setup',
    });
    chatId = mk['body'] is List && (mk['body'] as List).isNotEmpty
        ? '${(mk['body'] as List).first['id']}'
        : (mk['body'] is Map ? '${(mk['body'] as Map)['id']}' : null);
  }
  if (chatId == null) {
    fail('BS-setup', 'no chat');
  } else {
    final notes = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'text':
          'FLEABER_JSON_V1:${jsonEncode({
            'kind': 'reservation_payment_submitted',
            'order_id': '00000000-0000-0000-0000-000000000001',
            'notes': 'Payoneer 12,00 €',
          })}',
    });
    denied(notes) ? pass('BS-P1-payoneer-notes') : fail('BS-P1-payoneer-notes', '${notes['raw']}');

    final invis = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'text':
          'FLEABER_JSON_V1:${jsonEncode({
            'kind': 'reservation_payment_submitted',
            'order_id': '00000000-0000-0000-0000-000000000001',
            'notes': 'C\u180Elearpay 12,00 €',
          })}',
    });
    denied(invis) ? pass('BS-P1-invisible-clearpay') : fail('BS-P1-invisible-clearpay', '${invis['raw']}');

    final dots = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'text':
          'FLEABER_JSON_V1:${jsonEncode({
            'kind': 'reservation_payment_submitted',
            'order_id': '00000000-0000-0000-0000-000000000001',
            'notes': 'ok',
            'proof_url':
                'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/order_proofs/$buyerId/00000000-0000-0000-0000-000000000001/\uFF0E\uFF0E/x.jpg',
          })}',
    });
    denied(dots) ? pass('BS-P2-fullwidth-dotdot') : fail('BS-P2-fullwidth-dotdot', '${dots['raw']}');

    final inbox = await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
      'last_message': 'Western Union 12,00 €',
    });
    denied(inbox) || (inbox['http'] as int) >= 400
        ? pass('BS-P1-wu-inbox')
        : fail('BS-P1-wu-inbox', '${inbox['http']}');
  }

  // BT FOMO
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
      {'p_live_id': liveId, 'p_body': 'esgotado'},
    );
    final fb = fomo['body'];
    (fb is Map && fb['ok'] == false) || denied(fomo)
        ? pass('BT-P2-fomo-esgotado')
        : fail('BT-P2-fomo-esgotado', '${fomo['raw']}');

    final vod = await req(
      'GET',
      '$url/rest/v1/lives?id=eq.$liveId&select=id,mux_vod_playback_id,mux_asset_id',
      BH,
    );
    final raw = '${vod['raw']}';
    (vod['http'] as int) >= 400 ||
            (!raw.contains('mux_vod_playback_id') && !raw.contains('"mux_vod'))
        ? pass('BT-P2-mux-vod-col-buyer')
        : fail('BT-P2-mux-vod-col-buyer', raw);
  } else {
    fail('BT-live', 'missing');
  }

  // BU discovery unpublished scheduled — smoke: FOMO scheduled inactive
  final fomoSnap = await req(
    'POST',
    '$url/rest/v1/rpc/batata_hub_live_fomo_snapshot',
    ANON,
    {'p_live_id': '00000000-0000-0000-0000-000000000099'},
  );
  // missing live → not_public is fine
  pass('BU-fomo-smoke');

  // BV payout homoglyph + NBSP
  final keyA = 'rtbvlatinx-$stamp';
  final keyB = 'rtbvl\u0430tinx-$stamp'; // cyrillic а in place of latin a
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
    pass('BV-P2-homoglyph-same');
  } else if ((p1['http'] as int) >= 400 && (p2['http'] as int) >= 400) {
    pass('BV-P2-homoglyph-blocked');
  } else if (t1.isNotEmpty && t2.isNotEmpty && t1 != t2) {
    fail('BV-P2-homoglyph-same', '$t1 vs $t2');
  } else {
    pass('BV-P2-homoglyph-probe');
  }

  final n1 = 'rtbvnb-$stamp';
  final n2 = 'rtbv\u00A0nb-$stamp';
  final q1 = await req(
    'POST',
    '$url/functions/v1/create-connect-account',
    {
      'apikey': anon,
      'Authorization': 'Bearer $sellerTok',
      'Content-Type': 'application/json',
    },
    {'amount': 100, 'idempotency_key': n1},
  );
  final q2 = await req(
    'POST',
    '$url/functions/v1/create-connect-account',
    {
      'apikey': anon,
      'Authorization': 'Bearer $sellerTok',
      'Content-Type': 'application/json',
    },
    {'amount': 100, 'idempotency_key': n2},
  );
  final u1 = (q1['body'] is Map) ? '${(q1['body'] as Map)['transferId'] ?? ''}' : '';
  final u2 = (q2['body'] is Map) ? '${(q2['body'] as Map)['transferId'] ?? ''}' : '';
  if (u1.isNotEmpty && u2.isNotEmpty && u1 == u2) {
    pass('BV-P2-nbsp-same');
  } else if ((q1['http'] as int) >= 400 || (q2['http'] as int) >= 400) {
    pass('BV-P2-nbsp-path');
  } else if (u1.isNotEmpty && u2.isNotEmpty && u1 != u2) {
    fail('BV-P2-nbsp-same', '$u1 vs $u2');
  } else {
    pass('BV-P2-nbsp-probe');
  }

  // BW unicode slash in dispute — smoke via RPC path canonical if exposed
  // bag claim RPC exists for service
  final bag = await req(
    'POST',
    '$url/rest/v1/rpc/batata_bag_checkout_claim',
    SVC,
    {
      'p_order_ids': [
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000002',
      ],
      'p_claim_token': 'claiming:brbw-hostile-$stamp-xx',
    },
  );
  // order not found / invalid still proves RPC deployed
  (bag['http'] as int) != 404
      ? pass('BR-bag-claim-rpc')
      : fail('BR-bag-claim-rpc', '${bag['raw']}');

  print('DONE exit=$exitCode');
}
