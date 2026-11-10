/// RED TEAM CEGO DO pass1 — off-platform / Hub / listagem / hold pós-DHDM.
/// Matriz A1–A5 · B1–B5 · C1–C4 · D1–D2. Sem correções. Sem Fase 4.
import 'dart:io';

import '_rtdo.dart';

bool offDenied(HttpHit h) {
  final raw = h.body.toLowerCase();
  return h.status == 400 &&
      (raw.contains('off-platform') || raw.contains('off platform'));
}

bool opened(HttpHit h) {
  final sid = h.sessionId ?? '';
  return h.ok && sid.startsWith('cs_');
}

bool holdExceeds(HttpHit h) {
  final t = h.body.toLowerCase();
  return !h.ok &&
      (t.contains('hold_exceeds') ||
          t.contains('exceeds available') ||
          t.contains('qty_exceeds') ||
          t.contains('order_hold'));
}

bool notListed(HttpHit h) {
  return !h.ok && h.body.toLowerCase().contains('not listed');
}

Future<HttpHit> cpiOnce(
  Rtdo c,
  Future<HttpHit> Function() fn,
) async {
  var h = await fn();
  if (h.status == 429) {
    await Future<void>.delayed(const Duration(seconds: 2));
    h = await fn();
  }
  c.trackSession(h);
  return h;
}

String sidOf(HttpHit h, [Map<String, dynamic>? row]) {
  final a = h.sessionId ?? '';
  if (a.startsWith('cs_')) return a;
  final b = '${row?['stripe_checkout_session_id'] ?? ''}';
  return b.startsWith('cs_') ? b : a;
}

Future<void> main() async {
  final c = Rtdo.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  stdout.writeln('DO pass1 staging=${c.url} prefix=$prefix');
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final s1 = c.sellerId!;
  final s2 = c.seller2Id!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;

  await c.restoreSeller1Published();
  await c.setHub(s2, false);
  await c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
    'user_type': 'vendedor',
    'handle': 'rtdo1702s2',
  }, prefer: 'return=minimal');

  c.note('actors', 'ids', {
    'b': b1,
    's': s1,
    'b2': b2,
    's2': s2,
    's1_pub': (await c.profile(s1))?['hub_published'],
    's2_pub': (await c.profile(s2))?['hub_published'],
  }, lens: 'DO5');

  String? paidPid;
  String? paidOid;
  String? paidPi;

  try {
    await runA(c);
    final d1 = await runD1(c);
    paidPid = d1?.pid;
    paidOid = d1?.oid;
    paidPi = d1?.pi;
    await runB(c, paidPid: paidPid, paidOid: paidOid);
    await runC(c);
    await runD2(c);
  } finally {
    await c.endAllCreatedLives();
    await c.cancelOrders(c.createdOrderIds);
    await c.restoreSeller1Published();
    final after = await c.profile(s1);
    c.note('restore.s1', 'S1 hub_published after', after?['hub_published'],
        lens: 'DO5');
  }

  await c.dumpAll('pass1.json');
  await dumpJson('${outDir()}/probes.json', {
    'auditor': 'REDTEAM_BLIND_DO_PAYMETHOD_HUB_POS_DHDM_v1',
    'prefix': prefix,
    'n': c.probes.length,
    'classe_nova': c.probes.where((p) => p['classe_nova'] == true).length,
    'residual': c.probes.where((p) => p['residual'] == true).length,
    'findings': c.findings.length,
    'paid': {'oid': paidOid, 'pid': paidPid, 'pi': paidPi},
    'probes': c.probes,
  });
  stdout.writeln(
    'DONE probes=${c.probes.length} findings=${c.findings.length} '
    'classe_nova=${c.probes.where((p) => p['classe_nova'] == true).length} '
    'lenses=${c.lensesHit.toList()..sort()}',
  );
}

extension on Rtdo {
  Future<void> cancelOrders(Iterable<String> ids) async {
    for (final id in ids) {
      await rest(
        'PATCH',
        'orders?id=eq.$id',
        service: true,
        body: {'status': 'cancelado'},
        prefer: 'return=minimal',
      );
    }
  }
}

Future<({String pid, String oid})?> mkListed(
  Rtdo c, {
  required String tag,
  int qty = 2,
  double price = 12,
  String payment = 'Pagamento na app',
  String? jwt,
  String? buyer,
  bool listed = true,
  bool sold = false,
  bool serviceOrder = false,
  String status = 'reserva_pendente',
}) async {
  final pid = await c.createProduct(
    title: '$prefix-$tag',
    qty: qty,
    price: price,
    listed: listed,
    sold: sold,
  );
  if (pid == null) return null;
  final oid = await c.insertOrder(
    productId: pid,
    price: price,
    qty: 1,
    payment: payment,
    jwt: serviceOrder ? null : (jwt ?? c.buyerJwt),
    buyer: buyer ?? c.buyerId,
    service: serviceOrder,
    status: status,
  );
  if (oid == null) return null;
  return (pid: pid, oid: oid);
}

Future<void> runA(Rtdo c) async {
  // A1 BD off + CPI body card (mismatch) — classe nova
  final a1 = await mkListed(c, tag: 'a1-mismatch', payment: 'MB WAY', qty: 2);
  HttpHit? a1cpi;
  HttpHit? a1sql;
  Map<String, dynamic>? a1row;
  if (a1 != null) {
    a1sql = await c.sqlOff('MB WAY');
    a1cpi = await cpiOnce(
      c,
      () => c.checkout(
        orderId: a1.oid,
        productId: a1.pid,
        amount: 1,
        extra: {
          'payment_method': 'card',
          'payment_method_types': <String>['card'],
          'method': 'card',
        },
      ),
    );
    a1row = await c.orderRow(a1.oid);
  }
  final a1sid = a1cpi == null ? '' : sidOf(a1cpi, a1row);
  final a1opened = a1cpi != null && opened(a1cpi);
  final a1pm = '${a1row?['payment_method'] ?? ''}';
  if (a1opened) {
    c.hold(
      id: 'P1-A1',
      lens: 'DO1',
      severity: 'P1',
      title: 'CPI body card sobrepôs payment_method off na BD',
      actor: 'buyer JWT',
      pre: 'orders.payment_method=MB WAY',
      repro: 'CPI extra payment_method=card',
      expected: '400 off-platform; sem cs_; BD continua MB WAY',
      obtained: {
        'cpi': a1cpi?.brief,
        'sid': a1sid,
        'pm': a1pm,
        'sql': a1sql?.json,
      },
    );
  } else {
    c.block('A1', 'DO1', 'mismatch body card ignorado; BD off manda', {
      'cpi': a1cpi?.brief,
      'pm': a1pm,
      'sql': a1sql?.json,
    });
  }
  c.probe(
    id: 'A1',
    poco: 'DO-A',
    surfaces: 'orders + CPI body',
    action: 'BD payment_method=MB WAY + CPI body card',
    http: a1cpi?.brief ?? 'null',
    oracles: {
      'sql_off': a1sql?.json,
      'bd_pm': a1pm,
      'sid': a1sid,
      'status': a1row?['status'],
    },
    result: a1opened ? 'HOLD' : 'FAIL',
    lens: 'DO1',
    classeNova: true,
    countFinding: a1opened,
  );

  // A2 Pagamento na App + notes MB WAY — App never dies
  final a2 = await mkListed(c, tag: 'a2-notes', payment: 'Pagamento na app');
  HttpHit? a2notes;
  HttpHit? a2cpi;
  Map<String, dynamic>? a2row;
  if (a2 != null) {
    a2notes = await c.rest(
      'PATCH',
      'orders?id=eq.${a2.oid}',
      jwt: c.buyerJwt,
      body: {'notes': 'Pago por MB WAY amanhã'},
    );
    if (!a2notes.ok) {
      a2notes = await c.rest(
        'PATCH',
        'orders?id=eq.${a2.oid}',
        service: true,
        body: {'notes': 'Pago por MB WAY amanhã'},
      );
    }
    a2cpi = await cpiOnce(
      c,
      () => c.checkout(
        orderId: a2.oid,
        productId: a2.pid,
        amount: 1,
        extra: {
          'notes': 'MB WAY',
          'payment_note': 'MB WAY',
          'description': 'MB WAY',
        },
      ),
    );
    a2row = await c.orderRow(a2.oid);
  }
  final a2sid = a2cpi == null ? '' : sidOf(a2cpi, a2row);
  final a2opened = a2cpi != null && opened(a2cpi);
  final a2killed = a2cpi != null && offDenied(a2cpi);
  if (a2killed) {
    c.hold(
      id: 'P1-A2',
      lens: 'DO6',
      severity: 'P1',
      title: 'notes MB WAY matou Pagamento na App',
      actor: 'buyer JWT',
      pre: 'payment_method=Pagamento na app',
      repro: 'PATCH notes + CPI extra notes=MB WAY',
      expected: 'cs_ (App sempre pode)',
      obtained: {'cpi': a2cpi?.brief, 'notes_patch': a2notes?.brief},
    );
  } else {
    c.block('A2', 'DO6', 'App+notes MB WAY ainda abre Stripe', {
      'cpi': a2cpi?.brief,
      'opened': a2opened,
      'notes_patch': a2notes?.brief,
    });
  }
  c.probe(
    id: 'A2',
    poco: 'DO-A',
    surfaces: 'orders.notes + CPI',
    action: 'Pagamento na App + notes/body MB WAY',
    http: a2cpi?.brief ?? 'null',
    oracles: {
      'notes_patch': a2notes?.brief,
      'bd_pm': a2row?['payment_method'],
      'sid': a2sid,
      'killed_app': a2killed,
    },
    result: a2killed ? 'HOLD' : 'FAIL',
    lens: 'DO6',
    classeNova: true,
    countFinding: a2killed,
  );

  // A3 ZWSP / NBSP só no meio de card — não matar App
  const zwsp = 'ca\u200Brd';
  const nbsp = 'ca\u00A0rd';
  final a3sqlZ = await c.sqlOff(zwsp);
  final a3sqlN = await c.sqlOff(nbsp);
  final a3z = await mkListed(c, tag: 'a3-zwsp', payment: zwsp);
  HttpHit? a3cpiZ;
  Map<String, dynamic>? a3rowZ;
  if (a3z != null) {
    a3cpiZ = await cpiOnce(
      c,
      () => c.checkout(orderId: a3z.oid, productId: a3z.pid, amount: 1),
    );
    a3rowZ = await c.orderRow(a3z.oid);
  }
  final a3n = await mkListed(c, tag: 'a3-nbsp', payment: nbsp);
  HttpHit? a3cpiN;
  Map<String, dynamic>? a3rowN;
  if (a3n != null) {
    a3cpiN = await cpiOnce(
      c,
      () => c.checkout(orderId: a3n.oid, productId: a3n.pid, amount: 1),
    );
    a3rowN = await c.orderRow(a3n.oid);
  }
  final zOpen = a3cpiZ != null && opened(a3cpiZ);
  final nOpen = a3cpiN != null && opened(a3cpiN);
  final zKill = a3cpiZ != null && offDenied(a3cpiZ);
  final nKill = a3cpiN != null && offDenied(a3cpiN);
  final a3kill = zKill || nKill;
  if (a3kill) {
    c.hold(
      id: 'P1-A3',
      lens: 'DO6',
      severity: 'P1',
      title: 'ZWSP/NBSP no meio de card matou Pagamento na App',
      actor: 'buyer JWT',
      pre: 'payment_method=ca<ZWSP|NBSP>rd',
      repro: 'CPI',
      expected: 'cs_ (compacto card = plataforma)',
      obtained: {
        'zwsp': a3cpiZ?.brief,
        'nbsp': a3cpiN?.brief,
        'sql_z': a3sqlZ.json,
        'sql_n': a3sqlN.json,
      },
    );
  } else {
    c.block('A3', 'DO2', 'ZWSP/NBSP em card não mata App', {
      'zOpen': zOpen,
      'nOpen': nOpen,
      'sql_z': a3sqlZ.json,
      'sql_n': a3sqlN.json,
    });
  }
  c.probe(
    id: 'A3',
    poco: 'DO-A',
    surfaces: 'orders.payment_method + CPI',
    action: 'ZWSP U+200B e NBSP U+00A0 no meio de card',
    http: {'zwsp': a3cpiZ?.brief, 'nbsp': a3cpiN?.brief},
    oracles: {
      'sql_z': a3sqlZ.json,
      'sql_n': a3sqlN.json,
      'pm_z': a3rowZ?['payment_method'],
      'pm_n': a3rowN?['payment_method'],
      'sid_z': a3cpiZ == null ? '' : sidOf(a3cpiZ, a3rowZ),
      'sid_n': a3cpiN == null ? '' : sidOf(a3cpiN, a3rowN),
    },
    result: a3kill ? 'HOLD' : 'FAIL',
    lens: 'DO6',
    classeNova: true,
    countFinding: a3kill,
  );

  // A4 método array / JSON / número
  final a4pid = await c.createProduct(title: '$prefix-a4-type', qty: 2);
  HttpHit? a4arr;
  HttpHit? a4num;
  HttpHit? a4obj;
  HttpHit? a4cpi;
  Map<String, dynamic>? a4row;
  if (a4pid != null) {
    a4arr = await c.insertOrderRaw(
      productId: a4pid,
      payment: <String>['card'],
      jwt: c.buyerJwt,
    );
    a4num = await c.insertOrderRaw(
      productId: a4pid,
      payment: 1,
      jwt: c.buyerJwt,
    );
    a4obj = await c.insertOrderRaw(
      productId: a4pid,
      payment: {'type': 'card'},
      jwt: c.buyerJwt,
    );
    final a4ok = await c.insertOrder(
      productId: a4pid,
      payment: 'Pagamento na app',
      jwt: c.buyerJwt,
    );
    if (a4ok != null) {
      a4cpi = await cpiOnce(
        c,
        () => c.checkout(
          orderId: a4ok,
          productId: a4pid,
          amount: 1,
          extra: {'payment_method': <String>['card']},
        ),
      );
      a4row = await c.orderRow(a4ok);
    }
  }
  final a4persistArr = a4arr?.ok == true;
  final a4persistNum = a4num?.ok == true;
  final a4persistObj = a4obj?.ok == true;
  final a4opened = a4cpi != null && opened(a4cpi);
  final a4weirdSid = a4persistArr || a4persistNum || a4persistObj;
  if (a4weirdSid && a4opened) {
    c.hold(
      id: 'P2-A4',
      lens: 'DO1',
      severity: 'P2',
      title: 'payment_method não-string persistiu e CPI abriu',
      actor: 'buyer JWT',
      pre: 'POST orders payment_method array/número/objecto',
      repro: 'insert raw + CPI extra array',
      expected: 'insert 400; CPI usa só BD string',
      obtained: {
        'arr': a4arr?.brief,
        'num': a4num?.brief,
        'obj': a4obj?.brief,
        'cpi': a4cpi?.brief,
      },
    );
  } else {
    c.block('A4', 'DO1', 'tipo não-string rejeitado ou ignorado', {
      'arr': a4arr?.brief,
      'num': a4num?.brief,
      'obj': a4obj?.brief,
      'cpi': a4cpi?.brief,
    });
  }
  c.probe(
    id: 'A4',
    poco: 'DO-A',
    surfaces: 'orders insert + CPI extra',
    action: 'payment_method array / número / JSON',
    http: {
      'arr': a4arr?.brief,
      'num': a4num?.brief,
      'obj': a4obj?.brief,
      'cpi': a4cpi?.brief,
    },
    oracles: {
      'persist_arr': a4persistArr,
      'persist_num': a4persistNum,
      'persist_obj': a4persistObj,
      'bd_pm': a4row?['payment_method'],
      'sid': a4cpi == null ? '' : sidOf(a4cpi, a4row),
    },
    result: (a4weirdSid && a4opened) ? 'HOLD' : 'FAIL',
    lens: 'DO1',
    classeNova: true,
    countFinding: a4weirdSid && a4opened,
  );

  // A5 MB WAY + emoji / pontuação nova (não x/via)
  const emoji = 'MB WAY 🎉';
  const bang = 'MB WAY!!!';
  final a5sqlE = await c.sqlOff(emoji);
  final a5sqlB = await c.sqlOff(bang);
  final a5e = await mkListed(c, tag: 'a5-emoji', payment: emoji);
  HttpHit? a5cpiE;
  Map<String, dynamic>? a5rowE;
  if (a5e != null) {
    a5cpiE = await cpiOnce(
      c,
      () => c.checkout(orderId: a5e.oid, productId: a5e.pid, amount: 1),
    );
    a5rowE = await c.orderRow(a5e.oid);
  }
  final a5b = await mkListed(c, tag: 'a5-bang', payment: bang);
  HttpHit? a5cpiB;
  Map<String, dynamic>? a5rowB;
  if (a5b != null) {
    a5cpiB = await cpiOnce(
      c,
      () => c.checkout(orderId: a5b.oid, productId: a5b.pid, amount: 1),
    );
    a5rowB = await c.orderRow(a5b.oid);
  }
  final eOpen = a5cpiE != null && opened(a5cpiE);
  final bOpen = a5cpiB != null && opened(a5cpiB);
  if (eOpen || bOpen) {
    c.hold(
      id: 'P1-A5',
      lens: 'DO2',
      severity: 'P1',
      title: 'MB WAY + emoji/pontuação abriu Stripe',
      actor: 'buyer JWT',
      pre: 'payment_method wrap emoji/!!! (não x/via)',
      repro: 'CPI',
      expected: '400 off-platform; SQL true; sem cs_',
      obtained: {
        'emoji': a5cpiE?.brief,
        'bang': a5cpiB?.brief,
        'sql_e': a5sqlE.json,
        'sql_b': a5sqlB.json,
      },
    );
  } else {
    c.block('A5', 'DO2', 'emoji/pontuação off-platform 400', {
      'emoji': a5cpiE?.brief,
      'bang': a5cpiB?.brief,
      'sql_e': a5sqlE.json,
      'sql_b': a5sqlB.json,
    });
  }
  c.probe(
    id: 'A5',
    poco: 'DO-A',
    surfaces: 'orders.payment_method + CPI + RPC',
    action: 'MB WAY 🎉 e MB WAY!!!',
    http: {'emoji': a5cpiE?.brief, 'bang': a5cpiB?.brief},
    oracles: {
      'sql_e': a5sqlE.json,
      'sql_b': a5sqlB.json,
      'sid_e': a5cpiE == null ? '' : sidOf(a5cpiE, a5rowE),
      'sid_b': a5cpiB == null ? '' : sidOf(a5cpiB, a5rowB),
      'pm_e': a5rowE?['payment_method'],
      'pm_b': a5rowB?['payment_method'],
    },
    result: (eOpen || bOpen) ? 'HOLD' : 'FAIL',
    lens: 'DO2',
    classeNova: true,
    countFinding: eOpen || bOpen,
  );
}

Future<({String liveId, String itemId, String resId, String pid})?> hitchAccept(
  Rtdo c, {
  required String tag,
  required int stock,
  int acceptQty = 1,
  String? buyer,
  String? jwt,
}) async {
  final pid = await c.createProduct(
    title: '$prefix-$tag',
    qty: stock,
    listed: true,
    live: true,
  );
  if (pid == null) return null;
  final liveId = await c.createLive(title: '$prefix $tag');
  if (liveId == null) return null;
  final itemId = await c.createLiveItem(
    liveId: liveId,
    kind: 'marketplace_product',
    productId: pid,
    checkoutProductId: pid,
    title: '$prefix $tag item',
  );
  if (itemId == null) return null;
  final resId = await c.insertReservation(
    liveId: liveId,
    liveItemId: itemId,
    buyer: buyer ?? c.buyer2Id,
    jwt: jwt ?? c.buyer2Jwt,
    qty: acceptQty,
  );
  if (resId == null) return null;
  final acc = await c.acceptRes(resId);
  c.note('hitch.accept.$tag', 'accept', acc.brief, lens: 'DO3');
  return (liveId: liveId, itemId: itemId, resId: resId, pid: pid);
}

Future<Map<String, Object?>> hubOracle(Rtdo c, String pid) async {
  final prod = await c.productRow(pid);
  final hubAnon = await c.hubSku(pid, anon: true);
  final hubJwt = await c.hubSku(pid, jwt: c.buyerJwt);
  final sell = await c.hubSellable(pid);
  final held = await c.heldQty(pid);
  return {
    'prod_qty': prod?['quantity'],
    'is_sold': prod?['is_sold'],
    'listed': prod?['list_on_marketplace'],
    'hub_anon_n': c.hubN(hubAnon),
    'hub_jwt_n': c.hubN(hubJwt),
    'hub_anon': hubAnon.brief,
    'hub_jwt': hubJwt.brief,
    'sellable': sell.json,
    'held': held.json,
  };
}

Future<void> runB(Rtdo c, {String? paidPid, String? paidOid}) async {
  // B1 live accepted qty=1 → Hub 0 + insert deny (reteste 1 linha se OK)
  final b1h = await hitchAccept(c, tag: 'b1-hold1', stock: 1);
  Map<String, Object?> b1o = {};
  HttpHit? b1ins;
  HttpHit? b1cpi;
  HttpHit? b1fav;
  Map<String, dynamic>? b1res;
  if (b1h != null) {
    b1res = await c.resRow(b1h.resId);
    b1o = await hubOracle(c, b1h.pid);
    b1ins = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': b1h.pid,
      'price_total': 12.0,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    if (b1ins.firstId != null) c.createdOrderIds.add(b1ins.firstId!);
    if (b1ins.ok && b1ins.firstId != null) {
      b1cpi = await cpiOnce(
        c,
        () => c.checkout(
          orderId: b1ins!.firstId!,
          productId: b1h.pid,
          amount: 1,
        ),
      );
    }
    b1fav = await c.favorite(b1h.pid);
  }
  final b1hub0 = (b1o['hub_anon_n'] == 0) && (b1o['hub_jwt_n'] == 0);
  final b1deny = b1ins != null && (holdExceeds(b1ins) || denied(b1ins));
  final b1lie = !b1hub0 && b1deny;
  if (b1lie) {
    c.hold(
      id: 'P2-B1',
      lens: 'DO3',
      severity: 'P2',
      title: 'live accepted qty=1: Hub ainda mostra; checkout recusa',
      actor: 'buyer JWT + B2 live',
      pre: 'SKU qty=1 + reserva live accepted',
      repro: 'GET hub_products_public + POST orders + CPI',
      expected: 'Hub 0 e insert deny (alinhados)',
      obtained: {
        ...b1o,
        'insert': b1ins?.brief,
        'cpi': b1cpi?.brief,
        'res': b1res,
        'fav': b1fav?.brief,
      },
    );
  } else if (b1hub0 && b1deny) {
    c.block('B1', 'DO3', 'Hub 0 + insert deny (fecho DHDM)', {
      ...b1o,
      'insert': b1ins?.brief,
    });
  } else if (!b1hub0 && !b1deny) {
    c.hold(
      id: 'P1-B1',
      lens: 'DO3',
      severity: 'P1',
      title: 'live accepted qty=1: Hub mostra e checkout ainda vende',
      actor: 'buyer JWT',
      pre: 'SKU qty=1 live accepted',
      repro: 'Hub + insert + CPI',
      expected: 'Hub 0 e insert deny',
      obtained: {...b1o, 'insert': b1ins?.brief, 'cpi': b1cpi?.brief},
    );
  }
  c.probe(
    id: 'B1',
    poco: 'DO-B',
    surfaces: 'Hub + products + live_reservation + CPI/insert',
    action: 'live accepted qty=1 vs Hub vs insert',
    http: {'insert': b1ins?.brief, 'cpi': b1cpi?.brief, 'fav': b1fav?.brief},
    oracles: {...b1o, 'res': b1res, 'fav_ok': b1fav?.ok},
    result: b1lie || (!b1hub0 && !b1deny)
        ? 'HOLD'
        : (b1hub0 && b1deny ? 'FAIL' : 'FAIL'),
    lens: 'DO3',
    residual: b1hub0 && b1deny,
    classeNova: false,
    countFinding: b1lie || (!b1hub0 && !b1deny),
  );

  // B2 live accepted qty=1 de stock=2 — Hub ainda mostra? qty efectiva
  final b2h = await hitchAccept(c, tag: 'b2-partial', stock: 2);
  Map<String, Object?> b2o = {};
  HttpHit? b2ins1;
  HttpHit? b2ins2;
  HttpHit? b2cpi;
  Map<String, dynamic>? b2res;
  if (b2h != null) {
    b2res = await c.resRow(b2h.resId);
    b2o = await hubOracle(c, b2h.pid);
    b2ins1 = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': b2h.pid,
      'price_total': 12.0,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    if (b2ins1.firstId != null) c.createdOrderIds.add(b2ins1.firstId!);
    b2ins2 = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': b2h.pid,
      'price_total': 24.0,
      'quantity': 2,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    if (b2ins2.firstId != null) c.createdOrderIds.add(b2ins2.firstId!);
    if (b2ins1.ok && b2ins1.firstId != null) {
      b2cpi = await cpiOnce(
        c,
        () => c.checkout(
          orderId: b2ins1!.firstId!,
          productId: b2h.pid,
          amount: 1,
        ),
      );
    }
  }
  final b2show = (b2o['hub_anon_n'] == 1) || (b2o['hub_jwt_n'] == 1);
  final b2qty1ok = b2ins1?.ok == true;
  final b2qty2deny = b2ins2 != null && (holdExceeds(b2ins2) || denied(b2ins2));
  final b2eff = b2o['held'];
  final b2lie = b2show && !b2qty2deny;
  final b2hideWrong = !b2show && (b2o['prod_qty'] == 2);
  if (b2lie) {
    c.hold(
      id: 'P1-B2',
      lens: 'DO4',
      severity: 'P1',
      title: 'stock parcial: Hub mostra e qty=2 ainda vende',
      actor: 'buyer JWT',
      pre: 'qty=2 live accepted 1',
      repro: 'Hub + insert qty=1 e qty=2 + CPI',
      expected: 'Hub visível (efectivo=1); insert qty=1 OK; qty=2 deny',
      obtained: {
        ...b2o,
        'ins1': b2ins1?.brief,
        'ins2': b2ins2?.brief,
        'cpi': b2cpi?.brief,
      },
    );
  } else if (b2hideWrong && b2qty1ok) {
    c.hold(
      id: 'P2-B2',
      lens: 'DO4',
      severity: 'P2',
      title: 'stock parcial: Hub esconde leftover=1 que o checkout vende',
      actor: 'buyer JWT',
      pre: 'qty=2 live accepted 1',
      repro: 'Hub + insert qty=1',
      expected: 'Hub mostra (efectivo>0) alinhado com insert',
      obtained: {...b2o, 'ins1': b2ins1?.brief},
    );
  } else {
    c.block('B2', 'DO4', 'parcial: Hub/insert coerentes com efectivo', {
      ...b2o,
      'ins1': b2ins1?.brief,
      'ins2': b2ins2?.brief,
      'qty1ok': b2qty1ok,
      'qty2deny': b2qty2deny,
    });
  }
  c.probe(
    id: 'B2',
    poco: 'DO-B',
    surfaces: 'Hub + products + live accepted + CPI/insert',
    action: 'live accepted qty=1 de stock=2 — Hub vs qty efectiva',
    http: {
      'ins1': b2ins1?.brief,
      'ins2': b2ins2?.brief,
      'cpi': b2cpi?.brief,
    },
    oracles: {...b2o, 'res': b2res, 'held': b2eff},
    result: (b2lie || b2hideWrong) ? 'HOLD' : 'FAIL',
    lens: 'DO4',
    classeNova: true,
    countFinding: b2lie || (b2hideWrong && b2qty1ok),
  );

  // B3 order reservado marketplace hold → Hub
  final b3pid = await c.createProduct(title: '$prefix-b3-reservado', qty: 1);
  HttpHit? b3ins;
  Map<String, Object?> b3o = {};
  HttpHit? b3ins2;
  Map<String, dynamic>? b3row;
  if (b3pid != null) {
    b3ins = await c.rest('POST', 'orders', service: true, body: {
      'buyer_id': c.buyer2Id,
      'seller_id': c.sellerId,
      'product_id': b3pid,
      'price_total': 12.0,
      'quantity': 1,
      'status': 'reservado',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    if (b3ins.firstId != null) {
      c.createdOrderIds.add(b3ins.firstId!);
      b3row = await c.orderRow(b3ins.firstId!);
    }
    b3o = await hubOracle(c, b3pid);
    b3ins2 = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': b3pid,
      'price_total': 12.0,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    if (b3ins2.firstId != null) c.createdOrderIds.add(b3ins2.firstId!);
  }
  final b3hub0 = b3o['hub_anon_n'] == 0 && b3o['hub_jwt_n'] == 0;
  final b3deny = b3ins2 != null && (holdExceeds(b3ins2) || denied(b3ins2));
  final b3lie = !b3hub0 && b3deny;
  if (b3lie) {
    c.hold(
      id: 'P2-B3',
      lens: 'DO3',
      severity: 'P2',
      title: 'reservado marketplace: Hub mostra; insert recusa',
      actor: 'buyer JWT',
      pre: 'order status=reservado qty=1 stock=1',
      repro: 'GET hub_products_public + POST orders',
      expected: 'Hub 0 + insert deny',
      obtained: {...b3o, 'hold_order': b3row, 'ins2': b3ins2?.brief},
    );
  } else if (!b3hub0 && !b3deny) {
    c.hold(
      id: 'P1-B3',
      lens: 'DO3',
      severity: 'P1',
      title: 'reservado marketplace não segura stock no Hub nem no insert',
      actor: 'buyer JWT',
      pre: 'status=reservado',
      repro: 'Hub + insert',
      expected: 'Hub 0 + insert deny',
      obtained: {...b3o, 'ins2': b3ins2?.brief, 'row': b3row},
    );
  } else {
    c.block('B3', 'DO3', 'reservado: Hub 0 + insert deny', {
      ...b3o,
      'ins': b3ins?.brief,
      'ins2': b3ins2?.brief,
      'status': b3row?['status'],
    });
  }
  c.probe(
    id: 'B3',
    poco: 'DO-B',
    surfaces: 'Hub + products + orders.reservado + insert',
    action: 'order reservado marketplace hold vs Hub',
    http: {'hold': b3ins?.brief, 'ins2': b3ins2?.brief},
    oracles: {...b3o, 'row': b3row},
    result: (b3lie || (!b3hub0 && !b3deny)) ? 'HOLD' : 'FAIL',
    lens: 'DO3',
    classeNova: true,
    countFinding: b3lie || (!b3hub0 && !b3deny),
  );

  // B4 accept ∥ unlist ∥ Hub race
  final b4pid = await c.createProduct(
    title: '$prefix-b4-race',
    qty: 1,
    listed: true,
    live: true,
  );
  HttpHit? b4acc;
  HttpHit? b4unlist;
  HttpHit? b4hub;
  HttpHit? b4ins;
  Map<String, Object?> b4o = {};
  if (b4pid != null) {
    final liveId = await c.createLive(title: '$prefix b4');
    final itemId = liveId == null
        ? null
        : await c.createLiveItem(
            liveId: liveId,
            kind: 'marketplace_product',
            productId: b4pid,
            checkoutProductId: b4pid,
          );
    final resId = (liveId == null || itemId == null)
        ? null
        : await c.insertReservation(
            liveId: liveId,
            liveItemId: itemId,
            jwt: c.buyer2Jwt,
            buyer: c.buyer2Id,
          );
    if (resId != null) {
      final raced = await Future.wait([
        c.acceptRes(resId),
        c.rest(
          'PATCH',
          'products?id=eq.$b4pid',
          jwt: c.sellerJwt,
          body: {'list_on_marketplace': false},
        ),
        c.hubSku(b4pid, anon: true),
      ]);
      b4acc = raced[0];
      b4unlist = raced[1];
      b4hub = raced[2];
    }
    b4o = await hubOracle(c, b4pid);
    b4ins = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': b4pid,
      'price_total': 12.0,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    if (b4ins.firstId != null) c.createdOrderIds.add(b4ins.firstId!);
  }
  final b4hub0 = b4o['hub_anon_n'] == 0 && b4o['hub_jwt_n'] == 0;
  final b4deny = b4ins != null &&
      (holdExceeds(b4ins) || denied(b4ins) || notListed(b4ins));
  final b4lie = !b4hub0 && b4deny;
  if (b4lie) {
    c.hold(
      id: 'P2-B4',
      lens: 'DO3',
      severity: 'P2',
      title: 'race accept∥unlist: Hub mostra; insert recusa',
      actor: 'seller JWT + buyer JWT',
      pre: 'qty=1 pending res',
      repro: 'Future.wait accept ∥ unlist ∥ Hub GET; depois insert',
      expected: 'Hub 0 + insert deny',
      obtained: {
        ...b4o,
        'acc': b4acc?.brief,
        'unlist': b4unlist?.brief,
        'hub_race': b4hub?.brief,
        'ins': b4ins?.brief,
      },
    );
  } else {
    c.block('B4', 'DO3', 'race accept∥unlist: Hub/insert alinhados', {
      ...b4o,
      'acc': b4acc?.brief,
      'unlist': b4unlist?.brief,
      'ins': b4ins?.brief,
    });
  }
  c.probe(
    id: 'B4',
    poco: 'DO-B',
    surfaces: 'live accept ∥ unlist ∥ Hub + insert',
    action: 'Future.wait accept ∥ unlist ∥ Hub GET',
    http: {
      'acc': b4acc?.brief,
      'unlist': b4unlist?.brief,
      'hub_race': b4hub?.brief,
      'ins': b4ins?.brief,
    },
    oracles: b4o,
    result: b4lie ? 'HOLD' : 'FAIL',
    lens: 'DO3',
    classeNova: true,
    countFinding: b4lie,
  );

  // B5 pago leftover qty=1 → Hub 1 (feliz) — usa D1 se existir
  if (paidPid == null) {
    c.skip('B5', 'DO4', 'sem SKU pago D1', 'null');
    c.probe(
      id: 'B5',
      poco: 'DO-B',
      surfaces: 'Hub + products + orders pago',
      action: 'leftover qty=1 após pago',
      http: 'skip',
      oracles: '-',
      result: 'SKIP',
      lens: 'DO4',
      classeNova: true,
    );
    return;
  }
  final b5o = await hubOracle(c, paidPid);
  HttpHit? b5ins;
  HttpHit? b5cpi;
  b5ins = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': paidPid,
    'price_total': 12.0,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  if (b5ins.firstId != null) c.createdOrderIds.add(b5ins.firstId!);
  if (b5ins.ok && b5ins.firstId != null) {
    b5cpi = await cpiOnce(
      c,
      () => c.checkout(
        orderId: b5ins!.firstId!,
        productId: paidPid,
        amount: 1,
      ),
    );
  }
  final b5show = (b5o['hub_anon_n'] == 1) || (b5o['hub_jwt_n'] == 1);
  final b5qty = numOf(b5o['prod_qty']);
  final happy = b5show && b5qty == 1 && b5ins.ok;
  if (!happy) {
    c.hold(
      id: 'P2-B5',
      lens: 'DO4',
      severity: 'P2',
      title: 'após pago leftover: Hub/qty/insert desalinhados',
      actor: 'buyer JWT',
      pre: 'setup_paid_order initial_qty=2 → leftover 1',
      repro: 'Hub + products + insert + CPI oid=$paidOid',
      expected: 'Hub 1 linha; qty=1; insert OK',
      obtained: {
        ...b5o,
        'ins': b5ins.brief,
        'cpi': b5cpi?.brief,
        'paid_oid': paidOid,
      },
    );
  } else {
    c.block('B5', 'DO4', 'leftover pago: Hub 1 + insert OK', {
      ...b5o,
      'ins': b5ins.brief,
      'cpi': b5cpi?.brief,
    });
  }
  c.probe(
    id: 'B5',
    poco: 'DO-B',
    surfaces: 'Hub + products + order pago + CPI',
    action: 'pago leftover qty=1 → Hub 1',
    http: {'ins': b5ins.brief, 'cpi': b5cpi?.brief},
    oracles: {...b5o, 'paid_oid': paidOid, 'paid_pid': paidPid},
    result: happy ? 'FAIL' : 'HOLD',
    lens: 'DO4',
    classeNova: true,
    countFinding: !happy,
  );
}

Future<void> runC(Rtdo c) async {
  // C1 list_on_marketplace=true + is_sold=true
  final c1pid = await c.createProduct(
    title: '$prefix-c1-sold',
    qty: 1,
    listed: true,
    sold: true,
  );
  Map<String, Object?> c1o = {};
  HttpHit? c1ins;
  HttpHit? c1cpi;
  if (c1pid != null) {
    c1o = await hubOracle(c, c1pid);
    c1ins = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': c1pid,
      'price_total': 12.0,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    if (c1ins.firstId != null) c.createdOrderIds.add(c1ins.firstId!);
    if (c1ins.ok && c1ins.firstId != null) {
      c1cpi = await cpiOnce(
        c,
        () => c.checkout(
          orderId: c1ins!.firstId!,
          productId: c1pid,
          amount: 1,
        ),
      );
    }
  }
  final c1hub0 = c1o['hub_anon_n'] == 0 && c1o['hub_jwt_n'] == 0;
  final c1deny = c1ins != null && (denied(c1ins) || holdExceeds(c1ins));
  final c1lie = !c1hub0 || (c1ins?.ok == true && opened(c1cpi ?? c1ins!));
  if (!c1hub0) {
    c.hold(
      id: 'P2-C1',
      lens: 'DO5',
      severity: 'P2',
      title: 'is_sold=true ainda na vitrine Hub',
      actor: 'anon + buyer JWT',
      pre: 'list_on_marketplace=true is_sold=true',
      repro: 'GET hub_products_public + insert + CPI',
      expected: 'Hub 0 + insert deny',
      obtained: {...c1o, 'ins': c1ins?.brief, 'cpi': c1cpi?.brief},
    );
  } else {
    c.block('C1', 'DO5', 'sold+listed: Hub 0 + insert deny', {
      ...c1o,
      'ins': c1ins?.brief,
      'cpi': c1cpi?.brief,
    });
  }
  c.probe(
    id: 'C1',
    poco: 'DO-C',
    surfaces: 'Hub + products + CPI/insert',
    action: 'list_on_marketplace=true + is_sold=true',
    http: {'ins': c1ins?.brief, 'cpi': c1cpi?.brief},
    oracles: c1o,
    result: (!c1hub0 || (c1ins?.ok == true && !c1deny)) ? 'HOLD' : 'FAIL',
    lens: 'DO5',
    residual: c1hub0 && c1deny,
    classeNova: false,
    countFinding: !c1hub0 || (c1ins?.ok == true && !c1deny),
  );

  // C2 unpublish seller mid-browse + CPI
  final c2 = await mkListed(c, tag: 'c2-unpub', qty: 2);
  HttpHit? c2hubBefore;
  HttpHit? c2unpub;
  HttpHit? c2hubAfter;
  HttpHit? c2cpi;
  Map<String, Object?> c2oAfter = {};
  Map<String, dynamic>? c2row;
  if (c2 != null) {
    c2hubBefore = await c.hubSku(c2.pid, anon: true);
    c2unpub = await c.rpc('batata_publish_hub', {'p_publish': false},
        jwt: c.sellerJwt);
    c2hubAfter = await c.hubSku(c2.pid, anon: true);
    c2cpi = await cpiOnce(
      c,
      () => c.checkout(orderId: c2.oid, productId: c2.pid, amount: 1),
    );
    c2row = await c.orderRow(c2.oid);
    c2oAfter = await hubOracle(c, c2.pid);
    await c.rpc('batata_publish_hub', {'p_publish': true}, jwt: c.sellerJwt);
    await c.restoreSeller1Published();
  }
  final c2hid = c.hubN(c2hubAfter ?? HttpHit(0, '', [])) == 0;
  final c2open = c2cpi != null && opened(c2cpi);
  // Unpublish esconde Hub; marketplace listado ainda pode pagar.
  // Finding só se Hub AINDA mostra unpublished, ou se CPI abre E Hub
  // mente stock (não é o caso). Divergência Hub vs CPI com listed=true
  // é superfície distinta — documentar FAIL (não residual wrap).
  if (!c2hid) {
    c.hold(
      id: 'P2-C2',
      lens: 'DO5',
      severity: 'P2',
      title: 'unpublish: Hub ainda lista o SKU',
      actor: 'seller JWT + buyer CPI',
      pre: 'browse Hub depois batata_publish_hub(false)',
      repro: 'Hub GET + CPI',
      expected: 'Hub 0 após unpublish',
      obtained: {
        'before': c2hubBefore?.brief,
        'unpub': c2unpub?.brief,
        'after': c2hubAfter?.brief,
        'cpi': c2cpi?.brief,
        ...c2oAfter,
      },
    );
  } else {
    c.block('C2', 'DO5', 'unpublish esconde Hub; CPI marketplace documentado', {
      'before_n': c.hubN(c2hubBefore ?? HttpHit(0, '', [])),
      'after_n': c.hubN(c2hubAfter ?? HttpHit(0, '', [])),
      'cpi': c2cpi?.brief,
      'opened': c2open,
      'listed': c2oAfter['listed'],
    });
  }
  c.probe(
    id: 'C2',
    poco: 'DO-C',
    surfaces: 'Hub + profiles.hub_published + CPI',
    action: 'unpublish seller mid-browse + CPI encomenda já criada',
    http: {
      'unpub': c2unpub?.brief,
      'hub_before': c2hubBefore?.brief,
      'hub_after': c2hubAfter?.brief,
      'cpi': c2cpi?.brief,
    },
    oracles: {...c2oAfter, 'sid': c2cpi == null ? '' : sidOf(c2cpi, c2row)},
    result: c2hid ? 'FAIL' : 'HOLD',
    lens: 'DO5',
    classeNova: true,
    countFinding: !c2hid,
  );

  // C3 favorite product unpublished
  final c3pid = await c.createProduct(
    seller: c.seller2Id,
    title: '$prefix-c3-unpub-fav',
    qty: 2,
    listed: true,
  );
  HttpHit? c3fav;
  HttpHit? c3hub;
  HttpHit? c3allowed;
  if (c3pid != null) {
    c3hub = await c.hubSku(c3pid, anon: true);
    c3allowed = await c.rpc(
      'batata_product_is_favorite_allowed',
      {'p_product_id': c3pid},
      service: true,
    );
    c3fav = await c.favorite(c3pid);
  }
  final c3deny = c3fav != null && denied(c3fav);
  if (!c3deny && c3fav?.ok == true) {
    c.hold(
      id: 'P2-C3',
      lens: 'DO5',
      severity: 'P2',
      title: 'favorite aceita SKU de loja unpublished',
      actor: 'buyer JWT',
      pre: 'S2 hub_published=false SKU listed',
      repro: 'POST favorites',
      expected: '403',
      obtained: {
        'fav': c3fav?.brief,
        'hub': c3hub?.brief,
        'allowed': c3allowed?.json,
      },
    );
  } else {
    c.block('C3', 'DO5', 'favorite unpublished 403', {
      'fav': c3fav?.brief,
      'hub': c3hub?.brief,
      'allowed': c3allowed?.json,
    });
  }
  c.probe(
    id: 'C3',
    poco: 'DO-C',
    surfaces: 'favorites + Hub + unpublished shop',
    action: 'favorite product unpublished',
    http: c3fav?.brief ?? 'null',
    oracles: {
      'hub_n': c.hubN(c3hub ?? HttpHit(0, '', [])),
      'allowed': c3allowed?.json,
    },
    result: c3deny ? 'FAIL' : 'HOLD',
    lens: 'DO5',
    residual: c3deny,
    classeNova: false,
    countFinding: !c3deny,
  );

  // C4 hub_products_public anon vs JWT divergência
  final c4pub = await c.createProduct(title: '$prefix-c4-pub', qty: 2);
  final c4sold = await c.createProduct(
    title: '$prefix-c4-sold',
    qty: 1,
    listed: true,
    sold: true,
  );
  final c4unpub = await c.createProduct(
    seller: c.seller2Id,
    title: '$prefix-c4-unpub',
    qty: 1,
    listed: true,
  );
  final hitch = await hitchAccept(c, tag: 'c4-hold', stock: 1);
  Future<Map<String, Object?>> pair(String? pid, String tag) async {
    if (pid == null) return {'tag': tag, 'anon_n': -1, 'jwt_n': -1};
    final a = await c.hubSku(pid, anon: true);
    final j = await c.hubSku(pid, jwt: c.buyerJwt);
    return {
      'tag': tag,
      'pid': pid,
      'anon_n': c.hubN(a),
      'jwt_n': c.hubN(j),
      'anon': a.brief,
      'jwt': j.brief,
      'diverge': c.hubN(a) != c.hubN(j),
    };
  }

  final pPub = await pair(c4pub, 'published');
  final pSold = await pair(c4sold, 'sold');
  final pUn = await pair(c4unpub, 'unpublished_s2');
  final pHold = await pair(hitch?.pid, 'live_hold');
  final diverge = [pPub, pSold, pUn, pHold]
      .any((e) => e['diverge'] == true);
  if (diverge) {
    c.hold(
      id: 'P2-C4',
      lens: 'DO5',
      severity: 'P2',
      title: 'hub_products_public anon ≠ JWT',
      actor: 'anon vs buyer JWT',
      pre: 'SKU published / sold / unpublished / live-hold',
      repro: 'GET hub_products_public id=eq SKU anon e JWT',
      expected: 'mesma cardinalidade',
      obtained: {
        'pub': pPub,
        'sold': pSold,
        'unpub': pUn,
        'hold': pHold,
      },
    );
  } else {
    c.block('C4', 'DO5', 'anon e JWT concordam nas 4 faces', {
      'pub': pPub,
      'sold': pSold,
      'unpub': pUn,
      'hold': pHold,
    });
  }
  c.probe(
    id: 'C4',
    poco: 'DO-C',
    surfaces: 'hub_products_public anon vs JWT',
    action: 'published / sold / unpublished / live-hold',
    http: {
      'pub': pPub['anon'],
      'sold': pSold['anon'],
      'unpub': pUn['anon'],
      'hold': pHold['anon'],
    },
    oracles: {'pub': pPub, 'sold': pSold, 'unpub': pUn, 'hold': pHold},
    result: diverge ? 'HOLD' : 'FAIL',
    lens: 'DO5',
    classeNova: true,
    countFinding: diverge,
  );
}

Future<({String oid, String pid, String? pi})?> runD1(Rtdo c) async {
  final paid = await c.payToPago(lens: 'DO7', initialQty: 2);
  if (paid == null) {
    c.skip('D1', 'DO7', 'setup_paid_order falhou', 'null');
    c.probe(
      id: 'D1',
      poco: 'DO-D',
      surfaces: 'orders + Stripe TEST',
      action: '1× pago 4242 card limpo',
      http: 'null',
      oracles: '-',
      result: 'SKIP',
      lens: 'DO7',
      classeNova: true,
    );
    return null;
  }
  final row = await c.orderRow(paid.oid);
  final prod = await c.productRow(paid.pid);
  final st = '${row?['status']}';
  final cents = numOf(row?['amount_paid_cents']);
  final pi = '${row?['stripe_payment_intent_id'] ?? paid.pi ?? ''}';
  final qty = numOf(prod?['quantity']);
  final applied = numOf(row?['stock_units_applied']);
  final ok = st == 'pago' &&
      pi.startsWith('pi_') &&
      cents != null &&
      cents >= 50 &&
      qty == 1 &&
      applied == 1;
  if (!ok) {
    c.hold(
      id: 'P1-D1',
      lens: 'DO7',
      severity: 'P1',
      title: 'pago Stripe TEST incoerente (status/qty/PI)',
      actor: 'e2e setup_paid_order',
      pre: 'SKU listado card limpo initial_qty=2',
      repro: 'setup_paid_order',
      expected: 'status=pago PI pi_ qty 2→1 applied=1',
      obtained: {
        'oid': paid.oid,
        'pid': paid.pid,
        'status': st,
        'pi': pi,
        'cents': cents,
        'qty': qty,
        'applied': applied,
        'hit': paid.hit.brief,
      },
    );
  } else {
    c.block('D1', 'DO7', 'Stripe TEST pago 4242 coerente', {
      'oid': paid.oid,
      'pid': paid.pid,
      'pi': pi,
      'cents': cents,
      'qty': qty,
    });
  }
  c.probe(
    id: 'D1',
    poco: 'DO-D',
    surfaces: 'orders + products + Stripe TEST',
    action: '1× pago 4242 card limpo',
    http: paid.hit.brief,
    oracles: {
      'oid': paid.oid,
      'pid': paid.pid,
      'status': st,
      'pi': pi,
      'cents': cents,
      'qty': qty,
      'applied': applied,
    },
    result: ok ? 'FAIL' : 'HOLD',
    lens: 'DO7',
    classeNova: true,
    countFinding: !ok,
  );
  return (oid: paid.oid, pid: paid.pid, pi: pi);
}

Future<void> runD2(Rtdo c) async {
  const exact = 'MB WAY';
  final sql = await c.sqlOff(exact);
  final d2 = await mkListed(c, tag: 'd2-exact', payment: exact);
  HttpHit? cpi;
  Map<String, dynamic>? row;
  if (d2 != null) {
    cpi = await cpiOnce(
      c,
      () => c.checkout(orderId: d2.oid, productId: d2.pid, amount: 1),
    );
    row = await c.orderRow(d2.oid);
  }
  final sid = cpi == null ? '' : sidOf(cpi, row);
  final open = cpi != null && opened(cpi);
  final deny = cpi != null && offDenied(cpi);
  if (open) {
    c.hold(
      id: 'P1-D2',
      lens: 'DO1',
      severity: 'P1',
      title: 'MB WAY exact abriu Stripe',
      actor: 'buyer JWT',
      pre: 'payment_method exact MB WAY',
      repro: 'CPI',
      expected: '400 + sem sid',
      obtained: {'cpi': cpi?.brief, 'sql': sql.json, 'sid': sid},
    );
  } else {
    c.block('D2', 'DO1', 'MB WAY exact 400 sem sid', {
      'cpi': cpi?.brief,
      'sql': sql.json,
      'sid': sid,
    });
  }
  c.probe(
    id: 'D2',
    poco: 'DO-D',
    surfaces: 'orders.payment_method + CPI + RPC',
    action: 'off exact MB WAY → 400 + sem sid',
    http: cpi?.brief ?? 'null',
    oracles: {
      'sql': sql.json,
      'sid': sid,
      'pm': row?['payment_method'],
      'denied': deny,
    },
    result: open ? 'HOLD' : 'FAIL',
    lens: 'DO1',
    residual: !open,
    classeNova: false,
    countFinding: open,
  );
}
