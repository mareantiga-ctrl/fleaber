/// Ledger after hosted 4242 on A1 bag + confirm bag; orphan still unpaid?
import 'dart:io';
import '_rtes.dart';

Future<Map<String, Object?>> snapOrders(Rtdb c, List<String> oids) async {
  final ledger = <Map<String, Object?>>[];
  for (final id in oids) {
    final o = await c.orderRow(id);
    final p = o == null ? null : await c.productRow('${o['product_id']}');
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
  return {
    'ledger': ledger,
    'pagos': ledger.where((e) => '${e['status']}'.toLowerCase() == 'pago').length,
    'qtys': ledger.map((e) => e['qty']).toSet().toList(),
    'statuses': ledger.map((e) => e['status']).toSet().toList(),
  };
}

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();

  const a1bag =
      'cs_test_a1d3UdJJ5PmNC7poJ7cP4lX4jDs96YaCjqEMZCkR3fxCnlrcnJB4xbwhXG';
  const a1orph =
      'cs_test_a1XxM9eg8KaXSk3PNdhuqWTKiXs9NWuowp1ln5LRbcRsdCakLuI2Yvb2zh';
  const cbag =
      'cs_test_a1bzcBWodckk9REPaeJ7LAisgCF6R2u6nTxhbOA6F3gGDhTvcNumGT42vG';
  const corph =
      'cs_test_a15s8rmoJdCDJGPCXZI7T742wjqugYpa6R1sw92ziPBIjgF38qoYOO5fj0';

  final a1oids = [
    'b31ad253-7910-4497-b09b-7dcd904e9891',
    '50de1f5d-aa01-4af7-99d7-aa953a68b768',
    '08055bc3-cae9-4edf-b203-968361bef5c1',
    '60eb76e9-4426-47ae-be2c-b4ccf053afb0',
    '037a405a-b1a3-49a4-8373-22e0e9155312',
  ];
  final coids = [
    '9e8f28f7-7035-4543-8983-42e5568d04f9',
    '8498f640-532d-4708-8c84-bc7958230091',
    '526c3e46-f042-4dae-ace0-602aa3552c8f',
    'af9ce63a-e99f-47f4-a426-c2e373ccc733',
    'a72d1390-7c9a-44ae-9b41-b0debd511cbf',
  ];

  final s = {
    'a1_bag': (await c.settleGet(a1bag)).brief,
    'a1_orph': (await c.settleGet(a1orph)).brief,
    'confirm_bag': (await c.settleGet(cbag)).brief,
    'confirm_orph': (await c.settleGet(corph)).brief,
  };
  for (final e in s.entries) {
    stdout.writeln('${e.key} ${e.value}');
  }

  final a1 = await snapOrders(c, a1oids);
  final conf = await snapOrders(c, coids);
  final wallets = await c.wallets();
  final out = {
    'settle': s,
    'a1': a1,
    'confirm': conf,
    'wallets': wallets,
  };
  await dumpJson('${outDir()}/ledger_after_hosted.json', out);
  stdout.writeln(
    'A1 pagos=${a1['pagos']} ${a1['statuses']} qty=${a1['qtys']}',
  );
  stdout.writeln(
    'confirm pagos=${conf['pagos']} ${conf['statuses']} qty=${conf['qtys']}',
  );
  stdout.writeln('wallets $wallets');
}
