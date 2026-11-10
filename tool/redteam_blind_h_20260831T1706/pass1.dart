/// PASS 1 — H1 helper escalate / perm mínima · H4 JWT após kick · H5 staff loja alheia.
import 'dart:io';
import '_rth.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rth.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.ensureHelperChat();
  await c.ensureHelperRes();

  final out = <String, Object?>{
    'pass': 1,
    'prefix': prefix,
    'actors': {
      'buyer': c.buyerId,
      'seller': c.sellerId,
      'buyer2': c.buyer2Id,
      'seller2': c.seller2Id,
      'helperChat': c.helperChatId,
      'helperRes': c.helperResId,
    },
  };

  final pid = await c.insertProduct(title: '$prefix sku-h1', qty: 4);
  final live = await c.insertLive(active: true);
  out['sku'] = pid;
  out['live'] = live;

  c.helperChatLinkId = await c.inviteHelper(
    helperUserId: c.helperChatId!,
    helperJwt: c.helperChatJwt!,
    permissions: chatOnlyPerms,
    display: '$prefix chat-only',
  );
  c.helperResLinkId = await c.inviteHelper(
    helperUserId: c.helperResId!,
    helperJwt: c.helperResJwt!,
    permissions: resOnlyPerms,
    display: '$prefix res-only',
  );

  final rowChat = c.helperChatLinkId == null
      ? null
      : await c.helperRow(c.helperChatLinkId!);
  c.note('p1.helper.chat.row', 'chat-only after accept', rowChat, lens: 'H1');
  if (rowChat != null && permsEscalated(rowChat['permissions'])) {
    c.hold(
      id: 'RTH-H1-001',
      lens: 'H1',
      severity: 'P1',
      title: 'Helper chat-only alargou permissions no accept',
      actor: 'helperChat',
      pre: 'invite chat-only ${c.helperChatLinkId}',
      repro: 'PATCH seller_helpers permissions hostis ao aceitar',
      expected: 'permissions imutáveis (só chat)',
      obtained: rowChat['permissions'],
      evidence: {'row': rowChat},
    );
  }

  // ---- H1: perm mínima implica Y ----
  final hasRefund = await c.rpc('batata_staff_has_permission', {
    'p_seller_id': c.sellerId,
    'p_permission': 'can_issue_refunds',
  }, jwt: c.helperChatJwt);
  final hasRaffle = await c.rpc('batata_staff_has_permission', {
    'p_seller_id': c.sellerId,
    'p_permission': 'can_manage_raffles',
  }, jwt: c.helperChatJwt);
  final hasRes = await c.rpc('batata_staff_has_permission', {
    'p_seller_id': c.sellerId,
    'p_permission': 'can_manage_reservations',
  }, jwt: c.helperChatJwt);
  final hasChat = await c.rpc('batata_staff_has_permission', {
    'p_seller_id': c.sellerId,
    'p_permission': 'can_manage_chat',
  }, jwt: c.helperChatJwt);
  c.note('p1.h1.has', 'staff bits chat-only', {
    'refund': hasRefund.brief,
    'raffle': hasRaffle.brief,
    'res': hasRes.brief,
    'chat': hasChat.brief,
  }, lens: 'H1');
  if (hasRefund.body.trim() == 'true' || hasRaffle.body.trim() == 'true') {
    c.hold(
      id: 'RTH-H1-002',
      lens: 'H1',
      severity: 'P1',
      title: 'batata_staff_has_permission true para bits financeiros (chat-only)',
      actor: 'helperChat',
      pre: 'permissions chat-only',
      repro: 'rpc batata_staff_has_permission',
      expected: 'false',
      obtained: {
        'refund': hasRefund.body,
        'raffle': hasRaffle.body,
      },
    );
  }

  final prodIns = await c.rest('POST', 'products', jwt: c.helperChatJwt, body: {
    'seller_id': c.sellerId,
    'title': '$prefix helper-as-shop',
    'price': 9.9,
    'quantity': 1,
    'list_on_marketplace': true,
    'image_urls': <String>[],
  });
  c.note('p1.h1.prod.ins', 'helper INSERT product seller_id=shop', prodIns.brief,
      lens: 'H1');
  if (prodIns.ok && prodIns.firstId != null) {
    c.createdProductIds.add(prodIns.firstId!);
    c.hold(
      id: 'RTH-H1-003',
      lens: 'H1',
      severity: 'P1',
      title: 'Helper chat-only INSERT produto na loja do vendedor',
      actor: 'helperChat',
      pre: 'can_create_products=false',
      repro: 'POST products seller_id=shop JWT helper',
      expected: '403 / []',
      obtained: prodIns.brief,
    );
  }

  if (pid != null) {
    final prodPatch = await c.rest(
      'PATCH',
      'products?id=eq.$pid',
      jwt: c.helperChatJwt,
      body: {'price': 1.0, 'title': '$prefix hijack-price'},
    );
    c.note('p1.h1.prod.patch', 'helper PATCH shop SKU', prodPatch.brief,
        lens: 'H1');
    final afterP = await c.productRow(pid);
    if (afterP != null &&
        (afterP['price'] == 1.0 ||
            '${afterP['title']}'.contains('hijack-price'))) {
      c.hold(
        id: 'RTH-H1-004',
        lens: 'H1',
        severity: 'P1',
        title: 'Helper chat-only alterou preço/título do SKU da loja',
        actor: 'helperChat',
        pre: 'can_edit_products=false',
        repro: 'PATCH products JWT helper',
        expected: 'sem alteração',
        obtained: afterP,
      );
    }
  }

  final ordersH = await c.rest(
    'GET',
    'orders?seller_id=eq.${c.sellerId}&select=id,buyer_id,status,price_total&limit=8',
    jwt: c.helperChatJwt,
  );
  c.note('p1.h1.orders', 'helper SELECT orders da loja', ordersH.brief,
      lens: 'H1');
  if (ordersH.ok && ordersH.list.isNotEmpty) {
    c.hold(
      id: 'RTH-H1-005',
      lens: 'H1',
      severity: 'P2',
      title: 'Helper chat-only lê encomendas da loja',
      actor: 'helperChat',
      pre: 'can_manage_orders=false; RLS owner-only esperado',
      repro: 'GET orders?seller_id=eq.shop',
      expected: '[]',
      obtained: {'n': ordersH.list.length, 'snip': ordersH.snippet},
    );
  }

  final walH = await c.rest(
    'GET',
    'wallets?id=eq.${c.sellerId}&select=id,user_id,balance',
    jwt: c.helperChatJwt,
  );
  c.note('p1.h1.wallet', 'helper lê wallet da loja', walH.brief, lens: 'H1');
  if (walH.ok && walH.list.isNotEmpty) {
    c.hold(
      id: 'RTH-H1-006',
      lens: 'H1',
      severity: 'P0',
      title: 'Helper chat-only lê saldo da loja',
      actor: 'helperChat',
      pre: 'can_view_payouts=false',
      repro: 'GET wallets?id=eq.seller',
      expected: '[]',
      obtained: walH.snippet,
    );
  }

  final profH = await c.rest(
    'PATCH',
    'profiles?id=eq.${c.sellerId}',
    jwt: c.helperChatJwt,
    body: {'full_name': '$prefix hijack-shop'},
  );
  c.note('p1.h1.profile', 'helper PATCH perfil da loja', profH.brief,
      lens: 'H1');
  final profObs = await c.rest(
    'GET',
    'profiles?id=eq.${c.sellerId}&select=id,full_name',
    service: true,
  );
  if ('${profObs.map?['full_name']}'.contains('hijack-shop')) {
    c.hold(
      id: 'RTH-H1-007',
      lens: 'H1',
      severity: 'P1',
      title: 'Helper chat-only alterou o nome da loja',
      actor: 'helperChat',
      pre: 'can_edit_store_profile=false',
      repro: 'PATCH profiles id=seller',
      expected: 'sem alteração',
      obtained: profObs.snippet,
    );
  }

  final inviteAsHelper = await c.rpc('batata_staff_invite_helper_by_email', {
    'p_email': '${prefix.toLowerCase()}-b2@fleaber.test',
    'p_display_name': 'x',
    'p_permissions': {'can_issue_refunds': true},
  }, jwt: c.helperChatJwt);
  c.note('p1.h1.invite', 'helper convida outro helper', inviteAsHelper.brief,
      lens: 'H1');
  if (inviteAsHelper.ok &&
      !inviteAsHelper.body.contains('negad') &&
      !inviteAsHelper.body.contains('not_allowed') &&
      inviteAsHelper.status != 400 &&
      inviteAsHelper.status != 403) {
    c.hold(
      id: 'RTH-H1-008',
      lens: 'H1',
      severity: 'P1',
      title: 'Helper chat-only convidou colaborador (can_manage_helpers)',
      actor: 'helperChat',
      pre: 'can_manage_helpers=false',
      repro: 'rpc batata_staff_invite_helper_by_email',
      expected: 'negado',
      obtained: inviteAsHelper.brief,
    );
  }

  final raffleH = await c.rpc('batata_live_raffle_draw', {
    'p_live_id': live,
  }, jwt: c.helperChatJwt);
  c.note('p1.h1.raffle', 'helper chat-only rifa', raffleH.brief, lens: 'H1');
  if (raffleH.ok && raffleH.body.contains('ok') && !raffleH.body.contains('false') &&
      !raffleH.body.contains('not_allowed')) {
    final looksOk = raffleH.map?['ok'] == true || raffleH.status == 200 && raffleH.body.contains('"id"');
    if (looksOk && !raffleH.body.contains('not_allowed') && !raffleH.body.contains('Acesso')) {
      c.hold(
        id: 'RTH-H1-009',
        lens: 'H1',
        severity: 'P1',
        title: 'Helper chat-only disparou rifa',
        actor: 'helperChat',
        pre: 'can_manage_raffles=false',
        repro: 'rpc batata_live_raffle_draw',
        expected: 'not_allowed',
        obtained: raffleH.brief,
      );
    }
  }

  final muxH = await c.edge('create-mux-live', {
    'title': '$prefix helper mux',
  }, jwt: c.helperChatJwt);
  c.note('p1.h5.mux.helper', 'helper create-mux-live', muxH.brief, lens: 'H5');
  if (muxH.ok && (muxH.body.contains('mux') || muxH.map?['live_id'] != null)) {
    c.hold(
      id: 'RTH-H5-001',
      lens: 'H5',
      severity: 'P1',
      title: 'Helper comprador criou directo Mux',
      actor: 'helperChat',
      pre: 'user_type=comprador; chat-only',
      repro: 'POST create-mux-live JWT helper',
      expected: '403 Apenas contas de vendedor',
      obtained: muxH.brief,
    );
  }

  final livesIns = await c.rest('POST', 'lives', jwt: c.helperChatJwt, body: {
    'seller_id': c.sellerId,
    'vendedor_id': c.helperChatId,
    'title': '$prefix helper-as-shop-live',
    'status': 'live',
    'is_active': true,
  });
  c.note('p1.h5.lives.ins', 'helper INSERT lives seller_id=shop', livesIns.brief,
      lens: 'H5');
  if (livesIns.ok && livesIns.firstId != null) {
    c.createdLiveIds.add(livesIns.firstId!);
    c.hold(
      id: 'RTH-H5-002',
      lens: 'H5',
      severity: 'P1',
      title: 'Helper INSERT live atribuída à loja (seller_id alheio)',
      actor: 'helperChat',
      pre: 'lives_insert_own; vendedor_id=helper seller_id=shop',
      repro: 'POST lives JWT helper',
      expected: '403',
      obtained: livesIns.brief,
    );
  }

  if (live != null) {
    final completeX = await c.edge('complete-mux-live', {
      'live_id': live,
    }, jwt: c.helperChatJwt);
    c.note('p1.h5.complete', 'helper complete-mux loja', completeX.brief,
        lens: 'H5');
    if (completeX.ok) {
      c.hold(
        id: 'RTH-H5-003',
        lens: 'H5',
        severity: 'P1',
        title: 'Helper encerrou directo Mux da loja',
        actor: 'helperChat',
        pre: 'ownerId !== helper',
        repro: 'POST complete-mux-live live_id=shop',
        expected: '403',
        obtained: completeX.brief,
      );
    }

    final lk = await c.edge('livekit-mux-publish', {
      'step': 'token',
      'live_id': live,
    }, jwt: c.helperChatJwt);
    c.note('p1.h5.livekit', 'helper livekit token loja', lk.brief, lens: 'H5');
    if (lk.ok && (lk.body.contains('token') || lk.map?['token'] != null)) {
      c.hold(
        id: 'RTH-H5-004',
        lens: 'H5',
        severity: 'P1',
        title: 'Helper obteve token LiveKit da live da loja',
        actor: 'helperChat',
        pre: 'ownerId !== helper',
        repro: 'POST livekit-mux-publish step=token',
        expected: '403',
        obtained: lk.brief,
      );
    }

    final liIns = await c.rest('POST', 'live_items', jwt: c.helperChatJwt, body: {
      'live_id': live,
      'seller_id': c.sellerId,
      'title': '$prefix helper item',
      'price': 12.0,
      'quantity': 1,
    });
    c.note('p1.h5.live_items', 'helper INSERT live_items loja', liIns.brief,
        lens: 'H5');
    if (liIns.ok && liIns.firstId != null) {
      c.hold(
        id: 'RTH-H5-005',
        lens: 'H5',
        severity: 'P1',
        title: 'Helper chat-only INSERT live_item na live da loja',
        actor: 'helperChat',
        pre: 'live_items_insert_own_live = owner',
        repro: 'POST live_items JWT helper',
        expected: '403',
        obtained: liIns.brief,
      );
    }
  }

  // H5: staff na loja de seller2 (sem convite)
  final raffleS2 = await c.rpc('batata_live_raffle_draw', {
    'p_live_id': live,
  }, jwt: c.seller2Jwt);
  c.note('p1.h5.raffle.s2', 'seller2 rifa live de S1', raffleS2.brief, lens: 'H5');

  final refundS2 = await c.edge('refund-order', {
    'order_id': '00000000-0000-0000-0000-000000000001',
  }, jwt: c.helperChatJwt);
  c.note('p1.h5.refund.ghost', 'helper refund order fake', refundS2.brief,
      lens: 'H5');

  // Helper self-insert onto seller2
  final selfLink = await c.rest('POST', 'seller_helpers', jwt: c.helperChatJwt, body: {
    'seller_id': c.seller2Id,
    'helper_user_id': c.helperChatId,
    'invited_by': c.helperChatId,
    'invitation_status': 'accepted',
    'active': true,
    'display_name': '$prefix self',
    'permissions': refundPerms,
  });
  c.note('p1.h5.selflink', 'helper INSERT-se na loja S2', selfLink.brief,
      lens: 'H5');
  if (selfLink.ok && selfLink.firstId != null) {
    c.createdHelperIds.add(selfLink.firstId!);
    c.hold(
      id: 'RTH-H5-006',
      lens: 'H5',
      severity: 'P0',
      title: 'Helper auto-convidou-se para loja alheia com refund',
      actor: 'helperChat',
      pre: 'sem convite de S2',
      repro: 'POST seller_helpers seller_id=S2 helper=self accepted',
      expected: '403',
      obtained: selfLink.brief,
    );
  }

  // ---- H4: user_type + kick ----
  final utAdmin = await c.rest(
    'PATCH',
    'profiles?id=eq.${c.helperChatId}',
    jwt: c.helperChatJwt,
    body: {'user_type': 'admin'},
  );
  final utVend = await c.rest(
    'PATCH',
    'profiles?id=eq.${c.helperChatId}',
    jwt: c.helperChatJwt,
    body: {'user_type': 'vendedor'},
  );
  final utObs = await c.rest(
    'GET',
    'profiles?id=eq.${c.helperChatId}&select=id,user_type',
    service: true,
  );
  c.note('p1.h4.user_type', 'helper PATCH user_type', {
    'admin': utAdmin.brief,
    'vend': utVend.brief,
    'obs': utObs.snippet,
  }, lens: 'H4');
  final ut = '${utObs.map?['user_type']}'.toLowerCase();
  if (ut.contains('admin') || ut == 'vendedor' || ut == 'seller') {
    c.hold(
      id: 'RTH-H4-001',
      lens: 'H4',
      severity: 'P0',
      title: 'Helper elevou user_type (admin/vendedor)',
      actor: 'helperChat',
      pre: 'user_type=comprador',
      repro: 'PATCH profiles user_type',
      expected: 'comprador (frozen)',
      obtained: utObs.snippet,
    );
  }

  if (c.helperChatLinkId != null) {
    await c.kickHelper(c.helperChatLinkId!);
    final afterKick = await c.helperRow(c.helperChatLinkId!);
    c.note('p1.h4.kicked', 'helper chat kicked', afterKick, lens: 'H4');

    final hasChatAfter = await c.rpc('batata_staff_has_permission', {
      'p_seller_id': c.sellerId,
      'p_permission': 'can_manage_chat',
    }, jwt: c.helperChatJwt);
    c.note('p1.h4.has.after', 'perm após kick', hasChatAfter.brief, lens: 'H4');
    if (hasChatAfter.body.trim() == 'true') {
      c.hold(
        id: 'RTH-H4-002',
        lens: 'H4',
        severity: 'P1',
        title: 'JWT helper ainda tem permissão após kick',
        actor: 'helperChat',
        pre: 'active=false / revoked',
        repro: 'rpc batata_staff_has_permission após kick',
        expected: 'false',
        obtained: hasChatAfter.brief,
      );
    }

    final reactivate = await c.rest(
      'PATCH',
      'seller_helpers?id=eq.${c.helperChatLinkId}',
      jwt: c.helperChatJwt,
      body: {'active': true, 'invitation_status': 'accepted'},
    );
    c.note('p1.h4.reactivate', 'helper re-activa-se', reactivate.brief,
        lens: 'H4');
    final afterRe = await c.helperRow(c.helperChatLinkId!);
    if (afterRe?['active'] == true) {
      c.hold(
        id: 'RTH-H4-003',
        lens: 'H4',
        severity: 'P1',
        title: 'Helper reactivou o próprio convite após kick',
        actor: 'helperChat',
        pre: 'seller kicked',
        repro: 'PATCH seller_helpers active=true JWT helper',
        expected: 'active permanece false',
        obtained: afterRe,
      );
    }

    final muxAfter = await c.edge('create-mux-live', {
      'title': '$prefix after kick',
    }, jwt: c.helperChatJwt);
    c.note('p1.h4.mux.after', 'mux após kick', muxAfter.brief, lens: 'H4');
  }

  await c.endLives();
  out['notes'] = c.notes;
  out['findings'] = c.findings;
  out['helper_chat_link'] = c.helperChatLinkId;
  out['helper_res_link'] = c.helperResLinkId;
  await dumpJson('tool/redteam_blind_h_20260831T1706/pass1.json', out);
  stdout.writeln('PASS1 findings=${c.findings.length}');
}
