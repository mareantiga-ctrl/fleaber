/// PASS 2 — Stripe TEST até concluido (mão) · L2 timing · L6 flags JWT.
import 'dart:io';

import '_rtl.dart';

void main() async {
  final env = loadEnv();
  final c = Rtl.fromEnv(env);
  await c.loginActors();

  final w0 = await c.wallets();
  c.note('p2.w0', 'wallets antes', w0, lens: 'L7');

  final oid = await c.payAndComplete(lens: 'L2');
  if (oid == null) {
    stderr.writeln('FAIL fixture payAndComplete');
    exit(4);
  }
  var row = await c.orderRow(oid);
  c.note('p2.order', 'após concluido mão', row, lens: 'L2');

  if ((row?['status'] ?? '').toString().toLowerCase() != 'concluido') {
    c.hold(
      id: 'RTL-L2-fixture-not-concluido',
      lens: 'L2',
      severity: 'P2',
      title: 'Fixture Stripe TEST não chegou a concluido',
      actor: 'buyer confirma receção',
      pre: 'setup_paid_order + enviado + concluido',
      repro: 'payAndComplete',
      expected: 'status=concluido',
      obtained: row,
      proven: false,
    );
  }

  // L6: JWT PATCH completed_at para o passado (disparo cedo via cron real).
  final past = isoPast(const Duration(hours: 72));
  final patchCompleted = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {'completed_at': past},
  );
  final afterCompleted = await c.orderRow(oid);
  c.note('p2.l6.completed_at.jwt', 'PATCH completed_at JWT', {
    'http': patchCompleted.brief,
    'completed_at': afterCompleted?['completed_at'],
  }, lens: 'L6');
  final ca = afterCompleted?['completed_at']?.toString() ?? '';
  if (patchCompleted.ok && ca.contains('202') && ca.compareTo(isoPast(const Duration(hours: 60))) < 0) {
    c.hold(
      id: 'RTL-L6-completed-at-backdate',
      lens: 'L6',
      severity: 'P0',
      title: 'JWT recua completed_at (abre auto-feedback imediato)',
      actor: 'buyer JWT',
      pre: 'order concluido há segundos',
      repro: 'PATCH orders.completed_at = now()-72h',
      expected: 'completed_at imutável / revertido para now()',
      obtained: afterCompleted?['completed_at'],
      evidence: {'http': patchCompleted.brief, 'row': afterCompleted},
    );
  }

  final patchAfFlag = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {'auto_feedback_processed_at': DateTime.now().toUtc().toIso8601String()},
  );
  final afterAfFlag = await c.orderRow(oid);
  c.note('p2.l6.af_flag.jwt', 'PATCH auto_feedback_processed_at JWT', {
    'http': patchAfFlag.brief,
    'flag': afterAfFlag?['auto_feedback_processed_at'],
  }, lens: 'L6');
  if (afterAfFlag?['auto_feedback_processed_at'] != null &&
      row?['auto_feedback_processed_at'] == null) {
    c.hold(
      id: 'RTL-L6-af-flag-jwt',
      lens: 'L6',
      severity: 'P1',
      title: 'JWT grava auto_feedback_processed_at',
      actor: 'buyer JWT',
      pre: 'flag null',
      repro: 'PATCH auto_feedback_processed_at',
      expected: 'order_auto_feedback_flag_immutable',
      obtained: afterAfFlag?['auto_feedback_processed_at'],
    );
  }

  final patchRel = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {
      'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String(),
    },
  );
  c.note('p2.l6.release_flag.jwt', 'PATCH wallet_release JWT', patchRel.brief,
      lens: 'L6');

  // L2: JWT tenta auto-feedback agora (sem 48h) e com p_now.
  final jwtNow = await c.rpc('batata_generate_auto_feedback', {}, jwt: c.buyerJwt);
  final jwtPnow = await c.rpc(
    'batata_generate_auto_feedback',
    {'p_now': isoFuture(const Duration(days: 30))},
    jwt: c.buyerJwt,
  );
  c.note('p2.l2.jwt.now', 'auto_feedback JWT now', jwtNow.brief, lens: 'L2');
  c.note('p2.l2.jwt.pnow', 'auto_feedback JWT p_now+30d', jwtPnow.brief,
      lens: 'L2');

  // L2: service p_now cedo sobre order RECENTE — o cron legítimo com relógio forjado.
  // Atacante não tem service; isto prova se o job respeita 48h quando p_now=now().
  final svcNow = await c.rpc('batata_generate_auto_feedback', {}, service: true);
  final reviewsNow = await c.reviewsFor(oid);
  final rowNow = await c.orderRow(oid);
  c.note('p2.l2.svc.now', 'cron service now() em order recente', {
    'rpc': svcNow.brief,
    'reviews': reviewsNow.length,
    'af_at': rowNow?['auto_feedback_processed_at'],
    'release_at': rowNow?['wallet_release_processed_at'],
  }, lens: 'L2');
  if (reviewsNow.isNotEmpty && rowNow?['auto_feedback_processed_at'] != null) {
    c.hold(
      id: 'RTL-L2-early-now',
      lens: 'L2',
      severity: 'P0',
      title: 'Auto-feedback dispara antes das 48h com p_now=now()',
      actor: 'cron service_role now()',
      pre: 'concluido há segundos',
      repro: 'rpc batata_generate_auto_feedback() service',
      expected: '0 reviews, flag null',
      obtained: {
        'reviews': reviewsNow.length,
        'af': rowNow?['auto_feedback_processed_at'],
      },
    );
  }

  // L2: order NÃO concluido — service backdate completed_at em pago.
  final paid2 = await c.e2e('setup_paid_order', {'initial_qty': 2});
  final oidPago = c.parseE2eOrderId(paid2);
  final pidPago = c.parseE2eProductId(paid2);
  if (pidPago != null) c.createdProductIds.add(pidPago);
  if (oidPago != null) {
    c.createdOrderIds.add(oidPago);
    await c.rest('PATCH', 'orders?id=eq.$oidPago', service: true, body: {
      'completed_at': past,
    });
    final beforePago = await c.orderRow(oidPago);
    final svcPago = await c.rpc(
      'batata_generate_auto_feedback',
      {'p_now': isoFuture(const Duration(days: 2))},
      service: true,
    );
    final afterPago = await c.orderRow(oidPago);
    final revPago = await c.reviewsFor(oidPago);
    c.note('p2.l2.sem_concluido', 'cron em pago + completed_at antigo', {
      'status': afterPago?['status'],
      'rpc': svcPago.brief,
      'reviews': revPago.length,
      'af': afterPago?['auto_feedback_processed_at'],
      'before_status': beforePago?['status'],
    }, lens: 'L2');
    if (revPago.isNotEmpty || afterPago?['auto_feedback_processed_at'] != null) {
      c.hold(
        id: 'RTL-L2-sem-concluido',
        lens: 'L2',
        severity: 'P0',
        title: 'Auto-feedback em order que não está concluido',
        actor: 'cron service + completed_at forjado',
        pre: 'status=pago, completed_at -72h',
        repro: 'PATCH completed_at; rpc auto_feedback p_now+2d service',
        expected: 'job ignora (filtro status=concluido)',
        obtained: {
          'status': afterPago?['status'],
          'reviews': revPago.length,
          'af': afterPago?['auto_feedback_processed_at'],
        },
      );
    }
  }

  // L2: simular 48h com service p_now (prova do job, não do JWT).
  // Se JWT não recuou completed_at, service recua para o teste de duplo.
  row = await c.orderRow(oid);
  if (row?['auto_feedback_processed_at'] == null) {
    await c.rest('PATCH', 'orders?id=eq.$oid', service: true, body: {
      'completed_at': past,
    });
  }
  final wBefore = await c.wallets();
  final first = await c.rpc(
    'batata_generate_auto_feedback',
    {'p_now': isoFuture(const Duration(hours: 1))},
    service: true,
  );
  final rev1 = await c.reviewsFor(oid);
  final row1 = await c.orderRow(oid);
  final wAfter1 = await c.wallets();
  final tx1 = await c.walletTxns(orderId: oid);
  c.note('p2.l2.svc.48h', 'cron após 48h simuladas', {
    'rpc': first.brief,
    'reviews': rev1,
    'af': row1?['auto_feedback_processed_at'],
    'release': row1?['wallet_release_processed_at'],
    'w_before': wBefore,
    'w_after': wAfter1,
    'tx': tx1,
  }, lens: 'L2');

  // L2 duplo: segundo cron imediato.
  final second = await c.rpc(
    'batata_generate_auto_feedback',
    {'p_now': isoFuture(const Duration(hours: 2))},
    service: true,
  );
  final rev2 = await c.reviewsFor(oid);
  final wAfter2 = await c.wallets();
  c.note('p2.l2.duplo', '2.º cron auto_feedback', {
    'rpc': second.brief,
    'reviews': rev2.length,
    'seller_delta': (wAfter2['seller'] ?? 0) - (wAfter1['seller'] ?? 0),
  }, lens: 'L2');
  if (rev2.length > rev1.length ||
      ((wAfter2['seller'] ?? 0) - (wAfter1['seller'] ?? 0)) > 0.009) {
    c.hold(
      id: 'RTL-L2-duplo',
      lens: 'L2',
      severity: 'P0',
      title: 'Auto-feedback / release duplica no 2.º cron',
      actor: 'cron service ×2',
      pre: 'já processado',
      repro: '2× batata_generate_auto_feedback p_now futuro',
      expected: 'idempotente (0 reviews extra, Δwallet=0)',
      obtained: {
        'reviews_1': rev1.length,
        'reviews_2': rev2.length,
        'd_seller': (wAfter2['seller'] ?? 0) - (wAfter1['seller'] ?? 0),
      },
    );
  }

  // L7: Δwallet desta order.
  final dSeller = (wAfter1['seller'] ?? 0) - (wBefore['seller'] ?? 0);
  c.note('p2.l7.delta', 'Δ seller no 1.º cron', {
    'd_seller': dSeller,
    'tx': tx1,
  }, lens: 'L7');

  await dumpJson('${outDir()}/pass2.json', {
    'stamp': stamp,
    'order_id': oid,
    'notes': c.notes,
    'findings': c.findings,
    'w0': w0,
    'w_before_cron': wBefore,
    'w_after1': wAfter1,
    'w_after2': wAfter2,
  });
  stdout.writeln('PASS2 done oid=$oid findings=${c.findings.length}');
}
