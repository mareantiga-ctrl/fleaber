/// PASS 4 — overdraft verdadeiro (2× amount > saldo restante).
import '_rtbd.dart';

bool moneyMoved(HttpHit h) =>
    h.ok && (h.transferId != null || h.map?['success'] == true);

Future<void> main() async {
  final c = Rtbd.fromEnv(loadEnv());
  await c.loginActors();
  final bal = await c.walletBal(c.sellerId);
  final cents = (bal * 100).round();
  c.note('p4.bal', 'saldo', {'eur': bal, 'cents': cents}, lens: 'BD6');
  if (cents < 200) {
    c.skip('BD6.od', 'BD6', 'saldo <2€ para overdraft', bal);
    await c.dumpAll('pass4.json');
    return;
  }
  final each = cents; // cada pedido = 100% do saldo
  final hits = await parallel([
    c.payout(amount: each, key: '${prefix}-od-a-${DateTime.now().microsecondsSinceEpoch}'),
    c.payout(amount: each, key: '${prefix}-od-b-${DateTime.now().microsecondsSinceEpoch}'),
  ]);
  final ok = hits.where(moneyMoved).toList();
  final tr = ok.map((h) => h.transferId).whereType<String>().toSet();
  final wAfter = await c.walletBal(c.sellerId);
  c.note('bd6.overdraft', '2× payout = 100% saldo cada', {
    'each': each,
    'ok': ok.length,
    'uniqueTr': tr.length,
    'briefs': hits.map((h) => h.brief).toList(),
    'wAfter': wAfter,
  }, lens: 'BD6');
  if (tr.length >= 2 || wAfter < -0.009) {
    c.finding(
      id: 'BD6-overdraft-2x-full-balance',
      lens: 'BD6',
      severity: 'P0',
      title: 'Dois payouts paralelos do saldo inteiro geraram 2 Transfers / saldo negativo',
      actor: 'seller JWT',
      pre: 'saldo $bal €; 2× $each ¢ keys distintas',
      repro: 'Future.wait 2× payout amount=balance',
      expected: '1 Transfer + insufficient_balance; saldo ≥0',
      obtained: {'tr': tr.length, 'wAfter': wAfter, 'ok': ok.length},
    );
  } else {
    c.block('BD6.overdraft', 'BD6', '2º payout recusado; sem saldo negativo', {
      'ok': ok.length,
      'tr': tr.length,
      'wAfter': wAfter,
    });
  }
  await c.dumpAll('pass4.json');
}
