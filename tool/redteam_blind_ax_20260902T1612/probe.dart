/// PASS 1 — AX payout/wallet/refund pós-ANAS. Hash / JWT / Connect. Não corrige.
import 'dart:io';
import '_rtax.dart';

Future<void> main() async {
  final c = Rtax.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final top = await c.ensureMinBalance(c.sellerId, 20);
  c.note('fixture.balance', 'service_role top-up seller ≥20€ (saldo estava 0)',
      top.brief,
      lens: 'AX1');

  final w0 = await c.wallets();
  final sellerW = await c.walletRow(c.sellerId);
  c.note('snap.wallets', 'saldos iniciais', w0, lens: 'AX7');
  c.note('snap.seller.acct', 'Connect seller', sellerW?['stripe_account_id'],
      lens: 'AX2');

  // ---------------------------------------------------------------------------
  // AX1 — JWT RPCs money + auto_feedback cron
  // ---------------------------------------------------------------------------
  final moneyRpcs = <String, Map<String, Object?>>{
    'batata_wallet_payout_debit': {
      'p_user_id': c.sellerId,
      'p_amount_cents': 100,
      'p_idempotency_key': '${prefix}_jwt_debit',
    },
    'batata_wallet_payout_finish': {
      'p_idempotency_key': '${prefix}_jwt_debit',
      'p_stripe_transfer_id': 'tr_fake_ax',
      'p_failed': false,
    },
    'batata_clawback_seller_wallet_for_order': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_credit_wallet_once': {
      'p_wallet_id': c.buyerId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 9.99,
      'p_type': 'reembolso',
      'p_description': prefix,
    },
    'batata_refund_buyer_wallet_for_order': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_finalize_stripe_order_refund': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_refund_id': 're_fake_ax',
      'p_amount_cents': 99999,
    },
    'batata_process_partial_refund_dispute': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_refund_percent': 200,
    },
    'batata_ensure_wallet': {'p_user_id': c.sellerId},
    'batata_generate_auto_feedback': {
      'p_now': DateTime.now().toUtc().add(const Duration(days: 400)).toIso8601String(),
    },
  };

  for (final e in moneyRpcs.entries) {
    final buyerHit = await c.rpc(e.key, e.value, jwt: c.buyerJwt);
    final sellerHit = await c.rpc(e.key, e.value, jwt: c.sellerJwt);
    c.note('rpc.${e.key}', 'JWT sweep', {
      'buyer': buyerHit.brief,
      'seller': sellerHit.brief,
    }, lens: 'AX1');
    final minted = (!rpcDenied(buyerHit) &&
            buyerHit.ok &&
            (buyerHit.body == 'true' || buyerHit.body.contains('"ok":true'))) ||
        (!rpcDenied(sellerHit) &&
            sellerHit.ok &&
            (sellerHit.body == 'true' || sellerHit.body.contains('"ok":true')));
    if (e.key.contains('payout_debit') ||
        e.key.contains('payout_finish') ||
        e.key.contains('credit_wallet') ||
        e.key.contains('finalize_stripe') ||
        e.key.contains('generate_auto_feedback')) {
      if (minted ||
          (!rpcDenied(buyerHit) &&
              buyerHit.ok &&
              e.key.contains('payout') &&
              buyerHit.body.contains('"ok":true'))) {
        c.hold(
          id: 'AX1-jwt-${e.key}',
          lens: 'AX1',
          severity: e.key.contains('auto_feedback') ? 'P1' : 'P0',
          title: 'JWT executou RPC privilegiado ${e.key}',
          actor: 'buyer JWT',
          pre: 'authenticated, sem service_role',
          repro: 'POST rpc/${e.key}',
          expected: '403 42501',
          obtained: {'b': buyerHit.brief, 's': sellerHit.brief},
        );
      } else {
        c.block('AX1.${e.key}', 'AX1', 'JWT ${e.key}', {
          'buyer': buyerHit.brief,
          'seller': sellerHit.brief,
        });
      }
    }
  }

  final wAfterRpc = await c.wallets();
  final dBuyerRpc = (wAfterRpc['buyer'] ?? 0) - (w0['buyer'] ?? 0);
  final dSellerRpc = (wAfterRpc['seller'] ?? 0) - (w0['seller'] ?? 0);
  if (dBuyerRpc.abs() > 0.009 || dSellerRpc > 0.009) {
    c.hold(
      id: 'AX1-jwt-delta-wallet',
      lens: 'AX1',
      severity: 'P0',
      title: 'Sweep JWT alterou saldo',
      actor: 'JWT',
      pre: 'RPCs money',
      repro: 'POST rpc/*',
      expected: 'Δ 0',
      obtained: {'dBuyer': dBuyerRpc, 'dSeller': dSellerRpc},
    );
  } else {
    c.block('AX1.delta', 'AX1', 'sweep JWT Δwallet 0', {
      'dBuyer': dBuyerRpc,
      'dSeller': dSellerRpc,
    });
  }

  // GraphQL wallets
  final gql = await c.graphql(
    'mutation { updatewalletsCollection(filter: {id:{eq:"${c.sellerId}"}}, set: {balance: 9999.99}) { records { id balance } } }',
    jwt: c.buyerJwt,
  );
  c.note('ax1.graphql', 'GraphQL update wallets', gql.brief, lens: 'AX1');

  // ---------------------------------------------------------------------------
  // AX1 — idempotency HASH (não slice 64 exact AR-P3)
  // short key / replay / 2 users mesma key / prefix-64 agora deve DIVERGIR
  // ---------------------------------------------------------------------------
  final short7 = await c.payout(amountCents: 100, key: 'SHORT07');
  final short8sp = await c.payout(amountCents: 100, key: '       ');
  final shortEmpty = await c.payout(amountCents: 100, key: '');
  final keyNum = await c.edge('create-connect-account', {
    'amount': 100,
    'idempotency_key': 12345678,
  }, jwt: c.sellerJwt);
  final keyArr = await c.edge('create-connect-account', {
    'amount': 100,
    'idempotency_key': ['RTAX1612ARRAYK'],
  }, jwt: c.sellerJwt);
  c.note('ax1.short7', 'key 7 chars', short7.brief, lens: 'AX1');
  c.note('ax1.short.ws', 'key whitespace', short8sp.brief, lens: 'AX1');
  c.note('ax1.short.empty', 'key empty', shortEmpty.brief, lens: 'AX1');
  c.note('ax1.key.num', 'key number', keyNum.brief, lens: 'AX1');
  c.note('ax1.key.arr', 'key array', keyArr.brief, lens: 'AX1');
  for (final e in {
    'short7': short7,
    'ws': short8sp,
    'empty': shortEmpty,
    'num': keyNum,
    'arr': keyArr,
  }.entries) {
    if (e.value.ok && e.value.transferId != null) {
      c.hold(
        id: 'AX1-short-key-${e.key}',
        lens: 'AX1',
        severity: 'P1',
        title: 'Payout com idempotency_key inválida (${e.key}) criou Transfer',
        actor: 'seller JWT',
        pre: 'hash SHA-256; key curta / não-string',
        repro: 'POST create-connect-account idempotency_key=${e.key}',
        expected: '400 key em falta',
        obtained: e.value.brief,
      );
    } else {
      c.block('AX1.key-${e.key}', 'AX1', 'key ${e.key} recusada', e.value);
    }
  }

  // Unicode NFC vs NFD — hashes devem divergir (2 Transfers se saldo cobrir)
  const nfc = 'RTAX1612cafe\u00e9xx'; // café
  const nfd = 'RTAX1612cafe\u0301xx'; // cafe + combining acute
  final uniA = await c.payout(amountCents: 100, key: nfc);
  final uniB = await c.payout(amountCents: 100, key: nfd);
  c.note('ax1.unicode', 'NFC vs NFD', {
    'nfc': uniA.brief,
    'nfd': uniB.brief,
    'sameTid': uniA.transferId != null && uniA.transferId == uniB.transferId,
  }, lens: 'AX1');

  // Prefixo 64 (exact AR-P3 fechado): agora hash → 2 Transfers esperados
  final pad = 'H' * 64;
  final kA = '${pad}alphaAX1';
  final kB = '${pad}betaAX1x';
  final pA = await c.payout(amountCents: 100, key: kA);
  final pB = await c.payout(amountCents: 100, key: kB);
  c.note('ax1.hash.prefix64', 'keys que colidiam no slice 64', {
    'same64raw': kA.substring(0, 64) == kB.substring(0, 64),
    'a': pA.brief,
    'b': pB.brief,
    'sameTid': pA.transferId != null && pA.transferId == pB.transferId,
  }, lens: 'AX1');
  if (pA.ok &&
      pB.ok &&
      pA.transferId != null &&
      pA.transferId == pB.transferId) {
    c.hold(
      id: 'AX1-hash-prefix64-still-collides',
      lens: 'AX1',
      severity: 'P3',
      title: 'SHA-256 ainda funde duas keys com prefixo 64',
      actor: 'seller JWT',
      pre: 'ANAS hash; keys distintas após byte 64',
      repro: '2 POST create-connect-account keys pad64+alpha / pad64+beta',
      expected: '2 Transfer distintos (hash diverge)',
      obtained: {'tid': pA.transferId, 'a': pA.brief, 'b': pB.brief},
    );
  } else {
    c.block('AX1.hash-prefix64', 'AX1', 'hash separa prefixo 64', {
      'a': pA.transferId,
      'b': pB.transferId,
    });
  }

  // 3× mesma key (hash path) — 1 Transfer
  final sameK = '${prefix}_samekey8';
  final trips = await parallel([
    c.payout(amountCents: 100, key: sameK),
    c.payout(amountCents: 100, key: sameK),
    c.payout(amountCents: 100, key: sameK),
  ]);
  final tids = trips.map((h) => h.transferId).whereType<String>().toSet();
  c.note('ax1.replay.same', '3× mesma key hash', {
    'hits': trips.map((h) => h.brief).toList(),
    'uniqueTids': tids.toList(),
  }, lens: 'AX1');
  if (tids.length > 1) {
    c.hold(
      id: 'AX1-same-key-duplicate-transfer',
      lens: 'AX1',
      severity: 'P0',
      title: 'Replay mesma key hash criou Transfers distintos',
      actor: 'seller JWT',
      pre: '3 POST // mesma idempotency_key',
      repro: 'create-connect-account ×3',
      expected: '1 tr_',
      obtained: {'tids': tids.toList(), 'hits': trips.map((h) => h.brief)},
    );
  } else {
    c.block('AX1.replay-same', 'AX1', '3× mesma key → 1 Transfer',
        tids.toList());
  }

  // 2 users mesma raw key
  final shared = '${prefix}_shared8';
  final s1 = await c.payout(amountCents: 100, key: shared, jwt: c.sellerJwt);
  final s2 = await c.payout(amountCents: 100, key: shared, jwt: c.seller2Jwt);
  final b1 = await c.payout(amountCents: 100, key: shared, jwt: c.buyerJwt);
  c.note('ax1.two-users', 'mesma raw key S1/S2/B', {
    's1': s1.brief,
    's2': s2.brief,
    'b1': b1.brief,
    'sameTid': s1.transferId != null && s1.transferId == s2.transferId,
  }, lens: 'AX1');
  if (s2.ok && s2.transferId != null && s2.transferId == s1.transferId) {
    c.hold(
      id: 'AX1-two-users-same-hash',
      lens: 'AX1',
      severity: 'P0',
      title: 'Seller2 herdou Transfer do seller1 com a mesma raw key',
      actor: 'seller2 JWT',
      pre: 'hash inclui userId',
      repro: 'POST mesma idempotency_key',
      expected: 'hash distinto / 400 IBAN / 400 user cruzado',
      obtained: {'s1': s1.brief, 's2': s2.brief},
    );
  } else {
    c.block('AX1.two-users', 'AX1', '2 users mesma key não herda Transfer', {
      's1': s1.status,
      's2': s2.status,
      'b1': b1.status,
    });
  }

  // amount boolean / hex — coerção nova (não "1e2" / array AL/AR)
  final amtTrue = await c.edge('create-connect-account', {
    'amount': true,
    'idempotency_key': '${prefix}_amtrue8',
  }, jwt: c.sellerJwt);
  final amtHex = await c.edge('create-connect-account', {
    'amount': '0x64',
    'idempotency_key': '${prefix}_amhex08',
  }, jwt: c.sellerJwt);
  c.note('ax1.amount.true', 'amount:true', amtTrue.brief, lens: 'AX1');
  c.note('ax1.amount.hex', 'amount:0x64', amtHex.brief, lens: 'AX1');
  if (amtTrue.ok && amtTrue.transferId != null) {
    c.hold(
      id: 'AX1-amount-true',
      lens: 'AX1',
      severity: 'P3',
      title: 'amount:true (boolean) criou Transfer 1¢',
      actor: 'seller JWT',
      pre: 'Number(true)===1',
      repro: 'POST amount=true',
      expected: '400 valor inválido',
      obtained: amtTrue.brief,
    );
  } else {
    c.block('AX1.amount-true', 'AX1', 'amount true recusado', amtTrue);
  }
  if (amtHex.ok && amtHex.transferId != null) {
    c.hold(
      id: 'AX1-amount-hex',
      lens: 'AX1',
      severity: 'P3',
      title: 'amount:"0x64" criou Transfer (coerção hex)',
      actor: 'seller JWT',
      pre: 'Number("0x64")===100 — variante nova vs 1e2 AL',
      repro: 'POST amount="0x64"',
      expected: '400 / cêntimos inteiros decimais',
      obtained: amtHex.brief,
    );
  } else {
    c.block('AX1.amount-hex', 'AX1', 'amount hex recusado', amtHex);
  }

  // JWT debit com key já hashed estilo Edge p_+62hex
  final fakeHash = 'p_${'ab' * 31}';
  final jwtHash = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': c.sellerId,
    'p_amount_cents': 100,
    'p_idempotency_key': fakeHash,
  }, jwt: c.sellerJwt);
  c.note('ax1.jwt.hashed-key', 'JWT debit key p_hex', jwtHash.brief, lens: 'AX1');
  if (!rpcDenied(jwtHash) && jwtHash.ok && jwtHash.body.contains('"ok":true')) {
    c.hold(
      id: 'AX1-jwt-debit-hashed',
      lens: 'AX1',
      severity: 'P0',
      title: 'JWT debitou com key formato hash Edge',
      actor: 'seller JWT',
      pre: 'p_ + 62 hex',
      repro: 'rpc batata_wallet_payout_debit',
      expected: '403',
      obtained: jwtHash.brief,
    );
  } else {
    c.block('AX1.jwt-hashed', 'AX1', 'JWT hashed debit 403', jwtHash);
  }

  // RLS PATCH / INSERT
  final patchBal = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.buyerJwt,
    body: {'balance': 9999.99},
  );
  final insTxn = await c.rest('POST', 'wallet_transactions', jwt: c.buyerJwt, body: {
    'wallet_id': c.buyerId,
    'amount': 50,
    'type': 'reembolso',
    'description': prefix,
  });
  c.note('ax1.patch.balance', 'PATCH wallets.balance', patchBal.brief, lens: 'AX1');
  c.note('ax1.insert.txn', 'INSERT txn', insTxn.brief, lens: 'AX1');
  if (insTxn.ok && insTxn.firstId != null) {
    c.hold(
      id: 'AX1-insert-txn',
      lens: 'AX1',
      severity: 'P0',
      title: 'JWT inseriu wallet_transactions',
      actor: 'buyer JWT',
      pre: 'RLS',
      repro: 'POST wallet_transactions',
      expected: '403',
      obtained: insTxn.brief,
    );
  } else {
    c.block('AX1.insert-txn', 'AX1', 'INSERT txn', insTxn);
  }

  // ---------------------------------------------------------------------------
  // AX2 — Connect hijack variantes novas (não trailing-dot/CRLF/cyrillic AR)
  // ---------------------------------------------------------------------------
  final origins = <String, String>{
    'open-redirect-next': 'https://fleaber.pt/wallet?next=https://evil.com',
    'punycode': 'https://xn--fleaber-9za.pt',
    'backslash': r'https://fleaber.pt\@evil.com',
    'port-evil': 'https://fleaber.pt:443.evil.com',
    'origin-hdr': 'https://fleaber.pt',
  };
  for (final e in origins.entries) {
    final hit = await c.connectGet(
      qs: '?web_return_origin=${Uri.encodeComponent(e.value)}&next=https://evil.com',
      extra: e.key == 'origin-hdr'
          ? {
              'Origin': 'https://evil.com',
              'Referer': 'https://evil.com/phish',
              'X-Original-Host': 'evil.com',
              'Forwarded': 'host=evil.com;proto=https',
            }
          : null,
    );
    final loc = '${hit.location ?? ''} ${hit.body}'.toLowerCase();
    c.note('ax2.get.${e.key}', 'GET Connect ${e.key}', {
      'status': hit.status,
      'location': hit.location,
      'hasEvil': loc.contains('evil.com'),
      'snippet': clip(hit.body, 140),
    }, lens: 'AX2');
    if (loc.contains('evil.com') &&
        (hit.location != null && !hit.location!.contains('fleaber'))) {
      c.hold(
        id: 'AX2-redirect-${e.key}',
        lens: 'AX2',
        severity: 'P1',
        title: 'Connect GET desviou para evil.com (${e.key})',
        actor: 'anon GET',
        pre: 'web_return_origin / Origin hostil',
        repro: 'GET create-connect-account',
        expected: 'sem Location hostil',
        obtained: {'location': hit.location, 'status': hit.status},
      );
    } else {
      c.block('AX2.get-${e.key}', 'AX2', 'origem ${e.key}', hit.status);
    }
  }

  final postEvil = await c.edge(
    'create-connect-account',
    {
      'return_url': 'https://evil.com/cb',
      'refresh_url': 'https://evil.com/re',
      'web_return_origin': 'https://evil.com',
      'account': 'acct_1EVEL11111111111',
      'stripe_account_id': 'acct_1EVEL11111111111',
    },
    jwt: c.sellerJwt,
  );
  c.note('ax2.post.urls', 'POST return_url evil', {
    'brief': postEvil.brief,
    'hasEvil': postEvil.body.toLowerCase().contains('evil.com'),
  }, lens: 'AX2');
  if (postEvil.body.toLowerCase().contains('evil.com') &&
      (postEvil.map?['url']?.toString().contains('evil.com') == true)) {
    c.hold(
      id: 'AX2-post-return-url',
      lens: 'AX2',
      severity: 'P1',
      title: 'AccountLink apontou a evil.com',
      actor: 'seller JWT',
      pre: 'body return_url hostil',
      repro: 'POST create-connect-account',
      expected: 'URL Stripe / fleaber',
      obtained: postEvil.brief,
    );
  } else {
    c.block('AX2.post-urls', 'AX2', 'return_url ignorado', postEvil.status);
  }

  final w1 = await c.wallets();
  c.note('snap.wallets.end1', 'saldos fim pass1', {
    'w0': w0,
    'w1': w1,
    'dBuyer': (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0),
    'dSeller': (w1['seller'] ?? 0) - (w0['seller'] ?? 0),
  }, lens: 'AX7');

  await c.dumpAll('pass1.json');
  stdout.writeln(
      'PASS1 done findings=${c.findings.length} blocked=${c.blocked.length}');
}
