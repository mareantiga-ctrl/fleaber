/// T3 / T4 / T5 / T8 — disputa parcial, stock, resolvida, Stripe TEST, URLs.
/// Staging only. Não corrige.
import 'dart:io';
import '_rtt.dart';

Future<Map<String, dynamic>?> _advanceToEntregue(Rtt c, String orderId) async {
  final ship = await c.rest(
    'PATCH',
    'orders?id=eq.$orderId',
    jwt: c.sellerJwt,
    body: {'status': 'enviado', 'shipping_method': 'CTT'},
  );
  c.note('T3.ship', 'seller PATCH enviado', ship.brief, lens: 'T3');
  final rec = await c.rest(
    'PATCH',
    'orders?id=eq.$orderId',
    jwt: c.buyerJwt,
    body: {'status': 'entregue'},
  );
  c.note('T3.entregue', 'buyer PATCH entregue', rec.brief, lens: 'T3');
  return c.orderRow(orderId);
}

Future<void> main() async {
  final c = Rtt.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final wStart = await c.wallets();
  c.note('T3.wallets.start', 'saldos iniciais', wStart, lens: 'T3');

  final paid = await c.setupPaidStripe();
  final oid = paid['order_id'];
  final pid = paid['product_id'];
  final pi = paid['pi'];
  if (oid == null || pid == null) {
    stderr.writeln('no paid fixture ${paid}');
    await dumpJson('${outDir()}/pass3.json', {'error': 'no_paid', 'paid': paid});
    exit(1);
  }

  var order = await c.orderRow(oid);
  c.note('T3.paid.row', 'order Stripe TEST', order, lens: 'T3');
  final qty0 = (await c.productRow(pid))?['quantity'];

  // T4/Q6: inflacionar stock com encomenda activa
  final inf = await c.rest(
    'PATCH',
    'products?id=eq.$pid',
    jwt: c.sellerJwt,
    body: {'quantity': 50},
  );
  final qty1 = (await c.productRow(pid))?['quantity'];
  c.note('T4.inflate.active', 'PATCH products.quantity=50 com order activa', {
    'patch': inf.brief,
    'qty0': qty0,
    'qty1': qty1,
    'stock_units_applied': order?['stock_units_applied'],
  }, lens: 'T4');
  if (qty1 is num && qty0 is num && qty1 > qty0) {
    c.hold(
      id: 'T4-Q6-INFLATE-ACTIVE',
      lens: 'T4',
      severity: 'P1',
      title: 'Seller inflaciona products.quantity com encomenda activa',
      actor: 'seller JWT',
      pre: 'order pago Stripe; qty=$qty0 stock_units=${order?['stock_units_applied']}',
      repro: 'PATCH products quantity=50',
      expected: 'product_quantity_increase_blocked_active_order',
      obtained: {'qty0': qty0, 'qty1': qty1, 'patch': inf.brief},
    );
  } else {
    c.closed('T4.inflate.active', 'Q6 bloqueou inflate', inf.brief, lens: 'T4');
  }

  // T5/T3: avançar para entregue + disputa
  order = await _advanceToEntregue(c, oid) ?? order;
  final disp = await c.insertDispute(orderId: oid);
  c.note('T3.dispute.insert', 'buyer INSERT disputa', disp.brief, lens: 'T3');
  var did = disp.firstId;
  if (did != null) c.createdDisputeIds.add(did);

  // T7: B2 tenta disputa na order de B1
  final dispB2 = await c.insertDispute(orderId: oid, jwt: c.buyer2Jwt);
  c.note('T7.b2.dispute', 'B2 INSERT disputa order B1', dispB2.brief,
      lens: 'T7');
  if (dispB2.ok && dispB2.firstId != null) {
    c.hold(
      id: 'T7-B2-DISPUTE-B1-ORDER',
      lens: 'T7',
      severity: 'P1',
      title: 'Segundo comprador abre disputa na encomenda de B1',
      actor: 'buyer2 JWT',
      pre: 'order B1 entregue',
      repro: 'POST order_disputes order_id=<B1> buyer_id=<B2>',
      expected: 'RLS recusa',
      obtained: dispB2.map,
    );
  } else {
    c.closed('T7.b2.dispute', 'B2 não insere disputa alheia', dispB2.brief,
        lens: 'T7');
  }

  if (did == null) {
    c.note('T3.dispute.missing', 'sem disputa — skip T3/T5 PATCH', disp.brief,
        lens: 'T3');
  } else {
    // T5/Q5: seller fecha resolvida
    final res1 = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {'status': 'resolvida'},
    );
    var drow = await c.disputeRow(did);
    c.note('T5.seller.resolvida', 'seller PATCH resolvida', {
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
        pre: 'disputa aberta; sem buyer_decision',
        repro: 'PATCH order_disputes status=resolvida',
        expected: 'status permanece aberta',
        obtained: drow,
      );
    } else {
      c.closed('T5.seller.resolvida', 'Q5 bloqueou resolvida seller', drow,
          lens: 'T5');
    }

    // T5 twist: seller escreve buyer_decision e depois resolvida
    final bd = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {'buyer_decision': 'accepted_partial_refund'},
    );
    drow = await c.disputeRow(did);
    c.note('T5.seller.buyer_decision', 'seller PATCH buyer_decision', {
      'patch': bd.brief,
      'row': drow,
    }, lens: 'T5');
    final wroteBd = drow?['buyer_decision'] == 'accepted_partial_refund';
    if (wroteBd) {
      final res2 = await c.rest(
        'PATCH',
        'order_disputes?id=eq.$did',
        jwt: c.sellerJwt,
        body: {'status': 'resolvida'},
      );
      drow = await c.disputeRow(did);
      c.note('T5.seller.resolvida.after.bd', 'seller resolvida após forjar decisão',
          {'patch': res2.brief, 'row': drow},
          lens: 'T5');
      if (drow?['status'] == 'resolvida') {
        c.hold(
          id: 'T5-Q5-FORGE-BUYER-DECISION',
          lens: 'T5',
          severity: 'P1',
          title:
              'Seller escreve buyer_decision e fecha resolvida (Q5 só olha o campo, não o autor)',
          actor: 'seller JWT',
          pre: 'disputa aberta',
          repro:
              'PATCH buyer_decision=accepted_partial_refund; PATCH status=resolvida',
          expected: 'seller não escreve buyer_decision nem fecha',
          obtained: drow,
        );
      }
    } else {
      c.closed('T5.seller.buyer_decision', 'seller não escreve buyer_decision',
          drow,
          lens: 'T5');
    }

    // T5: recusada
    final recu = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {'status': 'recusada'},
    );
    drow = await c.disputeRow(did);
    c.note('T5.seller.recusada', 'seller PATCH recusada', {
      'patch': recu.brief,
      'row': drow,
    }, lens: 'T5');
    if (drow?['status'] == 'recusada') {
      c.hold(
        id: 'T5-SELLER-RECUSADA',
        lens: 'T5',
        severity: 'P1',
        title: 'Vendedor marca disputa recusada',
        actor: 'seller JWT',
        pre: 'disputa não terminal',
        repro: 'PATCH order_disputes status=recusada',
        expected: 'só comprador/admin',
        obtained: drow,
      );
    } else {
      c.closed('T5.seller.recusada', 'seller recusada bloqueada', drow,
          lens: 'T5');
    }

    // T5: escalate + current_turn
    final esc = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {'status': 'escalada_fleaber', 'current_turn': 'administracao'},
    );
    drow = await c.disputeRow(did);
    c.note('T5.escalate', 'seller escalate', {'patch': esc.brief, 'row': drow},
        lens: 'T5');

    final adminForge = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {
        'admin_resolution': 'refund_buyer',
        'admin_resolution_note': 'forged',
      },
    );
    drow = await c.disputeRow(did);
    c.note('T5.admin.forge', 'seller PATCH admin_resolution', {
      'patch': adminForge.brief,
      'row': drow,
    }, lens: 'T5');
    if (drow?['admin_resolution'] != null) {
      c.hold(
        id: 'T5-ADMIN-FORGE',
        lens: 'T5',
        severity: 'P1',
        title: 'Seller grava admin_resolution',
        actor: 'seller JWT',
        pre: 'disputa aberta/escalada',
        repro: 'PATCH admin_resolution=refund_buyer',
        expected: 'campo restaurado ao OLD',
        obtained: drow,
      );
    } else {
      c.closed('T5.admin.forge', 'admin_resolution imutável para seller', drow,
          lens: 'T5');
    }

    // T3: seller oferta parcial 40%
    final offer = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {
        'seller_offer_type': 'partial_refund',
        'seller_refund_percent': 40,
        'status': 'respondida_vendedor',
      },
    );
    drow = await c.disputeRow(did);
    c.note('T3.seller.offer', 'seller oferta 40%', {
      'patch': offer.brief,
      'row': drow,
    }, lens: 'T3');

    // T3/Q8: parcial em entregue (deve exigir Stripe)
    final wBeforeEnt = await c.wallets();
    final partEnt = await c.rpc(
      'batata_process_partial_refund_dispute',
      {'p_order_id': oid, 'p_refund_percent': 40},
      jwt: c.buyerJwt,
    );
    final wAfterEnt = await c.wallets();
    final oAfterEnt = await c.orderRow(oid);
    final txEnt = await c.walletTxns(orderId: oid);
    c.note('T3.partial.entregue', 'parcial em entregue', {
      'rpc': partEnt.brief,
      'wallets': {'before': wBeforeEnt, 'after': wAfterEnt},
      'order': oAfterEnt,
      'tx': txEnt.take(6).toList(),
    }, lens: 'T3');
    final mintedEnt = (wAfterEnt['buyer'] ?? 0) > (wBeforeEnt['buyer'] ?? 0);
    if (mintedEnt &&
        (oAfterEnt?['stripe_refund_id'] == null ||
            '${oAfterEnt?['stripe_refund_id']}'.isEmpty)) {
      c.hold(
        id: 'T3-Q8-PARTIAL-ENTREGUE-WALLET',
        lens: 'T3',
        severity: 'P0',
        title: 'Parcial em entregue creditou carteira sem Stripe refund',
        actor: 'buyer JWT',
        pre: 'order entregue, PI capturado, oferta 40%',
        repro: 'rpc batata_process_partial_refund_dispute',
        expected: 'dispute_partial_refund_requires_stripe',
        obtained: {
          'rpc': partEnt.json,
          'wallets_before': wBeforeEnt,
          'wallets_after': wAfterEnt,
          'order': oAfterEnt,
        },
        evidence: {'pi': pi, 'tx': txEnt},
      );
    } else {
      c.closed('T3.partial.entregue', 'Q8 Stripe-required ou sem mint',
          partEnt.brief,
          lens: 'T3');
    }

    // T3 twist Q8: pedido_devolucao
    final pd = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: c.buyerJwt,
      body: {'status': 'pedido_devolucao'},
    );
    final oPd = await c.orderRow(oid);
    c.note('T3.pedido_devolucao', 'buyer PATCH pedido_devolucao', {
      'patch': pd.brief,
      'row': oPd,
    }, lens: 'T3');

    final wBeforePd = await c.wallets();
    final partPd = await c.rpc(
      'batata_process_partial_refund_dispute',
      {'p_order_id': oid},
      jwt: c.buyerJwt,
    );
    final wAfterPd = await c.wallets();
    final oAfterPd = await c.orderRow(oid);
    final txPd = await c.walletTxns(orderId: oid);
    c.note('T3.partial.pedido_devolucao', 'parcial após pedido_devolucao', {
      'rpc': partPd.brief,
      'status': oPd?['status'],
      'wallets': {'before': wBeforePd, 'after': wAfterPd},
      'order': oAfterPd,
    }, lens: 'T3');
    final mintedPd = (wAfterPd['buyer'] ?? 0) > (wBeforePd['buyer'] ?? 0);
    if (mintedPd &&
        (oAfterPd?['stripe_refund_id'] == null ||
            '${oAfterPd?['stripe_refund_id']}'.isEmpty)) {
      c.hold(
        id: 'T3-Q8-PEDIDO-DEVOLUCAO-WALLET',
        lens: 'T3',
        severity: 'P0',
        title:
            'Parcial em pedido_devolucao mintou carteira com PI Stripe ainda capturado',
        actor: 'buyer JWT',
        pre: 'order passou entregue→pedido_devolucao; oferta 40%; PI activo',
        repro:
            'PATCH status=pedido_devolucao; rpc batata_process_partial_refund_dispute',
        expected: 'dispute_partial_refund_requires_stripe (pós-envio/devolução)',
        obtained: {
          'rpc': partPd.json,
          'wallets_before': wBeforePd,
          'wallets_after': wAfterPd,
          'order': oAfterPd,
          'delta_buyer': (wAfterPd['buyer'] ?? 0) - (wBeforePd['buyer'] ?? 0),
        },
        evidence: {'pi': pi, 'tx': txPd},
      );
    } else {
      c.closed(
          'T3.partial.pedido_devolucao',
          'parcial pedido_devolucao bloqueado ou sem mint',
          partPd.brief,
          lens: 'T3');
    }

    // T6: race partial ∥ refund-order
    final raceHits = await parallel([
      c.rpc(
        'batata_process_partial_refund_dispute',
        {'p_order_id': oid},
        jwt: c.buyerJwt,
      ),
      c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt),
    ]);
    final oRace = await c.orderRow(oid);
    final wRace = await c.wallets();
    c.note('T6.partial.refund', 'race partial∥refund-order', {
      'partial': raceHits[0].brief,
      'refund': raceHits[1].brief,
      'order': oRace,
      'wallets': wRace,
    }, lens: 'T6');
    final stripeRf = '${oRace?['stripe_refund_id'] ?? ''}';
    if (mintedPd && stripeRf.isNotEmpty) {
      c.hold(
        id: 'T6-WALLET-AND-STRIPE-REFUND',
        lens: 'T6',
        severity: 'P0',
        title: 'Carteira creditada E stripe_refund_id presente no mesmo pedido',
        actor: 'buyer+seller paralelo',
        pre: 'parcial já mintou ou race',
        repro: 'Future.wait partial_refund ∥ refund-order',
        expected: 'um só caminho de dinheiro',
        obtained: {
          'partial': raceHits[0].json,
          'refund': raceHits[1].json,
          'order': oRace,
          'wallets': wRace,
        },
        evidence: {'pi': pi},
      );
    }

    // T5: buyer reabre
    final reopen = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.buyerJwt,
      body: {'status': 'aberta', 'buyer_decision': null},
    );
    drow = await c.disputeRow(did);
    c.note('T5.buyer.reopen', 'buyer tenta reabrir', {
      'patch': reopen.brief,
      'row': drow,
    }, lens: 'T5');

    // URLs — variantes novas (não #https:// exact)
    final urlCases = <String, String>{
      'newline':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/x\nhttps://evil.example/p',
      'query_wrap':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/x?next=https://evil.example/phish',
      'userinfo': 'https://evil.example@fleaber.app/storage/x',
      'wildcard_supabase':
          'https://attacker.supabase.co/storage/v1/object/public/phish',
      'encoded_slash':
          'https://fleaber.app%2f%2fevil.example/x',
      'backslash':
          'https://fleaber.app\\@evil.example/x',
      'data': 'data:text/html,https://evil.example',
      'tabfrag':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/x#/https://evil.example',
    };
    for (final e in urlCases.entries) {
      final po = await c.rest(
        'PATCH',
        'orders?id=eq.$oid',
        jwt: c.buyerJwt,
        body: {'proof_url': e.value},
      );
      final after = await c.orderRow(oid);
      final stored = after?['proof_url']?.toString();
      c.note('T3.url.proof.${e.key}', 'proof_url ${e.key}', {
        'patch': po.brief,
        'stored': stored,
      }, lens: 'T3');
      if (po.ok && stored == e.value) {
        final sev = (e.key == 'query_wrap' ||
                e.key == 'newline' ||
                e.key == 'wildcard_supabase' ||
                e.key == 'userinfo')
            ? 'P2'
            : 'P2';
        c.hold(
          id: 'T3-PROOF-URL-${e.key.toUpperCase()}',
          lens: 'T3',
          severity: sev,
          title: 'proof_url aceitou variante ${e.key}',
          actor: 'buyer JWT',
          pre: 'order paga',
          repro: 'PATCH orders.proof_url=${e.key}',
          expected: 'order_proof_url_denied',
          obtained: stored,
        );
      } else {
        c.closed('T3.url.proof.${e.key}', 'proof_url ${e.key} recusado',
            po.brief,
            lens: 'T3');
      }
      if (did != null) {
        final lab = await c.rest(
          'PATCH',
          'order_disputes?id=eq.$did',
          jwt: c.sellerJwt,
          body: {'return_label_url': e.value},
        );
        final dAfter = await c.disputeRow(did);
        final ls = dAfter?['return_label_url']?.toString();
        if (lab.ok && ls == e.value) {
          c.hold(
            id: 'T3-LABEL-URL-${e.key.toUpperCase()}',
            lens: 'T3',
            severity: 'P2',
            title: 'return_label_url aceitou variante ${e.key}',
            actor: 'seller JWT',
            pre: 'disputa',
            repro: 'PATCH order_disputes.return_label_url=${e.key}',
            expected: 'order_dispute_label_url_denied',
            obtained: ls,
          );
        } else {
          c.closed('T3.url.label.${e.key}', 'label ${e.key} recusado',
              lab.brief,
              lens: 'T3');
        }
      }
    }
  }

  // T4: inflate após tentar concluido (Q6 exclui concluido do held)
  final conc = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {'status': 'concluido'},
  );
  final oConc = await c.orderRow(oid);
  c.note('T4.concluido', 'buyer PATCH concluido', {
    'patch': conc.brief,
    'row': oConc,
  }, lens: 'T4');
  if (oConc?['status'] == 'concluido') {
    final inf2 = await c.rest(
      'PATCH',
      'products?id=eq.$pid',
      jwt: c.sellerJwt,
      body: {'quantity': 77},
    );
    final qty2 = (await c.productRow(pid))?['quantity'];
    c.note('T4.inflate.concluido', 'inflate após concluido', {
      'patch': inf2.brief,
      'qty': qty2,
    }, lens: 'T4');
    if (qty2 is num && qty2 >= 77) {
      c.hold(
        id: 'T4-Q6-INFLATE-CONCLUIDO',
        lens: 'T4',
        severity: 'P2',
        title: 'Q6 não conta concluido como held — seller repor stock vendido',
        actor: 'seller JWT',
        pre: 'order concluido com stock_units_applied>0',
        repro: 'PATCH products quantity=77 após concluido',
        expected: 'stock vendido não reaparece sem restore explícito',
        obtained: {'qty': qty2, 'order': oConc},
      );
    }
  }

  // Stripe observe
  final listed = await c.e2e('list_stripe_refunds', {
    'payment_intent_id': pi,
    'order_id': oid,
  });
  c.note('T3.stripe.refunds', 'list_stripe_refunds', listed.brief, lens: 'T3');

  final wEnd = await c.wallets();
  await dumpJson('${outDir()}/pass3.json', {
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'paid': paid,
    'wallets': {'start': wStart, 'end': wEnd},
    'stripe_refunds': listed.json,
  });
  stdout.writeln(
      'PASS3 findings=${c.findings.length} closed=${c.blocked.length}');
  exit(0);
}
