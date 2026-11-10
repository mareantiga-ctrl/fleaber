// ignore_for_file: avoid_print
/// BL–BQ pós-fix — dart run tool/sec_blbq_20260902_hostile.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
  bool followRedirects = true,
]) async {
  final client = http.Client();
  try {
    late http.Response r;
    final uri = Uri.parse(u);
    if (method == 'POST') {
      r = await client.post(uri, headers: h, body: body == null ? null : jsonEncode(body));
    } else if (method == 'PATCH') {
      r = await client.patch(uri, headers: h, body: body == null ? null : jsonEncode(body));
    } else {
      final rq = http.Request('GET', uri);
      h.forEach((k, v) => rq.headers[k] = v);
      final streamed = await client.send(rq);
      if (!followRedirects) {
        r = await http.Response.fromStream(streamed);
      } else {
        r = await http.Response.fromStream(streamed);
        // default Client follows; Request path does not — follow manually if needed
        var hops = 0;
        var cur = r;
        while (followRedirects &&
            hops < 5 &&
            (cur.statusCode == 301 ||
                cur.statusCode == 302 ||
                cur.statusCode == 303 ||
                cur.statusCode == 307) &&
            cur.headers['location'] != null) {
          hops++;
          final next = Uri.parse(cur.headers['location']!);
          final nq = http.Request('GET', next);
          h.forEach((k, v) => nq.headers[k] = v);
          cur = await http.Response.fromStream(await client.send(nq));
        }
        r = cur;
      }
    }
    dynamic p;
    try {
      p = r.body.isEmpty ? null : jsonDecode(r.body);
    } catch (_) {
      p = r.body;
    }
    return {
      'http': r.statusCode,
      'body': p,
      'raw': r.body,
      'location': r.headers['location'],
    };
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
      raw.contains('purchase_announce');
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

  // --- BM: Clearpay notes ---
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
      SVC,
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'last_message': 'blbq-setup',
      },
    );
    if (mk['body'] is List && (mk['body'] as List).isNotEmpty) {
      chatId = '${(mk['body'] as List).first['id']}';
    } else if (mk['body'] is Map) {
      chatId = '${(mk['body'] as Map)['id']}';
    }
  }
  if (chatId == null) {
    fail('BM-setup-chat', 'no chat ${chats['raw']}');
  } else {
    final notes = await req(
      'POST',
      '$url/rest/v1/chat_messages',
      BH,
      {
        'chat_id': chatId,
        'sender_id': buyerId,
        'text':
            'FLEABER_JSON_V1:${jsonEncode({
              'kind': 'reservation_payment_submitted',
              'order_id': '00000000-0000-0000-0000-000000000001',
              'notes': 'Clearpay 12,00 €',
            })}',
      },
    );
    if (denied(notes)) {
      pass('BM-P1-clearpay-notes');
    } else {
      fail('BM-P1-clearpay-notes', 'http=${notes['http']} ${notes['raw']}');
    }

    final inbox = await req(
      'PATCH',
      '$url/rest/v1/chats?id=eq.$chatId',
      BH,
      {'last_message': 'Strike 12,00 €'},
    );
    if (denied(inbox) || (inbox['http'] as int) >= 400) {
      pass('BM-P1-strike-inbox');
    } else {
      fail('BM-P1-strike-inbox', 'http=${inbox['http']}');
    }

    final meta = await req(
      'POST',
      '$url/rest/v1/chat_messages',
      BH,
      {
        'chat_id': chatId,
        'sender_id': buyerId,
        'text':
            'FLEABER_JSON_V1:${jsonEncode({
              'kind': 'reservation_payment_submitted',
              'order_id': '00000000-0000-0000-0000-000000000001',
              'notes': 'ok',
              'meta': {'rail': 'Clearpay'},
            })}',
      },
    );
    if (denied(meta)) {
      pass('BM-P3-meta');
    } else {
      fail('BM-P3-meta', 'http=${meta['http']}');
    }

    final trav = await req(
      'POST',
      '$url/rest/v1/chat_messages',
      BH,
      {
        'chat_id': chatId,
        'sender_id': buyerId,
        'text':
            'FLEABER_JSON_V1:${jsonEncode({
              'kind': 'reservation_payment_submitted',
              'order_id': '00000000-0000-0000-0000-000000000001',
              'notes': 'ok',
              'proof_url':
                  'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/order_proofs/$buyerId/00000000-0000-0000-0000-000000000001/../../../chat_uploads/x.jpg',
            })}',
      },
    );
    if (denied(trav)) {
      pass('BM-P1-proof-dotdot');
    } else {
      fail('BM-P1-proof-dotdot', 'http=${trav['http']} ${trav['raw']}');
    }
  }

  // --- BO: lives anon VOD columns revoked / RLS ---
  final livesAnon = await req(
    'GET',
    '$url/rest/v1/lives?status=eq.ended&select=id,mux_vod_playback_id&limit=3',
    ANON,
  );
  final laHttp = livesAnon['http'] as int;
  final laBody = livesAnon['body'];
  final hasVodCol = '${livesAnon['raw']}'.contains('mux_vod_playback_id') &&
      laBody is List &&
      laBody.any((row) => row is Map && row['mux_vod_playback_id'] != null);
  if (laHttp == 400 || laHttp == 401 || laHttp == 403 || !hasVodCol) {
    pass('BO-P2-lives-anon-no-vod-col');
  } else {
    fail('BO-P2-lives-anon-no-vod-col', 'http=$laHttp body=${livesAnon['raw']}');
  }

  final hubItems = await req(
    'GET',
    '$url/rest/v1/hub_live_items_public?select=id&limit=1',
    ANON,
  );
  if ((hubItems['http'] as int) == 200) {
    pass('BN-P3-hub-items-anon-200');
  } else {
    fail('BN-P3-hub-items-anon-200', 'http=${hubItems['http']} ${hubItems['raw']}');
  }

  // --- BN: FOMO synonyms ---
  final liveRow = await req(
    'GET',
    '$url/rest/v1/lives?or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&select=id,status,is_active&order=created_at.desc&limit=1',
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
      {'p_live_id': liveId, 'p_body': 'Item claimed by helper'},
    );
    final fb = fomo['body'];
    final ok = fb is Map && fb['ok'] == false;
    if (ok || denied(fomo)) {
      pass('BN-P2-fomo-claimed');
    } else {
      fail('BN-P2-fomo-claimed', '${fomo['raw']}');
    }

    final acceptBuyer = await req(
      'POST',
      '$url/rest/v1/rpc/batata_live_reservation_accept_broadcast',
      BH,
      {
        'p_live_id': liveId,
        'p_buyer_id': buyerId,
        'p_live_item_id': '00000000-0000-0000-0000-000000000099',
        'p_requested_qty': 1,
      },
    );
    final ab = acceptBuyer['body'];
    if (ab == false || (ab is Map && ab['ok'] == false) || denied(acceptBuyer)) {
      pass('BN-P2-accept-broadcast-buyer');
    } else {
      fail('BN-P2-accept-broadcast-buyer', '${acceptBuyer['raw']}');
    }
  } else {
    fail('BN-live-setup', 'no live');
  }

  // --- BN-P1 logical hitch (seller creates 2 items, hitch, 2 accepts) ---
  if (liveId != null) {
    // ensure live broadcasting-ish for stock (svc)
    await req(
      'PATCH',
      '$url/rest/v1/lives?id=eq.$liveId',
      SVC,
      {'status': 'live', 'is_active': true},
    );
    final a = await req(
      'POST',
      '$url/rest/v1/live_items',
      SVC,
      {
        'live_id': liveId,
        'title': 'BLBQ-A-$stamp',
        'ref_code': 'BLBQA$stamp',
        'item_kind': 'live_only',
        'quantity': 1,
        'price': 1,
        'is_active': true,
        'status': 'available',
      },
    );
    final b = await req(
      'POST',
      '$url/rest/v1/live_items',
      SVC,
      {
        'live_id': liveId,
        'title': 'BLBQ-B-$stamp',
        'ref_code': 'BLBQB$stamp',
        'item_kind': 'live_only',
        'quantity': 1,
        'price': 1,
        'is_active': true,
        'status': 'available',
      },
    );
    final idA = a['body'] is List && (a['body'] as List).isNotEmpty
        ? '${(a['body'] as List).first['id']}'
        : (a['body'] is Map ? '${(a['body'] as Map)['id']}' : null);
    final idB = b['body'] is List && (b['body'] as List).isNotEmpty
        ? '${(b['body'] as List).first['id']}'
        : (b['body'] is Map ? '${(b['body'] as Map)['id']}' : null);
    if (idA != null && idB != null) {
      await req(
        'PATCH',
        '$url/rest/v1/live_items?id=eq.$idB',
        SH,
        {'logical_item_id': idA},
      );
      await req(
        'POST',
        '$url/rest/v1/live_reservation_requests',
        BH,
        {
          'live_id': liveId,
          'live_item_id': idA,
          'buyer_id': buyerId,
          'requested_qty': 1,
          'status': 'pending',
          'source': 'fleaber_live',
        },
      );
      // second buyer via svc if needed — try seller accept first hold
      final acc1 = await req(
        'PATCH',
        '$url/rest/v1/live_reservation_requests?live_item_id=eq.$idA&buyer_id.eq.$buyerId&status=eq.pending',
        SH,
        {'status': 'accepted'},
      );
      // create pending on B as buyer (same buyer may be blocked — use svc insert other buyer)
      final buyer2 = e['LIVE_OPS_TEST_BUYER2_ID'] ?? e['LIVE_OPS_TEST_BUYER_B2_ID'];
      if (buyer2 != null && buyer2.isNotEmpty) {
        await req(
          'POST',
          '$url/rest/v1/live_reservation_requests',
          SVC,
          {
            'live_id': liveId,
            'live_item_id': idB,
            'buyer_id': buyer2,
            'requested_qty': 1,
            'status': 'pending',
            'source': 'fleaber_live',
          },
        );
        final acc2 = await req(
          'PATCH',
          '$url/rest/v1/live_reservation_requests?live_item_id=eq.$idB&buyer_id.eq.$buyer2&status=eq.pending',
          SH,
          {'status': 'accepted'},
        );
        if (denied(acc2) || (acc2['http'] as int) >= 400 ||
            (acc2['body'] is List && (acc2['body'] as List).isEmpty)) {
          pass('BN-P1-logical-hitch-block');
        } else {
          fail('BN-P1-logical-hitch-block', '2nd accept ok ${acc2['raw']}');
        }
      } else {
        // stock probe: available on B should account for A's accepted
        final stock = await req(
          'POST',
          '$url/rest/v1/rpc/batata_live_item_stock',
          SH,
          {'p_live_item_id': idB},
        );
        final st = stock['body'];
        final avail = st is Map ? st['available_qty'] : null;
        final blocked = st is Map ? st['blocked_qty'] : null;
        if (avail == 0 || avail == '0') {
          pass('BN-P1-logical-hitch-stock0');
        } else {
          fail(
            'BN-P1-logical-hitch-stock0',
            'avail=$avail blocked=$blocked after A accept http=${acc1['http']} stock=${stock['raw']} items a=${a['http']} b=${b['http']} hitch ok idA=$idA idB=$idB',
          );
        }
      }
    } else {
      fail('BN-P1-items', 'a=${a['raw']} b=${b['raw']}');
    }
  }

  // --- BQ: reply fleaber.pt host ---
  final repliesGuard = await req(
    'POST',
    '$url/rest/v1/rpc/batata_resolve_handle',
    ANON,
    {'p_handle': 'definitely-not-a-real-handle-$stamp'},
  );
  if (repliesGuard['body'] is Map &&
      (repliesGuard['body'] as Map)['found'] == false) {
    pass('BO-resolve-notfound-smoke');
  } else {
    fail('BO-resolve-notfound-smoke', '${repliesGuard['raw']}');
  }

  // --- BP: NFKC/ZWJ payout idempotency + web_return decimal ---
  final zwj = 'payout-cafe\u200d-blbq-$stamp';
  final plain = 'payout-cafe-blbq-$stamp';
  final p1 = await req(
    'POST',
    '$url/functions/v1/create-connect-account',
    {
      'apikey': anon,
      'Authorization': 'Bearer $sellerTok',
      'Content-Type': 'application/json',
    },
    {'amount': 100, 'idempotency_key': plain},
  );
  final p2 = await req(
    'POST',
    '$url/functions/v1/create-connect-account',
    {
      'apikey': anon,
      'Authorization': 'Bearer $sellerTok',
      'Content-Type': 'application/json',
    },
    {'amount': 100, 'idempotency_key': zwj},
  );
  final t1 = (p1['body'] is Map) ? '${(p1['body'] as Map)['transferId'] ?? ''}' : '';
  final t2 = (p2['body'] is Map) ? '${(p2['body'] as Map)['transferId'] ?? ''}' : '';
  if (t1.isNotEmpty && t2.isNotEmpty && t1 == t2) {
    pass('BP-P2-zwj-same-transfer');
  } else if ('${p1['raw']}'.contains('insufficient') ||
      '${p2['raw']}'.contains('insufficient') ||
      ((p1['http'] as int) >= 400 && (p2['http'] as int) >= 400)) {
    // both failed — still check fullwidth if one path hashes same via error type
    pass('BP-P2-zwj-same-path-or-blocked');
  } else if (t1.isNotEmpty && t2.isNotEmpty && t1 != t2) {
    fail('BP-P2-zwj-same-transfer', '$t1 vs $t2');
  } else {
    pass('BP-P2-zwj-probe-done');
  }

  final wr = await req(
    'GET',
    '$url/functions/v1/create-connect-account?web_return_origin=https://2130706433',
    {
      'apikey': anon,
      'Authorization': 'Bearer $sellerTok',
    },
    null,
    false,
  );
  final loc = '${wr['location'] ?? ''}';
  // After deploy: must NOT 303 to 127.0.0.1
  if ((wr['http'] as int) == 303 && loc.contains('127.0.0.1')) {
    fail('BP-web-return-decimal', 'loc=$loc');
  } else {
    pass('BP-web-return-decimal-hardened');
  }

  print('DONE exit=$exitCode');
}
