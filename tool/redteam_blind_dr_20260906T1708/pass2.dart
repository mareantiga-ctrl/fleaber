/// pass2 — A2 tip_id em live válida; C2 CPI race real; re-ler status reservas (sem converted_order_id).
/// Staging only. No fixes.
import 'dart:io';

import '_rtdr.dart';

Future<void> main() async {
  final c = Rtdr.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2(hubPublished: true);
  await c.restoreSeller1Published();

  final s1 = c.sellerId!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;

  // A2b — tip_id cliente em live S1 + seller S1 (owner OK; tip_id deve 400)
  final liveA2 = await c.createLive(title: '$prefix p2-a2');
  final a2 = liveA2 == null
      ? null
      : await c.tipCheckout(
          liveId: liveA2,
          seller: s1,
          amountEur: 2,
          jwt: c.buyerJwt,
          extra: {'tip_id': '00000000-0000-4000-8000-0000000000aa'},
        );
  final a2fail = a2?.ok == true;
  if (a2fail) {
    c.hold(
      id: 'A2.tip_id.live_alheio',
      lens: 'DR1',
      severity: 'P1',
      title: 'Client tip_id aceite em live válida',
      actor: 'buyer JWT',
      pre: 'live S1 seller S1 broadcasting',
      repro: 'POST create-live-tip-checkout tip_id UUID',
      expected: '400 Client tip_id is not allowed',
      obtained: a2?.brief,
    );
  } else {
    c.block('A2.tip_id.client', 'DR1', 'tip_id cliente recusado', a2?.brief);
  }
  c.probe(
    id: 'A2.tip_id.live_alheio',
    poco: 'DR-A',
    payload: 'tip_id UUID cliente em live S1 seller S1 (pass2)',
    http: a2 ?? 'n/a',
    bd: {'tipId': a2?.tipId, 'sid': a2?.sessionId},
    result: a2fail ? 'FAIL' : 'HOLD',
    lens: 'DR1',
    classeNova: true,
    countFinding: a2fail,
  );

  // A1 sci/arr — confirmar tips pending Δ=0
  final liveSci = await c.createLive(title: '$prefix p2-sci');
  final w0 = await c.walletBal(s1);
  final sci = liveSci == null
      ? null
      : await c.tipCheckout(
          liveId: liveSci,
          seller: s1,
          amountEur: '1e2',
          jwt: c.buyer2Jwt,
        );
  final arr = liveSci == null
      ? null
      : await c.tipCheckout(
          liveId: liveSci,
          seller: s1,
          amountEur: [2],
          jwt: c.buyer2Jwt,
        );
  Map<String, dynamic>? sciTip;
  Map<String, dynamic>? arrTip;
  if (sci?.tipId != null) sciTip = await c.tipRow(sci!.tipId!);
  if (arr?.tipId != null) arrTip = await c.tipRow(arr!.tipId!);
  final w1 = await c.walletBal(s1);
  c.probe(
    id: 'A1.tip.amount.hostil',
    poco: 'DR-A',
    payload: 'pass2 confirm sci 1e2 + arr [2] Session; unpaid',
    http: '${sci?.brief ?? 'n/a'} | ${arr?.brief ?? 'n/a'}',
    bd: {
      'sci': sciTip,
      'arr': arrTip,
      'dWallet': w1 - w0,
    },
    result: (w1 - w0) > 0 ? 'FAIL' : 'HOLD',
    lens: 'DR1',
    classeNova: true,
    countFinding: (w1 - w0) > 0,
  );

  Future<({String? live, String? sku, String? item, String? res})> fixture({
    required String tag,
    int qty = 1,
    bool accept = false,
  }) async {
    final live = await c.createLive(title: '$prefix p2-$tag');
    final sku = await c.createProduct(
        title: '$prefix p2 $tag', qty: qty, live: true, price: 9);
    final item = (live == null || sku == null)
        ? null
        : await c.createLiveItem(
            liveId: live,
            title: '$prefix p2 $tag',
            ref: 'RTDR-P2-$tag',
            kind: 'live_only',
            checkoutProductId: sku,
            quantity: qty,
          );
    String? res;
    if (live != null && item != null) {
      res = await c.insertReservation(
        liveId: live,
        liveItemId: item,
        jwt: c.buyerJwt,
        buyer: b1,
      );
      if (accept && res != null) await c.accept(res);
    }
    return (live: live, sku: sku, item: item, res: res);
  }

  // C1 pending status re-read + CPI unpaid
  final f1 = await fixture(tag: 'c1', accept: false);
  final c1rpc = f1.res == null ? null : await c.convertRpc(f1.res!);
  String? oid1;
  HttpHit? c1cpi;
  if (f1.sku != null && f1.res != null && f1.live != null && f1.item != null) {
    oid1 = await c.insertOrder(
      productId: f1.sku!,
      buyer: b1,
      jwt: c.buyerJwt,
      price: 9,
    );
    c1cpi = oid1 == null
        ? null
        : await c.checkout(
            orderId: oid1,
            buyer: b1,
            jwt: c.buyerJwt,
            amount: 1,
            productId: f1.sku,
            seller: s1,
            extra: {
              'live_id': f1.live,
              'live_item_id': f1.item,
              'reservation_request_id': f1.res,
              'is_live': true,
              'live_seller_id': s1,
            },
          );
  }
  final c1row = f1.res == null ? null : await c.resRow(f1.res!);
  final c1ord = oid1 == null ? null : await c.orderRow(oid1);
  final c1bad = c1row?['status'] == 'converted' || c1ord?['status'] == 'pago';
  c.probe(
    id: 'C1.convert.pending',
    poco: 'DR-C',
    payload: 'pass2 pending convert RPC+CPI (order sem live_item insert)',
    http: '${c1rpc?.brief ?? 'n/a'} | ${c1cpi?.brief ?? 'n/a'}',
    bd: {'res': c1row, 'ord': c1ord?['status']},
    result: c1bad ? 'FAIL' : 'HOLD',
    lens: 'DR3',
    classeNova: true,
    countFinding: c1bad,
  );

  // C2 race CPI real
  final f2 = await fixture(tag: 'c2', qty: 1, accept: true);
  String? r2b;
  if (f2.live != null && f2.item != null) {
    r2b = await c.insertReservation(
      liveId: f2.live!,
      liveItemId: f2.item!,
      jwt: c.buyer2Jwt,
      buyer: b2,
    );
  }
  String? oidA;
  String? oidB;
  HttpHit? c2a;
  HttpHit? c2b;
  HttpHit? c2r1;
  HttpHit? c2r2;
  if (f2.sku != null && f2.res != null && f2.live != null && f2.item != null) {
    oidA = await c.insertOrder(
        productId: f2.sku!, buyer: b1, jwt: c.buyerJwt, price: 9);
    oidB = await c.insertOrder(
        productId: f2.sku!, buyer: b2, jwt: c.buyer2Jwt, price: 9);
    final extraA = {
      'live_id': f2.live,
      'live_item_id': f2.item,
      'reservation_request_id': f2.res,
      'is_live': true,
      'live_seller_id': s1,
    };
    final extraB = {
      'live_id': f2.live,
      'live_item_id': f2.item,
      'reservation_request_id': f2.res,
      'is_live': true,
      'live_seller_id': s1,
    };
    final raced = await Future.wait([
      oidA == null
          ? Future.value(HttpHit(0, 'no-a', null))
          : c.checkout(
              orderId: oidA,
              buyer: b1,
              jwt: c.buyerJwt,
              amount: 1,
              productId: f2.sku,
              seller: s1,
              extra: extraA,
            ),
      oidB == null
          ? Future.value(HttpHit(0, 'no-b', null))
          : c.checkout(
              orderId: oidB,
              buyer: b2,
              jwt: c.buyer2Jwt,
              amount: 1,
              productId: f2.sku,
              seller: s1,
              extra: extraB,
            ),
      c.convertRpc(f2.res!),
      r2b == null
          ? Future.value(HttpHit(0, 'no-r2b', null))
          : c.convertRpc(r2b),
    ]);
    c2a = raced[0];
    c2b = raced[1];
    c2r1 = raced[2];
    c2r2 = raced[3];
  }
  final rowA = f2.res == null ? null : await c.resRow(f2.res!);
  final rowB = r2b == null ? null : await c.resRow(r2b);
  final ordA = oidA == null ? null : await c.orderRow(oidA);
  final ordB = oidB == null ? null : await c.orderRow(oidB);
  final nConv = [
    rowA?['status'] == 'converted',
    rowB?['status'] == 'converted',
  ].where((x) => x).length;
  final nPago = [
    ordA?['status'] == 'pago',
    ordB?['status'] == 'pago',
  ].where((x) => x).length;
  final c2fail = nConv > 1 || nPago > 0 || rowB?['status'] == 'converted';
  if (c2fail) {
    c.hold(
      id: 'C2.convert.parallel',
      lens: 'DR4',
      severity: 'P0',
      title: 'convert∥convert double order / IDOR converted',
      actor: 'B1∥B2 CPI + RPC',
      pre: 'qty=1 B1 accepted',
      repro: '2 CPI + 2 convert',
      expected: '≤1 convert; B2 ≠converted; 0 pago',
      obtained: {'a': rowA, 'b': rowB, 'oa': ordA?['status'], 'ob': ordB?['status']},
    );
  } else {
    c.block('C2.convert.parallel', 'DR4', 'pass2 race sem double', {
      'a': rowA?['status'],
      'b': rowB?['status'],
      'oa': ordA?['status'],
      'ob': ordB?['status'],
      'c2a': c2a?.brief,
      'c2b': c2b?.brief,
    });
  }
  c.probe(
    id: 'C2.convert.parallel',
    poco: 'DR-C',
    payload: 'pass2 CPI B1∥B2(res B1) + RPC×2',
    http:
        '${c2a?.brief ?? 'n/a'} | ${c2b?.brief ?? 'n/a'} | ${c2r1?.brief ?? 'n/a'} | ${c2r2?.brief ?? 'n/a'}',
    bd: {
      'resA': rowA,
      'resB': rowB,
      'ordA': ordA?['status'],
      'ordB': ordB?['status'],
      'nConv': nConv,
      'nPago': nPago,
    },
    result: c2fail ? 'FAIL' : 'HOLD',
    lens: 'DR4',
    classeNova: true,
    race: true,
    countFinding: c2fail,
  );

  // C3 hitch accept∥CPI — re-read res + full CPI error
  final liveC3 = await c.createLive(title: '$prefix p2-c3');
  final skuC3 = await c.createProduct(
      title: '$prefix p2 c3', qty: 1, live: false, price: 9);
  final liL = (liveC3 == null || skuC3 == null)
      ? null
      : await c.createLiveItem(
          liveId: liveC3,
          title: '$prefix p2 c3l',
          ref: 'RTDR-P2-C3L',
          kind: 'live_only',
          checkoutProductId: skuC3,
          quantity: 1,
        );
  String? rC3;
  if (liveC3 != null && liL != null) {
    rC3 = await c.insertReservation(
      liveId: liveC3,
      liveItemId: liL,
      jwt: c.buyerJwt,
      buyer: b1,
    );
  }
  final oidC3 = skuC3 == null
      ? null
      : await c.insertOrder(
          productId: skuC3, buyer: b2, jwt: c.buyer2Jwt, price: 9);
  HttpHit? acc;
  HttpHit? cpi;
  if (rC3 != null && oidC3 != null && skuC3 != null) {
    final raced = await Future.wait([
      c.accept(rC3),
      c.checkout(
        orderId: oidC3,
        buyer: b2,
        jwt: c.buyer2Jwt,
        amount: 1,
        productId: skuC3,
        seller: s1,
      ),
    ]);
    acc = raced[0];
    cpi = raced[1];
  }
  final rowC3 = rC3 == null ? null : await c.resRow(rC3);
  final ordC3 = oidC3 == null ? null : await c.orderRow(oidC3);
  final prodC3 = skuC3 == null ? null : await c.productQty(skuC3);
  final c3fail =
      rowC3?['status'] == 'converted' && ordC3?['status'] == 'pago';
  c.probe(
    id: 'C3.accept.cpi.race',
    poco: 'DR-C',
    payload: 'pass2 accept∥marketplace CPI qty=1',
    http: '${acc?.brief ?? 'n/a'} | ${cpi?.brief ?? 'n/a'}',
    bd: {'res': rowC3, 'ord': ordC3?['status'], 'prod': prodC3},
    result: c3fail ? 'FAIL' : 'HOLD',
    lens: 'DR4',
    classeNova: true,
    race: true,
    countFinding: c3fail,
  );

  // C4 after ended — status
  final f4 = await fixture(tag: 'c4', accept: true);
  if (f4.live != null) await c.endLive(f4.live!);
  final c4rpc = f4.res == null ? null : await c.convertRpc(f4.res!);
  final c4patch = f4.res == null
      ? null
      : await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.${f4.res}',
          jwt: c.sellerJwt,
          body: {'status': 'converted'},
        );
  final c4row = f4.res == null ? null : await c.resRow(f4.res!);
  final c4fail = c4row?['status'] == 'converted';
  c.probe(
    id: 'C4.convert.after.ended',
    poco: 'DR-C',
    payload: 'pass2 convert após ended',
    http: '${c4rpc?.brief ?? 'n/a'} | ${c4patch?.brief ?? 'n/a'}',
    bd: c4row,
    result: c4fail ? 'FAIL' : 'HOLD',
    lens: 'DR6',
    countFinding: c4fail,
  );

  // C5 capacity
  final f5 = await fixture(tag: 'c5', qty: 1, accept: true);
  final st0 = f5.item == null ? null : await c.stock(f5.item!);
  final c5rpc = f5.res == null ? null : await c.convertRpc(f5.res!);
  String? r5b;
  if (f5.live != null && f5.item != null) {
    r5b = await c.insertReservation(
      liveId: f5.live!,
      liveItemId: f5.item!,
      jwt: c.buyer2Jwt,
      buyer: b2,
    );
  }
  HttpHit? acc5b;
  if (r5b != null) acc5b = await c.accept(r5b);
  final st1 = f5.item == null ? null : await c.stock(f5.item!);
  final a5 = f5.res == null ? null : await c.resRow(f5.res!);
  final b5 = r5b == null ? null : await c.resRow(r5b);
  final c5fail = a5?['status'] == 'converted' ||
      b5?['status'] == 'accepted' ||
      b5?['status'] == 'converted';
  c.probe(
    id: 'C5.capacity.vs.stock',
    poco: 'DR-C',
    payload: 'pass2 accepted qty=1; convert unpaid; 2º accept',
    http: '${c5rpc?.brief ?? 'n/a'} | acc2=${acc5b?.brief ?? 'n/a'}',
    bd: {'a': a5, 'b': b5, 'stock0': st0, 'stock1': st1},
    result: c5fail ? 'FAIL' : 'HOLD',
    lens: 'DR5',
    countFinding: c5fail,
  );

  // D2 ledger + res status
  final fD = await fixture(tag: 'd2', qty: 2, accept: true);
  String? oidD;
  HttpHit? dCpi;
  HttpHit? dSet;
  if (fD.sku != null && fD.res != null) {
    oidD = await c.insertOrder(
        productId: fD.sku!, buyer: b1, jwt: c.buyerJwt, price: 9);
    dCpi = oidD == null
        ? null
        : await c.checkout(
            orderId: oidD,
            buyer: b1,
            jwt: c.buyerJwt,
            amount: 1,
            productId: fD.sku,
            seller: s1,
            extra: {
              'live_id': fD.live,
              'live_item_id': fD.item,
              'reservation_request_id': fD.res,
              'is_live': true,
              'live_seller_id': s1,
            },
          );
    if (dCpi?.sessionId != null) {
      dSet = await c.edge(
        'create-payment-intent',
        method: 'GET',
        qs: 'checkout_return=success&session_id=${dCpi!.sessionId}',
      );
    }
  }
  final dRes = fD.res == null ? null : await c.resRow(fD.res!);
  final dOrd = oidD == null ? null : await c.orderRow(oidD);
  final dFail =
      dRes?['status'] == 'converted' || dOrd?['status'] == 'pago';
  c.probe(
    id: 'D2.convert.feliz.ledger',
    poco: 'DR-D',
    payload: 'pass2 accepted CPI ledger + settle unpaid',
    http: '${dCpi?.brief ?? 'n/a'} | ${dSet?.brief ?? 'n/a'}',
    bd: {
      'res': dRes,
      'ord': dOrd,
      'sid': dCpi?.sessionId,
      'ledger': oidD != null,
    },
    result: dFail ? 'FAIL' : (oidD == null ? 'SKIP' : 'HOLD'),
    lens: 'DR3',
    countFinding: dFail,
  );

  await c.endAllCreatedLives();
  await c.restoreSeller1Published();

  final counted = c.findings.where((f) => f['proven'] == true).toList();
  await dumpJson('${outDir()}/pass2.json', {
    'auditor': 'REDTEAM_BLIND_DR_TIP_RAFFLE_POS_DHDM_v1',
    'pass': 2,
    'prefix': prefix,
    'probes': c.probes,
    'findings': counted,
    'blocked': c.blocked,
    'notes': c.notes,
    'P0': counted.where((f) => f['severity'] == 'P0').length,
    'P1': counted.where((f) => f['severity'] == 'P1').length,
    'P2': counted.where((f) => f['severity'] == 'P2').length,
    'P3': counted.where((f) => f['severity'] == 'P3').length,
  });
  stdout.writeln(
    'PASS2 probes=${c.probes.length} findings=${counted.length}',
  );
}
