/// Extract Checkout bootstrap (pi / client_secret / config) from hosted page.
import 'dart:io';
import '_rteg.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  final sids = [
    'cs_test_a1JMp4ucughdACRM4rI9CIU8nnGv2l5QxZ43rsPRgEt09KFThyBx8gLgXg',
    'cs_test_a16ytZRsrNDqTQ0Sb52SSB1m8uZVnR1WW87eUQweF37N1tBhQEOv6kXjCU',
  ];
  final out = <Map<String, Object?>>[];
  for (final sid in sids) {
    final page = await c.rawGet('https://checkout.stripe.com/c/pay/$sid');
    final body = page.body;
    final keys = <String, Object?>{
      'sid': sid,
      'http': page.status,
      'len': body.length,
    };
    for (final pat in [
      'client_secret',
      'payment_intent',
      'cs_test_',
      'session_status',
      'this checkout session has expired',
      'Pay',
      'cardNumber',
      'merchant-ui-api',
      'api/checkout',
    ]) {
      keys['has_$pat'] = body.toLowerCase().contains(pat.toLowerCase());
    }
    final secrets = RegExp(r'pi_[A-Za-z0-9]{10,}_secret_[A-Za-z0-9]+')
        .allMatches(body)
        .map((m) => m.group(0))
        .toSet()
        .toList();
    final pis = RegExp(r'pi_[A-Za-z0-9]{15,}')
        .allMatches(body)
        .map((m) => m.group(0))
        .where((s) => s != null && !s.contains('secret') && !s.contains('cache'))
        .toSet()
        .toList();
    keys['secrets_n'] = secrets.length;
    keys['pis_n'] = pis.length;
    keys['secrets_clip'] = secrets.take(2).map((s) => s == null ? '' : '${s.substring(0, 18)}…').toList();
    keys['pis_clip'] = pis.take(4).map((s) => s == null ? '' : '${s.substring(0, 18)}…').toList();
    final cfg = RegExp(r'https://[^"\s]+checkout[^"\s]+').allMatches(body).take(8).map((m) => m.group(0)).toList();
    keys['urls'] = cfg;
    out.add(keys);
    stdout.writeln(keys);
  }
  await dumpJson('${outDir()}/extract_cs.json', out);
}
