/// RED TEAM CEGO AS — pass 3. Composição: pago→entregue→concluido sem disputa + release.
/// Staging only. Não corrige.
import 'dart:io';
import '_rtas.dart';

Future<void> main() async {
  final c = Rtas.fromEnv(loadEnv());
  await c.loginActors();

  final paid = await c.payToPago(lens: 'AS8', initialQty: 1);
  if (paid == null) {
    stderr.writeln('fixture fail');
    exit(1);
  }
  final w0 = await c.wallets();
  final e1 = await c.patchOrder(
    paid.oid,
    {'status': 'entregue'},
    jwt: c.sellerJwt,
  );
  final e2 = await c.patchOrder(
    paid.oid,
    {'status': 'concluido'},
    jwt: c.sellerJwt,
  );
  final o = await c.orderRow(paid.oid);
  final rel = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': paid.oid},
    jwt: c.buyerJwt,
  );
  final w1 = await c.wallets();
  final delta = ((w1['seller'] ?? 0) - (w0['seller'] ?? 0)).toDouble();
  c.note('AS8.no_ship_payout', 'pago→entregue→concluido seller + release buyer', {
    'entregue': e1.brief,
    'concluido': e2.brief,
    'order': o,
    'release': rel.brief,
    'w0': w0,
    'w1': w1,
    'delta_seller': delta,
    'pi': paid.pi,
  }, lens: 'AS8');

  if (e1.ok &&
      e2.ok &&
      o?['status'] == 'concluido' &&
      o?['shipped_at'] == null &&
      (rel.json == true || rel.body == 'true') &&
      delta > 0) {
    c.hold(
      id: 'AS8.payout_never_shipped',
      lens: 'AS8',
      severity: 'P0',
      title:
          'Seller salto pago→entregue→concluido (sem enviado/shipped_at) e release credita a carteira',
      actor: 'seller JWT hops + buyer JWT release',
      pre: 'pago capturado 5,90 €',
      repro:
          'PATCH entregue; PATCH concluido JWT=seller; rpc release JWT=buyer',
      expected: 'hop bloqueado e/ou release false sem shipped_at',
      obtained: {
        'status': o?['status'],
        'shipped_at': o?['shipped_at'],
        'release': rel.brief,
        'delta_seller_eur': delta,
        'wallet_release_processed_at': o?['wallet_release_processed_at'],
        'pi': paid.pi,
        'amount_paid_cents': o?['amount_paid_cents'],
      },
    );
  } else if (e1.ok && e2.ok && o?['status'] == 'concluido') {
    c.hold(
      id: 'AS8.concluido_never_shipped',
      lens: 'AS8',
      severity: 'P1',
      title: 'Seller chega a concluido sem shipped_at (release=${rel.brief})',
      actor: 'seller JWT',
      pre: 'pago',
      repro: 'PATCH entregue; PATCH concluido',
      expected: 'bloqueado',
      obtained: {
        'order': o,
        'release': rel.brief,
        'delta_seller': delta,
      },
    );
  } else {
    c.block('AS8.no_ship_payout', 'AS8', 'salto+release', {
      'entregue': e1.brief,
      'concluido': e2.brief,
      'status': o?['status'],
      'release': rel.brief,
      'delta': delta,
    });
  }

  await c.dumpAll('pass3.json');
  stdout.writeln(
      'PASS3 done findings=${c.findings.length} blocked=${c.blocked.length}');
}
