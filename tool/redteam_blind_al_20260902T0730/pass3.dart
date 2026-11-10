/// PASS 3 — AL buyer forja oferta disputa · B2 disputa limpa · SELECT cruzado.
import 'dart:io';
import '_rtal.dart';

Future<void> main() async {
  final c = Rtal.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  final w0 = await c.wallets();
  c.note('p3.snap', 'saldos', w0, lens: 'AL7');

  // ---------------------------------------------------------------------------
  // AL6 — buyer2 disputa em order B1 SEM disputa prévia
  // ---------------------------------------------------------------------------
  final paidB2 = await c.payToPago(lens: 'AL6');
  if (paidB2 != null) {
    await c.markMao(paidB2.oid);
    await c.rest('PATCH', 'orders?id=eq.${paidB2.oid}', jwt: c.buyerJwt, body: {
      'status': 'concluido',
    });
    final d2 = await c.insertDispute(paidB2.oid,
        jwt: c.buyer2Jwt, buyer: c.buyer2Id);
    c.note('al6.b2.clean-disp', 'buyer2 disputa order B1 (sem disputa)',
        d2.brief, lens: 'AL6');
    if (d2.ok && d2.firstId != null) {
      c.hold(
        id: 'AL6-b2-dispute-clean',
        lens: 'AL6',
        severity: 'P1',
        title: 'Buyer2 abriu disputa em encomenda de B1',
        actor: 'buyer2 JWT',
        pre: 'concluido, sem disputa, wallet_release null',
        repro: 'POST order_disputes buyer_id=B2 order_id=B1',
        expected: '403 RLS (order.buyer_id ≠ B2)',
        obtained: d2.brief,
      );
    } else {
      c.block('AL6-b2-clean', 'AL6', 'buyer2 disputa limpa recusada', d2);
    }
  }

  // ---------------------------------------------------------------------------
  // AL6 — buyer forja oferta do vendedor na disputa
  // ---------------------------------------------------------------------------
  final paidF = await c.payToPago(lens: 'AL6');
  if (paidF != null) {
    await c.markMao(paidF.oid);
    await c.rest('PATCH', 'orders?id=eq.${paidF.oid}', jwt: c.buyerJwt, body: {
      'status': 'concluido',
    });
    final disp = await c.insertDispute(paidF.oid);
    c.note('al6.forge.disp', 'disputa B1', disp.brief, lens: 'AL6');
    final forge = await c.rest(
      'PATCH',
      'order_disputes?order_id=eq.${paidF.oid}',
      jwt: c.buyerJwt,
      body: {
        'seller_offer_type': 'partial_refund',
        'seller_refund_percent': 40,
        'seller_offer_set_by': c.sellerId,
      },
    );
    c.note('al6.forge.offer', 'buyer PATCH oferta seller', forge.brief,
        lens: 'AL6');
    final part = await c.rpc('batata_process_partial_refund_dispute', {
      'p_order_id': paidF.oid,
      'p_refund_percent': 40,
    }, jwt: c.buyerJwt);
    c.note('al6.forge.partial', 'process_partial após oferta forjada',
        part.brief, lens: 'AL6');
    final w1 = await c.wallets();
    final dB = (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0);
    if (part.ok && '${part.body}' == 'true' && dB > 0.05) {
      c.hold(
        id: 'AL6-buyer-forged-seller-offer',
        lens: 'AL6',
        severity: 'P0',
        title: 'Buyer forjou oferta de reembolso do vendedor e mintou wallet',
        actor: 'buyer JWT',
        pre: 'disputa aberta; seller não ofereceu',
        repro: 'PATCH order_disputes seller_offer_* + process_partial',
        expected: 'seller_offer_set_by só pelo vendedor; sem mint',
        obtained: {'forge': forge.brief, 'rpc': part.brief, 'dB': dB},
      );
    } else if (forge.ok && forge.map != null) {
      final pct = forge.map?['seller_refund_percent'];
      final setBy = forge.map?['seller_offer_set_by'];
      if (pct != null || setBy == c.sellerId) {
        c.hold(
          id: 'AL6-buyer-writes-seller-offer',
          lens: 'AL6',
          severity: 'P2',
          title: 'Buyer consegue gravar oferta de reembolso em nome do vendedor',
          actor: 'buyer JWT',
          pre: 'disputa própria',
          repro: 'PATCH order_disputes seller_refund_percent',
          expected: 'colunas só vendedor / 0 rows',
          obtained: forge.brief,
          evidence: {'percent': pct, 'set_by': setBy, 'rpc': part.brief},
        );
      } else {
        c.block('AL6-forge', 'AL6', 'oferta forjada sem efeito útil', {
          'forge': forge.brief,
          'rpc': part.brief,
        });
      }
    } else {
      c.block('AL6-forge-patch', 'AL6', 'PATCH oferta buyer recusado/vazio', {
        'forge': forge.brief,
        'rpc': part.brief,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // AL1 — SELECT carteira / ledger alheia
  // ---------------------------------------------------------------------------
  final selSeller = await c.rest(
    'GET',
    'wallets?id=eq.${c.sellerId}&select=id,balance,stripe_account_id',
    jwt: c.buyerJwt,
  );
  c.note('al1.select.cross-wallet', 'buyer GET wallet seller', selSeller.brief,
      lens: 'AL1');
  if (selSeller.ok && selSeller.map?['balance'] != null) {
    c.hold(
      id: 'AL1-select-foreign-wallet',
      lens: 'AL1',
      severity: 'P2',
      title: 'Buyer lê saldo e Connect do vendedor',
      actor: 'buyer JWT',
      pre: 'RLS wallets select own',
      repro: 'GET wallets?id=eq.seller',
      expected: '200 []',
      obtained: selSeller.brief,
    );
  } else {
    c.block('AL1-sel-w', 'AL1', 'SELECT wallet alheia vazia', selSeller);
  }

  final selLed = await c.rest(
    'GET',
    'wallet_payout_ledger?user_id=eq.${c.sellerId}&select=idempotency_key,amount_cents,status,stripe_transfer_id&limit=3',
    jwt: c.buyerJwt,
  );
  c.note('al1.select.ledger', 'buyer GET ledger seller', selLed.brief,
      lens: 'AL1');
  if (selLed.ok && selLed.list.isNotEmpty) {
    c.hold(
      id: 'AL1-select-foreign-ledger',
      lens: 'AL1',
      severity: 'P2',
      title: 'Buyer lê ledger de levantamento do vendedor',
      actor: 'buyer JWT',
      pre: 'RLS ledger select own',
      repro: 'GET wallet_payout_ledger?user_id=eq.seller',
      expected: '200 []',
      obtained: selLed.brief,
    );
  } else {
    c.block('AL1-sel-led', 'AL1', 'SELECT ledger alheia vazia', selLed);
  }

  // ---------------------------------------------------------------------------
  // AL4 — observar Transfer dest hijack (pass1) via Stripe TEST
  // ---------------------------------------------------------------------------
  final tr = await c.stripe('GET', '/v1/transfers/tr_1UB7n4H7FWYUN3jhhGwUl9H6');
  c.note('al2.stripe.dest', 'Transfer pass1 destination body ignorado', {
    'status': tr.status,
    'destination': tr.map?['destination'],
    'amount': tr.map?['amount'],
    'meta': tr.map?['metadata'],
  }, lens: 'AL2');

  final wEnd = await c.wallets();
  c.note('p3.final', 'saldos', {
    'start': w0,
    'end': wEnd,
    'dB': (wEnd['buyer'] ?? 0) - (w0['buyer'] ?? 0),
    'dS': (wEnd['seller'] ?? 0) - (w0['seller'] ?? 0),
  }, lens: 'AL7');

  await c.dumpAll('pass3.json');
  stdout.writeln(
      'DONE3 findings=${c.findings.length} blocked=${c.blocked.length}');
}
