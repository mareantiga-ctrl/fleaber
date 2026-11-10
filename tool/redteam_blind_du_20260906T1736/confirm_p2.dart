/// Confirm P2 live_item still available after drawn. No fixes.
import 'dart:convert';
import 'dart:io';
import '_rtdu.dart';

Future<void> main() async {
  final c = Rtdu.fromEnv(loadEnv());
  const hitch = '01d82d01-07fc-4a55-826b-ff0dd49e67a9';
  const liveOnly = 'a6ae787e-382e-49b6-a53a-66029852c72d';
  const sku = '6fadb23c-c3cb-4a14-9116-69c371df7e68';
  final liH = await c.liveItemRow(hitch);
  final liL = await c.liveItemRow(liveOnly);
  final prod = await c.productRow(sku);
  final hub = await c.hubSku(sku, jwt: c.buyerJwt);
  final out = {
    'hitch_li': liH,
    'live_only_li': liL,
    'sku': prod,
    'hub_n': hub.list.length,
  };
  await dumpJson('${outDir()}/confirm_p2.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
