/// Extract pk_test from Checkout HTML and hit payment_pages init (public).
import 'dart:convert';
import 'dart:io';

import '_rtdz.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  final sid =
      'cs_test_a1tb6kvvPlkXRdRUswi745JIDqJjbexzik7Dse4yuvLt8kTAJUnvs4p2Db';
  final page = await c.rawGet('https://checkout.stripe.com/c/pay/$sid');
  final pk = RegExp(r'pk_test_[A-Za-z0-9]+').firstMatch(page.body)?.group(0);
  stdout.writeln('pk=${pk == null ? 'null' : '${pk.substring(0, 12)}… len=${pk.length}'}');
  final initHints = <String>[];
  for (final pat in [
    'payment_pages',
    '"status"',
    'session_status',
    'checkout_session',
    'expired',
  ]) {
    final i = page.body.indexOf(pat);
    if (i >= 0) {
      initHints.add('$pat@$i ${clip(page.body.substring(i, i + 80), 80)}');
    }
  }
  stdout.writeln('hints=$initHints');

  Future<void> tryGet(String label, String url, {Map<String, String>? h}) async {
    final hit = await c.rawGet(url);
    stdout.writeln('$label ${hit.status} ${clip(hit.body, 220)}');
  }

  if (pk != null) {
    await tryGet(
      'pp_init',
      'https://api.stripe.com/v1/payment_pages/$sid/init?key=$pk',
    );
    await tryGet(
      'cs_pub',
      'https://api.stripe.com/v1/checkout/sessions/$sid?key=$pk',
    );
  }
  await tryGet(
    'pay_json',
    'https://checkout.stripe.com/c/pay/$sid?__stripe_preview=false',
  );
}
