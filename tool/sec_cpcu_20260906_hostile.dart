// ignore_for_file: avoid_print
/// POS_ALLOWLIST CP–CU — dart run tool/sec_cpcu_20260906_hostile.dart
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
      raw.contains('forbidden') ||
      raw.contains('mismatch') ||
      raw.contains('23514') ||
      raw.contains('purchase_announce') ||
      raw.contains('off-platform') ||
      raw.contains('inválida') ||
      raw.contains('invalida');
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

  // CQ — notes allowlist estrita
  final chats = await req(
    'GET',
    '$url/rest/v1/chats?or=(user_a.eq.$buyerId,user_b.eq.$buyerId)&select=id&limit=1',
    BH,
  );
  String? chatId;
  if (chats['body'] is List && (chats['body'] as List).isNotEmpty) {
    chatId = '${(chats['body'] as List).first['id']}';
  }
  if (chatId != null) {
    Future<Map<String, dynamic>> card(String notes) =>
        req('POST', '$url/rest/v1/chat_messages', BH, {
          'chat_id': chatId,
          'sender_id': buyerId,
          'text':
              'FLEABER_JSON_V1:${jsonEncode({
                'kind': 'reservation_payment_submitted',
                'order_id': '00000000-0000-0000-0000-000000000001',
                'notes': notes,
              })}',
        });

    final ok = await card('stripe_paid_direct');
    if ((ok['http'] as int) >= 400 && '${ok['raw']}'.contains('54000')) {
      fail('cq-allow-stripe', '${ok['raw']}');
    } else {
      pass('cq-allow-stripe');
    }

    final bare = await card('12,00');
    denied(bare) ? pass('cq-deny-bare-amount') : fail('cq-deny-bare-amount', '${bare['raw']}');

    final doze = await card('doze euros');
    denied(doze) ? pass('cq-deny-doze') : fail('cq-deny-doze', '${doze['raw']}');

    final yen = await card('obrigado ￥ 12');
    denied(yen) ? pass('cq-deny-yen') : fail('cq-deny-yen', '${yen['raw']}');
  }

  // CP — off-platform encode via SQL helper
  final zwsp = await req(
    'POST',
    '$url/rest/v1/rpc/batata_is_off_platform_payment',
    SVC,
    {'p_method': 'mbway\u200b'},
  );
  if (zwsp['body'] == true) {
    pass('cp-off-zwsp');
  } else {
    fail('cp-off-zwsp', '${zwsp['raw']}');
  }
  final fw = await req(
    'POST',
    '$url/rest/v1/rpc/batata_is_off_platform_payment',
    SVC,
    {'p_method': 'ｍｂｗａｙ'},
  );
  if (fw['body'] == true) {
    pass('cp-off-fullwidth');
  } else {
    fail('cp-off-fullwidth', '${fw['raw']}');
  }
  final cyr = await req(
    'POST',
    '$url/rest/v1/rpc/batata_is_off_platform_payment',
    SVC,
    {'p_method': 'мbway'},
  );
  if (cyr['body'] == true) {
    pass('cp-off-cyrillic');
  } else {
    fail('cp-off-cyrillic', '${cyr['raw']}');
  }

  // CR — FOMO stems + welcome
  final live = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'status': 'live',
    'is_active': true,
    'title': 'cpcu-$stamp',
  });
  String? liveId;
  if (live['body'] is List && (live['body'] as List).isNotEmpty) {
    liveId = '${(live['body'] as List).first['id']}';
  } else if (live['body'] is Map) {
    liveId = '${(live['body'] as Map)['id']}';
  }
  if (liveId != null) {
    final welcome = await req(
      'POST',
      '$url/rest/v1/rpc/batata_live_system_message',
      SH,
      {'p_live_id': liveId, 'p_body': 'Bem-vindos ao directo!'},
    );
    final wOk = welcome['body'] is Map && (welcome['body'] as Map)['ok'] == true;
    wOk ? pass('cr-welcome-ok') : fail('cr-welcome-ok', '${welcome['raw']}');

    final jafoi = await req(
      'POST',
      '$url/rest/v1/rpc/batata_live_system_message',
      SH,
      {'p_live_id': liveId, 'p_body': 'já foi'},
    );
    final jf = jafoi['body'] is Map
        ? '${(jafoi['body'] as Map)['error']}'
        : '${jafoi['raw']}';
    jf.contains('purchase_announce')
        ? pass('cr-deny-jafoi')
        : fail('cr-deny-jafoi', jf);

    final fire = await req(
      'POST',
      '$url/rest/v1/rpc/batata_live_system_message',
      SH,
      {'p_live_id': liveId, 'p_body': '🔥1️⃣'},
    );
    final fr = fire['body'] is Map
        ? '${(fire['body'] as Map)['error']}'
        : '${fire['raw']}';
    fr.contains('purchase_announce')
        ? pass('cr-deny-fire-digit')
        : fail('cr-deny-fire-digit', fr);

    await req('PATCH', '$url/rest/v1/lives?id=eq.$liveId', SVC, {
      'status': 'ended',
      'is_active': false,
    });
  }

  // CU — path concat deny via helper
  final bad = await req(
    'POST',
    '$url/rest/v1/rpc/batata_dispute_proof_url_ok',
    SVC,
    {
      'p_url':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/order_disputes/$buyerId/00000000-0000-0000-0000-000000000099/ok.png%252f%255corder_disputes/4064686f-0000-0000-0000-000000000001/00000000-0000-0000-0000-000000000088/rtcu-secret.png',
      'p_buyer': buyerId,
      'p_oid': '00000000-0000-0000-0000-000000000099',
    },
  );
  if (bad['body'] == false) {
    pass('cu-deny-mixed-slash');
  } else {
    fail('cu-deny-mixed-slash', '${bad['raw']}');
  }

  final canon = await req(
    'POST',
    '$url/rest/v1/rpc/batata_storage_url_path_canonical',
    SVC,
    {'p_url': 'https://example.com/a'},
  );
  if ('${canon['raw']}'.contains('54000')) {
    fail('cu-no-54000', '${canon['raw']}');
  } else {
    pass('cu-no-54000');
  }

  if (exitCode == 0) print('ALL PASS');
}
