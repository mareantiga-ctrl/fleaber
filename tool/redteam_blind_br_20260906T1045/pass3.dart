/// BR pass3 — JWT a mexer no desconto tier do vendedor.
import 'dart:io';

import '_rtbr.dart';

Future<void> main() async {
  final c = Rtbr.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final buyer = await c.rest(
    'PATCH',
    'seller_bundle_discounts?seller_id=eq.${c.sellerId}',
    jwt: c.buyerJwt,
    body: {'tier_2_pct': 90, 'enabled': true},
  );
  final s2 = await c.rest(
    'PATCH',
    'seller_bundle_discounts?seller_id=eq.${c.sellerId}',
    jwt: c.seller2Jwt,
    body: {'tier_2_pct': 90},
  );
  final self = await c.rest(
    'PATCH',
    'seller_bundle_discounts?seller_id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {'tier_2_pct': 10},
  );
  final after = await c.rest(
    'GET',
    'seller_bundle_discounts?seller_id=eq.${c.sellerId}&select=seller_id,enabled,tier_2_pct,tier_3_pct',
    service: true,
  );
  c.note('P3.DISC.buyer', 'buyer PATCH tier 90', buyer.brief, lens: 'BR3');
  c.note('P3.DISC.s2', 'S2 PATCH S1 tier 90', s2.brief, lens: 'BR7');
  c.note('P3.DISC.self', 'S1 PATCH próprio (restore 10)', self.brief, lens: 'BR3');
  c.note('P3.DISC.after', 'row', after.brief, lens: 'BR3');

  if (buyer.ok) {
    c.hold(
      id: 'BR3-BUYER-PATCH-TIER',
      lens: 'BR3',
      severity: 'P0',
      title: 'Buyer PATCH seller_bundle_discounts',
      actor: 'buyer JWT',
      pre: 'tier_2=10 do vendedor',
      repro: 'PATCH tier_2_pct=90',
      expected: '403',
      obtained: buyer.brief,
    );
  } else {
    c.block('BR3-BUYER-PATCH-TIER', 'BR3', 'buyer não altera tier', buyer.brief);
  }
  if (s2.ok) {
    c.hold(
      id: 'BR7-S2-PATCH-S1-TIER',
      lens: 'BR7',
      severity: 'P0',
      title: 'Seller2 PATCH descontos do seller1',
      actor: 'seller2 JWT',
      pre: 'S1 discounts',
      repro: 'PATCH seller_bundle_discounts',
      expected: '403',
      obtained: s2.brief,
    );
  } else {
    c.block('BR7-S2-PATCH-S1-TIER', 'BR7', 'S2 não altera tier S1', s2.brief);
  }

  await c.dumpAll('findings_pass3.json');
  stdout.writeln('PASS3 findings=${c.findings.length}');
}
