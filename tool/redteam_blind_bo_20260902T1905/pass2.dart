/// BO pass 2 — confirmar JWT colunas seguras, VOD unpublished, Hub items 401, storage jpeg.
import 'dart:io';

import '_rtbo.dart';

Future<void> main() async {
  final c = Rtbo.fromEnv(loadEnv());
  try {
    await c.loginActors();
    await c.ensureBuyer2();
    await c.ensureSeller2Unpublished();
    await c.pickPlantedPlayback();
    final plant = c.plantedPlaybackId!;

    await c.rest('PATCH', 'profiles?id=eq.${c.sellerId}', service: true, body: {
      'hub_published': true,
    }, prefer: 'return=minimal');

    final liveSched = await c.insertLive(
      status: 'scheduled',
      active: false,
      title: '$prefix-p2-sched',
      muxPlaybackId: 'play-p2-sched',
      muxVodPlaybackId: plant,
      streamKey: 'sk-p2-sched',
    );
    final liveEndedUnpub = await c.insertLive(
      seller: c.seller2Id,
      status: 'ended',
      active: false,
      title: '$prefix-p2-ended-unpub',
      muxPlaybackId: 'play-p2-unpub',
      muxVodPlaybackId: plant,
      streamKey: 'sk-p2-unpub',
    );
    final liveAir = await c.insertLive(
      status: 'live',
      active: true,
      title: '$prefix-p2-air',
      muxPlaybackId: 'play-p2-air',
      muxVodPlaybackId: plant,
    );
    if (liveAir != null) await c.insertLiveItem(liveId: liveAir);

    final liveInactive = await c.insertLive(
      status: 'live',
      active: false,
      title: '$prefix-p2-inactive',
      muxPlaybackId: 'play-p2-inact',
      muxVodPlaybackId: plant,
    );

    Future<HttpHit> livesSafe(String? id, {String? jwt}) {
      return c.rest(
        'GET',
        'lives?id=eq.$id&select=id,status,is_active,mux_vod_playback_id,mux_playback_id,playback_id',
        jwt: jwt ?? c.buyerJwt,
      );
    }

    Future<HttpHit> hub(String view, String? id) {
      return c.rest('GET', '$view?id=eq.$id&select=id,status,mux_vod_playback_id,mux_playback_id');
    }

    for (final e in {
      'sched': liveSched,
      'ended_unpub': liveEndedUnpub,
      'air': liveAir,
      'inactive': liveInactive,
    }.entries) {
      final jwt = await livesSafe(e.value);
      final anon = await c.rest(
        'GET',
        'lives?id=eq.${e.value}&select=id,status,mux_vod_playback_id',
      );
      final disc = await hub('hub_lives_discovery_public', e.value);
      final pub = await hub('hub_lives_public', e.value);
      c.note('p2.jwt.${e.key}', 'buyer safe-cols', jwt, lens: 'BO7');
      c.note('p2.anon.${e.key}', 'anon lives safe-cols', anon, lens: 'BO7');
      c.note('p2.disc.${e.key}', 'discovery', disc, lens: 'BO1');
      c.note('p2.pub.${e.key}', 'hub_lives_public', pub, lens: 'BO1');

      final jwtVod = '${jwt.map?['mux_vod_playback_id'] ?? ''}'.trim();
      final discVod = '${disc.map?['mux_vod_playback_id'] ?? ''}'.trim();
      final pubVod = '${pub.map?['mux_vod_playback_id'] ?? ''}'.trim();

      if (jwt.ok && jwtVod.isNotEmpty && discVod.isEmpty && pubVod.isEmpty) {
        final cdn = await c.muxCdn(jwtVod);
        final watches = cdn.ok && cdn.body.contains('#EXTM3U');
        c.hold(
          id: 'p2.jwt.vod.${e.key}',
          lens: 'BO7',
          severity: watches ? 'P2' : 'P3',
          title:
              'buyer JWT lê mux_vod_playback_id em ${e.key}; Hub/discovery anulam; CDN ${watches ? "serve HLS" : "não serve"}',
          actor: 'buyer JWT',
          pre: 'GRANT colunas seguras lives; RLS status scheduled|live|ended',
          repro:
              'GET lives?id=eq.${e.value}&select=id,status,mux_vod_playback_id (sem stream_key)',
          expected: 'mesmo filtro que hub_lives_public (VOD só ended publicado)',
          obtained:
              'jwt=${jwt.brief} disc=${disc.brief} pub=${pub.brief} cdn=${cdn.status}',
          evidence: {
            'watches': watches,
            'jwt_vod': jwtVod,
            'disc_vod': discVod,
            'pub_vod': pubVod,
          },
        );
      } else if (e.key == 'sched' && discVod.isNotEmpty) {
        c.hold(
          id: 'p2.disc.sched.vod',
          lens: 'BO1',
          severity: 'P2',
          title: 'discovery scheduled+VOD (exacto BI — não contar)',
          actor: 'anon',
          pre: 'scheduled com vod',
          repro: 'GET hub_lives_discovery_public',
          expected: 'null',
          obtained: disc.brief,
          count: false,
        );
      } else {
        c.block('p2.jwt.vod.${e.key}', 'BO7', 'sem bypass ${e.key}', {
          'jwt': jwt.brief,
          'disc': disc.brief,
          'pub': pub.brief,
        });
      }
    }

    // Seller JWT PATCH reopen ended_unpub → scheduled (composição sem plant extra)
    if (liveEndedUnpub != null) {
      final patch = await c.rest(
        'PATCH',
        'lives?id=eq.$liveEndedUnpub',
        jwt: c.seller2Jwt,
        body: {'status': 'scheduled', 'is_active': false},
      );
      c.note('p2.patch.s2', 'seller2 PATCH ended→scheduled', patch, lens: 'BO7');
      if (patch.ok && patch.list.isNotEmpty) {
        c.hold(
          id: 'p2.reopen.jwt',
          lens: 'BO7',
          severity: 'P2',
          title: 'seller JWT reabre ended→scheduled e VOD continua nas colunas lives',
          actor: 'seller2 JWT',
          pre: 'ended unpublished com vod',
          repro: 'PATCH lives status=scheduled',
          expected: 'permission denied',
          obtained: patch.brief,
        );
      } else {
        c.block('p2.reopen.jwt', 'BO7', 'seller não PATCH lives', patch);
      }
    }

    // Hub items view — regressão BFBK revoke broadcasting
    final itemsAnon = await c.rest(
      'GET',
      'hub_live_items_public?limit=3',
    );
    final itemsBuyer = await c.rest(
      'GET',
      'hub_live_items_public?limit=3',
      jwt: c.buyerJwt,
    );
    final itemsDiscAnon = await c.rest(
      'GET',
      'hub_live_items_discovery_public?limit=3',
    );
    c.note('p2.items.anon', 'hub_live_items_public anon', itemsAnon, lens: 'BO1');
    c.note('p2.items.buyer', 'hub_live_items_public buyer', itemsBuyer, lens: 'BO1');
    c.note('p2.items.disc.anon', 'discovery items anon', itemsDiscAnon, lens: 'BO1');
    if (itemsAnon.status == 401 ||
        '${itemsAnon.err}'.contains('batata_live_is_broadcasting')) {
      c.hold(
        id: 'p2.hub.items.401',
        lens: 'BO1',
        severity: 'P2',
        title:
            'hub_live_items_public 401 anon: view chama batata_live_is_broadcasting após revoke BFBK',
        actor: 'anon',
        pre: 'revoke execute broadcasting from anon; view security_barrier invoker',
        repro: 'GET hub_live_items_public',
        expected: '200 catálogo (função corre como owner) ou view sem EXECUTE anon',
        obtained: itemsAnon.brief,
      );
    } else {
      c.block('p2.hub.items.401', 'BO1', 'items anon OK', itemsAnon);
    }
    if (itemsDiscAnon.status == 401 ||
        '${itemsDiscAnon.err}'.contains('batata_live_is_broadcasting')) {
      c.hold(
        id: 'p2.hub.items.disc.401',
        lens: 'BO1',
        severity: 'P2',
        title: 'hub_live_items_discovery_public 401 anon (mesmo revoke)',
        actor: 'anon',
        pre: 'view discovery items',
        repro: 'GET hub_live_items_discovery_public',
        expected: '200 ou vazio, não 401 função',
        obtained: itemsDiscAnon.brief,
      );
    }

    // Authenticated broadcasting oracle
    final bcBuyer = await c.rpc('batata_live_is_broadcasting', {
      'p_live_id': liveAir,
    }, jwt: c.buyerJwt);
    c.note('p2.bcast.buyer', 'buyer broadcasting oracle', bcBuyer, lens: 'BO1');
    if (bcBuyer.json == true || bcBuyer.json == false) {
      c.block('p2.bcast.buyer', 'BO1',
          'authenticated broadcasting (GRANT esperado)', bcBuyer);
    }

    // CORS header names
    final opt = await c.edge(
      'stripe-webhook',
      null,
      method: 'OPTIONS',
      extra: {
        'Origin': 'https://evil.com',
        'Access-Control-Request-Method': 'POST',
        'Access-Control-Request-Headers': 'x-webhook-secret,authorization',
      },
    );
    c.note('p2.cors.webhook', 'OPTIONS stripe-webhook', {
      'acao': opt.acao,
      'acah': opt.acah,
      'status': opt.status,
    }, lens: 'BO2');
    final acah = (opt.acah ?? '').toLowerCase();
    if (acah.contains('x-webhook-secret') || acah.contains('x-cleanup-secret')) {
      c.hold(
        id: 'p2.cors.secret.headers',
        lens: 'BO2',
        severity: 'P3',
        title: 'CORS Allow-Headers anuncia x-webhook-secret / x-cleanup-secret',
        actor: 'browser OPTIONS',
        pre: 'cors.ts Allow-Headers estático',
        repro: 'OPTIONS qualquer Edge com Origin hostil',
        expected: 'não anunciar nomes de segredos',
        obtained: opt.acah,
      );
    } else {
      c.block('p2.cors.secret.headers', 'BO2', 'ACAH sem secret names', opt.acah);
    }

    // Storage: jpeg upload + list with service then steal
    final jpeg = base64Jpeg();
    final upJpeg = await c.req(
      'POST',
      '/storage/v1/object/fleaber_private/$prefix-pwn.jpg',
      body: jpeg,
      extra: {'Content-Type': 'image/jpeg', 'x-upsert': 'true'},
    );
    c.note('p2.storage.jpeg', 'anon jpeg upload private', upJpeg, lens: 'BO6');
    await c.expectDenied(
      id: 'p2.storage.jpeg',
      lens: 'BO6',
      title: 'anon upload JPEG fleaber_private',
      hit: upJpeg,
      actor: 'anon',
      pre: 'mime image/jpeg permitido no bucket',
      repro: 'POST storage/v1/object/fleaber_private/*.jpg',
      severityIfOpen: 'P1',
      openIf: (h) => h.ok,
    );

    final svcBuckets = await c.req('GET', '/storage/v1/bucket', service: true);
    c.note('p2.storage.buckets.svc', 'service list buckets', svcBuckets,
        lens: 'BO6');
    if (svcBuckets.list.isNotEmpty) {
      for (final b in svcBuckets.list.take(8)) {
        if (b is! Map) continue;
        final id = '${b['id']}';
        final isPublic = b['public'] == true;
        final listing = await c.req(
          'POST',
          '/storage/v1/object/list/$id',
          body: {'prefix': '', 'limit': 5},
        );
        c.note('p2.storage.list.$id', 'anon list $id public=$isPublic', listing,
            lens: 'BO6');
        if (listing.ok && listing.list.isNotEmpty && !isPublic) {
          c.hold(
            id: 'p2.storage.list.private',
            lens: 'BO6',
            severity: 'P1',
            title: 'anon lista objectos de bucket privado $id',
            actor: 'anon',
            pre: 'public=$isPublic',
            repro: 'POST storage/v1/object/list/$id',
            expected: '403',
            obtained: listing.brief,
          );
        }
      }
    }

    // Octal dotted — mesma classe do exacto 2130706433 se Edge antigo
    final octal = await c.edge(
      'create-connect-account',
      null,
      method: 'GET',
      qs: 'web_return_origin=${Uri.encodeQueryComponent('https://0177.0.0.1')}',
    );
    c.note('p2.wr.octal', '0177.0.0.1', octal, lens: 'BO2');
    if (octal.status == 303 &&
        (octal.location ?? '').contains('127.0.0.1')) {
      c.hold(
        id: 'p2.wr.octal',
        lens: 'BO2',
        severity: 'P2',
        title:
            'web_return https://0177.0.0.1 → 303 127.0.0.1 (octeto octal; Edge sanitizer BFBK não observado)',
        actor: 'anon GET',
        pre: 'URL parser Deno normaliza 0177.0.0.1',
        repro: 'GET create-connect-account?web_return_origin=https://0177.0.0.1',
        expected: 'HTML wallet / sem 303 loopback via forma octal',
        obtained: octal.brief,
        count: false,
      );
    }

    // FOMO exact qty on air — already have available_qty 3. Confirm not PII.
    if (liveAir != null) {
      final fomo = await c.rpc('batata_hub_live_fomo_snapshot', {
        'p_live_id': liveAir,
      });
      c.note('p2.fomo.air.qty', 'FOMO exact qty', fomo, lens: 'BO1');
    }
  } finally {
    await c.endAllLives();
    await c.dumpAll('pass2.json');
    stdout.writeln(
        'PASS2 done findings=${c.findings.length} blocked=${c.blocked.length}');
  }
}

List<int> base64Jpeg() {
  // 1x1 jpeg
  const b64 =
      '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAGfAD/2Q==';
  return Uri.parse('data:image/jpeg;base64,$b64').data!.contentAsBytes();
}
