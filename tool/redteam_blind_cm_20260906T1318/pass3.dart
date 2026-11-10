/// RED TEAM CEGO CM pass3 — CM-C Edge Mux / CORS / create-mux (≥4).
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
  final airPub = ids['airPub'] as String;
  final airUnpub = ids['airUnpub'] as String;
  final s2 = ids['s2'] as String;

  // ----- C1 create-mux body hostil (buyer / seller≠owner) -----
  final c1buyer = await c.edge(
    'create-mux-live',
    jwt: c.buyerJwt,
    body: {
      'title': '$prefix hijack mux',
      'seller_id': s1,
      'vendedor_id': s1,
      'live_id': airPub,
      'mux_live_id': 'stolen_mux_live',
      'mux_stream_key': 'stolen_key',
      'mux_playback_id': 'stolen_pb',
    },
  );
  final c1b2 = await c.edge(
    'create-mux-live',
    jwt: c.buyer2Jwt,
    body: {
      'title': '$prefix b2 mux',
      'seller_id': s1,
    },
  );
  // S2 is vendedor: hostile body targeting S1. This MAY call Mux API.
  final c1s2 = await c.edge(
    'create-mux-live',
    jwt: c.seller2Jwt,
    body: {
      'title': '$prefix s2-for-s1',
      'seller_id': s1,
      'vendedor_id': s1,
      'live_id': airPub,
      'mux_live_id': 'inject_s1',
    },
  );
  c.note('c1.s2', 'create-mux S2 body seller=S1', c1s2, lens: 'CM4');
  String? createdLive;
  String? createdOwner;
  if (c1s2.ok) {
    createdLive = c1s2.map?['live'] is Map
        ? '${(c1s2.map!['live'] as Map)['id'] ?? ''}'
        : c1s2.map?['live_id']?.toString();
    if (createdLive != null && createdLive.isNotEmpty) {
      c.createdMuxLiveIds.add(createdLive);
      c.createdLiveIds.add(createdLive);
      final row = await c.rest(
        'GET',
        'lives?id=eq.$createdLive&select=id,seller_id,vendedor_id,title,mux_live_id,status',
        service: true,
      );
      createdOwner = '${row.map?['seller_id'] ?? row.map?['vendedor_id'] ?? ''}';
      c.note('c1.s2.live', 'live created by hostile body', row, lens: 'CM4');
    }
  }
  final buyerOk = c1buyer.ok || c1b2.ok;
  final hijackOwner = createdOwner != null &&
      createdOwner.isNotEmpty &&
      createdOwner == s1;
  c.probe(
    id: 'C1',
    poco: 'CM-C',
    payload:
        'create-mux-live buyer+S2 body seller_id=S1 + mux ids roubados',
    http: {
      'buyer': c1buyer.brief,
      'b2': c1b2.brief,
      's2': c1s2.brief,
      'createdOwner': createdOwner,
    },
    bd: {'live': createdLive, 'owner': createdOwner},
    result: buyerOk || hijackOwner ? 'FAIL' : 'HOLD',
    lens: 'CM4',
  );
  if (buyerOk) {
    c.hold(
      id: 'CM-C1-CREATE-MUX-BUYER',
      lens: 'CM4',
      severity: 'P1',
      title: 'comprador cria stream Mux',
      actor: c1buyer.ok ? 'B1' : 'B2',
      pre: 'user_type comprador; body seller_id=S1',
      repro: 'POST create-mux-live',
      expected: '403',
      obtained: {'b1': c1buyer.brief, 'b2': c1b2.brief},
    );
  }
  if (hijackOwner) {
    c.hold(
      id: 'CM-C1-CREATE-MUX-OWNER-INJECT',
      lens: 'CM4',
      severity: 'P0',
      title: 'S2 create-mux inseriu live com seller_id S1',
      actor: 'S2',
      pre: 'body.seller_id=S1',
      repro: 'POST create-mux-live',
      expected: 'live.seller_id = JWT S2 (ignorar body)',
      obtained: {'live': createdLive, 'owner': createdOwner, 'http': c1s2.brief},
    );
  }

  // End any Mux live we created (don't leave air).
  if (createdLive != null && createdLive.isNotEmpty) {
    await c.edge(
      'complete-mux-live',
      jwt: c.seller2Jwt,
      body: {'live_id': createdLive},
    );
    await c.rest('PATCH', 'lives?id=eq.$createdLive', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
  }

  // ----- C2 complete-mux cruzado -----
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
      actor: cmB2.ok
          ? 'B2'
          : (cmS2.ok ? 'S2' : (lkB2.ok ? 'B2-lk' : 'anon')),
      pre: airPub,
      repro: 'POST complete-mux-live / livekit-mux-publish',
      expected: '403/401',
      obtained: {
        'cmB2': cmB2.brief,
        'cmS2': cmS2.brief,
        'anon': cmAnon.brief,
        'lk': lkB2.brief,
      },
    );
  }

  // ----- C3 CORS Origin null / evil -----
  final origins = <String, String>{
    'null': 'null',
    'evil': 'https://evil.example',
    'ext': 'chrome-extension://abcdefghijklmnopqrstuvwxyz1234',
    'sub': 'https://evil.fleaber.pt',
    'file': 'file://',
  };
  final corsHits = <String, String>{};
  final reflected = <String>[];
  for (final e in origins.entries) {
    final opt = await c.edge(
      'create-mux-live',
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
    payload: 'OPTIONS/POST Edge Origin null / evil / chrome-ext / *.fleaber',
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
      pre: 'Origin null/evil/ext',
      repro: 'OPTIONS create-mux-live + POST resolve-mux-playback',
      expected: 'ACAO=https://fleaber.pt (não reflectir hostil)',
      obtained: corsHits,
    );
  }

  // ----- C4 resolve-mux dono vs buyer unpublished -----
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
        (t.contains('playback') ||
            t.contains('m3u8') ||
            col(h.map, 'playback_id') != null ||
            col(h.map, 'mux_playback_id') != null);
  }

  final buyerSees = muxIds(rB1) || muxIds(rAnon);
  c.probe(
    id: 'C4',
    poco: 'CM-C',
    payload: 'resolve-mux-playback unpublished anon/B1/dono S2',
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
      expected: '404 live_not_public (dono 200 ok)',
      obtained: {'anon': rAnon.brief, 'b1': rB1.brief, 'own': rOwn.brief},
    );
  }

  await dumpJson('${outDir()}/pass3.json', {
    'lenses': c.lensesHit.toList()..sort(),
    'probes': c.probes,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'skipped': c.skipped,
    'createdMuxLive': createdLive,
  });
}
