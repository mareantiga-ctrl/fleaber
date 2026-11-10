/// RED TEAM CEGO BB — pass 3. Reconcile no SKU marketplace + rifa + Hub. Não corrige.
import 'dart:io';
import '_rtbb.dart';

bool rpcOk(HttpHit h) =>
    h.ok && (h.body.contains('"ok":true') || h.body.contains('"ok": true'));

Future<void> main() async {
  final rt = Rtbb.fromEnv(loadEnv());
  await rt.loginActors();
  await rt.ensureBuyer2();
  await rt.ensureSeller2();
  await rt.ensureHelper();

  final leftover = await rt.rest(
    'GET',
    'lives?title=like.*$prefix*&select=id,status,is_active',
    service: true,
  );
  for (final row in leftover.list) {
    if (row is Map && row['id'] != null) {
      await rt.rest(
        'PATCH',
        'lives?id=eq.${row['id']}',
        service: true,
        body: {'status': 'ended', 'is_active': false},
        prefer: 'return=minimal',
      );
    }
  }

  final liveA = await rt.insertLive(title: '$prefix p3 A');
  if (liveA == null) {
    rt.skip('BB.p3.live', 'BB1', 'insertLive', null);
    await rt.dumpAll('pass3.json');
    exit(4);
  }
  final sku = await rt.createProduct(title: '$prefix p3 sku', qty: 2, price: 12);
  if (sku == null) {
    rt.skip('BB.p3.sku', 'BB1', 'sku', null);
    await rt.cleanupSoft();
    await rt.dumpAll('pass3.json');
    exit(4);
  }
  final item = await rt.insertItem(
    liveId: liveA,
    service: true,
    title: '$prefix p3 mp',
    qty: 1,
    productId: sku,
    kind: 'marketplace_product',
    price: 12,
  );
  final itemId = item.firstId;
  if (itemId == null) {
    rt.skip('BB.p3.item', 'BB1', item.brief, null);
    await rt.cleanupSoft();
    await rt.dumpAll('pass3.json');
    exit(4);
  }

  await rt.inviteHelper(
    helperUserId: rt.helperId!,
    status: 'accepted',
    active: true,
    perms: const {'can_manage_chat': true},
  );

  final w0 = await rt.wallets();

  // Reconcile MB WAY pendente num item com product_id
  final pend = await rt.rest('POST', 'orders', service: true, body: {
    'buyer_id': rt.buyerId,
    'seller_id': rt.sellerId,
    'product_id': sku,
    'price_total': 12,
    'quantity': 1,
    'status': 'aguarda_confirmacao',
    'payment_method': 'MB WAY',
    'shipping_method': 'entrega em mão',
    'live_item_id': itemId,
    'live_id': liveA,
  });
  if (pend.firstId != null) rt.createdOrderIds.add(pend.firstId!);
  final pendRow =
      pend.firstId != null ? await rt.orderRow(pend.firstId!) : null;
  rt.note('BB1-14.order', 'aguarda_confirmacao fixture', {
    'ins': pend.brief,
    'row': pendRow,
  }, lens: 'BB1');

  HttpHit recB = pend;
  HttpHit recS = pend;
  if (pend.firstId != null) {
    recB = await rt.rpc('batata_live_reconcile_stripe_order', {
      'p_order_id': pend.firstId,
    }, jwt: rt.buyerJwt);
    recS = await rt.rpc('batata_live_reconcile_stripe_order', {
      'p_order_id': pend.firstId,
    }, jwt: rt.sellerJwt);
  }
  final converted = await rt.rest(
    'GET',
    'live_reservation_requests?live_id=eq.$liveA&status=eq.converted&select=id,status,notes,source,live_item_id,buyer_id',
    service: true,
  );
  final itemAfter = await rt.itemRow(itemId);
  final orderAfter =
      pend.firstId != null ? await rt.orderRow(pend.firstId!) : null;
  final cracked = converted.list.isNotEmpty ||
      (rpcOk(recB) && !recB.body.contains('order_not_paid')) ||
      (rpcOk(recS) &&
          !recS.body.contains('order_not_paid') &&
          !recS.body.contains('no_request_to_convert'));
  rt.judge(
    id: 'BB1-14',
    lens: 'BB1',
    title: 'reconcile aguarda_confirmacao em marketplace_product converte sem captura',
    hit: recS,
    cracked: cracked,
    actor: 'buyer+seller JWT',
    pre: 'order status=aguarda_confirmacao + live_item com product_id',
    repro: 'rpc batata_live_reconcile_stripe_order',
    severity: 'P1',
    evidence: {
      'buyer': recB.brief,
      'seller': recS.brief,
      'converted': converted.list,
      'item': itemAfter,
      'order': orderAfter,
    },
  );

  // JWT premio_rifa
  final rifa = await rt.rest('POST', 'orders', jwt: rt.buyerJwt, body: {
    'buyer_id': rt.buyerId,
    'seller_id': rt.sellerId,
    'product_id': sku,
    'price_total': 0,
    'quantity': 1,
    'status': 'premio_rifa',
    'payment_method': 'rifa',
    'shipping_method': 'entrega em mão',
    'live_item_id': itemId,
    'live_id': liveA,
  });
  if (rifa.firstId != null) rt.createdOrderIds.add(rifa.firstId!);
  final rifaRow = rifa.firstId != null ? await rt.orderRow(rifa.firstId!) : null;
  rt.judge(
    id: 'BB1-09b',
    lens: 'BB8',
    title: 'Buyer INSERT order premio_rifa persiste esse status',
    hit: rifa,
    cracked: rifa.ok && '${rifaRow?['status']}' == 'premio_rifa',
    actor: 'buyer JWT',
    pre: 'sem rifa',
    repro: 'POST orders status=premio_rifa',
    severity: 'P3',
    evidence: {'row': rifaRow},
  );

  // Hub vê a mentira system?
  final marker = 'RTBB2-P3-HUB-${rt.nextRef()}';
  await rt.rpc('batata_live_system_message', {
    'p_live_id': liveA,
    'p_body': '✅ HubLie comprou $marker',
    'p_sender_label': 'Sistema',
  }, jwt: rt.helperJwt);
  final hubAuth = await rt.rest(
    'GET',
    'hub_live_messages_public?live_id=eq.$liveA&body=ilike.*$marker*&select=id,kind,body,live_id',
    jwt: rt.buyer2Jwt,
  );
  final hubAnon = await rt.rest(
    'GET',
    'hub_live_messages_public?live_id=eq.$liveA&body=ilike.*$marker*&select=id,kind,body,live_id',
  );
  rt.note('BB1-04.hub', 'mentira system no Hub', {
    'auth': hubAuth.brief,
    'anon': hubAnon.brief,
  }, lens: 'BB2');

  final w1 = await rt.wallets();
  rt.note('wallets.p3', 'caixa', {'t0': w0, 't1': w1}, lens: 'BB8');

  await rt.cleanupSoft();
  await rt.dumpAll('pass3.json');
  stdout.writeln(
    'DONE p3 findings=${rt.findings.length} blocked=${rt.blocked.length}',
  );
}
