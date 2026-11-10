/// RED TEAM CEGO AM — pass 1. Staging only. Não corrige.
import 'dart:io';
import '_rtam.dart';

Future<void> main() async {
  final c = Rtam.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.note('actors', 'JWT B1/S1/B2/S2', {
    'b1': c.buyerId,
    's1': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
  });

  final paid = await c.payToPago(lens: 'AM1', initialQty: 1);
  if (paid == null) {
    c.skip('AM.fixture', 'AM1', 'setup_paid_order falhou', 'null');
    await c.dumpAll('pass1.json');
    return;
  }
  final oid = paid.oid;
  final pid = paid.pid;
  var o = await c.orderRow(oid);
  var p = await c.productRow(pid);
  final wallets0 = await c.wallets();
  c.note('fixture.books', 'pago Stripe TEST', {
    'order': o,
    'product': p,
    'wallets': wallets0,
    'pi': paid.pi,
  }, lens: 'AM1');

  Future<Map<String, dynamic>> books() async => {
        'order': await c.orderRow(oid),
        'product': await c.productRow(pid),
        'wallets': await c.wallets(),
      };

  // -------------------------------------------------------------------------
  // AM1 — disputa vs FSM / JWT alheio
  // -------------------------------------------------------------------------
  final alien = await c.insertDispute(
    orderId: oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  if (alien.ok) {
    c.hold(
      id: 'AM1.alien_insert',
      lens: 'AM1',
      severity: 'P1',
      title: '2.º buyer abre disputa em encomenda alheia',
      actor: 'buyer2 JWT',
      pre: 'order pago B1/S1',
      repro: 'POST order_disputes buyer_id=B2 order_id=B1',
      expected: '401/403',
      obtained: alien.brief,
    );
  } else {
    c.block('AM1.alien_insert', 'AM1', 'JWT alheio insert disputa', alien);
  }

  final onPago = await c.insertDispute(orderId: oid);
  if (onPago.ok) {
    c.hold(
      id: 'AM1.dispute_on_pago',
      lens: 'AM1',
      severity: 'P1',
      title: 'Buyer abre disputa em status=pago (antes de entregue/concluido)',
      actor: 'buyer JWT',
      pre: 'order.status=pago',
      repro: 'POST order_disputes',
      expected: 'RLS recusa (só concluido/entregue)',
      obtained: onPago.brief,
    );
  } else {
    c.block('AM1.dispute_on_pago', 'AM1', 'disputa em pago', onPago);
  }

  final sellerInsert = await c.insertDispute(
    orderId: oid,
    jwt: c.sellerJwt,
    buyer: c.sellerId,
  );
  if (sellerInsert.ok) {
    c.hold(
      id: 'AM1.seller_insert',
      lens: 'AM1',
      severity: 'P1',
      title: 'Seller insere disputa como se fosse o comprador',
      actor: 'seller JWT',
      pre: 'order pago',
      repro: 'POST order_disputes buyer_id=seller',
      expected: '403',
      obtained: sellerInsert.brief,
    );
  } else {
    c.block('AM1.seller_insert', 'AM1', 'seller insert disputa', sellerInsert);
  }

  final anonIns = await c.rest('POST', 'order_disputes', body: {
    'order_id': oid,
    'buyer_id': c.buyerId,
    'reason': 'outro',
    'description': 'anon',
    'status': 'aberta',
  });
  if (anonIns.ok) {
    c.hold(
      id: 'AM1.anon_insert',
      lens: 'AM1',
      severity: 'P1',
      title: 'anon abre disputa',
      actor: 'anon',
      pre: 'order pago',
      repro: 'POST order_disputes sem JWT',
      expected: '401',
      obtained: anonIns.brief,
    );
  } else {
    c.block('AM1.anon_insert', 'AM1', 'anon insert', anonIns);
  }

  final adminRpc = await c.rpc(
    'batata_admin_resolve_dispute',
    {
      'p_dispute_id': '00000000-0000-0000-0000-000000000001',
      'p_resolution': 'favor_buyer_refund',
      'p_note': 'RTAM',
    },
    jwt: c.buyerJwt,
  );
  if (adminRpc.ok && adminRpc.map?[''] != false) {
    final brief = adminRpc.brief;
    if (!brief.toLowerCase().contains('admin') &&
        adminRpc.status < 400 &&
        adminRpc.body != 'false') {
      c.hold(
        id: 'AM1.admin_rpc',
        lens: 'AM1',
        severity: 'P0',
        title: 'Buyer executa batata_admin_resolve_dispute',
        actor: 'buyer JWT',
        pre: 'não-admin',
        repro: 'rpc batata_admin_resolve_dispute favor_buyer_refund',
        expected: 'exception admin only / false',
        obtained: brief,
      );
    } else {
      c.block('AM1.admin_rpc', 'AM1', 'admin resolve', adminRpc);
    }
  } else {
    c.block('AM1.admin_rpc', 'AM1', 'admin resolve', adminRpc);
  }

  // AM6 — mutar shipping_method pós-pago para mão e saltar enviado
  final shipMao = await c.patchOrder(oid, {'shipping_method': 'mão'},
      jwt: c.buyerJwt);
  o = await c.orderRow(oid);
  final shipNow = '${o?['shipping_method']}';
  c.note('AM6.ship_patch', 'PATCH shipping_method=mão', {
    'hit': shipMao.brief,
    'now': shipNow,
  }, lens: 'AM6');

  final skipEnviado = await c.patchOrder(oid, {'status': 'concluido'},
      jwt: c.buyerJwt);
  o = await c.orderRow(oid);
  if (o?['status'] == 'concluido' && o?['shipped_at'] == null) {
    c.hold(
      id: 'AM6.pago_concluido_via_mao_patch',
      lens: 'AM6',
      severity: 'P1',
      title: 'Buyer muta shipping_method=mão e salta enviado (pago→concluido)',
      actor: 'buyer JWT',
      pre: 'pago capturado, shipping vazio/carrier, shipped_at null',
      repro: 'PATCH shipping_method=mão; PATCH status=concluido',
      expected: 'order_concluido_requires_shipped / shipping imutável',
      obtained: {
        'patch_ship': shipMao.brief,
        'patch_status': skipEnviado.brief,
        'status': o?['status'],
        'shipped_at': o?['shipped_at'],
        'shipping_method': o?['shipping_method'],
      },
    );
  } else {
    c.block(
      'AM6.pago_concluido_via_mao_patch',
      'AM6',
      'pago→concluido via mão',
      {'status': o?['status'], 'hit': skipEnviado.brief},
    );
  }

  // Direct pago→concluido (clássico — só finding se ainda aberto)
  if ('${o?['status']}' == 'pago') {
    final direct = await c.patchOrder(oid, {'status': 'concluido'},
        jwt: c.buyerJwt);
    final afterDirect = await c.orderRow(oid);
    if (afterDirect?['status'] == 'concluido' &&
        afterDirect?['shipped_at'] == null) {
      c.hold(
        id: 'AM6.pago_concluido_direct',
        lens: 'AM6',
        severity: 'P1',
        title: 'pago→concluido carrier/vazio sem enviado',
        actor: 'buyer JWT',
        pre: 'pago sem shipped_at',
        repro: 'PATCH status=concluido',
        expected: '42501 order_concluido_requires_shipped',
        obtained: {'hit': direct.brief, 'status': afterDirect?['status']},
      );
    } else {
      c.block('AM6.pago_concluido_direct', 'AM6', 'clássico pago→concluido',
          direct);
    }
  }

  // -------------------------------------------------------------------------
  // AM2 — seller enviado; buyer disputa pós-envio
  // -------------------------------------------------------------------------
  o = await c.orderRow(oid);
  if ('${o?['status']}' == 'pago' || '${o?['status']}' == 'concluido') {
    // Se já concluido via mão, ainda testamos enviado noutro order.
  }

  final envHit = await c.patchOrder(oid, {'status': 'enviado'},
      jwt: c.sellerJwt);
  o = await c.orderRow(oid);
  c.note('AM2.seller_enviado', 'seller PATCH enviado', {
    'hit': envHit.brief,
    'status': o?['status'],
    'shipped_at': o?['shipped_at'],
  }, lens: 'AM2');

  if (o?['status'] == 'enviado' || o?['shipped_at'] != null) {
    final dispEnv = await c.insertDispute(orderId: oid);
    if (dispEnv.ok) {
      c.hold(
        id: 'AM2.dispute_on_enviado',
        lens: 'AM2',
        severity: 'P1',
        title: 'Buyer abre disputa em enviado (RLS deveria exigir entregue)',
        actor: 'buyer JWT',
        pre: 'status=enviado shipped_at set',
        repro: 'POST order_disputes',
        expected: 'RLS recusa',
        obtained: dispEnv.brief,
      );
    } else {
      c.block('AM2.dispute_on_enviado', 'AM2', 'disputa em enviado', dispEnv);
    }

    final refundShipped = await c.refund(oid, jwt: c.sellerJwt);
    if (refundShipped.ok && refundShipped.map?['ok'] == true) {
      c.hold(
        id: 'AM4.refund_after_enviado',
        lens: 'AM4',
        severity: 'P0',
        title: 'Seller refund-order após enviado/shipped_at',
        actor: 'seller JWT',
        pre: 'shipped_at set, Stripe capturado',
        repro: 'POST refund-order',
        expected: '403 order_refund_blocked_shipped',
        obtained: refundShipped.brief,
        evidence: await books(),
      );
    } else {
      c.block(
          'AM4.refund_after_enviado', 'AM4', 'refund pós-envio', refundShipped);
    }
  } else {
    c.note('AM2.no_enviado', 'seller não avançou para enviado', envHit.brief,
        lens: 'AM2');
  }

  final entHit = await c.patchOrder(oid, {'status': 'entregue'},
      jwt: c.buyerJwt);
  o = await c.orderRow(oid);
  c.note('AM5.buyer_entregue', 'buyer PATCH entregue', {
    'hit': entHit.brief,
    'status': o?['status'],
  }, lens: 'AM5');

  // Seller força entregue se buyer falhou
  if (o?['status'] == 'enviado') {
    final sEnt = await c.patchOrder(oid, {'status': 'entregue'},
        jwt: c.sellerJwt);
    o = await c.orderRow(oid);
    c.note('AM5.seller_entregue', 'seller PATCH entregue', {
      'hit': sEnt.brief,
      'status': o?['status'],
    }, lens: 'AM5');
  }

  // -------------------------------------------------------------------------
  // AM1/AM7 — abrir disputa em entregue/concluido
  // -------------------------------------------------------------------------
  o = await c.orderRow(oid);
  if (o?['status'] != 'entregue' && o?['status'] != 'concluido') {
    final toEnt = await c.patchOrder(oid, {'status': 'entregue'}, service: true);
    c.note('fixture.force_entregue', 'service_role observação hop entregue',
        toEnt.brief,
        lens: 'AM1');
    o = await c.orderRow(oid);
  }

  final evilPhoto = await c.insertDispute(
    orderId: oid,
    photos: [
      'javascript:alert(1)',
      'https://evil.example/disp.png',
    ],
  );
  if (evilPhoto.ok) {
    c.hold(
      id: 'AM7.dispute_evil_url',
      lens: 'AM7',
      severity: 'P2',
      title: 'INSERT disputa aceita proof_photos javascript:/URL externa',
      actor: 'buyer JWT',
      pre: 'entregue/concluido',
      repro: 'POST order_disputes proof_photos=[javascript:, https://evil]',
      expected: '42501 / URL deny',
      obtained: evilPhoto.brief,
    );
  } else {
    c.block('AM7.dispute_evil_url', 'AM7', 'evil proof insert', evilPhoto);
  }

  final disp = await c.insertDispute(orderId: oid);
  o = await c.orderRow(oid);
  c.note('AM1.dispute_insert', 'POST order_disputes (limpo)', {
    'hit': disp.brief,
    'order_status': o?['status'],
  }, lens: 'AM1');

  String? did = disp.firstId;
  if (did == null && !disp.ok) {
    final listed = await c.rest(
      'GET',
      'order_disputes?order_id=eq.$oid&select=id,status,buyer_id,proof_photos,seller_refund_percent,return_label_url',
      service: true,
    );
    did = listed.firstId;
    c.note('AM1.dispute_list', 'disputas existentes', listed.brief, lens: 'AM1');
  }

  if (did != null) {
    final b2read = await c.rest(
      'GET',
      'order_disputes?id=eq.$did&select=id,status,description,proof_photos,buyer_id',
      jwt: c.buyer2Jwt,
    );
    final rows = b2read.list;
    if (b2read.ok && rows.isNotEmpty) {
      c.hold(
        id: 'AM7.b2_read_dispute',
        lens: 'AM7',
        severity: 'P1',
        title: '2.º buyer lê disputa alheia',
        actor: 'buyer2 JWT',
        pre: 'disputa B1',
        repro: 'GET order_disputes?id=eq',
        expected: '[]',
        obtained: b2read.brief,
      );
    } else {
      c.block('AM7.b2_read_dispute', 'AM7', 'B2 lê disputa', b2read);
    }

    final s2read = await c.rest(
      'GET',
      'order_disputes?id=eq.$did&select=id,status,description',
      jwt: c.seller2Jwt,
    );
    if (s2read.ok && s2read.list.isNotEmpty) {
      c.hold(
        id: 'AM7.s2_read_dispute',
        lens: 'AM7',
        severity: 'P1',
        title: '2.º seller lê disputa alheia',
        actor: 'seller2 JWT',
        pre: 'disputa B1/S1',
        repro: 'GET order_disputes',
        expected: '[]',
        obtained: s2read.brief,
      );
    } else {
      c.block('AM7.s2_read_dispute', 'AM7', 'S2 lê disputa', s2read);
    }

    // Seller fecha resolvida (clássico — block esperado)
    final close = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {'status': 'resolvida', 'current_turn': 'administracao'},
    );
    final dAfterClose = await c.rest(
      'GET',
      'order_disputes?id=eq.$did&select=id,status,current_turn',
      service: true,
    );
    if ('${dAfterClose.map?['status']}' == 'resolvida') {
      c.hold(
        id: 'AM1.seller_close_resolvida',
        lens: 'AM1',
        severity: 'P1',
        title: 'Seller PATCH disputa status=resolvida',
        actor: 'seller JWT',
        pre: 'disputa aberta',
        repro: 'PATCH order_disputes status=resolvida',
        expected: 'status permanece aberta',
        obtained: {
          'hit': close.brief,
          'after': dAfterClose.map,
        },
      );
    } else {
      c.block('AM1.seller_close_resolvida', 'AM1', 'seller fecha resolvida', {
        'hit': close.brief,
        'status': dAfterClose.map?['status'],
      });
    }

    final labelEvil = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {'return_label_url': 'https://evil.example/label.pdf'},
    );
    final dLabel = await c.rest(
      'GET',
      'order_disputes?id=eq.$did&select=id,return_label_url',
      service: true,
    );
    final lab = '${dLabel.map?['return_label_url'] ?? ''}';
    if (lab.contains('evil.example')) {
      c.hold(
        id: 'AM6.return_label_evil',
        lens: 'AM6',
        severity: 'P2',
        title: 'Seller grava return_label_url externa',
        actor: 'seller JWT',
        pre: 'disputa aberta',
        repro: 'PATCH return_label_url=https://evil.example/label.pdf',
        expected: '42501 dispute_return_label_url_denied',
        obtained: {'hit': labelEvil.brief, 'url': lab},
      );
    } else {
      c.block('AM6.return_label_evil', 'AM6', 'label URL externa', {
        'hit': labelEvil.brief,
        'url': lab,
      });
    }

    // AM7 replies: evil insert + PATCH
    final replyEvil = await c.rest('POST', 'order_dispute_replies',
        jwt: c.buyerJwt,
        body: {
          'dispute_id': did,
          'sender_id': c.buyerId,
          'message': 'RTAM reply',
          'proof_photos': ['https://evil.example/r.png', 'javascript:x'],
        });
    if (replyEvil.ok) {
      c.hold(
        id: 'AM7.reply_evil_insert',
        lens: 'AM7',
        severity: 'P2',
        title: 'INSERT reply proof_photos URL arbitrária',
        actor: 'buyer JWT',
        pre: 'disputa aberta',
        repro: 'POST order_dispute_replies proof_photos evil',
        expected: '42501 dispute_proof_url_denied',
        obtained: replyEvil.brief,
      );
    } else {
      c.block('AM7.reply_evil_insert', 'AM7', 'reply evil insert', replyEvil);
    }

    final replyOk = await c.rest('POST', 'order_dispute_replies',
        jwt: c.buyerJwt,
        body: {
          'dispute_id': did,
          'sender_id': c.buyerId,
          'message': 'RTAM reply limpo',
          'proof_photos': <String>[],
        });
    final rid = replyOk.firstId;
    c.note('AM7.reply_ok', 'reply limpo', replyOk.brief, lens: 'AM7');
    if (rid != null) {
      final patchReply = await c.rest(
        'PATCH',
        'order_dispute_replies?id=eq.$rid',
        jwt: c.buyerJwt,
        body: {
          'proof_photos': ['javascript:alert(1)', 'https://evil.example/p.png'],
        },
      );
      final afterReply = await c.rest(
        'GET',
        'order_dispute_replies?id=eq.$rid&select=id,proof_photos',
        service: true,
      );
      final photos = '${afterReply.map?['proof_photos']}';
      if (photos.contains('evil') || photos.contains('javascript')) {
        c.hold(
          id: 'AM7.reply_patch_bypass',
          lens: 'AM7',
          severity: 'P2',
          title: 'PATCH reply prova: trigger só no INSERT — URL arbitrária grava',
          actor: 'buyer JWT',
          pre: 'reply inserido limpo',
          repro: 'PATCH order_dispute_replies proof_photos=[javascript:, evil]',
          expected: 'RLS recusa UPDATE ou URL deny',
          obtained: {'hit': patchReply.brief, 'photos': photos},
        );
      } else {
        c.block('AM7.reply_patch_bypass', 'AM7', 'PATCH reply fotos', {
          'hit': patchReply.brief,
          'photos': photos,
        });
      }
    }

    // Storage: buyer upload + S2 / B2 read folder
    final upPath =
        'order_disputes/${c.buyerId}/$oid-rtam.png';
    final up = await c.storage(
      'POST',
      'object/fleaber_private/$upPath',
      jwt: c.buyerJwt,
      bytes: <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A],
      contentType: 'image/png',
    );
    c.note('AM7.storage_up', 'upload disputa B1', up.brief, lens: 'AM7');

    final b2dl = await c.storage(
      'GET',
      'object/fleaber_private/$upPath',
      jwt: c.buyer2Jwt,
    );
    if (b2dl.status == 200) {
      c.hold(
        id: 'AM7.b2_storage_read',
        lens: 'AM7',
        severity: 'P1',
        title: '2.º buyer descarrega prova de disputa alheia no storage',
        actor: 'buyer2 JWT',
        pre: 'ficheiro order_disputes/B1/…',
        repro: 'GET storage fleaber_private/order_disputes/B1/…',
        expected: '400/403',
        obtained: b2dl.brief,
      );
    } else {
      c.block('AM7.b2_storage_read', 'AM7', 'B2 storage', b2dl);
    }

    // Seller2 (sem order com B1) vs pasta B1
    final s2dl = await c.storage(
      'GET',
      'object/fleaber_private/$upPath',
      jwt: c.seller2Jwt,
    );
    if (s2dl.status == 200) {
      c.hold(
        id: 'AM7.s2_storage_read',
        lens: 'AM7',
        severity: 'P1',
        title: 'Seller alheio lê provas de disputa no storage',
        actor: 'seller2 JWT',
        pre: 'S2 sem encomenda com B1',
        repro: 'GET storage order_disputes/B1/…',
        expected: '403',
        obtained: s2dl.brief,
      );
    } else {
      c.block('AM7.s2_storage_read', 'AM7', 'S2 storage', s2dl);
    }

    // Path traversal: B2 faz upload na pasta de B1
    final hijack = await c.storage(
      'POST',
      'object/fleaber_private/order_disputes/${c.buyerId}/hijack-rtam.bin',
      jwt: c.buyer2Jwt,
      bytes: [1, 2, 3, 4],
      contentType: 'application/octet-stream',
    );
    if (hijack.status == 200 || hijack.ok) {
      c.hold(
        id: 'AM7.storage_path_hijack',
        lens: 'AM7',
        severity: 'P1',
        title: 'B2 escreve no prefixo order_disputes/{B1}/',
        actor: 'buyer2 JWT',
        pre: 'pasta B1',
        repro: 'POST storage order_disputes/B1/hijack',
        expected: '403 (só own uid)',
        obtained: hijack.brief,
      );
    } else {
      c.block('AM7.storage_path_hijack', 'AM7', 'hijack path B1', hijack);
    }
  }

  // Dispute aberta NÃO congela FSM se buyer não hoppar pedido_devolucao
  o = await c.orderRow(oid);
  final concWithDisp = await c.patchOrder(oid, {'status': 'concluido'},
      jwt: c.buyerJwt);
  o = await c.orderRow(oid);
  c.note('AM5.concluido_com_disputa', 'buyer concluido com disputa aberta', {
    'hit': concWithDisp.brief,
    'status': o?['status'],
  }, lens: 'AM5');

  final rel = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': oid},
    jwt: c.buyerJwt,
  );
  final wRel = await c.wallets();
  final oRel = await c.orderRow(oid);
  final released = oRel?['wallet_release_processed_at'] != null;
  final dW = (wRel['seller'] ?? 0) - (wallets0['seller'] ?? 0);
  if (released && dW > 0) {
    c.hold(
      id: 'AM5.release_com_disputa',
      lens: 'AM5',
      severity: 'P0',
      title: 'Release carteira vendedor com disputa aberta',
      actor: 'buyer JWT',
      pre: 'disputa não recusada/resolvida; concluido',
      repro: 'rpc batata_release_seller_wallet_for_order',
      expected: 'false, sem Δwallet, flag null',
      obtained: {
        'rpc': rel.brief,
        'released': released,
        'dSeller': dW,
        'order': oRel,
      },
    );
  } else {
    c.block('AM5.release_com_disputa', 'AM5', 'release com disputa', {
      'rpc': rel.brief,
      'released': released,
      'dSeller': dW,
    });
  }

  final refundOpen = await c.refund(oid, jwt: c.sellerJwt);
  if (refundOpen.ok && refundOpen.map?['ok'] == true) {
    c.hold(
      id: 'AM4.refund_open_dispute',
      lens: 'AM4',
      severity: 'P0',
      title: 'refund-order com disputa aberta',
      actor: 'seller JWT',
      pre: 'disputa aberta, shipped ou não',
      repro: 'POST refund-order',
      expected: '403 open_dispute ou shipped',
      obtained: refundOpen.brief,
      evidence: await books(),
    );
  } else {
    c.block('AM4.refund_open_dispute', 'AM4', 'refund c/ disputa', refundOpen);
  }

  // -------------------------------------------------------------------------
  // AM3 — hop devolução seller → devolvida → stock restore sem refund
  // -------------------------------------------------------------------------
  final ped = await c.patchOrder(oid, {'status': 'pedido_devolucao'},
      jwt: c.buyerJwt);
  o = await c.orderRow(oid);
  c.note('AM3.pedido_devolucao', 'buyer PATCH pedido_devolucao', {
    'hit': ped.brief,
    'status': o?['status'],
  }, lens: 'AM3');

  // Seller tenta voltar a enviado/concluido
  final backEnv = await c.patchOrder(oid, {'status': 'enviado'},
      jwt: c.sellerJwt);
  final backConc = await c.patchOrder(oid, {'status': 'concluido'},
      jwt: c.sellerJwt);
  o = await c.orderRow(oid);
  if (o?['status'] == 'enviado' || o?['status'] == 'concluido') {
    c.hold(
      id: 'AM2.seller_unreturn',
      lens: 'AM2',
      severity: 'P1',
      title: 'Seller sai de pedido_devolucao para enviado/concluido',
      actor: 'seller JWT',
      pre: 'pedido_devolucao + disputa',
      repro: 'PATCH status=enviado|concluido',
      expected: '42501 order_return_in_progress',
      obtained: {
        'backEnv': backEnv.brief,
        'backConc': backConc.brief,
        'status': o?['status'],
      },
    );
  } else {
    c.block('AM2.seller_unreturn', 'AM2', 'seller hop fora da devolução', {
      'backEnv': backEnv.brief,
      'backConc': backConc.brief,
      'status': o?['status'],
    });
  }

  final qtyBeforeReturn = (await c.productRow(pid))?['quantity'];
  final appliedBefore = (await c.orderRow(oid))?['stock_units_applied'];
  final emDev = await c.patchOrder(oid, {'status': 'em_devolucao'},
      jwt: c.sellerJwt);
  final devEnt = await c.patchOrder(oid, {'status': 'devolucao_entregue'},
      jwt: c.sellerJwt);
  final devida = await c.patchOrder(oid, {'status': 'devolvida'},
      jwt: c.sellerJwt);
  final afterDev = await books();
  c.note('AM3.seller_return_chain', 'seller em_devolucao→devolucao_entregue→devolvida', {
    'emDev': emDev.brief,
    'devEnt': devEnt.brief,
    'devolvida': devida.brief,
    'after': afterDev,
    'qty_before': qtyBeforeReturn,
    'applied_before': appliedBefore,
  }, lens: 'AM3');

  final oDev = afterDev['order'] as Map?;
  final pDev = afterDev['product'] as Map?;
  final stDev = '${oDev?['status']}';
  final qtyAfter = pDev?['quantity'];
  final appliedAfter = oDev?['stock_units_applied'];
  final refundId = '${oDev?['stripe_refund_id'] ?? ''}';
  final w1 = afterDev['wallets'] as Map?;
  final dBuyer = ((w1?['buyer'] ?? 0) as num) - (wallets0['buyer'] ?? 0);
  final dSeller = ((w1?['seller'] ?? 0) as num) - (wallets0['seller'] ?? 0);

  final stockRestored = appliedBefore != null &&
      (appliedBefore as num) > 0 &&
      (appliedAfter == null || (appliedAfter is num && appliedAfter <= 0));
  final qtyUp = (qtyAfter is num) &&
      (qtyBeforeReturn is num) &&
      qtyAfter > qtyBeforeReturn;

  if (stDev == 'devolvida' &&
      (stockRestored || qtyUp) &&
      refundId.isEmpty &&
      dBuyer <= 0) {
    c.hold(
      id: 'AM3.devolvida_stock_sem_refund',
      lens: 'AM3',
      severity: 'P1',
      title:
          'Seller força cadeia de devolução até devolvida: stock restaura sem refund Stripe/wallet',
      actor: 'seller JWT',
      pre: 'pago capturado + disputa + pedido_devolucao; qty=$qtyBeforeReturn applied=$appliedBefore',
      repro:
          'PATCH em_devolucao → devolucao_entregue → devolvida (JWT vendedor, sem etiqueta/receção real)',
      expected:
          'hop recusado sem prova de devolução / stock permanece claimado até refund',
      obtained: {
        'status': stDev,
        'qty_before': qtyBeforeReturn,
        'qty_after': qtyAfter,
        'applied_before': appliedBefore,
        'applied_after': appliedAfter,
        'stripe_refund_id': refundId,
        'dBuyer': dBuyer,
        'dSeller': dSeller,
      },
      evidence: afterDev,
    );
  } else {
    c.note('AM3.devolvida_outcome', 'cadeia devolução resultado', {
      'status': stDev,
      'qty_before': qtyBeforeReturn,
      'qty_after': qtyAfter,
      'applied_before': appliedBefore,
      'applied_after': appliedAfter,
      'refund': refundId,
      'dBuyer': dBuyer,
    }, lens: 'AM3');
  }

  // AM4 — refund após devolvida (gate terminal ok:true)
  final refundDev = await c.refund(oid, jwt: c.sellerJwt);
  final afterRefundDev = await books();
  c.note('AM4.refund_devolvida', 'refund-order pós-devolvida', {
    'hit': refundDev.brief,
    'after': afterRefundDev,
  }, lens: 'AM4');
  final oRd = afterRefundDev['order'] as Map?;
  final pRd = afterRefundDev['product'] as Map?;
  final qtyRd = pRd?['quantity'];
  final doubleStock = (qtyAfter is num) &&
      (qtyRd is num) &&
      qtyRd > qtyAfter;
  if (refundDev.ok &&
      refundDev.map?['ok'] == true &&
      (stockRestored || qtyUp) &&
      doubleStock) {
    c.hold(
      id: 'AM3.double_restore_refund',
      lens: 'AM3',
      severity: 'P0',
      title: 'devolvida restaurou stock e refund-order restaurou outra vez',
      actor: 'seller JWT',
      pre: 'devolvida com stock já restored',
      repro: 'POST refund-order',
      expected: 'refund sem segundo restore (stock_units_applied já null)',
      obtained: {
        'refund': refundDev.brief,
        'qty_devolvida': qtyAfter,
        'qty_refund': qtyRd,
      },
      evidence: afterRefundDev,
    );
  } else if (refundDev.ok && refundDev.map?['ok'] == true && refundId.isEmpty) {
    // Stripe refund after keeping stock restored — money back + stock back
    // while original buyer may still "have" item. If stock was restored
    // without buyer refund before, now both happen: expected-ish if seller
    // chooses to refund. Not P0 unless double credit.
    final w2 = afterRefundDev['wallets'] as Map?;
    final dB2 = ((w2?['buyer'] ?? 0) as num) - (wallets0['buyer'] ?? 0);
    c.note('AM4.refund_devolvida_ok', 'Stripe refund em devolvida', {
      'dBuyer': dB2,
      'qty': qtyRd,
      'stripe_refund': oRd?['stripe_refund_id'],
    }, lens: 'AM4');
  }

  // AM8 — 2.ª venda no SKU restaurado
  final avail = await c.stockCheck(pid, need: 1);
  c.note('AM8.avail', 'stock disponível após cadeia', avail.brief, lens: 'AM8');
  final availOk = avail.map?['ok'] == true;
  if (availOk && (stockRestored || qtyUp)) {
    final oid2 = await c.insertOrder(
      productId: pid,
      buyer: c.buyer2Id,
      jwt: c.buyer2Jwt,
      price: 5.9,
    );
    if (oid2 != null) {
      final ck = await c.checkout(
        orderId: oid2,
        jwt: c.buyer2Jwt,
        buyer: c.buyer2Id,
        productId: pid,
        seller: c.sellerId,
        amount: 5.9,
      );
      c.note('AM8.second_checkout', 'B2 checkout SKU restaurado', {
        'order': oid2,
        'ck': ck.brief,
        'amount': ck.amountTotal,
        'session': ck.sessionId,
      }, lens: 'AM8');
      if (ck.ok && (ck.sessionId != null || ck.amountTotal != null)) {
        c.hold(
          id: 'AM8.second_sale_after_phantom_restore',
          lens: 'AM8',
          severity: 'P1',
          title:
              'Após devolvida sem prova, o SKU volta a checkout (2.ª captura possível no mesmo artigo)',
          actor: 'buyer2 JWT',
          pre:
              'order1 Stripe capturado + stock restored em devolvida sem refund prévio',
          repro: 'POST orders B2 + create-payment-intent no mesmo product_id',
          expected: 'available=0 enquanto a 1.ª captura não for refunded',
          obtained: {
            'avail': avail.brief,
            'checkout': ck.brief,
            'session': ck.sessionId,
            'amount': ck.amountTotal,
            'order1_refund': oRd?['stripe_refund_id'] ?? oDev?['stripe_refund_id'],
          },
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // AM4 — parcial disputa (oferta seller) em pago novo
  // -------------------------------------------------------------------------
  final paid2 = await c.payToPago(lens: 'AM4', initialQty: 1);
  if (paid2 != null) {
    final oidP = paid2.oid;
    await c.patchOrder(oidP, {'status': 'enviado'}, jwt: c.sellerJwt);
    await c.patchOrder(oidP, {'status': 'entregue'}, jwt: c.buyerJwt);
    final d2 = await c.insertDispute(orderId: oidP);
    final did2 = d2.firstId;
    c.note('AM4.disp2', 'disputa order2', d2.brief, lens: 'AM4');
    if (did2 != null) {
      final offer = await c.rest(
        'PATCH',
        'order_disputes?id=eq.$did2',
        jwt: c.sellerJwt,
        body: {
          'seller_offer_type': 'partial_refund',
          'seller_refund_percent': 40,
          'status': 'respondida_vendedor',
        },
      );
      c.note('AM4.offer40', 'seller oferta 40%', offer.brief, lens: 'AM4');
      final wBefore = await c.wallets();
      final part = await c.rpc(
        'batata_process_partial_refund_dispute',
        {'p_order_id': oidP, 'p_refund_percent': 99},
        jwt: c.buyerJwt,
      );
      final wAfter = await c.wallets();
      final oP = await c.orderRow(oidP);
      c.note('AM4.partial_rpc', 'partial refund disputa', {
        'rpc': part.brief,
        'dBuyer': (wAfter['buyer'] ?? 0) - (wBefore['buyer'] ?? 0),
        'dSeller': (wAfter['seller'] ?? 0) - (wBefore['seller'] ?? 0),
        'order': oP,
      }, lens: 'AM4');
      // TU: pós-envio exige Stripe — esperado bloquear. Finding se creditar.
      final credited = ((wAfter['buyer'] ?? 0) - (wBefore['buyer'] ?? 0)) > 0;
      if (credited && '${oP?['stripe_refund_id'] ?? ''}'.isEmpty) {
        c.hold(
          id: 'AM4.partial_wallet_pos_envio',
          lens: 'AM4',
          severity: 'P0',
          title:
              'Partial refund disputa credita wallet pós-envio sem refund Stripe',
          actor: 'buyer JWT',
          pre: 'enviado/entregue + oferta 40%',
          repro: 'rpc batata_process_partial_refund_dispute (p_refund_percent ignorado)',
          expected: '42501 dispute_partial_refund_requires_stripe',
          obtained: {
            'rpc': part.brief,
            'dBuyer': (wAfter['buyer'] ?? 0) - (wBefore['buyer'] ?? 0),
            'dSeller': (wAfter['seller'] ?? 0) - (wBefore['seller'] ?? 0),
            'stripe_refund': oP?['stripe_refund_id'],
          },
        );
      } else {
        c.block('AM4.partial_wallet_pos_envio', 'AM4', 'parcial pós-envio',
            part);
      }

      final sellerPart = await c.rpc(
        'batata_process_partial_refund_dispute',
        {'p_order_id': oidP},
        jwt: c.sellerJwt,
      );
      if (sellerPart.ok && sellerPart.body != 'false') {
        final looksAllowed = sellerPart.status < 400 &&
            !sellerPart.brief.contains('not_allowed') &&
            !sellerPart.brief.contains('42501');
        if (looksAllowed && sellerPart.body == 'true') {
          c.hold(
            id: 'AM4.seller_calls_partial',
            lens: 'AM4',
            severity: 'P1',
            title: 'Seller executa batata_process_partial_refund_dispute',
            actor: 'seller JWT',
            pre: 'RPC buyer-only',
            repro: 'rpc batata_process_partial_refund_dispute',
            expected: '42501 not_allowed',
            obtained: sellerPart.brief,
          );
        } else {
          c.block('AM4.seller_calls_partial', 'AM4', 'seller partial rpc',
              sellerPart);
        }
      } else {
        c.block(
            'AM4.seller_calls_partial', 'AM4', 'seller partial rpc', sellerPart);
      }
    }

    // Buyer chama refund-order (não é seller)
    final bRefund = await c.refund(oidP, jwt: c.buyerJwt);
    if (bRefund.ok && bRefund.map?['ok'] == true) {
      c.hold(
        id: 'AM4.buyer_refund_order',
        lens: 'AM4',
        severity: 'P0',
        title: 'Buyer chama refund-order (seller-only) e anula Stripe',
        actor: 'buyer JWT',
        pre: 'order pago B1',
        repro: 'POST refund-order',
        expected: '403 Sem permissão',
        obtained: bRefund.brief,
      );
    } else {
      c.block('AM4.buyer_refund_order', 'AM4', 'buyer refund-order', bRefund);
    }
  }

  // AM5 — buyer pedido_devolucao → concluido (reabre) com disputa
  if (paid2 != null) {
    final oidR = paid2.oid;
    await c.patchOrder(oidR, {'status': 'pedido_devolucao'}, jwt: c.buyerJwt);
    final reopen = await c.patchOrder(oidR, {'status': 'concluido'},
        jwt: c.buyerJwt);
    final oR = await c.orderRow(oidR);
    c.note('AM5.reopen_concluido', 'pedido_devolucao→concluido', {
      'hit': reopen.brief,
      'status': oR?['status'],
    }, lens: 'AM5');
    if (oR?['status'] == 'concluido') {
      final rel2 = await c.rpc(
        'batata_release_seller_wallet_for_order',
        {'p_order_id': oidR},
        jwt: c.buyerJwt,
      );
      final oR2 = await c.orderRow(oidR);
      if (oR2?['wallet_release_processed_at'] != null) {
        c.hold(
          id: 'AM5.reopen_then_release',
          lens: 'AM5',
          severity: 'P0',
          title:
              'Buyer reabre concluido a partir de pedido_devolucao e faz release com disputa viva',
          actor: 'buyer JWT',
          pre: 'disputa aberta',
          repro: 'PATCH concluido; rpc release',
          expected: 'release recusa disputa aberta; hop recusado',
          obtained: {
            'reopen': reopen.brief,
            'rpc': rel2.brief,
            'release_at': oR2?['wallet_release_processed_at'],
          },
        );
      } else {
        c.block('AM5.reopen_then_release', 'AM5', 'reopen+release', {
          'reopen': reopen.brief,
          'rpc': rel2.brief,
        });
      }
    }
  }

  await c.dumpAll('pass1.json');
  stdout.writeln(
      'DONE findings=${c.findings.length} blocked=${c.blocked.length} notes=${c.notes.length}');
}
