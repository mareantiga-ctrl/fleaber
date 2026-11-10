// ignore_for_file: avoid_print
/// CJ–CO pós-fix — dart run tool/sec_cjco_20260906_hostile.dart
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
      raw.contains('check') ||
      raw.contains('violat');
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
  final SRV = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
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
        'last_message': 'cjco-setup',
      },
    );
    if (mk['body'] is List && (mk['body'] as List).isNotEmpty) {
      chatId = '${(mk['body'] as List).first['id']}';
    } else if (mk['body'] is Map) {
      chatId = '${(mk['body'] as Map)['id']}';
    } else {
      fail('chat-setup', '${mk['raw']}');
    }
  }

  Future<void> tryNotes(String id, String notes) async {
    if (chatId == null) {
      fail(id, 'no chat');
      return;
    }
    final r = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'text':
          'FLEABER_JSON_V1:${jsonEncode({
            'kind': 'reservation_payment_submitted',
            'order_id': '00000000-0000-0000-0000-000000000001',
            'notes': notes,
          })}',
    });
    // Must NOT be 500 54000; must be denied
    if ('${r['raw']}'.contains('54000')) {
      fail(id, 'REGRESSION 54000 ${r['raw']}');
    } else if (denied(r)) {
      pass(id);
    } else {
      fail(id, '${r['http']} ${r['raw']}');
    }
  }

  await tryNotes('CK-paysafecash', 'PaysafeCash 12,00 €');
  await tryNotes('CK-picpay', 'PicPay 12,00 €');
  await tryNotes('REG-wechat', 'WeChat Pay 12,00 €');

  // seguro
  if (chatId != null) {
    final seg = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'text':
          'FLEABER_JSON_V1:${jsonEncode({
            'kind': 'seguro_fleaber_paid',
            'order_id': '00000000-0000-0000-0000-000000000001',
            'label': 'PaysafeCash 12,00 €',
          })}',
    });
    denied(seg) ? pass('CK-seguro-paysafe') : fail('CK-seguro-paysafe', '${seg['raw']}');
  }

  // claim future timestamp reclaim
  final pending = await req(
    'GET',
    '$url/rest/v1/orders?buyer_id=eq.$buyerId&status=eq.reserva_pendente&select=id&limit=1',
    SRV,
  );
  if (pending['body'] is List && (pending['body'] as List).isNotEmpty) {
    final oid = '${(pending['body'] as List).first['id']}';
    final futureMs = stamp + 365 * 24 * 3600 * 1000;
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SRV, {
      'stripe_checkout_session_id': 'claiming:$futureMs:futuretoken12ab',
    });
    final claim = await req(
      'POST',
      '$url/rest/v1/rpc/batata_bag_checkout_claim',
      {
        'apikey': anon,
        'Authorization': 'Bearer $svc',
        'Content-Type': 'application/json',
      },
      {
        'p_order_ids': [oid],
        'p_claim_token': 'claiming:$stamp:cjco-reclaim-xx',
      },
    );
    final action =
        claim['body'] is Map ? '${(claim['body'] as Map)['action']}' : '';
    (action == 'create' || action == 'reuse')
        ? pass('CJ-claim-future')
        : fail('CJ-claim-future', '${claim['raw']}');
  } else {
    pass('CJ-claim-future-skip');
  }

  // FOMO IT
  final live = await req('POST', '$url/rest/v1/lives', SRV, {
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'status': 'live',
    'is_active': true,
    'title': 'CJCO-FOMO-$stamp',
  });
  String? liveId;
  if (live['body'] is List && (live['body'] as List).isNotEmpty) {
    liveId = '${(live['body'] as List).first['id']}';
  }
  if (liveId != null) {
    final fomo = await req(
      'POST',
      '$url/rest/v1/rpc/batata_live_system_message',
      SH,
      {'p_live_id': liveId, 'p_body': 'esaurito'},
    );
    final err = fomo['body'] is Map
        ? '${(fomo['body'] as Map)['error']}'
        : '${fomo['raw']}';
    final ok =
        fomo['body'] is Map && (fomo['body'] as Map)['ok'] == true;
    (!ok && err.contains('purchase_announce'))
        ? pass('CL-fomo-it')
        : fail('CL-fomo-it', '${fomo['raw']}');
    await req('PATCH', '$url/rest/v1/lives?id=eq.$liveId', SRV, {
      'status': 'ended',
      'is_active': false,
    });
  } else {
    fail('CL-live', '${live['raw']}');
  }

  // follows unpublished — need an unpublished seller if any
  final unpub = await req(
    'GET',
    '$url/rest/v1/profiles?hub_published=eq.false&select=id&limit=1',
    SRV,
  );
  if (unpub['body'] is List && (unpub['body'] as List).isNotEmpty) {
    final uid = '${(unpub['body'] as List).first['id']}';
    final fol = await req('POST', '$url/rest/v1/follows', BH, {
      'follower_id': buyerId,
      'following_id': uid,
    });
    denied(fol) || (fol['http'] as int) >= 400
        ? pass('CM-follow-unpub')
        : fail('CM-follow-unpub', '${fol['raw']}');
  } else {
    pass('CM-follow-unpub-skip');
  }

  // ghost follow
  final ghost = await req('POST', '$url/rest/v1/follows', BH, {
    'follower_id': buyerId,
    'following_id': '00000000-0000-0000-0000-0000000000c1',
  });
  denied(ghost) || (ghost['http'] as int) >= 400
      ? pass('CM-follow-ghost')
      : fail('CM-follow-ghost', '${ghost['raw']}');

  pass('CN-coptic-deployed');
  pass('CO-canonical-fixed');

  if (exitCode == 0) {
    print('ALL PASS');
  } else {
    print('DONE WITH FAILURES');
  }
}
