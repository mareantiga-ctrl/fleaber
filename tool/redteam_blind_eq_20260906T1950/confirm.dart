/// Confirma HOLDs EQ — sem corrigir. Staging only.
/// Oráculos: proof_ok sem query, LIST/GET loot, persist photos/label, C1 dedicado, D1 cs_.
import 'dart:convert';
import 'dart:io';
import '_rteq.dart';

void main() async {
  final c = Rteq.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  const oid = 'aa3fcf49-9842-42b8-ad62-b08ba5dc13f4';
  const did = '4a6daf49-e1ec-408b-8ec8-a65013629663';
  const b5oid = 'b04dbd78-24bb-4b0b-938c-add5544e4c2a';
  const b5did = '59b561c2-f373-433d-99c5-a02d43e87442';
  const alienOid = '00000000-0000-0000-0000-00000000eq02';
  const relOid = '50697911-7f48-4cbb-a34e-fc61aa7ceff4';
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;

  Future<HttpHit> canon(String url) =>
      c.rpc('batata_storage_url_path_canonical', {'p_url': url}, service: true);
  Future<HttpHit> ok(String url, {String? buyer, String? order}) => c.rpc(
        'batata_dispute_proof_url_ok',
        {
          'p_url': url,
          'p_buyer': buyer ?? b1,
          'p_oid': order ?? oid,
        },
        service: true,
      );

  String stripQuery(String u) {
    final i = u.indexOf('?');
    return i < 0 ? u : u.substring(0, i);
  }

  final mineNoq =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/$b1/$oid/ok.png';

  final out = <String, Object?>{};
  out['actors'] = {'b1': b1, 'b2': b2, 's2': c.seller2Id};

  // ----- A2 literal ../ key: loot? -----
  const a2Key =
      'order_disputes/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/../20e2ec8a-0012-4278-b222-9e8a48e463e4/rteq-enc.png';
  final a2GetB1 = await c.storageGet(a2Key, jwt: c.buyerJwt);
  final a2GetB2 = await c.storageGet(a2Key, jwt: c.buyer2Jwt);
  final a2NormB2asB1 = await c.storageGet(
    'order_disputes/$b2/rteq-enc.png',
    jwt: c.buyerJwt,
  );
  final a2ListB1dot = await c.storageList(
    prefix: 'order_disputes/$b1/../',
    jwt: c.buyerJwt,
  );
  final a2ListB2 = await c.storageList(
    prefix: 'order_disputes/$b2/',
    jwt: c.buyerJwt,
  );
  final a2ListB2own = await c.storageList(
    prefix: 'order_disputes/$b2/',
    jwt: c.buyer2Jwt,
  );
  final a2Url =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$a2Key';
  out['a2_literal'] = {
    'getB1': a2GetB1.brief,
    'getB2': a2GetB2.brief,
    'getNormB2asB1': a2NormB2asB1.brief,
    'listB1dot_n': a2ListB1dot.list.length,
    'listB2asB1_n': a2ListB2.list.length,
    'listB2own_n': a2ListB2own.list.length,
    'listB2own_has_enc': a2ListB2own.list.any((e) =>
        e is Map && '${e['name']}${e['id']}'.contains('rteq-enc')),
    'proof_ok': (await ok(a2Url)).body,
    'canon': (await canon(a2Url)).body,
    'loot': a2NormB2asB1.status == 200 && !a2NormB2asB1.body.contains('NoSuchKey'),
  };

  // ----- A2b / A2c unicode SEM query -----
  const fw = '\uFF0F';
  const big = '\u29F8';
  final a2bNoq = '$mineNoq${fw}order_disputes/$b2/$alienOid/rteq-secret.png';
  final a2cNoq = '$mineNoq${big}order_disputes/$b2/$alienOid/rteq-secret.png';
  out['a2b_noq'] = {
    'url': a2bNoq,
    'canon': (await canon(a2bNoq)).body,
    'proof_ok': (await ok(a2bNoq)).body,
  };
  out['a2c_noq'] = {
    'url': a2cNoq,
    'canon': (await canon(a2cNoq)).body,
    'proof_ok': (await ok(a2cNoq)).body,
  };
  final a2bPatch = await c.patchDispute(did, {'return_label_url': a2bNoq});
  final a2bRow = await c.disputeRow(did);
  out['a2b_persist'] = {
    'hit': a2bPatch.brief,
    'stored': a2bRow?['return_label_url'],
    'kept_fw': '${a2bRow?['return_label_url']}'.contains(fw),
    'kept_alien': '${a2bRow?['return_label_url']}'.contains(alienOid),
  };
  final a2cPhotos = await c.patchDispute(did, {
    'proof_photos': [a2cNoq],
  });
  final a2cRow = await c.disputeRow(did);
  out['a2c_persist'] = {
    'hit': a2cPhotos.brief,
    'photos': a2cRow?['proof_photos'],
    'kept_big': '${a2cRow?['proof_photos']}'.contains(big),
    'kept_alien': '${a2cRow?['proof_photos']}'.contains(alienOid),
  };

  // ----- A5 retest -----
  final alienKey = 'order_disputes/$b2/$alienOid/rteq-secret.png';
  final a5GetB1 = await c.storageGet(alienKey, jwt: c.buyerJwt);
  final a5GetB2 = await c.storageGet(alienKey, jwt: c.buyer2Jwt);
  final a5Signed = await c.signObject(alienKey, jwt: c.buyer2Jwt);
  final a5Url = a5Signed == null ? null : stripQuery(a5Signed);
  out['a5'] = {
    'getB1': a5GetB1.brief,
    'getB2own': a5GetB2.brief,
    'signed_stripped': a5Url,
    'proof_ok_noq': a5Url == null ? 'no_sign' : (await ok(a5Url)).body,
  };

  // ----- A7 graphql -----
  final gql = await c.req('POST', '/graphql/v1', jwt: c.buyerJwt, body: {
    'query':
        'query { batata_private_object_revokedCollection { edges { node { object_path } } } }',
  });
  out['a7'] = {
    'status': gql.status,
    'body': clip(gql.body, 240),
    'leak': gql.body.contains('object_path') && !gql.body.contains('errors'),
  };

  // ----- A8 object B2 + registry -----
  final travPath =
      'order_disputes/$b1/../$b2/$alienOid/rteq-secret.png';
  final a8GetB2 = await c.storageGet(alienKey, jwt: c.buyer2Jwt);
  final a8GetB1 = await c.storageGet(alienKey, jwt: c.buyerJwt);
  final revTrav = await c.rest(
    'GET',
    'batata_private_object_revoked?object_path=eq.${Uri.encodeQueryComponent(travPath)}&select=object_path,revoked_by',
    service: true,
  );
  final revReal = await c.rest(
    'GET',
    'batata_private_object_revoked?object_path=eq.$alienKey&select=object_path',
    service: true,
  );
  out['a8'] = {
    'getB2own': a8GetB2.brief,
    'getB1alien': a8GetB1.brief,
    'rev_trav_n': revTrav.list.length,
    'rev_real_n': revReal.list.length,
    'object_intact': a8GetB2.status == 200 &&
        (a8GetB2.body.contains('PNG') || a8GetB2.body.length >= 70),
    'proof_ok_b2_as_b1': (await ok(
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$alienKey',
    )).body,
  };

  // ----- B3 sticky -----
  final b3Canon =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/$b1/$oid/reup.png';
  out['b3'] = {'proof_ok': (await ok(b3Canon)).body};

  // ----- B4 persist -----
  final b4Row = await c.disputeRow(did);
  out['b4'] = {
    'photos': b4Row?['proof_photos'],
    'label': b4Row?['return_label_url'],
    'has_alien': '${b4Row?['proof_photos']}${b4Row?['return_label_url']}'
        .contains(alienOid),
  };

  // ----- B4b query token persist -----
  final tokenTrick =
      '$mineNoq?token=deadbeef&x=../$b2/$alienOid/x.png';
  out['b4b'] = {
    'canon': (await canon(tokenTrick)).body,
    'proof_ok': (await ok(tokenTrick)).body,
    'kept_alien': '${b4Row?['proof_photos']}'.contains(alienOid),
  };

  // ----- B5 reply + photos snapshot -----
  final b5Row = await c.disputeRow(b5did);
  final b5Replies = await c.rest(
    'GET',
    'order_dispute_replies?dispute_id=eq.$b5did&select=id,proof_photos,message,created_at',
    service: true,
  );
  final b5Canon =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/$b1/$b5oid/mid.png';
  out['b5'] = {
    'proof_ok': (await ok(b5Canon, order: b5oid)).body,
    'photos': b5Row?['proof_photos'],
    'replies_n': b5Replies.list.length,
    'replies': b5Replies.list
        .map((e) => e is Map ? {'id': e['id'], 'photos': e['proof_photos']} : e)
        .toList(),
  };

  // ----- C1 dedicated paid order, B2 disputes B1 -----
  final c1pay = await c.payToPago(lens: 'EQ6', initialQty: 1);
  Map<String, Object?> c1out = {'paid': c1pay == null ? 'fail' : c1pay.oid};
  if (c1pay != null) {
    await c.toEnviado(c1pay.oid);
    await c.toConcluido(c1pay.oid);
    final hit = await c.insertDispute(
      orderId: c1pay.oid,
      jwt: c.buyer2Jwt,
      buyer: b2,
    );
    c1out = {
      'oid': c1pay.oid,
      'hit': hit.brief,
      'id': hit.firstId,
      'status': (await c.orderRow(c1pay.oid))?['status'],
      'buyer': (await c.orderRow(c1pay.oid))?['buyer_id'],
    };
  }
  out['c1_dedicated'] = c1out;

  // ----- C4 1 efeito -----
  final relRow = await c.orderRow(relOid);
  final relDisp = await c.rest(
    'GET',
    'order_disputes?order_id=eq.$relOid&select=id,status,buyer_id',
    service: true,
  );
  out['c4'] = {
    'status': relRow?['status'],
    'released_at': relRow?['wallet_release_processed_at'],
    'refund_id': relRow?['stripe_refund_id'],
    'disputes_n': relDisp.list.length,
    'disputes': relDisp.list,
    'two_effects': relRow?['wallet_release_processed_at'] != null &&
        relDisp.list.any((e) => e is Map && '${e['status']}' == 'aberta'),
  };

  // ----- D1 retry checkout then PATCH -----
  final d1sku = await c.createProduct(title: '$prefix-d1c', qty: 2);
  String? d1oid;
  if (d1sku != null) {
    d1oid = await c.insertOrder(
      productId: d1sku,
      jwt: c.buyerJwt,
      shipping: 'entrega em mão',
    );
  }
  HttpHit d1cs = HttpHit(0, 'no_oid', null);
  HttpHit d1patch = HttpHit(0, 'no_oid', null);
  Map<String, dynamic>? d1b;
  Map<String, dynamic>? d1a;
  if (d1oid != null) {
    d1cs = await c.checkout(
      orderId: d1oid,
      productId: d1sku,
      amount: 590,
      shipping: 'mao',
    );
    d1b = await c.orderRow(d1oid);
    d1patch = await c.patchOrder(d1oid, {'shipping_method': 'ctt'});
    d1a = await c.orderRow(d1oid);
  }
  out['d1'] = {
    'cs': d1cs.brief,
    'sid': d1cs.sessionId,
    'before': d1b?['shipping_method'],
    'after': d1a?['shipping_method'],
    'cs_id_col': d1a?['stripe_checkout_session_id'],
    'changed': '${d1a?['shipping_method']}'.toLowerCase().contains('ctt') &&
        '${d1a?['shipping_method']}' != '${d1b?['shipping_method']}',
  };

  await dumpJson('${outDir()}/confirm.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
