/// T3/T5 disputa + Stripe — envio só status; facebook_manual accept→convert.
import 'dart:io';
import '_rtt.dart';

Future<void> main() async {
  final c = Rtt.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  // ----- facebook_manual: pending → accept → convert (qty folga) -----
  final live = await c.insertLive();
  final fbItem = await c.insertLiveItem(
    liveId: live!,
    title: '$prefix fb-qty5',
    qty: 5,
    price: 9,
  );
  final fbIns = await c.rest('POST', 'live_reservation_requests',
      jwt: c.sellerJwt,
      body: {
        'live_id': live,
        'live_item_id': fbItem,
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'requested_qty': 1,
        'source': 'facebook_manual',
        'status': 'pending',
      });
  final fbId = fbIns.firstId;
  if (fbId != null) c.createdReservationIds.add(fbId);
  final acc = await c.processReservation(fbId ?? '', 'accept', jwt: c.sellerJwt);
  final afterAcc = fbId == null ? null : await c.reservationRow(fbId);
  final conv = await c.processReservation(fbId ?? '', 'convert', jwt: c.sellerJwt);
  final afterConv = fbId == null ? null : await c.reservationRow(fbId);
  final li = fbItem == null ? null : await c.liveItemRow(fbItem);
  c.note('T2.fb.accept.convert', 'facebook_manual accept→convert qty5', {
    'ins': fbIns.brief,
    'accept': acc.brief,
    'convert': conv.brief,
    'after_acc': afterAcc,
    'after_conv': afterConv,
    'item': li,
  }, lens: 'T2');
  if (afterConv?['status'] == 'converted') {
    c.hold(
      id: 'T2-FB-CONVERT-NOPAY',
      lens: 'T2',
      severity: 'P1',
      title: 'facebook_manual convertido sem encomenda paga',
      actor: 'seller JWT',
      pre: 'live_only qty=5; accept; zero PI',
      repro:
          'process accept; process convert source=facebook_manual',
      expected: 'convert_requires_paid_order',
      obtained: {'row': afterConv, 'item': li, 'rpc': conv.json},
    );
  } else {
    c.closed('T2.fb.accept.convert', 'facebook_manual convert não passou',
        conv.brief,
        lens: 'T2');
  }

  // ----- Stripe paid + ship + dispute -----
  final w0 = await c.wallets();
  final paid = await c.setupPaidStripe();
  final oid = paid['order_id'];
  final pid = paid['product_id'];
  final pi = paid['pi'];
  if (oid == null) {
    stderr.writeln('no paid');
    exit(1);
  }

  var ship = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.sellerJwt,
    body: {'status': 'enviado'},
  );
  c.note('T3.ship.status_only', 'seller PATCH enviado (sem shipping_method)',
      ship.brief,
      lens: 'T3');
  if (!ship.ok) {
    await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      service: true,
      body: {'shipping_method': 'CTT'},
      prefer: 'return=minimal',
    );
    ship = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: c.sellerJwt,
      body: {'status': 'enviado'},
    );
    c.note('T3.ship.after.fixture.seal', 'enviado após fixture CTT', ship.brief,
        lens: 'T3');
  }

  final rec = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {'status': 'entregue'},
  );
  c.note('T3.entregue2', 'buyer PATCH entregue', rec.brief, lens: 'T3');
  var order = await c.orderRow(oid);
  c.note('T3.order.after.ship', 'order pós envio/receção', order, lens: 'T3');

  final disp = await c.insertDispute(orderId: oid);
  c.note('T3.dispute2', 'buyer INSERT disputa', disp.brief, lens: 'T3');
  var did = disp.firstId;
  if (did != null) c.createdDisputeIds.add(did);

  // T3: disputa em pago via fixture se INSERT RLS falhou — RPC ainda é o actor
  if (did == null) {
    final fx = await c.rest('POST', 'order_disputes', service: true, body: {
      'order_id': oid,
      'buyer_id': c.buyerId,
      'reason': 'nao_corresponde',
      'description': '$prefix fixture disputa pago/entregue',
      'status': 'aberta',
      'seller_offer_type': 'partial_refund',
      'seller_refund_percent': 40,
      'seller_offer_set_by': c.sellerId,
    });
    c.note('T3.dispute.fixture', 'service_role INSERT disputa (pré-condição RPC)',
        fx.brief,
        lens: 'T3');
    did = fx.firstId;
    if (did != null) c.createdDisputeIds.add(did);
  }

  if (did != null) {
    final res1 = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {'status': 'resolvida'},
    );
    var drow = await c.disputeRow(did);
    c.note('T5.resolvida2', 'seller PATCH resolvida', {
      'patch': res1.brief,
      'row': drow,
    }, lens: 'T5');
    if (drow?['status'] == 'resolvida') {
      c.hold(
        id: 'T5-Q5-SELLER-RESOLVIDA',
        lens: 'T5',
        severity: 'P1',
        title: 'Vendedor fecha disputa resolvida sozinho',
        actor: 'seller JWT',
        pre: 'disputa aberta',
        repro: 'PATCH order_disputes status=resolvida',
        expected: 'status não muda para resolvida',
        obtained: drow,
      );
    } else {
      c.closed('T5.resolvida2', 'seller resolvida bloqueada', drow, lens: 'T5');
    }

    final bd = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {'buyer_decision': 'accepted_partial_refund'},
    );
    drow = await c.disputeRow(did);
    c.note('T5.bd2', 'seller PATCH buyer_decision', {
      'patch': bd.brief,
      'row': drow,
    }, lens: 'T5');
    if (drow?['buyer_decision'] == 'accepted_partial_refund') {
      final res2 = await c.rest(
        'PATCH',
        'order_disputes?id=eq.$did',
        jwt: c.sellerJwt,
        body: {'status': 'resolvida'},
      );
      drow = await c.disputeRow(did);
      if (drow?['status'] == 'resolvida') {
        c.hold(
          id: 'T5-FORGE-BUYER-DECISION',
          lens: 'T5',
          severity: 'P1',
          title: 'Seller forja buyer_decision e fecha resolvida',
          actor: 'seller JWT',
          pre: 'disputa aberta',
          repro: 'PATCH buyer_decision; PATCH resolvida',
          expected: 'seller não escreve buyer_decision',
          obtained: drow,
        );
      }
    } else {
      c.closed('T5.bd2', 'seller não escreve buyer_decision', drow, lens: 'T5');
    }

    final recu = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {'status': 'recusada'},
    );
    drow = await c.disputeRow(did);
    c.note('T5.recusada2', 'seller recusada', {
      'patch': recu.brief,
      'row': drow,
    }, lens: 'T5');
    if (drow?['status'] == 'recusada') {
      c.hold(
        id: 'T5-SELLER-RECUSADA',
        lens: 'T5',
        severity: 'P1',
        title: 'Seller marca disputa recusada',
        actor: 'seller JWT',
        pre: 'disputa não terminal',
        repro: 'PATCH status=recusada',
        expected: 'bloqueado',
        obtained: drow,
      );
    } else {
      c.closed('T5.recusada2', 'seller recusada bloqueada', drow, lens: 'T5');
    }

    final offer = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {
        'seller_offer_type': 'partial_refund',
        'seller_refund_percent': 40,
        'status': 'respondida_vendedor',
        'seller_offer_set_by': c.sellerId,
      },
    );
    drow = await c.disputeRow(did);
    c.note('T3.offer2', 'seller oferta 40%', {
      'patch': offer.brief,
      'row': drow,
    }, lens: 'T3');

    if (drow?['seller_offer_set_by'] == null) {
      await c.rest(
        'PATCH',
        'order_disputes?id=eq.$did',
        service: true,
        body: {'seller_offer_set_by': c.sellerId, 'seller_refund_percent': 40},
        prefer: 'return=minimal',
      );
      drow = await c.disputeRow(did);
      c.note('T3.offer.stamp', 'fixture stamp seller_offer_set_by', drow,
          lens: 'T3');
    }

    final wA = await c.wallets();
    final part = await c.rpc(
      'batata_process_partial_refund_dispute',
      {'p_order_id': oid},
      jwt: c.buyerJwt,
    );
    final wB = await c.wallets();
    order = await c.orderRow(oid);
    final tx = await c.walletTxns(orderId: oid);
    c.note('T3.partial2', 'parcial no estado actual', {
      'rpc': part.brief,
      'status': order?['status'],
      'wallets': {'before': wA, 'after': wB},
      'stripe_refund_id': order?['stripe_refund_id'],
      'tx': tx.take(8).toList(),
    }, lens: 'T3');
    final minted = (wB['buyer'] ?? 0) > (wA['buyer'] ?? 0);
    final noStripe = '${order?['stripe_refund_id'] ?? ''}'.isEmpty;
    if (minted && noStripe) {
      c.hold(
        id: 'T3-PARTIAL-WALLET-NO-STRIPE',
        lens: 'T3',
        severity: 'P0',
        title:
            'Parcial disputa creditou carteira com PI Stripe capturado e sem stripe_refund_id',
        actor: 'buyer JWT',
        pre: 'order status=${order?['status']}; PI $pi; oferta 40%',
        repro: 'rpc batata_process_partial_refund_dispute',
        expected: 'dispute_partial_refund_requires_stripe',
        obtained: {
          'rpc': part.json,
          'delta_buyer': (wB['buyer'] ?? 0) - (wA['buyer'] ?? 0),
          'order': order,
        },
        evidence: {'pi': pi, 'wallets_before': wA, 'wallets_after': wB, 'tx': tx},
      );
    } else {
      c.closed('T3.partial2', 'parcial sem mint ou Stripe-required', part.brief,
          lens: 'T3');
    }

    final pd = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: c.buyerJwt,
      body: {'status': 'pedido_devolucao'},
    );
    order = await c.orderRow(oid);
    c.note('T3.pd2', 'buyer pedido_devolucao', {
      'patch': pd.brief,
      'row': order,
    }, lens: 'T3');
    final wC = await c.wallets();
    final partPd = await c.rpc(
      'batata_process_partial_refund_dispute',
      {'p_order_id': oid},
      jwt: c.buyerJwt,
    );
    final wD = await c.wallets();
    order = await c.orderRow(oid);
    c.note('T3.partial.pd2', 'parcial em pedido_devolucao', {
      'rpc': partPd.brief,
      'status': order?['status'],
      'wallets': {'before': wC, 'after': wD},
      'stripe_refund_id': order?['stripe_refund_id'],
    }, lens: 'T3');
    final mintedPd = (wD['buyer'] ?? 0) > (wC['buyer'] ?? 0);
    if (mintedPd && '${order?['stripe_refund_id'] ?? ''}'.isEmpty) {
      c.hold(
        id: 'T3-Q8-PEDIDO-DEVOLUCAO-WALLET',
        lens: 'T3',
        severity: 'P0',
        title: 'Parcial em pedido_devolucao mintou carteira; Stripe ainda capturado',
        actor: 'buyer JWT',
        pre: 'pedido_devolucao + PI capturado',
        repro: 'rpc batata_process_partial_refund_dispute',
        expected: 'dispute_partial_refund_requires_stripe',
        obtained: {
          'rpc': partPd.json,
          'delta_buyer': (wD['buyer'] ?? 0) - (wC['buyer'] ?? 0),
          'order': order,
        },
        evidence: {'pi': pi},
      );
    } else {
      c.closed('T3.partial.pd2', 'parcial pedido_devolucao bloqueado/sem mint',
          partPd.brief,
          lens: 'T3');
    }

    // T6 race residual
    final raced = await parallel([
      c.rpc('batata_process_partial_refund_dispute', {'p_order_id': oid},
          jwt: c.buyerJwt),
      c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt),
    ]);
    order = await c.orderRow(oid);
    final wE = await c.wallets();
    c.note('T6.partial.refund2', 'race partial∥refund-order', {
      'p': raced[0].brief,
      'r': raced[1].brief,
      'order': {
        'status': order?['status'],
        'stripe_refund_id': order?['stripe_refund_id'],
        'wallet_refund': order?['wallet_refund_processed_at'],
      },
      'wallets': wE,
    }, lens: 'T6');
    final bothMoney = mintedPd &&
        '${order?['stripe_refund_id'] ?? ''}'.isNotEmpty;
    if (bothMoney) {
      c.hold(
        id: 'T6-WALLET-PLUS-STRIPE',
        lens: 'T6',
        severity: 'P0',
        title: 'Carteira mint + stripe_refund_id no mesmo pedido',
        actor: 'buyer∥seller',
        pre: 'parcial + refund-order',
        repro: 'Future.wait partial ∥ refund-order',
        expected: 'um canal',
        obtained: {'rpc': raced[0].json, 'edge': raced[1].json, 'order': order},
      );
    }

    // URLs novas
    for (final e in {
      'query_wrap':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/x?next=https://evil.example/phish',
      'wildcard_sb':
          'https://attacker.supabase.co/storage/v1/object/public/phish',
      'userinfo': 'https://evil.example@fleaber.app/x',
      'newline':
          'https://fleaber.app/ok\nhttps://evil.example',
    }.entries) {
      final po = await c.rest(
        'PATCH',
        'orders?id=eq.$oid',
        jwt: c.buyerJwt,
        body: {'proof_url': e.value},
      );
      final stored = (await c.orderRow(oid))?['proof_url']?.toString();
      if (po.ok && stored == e.value) {
        c.hold(
          id: 'T3-PROOF-${e.key.toUpperCase()}',
          lens: 'T3',
          severity: 'P2',
          title: 'proof_url aceitou ${e.key}',
          actor: 'buyer JWT',
          pre: 'order paga',
          repro: 'PATCH proof_url ${e.key}',
          expected: 'denied',
          obtained: stored,
        );
      } else {
        c.closed('T3.proof.${e.key}', 'proof ${e.key} recusado', po.brief,
            lens: 'T3');
      }
    }
  }

  final listed = await c.e2e('list_stripe_refunds', {
    'payment_intent_id': pi,
    'order_id': oid,
  });
  c.note('T3.stripe2', 'Stripe PI/refunds', listed.brief, lens: 'T3');
  final wEnd = await c.wallets();

  await c.endLives();
  await dumpJson('${outDir()}/pass3b.json', {
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'paid': paid,
    'wallets': {'start': w0, 'end': wEnd},
    'stripe': listed.json,
    'product_id': pid,
  });
  stdout.writeln(
      'PASS3b findings=${c.findings.length} closed=${c.blocked.length}');
  exit(0);
}
