// ignore_for_file: avoid_print
/// Reauditoria FASE 3B — probes JWT/anon independentes. Sem nuke. Sem payout real.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

late String url;
late String anon;
late String buyerId;
late String sellerId;

void main() async {
  final env = loadLiveOpsStagingEnv();
  url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  final client = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: 'unused',
  );

  final buyerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  print('auth buyer_ok seller_ok buyer=$buyerId');

  await _f01(buyerJwt, sellerJwt);
  await _f02(buyerJwt, sellerJwt);
  await _f04(buyerJwt, sellerJwt);
  await _f05(buyerJwt);
  print('PROBE_DONE');
}

Map<String, String> h(String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Map<String, String> get anonH => {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
    };

void out(String id, int status, String note, {String? body}) {
  var snippet = (body ?? '').replaceAll('\n', ' ');
  if (snippet.length > 240) snippet = snippet.substring(0, 240);
  print('R $id status=$status $note body=$snippet');
}

Future<http.Response> rpc(
  String fn,
  String jwt,
  Map<String, dynamic> params,
) =>
    http.post(
      Uri.parse('$url/rest/v1/rpc/$fn'),
      headers: h(jwt),
      body: jsonEncode(params),
    );

Future<http.Response> edge(
  String fn,
  String jwt,
  Object body,
) =>
    http.post(
      Uri.parse('$url/functions/v1/$fn'),
      headers: h(jwt),
      body: jsonEncode(body),
    );

Future<void> _f01(String buyerJwt, String sellerJwt) async {
  // Original attack: pending 50 + checkout tip_id + 1€
  final pending50 = await rpc('batata_create_live_tip_pending', buyerJwt, {
    'p_live_id': null,
    'p_seller_id': sellerId,
    'p_amount': 50,
    'p_message': 'reaudit_fase3b_do_not_pay',
  });
  out('F01_PENDING_50', pending50.statusCode, 'create pending 50',
      body: pending50.body);

  String? tip50;
  try {
    final d = jsonDecode(pending50.body);
    if (d is String) tip50 = d;
  } catch (_) {
    final t = pending50.body.replaceAll('"', '').trim();
    if (t.length == 36) tip50 = t;
  }

  if (tip50 != null) {
    final attack = await edge('create-live-tip-checkout', buyerJwt, {
      'tip_id': tip50,
      'seller_id': sellerId,
      'amount_eur': 1,
    });
    out('F01_ATTACK_TIPID_50_PAY_1', attack.statusCode,
        'original payB creditA', body: attack.body);

    final otherSeller = await edge('create-live-tip-checkout', buyerJwt, {
      'tip_id': tip50,
      'seller_id': buyerId,
      'amount_eur': 50,
    });
    out('F01_TIPID_SELLER_MISMATCH', otherSeller.statusCode, 'seller mismatch',
        body: otherSeller.body);

    final asSeller = await edge('create-live-tip-checkout', sellerJwt, {
      'tip_id': tip50,
      'seller_id': sellerId,
      'amount_eur': 1,
    });
    out('F01_TIPID_OTHER_BUYER', asSeller.statusCode, 'seller uses buyer tip',
        body: asSeller.body);

    final patchAmt = await http.patch(
      Uri.parse('$url/rest/v1/live_tips?id=eq.$tip50'),
      headers: h(buyerJwt),
      body: jsonEncode({'amount': 1, 'seller_amount': 50}),
    );
    out('F01_PATCH_TIP_AMOUNT', patchAmt.statusCode, 'client mutate tip',
        body: patchAmt.body);

    final settle2 = await rpc('batata_settle_live_tip_from_stripe', buyerJwt, {
      'p_tip_id': tip50,
      'p_stripe_session_id': 'cs_test_fake',
    });
    out('F01_SETTLE_2ARG_JWT', settle2.statusCode, 'old 2-arg settle',
        body: settle2.body);

    final settle3 = await rpc('batata_settle_live_tip_from_stripe', buyerJwt, {
      'p_tip_id': tip50,
      'p_stripe_session_id': 'cs_test_fake',
      'p_paid_amount_cents': 100,
    });
    out('F01_SETTLE_3ARG_JWT', settle3.statusCode, '3-arg as user',
        body: settle3.body);
  }

  final pending99999 = await rpc('batata_create_live_tip_pending', buyerJwt, {
    'p_live_id': null,
    'p_seller_id': sellerId,
    'p_amount': 99999,
    'p_message': 'reaudit_cap',
  });
  out('F01_PENDING_99999', pending99999.statusCode, 'rpc cap',
      body: pending99999.body);

  // Legitimate path: no tip_id, 1€ — creates matching session (do not pay)
  final legit = await edge('create-live-tip-checkout', buyerJwt, {
    'seller_id': sellerId,
    'amount_eur': 1,
  });
  out('F01_LEGIT_1EUR', legit.statusCode, 'legit checkout no tip_id',
      body: legit.body);

  String? legitTip;
  String? sessionA;
  try {
    final m = jsonDecode(legit.body);
    if (m is Map) {
      legitTip = m['tipId']?.toString();
      sessionA = m['checkoutSessionId']?.toString();
    }
  } catch (_) {}

  if (legitTip != null) {
    final second = await edge('create-live-tip-checkout', buyerJwt, {
      'tip_id': legitTip,
      'seller_id': sellerId,
      'amount_eur': 1,
    });
    out('F01_REUSE_LEGIT_TIPID', second.statusCode, 'reuse bound tip_id',
        body: second.body);

    final doubleCheckout = await edge('create-live-tip-checkout', buyerJwt, {
      'seller_id': sellerId,
      'amount_eur': 1,
    });
    out('F01_SECOND_LEGIT_SESSION', doubleCheckout.statusCode,
        'second distinct 1eur tip', body: doubleCheckout.body);
  }

  if (sessionA != null) {
    final getSettle = await http.get(
      Uri.parse(
        '$url/functions/v1/create-live-tip-checkout?checkout_return=success&session_id=$sessionA',
      ),
      headers: {'apikey': anon},
    );
    out('F01_GET_SETTLE_UNPAID', getSettle.statusCode, 'unpaid session settle',
        body: getSettle.body);
  }

  final fakeUuid = '00000000-0000-0000-0000-000000000001';
  final oldTip = await edge('create-live-tip-checkout', buyerJwt, {
    'tip_id': fakeUuid,
    'seller_id': sellerId,
    'amount_eur': 1,
  });
  out('F01_FAKE_TIPID', oldTip.statusCode, 'random tip_id', body: oldTip.body);
}

Future<void> _f02(String buyerJwt, String sellerJwt) async {
  Future<void> listBucket(
    String id,
    String bucket,
    String prefix,
    Map<String, String> headers,
  ) async {
    final r = await http.post(
      Uri.parse('$url/storage/v1/object/list/$bucket'),
      headers: headers,
      body: jsonEncode({'prefix': prefix, 'limit': 5, 'offset': 0}),
    );
    out(id, r.statusCode, 'list $bucket/$prefix', body: r.body);
  }

  await listBucket('F02_ANON_LIST_PROOFS_CHAT', 'chat_media', 'order_proofs/', anonH);
  await listBucket('F02_ANON_LIST_DISPUTES_CHAT', 'chat_media', 'order_disputes/', anonH);
  await listBucket('F02_ANON_LIST_PRIVATE_PROOFS', 'fleaber_private', 'order_proofs/', anonH);
  await listBucket('F02_ANON_LIST_CHAT_ROOT', 'chat_media', '', anonH);
  await listBucket('F02_ANON_LIST_PRODUCT', 'chat_media', 'product_photos/', anonH);

  final legacyGet = await http.get(
    Uri.parse(
      '$url/storage/v1/object/public/chat_media/order_proofs/1778673939223_1000000036.jpg',
    ),
  );
  out('F02_ANON_GET_LEGACY_PROOF', legacyGet.statusCode,
      'legacy public GET', body: 'len=${legacyGet.body.length} ct=${legacyGet.headers['content-type']}');

  final productGet = await http.get(
    Uri.parse('$url/storage/v1/object/list/chat_media'),
    headers: anonH,
  );
  // already listed

  final hijackProduct = await http.post(
    Uri.parse(
      '$url/storage/v1/object/chat_media/product_photos/$sellerId/reaudit_fase3b.txt',
    ),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'text/plain',
    },
    body: 'hijack',
  );
  out('F02_CROSS_PRODUCT_PHOTOS', hijackProduct.statusCode,
      'buyer -> seller product_photos', body: hijackProduct.body);

  final hijackPrivate = await http.post(
    Uri.parse(
      '$url/storage/v1/object/fleaber_private/order_proofs/$sellerId/reaudit.txt',
    ),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'text/plain',
    },
    body: 'hijack-private',
  );
  out('F02_CROSS_PRIVATE_PROOF', hijackPrivate.statusCode,
      'buyer upload seller private namespace', body: hijackPrivate.body);

  final oldProofInsert = await http.post(
    Uri.parse(
      '$url/storage/v1/object/chat_media/order_proofs/reaudit_unowned.txt',
    ),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'text/plain',
    },
    body: 'should-fail',
  );
  out('F02_NEW_PROOF_ON_PUBLIC_BUCKET', oldProofInsert.statusCode,
      'new order_proofs on chat_media', body: oldProofInsert.body);

  final ownPrivate = await http.post(
    Uri.parse(
      '$url/storage/v1/object/fleaber_private/order_proofs/$buyerId/reaudit_${DateTime.now().millisecondsSinceEpoch}.txt',
    ),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'text/plain',
      'x-upsert': 'true',
    },
    body: 'legit-private-proof',
  );
  out('F02_LEGIT_PRIVATE_UPLOAD', ownPrivate.statusCode, 'own private proof',
      body: ownPrivate.body);

  String? privatePath;
  try {
    final m = jsonDecode(ownPrivate.body);
    if (m is Map && m['Key'] != null) {
      privatePath = m['Key'].toString().replaceFirst('fleaber_private/', '');
    }
  } catch (_) {}

  if (privatePath != null) {
    final pub = await http.get(
      Uri.parse('$url/storage/v1/object/public/fleaber_private/$privatePath'),
    );
    out('F02_ANON_GET_NEW_PRIVATE', pub.statusCode, 'public GET new proof',
        body: 'len=${pub.body.length}');

    final signed = await http.post(
      Uri.parse('$url/storage/v1/object/sign/fleaber_private/$privatePath'),
      headers: h(buyerJwt),
      body: jsonEncode({'expiresIn': 60}),
    );
    out('F02_SIGNED_URL', signed.statusCode, 'owner signed url',
        body: signed.body);

    String? token;
    try {
      final m = jsonDecode(signed.body);
      token = (m is Map ? m['signedURL'] ?? m['signedUrl'] : null)?.toString();
    } catch (_) {}
    if (token != null && token.isNotEmpty) {
      final abs = token.startsWith('http')
          ? token
          : '$url/storage/v1${token.startsWith('/') ? token : '/$token'}';
      final got = await http.get(Uri.parse(abs));
      out('F02_SIGNED_FETCH', got.statusCode, 'fetch signed',
          body: 'len=${got.body.length}');
    }

    final sellerGet = await http.get(
      Uri.parse('$url/storage/v1/object/authenticated/fleaber_private/$privatePath'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $sellerJwt',
      },
    );
    out('F02_SELLER_GET_BUYER_PROOF', sellerGet.statusCode,
        'seller read buyer private proof', body: 'len=${sellerGet.body.length}');
  }

  final ownProduct = await http.post(
    Uri.parse(
      '$url/storage/v1/object/chat_media/product_photos/$buyerId/reaudit_ok.txt',
    ),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'text/plain',
      'x-upsert': 'true',
    },
    body: 'catalog-ok',
  );
  out('F02_LEGIT_PRODUCT_PHOTO', ownProduct.statusCode, 'own product_photos',
      body: ownProduct.body);

  if (ownProduct.statusCode < 300) {
    final cat = await http.get(
      Uri.parse(
        '$url/storage/v1/object/public/chat_media/product_photos/$buyerId/reaudit_ok.txt',
      ),
    );
    out('F02_PUBLIC_CATALOG_GET', cat.statusCode, 'catalog still public',
        body: 'len=${cat.body.length}');
  }

  final ownChat = await http.post(
    Uri.parse(
      '$url/storage/v1/object/chat_media/chat_uploads/$buyerId/reaudit.txt',
    ),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'text/plain',
      'x-upsert': 'true',
    },
    body: 'chat-ok',
  );
  out('F02_LEGIT_CHAT_UPLOAD', ownChat.statusCode, 'own chat_uploads',
      body: ownChat.body);

  final disputeChat = await http.post(
    Uri.parse(
      '$url/storage/v1/object/chat_media/order_disputes/$buyerId/x.jpg',
    ),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'text/plain',
    },
    body: 'nope',
  );
  out('F02_DISPUTE_ON_CHAT_MEDIA', disputeChat.statusCode,
      'dispute on public bucket', body: disputeChat.body);
}

Future<void> _f04(String buyerJwt, String sellerJwt) async {
  final noKey = await edge('create-connect-account', sellerJwt, {
    'user_id': sellerId,
    'amount': 100,
  });
  out('F04_PAYOUT_NO_KEY', noKey.statusCode, 'missing idempotency_key',
      body: noKey.body);

  final shortKey = await edge('create-connect-account', sellerJwt, {
    'user_id': sellerId,
    'amount': 100,
    'idempotency_key': 'short',
  });
  out('F04_PAYOUT_SHORT_KEY', shortKey.statusCode, 'key < 8',
      body: shortKey.body);

  final buyerPayout = await edge('create-connect-account', buyerJwt, {
    'user_id': buyerId,
    'amount': 100,
    'idempotency_key': 'wd_test_reaudit_should_not_transfer',
  });
  out('F04_PAYOUT_BUYER_WITH_KEY', buyerPayout.statusCode,
      'buyer keyed payout (expect connect/saldo fail, not missing key)',
      body: buyerPayout.body);
}

Future<void> _f05(String buyerJwt) async {
  final nuke = await edge('delete-test-account', buyerJwt, {
    'confirm': 'APAGAR TUDO',
  });
  out('F05_NUKE_BUYER', nuke.statusCode,
      'non-destructive expect deny (allowlist)', body: nuke.body);

  final noPhrase = await edge('delete-test-account', buyerJwt, {
    'confirm': 'nao',
  });
  out('F05_NUKE_BAD_PHRASE', noPhrase.statusCode, 'bad phrase',
      body: noPhrase.body);
}
