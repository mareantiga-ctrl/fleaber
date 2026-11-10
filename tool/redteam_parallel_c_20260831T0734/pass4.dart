/// Parallel C — Pass 4: bag quote exact + tip wallet observe (último ciclo).
import 'dart:convert';
import 'dart:io';
import '_rtc.dart';

Future<void> main() async {
  final c = Rtc(loadEnv());
  await c.boot();
  final bJwt = c.buyerJwt!;
  final sJwt = c.sellerJwt!;
  final bId = c.buyerId!;
  final sId = c.sellerId!;

  final tip = await c.rest(
    'GET',
    'live_tips',
    service: true,
    query:
        'id=eq.057b463b-a3ab-4c87-b5aa-2940253346ee&select=id,live_id,buyer_id,seller_id,amount,status,payment_source,seller_amount,processing_fee',
  );
  stdout.writeln('TIP ${tip['raw']}');
  stdout.writeln('wB=${await c.walletBalance(bId)} wS=${await c.walletBalance(sId)}');

  final pa = await c.createProduct(
      token: sJwt, seller: sId, title: '$prefix bagQA', price: 4, qty: 2);
  final pb = await c.createProduct(
      token: sJwt, seller: sId, title: '$prefix bagQB', price: 8, qty: 2);
  final oa = await c.createOrder(
      token: bJwt, buyer: bId, seller: sId, productId: pa!, shipping: 'entrega em mão');
  final ob = await c.createOrder(
      token: bJwt, buyer: bId, seller: sId, productId: pb!, shipping: 'entrega em mão');
  final ida = (oa['json'] as List).first['id'].toString();
  final idb = (ob['json'] as List).first['id'].toString();
  await c.rest(
    'PATCH',
    'products',
    token: sJwt,
    query: 'id=eq.$pb',
    body: {'price': 1},
  );
  final ck = await c.edge(
    'create-payment-intent',
    token: bJwt,
    body: {
      'buyer_id': bId,
      'bag_checkout': true,
      'shipping_method': 'carrier',
      'bag_lines': [
        {'order_id': ida, 'line_total_cents': 1, 'quantity': 9},
        {'order_id': idb, 'line_total_cents': 1},
      ],
      'amount': 50,
    },
  );
  File('tool/redteam_parallel_c_20260831T0734/out/bag_quote.json')
      .writeAsStringSync('${ck['raw']}');
  final j = ck['json'];
  stdout.writeln(
      'BAG http=${ck['http']} keys=${j is Map ? j.keys.toList() : j} server=${j is Map ? j['server_amount_cents'] : null} total=${j is Map ? j['amount_total'] : null}');

  // expected: contracts 400+800=1200 + ship 0 (mão selada) + prot(12.00)=125 → 1325
  final amt = j is Map ? asNum(j['server_amount_cents']) : null;
  c.rec(
    id: 'J.bag.quote.exact',
    surface: 'create-payment-intent bag',
    attack: 'bag 4€+8€ selados mão; catálogo B→1€; body carrier+amount=50',
    identity: 'buyer',
    httpCode: ck['http'] as int,
    result: 'server_amount_cents=$amt amount_total=${j is Map ? j['amount_total'] : null}',
    impact: (amt == 1325)
        ? 'contrato+prot mão (ignora body carrier e catálogo vivo)'
        : 'desvio vs 1325',
    sev: (amt != null && amt < 1200) ? 'P1' : '—',
    evidence: clip('${ck['raw']}', 220),
  );

  await c.dump('tool/redteam_parallel_c_20260831T0734/out/pass4.json');
  stdout.writeln('pass4 ${c.hits.first.toJson()}');
}
