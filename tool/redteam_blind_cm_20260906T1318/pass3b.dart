/// Inspect B2 user_type, end Mux leftovers, retry C2–C4, retry B1 with read-back.
import 'dart:convert';
import 'dart:io';
import '_rtcm.dart';

Future<void> main() async {
  final c = Rtcm.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final ids = jsonDecode(await File('${outDir()}/pass1_ids.json').readAsString())
      as Map<String, dynamic>;
  final s1 = ids['s1'] as String;
  final s2 = ids['s2'] as String;
  final airPub = ids['airPub'] as String;
  final airUnpub = ids['airUnpub'] as String;

  final b2p = await c.profile(c.buyer2Id!);
  final s2p = await c.profile(s2);
  c.note('b2.profile', 'B2 type', b2p, lens: 'CM4');
  c.note('s2.profile', 'S2 type', s2p, lens: 'CM4');

  // End any RTCM lives still active (Mux creates).
  final leftover = await c.rest(
    'GET',
    'lives?or=(title.ilike.*RTCM-20260906T1318*,title.ilike.*rtcm*)&select=id,title,status,is_active,seller_id,vendedor_id,mux_live_id&order=created_at.desc&limit=20',
    service: true,
  );
  c.note('leftover.lives', 'RTCM lives', leftover, lens: 'CM4');
  for (final row in leftover.list) {
    if (row is! Map) continue;
    final id = '${row['id']}';
    final st = '${row['status']}'.toLowerCase();
    final active = row['is_active'] == true;
    if (st != 'ended' || active) {
      await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
        'is_active': false,
        'status': 'ended',
      }, prefer: 'return=minimal');
      stdout.writeln('ended leftover $id ${row['title']}');
    }
  }

  // Keep airPub/airUnpub live for C4 if they were ended above — restore fixtures.
  await c.rest('PATCH', 'lives?id=eq.$airPub', service: true, body: {
    'status': 'live',
    'is_active': true,
  }, prefer: 'return=minimal');
  await c.rest('PATCH', 'lives?id=eq.$airUnpub', service: true, body: {
    'status': 'live',
    'is_active': true,
  }, prefer: 'return=minimal');

  // ----- C2 retry -----
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
  final lkB2 = await c.edge(
    'livekit-mux-publish',
    jwt: c.buyer2Jwt,
    body: {'step': 'token', 'live_id': airPub},
  );
  final c2fail = cmB2.ok || cmAnon.ok || cmS2.ok || lkB2.ok;
  c.probe(
    id: 'C2',
    poco: 'CM-C',
    payload: 'complete-mux B2/anon/S2 vs live S1 + livekit token B2',
    http: {
      'cmB2': cmB2.brief,
      'cmAnon': cmAnon.brief,
      'cmS2': cmS2.brief,
      'lkB2': lkB2.brief,
      'b2_user_type': b2p?['user_type'],
    },
    result: c2fail ? 'FAIL' : 'HOLD',
    lens: 'CM4',
  );
  if (c2fail) {
    c.hold(
      id: 'CM-C2-COMPLETE-MUX-CROSS',
      lens: 'CM4',
      severity: 'P0',
      title: 'complete-mux / livekit cruzado sucedeu',
      actor: 'cross',
      pre: airPub,
      repro: 'POST complete-mux-live',
      expected: '403/401',
      obtained: {
        'cmB2': cmB2.brief,
        'cmS2': cmS2.brief,
        'anon': cmAnon.brief,
        'lk': lkB2.brief,
      },
    );
  }

  // ----- C3 -----
  final origins = <String, String>{
    'null': 'null',
    'evil': 'https://evil.example',
    'ext': 'chrome-extension://abcdefghijklmnopqrstuvwxyz1234',
    'sub': 'https://evil.fleaber.pt',
  };
  final corsHits = <String, String>{};
  final reflected = <String>[];
  for (final e in origins.entries) {
    final opt = await c.edge(
      'resolve-mux-playback',
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
    corsHits['opt.${e.key}'] = opt.brief;
    corsHits['post.${e.key}'] = post.brief;
    if (opt.acao == e.value || post.acao == e.value) {
      reflected.add(e.key);
    }
  }
  c.probe(
    id: 'C3',
    poco: 'CM-C',
    payload: 'OPTIONS/POST resolve-mux Origin null/evil/ext/sub',
    http: corsHits,
    result: reflected.isEmpty ? 'HOLD' : 'FAIL',
    lens: 'CM2',
  );
  if (reflected.isNotEmpty) {
    c.hold(
      id: 'CM-C3-CORS-REFLECT',
      lens: 'CM2',
      severity: 'P2',
      title: 'CORS reflecte Origin hostil $reflected',
      actor: 'browser',
      pre: 'Origin null/evil',
      repro: 'OPTIONS/POST resolve-mux-playback',
      expected: 'ACAO=https://fleaber.pt',
      obtained: corsHits,
    );
  }

  // ----- C4 -----
  final rAnon = await c.edge(
    'resolve-mux-playback',
    body: {'live_id': airUnpub},
  );
  final rB1 = await c.edge(
    'resolve-mux-playback',
    jwt: c.buyerJwt,
    body: {'live_id': airUnpub},
  );
  final rOwn = await c.edge(
    'resolve-mux-playback',
    jwt: c.seller2Jwt,
    body: {'live_id': airUnpub},
  );
  bool muxIds(HttpHit h) {
    final t = h.body.toLowerCase();
    return h.ok &&
        (t.contains('playback') && !t.contains('live_not_public')) &&
        (t.contains('m3u8') ||
            col(h.map, 'playback_id') != null ||
            col(h.map, 'mux_playback_id') != null);
  }

  final buyerSees = muxIds(rB1) || muxIds(rAnon);
  c.probe(
    id: 'C4',
    poco: 'CM-C',
    payload: 'resolve-mux unpublished anon/B1/dono S2',
    http: {'anon': rAnon.brief, 'b1': rB1.brief, 'owner': rOwn.brief},
    result: buyerSees ? 'FAIL' : 'HOLD',
    lens: 'CM5',
  );
  if (buyerSees) {
    c.hold(
      id: 'CM-C4-RESOLVE-MUX-UNPUB',
      lens: 'CM5',
      severity: 'P1',
      title: 'resolve-mux unpublished devolve playback a não-dono',
      actor: muxIds(rAnon) ? 'anon' : 'B1',
      pre: airUnpub,
      repro: 'POST resolve-mux-playback',
      expected: '404 live_not_public',
      obtained: {'anon': rAnon.brief, 'b1': rB1.brief, 'own': rOwn.brief},
    );
  }

  // ----- B1 retry: publish S2, read-back, tip, unpublish, GET -----
  final pub = await c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
    'hub_published': true,
    'is_live': true,
    'user_type': 'vendedor',
  });
  final s2now = await c.profile(s2);
  await c.rest('PATCH', 'lives?id=eq.$airUnpub', service: true, body: {
    'status': 'live',
    'is_active': true,
    'seller_id': s2,
    'vendedor_id': s2,
  }, prefer: 'return=minimal');
  final b1create = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyerJwt,
    body: {
      'live_id': airUnpub,
      'seller_id': s2,
      'amount_eur': 2,
    },
  );
  c.note('b1.retry.profile', 'S2 after publish', s2now, lens: 'CM3');
  c.note('b1.retry.create', 'tip after verified publish', b1create, lens: 'CM3');
  String? tipId = b1create.map?['tipId']?.toString() ??
      b1create.map?['tip_id']?.toString();
  String? sessionId = b1create.map?['checkoutSessionId']?.toString() ??
      b1create.map?['sessionId']?.toString();

  await c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
    'hub_published': false,
  }, prefer: 'return=minimal');

  HttpHit? getAfter;
  String st = '';
  if (sessionId != null && sessionId.isNotEmpty) {
    getAfter = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      jwt: c.buyerJwt,
      qs: 'checkout_return=success&session_id=$sessionId',
    );
    if (tipId != null) {
      final row = await c.rest(
        'GET',
        'live_tips?id=eq.$tipId&select=id,status,amount',
        service: true,
      );
      st = '${row.map?['status'] ?? ''}';
    }
  }

  // Fallback B1 on S1: session already from pass2 B4 — create new, then brief unpublish S1, GET, restore.
  HttpHit? b1s1create;
  HttpHit? b1s1get;
  String stS1 = '';
  var usedS1 = false;
  if (!b1create.ok) {
    usedS1 = true;
    b1s1create = await c.edge(
      'create-live-tip-checkout',
      jwt: c.buyer2Jwt,
      body: {
        'live_id': airPub,
        'seller_id': s1,
        'amount_eur': 2,
      },
    );
    final sid = b1s1create.map?['checkoutSessionId']?.toString() ??
        b1s1create.map?['sessionId']?.toString();
    final tid = b1s1create.map?['tipId']?.toString() ??
        b1s1create.map?['tip_id']?.toString();
    await c.rest('PATCH', 'profiles?id=eq.$s1', service: true, body: {
      'hub_published': false,
    }, prefer: 'return=minimal');
    if (sid != null && sid.isNotEmpty) {
      b1s1get = await c.edge(
        'create-live-tip-checkout',
        method: 'GET',
        jwt: c.buyer2Jwt,
        qs: 'checkout_return=success&session_id=$sid',
      );
    }
    if (tid != null) {
      final row = await c.rest(
        'GET',
        'live_tips?id=eq.$tid&select=id,status',
        service: true,
      );
      stS1 = '${row.map?['status'] ?? ''}';
    }
    await c.rest('PATCH', 'profiles?id=eq.$s1', service: true, body: {
      'hub_published': true,
    }, prefer: 'return=minimal');
  }

  final credited = st == 'paid' || st == 'settled' || stS1 == 'paid' || stS1 == 'settled';
  final created = b1create.ok || (b1s1create?.ok ?? false);
  c.probe(
    id: 'B1',
    poco: 'CM-B',
    payload: usedS1
        ? 'FALLBACK S1: Session published → unpublish S1 → GET unpaid → restore S1'
        : 'S2 verified publish → Session → unpublish → GET unpaid',
    http: {
      's2hubBeforeTip': s2now?['hub_published'],
      's2create': b1create.brief,
      's2get': getAfter?.brief,
      's1create': b1s1create?.brief,
      's1get': b1s1get?.brief,
      'patchPub': pub.brief,
    },
    bd: {'st': st, 'stS1': stS1, 'b2type': b2p?['user_type']},
    result: !created ? 'SKIP' : (credited ? 'FAIL' : 'HOLD'),
    lens: 'CM3',
  );
  if (credited) {
    c.hold(
      id: 'CM-B1-UNPAID-CREDIT-MIDUNPUB',
      lens: 'CM3',
      severity: 'P0',
      title: 'GET settle após unpublish creditou unpaid',
      actor: 'buyer',
      pre: 'mid-unpublish',
      repro: 'GET create-live-tip-checkout return',
      expected: 'pending',
      obtained: {'st': st, 'stS1': stS1, 'get': getAfter?.brief ?? b1s1get?.brief},
    );
  }

  // B2 retry: S1 session then END live (dedicated), GET
  final liveB2 = await c.insertLive(
    seller: s1,
    active: true,
    status: 'live',
    muxPlayback: ids['pbAir']?.toString(),
    title: '$prefix b2-end',
  );
  final b2c = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyer2Jwt,
    body: {
      'live_id': liveB2,
      'seller_id': s1,
      'amount_eur': 2,
    },
  );
  final sid2 = b2c.map?['checkoutSessionId']?.toString() ??
      b2c.map?['sessionId']?.toString();
  final tid2 = b2c.map?['tipId']?.toString() ?? b2c.map?['tip_id']?.toString();
  await c.rest('PATCH', 'lives?id=eq.$liveB2', service: true, body: {
    'status': 'ended',
    'is_active': false,
  }, prefer: 'return=minimal');
  HttpHit? b2get;
  if (sid2 != null && sid2.isNotEmpty) {
    b2get = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      jwt: c.buyer2Jwt,
      qs: 'checkout_return=success&session_id=$sid2',
    );
  }
  String st2 = '';
  if (tid2 != null) {
    final row = await c.rest(
      'GET',
      'live_tips?id=eq.$tid2&select=id,status',
      service: true,
    );
    st2 = '${row.map?['status'] ?? ''}';
  }
  c.probe(
    id: 'B2',
    poco: 'CM-B',
    payload: 'tip bind S1 live → end live → GET settle unpaid',
    http: {'create': b2c.brief, 'get': b2get?.brief},
    bd: {'status': st2, 'live': liveB2},
    result: !b2c.ok ? 'SKIP' : ((st2 == 'paid' || st2 == 'settled') ? 'FAIL' : 'HOLD'),
    lens: 'CM3',
  );

  // Extra B5 webhook forged (compensate skip)
  final wh = await c.edge(
    'stripe-webhook',
    body: {
      'type': 'checkout.session.completed',
      'data': {
        'object': {
          'id': sessionId ?? sid2 ?? 'cs_test_fake',
          'payment_status': 'paid',
          'metadata': {'purpose': 'live_tip', 'tip_id': tipId ?? tid2},
        },
      },
    },
    extra: {'stripe-signature': 't=1,v1=deadbeef'},
  );
  c.probe(
    id: 'B5',
    poco: 'CM-B',
    payload: 'stripe-webhook assinatura forjada sobre tip session',
    http: wh,
    result: wh.ok ? 'FAIL' : 'HOLD',
    lens: 'CM3',
  );
  if (wh.ok) {
    c.hold(
      id: 'CM-B5-WEBHOOK-FORGED',
      lens: 'CM3',
      severity: 'P0',
      title: 'stripe-webhook aceita assinatura forjada',
      actor: 'anon',
      pre: 'v1=deadbeef',
      repro: 'POST stripe-webhook',
      expected: '400 invalid_signature',
      obtained: wh.brief,
    );
  }

  // restore S1 published, S2 unpublished
  await c.rest('PATCH', 'profiles?id=eq.$s1', service: true, body: {
    'hub_published': true,
  }, prefer: 'return=minimal');
  await c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
    'hub_published': false,
    'is_live': false,
  }, prefer: 'return=minimal');

  await dumpJson('${outDir()}/pass3b.json', {
    'lenses': c.lensesHit.toList()..sort(),
    'probes': c.probes,
    'findings': c.findings,
    'notes': c.notes,
    'skipped': c.skipped,
    'b2profile': b2p,
    's2profileAtTip': s2now,
  });
}
