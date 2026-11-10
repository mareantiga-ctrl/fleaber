/// Pass 7 — seller accept bundle hostil 0.50 → Session amount?
import 'dart:convert';
import 'dart:io';
import '_rte.dart';

void main() async {
  final env = loadEnv();
  final c = Rte.fromEnv(env);
  await c.loginActors(env);

  const bunId = '86c8e11b-d682-4e6f-8517-516e484fee2e';
  const bunOid = '03a7b734-9dc8-4e11-aad4-6aff8cab93fa';

  final acc = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bunId',
    jwt: c.sellerJwt,
    prefer: 'return=representation',
    body: {'status': 'accepted'},
  );

  final ck = await c.edge('create-payment-intent', {
    'order_id': bunOid,
    'buyer_id': c.buyerId,
    'currency': 'eur',
    'shipping_method': 'hand',
  }, jwt: c.buyerJwt);

  final bun = await c.rest(
    'GET',
    'product_bundles?id=eq.$bunId&select=id,status,total_eur,discount_pct,subtotal_eur',
    jwt: c.sellerJwt,
  );
  final ord = await c.rest(
    'GET',
    'orders?id=eq.$bunOid&select=id,status,price_total,contract_unit_cents,bundle_id',
    jwt: c.buyerJwt,
  );

  final out = {
    'accept': {'http': acc.status, 'snip': acc.snippet, 'json': acc.json},
    'ck_http': ck.status,
    'ck': ck.json ?? ck.body,
    'bundle': bun.json,
    'order': ord.json,
  };
  await dumpJson('tool/redteam_blind_e_orbita_20260830T1930/out/pass7.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
