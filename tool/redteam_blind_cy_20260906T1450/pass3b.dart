/// CY pass3b — encerrar Mux live + C1 buyer + C2 CORS + C3 resolve.
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
  const muxLive = '39a8c246-4dc8-499d-870a-840c714d759f';

  await c.restoreSeller1Published();
  await c.setHub(s2, false);

  for (final id in [muxLive, airPub, airUnpub]) {
    await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
  }
  final muxRow = await c.rest(
    'GET',
    'lives?id=eq.$muxLive&select=id,seller_id,vendedor_id,status,is_active,title',
    service: true,
  );
  c.note('mux.end', 'mux live ended', muxRow, lens: 'CY4');

  final b2p = await c.profile(c.buyer2Id!);
  final c1buyer = await c.edge(
    'create-mux-live',
    jwt: c.buyerJwt,
    body: {
      'title': '$prefix hijack mux',
      'seller_id': s1,
      'mux_live_id': 'stolen',
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
  final owner = '${muxRow.map?['seller_id'] ?? ''}';
  final hijack = owner == s1;
  final buyerOk = c1buyer.ok || c1b2.ok;
  c.probe(
    id: 'C1',
    poco: 'CY-C',
    payload: 'create-mux-live B1+B2(comprador); S2 body seller_id=S1 (pass3 200 owner=S2)',
    http: {
      'buyer': c1buyer.brief,
      'b2': c1b2.brief,
      'b2_type': b2p?['user_type'],
      's2_live': muxRow.brief,
      'owner': owner,
    },
    bd: {'live': muxLive, 'owner': owner, 'status': muxRow.map?['status']},
    result: buyerOk || hijack ? 'FAIL' : 'HOLD',
    lens: 'CY4',
    countFinding: buyerOk || hijack,
  );
  if (buyerOk) {
    c.hold(
      id: 'CY-C1-CREATE-MUX-BUYER',
      lens: 'CY4',
      severity: 'P1',
      title: 'comprador cria stream Mux',
      actor: c1buyer.ok ? 'B1' : 'B2',
      pre: 'user_type comprador',
      repro: 'POST create-mux-live',
      expected: '403',
      obtained: {'b1': c1buyer.brief, 'b2': c1b2.brief},
    );
  }

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
      expected: 'ACAO=https://fleaber.pt',
      obtained: corsHits,
    );
  }

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
      expected: '404 live_not_public',
      obtained: {'anon': rAnon.brief, 'b1': rB1.brief, 'own': rOwn.brief},
    );
  }

  final s1final = await c.profile(s1);
  await dumpJson('${outDir()}/pass3b.json', {
    'probes': c.probes,
    'findings': c.findings,
    'notes': c.notes,
    's1_hub_final': s1final?['hub_published'],
    'mux_row': muxRow.map,
  });
  stdout.writeln(
    'PASS3B done probes=${c.probes.length} findings=${c.findings.length} s1=${s1final?['hub_published']}',
  );
}
