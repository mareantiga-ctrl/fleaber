/// PASS 3 — L3 cron vs review humana · L5 races · L6 soft-delete · L7 Δwallet.
import 'dart:io';

import '_rtl.dart';

Future<HttpHit> humanReview(Rtl c, String oid, int stars) {
  return c.rest('POST', 'reviews', jwt: c.buyerJwt, body: {
    'order_id': oid,
    'buyer_id': c.buyerId,
    'target_id': c.sellerId,
    'stars': stars,
    'comment': '$prefix human $stars',
    'author_role': 'comprador',
    'target_type': 'seller',
    'is_automatic': false,
  });
}

void main() async {
  final env = loadEnv();
  final c = Rtl.fromEnv(env);
  await c.loginActors();

  final past = isoPast(const Duration(hours: 49));

  // ---- Order A: review humana 5★ isolada (sem cron na mesma transação) ----
  final oidA = await c.payAndComplete(lens: 'L3');
  if (oidA == null) {
    stderr.writeln('FAIL oidA');
    exit(4);
  }
  final wA0 = await c.wallets();
  final rev5 = await humanReview(c, oidA, 5);
  final rowA = await c.orderRow(oidA);
  final revsA = await c.reviewsFor(oidA);
  final wA1 = await c.wallets();
  c.note('p3.l3.human5', 'review humana 5★ sem cron', {
    'http': rev5.brief,
    'release': rowA?['wallet_release_processed_at'],
    'reviews': revsA,
    'd_seller': (wA1['seller'] ?? 0) - (wA0['seller'] ?? 0),
  }, lens: 'L3');

  if (!rev5.ok) {
    c.hold(
      id: 'RTL-L3-human-5-blocked',
      lens: 'L3',
      severity: 'P1',
      title: 'Review humana 5★ bloqueada — só o cron liberta a carteira',
      actor: 'buyer INSERT reviews',
      pre: 'Stripe TEST concluido (mão), wallet_release null',
      repro: 'POST reviews stars=5 author_role=comprador',
      expected: '201 + libertação wallet OU review aceite sem side-effect ilegal',
      obtained: rev5.brief,
      evidence: {
        'row': rowA,
        'd_seller': (wA1['seller'] ?? 0) - (wA0['seller'] ?? 0),
      },
    );
  } else if (rowA?['wallet_release_processed_at'] != null &&
      ((wA1['seller'] ?? 0) - (wA0['seller'] ?? 0)) > 0.009) {
    c.note('p3.l3.human5.release', 'humana 5★ libertou wallet (caminho humano vivo)',
        {'d_seller': (wA1['seller'] ?? 0) - (wA0['seller'] ?? 0)},
        lens: 'L3');
  }

  // Review 1★ noutro order (não deve libertar; stars<4).
  final oidLow = await c.payAndComplete(lens: 'L3');
  if (oidLow != null) {
    final wL0 = await c.wallets();
    final rev1 = await humanReview(c, oidLow, 1);
    final rowL = await c.orderRow(oidLow);
    final wL1 = await c.wallets();
    c.note('p3.l3.human1', 'review humana 1★', {
      'http': rev1.brief,
      'release': rowL?['wallet_release_processed_at'],
      'd_seller': (wL1['seller'] ?? 0) - (wL0['seller'] ?? 0),
    }, lens: 'L3');

    // L6: DELETE da 1★ e cron a forjar 5★.
    if (rev1.ok && rev1.firstId != null) {
      final del = await c.rest(
        'DELETE',
        'reviews?id=eq.${rev1.firstId}',
        jwt: c.buyerJwt,
      );
      c.note('p3.l6.delete', 'JWT DELETE review própria', del.brief, lens: 'L6');
      await c.rest('PATCH', 'orders?id=eq.$oidLow', service: true, body: {
        'completed_at': past,
        'auto_feedback_processed_at': null,
      });
      final cronAfterDel = await c.rpc(
        'batata_generate_auto_feedback',
        {'p_now': isoFuture()},
        service: true,
      );
      final revsAfterDel = await c.reviewsFor(oidLow);
      c.note('p3.l6.cron_after_delete', 'cron após DELETE review', {
        'rpc': cronAfterDel.brief,
        'reviews': revsAfterDel,
      }, lens: 'L6');
      final forged = revsAfterDel.any((r) {
        final m = Map<String, dynamic>.from(r as Map);
        return m['is_automatic'] == true && (m['stars'] as num?) == 5;
      });
      if (del.ok && forged) {
        c.hold(
          id: 'RTL-L6-delete-then-cron-5star',
          lens: 'L6',
          severity: 'P1',
          title: 'JWT apaga 1★ e o cron forja 5★ automáticas',
          actor: 'buyer DELETE reviews ∥ cron',
          pre: 'review humana 1★',
          repro: 'DELETE reviews JWT; rpc auto_feedback p_now futuro',
          expected: 'review imutável ou cron respeita histórico',
          obtained: revsAfterDel,
        );
      }
    } else if (!rev1.ok && oidLow != null) {
      // Se 1★ também bloqueada, cron 48h ainda liberta?
      await c.rest('PATCH', 'orders?id=eq.$oidLow', service: true, body: {
        'completed_at': past,
      });
      final wL2 = await c.wallets();
      final cronLow = await c.rpc(
        'batata_generate_auto_feedback',
        {'p_now': isoFuture()},
        service: true,
      );
      final wL3 = await c.wallets();
      final rowL2 = await c.orderRow(oidLow);
      c.note('p3.l3.cron_after_1star_blocked', 'cron após 1★ bloqueada', {
        'rpc': cronLow.brief,
        'release': rowL2?['wallet_release_processed_at'],
        'd_seller': (wL3['seller'] ?? 0) - (wL2['seller'] ?? 0),
      }, lens: 'L3');
    }
  }

  // ---- L5 race: humana 5★ ∥ cron (order B, completed_at -49h) ----
  final oidB = await c.payAndComplete(lens: 'L5');
  if (oidB == null) {
    stderr.writeln('FAIL oidB');
    exit(4);
  }
  await c.rest('PATCH', 'orders?id=eq.$oidB', service: true, body: {
    'completed_at': past,
  });
  final wB0 = await c.wallets();
  final raced = await parallel([
    humanReview(c, oidB, 5),
    c.rpc(
      'batata_generate_auto_feedback',
      {'p_now': isoFuture()},
      service: true,
    ),
  ]);
  final rowB = await c.orderRow(oidB);
  final revsB = await c.reviewsFor(oidB);
  final wB1 = await c.wallets();
  final txB = await c.walletTxns(orderId: oidB);
  c.note('p3.l5.review_cron', 'humana 5★ ∥ cron', {
    'human': raced[0].brief,
    'cron': raced[1].brief,
    'reviews': revsB,
    'release': rowB?['wallet_release_processed_at'],
    'd_seller': (wB1['seller'] ?? 0) - (wB0['seller'] ?? 0),
    'tx': txB,
  }, lens: 'L5');

  final vendaTx = txB.where((t) {
    final m = Map<String, dynamic>.from(t as Map);
    return m['type'] == 'venda' && m['order_id'] == oidB;
  }).length;
  if (vendaTx > 1) {
    c.hold(
      id: 'RTL-L5-double-credit-review-cron',
      lens: 'L5',
      severity: 'P0',
      title: 'Race review humana ∥ cron credita wallet duas vezes',
      actor: 'buyer INSERT reviews ∥ cron',
      pre: 'concluido + completed_at -49h',
      repro: 'Future.wait POST reviews ∥ batata_generate_auto_feedback',
      expected: '1 crédito venda',
      obtained: {'venda_tx': vendaTx, 'tx': txB, 'd_seller': (wB1['seller'] ?? 0) - (wB0['seller'] ?? 0)},
    );
  }

  // ---- L5 race: refund-order ∥ cron auto-feedback ----
  final oidC = await c.payAndComplete(lens: 'L5');
  if (oidC != null) {
    await c.rest('PATCH', 'orders?id=eq.$oidC', service: true, body: {
      'completed_at': past,
    });
    final wC0 = await c.wallets();
    final raceRf = await parallel([
      c.edge('refund-order', {'order_id': oidC}, jwt: c.sellerJwt),
      c.rpc(
        'batata_generate_auto_feedback',
        {'p_now': isoFuture()},
        service: true,
      ),
    ]);
    final rowC = await c.orderRow(oidC);
    final wC1 = await c.wallets();
    final txC = await c.walletTxns(orderId: oidC);
    c.note('p3.l5.refund_cron', 'refund-order ∥ cron', {
      'refund': raceRf[0].brief,
      'cron': raceRf[1].brief,
      'row': rowC,
      'd_seller': (wC1['seller'] ?? 0) - (wC0['seller'] ?? 0),
      'tx': txC,
    }, lens: 'L5');
    final released = rowC?['wallet_release_processed_at'] != null;
    final refunded = (rowC?['stripe_refund_id'] ?? '').toString().isNotEmpty ||
        rowC?['wallet_refund_processed_at'] != null;
    if (released && refunded) {
      final dSeller = (wC1['seller'] ?? 0) - (wC0['seller'] ?? 0);
      if (dSeller > 0.009) {
        c.hold(
          id: 'RTL-L5-refund-and-release',
          lens: 'L5',
          severity: 'P0',
          title: 'Refund ∥ cron: seller fica com crédito após reembolso',
          actor: 'seller refund-order ∥ cron',
          pre: 'concluido -49h',
          repro: 'Future.wait refund-order ∥ auto_feedback',
          expected: 'não creditar venda se refund ganhou; não refund se release ganhou sem compensação',
          obtained: {
            'd_seller': dSeller,
            'row': rowC,
            'refund_http': raceRf[0].brief,
          },
        );
      }
    }
  }

  // L6: JWT INSERT is_automatic=true (forjar auto-feedback).
  final oidD = await c.payAndComplete(lens: 'L6');
  if (oidD != null) {
    final fake = await c.rest('POST', 'reviews', jwt: c.buyerJwt, body: {
      'order_id': oidD,
      'buyer_id': c.buyerId,
      'target_id': c.sellerId,
      'stars': 5,
      'comment': 'forjado automatico',
      'author_role': 'comprador',
      'target_type': 'seller',
      'is_automatic': true,
    });
    final revsD = await c.reviewsFor(oidD);
    c.note('p3.l6.forge_auto', 'JWT INSERT is_automatic=true', {
      'http': fake.brief,
      'reviews': revsD,
    }, lens: 'L6');
    final kept = revsD.any((r) {
      final m = Map<String, dynamic>.from(r as Map);
      return m['is_automatic'] == true &&
          (m['comment'] ?? '').toString().contains('forjado');
    });
    if (fake.ok && kept) {
      c.hold(
        id: 'RTL-L6-forge-is-automatic',
        lens: 'L6',
        severity: 'P1',
        title: 'JWT cria review is_automatic=true',
        actor: 'buyer INSERT reviews',
        pre: 'concluido',
        repro: 'POST reviews is_automatic=true',
        expected: 'trigger força is_automatic=false ou recusa',
        obtained: revsD,
      );
    }
  }

  await dumpJson('${outDir()}/pass3.json', {
    'stamp': stamp,
    'notes': c.notes,
    'findings': c.findings,
  });
  stdout.writeln('PASS3 done findings=${c.findings.length}');
}
