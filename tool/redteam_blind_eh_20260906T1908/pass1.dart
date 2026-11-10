/// RED TEAM CEGO EH pass1 — off-platform / App / forge pós-OPEN.
/// Matriz A1–A7 · B1–B4 · C1–C5. Sem correções. Sem Fase 4.
import 'dart:io';

import '_rteh.dart';

Future<({String pid, String oid})?> mkOrder(
  Rteh c, {
  required String tag,
  String payment = 'Pagamento na App',
  bool service = false,
  String? jwt,
  String? buyer,
}) async {
  final pid = await c.createProduct(title: '$prefix-$tag');
  if (pid == null) return null;
  final oid = await c.insertOrder(
    productId: pid,
    payment: payment,
    jwt: service ? null : (jwt ?? c.buyerJwt),
    buyer: buyer ?? c.buyerId,
    service: service,
  );
  if (oid == null) return null;
  return (pid: pid, oid: oid);
}

Future<void> main() async {
  final c = Rteh.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  stdout.writeln('EH pass1 staging=${c.url} prefix=$prefix');
  await c.loginActors();
  await c.ensureBuyer2();
  c.note('actors', 'ids', {
    'b': c.buyerId,
    's': c.sellerId,
    'b2': c.buyer2Id,
  }, lens: 'EH-C');

  String? paidPid;
  String? paidOid;
  String? paidPi;

  try {
    await runA(c);
    await runB(c);
    final d = await runB4(c);
    paidPid = d?.pid;
    paidOid = d?.oid;
    paidPi = d?.pi;
    await runC(c);
  } finally {
    await c.cancelOrders(c.createdOrderIds);
  }

  await c.dumpAll('pass1.json');
  await dumpJson('${outDir()}/probes.json', {
    'auditor': 'REDTEAM_BLIND_EH_PAYMETHOD_POS_OPEN_v1',
    'prefix': prefix,
    'n': c.probes.length,
    'classe_nova': c.probes.where((p) => p['classe_nova'] == true).length,
    'residual': c.probes.where((p) => p['residual'] == true).length,
    'findings': c.findings,
    'paid': {'oid': paidOid, 'pid': paidPid, 'pi': paidPi},
    'probes': c.probes,
  });
  stdout.writeln(
    'DONE probes=${c.probes.length} findings=${c.findings.length} '
    'classe_nova=${c.probes.where((p) => p['classe_nova'] == true).length} '
    'lenses=${c.lensesHit.toList()..sort()}',
  );
}

Future<void> expectOffBlock(
  Rteh c, {
  required String id,
  required String lens,
  required String action,
  required String method,
  required HttpHit? cpi,
  required bool? sql,
  Map<String, dynamic>? row,
  Object? extraOracle,
  bool classeNova = true,
  bool residual = false,
}) async {
  final sid = cpi == null ? '' : sidOf(cpi, row);
  final openedCs = cpi != null && opened(cpi);
  final denied = cpi != null && offDenied(cpi);
  final pm = '${row?['payment_method'] ?? method}';
  if (openedCs) {
    c.hold(
      id: 'P2-$id',
      lens: lens,
      severity: 'P2',
      title: 'off-platform $method abriu Session Stripe',
      actor: 'buyer JWT',
      pre: 'order payment_method=$method',
      repro: 'RPC batata_is_off_platform_payment + create-payment-intent',
      expected: 'RPC true · CPI 400 sem cs_',
      obtained: {
        'sql': sql,
        'cpi': cpi?.brief,
        'sid': sid,
        'pm': pm,
      },
    );
  } else if (denied && sql == true) {
    c.block(id, lens, '$method 400 + RPC true sem sid', {
      'sql': sql,
      'cpi': cpi?.brief,
      'pm': pm,
    });
  } else {
    c.hold(
      id: 'P2-$id-align',
      lens: lens,
      severity: 'P2',
      title: 'RPC/CPI desalinhados ou recusa inesperada ($method)',
      actor: 'buyer JWT',
      pre: 'order payment_method=$method',
      repro: 'RPC + CPI',
      expected: 'RPC true e CPI 400 off-platform sem cs_',
      obtained: {
        'sql': sql,
        'cpi': cpi?.brief,
        'sid': sid,
        'denied': denied,
        'opened': openedCs,
      },
    );
  }
  c.probe(
    id: id,
    poco: 'EH-A',
    surfaces: 'orders.payment_method + CPI + RPC',
    action: action,
    http: {
      'cpi': cpi?.brief,
      'sql': sql,
    },
    oracles: {
      'pm': pm,
      'sid': sid,
      'sql': sql,
      if (extraOracle != null) 'extra': extraOracle,
    },
    result: openedCs || !(denied && sql == true) ? 'HOLD' : 'FAIL',
    lens: lens,
    classeNova: classeNova,
    residual: residual,
    countFinding: openedCs || !(denied && sql == true),
  );
}

Future<void> expectAppOpen(
  Rteh c, {
  required String id,
  required String lens,
  required String action,
  required String method,
  required HttpHit? cpi,
  required bool? sql,
  Map<String, dynamic>? row,
  bool classeNova = true,
}) async {
  final sid = cpi == null ? '' : sidOf(cpi, row);
  final openedCs = cpi != null && opened(cpi);
  final killed = cpi != null && offDenied(cpi);
  if (!openedCs) {
    c.hold(
      id: 'P1-$id',
      lens: lens,
      severity: 'P1',
      title: 'App/card $method não abriu Session',
      actor: 'buyer JWT',
      pre: 'order payment_method=$method',
      repro: 'create-payment-intent',
      expected: 'CPI 200 cs_ · RPC false',
      obtained: {
        'sql': sql,
        'cpi': cpi?.brief,
        'sid': sid,
        'killed': killed,
      },
    );
  } else if (sql == true) {
    c.hold(
      id: 'P2-$id-sql',
      lens: lens,
      severity: 'P2',
      title: 'RPC marca $method off mas CPI abriu cs_',
      actor: 'buyer JWT + RPC',
      pre: 'order payment_method=$method',
      repro: 'RPC vs CPI',
      expected: 'RPC false e CPI cs_',
      obtained: {'sql': sql, 'sid': sid},
    );
  } else {
    c.block(id, lens, '$method abriu cs_ RPC false', {
      'sql': sql,
      'sid': sid,
      'cpi': cpi?.brief,
    });
  }
  c.probe(
    id: id,
    poco: 'EH-B',
    surfaces: 'orders.payment_method + CPI + RPC',
    action: action,
    http: {'cpi': cpi?.brief, 'sql': sql},
    oracles: {'sid': sid, 'sql': sql, 'pm': method},
    result: openedCs && sql != true ? 'FAIL' : 'HOLD',
    lens: lens,
    classeNova: classeNova,
    countFinding: !(openedCs && sql != true),
  );
}

Future<void> runA(Rteh c) async {
  // A1 multibanco
  final a1 = await mkOrder(c, tag: 'a1-mb', payment: 'multibanco');
  HttpHit? a1cpi;
  bool? a1sql;
  Map<String, dynamic>? a1row;
  if (a1 != null) {
    a1sql = await c.sqlOffBool('multibanco');
    a1cpi = await c.cpiOnce(
      () => c.checkout(orderId: a1.oid, productId: a1.pid),
    );
    a1row = await c.orderRow(a1.oid);
  }
  await expectOffBlock(
    c,
    id: 'A1',
    lens: 'EH-A',
    action: 'multibanco exact',
    method: 'multibanco',
    cpi: a1cpi,
    sql: a1sql,
    row: a1row,
    classeNova: true,
  );

  // A2 ifthenpay + JSON {"psp":"ifthenpay"}
  final a2a = await mkOrder(c, tag: 'a2-ifthen', payment: 'ifthenpay');
  final jsonPm = '{"psp":"ifthenpay"}';
  String? a2pid;
  HttpHit? a2raw;
  HttpHit? a2cpiA;
  HttpHit? a2cpiB;
  bool? a2sqlA;
  bool? a2sqlB;
  Map<String, dynamic>? a2rowA;
  Map<String, dynamic>? a2rowB;
  if (a2a != null) {
    a2sqlA = await c.sqlOffBool('ifthenpay');
    a2cpiA = await c.cpiOnce(
      () => c.checkout(orderId: a2a.oid, productId: a2a.pid),
    );
    a2rowA = await c.orderRow(a2a.oid);
    a2pid = a2a.pid;
  }
  a2pid ??= await c.createProduct(title: '$prefix-a2-json');
  if (a2pid != null) {
    a2raw = await c.insertOrderRaw(
      productId: a2pid,
      payment: jsonPm,
      jwt: c.buyerJwt,
    );
    a2sqlB = await c.sqlOffBool(jsonPm);
    final oidB = a2raw.firstId;
    if (oidB != null) {
      a2cpiB = await c.cpiOnce(
        () => c.checkout(orderId: oidB, productId: a2pid),
      );
      a2rowB = await c.orderRow(oidB);
    }
  }
  final a2open = (a2cpiA != null && opened(a2cpiA)) ||
      (a2cpiB != null && opened(a2cpiB));
  final a2ok = !a2open &&
      a2cpiA != null &&
      offDenied(a2cpiA) &&
      a2sqlA == true &&
      a2sqlB == true &&
      (a2cpiB == null || offDenied(a2cpiB) || !a2raw!.ok);
  if (a2open) {
    c.hold(
      id: 'P2-A2',
      lens: 'EH-A',
      severity: 'P2',
      title: 'ifthenpay / JSON psp abriu Session',
      actor: 'buyer JWT',
      pre: 'payment_method ifthenpay e {"psp":"ifthenpay"}',
      repro: 'RPC + CPI nos dois',
      expected: 'ambos RPC true · CPI 400 sem cs_',
      obtained: {
        'sqlA': a2sqlA,
        'sqlB': a2sqlB,
        'cpiA': a2cpiA?.brief,
        'cpiB': a2cpiB?.brief,
        'raw': a2raw?.brief,
        'pmA': a2rowA?['payment_method'],
        'pmB': a2rowB?['payment_method'],
      },
    );
  } else if (a2ok) {
    c.block('A2', 'EH-A', 'ifthenpay + JSON 400 RPC true', {
      'sqlA': a2sqlA,
      'sqlB': a2sqlB,
      'cpiA': a2cpiA?.brief,
      'cpiB': a2cpiB?.brief,
      'raw': a2raw?.brief,
    });
  } else {
    c.hold(
      id: 'P2-A2-align',
      lens: 'EH-A',
      severity: 'P2',
      title: 'ifthenpay/JSON RPC vs CPI desalinhado',
      actor: 'buyer JWT',
      pre: 'ifthenpay + JSON',
      repro: 'RPC + CPI',
      expected: 'RPC true CPI 400',
      obtained: {
        'sqlA': a2sqlA,
        'sqlB': a2sqlB,
        'cpiA': a2cpiA?.brief,
        'cpiB': a2cpiB?.brief,
        'raw': a2raw?.brief,
      },
    );
  }
  c.probe(
    id: 'A2',
    poco: 'EH-A',
    surfaces: 'orders + CPI + RPC',
    action: 'ifthenpay + JSON {"psp":"ifthenpay"}',
    http: {
      'cpiA': a2cpiA?.brief,
      'cpiB': a2cpiB?.brief,
      'raw': a2raw?.brief,
    },
    oracles: {
      'sqlA': a2sqlA,
      'sqlB': a2sqlB,
      'pmA': a2rowA?['payment_method'],
      'pmB': a2rowB?['payment_method'],
    },
    result: a2ok ? 'FAIL' : 'HOLD',
    lens: 'EH-A',
    classeNova: true,
    countFinding: !a2ok,
  );

  // A3 contra reembolso / contra_reembolso / COD
  final a3labels = ['contra reembolso', 'contra_reembolso', 'COD'];
  final a3hits = <String, Object?>{};
  var a3anyOpen = false;
  var a3allGood = true;
  for (final lab in a3labels) {
    final o = await mkOrder(c, tag: 'a3-${lab.hashCode}', payment: lab);
    bool? sql;
    HttpHit? cpi;
    Map<String, dynamic>? row;
    if (o != null) {
      sql = await c.sqlOffBool(lab);
      cpi = await c.cpiOnce(
        () => c.checkout(orderId: o.oid, productId: o.pid),
      );
      row = await c.orderRow(o.oid);
    }
    final open = cpi != null && opened(cpi);
    final good = cpi != null && offDenied(cpi) && sql == true;
    a3anyOpen = a3anyOpen || open;
    a3allGood = a3allGood && good;
    a3hits[lab] = {
      'sql': sql,
      'cpi': cpi?.brief,
      'sid': cpi == null ? '' : sidOf(cpi, row),
      'pm': row?['payment_method'],
    };
  }
  if (a3anyOpen) {
    c.hold(
      id: 'P2-A3',
      lens: 'EH-A',
      severity: 'P2',
      title: 'COD / contra-reembolso abriu Session',
      actor: 'buyer JWT',
      pre: 'contra reembolso / contra_reembolso / COD',
      repro: 'RPC + CPI',
      expected: '400 sem cs_ nos três',
      obtained: a3hits,
    );
  } else if (a3allGood) {
    c.block('A3', 'EH-A', 'COD/contra-reembolso 400 RPC true', a3hits);
  } else {
    c.hold(
      id: 'P2-A3-align',
      lens: 'EH-A',
      severity: 'P2',
      title: 'COD/contra-reembolso RPC vs CPI desalinhado',
      actor: 'buyer JWT',
      pre: 'três labels COD',
      repro: 'RPC + CPI',
      expected: 'RPC true CPI 400',
      obtained: a3hits,
    );
  }
  c.probe(
    id: 'A3',
    poco: 'EH-A',
    surfaces: 'orders + CPI + RPC',
    action: 'contra reembolso / contra_reembolso / COD',
    http: a3hits,
    oracles: a3hits,
    result: a3allGood ? 'FAIL' : 'HOLD',
    lens: 'EH-A',
    classeNova: true,
    countFinding: !a3allGood,
  );

  // A4 sibs / referência
  final a4cases = <String, String>{
    'sibs': 'sibs',
    'ref_mb': 'Referência Multibanco',
    'referencia': 'referência',
  };
  final a4hits = <String, Object?>{};
  var a4sibsOk = false;
  var a4refMbOk = false;
  var a4refOpen = false;
  for (final e in a4cases.entries) {
    final o = await mkOrder(c, tag: 'a4-${e.key}', payment: e.value);
    bool? sql;
    HttpHit? cpi;
    Map<String, dynamic>? row;
    if (o != null) {
      sql = await c.sqlOffBool(e.value);
      cpi = await c.cpiOnce(
        () => c.checkout(orderId: o.oid, productId: o.pid),
      );
      row = await c.orderRow(o.oid);
    }
    final open = cpi != null && opened(cpi);
    final good = cpi != null && offDenied(cpi) && sql == true;
    a4hits[e.key] = {
      'label': e.value,
      'sql': sql,
      'cpi': cpi?.brief,
      'sid': cpi == null ? '' : sidOf(cpi, row),
      'pm': row?['payment_method'],
      'open': open,
      'good': good,
    };
    if (e.key == 'sibs') a4sibsOk = good;
    if (e.key == 'ref_mb') a4refMbOk = good;
    if (e.key == 'referencia') a4refOpen = open;
  }
  final a4coreOk = a4sibsOk && a4refMbOk;
  if (!a4coreOk) {
    c.hold(
      id: 'P2-A4',
      lens: 'EH-A',
      severity: 'P2',
      title: 'sibs / Referência Multibanco não bloqueou',
      actor: 'buyer JWT',
      pre: 'sibs + Referência Multibanco',
      repro: 'RPC + CPI',
      expected: '400 sem cs_',
      obtained: a4hits,
    );
  } else if (a4refOpen) {
    c.hold(
      id: 'P2-A4-ref',
      lens: 'EH-A',
      severity: 'P2',
      title: 'referência sozinha abriu Session Stripe',
      actor: 'buyer JWT',
      pre: 'payment_method=referência (sem multibanco/sibs)',
      repro: 'RPC + CPI',
      expected: 'fail-closed 400 (referência SIBS) ou documentar allow',
      obtained: a4hits,
    );
  } else {
    c.block('A4', 'EH-A', 'sibs / referência 400 RPC true', a4hits);
  }
  c.probe(
    id: 'A4',
    poco: 'EH-A',
    surfaces: 'orders + CPI + RPC',
    action: 'sibs / Referência Multibanco / referência',
    http: a4hits,
    oracles: a4hits,
    result: a4coreOk && !a4refOpen ? 'FAIL' : 'HOLD',
    lens: 'EH-A',
    classeNova: true,
    countFinding: !(a4coreOk && !a4refOpen),
  );

  // A5 MB WAY wrap NOVO (não x/via/omega)
  const a5pm = 'MB WAY (MBNet) ref 88321';
  final a5 = await mkOrder(c, tag: 'a5-mbnet', payment: a5pm);
  HttpHit? a5cpi;
  bool? a5sql;
  Map<String, dynamic>? a5row;
  if (a5 != null) {
    a5sql = await c.sqlOffBool(a5pm);
    a5cpi = await c.cpiOnce(
      () => c.checkout(orderId: a5.oid, productId: a5.pid),
    );
    a5row = await c.orderRow(a5.oid);
  }
  await expectOffBlock(
    c,
    id: 'A5',
    lens: 'EH-A',
    action: 'MB WAY (MBNet) ref — wrap novo',
    method: a5pm,
    cpi: a5cpi,
    sql: a5sql,
    row: a5row,
    classeNova: true,
  );

  // A6 transferência wrap novo
  const a6pm = 'transferência bancária IBAN PT50';
  final a6 = await mkOrder(c, tag: 'a6-iban', payment: a6pm);
  HttpHit? a6cpi;
  bool? a6sql;
  Map<String, dynamic>? a6row;
  if (a6 != null) {
    a6sql = await c.sqlOffBool(a6pm);
    a6cpi = await c.cpiOnce(
      () => c.checkout(orderId: a6.oid, productId: a6.pid),
    );
    a6row = await c.orderRow(a6.oid);
  }
  await expectOffBlock(
    c,
    id: 'A6',
    lens: 'EH-A',
    action: 'transferência bancária IBAN PT50',
    method: a6pm,
    cpi: a6cpi,
    sql: a6sql,
    row: a6row,
    classeNova: true,
  );

  // A7 array + notes/body mismatch
  final a7pid = await c.createProduct(title: '$prefix-a7-arr');
  HttpHit? a7raw;
  HttpHit? a7cpiArr;
  HttpHit? a7cpiNotes;
  HttpHit? a7cpiBody;
  bool? a7sqlArr;
  Map<String, dynamic>? a7rowArr;
  Map<String, dynamic>? a7rowApp;
  if (a7pid != null) {
    a7raw = await c.insertOrderRaw(
      productId: a7pid,
      payment: <String>['multibanco'],
      jwt: c.buyerJwt,
    );
    a7sqlArr = await c.sqlOffBool('["multibanco"]');
    final oidArr = a7raw.firstId;
    if (oidArr != null) {
      a7cpiArr = await c.cpiOnce(
        () => c.checkout(
          orderId: oidArr,
          productId: a7pid,
          extra: {'payment_method': 'card', 'method': 'card'},
        ),
      );
      a7rowArr = await c.orderRow(oidArr);
    }
    final app = await mkOrder(c, tag: 'a7-notes', payment: 'Pagamento na App');
    if (app != null) {
      a7cpiNotes = await c.cpiOnce(
        () => c.checkout(
          orderId: app.oid,
          productId: app.pid,
          extra: {
            'notes': 'paga por ifthenpay entidade 11234',
            'payment_method': 'ifthenpay',
          },
        ),
      );
      a7rowApp = await c.orderRow(app.oid);
    }
    final off = await mkOrder(c, tag: 'a7-body', payment: 'sibs');
    if (off != null) {
      a7cpiBody = await c.cpiOnce(
        () => c.checkout(
          orderId: off.oid,
          productId: off.pid,
          extra: {'payment_method': 'card', 'notes': 'card'},
        ),
      );
    }
  }
  final arrOpen = a7cpiArr != null && opened(a7cpiArr);
  final notesKilled = a7cpiNotes != null && offDenied(a7cpiNotes);
  final notesOpen = a7cpiNotes != null && opened(a7cpiNotes);
  final bodyOpen = a7cpiBody != null && opened(a7cpiBody);
  final bodyDenied = a7cpiBody != null && offDenied(a7cpiBody);
  final a7ok = !arrOpen &&
      notesOpen &&
      !notesKilled &&
      bodyDenied &&
      !bodyOpen;
  if (arrOpen || bodyOpen) {
    c.hold(
      id: 'P2-A7',
      lens: 'EH-A',
      severity: 'P2',
      title: 'array/body card sobrepôs método off',
      actor: 'buyer JWT',
      pre: 'array [multibanco] ou BD sibs + CPI body card',
      repro: 'insert array; CPI extra payment_method=card',
      expected: '400 sem cs_ no off; App notes não mata',
      obtained: {
        'raw': a7raw?.brief,
        'cpiArr': a7cpiArr?.brief,
        'cpiNotes': a7cpiNotes?.brief,
        'cpiBody': a7cpiBody?.brief,
        'pmArr': a7rowArr?['payment_method'],
        'pmApp': a7rowApp?['payment_method'],
        'sqlArr': a7sqlArr,
      },
    );
  } else if (notesKilled) {
    c.hold(
      id: 'P1-A7',
      lens: 'EH-B',
      severity: 'P1',
      title: 'notes/body ifthenpay matou Pagamento na App',
      actor: 'buyer JWT',
      pre: 'BD Pagamento na App',
      repro: 'CPI extra notes+payment_method ifthenpay',
      expected: 'cs_ (BD manda, App a salvo)',
      obtained: {
        'cpiNotes': a7cpiNotes?.brief,
        'pmApp': a7rowApp?['payment_method'],
      },
    );
  } else if (a7ok) {
    c.block('A7', 'EH-A', 'array off 400; App notes vive; body card ignorado', {
      'raw': a7raw?.brief,
      'cpiArr': a7cpiArr?.brief,
      'cpiNotes': a7cpiNotes?.brief,
      'cpiBody': a7cpiBody?.brief,
      'pmArr': a7rowArr?['payment_method'],
    });
  } else {
    c.hold(
      id: 'P2-A7-align',
      lens: 'EH-A',
      severity: 'P2',
      title: 'array/notes mismatch resultado inesperado',
      actor: 'buyer JWT',
      pre: 'array + notes + body',
      repro: 'CPI trio',
      expected: 'off 400 / App cs_',
      obtained: {
        'arrOpen': arrOpen,
        'notesOpen': notesOpen,
        'bodyDenied': bodyDenied,
        'raw': a7raw?.brief,
        'cpiArr': a7cpiArr?.brief,
        'cpiNotes': a7cpiNotes?.brief,
        'cpiBody': a7cpiBody?.brief,
      },
    );
  }
  c.probe(
    id: 'A7',
    poco: 'EH-A',
    surfaces: 'orders + CPI body/notes',
    action: 'array [multibanco] + notes ifthenpay em App + body card em sibs',
    http: {
      'raw': a7raw?.brief,
      'arr': a7cpiArr?.brief,
      'notes': a7cpiNotes?.brief,
      'body': a7cpiBody?.brief,
    },
    oracles: {
      'pmArr': a7rowArr?['payment_method'],
      'pmApp': a7rowApp?['payment_method'],
      'sqlArr': a7sqlArr,
    },
    result: a7ok ? 'FAIL' : 'HOLD',
    lens: 'EH-A',
    classeNova: true,
    countFinding: !a7ok,
  );
}

Future<void> runB(Rteh c) async {
  // B1 Pagamento na App
  final b1 = await mkOrder(c, tag: 'b1-app', payment: 'Pagamento na App');
  HttpHit? b1cpi;
  bool? b1sql;
  Map<String, dynamic>? b1row;
  if (b1 != null) {
    b1sql = await c.sqlOffBool('Pagamento na App');
    b1cpi = await c.cpiOnce(
      () => c.checkout(orderId: b1.oid, productId: b1.pid),
    );
    b1row = await c.orderRow(b1.oid);
  }
  await expectAppOpen(
    c,
    id: 'B1',
    lens: 'EH-B',
    action: 'Pagamento na App → cs_',
    method: 'Pagamento na App',
    cpi: b1cpi,
    sql: b1sql,
    row: b1row,
  );

  // B2 card
  final b2 = await mkOrder(c, tag: 'b2-card', payment: 'card');
  HttpHit? b2cpi;
  bool? b2sql;
  Map<String, dynamic>? b2row;
  if (b2 != null) {
    b2sql = await c.sqlOffBool('card');
    b2cpi = await c.cpiOnce(
      () => c.checkout(orderId: b2.oid, productId: b2.pid),
    );
    b2row = await c.orderRow(b2.oid);
  }
  await expectAppOpen(
    c,
    id: 'B2',
    lens: 'EH-B',
    action: 'card → cs_',
    method: 'card',
    cpi: b2cpi,
    sql: b2sql,
    row: b2row,
  );

  // B3 applepay / googlepay
  final b3hits = <String, Object?>{};
  var b3ok = true;
  for (final lab in ['applepay', 'googlepay']) {
    final o = await mkOrder(c, tag: 'b3-$lab', payment: lab);
    bool? sql;
    HttpHit? cpi;
    Map<String, dynamic>? row;
    if (o != null) {
      sql = await c.sqlOffBool(lab);
      cpi = await c.cpiOnce(
        () => c.checkout(orderId: o.oid, productId: o.pid),
      );
      row = await c.orderRow(o.oid);
    }
    final open = cpi != null && opened(cpi) && sql != true;
    b3ok = b3ok && open;
    b3hits[lab] = {
      'sql': sql,
      'cpi': cpi?.brief,
      'sid': cpi == null ? '' : sidOf(cpi, row),
    };
  }
  if (!b3ok) {
    c.hold(
      id: 'P1-B3',
      lens: 'EH-B',
      severity: 'P1',
      title: 'applepay/googlepay não abriu Session',
      actor: 'buyer JWT',
      pre: 'payment_method applepay e googlepay',
      repro: 'RPC + CPI',
      expected: 'RPC false · CPI cs_ nos dois',
      obtained: b3hits,
    );
  } else {
    c.block('B3', 'EH-B', 'applepay/googlepay cs_ RPC false', b3hits);
  }
  c.probe(
    id: 'B3',
    poco: 'EH-B',
    surfaces: 'orders + CPI + RPC',
    action: 'applepay / googlepay labels',
    http: b3hits,
    oracles: b3hits,
    result: b3ok ? 'FAIL' : 'HOLD',
    lens: 'EH-B',
    classeNova: true,
    countFinding: !b3ok,
  );
}

Future<({String oid, String pid, String? pi})?> runB4(Rteh c) async {
  final paid = await c.payToPago(lens: 'EH-B', initialQty: 2);
  if (paid == null) {
    c.skip('B4', 'EH-B', 'setup_paid_order falhou', 'null');
    c.probe(
      id: 'B4',
      poco: 'EH-B',
      surfaces: 'orders + Stripe TEST',
      action: '1× pago 4242 App',
      http: 'null',
      oracles: '-',
      result: 'SKIP',
      lens: 'EH-B',
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
  final pm = '${row?['payment_method'] ?? ''}';
  final ok = st == 'pago' &&
      pi.startsWith('pi_') &&
      cents != null &&
      cents >= 50 &&
      qty == 1 &&
      applied == 1;
  if (!ok) {
    c.hold(
      id: 'P1-B4',
      lens: 'EH-B',
      severity: 'P1',
      title: 'pago Stripe TEST incoerente (status/qty/PI)',
      actor: 'e2e setup_paid_order',
      pre: 'SKU listado Pagamento na app initial_qty=2',
      repro: 'setup_paid_order 4242',
      expected: 'status=pago PI pi_ qty 2→1 applied=1',
      obtained: {
        'oid': paid.oid,
        'pid': paid.pid,
        'status': st,
        'pi': pi,
        'cents': cents,
        'qty': qty,
        'applied': applied,
        'pm': pm,
        'hit': paid.hit.brief,
      },
    );
  } else {
    c.block('B4', 'EH-B', 'Stripe TEST pago 4242 coerente', {
      'oid': paid.oid,
      'pid': paid.pid,
      'pi': pi,
      'cents': cents,
      'qty': qty,
      'pm': pm,
    });
  }
  c.probe(
    id: 'B4',
    poco: 'EH-B',
    surfaces: 'orders + products + Stripe TEST',
    action: '1× pago 4242 Pagamento na App',
    http: paid.hit.brief,
    oracles: {
      'oid': paid.oid,
      'pid': paid.pid,
      'status': st,
      'pi': pi,
      'cents': cents,
      'qty': qty,
      'applied': applied,
      'pm': pm,
    },
    result: ok ? 'FAIL' : 'HOLD',
    lens: 'EH-B',
    classeNova: true,
    countFinding: !ok,
  );
  return (oid: paid.oid, pid: paid.pid, pi: pi);
}

Future<void> runC(Rteh c) async {
  // C1 PATCH method off após cs_ open
  final c1 = await mkOrder(c, tag: 'c1-patch', payment: 'Pagamento na App');
  HttpHit? c1open;
  HttpHit? c1patchB;
  HttpHit? c1patchS;
  HttpHit? c1cpi2;
  Map<String, dynamic>? c1before;
  Map<String, dynamic>? c1afterB;
  Map<String, dynamic>? c1afterS;
  if (c1 != null) {
    c1open = await c.cpiOnce(
      () => c.checkout(orderId: c1.oid, productId: c1.pid),
    );
    c1before = await c.orderRow(c1.oid);
    c1patchB = await c.patchOrder(
      c1.oid,
      {'payment_method': 'ifthenpay'},
      jwt: c.buyerJwt,
    );
    c1afterB = await c.orderRow(c1.oid);
    c1patchS = await c.patchOrder(
      c1.oid,
      {'payment_method': 'ifthenpay'},
      jwt: c.sellerJwt,
    );
    c1afterS = await c.orderRow(c1.oid);
    c1cpi2 = await c.cpiOnce(
      () => c.checkout(orderId: c1.oid, productId: c1.pid),
    );
  }
  final sid1 = c1open == null ? '' : sidOf(c1open, c1before);
  final pmAfterB = '${c1afterB?['payment_method'] ?? ''}';
  final pmAfterS = '${c1afterS?['payment_method'] ?? ''}';
  final flipped = pmAfterB.toLowerCase().contains('ifthenpay') ||
      pmAfterS.toLowerCase().contains('ifthenpay');
  final firstOpen = c1open != null && opened(c1open);
  if (flipped) {
    c.hold(
      id: 'P1-C1',
      lens: 'EH-C',
      severity: 'P1',
      title: 'PATCH payment_method off colou após cs_ aberto',
      actor: 'buyer/seller JWT',
      pre: 'Pagamento na App + CPI cs_',
      repro: 'PATCH payment_method=ifthenpay; CPI 2.º',
      expected: '403 immutable · pm App · sid intacto',
      obtained: {
        'open': c1open?.brief,
        'patchB': c1patchB?.brief,
        'patchS': c1patchS?.brief,
        'cpi2': c1cpi2?.brief,
        'pmBefore': c1before?['payment_method'],
        'pmAfterB': pmAfterB,
        'pmAfterS': pmAfterS,
        'sid': sid1,
        'sidAfter': c1afterS?['stripe_checkout_session_id'],
      },
    );
  } else if (!firstOpen) {
    c.hold(
      id: 'P1-C1-open',
      lens: 'EH-C',
      severity: 'P1',
      title: 'C1: App não abriu cs_ antes do PATCH',
      actor: 'buyer JWT',
      pre: 'Pagamento na App',
      repro: 'CPI then PATCH',
      expected: 'primeiro CPI cs_',
      obtained: {'open': c1open?.brief},
    );
  } else {
    c.block('C1', 'EH-C', 'PATCH ifthenpay após cs_ recusado; pm App', {
      'open': c1open?.brief,
      'patchB': c1patchB?.brief,
      'patchS': c1patchS?.brief,
      'cpi2': c1cpi2?.brief,
      'pm': pmAfterB,
      'sid': sid1,
    });
  }
  c.probe(
    id: 'C1',
    poco: 'EH-C',
    surfaces: 'orders PATCH + CPI',
    action: 'PATCH ifthenpay após cs_ open (buyer+seller)',
    http: {
      'open': c1open?.brief,
      'patchB': c1patchB?.brief,
      'patchS': c1patchS?.brief,
      'cpi2': c1cpi2?.brief,
    },
    oracles: {
      'pmBefore': c1before?['payment_method'],
      'pmAfterB': pmAfterB,
      'pmAfterS': pmAfterS,
      'sid': sid1,
      'flipped': flipped,
    },
    result: flipped || !firstOpen ? 'HOLD' : 'FAIL',
    lens: 'EH-C',
    classeNova: true,
    countFinding: flipped || !firstOpen,
  );

  // C2 buyer2 CPI order off alheia
  final c2 = await mkOrder(c, tag: 'c2-idor', payment: 'multibanco');
  HttpHit? c2own;
  HttpHit? c2b2;
  Map<String, dynamic>? c2row;
  if (c2 != null) {
    c2own = await c.cpiOnce(
      () => c.checkout(orderId: c2.oid, productId: c2.pid),
    );
    c2b2 = await c.cpiOnce(
      () => c.checkout(
        orderId: c2.oid,
        productId: c2.pid,
        jwt: c.buyer2Jwt,
        buyer: c.buyer2Id,
      ),
    );
    c2row = await c.orderRow(c2.oid);
  }
  final c2opened = c2b2 != null && opened(c2b2);
  final c2blocked = c2b2 != null && (belongDenied(c2b2) || offDenied(c2b2));
  if (c2opened) {
    c.hold(
      id: 'P1-C2',
      lens: 'EH-C',
      severity: 'P1',
      title: 'buyer2 abriu Session em encomenda off alheia',
      actor: 'buyer2 JWT',
      pre: 'order buyer1 payment_method=multibanco',
      repro: 'CPI buyer2 order_id alheio',
      expected: '403/400 sem cs_',
      obtained: {
        'own': c2own?.brief,
        'b2': c2b2?.brief,
        'sid': sidOf(c2b2!, c2row),
        'buyer': c2row?['buyer_id'],
      },
    );
  } else if (c2blocked) {
    c.block('C2', 'EH-C', 'buyer2 CPI off alheia recusado sem cs_', {
      'own': c2own?.brief,
      'b2': c2b2?.brief,
      'pm': c2row?['payment_method'],
    });
  } else {
    c.hold(
      id: 'P2-C2-align',
      lens: 'EH-C',
      severity: 'P2',
      title: 'buyer2 CPI resultado inesperado',
      actor: 'buyer2 JWT',
      pre: 'order off alheia',
      repro: 'CPI buyer2',
      expected: 'deny sem cs_',
      obtained: {'b2': c2b2?.brief, 'own': c2own?.brief},
    );
  }
  c.probe(
    id: 'C2',
    poco: 'EH-C',
    surfaces: 'CPI cross-buyer',
    action: 'buyer2 CPI order multibanco alheia',
    http: {'own': c2own?.brief, 'b2': c2b2?.brief},
    oracles: {
      'buyer': c2row?['buyer_id'],
      'b2': c.buyer2Id,
      'pm': c2row?['payment_method'],
    },
    result: c2opened || !c2blocked ? 'HOLD' : 'FAIL',
    lens: 'EH-C',
    classeNova: true,
    countFinding: c2opened || !c2blocked,
  );

  // C3 RPC vs CPI alinhados (bateria)
  final c3methods = [
    'multibanco',
    'ifthenpay',
    'sibs',
    'Pagamento na App',
    'card',
    'applepay',
  ];
  final c3rows = <String, Object?>{};
  var c3mis = false;
  for (final m in c3methods) {
    final sql = await c.sqlOffBool(m);
    final o = await mkOrder(c, tag: 'c3-${m.hashCode}', payment: m);
    HttpHit? cpi;
    if (o != null) {
      cpi = await c.cpiOnce(
        () => c.checkout(orderId: o.oid, productId: o.pid),
      );
    }
    final open = cpi != null && opened(cpi);
    final denied = cpi != null && offDenied(cpi);
    final aligned = sql == true ? (denied && !open) : (open && !denied);
    if (!aligned) c3mis = true;
    c3rows[m] = {
      'sql': sql,
      'cpi': cpi?.brief,
      'open': open,
      'denied': denied,
      'aligned': aligned,
    };
  }
  if (c3mis) {
    c.hold(
      id: 'P2-C3',
      lens: 'EH-C',
      severity: 'P2',
      title: 'RPC batata_is_off_platform_payment ≠ CPI',
      actor: 'buyer JWT + service RPC',
      pre: 'seis métodos App/off',
      repro: 'RPC e CPI no mesmo label',
      expected: 'sql true ⇔ CPI 400 off; sql false ⇔ cs_',
      obtained: c3rows,
    );
  } else {
    c.block('C3', 'EH-C', 'RPC e CPI alinhados nos 6 labels', c3rows);
  }
  c.probe(
    id: 'C3',
    poco: 'EH-C',
    surfaces: 'RPC batata_is_off_platform_payment vs CPI',
    action: 'multibanco/ifthenpay/sibs vs App/card/applepay',
    http: c3rows,
    oracles: c3rows,
    result: c3mis ? 'HOLD' : 'FAIL',
    lens: 'EH-C',
    classeNova: true,
    countFinding: c3mis,
  );

  // C4 empty / null method
  final c4pid = await c.createProduct(title: '$prefix-c4-empty');
  HttpHit? c4empty;
  HttpHit? c4null;
  HttpHit? c4cpiE;
  HttpHit? c4cpiN;
  bool? c4sqlE;
  bool? c4sqlN;
  Map<String, dynamic>? c4rowE;
  Map<String, dynamic>? c4rowN;
  if (c4pid != null) {
    c4sqlE = await c.sqlOffBool('');
    c4sqlN = await c.sqlOffBool('');
    c4empty = await c.insertOrderRaw(
      productId: c4pid,
      payment: '',
      jwt: c.buyerJwt,
    );
    final oidE = c4empty.firstId;
    if (oidE != null) {
      c4cpiE = await c.cpiOnce(
        () => c.checkout(orderId: oidE, productId: c4pid),
      );
      c4rowE = await c.orderRow(oidE);
    }
    c4null = await c.insertOrderRaw(
      productId: c4pid,
      payment: null,
      jwt: c.buyerJwt,
    );
    final oidN = c4null.firstId;
    if (oidN != null) {
      c4cpiN = await c.cpiOnce(
        () => c.checkout(orderId: oidN, productId: c4pid),
      );
      c4rowN = await c.orderRow(oidN);
    }
  }
  final emptyOpen = c4cpiE != null && opened(c4cpiE);
  final emptyOff = c4cpiE != null && offDenied(c4cpiE);
  final nullInserted = c4null != null && c4null.ok;
  final nullOpen = c4cpiN != null && opened(c4cpiN);
  // Denylist: empty/null not off → App may open. Finding only if RPC true (off)
  // but CPI opens, or RPC false and CPI 400 off-platform (App killed).
  final c4rpcSaysOff = c4sqlE == true;
  final c4killed = emptyOff && c4sqlE != true;
  final c4mismatchOpen = emptyOpen && c4rpcSaysOff;
  if (c4mismatchOpen || (nullOpen && c4sqlN == true)) {
    c.hold(
      id: 'P2-C4',
      lens: 'EH-C',
      severity: 'P2',
      title: 'empty/null RPC off mas CPI abriu cs_',
      actor: 'buyer JWT',
      pre: 'payment_method empty/null',
      repro: 'insert + RPC + CPI',
      expected: 'RPC e CPI iguais; se off então 400',
      obtained: {
        'sqlE': c4sqlE,
        'sqlN': c4sqlN,
        'empty': c4empty?.brief,
        'null': c4null?.brief,
        'cpiE': c4cpiE?.brief,
        'cpiN': c4cpiN?.brief,
        'pmE': c4rowE?['payment_method'],
        'pmN': c4rowN?['payment_method'],
      },
    );
  } else if (c4killed) {
    c.hold(
      id: 'P1-C4',
      lens: 'EH-C',
      severity: 'P1',
      title: 'empty method tratado off e matou checkout App-default',
      actor: 'buyer JWT',
      pre: 'payment_method=""',
      repro: 'CPI empty',
      expected: 'RPC false · App cs_ ou 400 genérico, não off-platform',
      obtained: {'cpiE': c4cpiE?.brief, 'sqlE': c4sqlE},
    );
  } else {
    c.block('C4', 'EH-C', 'empty/null: RPC e CPI coerentes (não bypass off)', {
      'sqlE': c4sqlE,
      'empty': c4empty?.brief,
      'cpiE': c4cpiE?.brief,
      'nullIns': c4null?.brief,
      'nullOpen': nullOpen,
      'pmE': c4rowE?['payment_method'],
      'emptyOpen': emptyOpen,
    });
  }
  c.probe(
    id: 'C4',
    poco: 'EH-C',
    surfaces: 'orders insert empty/null + RPC + CPI',
    action: 'empty string / null payment_method',
    http: {
      'empty': c4empty?.brief,
      'null': c4null?.brief,
      'cpiE': c4cpiE?.brief,
      'cpiN': c4cpiN?.brief,
    },
    oracles: {
      'sqlE': c4sqlE,
      'sqlN': c4sqlN,
      'pmE': c4rowE?['payment_method'],
      'pmN': c4rowN?['payment_method'],
      'nullInserted': nullInserted,
      'emptyOpen': emptyOpen,
    },
    result: c4mismatchOpen || c4killed ? 'HOLD' : 'FAIL',
    lens: 'EH-C',
    classeNova: true,
    countFinding: c4mismatchOpen || c4killed,
  );

  // C5 Paysafe / lixo ASCII / JSON hostil
  final c5cases = <String, String>{
    'paysafe': 'Paysafe',
    'junk': 'asdfghjklpay',
    'json': '{"psp":"paysafe","x":1}',
  };
  final c5hits = <String, Object?>{};
  var c5jsonOpen = false;
  var c5mismatch = false;
  for (final e in c5cases.entries) {
    final sql = await c.sqlOffBool(e.value);
    final o = await mkOrder(c, tag: 'c5-${e.key}', payment: e.value);
    HttpHit? cpi;
    Map<String, dynamic>? row;
    if (o != null) {
      cpi = await c.cpiOnce(
        () => c.checkout(orderId: o.oid, productId: o.pid),
      );
      row = await c.orderRow(o.oid);
    }
    final open = cpi != null && opened(cpi);
    final denied = cpi != null && offDenied(cpi);
    final aligned = sql == true ? (denied && !open) : (open || (cpi != null && !denied && !open));
    // For unknown ASCII, denylist false → App may open. That's aligned if sql!=true && open.
    final aligned2 = (sql == true && denied && !open) ||
        (sql != true && open) ||
        (sql != true && cpi != null && !cpi.ok && !denied);
    if (!aligned2) c5mismatch = true;
    if (e.key == 'json' && open) c5jsonOpen = true;
    c5hits[e.key] = {
      'label': e.value,
      'sql': sql,
      'cpi': cpi?.brief,
      'sid': cpi == null ? '' : sidOf(cpi, row),
      'open': open,
      'denied': denied,
      'aligned': aligned,
    };
  }
  // Mission: JSON hostil não abre Stripe.
  if (c5jsonOpen) {
    c.hold(
      id: 'P2-C5',
      lens: 'EH-C',
      severity: 'P2',
      title: 'JSON hostil payment_method abriu Session Stripe',
      actor: 'buyer JWT',
      pre: 'payment_method={"psp":"paysafe","x":1}',
      repro: 'RPC + CPI',
      expected: 'JSON hostil fail-closed 400 sem cs_',
      obtained: c5hits,
    );
  } else if (c5mismatch) {
    c.hold(
      id: 'P2-C5-align',
      lens: 'EH-C',
      severity: 'P2',
      title: 'Paysafe/lixo RPC vs CPI desalinhado',
      actor: 'buyer JWT',
      pre: 'Paysafe / ASCII junk / JSON',
      repro: 'RPC + CPI',
      expected: 'sql true ⇔ 400; sql false ⇔ cs_ ou insert fail',
      obtained: c5hits,
    );
  } else {
    c.block('C5', 'EH-C', 'Paysafe/lixo/JSON: RPC↔CPI coerente; JSON sem cs_', c5hits);
  }
  c.probe(
    id: 'C5',
    poco: 'EH-C',
    surfaces: 'orders + CPI + RPC',
    action: 'Paysafe / lixo ASCII / JSON {"psp":"paysafe"}',
    http: c5hits,
    oracles: c5hits,
    result: c5jsonOpen || c5mismatch ? 'HOLD' : 'FAIL',
    lens: 'EH-C',
    classeNova: true,
    countFinding: c5jsonOpen || c5mismatch,
  );
}
