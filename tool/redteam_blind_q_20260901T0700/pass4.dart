/// PASS 4 — Q6 stock∩refund, Q8 composição, credit RPC, unlist vs dono UI.
import 'dart:io';

import '_rtq.dart';

void main() async {
  final env = loadEnv();
  final c = Rtq.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final w0 = await c.wallets();

  final oid = await c.payToEntregue(lens: 'Q6');
  if (oid == null) {
    stderr.writeln('no paid order');
    exit(4);
  }
  var o = await c.orderRow(oid);
  final pid = o?['product_id']?.toString();
  final stock0 = pid != null ? await c.productRow(pid) : null;
  c.note('p4.paid', 'paid entregue', {'order': o, 'stock': stock0}, lens: 'Q6');

  // Q6-a: seller unlist + is_sold while order still entregue (buyer "owns")
  if (pid != null) {
    final unlist = await c.rest(
      'PATCH',
      'products?id=eq.$pid',
      jwt: c.sellerJwt,
      body: {
        'list_on_marketplace': true,
        'is_sold': false,
        'quantity': 9,
      },
    );
    c.note('p4.q6.relist', 'seller relista qty=9 com encomenda entregue',
        unlist.brief,
        lens: 'Q6');
    final stockRelist = await c.productRow(pid);
    final oStill = await c.orderRow(oid);
    if (unlist.ok &&
        numOf(stockRelist?['quantity']) == 9 &&
        oStill?['status'] == 'entregue') {
      c.hold(
        id: 'RTQ-Q6-relist-while-buyer-holds',
        lens: 'Q6',
        severity: 'P1',
        title:
            'Artigo relistado (qty=9) enquanto a encomenda do comprador continua entregue',
        actor: 'seller JWT',
        pre: 'stock já foi decrementado no pago; comprador ainda dono na UI',
        repro: 'PATCH products quantity=9 list_on_marketplace=true',
        expected: 'qty imutável enquanto stock_units_applied na order activa',
        obtained: {'stock': stockRelist, 'order': oStill, 'stock0': stock0},
      );
    }
  }

  // Q6-b: credit_wallet_once JWT
  final credit = await c.rpc(
    'batata_credit_wallet_once',
    {
      'p_wallet_id': c.buyerId,
      'p_order_id': oid,
      'p_amount': 40,
      'p_type': 'reembolso',
      'p_description': '$prefix mint',
    },
    jwt: c.buyerJwt,
  );
  c.note('p4.credit.jwt', 'buyer credit_wallet_once', credit.brief, lens: 'Q8');
  final wCredit = await c.wallets();
  if (credit.ok && (wCredit['buyer'] ?? 0) >= (w0['buyer'] ?? 0) + 39) {
    c.hold(
      id: 'RTQ-Q8-jwt-credit-wallet-once',
      lens: 'Q8',
      severity: 'P0',
      title: 'Comprador minta carteira via batata_credit_wallet_once',
      actor: 'buyer JWT',
      pre: 'RPC service_role',
      repro: 'rpc batata_credit_wallet_once 40€',
      expected: 'not granted',
      obtained: {'rpc': credit.brief, 'w0': w0, 'w': wCredit},
    );
  }

  // Open disputa + offer 50 + race process_partial ∥ relist qty
  final ins = await c.rest('POST', 'order_disputes', jwt: c.buyerJwt, body: {
    'order_id': oid,
    'buyer_id': c.buyerId,
    'reason': 'em_falta',
    'description': '$prefix p4',
  });
  c.note('p4.dispute', 'abre disputa', ins.brief, lens: 'Q8');
  final did = ins.firstId;
  if (did != null) {
    await c.rest('PATCH', 'order_disputes?id=eq.$did', jwt: c.sellerJwt, body: {
      'seller_refund_percent': 50,
      'seller_offer_type': 'partial_refund',
      'seller_offer_set_by': c.sellerId,
    });
    if (pid != null) {
      final race = await parallel([
        c.rpc(
          'batata_process_partial_refund_dispute',
          {'p_order_id': oid},
          jwt: c.buyerJwt,
        ),
        c.rest('PATCH', 'products?id=eq.$pid', jwt: c.sellerJwt, body: {
          'quantity': 7,
          'list_on_marketplace': true,
        }),
        c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
          'status': 'devolvida',
        }),
      ]);
      c.note('p4.q8.race.triple', 'partial ∥ relist ∥ devolvida', {
        'partial': race[0].brief,
        'relist': race[1].brief,
        'devolvida': race[2].brief,
      }, lens: 'Q8');
      final oEnd = await c.orderRow(oid);
      final stockEnd = await c.productRow(pid);
      final wEnd = await c.wallets();
      final tx = await c.walletTxns(orderId: oid);
      c.note('p4.q8.ledger', 'contabilidade fechada', {
        'order': oEnd,
        'stock': stockEnd,
        'w0': w0,
        'wEnd': wEnd,
        'tx': tx.take(8).toList(),
        'pi': oEnd?['stripe_payment_intent_id'],
        'refund': oEnd?['stripe_refund_id'],
      }, lens: 'Q8');

      final buyerGain = (wEnd['buyer'] ?? 0) - (w0['buyer'] ?? 0);
      final stockJump = (numOf(stockEnd?['quantity']) ?? 0) >
          (numOf(stock0?['quantity']) ?? 0);
      final stillEntregue = oEnd?['status'] == 'entregue' ||
          oEnd?['status'] == 'pago' ||
          oEnd?['status'] == 'enviado' ||
          oEnd?['status'] == 'concluido';
      if (buyerGain > 0.01 && stockJump && stillEntregue) {
        c.hold(
          id: 'RTQ-Q8-wallet-and-stock-buyer-still-owns',
          lens: 'Q8',
          severity: 'P0',
          title:
              'Carteira creditada e stock relistado com o comprador ainda dono da encomenda',
          actor: 'buyer JWT + seller JWT',
          pre: 'Stripe TEST pago; disputa 50%',
          repro:
              'Future.wait process_partial + PATCH qty + PATCH devolvida',
          expected: 'um efeito: ou dinheiro ou stock, alinhado ao status',
          obtained: {
            'order': oEnd,
            'stock0': stock0,
            'stockEnd': stockEnd,
            'buyerGain': buyerGain,
            'tx': tx.take(6).toList(),
          },
        );
      }
    }
  }

  // Legitimate seller enviado on a FRESH unpaid? skip.
  // Confirm refund-order after 100% still the intended path — new paid order.
  final oid2 = await c.payToEntregue(lens: 'Q8');
  if (oid2 != null) {
    final o2 = await c.orderRow(oid2);
    c.note('p4.legit.paid2', 'segunda ordem Stripe', o2, lens: 'Q8');
    final ins2 = await c.rest('POST', 'order_disputes', jwt: c.buyerJwt, body: {
      'order_id': oid2,
      'buyer_id': c.buyerId,
      'reason': 'outro',
      'description': '$prefix 100offer',
    });
    final d2 = ins2.firstId;
    if (d2 != null) {
      await c.rest(
        'PATCH',
        'order_disputes?id=eq.$d2',
        jwt: c.sellerJwt,
        body: {
          'seller_refund_percent': 100,
          'seller_offer_type': 'return_and_partial_refund',
        },
      );
      final rf = await c.edge('refund-order', {'order_id': oid2}, jwt: c.sellerJwt);
      c.note('p4.legit.refund.after100', 'refund-order após oferta 100%',
          rf.brief,
          lens: 'Q8');
      final o2b = await c.orderRow(oid2);
      // If refund-order is blocked by open dispute, that's a product bind (seller cannot refund while dispute) — note only.
      c.note('p4.legit.refund.result', 'order após refund-order', o2b, lens: 'Q8');
    }
  }

  await dumpJson('${outDir()}/pass4.json', {
    'notes': c.notes,
    'findings': c.findings,
    'w0': w0,
    'wEnd': await c.wallets(),
  });
  stdout.writeln('PASS4 findings=${c.findings.length}');
  exit(0);
}
