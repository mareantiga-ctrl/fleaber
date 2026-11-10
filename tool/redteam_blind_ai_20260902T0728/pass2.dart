// ignore_for_file: avoid_print
/// pass2 — PATCH/DELETE card real, signed URL correcto, GET traversal, review
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
]) async {
  late http.Response r;
  if (method == 'POST') {
    r = await http.post(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body));
  } else if (method == 'PATCH') {
    r = await http.patch(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body));
  } else if (method == 'DELETE') {
    r = await http.delete(Uri.parse(u), headers: h);
  } else {
    r = await http.get(Uri.parse(u), headers: h);
  }
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'raw': r.body};
}

void main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final buyerTok = await LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  ).signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  ).signIn(
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

  final out = <String, dynamic>{};

  // PATCH real FLEABER card 1143 (seller-owned cancel outcome)
  final patch = await req(
    'PATCH',
    '$url/rest/v1/chat_messages?id=eq.1143',
    SH,
    {'text': 'mutated'},
  );
  out['patch_1143'] = {'http': patch['http'], 'raw': '${patch['raw']}'.substring(0, '${patch['raw']}'.length.clamp(0, 200))};

  final patchB = await req(
    'PATCH',
    '$url/rest/v1/chat_messages?id=eq.1143',
    BH,
    {'text': 'mutated'},
  );
  out['patch_1143_buyer'] = {'http': patchB['http'], 'raw': '${patchB['raw']}'.substring(0, '${patchB['raw']}'.length.clamp(0, 200))};

  final del = await req('DELETE', '$url/rest/v1/chat_messages?id=eq.1143', SH);
  final still = await req(
    'GET',
    '$url/rest/v1/chat_messages?id=eq.1143&select=id,text',
    SH,
  );
  out['delete_1143'] = {
    'http': del['http'],
    'raw': '${del['raw']}'.substring(0, '${del['raw']}'.length.clamp(0, 200)),
    'still': still['body'],
  };

  // unsigned object URL vs signed (correct storage path)
  const path =
      'order_proofs/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/ffc2bb9a-1991-4811-acb4-e5feff94cc10';
  // list objects under prefix
  final listed = await req(
    'POST',
    '$url/storage/v1/object/list/fleaber_private',
    BH,
    {'prefix': path, 'limit': 5},
  );
  out['list_proofs'] = {'http': listed['http'], 'body': listed['body']};

  String? realFile;
  if (listed['body'] is List && (listed['body'] as List).isNotEmpty) {
    final first = (listed['body'] as List).first;
    if (first is Map) realFile = first['name']?.toString();
  }

  if (realFile != null) {
    final full = '$path/$realFile';
    final sign = await req(
      'POST',
      '$url/storage/v1/object/sign/fleaber_private/$full',
      BH,
      {'expiresIn': 3600},
    );
    out['sign'] = {'http': sign['http'], 'body': sign['body']};
    final sm = sign['body'];
    String? signedUrl;
    if (sm is Map) {
      final s = '${sm['signedURL'] ?? sm['signedUrl'] ?? ''}';
      if (s.startsWith('http')) {
        signedUrl = s;
      } else if (s.startsWith('/storage')) {
        signedUrl = '$url$s';
      } else if (s.isNotEmpty) {
        signedUrl = '$url/storage/v1$s';
      }
    }
    out['signed_url_constructed'] = signedUrl;
    if (signedUrl != null) {
      final chatId = '1b1250c4-8c4e-43a6-949b-16b8b6b7b496';
      final reserved = 'ffc2bb9a-1991-4811-acb4-e5feff94cc10';
      final postSigned = await req('POST', '$url/rest/v1/chat_messages', BH, {
        'chat_id': chatId,
        'text':
            'FLEABER_JSON_V1:${jsonEncode({'kind': 'reservation_payment_submitted', 'order_id': reserved, 'proof_url': signedUrl})}',
      });
      out['post_correct_signed'] = {
        'http': postSigned['http'],
        'raw': '${postSigned['raw']}'.substring(0, '${postSigned['raw']}'.length.clamp(0, 240)),
      };

      final unsigned =
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/$full';
      final postUn = await req('POST', '$url/rest/v1/chat_messages', BH, {
        'chat_id': chatId,
        'text':
            'FLEABER_JSON_V1:${jsonEncode({'kind': 'reservation_payment_submitted', 'order_id': reserved, 'proof_url': unsigned})}',
      });
      out['post_unsigned_object'] = {
        'http': postUn['http'],
        'raw': '${postUn['raw']}'.substring(0, '${postUn['raw']}'.length.clamp(0, 240)),
      };
    }
  }

  // GET traversal URL
  final trav = await req(
    'GET',
    'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/../public/x.png',
    {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
    },
  );
  out['get_traversal'] = {
    'http': trav['http'],
    'raw': '${trav['raw']}'.substring(0, '${trav['raw']}'.length.clamp(0, 160)),
  };

  // review insert
  final paid = '6fe7add4-c087-4ad1-9619-4520a4b7273a';
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final rev = await req('POST', '$url/rest/v1/reviews', BH, {
    'target_id': sellerId,
    'buyer_id': buyerId,
    'stars': 5,
    'comment': 'RTAI pass2',
    'target_type': 'seller',
    'author_role': 'comprador',
    'order_id': paid,
  });
  out['review_insert'] = {
    'http': rev['http'],
    'raw': '${rev['raw']}'.substring(0, '${rev['raw']}'.length.clamp(0, 240)),
  };

  final f = File('tool/redteam_blind_ai_20260902T0728/pass2.json');
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(const JsonEncoder.withIndent('  ').convert(out));
}
