/// Favorite SKU already visible to B1 via REST/Hub.
import 'dart:io';
import '_rtcy.dart';

Future<void> main() async {
  final c = Rtcy.fromEnv(loadEnv());
  await c.loginActors();
  const sku = 'de64a58b-19ef-43b2-bbc2-bb38d0df26c5';
  final seen = await c.rest(
    'GET',
    'products?id=eq.$sku&select=id,seller_id,list_on_marketplace,is_sold,quantity',
    jwt: c.buyerJwt,
  );
  final hub = await c.rest(
    'GET',
    'hub_products_public?id=eq.$sku&select=id,title',
    jwt: c.buyerJwt,
  );
  await c.rest(
    'DELETE',
    'favorites?user_id=eq.${c.buyerId}&product_id=eq.$sku',
    jwt: c.buyerJwt,
    prefer: 'return=minimal',
  );
  final fav = await c.rest('POST', 'favorites', jwt: c.buyerJwt, body: {
    'user_id': c.buyerId,
    'product_id': sku,
  });
  final out = {
    'rest_product': seen.brief,
    'hub_product': hub.brief,
    'favorite': fav.brief,
  };
  await dumpJson('${outDir()}/confirm_fav_visible.json', out);
  stdout.writeln(out);
}
