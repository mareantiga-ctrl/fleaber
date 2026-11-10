// ignore_for_file: avoid_print
/// Pass 2 — buyer2 fixture, copy-overwrite, %2e%2e sign, review stars, BD verify
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../live_ops_staging_client.dart';

const prefix = 'RTAC-20260901T1825';
const chatId = '4e89082a-a4f0-428e-9dad-5e4889a03715';
const paidOid = '8d22af32-c0d6-4877-b04c-def5175338bb';
const resOid = '60d32dc2-2d6f-4236-8905-9d960a240a79';
const offerId = '3fec2a14-7292-414d-ae7c-1fdef6fb82ac';
const proofPath =
    'order_proofs/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/8d22af32-c0d6-4877-b04c-def5175338bb/RTAC-20260901T1825-a.png';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
]) async {
  final encoded = body == null ? null : jsonEncode(body);
  late http.Response r;
  final uri = Uri.parse(u);
  switch (method) {
    case 'POST':
      r = await http.post(uri, headers: h, body: encoded);
      break;
    case 'PATCH':
      r = await http.patch(uri, headers: h, body: encoded);
      break;
    case 'DELETE':
      r = await http.delete(uri, headers: h);
      break;
    default:
      r = await http.get(uri, headers: h);
  }
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body.length > 400 ? '${r.body.substring(0, 400)}…' : r.body;
  }
  return {'http': r.statusCode, 'body': p};
}

String brief(Map<String, dynamic> r) {
  final b = r['body'];
  var s = b is Map
      ? '${b['message'] ?? b['hint'] ?? b['code'] ?? b['error'] ?? b}'
      : '$b';
  if (s.length > 280) s = '${s.substring(0, 280)}…';
  return 'http=${r['http']} $s';
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  Map<String, String> h(String tok) => {
        'apikey': anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  final BH = h(buyerTok);
  final SH = h(sellerTok);
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final out = <String, dynamic>{};

  // BD verify
  final order = await req(
    'GET',
    '$url/rest/v1/orders?id=eq.$resOid&select=id,status,amount_paid_cents,price_total,proof_url',
    SVC,
  );
  final paid = await req(
    'GET',
    '$url/rest/v1/orders?id=eq.$paidOid&select=id,status,amount_paid_cents,stripe_payment_intent_id',
    SVC,
  );
  final offer = await req(
    'GET',
    '$url/rest/v1/product_offers?id=eq.$offerId&select=id,status,amount',
    SVC,
  );
  out['order_hold'] = order['body'];
  out['order_paid'] = paid['body'];
  out['offer'] = offer['body'];
  print('HOLD ${brief(order)}');
  print('PAID ${brief(paid)}');
  print('OFFER ${brief(offer)}');

  // msg 985 still there?
  final m985 = await req(
    'GET',
    '$url/rest/v1/chat_messages?id=eq.985&select=id,text',
    SVC,
  );
  out['msg985'] = m985['body'];
  print('MSG985 ${brief(m985)}');

  // created_at after patch
  final ca = await req(
    'GET',
    '$url/rest/v1/chat_messages?id=eq.1004&select=id,created_at,text',
    SVC,
  );
  out['msg1004_created_at'] = ca['body'];

  // copy overwrite onto SAME path
  final copyOver = await req('POST', '$url/storage/v1/object/copy', BH, {
    'bucketId': 'fleaber_private',
    'sourceKey':
        'order_proofs/$buyerId/$paidOid/${prefix}-copy.png',
    'destinationKey': proofPath,
  });
  out['copy_overwrite'] = {'http': copyOver['http'], 'body': copyOver['body']};
  print('COPY_OVER ${brief(copyOver)}');

  // sign %2e%2e path
  final trav =
      'chat_uploads/$buyerId/%2e%2e/order_proofs/$buyerId/$paidOid/${prefix}-a.png';
  final signTrav = await req(
    'POST',
    '$url/storage/v1/object/sign/fleaber_private/$trav',
    BH,
    {'expiresIn': 60},
  );
  out['sign_pct_dotdot'] = {'http': signTrav['http'], 'body': signTrav['body']};
  print('SIGN_TRAV ${brief(signTrav)}');

  final signNorm = await req(
    'POST',
    '$url/storage/v1/object/sign/fleaber_private/chat_uploads/$buyerId/../order_proofs/$buyerId/$paidOid/${prefix}-a.png',
    BH,
    {'expiresIn': 60},
  );
  out['sign_literal_dotdot'] = {
    'http': signNorm['http'],
    'body': signNorm['body']
  };
  print('SIGN_DOTDOT ${brief(signNorm)}');

  // review fixture + fake stars card
  final rev = await req('POST', '$url/rest/v1/reviews', SVC, {
    'order_id': paidOid,
    'buyer_id': buyerId,
    'target_id': sellerId,
    'stars': 5,
    'comment': '$prefix genuine',
    'author_role': 'comprador',
    'target_type': 'seller',
  });
  out['review_insert'] = {'http': rev['http'], 'body': rev['body']};
  print('REVIEW ${brief(rev)}');
  final stars = await req('POST', '$url/rest/v1/chat_messages', BH, {
    'chat_id': chatId,
    'receiver_id': sellerId,
    'text':
        'FLEABER_JSON_V1:${jsonEncode({
          'kind': 'order_review_submitted',
          'order_id': paidOid,
          'author_role': 'comprador',
          'stars': 1,
        })}',
  });
  out['review_card'] = {'http': stars['http'], 'id': (stars['body'] is List && (stars['body'] as List).isNotEmpty) ? (stars['body'] as List).first['id'] : null, 'brief': brief(stars)};
  print('REVIEW_CARD ${brief(stars)}');

  // buyer2 via admin
  final email = 'rtac-b2-${DateTime.now().millisecondsSinceEpoch}@example.test';
  final b2id = await sb.createAdminUser(
    email: email,
    password: 'Testeteste1!',
    userMetadata: {'handle': 'rtac_b2'},
  );
  final b2tok = await sb.signIn(email: email, password: 'Testeteste1!');
  final B2H = h(b2tok);
  out['buyer2_id'] = b2id;

  final read = await req(
    'GET',
    '$url/rest/v1/chat_messages?chat_id=eq.$chatId&select=id&limit=5',
    B2H,
  );
  out['b2_read'] = {'http': read['http'], 'n': read['body'] is List ? (read['body'] as List).length : -1, 'brief': brief(read)};
  print('B2_READ ${brief(read)}');

  final write = await req('POST', '$url/rest/v1/chat_messages', B2H, {
    'chat_id': chatId,
    'text': '$prefix b2 inject',
  });
  out['b2_write'] = {'http': write['http'], 'brief': brief(write)};
  print('B2_WRITE ${brief(write)}');

  final signB2 = await req(
    'POST',
    '$url/storage/v1/object/sign/fleaber_private/$proofPath',
    B2H,
    {'expiresIn': 60},
  );
  out['b2_sign'] = {'http': signB2['http'], 'brief': brief(signB2)};
  print('B2_SIGN ${brief(signB2)}');

  final listB2 = await req('POST', '$url/storage/v1/object/list/fleaber_private', B2H, {
    'prefix': 'order_proofs/$buyerId',
    'limit': 10,
  });
  out['b2_list'] = {'http': listB2['http'], 'brief': brief(listB2)};
  print('B2_LIST ${brief(listB2)}');

  final chatsB2 = await req(
    'GET',
    '$url/rest/v1/chats?id=eq.$chatId&select=id,last_message',
    B2H,
  );
  out['b2_chat'] = {'http': chatsB2['http'], 'brief': brief(chatsB2)};
  print('B2_CHAT ${brief(chatsB2)}');

  // seller sign buyer proof (counterparty — expected?)
  final signS = await req(
    'POST',
    '$url/storage/v1/object/sign/fleaber_private/$proofPath',
    SH,
    {'expiresIn': 60},
  );
  out['seller_sign_buyer_proof'] = {'http': signS['http'], 'brief': brief(signS)};
  print('SELLER_SIGN ${brief(signS)}');

  // edge with richer body
  for (final body in [
    {'orderId': paidOid},
    {'order_id': paidOid},
    {'order_id': paidOid, 'product_id': '0a92077c-baca-4121-b8ac-10e1a08d5b44'},
  ]) {
    final er = await sb.invokeEdge('create-payment-intent', body,
        accessToken: buyerTok);
    print('EDGE ${er.statusCode} ${er.body.length > 180 ? er.body.substring(0, 180) : er.body}');
    out['edge_${body.keys.join("_")}'] = {
      'http': er.statusCode,
      'body': er.body.length > 300 ? '${er.body.substring(0, 300)}…' : er.body
    };
  }

  File('tool/redteam_blind_ac_20260901T1825/pass2.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print('WROTE pass2.json');
}
