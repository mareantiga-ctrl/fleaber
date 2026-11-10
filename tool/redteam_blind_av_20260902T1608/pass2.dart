// ignore_for_file: avoid_print
/// RED TEAM CEGO AV — pass2: refutar AV2-11, provar AV2-05, fechar AV3-02 / AV6-05
import 'dart:io';

import '_rtav.dart';

bool rpcOk(HttpHit h) {
  final t = h.body.replaceAll(' ', '');
  return t.contains('"ok":true');
}

Future<void> main() async {
  final env = loadEnv();
  final rt = Rtav.fromEnv(env);
  await rt.loginActors();
  await rt.ensureBuyer2();
  await rt.ensureHelper();

  final live = await rt.insertLive(title: '$prefix p2');
  if (live == null) {
    stderr.writeln('no live');
    exit(2);
  }
  final item = (await rt.insertItem(
    liveId: live,
    service: true,
    kind: 'live_only',
    qty: 1,
    price: 8,
    title: '$prefix p2-item',
  ))
      .firstId!;

  await rt.inviteHelper(
    helperUserId: rt.helperId!,
    status: 'accepted',
    active: true,
    perms: const {
      'can_manage_chat': true,
      'can_mark_items_sold': false,
      'can_manage_reservations': false,
    },
  );

  // --- AV2-11 refutação: PATCH 200 [] não muda kind ---
  final chat = await rt.rest('POST', 'live_messages', jwt: rt.buyerJwt, body: {
    'live_id': live,
    'user_id': rt.buyerId,
    'kind': 'chat',
    'body': 'rtav-p2-chat',
    'sender_label': 'B',
  });
  final chatId = chat.firstId;
  if (chatId == null) {
    rt.skip('AV2-11b', 'AV2', 'buyer chat insert fail', chat);
  } else {
    final patch = await rt.rest(
      'PATCH',
      'live_messages?id=eq.$chatId',
      jwt: rt.buyerJwt,
      body: {'kind': 'system', 'body': '✅ PATCH p2 comprou'},
    );
    final after = await rt.rest(
      'GET',
      'live_messages?id=eq.$chatId&select=id,kind,body',
      service: true,
    );
    final kind = after.map?['kind']?.toString();
    rt.judge(
      id: 'AV2-11',
      lens: 'AV2',
      title: 'Buyer PATCH chat → kind=system (verificar row)',
      hit: patch,
      cracked: kind == 'system',
      actor: 'buyer JWT',
      pre: 'mensagem chat própria; pass1 deu 200 []',
      repro: 'PATCH live_messages kind=system + GET service',
      expected: 'kind permanece chat',
      severity: 'P2',
      evidence: {'kind': kind, 'patch': patch.brief, 'row': after.map},
    );
  }

  // --- AV2-05: helper FOMO system_message ---
  final fake = '✅ RTAV-P2-FOMO comprou $prefix p2-item';
  final hSys = await rt.systemMsg(live, fake, jwt: rt.helperJwt, label: 'FOMO');
  final msgs = await rt.rest(
    'GET',
    'live_messages?live_id=eq.$live&kind=eq.system&body=ilike.*RTAV-P2-FOMO*&select=id,kind,body,user_id,sender_label',
    service: true,
  );
  final posted = msgs.list.any((e) =>
      e is Map && '${e['body']}'.contains('RTAV-P2-FOMO') && e['kind'] == 'system');
  rt.hold(
    id: 'AV2-05',
    lens: 'AV2',
    severity: 'P3',
    title: 'Helper can_manage_chat publica system "✅ comprou" sem order paga',
    actor: 'helper JWT can_manage_chat',
    pre: 'sem can_mark_items_sold / can_manage_reservations; zero PI neste item',
    repro: 'rpc batata_live_system_message',
    expected:
        'RPC permite staff chat (desenho). purchase_broadcast continua a exigir pago. Classificar P3 FOMO autorizado, não bypass de dinheiro.',
    obtained: {
      'rpc': hSys.brief,
      'rpcOk': rpcOk(hSys),
      'rowPosted': posted,
      'msgs': msgs.list,
    },
    proven: rpcOk(hSys) && posted,
  );

  final sellerFomo = await rt.systemMsg(
    live,
    '✅ RTAV-P2-SELLER comprou sem PI',
    jwt: rt.sellerJwt,
  );
  rt.note('av2.seller.fomo', 'seller system_message FOMO', sellerFomo, lens: 'AV2');

  // --- AV3-02 sold / qty=0 fora da vitrine ---
  final visItem = (await rt.insertItem(
    liveId: live,
    service: true,
    kind: 'live_only',
    qty: 1,
    price: 5,
    title: '$prefix p2-sold',
  ))
      .firstId;
  if (visItem != null) {
    await rt.rest('PATCH', 'live_items?id=eq.$visItem', service: true, body: {
      'status': 'sold',
      'quantity': 0,
      'is_active': true,
    }, prefer: 'return=minimal');
    final hub = await rt.hubDiscoveryItem(visItem);
    final buyerSee = await rt.rest(
      'GET',
      'live_items?id=eq.$visItem&select=id,status,quantity',
      jwt: rt.buyerJwt,
    );
    rt.judge(
      id: 'AV3-02',
      lens: 'AV3',
      title: 'Item sold qty=0 na vitrine Hub / REST buyer',
      hit: buyerSee,
      cracked: hub != null || buyerSee.list.isNotEmpty,
      actor: 'anon + buyer JWT',
      pre: 'service PATCH status=sold quantity=0',
      repro: 'hub_live_items_discovery_public + live_items SELECT buyer',
      expected: 'Hub vazio; buyer policy esconde sold',
      severity: 'P2',
      evidence: {'hub': hub, 'buyer': buyerSee.brief},
    );
  }

  // --- AV6-05 evidência: 2.º accept não ficou accepted ---
  final capLive = await rt.insertLive(title: '$prefix p2cap');
  final capItem = capLive == null
      ? null
      : (await rt.insertItem(
          liveId: capLive,
          service: true,
          kind: 'live_only',
          qty: 1,
          price: 6,
          title: '$prefix p2cap-item',
        ))
          .firstId;
  if (capLive != null && capItem != null) {
    final r1 = await rt.insertRes(
      liveId: capLive,
      itemId: capItem,
      jwt: rt.buyerJwt,
    );
    final r2 = await rt.insertRes(
      liveId: capLive,
      itemId: capItem,
      jwt: rt.buyer2Jwt,
      buyer: rt.buyer2Id,
    );
    if (r1.firstId != null && r2.firstId != null) {
      await Future.wait([
        rt.processRes(r1.firstId!, 'accept'),
        rt.processRes(r2.firstId!, 'accept'),
      ]);
      final s1 = await rt.resRow(r1.firstId!);
      final s2 = await rt.resRow(r2.firstId!);
      final nAcc = [s1?['status'], s2?['status']]
          .where((s) => s == 'accepted' || s == 'converted')
          .length;
      rt.judge(
        id: 'AV6-05',
        lens: 'AV6',
        title: 'Stock=1 duas accepts paralelas (contagem)',
        hit: HttpHit(200, 'nAcc=$nAcc s1=${s1?['status']} s2=${s2?['status']}', {
          's1': s1,
          's2': s2,
        }),
        cracked: nAcc >= 2,
        actor: 'seller JWT',
        pre: 'qty=1',
        repro: 'Future.wait 2x accept',
        expected: 'nAcc==1',
        severity: 'P1',
        evidence: {'nAcc': nAcc, 's1': s1?['status'], 's2': s2?['status']},
      );
    }
  }

  // Helper broadcast COM pago (happy) vs sem
  final paid = await rt.insertPaidOrder(
    productId: (await rt.createProduct(title: '$prefix p2sku', qty: 1))!,
    liveItemId: item,
    liveId: live,
    status: 'pago',
  );
  final hBcPaid = await rt.purchaseBc(
    liveId: live,
    buyer: rt.buyerId!,
    itemId: item,
    jwt: rt.helperJwt,
  );
  rt.note('av2.helper.bc.paid', 'helper broadcast com PI', {
    'order': paid,
    'bc': hBcPaid.brief,
  }, lens: 'AV2');

  // Convert after ended WITH paid (should work — already paid)
  final res = await rt.insertRes(
    liveId: live,
    itemId: item,
    jwt: rt.buyerJwt,
  );
  if (res.firstId != null) {
    await rt.processRes(res.firstId!, 'accept');
    await rt.rest('PATCH', 'lives?id=eq.$live', service: true, body: {
      'status': 'ended',
      'is_active': false,
    }, prefer: 'return=minimal');
    final convEnded = await rt.processRes(res.firstId!, 'convert');
    final row = await rt.resRow(res.firstId!);
    rt.note('av1.convert.ended.paid', 'convert após ended com PI', {
      'rpc': convEnded.brief,
      'status': row?['status'],
    }, lens: 'AV1');
  }

  await rt.cleanupSoft();
  await rt.dumpAll('pass2.json');
  stdout.writeln(
    'PASS2 findings=${rt.findings.length} blocked=${rt.blocked.length}',
  );
}
