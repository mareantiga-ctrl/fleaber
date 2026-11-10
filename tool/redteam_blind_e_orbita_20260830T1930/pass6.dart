/// Pass 6 — GET settle Session unlisted (sem pagar) + wallets snapshot.
import 'dart:convert';
import 'dart:io';
import '_rte.dart';

void main() async {
  final env = loadEnv();
  final c = Rte.fromEnv(env);
  await c.loginActors(env);

  const sid = 'cs_test_a1nYpPdgtR7ck4vleohKA2u0tkouG8D69FwRdQ4tBTZBkQUSje5Qm2gt53';
  const oid = 'c5d6b577-19b9-491e-b286-ea12cebf3c15';
  const pid = '3c58b97d-a083-47c3-9a0f-df8397b58d61';

  final beforeOrder = await c.rest(
    'GET',
    'orders?id=eq.$oid&select=id,status,amount_paid_cents,stripe_payment_intent_id,price_total',
    service: true,
  );
  final beforeProd = await c.rest(
    'GET',
    'products?id=eq.$pid&select=id,quantity,is_sold,list_on_marketplace',
    service: true,
  );
  final beforeWal = await c.rest(
    'GET',
    'wallets?id=eq.${c.sellerId}&select=id,balance,available_balance,pending_balance',
    service: true,
  );

  final settleAnon = await c.req(
    'GET',
    '/functions/v1/create-payment-intent?checkout_return=success&session_id=$sid',
  );
  final settleBuyer = await c.req(
    'GET',
    '/functions/v1/create-payment-intent?checkout_return=success&session_id=$sid',
    jwt: c.buyerJwt,
  );

  final afterOrder = await c.rest(
    'GET',
    'orders?id=eq.$oid&select=id,status,amount_paid_cents,stripe_payment_intent_id,price_total',
    service: true,
  );
  final afterProd = await c.rest(
    'GET',
    'products?id=eq.$pid&select=id,quantity,is_sold,list_on_marketplace',
    service: true,
  );
  final afterWal = await c.rest(
    'GET',
    'wallets?id=eq.${c.sellerId}&select=id,balance,available_balance,pending_balance',
    service: true,
  );

  final out = {
    'before_order': beforeOrder.json,
    'before_prod': beforeProd.json,
    'before_wal': beforeWal.json,
    'settle_anon': {
      'http': settleAnon.status,
      'loc': settleAnon.location,
      'snip': settleAnon.snippet,
    },
    'settle_buyer': {
      'http': settleBuyer.status,
      'loc': settleBuyer.location,
      'snip': settleBuyer.snippet,
    },
    'after_order': afterOrder.json,
    'after_prod': afterProd.json,
    'after_wal': afterWal.json,
  };
  await dumpJson('tool/redteam_blind_e_orbita_20260830T1930/out/pass6.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
