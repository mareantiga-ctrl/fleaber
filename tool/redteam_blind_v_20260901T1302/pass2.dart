/// Pass 2 — provas limpas V1/V8 (sem refund no meio; buyer hop desde enviado).
import 'dart:io';

import '_rtv.dart';

Future<void> main() async {
  final c = Rtv.fromEnv(loadEnv());
  await c.loginActors();

  // A: buyer unship directo desde enviado
  final a = await c.setupPaidStripe();
  final oa = a['order_id'];
  if (oa != null) {
    await c.rest('PATCH', 'orders?id=eq.$oa', jwt: c.sellerJwt, body: {
      'status': 'enviado',
    });
    final before = await c.orderRow(oa);
    final hop = await c.rest('PATCH', 'orders?id=eq.$oa', jwt: c.buyerJwt, body: {
      'status': 'reserva_pendente',
    });
    final after = await c.orderRow(oa);
    final buyerUnship = '${after?['status']}' == 'reserva_pendente';
    if (buyerUnship && '${before?['status']}' == 'enviado') {
      c.hold(
        id: 'RTV-V1-buyer-unship-from-enviado',
        lens: 'V1',
        severity: 'P0',
        title: 'Comprador unship directo enviado→reserva_pendente',
        actor: 'buyer JWT',
        pre: 'Stripe pago, seller marcou enviado, sem hops prévios',
        repro: 'PATCH orders status=reserva_pendente',
        expected: 'permanece enviado',
        obtained: {
          'http': hop.brief,
          'before': before?['status'],
          'after': after?['status'],
          'stripe_refund_id': after?['stripe_refund_id'],
        },
        evidence: {'pi': a['pi'], 'amount_paid_cents': after?['amount_paid_cents']},
      );
    } else {
      c.closed('V1.buyer.from-enviado', 'buyer não unshipa desde enviado', {
        'http': hop.brief,
        'before': before?['status'],
        'after': after?['status'],
      }, lens: 'V1');
    }
  }

  // B: seller hop enviado→reserva_pendente→pago SEM refund no meio
  final b = await c.setupPaidStripe();
  final ob = b['order_id'];
  if (ob != null) {
    await c.rest('PATCH', 'orders?id=eq.$ob', jwt: c.sellerJwt, body: {
      'status': 'enviado',
    });
    final s1 = await c.orderRow(ob);
    final hop1 = await c.rest('PATCH', 'orders?id=eq.$ob', jwt: c.sellerJwt, body: {
      'status': 'reserva_pendente',
    });
    final mid = await c.orderRow(ob);
    final hop2 = await c.rest('PATCH', 'orders?id=eq.$ob', jwt: c.sellerJwt, body: {
      'status': 'pago',
    });
    final end = await c.orderRow(ob);
    c.note('V1.clean.hop2', 'enviado→RP→pago sem refund', {
      's1': s1?['status'],
      'hop1': hop1.brief,
      'mid': mid?['status'],
      'hop2': hop2.brief,
      'end': end?['status'],
      'stripe_refund_id': end?['stripe_refund_id'],
      'pi': end?['stripe_payment_intent_id'],
    }, lens: 'V1');
    if ('${s1?['status']}' == 'enviado' &&
        '${mid?['status']}' == 'reserva_pendente' &&
        '${end?['status']}' == 'pago') {
      c.hold(
        id: 'RTV-V1-hop-rp-then-pago-no-refund',
        lens: 'V1',
        severity: 'P0',
        title: 'enviado→reserva_pendente→pago sem passar por refund',
        actor: 'seller JWT',
        pre: 'Stripe capturado, enviado; stripe_refund_id vazio',
        repro: 'PATCH reserva_pendente; PATCH pago',
        expected: 'bloqueado em algum dos dois PATCH',
        obtained: {
          'mid': mid?['status'],
          'end': end?['status'],
          'stripe_refund_id': end?['stripe_refund_id'],
        },
        evidence: {
          'pi': b['pi'],
          'amount_paid_cents': end?['amount_paid_cents'],
        },
      );
      // refund-order agora que está "pago" outra vez após envio real
      final rf = await c.refundOrder(ob);
      final afterRf = await c.orderRow(ob);
      c.note('V8.refund.after.clean-hop', 'refund-order após hop pago', {
        'http': rf.brief,
        'status': afterRf?['status'],
        'stripe_refund_id': afterRf?['stripe_refund_id'],
      }, lens: 'V8');
      if ('${afterRf?['stripe_refund_id'] ?? ''}'.trim().isNotEmpty ||
          (rf.map?['ok'] == true && rf.map?['skipped'] != true)) {
        c.hold(
          id: 'RTV-V8-refund-after-clean-hop-pago',
          lens: 'V8',
          severity: 'P0',
          title: 'refund-order após hop enviado→RP→pago (envio real, PI ainda capturado)',
          actor: 'seller JWT',
          pre: 'status=pago via hop; stripe_refund_id estava vazio',
          repro: 'POST refund-order',
          expected: 'bloqueado (já enviado)',
          obtained: {
            'http': rf.brief,
            'stripe_refund_id': afterRf?['stripe_refund_id'],
            'status': afterRf?['status'],
          },
        );
      }
    }
  }

  // C: cancelado (via refund pré-envio) → pago
  final d = await c.setupPaidStripe();
  final od = d['order_id'];
  if (od != null) {
    final rf = await c.refundOrder(od);
    final mid = await c.orderRow(od);
    final back = await c.rest('PATCH', 'orders?id=eq.$od', jwt: c.sellerJwt, body: {
      'status': 'pago',
    });
    final end = await c.orderRow(od);
    c.note('V1.cancelado-pago', 'refund em pago depois PATCH pago', {
      'refund': rf.brief,
      'mid': mid?['status'],
      'back': back.brief,
      'end': end?['status'],
      'stripe_refund_id': end?['stripe_refund_id'],
    }, lens: 'V1');
    if ('${mid?['status']}' == 'cancelado' && '${end?['status']}' == 'pago') {
      c.hold(
        id: 'RTV-V1-cancelado-to-pago',
        lens: 'V1',
        severity: 'P1',
        title: 'Após refund Stripe (cancelado) o seller volta a pago',
        actor: 'seller JWT',
        pre: 'refund-order em pago (antes de enviar) → cancelado',
        repro: 'PATCH status=pago',
        expected: 'cancelado terminal / order_cannot_reopen_pago',
        obtained: {
          'mid': mid?['status'],
          'end': end?['status'],
          'stripe_refund_id': end?['stripe_refund_id'],
        },
      );
    } else {
      c.closed('V1.cancelado-pago', 'cancelado não reabre pago', {
        'mid': mid?['status'],
        'end': end?['status'],
        'http': back.brief,
      }, lens: 'V1');
    }
  }

  await dumpJson('${outDir()}/pass2.json', {
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
  });
  stdout.writeln('PASS2 findings=${c.findings.length} blocked=${c.blocked.length}');
}
