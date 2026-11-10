/// Pass 5 — corpo completo Session + quote amount + estado BD.
import 'dart:convert';
import 'dart:io';
import '_rte.dart';

void main() async {
  final env = loadEnv();
  final c = Rte.fromEnv(env);
  await c.loginActors(env);

  Future<Map<String, dynamic>> pack(String label, String oid) async {
    final h = await c.edge('create-payment-intent', {
      'order_id': oid,
      'buyer_id': c.buyerId,
      'currency': 'eur',
      'shipping_method': 'hand',
    }, jwt: c.buyerJwt);
    final order = await c.rest(
      'GET',
      'orders?id=eq.$oid&select=id,status,price_total,amount_paid_cents,stripe_checkout_session_id,shipping_method,live_id,bundle_id,product_id,quantity,contract_unit_cents',
      jwt: c.buyerJwt,
    );
    return {
      'label': label,
      'http': h.status,
      'body': h.json ?? h.body,
      'order_http': order.status,
      'order': order.json,
    };
  }

  const stampOid = 'c5d6b577-19b9-491e-b286-ea12cebf3c15';
  const bunOid = '03a7b734-9dc8-4e11-aad4-6aff8cab93fa';
  const bunId = '86c8e11b-d682-4e6f-8517-516e484fee2e';

  final stampPack = await pack('stamp_unlist_live', stampOid);
  final bunPack = await pack('bundle_pending', bunOid);
  final bunRow = await c.rest(
    'GET',
    'product_bundles?id=eq.$bunId&select=id,status,total_eur,discount_pct,subtotal_eur,product_ids',
    jwt: c.buyerJwt,
  );

  final prod = await c.rest(
    'GET',
    'products?id=eq.3c58b97d-a083-47c3-9a0f-df8397b58d61&select=id,quantity,is_sold,list_on_marketplace,price,title',
    service: true,
  );
  final held = await c.rpc(
    'batata_product_held_qty',
    {'p_product_id': '3c58b97d-a083-47c3-9a0f-df8397b58d61'},
    service: true,
  );

  final out = {
    'stamp': stampPack,
    'bundle_ck': bunPack,
    'bundle_row': bunRow.json,
    'unlist_product': prod.json,
    'held_qty': held.json ?? held.body,
  };
  final outPath = 'tool/redteam_blind_e_orbita_20260830T1930/out/pass5.json';
  await dumpJson(outPath, out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'stamp_http': stampPack['http'],
    'stamp_body': stampPack['body'],
    'stamp_order': stampPack['order'],
    'bun_http': bunPack['http'],
    'bun_body': bunPack['body'],
    'bun_order': bunPack['order'],
    'bundle_row': bunRow.json,
    'product': prod.json,
    'held': held.json ?? held.body,
  }));
  stdout.writeln(outPath);
}
