/// Confirm D3 Hub listed=0 vs products qty=2. Staging only. No fixes.
import 'dart:convert';
import 'dart:io';

import '_rtei.dart';

Future<void> main() async {
  final c = Rtdu.fromEnv(loadEnv());
  await c.loginActors();
  const listed = '0154aad0-5567-4a51-b44e-02ebb79915cb';
  const leftover = '471f8913-97b7-4b84-a24c-fac96b32299c';
  const sold = '36e80ee0-4d9c-442b-87fb-53d4da32088c';
  const unlisted = '1fa03eb4-c655-41df-827b-5e0b6dcb688e';

  final sellListed = await c.rpc(
    'batata_product_hub_sellable',
    {'p_product_id': listed},
    service: true,
  );
  final sellLeft = await c.rpc(
    'batata_product_hub_sellable',
    {'p_product_id': leftover},
    service: true,
  );
  final heldListed = await c.heldQty(listed);
  final heldLeft = await c.heldQty(leftover);
  final pListed = await c.productRow(listed);
  final pLeft = await c.productRow(leftover);
  final hubListedB = await c.hubSku(listed, jwt: c.buyerJwt);
  final hubListedA = await c.hubSku(listed, anon: true);
  final hubLeftB = await c.hubSku(leftover, jwt: c.buyerJwt);
  final hubSold = await c.hubSku(sold, jwt: c.buyerJwt);
  final hubUn = await c.hubSku(unlisted, jwt: c.buyerJwt);
  final prof = await c.hubProfile(c.sellerId!, anon: false);
  final profA = await c.hubProfile(c.sellerId!, anon: true);
  final shop = await c.rest(
    'GET',
    'hub_products_public?seller_id=eq.${c.sellerId}&title=ilike.*RTEI-20260906T1905 D3*&select=id,title,price',
    jwt: c.buyerJwt,
  );

  final out = {
    'sell_listed': sellListed.brief,
    'sell_left': sellLeft.brief,
    'held_listed': heldListed.brief,
    'held_left': heldLeft.brief,
    'prod_listed': pListed,
    'prod_left': pLeft,
    'hub_listed_buyer_n': hubListedB.list.length,
    'hub_listed_anon_n': hubListedA.list.length,
    'hub_left_n': hubLeftB.list.length,
    'hub_sold_n': hubSold.list.length,
    'hub_un_n': hubUn.list.length,
    'hub_listed_buyer': hubListedB.brief,
    'profile_jwt': prof.brief,
    'profile_anon': profA.brief,
    'shop_d3': shop.brief,
  };
  await dumpJson('${outDir()}/confirm_d3.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
