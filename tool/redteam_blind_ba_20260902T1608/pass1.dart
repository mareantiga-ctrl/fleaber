/// RED TEAM CEGO BA — pass 1. Staging only. Não corrige.
/// Variantes novas: Klarna, iDEAL, emoji €, homoglyphs, sign path alheio.
/// Não repetir exactos AO/AU/AI (PayPal 50€, Wise/Revolut/Apple Pay, public/avatars, NBSP delete).
import 'dart:io';
import '_rtba.dart';

Future<void> main() async {
  final c = Rtba.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.note('actors', 'JWT B1/S1/B2/S2', {
    'b1': c.buyerId,
    's1': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
  });

  final sku1 = await c.createProduct(title: '$prefix-sku1', price: 12.0);
  final sku2 = await c.createProduct(
    seller: c.seller2Id,
    title: '$prefix-sku2',
    price: 9.0,
  );
  if (sku1 == null || sku2 == null) {
    stderr.writeln('ABORT: products');
    exit(4);
  }

  final unpaid = await c.insertOrder(
    productId: sku1,
    status: 'reserva_pendente',
    price: 12.0,
  );
  final paid = await c.insertOrder(
    productId: sku1,
    status: 'pago',
    price: 12.0,
    paidCents: 1200,
    pi: 'pi_rtba_fixture_${c.nextRef()}',
  );
  final unpaidB2 = await c.insertOrder(
    productId: sku2,
    buyer: c.buyer2Id,
    seller: c.seller2Id,
    status: 'reserva_pendente',
    price: 9.0,
  );
  final paidB2 = await c.insertOrder(
    productId: sku2,
    buyer: c.buyer2Id,
    seller: c.seller2Id,
    status: 'pago',
    price: 9.0,
    paidCents: 900,
    pi: 'pi_rtba_b2_${c.nextRef()}',
  );
  c.note('orders', 'fixtures', {
    'unpaid': unpaid,
    'paid': paid,
    'unpaidB2': unpaidB2,
    'paidB2': paidB2,
  });

  final chat = await c.getOrCreateChat(
    a: c.buyerId!,
    b: c.sellerId!,
    productId: sku1,
    jwt: c.buyerJwt,
  );
  final chat2 = await c.getOrCreateChat(
    a: c.buyer2Id!,
    b: c.seller2Id!,
    productId: sku2,
    jwt: c.buyer2Jwt,
  );
  if (chat == null || chat2 == null) {
    stderr.writeln('ABORT: chats ${c.notes.last}');
    exit(4);
  }
  c.note('chats', 'B1-S1 / B2-S2', {'c1': chat, 'c2': chat2});

  // =========================================================================
  // BA1 — cards (kinds novos + notes Klarna/iDEAL, não PayPal/Wise exact)
  // =========================================================================
  Future<void> card({
    required String id,
    required String title,
    required String text,
    String? jwt,
    String? sender,
    String? receiver,
    String? chatId,
    bool expectCrack = true,
    String severity = 'P2',
    String lens = 'BA1',
  }) async {
    final hit = await c.insertMsg(
      chatId: chatId ?? chat,
      text: text,
      jwt: jwt ?? c.buyerJwt!,
      sender: sender ?? c.buyerId,
      receiver: receiver ?? c.sellerId,
    );
    c.judge(
      id: id,
      lens: lens,
      title: title,
      hit: hit,
      cracked: expectCrack ? hit.ok : false,
      actor: 'buyer JWT',
      pre: 'chat B1-S1 + orders fixture',
      repro: 'POST chat_messages text=${clip(text, 120)}',
      severity: severity,
      expected: 'negado (kind/notes/display)',
      evidence: {'persisted_id': hit.firstId, 'text_head': clip(text, 80)},
    );
  }

  await card(
    id: 'BA1.kind.klarna_receipt',
    title: 'kind klarna_receipt (não allowlist)',
    text: c.jsonCard({'kind': 'klarna_receipt', 'total': '12.00'}),
  );
  await card(
    id: 'BA1.kind.ideal_paid',
    title: 'kind ideal_paid (não allowlist)',
    text: c.jsonCard({'kind': 'ideal_paid', 'amount': 15}),
  );
  await card(
    id: 'BA1.kind.order_paid',
    title: 'kind order_paid (server-only) via JWT',
    text: c.jsonCard({'kind': 'order_paid', 'order_id': unpaid}),
    severity: 'P1',
  );

  if (unpaid != null) {
    await card(
      id: 'BA1.notes.klarna',
      title: 'reservation_payment_submitted notes Klarna 12€ (amount antes)',
      text: c.jsonCard({
        'kind': 'reservation_payment_submitted',
        'order_id': unpaid,
        'notes': 'Klarna 12,00 € confirmado',
      }),
      severity: 'P2',
    );
    await card(
      id: 'BA1.notes.ideal',
      title: 'notes iDEAL 15 EUR aprovado (amount antes do keyword)',
      text: c.jsonCard({
        'kind': 'reservation_payment_submitted',
        'order_id': unpaid,
        'notes': 'iDEAL 15 EUR aprovado',
      }),
    );
    await card(
      id: 'BA1.notes.bancontact',
      title: 'notes Bancontact recebido 9€',
      text: c.jsonCard({
        'kind': 'reservation_payment_submitted',
        'order_id': unpaid,
        'notes': 'Bancontact recebido 9,00 €',
      }),
    );
    await card(
      id: 'BA1.notes.twint',
      title: 'notes Twint pago 12 EUR',
      text: c.jsonCard({
        'kind': 'reservation_payment_submitted',
        'order_id': unpaid,
        'notes': 'Twint pago 12 EUR',
      }),
    );
    await card(
      id: 'BA1.notes.klarna_confirmado_after',
      title: 'notes «Klarna confirmado 12,00 €» (keyword depois método)',
      text: c.jsonCard({
        'kind': 'reservation_payment_submitted',
        'order_id': unpaid,
        'notes': 'Klarna confirmado 12,00 €',
      }),
    );
  }

  if (paid != null) {
    await card(
      id: 'BA1.seguro.label.klarna',
      title: 'seguro_fleaber_paid label Klarna (rail gap)',
      text: c.jsonCard({
        'kind': 'seguro_fleaber_paid',
        'order_id': paid,
        'total': '12.00',
        'label': 'Klarna',
      }),
    );
    await card(
      id: 'BA1.cancel.display.ideal',
      title: 'cancel_request_outcome display iDEAL (seller)',
      text: c.jsonCard({
        'kind': 'cancel_request_outcome',
        'order_id': paid,
        'outcome': 'rejected',
        'display': 'iDEAL 12 EUR aprovado — pedido recusado',
      }),
      jwt: c.sellerJwt,
      sender: c.sellerId,
      receiver: c.buyerId,
    );
  }

  // =========================================================================
  // BA2 — encoding (emoji €, homoglyphs, Cf) — NÃO ZWSP-PayPal exact
  // =========================================================================
  const greekK = '\u039A'; // Κ
  const banknote = '\u{1F4B6}'; // 💶
  const hangulFiller = '\u3164';
  const braille = '\u2800';
  const zwj = '\u200D';

  final encPlain = <String, String>{
    'BA2.plain.klarna_emoji': 'Klarna confirmado 12 $banknote',
    'BA2.plain.ideal_emoji': 'iDEAL aprovado 15 $banknote',
    'BA2.plain.greek_klarna': '${greekK}larna confirmado 12,00 €',
    'BA2.plain.fullwidth': 'Ｋｌａｒｎａ １２ € confirmado',
    'BA2.plain.zwj_klarna': 'K${zwj}larna 12€ pago',
    'BA2.plain.dotless_i': 'ıDEAL 12 EUR confirmado',
  };
  for (final e in encPlain.entries) {
    final hit = await c.insertMsg(
      chatId: chat,
      text: e.value,
      jwt: c.buyerJwt!,
    );
    c.judge(
      id: e.key,
      lens: 'BA2',
      title: 'plain lie persiste: ${clip(e.value, 60)}',
      hit: hit,
      cracked: hit.ok,
      actor: 'buyer JWT',
      pre: 'denylist ANAS sem Klarna/iDEAL/💶',
      repro: 'POST chat_messages plain',
      severity: 'P3',
      expected: 'bloqueado se mentira de pagamento; senão P3 UI',
      evidence: {'text': e.value, 'id': hit.firstId},
    );
  }

  if (unpaid != null) {
    await card(
      id: 'BA2.notes.emoji_euro',
      title: 'notes Klarna confirmado 12 💶 (emoji ≠ €)',
      text: c.jsonCard({
        'kind': 'reservation_payment_submitted',
        'order_id': unpaid,
        'notes': 'Klarna confirmado 12 $banknote',
      }),
      lens: 'BA2',
    );
    await card(
      id: 'BA2.notes.homoglyph_k',
      title: 'notes Κlarna (Greek Kappa) confirmado 12€',
      text: c.jsonCard({
        'kind': 'reservation_payment_submitted',
        'order_id': unpaid,
        'notes': '${greekK}larna confirmado 12,00 €',
      }),
      lens: 'BA2',
    );
  }

  // =========================================================================
  // BA3 — cronologia
  // =========================================================================
  final past = '2020-01-01T00:00:00Z';
  final future = '2035-01-01T00:00:00Z';
  final chrono = await c.insertMsg(
    chatId: chat,
    text: '$prefix chrono past',
    jwt: c.buyerJwt!,
    createdAt: past,
  );
  final chronoId = chrono.firstId;
  if (chrono.ok && chronoId != null) {
    final row = await c.msgRow(chronoId);
    final got = row?['created_at']?.toString() ?? '';
    final stuckIn2020 = got.startsWith('2020');
    c.judge(
      id: 'BA3.created_at.past',
      lens: 'BA3',
      title: 'INSERT created_at=2020 cola',
      hit: chrono,
      cracked: stuckIn2020,
      actor: 'buyer JWT',
      pre: 'guard_insert força now()',
      repro: 'POST chat_messages created_at=2020-01-01',
      severity: 'P2',
      expected: 'created_at ≈ now',
      evidence: {'created_at': got},
    );
    final up = await c.rest(
      'PATCH',
      'chat_messages?id=eq.$chronoId',
      jwt: c.buyerJwt,
      body: {'created_at': past},
    );
    final after = await c.msgRow(chronoId);
    final still2020 = (after?['created_at']?.toString() ?? '').startsWith('2020');
    c.judge(
      id: 'BA3.patch.created_at',
      lens: 'BA3',
      title: 'PATCH created_at=2020 cola',
      hit: up,
      cracked: still2020,
      actor: 'buyer JWT',
      pre: 'guard_update NEW.created_at := OLD',
      repro: 'PATCH chat_messages created_at',
      severity: 'P2',
      expected: 'imutável / now',
      evidence: {'created_at': after?['created_at']},
    );
  } else {
    c.block('BA3.created_at.past', 'BA3', 'INSERT created_at', chrono);
  }

  final inboxFuture = await c.patchChat(chat, {
    'last_message_time': future,
  }, jwt: c.buyerJwt);
  final chatAfter = await c.chatRow(chat);
  final t = chatAfter?['last_message_time']?.toString() ?? '';
  final farFuture = t.startsWith('2035');
  c.judge(
    id: 'BA3.inbox.future',
    lens: 'BA3',
    title: 'PATCH last_message_time=2035 cola',
    hit: inboxFuture,
    cracked: farFuture,
    actor: 'buyer JWT',
    pre: 'chats_guard_update clamp ±minutos',
    repro: 'PATCH chats last_message_time=2035',
    severity: 'P3',
    expected: 'clamp now()',
    evidence: {'last_message_time': t},
  );

  // =========================================================================
  // BA4 / BA6 — URLs sign-only + path alheio + storage
  // =========================================================================
  final ownPath = 'chat_uploads/${c.buyerId}/$chat/rtba-own.png';
  final victimPath = 'chat_uploads/${c.buyer2Id}/$chat2/rtba-secret.png';
  final ownProof = 'order_proofs/${c.buyerId}/$unpaid/rtba-proof.png';
  final victimProof = 'order_proofs/${c.buyer2Id}/$unpaidB2/rtba-b2-secret.png';

  final upOwn = await c.uploadPrivate(ownPath, c.buyerJwt!);
  c.note('BA6.upload.own', 'upload chat B1', upOwn.brief, lens: 'BA6');
  final upVictim = await c.uploadPrivate(victimPath, c.buyer2Jwt!);
  c.note('BA6.upload.victim', 'upload chat B2', upVictim.brief, lens: 'BA6');
  if (unpaid != null) {
    final upProof = await c.uploadPrivate(ownProof, c.buyerJwt!);
    c.note('BA6.upload.proof', 'order_proofs B1', upProof.brief, lens: 'BA6');
  }
  if (unpaidB2 != null) {
    final upVProof = await c.uploadPrivate(victimProof, c.buyer2Jwt!);
    c.note('BA6.upload.vproof', 'order_proofs B2', upVProof.brief, lens: 'BA6');
  }

  final signOwn = await c.signPrivate(ownPath, c.buyerJwt!);
  final signVictim = await c.signPrivate(victimPath, c.buyer2Jwt!);
  final signVictimAsB1 = await c.signPrivate(victimPath, c.buyerJwt!);
  c.judge(
    id: 'BA6.sign.victim_as_b1',
    lens: 'BA6',
    title: 'B1 cria signed URL do path B2',
    hit: signVictimAsB1,
    cracked: signVictimAsB1.ok,
    actor: 'buyer JWT',
    pre: 'storage sign alheio',
    repro: 'POST /object/sign/fleaber_private/chat_uploads/{B2}/…',
    severity: 'P1',
    expected: '403',
  );

  final ownUrl = c.signedUrlFrom(signOwn, ownPath);
  final victimUrl = c.signedUrlFrom(signVictim, victimPath);
  c.note('BA4.urls', 'signed', {
    'own': clip(ownUrl, 120),
    'victim': clip(victimUrl, 120),
    'signOwn': signOwn.brief,
    'signVictim': signVictim.brief,
  }, lens: 'BA4');

  if (ownUrl.isNotEmpty) {
    await card(
      id: 'BA4.chat_image.own_sign',
      title: 'chat_image sign próprio (controlo happy)',
      text: c.jsonCard({
        'kind': 'chat_image',
        'path': ownPath,
        'url': ownUrl,
      }),
      expectCrack: false,
      lens: 'BA4',
    );
    // If control failed, note it (regression).
    final last = c.blocked.where((e) => e['id'] == 'BA4.chat_image.own_sign');
    if (last.isEmpty) {
      // judge with expectCrack:false never holds on ok — check manually
    }
  }
  // Re-judge control: ok is HOLD (not a finding)
  if (ownUrl.isNotEmpty) {
    final ctrl = await c.insertMsg(
      chatId: chat,
      text: c.jsonCard({'kind': 'chat_image', 'path': ownPath, 'url': ownUrl}),
      jwt: c.buyerJwt!,
    );
    if (ctrl.ok) {
      c.block('BA4.chat_image.own_sign.ok', 'BA4', 'happy sign próprio', ctrl);
    } else {
      c.hold(
        id: 'BA4.P3.own_sign_denied',
        lens: 'BA4',
        severity: 'P3',
        title: 'chat_image sign próprio recusado (possível regressão happy)',
        actor: 'buyer JWT',
        pre: 'upload+sign fleaber_private chat_uploads/{B1}/{chat}',
        repro: 'POST chat_image path+sign url',
        expected: '201',
        obtained: ctrl.brief,
      );
    }
  }

  if (victimUrl.isNotEmpty) {
    await card(
      id: 'BA4.chat_image.victim_path',
      title: 'chat_image path alheio (B2) no chat B1',
      text: c.jsonCard({
        'kind': 'chat_image',
        'path': victimPath,
        'url': victimUrl,
      }),
      severity: 'P1',
      lens: 'BA4',
    );
    await card(
      id: 'BA4.chat_image.own_path_victim_sign',
      title: 'chat_image path próprio + signed URL alheia',
      text: c.jsonCard({
        'kind': 'chat_image',
        'path': ownPath,
        'url': victimUrl,
      }),
      severity: 'P1',
      lens: 'BA4',
    );
  }

  final evilHost =
      'https://$projectMust.supabase.co.evil.example/storage/v1/object/sign/chat_uploads/${c.buyerId}/x.png';
  await card(
    id: 'BA4.chat_image.evil_host',
    title: 'chat_image host supabase.co.evil (suffix)',
    text: c.jsonCard({
      'kind': 'chat_image',
      'path': ownPath,
      'url': evilHost,
    }),
    lens: 'BA4',
  );

  final renderUrl =
      'https://$projectMust.supabase.co/storage/v1/render/image/sign/fleaber_private/$ownPath';
  await card(
    id: 'BA4.chat_image.render_sign',
    title: 'chat_image /render/image/sign/ (não object/sign)',
    text: c.jsonCard({
      'kind': 'chat_image',
      'path': ownPath,
      'url': renderUrl,
    }),
    lens: 'BA4',
  );

  if (unpaid != null && unpaidB2 != null) {
    final signVProof = await c.signPrivate(victimProof, c.buyer2Jwt!);
    final vProofUrl = c.signedUrlFrom(signVProof, victimProof);
    if (vProofUrl.isNotEmpty) {
      await card(
        id: 'BA4.proof_url.sign_alheio',
        title: 'reservation_payment_submitted proof_url = sign order_proofs B2',
        text: c.jsonCard({
          'kind': 'reservation_payment_submitted',
          'order_id': unpaid,
          'notes': 'comprovativo iDEAL',
          'proof_url': vProofUrl,
        }),
        severity: 'P1',
        lens: 'BA4',
      );
    }
    final authUrl =
        'https://$projectMust.supabase.co/storage/v1/object/authenticated/fleaber_private/$victimProof';
    await card(
      id: 'BA4.proof_url.authenticated_alheio',
      title: 'proof_url authenticated fleaber_private path B2',
      text: c.jsonCard({
        'kind': 'reservation_payment_submitted',
        'order_id': unpaid,
        'notes': 'comprovativo Klarna',
        'proof_url': authUrl,
      }),
      severity: 'P1',
      lens: 'BA4',
    );
  }

  final readVictim = await c.getObject(victimPath, c.buyerJwt!);
  c.judge(
    id: 'BA6.get.victim_object',
    lens: 'BA6',
    title: 'B1 GET object chat_uploads B2',
    hit: readVictim,
    cracked: readVictim.ok,
    actor: 'buyer JWT',
    pre: 'RLS fleaber_private chat counterparty só do mesmo chat',
    repro: 'GET /object/fleaber_private/chat_uploads/{B2}/…',
    severity: 'P1',
    expected: '403',
  );

  final uploadIntoVictim = await c.uploadPrivate(victimPath, c.buyerJwt!);
  c.judge(
    id: 'BA6.upload.into_victim',
    lens: 'BA6',
    title: 'B1 INSERT storage path B2',
    hit: uploadIntoVictim,
    cracked: uploadIntoVictim.ok,
    actor: 'buyer JWT',
    pre: 'insert_own exige chat_uploads/{uid}',
    repro: 'POST object fleaber_private chat_uploads/{B2}/…',
    severity: 'P1',
    expected: '403',
  );

  // =========================================================================
  // BA5 — inbox / delete (Klarna/iDEAL/emoji, não NBSP exact)
  // =========================================================================
  final inboxLies = <String, String>{
    'BA5.inbox.klarna_amount_first': 'Klarna 12,00 € confirmado',
    'BA5.inbox.ideal_amount_first': 'iDEAL 15 EUR aprovado',
    'BA5.inbox.emoji': 'Klarna confirmado 12 $banknote',
    'BA5.inbox.greek': '${greekK}larna confirmado 12€',
    'BA5.inbox.twint': 'Twint 9,99 € pago',
    'BA5.inbox.bancontact': 'Bancontact recebido 12 EUR',
  };
  for (final e in inboxLies.entries) {
    final hit = await c.patchChat(chat, {'last_message': e.value}, jwt: c.buyerJwt);
    final row = await c.chatRow(chat);
    final lm = row?['last_message']?.toString() ?? '';
    final stuck = lm == e.value;
    c.judge(
      id: e.key,
      lens: 'BA5',
      title: 'inbox last_message="${clip(e.value, 50)}"',
      hit: hit,
      cracked: stuck,
      actor: 'buyer JWT',
      pre: 'forged_inbox_preview = payment_lie_text ANAS (sem Klarna/iDEAL/💶)',
      repro: 'PATCH chats last_message',
      severity: 'P2',
      expected: 'chat_inbox_preview_forbidden',
      evidence: {'last_message': lm, 'wanted': e.value},
    );
  }

  // DELETE: JSON com prefixos exóticos (não NBSP/Zs exact)
  if (ownUrl.isNotEmpty) {
    final payloads = <String, String>{
      'BA5.del.hangul':
          '$hangulFiller${c.jsonCard({'kind': 'chat_image', 'path': ownPath, 'url': ownUrl})}',
      'BA5.del.braille':
          '$braille${c.jsonCard({'kind': 'chat_image', 'path': ownPath, 'url': ownUrl})}',
      'BA5.del.bom_zwsp':
          '\uFEFF\u200B${c.jsonCard({'kind': 'chat_image', 'path': ownPath, 'url': ownUrl})}',
    };
    for (final e in payloads.entries) {
      final ins = await c.insertMsg(
        chatId: chat,
        text: e.value,
        jwt: c.buyerJwt!,
      );
      final mid = ins.firstId;
      c.note('${e.key}.insert', 'insert prefixed JSON', ins.brief, lens: 'BA5');
      if (!ins.ok || mid == null) {
        c.block(e.key, 'BA5', 'INSERT prefixado recusado (delete n/a)', ins);
        continue;
      }
      final stored = await c.msgRow(mid);
      final del = await c.rest(
        'DELETE',
        'chat_messages?id=eq.$mid',
        jwt: c.buyerJwt,
      );
      final gone = await c.msgRow(mid);
      final cracked = del.ok && (gone == null || gone.isEmpty);
      c.judge(
        id: e.key,
        lens: 'BA5',
        title: 'DELETE JSON card com prefixo exótico',
        hit: del,
        cracked: cracked,
        actor: 'buyer JWT',
        pre: 'delete guard só NBSP/Zs + like FLEABER_JSON_V1',
        repro: 'INSERT prefix+JSON; DELETE own row',
        severity: 'P2',
        expected: 'chat_system_card_immutable',
        evidence: {
          'stored_head': clip(stored?['text'], 40),
          'delete': del.brief,
          'gone': gone == null,
        },
      );
    }
  }

  // =========================================================================
  // BA7 — cross-user
  // =========================================================================
  final xWrite = await c.insertMsg(
    chatId: chat2,
    text: '$prefix b1 into b2 chat',
    jwt: c.buyerJwt!,
    sender: c.buyerId,
    receiver: c.seller2Id,
  );
  c.judge(
    id: 'BA7.insert.other_chat',
    lens: 'BA7',
    title: 'B1 INSERT mensagem no chat B2-S2',
    hit: xWrite,
    cracked: xWrite.ok,
    actor: 'buyer JWT',
    pre: 'RLS insert self + participant',
    repro: 'POST chat_messages chat_id=B2-S2',
    severity: 'P1',
    expected: '403',
  );

  final xRead = await c.rest(
    'GET',
    'chat_messages?chat_id=eq.$chat2&select=id,text&limit=5',
    jwt: c.buyerJwt,
  );
  final leaked = xRead.ok && xRead.list.isNotEmpty;
  c.judge(
    id: 'BA7.read.other_chat',
    lens: 'BA7',
    title: 'B1 SELECT mensagens do chat B2-S2',
    hit: xRead,
    cracked: leaked,
    actor: 'buyer JWT',
    pre: 'select_participants',
    repro: 'GET chat_messages chat_id=B2-S2',
    severity: 'P1',
    expected: '[] / 403',
    evidence: {'n': xRead.list.length},
  );

  final xInbox = await c.patchChat(chat2, {'last_message': 'rtba b1'}, jwt: c.buyerJwt);
  final chat2After = await c.chatRow(chat2);
  final hijack = chat2After?['last_message']?.toString() == 'rtba b1';
  c.judge(
    id: 'BA7.patch.other_inbox',
    lens: 'BA7',
    title: 'B1 PATCH last_message do chat B2-S2',
    hit: xInbox,
    cracked: hijack,
    actor: 'buyer JWT',
    pre: 'chats RLS participant',
    repro: 'PATCH chats id=B2-S2',
    severity: 'P1',
    expected: '200 [] sem mutar / 403',
    evidence: {'last_message': chat2After?['last_message']},
  );

  if (c.createdMsgIds.isNotEmpty) {
    final foreign = c.createdMsgIds.last;
    final xDel = await c.rest(
      'DELETE',
      'chat_messages?id=eq.$foreign',
      jwt: c.buyer2Jwt,
    );
    c.judge(
      id: 'BA7.delete.other_msg',
      lens: 'BA7',
      title: 'B2 DELETE mensagem de B1',
      hit: xDel,
      cracked: xDel.ok && xDel.list.isNotEmpty,
      actor: 'buyer2 JWT',
      pre: 'delete_own',
      repro: 'DELETE chat_messages id=msg B1',
      severity: 'P1',
      expected: '403 / 200 []',
    );
  }

  // =========================================================================
  // BA8 — Edge (payload mutation; sem captura TEST necessária p/ chat)
  // =========================================================================
  final ocr = await c.edge('ingest-ocr-reservation', {
    'live_id': '00000000-0000-0000-0000-000000000001',
    'ocr_raw_line': 'Klarna confirmado 12,00 €',
    'parser_intent': 'paid',
    'requested_qty': 1,
  }, jwt: c.buyerJwt);
  c.note('BA8.ocr', 'ingest-ocr-reservation', ocr.brief, lens: 'BA8');
  final ocrMoney = ocr.ok &&
      (ocr.body.contains('reservation') || ocr.body.contains('"ok":true'));
  c.judge(
    id: 'BA8.ocr.klarna_paid',
    lens: 'BA8',
    title: 'OCR ingest aceita linha Klarna pago (sem live)',
    hit: ocr,
    cracked: ocrMoney,
    actor: 'buyer JWT',
    pre: 'edge OCR ≠ chat denylist',
    repro: 'POST ingest-ocr-reservation ocr_raw_line=Klarna…',
    severity: 'P2',
    expected: '401/403/live missing, sem reserva',
  );

  if (paid != null) {
    final ref = await c.edge('refund-order', {
      'order_id': paid,
      'amount_cents': 999999,
      'reason': 'Klarna chargeback via chat',
      'chat_id': chat,
    }, jwt: c.buyerJwt);
    c.note('BA8.refund', 'refund-order fixture PI', ref.brief, lens: 'BA8');
    final minted = ref.ok &&
        !ref.body.contains('error') &&
        (ref.body.contains('refund') || ref.body.contains('re_'));
    c.judge(
      id: 'BA8.refund.buyer_klarna',
      lens: 'BA8',
      title: 'buyer refund-order 999999 no PI fixture',
      hit: ref,
      cracked: minted,
      actor: 'buyer JWT',
      pre: 'refund seller-only + PI real',
      repro: 'POST refund-order amount_cents=999999',
      severity: 'P0',
      expected: '403',
    );
  }

  final cpi = await c.edge('create-payment-intent', {
    'product_id': sku1,
    'quantity': 1,
    'amount': 1,
    'chat_kind': 'order_paid',
    'chat_text': c.jsonCard({'kind': 'order_paid', 'total': '0.01'}),
    'last_message': 'Klarna 12,00 € confirmado',
  }, jwt: c.buyerJwt);
  c.note('BA8.cpi', 'create-payment-intent mutation', cpi.brief, lens: 'BA8');
  // Session created ≠ capture. Finding only if amount=1 sticks as payable 1 cent.
  final cheap = cpi.ok &&
      cpi.body.contains('cs_') &&
      (cpi.body.contains('"amount":1') ||
          cpi.body.contains('amount_total":1') ||
          cpi.body.contains('unit_amount":1'));
  c.judge(
    id: 'BA8.cpi.amount1_chat_inject',
    lens: 'BA8',
    title: 'CPI amount=1 + inject order_paid no body',
    hit: cpi,
    cracked: cheap,
    actor: 'buyer JWT',
    pre: 'Edge não confia amount do cliente; chat inject ignorado',
    repro: 'POST create-payment-intent amount=1 chat_kind=order_paid',
    severity: 'P0',
    expected: 'preço catálogo / 400; sem card order_paid',
  );

  await c.dumpAll('pass1.json');
  stdout.writeln(
    'PASS1 done findings=${c.findings.length} blocked=${c.blocked.length}',
  );
}
