/// Pass 4 — último ciclo: pairing table RLS, claim 2-arg, sem nova classe P0/P1 esperada.
import 'dart:io';
import '_rtf.dart';

void main() async {
  final env = loadEnv();
  final c = Rtf.fromEnv(env);
  await c.loginActors(env);
  await c.ensureBuyer2();

  final findings = <Map<String, dynamic>>[];
  final map = <String, dynamic>{};
  var n = 300;
  String nid(String s) => 'RTF0735-${s.toUpperCase()}-${++n}';
  void add(Map<String, dynamic> f) => findings.add(f);

  Future<HttpHit> note(String label, Future<HttpHit> fut, {String idn = ''}) async {
    final h = await fut;
    map[label] = {'http': h.status, 'snip': h.snippet, 'identity': idn, 'n': h.list.length};
    stderr.writeln('${h.status} $label ${h.snippet}');
    return h;
  }

  const endedLive = 'a61fd280-edd1-4efa-b203-c79bffeb6b1b';

  final created = await note(
    'F5-create',
    c.rpc('batata_ps_create_pairing', {'p_live_id': endedLive}, jwt: c.sellerJwt),
    idn: 'seller',
  );
  String? code;
  if (created.json is Map) code = (created.json as Map)['code']?.toString();

  // F1/F2: JWT lê ps_pairing_sessions (token em claro)?
  final sessB2 = await note(
    'F1-pairing-sessions-b2',
    c.rest(
      'GET',
      'ps_pairing_sessions?live_id=eq.$endedLive&select=id,code,device_token_plain,expires_at,claimed_at,seller_id',
      jwt: c.buyer2Jwt,
    ),
    idn: 'buyer2',
  );
  final sessBuyer = await note(
    'F1-pairing-sessions-buyer',
    c.rest(
      'GET',
      'ps_pairing_sessions?select=id,code,device_token_plain,expires_at&limit=5',
      jwt: c.buyerJwt,
    ),
    idn: 'buyer',
  );
  final sessAnon = await note(
    'F1-pairing-sessions-anon',
    c.rest('GET', 'ps_pairing_sessions?select=id,code,device_token_plain&limit=3'),
    idn: 'anon',
  );
  final sessSeller = await note(
    'F1-pairing-sessions-seller',
    c.rest(
      'GET',
      'ps_pairing_sessions?live_id=eq.$endedLive&select=id,code,device_token_plain,expires_at,claimed_at',
      jwt: c.sellerJwt,
    ),
    idn: 'seller',
  );

  void leakSessions(String who, HttpHit h) {
    if (!h.ok || h.list.isEmpty) return;
    final hasToken = h.body.contains('device_token_plain') &&
        RegExp(r'"device_token_plain"\s*:\s*"[a-f0-9]{16,}').hasMatch(h.body);
    final hasCode = h.body.contains('"code"');
    if (hasToken || hasCode) {
      add(finding(
        id: nid('f1-pair-table-$who'),
        lens: 'F1',
        severity: hasToken ? 'P1' : 'P2',
        title: hasToken
            ? '$who lê device_token_plain em ps_pairing_sessions'
            : '$who lê codes de ps_pairing_sessions',
        pre: 'tabela base vs RPC claim',
        repro: 'GET ps_pairing_sessions as $who',
        proven: true,
        evidence: {'snip': h.snippet},
      ));
    }
  }

  leakSessions('buyer2', sessB2);
  leakSessions('buyer', sessBuyer);
  leakSessions('anon', sessAnon);
  // seller own codes: expected, not a finding unless token is needless

  if (code != null) {
    final c2 = await note(
      'F5-claim-2arg-b2',
      c.rpc('batata_ps_claim_pairing', {
        'p_code': code,
        'p_device_id': 'rtf-2arg',
      }, jwt: c.buyer2Jwt),
      idn: 'buyer2',
    );
    if (c2.ok && c2.body.contains('"ok":true')) {
      add(finding(
        id: nid('f5-claim-2arg'),
        lens: 'F5',
        severity: 'P1',
        title: 'JWT claim pairing (2 args) em live ended devolveu ok',
        pre: 'code $code live ended',
        repro: 'rpc batata_ps_claim_pairing p_code p_device_id',
        proven: true,
        evidence: {'snip': c2.snippet},
      ));
    }
    final cAnon = await note(
      'F5-claim-2arg-anon',
      c.rpc('batata_ps_claim_pairing', {
        'p_code': code,
        'p_device_id': 'rtf-anon2',
      }),
      idn: 'anon',
    );
    if (cAnon.ok && cAnon.body.contains('"ok":true')) {
      add(finding(
        id: nid('f5-claim-anon'),
        lens: 'F5',
        severity: 'P1',
        title: 'Anon claim pairing 2-arg',
        pre: 'code $code',
        repro: 'rpc claim as anon',
        proven: true,
        evidence: {'snip': cAnon.snippet},
      ));
    }
  }

  // seller_device_tokens
  await note(
    'F1-device-tokens-b2',
    c.rest('GET', 'seller_device_tokens?select=id,seller_id,device_id,token_hash&limit=5', jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );
  await note(
    'F1-ps-heartbeats-b2',
    c.rest('GET', 'ps_reader_heartbeats?select=*&limit=5', jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );

  // F4: Edge refund vs PATCH stripe_refund_id
  await note(
    'F4-patch-refund-id',
    c.rest('PATCH', 'orders?id=eq.859c6ce4-7fc6-4b8e-9f3e-189cb2b590c2', jwt: c.buyerJwt, body: {
      'stripe_refund_id': 're_rtf_fake',
    }),
    idn: 'buyer',
  );

  await c.rest('PATCH', 'lives?id=eq.$endedLive', service: true, body: {
    'is_active': false,
    'status': 'ended',
  }, prefer: 'return=minimal');

  final proven = findings.where((f) => f['proven'] == true).toList();
  final dirPath = Directory.current.path.contains('redteam_blind_f_')
      ? Directory.current.path
      : '${Directory.current.path}/tool/redteam_blind_f_$stamp';
  await dumpJson('$dirPath/out/pass4.json', {
    'auditor': 'REDTEAM_BLIND_F_POLITICAS_FINAS_v1',
    'pass': 4,
    'map': map,
    'findings': findings,
    'proven_n': proven.length,
  });
  stderr.writeln('PASS4 proven=${proven.length}');
}
