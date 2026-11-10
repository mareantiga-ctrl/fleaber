// ignore_for_file: avoid_print
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
      ? await http.post(Uri.parse(u), headers: h, body: jsonEncode(body))
      : method == 'PATCH'
          ? await http.patch(Uri.parse(u), headers: h, body: jsonEncode(body))
          : method == 'DELETE'
              ? await http.delete(Uri.parse(u), headers: h)
              : await http.get(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body.length > 500 ? r.body.substring(0, 500) : r.body};
}

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return '${(body.first as Map)['id']}';
  }
  if (body is Map) return '${body['id']}';
  return null;
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
  final extraEmail = 'rtg3c.${DateTime.now().millisecondsSinceEpoch}@staging.fleaber.lab';
  final extraId = await sb.createAdminUser(
    email: extraEmail,
    password: 'RtgLab!20260829',
  );
  final extraTok = await sb.signIn(email: extraEmail, password: 'RtgLab!20260829');
  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final XH = {
    'apikey': anon,
    'Authorization': 'Bearer $extraTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final AH = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final probes = <Map<String, dynamic>>[];
  void add(String id, Map<String, dynamic> r, {String? note}) {
    probes.add({'id': id, 'http': r['http'], 'text': r['text'], 'note': note});
    stdout.writeln('$id http=${r['http']} ${r['text']}');
  }

  add('chats.buyer', await req('GET', '$url/rest/v1/chats?select=id,user_a,user_b,product_id&limit=10', BH));
  add('chats.extra', await req('GET', '$url/rest/v1/chats?select=id,user_a,user_b&limit=10', XH));
  add('chats.anon', await req('GET', '$url/rest/v1/chats?select=id,user_a,user_b&limit=5', AH));

  final chats = await req('GET', '$url/rest/v1/chats?select=id,user_a,user_b&limit=20', BH);
  String? ownChat;
  if (chats['body'] is List) {
    for (final c in chats['body'] as List) {
      if (c is Map) {
        ownChat = '${c['id']}';
        break;
      }
    }
  }
  if (ownChat != null) {
    add('msgs.extra_on_lab_chat', await req(
      'GET',
      '$url/rest/v1/chat_messages?chat_id=eq.$ownChat&select=id,chat_id,sender_id,text&limit=5',
      XH,
    ));
    add('msg.spoof', await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': ownChat,
      'sender_id': sellerId,
      'receiver_id': buyerId,
      'text': 'rtg3c spoof',
    }));
  }

  add('raffle.winners.insert', await req('POST', '$url/rest/v1/live_raffle_winners', BH, {
    'live_id': buyerId,
    'user_id': buyerId,
    'prize_title': 'rtg3c',
  }));
  add('raffle.entries.insert', await req('POST', '$url/rest/v1/live_raffle_entries', BH, {
    'live_id': buyerId,
    'user_id': extraId,
    'tickets': 99,
  }));
  add('raffle.create_prize.buyer', await req(
    'POST',
    '$url/rest/v1/rpc/batata_create_raffle_prize_order',
    BH,
    {'p_live_id': buyerId, 'p_winner_id': buyerId, 'p_qty': 1},
  ));

  add('bundle.insert.accepted', await req('POST', '$url/rest/v1/product_bundles', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_ids': ['00000000-0000-0000-0000-000000000001'],
    'status': 'accepted',
    'total_price': 1,
  }));

  add('disputes.extra.select', await req(
    'GET',
    '$url/rest/v1/order_disputes?select=id,order_id,buyer_id,status&limit=10',
    XH,
  ));

  // leftover mux
  add('mux.end', await req(
    'PATCH',
    '$url/rest/v1/lives?id=eq.ae04a7c9-c519-4ab0-97ff-6447ec835f48',
    SVC,
    {'status': 'ended', 'is_active': false},
  ));

  File('tool/redteam_blind_g_20260829/pass3c_raw.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({'probes': probes}));

  await http.delete(Uri.parse('$url/auth/v1/admin/users/$extraId'), headers: SVC);
}
