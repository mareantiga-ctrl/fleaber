/// RED TEAM CEGO CA pass2 — REST cols seguras unpublished, origin/CORS, tip unpaid, complete-mux, LiveKit.
import 'dart:convert';
import 'dart:io';
import '_rtca.dart';

Future<Map<String, dynamic>> loadIds() async {
  final f = File('${outDir()}/pass1.json');
  final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  return Map<String, dynamic>.from(j['ids'] as Map);
}

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
  final c = Rtca.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final ids = await loadIds();
  final airUnpub = ids['airUnpub'] as String;
  final schedUnpub = ids['schedUnpub'] as String;
  final endedUnpub = ids['endedUnpub'] as String;
  final airPub = ids['airPub'] as String;
  final schedPub = ids['schedPub'] as String;
  final endedPub = ids['endedPub'] as String;
  final s2 = ids['s2'] as String;
  final s1 = ids['s1'] as String;

  const pbOnly = 'id,status,is_active,seller_id,title,mux_playback_id,playback_id';
  const vodOnly = 'id,status,mux_vod_playback_id,mux_asset_id';

  Future<void> colProbe(String label, String id) async {
    final anon = await c.rest('GET', 'lives?id=eq.$id&select=$pbOnly');
    final b1 = await c.rest('GET', 'lives?id=eq.$id&select=$pbOnly', jwt: c.buyerJwt);
    final b2 = await c.rest('GET', 'lives?id=eq.$id&select=$pbOnly', jwt: c.buyer2Jwt);
    final s2j = await c.rest('GET', 'lives?id=eq.$id&select=$pbOnly', jwt: c.seller2Jwt);
    final vodB1 = await c.rest('GET', 'lives?id=eq.$id&select=$vodOnly', jwt: c.buyerJwt);
    c.note('ca7.cols.anon.$label', 'anon pb-only', anon, lens: 'CA7');
    c.note('ca7.cols.b1.$label', 'B1 pb-only', b1, lens: 'CA7');
    c.note('ca7.cols.b2.$label', 'B2 pb-only', b2, lens: 'CA7');
    c.note('ca7.cols.s2.$label', 'S2 pb-only', s2j, lens: 'CA7');
    c.note('ca5.vod.b1.$label', 'B1 vod-only', vodB1, lens: 'CA5');

    final unpub = label.contains('Unpub');
    final b1pb = col(b1.map, 'mux_playback_id') ?? col(b1.map, 'playback_id');
    final anonpb = col(anon.map, 'mux_playback_id') ?? col(anon.map, 'playback_id');
    final s2pb = col(s2j.map, 'mux_playback_id') ?? col(s2j.map, 'playback_id');
    final vod = col(vodB1.map, 'mux_vod_playback_id');

    if (unpub && anonpb != null) {
      c.hold(
        id: 'CA7-ANON-RESTPB-$label',
        lens: 'CA7',
        severity: 'P2',
        title: 'anon REST playback unpublished $label',
        actor: 'anon',
        pre: id,
        repro: 'GET lives?id=eq.$id&select=mux_playback_id,playback_id',
        expected: '401/403 ou sem colunas',
        obtained: anon.brief,
      );
    } else {
      c.block('ca7.anon.pb.$label', 'CA7', 'anon sem REST pb $label', anon);
    }

    if (unpub && b1pb != null) {
      c.hold(
        id: 'CA7-B1-RESTPB-$label',
        lens: 'CA7',
        severity: 'P2',
        title: 'B1 (não-dono) REST mux/playback unpublished $label',
        actor: 'B1',
        pre: 'S2 hub_published=false live=$id',
        repro: 'GET /rest/v1/lives?id=eq.$id&select=id,mux_playback_id,playback_id JWT B1',
        expected: 'sem playback (Hub unpublished; resolve-mux 404 anon/B1)',
        obtained: {
          'brief': b1.brief,
          'mux_playback_id': col(b1.map, 'mux_playback_id'),
          'playback_id': col(b1.map, 'playback_id'),
        },
      );
    } else if (unpub) {
      c.block('ca7.b1.pb.$label', 'CA7', 'B1 sem REST pb unpublished $label', b1);
    }

    if (unpub && s2pb != null && b1pb == null) {
      c.note('ca7.owner.rest.split.$label', 'só dono S2 lê REST pb unpublished', {
        's2': s2j.brief,
        'b1': b1.brief,
      }, lens: 'CA7');
    }

    if (vod != null && unpub) {
      c.hold(
        id: 'CA5-B1-RESTVOD-$label',
        lens: 'CA5',
        severity: 'P1',
        title: 'B1 lê mux_vod_playback_id unpublished $label',
        actor: 'B1',
        pre: id,
        repro: 'GET lives mux_vod_playback_id',
        expected: 'coluna revogada',
        obtained: vodB1.brief,
      );
    } else {
      c.block('ca5.b1.vod.$label', 'CA5', 'B1 sem VOD REST $label', vodB1);
    }
  }

  await colProbe('airUnpub', airUnpub);
  await colProbe('schedUnpub', schedUnpub);
  await colProbe('endedUnpub', endedUnpub);
  await colProbe('airPub', airPub);
  await colProbe('schedPub', schedPub);

  // seller_id filter
  final bySeller = await c.rest(
    'GET',
    'lives?seller_id=eq.$s2&select=$pbOnly&order=created_at.desc',
    jwt: c.buyerJwt,
  );
  c.note('ca7.b1.s2lives', 'B1 lista lives S2 unpublished', {
    'status': bySeller.status,
    'n': bySeller.list.length,
    'brief': bySeller.brief,
  }, lens: 'CA7');
  var anyPb = false;
  for (final row in bySeller.list) {
    if (row is Map) {
      final m = Map<String, dynamic>.from(row);
      if (col(m, 'mux_playback_id') != null || col(m, 'playback_id') != null) {
        anyPb = true;
      }
    }
  }
  if (bySeller.ok && anyPb) {
    c.hold(
      id: 'CA7-B1-S2-LIVES-PB',
      lens: 'CA7',
      severity: 'P2',
      title: 'B1 lista lives da loja unpublished com playback',
      actor: 'B1',
      pre: 'seller_id=S2 hub_published=false',
      repro: 'GET lives?seller_id=eq.$s2&select=mux_playback_id,playback_id',
      expected: '[] ou sem playback',
      obtained: {'n': bySeller.list.length, 'brief': bySeller.brief},
    );
  } else {
    c.block('ca7.b1.s2lives', 'CA7', 'B1 não lista playback S2', bySeller);
  }

  // Profiles discovery unpublished-while-live
  final profDisc = await c.rest(
    'GET',
    'hub_profiles_discovery_public?id=eq.$s2&select=id,handle,hub_published,full_name',
  );
  c.note('ca1.profdisc.s2', 'profiles discovery S2', profDisc, lens: 'CA1');
  if (profDisc.list.isNotEmpty && profDisc.map?['hub_published'] == false) {
    c.hold(
      id: 'CA1-PROFDISC-UNPUB-AIR',
      lens: 'CA1',
      severity: 'P2',
      title: 'FleaHub discovery de perfis mostra loja unpublished em directo',
      actor: 'anon',
      pre: 'S2 hub_published=false com live is_active',
      repro: 'GET hub_profiles_discovery_public?id=eq.$s2',
      expected:
          '[] alinhado a hub_lives_discovery (BRBW exige published) / hub_profiles_public',
      obtained: profDisc.brief,
    );
  } else {
    c.block('ca1.profdisc.s2', 'CA1', 'profiles discovery esconde unpublished', profDisc);
  }

  final slug = '${profDisc.map?['handle'] ?? 'rtca-20260906t1137-s2'}';
  final rh = await c.rpc('batata_resolve_handle', {'p_handle': slug});
  c.note('ca1.rh.slug', 'resolve_handle slug discovery', rh, lens: 'CA1');
  if (rh.map?['found'] == true) {
    c.hold(
      id: 'CA1-RESOLVE-HANDLE-UNPUB-SLUG',
      lens: 'CA1',
      severity: 'P2',
      title: 'resolve_handle encontra loja unpublished pelo slug de discovery',
      actor: 'anon',
      pre: 'slug=$slug S2 unpublished',
      repro: 'POST batata_resolve_handle {"p_handle":"$slug"}',
      expected: 'not_found',
      obtained: rh.brief,
    );
  } else {
    c.block('ca1.rh.slug', 'CA1', 'resolve_handle slug unpublished not_found', rh);
  }

  // ---------- CA2 CORS ----------
  final corsOrigins = [
    'https://evil.example',
    'https://fleaber.pt.evil.com',
    'https://evil.fleaber.pt',
    'null',
    'https://fleaber.pt',
    'http://localhost:5173',
    'http://127.0.0.1:3000',
    'https://127.0.0.1.nip.io',
    'https://attacker.com',
    'chrome-extension://abc',
  ];
  for (final origin in corsOrigins) {
    final opt = await c.edge(
      'resolve-mux-playback',
      method: 'OPTIONS',
      extra: {
        'Origin': origin,
        'Access-Control-Request-Method': 'POST',
      },
      body: {},
    );
    final post = await c.edge(
      'resolve-mux-playback',
      extra: {'Origin': origin},
      body: {'live_id': airPub},
    );
    c.note('ca2.cors.opt.$origin', 'OPTIONS', {
      'acao': opt.acao,
      'status': opt.status,
    }, lens: 'CA2');
    c.note('ca2.cors.post.$origin', 'POST', {
      'acao': post.acao,
      'status': post.status,
    }, lens: 'CA2');
    final reflected = post.acao == origin &&
        origin != 'https://fleaber.pt' &&
        !origin.startsWith('http://localhost') &&
        !origin.startsWith('http://127.0.0.1');
    if (reflected) {
      c.hold(
        id: 'CA2-CORS-REFLECT-$origin',
        lens: 'CA2',
        severity: 'P2',
        title: 'CORS reflecte Origin hostil',
        actor: 'anon',
        pre: 'Origin=$origin',
        repro: 'POST resolve-mux-playback Origin=$origin',
        expected: 'ACAO=https://fleaber.pt ou omitido',
        obtained: post.acao,
      );
    }
  }

  // ---------- CA2 web_return IPv6 / nip.io ----------
  final wr = <String>[
    'https://[::ffff:127.0.0.1]',
    'https://[::1]',
    'http://[::1]',
    'https://127.0.0.1.nip.io',
    'http://127.0.0.1.nip.io',
    'https://0.0.0.0.nip.io',
    'https://2130706433.nip.io',
    'https://localtest.me',
    'https://127.0.0.1.sslip.io',
    'https://lvh.me',
    'https://fleaber.pt.nip.io',
    'https://fleaber.pt.evil.com',
    'https://evil.com',
    'https://2130706433',
    'https://127.1',
    'https://0x7f000001',
    'http://127.0.0.1',
    'https://fleaber.pt',
    'https://[::ffff:7f00:1]',
    'https://localhost.nip.io',
    'https://fleaber.pt%2eevil.com',
    'https://fleaber.pt:443@evil.com',
    'https://127.0.0.1:80@evil.com',
    'https://user:pass@fleaber.pt',
    'https://fleaber.pt./',
    'http://0.0.0.0',
    'https://[fe80::1]',
  ];
  for (final origin in wr) {
    final qs =
        'web_return_origin=${Uri.encodeQueryComponent(origin)}';
    final h = await c.edge(
      'create-connect-account',
      method: 'GET',
      qs: qs,
    );
    c.note('ca2.wr.$origin', 'web_return GET', {
      'status': h.status,
      'loc': h.location,
      'acao': h.acao,
      'html': h.status == 200 && h.body.contains('<html'),
    }, lens: 'CA2');
    if (h.status == 303 && hostileRedirect(h.location)) {
      c.hold(
        id: 'CA2-WR-303-$origin',
        lens: 'CA2',
        severity: 'P1',
        title: 'web_return 303 para host hostil',
        actor: 'anon',
        pre: origin,
        repro: 'GET create-connect-account?web_return_origin=',
        expected: 'HTML wallet / sem 303 hostil',
        obtained: {'status': h.status, 'loc': h.location},
      );
    }
  }

  // Tip unpaid B2 + web_return in body
  final balS = await c.walletBal(s1);
  final tipBadSeller = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyerJwt,
    body: {
      'live_id': airPub,
      'seller_id': s2,
      'amount_eur': 2,
    },
  );
  c.note('ca3.tip.wrongseller', 'tip seller ≠ owner', tipBadSeller, lens: 'CA3');
  if (tipBadSeller.ok) {
    c.hold(
      id: 'CA3-TIP-WRONG-SELLER',
      lens: 'CA3',
      severity: 'P1',
      title: 'tip checkout com seller_id ≠ dono da live',
      actor: 'B1',
      pre: 'live S1 seller_id S2',
      repro: 'POST create-live-tip-checkout',
      expected: '400',
      obtained: tipBadSeller.brief,
    );
  } else {
    c.block('ca3.tip.wrongseller', 'CA3', 'seller mismatch recusado', tipBadSeller);
  }

  final tipUnpub = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyerJwt,
    body: {
      'live_id': airUnpub,
      'seller_id': s2,
      'amount_eur': 2,
      'web_return_origin': 'https://127.0.0.1.nip.io',
    },
  );
  c.note('ca3.tip.unpub', 'tip em live unpublished', tipUnpub, lens: 'CA3');
  if (tipUnpub.ok) {
    c.hold(
      id: 'CA3-TIP-UNPUB-AIR',
      lens: 'CA3',
      severity: 'P2',
      title: 'checkout de gorjeta em directo unpublished',
      actor: 'B1',
      pre: 'S2 hub_published=false broadcasting',
      repro: 'POST create-live-tip-checkout live unpublished',
      expected: 'recusar se loja desligada não é pública',
      obtained: tipUnpub.brief,
    );
  } else {
    c.block('ca3.tip.unpub', 'CA3', 'tip unpublished recusado ou live gate', tipUnpub);
  }

  final tipOk = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyerJwt,
    body: {
      'live_id': airPub,
      'seller_id': s1,
      'amount_eur': 2,
      'message': '$prefix tip',
      'web_return_origin': 'https://[::ffff:127.0.0.1]',
    },
  );
  c.note('ca3.tip.create', 'tip unpaid session', tipOk, lens: 'CA3');
  final cs = tipOk.map?['checkoutSessionId']?.toString();
  final tipId = tipOk.map?['tipId']?.toString();
  if (tipId != null) c.createdTipIds.add(tipId);

  if (cs != null && cs.isNotEmpty) {
    final settleB2 = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      qs: 'checkout_return=success&session_id=${Uri.encodeQueryComponent(cs)}',
      jwt: c.buyer2Jwt,
    );
    final settleAnon = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      qs: 'checkout_return=success&session_id=${Uri.encodeQueryComponent(cs)}',
    );
    c.note('ca3.settle.b2', 'GET settle unpaid B2', settleB2, lens: 'CA3');
    c.note('ca3.settle.anon', 'GET settle unpaid anon', settleAnon, lens: 'CA3');
    if (settleB2.status == 303 && hostileRedirect(settleB2.location)) {
      c.hold(
        id: 'CA3-TIP-SETTLE-REDIR',
        lens: 'CA3',
        severity: 'P1',
        title: 'settle unpaid 303 hostil',
        actor: 'B2',
        pre: cs,
        repro: 'GET create-live-tip-checkout session unpaid',
        expected: 'texto unpaid / HTML',
        obtained: settleB2.brief,
      );
    }
  } else {
    c.skip('ca3.settle', 'CA3', 'sem session', tipOk);
  }

  if (tipId != null) {
    final rpcB2 = await c.rpc(
      'batata_settle_live_tip_from_stripe',
      {
        'p_tip_id': tipId,
        'p_stripe_session_id': cs ?? 'cs_test_forged',
        'p_paid_amount_cents': 200,
      },
      jwt: c.buyer2Jwt,
    );
    c.note('ca3.rpc.b2', 'RPC settle B2', rpcB2, lens: 'CA3');
    if (rpcB2.ok && rpcB2.body.contains('true')) {
      c.hold(
        id: 'CA3-RPC-SETTLE-JWT',
        lens: 'CA3',
        severity: 'P0',
        title: 'JWT settle tip unpaid via RPC',
        actor: 'B2',
        pre: tipId,
        repro: 'POST batata_settle_live_tip_from_stripe',
        expected: '403',
        obtained: rpcB2.brief,
      );
    } else {
      c.block('ca3.rpc.b2', 'CA3', 'RPC settle JWT recusado', rpcB2);
    }
    final row = await c.rest(
      'GET',
      'live_tips?id=eq.$tipId&select=id,status,amount,buyer_id,seller_id',
      service: true,
    );
    final balAfter = await c.walletBal(s1);
    c.note('ca3.tip.row', 'tip após unpaid settle', {
      'row': row.brief,
      'wallet_before': balS,
      'wallet_after': balAfter,
    }, lens: 'CA3');
    final st = '${row.map?['status'] ?? ''}';
    if (st.toLowerCase() == 'completed' || balAfter > balS) {
      c.hold(
        id: 'CA3-TIP-UNPAID-CREDIT',
        lens: 'CA3',
        severity: 'P0',
        title: 'gorjeta creditada sem pagamento Stripe',
        actor: 'B2',
        pre: 'session unpaid',
        repro: 'GET settle + RPC',
        expected: 'pending Δwallet=0',
        obtained: {'status': st, 'before': balS, 'after': balAfter},
      );
    } else {
      c.block('ca3.unpaid.credit', 'CA3', 'unpaid não credita', {
        'status': st,
        'delta': balAfter - balS,
      });
    }
  }

  // complete-mux cruzado
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
  c.note('ca4.cm.b2', 'complete-mux B2 vs S1', cmB2, lens: 'CA4');
  c.note('ca4.cm.anon', 'complete-mux anon', cmAnon, lens: 'CA4');
  c.note('ca4.cm.s2', 'complete-mux S2 vs S1', cmS2, lens: 'CA4');
  if (cmB2.ok || cmS2.ok || cmAnon.ok) {
    c.hold(
      id: 'CA4-COMPLETE-MUX-CROSS',
      lens: 'CA4',
      severity: 'P0',
      title: 'complete-mux cruzado sucedeu',
      actor: cmB2.ok ? 'B2' : (cmS2.ok ? 'S2' : 'anon'),
      pre: airPub,
      repro: 'POST complete-mux-live live_id S1',
      expected: '403/401',
      obtained: {'b2': cmB2.brief, 's2': cmS2.brief, 'anon': cmAnon.brief},
    );
  } else {
    c.block('ca4.cm.cross', 'CA4', 'complete-mux cruzado recusado', cmB2);
  }

  // LiveKit cruzado + stream_key inject
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
  c.note('ca4.lk.b2', 'livekit token B2', lkB2, lens: 'CA4');
  c.note('ca4.eg.b2', 'egress B2', egB2, lens: 'CA4');
  if (lkB2.ok) {
    c.hold(
      id: 'CA4-LK-TOKEN-CROSS',
      lens: 'CA4',
      severity: 'P1',
      title: 'B2 obtém token LiveKit de live S1',
      actor: 'B2',
      pre: airPub,
      repro: 'POST livekit-mux-publish step=token',
      expected: '403',
      obtained: lkB2.brief,
    );
  } else {
    c.block('ca4.lk.b2', 'CA4', 'livekit cruzado recusado', lkB2);
  }

  final buyerMux = await c.edge(
    'create-mux-live',
    jwt: c.buyerJwt,
    body: {'title': '$prefix buyer mux'},
  );
  c.note('ca4.create.buyer', 'create-mux buyer', buyerMux, lens: 'CA4');
  if (buyerMux.ok) {
    c.hold(
      id: 'CA4-CREATE-MUX-BUYER',
      lens: 'CA4',
      severity: 'P1',
      title: 'comprador cria stream Mux',
      actor: 'B1',
      pre: 'user_type comprador',
      repro: 'POST create-mux-live',
      expected: '403',
      obtained: buyerMux.brief,
    );
  } else {
    c.block('ca4.create.buyer', 'CA4', 'buyer não cria Mux', buyerMux);
  }

  // PATCH mux_live_id as B1 / S2 on S1 live
  final patchB1 = await c.rest(
    'PATCH',
    'lives?id=eq.$airPub',
    jwt: c.buyerJwt,
    body: {'mux_live_id': 'stolen_mux', 'mux_playback_id': 'stolen_pb'},
  );
  final patchS2 = await c.rest(
    'PATCH',
    'lives?id=eq.$airPub',
    jwt: c.seller2Jwt,
    body: {'mux_live_id': 'stolen_mux'},
  );
  final patchOwn = await c.rest(
    'PATCH',
    'lives?id=eq.$airUnpub',
    jwt: c.seller2Jwt,
    body: {'mux_live_id': 'injected_by_owner', 'title': '$prefix patched'},
  );
  c.note('ca4.patch.b1', 'PATCH live S1 as B1', patchB1, lens: 'CA4');
  c.note('ca4.patch.s2', 'PATCH live S1 as S2', patchS2, lens: 'CA4');
  c.note('ca4.patch.own', 'PATCH own unpublished as S2', patchOwn, lens: 'CA4');
  if (patchB1.ok && (patchB1.list.isNotEmpty || patchB1.body.contains('stolen'))) {
    c.hold(
      id: 'CA4-PATCH-LIVE-CROSS',
      lens: 'CA4',
      severity: 'P1',
      title: 'B1 altera mux_live_id de live S1',
      actor: 'B1',
      pre: airPub,
      repro: 'PATCH lives mux_live_id',
      expected: '0 rows / 403',
      obtained: patchB1.brief,
    );
  } else {
    c.block('ca4.patch.b1', 'CA4', 'PATCH cruzado recusado', patchB1);
  }

  final cleanup = await c.edge(
    'livekit-egress-cleanup',
    body: {},
    extra: {'x-cleanup-secret': 'wrong', 'Origin': 'https://evil.example'},
  );
  c.note('ca4.cleanup', 'cleanup secret errado', cleanup, lens: 'CA4');
  if (cleanup.ok) {
    c.hold(
      id: 'CA4-CLEANUP-UNAUTH',
      lens: 'CA4',
      severity: 'P1',
      title: 'egress-cleanup sem segredo',
      actor: 'anon',
      pre: 'x-cleanup-secret=wrong',
      repro: 'POST livekit-egress-cleanup',
      expected: '401',
      obtained: cleanup.brief,
    );
  } else {
    c.block('ca4.cleanup', 'CA4', 'cleanup recusado', cleanup);
  }

  await dumpJson('${outDir()}/pass2.json', {
    'lenses': c.lensesHit.toList()..sort(),
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'skipped': c.skipped,
  });
  stdout.writeln('WROTE pass2.json findings=${c.findings.length}');
}
