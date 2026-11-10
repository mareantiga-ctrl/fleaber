/// RED TEAM CEGO CG pass2 — tip unpaid/settle, CORS/origin/IPv6, Edge Mux hostil.
import 'dart:convert';
import 'dart:io';
import '_rtcg.dart';

bool hostileRedirect(String? loc) {
  if (loc == null || loc.isEmpty) return false;
  Uri u;
  try {
    u = Uri.parse(loc);
  } catch (_) {
    return loc.contains('evil') || loc.contains('nip.io') || loc.contains('sslip');
  }
  final h = u.host.toLowerCase();
  const allow = {
    'fleaber.pt',
    'www.fleaber.pt',
    'fleaber.app',
    'www.fleaber.app',
    'localhost',
    '127.0.0.1',
  };
  if (h.isEmpty) return false;
  if (allow.contains(h)) return false;
  return true;
}

Future<void> main() async {
  final c = Rtcg.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final ids = jsonDecode(await File('${outDir()}/pass1_ids.json').readAsString())
      as Map<String, dynamic>;
  final airUnpub = ids['airUnpub'] as String;
  final airPub = ids['airPub'] as String;
  final s1 = ids['s1'] as String;
  final s2 = ids['s2'] as String;

  // ---------- CG-C CORS / Origin / IPv6 ----------
  final origins = <String, String>{
    'evil': 'https://evil.example',
    'null': 'null',
    'ipv6loop': 'http://[::1]',
    'ipv6port': 'http://[::1]:5173',
    'ipv6mapped': 'http://[::ffff:127.0.0.1]',
    'ipv6mapped443': 'https://[::ffff:127.0.0.1]',
    'localhost': 'http://localhost:5173',
    'fleaber': 'https://fleaber.pt',
    'sub': 'https://evil.fleaber.pt',
    'puny': 'https://xn--fleaber-pta.pt',
  };
  for (final e in origins.entries) {
    final opt = await c.edge(
      'create-live-tip-checkout',
      method: 'OPTIONS',
      extra: {
        'Origin': e.value,
        'Access-Control-Request-Method': 'POST',
      },
    );
    final post = await c.edge(
      'resolve-mux-playback',
      body: {'live_id': airPub},
      extra: {'Origin': e.value},
    );
    c.note('cg2.cors.opt.${e.key}', 'OPTIONS Origin ${e.value}', opt, lens: 'CG2');
    c.note('cg2.cors.post.${e.key}', 'POST Origin ${e.value}', post, lens: 'CG2');
    final reflected = (opt.acao == e.value && e.key != 'fleaber' && e.key != 'localhost') ||
        (post.acao == e.value &&
            e.key != 'fleaber' &&
            e.key != 'localhost');
    if (reflected) {
      c.hold(
        id: 'CG2-CORS-REFLECT-${e.key}',
        lens: 'CG2',
        severity: 'P2',
        title: 'CORS reflecte Origin hostil ${e.value}',
        actor: 'browser',
        pre: 'Origin=${e.value}',
        repro: 'OPTIONS/POST Edge com Origin hostil',
        expected: 'ACAO=https://fleaber.pt ou omitido',
        obtained: {'opt': opt.brief, 'post': post.brief},
      );
    } else {
      c.block('cg2.cors.${e.key}', 'CG2', 'CORS não reflecte ${e.key}', opt);
    }
  }

  final returns = <String, String>{
    'ipv6': 'http://[::1]',
    'ipv6https': 'https://[::1]',
    'mapped': 'http://[::ffff:127.0.0.1]',
    'nip': 'https://127.0.0.1.nip.io',
    'sslip': 'https://127.0.0.1.sslip.io',
    'localtest': 'http://localtest.me',
    'lvh': 'http://lvh.me',
    'decimal': 'https://2130706433',
    'hex': 'https://0x7f000001',
    'short': 'http://127.1',
    'nullorigin': 'null',
    'file': 'file://',
    'evil': 'https://evil.example/wallet',
    'ok': 'https://fleaber.pt',
  };
  for (final e in returns.entries) {
    final h = await c.edge(
      'create-connect-account',
      method: 'GET',
      jwt: c.sellerJwt,
      qs: 'web_return_origin=${Uri.encodeQueryComponent(e.value)}',
      extra: {'Origin': e.value.startsWith('http') ? e.value : 'https://evil.example'},
    );
    c.note('cg2.return.${e.key}', 'connect return ${e.value}', h, lens: 'CG2');
    if (h.status == 303 && hostileRedirect(h.location)) {
      c.hold(
        id: 'CG2-RETURN-HOSTILE-${e.key}',
        lens: 'CG2',
        severity: 'P1',
        title: 'Connect 303 para origin hostil ${e.value}',
        actor: 'S1',
        pre: 'GET create-connect-account web_return_origin',
        repro: 'GET ?web_return_origin=${e.value}',
        expected: 'HTML wallet / sem 303 hostil',
        obtained: h.brief,
      );
    } else if (h.status == 303 && e.key != 'ok') {
      c.hold(
        id: 'CG2-RETURN-303-${e.key}',
        lens: 'CG2',
        severity: 'P3',
        title: 'Connect 303 inesperado para ${e.value}',
        actor: 'S1',
        pre: e.value,
        repro: 'GET create-connect-account web_return_origin',
        expected: '200 HTML ou reject',
        obtained: h.brief,
      );
    } else {
      c.block('cg2.return.${e.key}', 'CG2', 'return ${e.key} sem 303 hostil', h);
    }
  }

  // ---------- CG-B tip ----------
  final balS = await c.walletBal(s1);
  final tipIdClient = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyer2Jwt,
    body: {
      'live_id': airPub,
      'seller_id': s1,
      'amount_eur': 2,
      'tip_id': '00000000-0000-0000-0000-000000000001',
    },
  );
  c.note('cg3.tip.tipid', 'tip_id cliente', tipIdClient, lens: 'CG3');
  if (tipIdClient.ok) {
    c.hold(
      id: 'CG3-TIPID-CLIENT',
      lens: 'CG3',
      severity: 'P0',
      title: 'Edge aceita tip_id do cliente',
      actor: 'B2',
      pre: 'body.tip_id forjado',
      repro: 'POST create-live-tip-checkout tip_id=uuid',
      expected: '400 Client tip_id is not allowed',
      obtained: tipIdClient.brief,
    );
  } else {
    c.block('cg3.tip.tipid', 'CG3', 'tip_id cliente recusado', tipIdClient);
  }

  final tipWrongSeller = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyer2Jwt,
    body: {
      'live_id': airPub,
      'seller_id': s2,
      'amount_eur': 2,
    },
  );
  c.note('cg3.tip.wrongseller', 'tip seller ≠ owner', tipWrongSeller, lens: 'CG3');
  if (tipWrongSeller.ok) {
    c.hold(
      id: 'CG3-TIP-BIND-ALIEN-SELLER',
      lens: 'CG3',
      severity: 'P0',
      title: 'tip bind a seller que não é dono da live',
      actor: 'B2',
      pre: 'live S1 + seller_id S2',
      repro: 'POST create-live-tip-checkout seller_id=S2 live_id=S1',
      expected: '400',
      obtained: tipWrongSeller.brief,
    );
  } else {
    c.block('cg3.tip.wrongseller', 'CG3', 'tip seller mismatch recusado',
        tipWrongSeller);
  }

  final tipAlienLive = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyer2Jwt,
    body: {
      'live_id': airUnpub,
      'seller_id': s2,
      'amount_eur': 2,
    },
  );
  c.note('cg3.tip.unpub', 'tip em live unpublished air', tipAlienLive, lens: 'CG3');
  if (tipAlienLive.ok) {
    c.hold(
      id: 'CG3-TIP-UNPUB-AIR',
      lens: 'CG3',
      severity: 'P2',
      title: 'checkout gorjeta em directo unpublished no ar',
      actor: 'B2',
      pre: 'S2 hub off + broadcasting',
      repro: 'POST create-live-tip-checkout live unpublished',
      expected: 'recusa (loja desligada)',
      obtained: tipAlienLive.brief,
    );
  } else {
    c.block('cg3.tip.unpub', 'CG3', 'tip unpublished recusado', tipAlienLive);
  }

  for (final amt in [0, 0.01, -1, 501, 0.5]) {
    final t = await c.edge(
      'create-live-tip-checkout',
      jwt: c.buyer2Jwt,
      body: {
        'live_id': airPub,
        'seller_id': s1,
        'amount_eur': amt,
      },
    );
    c.note('cg3.tip.amt.$amt', 'tip amount $amt', t, lens: 'CG3');
    if (t.ok) {
      c.hold(
        id: 'CG3-TIP-AMOUNT-$amt',
        lens: 'CG3',
        severity: amt >= 501 ? 'P2' : 'P1',
        title: 'tip aceita amount_eur=$amt',
        actor: 'B2',
        pre: 'teto 1–500',
        repro: 'POST create-live-tip-checkout amount_eur=$amt',
        expected: '400 Invalid tip amount',
        obtained: t.brief,
      );
    } else {
      c.block('cg3.tip.amt.$amt', 'CG3', 'amount $amt recusado', t);
    }
  }

  final tipOk = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyer2Jwt,
    body: {
      'live_id': airPub,
      'seller_id': s1,
      'amount_eur': 2,
      'web_return_origin': 'http://[::1]',
      'stripe_session_id': 'cs_test_forged',
    },
  );
  c.note('cg3.tip.create', 'tip unpaid session', tipOk, lens: 'CG3');
  String? tipId;
  String? sessionId;
  if (tipOk.map != null) {
    tipId = tipOk.map!['tipId']?.toString();
    sessionId = tipOk.map!['checkoutSessionId']?.toString();
  }
  if (tipId != null) c.createdTipIds.add(tipId);

  if (sessionId != null && sessionId.isNotEmpty) {
    final getUnpaid = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      jwt: c.buyer2Jwt,
      qs: 'checkout_return=success&session_id=$sessionId',
    );
    final getAnon = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      qs: 'checkout_return=success&session_id=$sessionId',
    );
    final getReplay = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      qs: 'checkout_return=success&session_id=$sessionId',
    );
    c.note('cg3.tip.get.b2', 'GET settle unpaid B2', getUnpaid, lens: 'CG3');
    c.note('cg3.tip.get.anon', 'GET settle unpaid anon', getAnon, lens: 'CG3');
    c.note('cg3.tip.get.replay', 'GET settle replay', getReplay, lens: 'CG3');

    final rpcB2 = await c.rpc(
      'batata_settle_live_tip_from_stripe',
      {
        'p_tip_id': tipId,
        'p_stripe_session_id': sessionId,
        'p_paid_amount_cents': 200,
      },
      jwt: c.buyer2Jwt,
    );
    final rpcAnon = await c.rpc(
      'batata_settle_live_tip_from_stripe',
      {
        'p_tip_id': tipId,
        'p_stripe_session_id': sessionId,
        'p_paid_amount_cents': 200,
      },
    );
    c.note('cg3.tip.rpc.b2', 'RPC settle JWT B2', rpcB2, lens: 'CG3');
    c.note('cg3.tip.rpc.anon', 'RPC settle anon', rpcAnon, lens: 'CG3');

    final tipRow = await c.rest(
      'GET',
      'live_tips?id=eq.$tipId&select=id,status,amount,buyer_id,seller_id,stripe_session_id',
      service: true,
    );
    final balAfter = await c.walletBal(s1);
    c.note('cg3.tip.row', 'tip row after unpaid settle', tipRow, lens: 'CG3');
    c.note('cg3.tip.wallet', 'Δwallet S1', {'before': balS, 'after': balAfter},
        lens: 'CG3');

    final st = '${tipRow.map?['status'] ?? ''}';
    final credited = st == 'paid' || st == 'settled' || (balAfter - balS) > 0;
    if (credited) {
      c.hold(
        id: 'CG3-TIP-UNPAID-CREDIT',
        lens: 'CG3',
        severity: 'P0',
        title: 'tip unpaid creditou seller / status pago',
        actor: 'B2',
        pre: 'Session criada, NÃO paga',
        repro:
            'GET create-live-tip-checkout?checkout_return=success&session_id=cs_…; RPC settle',
        expected: 'pending; Δwallet=0; «Pagamento ainda não confirmado»',
        obtained: {
          'get': getUnpaid.brief,
          'rpc': rpcB2.brief,
          'status': st,
          'delta': balAfter - balS,
        },
      );
    } else {
      c.block('cg3.unpaid.credit', 'CG3', 'unpaid não credita', {
        'status': st,
        'delta': balAfter - balS,
        'get': getUnpaid.brief,
      });
    }

    final paidMsg = getUnpaid.body.toLowerCase().contains('pagamento recebido') ||
        getUnpaid.body.toLowerCase().contains('confirmado') &&
            !getUnpaid.body.toLowerCase().contains('ainda não');
    if (paidMsg && !credited) {
      c.hold(
        id: 'CG3-TIP-UNPAID-PAID-COPY',
        lens: 'CG3',
        severity: 'P2',
        title: 'GET return diz pago sem Stripe paid',
        actor: 'B2',
        pre: sessionId,
        repro: 'GET checkout_return=success unpaid session',
        expected: '«Pagamento ainda não confirmado»',
        obtained: getUnpaid.brief,
      );
    }
  } else {
    c.skip('cg3.tip.session', 'CG3', 'não criou session tip', tipOk);
  }

  final wh = await c.edge(
    'stripe-webhook',
    body: {
      'type': 'checkout.session.completed',
      'data': {
        'object': {
          'id': sessionId ?? 'cs_test_fake',
          'payment_status': 'paid',
          'metadata': {'purpose': 'live_tip', 'tip_id': tipId},
        },
      },
    },
    extra: {'stripe-signature': 't=1,v1=deadbeef'},
  );
  c.note('cg3.webhook.forged', 'webhook assinatura forjada', wh, lens: 'CG3');
  if (wh.ok) {
    c.hold(
      id: 'CG3-WEBHOOK-FORGED',
      lens: 'CG3',
      severity: 'P0',
      title: 'stripe-webhook aceita assinatura forjada',
      actor: 'anon',
      pre: 'stripe-signature lixo',
      repro: 'POST stripe-webhook v1=deadbeef',
      expected: '400 invalid_signature',
      obtained: wh.brief,
    );
  } else {
    c.block('cg3.webhook', 'CG3', 'webhook forjado recusado', wh);
  }

  // ---------- CG-C/CG4 Edge Mux hostil ----------
  final cmB2 = await c.edge(
    'complete-mux-live',
    jwt: c.buyer2Jwt,
    body: {'live_id': airPub},
  );
  final cmAnon = await c.edge(
    'complete-mux-live',
    body: {'live_id': airPub},
  );
  final cmS2 = await c.edge(
    'complete-mux-live',
    jwt: c.seller2Jwt,
    body: {'live_id': airPub},
  );
  final cmS2own = await c.edge(
    'complete-mux-live',
    jwt: c.seller2Jwt,
    body: {'live_id': airUnpub},
  );
  c.note('cg4.cm.b2', 'complete-mux B2 vs S1', cmB2, lens: 'CG4');
  c.note('cg4.cm.anon', 'complete-mux anon', cmAnon, lens: 'CG4');
  c.note('cg4.cm.s2', 'complete-mux S2 vs S1', cmS2, lens: 'CG4');
  c.note('cg4.cm.s2own', 'complete-mux S2 own unpublished', cmS2own, lens: 'CG4');
  if (cmB2.ok || cmS2.ok || cmAnon.ok) {
    c.hold(
      id: 'CG4-COMPLETE-MUX-CROSS',
      lens: 'CG4',
      severity: 'P0',
      title: 'complete-mux cruzado sucedeu',
      actor: cmB2.ok ? 'B2' : (cmS2.ok ? 'S2' : 'anon'),
      pre: airPub,
      repro: 'POST complete-mux-live live_id S1',
      expected: '403/401',
      obtained: {'b2': cmB2.brief, 's2': cmS2.brief, 'anon': cmAnon.brief},
    );
  } else {
    c.block('cg4.cm.cross', 'CG4', 'complete-mux cruzado recusado', cmB2);
  }

  final leakKey = '${cmS2own.body}${cmB2.body}${cmAnon.body}'.contains('stream_key') ||
      '${cmS2own.body}'.contains('mux_stream_key');
  if (leakKey) {
    c.hold(
      id: 'CG4-EDGE-STREAMKEY',
      lens: 'CG4',
      severity: 'P1',
      title: 'Edge complete-mux vaza stream key',
      actor: 'S2',
      pre: airUnpub,
      repro: 'POST complete-mux-live',
      expected: 'sem stream_key no body',
      obtained: cmS2own.brief,
    );
  }

  final lkB2 = await c.edge(
    'livekit-mux-publish',
    jwt: c.buyer2Jwt,
    body: {'step': 'token', 'live_id': airPub},
  );
  final egB2 = await c.edge(
    'livekit-mux-publish',
    jwt: c.buyer2Jwt,
    body: {'step': 'egress', 'live_id': airPub, 'stream_key': 'stolen'},
  );
  c.note('cg4.lk.b2', 'livekit token B2', lkB2, lens: 'CG4');
  c.note('cg4.eg.b2', 'egress B2', egB2, lens: 'CG4');
  if (lkB2.ok) {
    c.hold(
      id: 'CG4-LK-TOKEN-CROSS',
      lens: 'CG4',
      severity: 'P1',
      title: 'B2 obtém token LiveKit de live S1',
      actor: 'B2',
      pre: airPub,
      repro: 'POST livekit-mux-publish step=token',
      expected: '403',
      obtained: lkB2.brief,
    );
  } else {
    c.block('cg4.lk.b2', 'CG4', 'livekit cruzado recusado', lkB2);
  }

  final buyerMux = await c.edge(
    'create-mux-live',
    jwt: c.buyerJwt,
    body: {'title': '$prefix buyer mux'},
  );
  c.note('cg4.create.buyer', 'create-mux buyer', buyerMux, lens: 'CG4');
  if (buyerMux.ok) {
    c.hold(
      id: 'CG4-CREATE-MUX-BUYER',
      lens: 'CG4',
      severity: 'P1',
      title: 'comprador cria stream Mux',
      actor: 'B1',
      pre: 'user_type comprador',
      repro: 'POST create-mux-live',
      expected: '403',
      obtained: buyerMux.brief,
    );
  } else {
    c.block('cg4.create.buyer', 'CG4', 'buyer não cria Mux', buyerMux);
  }

  final patchB1 = await c.rest(
    'PATCH',
    'lives?id=eq.$airPub',
    jwt: c.buyerJwt,
    body: {'mux_live_id': 'stolen_mux', 'mux_playback_id': 'stolen_pb'},
  );
  final insB1 = await c.rest(
    'POST',
    'lives',
    jwt: c.buyerJwt,
    body: {
      'seller_id': s1,
      'title': '$prefix hijack',
      'status': 'live',
      'is_active': true,
      'mux_live_id': 'stolen',
    },
  );
  c.note('cg4.patch.b1', 'PATCH live S1 as B1', patchB1, lens: 'CG4');
  c.note('cg4.insert.b1', 'INSERT lives as B1', insB1, lens: 'CG4');
  if (patchB1.ok &&
      (patchB1.list.isNotEmpty || patchB1.body.contains('stolen'))) {
    c.hold(
      id: 'CG4-PATCH-LIVE-CROSS',
      lens: 'CG4',
      severity: 'P1',
      title: 'B1 altera mux_live_id de live S1',
      actor: 'B1',
      pre: airPub,
      repro: 'PATCH lives mux_live_id',
      expected: '0 rows / 403',
      obtained: patchB1.brief,
    );
  } else {
    c.block('cg4.patch.b1', 'CG4', 'PATCH cruzado recusado', patchB1);
  }
  if (insB1.ok) {
    c.hold(
      id: 'CG4-INSERT-LIVE-CROSS',
      lens: 'CG4',
      severity: 'P1',
      title: 'B1 INSERT live com seller_id alheio',
      actor: 'B1',
      pre: 'seller_id=S1',
      repro: 'POST /rest/v1/lives',
      expected: '403',
      obtained: insB1.brief,
    );
  } else {
    c.block('cg4.insert.b1', 'CG4', 'INSERT lives JWT recusado', insB1);
  }

  final cleanup = await c.edge(
    'livekit-egress-cleanup',
    body: {},
    extra: {'x-cleanup-secret': 'wrong', 'Origin': 'https://evil.example'},
  );
  c.note('cg4.cleanup', 'cleanup secret errado', cleanup, lens: 'CG4');
  if (cleanup.ok) {
    c.hold(
      id: 'CG4-CLEANUP-UNAUTH',
      lens: 'CG4',
      severity: 'P1',
      title: 'egress-cleanup sem segredo',
      actor: 'anon',
      pre: 'x-cleanup-secret=wrong',
      repro: 'POST livekit-egress-cleanup',
      expected: '401',
      obtained: cleanup.brief,
    );
  } else {
    c.block('cg4.cleanup', 'CG4', 'cleanup recusado', cleanup);
  }

  await dumpJson('${outDir()}/pass2.json', {
    'lenses': c.lensesHit.toList()..sort(),
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'skipped': c.skipped,
    'tipId': tipId,
    'sessionId': sessionId,
  });
}
