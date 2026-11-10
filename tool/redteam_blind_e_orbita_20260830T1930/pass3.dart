/// Pass 3 — checkout com buyer_id; provar Session em morto+live_id; lives cols; bundle accept.
import 'dart:io';
import '_rte.dart';

void main() async {
  final env = loadEnv();
  final c = Rte.fromEnv(env);
  await c.loginActors(env);

  final findings = <Map<String, dynamic>>[];
  final log = <String, dynamic>{};
  var n = 40;
  String nid(String s) => 'E1930-${s.toUpperCase()}-${++n}';

  Future<HttpHit> ck(String oid, {String? origin, Map<String, Object?> extra = const {}}) {
    return c.edge('create-payment-intent', {
      'order_id': oid,
      'buyer_id': c.buyerId,
      'currency': 'eur',
      if (origin != null) 'web_return_origin': origin,
      ...extra,
    }, jwt: c.buyerJwt);
  }

  bool hasSession(HttpHit h) =>
      h.ok && (h.body.contains('cs_test_') || h.body.contains('checkout.stripe.com'));

  // Existing fixtures from pass2
  const stampOid = 'c5d6b577-19b9-491e-b286-ea12cebf3c15'; // unlist + live stamp
  const thenOid = 'dc3550fd-a813-4c8d-bfe7-208ca7875875'; // hold then unlist
  const bunOid = '03a7b734-9dc8-4e11-aad4-6aff8cab93fa';
  const okOid = 'ef2c31a2-6ecb-4dcb-b5ba-75a4f2191067';
  const bunId = '86c8e11b-d682-4e6f-8517-516e484fee2e';
  const unlistPid = '3c58b97d-a083-47c3-9a0f-df8397b58d61';

  final ckStamp = await ck(stampOid);
  log['ck_stamp'] = {'http': ckStamp.status, 'snip': ckStamp.snippet};
  findings.add(finding(
    id: nid('e6-stamp-session'),
    lens: 'E6',
    severity: hasSession(ckStamp) ? 'P1' : (ckStamp.status == 400 ? 'P2' : 'INFO'),
    title: hasSession(ckStamp)
        ? 'Unlisted+live_id stamp → Stripe Checkout Session TEST'
        : 'Checkout unlist+stamp: ${ckStamp.status} ${ckStamp.snippet}',
    pre: 'order $stampOid product unlisted live_id ended',
    repro: 'POST create-payment-intent order_id+buyer_id JWT buyer',
    proven: hasSession(ckStamp) ||
        (ckStamp.status == 400 &&
            !ckStamp.body.contains('not listed') &&
            !ckStamp.body.contains('sold')),
    evidence: {
      'http': ckStamp.status,
      'snip': ckStamp.snippet,
      'session': hasSession(ckStamp),
    },
    note: hasSession(ckStamp)
        ? 'SESSION aberta; captura Stripe não neste passo.'
        : 'hold 201 já provado; este passo é o gate Edge.',
  ));

  final ckThen = await ck(thenOid);
  log['ck_then'] = {'http': ckThen.status, 'snip': ckThen.snippet};
  findings.add(finding(
    id: nid('e6-then-unlist-session'),
    lens: 'E6',
    severity: hasSession(ckThen) ? 'P1' : 'INFO',
    title: hasSession(ckThen)
        ? 'Hold listed → unlist → Session ainda abre'
        : 'Edge bloqueia checkout após unlist (sem live_id)',
    pre: 'order $thenOid',
    repro: 'POST create-payment-intent after unlist',
    proven: hasSession(ckThen),
    evidence: {'http': ckThen.status, 'snip': ckThen.snippet},
  ));

  final ckBun = await ck(bunOid);
  log['ck_bun'] = {'http': ckBun.status, 'snip': ckBun.snippet};
  findings.add(finding(
    id: nid('e4-bun-session'),
    lens: 'E4',
    severity: hasSession(ckBun) ? 'P1' : 'INFO',
    title: hasSession(ckBun)
        ? 'Bundle pending 0.50€ → Session'
        : 'Edge recusa/ajusta bundle pending',
    pre: 'bundle $bunId pending total 0.50',
    repro: 'create-payment-intent order with bundle_id',
    proven: hasSession(ckBun),
    evidence: {'http': ckBun.status, 'snip': ckBun.snippet},
  ));

  final ckOk = await ck(okOid, origin: 'https://attacker.fleaber.pt');
  log['ck_ok_redir'] = {'http': ckOk.status, 'snip': ckOk.snippet};
  findings.add(finding(
    id: nid('e7-session-origin'),
    lens: 'E7',
    severity: hasSession(ckOk) ? 'P2' : 'INFO',
    title: hasSession(ckOk)
        ? 'Session criada com web_return_origin attacker.fleaber.pt'
        : 'Checkout listed-ok falhou (não testa origin)',
    pre: 'sanitize endsWith .fleaber.pt',
    repro: 'create-payment-intent web_return_origin=https://attacker.fleaber.pt',
    proven: hasSession(ckOk),
    evidence: {'http': ckOk.status, 'snip': ckOk.snippet},
  ));

  // Buyer tries to self-accept bundle
  final acc = await c.rest('PATCH', 'product_bundles?id=eq.$bunId', jwt: c.buyerJwt, prefer: 'return=representation', body: {
    'status': 'accepted',
  });
  log['buyer_accept'] = {'http': acc.status, 'snip': acc.snippet};
  findings.add(finding(
    id: nid('e4-buyer-accept'),
    lens: 'E4',
    severity: acc.ok && acc.body.contains('accepted') ? 'P1' : 'INFO',
    title: acc.ok && acc.body.contains('accepted')
        ? 'Buyer PATCH bundle → accepted (self-accept)'
        : 'Buyer não aceita o próprio bundle',
    pre: 'guard bundle_accept_seller_only',
    repro: 'PATCH product_bundles status=accepted JWT buyer',
    proven: acc.ok && acc.body.contains('"status":"accepted"'),
    evidence: {'http': acc.status, 'snip': acc.snippet},
  ));

  // lives columns as anon
  for (final sel in [
    'id,status,title',
    'id,mux_playback_id',
    'id,viewer_count',
    'id,publish_backend',
  ]) {
    final h = await c.rest('GET', 'lives?select=$sel&limit=2');
    log['lives_$sel'] = {'http': h.status, 'snip': h.snippet};
  }

  // Hub still shows unlisted? (should not if list_on_marketplace false)
  final hubUn = await c.rest('GET', 'hub_products_public?id=eq.$unlistPid&select=id,title,is_sold');
  log['hub_unlist'] = {'http': hubUn.status, 'snip': hubUn.snippet};

  // Confirm hold still on unlisted product (stock)
  final prod = await c.rest(
    'GET',
    'products?id=eq.$unlistPid&select=id,quantity,is_sold,list_on_marketplace',
    service: true,
  );
  log['unlist_stock'] = {'http': prod.status, 'snip': prod.snippet};
  final held = await c.rpc('batata_product_held_qty', {'p_product_id': unlistPid}, service: true);
  log['held_qty'] = {'http': held.status, 'snip': held.snippet};

  final outPath = Directory.current.path.endsWith('20260830T1930')
      ? 'out/pass3.json'
      : 'tool/redteam_blind_e_orbita_$stamp/out/pass3.json';
  await dumpJson(outPath, {'stamp': stamp, 'log': log, 'findings': findings});
  stdout.writeln('pass3 proven=${findings.where((f) => f['proven'] == true).length}');
  stdout.writeln(ckStamp.snippet);
  stdout.writeln(outPath);
}
