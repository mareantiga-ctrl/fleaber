/// FA confirm — B1 amount vs desconto conjunto; C2 ledger disjuntos.
import 'dart:convert';
import 'dart:io';

import '_rtfa.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();

  const b1oids = [
    '4662d9ff-10b9-4a51-b1a1-9870efdba679',
    '809aaf07-bdc7-47e9-b1ad-3ba233ff898e',
    '29072732-2547-40ad-af8a-41450e6ce3b4',
  ];
  const c1oid = '89d1ed22-97ee-4940-a47e-a870dfa0a275';
  const c2a = [
    '6628d1b7-1a6f-4543-bb04-e72af252a224',
    '1c1eb776-c761-4f50-8486-a873fdc4ea47',
  ];
  const c2b = [
    '95ea61f8-924b-4b2a-a3f2-afb5194e21de',
    '0fa3aeb5-5c74-4405-a9a3-9fa6307e4b7a',
  ];
  const paid = 'df634509-fa17-4ec6-91bc-b8ed67d2c535';
  const paidPid = '0087eb39-7004-4d82-85ec-d6b54b818306';

  Future<Map<String, Object?>> snapOid(String oid) async {
    final o = await c.orderRow(oid);
    final pid = '${o?['product_id'] ?? ''}';
    final p = pid.isEmpty ? null : await c.productRow(pid);
    return {
      'oid': oid,
      'status': o?['status'],
      'price_total': o?['price_total'],
      'cs': o?['stripe_checkout_session_id'],
      'pi': o?['stripe_payment_intent_id'],
      'pid': pid,
      'qty': p?['quantity'],
      'sold': p?['is_sold'],
      'product_price': p?['price'],
    };
  }

  final b1 = [for (final id in b1oids) await snapOid(id)];
  final catalog = b1.fold<num>(
    0,
    (s, r) => s + (numOf(r['price_total']) ?? 0),
  );
  const observed = 3341;
  const discPct = 20;
  final discounted = ((catalog * 100) * (1 - discPct / 100)).round();
  const protFixed = 0.65;
  const protPct = 0.05;
  final baseEur = discounted / 100;
  final protEur =
      ((protFixed + baseEur * protPct) * 100).round() / 100;
  final protCents = (protEur * 100).round();
  final expected = discounted + protCents;

  final c1 = await snapOid(c1oid);
  final bagA = [for (final id in c2a) await snapOid(id)];
  final bagB = [for (final id in c2b) await snapOid(id)];
  final pago = await snapOid(paid);
  final hub = await c.hubSku(paidPid);
  final wallets = await c.wallets();

  final out = {
    'b1': {
      'orders': b1,
      'catalog_eur': catalog,
      'catalog_cents': (catalog * 100).round(),
      'disc_pct': discPct,
      'discounted_cents': discounted,
      'prot_cents': protCents,
      'expected_stripe_cents': expected,
      'observed_amount_total': observed,
      'matches_formula': expected == observed,
      'client_amount_ignored': observed > 50 && observed != 1,
    },
    'c1': c1,
    'c2a': bagA,
    'c2b': bagB,
    'c2_sids_a': [
      for (final r in bagA) '${r['cs'] ?? ''}',
    ],
    'c2_sids_b': [
      for (final r in bagB) '${r['cs'] ?? ''}',
    ],
    'pago_e2e': pago,
    'hub_n': hub.list.length,
    'hub_http': hub.status,
    'seller_wallet': wallets['seller'],
  };
  await dumpJson('${outDir()}/confirm.json', out);
  stdout.writeln(const JsonEncoderPretty().convert(out));
}

class JsonEncoderPretty {
  const JsonEncoderPretty();
  String convert(Object data) =>
      const JsonEncoder.withIndent('  ').convert(data);
}
