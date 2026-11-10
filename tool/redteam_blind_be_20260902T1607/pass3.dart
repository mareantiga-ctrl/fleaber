/// RED TEAM CEGO BE — pass 3. Fechar contabilística e falsos positivos.
import 'dart:io';
import '_rtbe.dart';

Future<void> main() async {
  final c = Rtbe.fromEnv(loadEnv());
  await c.loginActors();

  const ids = {
    'p2': 'fbd46089-ab95-420f-816a-f768584c9552',
    'n1': '916cac96-b102-4ed5-becd-70e68f4df811',
    'n3': '600c31a8-0883-4526-8056-509602d90c25',
    'p5': 'cc4dbd38-d21a-4a97-aa7b-5a5228086532',
    'p8': '17b4d90a-99e9-4beb-8dc3-c5bf6a1b540f',
  };

  for (final e in ids.entries) {
    final row = await c.orderRow(e.value);
    final prod = row?['product_id'] == null
        ? null
        : await c.productRow('${row!['product_id']}');
    c.note('final.${e.key}', 'row', {
      'status': row?['status'],
      'refund': row?['stripe_refund_id'],
      'applied': row?['stock_units_applied'],
      'qty_prod': prod?['quantity'],
      'release': row?['wallet_release_processed_at'],
      'wrefund': row?['wallet_refund_processed_at'],
      'shipped_at': row?['shipped_at'],
      'paid': row?['amount_paid_cents'],
    }, lens: 'BE8');
  }

  c.note('wallets.final', 'saldos', await c.wallets(), lens: 'BE8');

  // n1: pago→em_devolucao→devolucao_entregue sem disputa. Consegue devolvida?
  final dv = await c.patchOrder(ids['n1']!, {'status': 'devolvida'}, jwt: c.sellerJwt);
  final n1 = await c.orderRow(ids['n1']!);
  c.note('BE1.n1.devolvida', 'S1 devolvida sem disputa desde pago-skip', {
    'hit': dv.brief,
    'status': n1?['status'],
  }, lens: 'BE1');
  if ('${n1?['status']}' == 'devolvida') {
    c.hold(
      id: 'BE1.devolvida_without_dispute',
      lens: 'BE1',
      severity: 'P1',
      title: 'S1 chega a devolvida sem disputa (skip desde pago)',
      actor: 'S1 JWT',
      pre: 'pago→em_devolucao→devolucao_entregue, sem order_disputes',
      repro: 'PATCH devolvida',
      expected: 'order_devolvida_requires_dispute',
      obtained: n1?['status'],
    );
    final rf = await c.refund(ids['n1']!, jwt: c.sellerJwt);
    final n1b = await c.orderRow(ids['n1']!);
    final qty = (await c.productRow('${n1b?['product_id']}'))?['quantity'];
    c.note('BE1.n1.refund', 'refund n1', {
      'hit': rf.brief,
      'status': n1b?['status'],
      'refund': n1b?['stripe_refund_id'],
      'qty': qty,
    }, lens: 'BE4');
  } else {
    c.block('BE1.devolvida_without_dispute', 'BE1', 'devolvida sem disputa', dv);
  }

  // Ledger seller — movimentos recentes
  final led = await c.rest(
    'GET',
    'wallet_ledger?user_id=eq.${c.sellerId}&select=id,user_id,amount,entry_type,order_id,description,created_at&order=created_at.desc&limit=12',
    service: true,
  );
  c.note('ledger.seller', 'últimos movimentos seller', led.brief, lens: 'BE8');

  final ledB = await c.rest(
    'GET',
    'wallet_ledger?user_id=eq.${c.buyerId}&select=id,user_id,amount,entry_type,order_id,description,created_at&order=created_at.desc&limit=8',
    service: true,
  );
  c.note('ledger.buyer', 'últimos movimentos buyer', ledB.brief, lens: 'BE8');

  // Disputas n1
  final d1 = await c.rest(
    'GET',
    'order_disputes?order_id=eq.${ids['n1']}&select=id,status',
    service: true,
  );
  c.note('BE1.n1.disp', 'disputas n1', d1.brief, lens: 'BE1');

  await c.dumpAll('pass3.json');
  stdout.writeln(
      'DONE pass3 findings=${c.findings.length} blocked=${c.blocked.length}');
}
