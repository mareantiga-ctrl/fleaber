/// Confirmar B3 Hub lives ended + B4 raffle live_item_id / prize.
import 'dart:convert';
import 'dart:io';
import '_rtds.dart';

Future<void> main() async {
  final c = Rtds.fromEnv(loadEnv());
  await c.loginActors();

  const liveB3 = '0a8b53e4-5549-4fd1-864c-854b1e8a07cd';
  const rafId = '2aba4530-50b4-4f82-8fb9-809e72ad37f1';

  final live = await c.rest(
    'GET',
    'lives?id=eq.$liveB3&select=id,status,is_active,title,seller_id',
    service: true,
  );
  final hubLiveAnon = await c.hubLives(liveB3);
  final hubLiveJwt = await c.rest(
    'GET',
    'hub_lives_public?id=eq.$liveB3&select=id,title,seller_id,status,is_active',
    jwt: c.buyerJwt,
  );
  final raf = await c.rest(
    'GET',
    'live_raffles?id=eq.$rafId&select=id,status,live_id,live_item_id,seller_id,title,winner_count',
    service: true,
  );
  final winners = await c.raffleWinners(rafId);
  final liId = raf.map?['live_item_id']?.toString();
  Map<String, dynamic>? li;
  Map<String, dynamic>? prod;
  HttpHit? hubSku;
  HttpHit? cpiPrize;
  if (liId != null) {
    li = (await c.rest(
      'GET',
      'live_items?id=eq.$liId&select=id,product_id,checkout_product_id,quantity,status,item_kind',
      service: true,
    ))
        .map;
    final pid = (li?['product_id'] ?? li?['checkout_product_id'])?.toString();
    if (pid != null) {
      prod = await c.productRow(pid);
      hubSku = await c.hubSku(pid, jwt: c.buyerJwt);
      final oid = await c.insertOrder(
        productId: pid,
        jwt: c.buyerJwt,
        price: 12.0,
      );
      if (oid != null) {
        cpiPrize = await c.checkout(
          orderId: oid,
          productId: pid,
          jwt: c.buyerJwt,
        );
      }
    }
  }
  final prizes = await c.rest(
    'GET',
    'orders?live_raffle_id=eq.$rafId&select=id,status,buyer_id,product_id,live_raffle_id',
    service: true,
  );

  final out = {
    'live': live.map,
    'hub_live_anon_n': hubLiveAnon.list.length,
    'hub_live_anon': hubLiveAnon.brief,
    'hub_live_jwt_n': hubLiveJwt.list.length,
    'hub_live_jwt': hubLiveJwt.brief,
    'raffle': raf.map,
    'winners': winners,
    'live_item': li,
    'product': prod,
    'hub_sku_n': hubSku?.list.length,
    'hub_sku': hubSku?.brief,
    'cpi_after_draw': cpiPrize?.brief,
    'cpi_cs': cpiPrize?.sessionId,
    'prize_orders_n': prizes.list.length,
  };
  await dumpJson('${outDir()}/confirm_b.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
