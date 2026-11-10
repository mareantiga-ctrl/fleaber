/// PASS 1 — I1 JWT/Edge payout · I2 Connect hijack · I6 refund alheio.
/// Proibido: dual Session, bag unlist, cancel hold, review 5★.
import 'dart:io';
import '_rti.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rti.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final out = <String, Object?>{
    'pass': 1,
    'prefix': prefix,
    'actors': {
      'buyer': c.buyerId,
      'seller': c.sellerId,
      'buyer2': c.buyer2Id,
      'seller2': c.seller2Id,
    },
  };

  // ---- Discover money-out RPCs (not inbox) ----
  final openapi = await c.req(
    'GET',
    '/rest/v1/',
    extra: {'Accept': 'application/openapi+json'},
    service: true,
  );
  final rpcNames = <String>[];
  if (openapi.json is Map) {
    final paths = (openapi.json as Map)['paths'];
    if (paths is Map) {
      for (final k in paths.keys) {
        final s = k.toString();
        if (s.startsWith('/rpc/')) {
          final n = s.substring(5);
          if (RegExp(
            r'payout|clawback|refund|release|transfer|connect|debit|credit_wallet|wallet_payout|partial_refund',
            caseSensitive: false,
          ).hasMatch(n)) {
            rpcNames.add(n);
          }
        }
      }
    }
  }
  rpcNames.sort();
  out['rpc_money_out'] = rpcNames;
  c.note('p1.rpcs', 'RPCs saída/dinheiro', rpcNames.length, lens: 'I1');

  final w0 = await c.wallets();
  final sellerWallet = await c.walletRow(c.sellerId);
  out['wallets_start'] = w0;
  out['seller_connect'] = sellerWallet?['stripe_account_id'];
  c.note('p1.wallets', 'saldos iniciais', w0, lens: 'I7');

  // ========== I1: JWT DEFINER payout / finish / clawback ==========
  final debitJwt = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': c.sellerId,
    'p_amount_cents': 100,
    'p_idempotency_key': '${prefix}_jwt_debit',
  }, jwt: c.buyerJwt);
  c.note('p1.i1.debit_jwt', 'buyer JWT payout_debit seller', debitJwt.brief,
      lens: 'I1');
  if (debitJwt.ok && debitJwt.map?['ok'] == true) {
    c.hold(
      id: 'RTI-I1-001',
      lens: 'I1',
      severity: 'P0',
      title: 'JWT autenticado executou batata_wallet_payout_debit',
      actor: 'buyer JWT',
      pre: 'GRANT deveria ser só service_role',
      repro: 'POST rpc/batata_wallet_payout_debit p_user_id=seller',
      expected: '403 permission denied',
      obtained: debitJwt.brief,
    );
  }

  final debitSelf = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': c.buyerId,
    'p_amount_cents': 100,
    'p_idempotency_key': '${prefix}_jwt_self',
  }, jwt: c.buyerJwt);
  c.note('p1.i1.debit_self', 'buyer JWT debit self', debitSelf.brief, lens: 'I1');

  final finishJwt = await c.rpc('batata_wallet_payout_finish', {
    'p_idempotency_key': '${prefix}_jwt_debit',
    'p_stripe_transfer_id': 'tr_fake_rti',
    'p_failed': false,
  }, jwt: c.sellerJwt);
  c.note('p1.i1.finish_jwt', 'seller JWT payout_finish', finishJwt.brief,
      lens: 'I1');
  if (finishJwt.ok && finishJwt.map?['ok'] == true) {
    c.hold(
      id: 'RTI-I1-002',
      lens: 'I1',
      severity: 'P0',
      title: 'JWT autenticado executou batata_wallet_payout_finish',
      actor: 'seller JWT',
      pre: 'ledger inexistente ou alheio',
      repro: 'POST rpc/batata_wallet_payout_finish',
      expected: '403',
      obtained: finishJwt.brief,
    );
  }

  final clawJwt = await c.rpc(
    'batata_clawback_seller_wallet_for_order',
    {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    jwt: c.buyerJwt,
  );
  c.note('p1.i1.claw_jwt', 'buyer JWT clawback', clawJwt.brief, lens: 'I1');
  if (clawJwt.status == 200 && clawJwt.json is num && (clawJwt.json as num) > 0) {
    c.hold(
      id: 'RTI-I1-003',
      lens: 'I1',
      severity: 'P0',
      title: 'JWT clawback devolveu montante >0',
      actor: 'buyer JWT',
      pre: 'order fake',
      repro: 'rpc batata_clawback_seller_wallet_for_order',
      expected: '403',
      obtained: clawJwt.brief,
    );
  }

  // ========== I1/I2: Edge create-connect-account hostil ==========
  final crossUser = await c.edge(
    'create-connect-account',
    {
      'user_id': c.sellerId,
      'amount': 100,
      'idempotency_key': '${prefix}_cross_uid',
    },
    jwt: c.buyerJwt,
  );
  c.note('p1.i2.user_id_cross', 'buyer JWT user_id=seller + amount',
      crossUser.brief,
      lens: 'I2');
  if (crossUser.ok &&
      (crossUser.map?['success'] == true ||
          crossUser.map?['url'] != null ||
          crossUser.map?['stripeAccountId'] != null)) {
    c.hold(
      id: 'RTI-I2-001',
      lens: 'I2',
      severity: 'P0',
      title: 'Edge Connect aceitou user_id de outra conta',
      actor: 'buyer JWT',
      pre: 'body.user_id = seller',
      repro: 'POST create-connect-account user_id=seller amount=100',
      expected: 'erro Cannot create another user',
      obtained: crossUser.brief,
    );
  }

  final negAmt = await c.edge(
    'create-connect-account',
    {
      'amount': -500,
      'idempotency_key': '${prefix}_negamt',
    },
    jwt: c.sellerJwt,
  );
  c.note('p1.i1.neg_amount', 'seller amount=-500', negAmt.brief, lens: 'I1');
  if (negAmt.ok && negAmt.map?['success'] == true) {
    c.hold(
      id: 'RTI-I1-004',
      lens: 'I1',
      severity: 'P0',
      title: 'Levantamento com amount negativo aceite',
      actor: 'seller JWT',
      pre: 'carteira seller',
      repro: 'POST create-connect-account amount=-500',
      expected: '400 valor inválido',
      obtained: negAmt.brief,
    );
  }

  final euroConfused = await c.edge(
    'create-connect-account',
    {
      'amount': 5.90,
      'idempotency_key': '${prefix}_eurofloat',
    },
    jwt: c.sellerJwt,
  );
  c.note('p1.i1.float_amount', 'amount=5.90 (euros vs cêntimos)',
      euroConfused.brief,
      lens: 'I1');

  final huge = await c.edge(
    'create-connect-account',
    {
      'amount': 999999999,
      'idempotency_key': '${prefix}_huge',
    },
    jwt: c.sellerJwt,
  );
  c.note('p1.i1.huge', 'amount=999999999¢', huge.brief, lens: 'I1');
  final sellerAfterHuge = await c.walletBal(c.sellerId);
  if (sellerAfterHuge < (w0['seller'] ?? 0) - 1) {
    c.hold(
      id: 'RTI-I1-005',
      lens: 'I1',
      severity: 'P0',
      title: 'Pedido enorme debitou carteira',
      actor: 'seller JWT',
      pre: 'amount >> saldo',
      repro: 'POST create-connect-account amount=999999999',
      expected: 'saldo inalterado',
      obtained: {'before': w0['seller'], 'after': sellerAfterHuge, 'edge': huge.brief},
    );
  }

  final noKey = await c.edge(
    'create-connect-account',
    {'amount': 100},
    jwt: c.sellerJwt,
  );
  c.note('p1.i1.nokey', 'amount sem idempotency_key', noKey.brief, lens: 'I1');

  // I2: return_url / onboarding hijack
  final origins = <String>[
    'https://evil.com',
    'https://fleaber.pt.evil.com',
    'https://evil.com/fleaber.pt',
    'javascript:alert(1)',
    'https://fleaber.pt/wallet?next=https://evil.com',
    'https://attacker@fleaber.pt',
    'http://fleaber.pt',
    'https://127.0.0.1',
    '//evil.com',
    'https://fleaber.app.evil.com',
  ];
  final redirectHits = <String, Object?>{};
  for (final o in origins) {
    final g = await c.edge(
      'create-connect-account?web_return_origin=${Uri.encodeQueryComponent(o)}&wallet_return=1',
      null,
      method: 'GET',
      jwt: c.buyerJwt,
    );
    redirectHits[o] = {
      'status': g.status,
      'location': g.location,
      'body': clip(g.body, 80),
    };
    final loc = (g.location ?? '').toLowerCase();
    if (g.status >= 300 &&
        g.status < 400 &&
        loc.isNotEmpty &&
        (loc.contains('evil') ||
            loc.startsWith('javascript:') ||
            loc.contains('attacker'))) {
      c.hold(
        id: 'RTI-I2-002',
        lens: 'I2',
        severity: 'P1',
        title: 'GET Connect 303 para origem hostil',
        actor: 'unauth/JWT GET',
        pre: 'web_return_origin=$o',
        repro: 'GET create-connect-account?web_return_origin=',
        expected: 'sem Location para evil',
        obtained: {'origin': o, 'status': g.status, 'location': g.location},
      );
    }
  }
  out['i2_get_redirects'] = redirectHits;

  final postOrigin = await c.edge(
    'create-connect-account',
    {'web_return_origin': 'https://evil.com/steal'},
    jwt: c.sellerJwt,
  );
  c.note('p1.i2.post_origin', 'POST web_return_origin=evil.com', {
    'brief': postOrigin.brief,
    'url': postOrigin.map?['url'],
    'account': postOrigin.map?['stripeAccountId'],
  }, lens: 'I2');
  final onboardUrl = '${postOrigin.map?['url'] ?? ''}';
  if (onboardUrl.contains('evil.com')) {
    c.hold(
      id: 'RTI-I2-003',
      lens: 'I2',
      severity: 'P1',
      title: 'AccountLink Stripe aponta para domínio hostil',
      actor: 'seller JWT',
      pre: 'web_return_origin=https://evil.com/steal',
      repro: 'POST create-connect-account',
      expected: 'return_url só na Edge Fleaber',
      obtained: onboardUrl,
    );
  }

  // I2: PATCH stripe_account_id / balance
  final fakeAcct = 'acct_RTI_HIJACK_0001';
  final patchOwnAcct = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {'stripe_account_id': fakeAcct},
  );
  c.note('p1.i2.patch_own_acct', 'seller PATCH own stripe_account_id',
      patchOwnAcct.brief,
      lens: 'I2');
  final afterOwn = await c.walletRow(c.sellerId);
  if (afterOwn?['stripe_account_id'] == fakeAcct) {
    c.hold(
      id: 'RTI-I2-004',
      lens: 'I2',
      severity: 'P0',
      title: 'JWT alterou stripe_account_id da própria carteira',
      actor: 'seller JWT',
      pre: 'PATCH wallets stripe_account_id',
      repro: 'PATCH wallets?id=eq.self',
      expected: '0 rows / RLS',
      obtained: afterOwn,
    );
  }

  final patchVictim = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.buyerJwt,
    body: {'stripe_account_id': fakeAcct, 'balance': 9999},
  );
  c.note('p1.i2.patch_victim', 'buyer PATCH seller wallet', patchVictim.brief,
      lens: 'I2');
  if (patchVictim.ok && patchVictim.list.isNotEmpty) {
    c.hold(
      id: 'RTI-I2-005',
      lens: 'I2',
      severity: 'P0',
      title: 'Comprador PATCH da carteira do vendedor',
      actor: 'buyer JWT',
      pre: 'wallets seller',
      repro: 'PATCH wallets?id=eq.seller stripe_account_id+balance',
      expected: '0 rows',
      obtained: patchVictim.brief,
    );
  }

  final patchBal = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.buyerId}',
    jwt: c.buyerJwt,
    body: {'balance': 9999.99},
  );
  c.note('p1.i1.patch_balance', 'buyer PATCH own balance', patchBal.brief,
      lens: 'I1');
  final buyerBal = await c.walletBal(c.buyerId);
  if ((buyerBal - (w0['buyer'] ?? 0)).abs() > 1 && patchBal.ok) {
    c.hold(
      id: 'RTI-I1-006',
      lens: 'I1',
      severity: 'P0',
      title: 'JWT mintou saldo via PATCH wallets.balance',
      actor: 'buyer JWT',
      pre: 'saldo $w0',
      repro: 'PATCH wallets balance=9999.99',
      expected: 'saldo inalterado',
      obtained: {'before': w0['buyer'], 'after': buyerBal},
    );
  }

  final insLedger = await c.rest(
    'POST',
    'wallet_payout_ledger',
    jwt: c.sellerJwt,
    body: {
      'idempotency_key': '${prefix}_forged_ledger',
      'user_id': c.sellerId,
      'amount_cents': 1,
      'amount_eur': 0.01,
      'status': 'transferred',
      'stripe_transfer_id': 'tr_forged_rti',
    },
  );
  c.note('p1.i1.insert_ledger', 'JWT INSERT payout_ledger', insLedger.brief,
      lens: 'I1');
  if (insLedger.ok && insLedger.firstId != null) {
    c.hold(
      id: 'RTI-I1-007',
      lens: 'I1',
      severity: 'P1',
      title: 'JWT inseriu linha em wallet_payout_ledger',
      actor: 'seller JWT',
      pre: 'sem INSERT policy',
      repro: 'POST wallet_payout_ledger status=transferred',
      expected: '403 / RLS',
      obtained: insLedger.brief,
    );
  }

  // ========== I6: refund alheio ==========
  final pHold = await c.insertProduct(title: '$prefix i6-hold', qty: 2);
  final oidHold = await c.insertOrder(productId: pHold!, jwt: c.buyerJwt);
  final refundB2 = await c.edge(
    'refund-order',
    {'order_id': oidHold},
    jwt: c.buyer2Jwt,
  );
  c.note('p1.i6.refund_b2', 'buyer2 refund-order hold alheia', refundB2.brief,
      lens: 'I6');
  if (refundB2.ok && refundB2.map?['ok'] == true && refundB2.map?['skipped'] != true) {
    c.hold(
      id: 'RTI-I6-001',
      lens: 'I6',
      severity: 'P0',
      title: '2.º comprador reembolsou encomenda alheia',
      actor: 'buyer2 JWT',
      pre: 'order buyer1 reserva_pendente',
      repro: 'POST refund-order',
      expected: '403 Sem permissão',
      obtained: refundB2.brief,
    );
  }

  final refundBuyer = await c.edge(
    'refund-order',
    {'order_id': oidHold},
    jwt: c.buyerJwt,
  );
  c.note('p1.i6.refund_buyer', 'buyer1 refund-order própria (não seller)',
      refundBuyer.brief,
      lens: 'I6');
  if (refundBuyer.ok &&
      refundBuyer.map?['ok'] == true &&
      refundBuyer.map?['skipped'] != true) {
    c.hold(
      id: 'RTI-I6-002',
      lens: 'I6',
      severity: 'P1',
      title: 'Comprador chamou refund-order (rota do vendedor)',
      actor: 'buyer JWT',
      pre: 'Edge exige seller_id',
      repro: 'POST refund-order order_id própria',
      expected: '403 Sem permissão',
      obtained: refundBuyer.brief,
    );
  }

  final refundS2 = await c.edge(
    'refund-order',
    {'order_id': oidHold},
    jwt: c.seller2Jwt,
  );
  c.note('p1.i6.refund_s2', 'seller2 refund-order de seller1', refundS2.brief,
      lens: 'I6');
  if (refundS2.ok && refundS2.map?['ok'] == true && refundS2.map?['skipped'] != true) {
    c.hold(
      id: 'RTI-I6-003',
      lens: 'I6',
      severity: 'P0',
      title: 'Vendedor alheio reembolsou encomenda',
      actor: 'seller2 JWT',
      pre: 'order seller1',
      repro: 'POST refund-order',
      expected: '403',
      obtained: refundS2.brief,
    );
  }

  final refundRpcB2 = await c.rpc(
    'batata_refund_buyer_wallet_for_order',
    {'p_order_id': oidHold},
    jwt: c.buyer2Jwt,
  );
  c.note('p1.i6.rpc_refund_b2', 'buyer2 RPC refund_buyer_wallet',
      refundRpcB2.brief,
      lens: 'I6');
  if (refundRpcB2.ok && refundRpcB2.json == true) {
    c.hold(
      id: 'RTI-I6-004',
      lens: 'I6',
      severity: 'P0',
      title: 'JWT alheio creditou reembolso wallet',
      actor: 'buyer2 JWT',
      pre: 'order não é sua e não está devolvida',
      repro: 'rpc batata_refund_buyer_wallet_for_order',
      expected: 'false / 403',
      obtained: refundRpcB2.brief,
    );
  }

  final partialB2 = await c.rpc(
    'batata_process_partial_refund_dispute',
    {'p_order_id': oidHold, 'p_refund_percent': 100},
    jwt: c.buyer2Jwt,
  );
  c.note('p1.i6.partial_b2', 'buyer2 partial_refund alheio', partialB2.brief,
      lens: 'I6');
  if (partialB2.ok && partialB2.json == true) {
    c.hold(
      id: 'RTI-I6-005',
      lens: 'I6',
      severity: 'P0',
      title: '2.º buyer processou reembolso parcial alheio',
      actor: 'buyer2 JWT',
      pre: 'sem disputa',
      repro: 'rpc batata_process_partial_refund_dispute',
      expected: 'not_allowed / false',
      obtained: partialB2.brief,
    );
  }

  // JWT release on unpaid hold (should false, not mint)
  final relHold = await c.tryRelease(oidHold!, jwt: c.buyerJwt);
  c.note('p1.i3.release_unpaid', 'release em reserva_pendente', relHold.brief,
      lens: 'I3');
  if (relHold.ok && relHold.json == true) {
    c.hold(
      id: 'RTI-I3-001',
      lens: 'I3',
      severity: 'P0',
      title: 'Release wallet em encomenda não concluída',
      actor: 'buyer JWT',
      pre: 'status reserva_pendente',
      repro: 'rpc batata_release_seller_wallet_for_order',
      expected: 'false',
      obtained: relHold.brief,
    );
  }

  out['findings'] = c.findings;
  out['notes'] = c.notes;
  out['wallets_end'] = await c.wallets();
  await dumpJson(
    'tool/redteam_blind_i_20260831T1706/pass1.json',
    out,
  );
  stdout.writeln('PASS1 findings=${c.findings.length}');
}
