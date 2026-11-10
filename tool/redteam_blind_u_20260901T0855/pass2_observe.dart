/// Observe: retract 200[] false positives; MB WAY stock; offer order.
library;

import '_rtu.dart';
import 'dart:io';

Future<void> main() async {
  final c = Rtu.fromEnv(loadEnv());
  await c.loginActors();

  final offerOrder = await c.orderRow('ba60d4f8-8424-499f-aee0-be254676b40b');
  final offerProd = await c.productRow('68a3c3da-f0cb-41de-9faf-6a759f0e76c2');
  final bunOrder = await c.orderRow('09d1ae07-641b-4c97-bf50-de9b0f38ee60');
  final mb = await c.orderRow('274ac914-4019-45f0-8d47-dfb79e3553b5');
  final mbProd = mb?['product_id'] == null
      ? null
      : await c.productRow(mb!['product_id'].toString());
  final legit = await c.orderRow('c73842ae-b5ca-4772-ac6f-557a74f4efdc');
  final legitP = await c.productRow('ec4914a1-29e6-43c8-8623-c25d35af874d');

  final s2skus = await c.rest(
    'GET',
    'products?seller_id=eq.${c.seller2Id}&description=eq.$prefix&select=id,title,price,list_on_marketplace,quantity,seller_id',
    service: true,
  );

  await dumpJson('${outDir()}/pass2_observe.json', {
    'offer_order': offerOrder,
    'offer_product': offerProd,
    'bundle_order': bunOrder,
    'mbway_order': mb,
    'mbway_product': mbProd,
    'legit_order': legit,
    'legit_product': legitP,
    's2_alien': s2skus.list,
    'wallets': await c.wallets(),
  });
  stdout.writeln('observe written');
}
