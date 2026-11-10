// ignore_for_file: avoid_print
/// RED TEAM CEGO AV — live/staff pós-ANAS · pass1
/// dart run tool/redteam_blind_av_20260902T1608/pass1.dart
///
/// Variantes NOVAS (não repetir exactos AP-P2-01 / AP-P3-01 / AJ4-02 / AJ4-03 / AD1):
/// - broadcast com order cancelada + PI vivo
/// - order de outro live_item
/// - helper can_manage_chat only
/// - race accept após ended (micro janela)
/// - INSERT live_messages system directo + RPC system_message
/// - UPDATE pending pós-ended + reopen+accept
import 'dart:io';

import '_rtav.dart';

Future<void> main() async {
  final env = loadEnv();
  final rt = Rtav.fromEnv(env);
  await rt.loginActors();
  await rt.ensureBuyer2();
  await rt.ensureSeller2();
  await rt.ensureHelper();

  final wallets0 = await rt.wallets();
  rt.note('av.wallets0', 'wallet snapshot start', wallets0, lens: 'AV8');

  final sku = await rt.createProduct(title: '$prefix sku-a', qty: 3, price: 11);
  final skuB = await rt.createProduct(title: '$prefix sku-b', qty: 2, price: 13);
  final skuS2 = await rt.createProduct(
    seller: rt.seller2Id,
    title: '$prefix sku-s2',
    qty: 2,
    price: 15,
  );
  if (sku == null || skuB == null || skuS2 == null) {
    stderr.writeln('fixture product fail');
    await rt.dumpAll('pass1.json');
    exit(2);
  }

  final liveA = await rt.insertLive(title: '$prefix A');
  final liveB = await rt.insertLive(title: '$prefix B');
  final liveS2 = await rt.insertLive(seller: rt.seller2Id, title: '$prefix S2');
  if (liveA == null || liveB == null || liveS2 == null) {
    stderr.writeln('fixture live fail');
    await rt.dumpAll('pass1.json');
    exit(2);
  }

  final itemA = (await rt.insertItem(
    liveId: liveA,
    service: true,
    productId: sku,
    kind: 'marketplace_product',
    price: 11,
    qty: 1,
    title: '$prefix item-A',
  ))
      .firstId;
  final itemA2 = (await rt.insertItem(
    liveId: liveA,
    service: true,
    kind: 'live_only',
    price: 9,
    qty: 1,
    title: '$prefix item-A2-only',
    checkoutProductId: skuB,
  ))
      .firstId;
  final itemB = (await rt.insertItem(
    liveId: liveB,
    service: true,
    productId: skuB,
    kind: 'marketplace_product',
    price: 13,
    qty: 1,
    title: '$prefix item-B',
  ))
      .firstId;
  final itemS2 = (await rt.insertItem(
    liveId: liveS2,
    service: true,
    productId: skuS2,
    kind: 'marketplace_product',
    price: 15,
    qty: 1,
    title: '$prefix item-S2',
  ))
      .firstId;
  if (itemA == null || itemA2 == null || itemB == null || itemS2 == null) {
    stderr.writeln('fixture item fail');
    await rt.dumpAll('pass1.json');
    exit(2);
  }

  final helperChat = await rt.inviteHelper(
    helperUserId: rt.helperId!,
    status: 'accepted',
    active: true,
    perms: const {
      'can_manage_chat': true,
      'can_mark_items_sold': false,
      'can_manage_reservations': false,
      'can_view_live_dashboard': false,
      'can_change_current_item': false,
    },
  );
  rt.note('av.helper.chat', 'helper can_manage_chat only', helperChat, lens: 'AV2');

  // =========================================================================
  // AV1 — Convert bypass (variantes ≠ AD1 exact)
  // =========================================================================

  final resConv = await rt.insertRes(
    liveId: liveA,
    itemId: itemA,
    jwt: rt.buyerJwt,
    qty: 1,
  );
  rt.judge(
    id: 'AV1-01',
    lens: 'AV1',
    title: 'Buyer INSERT reservation converted (force pending)',
    hit: resConv,
    cracked: resConv.ok && (resConv.map?['status']?.toString() == 'converted'),
    actor: 'buyer JWT',
    pre: 'live A broadcasting',
    repro: 'INSERT live_reservation_requests status omitido (buyer)',
    expected: 'pending',
    evidence: {'status': resConv.map?['status']},
  );
  final resAId = resConv.firstId;

  if (resAId != null) {
    final acc = await rt.processRes(resAId, 'accept');
    rt.note('av1.accept', 'seller accept pending', acc, lens: 'AV1');

    final convNoPay = await rt.processRes(resAId, 'convert');
    final afterNoPay = await rt.resRow(resAId);
    rt.judge(
      id: 'AV1-02',
      lens: 'AV1',
      title: 'Convert accepted sem order paga',
      hit: convNoPay,
      cracked: afterNoPay?['status'] == 'converted',
      actor: 'seller JWT',
      pre: 'accepted sem PI',
      repro: 'rpc batata_process_live_reservation_request convert',
      expected: 'convert_requires_paid_order',
      severity: 'P1',
    );

    final cancelPi = await rt.insertPaidOrder(
      productId: sku,
      liveItemId: itemA,
      liveId: liveA,
      status: 'cancelado',
      pi: 'pi_rtav_cancel',
    );
    rt.note('av1.cancelPi', 'order cancelada + PI + cents', cancelPi, lens: 'AV1');

    final convCancel = await rt.processRes(resAId, 'convert');
    final afterCancel = await rt.resRow(resAId);
    rt.judge(
      id: 'AV1-03',
      lens: 'AV1',
      title: 'Convert com order cancelada mas PI vivo',
      hit: convCancel,
      cracked: afterCancel?['status'] == 'converted',
      actor: 'seller JWT',
      pre: 'order status=cancelado amount_paid_cents>0 PI set no mesmo item',
      repro: 'rpc convert após fixture cancelado+PI',
      expected: 'convert_requires_paid_order',
      severity: 'P1',
      evidence: {'res': afterCancel, 'order': cancelPi},
    );

    final paidOther = await rt.insertPaidOrder(
      productId: skuB,
      liveItemId: itemA2,
      liveId: liveA,
      status: 'pago',
      pi: 'pi_rtav_otheritem',
    );
    final convOtherItem = await rt.processRes(resAId, 'convert');
    final afterOther = await rt.resRow(resAId);
    rt.judge(
      id: 'AV1-04',
      lens: 'AV1',
      title: 'Convert item A com order paga do live_item A2',
      hit: convOtherItem,
      cracked: afterOther?['status'] == 'converted',
      actor: 'seller JWT',
      pre: 'pago em itemA2, reserva em itemA',
      repro: 'rpc convert',
      expected: 'convert_requires_paid_order (PI tem de ser DESTE live_item)',
      severity: 'P1',
      evidence: {'paidOther': paidOther, 'res': afterOther},
    );

    final patchConv = await rt.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$resAId',
      jwt: rt.sellerJwt,
      body: {'status': 'converted'},
    );
    final afterPatch = await rt.resRow(resAId);
    rt.judge(
      id: 'AV1-05',
      lens: 'AV1',
      title: 'PATCH status=converted sem PI deste item',
      hit: patchConv,
      cracked: afterPatch?['status'] == 'converted',
      actor: 'seller JWT',
      pre: 'accepted, só PI noutro item / cancelado',
      repro: 'PATCH live_reservation_requests status=converted',
      expected: 'convert_requires_paid_order / status intacto',
      severity: 'P1',
      evidence: {'res': afterPatch},
    );
  }

  final insConvSeller = await rt.insertRes(
    liveId: liveA,
    itemId: itemA2,
    jwt: rt.sellerJwt,
    status: 'converted',
    qty: 1,
  );
  rt.judge(
    id: 'AV1-06',
    lens: 'AV1',
    title: 'Seller INSERT reservation já converted',
    hit: insConvSeller,
    cracked: insConvSeller.ok &&
        insConvSeller.map?['status']?.toString() == 'converted',
    actor: 'seller JWT',
    pre: 'live A',
    repro: 'INSERT live_reservation_requests status=converted',
    expected: 'convert_requires_paid_order ou force pending',
    severity: 'P1',
  );

  // =========================================================================
  // AV1/AV2 — purchase broadcast variantes novas
  // =========================================================================

  final bcCancel = await rt.purchaseBc(
    liveId: liveA,
    buyer: rt.buyerId!,
    itemId: itemA,
    jwt: rt.sellerJwt,
  );
  final nCancel = await rt.countSystemMsgs(liveA, contains: 'comprou');
  rt.judge(
    id: 'AV1-07',
    lens: 'AV1',
    title: 'Broadcast com order cancelada + PI (seller JWT)',
    hit: bcCancel,
    cracked: bcCancel.ok && '${bcCancel.body}' == 'true',
    actor: 'seller JWT',
    pre: 'único PI no itemA está cancelado',
    repro: 'rpc batata_live_purchase_broadcast',
    expected: 'false, sem mensagem system',
    severity: 'P2',
    evidence: {'msgs': nCancel, 'body': bcCancel.body},
  );

  final itemNoPay = (await rt.insertItem(
    liveId: liveA,
    service: true,
    kind: 'live_only',
    qty: 1,
    price: 9,
    title: '$prefix item-nopay',
  ))
      .firstId;
  if (itemNoPay != null) {
    final bcNoPayItem = await rt.purchaseBc(
      liveId: liveA,
      buyer: rt.buyerId!,
      itemId: itemNoPay,
      jwt: rt.sellerJwt,
    );
    rt.judge(
      id: 'AV1-08',
      lens: 'AV1',
      title: 'Broadcast noutro live_item sem order paga desse item',
      hit: bcNoPayItem,
      cracked: '${bcNoPayItem.body}' == 'true',
      actor: 'seller JWT',
      pre: 'pago existe noutros items da mesma live; este item sem PI',
      repro: 'rpc broadcast p_live_item_id=item sem order',
      expected: 'false',
      severity: 'P2',
    );
  }

  final bcCrossLive = await rt.purchaseBc(
    liveId: liveB,
    buyer: rt.buyerId!,
    itemId: itemA2,
    jwt: rt.sellerJwt,
  );
  rt.judge(
    id: 'AV1-09',
    lens: 'AV1',
    title: 'Broadcast live B com item/order da live A',
    hit: bcCrossLive,
    cracked: bcCrossLive.ok && '${bcCrossLive.body}' == 'true',
    actor: 'seller JWT',
    pre: 'pago em live A item A2; p_live_id = live B',
    repro: 'rpc broadcast live_id mismatch',
    expected: 'false (live_id is not distinct from p_live_id)',
    severity: 'P2',
  );

  final bcBuyerSpoof = await rt.purchaseBc(
    liveId: liveA,
    buyer: rt.buyer2Id!,
    itemId: itemA2,
    jwt: rt.buyerJwt,
  );
  rt.judge(
    id: 'AV1-10',
    lens: 'AV1',
    title: 'Buyer1 broadcast a anunciar compra do buyer2',
    hit: bcBuyerSpoof,
    cracked: bcBuyerSpoof.ok && '${bcBuyerSpoof.body}' == 'true',
    actor: 'buyer JWT',
    pre: 'p_buyer_id = B2, JWT = B1, sem order B2',
    repro: 'rpc broadcast p_buyer_id alheio',
    expected: 'false (uid ≠ p_buyer_id e ≠ seller)',
    severity: 'P2',
  );

  // =========================================================================
  // AV2 — Staff / helper can_manage_chat only
  // =========================================================================

  final statusBeforeH = (await rt.itemRow(itemA))?['status'];
  final hMark = await rt.markSold(itemA, jwt: rt.helperJwt);
  final statusAfterH = (await rt.itemRow(itemA))?['status'];
  rt.judge(
    id: 'AV2-01',
    lens: 'AV2',
    title: 'Helper can_manage_chat only executa mark_sold',
    hit: hMark,
    cracked: statusAfterH == 'sold' && statusBeforeH != 'sold',
    actor: 'helper JWT can_manage_chat',
    pre: 'perms só can_manage_chat',
    repro: 'rpc batata_mark_live_item_sold',
    expected: 'not_allowed',
    severity: 'P1',
  );

  if (resAId != null) {
    final hAcc = await rt.processRes(resAId, 'accept', jwt: rt.helperJwt);
    rt.judge(
      id: 'AV2-02',
      lens: 'AV2',
      title: 'Helper can_manage_chat accept reserva',
      hit: hAcc,
      cracked: hAcc.ok && '${hAcc.body}'.contains('"ok":true'),
      actor: 'helper JWT can_manage_chat',
      pre: 'sem can_manage_reservations',
      repro: 'rpc process accept',
      expected: 'not_allowed',
      severity: 'P1',
    );
    final hConv = await rt.processRes(resAId, 'convert', jwt: rt.helperJwt);
    rt.judge(
      id: 'AV2-03',
      lens: 'AV2',
      title: 'Helper can_manage_chat convert',
      hit: hConv,
      cracked: hConv.ok && '${hConv.body}'.contains('"ok":true'),
      actor: 'helper JWT can_manage_chat',
      pre: 'sem can_manage_reservations',
      repro: 'rpc process convert',
      expected: 'not_allowed',
      severity: 'P1',
    );
  }

  final hBcNoPay = await rt.purchaseBc(
    liveId: liveA,
    buyer: rt.buyerId!,
    itemId: itemA,
    jwt: rt.helperJwt,
  );
  rt.judge(
    id: 'AV2-04',
    lens: 'AV2',
    title: 'Helper can_manage_chat broadcast sem order paga do item',
    hit: hBcNoPay,
    cracked: hBcNoPay.ok && '${hBcNoPay.body}' == 'true',
    actor: 'helper JWT can_manage_chat',
    pre: 'itemA só tem order cancelada',
    repro: 'rpc purchase_broadcast',
    expected: 'false',
    severity: 'P2',
  );

  final fakeBody =
      '✅ Comprador-RTAV comprou ${prefix} item-A';
  final hSys = await rt.systemMsg(liveA, fakeBody,
      jwt: rt.helperJwt, label: 'Comprador-RTAV');
  final nAfterH = await rt.countSystemMsgs(liveA, contains: 'Comprador-RTAV');
  rt.judge(
    id: 'AV2-05',
    lens: 'AV2',
    title: 'Helper can_manage_chat posta prova social falsa via system_message',
    hit: hSys,
    cracked: hSys.ok && '${hSys.body}'.contains('"ok":true') && nAfterH > 0,
    actor: 'helper JWT can_manage_chat',
    pre: 'sem PI pago no item anunciado',
    repro: 'rpc batata_live_system_message body "✅ … comprou"',
    expected: 'ok (chat perm) — prova social sem pagamento; classificar P2 se indistinguível',
    severity: 'P2',
    evidence: {'n': nAfterH, 'body': hSys.body},
  );

  final bSys = await rt.systemMsg(
    liveA,
    '✅ Buyer fantasma comprou artigo AV',
    jwt: rt.buyerJwt,
    label: 'Sistema',
  );
  rt.judge(
    id: 'AV2-06',
    lens: 'AV2',
    title: 'Buyer RPC system_message prova social falsa',
    hit: bSys,
    cracked: bSys.ok && '${bSys.body}'.contains('"ok":true'),
    actor: 'buyer JWT',
    pre: 'não é seller/staff',
    repro: 'rpc batata_live_system_message',
    expected: 'not_allowed',
    severity: 'P2',
  );

  final s2Sys = await rt.systemMsg(
    liveA,
    '✅ Seller2 comprou artigo AV',
    jwt: rt.seller2Jwt,
  );
  rt.judge(
    id: 'AV2-07',
    lens: 'AV2',
    title: 'Seller2 system_message na live A',
    hit: s2Sys,
    cracked: s2Sys.ok && '${s2Sys.body}'.contains('"ok":true'),
    actor: 'seller2 JWT',
    pre: 'live A do seller 1',
    repro: 'rpc batata_live_system_message',
    expected: 'not_allowed',
    severity: 'P2',
  );

  final esc = await rt.rest(
    'PATCH',
    'seller_helpers?id=eq.$helperChat',
    jwt: rt.helperJwt,
    body: {
      'permissions': {
        'can_manage_chat': true,
        'can_mark_items_sold': true,
        'can_manage_reservations': true,
      },
    },
  );
  rt.judge(
    id: 'AV2-08',
    lens: 'AV2',
    title: 'Helper escalate perms via PATCH próprio seller_helpers',
    hit: esc,
    cracked: esc.ok && '${esc.body}'.contains('can_mark_items_sold'),
    actor: 'helper JWT',
    pre: 'só can_manage_chat',
    repro: 'PATCH seller_helpers permissions',
    expected: 'RLS 403 / sem row',
    severity: 'P1',
  );

  // =========================================================================
  // AV — INSERT live_messages system directo (≠ broadcast RPC)
  // =========================================================================

  final insSysBuyer = await rt.rest('POST', 'live_messages', jwt: rt.buyerJwt, body: {
    'live_id': liveA,
    'user_id': rt.buyerId,
    'kind': 'system',
    'body': '✅ INSERT directo comprou artigo',
    'sender_label': 'Comprador',
  });
  rt.judge(
    id: 'AV2-09',
    lens: 'AV2',
    title: 'Buyer INSERT live_messages kind=system directo',
    hit: insSysBuyer,
    cracked: insSysBuyer.ok,
    actor: 'buyer JWT',
    pre: 'RLS insert chat-only',
    repro: 'POST live_messages kind=system',
    expected: '403 RLS',
    severity: 'P2',
  );

  final insSysSeller = await rt.rest('POST', 'live_messages', jwt: rt.sellerJwt, body: {
    'live_id': liveA,
    'user_id': rt.sellerId,
    'kind': 'system',
    'body': '✅ Seller INSERT system comprou',
    'sender_label': 'Sistema',
  });
  rt.judge(
    id: 'AV2-10',
    lens: 'AV2',
    title: 'Seller INSERT live_messages kind=system directo',
    hit: insSysSeller,
    cracked: insSysSeller.ok,
    actor: 'seller JWT',
    pre: 'policy kind=chat',
    repro: 'POST live_messages kind=system',
    expected: '403 RLS (RPC only)',
    severity: 'P2',
  );

  final chatThenPatch = await rt.rest('POST', 'live_messages', jwt: rt.buyerJwt, body: {
    'live_id': liveA,
    'user_id': rt.buyerId,
    'kind': 'chat',
    'body': 'ola',
    'sender_label': 'B',
  });
  final chatId = chatThenPatch.firstId;
  if (chatId != null) {
    final upKind = await rt.rest(
      'PATCH',
      'live_messages?id=eq.$chatId',
      jwt: rt.buyerJwt,
      body: {
        'kind': 'system',
        'body': '✅ PATCH kind system comprou',
      },
    );
    rt.judge(
      id: 'AV2-11',
      lens: 'AV2',
      title: 'Buyer PATCH chat → kind=system',
      hit: upKind,
      cracked: upKind.ok,
      actor: 'buyer JWT',
      pre: 'mensagem chat própria',
      repro: 'PATCH live_messages kind=system',
      expected: 'sem policy UPDATE / 403',
      severity: 'P2',
    );
  } else {
    rt.note('av2.chat.insert', 'buyer chat insert', chatThenPatch, lens: 'AV2');
  }

  // =========================================================================
  // AV3 — Stock / Hub / REST
  // =========================================================================

  final paused = (await rt.insertItem(
    liveId: liveA,
    service: true,
    kind: 'live_only',
    qty: 2,
    price: 8,
    status: 'paused',
    active: true,
    title: '$prefix paused',
  ))
      .firstId;
  final soldish = (await rt.insertItem(
    liveId: liveA,
    service: true,
    kind: 'live_only',
    qty: 0,
    price: 8,
    status: 'sold',
    active: true,
    title: '$prefix soldish',
  ))
      .firstId;

  if (paused != null) {
    final hubP = await rt.hubDiscoveryItem(paused);
    final restP = await rt.rest(
      'GET',
      'live_items?id=eq.$paused&select=id,status,quantity',
      jwt: rt.buyerJwt,
    );
    final anonP = await rt.stockRpc(paused, anon: true);
    final vis = hubP != null || restP.ok && restP.list.isNotEmpty;
    rt.judge(
      id: 'AV3-01',
      lens: 'AV3',
      title: 'Item paused visível em Hub/REST buyer/anon stock',
      hit: anonP,
      cracked: vis || (anonP.ok && '${anonP.body}'.contains('available_qty')),
      actor: 'anon + buyer JWT',
      pre: 'status=paused quantity=2 live broadcasting',
      repro: 'hub_live_items_discovery_public + live_items SELECT + stock RPC anon',
      expected: 'Hub vazio; REST buyer sem row (policy); anon stock not_found',
      severity: 'P2',
      evidence: {
        'hub': hubP,
        'rest': restP.brief,
        'anonStock': anonP.brief,
      },
    );
  }

  if (soldish != null) {
    final hubS = await rt.hubDiscoveryItem(soldish);
    rt.judge(
      id: 'AV3-02',
      lens: 'AV3',
      title: 'Item sold qty=0 na vitrine Hub',
      hit: HttpHit(hubS == null ? 404 : 200, '${hubS ?? ''}', hubS),
      cracked: hubS != null,
      actor: 'anon',
      pre: 'status=sold quantity=0',
      repro: 'GET hub_live_items_discovery_public',
      expected: 'sem row',
      severity: 'P2',
    );
  }

  await rt.rest('PATCH', 'lives?id=eq.$liveB', service: true, body: {
    'status': 'ended',
    'is_active': false,
  }, prefer: 'return=minimal');

  final anonEnded = await rt.stockRpc(itemB, anon: true);
  final hubEnded = await rt.hubDiscoveryItem(itemB);
  rt.judge(
    id: 'AV3-03',
    lens: 'AV3',
    title: 'Stock/Hub de live ended visível a anon',
    hit: anonEnded,
    cracked: (anonEnded.ok && '${anonEnded.body}'.contains('available_qty')) ||
        hubEnded != null,
    actor: 'anon',
    pre: 'live B ended',
    repro: 'rpc batata_live_item_stock anon + hub discovery',
    expected: 'live_item_not_found / Hub vazio',
    severity: 'P2',
    evidence: {'hub': hubEnded, 'stock': anonEnded.brief},
  );

  // pending on ended live — INSERT
  final pendEnded = await rt.insertRes(
    liveId: liveB,
    itemId: itemB,
    jwt: rt.buyerJwt,
  );
  rt.judge(
    id: 'AV3-04',
    lens: 'AV3',
    title: 'INSERT reserva pending em live ended',
    hit: pendEnded,
    cracked: pendEnded.ok,
    actor: 'buyer JWT',
    pre: 'live B ended (ANAS INSERT trigger)',
    repro: 'POST live_reservation_requests',
    expected: 'live_ended',
    severity: 'P2',
  );

  // =========================================================================
  // AV6 — UPDATE pending pós-ended + race accept + reopen
  // =========================================================================

  final raceLive = await rt.insertLive(title: '$prefix race');
  final raceItem = raceLive == null
      ? null
      : (await rt.insertItem(
          liveId: raceLive,
          service: true,
          kind: 'live_only',
          qty: 1,
          price: 7,
          title: '$prefix race-item',
        ))
          .firstId;
  String? raceResId;
  if (raceLive != null && raceItem != null) {
    final rPend = await rt.insertRes(
      liveId: raceLive,
      itemId: raceItem,
      jwt: rt.buyerJwt,
    );
    raceResId = rPend.firstId;
    rt.note('av6.pend', 'pending while live', rPend, lens: 'AV6');

    await rt.rest('PATCH', 'lives?id=eq.$raceLive', service: true, body: {
      'status': 'ended',
      'is_active': false,
    }, prefer: 'return=minimal');

    if (raceResId != null) {
      final updAcc = await rt.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$raceResId',
        jwt: rt.sellerJwt,
        body: {'status': 'accepted'},
      );
      final rowUpd = await rt.resRow(raceResId);
      rt.judge(
        id: 'AV6-01',
        lens: 'AV6',
        title: 'UPDATE pending→accepted após live ended',
        hit: updAcc,
        cracked: rowUpd?['status'] == 'accepted',
        actor: 'seller JWT',
        pre: 'pending criado em live; depois ended (INSERT já não aplica)',
        repro: 'PATCH status=accepted',
        expected: 'live_ended',
        severity: 'P1',
        evidence: {'res': rowUpd},
      );

      final rpcAcc = await rt.processRes(raceResId, 'accept');
      final rowRpc = await rt.resRow(raceResId);
      rt.judge(
        id: 'AV6-02',
        lens: 'AV6',
        title: 'RPC accept após live ended',
        hit: rpcAcc,
        cracked: rowRpc?['status'] == 'accepted',
        actor: 'seller JWT',
        pre: 'live ended, pending intacto',
        repro: 'rpc process accept',
        expected: 'live_ended',
        severity: 'P1',
        evidence: {'res': rowRpc},
      );

      // reopen + accept
      await rt.rest('PATCH', 'lives?id=eq.$raceLive', jwt: rt.sellerJwt, body: {
        'status': 'live',
        'is_active': true,
      }, prefer: 'return=minimal');
      final afterReopenAcc = await rt.processRes(raceResId, 'accept');
      final rowRe = await rt.resRow(raceResId);
      rt.judge(
        id: 'AV6-03',
        lens: 'AV6',
        title: 'Seller reabre live ended e accept pending antigo',
        hit: afterReopenAcc,
        cracked: rowRe?['status'] == 'accepted',
        actor: 'seller JWT',
        pre: 'PATCH lives status=live is_active=true depois ended',
        repro: 'reopen JWT + rpc accept',
        expected: 'produto: seller dono pode reabrir; documentar se fila fantasma revive',
        severity: 'P3',
        evidence: {'res': rowRe},
      );
    }
  }

  // Micro race: end ∥ accept
  final race2 = await rt.insertLive(title: '$prefix race2');
  final race2Item = race2 == null
      ? null
      : (await rt.insertItem(
          liveId: race2,
          service: true,
          kind: 'live_only',
          qty: 1,
          price: 7,
          title: '$prefix race2-item',
        ))
          .firstId;
  if (race2 != null && race2Item != null) {
    final p2 = await rt.insertRes(
      liveId: race2,
      itemId: race2Item,
      jwt: rt.buyerJwt,
    );
    final p2id = p2.firstId;
    if (p2id != null) {
      final results = await Future.wait([
        rt.rest('PATCH', 'lives?id=eq.$race2', jwt: rt.sellerJwt, body: {
          'status': 'ended',
          'is_active': false,
        }, prefer: 'return=minimal'),
        rt.processRes(p2id, 'accept'),
        rt.processRes(p2id, 'accept'),
      ]);
      final rowR = await rt.resRow(p2id);
      final liveR = await rt.rest(
        'GET',
        'lives?id=eq.$race2&select=id,status,is_active',
        service: true,
      );
      final acceptedOnEnded = rowR?['status'] == 'accepted' &&
          liveR.map?['status'] == 'ended' &&
          liveR.map?['is_active'] == false;
      rt.judge(
        id: 'AV6-04',
        lens: 'AV6',
        title: 'Race micro: end live ∥ accept pending',
        hit: results[1],
        cracked: acceptedOnEnded,
        actor: 'seller JWT parallel',
        pre: 'pending qty=1',
        repro: 'Future.wait PATCH ended + 2x process accept',
        expected: 'ou live_ended, ou accepted só se live ainda broadcasting',
        severity: 'P1',
        evidence: {'res': rowR, 'live': liveR.map, 'end': results[0].brief},
      );
    }

    // qty=1 two buyers race accept
    final liveCap = await rt.insertLive(title: '$prefix cap');
    if (liveCap != null) {
      final capItem = (await rt.insertItem(
        liveId: liveCap,
        service: true,
        kind: 'live_only',
        qty: 1,
        price: 6,
        title: '$prefix cap-item',
      ))
          .firstId;
      if (capItem != null) {
        final r1 = await rt.insertRes(
          liveId: liveCap,
          itemId: capItem,
          jwt: rt.buyerJwt,
        );
        final r2 = await rt.insertRes(
          liveId: liveCap,
          itemId: capItem,
          jwt: rt.buyer2Jwt,
          buyer: rt.buyer2Id,
        );
        if (r1.firstId != null && r2.firstId != null) {
          final raceAcc = await Future.wait([
            rt.processRes(r1.firstId!, 'accept'),
            rt.processRes(r2.firstId!, 'accept'),
          ]);
          final s1 = await rt.resRow(r1.firstId!);
          final s2 = await rt.resRow(r2.firstId!);
          final both = s1?['status'] == 'accepted' && s2?['status'] == 'accepted';
          rt.judge(
            id: 'AV6-05',
            lens: 'AV6',
            title: 'Stock=1 duas accepts paralelas',
            hit: raceAcc[0],
            cracked: both,
            actor: 'seller JWT',
            pre: 'qty=1 two pending B1+B2',
            repro: 'Future.wait 2x process accept',
            expected: 'só 1 accepted',
            severity: 'P1',
            evidence: {'b1': s1?['status'], 'b2': s2?['status']},
          );
        }
      }
    }
  }

  // =========================================================================
  // AV4 — mark_sold / hitch (≠ AJ4-02 foreign exact / AJ4-03 INSERT sold)
  // =========================================================================

  final skuHitch = await rt.createProduct(
    title: '$prefix sku-hitch',
    qty: 2,
    listed: true,
    price: 10,
  );
  final itemHitch = (await rt.insertItem(
    liveId: liveA,
    service: true,
    kind: 'live_only',
    qty: 1,
    price: 10,
    title: '$prefix hitch-nopi',
    checkoutProductId: skuHitch,
  ))
      .firstId;
  if (itemHitch != null && skuHitch != null) {
    final beforeHitch = await rt.productRow(skuHitch);
    final msNoPi = await rt.markSold(itemHitch);
    final afterHitch = await rt.productRow(skuHitch);
    final unlistedWithoutPi = afterHitch?['is_sold'] == true ||
        afterHitch?['list_on_marketplace'] == false;
    rt.judge(
      id: 'AV4-01',
      lens: 'AV4',
      title: 'mark_sold live_only hitch SKU próprio sem PI deslista catálogo',
      hit: msNoPi,
      cracked: unlistedWithoutPi,
      actor: 'seller JWT',
      pre: 'live_only checkout_product próprio, zero orders pagas neste item',
      repro: 'mark_sold sem PI',
      expected: 'SKU continua listado (AHAM)',
      severity: 'P1',
      evidence: {
        'before': beforeHitch,
        'after': afterHitch,
        'ms': msNoPi.brief,
      },
    );
  }

  final hitchS2 = await rt.rest(
    'PATCH',
    'live_items?id=eq.$itemA2',
    jwt: rt.sellerJwt,
    body: {'checkout_product_id': skuS2},
  );
  rt.judge(
    id: 'AV4-02',
    lens: 'AV4',
    title: 'Hitch checkout_product de seller2 no item da live A',
    hit: hitchS2,
    cracked: hitchS2.ok,
    actor: 'seller JWT',
    pre: 'skuS2 seller2',
    repro: 'PATCH live_items.checkout_product_id = sku alheio',
    expected: 'live_item_checkout_product_seller_mismatch',
    severity: 'P1',
  );

  final stA0 = (await rt.itemRow(itemA))?['status'];
  final buyerMs = await rt.markSold(itemA, jwt: rt.buyerJwt);
  final stA1 = (await rt.itemRow(itemA))?['status'];
  rt.judge(
    id: 'AV4-03',
    lens: 'AV4',
    title: 'Buyer mark_sold',
    hit: buyerMs,
    cracked: stA1 == 'sold' && stA0 != 'sold',
    actor: 'buyer JWT',
    pre: 'item marketplace live A',
    repro: 'rpc mark_sold',
    expected: 'not_allowed',
    severity: 'P1',
  );

  final stA2 = (await rt.itemRow(itemA))?['status'];
  final s2Ms = await rt.markSold(itemA, jwt: rt.seller2Jwt);
  final stA3 = (await rt.itemRow(itemA))?['status'];
  rt.judge(
    id: 'AV4-04',
    lens: 'AV4',
    title: 'Seller2 mark_sold na live A',
    hit: s2Ms,
    cracked: stA3 == 'sold' && stA2 != 'sold',
    actor: 'seller2 JWT',
    pre: 'live A alheia',
    repro: 'rpc mark_sold',
    expected: 'not_allowed',
    severity: 'P1',
  );

  final insSold = await rt.insertItem(
    liveId: liveA,
    jwt: rt.sellerJwt,
    kind: 'live_only',
    qty: 1,
    status: 'sold',
    title: '$prefix insert-sold',
  );
  rt.judge(
    id: 'AV4-05',
    lens: 'AV4',
    title: 'INSERT live_item já status=sold (JWT seller)',
    hit: insSold,
    cracked: insSold.ok && insSold.map?['status'] == 'sold',
    actor: 'seller JWT',
    pre: 'AHAM sold rpc-only',
    repro: 'POST live_items status=sold',
    expected: 'live_item_status_sold_rpc_only',
    severity: 'P2',
  );

  // =========================================================================
  // AV5 — live_id / qty / cross-seller
  // =========================================================================

  final qtyUp = await rt.rest(
    'PATCH',
    'live_items?id=eq.$itemA2',
    jwt: rt.sellerJwt,
    body: {'quantity': 99},
  );
  rt.judge(
    id: 'AV5-01',
    lens: 'AV5',
    title: 'Seller infla quantity live_only',
    hit: qtyUp,
    cracked: qtyUp.ok && ((await rt.itemRow(itemA2))?['quantity'] == 99),
    actor: 'seller JWT',
    pre: 'live_only qty=1',
    repro: 'PATCH live_items.quantity=99',
    expected: 'live_item_qty_increase_not_allowed',
    severity: 'P1',
  );

  final moveLive = await rt.rest(
    'PATCH',
    'live_items?id=eq.$itemA',
    jwt: rt.sellerJwt,
    body: {'live_id': liveS2},
  );
  rt.judge(
    id: 'AV5-02',
    lens: 'AV5',
    title: 'Mover live_item com reservas para live de seller2',
    hit: moveLive,
    cracked: moveLive.ok && (await rt.itemRow(itemA))?['live_id'] == liveS2,
    actor: 'seller JWT',
    pre: 'itemA tem reservas',
    repro: 'PATCH live_items.live_id',
    expected: 'live_item_live_id_immutable / not_authorized',
    severity: 'P1',
  );

  final hitchProd = await rt.rest(
    'PATCH',
    'live_items?id=eq.$itemA2',
    jwt: rt.sellerJwt,
    body: {'product_id': skuS2},
  );
  rt.judge(
    id: 'AV5-03',
    lens: 'AV5',
    title: 'Hitch product_id de seller2',
    hit: hitchProd,
    cracked: hitchProd.ok,
    actor: 'seller JWT',
    pre: 'skuS2 alheio',
    repro: 'PATCH live_items.product_id',
    expected: 'live_item_product_seller_mismatch',
    severity: 'P1',
  );

  final resMismatch = await rt.rest(
    'POST',
    'live_reservation_requests',
    jwt: rt.buyerJwt,
    body: {
      'live_id': liveA,
      'live_item_id': itemS2,
      'buyer_id': rt.buyerId,
      'seller_id': rt.sellerId,
      'status': 'pending',
      'source': 'fleaber_live',
      'requested_qty': 1,
    },
  );
  rt.judge(
    id: 'AV5-04',
    lens: 'AV5',
    title: 'Reserva live A apontando a item da live S2',
    hit: resMismatch,
    cracked: resMismatch.ok,
    actor: 'buyer JWT',
    pre: 'live_id ≠ item.live_id',
    repro: 'INSERT reservation live_id mismatch',
    expected: 'live_item_live_mismatch',
    severity: 'P2',
  );

  // =========================================================================
  // AV7 — Sabotar live alheia / Mux
  // =========================================================================

  final completeB = await rt.edge('complete-mux-live', {'live_id': liveA},
      jwt: rt.buyerJwt);
  rt.judge(
    id: 'AV7-01',
    lens: 'AV7',
    title: 'Buyer complete-mux-live na live do seller',
    hit: completeB,
    cracked: completeB.ok || completeB.status == 502,
    actor: 'buyer JWT',
    pre: 'live A sem mux real (não matar stream prod)',
    repro: 'POST functions/v1/complete-mux-live',
    expected: '403 Sem permissão',
    severity: 'P1',
  );

  final completeS2 = await rt.edge('complete-mux-live', {'live_id': liveA},
      jwt: rt.seller2Jwt);
  rt.judge(
    id: 'AV7-02',
    lens: 'AV7',
    title: 'Seller2 complete-mux-live na live A',
    hit: completeS2,
    cracked: completeS2.ok || completeS2.status == 502,
    actor: 'seller2 JWT',
    pre: 'live A alheia',
    repro: 'POST complete-mux-live',
    expected: '403',
    severity: 'P1',
  );

  final muxBuyer = await rt.edge('create-mux-live', {'title': '$prefix mux'},
      jwt: rt.buyerJwt);
  rt.judge(
    id: 'AV7-03',
    lens: 'AV7',
    title: 'Buyer create-mux-live (custo Mux)',
    hit: muxBuyer,
    cracked: muxBuyer.ok,
    actor: 'buyer JWT',
    pre: 'user_type comprador',
    repro: 'POST create-mux-live',
    expected: '403 só vendedor',
    severity: 'P2',
  );

  final lkS2 = await rt.edge('livekit-mux-publish', {
    'step': 'token',
    'live_id': liveA,
  }, jwt: rt.seller2Jwt);
  rt.judge(
    id: 'AV7-04',
    lens: 'AV7',
    title: 'Seller2 pede token LiveKit da live A',
    hit: lkS2,
    cracked: lkS2.ok,
    actor: 'seller2 JWT',
    pre: 'live A alheia',
    repro: 'POST livekit-mux-publish step=token',
    expected: '403',
    severity: 'P1',
  );

  final patchEnd = await rt.rest(
    'PATCH',
    'lives?id=eq.$liveA',
    jwt: rt.buyerJwt,
    body: {'status': 'ended', 'is_active': false},
  );
  rt.judge(
    id: 'AV7-05',
    lens: 'AV7',
    title: 'Buyer PATCH lives ended (sabotar directo)',
    hit: patchEnd,
    cracked: patchEnd.ok,
    actor: 'buyer JWT',
    pre: 'lives_update_own',
    repro: 'PATCH lives status=ended',
    expected: '0 rows / 403',
    severity: 'P1',
  );

  final stealKey = await rt.rest(
    'GET',
    'lives?id=eq.$liveA&select=id,mux_stream_key,stream_key,mux_live_id',
    jwt: rt.buyerJwt,
  );
  final keyLeak = stealKey.ok &&
      stealKey.list.isNotEmpty &&
      (stealKey.map?['mux_stream_key'] != null ||
          stealKey.map?['stream_key'] != null);
  rt.judge(
    id: 'AV7-06',
    lens: 'AV7',
    title: 'Buyer lê mux_stream_key / stream_key',
    hit: stealKey,
    cracked: keyLeak,
    actor: 'buyer JWT',
    pre: 'REVOKE select stream keys',
    repro: 'GET lives select mux_stream_key',
    expected: 'permission denied / colunas ausentes',
    severity: 'P1',
  );

  final stealOwner = await rt.rest(
    'PATCH',
    'lives?id=eq.$liveA',
    jwt: rt.seller2Jwt,
    body: {'seller_id': rt.seller2Id, 'vendedor_id': rt.seller2Id},
  );
  rt.judge(
    id: 'AV7-07',
    lens: 'AV7',
    title: 'Seller2 toma ownership da live A',
    hit: stealOwner,
    cracked: stealOwner.ok,
    actor: 'seller2 JWT',
    pre: 'update own only',
    repro: 'PATCH lives seller_id',
    expected: '0 rows',
    severity: 'P1',
  );

  // =========================================================================
  // AV8 — Caixa / order fantasma
  // =========================================================================

  final ghost = await rt.insertOpenOrder(
    productId: sku,
    jwt: rt.buyerJwt,
    liveItemId: itemA,
    liveId: liveA,
    status: 'pago',
    price: 11,
  );
  Map<String, dynamic>? ghostRow;
  if (ghost != null) {
    ghostRow = await rt.orderRow(ghost);
  }
  rt.judge(
    id: 'AV8-01',
    lens: 'AV8',
    title: 'Buyer INSERT order já status=pago (fantasma)',
    hit: HttpHit(ghost == null ? 403 : 201, '$ghostRow', ghostRow),
    cracked: ghostRow?['status'] == 'pago',
    actor: 'buyer JWT',
    pre: 'guard paid status INSERT',
    repro: 'POST orders status=pago',
    expected: 'reserva_pendente (não pago)',
    severity: 'P1',
    evidence: {'order': ghostRow},
  );

  final payPatch = ghost == null
      ? HttpHit(0, 'no ghost', null)
      : await rt.rest(
          'PATCH',
          'orders?id=eq.$ghost',
          jwt: rt.buyerJwt,
          body: {
            'status': 'pago',
            'amount_paid_cents': 1100,
            'stripe_payment_intent_id': 'pi_rtav_forged',
          },
        );
  final ghostAfter = ghost == null ? null : await rt.orderRow(ghost);
  rt.judge(
    id: 'AV8-02',
    lens: 'AV8',
    title: 'Buyer PATCH order para pago + PI forjado',
    hit: payPatch,
    cracked: ghostAfter?['status'] == 'pago' &&
        (ghostAfter?['stripe_payment_intent_id']?.toString().contains('forged') ??
            false),
    actor: 'buyer JWT',
    pre: 'order aberta própria',
    repro: 'PATCH orders status+PI+cents',
    expected: 'money cols / status bloqueados',
    severity: 'P0',
    evidence: {'order': ghostAfter},
  );

  if (ghost != null && ghostAfter?['status'] == 'pago') {
    final bcForge = await rt.purchaseBc(
      liveId: liveA,
      buyer: rt.buyerId!,
      itemId: itemA,
      jwt: rt.buyerJwt,
    );
    rt.judge(
      id: 'AV8-03',
      lens: 'AV8',
      title: 'Broadcast após order pago forjado pelo buyer',
      hit: bcForge,
      cracked: '${bcForge.body}' == 'true',
      actor: 'buyer JWT',
      pre: 'AV8-02 se cracked',
      repro: 'rpc purchase_broadcast',
      expected: 'false se PATCH foi bloqueado; true = prova social + estado pago falso',
      severity: 'P1',
    );
  } else {
    rt.block('AV8-03', 'AV8', 'broadcast forjado N/A (PATCH pago bloqueado)',
        payPatch);
  }

  final wallets1 = await rt.wallets();
  final dBuyer = (wallets1['buyer'] ?? 0) - (wallets0['buyer'] ?? 0);
  final dSeller = (wallets1['seller'] ?? 0) - (wallets0['seller'] ?? 0);
  final dB2 = (wallets1['buyer2'] ?? 0) - (wallets0['buyer2'] ?? 0);
  final dS2 = (wallets1['seller2'] ?? 0) - (wallets0['seller2'] ?? 0);
  rt.judge(
    id: 'AV8-04',
    lens: 'AV8',
    title: 'Δ wallet após probes sem Stripe TEST pago',
    hit: HttpHit(200, '$wallets1 ΔB=$dBuyer ΔS=$dSeller ΔB2=$dB2 ΔS2=$dS2', {
      'before': wallets0,
      'after': wallets1,
    }),
    cracked: dBuyer != 0 || dSeller != 0 || dB2 != 0 || dS2 != 0,
    actor: 'observe service_role',
    pre: 'nenhuma captura Stripe TEST nesta ronda',
    repro: 'wallets before/after',
    expected: 'Δ=0',
    severity: 'P0',
    evidence: {
      'dBuyer': dBuyer,
      'dSeller': dSeller,
      'dB2': dB2,
      'dS2': dS2,
    },
  );

  await rt.cleanupSoft();
  await rt.dumpAll('pass1.json');
  stdout.writeln(
    'DONE findings=${rt.findings.length} blocked=${rt.blocked.length} '
    'lenses=${rt.lensesHit.toList()..sort()}',
  );
}
