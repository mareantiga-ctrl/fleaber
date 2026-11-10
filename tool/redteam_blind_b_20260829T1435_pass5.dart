// ignore_for_file: avoid_print
/// Pass 5 — último ciclo de classes novas + cleanup.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

late String base, anon, service, buyerId, sellerId, buyerJwt, sellerJwt;

Map<String, String> hUser(String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
Map<String, String> hSvc() => {
      'apikey': service,
      'Authorization': 'Bearer $service',
      'Content-Type': 'application/json',
    };

Future<http.Response> rest(String m, String p,
    {Map<String, String>? headers, Object? body}) {
  final uri = Uri.parse(p.startsWith('http') ? p : '$base$p');
  final hh = headers ?? hUser(buyerJwt);
  final b = body == null ? null : jsonEncode(body);
  switch (m) {
    case 'GET':
      return http.get(uri, headers: hh);
    case 'POST':
      return http.post(uri, headers: hh, body: b);
    case 'PATCH':
      return http.patch(uri, headers: hh, body: b);
    case 'DELETE':
      return http.delete(uri, headers: hh);
    default:
      throw ArgumentError(m);
  }
}

String clip(String s, [int n = 220]) {
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  return s.length <= n ? s : '${s.substring(0, n)}…';
}

void main() async {
  final env = loadLiveOpsStagingEnv();
  base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final sb = LiveOpsStagingClient(
    url: base,
    anonKey: anon,
    serviceRoleKey: service,
  );
  buyerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  sellerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  final rec = <String, dynamic>{};
  final findings = <Map<String, dynamic>>[];

  final lives = await sb.select(
    'lives',
    filter: 'seller_id=eq.$sellerId',
    limit: 1,
  );
  if (lives.isNotEmpty) {
    final lid = lives.first['id'];
    final complete = await rest(
      'POST',
      '/functions/v1/complete-mux-live',
      headers: hUser(buyerJwt),
      body: {'live_id': lid},
    );
    rec['complete_mux_as_buyer'] = {
      'http': complete.statusCode,
      'body': clip(complete.body),
    };
    if (complete.statusCode == 200 &&
        !complete.body.toLowerCase().contains('error')) {
      findings.add({
        'id': 'RTB2-MUX-03',
        'severity': 'P1',
        'title': 'Buyer termina directo Mux alheio',
        'result': rec['complete_mux_as_buyer'],
      });
    }
    final play = await rest(
      'POST',
      '/functions/v1/resolve-mux-playback',
      headers: hUser(buyerJwt),
      body: {'live_id': lid},
    );
    rec['resolve_playback'] = {
      'http': play.statusCode,
      'has_stream_key': play.body.contains('stream_key') &&
          !play.body.contains('null'),
      'body': clip(play.body),
    };
    if (play.body.contains('stream_key') &&
        RegExp(r'"stream_key"\s*:\s*"[^"]+"').hasMatch(play.body)) {
      findings.add({
        'id': 'RTB2-MUX-04',
        'severity': 'P1',
        'title': 'resolve-mux-playback devolve stream_key',
        'result': {'http': play.statusCode},
      });
    }
  }

  final patchLive = await rest(
    'PATCH',
    '/rest/v1/lives?seller_id=eq.$sellerId&select=id',
    headers: hUser(buyerJwt),
    body: {'status': 'ended', 'is_active': false},
  );
  rec['buyer_patch_seller_lives'] = {
    'http': patchLive.statusCode,
    'body': clip(patchLive.body),
  };

  final offers = await rest(
    'POST',
    '/rest/v1/product_offers',
    headers: hUser(buyerJwt),
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': '00000000-0000-0000-0000-000000000001',
      'amount': 1,
      'status': 'accepted',
    },
  );
  rec['offer_spoof_accepted'] = {
    'http': offers.statusCode,
    'body': clip(offers.body),
  };

  final bag = await rest(
    'POST',
    '/functions/v1/create-payment-intent',
    headers: hUser(buyerJwt),
    body: {
      'buyer_id': buyerId,
      'bag_checkout': true,
      'shipping_method': 'hand',
      'bag_lines': [
        {'order_id': '00000000-0000-0000-0000-000000000001'},
      ],
    },
  );
  rec['bag_foreign_order'] = {
    'http': bag.statusCode,
    'body': clip(bag.body),
  };

  final prize = await rest(
    'POST',
    '/functions/v1/create-payment-intent',
    headers: hUser(buyerJwt),
    body: {
      'buyer_id': buyerId,
      'order_id': '00000000-0000-0000-0000-000000000001',
      'prize_shipping': true,
      'shipping_method': 'carrier',
    },
  );
  rec['prize_flag'] = {'http': prize.statusCode, 'body': clip(prize.body)};

  final sms = await rest(
    'POST',
    '/functions/v1/send-sms-bulkgate',
    headers: hUser(buyerJwt),
    body: {'to': '+351910000000', 'text': 'rtb2'},
  );
  rec['sms'] = {'http': sms.statusCode, 'body': clip(sms.body)};

  final ocr = await rest(
    'POST',
    '/functions/v1/ingest-ocr-reservation',
    headers: {
      ...hUser(buyerJwt),
      'x-device-token': 'x',
    },
    body: {
      'live_id': lives.isEmpty ? null : lives.first['id'],
      'ocr_line_hash': '12345678',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'requested_qty': 99,
    },
  );
  rec['ocr_qty99'] = {'http': ocr.statusCode, 'body': clip(ocr.body)};

  // Cleanup planted public secret + dummy reservation
  await http.delete(
    Uri.parse(
      '$base/storage/v1/object/chat_media/chat_uploads/dc186402-cad0-42aa-bd1c-0a6d649c4f4f/rtb2_20260829T1435.txt',
    ),
    headers: hSvc(),
  );
  await rest(
    'PATCH',
    '/rest/v1/live_reservation_requests?id=eq.103ec3f5-ed75-4c68-b31f-79a2c2d86c03',
    headers: hSvc(),
    body: {'status': 'rejected'},
  );
  await rest(
    'PATCH',
    '/rest/v1/profiles?id=eq.$buyerId',
    headers: hSvc(),
    body: {'user_type': 'comprador'},
  );
  await rest(
    'PATCH',
    '/rest/v1/lives?id=eq.5772b38e-e6df-4497-8d2e-e83e840a0e1f',
    headers: hSvc(),
    body: {'status': 'ended', 'is_active': false},
  );

  rec['findings'] = findings;
  File('tool/reports/redteam_blind_b_20260829T1435/pass5.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rec));
  print('PASS5 new_p0p1=${findings.length}');
  for (final f in findings) {
    print(' ${f['id']} ${f['title']}');
  }
}
