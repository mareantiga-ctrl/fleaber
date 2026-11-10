import '_rtcn.dart';

/// Pass 3 — CN2 web_return · CN5 wallet RLS · 2.º webhook sig inválida
void main() async {
  final c = Rtcn.fromEnv(loadEnv());
  await c.loginActors();

  final wr = await c.connect({
    'web_return_origin': 'https://fleaber.pt.evil.pt',
  });
  final url = '${wr.map?['url'] ?? ''} ${wr.location ?? ''}'.toLowerCase();
  final hostile = url.contains('evil');
  c.probe(
    id: 'CN-2-WR-EVILPT',
    lens: 'CN2',
    payload: 'POST web_return_origin=https://fleaber.pt.evil.pt',
    httpBd: wr.brief,
    result: hostile ? 'FAIL' : 'HOLD',
  );
  if (hostile) {
    c.hold(
      id: 'CN-P2-WR-EVILPT',
      lens: 'CN2',
      severity: 'P2',
      title: 'web_return_origin suffix evil vazou para Stripe url',
      actor: 'seller JWT',
      pre: 'sanitizeWebReturnOrigin allowlist',
      repro: 'POST create-connect-account {web_return_origin: https://fleaber.pt.evil.pt}',
      expected: 'url Stripe sem host hostil',
      obtained: wr.brief,
    );
  } else {
    c.block('wr.evilpt', 'CN2', 'POST origin não vazou hostil', wr);
  }

  final insOwn = await c.rest('POST', 'wallets', jwt: c.sellerJwt, body: {
    'id': c.sellerId,
    'balance': 99999.99,
  });
  c.probe(
    id: 'CN-5-WALLET-INS',
    lens: 'CN5',
    payload: 'JWT POST wallets {id:self, balance:99999.99}',
    httpBd: insOwn.brief,
    result: insOwn.ok ? 'FAIL' : 'HOLD',
  );
  await c.expectDenied(
    id: 'CN-P0-WALLET-INS-OWN',
    lens: 'CN5',
    title: 'JWT INSERT wallets própria com saldo 99999',
    hit: insOwn,
    actor: 'seller JWT',
    pre: 'INSERT wallets revogado',
    repro: 'POST /rest/v1/wallets {id:self, balance:99999.99}',
    severityIfOpen: 'P0',
    openIf: (h) => h.ok,
  );

  final balBefore = await c.walletBal(c.sellerId);
  final updBal = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {'balance': 77777.00},
  );
  final balAfter = await c.walletBal(c.sellerId);
  final minted = updBal.ok && (balAfter - balBefore).abs() > 0.009;
  c.probe(
    id: 'CN-5-WALLET-PATCH',
    lens: 'CN5',
    payload: 'JWT PATCH wallets.balance=77777',
    httpBd: '${updBal.brief} before=$balBefore after=$balAfter',
    result: minted ? 'FAIL' : 'HOLD',
  );
  if (minted) {
    c.hold(
      id: 'CN-P0-WALLET-PATCH-BAL',
      lens: 'CN5',
      severity: 'P0',
      title: 'JWT PATCH wallets.balance mintou saldo',
      actor: 'seller JWT',
      pre: 'sem policy UPDATE wallets',
      repro: 'PATCH wallets?id=eq.self {balance:77777}',
      expected: 'denied, Δ=0',
      obtained: {'hit': updBal.brief, 'before': balBefore, 'after': balAfter},
    );
  } else {
    c.block('rls.patch.bal', 'CN5', 'JWT PATCH balance recusado ou Δ=0', updBal);
  }

  final whOld = await c.req(
    'POST',
    '/functions/v1/stripe-webhook',
    jwt: c.sellerJwt,
    body:
        '{"id":"evt_rtcn_replay","type":"checkout.session.completed","created":1600000000,"data":{"object":{"id":"cs_rtcn_old","payment_status":"paid"}}}',
    extra: {'stripe-signature': 't=1600000000,v1=deadbeefdeadbeef'},
  );
  c.probe(
    id: 'CN-C-WH-OLDSIG',
    lens: 'CN4',
    payload: 'POST stripe-webhook t=2020 sig lixo',
    httpBd: whOld.brief,
    result: whOld.ok ? 'FAIL' : 'HOLD',
  );
  if (whOld.ok) {
    c.hold(
      id: 'CN-P0-WH-OLD',
      lens: 'CN4',
      severity: 'P0',
      title: 'webhook evento antigo com assinatura inválida aceite',
      actor: 'seller JWT',
      pre: 'signature fail → 400',
      repro: 'POST stripe-webhook Stripe-Signature=t=1600000000,v1=deadbeef',
      expected: '400 invalid_signature',
      obtained: whOld.brief,
    );
  } else {
    c.block('wh.oldsig', 'CN4', 'evento antigo + sig inválida recusado', whOld);
  }

  await c.dumpAll('pass3.json');
}
