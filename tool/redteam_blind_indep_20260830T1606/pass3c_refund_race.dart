import 'dart:convert';
import 'dart:io';

import '../live_ops_staging_client.dart';

void main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final admin = LiveOpsStagingClient(
    url: url,
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final sellerJwt = await admin.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerJwt = await admin.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  const oid = 'e44e602e-ada0-4d64-a13f-f9c7746581cb';
  final before = await admin.select('orders', filter: 'id=eq.$oid', limit: 1);
  stdout.writeln('BEFORE ${jsonEncode({
    'status': before.first['status'],
    'paid': before.first['amount_paid_cents'],
    'refund': before.first['stripe_refund_id'],
    'pi': before.first['stripe_payment_intent_id'],
  })}');
  final w0s = (await admin.select('wallets', filter: 'id=eq.${envRequire(env, 'LIVE_OPS_TEST_SELLER_ID')}', limit: 1)).first['balance'];
  final w0b = (await admin.select('wallets', filter: 'id=eq.${envRequire(env, 'LIVE_OPS_TEST_BUYER_ID')}', limit: 1)).first['balance'];
  stdout.writeln('WALLETS s=$w0s b=$w0b');

  final buyerTry = await admin.invokeEdge('refund-order', {'order_id': oid}, accessToken: buyerJwt);
  stdout.writeln('BUYER_REFUND ${buyerTry.statusCode} ${buyerTry.body}');

  final rs = await Future.wait(List.generate(
    6,
    (_) => admin.invokeEdge('refund-order', {'order_id': oid}, accessToken: sellerJwt),
  ));
  for (var i = 0; i < rs.length; i++) {
    stdout.writeln('SELLER_REFUND#$i ${rs[i].statusCode} ${rs[i].body}');
  }
  final after = await admin.select('orders', filter: 'id=eq.$oid', limit: 1);
  stdout.writeln('AFTER ${jsonEncode({
    'status': after.first['status'],
    'paid': after.first['amount_paid_cents'],
    'refund': after.first['stripe_refund_id'],
    'pi': after.first['stripe_payment_intent_id'],
    'wallet_refund': after.first['wallet_refund_processed_at'],
  })}');
  final prod = await admin.select('products', filter: 'id=eq.${after.first['product_id']}', limit: 1);
  stdout.writeln('PRODUCT ${jsonEncode({'qty': prod.first['quantity'], 'sold': prod.first['is_sold']})}');
  final w1s = (await admin.select('wallets', filter: 'id=eq.${envRequire(env, 'LIVE_OPS_TEST_SELLER_ID')}', limit: 1)).first['balance'];
  final w1b = (await admin.select('wallets', filter: 'id=eq.${envRequire(env, 'LIVE_OPS_TEST_BUYER_ID')}', limit: 1)).first['balance'];
  stdout.writeln('WALLETS_AFTER s=$w1s b=$w1b');
}
