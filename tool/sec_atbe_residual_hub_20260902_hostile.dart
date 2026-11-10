// ignore_for_file: avoid_print
/// Residual Hub/CDN/FOMO — dart run tool/sec_atbe_residual_hub_20260902_hostile.dart
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
    return '${(body.first as Map)['id']}'.trim();
  }
  if (body is Map && body['id'] != null) return '${body['id']}'.trim();
  return null;
}

void pass(String id) => print('PASS $id');
void fail(String id, String why) {
  print('FAIL $id: $why');
  exitCode = 1;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: wrong project');
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
  };

  // Ensure seller hub_published for view join (não alterar handle QA)
  await req('PATCH', '$url/rest/v1/profiles?id=eq.$sellerId', SVC, {
    'hub_published': true,
  });

  // BC — scheduled with fake VOD id must not leak vod/playback in Hub
  final sched = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'title': 'ATBE residual sched $stamp',
    'status': 'scheduled',
    'is_active': false,
    'mux_playback_id': 'fakePlaySched$stamp',
    'mux_vod_playback_id': 'fakeVodSched$stamp',
  });
  final schedId = idOf(sched['body']);
  if (schedId == null) {
    fail('seed-sched', '${sched['raw']}');
  } else {
    final hub = await req(
      'GET',
      '$url/rest/v1/hub_lives_public?id=eq.$schedId&select=status,mux_playback_id,mux_vod_playback_id',
      ANON,
    );
    final row = (hub['body'] is List && (hub['body'] as List).isNotEmpty)
        ? (hub['body'] as List).first as Map
        : null;
    if (row == null) {
      fail('BC-sched-no-vod-leak', 'not in hub: ${hub['raw']}');
    } else if (row['mux_vod_playback_id'] != null || row['mux_playback_id'] != null) {
      fail('BC-sched-no-vod-leak', 'leaked ids: $row');
    } else {
      pass('BC-sched-no-vod-leak');
    }
  }

  // BC — draft+active must not appear in Hub
  final draft = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'title': 'ATBE residual draft $stamp',
    'status': 'draft',
    'is_active': true,
    'mux_vod_playback_id': 'fakeVodDraft$stamp',
  });
  final draftId = idOf(draft['body']);
  if (draftId == null) {
    fail('seed-draft', '${draft['raw']}');
  } else {
    final hub = await req(
      'GET',
      '$url/rest/v1/hub_lives_public?id=eq.$draftId&select=id',
      ANON,
    );
    final n = hub['body'] is List ? (hub['body'] as List).length : -1;
    if (n == 0) {
      pass('BC-draft-not-in-hub');
    } else {
      fail('BC-draft-not-in-hub', 'n=$n ${hub['raw']}');
    }
  }

  // BC — ended keeps VOD
  final ended = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'title': 'ATBE residual ended $stamp',
    'status': 'ended',
    'is_active': false,
    'mux_vod_playback_id': 'fakeVodEnded$stamp',
    'mux_playback_id': 'fakePlayEnded$stamp',
  });
  final endedId = idOf(ended['body']);
  if (endedId == null) {
    fail('seed-ended', '${ended['raw']}');
  } else {
    final hub = await req(
      'GET',
      '$url/rest/v1/hub_lives_public?id=eq.$endedId&select=mux_playback_id,mux_vod_playback_id',
      ANON,
    );
    final row = (hub['body'] is List && (hub['body'] as List).isNotEmpty)
        ? (hub['body'] as List).first as Map
        : null;
    if (row == null) {
      fail('BC-ended-vod-kept', 'missing from hub');
    } else if (row['mux_vod_playback_id'] != 'fakeVodEnded$stamp') {
      fail('BC-ended-vod-kept', 'vod=${row['mux_vod_playback_id']}');
    } else if (row['mux_playback_id'] != null) {
      fail('BC-ended-vod-kept', 'live play leaked on ended: $row');
    } else {
      pass('BC-ended-vod-kept');
    }
  }

  // Stock JWT on ended item → not_found
  if (endedId != null) {
    final li = await req('POST', '$url/rest/v1/live_items', SVC, {
      'live_id': endedId,
      'title': 'ATBE stock $stamp',
      'ref_code': 'ATBE-$stamp',
      'price': 5.0,
      'quantity': 1,
      'is_active': true,
      'status': 'reserved_full',
      'item_kind': 'live_only',
    });
    final liId = idOf(li['body']);
    if (liId == null) {
      fail('BC-jwt-stock-ended', 'no item ${li['raw']}');
    } else {
      final stock = await req(
        'POST',
        '$url/rest/v1/rpc/batata_live_item_stock',
        {
          'apikey': anon,
          'Authorization': 'Bearer $buyerTok',
          'Content-Type': 'application/json',
        },
        {'p_live_item_id': liId},
      );
      final raw = '${stock['raw']}';
      if (raw.contains('live_item_not_found') || raw.contains('"ok":false') || raw.contains('"ok": false')) {
        pass('BC-jwt-stock-ended');
      } else {
        fail('BC-jwt-stock-ended', raw);
      }
    }
  }

  // AV — system_message «comprou» blocked
  final liveAir = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'title': 'ATBE residual live $stamp',
    'status': 'live',
    'is_active': true,
  });
  final liveId = idOf(liveAir['body']);
  if (liveId == null) {
    fail('AV-comprou-blocked', 'no live ${liveAir['raw']}');
  } else {
    final msg = await req(
      'POST',
      '$url/rest/v1/rpc/batata_live_system_message',
      SH,
      {
        'p_live_id': liveId,
        'p_body': '✅ Comprador X comprou Ref ABC',
        'p_sender_label': 'FOMO',
      },
    );
    final raw = '${msg['raw']}';
    if (raw.contains('purchase_announce_via_broadcast_only') ||
        raw.contains('"ok":false') ||
        raw.contains('"ok": false')) {
      pass('AV-comprou-blocked');
    } else {
      fail('AV-comprou-blocked', raw);
    }
    // Non-purchase system still OK
    final okMsg = await req(
      'POST',
      '$url/rest/v1/rpc/batata_live_system_message',
      SH,
      {
        'p_live_id': liveId,
        'p_body': 'Bem-vindos ao directo ATBE',
        'p_sender_label': 'Sistema',
      },
    );
    if ('${okMsg['raw']}'.contains('"ok":true') || '${okMsg['raw']}'.contains('"ok": true')) {
      pass('AV-system-ok-non-purchase');
    } else {
      fail('AV-system-ok-non-purchase', '${okMsg['raw']}');
    }
  }

  // Tip settle forge — no Stripe oracle
  final tip = await req(
    'GET',
    '$url/functions/v1/create-live-tip-checkout?session_id=cs_test_aaa_forged&checkout_return=success',
    ANON,
  );
  final tipRaw = '${tip['raw']}';
  if (tipRaw.contains('No such checkout') || tipRaw.contains('cs_test_aaa')) {
    fail('BC-tip-settle-oracle', tipRaw);
  } else if (tipRaw.toLowerCase().contains('ainda não confirmado') ||
      tipRaw.toLowerCase().contains('ainda nao confirmado') ||
      tip['http'] == 400) {
    pass('BC-tip-settle-oracle');
  } else {
    fail('BC-tip-settle-oracle', 'unexpected: $tipRaw');
  }

  // Cleanup
  for (final id in [schedId, draftId, endedId, liveId]) {
    if (id != null) {
      await req('PATCH', '$url/rest/v1/lives?id=eq.$id', SVC, {
        'status': 'ended',
        'is_active': false,
      });
    }
  }

  print(exitCode == 0 ? 'ALL PASS residual hub' : 'SOME FAIL residual hub');
}
