/// Observar wallet seller após pass1 (PATCH dest).
import 'dart:io';
import '_rtbj.dart';

Future<void> main() async {
  final c = Rtbj.fromEnv(loadEnv());
  await c.loginActors();
  final w = await c.walletRow(c.sellerId);
  stdout.writeln('WALLET ${clip(w)}');
  final patch = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {'stripe_account_id': 'acct_1HijackDestBJ'},
  );
  stdout.writeln('PATCH ${patch.brief} mutated=${patch.mutated}');
  final w2 = await c.walletRow(c.sellerId);
  stdout.writeln('AFTER ${clip(w2)}');
  final led = await c.payoutLedger(userId: c.sellerId, limit: 8);
  stdout.writeln('LEDGER $led');
}
