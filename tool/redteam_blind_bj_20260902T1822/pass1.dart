/// PASS 1 — BJ1 Connect/payout HTTP · BJ2 return hijack · BJ4 NFC/NFD · crash_inject.
/// Exactos ATBE (não contar): PUT/PATCH/DELETE Transfer · amount true/0x64/"1e2".
import 'dart:io';
import '_rtbj.dart';

bool payoutOk(HttpHit h) =>
    h.ok &&
    (h.map?['success'] == true ||
        (h.transferId != null && h.transferId!.startsWith('tr_')));

Future<void> main() async {
  final env = loadEnv();
  final c = Rtbj.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final w0 = await c.wallets();
  final sellerW = await c.walletRow(c.sellerId);
  c.note('p1.wallets', 'saldos iniciais', w0, lens: 'BJ7');
  c.note('p1.connect', 'seller stripe_account_id',
      sellerW?['stripe_account_id'], lens: 'BJ1');

  // ---- Exactos ATBE: métodos HTTP (observar, não contar) ----
  for (final m in ['PUT', 'PATCH', 'DELETE']) {
    final h = await c.connect({
      'amount': 100,
      'idempotency_key': '${prefix}_exacto_$m',
    }, method: m);
    c.note('p1.exacto.$m', 'ATBE exacto $m Transfer', h.brief, lens: 'BJ1');
  }
  for (final amt in [true, '0x64', '1e2']) {
    final h = await c.connect({
      'amount': amt,
      'idempotency_key': '${prefix}_exacto_${amt.runtimeType}_$amt',
    });
    c.note('p1.exacto.amt', 'ATBE exacto amount=$amt', h.brief, lens: 'BJ1');
  }

  // ---- BJ1 novas: array / locale vírgula / objecto ----
  await c.expectDenied(
    id: 'BJ1-01-array-amount',
    lens: 'BJ1',
    title: 'amount como array cria Transfer',
    hit: await c.connect({
      'amount': [100],
      'idempotency_key': '${prefix}_arr_amt',
    }),
    actor: 'seller JWT',
    pre: 'Connect Edge POST',
    repro: 'POST create-connect-account amount=[100]',
    severityIfOpen: 'P0',
    isSuccess: payoutOk,
  );

  await c.expectDenied(
    id: 'BJ1-02-locale-comma',
    lens: 'BJ1',
    title: 'amount locale vírgula ("100,00") cria Transfer',
    hit: await c.connect({
      'amount': '100,00',
      'idempotency_key': '${prefix}_comma',
    }),
    actor: 'seller JWT',
    pre: 'cêntimos estritos',
    repro: 'POST amount="100,00"',
    severityIfOpen: 'P0',
    isSuccess: payoutOk,
  );

  await c.expectDenied(
    id: 'BJ1-03-locale-euro',
    lens: 'BJ1',
    title: 'amount "1,99" (euros) cria Transfer de 199¢',
    hit: await c.connect({
      'amount': '1,99',
      'idempotency_key': '${prefix}_eurocomma',
    }),
    actor: 'seller JWT',
    pre: 'parser Number() frouxo',
    repro: 'POST amount="1,99"',
    severityIfOpen: 'P1',
    isSuccess: payoutOk,
  );

  await c.expectDenied(
    id: 'BJ1-04-object-amount',
    lens: 'BJ1',
    title: 'amount objecto cria Transfer',
    hit: await c.connect({
      'amount': {'cents': 100},
      'idempotency_key': '${prefix}_obj_amt',
    }),
    actor: 'seller JWT',
    pre: 'JSON object',
    repro: 'POST amount={cents:100}',
    severityIfOpen: 'P1',
    isSuccess: payoutOk,
  );

  await c.expectDenied(
    id: 'BJ1-05-nbsp-amount',
    lens: 'BJ1',
    title: 'amount com NBSP/"100 " parseia para Transfer',
    hit: await c.connect({
      'amount': '100\u00a0',
      'idempotency_key': '${prefix}_nbsp',
    }),
    actor: 'seller JWT',
    pre: 'trim só ASCII space',
    repro: 'POST amount="100"+NBSP',
    severityIfOpen: 'P2',
    isSuccess: payoutOk,
  );

  // ---- BJ1 destination spoof ----
  final destSpoof = await c.connect({
    'amount': 100,
    'idempotency_key': '${prefix}_dest_spoof',
    'destination': 'acct_1HijackDestBJ',
    'stripe_account_id': 'acct_1HijackDestBJ',
    'account': 'acct_1HijackDestBJ',
  });
  c.note('p1.dest.body', 'destination no body', destSpoof.brief, lens: 'BJ1');
  if (payoutOk(destSpoof) &&
      '${destSpoof.map}'.contains('acct_1HijackDestBJ')) {
    c.hold(
      id: 'BJ1-06-dest-body',
      lens: 'BJ1',
      severity: 'P0',
      title: 'Body destination/account desviou a Transfer',
      actor: 'seller JWT',
      pre: 'Edge ignora destination; usa conta JWT',
      repro: 'POST amount=100 destination=acct_fake',
      expected: 'destino = conta Connect do JWT',
      obtained: destSpoof.brief,
    );
  } else if (payoutOk(destSpoof)) {
    c.note('p1.dest.body.ok-own', 'Transfer criada mas destino provavelmente próprio',
        destSpoof.brief, lens: 'BJ1');
  } else {
    c.block('BJ1-06-dest-body', 'BJ1', 'destination body não desviou', destSpoof);
  }

  final patchWallet = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {'stripe_account_id': 'acct_1HijackDestBJ'},
  );
  await c.expectDenied(
    id: 'BJ1-07-patch-wallet-dest',
    lens: 'BJ1',
    title: 'Seller PATCH wallets.stripe_account_id para conta alheia',
    hit: patchWallet,
    actor: 'seller JWT',
    pre: 'RLS wallets sem UPDATE',
    repro: 'PATCH wallets stripe_account_id=acct_fake',
    severityIfOpen: 'P0',
    isSuccess: (h) => h.mutated,
  );

  if (c.seller2Id != null) {
    final crossUid = await c.connect({
      'user_id': c.seller2Id,
      'amount': 100,
      'idempotency_key': '${prefix}_uid_s2',
    }, jwt: c.sellerJwt);
    await c.expectDenied(
      id: 'BJ1-08-user-id-s2',
      lens: 'BJ1',
      title: 'Seller1 payout com user_id=Seller2',
      hit: crossUid,
      actor: 'seller JWT',
      pre: 'body.user_id ≠ JWT',
      repro: 'POST user_id=S2 amount=100',
      severityIfOpen: 'P0',
      isSuccess: payoutOk,
    );
  }

  final buyerPayout = await c.connect({
    'amount': 100,
    'idempotency_key': '${prefix}_buyer_payout',
    'user_id': c.sellerId,
  }, jwt: c.buyerJwt);
  await c.expectDenied(
    id: 'BJ1-09-buyer-payout-seller',
    lens: 'BJ6',
    title: 'Buyer JWT levantamento na conta do vendedor',
    hit: buyerPayout,
    actor: 'buyer JWT',
    pre: 'user_id=seller',
    repro: 'POST create-connect-account JWT=buyer user_id=seller',
    severityIfOpen: 'P0',
    isSuccess: payoutOk,
  );

  // JWT RPCs débito / finish / clawback
  final debitJwt = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': c.sellerId,
    'p_amount_cents': 100,
    'p_idempotency_key': '${prefix}_jwt_debit_xxxxxxxx',
  }, jwt: c.buyerJwt);
  await c.expectDenied(
    id: 'BJ1-10-jwt-debit',
    lens: 'BJ1',
    title: 'JWT executou batata_wallet_payout_debit',
    hit: debitJwt,
    actor: 'buyer JWT',
    pre: 'GRANT service_role',
    repro: 'POST rpc/batata_wallet_payout_debit',
    severityIfOpen: 'P0',
    isSuccess: (h) => h.ok && h.map?['ok'] == true,
  );

  final finishJwt = await c.rpc('batata_wallet_payout_finish', {
    'p_idempotency_key': '${prefix}_jwt_debit_xxxxxxxx',
    'p_stripe_transfer_id': 'tr_fake_bj',
    'p_failed': false,
  }, jwt: c.sellerJwt);
  await c.expectDenied(
    id: 'BJ1-11-jwt-finish',
    lens: 'BJ1',
    title: 'JWT executou batata_wallet_payout_finish',
    hit: finishJwt,
    actor: 'seller JWT',
    pre: 'GRANT service_role',
    repro: 'POST rpc/batata_wallet_payout_finish',
    severityIfOpen: 'P0',
    isSuccess: (h) => h.ok && h.map?['ok'] == true,
  );

  // ---- BJ2 return_url hijack ----
  for (final origin in [
    'https://evil.com',
    'https://fleaber.pt.evil.com',
    'https://attacker.fleaber.pt',
    'javascript:alert(1)',
    'https://fleaber.pt/wallet?next=https://evil.com',
  ]) {
    final h = await c.edge(
      'create-connect-account',
      method: 'GET',
      qs: '?web_return_origin=${Uri.encodeComponent(origin)}',
      jwt: c.sellerJwt,
    );
    final loc = h.location ?? '';
    c.note('p1.bj2.get', 'GET web_return_origin=$origin',
        '${h.status} loc=$loc', lens: 'BJ2');
    if (loc.contains('evil.com') ||
        loc.startsWith('javascript:') ||
        loc.contains('attacker.fleaber.pt')) {
      c.hold(
        id: 'BJ2-01-open-redirect',
        lens: 'BJ2',
        severity: 'P1',
        title: 'GET Connect redirecciona para origem hostil',
        actor: 'GET anónimo/JWT',
        pre: 'allowlist hosts',
        repro: 'GET create-connect-account?web_return_origin=$origin',
        expected: 'sem Location evil',
        obtained: '${h.status} $loc',
      );
    } else {
      c.block('BJ2-01-$origin', 'BJ2', 'redirect hostil bloqueado', h);
    }
  }

  final postOrigin = await c.connect({
    'web_return_origin': 'https://evil.com',
  });
  c.note('p1.bj2.post', 'POST onboarding web_return_origin=evil',
      postOrigin.brief, lens: 'BJ2');
  final url = '${postOrigin.map?['url'] ?? ''}';
  if (url.contains('evil.com')) {
    c.hold(
      id: 'BJ2-02-onboarding-evil',
      lens: 'BJ2',
      severity: 'P1',
      title: 'AccountLink return_url aponta a evil.com',
      actor: 'seller JWT',
      pre: 'sanitizeWebReturnOrigin',
      repro: 'POST web_return_origin=https://evil.com',
      expected: 'return_url domínio Fleaber',
      obtained: postOrigin.brief,
    );
  } else {
    c.block('BJ2-02-onboarding-evil', 'BJ2', 'onboarding origin evil', postOrigin);
  }

  // ---- BJ4 NFC vs NFD idempotency (2 Transfers?) ----
  final nfc = 'payout-caf\u00e9-bj22xx'; // U+00E9
  final nfd = 'payout-cafe\u0301-bj22xx'; // e + combining acute
  if (nfc == nfd) {
    c.skip('BJ4-01-nfc-nfd', 'BJ4', 'Dart colapsou NFC/NFD', nfc);
  } else {
    final bal = await c.walletBal(c.sellerId);
    if (bal < 3) {
      await c.fixtureCreditSeller(5);
    }
    final hNfc = await c.connect({
      'amount': 100,
      'idempotency_key': nfc,
    });
    final hNfd = await c.connect({
      'amount': 100,
      'idempotency_key': nfd,
    });
    c.note('p1.nfc', 'idempotency NFC', hNfc.brief, lens: 'BJ4');
    c.note('p1.nfd', 'idempotency NFD', hNfd.brief, lens: 'BJ4');
    final t1 = hNfc.transferId;
    final t2 = hNfd.transferId;
    if (payoutOk(hNfc) &&
        payoutOk(hNfd) &&
        t1 != null &&
        t2 != null &&
        t1 != t2) {
      c.hold(
        id: 'BJ4-01-nfc-nfd-dup-transfer',
        lens: 'BJ4',
        severity: 'P0',
        title: 'idempotency_key NFC vs NFD gerou duas Transfers',
        actor: 'seller JWT',
        pre: 'hash SHA-256 sem Unicode normalize; saldo ≥2€',
        repro: 'POST amount=100 key=café(NFC) depois café(NFD)',
        expected: '2ª request idempotente / mesma Transfer',
        obtained: {'nfc': hNfc.brief, 'nfd': hNfd.brief, 't1': t1, 't2': t2},
      );
    } else if (payoutOk(hNfc) && payoutOk(hNfd) && t1 == t2 && t1 != null) {
      c.block('BJ4-01-nfc-nfd', 'BJ4', 'NFC/NFD mesma Transfer', {
        'nfc': hNfc.brief,
        'nfd': hNfd.brief,
      });
    } else {
      c.note('p1.nfc.nfd.outcome', 'sem duplo Transfer', {
        'nfc': hNfc.brief,
        'nfd': hNfd.brief,
      }, lens: 'BJ4');
      if (!hNfc.denied && !hNfd.denied) {
        // Ambos 2xx sem tr_ — possível onboarding
        c.block('BJ4-01-nfc-nfd', 'BJ4', 'NFC/NFD sem Transfer (Connect?)', {
          'nfc': hNfc.brief,
          'nfd': hNfd.brief,
        });
      } else {
        c.block('BJ4-01-nfc-nfd', 'BJ4', 'NFC/NFD sem 2 Transfers', {
          'nfc': hNfc.brief,
          'nfd': hNfd.brief,
        });
      }
    }
  }

  // crash_inject SEM secret
  final crashNoSecret = await c.connect({
    'amount': 100,
    'idempotency_key': '${prefix}_crash_nosecret',
    'crash_inject': 'after_debit_before_stripe',
  });
  c.note('p1.crash.nosecret', 'crash_inject sem header secret',
      crashNoSecret.brief, lens: 'BJ1');
  if (crashNoSecret.map?['crash_inject'] == true) {
    c.hold(
      id: 'BJ1-12-crash-no-secret',
      lens: 'BJ1',
      severity: 'P1',
      title: 'crash_inject activou sem secret',
      actor: 'seller JWT',
      pre: 'allowPayoutCrashInject exige header+env',
      repro: 'POST crash_inject=after_debit_before_stripe sem secret',
      expected: 'ignorar inject',
      obtained: crashNoSecret.brief,
    );
  } else {
    c.block('BJ1-12-crash-no-secret', 'BJ1', 'crash_inject sem secret',
        crashNoSecret);
  }

  // crash_inject COM secret (staging TEST)
  if (c.crashSecret.length >= 16) {
    final bal2 = await c.walletBal(c.sellerId);
    if (bal2 < 2) await c.fixtureCreditSeller(5);
    final keyCrash = '${prefix}_crash_after_debit';
    final crash1 = await c.connect({
      'amount': 100,
      'idempotency_key': keyCrash,
      'crash_inject': 'after_debit_before_stripe',
    }, extra: {
      'x-fleaber-crash-inject-secret': c.crashSecret,
    });
    c.note('p1.crash.after_debit', 'inject after_debit_before_stripe',
        crash1.brief, lens: 'BJ4');
    final led1 = await c.payoutLedger(userId: c.sellerId, limit: 5);
    c.note('p1.crash.ledger1', 'ledger após crash debit', led1, lens: 'BJ4');

    final retry = await c.connect({
      'amount': 100,
      'idempotency_key': keyCrash,
    });
    c.note('p1.crash.retry', 'retry mesma key após crash debit', retry.brief,
        lens: 'BJ4');
    final led2 = await c.payoutLedger(userId: c.sellerId, limit: 5);
    final transfers = led2
        .where((r) =>
            r is Map &&
            '${r['idempotency_key']}'.contains('p_') &&
            r['stripe_transfer_id'] != null)
        .map((r) => (r as Map)['stripe_transfer_id'])
        .toSet();
    c.note('p1.crash.ledger2', 'ledger após retry', led2, lens: 'BJ4');

    if (crash1.status == 500 &&
        crash1.map?['needs_reconcile'] == true &&
        payoutOk(retry)) {
      c.block('BJ4-02-crash-debit-retry', 'BJ4',
          'crash debit + retry completou 1 Transfer', retry);
    } else if (crash1.map?['crash_inject'] == true && retry.denied) {
      c.note('p1.crash.retry.denied', 'retry falhou após crash', retry.brief,
          lens: 'BJ4');
    }

    final keyCrash2 = '${prefix}_crash_after_stripe';
    final crashStripe = await c.connect({
      'amount': 100,
      'idempotency_key': keyCrash2,
      'crash_inject': 'after_stripe_before_finish',
    }, extra: {
      'x-fleaber-crash-inject-secret': c.crashSecret,
    });
    c.note('p1.crash.after_stripe', 'inject after_stripe_before_finish',
        crashStripe.brief, lens: 'BJ4');
    final tCrash = crashStripe.transferId;
    final retry2 = await c.connect({
      'amount': 100,
      'idempotency_key': keyCrash2,
    });
    c.note('p1.crash.retry2', 'retry após Transfer sem finish', retry2.brief,
        lens: 'BJ4');
    final tRetry = retry2.transferId;
    if (tCrash != null &&
        tRetry != null &&
        tCrash != tRetry &&
        tCrash.startsWith('tr_') &&
        tRetry.startsWith('tr_')) {
      c.hold(
        id: 'BJ4-03-crash-stripe-dup',
        lens: 'BJ4',
        severity: 'P0',
        title: 'crash after_stripe + retry criou 2ª Transfer',
        actor: 'seller JWT + crash_inject secret',
        pre: 'idempotency Stripe fleaber_wd_{key}',
        repro: 'POST crash_inject=after_stripe_before_finish; retry mesma key',
        expected: 'retry finish da mesma tr_',
        obtained: {
          'crash': crashStripe.brief,
          'retry': retry2.brief,
          't1': tCrash,
          't2': tRetry,
        },
      );
    } else {
      c.block('BJ4-03-crash-stripe-dup', 'BJ4',
          'retry após Transfer não duplicou', {
        'crash': crashStripe.brief,
        'retry': retry2.brief,
      });
    }
    c.note('p1.crash.transfers_set', 'transfer ids ledger', transfers.toList(),
        lens: 'BJ4');
  } else {
    c.skip('BJ4-02-crash', 'BJ4', 'sem crash inject secret', '');
  }

  // race mesma key
  final raceKey = '${prefix}_race_samekey';
  final race = await Future.wait([
    c.connect({'amount': 100, 'idempotency_key': raceKey}),
    c.connect({'amount': 100, 'idempotency_key': raceKey}),
  ]);
  c.note('p1.race.a', 'race same key A', race[0].brief, lens: 'BJ4');
  c.note('p1.race.b', 'race same key B', race[1].brief, lens: 'BJ4');
  final raceTs = race
      .map((h) => h.transferId)
      .where((t) => t != null && t.startsWith('tr_'))
      .toSet();
  if (raceTs.length > 1) {
    c.hold(
      id: 'BJ4-04-race-same-key',
      lens: 'BJ4',
      severity: 'P0',
      title: 'Future.wait mesma idempotency_key = 2 Transfers',
      actor: 'seller JWT ×2',
      pre: 'ledger unique key',
      repro: 'Future.wait 2× POST mesma key amount=100',
      expected: '1 Transfer',
      obtained: race.map((h) => h.brief).toList(),
    );
  } else {
    c.block('BJ4-04-race-same-key', 'BJ4', 'race mesma key ≤1 Transfer', raceTs);
  }

  final w1 = await c.wallets();
  c.note('p1.wallets.end', 'saldos fim pass1', w1, lens: 'BJ7');

  await c.dumpAll('pass1.json');
  stdout.writeln('PASS1 findings=${c.findings.length} blocked=${c.blocked.length}');
}
