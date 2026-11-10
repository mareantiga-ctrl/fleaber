/// Confirm: B1 vê views Hub vs REST profiles/products.
import 'dart:io';
import '_rtcy.dart';

Future<void> main() async {
  final c = Rtcy.fromEnv(loadEnv());
  await c.loginActors();
  final s1 = c.sellerId!;
  final views = <String, String>{};
  for (final t in [
    'hub_products_public?seller_id=eq.$s1&select=id,title&limit=3',
    'hub_lives_public?select=id,title&limit=3',
    'products?seller_id=eq.$s1&select=id,title,list_on_marketplace,quantity,is_sold&limit=5',
    'profiles?id=eq.$s1&select=id,hub_published,handle',
    'profiles_directory_public?id=eq.$s1&select=id,handle',
  ]) {
    final h = await c.rest('GET', t, jwt: c.buyerJwt);
    views[t.split('?').first] = '${h.status} n=${h.list.length} ${clip(h.body, 140)}';
  }
  final anonHub = await c.rest(
    'GET',
    'hub_products_public?seller_id=eq.$s1&select=id,title&limit=3',
  );
  views['anon.hub_products'] = '${anonHub.status} n=${anonHub.list.length}';
  await dumpJson('${outDir()}/confirm_views.json', views);
  stdout.writeln(views);
}
