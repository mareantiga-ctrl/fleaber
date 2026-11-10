import 'dart:io';

import '_rtm.dart';

/// Pass 2 — deepen M1 handle/discovery, M6 storage prefixes, M5 mux write,
/// M7 one unpaid Session ≠ capture. No dual Session / mint / invite / pairing.
void main() async {
  final c = Rtm.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final s2 = c.seller2Id!;

  final out = <String, Object?>{'pass': 2};

  // actual handle after trigger
  final s2row = await c.rest(
    'GET',
    'profiles?id=eq.$s2&select=id,handle,full_name,hub_published,is_live,location,phone,iban,mb_way,phone_verified_at,external_payments_enabled',
    service: true,
  );
  c.note('p2.s2.row', 'seller2 profile svc', s2row.brief, lens: 'M1');
  final handle = s2row.map?['handle']?.toString() ?? 'rtm-20260831t1802-s2';
  out['s2_handle'] = handle;

  final rh = await c.rpc('batata_resolve_handle', {'p_handle': handle});
  c.note('p2.m1.resolve.real', 'anon resolve actual unpublished handle', rh.brief,
      lens: 'M1');
  if (rh.map?['found'] == true && rh.map?['profile_id']?.toString() == s2) {
    c.hold(
      id: 'RTM-M1-011',
      lens: 'M1',
      severity: 'P1',
      title: 'anon resolve_handle devolve UUID de vitrine não publicada (handle real)',
      actor: 'anon',
      pre: 'handle=$handle hub_published=false',
      repro: 'POST rpc/batata_resolve_handle p_handle=$handle',
      expected: '404 not_found',
      obtained: rh.snippet,
      evidence: {'map': rh.map},
    );
  }

  // JWT buyer: profiles * of unpublished seller
  final profStar = await c.rest(
    'GET',
    'profiles?id=eq.$s2&select=*',
    jwt: c.buyerJwt,
  );
  c.note('p2.m1.prof.star', 'buyer GET profiles * unpublished',
      '${profStar.status} keys=${profStar.map?.keys.toList()}',
      lens: 'M1');
  out['prof_star_keys'] = profStar.map?.keys.toList();
  out['prof_star_snip'] = profStar.snippet;
  if (profStar.ok && profStar.map != null) {
    final m = profStar.map!;
    final sensitive = [
      'iban',
      'mb_way',
      'nif',
      'address',
      'phone',
      'phone_verified_at',
      'date_of_birth',
      'birth_date',
      'morada',
      'postal_code',
      'stripe_connect_id',
      'connect_account_id',
    ].where((k) => m.containsKey(k) && m[k] != null && '${m[k]}'.trim().isNotEmpty);
    if (sensitive.isNotEmpty) {
      c.hold(
        id: 'RTM-M1-012',
        lens: 'M1',
        severity: 'P1',
        title: 'JWT lê PII de perfil não publicado: ${sensitive.join(",")}',
        actor: 'buyer JWT',
        pre: 'hub_published=false',
        repro: 'GET profiles?id=eq.<s2>&select=*',
        expected: 'sem IBAN/telefone/morada de terceiros',
        obtained: clip({for (final k in sensitive) k: m[k]}, 400),
      );
    }
  }

  // authenticated lives unpublished
  final livesAuth = await c.rest(
    'GET',
    'lives?seller_id=eq.$s2&select=id,status,title,mux_playback_id,mux_live_id,mux_stream_key,stream_key,is_active&order=created_at.desc&limit=8',
    jwt: c.buyerJwt,
  );
  c.note('p2.m1.lives.auth', 'buyer GET lives seller2', livesAuth.brief, lens: 'M1');
  out['lives_auth'] = livesAuth.snippet;
  if (livesAuth.ok && livesAuth.list.isNotEmpty) {
    final keys = livesAuth.body.contains('rtm_unpub_sk_') ||
        livesAuth.list.any((e) =>
            e is Map &&
            (e['mux_stream_key'] != null || e['stream_key'] != null));
    c.hold(
      id: 'RTM-M1-013',
      lens: 'M1',
      severity: keys ? 'P0' : 'P1',
      title: keys
          ? 'JWT comprador lê stream_key de lives de outro vendedor'
          : 'JWT comprador enumera lives (incl. draft/scheduled) de vitrine não publicada',
      actor: 'buyer JWT',
      pre: 'seller2 hub_published=false',
      repro: 'GET lives?seller_id=eq.<s2>',
      expected: 'tabela lives não é a fronteira Hub; só views públicas',
      obtained: livesAuth.snippet,
    );
  }

  // ghost is_live without real live
  await c.endLives();
  await c.rest(
    'PATCH',
    'lives?seller_id=eq.$s2',
    service: true,
    body: {'is_active': false, 'status': 'ended'},
    prefer: 'return=minimal',
  );
  await c.rest(
    'PATCH',
    'profiles?id=eq.$s2',
    service: true,
    body: {'is_live': true, 'hub_published': false},
    prefer: 'return=minimal',
  );
  final ghost = await c.rest(
    'GET',
    'hub_profiles_discovery_public?id=eq.$s2&select=id,handle,is_live,hub_published,location',
  );
  c.note('p2.m1.ghost', 'discovery with is_live flag, no active live', ghost.brief,
      lens: 'M1');
  out['ghost'] = ghost.snippet;
  if (ghost.ok && ghost.list.isNotEmpty) {
    c.hold(
      id: 'RTM-M1-014',
      lens: 'M1',
      severity: 'P1',
      title: 'discovery lista perfil não publicado só com flag is_live (sem directo real)',
      actor: 'anon',
      pre: 'hub_published=false is_live=true lives ended',
      repro: 'GET hub_profiles_discovery_public?id=eq.s2',
      expected: 'E0817: só hub_published OU directo REAL activo',
      obtained: ghost.snippet,
    );
  }

  // unpublished discovery extras: location / payments
  final disc = await c.rest(
    'GET',
    'hub_profiles_discovery_public?id=eq.$s2&select=*',
  );
  c.note('p2.m1.disc.star', 'discovery * seller2', disc.brief, lens: 'M1');
  out['disc_star'] = disc.snippet;

  // ---- M6 recurse storage ----
  Future<List<Map<String, dynamic>>> listPrefix(
    String bucket,
    String prefix, {
    bool service = false,
    String? jwt,
  }) async {
    final h = await c.req(
      'POST',
      '/storage/v1/object/list/$bucket',
      service: service,
      jwt: jwt,
      body: {'prefix': prefix, 'limit': 30},
    );
    c.note('p2.m6.list', '$bucket/$prefix svc=$service jwt=${jwt != null}',
        '${h.status} n=${h.list.length} ${h.snippet}',
        lens: 'M6');
    return h.list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  final chatTop = await listPrefix('chat_media', '');
  out['chat_top_anon'] = chatTop.map((e) => e['name']).toList();
  for (final folder in ['live_item_photos', 'live_raffle_prize', 'profile_photos', 'product_photos', 'catalog']) {
    final kids = await listPrefix('chat_media', folder);
    if (kids.isNotEmpty) {
      c.hold(
        id: 'RTM-M6-005',
        lens: 'M6',
        severity: 'P1',
        title: 'anon lista prefixo chat_media/$folder (n=${kids.length})',
        actor: 'anon',
        pre: 'POST object/list/chat_media prefix=$folder',
        repro: 'storage list chat_media/$folder',
        expected: 'lista vazia para quem não é dono (excepto catálogo intencional documentado)',
        obtained: clip(kids.map((e) => e['name']).take(8).toList(), 300),
      );
      // try GET first file-like
      for (final kid in kids.take(3)) {
        final name = kid['name']?.toString() ?? '';
        final isFile = kid['id'] != null;
        if (!isFile || name.isEmpty) {
          final nested = await listPrefix('chat_media', '$folder/$name');
          if (nested.isNotEmpty) {
            final f = nested.first;
            final fname = f['name']?.toString() ?? '';
            final path = '$folder/$name/$fname';
            final pub = await c.req(
              'GET',
              '/storage/v1/object/public/chat_media/$path',
            );
            c.note('p2.m6.get.public', path, '${pub.status} len=${pub.body.length}',
                lens: 'M6');
            final nbytes = int.tryParse(pub.headers['x-rtm-bytes']?.first ?? '') ??
                pub.body.length;
            if (pub.ok && nbytes > 64) {
              c.hold(
                id: 'RTM-M6-006',
                lens: 'M6',
                severity: 'P1',
                title: 'anon GET público chat_media/$path após listar UUID de outro user',
                actor: 'anon',
                pre: 'listou live_item_photos/<otherUserId>/',
                repro: 'GET /storage/v1/object/public/chat_media/$path',
                expected: '403 se foto de live/item não for catálogo marketplace',
                obtained: 'HTTP ${pub.status} bytes=$nbytes ct=${pub.headers['content-type']}',
              );
            }
            break;
          }
          continue;
        }
        final path = '$folder/$name';
        final pub = await c.req(
          'GET',
          '/storage/v1/object/public/chat_media/$path',
        );
        c.note('p2.m6.get.file', path, '${pub.status} len=${pub.body.length}',
            lens: 'M6');
      }
    }
  }

  for (final folder in ['order_disputes', 'order_proofs', 'chat_uploads']) {
    final anonKids = await listPrefix('fleaber_private', folder);
    final authKids = await listPrefix('fleaber_private', folder, jwt: c.buyerJwt);
    final svcKids = await listPrefix('fleaber_private', folder, service: true);
    out['priv_$folder'] = {
      'anon_n': anonKids.length,
      'auth_n': authKids.length,
      'svc_n': svcKids.length,
      'svc_names': svcKids.map((e) => e['name']).take(6).toList(),
    };
    if (anonKids.isNotEmpty) {
      c.hold(
        id: 'RTM-M6-007',
        lens: 'M6',
        severity: 'P0',
        title: 'anon lista fleaber_private/$folder',
        actor: 'anon',
        pre: 'bucket privado',
        repro: 'POST object/list/fleaber_private prefix=$folder',
        expected: '[]',
        obtained: clip(anonKids, 300),
      );
    }
    if (authKids.isNotEmpty) {
      c.hold(
        id: 'RTM-M6-008',
        lens: 'M6',
        severity: 'P0',
        title: 'comprador lista fleaber_private/$folder alheio n=${authKids.length}',
        actor: 'buyer JWT',
        pre: 'prefix=$folder',
        repro: 'POST object/list/fleaber_private',
        expected: 'só objectos do próprio / contra-parte da encomenda',
        obtained: clip(authKids.map((e) => e['name']).take(10).toList(), 300),
      );
    }
    if (svcKids.isNotEmpty) {
      final n = svcKids.first['name']?.toString() ?? '';
      if (n.isNotEmpty) {
        final path = '$folder/$n';
        final pub = await c.req(
          'GET',
          '/storage/v1/object/public/fleaber_private/$path',
        );
        final authGet = await c.req(
          'GET',
          '/storage/v1/object/fleaber_private/$path',
          jwt: c.buyer2Jwt,
        );
        c.note('p2.m6.priv.get', path, 'pub=${pub.status} b2=${authGet.status} blen=${authGet.body.length}',
            lens: 'M6');
        if (authGet.ok && authGet.body.length > 32) {
          c.hold(
            id: 'RTM-M6-009',
            lens: 'M6',
            severity: 'P0',
            title: 'B2 lê ficheiro fleaber_private/$path (prova/disputa alheia)',
            actor: 'buyer2 JWT',
            pre: 'objecto listado por service_role',
            repro: 'GET /storage/v1/object/fleaber_private/$path',
            expected: '403',
            obtained: '${authGet.status} bytes=${authGet.body.length}',
          );
        }
      }
    }
  }

  // ---- M5 mux write side-effect on unpublished ended without vod ----
  final writeLive = await c.insertLive(
    seller: s2,
    status: 'ended',
    active: false,
    muxPlayback: 'rtm_write_pb_$stamp',
  );
  if (writeLive != null) {
    await c.rest(
      'PATCH',
      'lives?id=eq.$writeLive',
      service: true,
      body: {'mux_vod_playback_id': null, 'mux_asset_id': null},
      prefer: 'return=minimal',
    );
    final mux = await c.edge('resolve-mux-playback', body: {'live_id': writeLive});
    c.note('p2.m5.mux.write', 'anon resolve ended unpublished', mux.brief,
        lens: 'M5');
    final after = await c.rest(
      'GET',
      'lives?id=eq.$writeLive&select=id,mux_vod_playback_id,mux_asset_id,mux_playback_id',
      service: true,
    );
    c.note('p2.m5.mux.after', 'live after anon resolve', after.brief, lens: 'M5');
    out['mux_write'] = {'resp': mux.brief, 'row': after.snippet};
  }

  // buyer complete / livekit stream_key inject on seller live (existing pub)
  final sellerLive = await c.rest(
    'GET',
    'lives?seller_id=eq.${c.sellerId}&select=id,status&order=created_at.desc&limit=1',
    service: true,
  );
  final sid = sellerLive.firstId;
  if (sid != null) {
    final inj = await c.edge(
      'livekit-mux-publish',
      jwt: c.sellerJwt,
      body: {
        'step': 'egress',
        'live_id': sid,
        'stream_key': 'rtm-injected-key-$stamp',
      },
    );
    c.note('p2.m5.stream_key.inject', 'owner inject foreign stream_key', inj.brief,
        lens: 'M5');
    if (inj.ok) {
      c.hold(
        id: 'RTM-M5-004',
        lens: 'M5',
        severity: 'P1',
        title: 'livekit-mux-publish aceita stream_key injectado pelo cliente',
        actor: 'seller JWT (dono)',
        pre: 'body.stream_key ≠ key da live',
        repro: 'POST livekit-mux-publish step=egress stream_key=injected',
        expected: '403 stream_key do cliente não autorizado',
        obtained: inj.snippet,
      );
    }
    final bComplete = await c.edge(
      'complete-mux-live',
      jwt: c.buyerJwt,
      body: {'live_id': sid},
    );
    c.note('p2.m5.buyer.complete', 'buyer complete seller live', bComplete.brief,
        lens: 'M5');
  }

  // ---- M4 tip amount huge / seller_id of unpublished ----
  final liveForTip = await c.insertLive(
    seller: c.sellerId,
    status: 'live',
    active: true,
  );
  final tipHuge = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyerJwt,
    body: {
      'seller_id': c.sellerId,
      'amount_eur': 499,
      'live_id': liveForTip,
      'web_return_origin': 'https://attacker.fleaber.pt',
    },
  );
  c.note('p2.m4.tip.huge_origin', 'tip 499€ attacker.fleaber.pt', tipHuge.brief,
      lens: 'M4');
  out['tip_huge'] = tipHuge.brief;

  // ---- M7 ONE unpaid Session ≠ capture (not dual) ----
  final tipOk = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyerJwt,
    body: {
      'seller_id': c.sellerId,
      'amount_eur': 1,
      'live_id': liveForTip,
      'web_return_origin': 'https://fleaber.pt',
    },
  );
  c.note('p2.m7.tip.session', 'ONE tip Session', tipOk.brief, lens: 'M7');
  final cs = tipOk.map?['checkoutSessionId']?.toString() ??
      tipOk.map?['checkout_session_id']?.toString();
  out['tip_session'] = {'http': tipOk.status, 'cs': cs, 'body': tipOk.snippet};
  if (cs != null && cs.startsWith('cs_')) {
    final settle = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      qs: '?checkout_return=success&session_id=$cs',
    );
    c.note('p2.m7.settle.unpaid', 'GET settle unpaid Session', settle.brief,
        lens: 'M7');
    out['tip_settle_unpaid'] = settle.brief;
    if (settle.ok &&
        ((settle.location ?? '').contains('stripe-success') ||
            settle.body.toLowerCase().contains('pagamento recebido'))) {
      c.hold(
        id: 'RTM-M7-001',
        lens: 'M7',
        severity: 'P0',
        title: 'GET settle trata Session de gorjeta NÃO paga como sucesso/captura',
        actor: 'anon GET',
        pre: 'Session criada, payment_status≠paid',
        repro: 'GET create-live-tip-checkout?checkout_return=success&session_id=<unpaid>',
        expected: 'pagamento ainda não confirmado; sem crédito wallet',
        obtained: settle.brief,
      );
    }
  }

  // PI with attacker.fleaber.pt (CORS allows, sanitizer?)
  final unlistedOk = await c.insertProduct(
    title: '$prefix listed for origin',
    listed: true,
    qty: 2,
    price: 5.9,
  );
  final piOrigin = await c.edge(
    'create-payment-intent',
    jwt: c.buyerJwt,
    body: {
      'product_id': unlistedOk,
      'quantity': 1,
      'web_return_origin': 'https://attacker.fleaber.pt',
    },
  );
  c.note('p2.m2.pi.attacker_sub', 'PI web_return attacker.fleaber.pt',
      piOrigin.brief,
      lens: 'M2');
  out['pi_attacker'] = piOrigin.brief;
  if (piOrigin.ok && piOrigin.hasCheckout) {
    c.hold(
      id: 'RTM-M2-004',
      lens: 'M2',
      severity: 'P1',
      title: 'create-payment-intent aceita web_return_origin=https://attacker.fleaber.pt (CORS já reflecte este host)',
      actor: 'buyer JWT',
      pre: 'subdomínio *.fleaber.pt',
      repro: 'POST create-payment-intent web_return_origin=https://attacker.fleaber.pt',
      expected: 'sanitize rejeita (só hosts exactos, não *.fleaber.pt)',
      obtained: piOrigin.snippet,
      proven: false,
    );
  }

  // PI settle stolen cs as B2 again with checkout_return
  const stolen = 'cs_test_a1i7M1nuRWdNVOH5MwLJrcvJ3ILsdAs7QUWt1ciBNxHqGm1ur02Bl898Y4';
  final steal2 = await c.req(
    'GET',
    '/functions/v1/create-payment-intent?checkout_return=success&session_id=$stolen',
    jwt: c.buyer2Jwt,
  );
  c.note('p2.m3.steal.b2', 'B2 settle stolen order cs', steal2.brief, lens: 'M3');
  out['steal_b2'] = steal2.brief;

  // delete-test-account / sms
  final nuke = await c.edge(
    'delete-test-account',
    jwt: c.buyerJwt,
    body: {'confirm': 'APAGAR TUDO', 'user_id': c.sellerId},
  );
  c.note('p2.m4.nuke', 'buyer nuke with seller user_id', nuke.brief, lens: 'M4');
  final sms = await c.edge(
    'send-sms-bulkgate',
    body: {
      'user_id': c.sellerId,
      'phone': '+351912000000',
      'message': 'RTM',
    },
  );
  c.note('p2.m4.sms', 'anon send-sms', sms.brief, lens: 'M4');

  await c.endLives();
  out['findings'] = c.findings;
  out['notes'] = c.notes;
  await dumpJson('${repoRoot()}/tool/redteam_blind_m_$stamp/pass2.json', out);
  stdout.writeln('FINDINGS ${c.findings.length}');
}
