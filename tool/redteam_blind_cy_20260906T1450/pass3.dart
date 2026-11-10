/// RED TEAM CEGO CY pass3 — CY-C Edge / Mux (≥3).
import 'dart:convert';
import 'dart:io';
import '_rtcy.dart';

Future<void> main() async {
  final c = Rtcy.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final ids = jsonDecode(await File('${outDir()}/pass1_ids.json').readAsString())
      as Map<String, dynamic>;
  final s1 = ids['s1'] as String;
  final s2 = ids['s2'] as String;
  final airPub = ids['airPub'] as String;
  final airUnpub = ids['airUnpub'] as String;

  await c.restoreSeller1Published();
  await c.setHub(s2, false);
  await c.rest('PATCH', 'profiles?id=eq.${c.buyer2Id}', service: true, body: {
    'user_type': 'comprador',
    'hub_published': false,
  }, prefer: 'return=minimal');
  final b2p = await c.profile(c.buyer2Id!);
  c.note('c.b2.type', 'B2 user_type', b2p?['user_type'], lens: 'CY4');

  // ----- C1 create-mux body hostil (buyer / ≠owner) -----
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
  c.note('c1.s2', 'create-mux S2 body seller=S1', c1s2, lens: 'CY4');
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
        'lives?id=eq.$createdLive&select=id,seller_id,vendedor_id,title,mux_live_id,status,is_active',
        service: true,
      );
      createdOwner = '${row.map?['seller_id'] ?? row.map?['vendedor_id'] ?? ''}';
      c.note('c1.s2.live', 'live created by hostile body', row, lens: 'CY4');
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
  }
  final buyerOk = c1buyer.ok || c1b2.ok;
  final hijackOwner =
      createdOwner != null && createdOwner.isNotEmpty && createdOwner == s1;
  c.probe(
    id: 'C1',
    poco: 'CY-C',
    payload: 'create-mux-live B1+B2(comprador)+S2 body seller_id=S1',
    http: {
      'buyer': c1buyer.brief,
      'b2': c1b2.brief,
      'b2_type': b2p?['user_type'],
      's2': c1s2.brief,
      'createdOwner': createdOwner,
    },
    bd: {'live': createdLive, 'owner': createdOwner},
    result: buyerOk || hijackOwner ? 'FAIL' : 'HOLD',
    lens: 'CY4',
    countFinding: buyerOk || hijackOwner,
  );
  if (buyerOk) {
    c.hold(
      id: 'CY-C1-CREATE-MUX-BUYER',
      lens: 'CY4',
      severity: 'P1',
      title: 'comprador cria stream Mux',
      actor: c1buyer.ok ? 'B1' : 'B2',
      pre: 'user_type comprador; body seller_id=S1',
      repro: 'POST create-mux-live',
      expected: '403 Apenas contas de vendedor',
      obtained: {'b1': c1buyer.brief, 'b2': c1b2.brief, 'b2_type': b2p?['user_type']},
    );
  }
  if (hijackOwner) {
    c.hold(
      id: 'CY-C1-CREATE-MUX-OWNER-INJECT',
      lens: 'CY4',
      severity: 'P0',
      title: 'S2 create-mux inseriu live com seller_id S1',
      actor: 'S2',
      pre: 'body.seller_id=S1',
      repro: 'POST create-mux-live',
      expected: 'live.seller_id = JWT S2',
      obtained: {'live': createdLive, 'owner': createdOwner, 'http': c1s2.brief},
    );
  }

  // ----- C2 CORS Origin null / evil -----
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
    id: 'C2',
    poco: 'CY-C',
    payload: 'OPTIONS/POST Origin null / evil / chrome-ext / *.fleaber / file',
    http: corsHits,
    result: reflected.isEmpty ? 'HOLD' : 'FAIL',
    lens: 'CY5',
    countFinding: reflected.isNotEmpty,
  );
  if (reflected.isNotEmpty) {
    c.hold(
      id: 'CY-C2-CORS-REFLECT',
      lens: 'CY5',
      severity: 'P2',
      title: 'CORS reflecte Origin hostil $reflected',
      actor: 'browser',
      pre: 'Origin null/evil/ext',
      repro: 'OPTIONS create-mux-live + POST resolve-mux-playback',
      expected: 'ACAO=https://fleaber.pt (não reflectir hostil)',
      obtained: corsHits,
    );
  }

  // ----- C3 resolve-mux unpublished dono vs buyer -----
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
    id: 'C3',
    poco: 'CY-C',
    payload: 'resolve-mux-playback unpublished anon/B1/dono S2',
    http: {'anon': rAnon.brief, 'b1': rB1.brief, 'owner': rOwn.brief},
    result: buyerSees ? 'FAIL' : 'HOLD',
    lens: 'CY4',
    countFinding: buyerSees,
  );
  if (buyerSees) {
    c.hold(
      id: 'CY-C3-RESOLVE-MUX-UNPUB',
      lens: 'CY4',
      severity: 'P1',
      title: 'resolve-mux unpublished devolve playback a não-dono',
      actor: muxIds(rAnon) ? 'anon' : 'B1',
      pre: airUnpub,
      repro: 'POST resolve-mux-playback',
      expected: '404 live_not_public (dono 200 studio ok)',
      obtained: {'anon': rAnon.brief, 'b1': rB1.brief, 'own': rOwn.brief},
    );
  }

  // Encerrar lives de fixture (não deixar directo a correr).
  for (final id in [airPub, airUnpub, createdLive]) {
    if (id == null || id.isEmpty) continue;
    await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
  }
  await c.setHub(s2, false);
  await c.restoreSeller1Published();
  final s1final = await c.profile(s1);
  c.note('end.s1', 'S1 hub restored', s1final?['hub_published'], lens: 'CY1');

  await dumpJson('${outDir()}/pass3.json', {
    'probes': c.probes,
    'findings': c.findings,
    'notes': c.notes,
    'skipped': c.skipped,
    'lenses': c.lensesHit.toList()..sort(),
    's1_hub_final': s1final?['hub_published'],
  });
  stdout.writeln('PASS3 done probes=${c.probes.length} findings=${c.findings.length}');
}
