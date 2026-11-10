import 'dart:io';
import '_rtc.dart';

Future<void> main() async {
  final c = Rtc(loadEnv());
  final r = await c.rest(
    'GET',
    'seller_bundle_discounts',
    service: true,
    query:
        'seller_id=eq.${c.labSellerId}&select=seller_id,enabled,tier_2_pct,tier_3_pct,tier_5_pct',
  );
  stdout.writeln(r['raw']);
  // cleanup prefix products
  final p = await c.rest(
    'GET',
    'products',
    service: true,
    query:
        'ref_code=like.${prefix}*&select=id,title,ref_code,list_on_marketplace&limit=50',
  );
  stdout.writeln('products ${r['http']} ${p['raw']}');
}
