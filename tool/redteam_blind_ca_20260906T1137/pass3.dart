/// RED TEAM CEGO CA pass3 — storage, resolve_handle sem air, OpenAPI, cleanup fixtures.
import 'dart:convert';
import 'dart:io';
import '_rtca.dart';

Future<Map<String, dynamic>> loadIds() async {
  final f = File('${outDir()}/pass1.json');
  final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  return Map<String, dynamic>.from(j['ids'] as Map);
}

Future<int> statusOnly(
  Rtca c,
  String method,
  String path, {
  String? jwt,
  Object? body,
}) async {
  final key = c.anon;
  final uri = Uri.parse('${c.url}$path');
  final client = HttpClient();
  try {
    final rq = await client.openUrl(method, uri);
    rq.followRedirects = false;
    rq.headers.set('apikey', key);
    rq.headers.set('Authorization', 'Bearer ${jwt ?? key}');
    if (body != null) {
      rq.headers.set('Content-Type', 'application/json');
      rq.add(utf8.encode(body is String ? body : jsonEncode(body)));
    }
    final rs = await rq.close().timeout(const Duration(seconds: 20));
    await rs.drain<void>();
    return rs.statusCode;
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  final c = Rtca.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final ids = await loadIds();
  final airUnpub = ids['airUnpub'] as String;
  final airPub = ids['airPub'] as String;
  final s2 = ids['s2'] as String;
  final s1 = ids['s1'] as String;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;

  // Pause unpublished air: remaining scheduled+ended unpublished.
  await c.rest('PATCH', 'lives?id=eq.$airUnpub', service: true, body: {
    'is_active': false,
    'status': 'ended',
  }, prefer: 'return=minimal');

  final profAfter = await c.rest(
    'GET',
    'hub_profiles_discovery_public?id=eq.$s2&select=id,handle,hub_published',
  );
  final livesDiscAfter = await c.rest(
    'GET',
    'hub_lives_discovery_public?seller_id=eq.$s2&select=id,status,mux_playback_id,mux_vod_playback_id',
  );
  final rhAfter = await c.rpc(
    'batata_resolve_handle',
    {'p_handle': 'rtca-20260906t1137-s2'},
  );
  c.note('ca1.prof.after-air', 'profiles discovery após end air', profAfter,
      lens: 'CA1');
  c.note('ca1.disc.after-air', 'lives discovery S2 após end', livesDiscAfter,
      lens: 'CA1');
  c.note('ca1.rh.after-air', 'resolve_handle após end air', rhAfter, lens: 'CA1');

  if (profAfter.list.isNotEmpty) {
    c.hold(
      id: 'CA1-PROFDISC-UNPUB-ENDED',
      lens: 'CA1',
      severity: 'P2',
      title: 'profiles discovery ainda mostra unpublished sem directo no ar',
      actor: 'anon',
      pre: 'S2 air ended; só scheduled+ended',
      repro: 'GET hub_profiles_discovery_public S2',
      expected: '[]',
      obtained: profAfter.brief,
    );
  } else {
    c.block('ca1.prof.after', 'CA1', 'profiles discovery some sem air', profAfter);
  }

  if (rhAfter.map?['found'] == true) {
    c.hold(
      id: 'CA1-RESOLVE-HANDLE-UNPUB-ENDED',
      lens: 'CA1',
      severity: 'P2',
      title: 'resolve_handle encontra unpublished só com scheduled/ended',
      actor: 'anon',
      pre: 'S2 hub_published=false; air ended',
      repro: 'POST batata_resolve_handle slug S2',
      expected: 'not_found (loja desligada sem directo no ar)',
      obtained: rhAfter.brief,
    );
  } else {
    c.block('ca1.rh.after', 'CA1', 'resolve_handle not_found após end', rhAfter);
  }

  if (livesDiscAfter.list.isNotEmpty) {
    final vod = col(livesDiscAfter.map, 'mux_vod_playback_id');
    c.hold(
      id: 'CA1-DISC-UNPUB-AFTER',
      lens: 'CA1',
      severity: 'P2',
      title: 'lives discovery lista unpublished após end',
      actor: 'anon',
      pre: s2,
      repro: 'GET hub_lives_discovery_public seller_id S2',
      expected: '[] (exacto BRBW se unpublished)',
      obtained: livesDiscAfter.brief,
      countExactClosed: vod == null,
    );
  } else {
    c.block('ca1.disc.after', 'CA1', 'lives discovery vazia S2', livesDiscAfter);
  }

  // OpenAPI / schema leak
  final openapi = await c.req(
    'GET',
    '/rest/v1/',
    extra: {'Accept': 'application/openapi+json'},
  );
  c.note('ca5.openapi', 'openapi', {
    'status': openapi.status,
    'has_lives': openapi.body.contains('/lives'),
    'has_mux': openapi.body.contains('mux_stream_key') ||
        openapi.body.contains('stream_key'),
    'len': openapi.body.length,
  }, lens: 'CA5');

  // ---------- CA6 storage ----------
  final buckets = await c.req('GET', '/storage/v1/bucket');
  final bucketsJwt = await c.req('GET', '/storage/v1/bucket', jwt: c.buyerJwt);
  c.note('ca6.buckets.anon', 'list buckets anon', buckets, lens: 'CA6');
  c.note('ca6.buckets.b1', 'list buckets B1', bucketsJwt, lens: 'CA6');

  List<dynamic> bucketList(HttpHit h) {
    if (h.json is List) return h.json as List;
    return const [];
  }

  for (final b in [...bucketList(buckets), ...bucketList(bucketsJwt)]) {
    if (b is Map && b['public'] == true) {
      c.note('ca6.public.bucket', 'bucket public', b['id'], lens: 'CA6');
    }
  }

  Future<HttpHit> listBucket(String bucket, String prefix, {String? jwt}) {
    return c.req(
      'POST',
      '/storage/v1/object/list/$bucket',
      jwt: jwt,
      body: {
        'prefix': prefix,
        'limit': 20,
        'offset': 0,
      },
    );
  }

  for (final bucket in [
    'fleaber_private',
    'chat_media',
    'product_photos',
    'avatars',
    'mux',
    'recordings',
    'lives',
  ]) {
    final anon = await listBucket(bucket, '');
    final b1l = await listBucket(bucket, '', jwt: c.buyerJwt);
    c.note('ca6.list.anon.$bucket', 'list anon', {
      'status': anon.status,
      'n': anon.list.length,
      'snip': clip(anon.body, 160),
    }, lens: 'CA6');
    c.note('ca6.list.b1.$bucket', 'list B1', {
      'status': b1l.status,
      'n': b1l.list.length,
      'snip': clip(b1l.body, 160),
    }, lens: 'CA6');
  }

  // Cross-user: B1 lists B2 uid prefix; B2 GET B1 object
  final listCross = await listBucket('fleaber_private', b2, jwt: c.buyerJwt);
  c.note('ca6.list.cross', 'B1 lista prefix B2', {
    'status': listCross.status,
    'n': listCross.list.length,
    'brief': listCross.brief,
  }, lens: 'CA6');

  // Upload as B1 then GET as B2 / anon
  final objName = '$b1/rtca1137-probe.txt';
  final up = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$objName',
    jwt: c.buyerJwt,
    extra: {'Content-Type': 'text/plain', 'x-upsert': 'true'},
    body: 'rtca-private-probe',
  );
  // req() JSON-encodes body - might fail. Try raw if needed.
  c.note('ca6.up.b1', 'upload B1 private', up, lens: 'CA6');

  final getB2 = await statusOnly(
    c,
    'GET',
    '/storage/v1/object/fleaber_private/$objName',
    jwt: c.buyer2Jwt,
  );
  final getAnon = await statusOnly(
    c,
    'GET',
    '/storage/v1/object/fleaber_private/$objName',
  );
  final getPub = await statusOnly(
    c,
    'GET',
    '/storage/v1/object/public/fleaber_private/$objName',
  );
  c.note('ca6.get.cross', 'GET object cruzado', {
    'b2': getB2,
    'anon': getAnon,
    'public_url': getPub,
  }, lens: 'CA6');
  if (getB2 == 200 || getAnon == 200 || getPub == 200) {
    c.hold(
      id: 'CA6-STORAGE-CROSS-GET',
      lens: 'CA6',
      severity: 'P1',
      title: 'GET storage fleaber_private alheio/anónimo',
      actor: getB2 == 200 ? 'B2' : 'anon',
      pre: objName,
      repro: 'GET /storage/v1/object/fleaber_private/{b1}/…',
      expected: '400/403',
      obtained: {'b2': getB2, 'anon': getAnon, 'public': getPub},
    );
  } else {
    c.block('ca6.get.cross', 'CA6', 'GET cruzado recusado', {
      'b2': getB2,
      'anon': getAnon,
      'public': getPub,
    });
  }

  if (listCross.ok && listCross.list.isNotEmpty) {
    c.hold(
      id: 'CA6-STORAGE-LIST-CROSS',
      lens: 'CA6',
      severity: 'P2',
      title: 'B1 lista objectos do prefixo B2',
      actor: 'B1',
      pre: 'prefix=$b2',
      repro: 'POST storage list fleaber_private prefix B2',
      expected: '[]',
      obtained: listCross.brief,
    );
  } else {
    c.block('ca6.list.cross', 'CA6', 'list prefix alheio vazio/negado', listCross);
  }

  // chat_media public URL
  final chatPub = await c.req('GET', '/storage/v1/bucket/chat_media');
  c.note('ca6.bucket.chat', 'chat_media meta', chatPub, lens: 'CA6');

  // user_type privilege
  final ut = await c.rest(
    'PATCH',
    'profiles?id=eq.$b1',
    jwt: c.buyerJwt,
    body: {'user_type': 'vendedor', 'hub_published': true},
  );
  c.note('ca7.ut.patch', 'B1 PATCH user_type', ut, lens: 'CA7');
  if (ut.ok && (ut.body.contains('vendedor') || ut.list.isNotEmpty)) {
    final mux = await c.edge(
      'create-mux-live',
      jwt: c.buyerJwt,
      body: {'title': '$prefix priv-esc mux'},
    );
    c.note('ca7.ut.mux', 'create-mux after user_type patch', mux, lens: 'CA7');
    if (mux.ok) {
      c.hold(
        id: 'CA7-USERTYPE-MUX',
        lens: 'CA7',
        severity: 'P1',
        title: 'comprador PATCH user_type e cria Mux',
        actor: 'B1',
        pre: 'PATCH profiles user_type=vendedor',
        repro: 'PATCH profiles + POST create-mux-live',
        expected: 'PATCH ignorado / create 403',
        obtained: {'patch': ut.brief, 'mux': mux.brief},
      );
    }
  } else {
    c.block('ca7.ut.patch', 'CA7', 'user_type não escalável por JWT', ut);
  }

  // B1 GET ended unpublished VOD via Hub view after we ended air (now ended unpublished with real vod)
  final endedDisc = await c.rest(
    'GET',
    'hub_lives_public?id=eq.$airUnpub&select=id,status,mux_vod_playback_id',
  );
  c.note('ca5.hub.ended.unpub', 'hub public ended unpublished', endedDisc,
      lens: 'CA5');

  // Restore nothing on lab S1; end remaining fixtures.
  await c.rest('PATCH', 'lives?id=eq.$airPub', service: true, body: {
    'is_active': false,
    'status': 'ended',
  }, prefer: 'return=minimal');
  for (final id in [
    ids['schedUnpub'],
    ids['endedUnpub'],
    ids['endedPub'],
    ids['inactivePub'],
    ids['schedPub'],
    airUnpub,
  ]) {
    if (id is String) {
      await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
        'is_active': false,
        'status': 'ended',
      }, prefer: 'return=minimal');
    }
  }

  await dumpJson('${outDir()}/pass3.json', {
    'lenses': c.lensesHit.toList()..sort(),
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'skipped': c.skipped,
  });
  stdout.writeln('WROTE pass3.json findings=${c.findings.length}');
}
