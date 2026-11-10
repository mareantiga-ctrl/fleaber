/// T3 T5 T8 + URL + disputa Stripe TEST
import 'dart:io';

import '_rtt.dart';

Future<void> main() async {
  final c = Rtt.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  try {
    await t3PartialOnPago(c);
    await t3PartialAfterReturnStatus(c);
    await t5AliasResolved(c);
    await t5ForgeBuyerDecision(c);
    await t5BuyerReopen(c);
    await t7B2Dispute(c);
    await t6PartialVsShip(c);
    await tUrlVariants(c);
  } finally {
    await c.endLives();
  }

  await dumpJson('${outDir()}/pass2.json', {
    'pass': 2,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
  });
  stdout.writeln('pass2 findings=${c.findings.length} blocked=${c.blocked.length}');
}

Future<Map<String, String?>> paidToEntregue(Rtt c, {String lens = 'T3'}) async {
  final paid = await c.setupPaidStripe();
  final oid = paid['order_id'];
  final pid = paid['product_id'];
  if (oid == null) return paid;
  if (pid != null) await c.ensureChat(pid);
  await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
    'shipping_method': 'Envio Transportadora (€3.50)',
  });
  final env = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
    'status': 'enviado',
  });
  c.note('$lens.enviado', 'seller marca enviado', env.brief, lens: lens);
  final ent = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
    'status': 'entregue',
  });
  c.note('$lens.entregue', 'buyer marca entregue', ent.brief, lens: lens);
  return paid;
}

Future<HttpHit> insertDispute(Rtt c, String orderId, {String? jwt, String? buyer}) {
  return c.rest('POST', 'order_disputes', jwt: jwt ?? c.buyerJwt, body: {
    'order_id': orderId,
    'buyer_id': buyer ?? c.buyerId,
    'reason': 'danificado',
    'status': 'aberta',
  });
}

Future<void> t3PartialOnPago(Rtt c) async {
  final paid = await c.setupPaidStripe();
  final oid = paid['order_id'];
  if (oid == null) return;
  final w0 = await c.wallets();
  final d = await insertDispute(c, oid);
  c.note('T3.pago.disp', 'INSERT disputa em pago', d.brief, lens: 'T3');
  if (!d.ok) {
    c.closed('T3-01', 'disputa em pago bloqueada (RLS)', d.brief, lens: 'T3');
    return;
  }
  if (d.firstId != null) c.createdDisputeIds.add(d.firstId!);
  final offer = await c.rest('PATCH', 'order_disputes?order_id=eq.$oid', jwt: c.sellerJwt, body: {
    'seller_refund_percent': 40,
    'seller_offer_type': 'partial_refund',
  });
  final rpc = await c.rpc('batata_process_partial_refund_dispute', {
    'p_order_id': oid,
  }, jwt: c.buyerJwt);
  final w1 = await c.wallets();
  final order = await c.orderRow(oid);
  c.note('T3.pago.rpc', 'parcial em pago', rpc.brief, lens: 'T3');
  final db = w1['buyer']! - w0['buyer']!;
  if (rpc.ok && db > 0 && (order?['stripe_refund_id'] == null || '${order?['stripe_refund_id']}' == '')) {
    c.hold(
      id: 'T3-01',
      lens: 'T3',
      severity: 'P0',
      title: 'Parcial em pago credita carteira sem Stripe refund (PI capturado)',
      actor: 'buyer JWT',
      pre: 'order Stripe TEST status=pago amount_paid_cents>0',
      repro: 'INSERT disputa + oferta 40% + rpc process_partial_refund_dispute',
      expected: 'plataforma capturada → Stripe; sem mint carteira',
      obtained: {
        'rpc': rpc.brief,
        'offer': offer.brief,
        'dBuyer': db,
        'w0': w0,
        'w1': w1,
        'order': order,
        'pi': paid['pi'],
      },
    );
  } else {
    c.closed('T3-01', 'parcial pago sem mint ou RPC fail', {
      'rpc': rpc.brief,
      'dBuyer': db,
      'order': order,
    }, lens: 'T3');
  }
}

Future<void> t3PartialAfterReturnStatus(Rtt c) async {
  final paid = await paidToEntregue(c);
  final oid = paid['order_id'];
  if (oid == null) return;
  final order0 = await c.orderRow(oid);
  final d = await insertDispute(c, oid);
  c.note('T3.ret.disp', 'INSERT disputa em entregue', {
    'http': d.brief,
    'order': order0,
  }, lens: 'T3');
  if (!d.ok) {
    c.closed('T3-02', 'disputa em entregue bloqueada', {
      'http': d.brief,
      'order': order0,
    }, lens: 'T3');
    return;
  }
  if (d.firstId != null) c.createdDisputeIds.add(d.firstId!);
  final offer = await c.rest('PATCH', 'order_disputes?order_id=eq.$oid', jwt: c.sellerJwt, body: {
    'seller_refund_percent': 40,
    'seller_offer_type': 'partial_refund',
  });
  c.note('T3.ret.offer', 'seller oferta 40%', offer.brief, lens: 'T3');
  final ret = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
    'status': 'pedido_devolucao',
  });
  c.note('T3.ret.status', 'buyer pedido_devolucao', ret.brief, lens: 'T3');
  final w0 = await c.wallets();
  final rpcEnt = await c.rpc('batata_process_partial_refund_dispute', {
    'p_order_id': oid,
  }, jwt: c.buyerJwt);
  c.note('T3.ret.rpc_if_entregue', 'parcial (status actual)', rpcEnt.brief, lens: 'T3');
  final order1 = await c.orderRow(oid);
  final w1 = await c.wallets();
  final db = w1['buyer']! - w0['buyer']!;
  final st = '${order1?['status']}'.toLowerCase();
  final noStripe = order1?['stripe_refund_id'] == null ||
      '${order1?['stripe_refund_id']}'.trim().isEmpty;
  if (rpcEnt.ok &&
      db > 0 &&
      noStripe &&
      (st.contains('devol') || st == 'pago')) {
    c.hold(
      id: 'T3-02',
      lens: 'T3',
      severity: 'P0',
      title: 'Parcial pós-envio em pedido_devolucao credita carteira; Q8 só bloqueia enviado/entregue/concluido',
      actor: 'buyer JWT',
      pre: 'Stripe TEST capturado; enviado→entregue; disputa+oferta 40%; status pedido_devolucao',
      repro: 'rpc batata_process_partial_refund_dispute após PATCH pedido_devolucao',
      expected: 'qualquer pós-envio plataforma capturada → Stripe',
      obtained: {
        'rpc': rpcEnt.brief,
        'dBuyer': db,
        'w0': w0,
        'w1': w1,
        'order': order1,
        'pi': paid['pi'],
        'txns': await c.walletTxns(orderId: oid),
      },
    );
  } else if (rpcEnt.ok && db > 0 && noStripe) {
    c.hold(
      id: 'T3-02b',
      lens: 'T3',
      severity: 'P0',
      title: 'Parcial pós-envio credita carteira sem stripe_refund_id',
      actor: 'buyer JWT',
      pre: 'Stripe TEST capturado; disputa 40%',
      repro: 'rpc batata_process_partial_refund_dispute',
      expected: 'Stripe partial refund',
      obtained: {
        'rpc': rpcEnt.brief,
        'dBuyer': db,
        'order': order1,
        'ret': ret.brief,
      },
    );
  } else {
    c.closed('T3-02', 'parcial pós-envio sem mint carteira', {
      'rpc': rpcEnt.brief,
      'ret': ret.brief,
      'dBuyer': db,
      'order': order1,
    }, lens: 'T3');
  }
}

Future<void> t5AliasResolved(Rtt c) async {
  final paid = await paidToEntregue(c, lens: 'T5');
  final oid = paid['order_id'];
  if (oid == null) return;
  final d = await insertDispute(c, oid);
  if (!d.ok) {
    c.closed('T5-01', 'sem disputa para alias', d.brief, lens: 'T5');
    return;
  }
  if (d.firstId != null) c.createdDisputeIds.add(d.firstId!);
  final aliases = ['resolved', 'fechada', 'closed', 'arquivada', 'concluida'];
  Map<String, dynamic>? last;
  HttpHit? hit;
  for (final a in aliases) {
    hit = await c.rest('PATCH', 'order_disputes?order_id=eq.$oid', jwt: c.sellerJwt, body: {
      'status': a,
    });
    final row = await c.rest(
      'GET',
      'order_disputes?order_id=eq.$oid&select=id,status,current_turn,buyer_decision,seller_refund_percent',
      service: true,
    );
    last = row.map;
    c.note('T5.alias.$a', 'seller PATCH status=$a', {
      'http': hit.brief,
      'row': last,
    }, lens: 'T5');
    if (hit.ok && '${last?['status']}'.toLowerCase() == a) {
      c.hold(
        id: 'T5-01',
        lens: 'T5',
        severity: 'P1',
        title: 'Seller fecha disputa via alias "$a" (Q5 só intercepta resolvida)',
        actor: 'seller JWT',
        pre: 'disputa aberta; sem buyer_decision',
        repro: 'PATCH order_disputes status=$a',
        expected: 'aliases terminais com a mesma guarda que resolvida',
        obtained: {'http': hit.brief, 'row': last},
      );
      return;
    }
  }
  c.closed('T5-01', 'aliases terminais recusados/revertidos', {
    'lastHttp': hit?.brief,
    'row': last,
  }, lens: 'T5');
}

Future<void> t5ForgeBuyerDecision(Rtt c) async {
  final paid = await paidToEntregue(c, lens: 'T5');
  final oid = paid['order_id'];
  if (oid == null) return;
  final d = await insertDispute(c, oid);
  if (!d.ok) {
    c.closed('T5-02', 'sem disputa para forge', d.brief, lens: 'T5');
    return;
  }
  if (d.firstId != null) c.createdDisputeIds.add(d.firstId!);
  final forge = await c.rest('PATCH', 'order_disputes?order_id=eq.$oid', jwt: c.sellerJwt, body: {
    'buyer_decision': 'accepted_partial_refund',
    'status': 'resolvida',
  });
  final row = await c.rest(
    'GET',
    'order_disputes?order_id=eq.$oid&select=id,status,buyer_decision,current_turn,seller_refund_percent',
    service: true,
  );
  c.note('T5.forge', 'seller PATCH buyer_decision+resolvida', forge.brief, lens: 'T5');
  final st = '${row.map?['status']}'.toLowerCase();
  final dec = '${row.map?['buyer_decision']}'.toLowerCase();
  if (forge.ok && st == 'resolvida' && dec.contains('accepted')) {
    c.hold(
      id: 'T5-02',
      lens: 'T5',
      severity: 'P1',
      title: 'Seller forja buyer_decision e fecha resolvida no mesmo PATCH',
      actor: 'seller JWT',
      pre: 'disputa aberta sem decisão comprador',
      repro:
          'PATCH order_disputes buyer_decision=accepted_partial_refund,status=resolvida',
      expected: 'buyer_decision só o comprador; Q5 não aceitar decisão forjada pelo seller',
      obtained: {'http': forge.brief, 'row': row.map},
    );
  } else {
    c.closed('T5-02', 'forge buyer_decision+resolvida bloqueado', {
      'http': forge.brief,
      'row': row.map,
    }, lens: 'T5');
  }
}

Future<void> t5BuyerReopen(Rtt c) async {
  final paid = await paidToEntregue(c, lens: 'T5');
  final oid = paid['order_id'];
  if (oid == null) return;
  final d = await insertDispute(c, oid);
  if (!d.ok) return;
  await c.rest('PATCH', 'order_disputes?order_id=eq.$oid', jwt: c.sellerJwt, body: {
    'buyer_decision': 'accepted_return',
    'status': 'resolvida',
  });
  final reopen = await c.rest('PATCH', 'order_disputes?order_id=eq.$oid', jwt: c.buyerJwt, body: {
    'status': 'aberta',
    'buyer_decision': null,
  });
  final row = await c.rest(
    'GET',
    'order_disputes?order_id=eq.$oid&select=id,status,buyer_decision',
    service: true,
  );
  c.note('T5.reopen', 'buyer reabre após terminal', reopen.brief, lens: 'T5');
  if (reopen.ok && '${row.map?['status']}'.toLowerCase() == 'aberta') {
    c.hold(
      id: 'T5-03',
      lens: 'T5',
      severity: 'P1',
      title: 'Comprador reabre disputa terminal',
      actor: 'buyer JWT',
      pre: 'disputa resolvida',
      repro: 'PATCH order_disputes status=aberta',
      expected: 'terminal imutável',
      obtained: {'http': reopen.brief, 'row': row.map},
    );
  } else {
    c.closed('T5-03', 'reabrir terminal bloqueado', {
      'http': reopen.brief,
      'row': row.map,
    }, lens: 'T5');
  }
}

Future<void> t7B2Dispute(Rtt c) async {
  final paid = await paidToEntregue(c, lens: 'T7');
  final oid = paid['order_id'];
  if (oid == null) return;
  final d = await insertDispute(c, oid, jwt: c.buyer2Jwt, buyer: c.buyer2Id);
  c.note('T7.b2.disp', 'B2 INSERT disputa na order de B1', d.brief, lens: 'T7');
  if (d.ok) {
    c.hold(
      id: 'T7-02',
      lens: 'T7',
      severity: 'P0',
      title: 'B2 abre disputa na encomenda de B1',
      actor: 'buyer2 JWT',
      pre: 'order B1 entregue Stripe TEST',
      repro: 'POST order_disputes order_id=<B1> buyer_id=B2',
      expected: 'INSERT só buyer da encomenda',
      obtained: d.brief,
    );
  } else {
    c.closed('T7-02', 'B2 disputa noutro order bloqueada', d.brief, lens: 'T7');
  }
}

Future<void> t6PartialVsShip(Rtt c) async {
  final paid = await c.setupPaidStripe();
  final oid = paid['order_id'];
  if (oid == null) return;
  if (paid['product_id'] != null) await c.ensureChat(paid['product_id']!);
  await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
    'shipping_method': 'Envio Transportadora (€3.50)',
  });
  await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
    'status': 'enviado',
  });
  await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
    'status': 'entregue',
  });
  final d = await insertDispute(c, oid);
  if (!d.ok) {
    c.closed('T6-02', 'sem disputa para race partial∥refund', d.brief, lens: 'T6');
    return;
  }
  await c.rest('PATCH', 'order_disputes?order_id=eq.$oid', jwt: c.sellerJwt, body: {
    'seller_refund_percent': 40,
    'seller_offer_type': 'partial_refund',
  });
  final w0 = await c.wallets();
  final raced = await parallel([
    c.rpc('batata_process_partial_refund_dispute', {'p_order_id': oid}, jwt: c.buyerJwt),
    c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt),
  ]);
  final w1 = await c.wallets();
  final order = await c.orderRow(oid);
  final txns = await c.walletTxns(orderId: oid);
  c.note('T6.partial_refund', 'partial RPC ∥ refund-order Edge', {
    'rpc': raced[0].brief,
    'edge': raced[1].brief,
    'dBuyer': w1['buyer']! - w0['buyer']!,
    'dSeller': w1['seller']! - w0['seller']!,
  }, lens: 'T6');
  final db = w1['buyer']! - w0['buyer']!;
  final hasStripe = '${order?['stripe_refund_id']}'.trim().isNotEmpty;
  if (db > 0 && hasStripe) {
    c.hold(
      id: 'T6-02',
      lens: 'T6',
      severity: 'P0',
      title: 'Race parcial carteira ∥ refund-order Stripe — duplo reembolso',
      actor: 'buyer JWT ∥ seller JWT',
      pre: 'disputa 40% em entregue Stripe TEST',
      repro: 'Future.wait process_partial_refund_dispute ∥ refund-order',
      expected: 'um único caminho de dinheiro',
      obtained: {
        'rpc': raced[0].brief,
        'edge': raced[1].brief,
        'dBuyer': db,
        'order': order,
        'txns': txns,
        'pi': paid['pi'],
      },
    );
  } else {
    c.closed('T6-02', 'race partial∥stripe sem duplo crédito', {
      'rpc': raced[0].brief,
      'edge': raced[1].brief,
      'dBuyer': db,
      'order': order,
    }, lens: 'T6');
  }
}

Future<void> tUrlVariants(Rtt c) async {
  final paid = await c.setupPaidStripe();
  final oid = paid['order_id'];
  if (oid == null) return;
  final variants = <String, String>{
    'other_supabase': 'https://abcdefghijklmnop.supabase.co/storage/v1/object/public/x',
    'query_https': 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/x?next=https://evil.example/phish',
    'at_userinfo': 'https://fleaber.app@evil.example/phish',
    'encoded_slash': 'https://fleaber.app%2F%2Fevil.example/phish',
    'backslash': r'https://fleaber.app\https://evil.example/phish',
    'newline': 'https://fleaber.app/\nhttps://evil.example/phish',
    'tabfrag': 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/x#/https://evil.example',
    'js': 'javascript:alert(1)',
  };
  for (final e in variants.entries) {
    final hit = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
      'proof_url': e.value,
    });
    final row = await c.rest(
      'GET',
      'orders?id=eq.$oid&select=id,proof_url,status',
      service: true,
    );
    final stored = '${row.map?['proof_url']}';
    c.note('URL.${e.key}', 'proof_url variant', {
      'http': hit.brief,
      'stored': stored,
    }, lens: 'T8');
    if (hit.ok && stored == e.value) {
      c.hold(
        id: 'T8-URL-${e.key}',
        lens: 'T8',
        severity: e.key == 'other_supabase' || e.key == 'at_userinfo' ? 'P2' : 'P2',
        title: 'proof_url aceita variante ${e.key} (não é #https:// exact)',
        actor: 'seller JWT',
        pre: 'order Stripe TEST paga',
        repro: 'PATCH orders.proof_url=${e.key}',
        expected: 'allowlist estrita do bucket Fleaber; sem wrap/query/userinfo',
        obtained: {'http': hit.brief, 'stored': stored},
      );
    } else {
      c.closed('URL-${e.key}', 'variant blocked', hit.brief, lens: 'T8');
    }
  }
  final dPaid = await paidToEntregue(c, lens: 'T8');
  final did = dPaid['order_id'];
  if (did == null) return;
  final disp = await insertDispute(c, did);
  if (!disp.ok) return;
  final lab = await c.rest('PATCH', 'order_disputes?order_id=eq.$did', jwt: c.sellerJwt, body: {
    'return_label_url':
        'https://abcdefghijklmnop.supabase.co/storage/v1/object/public/labels/x',
  });
  final drow = await c.rest(
    'GET',
    'order_disputes?order_id=eq.$did&select=id,return_label_url',
    service: true,
  );
  c.note('URL.label.other_sb', 'return_label_url outro projecto supabase', lab.brief,
      lens: 'T8');
  final storedLab = '${drow.map?['return_label_url']}';
  if (lab.ok && storedLab.contains('abcdefghijklmnop.supabase.co')) {
    c.hold(
      id: 'T8-URL-label-other-sb',
      lens: 'T8',
      severity: 'P2',
      title: 'return_label_url aceita qualquer *.supabase.co/storage (allowlist demasiado larga)',
      actor: 'seller JWT',
      pre: 'disputa aberta',
      repro: 'PATCH return_label_url=https://abcdefghijklmnop.supabase.co/storage/...',
      expected: 'só bucket do projecto Fleaber',
      obtained: {'http': lab.brief, 'row': drow.map},
    );
  } else {
    c.closed('URL-label-other-sb', 'label other supabase blocked', lab.brief, lens: 'T8');
  }
}
