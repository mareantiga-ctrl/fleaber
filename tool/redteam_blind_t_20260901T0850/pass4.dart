/// T3/T8 — rollback entregue→pago para mint; parcial em pago; buyer fecha disputa.
import 'dart:io';
import '_rtt.dart';

Future<String?> _paidShippedDisputed(Rtt c) async {
  final paid = await c.setupPaidStripe();
  final oid = paid['order_id'];
  if (oid == null) return null;
  await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
    'status': 'enviado',
  });
  await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
    'status': 'entregue',
  });
  final d = await c.insertDispute(orderId: oid);
  final did = d.firstId;
  if (did != null) {
    c.createdDisputeIds.add(did);
    await c.rest('PATCH', 'order_disputes?id=eq.$did', jwt: c.sellerJwt, body: {
      'seller_offer_type': 'partial_refund',
      'seller_refund_percent': 40,
      'status': 'respondida_vendedor',
      'seller_offer_set_by': c.sellerId,
    });
    final row = await c.disputeRow(did);
    if (row?['seller_offer_set_by'] == null) {
      await c.rest('PATCH', 'order_disputes?id=eq.$did', service: true, body: {
        'seller_offer_set_by': c.sellerId,
        'seller_refund_percent': 40,
        'seller_offer_type': 'partial_refund',
      }, prefer: 'return=minimal');
    }
  }
  return oid;
}

Future<void> main() async {
  final c = Rtt.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  // A — seller rollback entregue → pago, depois parcial
  final oidA = await _paidShippedDisputed(c);
  if (oidA != null) {
    final before = await c.orderRow(oidA);
    final roll = await c.rest(
      'PATCH',
      'orders?id=eq.$oidA',
      jwt: c.sellerJwt,
      body: {'status': 'pago'},
    );
    final afterRoll = await c.orderRow(oidA);
    c.note('T3.rollback.pago', 'seller entregue→pago', {
      'patch': roll.brief,
      'before': before?['status'],
      'after': afterRoll?['status'],
    }, lens: 'T3');
    if (afterRoll?['status'] == 'pago') {
      final w0 = await c.wallets();
      final part = await c.rpc(
        'batata_process_partial_refund_dispute',
        {'p_order_id': oidA},
        jwt: c.buyerJwt,
      );
      final w1 = await c.wallets();
      final o = await c.orderRow(oidA);
      c.note('T3.partial.after.rollback', 'parcial após rollback pago', {
        'rpc': part.brief,
        'wallets': {'before': w0, 'after': w1},
        'stripe_refund_id': o?['stripe_refund_id'],
      }, lens: 'T8');
      final minted = (w1['buyer'] ?? 0) > (w0['buyer'] ?? 0);
      if (minted && '${o?['stripe_refund_id'] ?? ''}'.isEmpty) {
        c.hold(
          id: 'T3-ROLLBACK-PAGO-WALLET-MINT',
          lens: 'T8',
          severity: 'P0',
          title:
              'Seller reabre status pago após entregue e o parcial minta carteira sem Stripe',
          actor: 'seller JWT + buyer JWT (conluio)',
          pre: 'entregue + disputa + oferta 40% + PI capturado',
          repro:
              'PATCH orders status=pago; rpc batata_process_partial_refund_dispute',
          expected: 'não voltar a pago; ou parcial continua a exigir Stripe',
          obtained: {
            'rollback': roll.brief,
            'rpc': part.json,
            'delta_buyer': (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0),
            'order': o,
          },
          evidence: {'wallets_before': w0, 'wallets_after': w1},
        );
      } else {
        c.closed('T3.partial.after.rollback', 'rollback pago sem mint Stripe-gated',
            part.brief,
            lens: 'T3');
      }
    } else {
      c.closed('T3.rollback.pago', 'seller não reabre pago após entregue',
          roll.brief,
          lens: 'T3');
    }
  }

  // B — parcial directo em pago (disputa fixture: RLS não deixa abrir em pago)
  final paidB = await c.setupPaidStripe();
  final oidB = paidB['order_id'];
  final piB = paidB['pi'];
  if (oidB != null) {
    final ins = await c.rest('POST', 'order_disputes', service: true, body: {
      'order_id': oidB,
      'buyer_id': c.buyerId,
      'reason': 'nao_corresponde',
      'description': '$prefix disputa-on-pago',
      'status': 'respondida_vendedor',
      'seller_offer_type': 'partial_refund',
      'seller_refund_percent': 40,
      'seller_offer_set_by': c.sellerId,
    });
    c.note('T3.disp.pago.fixture', 'disputa em pago (fixture RLS)', ins.brief,
        lens: 'T3');
    if (ins.firstId != null) c.createdDisputeIds.add(ins.firstId!);
    final w0 = await c.wallets();
    final part = await c.rpc(
      'batata_process_partial_refund_dispute',
      {'p_order_id': oidB},
      jwt: c.buyerJwt,
    );
    final w1 = await c.wallets();
    final o = await c.orderRow(oidB);
    c.note('T3.partial.pago', 'parcial status=pago PI capturado', {
      'rpc': part.brief,
      'status': o?['status'],
      'wallets': {'before': w0, 'after': w1},
      'stripe_refund_id': o?['stripe_refund_id'],
      'pi': piB,
    }, lens: 'T3');
    final minted = (w1['buyer'] ?? 0) > (w0['buyer'] ?? 0);
    if (minted && '${o?['stripe_refund_id'] ?? ''}'.isEmpty) {
      c.hold(
        id: 'T3-PARTIAL-ON-PAGO-WALLET',
        lens: 'T3',
        severity: 'P1',
        title:
            'RPC parcial em pago credita carteira sem refund Stripe (disputa não abrível por JWT neste estado)',
        actor: 'buyer JWT (disputa pré-existente)',
        pre: 'order pago capturado; oferta 40%',
        repro: 'rpc batata_process_partial_refund_dispute enquanto status=pago',
        expected: 'exige Stripe ou recusa até envio/refund-order',
        obtained: {
          'rpc': part.json,
          'delta_buyer': (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0),
          'order': o,
        },
        evidence: {'pi': piB, 'w0': w0, 'w1': w1},
      );
    } else {
      c.closed('T3.partial.pago', 'parcial pago recusado ou sem mint', part.brief,
          lens: 'T3');
    }
  }

  // T5: buyer fecha resolvida sem decisão / sem oferta
  if (oidA != null) {
    final dlist = await c.rest(
      'GET',
      'order_disputes?order_id=eq.$oidA&select=id,status,buyer_decision',
      service: true,
    );
    final did = dlist.firstId;
    if (did != null) {
      final br = await c.rest(
        'PATCH',
        'order_disputes?id=eq.$did',
        jwt: c.buyerJwt,
        body: {'status': 'resolvida'},
      );
      final drow = await c.disputeRow(did);
      c.note('T5.buyer.resolvida', 'buyer PATCH resolvida', {
        'patch': br.brief,
        'row': drow,
      }, lens: 'T5');
      if (drow?['status'] == 'resolvida' &&
          (drow?['buyer_decision'] == null ||
              '${drow?['buyer_decision']}' == '')) {
        c.hold(
          id: 'T5-BUYER-RESOLVIDA-NO-DECISION',
          lens: 'T5',
          severity: 'P2',
          title: 'Comprador fecha disputa resolvida sem buyer_decision',
          actor: 'buyer JWT',
          pre: 'disputa aberta/respondida',
          repro: 'PATCH status=resolvida',
          expected: 'exigir decisão ou fluxo de oferta',
          obtained: drow,
        );
      } else {
        c.closed('T5.buyer.resolvida', 'buyer resolvida com/sem efeito documentado',
            drow,
            lens: 'T5');
      }

      final b2p = await c.rest(
        'PATCH',
        'order_disputes?id=eq.$did',
        jwt: c.buyer2Jwt,
        body: {'status': 'resolvida'},
      );
      c.note('T7.b2.patch.dispute', 'B2 PATCH disputa B1', b2p.brief, lens: 'T7');
      if (b2p.ok && (await c.disputeRow(did))?['status'] == 'resolvida') {
        // only finding if B2 actually changed something they shouldn't
      } else {
        c.closed('T7.b2.patch.dispute', 'B2 não PATCHa disputa alheia', b2p.brief,
            lens: 'T7');
      }
    }
  }

  // T4: diminuir quantity abaixo do held
  if (oidB != null) {
    final o = await c.orderRow(oidB);
    final pid = o?['product_id']?.toString();
    if (pid != null) {
      final before = await c.productRow(pid);
      final dec = await c.rest(
        'PATCH',
        'products?id=eq.$pid',
        jwt: c.sellerJwt,
        body: {'quantity': 0},
      );
      final after = await c.productRow(pid);
      c.note('T4.decrease.held', 'PATCH quantity=0 com stock_units_applied>0', {
        'patch': dec.brief,
        'before': before?['quantity'],
        'after': after?['quantity'],
        'held': o?['stock_units_applied'],
      }, lens: 'T4');
      if (after?['quantity'] == 0 &&
          (o?['stock_units_applied'] is num) &&
          (o!['stock_units_applied'] as num) > 0) {
        c.hold(
          id: 'T4-Q6-DECREASE-BELOW-HELD',
          lens: 'T4',
          severity: 'P2',
          title: 'Q6 só bloqueia aumento — seller põe quantity=0 com encomenda a segurar stock',
          actor: 'seller JWT',
          pre: 'order pago stock_units_applied=1',
          repro: 'PATCH products quantity=0',
          expected: 'chão ≥ unidades em encomendas activas',
          obtained: after,
        );
      } else {
        c.closed('T4.decrease.held', 'decrease bloqueado ou inalterado', dec.brief,
            lens: 'T4');
      }
    }
  }

  await dumpJson('${outDir()}/pass4.json', {
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'wallets': await c.wallets(),
  });
  stdout.writeln(
      'PASS4 findings=${c.findings.length} closed=${c.blocked.length}');
  exit(0);
}
