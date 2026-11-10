/// Ledger after hosted Stripe Checkout 4242 on A1 dual sessions.
import 'dart:io';
import '_rtes.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();

  const sid1 =
      'cs_test_a1d3UdJJ5PmNC7poJ7cP4lX4jDs96YaCjqEMZCkR3fxCnlrcnJB4xbwhXG';
  const sid2 =
      'cs_test_a1XxM9eg8KaXSk3PNdhuqWTKiXs9NWuowp1ln5LRbcRsdCakLuI2Yvb2zh';
  const oids = [
    'b31ad253-7910-4497-b09b-7dcd904e9891',
    '50de1f5d-aa01-4af7-99d7-aa953a68b768',
    '08055bc3-cae9-4edf-b203-968361bef5c1',
    '60eb76e9-4426-47ae-be2c-b4ccf053afb0',
    '037a405a-b1a3-49a4-8373-22e0e9155312',
  ];

  final s1 = await c.settleGet(sid1);
  final s2 = await c.settleGet(sid2);
  stdout.writeln('settle1 ${s1.brief}');
  stdout.writeln('settle2 ${s2.brief}');

  final ledger = <Map<String, Object?>>[];
  for (final id in oids) {
    final o = await c.orderRow(id);
    final p = await c.productRow('${o?['product_id']}');
    ledger.add({
      'oid': id,
      'status': o?['status'],
      'cs': o?['stripe_checkout_session_id'],
      'pi': o?['stripe_payment_intent_id'],
      'paid': o?['amount_paid_cents'],
      'applied': o?['stock_units_applied'],
      'qty': p?['quantity'],
      'sold': p?['is_sold'],
    });
  }
  final wallets = await c.wallets();
  final out = {
    'settle': {'s1': s1.brief, 's2': s2.brief},
    'ledger': ledger,
    'wallets': wallets,
    'pagos': ledger
        .where((e) => '${e['status']}'.toLowerCase() == 'pago')
        .length,
  };
  await dumpJson('${outDir()}/ledger_after_browser.json', out);
  stdout.writeln(
    'pagos=${out['pagos']} statuses=${ledger.map((e) => e['status']).toSet()} '
    'qtys=${ledger.map((e) => e['qty']).toSet()} '
    'seller=${wallets['seller']}',
  );
}
