/// dart run tool/redteam_blind_ad_20260901T1825/pass3.dart
import 'dart:io';
import '_rtad.dart';

Future<void> main() async {
  final c = Rtad.fromEnv(loadEnv());
  try {
    await c.loginActors();
    final live = await c.insertLive();
    if (live == null) throw StateError('live');
    // Warm item so stock RPC sees qty (pass2 first item was available=0).
    final warm = await c.insertLiveOnlyItem(
        liveId: live, qty: 2, ref: 'P3W', jwt: c.sellerJwt);
    if (warm != null) {
      c.note('p3.warm', 'warm item', await c.itemRow(warm));
    }
    final item = await c.insertLiveOnlyItem(
        liveId: live, qty: 2, ref: 'P3A', jwt: c.sellerJwt);
    if (item == null) throw StateError('item');
    final rowItem = await c.itemRow(item);
    final st0 = await c.stock(item);
    final hub0 = await c.hubItem(item);
    final ins = await c.insertReservation(
      liveId: live,
      liveItemId: item,
      buyer: c.sellerId,
      source: 'fleaber_live',
      status: 'converted',
      jwt: c.sellerJwt,
    );
    final id = ins.firstId;
    final row = id == null ? null : await c.reqRow(id);
    final st1 = await c.stock(item);
    final hub1 = await c.hubItem(item);
    final disc1 = await c.hubDiscovery(item, jwt: c.buyerJwt);
    final orders = await c.ordersForItem(item);
    c.note('p3.insert.converted', 'INSERT fleaber converted qty=2', {
      'item': rowItem,
      'insert': ins.brief,
      'row': row,
      'stock0': st0.map,
      'stock1': st1.map,
      'hub0': hub0,
      'hub1': hub1,
      'discovery': disc1,
      'orders': orders,
    }, lens: 'AD1');
    final sold = numOf(st1.map?['sold_converted_qty']) ?? 0;
    if (row?['status'] == 'converted' && sold >= 1 && orders.isEmpty) {
      c.hold(
        id: 'RTAD-AD1-insert-fleaber-converted-p3',
        lens: 'AD1',
        severity: 'P1',
        title: 'INSERT fleaber_live converted consome sold_converted_qty sem order',
        actor: 'seller',
        pre: 'live_only qty=2; Hub visível; zero PI',
        repro: 'POST source=fleaber_live status=converted buyer_id=seller',
        expected: 'pending; sold=0',
        obtained: {
          'status': row?['status'],
          'sold': sold,
          'available': st1.map?['available_qty'],
          'hub': hub1,
          'processed_by': row?['processed_by_user_id'],
          'orders': 0,
        },
      );
    } else {
      c.block('RTAD-AD1-insert-fleaber-converted-p3', 'AD1',
          'INSERT converted p3 não consumiu', {
        'insert': ins.brief,
        'row': row,
        'stock0': st0.map,
        'stock1': st1.map,
      });
    }
  } finally {
    await c.dumpAll('findings_pass3.json');
    await c.endLives();
    stdout.writeln('PASS3 findings=${c.findings.length}');
  }
}
