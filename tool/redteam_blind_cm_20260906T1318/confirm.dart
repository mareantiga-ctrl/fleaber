/// Confirm A3/A4 columns + A11 ghost follow + favorite ghost oracle.
import 'dart:convert';
import 'dart:io';
import '_rtcm.dart';

Future<void> main() async {
  final c = Rtcm.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  final ids = jsonDecode(await File('${outDir()}/pass1_ids.json').readAsString())
      as Map<String, dynamic>;
  final itemUnpub = ids['itemUnpub'] as String?;
  final prodUnpub = ids['prodUnpub'] as String?;
  final b1 = ids['b1'] as String;
  const ghost = '00000000-0000-4000-a000-0000000000c1';
  const ghostProd = '00000000-0000-4000-a000-0000000000c2';

  final a3 = await c.rest(
    'GET',
    'hub_live_items_public?id=eq.$itemUnpub&select=id,title,price',
  );
  final a3d = await c.rest(
    'GET',
    'hub_live_items_discovery_public?id=eq.$itemUnpub&select=id,title,price',
  );
  c.probe(
    id: 'A3b',
    poco: 'CM-A',
    payload: 'GET hub_live_items_* unpublished select id,title,price',
    http: {'pub': a3.brief, 'disc': a3d.brief},
    result: (leakRow(a3) || leakRow(a3d)) ? 'FAIL' : 'HOLD',
    lens: 'CM1',
  );

  final a4 = await c.rest(
    'GET',
    'hub_products_public?id=eq.$prodUnpub&select=id,title,price',
  );
  c.probe(
    id: 'A4b',
    poco: 'CM-A',
    payload: 'GET hub_products_public unpublished select id,title,price',
    http: a4,
    result: leakRow(a4) ? 'FAIL' : 'HOLD',
    lens: 'CM1',
  );

  final ghostRow = await c.rest(
    'GET',
    'follows?id=eq.cb1db287-0000-0000-0000-000000000000&select=id,follower_id,following_id',
    service: true,
  );
  final ghostList = await c.rest(
    'GET',
    'follows?following_id=eq.$ghost&select=id,follower_id,following_id',
    service: true,
  );
  c.probe(
    id: 'A11b',
    poco: 'CM-A',
    payload: 'BD follows following_id=ghost UUID',
    http: ghostList,
    bd: {'n': ghostList.list.length, 'rows': clip(ghostList.body, 240)},
    result: leakRow(ghostList) ? 'FAIL' : 'HOLD',
    lens: 'CM1',
  );

  final favGhost = await c.rest('POST', 'favorites', jwt: c.buyerJwt, body: {
    'user_id': b1,
    'product_id': ghostProd,
  });
  c.probe(
    id: 'A13b',
    poco: 'CM-A',
    payload: 'B1 POST favorites product_id ghost UUID (oracle vs A13)',
    http: favGhost,
    result: favGhost.ok ? 'FAIL' : 'HOLD',
    lens: 'CM1',
  );

  await dumpJson('${outDir()}/pass1b.json', {
    'probes': c.probes,
    'notes': c.notes,
    'ghostFollow': ghostList.brief,
    'favGhost': favGhost.brief,
    'a3': a3.brief,
    'a4': a4.brief,
  });
}
