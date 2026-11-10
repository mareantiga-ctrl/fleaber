/// Confirm EA — buyer PATCH live_item após drawn; C2 draw nWin.
/// Staging only. NÃO corrigir.
import 'dart:io';

import '_rtea.dart';

String futureIso() => DateTime.now()
    .toUtc()
    .add(const Duration(hours: 2))
    .toIso8601String();

Future<void> main() async {
  final c = Rtdu.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  final s1 = c.sellerId!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;
  await c.restoreSeller1Published();

  try {
    final sku = await c.createProduct(
      title: '$prefix confirm D3 patch',
      qty: 1,
      listed: true,
      live: true,
      price: 9.0,
    );
    final live = await c.createLive(title: '$prefix confirm D3');
    final li = (live != null && sku != null)
        ? await c.createLiveItem(
            liveId: live,
            title: '$prefix confirm-li',
            kind: 'marketplace_product',
            productId: sku,
          )
        : null;
    HttpHit? ins;
    String? raf;
    if (live != null) {
      ins = await c.rest('POST', 'live_raffles', service: true, body: {
        'live_id': live,
        'seller_id': s1,
        'title': '$prefix confirm D3',
        'status': 'active',
        'winner_count': 1,
        if (li != null) 'live_item_id': li,
        'ends_at': futureIso(),
      });
      raf = ins.firstId;
      if (raf != null) c.createdRaffleIds.add(raf);
    }
    HttpHit? join;
    HttpHit? close;
    HttpHit? draw;
    HttpHit? patchBuyer;
    HttpHit? patchSeller;
    HttpHit? rec;
    Map<String, dynamic>? li0;
    Map<String, dynamic>? liBuyer;
    Map<String, dynamic>? liSeller;
    Map<String, dynamic>? liRec;
    if (raf != null && li != null) {
      join = await c.joinRaffle(raf);
      await c.awardTickets(raffleId: raf, userId: b1, delta: 4);
      close = await c.closeRaffle(raf);
      draw = await c.drawRaffle(raf);
      li0 = await c.liveItemRow(li);
      patchBuyer = await c.rest(
        'PATCH',
        'live_items?id=eq.$li',
        jwt: c.buyerJwt,
        body: {'status': 'available', 'is_active': true},
      );
      liBuyer = await c.liveItemRow(li);
      patchSeller = await c.rest(
        'PATCH',
        'live_items?id=eq.$li',
        jwt: c.sellerJwt,
        body: {'status': 'available', 'is_active': true},
      );
      liSeller = await c.liveItemRow(li);
      rec = await c.recomputeLiveItem(li, jwt: c.sellerJwt);
      liRec = await c.liveItemRow(li);
    }

    await dumpJson('${outDir()}/confirm.json', {
      'auditor': 'REDTEAM_BLIND_EA_RAFFLE_HUB_POS_DTDY_v1',
      'confirm': 'buyer_patch_after_drawn',
      'join': join?.brief,
      'close': close?.brief,
      'draw': draw?.brief,
      'li0': li0,
      'patch_buyer': patchBuyer?.brief,
      'li_after_buyer': liBuyer,
      'patch_seller': patchSeller?.brief,
      'li_after_seller': liSeller,
      'recompute': rec?.brief,
      'li_after_rec': liRec,
      'buyer_id': b1,
      'buyer2': b2,
    });
    stdout.writeln('buyer_patch ${patchBuyer?.brief}');
    stdout.writeln('seller_patch ${patchSeller?.brief}');
    stdout.writeln('li0 ${li0?['status']} ${li0?['is_active']}');
    stdout.writeln('liBuyer ${liBuyer?['status']} ${liBuyer?['is_active']}');
    stdout.writeln('liSeller ${liSeller?['status']} ${liSeller?['is_active']}');
    stdout.writeln('liRec ${liRec?['status']} ${liRec?['is_active']} rec=${rec?.brief}');
  } finally {
    await c.endAllCreatedLives();
    await c.restoreSeller1Published();
  }
}
