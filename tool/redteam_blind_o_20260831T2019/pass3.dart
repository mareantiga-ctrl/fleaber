/// REDTEAM_BLIND_O pass 3 — observe + O2 reopen enviado + O3 stock/refund residual.
import 'dart:io';

import '_rto.dart';

Future<void> main() async {
  final c = Rto.fromEnv(loadEnv());
  await c.loginActors();

  const observe = <String, String>{
    'selfdeal': '3af995b1-1e91-432c-955f-d394bf64bbbe',
    'seller_offer_100': '10576d71-f0a7-4270-9bb1-b7a784b3a880',
    'return_fsm': '00a531cd-da81-4987-b794-c54efbacc42c',
    'reconcluido': 'ecc6161e-8fa9-4f1e-ac1c-40e01d1e0fba',
    'label': '00185e2c-68cb-4ccc-81ee-70aa453db2cc',
    'race_dev': 'fe1b050a-9173-4060-b7a9-bd4a94a6f876',
    'pass1_proof': '8e4b7057-ef6f-44bf-88c8-f5c2dd8e4489',
  };

  final observed = <String, Object?>{};
  for (final e in observe.entries) {
    final o = await c.orderRow(e.value);
    final pid = o?['product_id']?.toString();
    observed[e.key] = {
      'order': o,
      'product': pid == null ? null : await c.productRow(pid),
      'dispute': await c.disputeRow(e.value),
      'txns': await c.walletTxns(orderId: e.value),
    };
  }
  c.note('p3.observe', 'estado final pass2', observed, lens: 'O8');

  // ---- O2: seller re-enviado após pedido_devolucao ----
  final fx = await c.payAndComplete(lens: 'O2');
  if (fx == null) return;
  final pid = (await c.orderRow(fx))?['product_id']?.toString();
  final qty0 = pid == null ? null : (await c.productRow(pid))?['quantity'];
  await c.insertDispute(fx);
  final pd = await c.rest('PATCH', 'orders?id=eq.$fx', jwt: c.buyerJwt, body: {
    'status': 'pedido_devolucao',
  });
  final stPd = (await c.orderRow(fx))?['status'];
  final reEnv = await c.markEnviado(fx);
  final stEnv = await c.orderRow(fx);
  final relDuring = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': fx},
    jwt: c.buyerJwt,
  );
  c.note('p3.o2.reenviado', 'seller enviado após pedido_devolucao', {
    'pedido_dev': pd.brief,
    'status_after_pd': stPd,
    'reenviado': reEnv.brief,
    'order_after': stEnv,
    'release': relDuring.brief,
  }, lens: 'O2');
  if (stEnv?['status'] == 'enviado' && stPd == 'pedido_devolucao') {
    c.hold(
      id: 'RTO-O2-seller-abort-return',
      lens: 'O2',
      severity: 'P1',
      title: 'Vendedor marca enviado e aborta pedido de devolução',
      actor: 'seller JWT',
      pre: 'pago+concluido+disputa+pedido_devolucao',
      repro: 'PATCH status=enviado',
      expected: 'permanece pedido_devolucao (devolução em curso)',
      obtained: 'status=${stEnv?['status']}',
      evidence: {'order': stEnv, 'pre_status': stPd},
    );
  }

  // ---- O3: devolvida Stripe: stock vs wallet vs PI ----
  final g = await c.payAndComplete(lens: 'O3');
  if (g != null) {
    final o0 = await c.orderRow(g);
    final p0 = await c.productRow('${o0?['product_id']}');
    await c.insertDispute(g);
    await c.rest('PATCH', 'orders?id=eq.$g', jwt: c.buyerJwt, body: {
      'status': 'pedido_devolucao',
    });
    await c.rest('PATCH', 'orders?id=eq.$g', jwt: c.buyerJwt, body: {
      'status': 'em_devolucao',
    });
    await c.rest('PATCH', 'orders?id=eq.$g', jwt: c.buyerJwt, body: {
      'status': 'devolucao_entregue',
    });
    final w0 = await c.wallets();
    final dev = await c.rest('PATCH', 'orders?id=eq.$g', jwt: c.sellerJwt, body: {
      'status': 'devolvida',
    });
    final o1 = await c.orderRow(g);
    final p1 = await c.productRow('${o0?['product_id']}');
    final w1 = await c.wallets();
    final ref = await c.edge('refund-order', {'order_id': g}, jwt: c.sellerJwt);
    final rw = await c.rpc(
      'batata_refund_buyer_wallet_for_order',
      {'p_order_id': g},
      jwt: c.buyerJwt,
    );
    final listed = await c.e2e('list_stripe_refunds', {
      'payment_intent_id': o1?['stripe_payment_intent_id'],
    });
    c.note('p3.o3.devolvida_stripe', 'devolvida captura Stripe', {
      'qty0': p0?['quantity'],
      'sold0': p0?['is_sold'],
      'listed0': p0?['list_on_marketplace'],
      'dev': dev.brief,
      'order': o1,
      'qty1': p1?['quantity'],
      'sold1': p1?['is_sold'],
      'listed1': p1?['list_on_marketplace'],
      'delta_buyer': (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0),
      'delta_seller': (w1['seller'] ?? 0) - (w0['seller'] ?? 0),
      'txns': await c.walletTxns(orderId: g),
      'refund_order': ref.brief,
      'rpc_refund': rw.brief,
      'stripe_refunds': listed.brief,
    }, lens: 'O3');

    final qty0n = p0?['quantity'];
    final qty1n = p1?['quantity'];
    final db = (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0);
    final stockBack = qty1n is num && qty0n is num && qty1n > qty0n;
    final noStripe = o1?['stripe_refund_id'] == null;
    if (o1?['status'] == 'devolvida' && stockBack && db == 0 && noStripe) {
      c.hold(
        id: 'RTO-O3-devolvida-stock-sem-reembolso',
        lens: 'O3',
        severity: 'P1',
        title: 'devolvida relista stock sem reembolsar comprador nem anular Stripe',
        actor: 'seller JWT PATCH devolvida',
        pre: 'Stripe TEST capturado; comprador só marcou devolucao_entregue',
        repro: 'pedido_devolucao→em_devolucao→devolucao_entregue→devolvida',
        expected: 'refund Stripe ou wallet = captura; stock só depois do dinheiro voltar',
        obtained:
            'status=devolvida qty $qty0n→$qty1n Δbuyer=$db stripe_refund=null flags release=${o1?['wallet_release_processed_at']} refund=${o1?['wallet_refund_processed_at']}',
        evidence: {
          'order': o1,
          'product_before': p0,
          'product_after': p1,
          'refund_order': ref.brief,
        },
      );
    }
  }

  // ---- O6 proof_url persist (buyer+seller) ----
  final proofRow = await c.orderRow('8e4b7057-ef6f-44bf-88c8-f5c2dd8e4489');
  c.note('p3.o6.proof_persist', 'proof_url still evil?', proofRow?['proof_url'],
      lens: 'O6');
  if ('${proofRow?['proof_url']}'.contains('evil.example')) {
    c.hold(
      id: 'RTO-O6-proof-url-unvalidated',
      lens: 'O6',
      severity: 'P2',
      title: 'proof_url aceita URL arbitrária após pago (vendedor e comprador)',
      actor: 'seller/buyer JWT',
      pre: 'encomenda Stripe paga',
      repro: 'PATCH orders proof_url=https://evil.example/…',
      expected: 'domínio Fleaber / storage próprio, ou coluna imutável pós-pago',
      obtained: '${proofRow?['proof_url']}',
    );
  }

  // ---- O1 escalate from aberta (not terminal) ----
  final h = await c.payAndComplete(lens: 'O1');
  if (h != null) {
    await c.insertDispute(h);
    final esc = await c.rest(
      'PATCH',
      'order_disputes?order_id=eq.$h',
      jwt: c.buyerJwt,
      body: {
        'status': 'escalada_fleaber',
        'current_turn': 'administracao',
      },
    );
    final row = await c.disputeRow(h);
    c.note('p3.o1.escalate', 'escalate JWT', {
      'http': esc.brief,
      'dispute': row,
    }, lens: 'O1');
  }

  final out = {
    'auditor': 'REDTEAM_BLIND_O_DISPUTA_ENVIO_v1',
    'pass': 3,
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
    'wallets': await c.wallets(),
    'notes': c.notes,
    'findings': c.findings,
    'orders': c.createdOrderIds,
  };
  await dumpJson('${outDir()}/pass3.json', out);
  stdout.writeln('WROTE pass3.json findings=${c.findings.length}');
}
