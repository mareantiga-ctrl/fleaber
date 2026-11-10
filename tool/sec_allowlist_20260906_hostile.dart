// ignore_for_file: avoid_print
/// Allowlist pós-fix — dart run tool/sec_allowlist_20260906_hostile.dart
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

  final chats = await req(
    'GET',
    '$url/rest/v1/chats?or=(user_a.eq.$buyerId,user_b.eq.$buyerId)&select=id&limit=1',
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
        'user_a': buyerId,
        'user_b': sellerId,
        'last_message': 'allow-setup',
      },
    );
    if (mk['body'] is List && (mk['body'] as List).isNotEmpty) {
      chatId = '${(mk['body'] as List).first['id']}';
    } else if (mk['body'] is Map && (mk['body'] as Map)['id'] != null) {
      chatId = '${(mk['body'] as Map)['id']}';
    } else {
      fail('chat', '${mk['http']} ${mk['raw']}');
    }
  }

  Future<Map<String, dynamic>> card(String kind, Map extra) async {
    return req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chatId,
      'sender_id': buyerId,
      'text': 'FLEABER_JSON_V1:${jsonEncode({
            'kind': kind,
            'order_id': '00000000-0000-0000-0000-000000000001',
            ...extra,
          })}',
    });
  }

  if (chatId != null) {
    // Allow: empty notes / stripe_paid_direct / plain text
    final okEmpty = await card('reservation_payment_submitted', {'notes': ''});
    if ('${okEmpty['raw']}'.contains('54000')) {
      fail('allow-empty', '54000');
    } else {
      pass('allow-no-54000-empty');
    }

    final okStripe = await card(
      'reservation_payment_submitted',
      {'notes': 'stripe_paid_direct'},
    );
    if ('${okStripe['raw']}'.contains('54000')) {
      fail('allow-stripe', '54000');
    } else {
      pass('allow-no-54000-stripe');
    }

    final plain = await card(
      'reservation_payment_submitted',
      {'notes': 'segue o comprovativo anexo por favor'},
    );
    if ('${plain['raw']}'.contains('54000')) {
      fail('allow-plain', '54000');
    } else {
      pass('allow-plain-text');
    }

    final amt = await card(
      'reservation_payment_submitted',
      {'notes': 'paguei 12,00 € ontem'},
    );
    denied(amt) ? pass('deny-amount') : fail('deny-amount', '${amt['raw']}');

    final bareAmt = await card(
      'reservation_payment_submitted',
      {'notes': '12,00'},
    );
    denied(bareAmt)
        ? pass('deny-bare-amount')
        : fail('deny-bare-amount', '${bareAmt['raw']}');

    final brand = await card(
      'reservation_payment_submitted',
      {'notes': 'PaysafeCash 12,00 €'},
    );
    denied(brand) ? pass('deny-brand') : fail('deny-brand', '${brand['raw']}');

    final seg = await card(
      'seguro_fleaber_paid',
      {'label': 'PaysafeCash 12,00 €'},
    );
    denied(seg)
        ? pass('deny-seguro-label')
        : fail('deny-seguro-label', '${seg['raw']}');

    final segOk = await card('seguro_fleaber_paid', {});
    if ('${segOk['raw']}'.contains('54000')) {
      fail('seguro-empty-label', '54000');
    } else {
      pass('seguro-empty-label-ok');
    }
  }

  // FOMO stems
  final live = await req(
    'POST',
    '$url/rest/v1/lives',
    {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    },
    {
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'status': 'live',
      'is_active': true,
      'title': 'ALLOW-FOMO-$stamp',
    },
  );
  String? liveId;
  if (live['body'] is List && (live['body'] as List).isNotEmpty) {
    liveId = '${(live['body'] as List).first['id']}';
  }
  if (liveId != null) {
    final bad = await req(
      'POST',
      '$url/rest/v1/rpc/batata_live_system_message',
      SH,
      {'p_live_id': liveId, 'p_body': 'esaurito'},
    );
    final err = bad['body'] is Map ? '${(bad['body'] as Map)['error']}' : '';
    final ok = bad['body'] is Map && (bad['body'] as Map)['ok'] == true;
    (!ok && err.contains('purchase_announce'))
        ? pass('fomo-stem-it')
        : fail('fomo-stem-it', '${bad['raw']}');

    final welcome = await req(
      'POST',
      '$url/rest/v1/rpc/batata_live_system_message',
      SH,
      {'p_live_id': liveId, 'p_body': 'Bem-vindos ao directo!'},
    );
    final wok =
        welcome['body'] is Map && (welcome['body'] as Map)['ok'] == true;
    wok ? pass('fomo-welcome-ok') : fail('fomo-welcome-ok', '${welcome['raw']}');

    await req(
      'PATCH',
      '$url/rest/v1/lives?id=eq.$liveId',
      {
        'apikey': svc,
        'Authorization': 'Bearer $svc',
        'Content-Type': 'application/json',
      },
      {'status': 'ended', 'is_active': false},
    );
  } else {
    fail('live', '${live['raw']}');
  }

  // Payout charset — Edge
  final payout = await req(
    'POST',
    '$url/functions/v1/create-connect-account',
    {
      'apikey': anon,
      'Authorization': 'Bearer $sellerTok',
      'Content-Type': 'application/json',
    },
    {
      'amount': 100,
      'idempotency_key': 'rtcnⲟCoptAllow01',
    },
  );
  final praw = '${payout['raw']}'.toLowerCase();
  (payout['http'] == 400 &&
          (praw.contains('inválida') ||
              praw.contains('invalida') ||
              praw.contains('idempotency')))
      ? pass('payout-charset-reject')
      : fail('payout-charset-reject', '${payout['http']} ${payout['raw']}');

  if (exitCode == 0) {
    print('ALL PASS');
  } else {
    print('DONE WITH FAILURES');
  }
}
