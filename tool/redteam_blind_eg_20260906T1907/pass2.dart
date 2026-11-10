/// EG pass2 — Hub leftover sem coluna quantity; ledger A1 após tentativa 4242; browser incomplete.
import 'dart:io';
import '_rteg.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer3();
  c.buyerId = c.buyer3Id;
  c.buyerJwt = c.buyer3Jwt;

  const c3pid = 'c5a8b9fc-7f39-4c0b-af1f-380063dfb1f4';
  const c3oid = 'a970e19f-f96e-484a-a035-a24d151f457e';
  final hub = await c.rest(
    'GET',
    'hub_products_public?id=eq.$c3pid&select=id,title,seller_id,is_sold,price',
  );
  final prod = await c.productRow(c3pid);
  final ord = await c.orderRow(c3oid);

  const a1oids = [
    '4d033786-2624-4fe4-a87d-fe3d48239a6c',
    'f5326620-0d9a-4f6f-a36f-ca576751f797',
    'de355cf3-63ed-463a-8f05-48226bfdac06',
    '01a729c2-f46a-4b25-9ff4-00a42804fa06',
    'fde2e3de-b318-4f38-b187-fb9a36355b9d',
    '3e5aa04a-7ad5-4fd4-a97b-f0ee6310bb5c',
  ];
  final a1 = <Map<String, Object?>>[];
  for (final id in a1oids) {
    final o = await c.orderRow(id);
    final p = await c.productRow('${o?['product_id']}');
    a1.add({
      'oid': id,
      'status': o?['status'],
      'cs': o?['stripe_checkout_session_id'],
      'pi': o?['stripe_payment_intent_id'],
      'paid': o?['amount_paid_cents'],
      'applied': o?['stock_units_applied'],
      'product_qty': p?['quantity'],
      'sold': p?['is_sold'],
    });
  }

  final s1 = await c.settleGet(
    'cs_test_a1JMp4ucughdACRM4rI9CIU8nnGv2l5QxZ43rsPRgEt09KFThyBx8gLgXg',
  );
  final s2 = await c.settleGet(
    'cs_test_a16ytZRsrNDqTQ0Sb52SSB1m8uZVnR1WW87eUQweF37N1tBhQEOv6kXjCU',
  );

  final out = {
    'browser_checkout': {
      'url_used':
          'full checkoutUrl 473 chars with hash (identical suffix across all cs_)',
      'page': 'This link is incomplete — Use the unmodified checkout URL',
      'paid': false,
    },
    'c3_hub': {
      'http': hub.status,
      'n': hub.list.length,
      'row': hub.map,
      'product_qty': prod?['quantity'],
      'order_status': ord?['status'],
      'applied': ord?['stock_units_applied'],
    },
    'a1_ledger_after_pay_attempt': a1,
    'settle_a1': {'s1': s1.brief, 's2': s2.brief},
    'wallets': await c.wallets(),
  };
  await dumpJson('${outDir()}/pass2.json', out);
  stdout.writeln('C3 hub ${hub.status} n=${hub.list.length} qty=${prod?['quantity']} status=${ord?['status']}');
  stdout.writeln('A1 statuses=${a1.map((e) => e['status']).toSet()} qtys=${a1.map((e) => e['product_qty']).toSet()} pagos=${a1.where((e) => e['paid'] != null).length}');
  stdout.writeln('settle ${s1.status} ${s2.status}');
}
