/// Pass 4 — checkout com shipping_method=hand.
import 'dart:convert';
import 'dart:io';
import '_rte.dart';

void main() async {
  final env = loadEnv();
  final c = Rte.fromEnv(env);
  await c.loginActors(env);

  Future<HttpHit> ck(String oid, {String? origin}) {
    return c.edge('create-payment-intent', {
      'order_id': oid,
      'buyer_id': c.buyerId,
      'currency': 'eur',
      'shipping_method': 'hand',
      if (origin != null) 'web_return_origin': origin,
    }, jwt: c.buyerJwt);
  }

  bool sess(HttpHit h) =>
      h.ok && (h.body.contains('cs_test_') || h.body.contains('checkout.stripe.com'));

  const cases = <String, List<String?>>{
    'stamp': ['c5d6b577-19b9-491e-b286-ea12cebf3c15', null],
    'then': ['dc3550fd-a813-4c8d-bfe7-208ca7875875', null],
    'bun': ['03a7b734-9dc8-4e11-aad4-6aff8cab93fa', null],
    'ok_redir': ['ef2c31a2-6ecb-4dcb-b5ba-75a4f2191067', 'https://attacker.fleaber.pt'],
  };

  final log = <String, dynamic>{};
  for (final e in cases.entries) {
    final oid = e.value[0]!;
    final origin = e.value[1];
    final h = await ck(oid, origin: origin);
    log[e.key] = {
      'http': h.status,
      'session': sess(h),
      'snip': h.snippet,
    };
  }

  final outPath = 'tool/redteam_blind_e_orbita_$stamp/out/pass4.json';
  await dumpJson(outPath, {'stamp': stamp, 'log': log});
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(log));
  stdout.writeln(outPath);
}
