/// PASS 2 — AR Stripe TEST pago + refund/release/payout. Variantes novas. Não corrige.
import 'dart:io';
import '_rtar.dart';

Future<void> main() async {
  final c = Rtar.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final w0 = await c.wallets();
  c.note('p2.snap', 'saldos', w0, lens: 'AR7');

  // ---------------------------------------------------------------------------
  // AR6 — cancel pós-pago AHAM (esperado 403, não 200 silencioso AL5)
  // ---------------------------------------------------------------------------
  final paidCan = await c.payToPago(lens: 'AR6');
  if (paidCan != null) {
    final canPago = await c.patchOrder(paidCan.oid, {'status': 'cancelado'},
        jwt: c.buyerJwt);
    final rowPago = await c.orderRow(paidCan.oid);
    c.note('ar6.cancel.pago', 'buyer PATCH cancelado em pago', {
      'http': canPago.status,
      'bodyStatus': canPago.map?['status'],
      'db': rowPago?['status'],
      'brief': canPago.brief,
    }, lens: 'AR6');
    if (canPago.status == 200 &&
        (rowPago?['status'] == 'cancelado' ||
            canPago.map?['status'] == 'cancelado')) {
      c.hold(
        id: 'AR6-cancel-pago-applied',
        lens: 'AR6',
        severity: 'P0',
        title: 'Buyer cancelou encomenda paga (estado mudou)',
        actor: 'buyer JWT',
        pre: 'status=pago PI capturado',
        repro: 'PATCH orders status=cancelado',
        expected: '403 order_cancel_denied_post_pay',
        obtained: {
          'http': canPago.status,
          'db': rowPago?['status'],
          'refund': rowPago?['stripe_refund_id'],
        },
      );
    } else if (canPago.status == 200) {
      // Exact AL5 — não HOLD como achado novo; nota de atrofia
      c.note('ar6.cancel.pago.silent200',
          'HTTP 200 silencioso (classe AL5) — não contar como achado AR', {
        'http': canPago.status,
        'db': rowPago?['status'],
      }, lens: 'AR6');
      c.block('AR6.cancel-pago-403', 'AR6',
          'AHAM 403 NÃO — ainda 200 silencioso (AL5 exact, não HOLD)',
          canPago.status);
    } else {
      c.block('AR6.cancel-pago', 'AR6', 'cancel pago recusado', {
        'http': canPago.status,
        'db': rowPago?['status'],
      });
    }

    await c.markMao(paidCan.oid);
    final conc = await c.patchOrder(paidCan.oid, {'status': 'concluido'},
        jwt: c.buyerJwt);
    c.note('ar6.concluido', 'buyer concluido (mão)', conc.brief, lens: 'AR6');
    final canConc = await c.patchOrder(paidCan.oid, {'status': 'cancelado'},
        jwt: c.buyerJwt);
    final rowConc = await c.orderRow(paidCan.oid);
    c.note('ar6.cancel.concluido', 'buyer PATCH cancelado em concluido', {
      'http': canConc.status,
      'db': rowConc?['status'],
      'brief': canConc.brief,
    }, lens: 'AR6');
    if (canConc.status == 200 && rowConc?['status'] == 'cancelado') {
      c.hold(
        id: 'AR6-cancel-concluido-applied',
        lens: 'AR6',
        severity: 'P0',
        title: 'Buyer cancelou encomenda concluida',
        actor: 'buyer JWT',
        pre: 'concluido',
        repro: 'PATCH cancelado',
        expected: '403',
        obtained: canConc.brief,
      );
    } else if (canConc.status >= 400) {
      c.block('AR6.cancel-concluido', 'AR6', 'cancel concluido 4xx',
          canConc.status);
    } else {
      c.note('ar6.cancel.concluido.200', '200 sem mudar estado', {
        'http': canConc.status,
        'db': rowConc?['status'],
      }, lens: 'AR6');
    }

    // Mass PATCH cancelado (order própria + dummy)
    final mass = await c.rest(
      'PATCH',
      'orders?id=in.(${paidCan.oid},00000000-0000-0000-0000-000000000099)',
      jwt: c.buyerJwt,
      body: {'status': 'cancelado'},
    );
    c.note('ar6.mass.cancel', 'PATCH id=in cancelado', mass.brief, lens: 'AR6');
  }

  // ---------------------------------------------------------------------------
  // AR5/AR6 — PATCH shipped_at=null depois enviado, depois refund-order
  // ---------------------------------------------------------------------------
  final paidShip = await c.payToPago(lens: 'AR5');
  if (paidShip != null) {
    final env = await c.patchOrder(paidShip.oid, {'status': 'enviado'},
        jwt: c.sellerJwt);
    c.note('ar5.enviado', 'seller enviado', env.brief, lens: 'AR5');
    final rowEnv = await c.orderRow(paidShip.oid);
    final unshipBuyer = await c.patchOrder(
      paidShip.oid,
      {'shipped_at': null},
      jwt: c.buyerJwt,
    );
    final unshipSeller = await c.patchOrder(
      paidShip.oid,
      {'shipped_at': null},
      jwt: c.sellerJwt,
    );
    final afterUnship = await c.orderRow(paidShip.oid);
    c.note('ar5.unship', 'PATCH shipped_at=null', {
      'buyer': unshipBuyer.brief,
      'seller': unshipSeller.brief,
      'before': rowEnv?['shipped_at'],
      'after': afterUnship?['shipped_at'],
    }, lens: 'AR5');
    final refAfterUnship = await c.refund(paidShip.oid);
    c.note('ar5.refund.after-unship', 'refund-order após unship',
        refAfterUnship.brief, lens: 'AR5');
    final rowRef = await c.orderRow(paidShip.oid);
    if (afterUnship?['shipped_at'] == null &&
        rowEnv?['shipped_at'] != null &&
        refundSucceeded(refAfterUnship)) {
      c.hold(
        id: 'AR5-unship-then-refund',
        lens: 'AR5',
        severity: 'P1',
        title: 'Seller/buyer limpou shipped_at e reembolsou Stripe pós-envio',
        actor: 'JWT + refund-order',
        pre: 'enviado com shipped_at selado',
        repro: 'PATCH shipped_at=null; POST refund-order',
        expected: 'shipped_at imutável; refund 403 shipped',
        obtained: {
          'unshipB': unshipBuyer.brief,
          'unshipS': unshipSeller.brief,
          'refund': refAfterUnship.brief,
          'status': rowRef?['status'],
          'rid': rowRef?['stripe_refund_id'],
        },
      );
    } else if (refundSucceeded(refAfterUnship) &&
        afterUnship?['shipped_at'] != null) {
      c.hold(
        id: 'AR5-refund-while-shipped',
        lens: 'AR5',
        severity: 'P1',
        title: 'refund-order em enviado com shipped_at intacto',
        actor: 'seller JWT',
        pre: 'enviado',
        repro: 'POST refund-order',
        expected: '403 order_refund_blocked_shipped',
        obtained: refAfterUnship.brief,
      );
    } else {
      c.block('AR5.unship-refund', 'AR5', 'unship/refund bloqueado', {
        'unshipB': unshipBuyer.status,
        'unshipS': unshipSeller.status,
        'refund': refAfterUnship.brief,
        'shipped_at': afterUnship?['shipped_at'],
      });
    }
  }

  // ---------------------------------------------------------------------------
  // AR6 — 2× refund-order em paralelo no mesmo pago (não sequencial AL)
  // ---------------------------------------------------------------------------
  final paidPar = await c.payToPago(lens: 'AR6');
  if (paidPar != null) {
    final pair = await parallel([
      c.refund(paidPar.oid, extra: {'amount': 99999, 'reverse_transfer': true}),
      c.refund(paidPar.oid, extra: {'refund_application_fee': true}),
    ]);
    final rowPar = await c.orderRow(paidPar.oid);
    final listed = paidPar.pi == null
        ? null
        : await c.listStripeRefunds(paidPar.pi!);
    c.note('ar6.parallel.refund', '2× refund-order //', {
      'a': pair[0].brief,
      'b': pair[1].brief,
      'status': rowPar?['status'],
      'rid': rowPar?['stripe_refund_id'],
      'stripe': listed?.brief,
    }, lens: 'AR6');
    final nOk = pair.where(refundSucceeded).length;
    final refundCount = listed?.map?['refund_count'];
    final nStripe = refundCount is num ? refundCount.toInt() : -1;
    if (nStripe > 1) {
      c.hold(
        id: 'AR6-parallel-double-stripe-refund',
        lens: 'AR6',
        severity: 'P0',
        title: 'Dois refunds Stripe no mesmo PI (race refund-order)',
        actor: 'seller JWT ×2',
        pre: 'pago 590¢',
        repro: 'POST refund-order // ×2',
        expected: '1 refund idempotente',
        obtained: {
          'a': pair[0].brief,
          'b': pair[1].brief,
          'refund_count': nStripe,
        },
      );
    } else {
      c.block('AR6.parallel-refund', 'AR6', 'parallel refund', {
        'nOk': nOk,
        'nStripe': nStripe,
        'status': rowPar?['status'],
      });
    }
  }

  // ---------------------------------------------------------------------------
  // AR1 — prefixo 64 + 3× mesma key (não replay clássico 2× same-key)
  // ---------------------------------------------------------------------------
  final pad = 'K' * 64;
  final pfxA = await c.payout(
    amountCents: 100,
    key: '${pad}alphaAR1',
  );
  final pfxB = await c.payout(
    amountCents: 100,
    key: '${pad}betaAR1x',
  );
  c.note('ar1.prefix.payout', 'duas keys mesmo slice(0,64)', {
    'a': pfxA.brief,
    'b': pfxB.brief,
    'sameTid': pfxA.transferId != null &&
        pfxA.transferId == pfxB.transferId,
  }, lens: 'AR1');
  if (pfxA.ok &&
      pfxB.ok &&
      pfxA.transferId != null &&
      pfxB.transferId != null &&
      pfxA.transferId != pfxB.transferId) {
    c.note('ar1.prefix.two-transfers',
        'slice 64 NÃO colidiu — duas Transfers (keys distintas após trim?)', {
      'ta': pfxA.transferId,
      'tb': pfxB.transferId,
    }, lens: 'AR1');
  } else if (pfxA.ok &&
      pfxA.transferId != null &&
      pfxB.ok &&
      pfxA.transferId == pfxB.transferId &&
      pfxB.map?['idempotent'] == true) {
    c.hold(
      id: 'AR1-idempotency-prefix-64',
      lens: 'AR1',
      severity: 'P3',
      title: 'idempotency_key truncada a 64 funde duas intenções distintas',
      actor: 'seller JWT',
      pre: 'duas keys >64 chars com o mesmo prefixo',
      repro: 'POST create-connect-account amount=100 keys pad64+alpha / pad64+beta',
      expected: '2 Transfer ou 400 na 2.ª key',
      obtained: {
        'a': pfxA.brief,
        'b': pfxB.brief,
      },
    );
  } else {
    c.block('AR1.prefix-64', 'AR1', 'prefix 64', {
      'a': pfxA.brief,
      'b': pfxB.brief,
    });
  }

  final triKey = '${prefix}_tri_same_xx';
  final tri = await parallel([
    c.payout(amountCents: 100, key: triKey),
    c.payout(amountCents: 100, key: triKey),
    c.payout(amountCents: 100, key: triKey),
  ]);
  final tids = tri
      .map((h) => h.transferId)
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet();
  c.note('ar1.tri.samekey', '3× mesma key //', {
    'hits': tri.map((h) => h.brief).toList(),
    'uniqueTids': tids.toList(),
  }, lens: 'AR1');
  if (tids.length > 1) {
    c.hold(
      id: 'AR1-tri-samekey-multi-transfer',
      lens: 'AR1',
      severity: 'P0',
      title: '3 pedidos paralelos da mesma key criaram Transfers distintas',
      actor: 'seller JWT',
      pre: 'saldo ≥ 3,00 €',
      repro: 'POST create-connect-account ×3 mesma idempotency_key',
      expected: '1 transferId',
      obtained: {'tids': tids.toList(), 'hits': tri.map((h) => h.brief).toList()},
    );
  } else {
    c.block('AR1.tri-samekey', 'AR1', '3× same key 1 Transfer', {
      'n': tids.length,
      'tid': tids.isEmpty ? null : tids.first,
    });
  }

  // Crash inject after_stripe + key NOVA (não retry da mesma — variante)
  if (c.e2eSecret.length >= 16) {
    final crashKey = '${prefix}_crash_oldk';
    final crash = await c.payout(
      amountCents: 100,
      key: crashKey,
      extra: {'crash_inject': 'after_stripe_before_finish'},
      headers: {'x-fleaber-crash-inject-secret': c.e2eSecret},
    );
    c.note('ar1.crash.after-stripe', 'crash after_stripe_before_finish',
        crash.brief, lens: 'AR1');
    final newKey = await c.payout(
      amountCents: 100,
      key: '${prefix}_crash_newk',
    );
    final retryOld = await c.payout(amountCents: 100, key: crashKey);
    c.note('ar1.crash.newkey', 'key nova após crash + retry old', {
      'new': newKey.brief,
      'retryOld': retryOld.brief,
      'crashTid': crash.transferId,
      'newTid': newKey.transferId,
      'oldTid': retryOld.transferId,
    }, lens: 'AR1');
    final setT = {
      if (crash.transferId != null) crash.transferId,
      if (newKey.transferId != null) newKey.transferId,
      if (retryOld.transferId != null) retryOld.transferId,
    };
    // 2 Transfers = crash (1) + new key (1) + retry old same as crash. Esperado se saldo cobria.
    // P0 só se retry old CRIAR terceira Transfer diferente da do crash.
    if (crash.transferId != null &&
        retryOld.transferId != null &&
        crash.transferId != retryOld.transferId) {
      c.hold(
        id: 'AR1-crash-retry-new-transfer',
        lens: 'AR1',
        severity: 'P0',
        title: 'Retry da mesma key após crash Stripe criou 2.ª Transfer',
        actor: 'seller JWT + crash_inject',
        pre: 'after_stripe_before_finish',
        repro: 'payout crash; payout mesma key',
        expected: 'mesmo transferId',
        obtained: {
          'crash': crash.brief,
          'retry': retryOld.brief,
        },
      );
    } else {
      c.block('AR1.crash-retry', 'AR1', 'crash retry mesma Transfer', {
        'setT': setT.toList(),
        'newOk': newKey.ok,
      });
    }
  } else {
    c.skip('AR1.crash', 'AR1', 'sem crash secret', 'skip');
  }

  // ---------------------------------------------------------------------------
  // AR5/AR3/AR7 — hop devolvida (AHAM stock) + refund-order (AHAM gate)
  // ---------------------------------------------------------------------------
  final paidDev = await c.payToPago(lens: 'AR5', initialQty: 1);
  if (paidDev != null) {
    final qty0 = numOf((await c.productRow(paidDev.pid))?['quantity']);
    final applied0 = numOf((await c.orderRow(paidDev.oid))?['stock_units_applied']);
    final wBeforeHop = await c.wallets();
    final hop = await c.hopReturnToDevolvida(paidDev.oid, lens: 'AR5');
    final prodHop = await c.productRow(paidDev.pid);
    final qtyHop = numOf(prodHop?['quantity']);
    c.note('ar5.devolvida.stock', 'stock após devolvida (pré-refund)', {
      'status': hop?['status'],
      'qty0': qty0,
      'qtyHop': qtyHop,
      'applied0': applied0,
      'appliedHop': hop?['stock_units_applied'],
      'rid': hop?['stripe_refund_id'],
      'shipped': hop?['shipped_at'],
    }, lens: 'AR5');
    final restoredWithoutRefund = hop?['status'] == 'devolvida' &&
        hop?['stripe_refund_id'] == null &&
        (qtyHop ?? 0) > (qty0 ?? 0);
    if (restoredWithoutRefund) {
      c.hold(
        id: 'AR5-devolvida-stock-sem-refund',
        lens: 'AR5',
        severity: 'P1',
        title: 'devolvida restaurou stock com captura Stripe ainda viva',
        actor: 'seller JWT hops',
        pre: 'pago qty=1 applied=1, sem stripe_refund_id',
        repro: 'enviado→entregue→disputa→…→devolvida',
        expected: 'quantity inalterada até refund (AHAM)',
        obtained: {
          'qty0': qty0,
          'qtyHop': qtyHop,
          'applied': hop?['stock_units_applied'],
          'rid': hop?['stripe_refund_id'],
        },
      );
    } else {
      c.block('AR5.stock-pre-refund', 'AR5', 'stock não restaurou sem refund', {
        'qty0': qty0,
        'qtyHop': qtyHop,
        'status': hop?['status'],
      });
    }

    final wMid = await c.wallets();
    final dBuyerMid =
        (wMid['buyer'] ?? 0) - (wBeforeHop['buyer'] ?? 0);
    if (dBuyerMid > 0.05 && hop?['stripe_refund_id'] == null) {
      c.hold(
        id: 'AR3-mint-wallet-on-devolvida',
        lens: 'AR3',
        severity: 'P0',
        title: 'devolvida mintou carteira comprador sem refund Stripe',
        actor: 'trigger/RPC',
        pre: 'plataforma capturada, rid null',
        repro: 'PATCH devolvida (hops JWT)',
        expected: 'Δbuyer 0; buyer via Stripe',
        obtained: {'dBuyer': dBuyerMid, 'rid': hop?['stripe_refund_id']},
      );
    } else {
      c.block('AR3.mint-devolvida', 'AR3', 'sem mint wallet em devolvida',
          dBuyerMid);
    }

    final refDev = await c.refund(paidDev.oid);
    final afterRef = await c.orderRow(paidDev.oid);
    final prodRef = await c.productRow(paidDev.pid);
    final listed = paidDev.pi == null
        ? null
        : await c.listStripeRefunds(paidDev.pi!);
    c.note('ar5.refund.devolvida', 'refund-order após devolvida+shipped_at', {
      'refund': refDev.brief,
      'status': afterRef?['status'],
      'rid': afterRef?['stripe_refund_id'],
      'qty': prodRef?['quantity'],
      'applied': afterRef?['stock_units_applied'],
      'stripe': listed?.brief,
    }, lens: 'AR5');
    if (hop?['status'] == 'devolvida' &&
        !refundSucceeded(refDev) &&
        '${refDev.map?['code']}'.contains('shipped')) {
      c.hold(
        id: 'AR5-refund-devolvida-ainda-shipped',
        lens: 'AR5',
        severity: 'P2',
        title: 'refund-order em devolvida ainda bloqueado por shipped_at',
        actor: 'seller JWT',
        pre: 'AHAM: terminal devolvida antes de shipped_at',
        repro: 'POST refund-order',
        expected: '200 refund Stripe',
        obtained: refDev.brief,
      );
    } else if (refundSucceeded(refDev)) {
      c.block('AR5.refund-devolvida', 'AR5', 'refund terminal devolvida OK',
          refDev.brief);
    } else {
      c.block('AR5.refund-devolvida-other', 'AR5', 'refund devolvida',
          refDev.brief);
    }

    final wEnd = await c.wallets();
    final dBuyerEnd = (wEnd['buyer'] ?? 0) - (wBeforeHop['buyer'] ?? 0);
    if (dBuyerEnd > 0.05 && refundSucceeded(refDev)) {
      c.hold(
        id: 'AR3-stripe-plus-wallet',
        lens: 'AR3',
        severity: 'P0',
        title: 'Refund Stripe + crédito wallet no mesmo pedido',
        actor: 'seller refund-order + trigger',
        pre: 'devolvida então refund-order',
        repro: 'hops + POST refund-order',
        expected: 'Δbuyer 0 (dinheiro volta no cartão)',
        obtained: {'dBuyer': dBuyerEnd, 'refund': refDev.brief},
      );
    }
  }

  // ---------------------------------------------------------------------------
  // AR3/AR7 — release + refund + pedido_devolucao pós-release
  // ---------------------------------------------------------------------------
  final paidRel = await c.payToPago(lens: 'AR3');
  if (paidRel != null) {
    await c.markMao(paidRel.oid);
    final conc = await c.patchOrder(paidRel.oid, {'status': 'concluido'},
        jwt: c.buyerJwt);
    final rel = await c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': paidRel.oid,
    }, jwt: c.buyerJwt);
    final wRel = await c.wallets();
    c.note('ar3.release', 'concluido+release', {
      'conc': conc.brief,
      'rel': rel.brief,
      'dSeller': (wRel['seller'] ?? 0) - (w0['seller'] ?? 0),
    }, lens: 'AR3');
    final payTiny = await c.payout(
      amountCents: 100,
      key: '${prefix}_afterrel_xx',
    );
    c.note('ar3.payout.after-rel', 'payout 100¢ pós-release', payTiny.brief,
        lens: 'AR3');
    final ped = await c.patchOrder(paidRel.oid, {'status': 'pedido_devolucao'},
        jwt: c.buyerJwt);
    final disp = await c.insertDispute(paidRel.oid);
    final refPost = await c.refund(paidRel.oid);
    final claw = await c.rpc('batata_clawback_seller_wallet_for_order', {
      'p_order_id': paidRel.oid,
    }, jwt: c.buyerJwt);
    final rowPost = await c.orderRow(paidRel.oid);
    final wPost = await c.wallets();
    c.note('ar3.after-release', 'return/refund/clawback pós-release+payout', {
      'pedido': ped.brief,
      'disp': disp.brief,
      'refund': refPost.brief,
      'claw': claw.brief,
      'status': rowPost?['status'],
      'rid': rowPost?['stripe_refund_id'],
      'dBuyer': (wPost['buyer'] ?? 0) - (w0['buyer'] ?? 0),
    }, lens: 'AR3');
    if (refundSucceeded(refPost) && payTiny.transferId != null) {
      c.hold(
        id: 'AR3-payout-then-stripe-refund',
        lens: 'AR3',
        severity: 'P0',
        title: 'Payout Connect + refund Stripe no mesmo pedido',
        actor: 'seller',
        pre: 'release + Transfer 100¢ + refund-order',
        repro: 'release; payout; refund-order',
        expected: 'refund 403 concluido; Transfer sem refund da captura',
        obtained: {
          'payout': payTiny.brief,
          'refund': refPost.brief,
          'status': rowPost?['status'],
        },
      );
    } else {
      c.block('AR3.payout-then-refund', 'AR3', 'refund pós-release bloqueado', {
        'refund': refPost.brief,
        'pedido': ped.status,
        'payout': payTiny.transferId,
      });
    }
  }

  // Buyer / B2 refund alheio
  final paidX = await c.payToPago(lens: 'AR6');
  if (paidX != null) {
    final b = await c.refund(paidX.oid, jwt: c.buyerJwt);
    final b2 = await c.refund(paidX.oid, jwt: c.buyer2Jwt);
    c.note('ar6.cross.refund', 'buyer/B2 refund-order', {
      'b': b.brief,
      'b2': b2.brief,
    }, lens: 'AR6');
    if (refundSucceeded(b) || refundSucceeded(b2)) {
      c.hold(
        id: 'AR6-buyer-refund-alheio',
        lens: 'AR6',
        severity: 'P0',
        title: 'Não-vendedor executou refund-order',
        actor: 'buyer JWT',
        pre: 'order de B1-S1',
        repro: 'POST refund-order',
        expected: '403 Sem permissão',
        obtained: {'b': b.brief, 'b2': b2.brief},
      );
    } else {
      c.block('AR6.buyer-refund', 'AR6', 'buyer refund 403', b.status);
    }
  }

  await c.dumpAll('pass2.json');
  stdout.writeln(
      'PASS2 done findings=${c.findings.length} blocked=${c.blocked.length}');
  exit(0);
}
