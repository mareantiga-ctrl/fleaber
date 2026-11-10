/// Pagar as duas cs_ A1 (4242) + ledger.
import 'dart:io';
import '_rtes.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer3();

  const sid1 =
      'cs_test_a1BjYEA3HeSVskzVZ3rhLIXoTnn25bO2invtdwAjDZQSBXjebw1u9tY8PE';
  const sid2 =
      'cs_test_a1yQ9AkZO1H0FMemGUApbiMCGymvaNfljV3hlfL7JfV6fPilMjxph00KlC';
  const url1 =
      'https://checkout.stripe.com/c/pay/cs_test_a1BjYEA3HeSVskzVZ3rhLIXoTnn25bO2invtdwAjDZQSBXjebw1u9tY8PE#fidnandhYHdWcXxpYCc%2FJ2FgY2RwaXEnKSdicGRmZGhqaWBTZHdsZGtxJz8nZmprcXdqaScpJ2R1bE5gfCc%2FJ3VuWnFgdnFaMDRXdjRpSE0yQ1JcUEs2b21oYWlsUnxrVkRhQUQyNlJjSWBCN3BXNXVvVT1hamlcf3Fjd1dRMGJmREk9Yz09PH1CMzVTY0pBXD1kMU5HZl1da05gf0s1XGQ1NWA3bVFBNzNMJyknY3dqaFZgd3Ngdyc%2FcXdwYCknZ2RmbmJ3anBrYUZqaWp3Jz8nJmNjY2NjYycpJ2lkfGpwcVF8dWAnPyd2bGtiaWBabHFgaCcpJ2BrZGdpYFVpZGZgbWppYWB3dic%2FcXdwYHgl';
  const url2 =
      'https://checkout.stripe.com/c/pay/cs_test_a1yQ9AkZO1H0FMemGUApbiMCGymvaNfljV3hlfL7JfV6fPilMjxph00KlC#fidnandhYHdWcXxpYCc%2FJ2FgY2RwaXEnKSdicGRmZGhqaWBTZHdsZGtxJz8nZmprcXdqaScpJ2R1bE5gfCc%2FJ3VuWnFgdnFaMDRXdjRpSE0yQ1JcUEs2b21oYWlsUnxrVkRhQUQyNlJjSWBCN3BXNXVvVT1hamlcf3Fjd1dRMGJmREk9Yz09PH1CMzVTY0pBXD1kMU5HZl1da05gf0s1XGQ1NWA3bVFBNzNMJyknY3dqaFZgd3Ngdyc%2FcXdwYCknZ2RmbmJ3anBrYUZqaWp3Jz8nJmNjY2NjYycpJ2lkfGpwcVF8dWAnPyd2bGtiaWBabHFgaCcpJ2BrZGdpYFVpZGZgbWppYWB3dic%2FcXdwYHgl';

  stdout.writeln('url1_len=${url1.length} hash1=${url1.indexOf('#') >= 0 ? url1.substring(url1.indexOf('#')).length : 0}');
  stdout.writeln('url2_len=${url2.length}');

  stdout.writeln('PAY1 $sid1');
  final pay1 = await c.payCheckout4242(sid1, checkoutUrl: url1);
  stdout.writeln('PAY1 paid=${pay1['paid']} via=${pay1['via']} secret_n=${pay1['html_secret_n']} pi_n=${pay1['html_real_pi_n']} settle=${pay1['settle']}');

  stdout.writeln('PAY2 $sid2');
  final pay2 = await c.payCheckout4242(sid2, checkoutUrl: url2);
  stdout.writeln('PAY2 paid=${pay2['paid']} via=${pay2['via']} secret_n=${pay2['html_secret_n']} pi_n=${pay2['html_real_pi_n']} settle=${pay2['settle']}');

  const oids = [
    'fada5375-3f06-4350-8c55-acd85c8c3324',
    '863c9782-2fe8-4aff-adf3-867c3cd926bc',
    '3ba83ca8-94eb-41ca-a920-5d602c580916',
    'f59829e0-0451-4a3c-ba42-ec0ee5cf4217',
    'da4ca3e9-a66f-42e1-852c-182467a5bbb3',
  ];
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
      'qty': p?['quantity'],
      'sold': p?['is_sold'],
    });
  }
  final s1 = await c.settleGet(sid1);
  final s2 = await c.settleGet(sid2);
  final out = {
    'pay1': pay1,
    'pay2': pay2,
    'ledger': ledger,
    'settle': {'s1': s1.brief, 's2': s2.brief},
    'wallets': await c.wallets(),
  };
  await dumpJson('${outDir()}/a1_pay.json', out);
  stdout.writeln(
    'ledger statuses=${ledger.map((e) => e['status']).toSet()} '
    'qtys=${ledger.map((e) => e['qty']).toSet()} '
    'pagos=${ledger.where((e) => '${e['status']}'.toLowerCase() == 'pago').length}',
  );
}
