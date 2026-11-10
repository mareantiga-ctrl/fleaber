/// REDTEAM_BLIND_BK pass3 — saturação: FP mid-return, wrap com order real, race, Edge vs BD.
/// Staging. Não corrigir.
import 'dart:io';
import '_rtbk.dart';

Future<void> main() async {
  final c = Rtbk.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  final w0 = await c.wallets();
  c.note('w0', 'pass3 wallets', w0);

  await _midReturnTrue(c);
  await _wrapRealOrder(c);
  await _edgeVsBd(c);
  await _raceShipDispute(c);
  await _unicodeWrap(c);

  await c.dumpAll('pass3.json');
  stdout.writeln(
    'pass3 done findings=${c.findings.length} blocked=${c.blocked.length} '
    'lenses=${c.lensesHit.toList()..sort()}',
  );
}

/// True mid-return: disputa ABERTA + pedido_devolucao, depois concluido.
Future<void> _midReturnTrue(Rtbk c) async {
  final paid = await c.setupPaid();
  if (paid == null) return;
  final oid = paid['order_id'].toString();
  if (!await c.toConcluido(oid)) return;
  final d = await c.openDispute(oid);
  if (!d.ok) {
    c.skip('BK2.mid.open', 'BK2', 'disputa falhou', d);
    return;
  }
  final ped = await c.patchOrder(oid, {'status': 'pedido_devolucao'}, jwt: c.buyerJwt);
  var row = await c.orderRow(oid);
  c.note('BK2.mid.pedido', 'após PATCH pedido', {
    'patch': ped.brief,
    'status': row?['status'],
  }, lens: 'BK2');
  if ('${row?['status']}'.toLowerCase() != 'pedido_devolucao') {
    c.skip('BK2.mid.not_pedido', 'BK2', 'não ficou pedido_devolucao', row);
    return;
  }
  final conc = await c.patchOrder(oid, {'status': 'concluido'}, jwt: c.buyerJwt);
  row = await c.orderRow(oid);
  if ('${row?['status']}'.toLowerCase() == 'concluido') {
    c.hold(
      id: 'BK2.buyer_concluido_mid_return',
      lens: 'BK2',
      severity: 'P1',
      title: 'Buyer força concluido com pedido_devolucao activo',
      actor: 'buyer JWT',
      pre: 'pedido_devolucao + disputa aberta',
      repro: 'PATCH concluido',
      expected: 'order_concluido_denied_during_return',
      obtained: {'patch': conc.brief, 'status': row?['status'], 'row': row},
    );
  } else {
    c.block('BK2.buyer_concluido_mid_return', 'BK2', 'concluido mid-return (disputa aberta)', {
      'patch': conc.brief,
      'status': row?['status'],
    });
  }
}

/// Wrap URL apontando para path de OUTRA order real do mesmo par B1-S1.
Future<void> _wrapRealOrder(Rtbk c) async {
  final a = await c.setupPaid();
  final b = await c.setupPaid();
  if (a == null || b == null) return;
  final oidA = a['order_id'].toString();
  final oidB = b['order_id'].toString();
  if (!await c.toConcluido(oidA) || !await c.toConcluido(oidB)) return;
  final dA = await c.openDispute(oidA);
  final dB = await c.openDispute(oidB);
  if (!dA.ok || !dB.ok) {
    c.skip('BK3.wrap2', 'BK3', 'disputas A/B falharam', {
      'a': dA.brief,
      'b': dB.brief,
    });
    return;
  }
  final didA = dA.firstId!;
  final nA = c.needle(c.buyerId, oidA);
  final nB = c.needle(c.buyerId, oidB);
  final wrap =
      '${c.storageBase}/$nB/secret.png?q=$nA';

  final patch = await c.patchDispute(didA, {
    'proof_photos': [wrap],
    'return_label_url': wrap,
  }, jwt: c.buyerJwt);
  final row = await c.disputeByOrder(oidA);
  final stored = '${row?['return_label_url']}' == wrap ||
      '${row?['proof_photos']}'.contains(nB);

  // GET object as seller / buyer — existe?
  final getSeller = await c.req(
    'GET',
    '/storage/v1/object/authenticated/fleaber_private/$nB/secret.png',
    jwt: c.sellerJwt,
  );
  final getBuyer = await c.req(
    'GET',
    '/storage/v1/object/authenticated/fleaber_private/$nB/secret.png',
    jwt: c.buyerJwt,
  );
  // List prefix B as seller
  final listB = await c.req(
    'POST',
    '/storage/v1/object/list/fleaber_private',
    jwt: c.sellerJwt,
    body: {'prefix': nB, 'limit': 10},
  );

  c.note('BK3.wrap_real', 'wrap A←B', {
    'wrap': wrap,
    'patch': patch.brief,
    'stored': stored,
    'getSeller': getSeller.brief,
    'getBuyer': getBuyer.brief,
    'listB': listB.brief,
    'label': row?['return_label_url'],
    'photos': row?['proof_photos'],
  }, lens: 'BK3');

  if (stored && (getSeller.ok || getBuyer.ok) && getSeller.status != 404) {
    c.hold(
      id: 'BK3.wrap_cross_order_read',
      lens: 'BK3',
      severity: 'P1',
      title: 'Wrap URL liga prova de outra order e o storage entrega',
      actor: 'buyer JWT',
      pre: 'duas orders B1-S1 com disputa',
      repro: 'PATCH proof/label wrap path B ?q=needle A; GET storage path B',
      expected: 'URL recusada ou GET 403/404',
      obtained: {
        'stored': stored,
        'getSeller': getSeller.brief,
        'getBuyer': getBuyer.brief,
      },
    );
  } else if (stored) {
    c.hold(
      id: 'BK3.wrap_bind_substring',
      lens: 'BK3',
      severity: 'P2',
      title: 'Bind proof/label é substring: URL de outra order persiste (ficheiro 404)',
      actor: 'buyer JWT',
      pre: 'duas disputas B1-S1',
      repro: 'PATCH return_label_url+proof_photos wrap path B?q=needle A',
      expected: 'position(needle) no path do object, não na query',
      obtained: {
        'url': wrap,
        'patch': patch.brief,
        'getSeller': getSeller.status,
        'getBuyer': getBuyer.status,
        'row': row,
      },
    );
  } else {
    c.block('BK3.wrap_real', 'BK3', 'wrap real order', patch);
  }
}

/// Edge refund-order status vs BD (exacto AY/BE — residual se cancelado vs outro).
Future<void> _edgeVsBd(Rtbk c) async {
  final paid = await c.setupPaid();
  if (paid == null) return;
  final oid = paid['order_id'].toString();
  final edge = await c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt);
  final row = await c.orderRow(oid);
  final edgeStatus = '${edge.map?['status']}'.toLowerCase();
  final bdStatus = '${row?['status']}'.toLowerCase();
  c.note('BK4.edge_vs_bd', 'refund-order vs BD', {
    'edge': edge.brief,
    'edgeStatus': edgeStatus,
    'bdStatus': bdStatus,
    'refund': row?['stripe_refund_id'],
    'units': row?['stock_units_applied'],
  }, lens: 'BK4');
  if (edge.ok &&
      edgeStatus == 'cancelado' &&
      bdStatus != 'cancelado' &&
      bdStatus != 'cancelled') {
    c.residual('AYBE.edge_cancelado_vs_bd', 'Edge status=cancelado vs BD=$bdStatus', {
      'edgeStatus': edgeStatus,
      'bdStatus': bdStatus,
      'oid': oid,
    });
  } else if (edge.ok && edgeStatus == bdStatus) {
    c.block('BK4.edge_status_matches_bd', 'BK4', 'Edge status = BD', {
      'status': bdStatus,
    });
  }
}

/// Race seller enviado ∥ buyer disputa (após concluido? disputa precisa concluido.
/// Aqui: pago, seller enviado ∥ buyer tenta disputa (deve falhar RLS) e
/// pago→mão concluido∥enviado.
Future<void> _raceShipDispute(Rtbk c) async {
  final paid = await c.setupPaid();
  if (paid == null) return;
  final oid = paid['order_id'].toString();
  await c.patchOrder(oid, {'shipping_method': 'entrega em mão'}, service: true);

  final raced = await Future.wait([
    c.patchOrder(oid, {'status': 'enviado'}, jwt: c.sellerJwt),
    c.patchOrder(oid, {'status': 'concluido'}, jwt: c.buyerJwt),
  ]);
  final row = await c.orderRow(oid);
  c.note('BK2.race_ship_conc', 'enviado∥concluido', {
    'seller': raced[0].brief,
    'buyer': raced[1].brief,
    'status': row?['status'],
    'shipped_at': row?['shipped_at'],
  }, lens: 'BK2');

  // After a concluido winner, race 2× disputa
  if ('${row?['status']}'.toLowerCase() == 'concluido' ||
      '${row?['status']}'.toLowerCase() == 'enviado') {
    if ('${row?['status']}'.toLowerCase() == 'enviado') {
      await c.patchOrder(oid, {'status': 'concluido'}, jwt: c.buyerJwt);
    }
    final r2 = await Future.wait([
      c.openDispute(oid),
      c.openDispute(oid),
    ]);
    final all = await c.rest(
      'GET',
      'order_disputes?order_id=eq.$oid&select=id,status',
      service: true,
    );
    c.note('BK7.race_2disp', '2× INSERT disputa', {
      'a': r2[0].brief,
      'b': r2[1].brief,
      'n': all.list.length,
    }, lens: 'BK7');
    if (all.list.length >= 2) {
      c.hold(
        id: 'BK7.race_two_disputes',
        lens: 'BK7',
        severity: 'P1',
        title: 'Race 2× INSERT disputa criou 2 linhas',
        actor: 'buyer JWT ×2',
        pre: 'concluido sem disputa',
        repro: 'Future.wait 2× POST order_disputes',
        expected: '1 linha',
        obtained: {'n': all.list.length, 'a': r2[0].brief, 'b': r2[1].brief},
      );
    } else {
      c.block('BK7.race_two_disputes', 'BK7', 'race 2 disputas', {
        'n': all.list.length,
        'a': r2[0].status,
        'b': r2[1].status,
      });
    }
  }
}

Future<void> _unicodeWrap(Rtbk c) async {
  final paid = await c.setupPaid();
  if (paid == null) return;
  final oid = paid['order_id'].toString();
  if (!await c.toConcluido(oid)) return;
  final d = await c.openDispute(oid);
  if (!d.ok) return;
  final did = d.firstId!;
  final n = c.needle(c.buyerId, oid);
  final variants = <String, String>{
    'encoded_slash':
        '${c.storageBase}/${c.buyerId}%2f$oid/x.png',
    'dotdot':
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/authenticated/fleaber_private/order_disputes/../$n/x.png',
    'fleaber_open_redirect': 'https://fleaber.app/$n',
  };
  for (final e in variants.entries) {
    final h = await c.patchDispute(did, {'return_label_url': e.value}, jwt: c.buyerJwt);
    final after = await c.disputeByOrder(oid);
    final stored = '${after?['return_label_url']}' == e.value;
    if (h.ok && !h.noop && stored) {
      c.hold(
        id: 'BK3.unicode_${e.key}',
        lens: 'BK3',
        severity: 'P2',
        title: 'return_label variante ${e.key} persistiu',
        actor: 'buyer JWT',
        pre: 'disputa aberta',
        repro: 'PATCH return_label_url=${e.value}',
        expected: 'recusado',
        obtained: {'patch': h.brief, 'url': after?['return_label_url']},
      );
    } else {
      c.block('BK3.unicode_${e.key}', 'BK3', e.key, h);
    }
  }
}
