/// RED TEAM CEGO AS — pass 1. Staging only. Não corrige.
/// Lentes AS1–AS8. Não redescobrir exactos AM3/AM4/AM7/AM3-P3.
import 'dart:io';
import '_rtas.dart';

Future<void> main() async {
  final c = Rtas.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.note('actors', 'JWT B1/S1/B2/S2', {
    'b1': c.buyerId,
    's1': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
  });

  Future<Map<String, dynamic>> books(String oid, String pid) async => {
        'order': await c.orderRow(oid),
        'product': await c.productRow(pid),
        'wallets': await c.wallets(),
        'stock': (await c.stockCheck(pid)).map,
      };

  Future<({String oid, String pid, String? pi})> mustPay(String lens) async {
    final paid = await c.payToPago(lens: lens, initialQty: 1);
    if (paid == null) {
      throw StateError('setup_paid_order failed $lens');
    }
    return paid;
  }

  // =========================================================================
  // AS1 — disputa vs FSM (estados errados / fecho JWT)
  // =========================================================================
  final p1 = await mustPay('AS1');
  var o = await c.orderRow(p1.oid);
  c.note('AS1.fixture', 'pago Stripe TEST', {
    'oid': p1.oid,
    'pid': p1.pid,
    'status': o?['status'],
    'paid': o?['amount_paid_cents'],
    'pi': p1.pi,
  }, lens: 'AS1');

  Future<void> expectBlock(
    String id,
    String lens,
    String title,
    HttpHit hit,
  ) async {
    if (hit.ok) {
      c.hold(
        id: id,
        lens: lens,
        severity: 'P1',
        title: title,
        actor: 'JWT',
        pre: 'ver id',
        repro: id,
        expected: '401/403/empty',
        obtained: hit.brief,
      );
    } else {
      c.block(id, lens, title, hit);
    }
  }

  await expectBlock(
    'AS1.alien_insert',
    'AS1',
    'B2 abre disputa em encomenda B1 (verify)',
    await c.insertDispute(
      orderId: p1.oid,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    ),
  );
  await expectBlock(
    'AS1.dispute_on_pago',
    'AS1',
    'Buyer abre disputa em pago',
    await c.insertDispute(orderId: p1.oid),
  );
  await expectBlock(
    'AS1.seller_insert',
    'AS1',
    'Seller insere disputa',
    await c.insertDispute(
      orderId: p1.oid,
      jwt: c.sellerJwt,
      buyer: c.sellerId,
    ),
  );

  final insertResolvida = await c.insertDispute(
    orderId: p1.oid,
    status: 'resolvida',
  );
  if (insertResolvida.ok) {
    final st = insertResolvida.map?['status'];
    if ('$st' == 'resolvida') {
      c.hold(
        id: 'AS1.insert_resolvida_persists',
        lens: 'AS1',
        severity: 'P3',
        title: 'INSERT disputa status=resolvida persistiu (AHAM deveria forçar aberta)',
        actor: 'buyer JWT',
        pre: 'pago — insert should fail RLS anyway',
        repro: 'POST order_disputes status=resolvida',
        expected: '403 ou status forçado aberta',
        obtained: insertResolvida.brief,
      );
    } else {
      c.block('AS1.insert_resolvida', 'AS1', 'INSERT resolvida forçado/recusado',
          insertResolvida);
    }
  } else {
    c.block('AS1.insert_resolvida', 'AS1', 'INSERT resolvida recusado (pago)',
        insertResolvida);
  }

  final adminRpc = await c.rpc(
    'batata_admin_resolve_dispute',
    {
      'p_dispute_id': '00000000-0000-0000-0000-000000000001',
      'p_resolution': 'favor_buyer_refund',
      'p_note': 'RTAS',
    },
    jwt: c.buyerJwt,
  );
  final adminBrief = adminRpc.brief.toLowerCase();
  if (adminRpc.ok &&
      !adminBrief.contains('admin') &&
      adminRpc.body != 'false' &&
      adminRpc.body != 'null') {
    c.hold(
      id: 'AS1.admin_rpc',
      lens: 'AS1',
      severity: 'P0',
      title: 'Buyer executa batata_admin_resolve_dispute',
      actor: 'buyer JWT',
      pre: 'não-admin',
      repro: 'rpc batata_admin_resolve_dispute',
      expected: 'admin only / false',
      obtained: adminRpc.brief,
    );
  } else {
    c.block('AS1.admin_rpc', 'AS1', 'admin resolve recusado', adminRpc);
  }

  // Seller pago → entregue (salta enviado) — cronologia mente
  final skipShip = await c.patchOrder(
    p1.oid,
    {'status': 'entregue'},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(p1.oid);
  if (skipShip.ok && o?['status'] == 'entregue') {
    c.hold(
      id: 'AS2.seller_pago_to_entregue',
      lens: 'AS2',
      severity: 'P1',
      title: 'Seller marca entregue a partir de pago sem enviado',
      actor: 'seller JWT',
      pre: 'order.status=pago capturado',
      repro: 'PATCH status=entregue',
      expected: '42501 (só enviado após pago; entregue é do comprador)',
      obtained: {
        'hit': skipShip.brief,
        'status': o?['status'],
        'shipped_at': o?['shipped_at'],
      },
    );
  } else {
    c.block('AS2.seller_pago_to_entregue', 'AS2', 'seller pago→entregue', {
      'hit': skipShip.brief,
      'status': o?['status'],
    });
  }

  // Enviado legítimo
  final toEnv = await c.patchOrder(
    p1.oid,
    {'status': 'enviado'},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(p1.oid);
  c.note('AS2.enviado', 'seller → enviado', {
    'hit': toEnv.brief,
    'status': o?['status'],
    'shipped_at': o?['shipped_at'],
  }, lens: 'AS2');

  final disputeOnEnviado = await c.insertDispute(orderId: p1.oid);
  await expectBlock(
    'AS1.dispute_on_enviado',
    'AS1',
    'Buyer abre disputa em enviado (RLS só entregue/concluido)',
    disputeOnEnviado,
  );

  // Race enviado∥disputa já passou; race entregue∥disputa
  final pRace = await mustPay('AS2');
  await c.patchOrder(pRace.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final raced = await parallel([
    c.patchOrder(pRace.oid, {'status': 'entregue'}, jwt: c.buyerJwt),
    c.insertDispute(orderId: pRace.oid),
  ]);
  final raceOrder = await c.orderRow(pRace.oid);
  final raceDisp = await c.rest(
    'GET',
    'order_disputes?order_id=eq.${pRace.oid}&select=id,status',
    service: true,
  );
  c.note('AS2.race_entregue_dispute', 'Future.wait entregue∥POST disputa', {
    'entregue': raced[0].brief,
    'dispute': raced[1].brief,
    'order': raceOrder,
    'disputes': raceDisp.snippet,
  }, lens: 'AS2');
  if (raced[1].ok && raceOrder?['status'] != 'entregue') {
    c.hold(
      id: 'AS2.race_dispute_before_entregue',
      lens: 'AS2',
      severity: 'P1',
      title: 'Race: disputa INSERT 201 sem entregue persistido',
      actor: 'buyer JWT paralelo',
      pre: 'enviado; Future.wait entregue∥disputa',
      repro: 'parallel PATCH entregue + POST order_disputes',
      expected: 'disputa só se status entregue/concluido',
      obtained: {
        'dispute': raced[1].brief,
        'entregue': raced[0].brief,
        'status': raceOrder?['status'],
      },
    );
  }

  // Buyer entregue (caminho feliz) no p1
  if (o?['status'] == 'enviado') {
    await c.patchOrder(p1.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  }
  o = await c.orderRow(p1.oid);

  final dIns = await c.insertDispute(orderId: p1.oid);
  final did = dIns.firstId;
  c.note('AS1.dispute_entregue', 'disputa em entregue', dIns.brief, lens: 'AS1');
  if (!dIns.ok) {
    c.skip('AS1.dispute_entregue', 'AS1', 'não abriu disputa em entregue', dIns);
  }

  if (did != null) {
    // Buyer fecha recusada (auto-absolve seller)
    final recusa = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.buyerJwt,
      body: {'status': 'recusada'},
    );
    final recusaRow = await c.rest(
      'GET',
      'order_disputes?id=eq.$did&select=id,status,current_turn,buyer_decision',
      service: true,
    );
    if (recusa.ok && recusaRow.map?['status'] == 'recusada') {
      c.hold(
        id: 'AS1.buyer_self_recusada',
        lens: 'AS1',
        severity: 'P2',
        title: 'Buyer PATCH disputa → recusada (fecha o slot sem admin)',
        actor: 'buyer JWT',
        pre: 'disputa aberta em entregue',
        repro: 'PATCH order_disputes status=recusada',
        expected: 'terminal só via decisão/admin; recusada não é self-serve',
        obtained: {
          'hit': recusa.brief,
          'row': recusaRow.map,
        },
      );
    } else {
      c.block('AS1.buyer_self_recusada', 'AS1', 'buyer recusada', {
        'hit': recusa.brief,
        'row': recusaRow.map,
      });
    }

    // Reabrir / 2.ª disputa após tentativa recusada
    final d2 = await c.insertDispute(orderId: p1.oid, reason: 'nao_corresponde');
    if (d2.ok) {
      c.note('AS1.second_dispute', '2.ª disputa no mesmo order', d2.brief,
          lens: 'AS1');
    } else {
      c.block('AS1.second_dispute', 'AS1', '2.ª disputa bloqueada', d2);
    }

    final fakeResolve = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.buyerJwt,
      body: {
        'buyer_decision': 'accepted_partial_refund',
        'status': 'resolvida',
      },
    );
    final afterFake = await c.rest(
      'GET',
      'order_disputes?id=eq.$did&select=id,status,buyer_decision,current_turn',
      service: true,
    );
    if (afterFake.map?['status'] == 'resolvida') {
      c.hold(
        id: 'AS1.buyer_resolvida_fake_decision',
        lens: 'AS1',
        severity: 'P1',
        title:
            'Buyer fecha disputa resolvida com buyer_decision=accepted_partial_refund sem RPC de refund',
        actor: 'buyer JWT',
        pre: 'disputa aberta (ou recusada)',
        repro:
            'PATCH buyer_decision=accepted_partial_refund status=resolvida',
        expected: 'resolvida só após dinheiro mover / admin',
        obtained: {
          'hit': fakeResolve.brief,
          'row': afterFake.map,
        },
      );
    } else {
      c.block('AS1.buyer_resolvida_fake_decision', 'AS1',
          'buyer resolvida+decision', {
        'hit': fakeResolve.brief,
        'row': afterFake.map,
      });
    }

    final sellerTurn = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {'current_turn': 'administracao'},
    );
    final turnRow = await c.rest(
      'GET',
      'order_disputes?id=eq.$did&select=id,current_turn,status',
      service: true,
    );
    if (turnRow.map?['current_turn'] == 'administracao' &&
        turnRow.map?['status'] != 'escalada_fleaber' &&
        turnRow.map?['status'] != 'resolvida' &&
        turnRow.map?['status'] != 'recusada') {
      c.hold(
        id: 'AS1.seller_turn_admin',
        lens: 'AS1',
        severity: 'P2',
        title: 'Seller força current_turn=administracao sem escalar',
        actor: 'seller JWT',
        pre: 'disputa não terminal',
        repro: 'PATCH current_turn=administracao',
        expected: 'revertido ao turn anterior',
        obtained: {
          'hit': sellerTurn.brief,
          'row': turnRow.map,
        },
      );
    } else {
      c.block('AS1.seller_turn_admin', 'AS1', 'seller turn admin', {
        'hit': sellerTurn.brief,
        'row': turnRow.map,
      });
    }

    final deliveredAt = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {'return_delivered_at': DateTime.now().toUtc().toIso8601String()},
    );
    final delRow = await c.rest(
      'GET',
      'order_disputes?id=eq.$did&select=id,return_delivered_at',
      service: true,
    );
    if (delRow.map?['return_delivered_at'] != null) {
      c.hold(
        id: 'AS5.seller_fake_return_delivered',
        lens: 'AS5',
        severity: 'P2',
        title: 'Seller grava return_delivered_at sem prova de receção',
        actor: 'seller JWT',
        pre: 'disputa aberta, sem etiqueta/scan',
        repro: 'PATCH return_delivered_at=now()',
        expected: 'campo só via carrier/admin',
        obtained: {
          'hit': deliveredAt.brief,
          'row': delRow.map,
        },
      );
    } else {
      c.block('AS5.seller_fake_return_delivered', 'AS5',
          'return_delivered_at', {
        'hit': deliveredAt.brief,
        'row': delRow.map,
      });
    }

    final pct = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {
        'seller_refund_percent': 200,
        'seller_offer_type': 'partial_refund',
      },
    );
    final pctRow = await c.rest(
      'GET',
      'order_disputes?id=eq.$did&select=id,seller_refund_percent,seller_offer_type',
      service: true,
    );
    final pctN = numOf(pctRow.map?['seller_refund_percent']);
    if (pctN != null && pctN > 100) {
      c.hold(
        id: 'AS4.refund_percent_over_100',
        lens: 'AS4',
        severity: 'P1',
        title: 'seller_refund_percent=200 persistiu',
        actor: 'seller JWT',
        pre: 'disputa aberta',
        repro: 'PATCH seller_refund_percent=200',
        expected: 'CHECK ≤100',
        obtained: {
          'hit': pct.brief,
          'row': pctRow.map,
        },
      );
    } else {
      c.block('AS4.refund_percent_over_100', 'AS4', 'percent>100', {
        'hit': pct.brief,
        'row': pctRow.map,
      });
    }

    // Label URL com prefixo supabase apontando a path alheio
    final evilLabel =
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/chat_media/rtas-evil.pdf';
    final lab = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {'return_label_url': evilLabel},
    );
    final labRow = await c.rest(
      'GET',
      'order_disputes?id=eq.$did&select=id,return_label_url',
      service: true,
    );
    if ('${labRow.map?['return_label_url'] ?? ''}' == evilLabel) {
      c.hold(
        id: 'AS6.label_public_bucket',
        lens: 'AS6',
        severity: 'P2',
        title: 'return_label_url aceita URL supabase public/chat_media',
        actor: 'seller JWT',
        pre: 'disputa aberta',
        repro: 'PATCH return_label_url=…/storage/v1/object/public/chat_media/…',
        expected: 'deny (só etiqueta da encomenda / carrier)',
        obtained: {
          'hit': lab.brief,
          'row': labRow.map,
        },
      );
    } else {
      c.block('AS6.label_public_bucket', 'AS6', 'label public bucket', {
        'hit': lab.brief,
        'url': labRow.map?['return_label_url'],
      });
    }
  }

  // =========================================================================
  // AS7 — provas: XSS prefix, order_proofs raso, path alheio
  // =========================================================================
  final xssUrl =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/x" onerror="alert(1)';
  final xss = await c.insertDispute(
    orderId: p1.oid,
    photos: [xssUrl],
  );
  if (xss.ok) {
    final photos = xss.map?['proof_photos'];
    c.hold(
      id: 'AS7.proof_xss_prefix',
      lens: 'AS7',
      severity: 'P2',
      title: 'proof_photos aceita prefixo supabase + breakout HTML',
      actor: 'buyer JWT',
      pre: 'entregue (ou 2.ª disputa)',
      repro: 'POST proof_photos=["https://…supabase.co/storage/x\\" onerror="alert(1)"]',
      expected: 'dispute_proof_url_denied (allowlist path estrito)',
      obtained: {'hit': xss.brief, 'photos': photos},
    );
  } else {
    c.block('AS7.proof_xss_prefix', 'AS7', 'XSS prefix denied', xss);
  }

  final pubUrl =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/chat_media/rtas.png';
  final pubPhoto = await c.rest(
    'PATCH',
    'order_disputes?order_id=eq.${p1.oid}',
    jwt: c.buyerJwt,
    body: {
      'proof_photos': [pubUrl],
    },
  );
  if (pubPhoto.ok && pubPhoto.body.contains('chat_media')) {
    c.hold(
      id: 'AS7.proof_public_bucket',
      lens: 'AS7',
      severity: 'P2',
      title: 'proof_photos aceita object/public/chat_media (não fleaber_private)',
      actor: 'buyer JWT',
      pre: 'disputa existente',
      repro: 'PATCH proof_photos=[public chat_media URL]',
      expected: 'só fleaber_private/order_disputes/{uid}/{order_id}',
      obtained: pubPhoto.brief,
    );
  } else {
    c.block('AS7.proof_public_bucket', 'AS7', 'public bucket proof', pubPhoto);
  }

  // Upload provas: path raso order_proofs/{buyer}/file (sem order_id)
  const png = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
    0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
    0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
  ];
  final shallowPath =
      'object/fleaber_private/order_proofs/${c.buyerId}/rtas-shallow.png';
  final upShallow = await c.storage(
    'POST',
    shallowPath,
    jwt: c.buyerJwt,
    bytes: png,
    contentType: 'image/png',
  );
  c.note('AS7.upload_shallow', 'upload order_proofs raso', upShallow.brief,
      lens: 'AS7');

  // S2 order paga com B1 para leak S1←S2 proofs
  final paidS2 = await c.e2e('setup_paid_order', {'initial_qty': 1},
      seller: c.seller2Id, buyer: c.buyerId);
  final oidS2 = c.parseE2eOrderId(paidS2);
  final pidS2 = c.parseE2eProductId(paidS2);
  if (pidS2 != null) c.createdProductIds.add(pidS2);
  if (oidS2 != null) c.createdOrderIds.add(oidS2);
  c.note('AS7.s2_paid', 'B1–S2 pago', paidS2.brief, lens: 'AS7');

  if (oidS2 != null) {
    final deepS2 =
        'object/fleaber_private/order_proofs/${c.buyerId}/$oidS2/rtas-s2-secret.png';
    final upS2 = await c.storage(
      'POST',
      deepS2,
      jwt: c.buyerJwt,
      bytes: png,
      contentType: 'image/png',
    );
    c.note('AS7.upload_s2_proof', 'B1 upload prova S2', upS2.brief, lens: 'AS7');

    final s1ReadDeep = await c.storage(
      'GET',
      deepS2,
      jwt: c.sellerJwt,
    );
    if (s1ReadDeep.ok) {
      c.hold(
        id: 'AS7.s1_reads_s2_order_proofs',
        lens: 'AS7',
        severity: 'P1',
        title: 'S1 lê order_proofs de encomenda B1–S2',
        actor: 'seller JWT S1',
        pre: 'ficheiro order_proofs/{B1}/{orderS2}/…',
        repro: 'GET storage fleaber_private/order_proofs/{B1}/{orderS2}/…',
        expected: '403 — só o vendedor daquela encomenda',
        obtained: s1ReadDeep.brief,
      );
    } else {
      c.block('AS7.s1_reads_s2_order_proofs', 'AS7',
          'S1 não lê prova profunda S2', s1ReadDeep);
    }

    final s1ReadShallow = await c.storage(
      'GET',
      shallowPath,
      jwt: c.sellerJwt,
    );
    if (s1ReadShallow.ok) {
      c.hold(
        id: 'AS7.s1_reads_shallow_order_proofs',
        lens: 'AS7',
        severity: 'P1',
        title:
            'S1 lê order_proofs/{B1}/ficheiro raso (policy sem order_id, 1 nível)',
        actor: 'seller JWT S1',
        pre: 'B1–S1 têm histórico; ficheiro order_proofs/{B1}/rtas-shallow.png',
        repro: 'GET storage order_proofs/{B1}/rtas-shallow.png JWT=S1',
        expected: '403 — path raso não é da encomenda S1',
        obtained: s1ReadShallow.brief,
      );
    } else {
      c.block('AS7.s1_reads_shallow_order_proofs', 'AS7',
          'S1 shallow order_proofs', s1ReadShallow);
    }

    // Dispute file WITH order_id (AM7 exact closed — verify only)
    await c.patchOrder(oidS2, {'status': 'enviado'}, jwt: c.seller2Jwt);
    await c.patchOrder(oidS2, {'status': 'entregue'}, jwt: c.buyerJwt);
    final dS2 = await c.insertDispute(orderId: oidS2);
    final pathDisp =
        'object/fleaber_private/order_disputes/${c.buyerId}/$oidS2/rtas-disp.png';
    final upDisp = await c.storage(
      'POST',
      pathDisp,
      jwt: c.buyerJwt,
      bytes: png,
      contentType: 'image/png',
    );
    final s1Disp = await c.storage('GET', pathDisp, jwt: c.sellerJwt);
    final s2Disp = await c.storage('GET', pathDisp, jwt: c.seller2Jwt);
    c.note('AS7.am7_verify', 'S1 vs S2 lê disputa B1–S2 (AHAM path order_id)', {
      'upload': upDisp.brief,
      's1': s1Disp.brief,
      's2': s2Disp.brief,
      'dispute': dS2.brief,
    }, lens: 'AS7');
    if (s1Disp.ok) {
      c.hold(
        id: 'AS7.am7_regress_s1_reads_dispute',
        lens: 'AS7',
        severity: 'P1',
        title: 'REGRESSÃO AHAM: S1 volta a ler provas disputa B1–S2',
        actor: 'seller JWT S1',
        pre: 'path com order_id S2',
        repro: 'GET order_disputes/{B1}/{orderS2}/…',
        expected: '403 após AHAM',
        obtained: s1Disp.brief,
      );
    } else {
      c.block('AS7.am7_verify_closed', 'AS7', 'AHAM AM7 continua fechado',
          {'s1': s1Disp.brief, 's2': s2Disp.brief});
    }
  }

  // =========================================================================
  // AS3 / AS4 / AS8 — cadeia devolução + stock + refund (NÃO o exacto AM3)
  // =========================================================================
  final pRet = await mustPay('AS3');
  final oid = pRet.oid;
  final pid = pRet.pid;
  final w0 = await c.wallets();
  await c.patchOrder(oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  final dRet = await c.insertDispute(orderId: oid);
  final didRet = dRet.firstId;

  final hopPedido =
      await c.patchOrder(oid, {'status': 'pedido_devolucao'}, jwt: c.buyerJwt);
  var bPedido = await books(oid, pid);
  c.note('AS3.pedido', 'após pedido_devolucao', {
    'hit': hopPedido.brief,
    'books': bPedido,
  }, lens: 'AS3');

  // 2.º checkout DURANTE pedido_devolucao (stock ainda claimado?)
  final availPedido = await c.stockCheck(pid);
  final b2Order = await c.insertOrderHit(
    productId: pid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
    price: 5.0,
  );
  c.note('AS3.second_hold_pedido', 'B2 hold no mesmo SKU em pedido_devolucao', {
    'avail': availPedido.brief,
    'order': b2Order.brief,
    'qty': (bPedido['product'] as Map?)?['quantity'],
  }, lens: 'AS3');

  // Shortcut: pedido_devolucao → disputa_devolucao_vendedor → devolvida
  final hopShortcut = await c.patchOrder(
    oid,
    {'status': 'disputa_devolucao_vendedor'},
    jwt: c.sellerJwt,
  );
  final hopDevShort = await c.patchOrder(
    oid,
    {'status': 'devolvida'},
    jwt: c.sellerJwt,
  );
  var bShort = await books(oid, pid);
  c.note('AS3.shortcut', 'salta em_devolucao/devolucao_entregue', {
    'to_disputa_dev': hopShortcut.brief,
    'to_devolvida': hopDevShort.brief,
    'books': bShort,
  }, lens: 'AS3');
  final stShort = (bShort['order'] as Map?)?['status'];
  final qtyShort = (bShort['product'] as Map?)?['quantity'];
  final appliedShort = (bShort['order'] as Map?)?['stock_units_applied'];
  final refundShort = (bShort['order'] as Map?)?['stripe_refund_id'];
  if (stShort == 'devolvida' &&
      (hopPedido.ok) &&
      '${refundShort ?? ''}'.isEmpty) {
    if (qtyShort == 1 || appliedShort == null) {
      // Exact AM3 would be stock restore. If restored → REGRESSION.
      c.hold(
        id: 'AS3.am3_regress_stock_on_devolvida',
        lens: 'AS3',
        severity: 'P1',
        title: 'REGRESSÃO AHAM: devolvida restaurou stock sem stripe_refund_id',
        actor: 'seller JWT',
        pre: 'captura viva, hops até devolvida',
        repro: 'PATCH disputa_devolucao_vendedor → devolvida',
        expected: 'qty continua 0, stock_units_applied set',
        obtained: bShort,
      );
    } else {
      c.block(
        'AS3.am3_verify_no_restore',
        'AS3',
        'AHAM: stock NÃO restaura em devolvida sem refund',
        {
          'qty': qtyShort,
          'applied': appliedShort,
          'shortcut_ok': hopDevShort.ok,
        },
      );
    }
    if (hopShortcut.ok && hopDevShort.ok) {
      c.hold(
        id: 'AS3.skip_return_hops',
        lens: 'AS3',
        severity: 'P2',
        title:
            'Seller salto pedido_devolucao → disputa_devolucao_vendedor → devolvida (sem em_devolucao nem receção)',
        actor: 'seller JWT',
        pre: 'pedido_devolucao após disputa',
        repro:
            'PATCH disputa_devolucao_vendedor; PATCH devolvida',
        expected: 'cadeia em_devolucao → devolucao_entregue obrigatória',
        obtained: {
          'shortcut': hopShortcut.brief,
          'devolvida': hopDevShort.brief,
          'status': stShort,
        },
      );
    }
  }

  // Fake stripe_refund_id (deveria ser money immutable)
  final fakeRef = await c.patchOrder(
    oid,
    {'stripe_refund_id': 're_RTAS_fake'},
    jwt: c.sellerJwt,
  );
  final afterFakeRef = await c.orderRow(oid);
  if (fakeRef.ok &&
      '${afterFakeRef?['stripe_refund_id']}' == 're_RTAS_fake') {
    c.hold(
      id: 'AS4.fake_stripe_refund_id',
      lens: 'AS4',
      severity: 'P0',
      title: 'Seller PATCH stripe_refund_id falso',
      actor: 'seller JWT',
      pre: 'devolvida com captura viva',
      repro: 'PATCH stripe_refund_id=re_RTAS_fake',
      expected: 'order_money_fields_immutable',
      obtained: {
        'hit': fakeRef.brief,
        'row': afterFakeRef,
      },
    );
  } else {
    c.block('AS4.fake_stripe_refund_id', 'AS4', 'fake refund id', fakeRef);
  }

  final zeroPaid = await c.patchOrder(
    oid,
    {'amount_paid_cents': 0, 'stripe_payment_intent_id': ''},
    jwt: c.sellerJwt,
  );
  if (zeroPaid.ok) {
    c.hold(
      id: 'AS4.clear_capture_fields',
      lens: 'AS4',
      severity: 'P0',
      title: 'Seller limpa amount_paid_cents / PI após captura',
      actor: 'seller JWT',
      pre: 'order capturada',
      repro: 'PATCH amount_paid_cents=0 stripe_payment_intent_id=""',
      expected: 'immutable',
      obtained: zeroPaid.brief,
    );
  } else {
    c.block('AS4.clear_capture_fields', 'AS4', 'clear capture', zeroPaid);
  }

  // Refund em estados intermédios vs devolvida (AM4 exact = blocked on devolvida;
  // agora o gate terminal deve PERMITIR. Se 403 shipped = regressão AM4.)
  if (stShort != 'devolvida') {
    // Caminho clássico se shortcut falhou
    await c.patchOrder(oid, {'status': 'em_devolucao'}, jwt: c.sellerJwt);
    final refEm = await c.refund(oid, jwt: c.sellerJwt);
    await expectBlock(
      'AS4.refund_em_devolucao',
      'AS4',
      'refund-order em em_devolucao',
      refEm.status == 200 && (refEm.map?['ok'] == true)
          ? HttpHit(200, refEm.body, refEm.json)
          : refEm,
    );
    // expectBlock treats ok HTTP as finding; refund 403 is block. Handle 403 as block.
    if (refEm.status >= 400 || refEm.map?['ok'] == false) {
      // already noted if we called expectBlock wrong. Fix: just block.
    }
    await c.patchOrder(oid, {'status': 'devolucao_entregue'}, jwt: c.sellerJwt);
    await c.patchOrder(oid, {'status': 'devolvida'}, jwt: c.sellerJwt);
  }

  final beforeRef = await books(oid, pid);
  final refDev = await c.refund(oid, jwt: c.sellerJwt);
  final afterRef = await books(oid, pid);
  c.note('AS4.refund_devolvida', 'refund-order pós-devolvida (AHAM gate)', {
    'hit': refDev.brief,
    'before': beforeRef,
    'after': afterRef,
  }, lens: 'AS4');

  final refOk = refDev.ok && refDev.map?['ok'] != false;
  final afterSt = (afterRef['order'] as Map?)?['status'];
  final afterQty = (afterRef['product'] as Map?)?['quantity'];
  final afterRefundId = (afterRef['order'] as Map?)?['stripe_refund_id'];
  final afterApplied = (afterRef['order'] as Map?)?['stock_units_applied'];

  if (!refOk &&
      '${(beforeRef['order'] as Map?)?['status']}' == 'devolvida' &&
      refDev.body.contains('order_refund_blocked_shipped')) {
    c.hold(
      id: 'AS4.am4_regress_refund_blocked',
      lens: 'AS4',
      severity: 'P1',
      title: 'REGRESSÃO AHAM: refund-order em devolvida ainda blocked shipped',
      actor: 'seller JWT',
      pre: 'devolvida + shipped_at',
      repro: 'POST refund-order',
      expected: 'ok:true (gate terminal antes de shipped_at)',
      obtained: refDev.brief,
    );
  } else if (refOk) {
    c.block('AS4.am4_verify_refund_allowed', 'AS4',
        'AHAM: refund-order em devolvida permitido', refDev);
    if (afterSt == 'cancelado') {
      c.hold(
        id: 'AS4.finalize_devolvida_to_cancelado',
        lens: 'AS4',
        severity: 'P2',
        title:
            'refund-order em devolvida passa status para cancelado (apaga o terminal de devolução)',
        actor: 'Edge refund-order / finalize',
        pre: 'status=devolvida, refund Stripe TEST',
        repro: 'POST refund-order',
        expected: 'permanece devolvida (ou refunded) — não reescrever como cancelado',
        obtained: {
          'hit': refDev.brief,
          'status': afterSt,
          'stripe_refund_id': afterRefundId,
        },
      );
    }
    if (afterQty is num && afterQty >= 2) {
      c.hold(
        id: 'AS3.double_stock_restore',
        lens: 'AS3',
        severity: 'P1',
        title: 'Refund em devolvida restaurou stock a mais (qty≥2, era 1)',
        actor: 'triggers restore×2',
        pre: 'qty 0, applied 1, captura 1 unidade',
        repro: 'refund-order após devolvida',
        expected: 'qty=1',
        obtained: afterRef,
      );
    }
  }

  // 2.º checkout após refund real (intencional se refund+restore)
  final availAfter = await c.stockCheck(pid);
  final chk2 = await c.checkout(
    orderId: b2Order.firstId ?? oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
    productId: pid,
    seller: c.sellerId,
    amount: 5.9,
  );
  c.note('AS8.second_checkout', 'B2 create-payment-intent no SKU', {
    'avail': availAfter.brief,
    'checkout': chk2.brief,
    'qty': afterQty,
    'applied': afterApplied,
    'refund_id': afterRefundId,
  }, lens: 'AS8');

  // Buyer refund-order
  final pBuy = await mustPay('AS4');
  final buyerRef = await c.refund(pBuy.oid, jwt: c.buyerJwt);
  if (buyerRef.ok && buyerRef.map?['ok'] == true) {
    c.hold(
      id: 'AS4.buyer_refund_order',
      lens: 'AS4',
      severity: 'P1',
      title: 'Buyer chama refund-order com sucesso',
      actor: 'buyer JWT',
      pre: 'order pago B1',
      repro: 'POST refund-order JWT=buyer',
      expected: '403 Sem permissão (seller-only)',
      obtained: buyerRef.brief,
    );
  } else {
    c.block('AS4.buyer_refund_order', 'AS4', 'buyer refund-order', buyerRef);
  }

  // Partial refund RPC seller
  final partSeller = await c.rpc(
    'batata_process_partial_refund_dispute',
    {'p_order_id': oid, 'p_refund_percent': 50},
    jwt: c.sellerJwt,
  );
  if (partSeller.ok &&
      partSeller.body != 'false' &&
      !partSeller.brief.toLowerCase().contains('not_allowed')) {
    c.hold(
      id: 'AS4.partial_seller_rpc',
      lens: 'AS4',
      severity: 'P1',
      title: 'Seller executa batata_process_partial_refund_dispute',
      actor: 'seller JWT',
      pre: 'order em cadeia devolução',
      repro: 'rpc percent=50',
      expected: 'not_allowed (só buyer)',
      obtained: partSeller.brief,
    );
  } else {
    c.block('AS4.partial_seller_rpc', 'AS4', 'partial seller', partSeller);
  }

  // =========================================================================
  // AS5 — receção ∩ disputa / saltos
  // =========================================================================
  final p5 = await mustPay('AS5');
  await c.patchOrder(p5.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(p5.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  final d5 = await c.insertDispute(orderId: p5.oid);
  await c.patchOrder(p5.oid, {'status': 'pedido_devolucao'}, jwt: c.buyerJwt);
  final backConcl = await c.patchOrder(
    p5.oid,
    {'status': 'concluido'},
    jwt: c.buyerJwt,
  );
  final afterConcl = await c.orderRow(p5.oid);
  c.note('AS5.pedido_to_concluido', 'buyer aborta devolução → concluido', {
    'hit': backConcl.brief,
    'order': afterConcl,
    'dispute': d5.brief,
  }, lens: 'AS5');
  if (backConcl.ok && afterConcl?['status'] == 'concluido') {
    final rel = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': p5.oid},
      jwt: c.buyerJwt,
    );
    final wRel = await c.wallets();
    final dSt = await c.rest(
      'GET',
      'order_disputes?order_id=eq.${p5.oid}&select=id,status',
      service: true,
    );
    c.note('AS5.release_after_abort', 'release wallet com disputa?', {
      'rpc': rel.brief,
      'wallets': wRel,
      'w0_seller_delta_hint': w0,
      'dispute': dSt.map,
    }, lens: 'AS5');
    if (rel.body == 'true' || rel.json == true) {
      c.hold(
        id: 'AS5.release_with_open_dispute',
        lens: 'AS5',
        severity: 'P1',
        title:
            'Buyer hop pedido_devolucao→concluido + release wallet com disputa não recusada',
        actor: 'buyer JWT',
        pre: 'disputa aberta, hop concluido',
        repro: 'PATCH concluido; rpc batata_release_seller_wallet_for_order',
        expected: 'release false enquanto disputa aberta',
        obtained: {
          'hop': backConcl.brief,
          'release': rel.brief,
          'dispute': dSt.map,
        },
      );
    } else {
      c.block('AS5.release_with_open_dispute', 'AS5',
          'release recusado com disputa', rel);
    }
  } else {
    c.block('AS5.pedido_to_concluido', 'AS5', 'buyer pedido→concluido',
        backConcl);
  }

  // Seller marca concluido a partir de enviado
  final p5b = await mustPay('AS5');
  await c.patchOrder(p5b.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final sellerConcl = await c.patchOrder(
    p5b.oid,
    {'status': 'concluido'},
    jwt: c.sellerJwt,
  );
  final o5b = await c.orderRow(p5b.oid);
  if (sellerConcl.ok && o5b?['status'] == 'concluido') {
    c.hold(
      id: 'AS5.seller_enviado_to_concluido',
      lens: 'AS5',
      severity: 'P1',
      title: 'Seller marca concluido a partir de enviado (sem o comprador)',
      actor: 'seller JWT',
      pre: 'enviado capturado',
      repro: 'PATCH status=concluido',
      expected: 'só o comprador confirma receção',
      obtained: {'hit': sellerConcl.brief, 'status': o5b?['status']},
    );
  } else {
    c.block('AS5.seller_enviado_to_concluido', 'AS5',
        'seller enviado→concluido', sellerConcl);
  }

  final sellerEnt = await c.patchOrder(
    p5b.oid,
    {'status': 'entregue'},
    jwt: c.sellerJwt,
  );
  final oEnt = await c.orderRow(p5b.oid);
  if (sellerEnt.ok && oEnt?['status'] == 'entregue') {
    c.hold(
      id: 'AS5.seller_marks_entregue',
      lens: 'AS5',
      severity: 'P2',
      title: 'Seller marca entregue (confirma receção no lugar do comprador)',
      actor: 'seller JWT',
      pre: 'enviado',
      repro: 'PATCH status=entregue JWT=seller',
      expected: 'entregue é acção do comprador',
      obtained: {'hit': sellerEnt.brief, 'status': oEnt?['status']},
    );
  } else {
    c.block('AS5.seller_marks_entregue', 'AS5', 'seller entregue', sellerEnt);
  }

  // =========================================================================
  // AS6 — etiqueta / carrier / captura
  // =========================================================================
  final unpaid = await c.createProduct(qty: 1, price: 8, title: '$prefix-unpaid');
  if (unpaid != null) {
    final uo = await c.insertOrder(
      productId: unpaid,
      jwt: c.buyerJwt,
      price: 8,
      shipping: 'CTT',
    );
    if (uo != null) {
      final shipUnpaid = await c.patchOrder(
        uo,
        {'status': 'enviado'},
        jwt: c.sellerJwt,
      );
      final urow = await c.orderRow(uo);
      if (shipUnpaid.ok && urow?['status'] == 'enviado') {
        c.hold(
          id: 'AS6.enviado_without_capture',
          lens: 'AS6',
          severity: 'P1',
          title: 'Seller marca enviado sem captura plataforma',
          actor: 'seller JWT',
          pre: 'order reserva_pendente, Pagamento na app, sem PI',
          repro: 'PATCH status=enviado',
          expected: 'order_status_requires_capture / order_ship_requires_pago',
          obtained: {'hit': shipUnpaid.brief, 'row': urow},
        );
      } else {
        c.block('AS6.enviado_without_capture', 'AS6', 'enviado sem captura',
            shipUnpaid);
      }
    }
  }

  final freezeShip = await c.patchOrder(
    p1.oid,
    {'shipping_method': 'mão'},
    jwt: c.buyerJwt,
  );
  if (freezeShip.ok) {
    final fr = await c.orderRow(p1.oid);
    if ('${fr?['shipping_method']}' == 'mão' ||
        '${fr?['shipping_method']}'.contains('mão')) {
      c.hold(
        id: 'AS6.shipping_unfrozen',
        lens: 'AS6',
        severity: 'P1',
        title: 'Buyer altera shipping_method após pagamento',
        actor: 'buyer JWT',
        pre: 'order pós-pago',
        repro: 'PATCH shipping_method=mão',
        expected: 'order_shipping_frozen_after_payment',
        obtained: {'hit': freezeShip.brief, 'method': fr?['shipping_method']},
      );
    } else {
      c.block('AS6.shipping_unfrozen', 'AS6', 'shipping freeze (no change)',
          freezeShip);
    }
  } else {
    c.block('AS6.shipping_frozen', 'AS6', 'shipping freeze', freezeShip);
  }

  // Cancel pós-pago
  final cancelPay = await c.patchOrder(
    p5b.oid,
    {'status': 'cancelado'},
    jwt: c.sellerJwt,
  );
  if (cancelPay.ok && (await c.orderRow(p5b.oid))?['status'] == 'cancelado') {
    c.hold(
      id: 'AS3.cancel_post_pay',
      lens: 'AS3',
      severity: 'P1',
      title: 'Seller cancela pós-pago (restaura stock?)',
      actor: 'seller JWT',
      pre: 'enviado/entregue capturado',
      repro: 'PATCH status=cancelado',
      expected: 'order_cancel_denied_post_pay',
      obtained: cancelPay.brief,
    );
  } else {
    c.block('AS3.cancel_post_pay', 'AS3', 'cancel pós-pago', cancelPay);
  }

  // Replies evil URL
  if (didRet != null) {
    final reply = await c.rest('POST', 'order_dispute_replies', jwt: c.buyerJwt, body: {
      'dispute_id': didRet,
      'sender_id': c.buyerId,
      'message': 'prova',
      'proof_photos': ['javascript:alert(1)'],
    });
    if (reply.ok) {
      c.hold(
        id: 'AS7.reply_javascript',
        lens: 'AS7',
        severity: 'P2',
        title: 'reply proof_photos javascript: aceite',
        actor: 'buyer JWT',
        pre: 'disputa return chain',
        repro: 'POST order_dispute_replies proof_photos javascript:',
        expected: 'dispute_proof_url_denied',
        obtained: reply.brief,
      );
    } else {
      c.block('AS7.reply_javascript', 'AS7', 'reply js denied', reply);
    }
  }

  await c.dumpAll('pass1.json');
  stdout.writeln(
      'PASS1 done findings=${c.findings.length} blocked=${c.blocked.length}');
}
