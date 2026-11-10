/// Confirm B4: sellable RPC vs Hub listed filter. Staging only. No fixes.
import 'dart:convert';
import 'dart:io';

import '_rtep.dart';

Future<void> main() async {
  final c = Rtdu.fromEnv(loadEnv());
  await c.loginActors();
  final listedRows = await c.rest(
    'GET',
    'products?title=ilike.*B4 listed*&select=id,quantity,is_sold,list_on_marketplace&order=created_at.desc&limit=1',
    service: true,
  );
  final soldRows = await c.rest(
    'GET',
    'products?title=ilike.*B4 sold*&select=id,quantity,is_sold,list_on_marketplace&order=created_at.desc&limit=1',
    service: true,
  );
  final unRows = await c.rest(
    'GET',
    'products?title=ilike.*B4 unlisted*&select=id,quantity,is_sold,list_on_marketplace&order=created_at.desc&limit=1',
    service: true,
  );
  final lid = listedRows.firstId;
  final sid = soldRows.firstId;
  final uid = unRows.firstId;

  Future<Map<String, Object?>> snap(String? id, String tag) async {
    if (id == null) return {'tag': tag, 'missing': true};
    final sell = await c.hubSellable(id);
    final hubB = await c.hubSku(id, jwt: c.buyerJwt);
    final hubA = await c.hubSku(id, anon: true);
    final prod = await c.productRow(id);
    return {
      'tag': tag,
      'id': id,
      'prod': prod,
      'sellable_brief': sell.brief,
      'sellable_json': sell.json,
      'hub_buyer_n': hubB.list.length,
      'hub_anon_n': hubA.list.length,
    };
  }

  final out = {
    'listed': await snap(lid, 'listed'),
    'sold': await snap(sid, 'sold'),
    'unlisted': await snap(uid, 'unlisted'),
    'contract':
        'batata_product_hub_sellable = stock-held>0 only; Hub view also requires listed && !sold',
  };
  await dumpJson('${outDir()}/confirm_b4.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
