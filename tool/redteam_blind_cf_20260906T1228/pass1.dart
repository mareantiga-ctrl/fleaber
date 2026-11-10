/// REDTEAM_BLIND_CF_LIVE_POS_BXCC_v1 — pass1 FOMO matriz + staff emit.
/// Staging only. No fixes.
import 'dart:io';

import '_rtcf.dart';

Future<void> main() async {
  final c = Rtcf.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureHelperChatOnly();
  await c.ensureHelperNone();
  await c.ensureHelperSold();

  final liveId = await c.createLive(title: '$prefix p1');
  final sku = await c.createProduct(title: '$prefix p1 sku', qty: 2, live: true);
  if (liveId == null || sku == null) {
    stderr.writeln('fixture live/sku fail');
    exit(4);
  }
  final itemId = await c.createLiveItem(
    liveId: liveId,
    title: '$prefix p1 item',
    ref: 'RTCF-P1A',
    kind: 'live_only',
    checkoutProductId: sku,
    quantity: 2,
  );
  if (itemId == null) {
    stderr.writeln('fixture item fail ${c.notes}');
    await c.endAllCreatedLives();
    exit(4);
  }

  final stockBefore = await c.stock(itemId);
  c.note('p1.stock.before', 'stock antes FOMO', stockBefore, lens: 'CF3');

  Future<Map<String, dynamic>> tryFomo({
    required String id,
    required String body,
    required String? jwt,
    required String actor,
    bool exactClosed = false,
  }) async {
    final h = await c.rpc(
      'batata_live_system_message',
      {
        'p_live_id': liveId,
        'p_body': body,
        'p_sender_label': 'Sistema',
      },
      jwt: jwt,
    );
    final ok = h.map?['ok'] == true;
    final err = h.map?['error']?.toString() ?? h.brief;
    if (ok) {
      if (exactClosed) {
        c.hold(
          id: id,
          lens: 'CF2',
          severity: 'P2',
          title: 'REGRESSÃO BXCC FOMO persistiu: $body',
          actor: actor,
          pre: 'exacto BXCC deveria recusar',
          repro: 'rpc batata_live_system_message p_body=$body',
          expected: 'ok=false purchase_announce_via_broadcast_only',
          obtained: h.brief,
          evidence: {'body': body, 'rpc': h.map},
        );
      } else {
        c.hold(
          id: id,
          lens: 'CF2',
          severity: 'P2',
          title: 'FOMO anúncio persistiu: $body',
          actor: actor,
          pre: 'denylist BXCC sem este payload',
          repro: 'rpc batata_live_system_message p_body=$body',
          expected: 'ok=false purchase_announce_via_broadcast_only',
          obtained: h.brief,
          evidence: {'body': body, 'rpc': h.map},
        );
      }
    } else {
      c.block(
        id,
        'CF2',
        exactClosed ? 'exacto BXCC recusado (não contar)' : 'variante recusada',
        err,
      );
    }
    return {
      'id': id,
      'body': body,
      'ok': ok,
      'err': err,
      'exact': exactClosed,
      'actor': actor,
    };
  }

  // Exactos BXCC / BZ — HOLD se recusados; regressão se persistirem.
  final exact = <List<String>>[
    ['lastone', 'last one'],
    ['janoha', 'já não há'],
    ['semstock', 'sem stock'],
    ['sold', 'sold'],
    ['oneleft', '1 left'],
    ['taken', 'taken'],
    ['minenow', 'mine now'],
    ['esgotou', 'esgotou'],
    ['claimed', 'claimed'],
    ['s0ld', 's0ld'],
    ['janoha_sp', 'já  não   há'],
  ];
  for (final row in exact) {
    await tryFomo(
      id: 'p1.fomo.exact.${row[0]}',
      body: row[1],
      jwt: c.sellerJwt,
      actor: 'seller JWT',
      exactClosed: true,
    );
  }

  // Matriz nova ≥10 (emoji / l33t / spaced / sinonímia / homógrafo / bidi).
  final variants = <List<String>>[
    ['emoji_fire_1left', '🔥1 left🔥'],
    ['emoji_warn_sold', '⚠️sold⚠️'],
    ['emoji_check_taken', '✅taken'],
    ['spaced_last_one', 'l a s t   o n e'],
    ['foi_embora', 'foi embora'],
    ['ja_tem_dono', 'já tem dono'],
    ['claiming', 'claiming'],
    ['no_more_left', 'no more left'],
    ['acaba_de_sair', 'acaba de sair'],
    ['last_hyphen', 'last-one'],
    ['lastone_concat', 'lastone'],
    ['longs_sold', '\u017fold'],
    ['cyr_a_sold', 's\u0430ld'],
    ['bidi_sold', 's\u202eold'],
    ['agotado', 'agotado'],
    ['se_fue', 'se fue'],
    ['ya_dueno', 'ya tiene dueño'],
    ['final_piece', 'final piece'],
    ['levado', 'levado'],
    ['going_once', 'going once'],
    ['esgotou_pt_new', 'esgotou-se'],
    ['mine_now_spaced', 'm i n e   n o w'],
    ['sold_dot', 'sold.'],
    ['reservado_hom', 'reservado'],
    ['owner_now', 'já tem dono agora'],
    ['acaba_sair', 'acaba de sair da live'],
    ['one_left_emoji_only', '🔥1🔥'],
    ['taken_check_only', '✅'],
    ['staff_imit_gone_pt', 'foi embora da loja'],
  ];
  final persisted = <Map<String, dynamic>>[];
  for (final row in variants) {
    final r = await tryFomo(
      id: 'p1.fomo.new.${row[0]}',
      body: row[1],
      jwt: c.sellerJwt,
      actor: 'seller JWT',
    );
    if (r['ok'] == true) persisted.add(r);
  }

  // Helper chat-only em variantes novas (não exactos).
  for (final body in ['foi embora', 'claiming', 'l a s t   o n e', 'já tem dono']) {
    await tryFomo(
      id: 'p1.fomo.helper.${body.hashCode}',
      body: body,
      jwt: c.helperJwt,
      actor: 'helper can_manage_chat',
    );
  }

  // Helper sem perms.
  await tryFomo(
    id: 'p1.fomo.helper0.foi',
    body: 'foi embora',
    jwt: c.helperNoneJwt,
    actor: 'helper zero perms',
  );

  // Helper só can_mark_items_sold.
  await tryFomo(
    id: 'p1.fomo.helpersold.foi',
    body: 'foi embora',
    jwt: c.helperSoldJwt,
    actor: 'helper can_mark_items_sold',
  );

  // Buyer RPC system.
  final buyerSys = await c.rpc(
    'batata_live_system_message',
    {
      'p_live_id': liveId,
      'p_body': 'foi embora',
      'p_sender_label': 'Sistema',
    },
    jwt: c.buyerJwt,
  );
  if (buyerSys.map?['ok'] == true) {
    c.hold(
      id: 'p1.fomo.buyer.system',
      lens: 'CF2',
      severity: 'P2',
      title: 'Buyer RPC system_message FOMO persistiu',
      actor: 'buyer JWT',
      pre: 'só seller/helper chat',
      repro: 'rpc batata_live_system_message foi embora',
      expected: 'not_allowed',
      obtained: buyerSys.brief,
    );
  } else {
    c.block('p1.fomo.buyer.system', 'CF2', 'buyer system recusado',
        buyerSys.brief);
  }

  // INSERT kind=system bypass.
  Future<void> tryInsertSystem({
    required String id,
    required String? jwt,
    required String actor,
    required String body,
  }) async {
    final uid = actor.contains('buyer')
        ? c.buyerId
        : actor.contains('helper')
            ? c.helperId
            : c.sellerId;
    final h = await c.rest('POST', 'live_messages', jwt: jwt, body: {
      'live_id': liveId,
      'user_id': uid,
      'kind': 'system',
      'body': body,
      'sender_label': 'Sistema',
    });
    if (h.ok && h.firstId != null) {
      c.hold(
        id: id,
        lens: 'CF2',
        severity: 'P2',
        title: 'INSERT live_messages kind=system bypass RPC: $body ($actor)',
        actor: actor,
        pre: 'denylist só em batata_live_system_message',
        repro: 'POST live_messages kind=system body=$body',
        expected: '403/RLS',
        obtained: h.brief,
        evidence: {'body': body, 'id': h.firstId},
      );
    } else {
      c.block(id, 'CF2', 'INSERT system recusado ($actor)', h.brief);
    }
  }

  await tryInsertSystem(
    id: 'p1.fomo.insert.buyer.foi',
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    body: 'foi embora',
  );
  await tryInsertSystem(
    id: 'p1.fomo.insert.seller.foi',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    body: 'foi embora',
  );

  // Buyer imita staff: chat + sender_label Sistema.
  final buyerChat = await c.rest('POST', 'live_messages', jwt: c.buyerJwt, body: {
    'live_id': liveId,
    'user_id': c.buyerId,
    'kind': 'chat',
    'body': 'foi embora — última unidade',
    'sender_label': 'Sistema',
  });
  if (buyerChat.ok && buyerChat.firstId != null) {
    final row = await c.rest(
      'GET',
      'live_messages?id=eq.${buyerChat.firstId}&select=id,kind,body,sender_label,user_id',
      jwt: c.buyer2Jwt,
    );
    final label = row.map?['sender_label']?.toString();
    if (label == 'Sistema') {
      c.hold(
        id: 'p1.fomo.buyer.imitate.staff',
        lens: 'CF2',
        severity: 'P2',
        title: 'Buyer chat com sender_label=Sistema visível a outro buyer',
        actor: 'buyer JWT',
        pre: 'INSERT kind=chat permite sender_label livre',
        repro: 'POST live_messages kind=chat sender_label=Sistema',
        expected: 'label forçada ao perfil / recusa Sistema',
        obtained: row.map,
        evidence: {'insert': buyerChat.brief, 'seen': row.map},
      );
    } else {
      c.block('p1.fomo.buyer.imitate.staff', 'CF2',
          'label não ficou Sistema', {'insert': buyerChat.brief, 'row': row.map});
    }
  } else {
    c.block('p1.fomo.buyer.imitate.staff', 'CF2', 'buyer chat FOMO recusado',
        buyerChat.brief);
  }

  // Seller chat FOMO (não system) — anotar; só finding se buyer vê como system.
  final sellerChat = await c.rest('POST', 'live_messages', jwt: c.sellerJwt, body: {
    'live_id': liveId,
    'user_id': c.sellerId,
    'kind': 'chat',
    'body': 'já tem dono',
    'sender_label': 'Sistema',
  });
  c.note('p1.fomo.seller.chat', 'seller chat FOMO', sellerChat.brief, lens: 'CF2');

  final seen = await c.rest(
    'GET',
    'live_messages?live_id=eq.$liveId&select=id,kind,body,sender_label&order=created_at.desc&limit=80',
    jwt: c.buyerJwt,
  );
  final bodies = seen.list
      .whereType<Map>()
      .map((m) => {
            'kind': m['kind'],
            'body': m['body'],
            'label': m['sender_label'],
          })
      .toList();
  c.note('p1.fomo.buyer.sees', 'buyer vê messages', bodies, lens: 'CF2');

  final stockAfter = await c.stock(itemId);
  c.note('p1.stock.after', 'stock depois FOMO', stockAfter, lens: 'CF3');
  final availB = stockBefore?['available_qty'];
  final availA = stockAfter?['available_qty'];
  if (availB != null && availA != null && availA != availB) {
    c.hold(
      id: 'p1.fomo.stock.delta',
      lens: 'CF3',
      severity: 'P1',
      title: 'FOMO system message alterou stock',
      actor: 'seller JWT',
      pre: 'só anúncio, sem accept/pagamento',
      repro: 'stock before/after system_message',
      expected: 'available_qty inalterado',
      obtained: {'before': stockBefore, 'after': stockAfter},
    );
  } else {
    c.block('p1.fomo.stock.delta', 'CF3', 'stock inalterado após FOMO', {
      'before': stockBefore,
      'after': stockAfter,
    });
  }

  final orders = await c.rest(
    'GET',
    'orders?live_id=eq.$liveId&select=id,status,amount_paid_cents',
    service: true,
  );
  final paid = orders.list.whereType<Map>().where((o) {
    final st = '${o['status']}'.toLowerCase();
    final cents = o['amount_paid_cents'];
    return st.contains('pago') || (cents is num && cents > 0);
  }).toList();
  if (paid.isNotEmpty) {
    c.hold(
      id: 'p1.fomo.caixa.pago',
      lens: 'CF8',
      severity: 'P0',
      title: 'FOMO coincidiu com order paga nesta live de fixture',
      actor: 'n/a',
      pre: 'fixture sem checkout',
      repro: 'GET orders live_id',
      expected: 'zero pago',
      obtained: paid,
    );
  } else {
    c.block('p1.fomo.caixa.pago', 'CF8', 'FOMO não criou order paga',
        {'n': orders.list.length});
  }

  await dumpJson('${outDir()}/pass1.json', {
    'auditor': 'REDTEAM_BLIND_CF_LIVE_POS_BXCC_v1',
    'prefix': prefix,
    'liveId': liveId,
    'itemId': itemId,
    'persisted_new': persisted,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
      'pass1 done findings=${c.findings.length} blocked=${c.blocked.length} persisted_new=${persisted.length}');
}
