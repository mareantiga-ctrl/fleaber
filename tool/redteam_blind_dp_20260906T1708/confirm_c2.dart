/// Confirm C2: dest alheio SEM user_id (pass1 short-circuitou em user_id).
import 'dart:io';
import '_rtdp.dart';

Future<void> main() async {
  final c = Rtdp.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureWalletBalance(c.sellerId!, 3);
  final before = await c.walletBal(c.sellerId);
  final tids0 = await c.transferIds(c.sellerId!);
  final own = await c.walletRow(c.sellerId);
  const alien = 'acct_1UB7nWHKe5ETfHI5';
  final hit = await c.connect({
    'amount': 100,
    'idempotency_key': 'rtdpC2destOnly1708xx',
    'destination': alien,
    'stripe_account_id': alien,
    'account': alien,
    'currency': 'usd',
    'metadata': {'fleaber_user_id': 'hostile-c2'},
  });
  final after = await c.walletBal(c.sellerId);
  final tids1 = await c.transferIds(c.sellerId!);
  final neu = tids1.difference(tids0);
  c.probe(
    id: 'C2b',
    lens: 'DP4',
    edgeRpc: 'create-connect-account dest alheio (sem user_id)',
    payload: 'dest=$alien currency=usd amount=100',
    http: hit,
    stripeBd:
        'own=${own?['stripe_account_id']} Δ=${after - before} new_tr=${neu.toList()}',
    result: neu.length > 1 ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: neu.length > 1,
  );
  await c.dumpAll('confirm_c2.json');
  stdout.writeln(
      'C2b ${hit.brief} Δ=${after - before} new=${neu.toList()} own=${own?['stripe_account_id']}');
}
