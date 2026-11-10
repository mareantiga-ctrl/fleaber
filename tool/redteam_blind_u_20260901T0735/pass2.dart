/// Pass 2 — confirmar falsos positivos e fechar impacto (sem corrigir).
import 'dart:io';

import '_rtu.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rtu.fromEnv(env);
  await c.loginActors();

  // U1 unlist alheio: 200 [] = 0 rows? confirmar list flag.
  const unlistSku = 'e519379d-8726-437d-86a9-6cb8d0c73d43';
  final listed = await c.productRow(unlistSku);
  c.note('p2.unlist.sku', 'SKU alvo do PATCH buyer', listed, lens: 'U1');
  if (listed?['list_on_marketplace'] == true) {
    c.block('RTU-U1-unlist-alheio', 'U1', '200 [] era no-op RLS; SKU continua listado', listed);
  } else if (listed?['list_on_marketplace'] == false) {
    c.hold(
      id: 'RTU-U1-unlist-alheio-confirmed',
      lens: 'U1',
      severity: 'P0',
      title: 'Comprador unlista anúncio alheio (confirmado na row)',
      actor: 'buyer JWT',
      pre: 'PATCH 200 [] no pass1',
      repro: 'GET products service_role',
      expected: 'list_on_marketplace=true',
      obtained: listed,
    );
  }

  // Penny offer hold stuck
  const pennyOid = 'e522af37-d399-4f75-a0a3-4185cf9e39a9';
  const pennyPid = '1a82b315-33db-446b-b675-05e2fe8abbff';
  final pennyO = await c.orderRow(pennyOid);
  final pennyP = await c.productRow(pennyPid);
  c.note('p2.penny', 'hold 0.01€ unpayable', {
    'order': {
      'status': pennyO?['status'],
      'contract': pennyO?['contract_unit_cents'],
      'offer': pennyO?['product_offer_id'],
    },
    'product': {'qty': pennyP?['quantity'], 'listed': pennyP?['list_on_marketplace']},
  }, lens: 'U2');
  final ck = await c.checkout(orderId: pennyOid, amount: 50);
  c.note('p2.penny.ck', 're-checkout penny', ck.brief, lens: 'U2');
  final can = await c.markCancel(pennyOid, jwt: c.buyerJwt);
  final pennyAfter = await c.orderRow(pennyOid);
  c.note('p2.penny.cancel', 'buyer cancela hold unpayable', {
    'can': can.brief,
    'status': pennyAfter?['status'],
  }, lens: 'U2');
  if ((pennyO?['status'] == 'reserva_pendente') &&
      !ck.ok &&
      pennyAfter?['status'] != 'cancelado') {
    c.hold(
      id: 'RTU-U2-penny-hold-stuck',
      lens: 'U2',
      severity: 'P1',
      title: 'Oferta 0,01€ sela hold que não faz checkout e não cancela',
      actor: 'buyer JWT',
      pre: 'contract_unit_cents=1; line < 50 cêntimos',
      repro: 'create-payment-intent; PATCH cancelado',
      expected: 'checkout recusa E hold cancelável',
      obtained: pennyAfter?['status'],
    );
  }

  // Bundle race: accepted + unlisted member → hold/checkout
  const bunRace = 'a73c7113-e96c-4745-9584-6ffe9bb0e32d';
  const raceA = '22860323-5e16-4ced-ac1a-ddacad302ca9';
  const raceB = '2ddabe86-7d57-486b-ac61-b1f67dfb31c7';
  final bun = await c.rest('GET', 'product_bundles?id=eq.$bunRace', service: true);
  final pa = await c.productRow(raceA);
  final pb = await c.productRow(raceB);
  c.note('p2.bun.race', 'bundle aceite vs SKUs', {
    'bundle': bun.map,
    'a_listed': pa?['list_on_marketplace'],
    'b_listed': pb?['list_on_marketplace'],
  }, lens: 'U2');
  final oa = await c.insertOrder(
    productId: raceA,
    jwt: c.buyerJwt,
    bundleId: bunRace,
    price: 14,
  );
  final ob = await c.insertOrder(
    productId: raceB,
    jwt: c.buyerJwt,
    bundleId: bunRace,
    price: 14,
  );
  c.note('p2.bun.holds', 'holds no bundle aceite+unlist', {'a': oa, 'b': ob}, lens: 'U2');
  if (oa != null && ob != null) {
    final bag = await c.checkoutBag(
      lines: [
        {'order_id': oa, 'product_id': raceA},
        {'order_id': ob, 'product_id': raceB},
      ],
      amount: 50,
    );
    c.note('p2.bun.checkout', 'checkout bundle morto', bag.brief, lens: 'U2');
    if (bag.ok && (bag.checkoutSessionId ?? '').startsWith('cs_')) {
      c.hold(
        id: 'RTU-U2-dead-bundle-checkout',
        lens: 'U2',
        severity: 'P0',
        title: 'Checkout Session de conjunto aceite com SKU unlistado',
        actor: 'buyer JWT',
        pre: 'bundle accepted; um membro list=false',
        repro: 'POST orders + bag_checkout',
        expected: 'product is not listed',
        obtained: bag.brief,
      );
    } else {
      c.block('RTU-U2-dead-bundle-ck', 'U2', 'checkout do bundle unlistado recusado', bag.brief);
    }
  } else if (oa != null || ob != null) {
    c.note('p2.bun.partial', 'só um hold no par unlistado', {'a': oa, 'b': ob}, lens: 'U2');
  }

  // Shipping: seller PATCH carrier on hand hold
  const shipOid = '83742d0d-853c-4a2e-a390-580714affd1d';
  final before = await c.orderRow(shipOid);
  final sPatch = await c.rest(
    'PATCH',
    'orders?id=eq.$shipOid',
    jwt: c.sellerJwt,
    body: {'shipping_method': 'transportadora'},
  );
  final after = await c.orderRow(shipOid);
  c.note('p2.ship.seller', 'S PATCH portes no hold do buyer', {
    'before': before?['shipping_method'],
    'patch': sPatch.brief,
    'after': after?['shipping_method'],
  }, lens: 'U3');
  if (after?['shipping_method']?.toString().contains('transportadora') == true &&
      (before?['shipping_method']?.toString() ?? '').contains('mão')) {
    final q = await c.checkout(orderId: shipOid, amount: 50, shipping: 'mao');
    c.note('p2.ship.seller.quote', 'quote após S mudar portes', q.brief, lens: 'U3');
    if (q.ok && (q.serverAmount ?? 0) >= 1600) {
      c.hold(
        id: 'RTU-U3-seller-ship-hijack',
        lens: 'U3',
        severity: 'P1',
        title: 'Vendedor altera portes do hold e o Stripe cobra transportadora',
        actor: 'seller JWT',
        pre: 'buyer selou mão',
        repro: 'PATCH shipping_method=transportadora; create-payment-intent',
        expected: 'selo do comprador',
        obtained: q.serverAmount,
      );
    }
  }

  // Dual session: orders still reserva? both cs open is already proven.
  const bagOa = 'e39a9266-4bb9-4e7e-9b7d-076d12459700';
  // ids from pass1 bundle orders:
  final bagOrders = await c.rest(
    'GET',
    'orders?bundle_id=eq.0998a6f8-151d-4c9b-afcc-761d66173d01&select=id,status,stripe_checkout_session_id,price_total,contract_unit_cents',
    service: true,
  );
  c.note('p2.dual.orders', 'orders do saco com 2 cs_', bagOrders.list, lens: 'U3');

  // Hub ghost still visible
  const ghost = '1b7cba91-0169-4216-8d4e-3bd3d7c99b14';
  final hub = await c.rest(
    'GET',
    'hub_products_public?id=eq.$ghost&select=id,price,is_sold,title',
  );
  c.note('p2.hub.ghost', 'ghost ainda no Hub', hub.map ?? hub.list, lens: 'U7');

  final out = {
    'auditor': 'REDTEAM_BLIND_U_MARKETPLACE_CHECKOUT_v1',
    'pass': 2,
    'notes': c.notes,
    'blocked': c.blocked,
    'findings': c.findings,
  };
  await dumpJson('${outDir()}/pass2.json', out);
  stdout.writeln('WROTE pass2 findings=${c.findings.length} blocked=${c.blocked.length}');
}
