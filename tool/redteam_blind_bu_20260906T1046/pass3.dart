/// RED TEAM CEGO BU pass3 — prova storage cross-user + resolve unpublished air. Sem correcções.
import 'dart:io';
import 'dart:convert';
import '_rtbu.dart';

Future<int> statusOnly(
  Rtbu c,
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
  final c = Rtbu.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  // Recreate unpublished air briefly
  final airUnpub = await c.insertLive(
    seller: c.seller2Id,
    active: true,
    status: 'live',
    muxPlayback: 'rtbuUnpubAirPb3',
    title: '$prefix unpub-air-p3',
  );
  final r = await c.edge('resolve-mux-playback', body: {'live_id': airUnpub});
  c.note('p3.resolve.unpubair', 'resolve unpublished air', r, lens: 'BU5');
  final disc = await c.rest(
    'GET',
    'hub_lives_discovery_public?id=eq.$airUnpub&select=id,mux_playback_id,status,is_active,seller_handle',
  );
  final pub = await c.rest(
    'GET',
    'hub_lives_public?id=eq.$airUnpub&select=id,mux_playback_id,status',
  );
  c.note('p3.disc.unpubair', 'discovery unpublished air', disc, lens: 'BU1');
  c.note('p3.pub.unpubair', 'hub public unpublished air', pub, lens: 'BU1');
  final pid = '${r.map?['playback_id'] ?? ''}';
  if (pid.isNotEmpty && pid != 'null') {
    c.hold(
      id: 'BU5-RESOLVE-UNPUB-AIR',
      lens: 'BU5',
      severity: 'P2',
      title: 'resolve-mux serve playback de directo unpublished',
      actor: 'anon',
      pre: 'S2 hub_published=false broadcasting',
      repro: 'POST resolve-mux-playback live_id unpublished air',
      expected: '404 se Hub unpublished escondesse o stream',
      obtained: r.brief,
    );
  } else {
    c.block('p3.resolve.unpub', 'BU5', 'resolve recusa unpublished air', r);
  }

  // List seller prefix as B1
  final listSeller = await c.req(
    'POST',
    '/storage/v1/object/list/fleaber_private',
    jwt: c.buyerJwt,
    body: {'prefix': 'order_disputes/${c.sellerId}/', 'limit': 10},
  );
  c.note('p3.list.seller', 'B1 lista disputes do seller', listSeller, lens: 'BU6');
  if (listSeller.list.isNotEmpty) {
    c.hold(
      id: 'BU6-LIST-SELLER',
      lens: 'BU6',
      severity: 'P1',
      title: 'B1 lista order_disputes do vendedor',
      actor: 'B1',
      pre: 'prefix=order_disputes/${c.sellerId}/',
      repro: 'POST list fleaber_private',
      expected: '[]',
      obtained: listSeller.brief,
    );
  } else {
    c.block('p3.list.seller', 'BU6', 'B1 não lista pasta do seller', listSeller);
  }

  final listOwn = await c.req(
    'POST',
    '/storage/v1/object/list/fleaber_private',
    jwt: c.buyerJwt,
    body: {
      'prefix': 'order_disputes/${c.buyerId}/',
      'limit': 5,
    },
  );
  final ownName = listOwn.list
      .whereType<Map>()
      .map((e) => '${e['name'] ?? ''}')
      .where((n) => n.contains('.'))
      .cast<String?>()
      .firstWhere((n) => n != null, orElse: () => null);

  if (ownName != null) {
    final ownPath = 'order_disputes/${c.buyerId}/$ownName';
    final stOwn = await statusOnly(
      c,
      'GET',
      '/storage/v1/object/authenticated/fleaber_private/$ownPath',
      jwt: c.buyerJwt,
    );
    final stB2 = await statusOnly(
      c,
      'GET',
      '/storage/v1/object/authenticated/fleaber_private/$ownPath',
      jwt: c.buyer2Jwt,
    );
    c.note('p3.get.own', 'GET own file B1=$stOwn B2=$stB2 path=$ownPath', null,
        lens: 'BU6');
    if (stB2 == 200) {
      c.hold(
        id: 'BU6-CROSS-READ',
        lens: 'BU6',
        severity: 'P1',
        title: 'B2 lê prova fleaber_private de B1',
        actor: 'B2',
        pre: ownPath,
        repro: 'GET object/authenticated/fleaber_private/... JWT B2',
        expected: '400/403',
        obtained: 'HTTP $stB2',
      );
    } else {
      c.block('p3.cross.read', 'BU6', 'B2 não lê ficheiro B1', 'st=$stB2 ownB1=$stOwn');
    }
  } else {
    c.skip('p3.own.file', 'BU6', 'sem ficheiro próprio para GET', listOwn.brief);
  }

  // Service: pick a seller-owned object and try B1 GET
  final svcList = await c.req(
    'POST',
    '/storage/v1/object/list/fleaber_private',
    service: true,
    body: {'prefix': 'order_disputes/${c.sellerId}/', 'limit': 5},
  );
  c.note('p3.svc.seller.list', 'svc list seller disputes', svcList, lens: 'BU6');
  final sName = svcList.list
      .whereType<Map>()
      .map((e) => '${e['name'] ?? ''}')
      .where((n) => n.contains('.'))
      .cast<String?>()
      .firstWhere((n) => n != null, orElse: () => null);
  if (sName != null) {
    final p = 'order_disputes/${c.sellerId}/$sName';
    final st = await statusOnly(
      c,
      'GET',
      '/storage/v1/object/authenticated/fleaber_private/$p',
      jwt: c.buyerJwt,
    );
    c.note('p3.get.sellerfile', 'B1 GET seller file $p → $st', null, lens: 'BU6');
    if (st == 200) {
      c.hold(
        id: 'BU6-READ-SELLER-FILE',
        lens: 'BU6',
        severity: 'P1',
        title: 'B1 lê objecto fleaber_private do vendedor',
        actor: 'B1',
        pre: p,
        repro: 'GET authenticated fleaber_private seller path',
        expected: '403',
        obtained: 'HTTP $st',
      );
    } else {
      c.block('p3.read.seller', 'BU6', 'B1 não lê ficheiro seller', 'HTTP $st');
    }
  } else {
    c.skip('p3.seller.file', 'BU6', 'seller sem ficheiro disputes', svcList.brief);
  }

  if (airUnpub != null) {
    await c.rest('PATCH', 'lives?id=eq.$airUnpub', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
  }

  await dumpJson('${outDir()}/pass3.json', {
    'findings': c.findings,
    'blocked': c.blocked,
    'skipped': c.skipped,
    'notes': c.notes,
  });
  stdout.writeln('PASS3 findings=${c.findings.length} blocked=${c.blocked.length}');
}
