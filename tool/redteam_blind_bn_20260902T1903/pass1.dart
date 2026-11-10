/// BN pass1 — all 8 lenses. Staging only. Do not fix.
import 'dart:io';

import '_rtbn.dart';

Future<void> main() async {
  final c = Rtbn.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final chatH = await c.ensureNamedHelper(tag: 'hc', pass: 'Rtbn1903hc!xK');
  final markH = await c.ensureNamedHelper(tag: 'hm', pass: 'Rtbn1903hm!xK');
  final viewH = await c.ensureNamedHelper(tag: 'hv', pass: 'Rtbn1903hv!xK');
  c.helperChatId = chatH['id'];
  c.helperChatJwt = chatH['jwt'];
  c.helperMarkId = markH['id'];
  c.helperMarkJwt = markH['jwt'];
  c.helperViewId = viewH['id'];
  c.helperViewJwt = viewH['jwt'];

  if (c.helperChatId != null) {
    await c.fixtureHelper(helperUserId: c.helperChatId!, perms: {
      'can_manage_chat': true,
      'can_mark_items_sold': false,
      'can_manage_reservations': false,
      'can_change_current_item': false,
    });
  }
  if (c.helperMarkId != null) {
    await c.fixtureHelper(helperUserId: c.helperMarkId!, perms: {
      'can_manage_chat': false,
      'can_mark_items_sold': true,
      'can_manage_reservations': false,
      'can_change_current_item': false,
    });
  }
  if (c.helperViewId != null) {
    await c.fixtureHelper(helperUserId: c.helperViewId!, perms: {
      'can_view_live_dashboard': true,
      'can_manage_chat': false,
      'can_mark_items_sold': false,
      'can_manage_reservations': false,
    });
  }

  final wallets0 = await c.wallets();
  c.note('w0', 'wallets start', wallets0, lens: 'BN8');

  final liveA = await c.insertLive(
    muxPlayback: 'bnAplay$stamp',
    muxLiveId: 'bnAlive$stamp',
    muxStreamKey: 'bnAkey$stamp',
  );
  final liveB = await c.insertLive(seller: c.seller2Id, status: 'live');
  final liveSched = await c.insertLive(status: 'scheduled', active: false);

  final skuA = await c.createProduct(title: '$prefix-skuA', qty: 2);
  final skuExtra = await c.createProduct(title: '$prefix-extra', qty: 1);
  final skuS2 = await c.createProduct(
    seller: c.seller2Id,
    title: '$prefix-s2',
    qty: 1,
  );

  if (liveA == null || skuA == null) {
    stderr.writeln('fixture live/sku failed');
    await dumpJson('${outDir()}/pass1.json', {'ok': false});
    return;
  }

  final itemLo = await c.insertLiveOnlyItem(
    liveId: liveA,
    qty: 1,
    ref: 'BNLO1',
    service: true,
  );
  final itemMkt = await c.insertMarketItem(
    liveId: liveA,
    productId: skuA,
    service: true,
  );
  final itemHitch = await c.insertLiveOnlyItem(
    liveId: liveA,
    qty: 1,
    ref: 'BNHITCH',
    checkoutProductId: skuExtra,
    service: true,
  );
  final itemPool1 = await c.insertLiveOnlyItem(
    liveId: liveA,
    qty: 1,
    ref: 'BNPOOL',
    service: true,
  );

  // ── BN1 convert / broadcast ──────────────────────────────────────────
  if (itemLo != null) {
    final restConv = await c.insertReservation(
      liveId: liveA,
      liveItemId: itemLo,
      buyer: c.buyerId,
      status: 'converted',
      jwt: c.buyerJwt,
    );
    if (restConv.ok && (restConv.map?['status']?.toString() == 'converted')) {
      c.hold(
        id: 'P1-BN1-rest-insert-converted',
        lens: 'BN1',
        severity: 'P1',
        title: 'Buyer REST INSERT reservation status=converted sem PI',
        actor: 'buyer JWT',
        pre: 'live broadcasting, live_only qty=1, sem order paga',
        repro: 'POST live_reservation_requests status=converted',
        expected: 'bloqueado convert_requires_paid_order',
        obtained: restConv.brief,
      );
    } else {
      c.block('BN1-01', 'BN1', 'REST INSERT converted', restConv);
    }

    final pend = await c.insertReservation(
      liveId: liveA,
      liveItemId: itemLo,
      buyer: c.buyerId,
      jwt: c.buyerJwt,
    );
    final pendId = pend.firstId;
    if (pendId != null) {
      final convB = await c.stripeConvert(pendId, jwt: c.buyerJwt);
      final afterB = await c.reqRow(pendId);
      final stB = afterB?['status']?.toString();
      if (convB.rpcOk && stB == 'converted') {
        c.hold(
          id: 'P1-BN1-stripe-convert-sem-pi',
          lens: 'BN1',
          severity: 'P1',
          title: 'Buyer JWT stripe_convert reserva pending sem order paga',
          actor: 'buyer JWT',
          pre: 'pending fleaber_live, sem PI/captura',
          repro: 'rpc batata_live_reservation_stripe_convert',
          expected: 'convert_requires_paid_order / not_allowed',
          obtained: {'rpc': convB.brief, 'status': stB},
        );
      } else {
        c.block('BN1-02', 'BN1', 'stripe_convert buyer sem PI', {
          'rpc': convB.brief,
          'status': stB,
        });
      }

      if (stB != 'converted') {
        final convS = await c.stripeConvert(pendId, jwt: c.sellerJwt);
        final afterS = await c.reqRow(pendId);
        final stS = afterS?['status']?.toString();
        if (convS.rpcOk && stS == 'converted') {
          c.hold(
            id: 'P1-BN1-seller-stripe-convert-sem-pi',
            lens: 'BN1',
            severity: 'P1',
            title: 'Seller JWT stripe_convert pending sem PI',
            actor: 'seller JWT',
            pre: 'pending sem order paga',
            repro: 'rpc batata_live_reservation_stripe_convert JWT seller',
            expected: 'convert_requires_paid_order',
            obtained: {'rpc': convS.brief, 'status': stS},
          );
        } else {
          c.block('BN1-03', 'BN1', 'stripe_convert seller sem PI', {
            'rpc': convS.brief,
            'status': stS,
          });
        }
      }
    } else {
      c.note('BN1.pend.fail', 'pending insert', pend.brief, lens: 'BN1');
    }

    final bc = await c.purchaseBroadcast(
      liveId: liveA,
      buyer: c.buyerId!,
      liveItemId: itemLo,
      jwt: c.sellerJwt,
    );
    final afterBc = await c.msgs(liveA);
    final fakeBuy = afterBc.any((m) {
      final b = '${m['body']}'.toLowerCase();
      return b.contains('comprou') && '${m['kind']}' == 'system';
    });
    if (bc.json == true || (bc.ok && bc.body.trim() == 'true') || fakeBuy) {
      c.hold(
        id: 'P2-BN1-broadcast-sem-pago',
        lens: 'BN1',
        severity: 'P2',
        title: 'purchase_broadcast anuncia compra sem order paga',
        actor: 'seller JWT',
        pre: 'sem order pago no item',
        repro: 'rpc batata_live_purchase_broadcast',
        expected: 'false, sem mensagem system comprou',
        obtained: {'rpc': bc.brief, 'msgs': afterBc.take(3).toList()},
      );
    } else {
      c.block('BN1-04', 'BN1', 'purchase_broadcast sem pago', bc);
    }

    final bcB = await c.purchaseBroadcast(
      liveId: liveA,
      buyer: c.buyerId!,
      liveItemId: itemLo,
      jwt: c.buyerJwt,
    );
    c.block('BN1-05', 'BN1', 'buyer purchase_broadcast sem pago', bcB);
  }

  final restSys = await c.rest('POST', 'live_messages', jwt: c.sellerJwt, body: {
    'live_id': liveA,
    'user_id': c.sellerId,
    'kind': 'system',
    'body': 'Ana claimed the jacket',
  });
  if (restSys.ok) {
    c.hold(
      id: 'P2-BN1-rest-system-claimed',
      lens: 'BN1',
      severity: 'P2',
      title: 'REST INSERT live_messages kind=system «claimed» (bypass RPC FOMO)',
      actor: 'seller JWT',
      pre: 'RLS insert chat-only esperado',
      repro: 'POST live_messages kind=system',
      expected: 'RLS rejeita kind=system',
      obtained: restSys.brief,
    );
  } else {
    c.block('BN1-06', 'BN1', 'REST system message', restSys);
  }

  final accBc = await c.rpc('batata_live_reservation_accept_broadcast', {
    'p_live_id': liveA,
    'p_buyer_id': c.buyerId,
    'p_live_item_id': itemLo,
    'p_requested_qty': 1,
  }, jwt: c.buyerJwt);
  final accMsgs = await c.msgs(liveA);
  final accPosted = accMsgs.any((m) {
    final b = '${m['body']}';
    return b.contains('Reserva aceite') && '${m['kind']}' == 'system';
  });
  if ((accBc.json == true || accBc.body.trim() == 'true') && accPosted) {
    c.hold(
      id: 'P2-BN1-accept-broadcast-buyer',
      lens: 'BN1',
      severity: 'P2',
      title: 'Buyer JWT accept_broadcast publica «Reserva aceite» sem accept real',
      actor: 'buyer JWT',
      pre: 'sem reserva accepted',
      repro: 'rpc batata_live_reservation_accept_broadcast',
      expected: 'false / not_allowed, sem system message',
      obtained: {'rpc': accBc.brief, 'posted': accPosted},
    );
  } else {
    c.block('BN1-07', 'BN1', 'accept_broadcast buyer', {
      'rpc': accBc.brief,
      'posted': accPosted,
    });
  }

  // ── BN2 FOMO synonyms + helper perms ─────────────────────────────────
  final fomoBodies = <String, String>{
    'snap-up': 'Ana just snapped up the jacket',
    'claimed': 'Item claimed by Ana',
    'grabbed': 'Ana grabbed the last one',
    'took': 'Ana took it',
    'gone': "it's gone",
    'mine': 'this one is mine now',
    'reserved-for': 'reserved for Ana',
    'braille-claimed': '\u2800 claimed by Ana',
    'fullwidth-comprou': 'Ana \uFF43\uFF4F\uFF4D\uFF50\uFF52\uFF4F\uFF55 o casaco',
    'cyrillic-o': 'Ana c\u043Emprou o casaco',
    'cyrillic-s': 'Ana \u0441omprou o casaco',
    'braille-word':
        'Ana \u2809\u2815\u280d\u280f\u2817\u2815\u2825 o casaco',
  };
  final persisted = <String, String>{};
  for (final e in fomoBodies.entries) {
    final r = await c.sysMsg(liveA, e.value);
    final listed = await c.msgs(liveA, limit: 8);
    final hit = listed.any((m) => '${m['body']}' == e.value);
    if (r.rpcOk && hit) {
      persisted[e.key] = e.value;
      c.note('BN2.fomo.${e.key}', 'persisted', r.brief, lens: 'BN2');
    } else {
      c.block('BN2-fomo-${e.key}', 'BN2', 'FOMO ${e.key}', {
        'rpc': r.brief,
        'hit': hit,
      });
    }
  }
  if (persisted.isNotEmpty) {
    c.hold(
      id: 'P2-BN2-fomo-synonyms-persist',
      lens: 'BN2',
      severity: 'P2',
      title:
          'system_message persiste anúncio de compra com sinónimos novos (snap/claimed/Braille/fullwidth/cirílico)',
      actor: 'seller JWT',
      pre:
          'filtro BFBK cobre levou/sold/ZWJ/c0mprou; variantes snap/claimed/Braille/homoglyph não listadas',
      repro: 'rpc batata_live_system_message bodies: ${persisted.keys.join(",")}',
      expected: 'purchase_announce_via_broadcast_only',
      obtained: persisted,
    );
  }

  // exact residual — do not count
  final exactLevou = await c.sysMsg(liveA, 'Ana levou o casaco');
  c.note('BN2.exact.levou', 'exact BH residual', exactLevou.brief, lens: 'BN2');

  final chatFomo = await c.sysMsg(
    liveA,
    'Item claimed by helper',
    jwt: c.helperChatJwt,
  );
  final chatFomoMsgs = await c.msgs(liveA, limit: 5);
  final chatFomoHit =
      chatFomoMsgs.any((m) => '${m['body']}' == 'Item claimed by helper');
  if (chatFomo.rpcOk && chatFomoHit) {
    c.hold(
      id: 'P2-BN2-helper-chat-claimed',
      lens: 'BN2',
      severity: 'P2',
      title: 'Helper can_manage_chat only anuncia FOMO «claimed»',
      actor: 'helper chat JWT',
      pre: 'helper active accepted, só can_manage_chat',
      repro: 'rpc batata_live_system_message claimed',
      expected: 'bloqueado purchase_announce ou not_allowed',
      obtained: chatFomo.brief,
    );
  } else {
    c.block('BN2-01', 'BN2', 'helper chat claimed', chatFomo);
  }

  if (itemLo != null) {
    final chatMark = await c.markSold(itemLo, jwt: c.helperChatJwt);
    final itemAfterChat = await c.itemRow(itemLo);
    if (chatMark.rpcOk &&
        itemAfterChat?['status']?.toString().toLowerCase() == 'sold') {
      c.hold(
        id: 'P1-BN2-helper-chat-mark-sold',
        lens: 'BN2',
        severity: 'P1',
        title: 'Helper can_manage_chat only executa mark_sold',
        actor: 'helper chat JWT',
        pre: 'perms sem can_mark_items_sold',
        repro: 'rpc batata_mark_live_item_sold',
        expected: 'not_allowed',
        obtained: {'rpc': chatMark.brief, 'status': itemAfterChat?['status']},
      );
    } else {
      c.block('BN2-02', 'BN2', 'helper chat mark_sold', chatMark);
    }

    final viewMark = await c.markSold(itemLo, jwt: c.helperViewJwt);
    c.block('BN2-03', 'BN2', 'helper view mark_sold', viewMark);

    final markMsg = await c.sysMsg(
      liveA,
      'Helper snapped this up',
      jwt: c.helperMarkJwt,
    );
    final markMsgHit = (await c.msgs(liveA, limit: 5))
        .any((m) => '${m['body']}' == 'Helper snapped this up');
    if (markMsg.rpcOk && markMsgHit) {
      c.hold(
        id: 'P2-BN2-helper-mark-sysmsg',
        lens: 'BN2',
        severity: 'P2',
        title: 'Helper mark_sold-only envia system_message FOMO',
        actor: 'helper mark JWT',
        pre: 'perms só can_mark_items_sold',
        repro: 'rpc batata_live_system_message',
        expected: 'not_allowed (falta can_manage_chat)',
        obtained: markMsg.brief,
      );
    } else {
      c.block('BN2-04', 'BN2', 'helper mark sysmsg', markMsg);
    }
  }

  if (c.createdHelperIds.isNotEmpty) {
    final hid = c.createdHelperIds.first;
    final esc = await c.rest(
      'PATCH',
      'seller_helpers?id=eq.$hid',
      jwt: c.helperChatJwt,
      body: {
        'permissions': {
          'can_mark_items_sold': true,
          'can_manage_reservations': true,
          'can_manage_chat': true,
        },
        'active': true,
      },
    );
    final row = await c.rest(
      'GET',
      'seller_helpers?id=eq.$hid&select=permissions,active',
      service: true,
    );
    final perms = row.map?['permissions'];
    final gotMark = perms is Map && perms['can_mark_items_sold'] == true;
    if (esc.ok && gotMark) {
      c.hold(
        id: 'P1-BN2-helper-self-escalate',
        lens: 'BN2',
        severity: 'P1',
        title: 'Helper PATCH permissions self-escalate can_mark_items_sold',
        actor: 'helper chat JWT',
        pre: 'helper só can_manage_chat',
        repro: 'PATCH seller_helpers permissions',
        expected: 'RLS bloqueia UPDATE de permissions pelo helper',
        obtained: {'patch': esc.brief, 'perms': perms},
      );
    } else {
      c.block('BN2-05', 'BN2', 'helper self-escalate', {
        'patch': esc.brief,
        'perms': perms,
      });
    }
  }

  // ── BN4 hitch / mark_sold ────────────────────────────────────────────
  if (itemHitch != null && skuExtra != null) {
    final before = await c.productRow(skuExtra);
    final ms = await c.markSold(itemHitch, jwt: c.sellerJwt);
    final after = await c.productRow(skuExtra);
    final itemSt = await c.itemRow(itemHitch);
    final unlisted = after?['list_on_marketplace'] == false ||
        after?['is_sold'] == true;
    if (unlisted && before?['list_on_marketplace'] == true) {
      c.hold(
        id: 'P1-BN4-hitch-own-unlist-sem-pi',
        lens: 'BN4',
        severity: 'P1',
        title: 'mark_sold live_only hitch SKU extra próprio deslista sem PI',
        actor: 'seller JWT',
        pre: 'live_only checkout_product_id=SKU extra, sem order paga',
        repro: 'rpc batata_mark_live_item_sold',
        expected: 'item pode sold; SKU extra permanece listado sem PI',
        obtained: {
          'rpc': ms.brief,
          'item': itemSt?['status'],
          'sku_listed': after?['list_on_marketplace'],
          'sku_sold': after?['is_sold'],
        },
      );
    } else {
      c.block('BN4-01', 'BN4', 'hitch own mark_sold unlist', {
        'rpc': ms.brief,
        'item': itemSt?['status'],
        'sku': after,
      });
    }
  }

  if (itemLo != null && skuS2 != null) {
    final hitchAlien = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemLo',
      jwt: c.sellerJwt,
      body: {'checkout_product_id': skuS2},
    );
    if (hitchAlien.ok) {
      c.hold(
        id: 'P1-BN4-hitch-alien-sku',
        lens: 'BN4',
        severity: 'P1',
        title: 'Seller PATCH checkout_product_id para SKU do seller2',
        actor: 'seller JWT',
        pre: 'skuS2.seller_id = S2',
        repro: 'PATCH live_items checkout_product_id',
        expected: 'live_item_checkout_product_seller_mismatch',
        obtained: hitchAlien.brief,
      );
    } else {
      c.block('BN4-02', 'BN4', 'hitch alien sku', hitchAlien);
    }
  }

  if (itemMkt != null) {
    final bMark = await c.markSold(itemMkt, jwt: c.buyerJwt);
    c.block('BN4-03', 'BN4', 'buyer mark_sold', bMark);
    if (c.seller2Jwt != null) {
      final s2Mark = await c.markSold(itemMkt, jwt: c.seller2Jwt);
      c.block('BN4-04', 'BN4', 'seller2 mark_sold live A', s2Mark);
    }
    final patchSold = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemMkt',
      jwt: c.sellerJwt,
      body: {'status': 'sold'},
    );
    c.block('BN4-05', 'BN4', 'PATCH status=sold', patchSold);
  }

  // ── BN5 live_id / qty ────────────────────────────────────────────────
  if (itemLo != null && liveB != null) {
    final move = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemLo',
      jwt: c.sellerJwt,
      body: {'live_id': liveB},
    );
    final afterMove = await c.itemRow(itemLo);
    if (move.ok && afterMove?['live_id']?.toString() == liveB) {
      c.hold(
        id: 'P1-BN5-move-item-cross-seller',
        lens: 'BN5',
        severity: 'P1',
        title: 'Seller move live_item para live do seller2',
        actor: 'seller JWT',
        pre: 'item na live A; live B é S2',
        repro: 'PATCH live_items live_id',
        expected: 'bloqueado (owner mismatch / immutable)',
        obtained: {'patch': move.brief, 'live_id': afterMove?['live_id']},
      );
    } else {
      c.block('BN5-01', 'BN5', 'move live_id cross-seller', move);
    }

    final inflate = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemLo',
      jwt: c.sellerJwt,
      body: {'quantity': 99},
    );
    final afterInf = await c.itemRow(itemLo);
    final q = afterInf?['quantity'];
    if (inflate.ok && q is num && q >= 99) {
      c.hold(
        id: 'P1-BN5-inflate-live-only-qty',
        lens: 'BN5',
        severity: 'P1',
        title: 'Seller infla quantity live_only 1→99',
        actor: 'seller JWT',
        pre: 'live_only qty=1',
        repro: 'PATCH live_items quantity=99',
        expected: 'live_item_qty_increase_not_allowed',
        obtained: {'patch': inflate.brief, 'qty': q},
      );
    } else {
      c.block('BN5-02', 'BN5', 'inflate live_only qty', {
        'patch': inflate.brief,
        'qty': q,
      });
    }
  }

  if (itemPool1 != null) {
    final logical = itemPool1;
    final itemPool2 = await c.insertLiveOnlyItem(
      liveId: liveA,
      qty: 1,
      ref: 'BNPOOL2',
      logicalItemId: logical,
      service: true,
    );
    if (itemPool2 != null) {
      final r1 = await c.insertReservation(
        liveId: liveA,
        liveItemId: itemPool1,
        buyer: c.buyerId,
        jwt: c.buyerJwt,
      );
      final r2 = await c.insertReservation(
        liveId: liveA,
        liveItemId: itemPool2,
        buyer: c.buyer2Id,
        jwt: c.buyer2Jwt,
      );
      final id1 = r1.firstId;
      final id2 = r2.firstId;
      if (id1 != null && id2 != null) {
        final a1 = await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$id1',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
        final a2 = await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$id2',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
        final row1 = await c.reqRow(id1);
        final row2 = await c.reqRow(id2);
        final both = row1?['status'] == 'accepted' &&
            row2?['status'] == 'accepted';
        if (both) {
          c.hold(
            id: 'P1-BN5-qty-pool-double-accept',
            lens: 'BN5',
            severity: 'P1',
            title:
                'Dois live_only no mesmo logical_item_id aceites (pool qty=1 → 2 holds)',
            actor: 'seller JWT',
            pre: 'pool_base_qty = max(quantity)=1; dois items qty=1 same logical',
            repro: 'PATCH accepted em ambos os pedidos',
            expected: '2.º accept qty_exceeds_stock',
            obtained: {
              'a1': a1.brief,
              'a2': a2.brief,
              's1': row1?['status'],
              's2': row2?['status'],
            },
          );
        } else {
          c.block('BN5-03', 'BN5', 'qty pool double accept', {
            'a1': a1.brief,
            'a2': a2.brief,
            's1': row1?['status'],
            's2': row2?['status'],
          });
        }
      }
    }
  }

  // ── BN3 stock / Hub ──────────────────────────────────────────────────
  if (itemLo != null) {
    final stAnon = await c.stock(itemLo);
    c.note('BN3.stock.anon-or-default', 'stock itemLo', stAnon.brief,
        lens: 'BN3');
    final stBuyer = await c.stock(itemLo, jwt: c.buyerJwt);
    c.note('BN3.stock.buyer', 'stock buyer', stBuyer.brief, lens: 'BN3');
    final disc = await c.rest(
      'GET',
      'hub_live_items_discovery_public?id=eq.$itemLo&select=id,status,is_active',
    );
    c.note('BN3.hub.item', 'discovery item', disc.brief, lens: 'BN3');
  }

  if (liveSched != null) {
    final fomoSched = await c.rpc(
      'batata_hub_live_fomo_snapshot',
      {'p_live_id': liveSched},
    );
    c.note('BN3.fomo.sched', 'FOMO scheduled', fomoSched.brief, lens: 'BN3');
  }

  // ── BN6 race end∥accept ──────────────────────────────────────────────
  final raceLive = await c.insertLive();
  final raceItem = raceLive == null
      ? null
      : await c.insertLiveOnlyItem(
          liveId: raceLive,
          qty: 1,
          ref: 'BNRACE',
          service: true,
        );
  if (raceLive != null && raceItem != null) {
    final rp = await c.insertReservation(
      liveId: raceLive,
      liveItemId: raceItem,
      buyer: c.buyerId,
      jwt: c.buyerJwt,
    );
    final rid = rp.firstId;
    if (rid != null) {
      final raced = await parallel([
        c.rest(
          'PATCH',
          'lives?id=eq.$raceLive',
          jwt: c.sellerJwt,
          body: {'status': 'ended', 'is_active': false},
        ),
        c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$rid',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        ),
      ]);
      final liveAfter = await c.rest(
        'GET',
        'lives?id=eq.$raceLive&select=id,status,is_active',
        service: true,
      );
      final reqAfter = await c.reqRow(rid);
      final ended = '${liveAfter.map?['status']}'.toLowerCase() == 'ended';
      final accepted = reqAfter?['status'] == 'accepted';
      c.note('BN6.race.raw', 'end||accept', {
        'end': raced[0].brief,
        'accept': raced[1].brief,
        'live': liveAfter.map,
        'req': reqAfter?['status'],
      }, lens: 'BN6');
      if (ended && accepted) {
        c.hold(
          id: 'P2-BN6-race-end-accept',
          lens: 'BN6',
          severity: 'P2',
          title: 'Race end live ∥ accept deixa reserva accepted em live ended',
          actor: 'seller JWT ×2 paralelo',
          pre: 'pending qty=1; PATCH ended ∥ PATCH accepted',
          repro: 'Future.wait PATCH lives ended + PATCH reservation accepted',
          expected: 'accept falha live_ended OU live ainda broadcasting',
          obtained: {
            'ended': ended,
            'accepted': accepted,
            'live': liveAfter.map,
            'req': reqAfter,
          },
        );
      } else {
        c.block('BN6-01', 'BN6', 'race end||accept', {
          'ended': ended,
          'accepted': accepted,
        });
      }
    }

    // two parallel accepts qty=1
    final raceLive2 = await c.insertLive();
    final raceItem2 = raceLive2 == null
        ? null
        : await c.insertLiveOnlyItem(
            liveId: raceLive2,
            qty: 1,
            ref: 'BNRACE2',
            service: true,
          );
    if (raceLive2 != null && raceItem2 != null) {
      final pA = await c.insertReservation(
        liveId: raceLive2,
        liveItemId: raceItem2,
        buyer: c.buyerId,
        jwt: c.buyerJwt,
      );
      final pB = await c.insertReservation(
        liveId: raceLive2,
        liveItemId: raceItem2,
        buyer: c.buyer2Id,
        jwt: c.buyer2Jwt,
      );
      final ia = pA.firstId;
      final ib = pB.firstId;
      if (ia != null && ib != null) {
        final dual = await parallel([
          c.rest(
            'PATCH',
            'live_reservation_requests?id=eq.$ia',
            jwt: c.sellerJwt,
            body: {'status': 'accepted'},
          ),
          c.rest(
            'PATCH',
            'live_reservation_requests?id=eq.$ib',
            jwt: c.sellerJwt,
            body: {'status': 'accepted'},
          ),
        ]);
        final ra = await c.reqRow(ia);
        final rb = await c.reqRow(ib);
        final nAcc = [
          ra?['status'],
          rb?['status'],
        ].where((s) => s == 'accepted').length;
        if (nAcc >= 2) {
          c.hold(
            id: 'P1-BN6-double-accept-qty1',
            lens: 'BN6',
            severity: 'P1',
            title: 'Race dois accept em live_only qty=1 → 2 accepted',
            actor: 'seller JWT paralelo',
            pre: 'dois pending, qty=1',
            repro: 'Future.wait PATCH accepted ×2',
            expected: '1 accepted, 1 qty_exceeds_stock',
            obtained: {
              'a': dual[0].brief,
              'b': dual[1].brief,
              'sa': ra?['status'],
              'sb': rb?['status'],
            },
          );
        } else {
          c.block('BN6-02', 'BN6', 'double accept qty1', {
            'nAcc': nAcc,
            'sa': ra?['status'],
            'sb': rb?['status'],
          });
        }
      }
    }
  }

  // ── BN7 Mux cruzado ──────────────────────────────────────────────────
  final muxBuyer = await c.edge('complete-mux-live', {'live_id': liveA},
      jwt: c.buyerJwt);
  if (muxBuyer.ok) {
    c.hold(
      id: 'P1-BN7-buyer-complete-mux',
      lens: 'BN7',
      severity: 'P1',
      title: 'Buyer complete-mux-live na live do vendedor',
      actor: 'buyer JWT',
      pre: 'live A do seller, mux_live_id dummy',
      repro: 'POST functions/v1/complete-mux-live',
      expected: '403 Sem permissão',
      obtained: muxBuyer.brief,
    );
  } else {
    c.block('BN7-01', 'BN7', 'buyer complete-mux', muxBuyer);
  }

  if (c.seller2Jwt != null) {
    final muxS2 = await c.edge('complete-mux-live', {'live_id': liveA},
        jwt: c.seller2Jwt);
    if (muxS2.ok) {
      c.hold(
        id: 'P1-BN7-s2-complete-mux',
        lens: 'BN7',
        severity: 'P1',
        title: 'Seller2 complete-mux-live na live A',
        actor: 'seller2 JWT',
        pre: 'owner ≠ S2',
        repro: 'POST complete-mux-live live_id=A',
        expected: '403',
        obtained: muxS2.brief,
      );
    } else {
      c.block('BN7-02', 'BN7', 's2 complete-mux', muxS2);
    }

    final pubS2 = await c.edge('livekit-mux-publish', {
      'step': 'token',
      'live_id': liveA,
    }, jwt: c.seller2Jwt);
    if (pubS2.ok && (pubS2.map?['token'] != null || pubS2.map?['ok'] == true)) {
      c.hold(
        id: 'P1-BN7-s2-livekit-token',
        lens: 'BN7',
        severity: 'P1',
        title: 'Seller2 obtém LiveKit token da live A',
        actor: 'seller2 JWT',
        pre: 'owner ≠ S2',
        repro: 'POST livekit-mux-publish step=token',
        expected: '403',
        obtained: pubS2.brief,
      );
    } else {
      c.block('BN7-03', 'BN7', 's2 livekit token', pubS2);
    }
  }

  final patchKey = await c.rest(
    'PATCH',
    'lives?id=eq.$liveA',
    jwt: c.buyerJwt,
    body: {'mux_stream_key': 'stolen-key', 'mux_playback_id': 'stolen-play'},
  );
  if (patchKey.ok) {
    c.hold(
      id: 'P1-BN7-buyer-patch-mux-key',
      lens: 'BN7',
      severity: 'P1',
      title: 'Buyer PATCH mux_stream_key / playback da live alheia',
      actor: 'buyer JWT',
      pre: 'live A do seller',
      repro: 'PATCH lives mux_stream_key',
      expected: 'RLS bloqueia',
      obtained: patchKey.brief,
    );
  } else {
    c.block('BN7-04', 'BN7', 'buyer PATCH mux key', patchKey);
  }

  if (liveSched != null) {
    final resolveSched = await c.edge(
      'resolve-mux-playback',
      {'live_id': liveSched},
    );
    if (resolveSched.ok && resolveSched.map?['playback_id'] != null) {
      c.hold(
        id: 'P2-BN7-resolve-scheduled',
        lens: 'BN7',
        severity: 'P2',
        title: 'resolve-mux-playback devolve playback em live scheduled',
        actor: 'anon',
        pre: 'live status=scheduled is_active=false',
        repro: 'POST resolve-mux-playback',
        expected: '404 live_not_public',
        obtained: resolveSched.brief,
      );
    } else {
      c.block('BN7-05', 'BN7', 'resolve scheduled', resolveSched);
    }
  }

  // ── BN8 caixa / pending fantasma notes ───────────────────────────────
  if (itemMkt != null && skuA != null) {
    final fakePago = await c.insertOrder(
      productId: skuA,
      liveItemId: itemMkt,
      liveId: liveA,
      status: 'pago',
      amountPaidCents: 1200,
      pi: 'pi_rtbn_fake_$stamp',
      jwt: c.buyerJwt,
    );
    c.note('BN8.fake-pago.jwt', 'INSERT pago+PI JWT', fakePago.brief,
        lens: 'BN8');

    final fakeSvc = await c.insertOrder(
      productId: skuA,
      liveItemId: itemMkt,
      liveId: liveA,
      status: 'pago',
      amountPaidCents: 1200,
      pi: 'pi_rtbn_svc_$stamp',
      service: true,
    );
    c.note('BN8.fake-pago.svc', 'INSERT pago+PI service fixture', fakeSvc.brief,
        lens: 'BN8');

    final oid = fakeSvc.firstId ?? fakePago.firstId;
    if (oid != null) {
      final orow = await c.orderRow(oid);
      final captured = (orow?['amount_paid_cents'] is num &&
              (orow!['amount_paid_cents'] as num) > 0) ||
          (orow?['stripe_payment_intent_id']?.toString().isNotEmpty ?? false);
      c.note('BN8.order.captured', 'fixture captured?', {
        'id': oid,
        'status': orow?['status'],
        'captured': captured,
        'cents': orow?['amount_paid_cents'],
        'pi': orow?['stripe_payment_intent_id'],
      }, lens: 'BN8');

      // exact residual: reconcile aguarda without capture — do not count
      final aguarda = await c.insertOrder(
        productId: skuA,
        liveItemId: itemMkt,
        liveId: liveA,
        status: 'aguarda_confirmacao',
        jwt: c.buyerJwt,
      );
      if (aguarda.firstId != null) {
        final recAguarda =
            await c.reconcileStripe(aguarda.firstId!, jwt: c.buyerJwt);
        c.note('BN8.exact.aguarda', 'exact BH residual reconcile sem captura',
            recAguarda.brief,
            lens: 'BN8');
      }

      if (captured) {
        final ghost = await c.insertReservation(
          liveId: liveA,
          liveItemId: itemMkt,
          buyer: c.buyer2Id,
          notes: 'stripe_checkout:$oid',
          jwt: c.buyer2Jwt,
        );
        final gid = ghost.firstId;
        c.note('BN8.ghost.insert', 'B2 pending notes other order', ghost.brief,
            lens: 'BN8');
        if (gid != null) {
          final rec = await c.reconcileStripe(oid, jwt: c.sellerJwt);
          final grow = await c.reqRow(gid);
          if (grow?['status'] == 'converted') {
            c.hold(
              id: 'P1-BN8-ghost-notes-convert',
              lens: 'BN8',
              severity: 'P1',
              title:
                  'Reconcile da order B1 converte pending fantasma B2 via notes stripe_checkout',
              actor: 'seller JWT reconcile + buyer2 pending',
              pre: 'B2 pending notes contém stripe_checkout:<order B1>',
              repro: 'rpc batata_live_reconcile_stripe_order',
              expected: 'só converte pedido do buyer da order',
              obtained: {
                'rec': rec.brief,
                'ghost_status': grow?['status'],
                'ghost_buyer': grow?['buyer_id'],
                'order_buyer': orow?['buyer_id'],
              },
            );
          } else {
            c.block('BN8-01', 'BN8', 'ghost notes convert', {
              'rec': rec.brief,
              'ghost': grow?['status'],
            });
          }
        }
      } else {
        c.skip('BN8-pay', 'BN8',
            'sem order capturada (JWT/service limpos) — Stripe TEST em pass2 se P0/P1 caixa',
            fakeSvc.brief);
      }
    }
  }

  final wallets1 = await c.wallets();
  c.note('w1', 'wallets end', {'before': wallets0, 'after': wallets1},
      lens: 'BN8');

  await c.endLives();

  final open = c.findings.where((f) => f['proven'] == true).toList();
  await dumpJson('${outDir()}/pass1.json', {
    'auditor': 'REDTEAM_BLIND_BN_LIVE_POS_BFBK_v1',
    'stamp': stamp,
    'prefix': prefix,
    'lenses': c.lensesHit.toList()..sort(),
    'findings': open,
    'blocked': c.blocked,
    'notes': c.notes,
    'skipped': c.skipped,
    'created': {
      'lives': c.createdLiveIds,
      'items': c.createdItemIds,
      'products': c.createdProductIds,
      'orders': c.createdOrderIds,
      'reqs': c.createdReqIds,
    },
  });
  stdout.writeln(
      'PASS1 done findings=${open.length} blocked=${c.blocked.length}');
}
