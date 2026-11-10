// ignore_for_file: avoid_print
/// PASS 3b — dual session, storage proofs, raffle seeds, race repeats, refund dual.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

void main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final otherSeller = '69104e91-6a00-40d9-a7c9-b1571422ae43';
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  final matrix = <Map<String, dynamic>>[];

  Future<http.Response> req(String method, String path,
      {String? token, Object? body, bool service = false}) {
    final headers = <String, String>{
      'apikey': service ? svc : anon,
      'Authorization': 'Bearer ${service ? svc : (token ?? anon)}',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
    final uri = Uri.parse('$url$path');
    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers);
      case 'POST':
        return http.post(uri, headers: headers, body: body == null ? null : jsonEncode(body));
      case 'PATCH':
        return http.patch(uri, headers: headers, body: body == null ? null : jsonEncode(body));
      default:
        throw StateError(method);
    }
  }

  void rec(String s, String a, String i, http.Response r) {
    matrix.add({
      'surface': s,
      'attack': a,
      'identity': i,
      'result': r.statusCode,
      'body': r.body.length > 1200 ? '${r.body.substring(0, 1200)}…' : r.body,
    });
    print('$i $s $a → ${r.statusCode} ${r.body.length > 200 ? r.body.substring(0, 200) : r.body}');
  }

  Future<http.Response> edge(String fn, Object body, {String? token}) {
    return http.post(
      Uri.parse('$url/functions/v1/$fn'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer ${token ?? anon}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
  }

  // dual session same pending order
  const oid = '1eee5383-20e0-4e8e-b34f-0f915c48cb65';
  final dual = await Future.wait([
    edge('create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': oid,
      'amount': 1,
      'shipping_method': 'hand',
    }, token: buyerTok),
    edge('create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': oid,
      'amount': 999999,
      'shipping_method': 'hand',
    }, token: buyerTok),
  ]);
  rec('edge/create-payment-intent', 'dual session same order A', 'buyer', dual[0]);
  rec('edge/create-payment-intent', 'dual session same order B', 'buyer', dual[1]);

  // raffle active seeds
  rec(
    'live_raffles',
    'SELECT active with draw_seed',
    'buyer',
    await req('GET',
        '/rest/v1/live_raffles?status=eq.active&select=id,seller_id,status,draw_seed,title&limit=20',
        token: buyerTok),
  );

  // storage proofs
  rec(
    'storage',
    'list order_proofs other seller',
    'buyer',
    await req('POST', '/storage/v1/object/list/chat_media', token: buyerTok, body: {
      'prefix': 'order_proofs/$otherSeller',
      'limit': 20,
    }),
  );
  rec(
    'storage',
    'list order_proofs other seller fleaber_private',
    'buyer',
    await req('POST', '/storage/v1/object/list/fleaber_private', token: buyerTok, body: {
      'prefix': 'order_proofs/$otherSeller',
      'limit': 20,
    }),
  );
  rec(
    'storage',
    'list order_disputes',
    'buyer',
    await req('POST', '/storage/v1/object/list/chat_media', token: buyerTok, body: {
      'prefix': 'order_disputes',
      'limit': 20,
    }),
  );
  rec(
    'storage',
    'GET public object other seller photo',
    'anon',
    await req(
      'GET',
      '/storage/v1/object/public/chat_media/product_photos/$otherSeller/1778588031250_0_scaled_1000000018.jpg',
    ),
  );
  rec(
    'storage',
    'GET authenticated object order_proofs other',
    'buyer',
    await req(
      'GET',
      '/storage/v1/object/chat_media/order_proofs/$otherSeller/x',
      token: buyerTok,
    ),
  );

  // refund dual on paid stripe order
  const paid = '6a3268c5-44ea-4a9e-b87e-b4ca13887131';
  final refs = await Future.wait([
    edge('refund-order', {'order_id': paid}, token: sellerTok),
    edge('refund-order', {'order_id': paid}, token: sellerTok),
  ]);
  rec('edge/refund-order', 'dual refund A', 'seller', refs[0]);
  rec('edge/refund-order', 'dual refund B', 'seller', refs[1]);
  rec('edge/refund-order', 'buyer refund paid', 'buyer',
      await edge('refund-order', {'order_id': paid}, token: buyerTok));

  // dispute
  rec(
    'order_disputes',
    'INSERT on own paid',
    'buyer',
    await req('POST', '/rest/v1/order_disputes', token: buyerTok, body: {
      'order_id': paid,
      'reason': 'outro',
      'description': 'hostile audit',
    }),
  );
  rec(
    'order_disputes',
    'INSERT third-party',
    'buyer',
    await req('POST', '/rest/v1/order_disputes', token: buyerTok, body: {
      'order_id': '92b6dc7f-209f-45ad-a8a1-20159fdddcbf',
      'reason': 'outro',
      'description': 'hostile',
    }),
  );

  // 10 rounds stock=1 two concurrent inserts
  final raceWins = <int>[];
  for (var round = 0; round < 10; round++) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final pr = jsonDecode((await req('POST', '/rest/v1/products', service: true, body: {
      'seller_id': sellerId,
      'title': 'RT-R$round-$stamp',
      'price': 5.0,
      'quantity': 1,
      'list_on_marketplace': false,
      'is_sold': false,
      'ref_code': 'RR$stamp',
    })).body);
    final pid = (pr is List) ? pr.first['id'] as String : (pr as Map)['id'] as String;
    final ins = await Future.wait([
      req('POST', '/rest/v1/orders', token: buyerTok, body: {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pid,
        'status': 'reserva_pendente',
        'quantity': 1,
        'payment_method': 'Pagamento na app',
        'shipping_method': 'hand',
      }),
      req('POST', '/rest/v1/orders', token: buyerTok, body: {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pid,
        'status': 'reserva_pendente',
        'quantity': 1,
        'payment_method': 'Pagamento na app',
        'shipping_method': 'hand',
      }),
    ]);
    var wins = 0;
    final ids = <String>[];
    for (final r in ins) {
      if (r.statusCode == 201) {
        wins++;
        final b = jsonDecode(r.body);
        if (b is List && b.isNotEmpty) ids.add(b.first['id'] as String);
      }
    }
    raceWins.add(wins);
    for (final id in ids) {
      await req('PATCH', '/rest/v1/orders?id=eq.$id', service: true, body: {'status': 'cancelado'});
    }
    print('race_round=$round wins=$wins');
  }

  // staff helper insert result
  rec(
    'seller_helpers',
    'INSERT self helper',
    'buyer',
    await req('POST', '/rest/v1/seller_helpers', token: buyerTok, body: {
      'seller_id': sellerId,
      'helper_user_id': buyerId,
      'display_name': 'h',
      'active': true,
      'invitation_status': 'accepted',
      'permissions': {'can_mark_items_sold': true},
    }),
  );

  // cleanup mb way pago leftover
  await req('PATCH', '/rest/v1/orders?id=eq.b31c1686-e3cc-4234-ac34-992c730c51dd',
      service: true, body: {'status': 'cancelado'});
  await req('PATCH', '/rest/v1/orders?id=eq.295610ed-818f-4913-a32b-76cadd76f1ad',
      service: true, body: {'status': 'cancelado'});

  File('tool/redteam_blind_indep_20260830/out/03_pass3b.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({'race_wins_per_round': raceWins, 'matrix': matrix}),
  );
  print('race_wins=$raceWins max=${raceWins.fold<int>(0, (a, b) => a > b ? a : b)}');
}
