/// RED TEAM CEGO BB — pass 3b. Snapshot reservas após reconcile buyer. Não corrige.
import 'dart:io';
import '_rtbb.dart';

Future<void> main() async {
  final rt = Rtbb.fromEnv(loadEnv());
  await rt.loginActors();

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

  final liveA = await rt.insertLive(title: '$prefix p3b A');
  final sku = await rt.createProduct(title: '$prefix p3b sku', qty: 2, price: 12);
  if (liveA == null || sku == null) {
    await rt.dumpAll('pass3b.json');
    exit(4);
  }
  final item = await rt.insertItem(
    liveId: liveA,
    service: true,
    title: '$prefix p3b mp',
    productId: sku,
    kind: 'marketplace_product',
    price: 12,
  );
  final itemId = item.firstId!;
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

  final recB = await rt.rpc('batata_live_reconcile_stripe_order', {
    'p_order_id': pend.firstId,
  }, jwt: rt.buyerJwt);

  final allRes = await rt.rest(
    'GET',
    'live_reservation_requests?live_item_id=eq.$itemId&select=id,status,source,notes,requested_qty,buyer_id',
    service: true,
  );
  final itemRow = await rt.itemRow(itemId);
  final orderRow = pend.firstId != null ? await rt.orderRow(pend.firstId!) : null;

  final statuses = allRes.list
      .whereType<Map>()
      .map((m) => '${m['status']}')
      .toList();
  final hasConverted = statuses.contains('converted');
  final hasPending = statuses.contains('pending') || statuses.contains('accepted');

  if (hasConverted) {
    rt.hold(
      id: 'BB1-14',
      lens: 'BB1',
      severity: 'P1',
      title: 'reconcile aguarda_confirmacao persiste reservation converted',
      actor: 'buyer JWT',
      pre: 'MB WAY pendente',
      repro: 'rpc batata_live_reconcile_stripe_order',
      expected: 'order_not_paid / convert_requires_paid_order',
      obtained: recB.brief,
      evidence: {
        'reservations': allRes.list,
        'item': itemRow,
        'order': orderRow,
      },
    );
  } else if (recB.ok && recB.body.contains('direct_insert') && hasPending) {
    rt.hold(
      id: 'BB1-14',
      lens: 'BB1',
      severity: 'P3',
      title:
          'reconcile aguarda_confirmacao devolve ok/direct_insert mas só cria pending (não converted)',
      actor: 'buyer JWT',
      pre: 'force_pending no INSERT converted',
      repro: 'rpc batata_live_reconcile_stripe_order',
      expected: 'order_not_paid sem INSERT',
      obtained: recB.brief,
      evidence: {
        'reservations': allRes.list,
        'item': itemRow,
        'order': orderRow,
      },
    );
  } else {
    rt.block('BB1-14', 'BB1', 'reconcile não converte nem fila', {
      'rpc': recB.brief,
      'reservations': allRes.list,
      'item': itemRow,
      'order': orderRow,
      'statuses': statuses,
    });
  }

  await rt.cleanupSoft();
  await rt.dumpAll('pass3b.json');
  stdout.writeln('DONE p3b findings=${rt.findings.length} blocked=${rt.blocked.length}');
}
