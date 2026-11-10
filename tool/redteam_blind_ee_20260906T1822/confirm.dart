/// Confirm P1 B5 6∥4, P1 D4 expand, C3 wallet vs release∥disputa, C4 revoke mid-disputa.
/// Staging only. NÃO corrigir.
import 'dart:io';
import '_rtee.dart';
const pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

Future<void> main() async {
  final c = Rtee.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer3();
  final s1 = c.sellerId!;
  final b3 = c.buyer3Id!;
  final out = <String, Object?>{};

  out['c3_hist'] = await confirmC3(c);
  out['c4'] = await confirmC4(c, s1);
  out['b5'] = await confirmB5(c, s1, b3);
  out['d4'] = await confirmD4(c, s1, b3);

  await c.endAllCreatedLives();
  await c.restoreSeller1Published();
  await dumpJson('${outDir()}/confirm.json', out);
  stdout.writeln('WROTE confirm.json');
}

Future<Map<String, Object?>> confirmC3(Rtee c) async {
  const oid = '29639022-818e-4b96-bc98-3967bc714674';
  final ord = await c.orderRow(oid);
  final txn = await c.rest(
    'GET',
    'wallet_transactions?order_id=eq.$oid&select=id,wallet_id,amount,type,description,order_id,created_at&order=created_at.desc&limit=8',
    service: true,
  );
  final disp = await c.rest(
    'GET',
    'order_disputes?order_id=eq.$oid&select=id,status,created_at&limit=5',
    service: true,
  );
  final w = await c.walletRow(c.sellerId);
  stdout.writeln('C3 hist status=${ord?['status']} rel_at=${ord?['wallet_release_processed_at']} '
      'txn=${txn.list.length} disp=${disp.list.length} w=${w?['balance']}');
  return {
    'ord': {
      'status': ord?['status'],
      'release_at': ord?['wallet_release_processed_at'],
      'refund_at': ord?['wallet_refund_processed_at'],
    },
    'txn': txn.brief,
    'disp': disp.brief,
    'wallet': w?['balance'],
  };
}

Future<Map<String, Object?>> confirmC4(Rtee c, String s1) async {
  final paid = await c.payToPago(lens: 'EE3', initialQty: 1);
  if (paid == null) return {'skip': 'paid fail'};
  await c.plantConcluidoMao(paid.oid);
  final path = c.disputeObj(c.buyerId!, paid.oid, 'mid2.png');
  final up = await c.storageUpload(
    objectName: path,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final signed = await c.signObject(path, jwt: c.buyerJwt);
  final noQ =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$path';
  final disp = await c.insertDispute(
    orderId: paid.oid,
    photos: [(signed ?? noQ)],
  );
  final del = await c.storageDelete(path, jwt: c.buyerJwt);
  final rev = await c.revokePath(path, jwt: c.buyerJwt);
  final ok = await c.proofOk(noQ, service: true, buyer: c.buyerId, oid: paid.oid);
  HttpHit? reply;
  if (disp.firstId != null) {
    reply = await c.insertReply(
      disputeId: disp.firstId!,
      photos: [noQ],
      message: 'RTEE C4 confirm UI',
    );
  }
  stdout.writeln(
      'C4 up=${up.status} disp=${disp.status} rev=${rev.body} ok=${ok.body} reply=${reply?.status}');
  return {
    'up': up.brief,
    'disp': disp.brief,
    'del': del.brief,
    'rev': rev.body,
    'proof_ok': ok.body,
    'reply': reply?.brief,
    'pi': paid.pi,
  };
}

Future<Map<String, Object?>> confirmB5(Rtee c, String s1, String b3) async {
  final skus = <String>[];
  final oids = <String>[];
  for (var i = 0; i < 6; i++) {
    final pid = await c.createProduct(
      title: '$prefix p2-b5-$i',
      qty: 2,
      listed: true,
      live: false,
    );
    if (pid == null) continue;
    skus.add(pid);
    final oid = await c.insertOrder(
      productId: pid,
      jwt: c.buyer3Jwt,
      buyer: b3,
      price: 12.0,
    );
    if (oid != null) oids.add(oid);
  }
  List<Map<String, Object?>> lines(List<int> idx) => [
        for (final i in idx)
          if (i < oids.length && i < skus.length)
            {
              'order_id': oids[i],
              'product_id': skus[i],
              'quantity': 1,
              'price': 12.0,
            },
      ];
  if (oids.length < 6) return {'skip': 'oids ${oids.length}'};
  final raced = await Future.wait([
    c.checkoutBag(
        lines: lines([0, 1, 2, 3, 4, 5]),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1),
    c.checkoutBag(
        lines: lines([1, 2, 3, 4]),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1),
  ]);
  final sids = raced
      .map((h) => h.sessionId ?? '')
      .where((s) => s.startsWith('cs_'))
      .toSet();
  final stored = <String>[];
  for (final oid in oids) {
    stored.add('${(await c.orderRow(oid))?['stripe_checkout_session_id'] ?? ''}');
  }
  stdout.writeln('B5 confirm cs=${sids.length} $sids stored=$stored');
  return {
    'http': raced.map((h) => h.brief).toList(),
    'sids': sids.toList(),
    'cs_n': sids.length,
    'ledger': stored,
    'reused': raced.map((h) => h.reused).toList(),
  };
}

Future<Map<String, Object?>> confirmD4(Rtee c, String s1, String b3) async {
  final skus = <String>[];
  final oids = <String>[];
  for (var i = 0; i < 4; i++) {
    final pid = await c.createProduct(
      title: '$prefix p2-d4-$i',
      qty: 2,
      listed: true,
      live: false,
    );
    if (pid == null) continue;
    skus.add(pid);
    final oid = await c.insertOrder(
      productId: pid,
      jwt: c.buyer3Jwt,
      buyer: b3,
      price: 14.0,
    );
    if (oid != null) oids.add(oid);
  }
  List<Map<String, Object?>> lines(List<int> idx) => [
        for (final i in idx)
          if (i < oids.length && i < skus.length)
            {
              'order_id': oids[i],
              'product_id': skus[i],
              'quantity': 1,
              'price': 14.0,
            },
      ];
  if (oids.length < 4) return {'skip': 'oids ${oids.length}'};
  final raced = await Future.wait([
    c.checkoutBag(
        lines: lines([0, 1]), jwt: c.buyer3Jwt, buyer: b3, seller: s1),
    Future(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c.checkoutBag(
          lines: lines([0, 1, 2, 3]),
          jwt: c.buyer3Jwt,
          buyer: b3,
          seller: s1);
    }),
  ]);
  final sids = raced
      .map((h) => h.sessionId ?? '')
      .where((s) => s.startsWith('cs_'))
      .toSet();
  final stored = <String>[];
  for (final oid in oids) {
    stored.add('${(await c.orderRow(oid))?['stripe_checkout_session_id'] ?? ''}');
  }
  stdout.writeln('D4 confirm cs=${sids.length} $sids stored=$stored');
  return {
    'http': raced.map((h) => h.brief).toList(),
    'sids': sids.toList(),
    'cs_n': sids.length,
    'ledger': stored,
    'reused': raced.map((h) => h.reused).toList(),
  };
}
