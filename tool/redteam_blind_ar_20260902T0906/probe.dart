/// PASS 1 — AR payout/wallet/refund pós-AHAM. Variantes novas. Não corrige.
import 'dart:io';
import '_rtar.dart';

Future<void> main() async {
  final c = Rtar.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final w0 = await c.wallets();
  final sellerW = await c.walletRow(c.sellerId);
  c.note('snap.wallets', 'saldos iniciais', w0, lens: 'AR7');
  c.note('snap.seller.acct', 'Connect seller', sellerW?['stripe_account_id'],
      lens: 'AR2');

  // ---------------------------------------------------------------------------
  // AR1 — JWT / Edge hostil, RPCs extra, Stripe-Account, methods
  // ---------------------------------------------------------------------------
  final moneyRpcs = <String, Map<String, Object?>>{
    'batata_wallet_payout_debit': {
      'p_user_id': c.sellerId,
      'p_amount_cents': 100,
      'p_idempotency_key': '${prefix}_jwt_debit',
    },
    'batata_wallet_payout_finish': {
      'p_idempotency_key': '${prefix}_jwt_debit',
      'p_stripe_transfer_id': 'tr_fake_ar',
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
      'p_refund_id': 're_fake_ar',
      'p_amount_cents': 99999,
    },
    'batata_process_partial_refund_dispute': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_refund_percent': 200,
    },
    'batata_wallet_apply_tip_once': {
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_ensure_wallet': {'p_user_id': c.sellerId},
    'batata_order_allows_seller_stripe_refund': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_order_wallet_reembolso_cents': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
  };

  for (final e in moneyRpcs.entries) {
    final buyerHit = await c.rpc(e.key, e.value, jwt: c.buyerJwt);
    final sellerHit = await c.rpc(e.key, e.value, jwt: c.sellerJwt);
    c.note('rpc.${e.key}', 'JWT sweep', {
      'buyer': buyerHit.brief,
      'seller': sellerHit.brief,
    }, lens: 'AR1');
    final minted = (!rpcDenied(buyerHit) && buyerHit.ok && buyerHit.body == 'true') ||
        (!rpcDenied(sellerHit) && sellerHit.ok && sellerHit.body == 'true');
    if (e.key.contains('payout_debit') ||
        e.key.contains('payout_finish') ||
        e.key.contains('credit_wallet') ||
        e.key.contains('finalize_stripe')) {
      if (!rpcDenied(buyerHit) && buyerHit.ok && buyerHit.status != 200 ||
          (buyerHit.ok &&
              buyerHit.body.contains('"ok":true') &&
              e.key.contains('payout'))) {
        c.hold(
          id: 'AR1-jwt-${e.key}',
          lens: 'AR1',
          severity: 'P0',
          title: 'JWT executou RPC de saída de dinheiro ${e.key}',
          actor: 'buyer JWT',
          pre: 'authenticated, sem service_role',
          repro: 'POST rpc/${e.key}',
          expected: '403 42501',
          obtained: buyerHit.brief,
        );
      } else {
        c.block('AR1.${e.key}', 'AR1', 'JWT ${e.key}', {
          'buyer': buyerHit.brief,
          'seller': sellerHit.brief,
        });
      }
    } else if (minted && e.key.contains('credit')) {
      c.hold(
        id: 'AR1-jwt-credit',
        lens: 'AR1',
        severity: 'P0',
        title: 'JWT credit_wallet_once mintou',
        actor: 'JWT',
        pre: 'uuid dummy',
        repro: 'POST rpc/batata_credit_wallet_once',
        expected: '403',
        obtained: {'b': buyerHit.brief, 's': sellerHit.brief},
      );
    }
  }

  final wAfterRpc = await c.wallets();
  final dBuyerRpc = (wAfterRpc['buyer'] ?? 0) - (w0['buyer'] ?? 0);
  final dSellerRpc = (wAfterRpc['seller'] ?? 0) - (w0['seller'] ?? 0);
  if (dBuyerRpc.abs() > 0.009 || dSellerRpc > 0.009) {
    c.hold(
      id: 'AR1-jwt-delta-wallet',
      lens: 'AR1',
      severity: 'P0',
      title: 'Sweep JWT alterou saldo',
      actor: 'JWT',
      pre: 'RPCs money',
      repro: 'POST rpc/*',
      expected: 'Δ 0',
      obtained: {'dBuyer': dBuyerRpc, 'dSeller': dSellerRpc},
    );
  } else {
    c.block('AR1.delta', 'AR1', 'sweep JWT Δwallet 0', {
      'dBuyer': dBuyerRpc,
      'dSeller': dSellerRpc,
    });
  }

  // Stripe-Account header no onboarding (sem amount — não gastar saldo)
  final acctHdr = await c.edge(
    'create-connect-account',
    {
      'currency': 'usd',
      'reverse_transfer': true,
      'destination': 'acct_1EVEL11111111111',
    },
    jwt: c.sellerJwt,
    extra: {'Stripe-Account': 'acct_1EVEL11111111111'},
  );
  c.note('ar1.stripe-account-hdr', 'payout Stripe-Account + currency usd',
      acctHdr.brief, lens: 'AR1');
  if (acctHdr.ok &&
      acctHdr.transferId != null &&
      (acctHdr.body.contains('acct_1EVEL') ||
          '${acctHdr.map?['destination']}'.contains('EVEL'))) {
    c.hold(
      id: 'AR1-stripe-account-header',
      lens: 'AR1',
      severity: 'P0',
      title: 'Header Stripe-Account desviou Transfer',
      actor: 'seller JWT',
      pre: 'Connect próprio no JWT',
      repro: 'POST create-connect-account Stripe-Account: acct_evil',
      expected: 'Transfer na conta do JWT / 400',
      obtained: acctHdr.brief,
    );
  } else {
    c.block('AR1.stripe-acct-hdr', 'AR1', 'Stripe-Account header', acctHdr);
  }

  final putPay = await c.edge(
    'create-connect-account',
    {'web_return_origin': 'https://fleaber.pt'},
    jwt: c.sellerJwt,
    method: 'PUT',
  );
  c.note('ar1.put', 'PUT create-connect-account (sem amount)', putPay.brief,
      lens: 'AR1');
  if (putPay.ok && putPay.transferId != null) {
    c.hold(
      id: 'AR1-put-payout',
      lens: 'AR1',
      severity: 'P2',
      title: 'PUT sem amount criou Transfer',
      actor: 'seller JWT',
      pre: 'method PUT',
      repro: 'PUT create-connect-account',
      expected: '405 ou onboarding sem Transfer',
      obtained: putPay.brief,
    );
  }

  final getRefund = await c.edge(
    'refund-order',
    null,
    jwt: c.sellerJwt,
    method: 'GET',
  );
  c.note('ar1.refund.get', 'GET refund-order', getRefund.brief, lens: 'AR1');

  final arrAmt = await c.payout(
    amountCents: 100,
    key: '${prefix}_arramtxx',
    extra: {
      'amount': [100],
    },
  );
  c.note('ar1.amount-array', 'amount como array', arrAmt.brief, lens: 'AR1');
  if (arrAmt.ok && arrAmt.transferId != null) {
    c.hold(
      id: 'AR1-amount-array',
      lens: 'AR1',
      severity: 'P1',
      title: 'amount:[100] criou Transfer',
      actor: 'seller JWT',
      pre: 'body amount array',
      repro: 'POST create-connect-account amount=[100]',
      expected: '400 valor inválido',
      obtained: arrAmt.brief,
    );
  } else {
    c.block('AR1.amount-array', 'AR1', 'amount array recusado', arrAmt);
  }

  // Prefixo 64 chars: duas keys distintas no cliente, mesmo slice
  final pad = 'P' * 64;
  final kA = '${pad}AAAA-AR';
  final kB = '${pad}BBBB-AR';
  c.note('ar1.prefix.keys', 'keys truncadas', {
    'kA8': kA.substring(0, 8),
    'same64': kA.substring(0, 64) == kB.substring(0, 64),
    'len': kA.length,
  }, lens: 'AR1');

  // REST money
  final patchBal = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.buyerJwt,
    body: {'balance': 9999.99},
  );
  c.note('ar1.patch.bal.cross', 'buyer PATCH seller balance', patchBal.brief,
      lens: 'AR1');
  final insTxn = await c.rest('POST', 'wallet_transactions', jwt: c.buyerJwt,
      body: {
        'wallet_id': c.buyerId,
        'amount': 50,
        'type': 'reembolso',
        'description': prefix,
      });
  c.note('ar1.insert.txn', 'INSERT wallet_transactions', insTxn.brief,
      lens: 'AR1');
  if (insTxn.ok && insTxn.firstId != null) {
    c.hold(
      id: 'AR1-insert-txn',
      lens: 'AR1',
      severity: 'P0',
      title: 'JWT inseriu wallet_transactions',
      actor: 'buyer JWT',
      pre: 'RLS',
      repro: 'POST wallet_transactions',
      expected: '403',
      obtained: insTxn.brief,
    );
  } else {
    c.block('AR1.insert-txn', 'AR1', 'INSERT txn', insTxn);
  }

  final massWal = await c.rest(
    'PATCH',
    'wallets?id=in.(${c.buyerId},${c.sellerId})',
    jwt: c.buyerJwt,
    body: {'balance': 1},
  );
  c.note('ar1.mass.wallets', 'PATCH wallets id=in buyer+seller', massWal.brief,
      lens: 'AR1');
  final wMass = await c.wallets();
  if ((wMass['seller'] ?? 0) == 1 && (w0['seller'] ?? 0) != 1) {
    c.hold(
      id: 'AR1-mass-patch-wallets',
      lens: 'AR1',
      severity: 'P0',
      title: 'PATCH em massa alterou carteira do vendedor',
      actor: 'buyer JWT',
      pre: 'id=in.(buyer,seller)',
      repro: 'PATCH wallets?id=in.(…)',
      expected: '200 [] / sem Δ seller',
      obtained: {'hit': massWal.brief, 'seller': wMass['seller']},
    );
  } else {
    c.block('AR1.mass-wallets', 'AR1', 'mass PATCH wallets', massWal);
  }

  // ---------------------------------------------------------------------------
  // AR2 — Connect hijack variantes novas (não evil.com exacto AL)
  // ---------------------------------------------------------------------------
  final origins = <String, String>{
    'trailing-dot': 'https://fleaber.pt.',
    'crlf': 'https://fleaber.pt%0d%0aLocation:%20https://evil.com',
    'at-userinfo': 'https://fleaber.pt%2f%40evil.com',
    'cyrillic-a': 'https://fleаber.pt',
    'ipv6': 'http://[::1]',
    'fwd-host': 'https://fleaber.pt',
    'scheme-fleaber': 'fleaber://evil.com/wallet',
    'data': 'data:text/html,phish',
  };
  for (final e in origins.entries) {
    final hit = await c.connectGet(
      qs: '?web_return_origin=${e.value}',
      extra: e.key == 'fwd-host'
          ? {
              'X-Forwarded-Host': 'evil.com',
              'X-Forwarded-Proto': 'https',
              'Host': 'evil.com',
            }
          : null,
    );
    final loc = '${hit.location ?? ''} ${hit.body}'.toLowerCase();
    c.note('ar2.get.${e.key}', 'GET Connect origem ${e.key}', {
      'status': hit.status,
      'location': hit.location,
      'hasEvil': loc.contains('evil.com'),
      'snippet': clip(hit.body, 160),
    }, lens: 'AR2');
    if (loc.contains('evil.com') ||
        (hit.location != null &&
            hit.location!.contains('evil') &&
            !hit.location!.contains('fleaber'))) {
      c.hold(
        id: 'AR2-redirect-${e.key}',
        lens: 'AR2',
        severity: 'P1',
        title: 'Connect return desviou para host hostil (${e.key})',
        actor: 'anon GET',
        pre: 'web_return_origin=${e.key}',
        repro: 'GET create-connect-account',
        expected: 'sem Location hostil',
        obtained: {'status': hit.status, 'location': hit.location},
      );
    } else {
      c.block('AR2.${e.key}', 'AR2', 'origem ${e.key}', hit.status);
    }
  }

  final onboard = await c.edge(
    'create-connect-account',
    {
      'web_return_origin': 'https://evil.com',
      'return_url': 'https://evil.com/cb',
      'refresh_url': 'https://evil.com/refresh',
    },
    jwt: c.sellerJwt,
  );
  c.note('ar2.onboard.evil', 'POST onboarding return_url hostil', {
    'status': onboard.status,
    'url': clip('${onboard.map?['url']}', 180),
    'hasEvil': onboard.body.toLowerCase().contains('evil.com'),
  }, lens: 'AR2');
  if (onboard.body.toLowerCase().contains('evil.com')) {
    c.hold(
      id: 'AR2-onboard-url-evil',
      lens: 'AR2',
      severity: 'P1',
      title: 'AccountLink URL contém origem hostil',
      actor: 'seller JWT',
      pre: 'POST sem amount, return_url evil',
      repro: 'POST create-connect-account',
      expected: 'refresh/return na Edge allowlist',
      obtained: clip(onboard.body, 300),
    );
  } else {
    c.block('AR2.onboard-evil', 'AR2', 'AccountLink sem evil', onboard.status);
  }

  final xuser = await c.edge(
    'create-connect-account',
    {'user_id': c.seller2Id, 'web_return_origin': 'https://fleaber.pt'},
    jwt: c.buyerJwt,
  );
  c.note('ar2.cross.user', 'buyer cria Connect de seller2', xuser.brief,
      lens: 'AR2');
  if (xuser.ok && xuser.map?['stripeAccountId'] != null) {
    c.hold(
      id: 'AR2-cross-user-connect',
      lens: 'AR2',
      severity: 'P0',
      title: 'Buyer criou/ligou Connect de outro user_id',
      actor: 'buyer JWT',
      pre: 'user_id=seller2',
      repro: 'POST create-connect-account user_id=S2',
      expected: '400 Cannot create another user',
      obtained: xuser.brief,
    );
  } else {
    c.block('AR2.cross-user', 'AR2', 'user_id cruzado', xuser);
  }

  // ---------------------------------------------------------------------------
  // AR4 — webhook: transfer.created / charge.refunded (não o unsigned clássico só)
  // ---------------------------------------------------------------------------
  for (final t in [
    'transfer.created',
    'payout.paid',
    'charge.refunded',
    'account.updated',
  ]) {
    final wh = await c.edge('stripe-webhook', {
      'type': t,
      'data': {
        'object': {
          'id': 'tr_fake_ar',
          'amount': 99999,
          'destination': 'acct_fake',
        }
      },
    }, extra: {
      'stripe-signature': 't=1,v1=deadbeef',
    });
    c.note('ar4.wh.$t', 'webhook $t assinatura lixo', wh.brief, lens: 'AR4');
    if (wh.ok && wh.map?['ok'] == true && wh.map?['ignored'] == null) {
      c.hold(
        id: 'AR4-webhook-$t',
        lens: 'AR4',
        severity: 'P0',
        title: 'Webhook $t aceite com assinatura inválida',
        actor: 'anon',
        pre: 'stripe-signature lixo',
        repro: 'POST stripe-webhook type=$t',
        expected: '400 invalid_signature',
        obtained: wh.brief,
      );
    } else {
      c.block('AR4.wh.$t', 'AR4', '$t assinatura lixo', wh);
    }
  }

  final gql = await c.req('POST', '/graphql/v1', jwt: c.buyerJwt, body: {
    'query':
        'mutation { updatewalletsCollection(filter: {id:{eq:"${c.sellerId}"}}, set: {balance: 999}) { records { id balance } } }',
  });
  c.note('ar1.graphql', 'GraphQL update wallets', gql.brief, lens: 'AR1');
  if (gql.ok && gql.body.contains('"balance"') && gql.body.contains('999')) {
    c.hold(
      id: 'AR1-graphql-wallet',
      lens: 'AR1',
      severity: 'P0',
      title: 'GraphQL alterou balance',
      actor: 'buyer JWT',
      pre: '/graphql/v1',
      repro: 'mutation updatewalletsCollection',
      expected: '403 / disabled',
      obtained: gql.brief,
    );
  } else {
    c.block('AR1.graphql', 'AR1', 'GraphQL wallets', gql.status);
  }

  await c.dumpAll('pass1.json');
  stdout.writeln('PASS1 done findings=${c.findings.length} blocked=${c.blocked.length}');
  exit(0);
}
