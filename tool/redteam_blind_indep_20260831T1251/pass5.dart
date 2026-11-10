/// Pass 5 — mundo live activa, wallet pós-concluido, lives stream_key, cleanup.
import 'dart:io';
import '_rt.dart';

Future<void> main() async {
  final c = Rti4(loadEnv());
  await c.boot();

  final active = await c.rest(
    'GET',
    'lives?is_active=eq.true&select=id,status,is_active,seller_id,title&limit=20',
    service: true,
  );
  c.note('p1.lives.active', 'lives is_active=true', {
    'http': active.status,
    'n': active.list.length,
    'rows': active.list.take(5).toList(),
  }, well: '1');

  // Buyer SELECT lives (stream keys?)
  final liveBuy = await c.rest(
    'GET',
    'lives?select=id,status,is_active,mux_stream_key,stream_key,seller_id&limit=5',
    token: c.buyerJwt,
  );
  c.note('p3.lives.buyer', 'buyer lives', liveBuy.brief, well: '3');
  if (liveBuy.ok && liveBuy.list.any((e) {
        if (e is! Map) return false;
        final k = '${e['mux_stream_key'] ?? e['stream_key'] ?? ''}';
        return k.isNotEmpty && k != 'null';
      })) {
    c.finding(
      id: 'P3-BUYER-STREAM-KEY',
      title: 'Buyer lê stream key de lives',
      actor: 'buyer JWT',
      sev: 'P1',
      well: '3',
      pre: 'GET lives',
      request: 'GET lives select stream_key',
      before: null,
      after: clip(liveBuy.body, 400),
      impact: 'Ingest hijack',
      repro: 'GET lives as buyer',
    );
  } else {
    c.hold('p3.lives.buyer', 'buyer sem lives/keys', liveBuy.brief, well: '3');
  }

  // Wallet txs around hand concluido
  final wTx = await c.rest(
    'GET',
    'wallet_transactions?user_id=eq.${c.sellerId}&select=id,amount,type,category,order_id,created_at&order=created_at.desc&limit=8',
    service: true,
  );
  c.note('p2.wallet.tx', 'seller wallet tx', {
    'http': wTx.status,
    'n': wTx.list.length,
    'snip': clip(wTx.body, 500),
  }, well: '2');

  final handOrder = await c.rest(
    'GET',
    'orders?id=eq.e0c09e65-25bd-45d5-978d-3d0bc25bf000&select=id,status,wallet_release_processed_at,amount_paid_cents,shipping_method',
    service: true,
  );
  c.note('p2.hand.order.final', 'hand concluido row', handOrder.brief, well: '2');

  // If an active live of our seller exists, try unlist checkout then END it if we created RTI4
  for (final row in active.list) {
    if (row is! Map) continue;
    final sid = '${row['seller_id']}';
    final lid = '${row['id']}';
    final title = '${row['title']}';
    if (sid != c.sellerId) continue;
    final unlist = await c.insertProduct(
      listed: false,
      sold: false,
      title: '$prefix-WORLD-UL',
      qty: 1,
    );
    if (unlist == null) break;
    final o = await c.insertOrder(
      token: c.buyerJwt,
      productId: unlist['id'].toString(),
      liveId: lid,
    );
    c.note('p1.world.live.order', 'unlist + existing active live', {
      'live': row,
      'order': o.brief,
    }, well: '1');
    if (o.ok) {
      final oid = c.orderIdOf(o);
      if (oid != null) {
        final chk = await c.checkout(
          token: c.buyerJwt,
          orderId: oid,
          productId: unlist['id'].toString(),
        );
        final session = chk.ok &&
            '${chk.map?['checkoutUrl'] ?? ''}'.contains('checkout.stripe.com');
        c.finding(
          id: 'P1-WORLD-LIVE-UNLIST',
          title: 'Live is_active existente vende unlist fora do catálogo live',
          actor: 'buyer JWT',
          sev: session ? 'P1' : 'P2',
          well: '1',
          pre: 'live id=$lid status=${row['status']} is_active=true; Hub unlist vazio',
          request: 'POST orders live_id; checkout',
          before: row,
          after: {'order': o.brief, 'checkout': clip(chk.body, 300), 'session': session},
          impact: 'Montra morta ainda gera Session durante directo',
          repro: 'POST orders unlist+live_id de live activa',
        );
      }
    } else {
      c.hold('p1.world.live.order', 'hold unlist em live activa mundial bloqueado', o.brief,
          well: '1');
    }
    if (title.contains('RTI4-')) {
      await c.rest(
        'PATCH',
        'lives?id=eq.$lid',
        service: true,
        body: {'is_active': false, 'status': 'ended'},
      );
    }
    break;
  }

  // Authenticated directory / PII
  final dir = await c.rest(
    'GET',
    'profiles_directory_public?select=id,full_name,location,user_type&limit=10',
    token: c.freshJwt ?? c.buyerJwt,
  );
  c.note('p3.directory', 'profiles_directory_public', {
    'http': dir.status,
    'n': dir.list.length,
  }, well: '3');

  final otherProf = await c.rest(
    'GET',
    'profiles?id=eq.${c.sellerId}&select=id,full_name,phone,iban,mb_way,shipping_line1,location',
    token: c.buyerJwt,
  );
  c.note('p3.profiles.buyer.other', 'buyer GET seller profile', otherProf.brief, well: '3');
  if (otherProf.ok && otherProf.list.any((e) {
        if (e is! Map) return false;
        return '${e['iban'] ?? ''}'.isNotEmpty ||
            '${e['phone'] ?? ''}'.isNotEmpty ||
            '${e['mb_way'] ?? ''}'.isNotEmpty;
      })) {
    c.finding(
      id: 'P3-PROFILE-PII',
      title: 'Buyer lê IBAN/telefone do seller via profiles',
      actor: 'buyer JWT',
      sev: 'P1',
      well: '3',
      pre: 'GET profiles other uid',
      request: 'GET profiles',
      before: null,
      after: clip(otherProf.body, 400),
      impact: 'PII financeira',
      repro: 'GET profiles?id=eq.seller',
    );
  } else {
    c.hold('p3.profiles.buyer.other', 'sem PII financeira nesta leitura', otherProf.brief,
        well: '3');
  }

  // Cleanup RTI4 lives still active
  final ours = await c.rest(
    'GET',
    'lives?title=like.$prefix*&select=id,status,is_active,title',
    service: true,
  );
  for (final row in ours.list) {
    if (row is! Map) continue;
    if (row['is_active'] == true) {
      await c.rest(
        'PATCH',
        'lives?id=eq.${row['id']}',
        service: true,
        body: {'is_active': false, 'status': 'ended'},
      );
    }
  }
  c.note('p1.cleanup.lives', 'ended our live titles', {'n': ours.list.length}, well: '1');

  // Unlist leftover RTI4 products (service observe/cleanup)
  final prods = await c.rest(
    'GET',
    'products?title=like.$prefix*&select=id,title,list_on_marketplace,is_sold&limit=80',
    service: true,
  );
  for (final row in prods.list) {
    if (row is! Map) continue;
    await c.rest(
      'PATCH',
      'products?id=eq.${row['id']}',
      service: true,
      body: {'list_on_marketplace': false},
    );
  }
  c.note('p1.cleanup.products', 'unlisted RTI4 products', {'n': prods.list.length}, well: '1');

  await c.dump('pass5');
  stdout.writeln('pass5 done findings=${c.findings.length} holds=${c.holds.length}');
}
