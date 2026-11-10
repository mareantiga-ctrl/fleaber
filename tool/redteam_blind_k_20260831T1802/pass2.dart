// ignore_for_file: avoid_print
/// Pass 2 — K4/K6 leftovers: legacy plain receipt + kinds on MB WAY pago + mao release.
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
    r = await http.post(Uri.parse(u),
        headers: h, body: body == null ? null : jsonEncode(body));
  } else if (method == 'PATCH') {
    r = await http.patch(Uri.parse(u),
        headers: h, body: body == null ? null : jsonEncode(body));
  } else {
    r = await http.get(Uri.parse(u), headers: h);
  }
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body};
}

Map<String, dynamic>? firstMap(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
  return null;
}

void main() async {
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
  Map<String, String> H(String t) => {
        'apikey': anon,
        'Authorization': 'Bearer $t',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  final BH = H(buyerTok);
  final SH = H(sellerTok);
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  const chatId = '2852d2af-4f03-4d84-a0b2-fd472f0bf0cd';
  const maoOid = '916b1667-fb33-4216-a640-dda3dc22c861';
  const holdOid = 'a093d3ef-9ff6-4336-8f96-cccbaeaa9187';

  final out = <String, dynamic>{};

  Future<void> ins(String tag, Map<String, String> h, String text) async {
    final r = await req('POST', '$url/rest/v1/chat_messages', h, {
      'chat_id': chatId,
      'sender_id': h == SH ? sellerId : buyerId,
      'text': text,
      'is_read': false,
    });
    out[tag] = {'http': r['http'], 'body': r['body'], 'text_sent': text};
    stdout.writeln('$tag HTTP ${r['http']} ${r['text']}'.substring(
        0, ( '${r['http']} ${r['text']}'.length + tag.length + 6).clamp(0, 240)));
  }

  // Legacy plain receipt — UI _isLegacySeguroFleaberPaidPlainText
  await ins(
    'legacy_plain_unpaid_hold',
    BH,
    'Compra paga através do Seguro Fleaber (8888.88 €) [order:$holdOid]',
  );
  await ins(
    'legacy_plain_mao',
    BH,
    'Compra paga através do Seguro Fleaber (3.50 €) [order:$maoOid]',
  );
  await ins(
    'legacy_bag_plain',
    BH,
    'Compra em conjunto paga através do Seguro Fleaber (99.00 €)',
  );

  String card(String kind, String oid) =>
      'FLEABER_JSON_V1:${jsonEncode({'kind': kind, 'order_id': oid})}';

  await ins('json_completed_mao', BH, card('reservation_order_completed', maoOid));
  await ins('json_shipped_mao_seller', SH, card('reservation_order_shipped', maoOid));
  await ins('json_receipt_seller_mao', SH, card('reservation_seller_confirmed_receipt', maoOid));
  await ins('json_order_paid_mao', BH, card('order_paid', maoOid));
  await ins('json_raffle_awarded', BH, card('raffle_prize_awarded', maoOid));

  // mao release — platform funds should be 0
  final w0 = firstMap((await req(
    'GET',
    '$url/rest/v1/wallets?id=eq.$sellerId&select=balance',
    SVC,
  ))['body']);
  final rel = await req(
    'POST',
    '$url/rest/v1/rpc/batata_release_seller_wallet_for_order',
    BH,
    {'p_order_id': maoOid},
  );
  final w1 = firstMap((await req(
    'GET',
    '$url/rest/v1/wallets?id=eq.$sellerId&select=balance',
    SVC,
  ))['body']);
  final row = firstMap((await req(
    'GET',
    '$url/rest/v1/orders?id=eq.$maoOid&select=id,status,amount_paid_cents,wallet_release_processed_at,payment_method',
    SVC,
  ))['body']);
  out['mao_release'] = {
    'rpc': rel['body'],
    'http': rel['http'],
    'bal_before': w0?['balance'],
    'bal_after': w1?['balance'],
    'order': row,
  };
  stdout.writeln(
      'mao_release http=${rel['http']} rpc=${rel['body']} bal ${w0?['balance']}→${w1?['balance']} rel_at=${row?['wallet_release_processed_at']}');

  File('tool/redteam_blind_k_20260831T1802/pass2.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
}
