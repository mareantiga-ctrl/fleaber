/// Pass 4 — J3 GET cross-user on known private objects; confirm pass2 list.
import 'dart:io';

import '_rtj.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rtj.fromEnv(env);
  await c.loginActors(env);
  await c.ensureBuyer2();

  const buyer = 'bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96';
  const seller = '980f4fa1-0004-42f9-abca-69f1a9c29588';
  const objects = [
    'chat_uploads/$buyer/reaudit.txt',
    'chat_uploads/$buyer/rtb_ok_1788005353584.png',
    'order_disputes/$buyer/reaudit_d.jpg',
    'chat_uploads/f8859e23-504b-4c85-8a51-aeb04a9e95a0/RTJ-20260831T1706-own.json',
  ];

  Future<Map<String, Object?>> getObj(String path, {String? jwt, bool anon = false}) async {
    final h = await c.req(
      'GET',
      '/storage/v1/object/fleaber_private/$path',
      jwt: anon ? null : jwt,
    );
    return {
      'path': path,
      'who': anon
          ? 'anon'
          : (jwt == c.sellerJwt
              ? 'seller'
              : jwt == c.buyer2Jwt
                  ? 'buyer2'
                  : jwt == c.buyerJwt
                      ? 'buyer'
                      : 'other'),
      'http': h.status,
      'len': h.body.startsWith('binary:')
          ? int.tryParse(h.body.substring(7)) ?? h.body.length
          : h.body.length,
      'snip': clip(h.body, 120),
    };
  }

  final gets = <Map<String, Object?>>[];
  for (final p in objects) {
    gets.add(await getObj(p, jwt: c.sellerJwt));
    gets.add(await getObj(p, jwt: c.buyer2Jwt));
    gets.add(await getObj(p, jwt: c.buyerJwt));
    gets.add(await getObj(p, anon: true));
  }
  c.note('gets', gets);

  for (final g in gets) {
    final http = g['http'] as int;
    final who = g['who'];
    final path = g['path']?.toString() ?? '';
    final ownBuyer = path.contains(buyer);
    final ownB2 = path.contains('f8859e23');
    if (http >= 200 && http < 300 && (g['len'] as int) > 20) {
      if (who == 'buyer2' && ownBuyer) {
        c.addFinding(finding(
          id: '$prefix-J3-GET-STRANGER',
          lens: 'J3',
          severity: 'P1',
          title: 'buyer2 GET media privada do buyer1',
          pre: path,
          repro: 'GET /storage/v1/object/fleaber_private/$path',
          proven: true,
          evidence: g,
        ));
      }
      if (who == 'seller' && path.contains('chat_uploads/') && ownBuyer) {
        c.addFinding(finding(
          id: '$prefix-J3-GET-CHAT-UPLOADS-COUNTERPARTY',
          lens: 'J3',
          severity: 'P1',
          title: 'Seller GET chat_uploads do comprador (fora de order_proofs)',
          pre: 'counterparty policy não cobre chat_uploads',
          repro: 'GET fleaber_private/chat_uploads/{buyer}/…',
          proven: true,
          evidence: g,
        ));
      }
      if (who == 'anon' && !path.contains('product_photos')) {
        c.addFinding(finding(
          id: '$prefix-J3-GET-ANON',
          lens: 'J3',
          severity: 'P0',
          title: 'anon GET fleaber_private',
          pre: path,
          repro: 'GET sem JWT',
          proven: true,
          evidence: g,
        ));
      }
    }
  }

  // seller lists other buyers' chat_uploads (UUID 4b343994 from reviews)
  const other = '4b343994-0b66-488e-a470-b7594f51cffb';
  final listOther = await c.req(
    'POST',
    '/storage/v1/object/list/fleaber_private',
    jwt: c.sellerJwt,
    body: {'prefix': 'chat_uploads/$other/', 'limit': 10},
  );
  c.note('list.other_buyer_uploads', {
    'http': listOther.status,
    'n': listOther.list.length,
    'body': listOther.snippet,
  });

  final listB2asSeller = await c.req(
    'POST',
    '/storage/v1/object/list/fleaber_private',
    jwt: c.sellerJwt,
    body: {
      'prefix': 'chat_uploads/f8859e23-504b-4c85-8a51-aeb04a9e95a0/',
      'limit': 10,
    },
  );
  c.note('list.b2_uploads_as_seller', {
    'http': listB2asSeller.status,
    'n': listB2asSeller.list.length,
    'body': listB2asSeller.snippet,
  });
  if (listB2asSeller.ok && listB2asSeller.list.isNotEmpty) {
    c.addFinding(finding(
      id: '$prefix-J3-LIST-STRANGER-UPLOADS',
      lens: 'J3',
      severity: 'P1',
      title: 'Seller lista chat_uploads de buyer2 (sem encomenda partilhada)',
      pre: 'buyer2 lab sem orders com seller',
      repro: 'POST object/list prefix=chat_uploads/{b2}/',
      proven: true,
      evidence: {
        'n': listB2asSeller.list.length,
        'names': listB2asSeller.list
            .whereType<Map>()
            .map((e) => e['name'])
            .toList(),
      },
    ));
  }

  await dumpJson('${Directory.current.path}/out/pass4.json', {
    'prefix': prefix,
    'notes': c.notes,
    'findings': c.findings,
  });
  stdout.writeln('pass4 findings=${c.findings.length}');
  for (final f in c.findings) {
    stdout.writeln('  ${f['severity']} ${f['id']} ${f['title']}');
  }
}
