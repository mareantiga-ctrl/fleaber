/// Observe Stripe TEST PI after T3-02 wallet mint — no fixes.
import 'dart:io';

import '_rtt.dart';

Future<void> main() async {
  final c = Rtt.fromEnv(loadEnv());
  await c.loginActors();
  final pi = 'pi_3UAlQqH7FWYUN3jh0ExuEeaQ';
  final hit = await c.e2e('list_stripe_refunds', {'payment_intent_id': pi});
  stdout.writeln(hit.brief);
  await dumpJson('${outDir()}/pass3_stripe_observe.json', {
    'pi': pi,
    'http': hit.status,
    'body': hit.json,
  });
}
