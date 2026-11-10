/// RED TEAM CEGO AP — pass 1. Staging only. Não corrige.
import 'dart:io';
import '_rtap.dart';

Future<void> main() async {
  final rt = Rtap.fromEnv(loadEnv());
  await rt.loginActors();
  await rt.ensureBuyer2();
  await rt.ensureSeller2();
  await rt.ensureHelper();
  rt.note('actors', 'JWT B1/S1/B2/S2/H', {
    'b1': rt.buyerId,
    's1': rt.sellerId,
    'b2': rt.buyer2Id,
    's2': rt.seller2Id,
    'h': rt.helperId,
  });

  final wallets0 = await rt.wallets();
  rt.note('wallets.t0', 'saldos iniciais', wallets0, lens: 'AP8');

  // Encerrar leftovers da ronda anterior (mesmo prefixo).
  final leftover = await rt.rest(
    'GET',
    'lives?title=like.*$prefix*&select=id,status,is_active',
    service: true,
  );
  for (final row in leftover.list) {
    if (row is Map && row['id'] != null) {
      await rt.rest(
        'PATCH',
        'lives?id=eq.${row['id']}',
        service: true,
        body: {'status': 'ended', 'is_active': false},
        prefer: 'return=minimal',
      );
    }
  }

  final liveA = await rt.insertLive(title: '$prefix A');
  final liveA2 = await rt.insertLive(title: '$prefix A2 pool');
  final liveB = await rt.insertLive(seller: rt.seller2Id, title: '$prefix B s2');
  if (liveA == null || liveB == null) {
    rt.skip('AP.fixture', 'AP1', 'insertLive falhou', {'a': liveA, 'b': liveB});
    await rt.cleanupSoft();
    await rt.dumpAll('pass1.json');
    exit(4);
  }

  final skuA = await rt.createProduct(title: '$prefix skuA', qty: 2, price: 11);
  final skuExtra = await rt.createProduct(
      title: '$prefix skuExtra', qty: 4, price: 33, listed: true);
  final skuVictim = await rt.createProduct(
      seller: rt.seller2Id, title: '$prefix skuVictim', qty: 2, price: 22);
  final skuPool = await rt.createProduct(title: '$prefix skuPool', qty: 1, price: 8);
  if ([skuA, skuExtra, skuVictim, skuPool].contains(null)) {
    rt.skip('AP.sku', 'AP4', 'createProduct falhou', {
      'a': skuA,
      'x': skuExtra,
      'v': skuVictim,
      'p': skuPool,
    });
  }

  final itemOnly = await rt.insertItem(
    liveId: liveA,
    jwt: rt.sellerJwt,
    kind: 'live_only',
    qty: 2,
    price: 15,
    title: '$prefix live_only',
  );
  final itemMkt = await rt.insertItem(
    liveId: liveA,
    jwt: rt.sellerJwt,
    kind: 'marketplace_product',
    productId: skuA,
    qty: 2,
    price: 11,
    title: '$prefix mkt',
  );
  final itemPool1 = await rt.insertItem(
    liveId: liveA,
    jwt: rt.sellerJwt,
    kind: 'marketplace_product',
    productId: skuPool,
    qty: 1,
    price: 8,
    title: '$prefix pool1',
  );
  final itemPool2 = await rt.insertItem(
    liveId: liveA2 ?? liveA,
    jwt: rt.sellerJwt,
    kind: 'marketplace_product',
    productId: skuPool,
    qty: 1,
    price: 8,
    title: '$prefix pool2',
  );
  final itemS2 = await rt.insertItem(
    liveId: liveB,
    jwt: rt.seller2Jwt,
    kind: 'live_only',
    qty: 1,
    price: 19,
    title: '$prefix s2 item',
  );

  final idOnly = itemOnly.firstId;
  final idMkt = itemMkt.firstId;
  final idPool1 = itemPool1.firstId;
  final idPool2 = itemPool2.firstId;
  final idS2 = itemS2.firstId;
  rt.note('fixture.items', 'live items', {
    'only': itemOnly.brief,
    'mkt': itemMkt.brief,
    'pool1': itemPool1.brief,
    'pool2': itemPool2.brief,
    's2': itemS2.brief,
  }, lens: 'AP1');

  if (idOnly == null) {
    rt.skip('AP.items', 'AP1', 'live_only insert falhou', itemOnly.brief);
    await rt.cleanupSoft();
    await rt.dumpAll('pass1.json');
    exit(5);
  }
  if (idMkt == null) {
    rt.note('AP.items.mkt', 'marketplace insert falhou — probes mkt degradados',
        itemMkt.brief, lens: 'AP4');
  }

  try {
  // =========================================================================
  // AP1 — Convert bypass (caminhos NÃO accepted→converted exactos)
  // =========================================================================
  final resPending = await rt.insertRes(
    liveId: liveA,
    itemId: idOnly,
    jwt: rt.buyerJwt,
    qty: 1,
  );
  final ridPending = resPending.firstId;
  rt.judge(
    id: 'AP1-01',
    lens: 'AP1',
    title: 'Buyer INSERT reservation status=converted',
    hit: await rt.insertRes(
      liveId: liveA,
      itemId: idOnly,
      jwt: rt.buyerJwt,
      status: 'converted',
      qty: 1,
    ),
    cracked: false, // set below via row
    actor: 'buyer JWT',
    pre: 'live broadcasting, live_only qty=2',
    repro: 'POST live_reservation_requests status=converted',
  );
  // Re-judge based on actual created row if any slipped through
  final convInsert = await rt.insertRes(
    liveId: liveA,
    itemId: idOnly,
    jwt: rt.buyerJwt,
    status: 'converted',
    qty: 1,
  );
  final convInsertId = convInsert.firstId;
  if (convInsertId != null) {
    final row = await rt.resRow(convInsertId);
    final st = '${row?['status']}'.toLowerCase();
    if (st == 'converted') {
      rt.hold(
        id: 'AP1-01b',
        lens: 'AP1',
        severity: 'P1',
        title: 'Buyer INSERT ficou converted sem order paga',
        actor: 'buyer JWT',
        pre: 'sem PI',
        repro: 'POST reservation status=converted',
        expected: 'pending ou 403',
        obtained: row,
      );
    } else {
      rt.block('AP1-01b', 'AP1', 'INSERT converted forçado a $st', convInsert);
    }
  } else {
    rt.block('AP1-01b', 'AP1', 'INSERT converted recusado', convInsert);
  }

  if (ridPending != null) {
    final patchConv = await rt.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$ridPending',
      jwt: rt.sellerJwt,
      body: {'status': 'converted'},
    );
    final afterPatch = await rt.resRow(ridPending);
    final st = '${afterPatch?['status']}'.toLowerCase();
    if (patchConv.ok && st == 'converted') {
      rt.hold(
        id: 'AP1-02',
        lens: 'AP1',
        severity: 'P1',
        title: 'Seller PATCH pending→converted sem order paga',
        actor: 'seller JWT',
        pre: 'reservation pending, sem PI',
        repro: 'PATCH live_reservation_requests status=converted',
        expected: 'convert_requires_paid_order',
        obtained: {'hit': patchConv.brief, 'row': afterPatch},
      );
    } else {
      rt.block('AP1-02', 'AP1', 'PATCH converted sem PI',
          {'hit': patchConv.brief, 'row': afterPatch});
    }

    final rpcConv = await rt.processRes(ridPending, 'convert');
    final afterRpc = await rt.resRow(ridPending);
    if (rpcConv.ok && '${afterRpc?['status']}'.toLowerCase() == 'converted') {
      rt.hold(
        id: 'AP1-03',
        lens: 'AP1',
        severity: 'P1',
        title: 'RPC convert pending sem order paga',
        actor: 'seller JWT',
        pre: 'pending, sem PI',
        repro: 'batata_process_live_reservation_request convert',
        expected: 'convert_requires_paid_order',
        obtained: {'hit': rpcConv.brief, 'row': afterRpc},
      );
    } else {
      rt.block('AP1-03', 'AP1', 'RPC convert sem PI',
          {'hit': rpcConv.brief, 'row': afterRpc});
    }

    final buyerRpc = await rt.processRes(ridPending, 'convert', jwt: rt.buyerJwt);
    rt.judge(
      id: 'AP1-04',
      lens: 'AP1',
      title: 'Buyer RPC convert na reserva própria',
      hit: buyerRpc,
      cracked: buyerRpc.ok && !buyerRpc.body.contains('not_allowed'),
      actor: 'buyer JWT',
      pre: 'pending',
      repro: 'process convert JWT buyer',
      expected: 'not_allowed',
    );
  } else {
    rt.skip('AP1-pending', 'AP1', 'INSERT pending falhou', resPending);
  }

  // Hitch paid order (marketplace, sem live_item) → live_item → convert
  if (skuA != null && idMkt != null) {
    final paidMkt = await rt.insertPaidOrder(
      productId: skuA,
      price: 11,
      pi: 'pi_rtap_mkt',
    );
    final resForHitch = await rt.insertRes(
      liveId: liveA,
      itemId: idMkt,
      jwt: rt.buyerJwt,
      qty: 1,
    );
    final ridHitch = resForHitch.firstId;
    if (paidMkt != null && ridHitch != null) {
      await rt.processRes(ridHitch, 'accept');
      final hitch = await rt.rest(
        'PATCH',
        'orders?id=eq.$paidMkt',
        jwt: rt.sellerJwt,
        body: {'live_item_id': idMkt, 'live_id': liveA},
      );
      final oHitch = await rt.orderRow(paidMkt);
      final hitchOk = hitch.ok && oHitch?['live_item_id']?.toString() == idMkt;
      if (hitchOk) {
        rt.hold(
          id: 'AP1-05',
          lens: 'AP1',
          severity: 'P1',
          title: 'Seller hitch live_item_id numa order paga de marketplace',
          actor: 'seller JWT',
          pre: 'order pago sem live_item',
          repro: 'PATCH orders.live_item_id = live item',
          expected: 'live_item_id imutável pós-pago',
          obtained: {'hit': hitch.brief, 'order': oHitch},
        );
        final convHitch = await rt.processRes(ridHitch, 'convert');
        final rHitch = await rt.resRow(ridHitch);
        if (convHitch.ok &&
            '${rHitch?['status']}'.toLowerCase() == 'converted') {
          rt.hold(
            id: 'AP1-06',
            lens: 'AP1',
            severity: 'P0',
            title: 'Convert live com PI de encomenda marketplace hitchada',
            actor: 'seller JWT',
            pre: 'PI de SKU marketplace, não do live item',
            repro: 'PATCH live_item_id + RPC convert',
            expected: 'convert_requires_paid_order para ESTE live_item',
            obtained: {'hit': convHitch.brief, 'res': rHitch, 'order': oHitch},
          );
        } else {
          rt.block('AP1-06', 'AP1', 'convert após hitch order',
              {'hit': convHitch.brief, 'res': rHitch});
        }
      } else {
        rt.block('AP1-05', 'AP1', 'hitch live_item_id em order paga',
            {'hit': hitch.brief, 'order': oHitch});
      }

      // Cross-item: paid order on idMkt vs convert on idOnly
      final resOther = await rt.insertRes(
        liveId: liveA,
        itemId: idOnly,
        jwt: rt.buyerJwt,
        qty: 1,
      );
      final ridOther = resOther.firstId;
      if (ridOther != null) {
        await rt.processRes(ridOther, 'accept');
        final convCross = await rt.processRes(ridOther, 'convert');
        final rCross = await rt.resRow(ridOther);
        if (convCross.ok &&
            '${rCross?['status']}'.toLowerCase() == 'converted') {
          rt.hold(
            id: 'AP1-07',
            lens: 'AP1',
            severity: 'P1',
            title: 'Convert item A com PI que só existe no item B',
            actor: 'seller JWT',
            pre: 'pago em idMkt, reserva em idOnly',
            repro: 'RPC convert noutro live_item_id',
            expected: 'convert_requires_paid_order',
            obtained: {'hit': convCross.brief, 'res': rCross},
          );
        } else {
          rt.block('AP1-07', 'AP1', 'convert cross live_item',
              {'hit': convCross.brief, 'res': rCross});
        }
      }

      // Cross-buyer: hitch paid order buyer_id to buyer2 then convert buyer2 res
      final resB2 = await rt.insertRes(
        liveId: liveA,
        itemId: idMkt,
        jwt: rt.buyer2Jwt,
        buyer: rt.buyer2Id,
        qty: 1,
      );
      final ridB2 = resB2.firstId;
      if (ridB2 != null) {
        await rt.processRes(ridB2, 'accept');
        final stealBuyer = await rt.rest(
          'PATCH',
          'orders?id=eq.$paidMkt',
          jwt: rt.sellerJwt,
          body: {'buyer_id': rt.buyer2Id},
        );
        final oSteal = await rt.orderRow(paidMkt);
        if (stealBuyer.ok && oSteal?['buyer_id']?.toString() == rt.buyer2Id) {
          rt.hold(
            id: 'AP1-08',
            lens: 'AP1',
            severity: 'P1',
            title: 'Seller PATCH buyer_id de order paga para outro comprador',
            actor: 'seller JWT',
            pre: 'order pago B1',
            repro: 'PATCH orders.buyer_id=B2',
            expected: 'buyer_id imutável',
            obtained: {'hit': stealBuyer.brief, 'order': oSteal},
          );
        } else {
          rt.block('AP1-08', 'AP1', 'PATCH buyer_id order paga',
              {'hit': stealBuyer.brief, 'order': oSteal});
        }
        final convB2 = await rt.processRes(ridB2, 'convert');
        final rB2 = await rt.resRow(ridB2);
        if (convB2.ok && '${rB2?['status']}'.toLowerCase() == 'converted') {
          rt.hold(
            id: 'AP1-09',
            lens: 'AP1',
            severity: 'P1',
            title: 'Convert reserva B2 com PI originalmente de B1',
            actor: 'seller JWT',
            pre: 'PI B1',
            repro: 'convert reserva B2',
            expected: 'convert_requires_paid_order',
            obtained: {'hit': convB2.brief, 'res': rB2, 'order': oSteal},
          );
        } else {
          rt.block('AP1-09', 'AP1', 'convert B2 sem PI B2',
              {'hit': convB2.brief, 'res': rB2});
        }
      }
    } else {
      rt.skip('AP1-hitch', 'AP1', 'paid order ou res falhou', {
        'paid': paidMkt,
        'res': resForHitch.brief,
      });
    }
  }

  // Fake PI via JWT then convert
  if (ridPending != null) {
    final fakePi = await rt.rest(
      'PATCH',
      'orders?select=id',
      jwt: rt.sellerJwt,
      body: {'stripe_payment_intent_id': 'pi_rtap_jwt_fake'},
    );
    rt.note('AP1.fakePi.blind', 'PATCH PI sem filtro', fakePi, lens: 'AP1');
  }

  final sellerManualConv = await rt.insertRes(
    liveId: liveA,
    itemId: idOnly,
    jwt: rt.sellerJwt,
    status: 'converted',
    source: 'helper_manual',
    qty: 1,
  );
  final smId = sellerManualConv.firstId;
  if (smId != null) {
    final sm = await rt.resRow(smId);
    if ('${sm?['status']}'.toLowerCase() == 'converted') {
      rt.hold(
        id: 'AP1-10',
        lens: 'AP1',
        severity: 'P1',
        title: 'Seller INSERT helper_manual já converted',
        actor: 'seller JWT',
        pre: 'sem PI',
        repro: 'POST source=helper_manual status=converted',
        expected: 'pending / convert_requires_paid_order',
        obtained: sm,
      );
    } else {
      rt.block('AP1-10', 'AP1', 'INSERT helper_manual converted → ${sm?['status']}',
          sellerManualConv);
    }
  } else {
    rt.block('AP1-10', 'AP1', 'INSERT helper_manual converted recusado',
        sellerManualConv);
  }

  final purchaseBc = await rt.rpc('batata_live_purchase_broadcast', {
    'p_live_id': liveA,
    'p_buyer_id': rt.buyerId,
    'p_live_item_id': idOnly,
  }, jwt: rt.buyerJwt);
  rt.judge(
    id: 'AP1-11',
    lens: 'AP1',
    title: 'Buyer chama purchase_broadcast directo',
    hit: purchaseBc,
    cracked: purchaseBc.ok,
    actor: 'buyer JWT',
    pre: 'sem convert pago',
    repro: 'rpc batata_live_purchase_broadcast',
    expected: 'revoke / not_allowed',
    severity: 'P2',
  );

  // =========================================================================
  // AP2 — Staff / helper
  // =========================================================================
  final hidView = await rt.inviteHelper(
    helperUserId: rt.helperId!,
    perms: {
      'can_view_live_dashboard': true,
      'can_mark_items_sold': false,
      'can_manage_reservations': false,
      'can_change_current_item': true,
    },
  );
  if (hidView != null) {
    final esc = await rt.rest(
      'PATCH',
      'seller_helpers?id=eq.$hidView',
      jwt: rt.helperJwt,
      body: {
        'invitation_status': 'accepted',
        'responded_at': DateTime.now().toUtc().toIso8601String(),
        'active': true,
        'permissions': {
          'can_mark_items_sold': true,
          'can_manage_reservations': true,
          'can_view_live_dashboard': true,
          'can_change_current_item': true,
        },
      },
    );
    final hrow = await rt.helperRow(hidView);
    final perms = hrow?['permissions'];
    final mark = perms is Map && perms['can_mark_items_sold'] == true;
    if (esc.ok && mark) {
      rt.hold(
        id: 'AP2-01',
        lens: 'AP2',
        severity: 'P1',
        title: 'Helper alarga permissions ao aceitar convite',
        actor: 'helper JWT',
        pre: 'convite view-only + can_change_current_item',
        repro: 'PATCH seller_helpers permissions+accepted',
        expected: 'permissions imutáveis (SEC-014)',
        obtained: {'hit': esc.brief, 'row': hrow},
      );
    } else {
      rt.block('AP2-01', 'AP2', 'helper escalate permissions',
          {'hit': esc.brief, 'row': hrow});
    }

    // Accept properly (view-only + can_change_current_item) if still pending
    if ('${hrow?['invitation_status']}' == 'pending') {
      await rt.rest(
        'PATCH',
        'seller_helpers?id=eq.$hidView',
        jwt: rt.helperJwt,
        body: {
          'invitation_status': 'accepted',
          'responded_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
    }
    final hAfter = await rt.helperRow(hidView);
    rt.note('AP2.helper.after', 'estado helper', hAfter, lens: 'AP2');

    final viewMs = await rt.markSold(idOnly, jwt: rt.helperJwt);
    final itemAfterView = await rt.itemRow(idOnly);
    if (viewMs.ok &&
        '${itemAfterView?['status']}'.toLowerCase() == 'sold' &&
        (hAfter?['permissions'] is Map &&
            (hAfter!['permissions'] as Map)['can_mark_items_sold'] != true)) {
      rt.hold(
        id: 'AP2-02',
        lens: 'AP2',
        severity: 'P1',
        title: 'Helper sem can_mark_items_sold executa mark_sold (can_change_current_item)',
        actor: 'helper JWT',
        pre: 'AHAM removeu can_change_current_item de mark_sold',
        repro: 'rpc mark_sold JWT helper view/change',
        expected: 'not_allowed',
        obtained: {'hit': viewMs.brief, 'item': itemAfterView, 'helper': hAfter},
      );
    } else {
      rt.block('AP2-02', 'AP2', 'helper mark_sold sem can_mark',
          {'hit': viewMs.brief, 'item': itemAfterView});
    }

    if (ridPending != null) {
      final hConv = await rt.processRes(ridPending, 'convert', jwt: rt.helperJwt);
      rt.judge(
        id: 'AP2-03',
        lens: 'AP2',
        title: 'Helper view-only RPC convert',
        hit: hConv,
        cracked: hConv.ok && !hConv.body.contains('not_allowed'),
        actor: 'helper JWT',
        pre: 'sem can_manage_reservations',
        repro: 'process convert JWT helper',
        expected: 'not_allowed',
      );
    }

    final selfInvite = await rt.rest('POST', 'seller_helpers', jwt: rt.helperJwt, body: {
      'seller_id': rt.sellerId,
      'helper_user_id': rt.helperId,
      'display_name': 'pwn',
      'invited_by': rt.helperId,
      'invitation_status': 'accepted',
      'active': true,
      'permissions': {'can_mark_items_sold': true},
    });
    rt.judge(
      id: 'AP2-04',
      lens: 'AP2',
      title: 'Helper INSERT seller_helpers na loja alheia',
      hit: selfInvite,
      cracked: selfInvite.ok,
      actor: 'helper JWT',
      pre: 'não é o seller',
      repro: 'POST seller_helpers seller_id=S1',
      expected: 'RLS deny',
    );

    final inviteRpc = await rt.rpc('batata_staff_invite_helper_by_email', {
      'p_email': '${prefix.toLowerCase()}-b2@fleaber.test',
      'p_display_name': 'pwn',
      'p_permissions': {'can_mark_items_sold': true},
    }, jwt: rt.helperJwt);
    rt.judge(
      id: 'AP2-05',
      lens: 'AP2',
      title: 'Helper convoca outro helper via RPC',
      hit: inviteRpc,
      cracked: inviteRpc.ok,
      actor: 'helper JWT',
      pre: 'não é vendedor dono',
      repro: 'batata_staff_invite_helper_by_email',
      expected: 'not_allowed',
    );
  } else {
    rt.skip('AP2.invite', 'AP2', 'inviteHelper falhou', 'null');
  }

  // =========================================================================
  // AP4 — hitch / mark_sold (ângulos ≠ AJ4-02 foreign checkout exact)
  // =========================================================================
  if (skuVictim != null) {
    final hitchPid = await rt.rest(
      'PATCH',
      'live_items?id=eq.$idOnly',
      jwt: rt.sellerJwt,
      body: {'product_id': skuVictim, 'item_kind': 'marketplace_product'},
    );
    final afterPid = await rt.itemRow(idOnly);
    if (hitchPid.ok && afterPid?['product_id']?.toString() == skuVictim) {
      rt.hold(
        id: 'AP4-01',
        lens: 'AP4',
        severity: 'P1',
        title: 'Seller hitch product_id de catálogo alheio no live_item',
        actor: 'seller JWT',
        pre: 'product seller2',
        repro: 'PATCH live_items.product_id = sku vítima',
        expected: 'live_item_product_seller_mismatch',
        obtained: {'hit': hitchPid.brief, 'item': afterPid},
      );
    } else {
      rt.block('AP4-01', 'AP4', 'hitch product_id alheio',
          {'hit': hitchPid.brief, 'item': afterPid});
    }

    final hitchCpi = await rt.rest(
      'PATCH',
      'live_items?id=eq.$idOnly',
      jwt: rt.sellerJwt,
      body: {'checkout_product_id': skuVictim},
    );
    final afterCpi = await rt.itemRow(idOnly);
    if (hitchCpi.ok && afterCpi?['checkout_product_id']?.toString() == skuVictim) {
      rt.hold(
        id: 'AP4-02',
        lens: 'AP4',
        severity: 'P1',
        title: 'Seller hitch checkout_product_id alheio (UPDATE, não INSERT)',
        actor: 'seller JWT',
        pre: 'sku seller2',
        repro: 'PATCH checkout_product_id',
        expected: 'live_item_checkout_product_seller_mismatch',
        obtained: {'hit': hitchCpi.brief, 'item': afterCpi},
      );
    } else {
      rt.block('AP4-02', 'AP4', 'hitch checkout_product UPDATE alheio',
          {'hit': hitchCpi.brief, 'item': afterCpi});
    }
  }

  // Hitch próprio SKU extra + mark_sold com PI noutro contexto
  if (skuExtra != null) {
    final hitchOwn = await rt.rest(
      'PATCH',
      'live_items?id=eq.$idOnly',
      jwt: rt.sellerJwt,
      body: {'checkout_product_id': skuExtra},
    );
    final afterOwn = await rt.itemRow(idOnly);
    rt.note('AP4.hitchOwn', 'hitch checkout SKU extra próprio', {
      'hit': hitchOwn.brief,
      'item': afterOwn,
    }, lens: 'AP4');

    final msNoPi = await rt.markSold(idOnly);
    final extraAfter = await rt.productRow(skuExtra);
    final itemMs = await rt.itemRow(idOnly);
    final unlisted = extraAfter?['list_on_marketplace'] == false ||
        extraAfter?['is_sold'] == true;
    if (msNoPi.ok && unlisted) {
      rt.hold(
        id: 'AP4-03',
        lens: 'AP4',
        severity: 'P1',
        title: 'mark_sold live_only deslista SKU extra hitchado sem PI deste item',
        actor: 'seller JWT',
        pre: 'checkout_product=skuExtra, sem order paga no live_item',
        repro: 'PATCH checkout_product_id próprio + mark_sold',
        expected: 'SKU extra permanece listado (AHAM exige PI)',
        obtained: {
          'hit': msNoPi.brief,
          'extra': extraAfter,
          'item': itemMs,
        },
      );
    } else {
      rt.block('AP4-03', 'AP4', 'mark_sold sem PI não deslista sku extra', {
        'hit': msNoPi.brief,
        'extra': extraAfter,
        'item': itemMs,
      });
    }
  }

  if (idMkt != null) {
    final unicodeSold = await rt.rest(
      'PATCH',
      'live_items?id=eq.$idMkt',
      jwt: rt.sellerJwt,
      body: {'status': 'SOLD'},
    );
    final afterU = await rt.itemRow(idMkt);
    if (unicodeSold.ok && '${afterU?['status']}'.toLowerCase() == 'sold') {
      rt.hold(
        id: 'AP4-04',
        lens: 'AP4',
        severity: 'P2',
        title: 'PATCH status=SOLD (maiúsculas) contorna rpc-only',
        actor: 'seller JWT',
        pre: 'guard compara lower=sold',
        repro: 'PATCH live_items.status=SOLD',
        expected: 'live_item_status_sold_rpc_only ou no-op',
        obtained: {'hit': unicodeSold.brief, 'item': afterU},
      );
    } else {
      rt.block('AP4-04', 'AP4', 'PATCH status=SOLD',
          {'hit': unicodeSold.brief, 'item': afterU});
    }
  }

  final s2ms = await rt.markSold(idOnly, jwt: rt.seller2Jwt);
  rt.judge(
    id: 'AP4-05',
    lens: 'AP4',
    title: 'Seller2 mark_sold no item da live A',
    hit: s2ms,
    cracked: s2ms.ok && !s2ms.body.contains('not_allowed'),
    actor: 'seller2 JWT',
    pre: 'live A é do seller1',
    repro: 'rpc mark_sold JWT s2',
    expected: 'not_allowed',
  );

  final insertSold = await rt.insertItem(
    liveId: liveA,
    jwt: rt.sellerJwt,
    kind: 'live_only',
    qty: 1,
    status: 'sold',
    title: '$prefix insert sold',
  );
  rt.judge(
    id: 'AP4-06',
    lens: 'AP4',
    title: 'INSERT live_item já status=sold',
    hit: insertSold,
    cracked: insertSold.ok,
    actor: 'seller JWT',
    pre: 'AHAM INSERT sold bloqueado',
    repro: 'POST live_items status=sold',
    expected: 'live_item_status_sold_rpc_only',
    severity: 'P2',
  );

  // =========================================================================
  // AP5 — live_id / qty / cross-seller / two items same SKU
  // =========================================================================
  if (idS2 != null) {
    final stealLive = await rt.rest(
      'PATCH',
      'live_items?id=eq.$idS2',
      jwt: rt.sellerJwt,
      body: {'live_id': liveA},
    );
    final afterSteal = await rt.itemRow(idS2);
    if (stealLive.ok && afterSteal?['live_id']?.toString() == liveA) {
      rt.hold(
        id: 'AP5-01',
        lens: 'AP5',
        severity: 'P1',
        title: 'Seller A move live_item da live B para a sua live',
        actor: 'seller JWT',
        pre: 'item pertence a seller2',
        repro: 'PATCH live_items.live_id',
        expected: 'live_item_not_authorized',
        obtained: {'hit': stealLive.brief, 'item': afterSteal},
      );
    } else {
      rt.block('AP5-01', 'AP5', 'mover live_id alheio',
          {'hit': stealLive.brief, 'item': afterSteal});
    }
  }

  final bumpQty = await rt.rest(
    'PATCH',
    'live_items?id=eq.$idOnly',
    jwt: rt.sellerJwt,
    body: {'quantity': 99},
  );
  final afterBump = await rt.itemRow(idOnly);
  final qtyNow = afterBump?['quantity'];
  if (bumpQty.ok && (qtyNow is num && qtyNow >= 99)) {
    rt.hold(
      id: 'AP5-02',
      lens: 'AP5',
      severity: 'P1',
      title: 'Seller aumenta qty de live_only para 99',
      actor: 'seller JWT',
      pre: 'live_only qty=2, AHAM bloqueia aumento live_only',
      repro: 'PATCH live_items.quantity=99',
      expected: 'live_item_qty_increase_not_allowed',
      obtained: {'hit': bumpQty.brief, 'item': afterBump},
    );
  } else {
    rt.block('AP5-02', 'AP5', 'qty increase live_only',
        {'hit': bumpQty.brief, 'item': afterBump});
  }

  if (idPool1 != null && idPool2 != null && skuPool != null) {
    final r1 = await rt.insertRes(
      liveId: liveA,
      itemId: idPool1,
      jwt: rt.buyerJwt,
      qty: 1,
    );
    final r2 = await rt.insertRes(
      liveId: liveA2 ?? liveA,
      itemId: idPool2,
      jwt: rt.buyer2Jwt,
      buyer: rt.buyer2Id,
      qty: 1,
    );
    final a1 = r1.firstId != null ? await rt.processRes(r1.firstId!, 'accept') : r1;
    final a2 = r2.firstId != null ? await rt.processRes(r2.firstId!, 'accept') : r2;
    final rr1 = r1.firstId != null ? await rt.resRow(r1.firstId!) : null;
    final rr2 = r2.firstId != null ? await rt.resRow(r2.firstId!) : null;
    final bothAcc = '${rr1?['status']}' == 'accepted' &&
        '${rr2?['status']}' == 'accepted';
    if (bothAcc) {
      rt.hold(
        id: 'AP5-03',
        lens: 'AP5',
        severity: 'P1',
        title: 'Dois live_items no mesmo SKU qty=1 aceitam 2 reservas',
        actor: 'seller JWT',
        pre: 'product.quantity=1, dois live_items qty=1',
        repro: 'accept em pool1 e pool2',
        expected: '2.º accept qty_exceeds_stock / hold produto',
        obtained: {
          'a1': a1.brief,
          'a2': a2.brief,
          'r1': rr1,
          'r2': rr2,
          'product': await rt.productRow(skuPool),
        },
      );
    } else {
      rt.block('AP5-03', 'AP5', 'cross-item same SKU accept', {
        'a1': a1.brief,
        'a2': a2.brief,
        'r1': rr1,
        'r2': rr2,
      });
    }
  }

  final s2itemOnA = await rt.insertItem(
    liveId: liveA,
    jwt: rt.seller2Jwt,
    kind: 'live_only',
    qty: 1,
    title: '$prefix s2 on A',
  );
  rt.judge(
    id: 'AP5-04',
    lens: 'AP5',
    title: 'Seller2 INSERT item na live A',
    hit: s2itemOnA,
    cracked: s2itemOnA.ok,
    actor: 'seller2 JWT',
    pre: 'live A seller1',
    repro: 'POST live_items live_id=A JWT s2',
    expected: 'live_item_not_authorized',
  );

  // =========================================================================
  // AP6 — Race accept/convert
  // =========================================================================
  final raceItem = await rt.insertItem(
    liveId: liveA,
    jwt: rt.sellerJwt,
    kind: 'live_only',
    qty: 1,
    title: '$prefix race',
  );
  final raceId = raceItem.firstId;
  if (raceId != null) {
    final ra = await rt.insertRes(
        liveId: liveA, itemId: raceId, jwt: rt.buyerJwt, qty: 1);
    final rb = await rt.insertRes(
        liveId: liveA,
        itemId: raceId,
        jwt: rt.buyer2Jwt,
        buyer: rt.buyer2Id,
        qty: 1);
    if (ra.firstId != null && rb.firstId != null) {
      final raced = await Future.wait([
        rt.processRes(ra.firstId!, 'accept'),
        rt.processRes(rb.firstId!, 'accept'),
      ]);
      final sa = await rt.resRow(ra.firstId!);
      final sb = await rt.resRow(rb.firstId!);
      final acc = [
        if ('${sa?['status']}' == 'accepted') 1,
        if ('${sb?['status']}' == 'accepted') 1,
      ].length;
      if (acc >= 2) {
        rt.hold(
          id: 'AP6-01',
          lens: 'AP6',
          severity: 'P1',
          title: 'Race accept stock=1: duas reservas accepted',
          actor: 'seller JWT paralelo',
          pre: 'live_only qty=1, duas pending',
          repro: 'dois process accept em paralelo',
          expected: 'só 1 accepted',
          obtained: {
            'h0': raced[0].brief,
            'h1': raced[1].brief,
            'r0': sa,
            'r1': sb,
          },
        );
      } else {
        rt.block('AP6-01', 'AP6', 'race accept stock=1', {
          'h0': raced[0].brief,
          'h1': raced[1].brief,
          'r0': sa,
          'r1': sb,
        });
      }
    } else {
      rt.skip('AP6.res', 'AP6', 'reservas race falharam', {
        'a': ra.brief,
        'b': rb.brief,
      });
    }
  }

  // =========================================================================
  // AP3 — Hub / REST / stock fantasma (≠ anon 401 exact)
  // =========================================================================
  final hubSnap = await rt.rest(
    'GET',
    'profiles?id=eq.${rt.sellerId}&select=id,hub_published,handle,is_live',
    service: true,
  );
  rt.note('AP3.profile', 'hub flags seller', hubSnap.map, lens: 'AP3');

  // Force reserved_full via accept filling qty on a dedicated item
  final ghost = await rt.insertItem(
    liveId: liveA,
    jwt: rt.sellerJwt,
    kind: 'live_only',
    qty: 1,
    title: '$prefix ghost',
  );
  final gid = ghost.firstId;
  String? ghostStatus;
  if (gid != null) {
    final gr = await rt.insertRes(
        liveId: liveA, itemId: gid, jwt: rt.buyerJwt, qty: 1);
    if (gr.firstId != null) {
      await rt.processRes(gr.firstId!, 'accept');
    }
    final grow = await rt.itemRow(gid);
    ghostStatus = '${grow?['status']}';
    rt.note('AP3.ghost.item', 'após accept qty=1', grow, lens: 'AP3');

    final hubItems = await rt.rest(
      'GET',
      'hub_live_items_public?id=eq.$gid&select=id,status,title',
    );
    final disc = await rt.rest(
      'GET',
      'hub_live_items_discovery_public?id=eq.$gid&select=id,status,title',
    );
    final restBuyer = await rt.rest(
      'GET',
      'live_items?id=eq.$gid&select=id,status,quantity,is_active',
      jwt: rt.buyerJwt,
    );
    final restAnon = await rt.rest(
      'GET',
      'live_items?id=eq.$gid&select=id,status,quantity,is_active',
    );
    final stockAnon = await rt.rpc('batata_live_item_stock', {
      'p_live_item_id': gid,
    });
    final stockMap = stockAnon.map;
    final avail = stockMap == null
        ? null
        : int.tryParse('${stockMap['available_qty'] ?? ''}');
    final reservedFull = ghostStatus.toLowerCase().contains('reserved');

    final hubShows = hubItems.ok && hubItems.list.isNotEmpty;
    final discShows = disc.ok && disc.list.isNotEmpty;
    if (reservedFull && (hubShows || discShows)) {
      rt.hold(
        id: 'AP3-01',
        lens: 'AP3',
        severity: 'P2',
        title: 'Item reserved_full ainda visível no Hub',
        actor: 'anon',
        pre: 'accept stock=1',
        repro: 'GET hub_live_items_public / discovery',
        expected: '0 rows',
        obtained: {
          'status': ghostStatus,
          'hub': hubItems.brief,
          'disc': disc.brief,
        },
      );
    } else {
      rt.block('AP3-01', 'AP3', 'Hub esconde reserved_full/esgotado', {
        'status': ghostStatus,
        'hub': hubItems.brief,
        'disc': disc.brief,
      });
    }

    if (restBuyer.ok && restBuyer.list.isNotEmpty && reservedFull) {
      rt.hold(
        id: 'AP3-02',
        lens: 'AP3',
        severity: 'P2',
        title: 'Buyer REST vê live_item reserved_full (AHAM broadcasting+stock)',
        actor: 'buyer JWT',
        pre: 'item reserved_full',
        repro: 'GET live_items id',
        expected: '0 rows para não-owner',
        obtained: restBuyer.brief,
      );
    } else {
      rt.block('AP3-02', 'AP3', 'REST buyer reserved_full', restBuyer);
    }

    rt.note('AP3.anon.rest', 'anon live_items', restAnon.brief, lens: 'AP3');
    rt.note('AP3.anon.stock', 'anon stock rpc', stockAnon.brief, lens: 'AP3');
    if (stockAnon.ok && avail != null && avail > 0 && reservedFull) {
      rt.hold(
        id: 'AP3-03',
        lens: 'AP3',
        severity: 'P2',
        title: 'RPC stock anon diz available_qty>0 em reserved_full',
        actor: 'anon',
        pre: 'accept qty=1',
        repro: 'batata_live_item_stock',
        expected: 'available_qty=0',
        obtained: stockAnon.brief,
      );
    } else {
      rt.block('AP3-03', 'AP3', 'stock rpc reserved_full', stockAnon);
    }
  }

  // Ended live still exposing items
  final endedLive = await rt.insertLive(
    status: 'ended',
    active: false,
    title: '$prefix ended',
  );
  if (endedLive != null) {
    final endedItem = await rt.insertItem(
      liveId: endedLive,
      service: true,
      kind: 'live_only',
      qty: 1,
      title: '$prefix ended item',
    );
    final eid = endedItem.firstId;
    if (eid != null) {
      final hubEnded = await rt.rest(
        'GET',
        'hub_live_items_public?id=eq.$eid&select=id,status',
      );
      final restEnded = await rt.rest(
        'GET',
        'live_items?id=eq.$eid&select=id,status,live_id',
        jwt: rt.buyerJwt,
      );
      final stockEnded = await rt.rpc('batata_live_item_stock', {
        'p_live_item_id': eid,
      });
      if (hubEnded.ok && hubEnded.list.isNotEmpty) {
        rt.hold(
          id: 'AP3-04',
          lens: 'AP3',
          severity: 'P2',
          title: 'Hub mostra item de live ended',
          actor: 'anon',
          pre: 'live status=ended is_active=false',
          repro: 'GET hub_live_items_public',
          expected: '0 rows (broadcasting filter)',
          obtained: hubEnded.brief,
        );
      } else {
        rt.block('AP3-04', 'AP3', 'Hub ended item', hubEnded);
      }
      if (restEnded.ok && restEnded.list.isNotEmpty) {
        rt.hold(
          id: 'AP3-05',
          lens: 'AP3',
          severity: 'P2',
          title: 'Buyer REST lê live_item de live ended',
          actor: 'buyer JWT',
          pre: 'AHAM REST exige broadcasting',
          repro: 'GET live_items',
          expected: '0 rows',
          obtained: restEnded.brief,
        );
      } else {
        rt.block('AP3-05', 'AP3', 'REST ended item', restEnded);
      }
      rt.note('AP3.ended.stock', 'stock rpc ended', stockEnded.brief, lens: 'AP3');

      final resEnded = await rt.insertRes(
        liveId: endedLive,
        itemId: eid,
        jwt: rt.buyerJwt,
        qty: 1,
      );
      rt.judge(
        id: 'AP3-06',
        lens: 'AP3',
        title: 'Buyer reserva em live ended',
        hit: resEnded,
        cracked: resEnded.ok,
        actor: 'buyer JWT',
        pre: 'live ended',
        repro: 'POST live_reservation_requests',
        expected: 'live_ended',
      );
    }
  }

  // =========================================================================
  // AP7 — Sabotar live alheia / Mux
  // =========================================================================
  final killLive = await rt.rest(
    'PATCH',
    'lives?id=eq.$liveA',
    jwt: rt.seller2Jwt,
    body: {'status': 'ended', 'is_active': false},
  );
  final liveAfterKill = await rt.rest(
    'GET',
    'lives?id=eq.$liveA&select=id,status,is_active,seller_id',
    service: true,
  );
  final la = liveAfterKill.map;
  if (killLive.ok && '${la?['status']}' == 'ended') {
    rt.hold(
      id: 'AP7-01',
      lens: 'AP7',
      severity: 'P1',
      title: 'Seller2 termina a live A via REST',
      actor: 'seller2 JWT',
      pre: 'live A seller1',
      repro: 'PATCH lives status=ended',
      expected: 'RLS deny',
      obtained: {'hit': killLive.brief, 'live': la},
    );
  } else {
    rt.block('AP7-01', 'AP7', 'PATCH live alheia',
        {'hit': killLive.brief, 'live': la});
  }

  final completeMux = await rt.edge('complete-mux-live', {
    'live_id': liveA,
  }, jwt: rt.seller2Jwt);
  rt.judge(
    id: 'AP7-02',
    lens: 'AP7',
    title: 'Seller2 complete-mux-live na live A',
    hit: completeMux,
    cracked: completeMux.ok,
    actor: 'seller2 JWT',
    pre: 'não é owner',
    repro: 'edge complete-mux-live',
    expected: '403',
  );

  final pubMux = await rt.edge('livekit-mux-publish', {
    'step': 'token',
    'live_id': liveA,
  }, jwt: rt.seller2Jwt);
  rt.judge(
    id: 'AP7-03',
    lens: 'AP7',
    title: 'Seller2 pede token LiveKit da live A',
    hit: pubMux,
    cracked: pubMux.ok,
    actor: 'seller2 JWT',
    pre: 'não é owner',
    repro: 'edge livekit-mux-publish token',
    expected: '403',
  );

  final insertAlien = await rt.rest('POST', 'lives', jwt: rt.seller2Jwt, body: {
    'seller_id': rt.sellerId,
    'vendedor_id': rt.sellerId,
    'title': '$prefix hijack',
    'status': 'live',
    'is_active': true,
  });
  rt.judge(
    id: 'AP7-04',
    lens: 'AP7',
    title: 'Seller2 INSERT live com seller_id da vítima',
    hit: insertAlien,
    cracked: insertAlien.ok,
    actor: 'seller2 JWT',
    pre: 'seller_id=S1',
    repro: 'POST lives',
    expected: 'RLS with check fail',
  );

  final sk = await rt.rest(
    'GET',
    'lives?id=eq.$liveA&select=id,stream_key,mux_stream_key,mux_live_id',
    jwt: rt.buyerJwt,
  );
  final leaked = sk.body.contains('stream_key') &&
      !sk.body.contains('PGRST') &&
      sk.ok &&
      (sk.map?['stream_key'] != null || sk.map?['mux_stream_key'] != null);
  if (leaked) {
    rt.hold(
      id: 'AP7-05',
      lens: 'AP7',
      severity: 'P1',
      title: 'Buyer lê stream_key da live via REST',
      actor: 'buyer JWT',
      pre: 'SEC-003b revoke colunas secretas',
      repro: 'GET lives select stream_key',
      expected: 'PGRST column deny / null',
      obtained: sk.brief,
    );
  } else {
    rt.block('AP7-05', 'AP7', 'REST stream_key', sk);
  }

  final delLive = await rt.rest(
    'DELETE',
    'lives?id=eq.$liveA',
    jwt: rt.seller2Jwt,
  );
  rt.judge(
    id: 'AP7-06',
    lens: 'AP7',
    title: 'Seller2 DELETE live A',
    hit: delLive,
    cracked: delLive.ok && delLive.list.isNotEmpty,
    actor: 'seller2 JWT',
    pre: 'live A',
    repro: 'DELETE lives',
    expected: 'RLS deny',
  );

  final ocr = await rt.edge('ingest-ocr-reservation', {
    'live_id': liveA,
    'ocr_line_hash': 'rtaphash12345678',
    'detected_at': DateTime.now().toUtc().toIso8601String(),
    'ref_number': 1,
    'external_display_name': 'pwn',
  }, jwt: rt.buyerJwt);
  rt.judge(
    id: 'AP7-07',
    lens: 'AP7',
    title: 'Buyer ingest OCR na live alheia sem device token',
    hit: ocr,
    cracked: ocr.ok && ocr.body.contains('"ok":true'),
    actor: 'buyer JWT',
    pre: 'sem x-device-token',
    repro: 'edge ingest-ocr-reservation',
    expected: '401 missing_device_token',
    severity: 'P2',
  );

  if (hidView != null) {
    final helperKill = await rt.rest(
      'PATCH',
      'lives?id=eq.$liveA',
      jwt: rt.helperJwt,
      body: {'status': 'ended', 'is_active': false},
    );
    rt.judge(
      id: 'AP7-08',
      lens: 'AP7',
      title: 'Helper view-only termina a live REST',
      hit: helperKill,
      cracked: helperKill.ok,
      actor: 'helper JWT',
      pre: 'não é owner',
      repro: 'PATCH lives',
      expected: 'RLS deny',
    );
  }

  // =========================================================================
  // AP8 — Caixa: wallet / order fantasma
  // =========================================================================
  final wallets1 = await rt.wallets();
  rt.note('wallets.t1', 'saldos após probes', wallets1, lens: 'AP8');
  for (final k in wallets0.keys) {
    final d = (wallets1[k] ?? 0) - (wallets0[k] ?? 0);
    if (d.abs() > 0.009) {
      rt.hold(
        id: 'AP8-01-$k',
        lens: 'AP8',
        severity: 'P0',
        title: 'Wallet $k mudou sem pagamento Stripe TEST',
        actor: 'probes JWT',
        pre: 't0=$wallets0 t1=$wallets1',
        repro: 'convert/mark_sold/hitch sem captura nova',
        expected: 'Δ=0',
        obtained: {'delta': d, 't0': wallets0[k], 't1': wallets1[k]},
      );
    } else {
      rt.block('AP8-01-$k', 'AP8', 'wallet $k estável', {
        't0': wallets0[k],
        't1': wallets1[k],
      });
    }
  }

  // Ghost order: convert should not INSERT orders
  final ghostOrders = await rt.rest(
    'GET',
    'orders?description=eq.$prefix&select=id,status,amount_paid_cents,live_item_id',
    service: true,
  );
  rt.note('AP8.orders.prefix', 'orders criadas no probe', {
    'created': rt.createdOrderIds,
    'query': ghostOrders.brief,
  }, lens: 'AP8');

  final fakePiOrder = await rt.insertOpenOrder(
    productId: skuA ?? skuPool ?? skuExtra ?? '',
    jwt: rt.buyerJwt,
    liveItemId: idOnly,
    liveId: liveA,
    price: 15,
  );
  if (fakePiOrder != null) {
    final stampPi = await rt.rest(
      'PATCH',
      'orders?id=eq.$fakePiOrder',
      jwt: rt.buyerJwt,
      body: {
        'stripe_payment_intent_id': 'pi_buyer_lie',
        'amount_paid_cents': 1500,
        'status': 'pago',
      },
    );
    final oLie = await rt.orderRow(fakePiOrder);
    final paidLie = '${oLie?['status']}' == 'pago' ||
        (oLie?['stripe_payment_intent_id']?.toString().contains('pi_buyer') ??
            false) ||
        (oLie?['amount_paid_cents'] is num &&
            (oLie!['amount_paid_cents'] as num) > 0);
    if (stampPi.ok && paidLie) {
      rt.hold(
        id: 'AP8-02',
        lens: 'AP8',
        severity: 'P0',
        title: 'Buyer carimba PI/pago na própria order',
        actor: 'buyer JWT',
        pre: 'reserva_pendente',
        repro: 'PATCH stripe_payment_intent_id + status=pago',
        expected: 'money_cols / buyer cannot mark pago',
        obtained: {'hit': stampPi.brief, 'order': oLie},
      );
      if (ridPending != null) {
        final convLie = await rt.processRes(ridPending, 'convert');
        final rLie = await rt.resRow(ridPending);
        if (convLie.ok && '${rLie?['status']}' == 'converted') {
          rt.hold(
            id: 'AP8-03',
            lens: 'AP8',
            severity: 'P0',
            title: 'Convert aceita PI carimbado pelo buyer',
            actor: 'seller JWT após lie buyer',
            pre: 'PI jwt fake',
            repro: 'PATCH PI buyer + convert',
            expected: 'convert_requires_paid_order',
            obtained: {'hit': convLie.brief, 'res': rLie, 'order': oLie},
          );
        } else {
          rt.block('AP8-03', 'AP8', 'convert após PI jwt',
              {'hit': convLie.brief, 'res': rLie});
        }
      }
    } else {
      rt.block('AP8-02', 'AP8', 'buyer stamp PI/pago',
          {'hit': stampPi.brief, 'order': oLie});
    }
  }
  } finally {
    await rt.cleanupSoft();
    await rt.dumpAll('pass1.json');
  }
  stdout.writeln(
      'DONE findings=${rt.findings.length} blocked=${rt.blocked.length} notes=${rt.notes.length}');
}
