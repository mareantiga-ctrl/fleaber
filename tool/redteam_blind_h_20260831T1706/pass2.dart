/// PASS 2 — H2 device token / pairing após kick ou troca de seller.
import 'dart:io';
import '_rth.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rth.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.ensureHelperChat();
  await c.ensureHelperRes();

  final out = <String, Object?>{
    'pass': 2,
    'prefix': prefix,
  };

  // Encerrar lives Mux acidentais do pass1 (custo; não é correção de produto).
  for (final id in [
    '9d0f249f-3b10-4aa5-ab55-0a9f0df2e390',
    '1d81f075-8f7a-4c76-8aa0-4f5a1549e8fd',
  ]) {
    await c.edge('complete-mux-live', {'live_id': id}, jwt: c.helperChatJwt);
    await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
  }

  // H4 real: user_type BEFORE vs AFTER no buyer2 (não no helper default).
  final b2before = await c.rest(
    'GET',
    'profiles?id=eq.${c.buyer2Id}&select=id,user_type',
    service: true,
  );
  c.note('p2.h4.b2.before', 'buyer2 user_type', b2before.snippet, lens: 'H4');
  final b2admin = await c.rest(
    'PATCH',
    'profiles?id=eq.${c.buyer2Id}',
    jwt: c.buyer2Jwt,
    body: {'user_type': 'admin'},
  );
  final b2vend = await c.rest(
    'PATCH',
    'profiles?id=eq.${c.buyer2Id}',
    jwt: c.buyer2Jwt,
    body: {'user_type': 'vendedor'},
  );
  final b2after = await c.rest(
    'GET',
    'profiles?id=eq.${c.buyer2Id}&select=id,user_type',
    service: true,
  );
  c.note('p2.h4.b2.after', 'buyer2 user_type após PATCH JWT', {
    'before': b2before.snippet,
    'admin': b2admin.brief,
    'vend': b2vend.brief,
    'after': b2after.snippet,
  }, lens: 'H4');
  final beforeT = '${b2before.map?['user_type']}'.toLowerCase();
  final afterT = '${b2after.map?['user_type']}'.toLowerCase();
  if (beforeT != afterT &&
      (afterT.contains('admin') || afterT == 'vendedor' || afterT == 'seller')) {
    c.hold(
      id: 'RTH-H4-010',
      lens: 'H4',
      severity: 'P0',
      title: 'JWT elevou user_type (before≠after)',
      actor: 'buyer2',
      pre: 'before=$beforeT',
      repro: 'PATCH profiles user_type=admin/vendedor',
      expected: 'frozen',
      obtained: 'after=$afterT',
    );
  }

  final muxB2 = await c.edge('create-mux-live', {
    'title': '$prefix b2 mux',
  }, jwt: c.buyer2Jwt);
  c.note('p2.h5.mux.b2', 'buyer2 create-mux-live', muxB2.brief, lens: 'H5');
  if (muxB2.ok && muxB2.map?['live'] != null) {
    final lid = (muxB2.map?['live'] is Map)
        ? (muxB2.map!['live'] as Map)['id']?.toString()
        : null;
    if (lid != null) {
      await c.edge('complete-mux-live', {'live_id': lid}, jwt: c.buyer2Jwt);
      await c.rest('PATCH', 'lives?id=eq.$lid', service: true, body: {
        'is_active': false,
        'status': 'ended',
      }, prefer: 'return=minimal');
    }
    if (beforeT.contains('comprador') || beforeT.contains('buyer')) {
      c.hold(
        id: 'RTH-H5-010',
        lens: 'H5',
        severity: 'P1',
        title: 'Conta comprador criou directo Mux',
        actor: 'buyer2',
        pre: 'user_type=$beforeT',
        repro: 'POST create-mux-live JWT buyer2',
        expected: '403',
        obtained: muxB2.brief,
      );
    }
  }

  // Forçar helper a comprador (svc) e repetir Mux — prova H5 sem default vendedor.
  await c.rest(
    'PATCH',
    'profiles?id=eq.${c.helperChatId}',
    service: true,
    body: {'user_type': 'comprador'},
    prefer: 'return=minimal',
  );
  final hcType = await c.rest(
    'GET',
    'profiles?id=eq.${c.helperChatId}&select=id,user_type',
    service: true,
  );
  c.note('p2.h5.helper.type', 'helper após svc comprador', hcType.snippet,
      lens: 'H5');
  final muxHc = await c.edge('create-mux-live', {
    'title': '$prefix helper as buyer mux',
  }, jwt: c.helperChatJwt);
  c.note('p2.h5.mux.helper.buyer', 'helper comprador Mux', muxHc.brief,
      lens: 'H5');
  if (muxHc.ok && muxHc.map?['live'] != null) {
    final lid = (muxHc.map?['live'] is Map)
        ? (muxHc.map!['live'] as Map)['id']?.toString()
        : null;
    if (lid != null) {
      await c.edge('complete-mux-live', {'live_id': lid}, jwt: c.helperChatJwt);
      await c.rest('PATCH', 'lives?id=eq.$lid', service: true, body: {
        'is_active': false,
        'status': 'ended',
      }, prefer: 'return=minimal');
    }
    if ('${hcType.map?['user_type']}'.toLowerCase().contains('comprador')) {
      c.hold(
        id: 'RTH-H5-011',
        lens: 'H5',
        severity: 'P1',
        title: 'Helper com user_type=comprador (svc) ainda cria Mux',
        actor: 'helperChat',
        pre: 'svc PATCH user_type=comprador',
        repro: 'POST create-mux-live',
        expected: '403',
        obtained: {'type': hcType.snippet, 'mux': muxHc.brief},
      );
    }
  }

  c.helperResLinkId = await c.inviteHelper(
    helperUserId: c.helperResId!,
    helperJwt: c.helperResJwt!,
    permissions: resOnlyPerms,
    display: '$prefix res-only',
  );
  final row = c.helperResLinkId == null
      ? null
      : await c.helperRow(c.helperResLinkId!);
  c.note('p2.helper.res', 'res-only row', row, lens: 'H2');

  final liveA = await c.insertLive(active: true);
  final liveB = await c.insertLive(active: true, seller: c.seller2Id);
  final sku = await c.insertProduct(
    title: '$prefix h2-live-sku',
    qty: 3,
    live: true,
    listed: false,
  );
  out['liveA'] = liveA;
  out['liveB'] = liveB;
  out['sku'] = sku;

  String? itemA;
  if (liveA != null && sku != null) {
    final up = await c.rpc('batata_upsert_marketplace_live_item', {
      'p_seller_id': c.sellerId,
      'p_product_id': sku,
      'p_live_id': liveA,
    }, jwt: c.sellerJwt);
    c.note('p2.upsert', 'live item S1', up.brief, lens: 'H2');
    itemA = RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    ).firstMatch(up.body)?.group(0);
  }

  if (liveA == null) {
    out['abort'] = 'no liveA';
    await dumpJson('tool/redteam_blind_h_20260831T1706/pass2.json', out);
    return;
  }

  // Helper res cria pairing na live A
  final pairH = await c.rpc('batata_ps_create_pairing', {
    'p_live_id': liveA,
    'p_device_id_hint': 'rth1706-hres',
  }, jwt: c.helperResJwt);
  c.note('p2.pair.helper', 'helper res pairing live A', pairH.brief, lens: 'H2');
  final codeH = pairH.map?['code']?.toString();

  String? tokenHelper;
  if (codeH != null && codeH.length == 6) {
    final claim = await c.edge('ps-pairing-claim', {
      'code': codeH,
      'device_id': 'rth1706-hres',
    });
    c.note('p2.claim.helper', 'claim helper pairing', claim.brief, lens: 'H2');
    tokenHelper = claim.map?['device_token']?.toString();
  } else if (pairH.map?['ok'] == true) {
    // some RPCs nest code
    final nested = pairH.map?['pairing'];
    final alt = nested is Map ? nested['code']?.toString() : null;
    if (alt != null) {
      final claim = await c.edge('ps-pairing-claim', {
        'code': alt,
        'device_id': 'rth1706-hres',
      });
      tokenHelper = claim.map?['device_token']?.toString();
    }
  }

  // Seller pairing (owner token) — kick helper não deve revogar
  final pairS = await c.rpc('batata_ps_create_pairing', {
    'p_live_id': liveA,
    'p_device_id_hint': 'rth1706-seller',
  }, jwt: c.sellerJwt);
  c.note('p2.pair.seller', 'seller pairing live A', pairS.brief, lens: 'H2');
  final codeS = pairS.map?['code']?.toString();
  String? tokenSeller;
  if (codeS != null && codeS.length == 6) {
    final claimS = await c.edge('ps-pairing-claim', {
      'code': codeS,
      'device_id': 'rth1706-seller',
    });
    c.note('p2.claim.seller', 'claim seller pairing', claimS.brief, lens: 'H2');
    tokenSeller = claimS.map?['device_token']?.toString();
  }

  Future<HttpHit> hb(String token, String liveId, String device) {
    return c.edge(
      'ps-heartbeat',
      {
        'live_id': liveId,
        'device_id': device,
        'status': 'online',
      },
      extra: {'x-device-token': token},
    );
  }

  Future<HttpHit> ocr(String token, String liveId, String hash) {
    return c.edge(
      'ingest-ocr-reservation',
      {
        'live_id': liveId,
        'ocr_line_hash': hash,
        'detected_at': DateTime.now().toUtc().toIso8601String(),
        'ref_slug': 'rth',
        'requested_qty': 1,
        'external_display_name': '$prefix ocr',
        'device_id': 'rth1706-hres',
      },
      extra: {'x-device-token': token},
    );
  }

  if (tokenHelper != null) {
    final hbOk = await hb(tokenHelper, liveA, 'rth1706-hres');
    c.note('p2.hb.helper.before', 'heartbeat helper token live A', hbOk.brief,
        lens: 'H2');

    if (liveB != null) {
      final hbCross = await hb(tokenHelper, liveB, 'rth1706-hres');
      c.note('p2.hb.cross', 'helper token on seller2 live', hbCross.brief,
          lens: 'H2');
      if (hbCross.ok && hbCross.map?['ok'] == true) {
        c.hold(
          id: 'RTH-H2-001',
          lens: 'H2',
          severity: 'P1',
          title: 'Device token da loja A faz heartbeat na live da loja B',
          actor: 'anon+token helper S1',
          pre: 'token claimed on S1 live; live B is S2',
          repro: 'POST ps-heartbeat live_id=S2 x-device-token=S1',
          expected: 'live_not_owned',
          obtained: hbCross.brief,
        );
      }
      final ocrCross = await ocr(
        tokenHelper,
        liveB,
        'rth1706crosshashabcdefgh',
      );
      c.note('p2.ocr.cross', 'OCR token S1 na live S2', ocrCross.brief,
          lens: 'H2');
      if (ocrCross.ok &&
          ocrCross.map?['ok'] == true &&
          ocrCross.map?['reservation_id'] != null) {
        c.hold(
          id: 'RTH-H2-002',
          lens: 'H2',
          severity: 'P1',
          title: 'OCR com token da loja A criou reserva na live da loja B',
          actor: 'anon+token',
          pre: 'token S1; live S2',
          repro: 'POST ingest-ocr-reservation live_id=S2',
          expected: 'live_not_owned / invalid_token',
          obtained: ocrCross.brief,
        );
      }
    }

    if (c.helperResLinkId != null) {
      await c.kickHelper(c.helperResLinkId!);
      c.note('p2.kick', 'kicked helper res', c.helperResLinkId, lens: 'H2');

      final hbAfter = await hb(tokenHelper, liveA, 'rth1706-hres');
      c.note('p2.hb.afterkick', 'heartbeat após kick', hbAfter.brief, lens: 'H2');
      if (hbAfter.ok && hbAfter.map?['ok'] == true) {
        c.hold(
          id: 'RTH-H2-003',
          lens: 'H2',
          severity: 'P1',
          title: 'Device token do helper continua válido após kick',
          actor: 'anon+token helper',
          pre: 'helper res kicked; token created_by helper',
          repro: 'POST ps-heartbeat após PATCH seller_helpers revoked',
          expected: 'token_staff_revoked',
          obtained: hbAfter.brief,
        );
      }

      final ocrAfter = await ocr(
        tokenHelper,
        liveA,
        'rth1706kickhashabcdefgh',
      );
      c.note('p2.ocr.afterkick', 'OCR após kick', ocrAfter.brief, lens: 'H2');
      if (ocrAfter.ok &&
          (ocrAfter.map?['ok'] == true ||
              ocrAfter.map?['action'] == 'created')) {
        c.hold(
          id: 'RTH-H2-004',
          lens: 'H2',
          severity: 'P1',
          title: 'OCR após kick do helper ainda cria reserva',
          actor: 'anon+token',
          pre: 'helper kicked',
          repro: 'ingest-ocr-reservation com token pré-kick',
          expected: 'token_staff_revoked',
          obtained: ocrAfter.brief,
        );
      }
    }
  } else {
    c.note('p2.no.helper.token', 'pairing helper não emitiu token', pairH.brief,
        lens: 'H2');
  }

  if (tokenSeller != null && c.helperResLinkId != null) {
    // já kicked acima; token do seller deve continuar
    final hbS = await hb(tokenSeller, liveA, 'rth1706-seller');
    c.note('p2.hb.seller.afterkick', 'token owner após kick helper', hbS.brief,
        lens: 'H2');
  }

  // Helper kicked tenta novo pairing
  final pairAfter = await c.rpc('batata_ps_create_pairing', {
    'p_live_id': liveA,
    'p_device_id_hint': 'rth1706-after',
  }, jwt: c.helperResJwt);
  c.note('p2.pair.afterkick', 'pairing JWT após kick', pairAfter.brief,
      lens: 'H2');
  if (pairAfter.ok && pairAfter.map?['ok'] == true) {
    c.hold(
      id: 'RTH-H2-005',
      lens: 'H2',
      severity: 'P1',
      title: 'Helper kicked ainda cria pairing',
      actor: 'helperRes JWT',
      pre: 'active=false',
      repro: 'rpc batata_ps_create_pairing após kick',
      expected: 'not_allowed',
      obtained: pairAfter.brief,
    );
  }

  // Tokens JWT: helper lê seller_device_tokens da loja (ainda kicked)
  final toks = await c.rest(
    'GET',
    'seller_device_tokens?seller_id=eq.${c.sellerId}&select=id,seller_id,device_id,revoked_at,created_by&limit=8',
    jwt: c.helperResJwt,
  );
  c.note('p2.tokens.jwt', 'helper GET device tokens', toks.brief, lens: 'H2');
  if (toks.ok && toks.list.isNotEmpty) {
    c.hold(
      id: 'RTH-H2-006',
      lens: 'H2',
      severity: 'P2',
      title: 'Helper (kicked) lê seller_device_tokens da loja',
      actor: 'helperRes',
      pre: 'kicked',
      repro: 'GET seller_device_tokens',
      expected: '[]',
      obtained: {'n': toks.list.length, 'snip': toks.snippet},
    );
  }

  out['itemA'] = itemA;
  out['notes'] = c.notes;
  out['findings'] = c.findings;
  await c.endLives();
  await dumpJson('tool/redteam_blind_h_20260831T1706/pass2.json', out);
  stdout.writeln('PASS2 findings=${c.findings.length}');
}
