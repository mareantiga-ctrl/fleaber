/// REDTEAM_BLIND_AO pass1 — variantes NOVAS pós-AHAM. Staging. Não corrigir.
import 'dart:convert';
import 'dart:io';
import '_rtao.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Future<void> main() async {
  final c = Rtao.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  c.note('actors', 'JWT B1/S1/B2', {
    'b1': c.buyerId,
    's1': c.sellerId,
    'b2': c.buyer2Id,
  });

  final paid = await c.payToPago(lens: 'AO8', initialQty: 1);
  if (paid == null) {
    c.skip('AO.fixture', 'AO8', 'setup_paid_order falhou', 'null');
    await c.dumpAll('pass1.json');
    return;
  }
  final oid = paid.oid;
  final o0 = await c.orderRow(oid);
  final wallets0 = await c.wallets();
  final paidCents = numOf(o0?['amount_paid_cents']) ?? 0;
  final totalEur = (paidCents / 100).toStringAsFixed(2);
  c.note('fixture.books', 'pago Stripe TEST', {
    'order': o0,
    'wallets': wallets0,
    'totalEur': totalEur,
  }, lens: 'AO8');

  final chatId = await c.ensureChat();
  if (chatId == null) {
    c.skip('AO.chat', 'AO1', 'ensureChat falhou', 'null');
    await c.dumpAll('pass1.json');
    return;
  }
  c.note('fixture.chat', 'chat B1-S1', chatId, lens: 'AO1');

  // -------------------------------------------------------------------------
  // Controlos exactos AHAM (não são findings se bloqueados)
  // -------------------------------------------------------------------------
  await c.expectDenied(
    id: 'CTRL.display-reembolso',
    lens: 'AO1',
    title: 'controlo exact AI P2-01 display Reembolso',
    hit: await c.msg(
      chatId,
      fj({
        'kind': 'cancel_request_outcome',
        'order_id': oid,
        'outcome': 'rejected',
        'display': 'Reembolso 4321 EUR processado',
      }),
      jwt: c.sellerJwt!,
      sender: c.sellerId,
    ),
    actor: 'seller JWT',
    pre: 'order pago',
    repro: 'POST cancel_request_outcome display=Reembolso 4321 EUR',
  );

  await c.expectDenied(
    id: 'CTRL.notes-reembolso',
    lens: 'AO1',
    title: 'controlo exact AI P2-03 notes Reembolso',
    hit: await c.msg(
      chatId,
      fj({
        'kind': 'reservation_payment_submitted',
        'order_id': oid,
        'notes': 'Reembolso 4321 € já enviado',
      }),
      jwt: c.buyerJwt!,
      sender: c.buyerId,
    ),
    actor: 'buyer JWT',
    pre: 'order pago',
    repro: 'POST reservation_payment_submitted notes=Reembolso 4321 €',
  );

  await c.expectDenied(
    id: 'CTRL.inbox-paypal',
    lens: 'AO5',
    title: 'controlo exact AI P2-07 inbox PayPal 50€',
    hit: await c.patchChat(chatId, {'last_message': 'PayPal 50€'}, jwt: c.buyerJwt),
    actor: 'buyer JWT',
    pre: 'chat B1-S1',
    repro: 'PATCH chats last_message=PayPal 50€',
  );

  // -------------------------------------------------------------------------
  // AO1 — cards vs BD: campos/keywords NOVOS
  // -------------------------------------------------------------------------
  final displayVariants = <String, String>{
    'refund-eur': 'Refund 50 EUR processed',
    'estorno': 'Estorno 50€ feito',
    'devolucao': 'Devolução 50,00 € na conta',
    'remboursement': 'Remboursement 50 €',
    'chargeback': 'Chargeback 50 EUR',
    'homoglyph-reembolso': 'R\u0435embolso 50 EUR processado', // Cyrillic е
  };
  for (final e in displayVariants.entries) {
    await c.expectDenied(
      id: 'AO1.display-${e.key}',
      lens: 'AO1',
      title: 'cancel display mentiroso keyword nova (${e.key})',
      hit: await c.msg(
        chatId,
        fj({
          'kind': 'cancel_request_outcome',
          'order_id': oid,
          'outcome': 'rejected',
          'display': e.value,
        }),
        jwt: c.sellerJwt!,
        sender: c.sellerId,
      ),
      actor: 'seller JWT',
      pre: 'order pago, outcome=rejected (BD não cancelado)',
      repro: 'POST cancel_request_outcome display=${e.value}',
      evidence: {'text': e.value},
    );
  }

  final notesVariants = <String, String>{
    'wise': 'Wise 50€ já caiu',
    'revolut': 'Revolut 12,00 € confirmado',
    'multibanco': 'Multibanco 50€ pago',
    'applepay': 'Apple Pay 20€',
    'homoglyph-mbway': 'M\u0412 WAY 50€ confirmado', // Cyrillic В
  };
  for (final e in notesVariants.entries) {
    await c.expectDenied(
      id: 'AO1.notes-${e.key}',
      lens: 'AO1',
      title: 'notes comprovativo keyword nova (${e.key})',
      hit: await c.msg(
        chatId,
        fj({
          'kind': 'reservation_payment_submitted',
          'order_id': oid,
          'notes': e.value,
        }),
        jwt: c.buyerJwt!,
        sender: c.buyerId,
      ),
      actor: 'buyer JWT',
      pre: 'order pago',
      repro: 'POST reservation_payment_submitted notes=${e.value}',
      evidence: {'text': e.value},
    );
  }

  // Campos paralelos a notes/display que o card Flutter NÃO sanitiza no SQL
  await c.expectDenied(
    id: 'AO1.notes-via-caption',
    lens: 'AO1',
    title: 'lie em caption (não notes) no comprovativo',
    hit: await c.msg(
      chatId,
      fj({
        'kind': 'reservation_payment_submitted',
        'order_id': oid,
        'caption': 'MB WAY 50€ confirmado',
        'notes': 'ok',
      }),
      jwt: c.buyerJwt!,
      sender: c.buyerId,
    ),
    actor: 'buyer JWT',
    pre: 'order pago; Flutter só mostra notes',
    repro: 'POST reservation_payment_submitted caption=MB WAY 50€ notes=ok',
    severityIfOpen: 'P3',
  );

  // seguro label keywords fora da lista (Wise / Pago)
  await c.expectDenied(
    id: 'AO1.seguro-label-wise',
    lens: 'AO1',
    title: 'seguro_fleaber_paid label Wise sem dígitos',
    hit: await c.msg(
      chatId,
      fj({
        'kind': 'seguro_fleaber_paid',
        'order_id': oid,
        'total': num.parse(totalEur),
        'label': 'Wise',
      }),
      jwt: c.buyerJwt!,
      sender: c.buyerId,
    ),
    actor: 'buyer JWT',
    pre: 'order pago, total=$totalEur',
    repro: 'POST seguro_fleaber_paid label=Wise total=BD',
  );

  await c.expectDenied(
    id: 'AO1.seguro-label-pago',
    lens: 'AO1',
    title: 'seguro_fleaber_paid label Pago no MB',
    hit: await c.msg(
      chatId,
      fj({
        'kind': 'seguro_fleaber_paid',
        'order_id': oid,
        'total': num.parse(totalEur),
        'label': 'Pago no MB',
      }),
      jwt: c.buyerJwt!,
      sender: c.buyerId,
    ),
    actor: 'buyer JWT',
    pre: 'order pago',
    repro: 'POST seguro_fleaber_paid label=Pago no MB',
  );

  // Plain-text legado: espaços Unicode que o SQL ^\\s* não come, o Dart trim() sim
  final legado = 'Compra paga através do Seguro Fleaber (4321,00 €)';
  final unicodePads = <String, String>{
    'nbsp': '\u00A0$legado',
    'emspace': '\u2003$legado',
    'ideographic': '\u3000$legado',
    'nnbsp': '\u202F$legado',
    'thin': '\u2009$legado',
  };
  for (final e in unicodePads.entries) {
    await c.expectDenied(
      id: 'AO1.legacy-pad-${e.key}',
      lens: 'AO1',
      title: 'plain Seguro card via pad Unicode ${e.key} (SQL ^\\s* vs Dart trim)',
      hit: await c.msg(chatId, e.value, jwt: c.buyerJwt!, sender: c.buyerId),
      actor: 'buyer JWT',
      pre: 'forged_seguro_plain usa ^\\s*; Flutter trim()+startsWith Compra paga',
      repro: 'POST chat_messages text=U+${e.key}+Compra paga através… (4321,00 €)',
      evidence: {'pad': e.key, 'stored': e.value},
    );
  }

  // -------------------------------------------------------------------------
  // AO2 — prefixo / encoding (não ZWSP exacto)
  // -------------------------------------------------------------------------
  final ghost = jsonEncode({
    'kind': 'cancel_request_outcome',
    'order_id': oid,
    'outcome': 'rejected',
    'display': 'Pedido atualizado',
  });
  final prefixVariants = <String, String>{
    'nbsp-prefix': '\u00A0FLEABER_JSON_V1:$ghost',
    'emspace-prefix': '\u2003FLEABER_JSON_V1:$ghost',
    'tab-prefix': '\tFLEABER_JSON_V1:$ghost',
    'fullwidth-colon': 'FLEABER_JSON_V1\uFF1A$ghost',
    'lower-prefix': 'fleaber_json_v1:$ghost',
    'newline-after': 'FLEABER_JSON_V1:\n$ghost',
    'double-prefix': 'FLEABER_JSON_V1:FLEABER_JSON_V1:$ghost',
    'bom-after-prefix': 'FLEABER_JSON_V1:\uFEFF$ghost',
  };
  for (final e in prefixVariants.entries) {
    final hit = await c.msg(chatId, e.value, jwt: c.sellerJwt!, sender: c.sellerId);
    if (hit.ok) {
      final stored = hit.map?['text']?.toString() ?? '';
      final looksCard = stored.startsWith('FLEABER_JSON_V1:');
      c.hold(
        id: 'AO2.prefix-${e.key}',
        lens: 'AO2',
        severity: looksCard ? 'P2' : 'P3',
        title: looksCard
            ? 'prefixo variante ${e.key} gravou card parseável'
            : 'prefixo variante ${e.key} gravou bolha JSON crua',
        actor: 'seller JWT',
        pre: 'strip Cf/BOM; cliente só startsWith(FLEABER_JSON_V1:)',
        repro: 'POST text=${e.key}',
        expected: '4xx ou texto não-card',
        obtained: hit.brief,
        evidence: {
          'stored_starts_prefix': looksCard,
          'stored_len': stored.length,
        },
      );
    } else {
      c.block('AO2.prefix-${e.key}', 'AO2', 'prefixo ${e.key}', hit);
    }
  }

  // Kind unicode-escape (jsonb decodifica) — server-only
  await c.expectDenied(
    id: 'AO2.kind-unicode-escape-server',
    lens: 'AO2',
    title: 'kind \\u0073eguro_fleaber_paid via escape',
    hit: await c.msg(
      chatId,
      'FLEABER_JSON_V1:{"kind":"\\u0073eguro_fleaber_paid","order_id":"$oid","total":$totalEur}',
      jwt: c.buyerJwt!,
      sender: c.buyerId,
    ),
    actor: 'buyer JWT',
    pre: 'jsonb unescapes kind',
    repro: 'POST kind=\\u0073eguro_fleaber_paid',
  );

  await c.expectDenied(
    id: 'AO2.kind-unknown',
    lens: 'AO2',
    title: 'kind payment_confirmed fora da allowlist',
    hit: await c.msg(
      chatId,
      fj({'kind': 'payment_confirmed', 'order_id': oid, 'total': 99}),
      jwt: c.buyerJwt!,
      sender: c.buyerId,
    ),
    actor: 'buyer JWT',
    pre: 'allowlist kinds',
    repro: 'POST kind=payment_confirmed',
  );

  // -------------------------------------------------------------------------
  // AO3 — cronologia
  // -------------------------------------------------------------------------
  final back = await c.msg(
    chatId,
    'RTAO ping cronologia',
    jwt: c.buyerJwt!,
    sender: c.buyerId,
    createdAt: '2020-01-01T00:00:00Z',
  );
  if (back.ok) {
    final storedAt = back.map?['created_at']?.toString() ?? '';
    final is2020 = storedAt.startsWith('2020');
    if (is2020) {
      c.hold(
        id: 'AO3.created-at-backdate',
        lens: 'AO3',
        severity: 'P2',
        title: 'INSERT chat_messages aceita created_at=2020',
        actor: 'buyer JWT',
        pre: 'guard_insert deve forçar NEW.created_at := now()',
        repro: 'POST chat_messages created_at=2020-01-01',
        expected: 'created_at ≈ now()',
        obtained: storedAt,
      );
    } else {
      c.block('AO3.created-at-backdate', 'AO3', 'created_at forçado now()', back);
    }
  } else {
    c.block('AO3.created-at-backdate', 'AO3', 'INSERT com created_at 2020', back);
  }

  if (back.firstId != null) {
    final patchAt = await c.rest(
      'PATCH',
      'chat_messages?id=eq.${back.firstId}',
      jwt: c.buyerJwt,
      body: {'created_at': '2020-01-01T00:00:00Z'},
    );
    await c.expectDenied(
      id: 'AO3.patch-created-at',
      lens: 'AO3',
      title: 'PATCH created_at de mensagem própria para 2020',
      hit: patchAt,
      actor: 'buyer JWT',
      pre: 'mensagem própria',
      repro: 'PATCH chat_messages created_at=2020',
    );
  }

  final inboxPast = await c.patchChat(
    chatId,
    {'last_message': 'ola rtao', 'last_message_time': '2020-01-01T00:00:00Z'},
    jwt: c.buyerJwt,
  );
  if (inboxPast.ok) {
    final t = inboxPast.map?['last_message_time']?.toString() ?? '';
    if (t.startsWith('2020')) {
      c.hold(
        id: 'AO3.inbox-time-backdate',
        lens: 'AO3',
        severity: 'P2',
        title: 'PATCH last_message_time=2020 persistiu',
        actor: 'buyer JWT',
        pre: 'chats_guard_update clampa < now-30s',
        repro: 'PATCH chats last_message_time=2020',
        expected: 'clamped to now()',
        obtained: t,
      );
    } else {
      c.block('AO3.inbox-time-backdate', 'AO3', 'time clamped', inboxPast);
    }
  } else {
    c.block('AO3.inbox-time-backdate', 'AO3', 'PATCH last_message_time', inboxPast);
  }

  // -------------------------------------------------------------------------
  // AO4 — URLs / provas (não fleaber.app exact, não signed denied exact)
  // -------------------------------------------------------------------------
  final evilUrls = <String, String>{
    'data': 'data:text/html,<h1>pwn</h1>',
    'js': 'javascript:alert(1)',
    'vbscript': 'vbscript:msgbox(1)',
    'protocol-rel': '//evil.example/x.png',
    'public-bucket':
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/avatars/x.png',
    'render':
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/render/image/public/avatars/x',
    'userinfo':
        'https://fxdknzrqjenzqcvnwqqq.supabase.co.evil@attacker.example/x',
    'nl-inject':
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/x\nhttps://evil.example',
  };
  for (final e in evilUrls.entries) {
    await c.expectDenied(
      id: 'AO4.proof-${e.key}',
      lens: 'AO4',
      title: 'proof_url ${e.key}',
      hit: await c.msg(
        chatId,
        fj({
          'kind': 'reservation_payment_submitted',
          'order_id': oid,
          'proof_url': e.value,
        }),
        jwt: c.buyerJwt!,
        sender: c.buyerId,
      ),
      actor: 'buyer JWT',
      pre: 'assert proof_url allowlist fleaber_private',
      repro: 'POST proof_url=${e.key}',
    );
  }

  // chat_image: path próprio + url noutro sítio do storage
  await c.expectDenied(
    id: 'AO4.chat-image-public-url',
    lens: 'AO4',
    title: 'chat_image path próprio + url object/public',
    hit: await c.msg(
      chatId,
      fj({
        'kind': 'chat_image',
        'path': 'chat_uploads/${c.buyerId}/rtao.png',
        'url':
            'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/avatars/x.png',
      }),
      jwt: c.buyerJwt!,
      sender: c.buyerId,
    ),
    actor: 'buyer JWT',
    pre: 'chat_image url só precisa supabase.co/storage/%',
    repro: 'POST chat_image url=.../object/public/avatars/x.png',
  );

  await c.expectDenied(
    id: 'AO4.chat-image-js',
    lens: 'AO4',
    title: 'chat_image url javascript:',
    hit: await c.msg(
      chatId,
      fj({
        'kind': 'chat_image',
        'path': 'chat_uploads/${c.buyerId}/rtao.png',
        'url': 'javascript:alert(1)',
      }),
      jwt: c.buyerJwt!,
      sender: c.buyerId,
    ),
    actor: 'buyer JWT',
    pre: 'url javascript',
    repro: 'POST chat_image url=javascript:',
  );

  await c.expectDenied(
    id: 'AO4.chat-image-path-traversal',
    lens: 'AO4',
    title: 'chat_image path traversal',
    hit: await c.msg(
      chatId,
      fj({
        'kind': 'chat_image',
        'path': 'chat_uploads/${c.buyerId}/../../order_proofs/x.png',
      }),
      jwt: c.buyerJwt!,
      sender: c.buyerId,
    ),
    actor: 'buyer JWT',
    pre: 'path like %..%',
    repro: 'POST chat_image path=.../../..',
  );

  // XSS em notes (HTML) — se gravar, card mostra texto cru
  await c.expectDenied(
    id: 'AO4.notes-html',
    lens: 'AO4',
    title: 'notes HTML/img em comprovativo',
    hit: await c.msg(
      chatId,
      fj({
        'kind': 'reservation_payment_submitted',
        'order_id': oid,
        'notes': '<img src=x onerror=alert(1)> ver comprovativo',
      }),
      jwt: c.buyerJwt!,
      sender: c.buyerId,
    ),
    actor: 'buyer JWT',
    pre: 'Flutter Text() não executa HTML; gravar = P3',
    repro: 'POST notes=<img onerror>',
    severityIfOpen: 'P3',
  );

  // -------------------------------------------------------------------------
  // AO5 — inbox / delete
  // -------------------------------------------------------------------------
  final inboxLies = <String, String>{
    'wise': 'Wise 50€',
    'revolut': 'Revolut 12€ confirmado',
    'mbway-aprovado': 'MB WAY aprovado',
    'pagamento-recebido': 'Pagamento recebido',
    'transf-confirmada': 'Transferência confirmada',
    'recebi-wise': 'Recebi no Wise',
  };
  for (final e in inboxLies.entries) {
    await c.expectDenied(
      id: 'AO5.inbox-${e.key}',
      lens: 'AO5',
      title: 'inbox last_message "${e.value}"',
      hit: await c.patchChat(chatId, {'last_message': e.value}, jwt: c.buyerJwt),
      actor: 'buyer JWT',
      pre: 'forged_inbox_preview = payment_lie_text',
      repro: 'PATCH chats last_message=${e.value}',
    );
  }

  // DELETE de card FLEABER (imutável)
  final harmless = await c.msg(
    chatId,
    fj({
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'comprovativo rtao',
    }),
    jwt: c.buyerJwt!,
    sender: c.buyerId,
  );
  if (harmless.ok && harmless.firstId != null) {
    c.block('AO1.notes-benign', 'AO1', 'notes benignas aceites', harmless);
    final del = await c.rest(
      'DELETE',
      'chat_messages?id=eq.${harmless.firstId}',
      jwt: c.buyerJwt,
    );
    await c.expectDenied(
      id: 'AO5.delete-json-card',
      lens: 'AO5',
      title: 'DELETE card FLEABER_JSON_V1',
      hit: del,
      actor: 'buyer JWT',
      pre: 'mensagem própria kind=reservation_payment_submitted',
      repro: 'DELETE chat_messages id=card',
    );
    final patchTxt = await c.rest(
      'PATCH',
      'chat_messages?id=eq.${harmless.firstId}',
      jwt: c.buyerJwt,
      body: {'text': 'apagado'},
    );
    await c.expectDenied(
      id: 'AO5.patch-json-card',
      lens: 'AO5',
      title: 'PATCH text de card FLEABER_JSON_V1',
      hit: patchTxt,
      actor: 'buyer JWT',
      pre: 'card próprio',
      repro: 'PATCH text=apagado',
    );
  } else {
    c.note('AO1.notes-benign', 'notes benignas recusadas?', harmless.brief,
        lens: 'AO1');
  }

  // -------------------------------------------------------------------------
  // AO6 — storage
  // -------------------------------------------------------------------------
  final ownProof =
      'order_proofs/${c.buyerId}/$oid/${prefix}-own.png';
  final upOwn = await c.storagePut(ownProof, png, jwt: c.buyerJwt!);
  if (upOwn.ok) {
    c.block('AO6.upload-own', 'AO6', 'upload order_proofs próprio', upOwn);
    final signOwn = await c.storageSign(ownProof, jwt: c.buyerJwt!);
    if (signOwn.ok) {
      c.block('AO6.sign-own', 'AO6', 'sign próprio', signOwn);
      final signedPath = signOwn.map?['signedURL']?.toString() ??
          signOwn.map?['signedUrl']?.toString() ??
          '';
      // signed URL no card — AHAM diz aceite; confirmar e ver se path alheio também
      if (signedPath.isNotEmpty) {
        final abs = signedPath.startsWith('http')
            ? signedPath
            : '${c.url}$signedPath';
        final withSigned = await c.msg(
          chatId,
          fj({
            'kind': 'reservation_payment_submitted',
            'order_id': oid,
            'proof_url': abs,
          }),
          jwt: c.buyerJwt!,
          sender: c.buyerId,
        );
        if (withSigned.ok) {
          c.block('AO4.signed-own-accepted', 'AO4',
              'signed proof próprio aceite (AHAM)', withSigned);
        } else {
          c.note('AO4.signed-own', 'signed próprio recusado?', withSigned.brief,
              lens: 'AO4');
        }
      }
    } else {
      c.note('AO6.sign-own', 'sign próprio falhou', signOwn.brief, lens: 'AO6');
    }
    final upsert = await c.storagePut(ownProof, png,
        jwt: c.buyerJwt!, upsert: true);
    await c.expectDenied(
      id: 'AO6.upsert-own',
      lens: 'AO6',
      title: 'upsert overwrite prova própria',
      hit: upsert,
      actor: 'buyer JWT',
      pre: 'policy sem UPDATE em order_proofs',
      repro: 'POST storage x-upsert=true mesmo path',
    );
  } else {
    c.note('AO6.upload-own', 'upload próprio falhou', upOwn.brief, lens: 'AO6');
  }

  if (c.buyer2Id != null && c.buyer2Jwt != null) {
    final alienPath =
        'order_proofs/${c.buyer2Id}/$oid/${prefix}-alien.png';
    final upAlien = await c.storagePut(alienPath, png, jwt: c.buyerJwt!);
    await c.expectDenied(
      id: 'AO6.upload-b2-path',
      lens: 'AO6',
      title: 'buyer1 faz upload em order_proofs/buyer2/order',
      hit: upAlien,
      actor: 'buyer JWT',
      pre: 'path buyer2 + order B1',
      repro: 'POST storage order_proofs/{b2}/{oid}/x.png',
    );

    final signAlien = await c.storageSign(
      'order_proofs/${c.buyer2Id}/x.png',
      jwt: c.buyerJwt!,
    );
    await c.expectDenied(
      id: 'AO6.sign-b2-path',
      lens: 'AO6',
      title: 'buyer1 pede signed URL de path buyer2',
      hit: signAlien,
      actor: 'buyer JWT',
      pre: 'createSignedUrl path alheio',
      repro: 'POST /object/sign/fleaber_private/order_proofs/{b2}/x.png',
    );

    final signAsB2 = await c.storageSign(ownProof, jwt: c.buyer2Jwt!);
    await c.expectDenied(
      id: 'AO6.b2-sign-b1-proof',
      lens: 'AO6',
      title: 'buyer2 signed URL da prova do buyer1',
      hit: signAsB2,
      actor: 'buyer2 JWT',
      pre: 'order_proofs/B1/oid',
      repro: 'POST sign path B1 com JWT B2',
    );
  }

  // -------------------------------------------------------------------------
  // AO7 — cross-user
  // -------------------------------------------------------------------------
  if (c.buyer2Jwt != null && c.buyer2Id != null) {
    await c.expectDenied(
      id: 'AO7.b2-insert-thread',
      lens: 'AO7',
      title: 'B2 insere mensagem no chat B1-S1',
      hit: await c.msg(chatId, 'ola do b2', jwt: c.buyer2Jwt!, sender: c.buyer2Id),
      actor: 'buyer2 JWT',
      pre: 'B2 não é participante',
      repro: 'POST chat_messages chat_id=B1-S1',
    );

    final read = await c.rest(
      'GET',
      'chat_messages?chat_id=eq.$chatId&select=id,text&limit=3',
      jwt: c.buyer2Jwt,
    );
    final leaked = read.ok && read.list.isNotEmpty;
    if (leaked) {
      c.hold(
        id: 'AO7.b2-read-thread',
        lens: 'AO7',
        severity: 'P1',
        title: 'B2 lê mensagens do chat B1-S1',
        actor: 'buyer2 JWT',
        pre: 'RLS chat_messages só participantes',
        repro: 'GET chat_messages?chat_id=eq.B1-S1',
        expected: '200 []',
        obtained: '${read.status} n=${read.list.length}',
      );
    } else {
      c.block('AO7.b2-read-thread', 'AO7', 'B2 GET vazio/403', read);
    }

    await c.expectDenied(
      id: 'AO7.b2-patch-inbox',
      lens: 'AO7',
      title: 'B2 PATCH last_message do chat alheio',
      hit: await c.patchChat(chatId, {'last_message': 'rtao b2'}, jwt: c.buyer2Jwt),
      actor: 'buyer2 JWT',
      pre: 'chat B1-S1',
      repro: 'PATCH chats last_message',
    );

    await c.expectDenied(
      id: 'AO7.seller-buyer-only-kind',
      lens: 'AO7',
      title: 'seller injecta kind buyer-only seguro_fleaber_paid',
      hit: await c.msg(
        chatId,
        fj({
          'kind': 'seguro_fleaber_paid',
          'order_id': oid,
          'total': num.parse(totalEur),
        }),
        jwt: c.sellerJwt!,
        sender: c.sellerId,
      ),
      actor: 'seller JWT',
      pre: 'kind buyer-only',
      repro: 'POST seguro_fleaber_paid como seller',
    );

    await c.expectDenied(
      id: 'AO7.buyer-seller-only-kind',
      lens: 'AO7',
      title: 'buyer injecta cancel_request_outcome (seller-only)',
      hit: await c.msg(
        chatId,
        fj({
          'kind': 'cancel_request_outcome',
          'order_id': oid,
          'outcome': 'rejected',
          'display': 'Pedido atualizado',
        }),
        jwt: c.buyerJwt!,
        sender: c.buyerId,
      ),
      actor: 'buyer JWT',
      pre: 'kind seller-only',
      repro: 'POST cancel_request_outcome como buyer',
    );

    final notif = await c.rest('POST', 'user_notifications', jwt: c.buyerJwt, body: {
      'user_id': c.sellerId,
      'kind': 'price_offer',
      'title': 'MB WAY 50€ confirmado',
    });
    await c.expectDenied(
      id: 'AO7.notify-other',
      lens: 'AO7',
      title: 'buyer INSERT notificação no seller',
      hit: notif,
      actor: 'buyer JWT',
      pre: 'user_notifications RLS insert own',
      repro: 'POST user_notifications user_id=seller',
    );
  }

  // -------------------------------------------------------------------------
  // AO8 — mentira UI sem mint (controlo livros)
  // -------------------------------------------------------------------------
  final wallets1 = await c.wallets();
  final o1 = await c.orderRow(oid);
  final mint = (numOf(wallets1['buyer']) ?? 0) != (numOf(wallets0['buyer']) ?? 0) ||
      (numOf(wallets1['seller']) ?? 0) != (numOf(wallets0['seller']) ?? 0);
  final statusChanged = '${o1?['status']}' != '${o0?['status']}';
  final paidChanged =
      '${o1?['amount_paid_cents']}' != '${o0?['amount_paid_cents']}';
  if (mint || statusChanged || paidChanged) {
    c.hold(
      id: 'AO8.books-moved',
      lens: 'AO8',
      severity: 'P0',
      title: 'INSERT chat alterou wallet/status/paid sem Edge',
      actor: 'JWT',
      pre: 'só POST chat_messages / PATCH chats',
      repro: 'comparar wallets+order antes/depois',
      expected: 'Δwallet=0 status/paid iguais',
      obtained: {
        'wallets0': wallets0,
        'wallets1': wallets1,
        'status0': o0?['status'],
        'status1': o1?['status'],
        'paid0': o0?['amount_paid_cents'],
        'paid1': o1?['amount_paid_cents'],
      },
    );
  } else {
    c.block('AO8.books-held', 'AO8', 'wallets/status/paid intactos', {
      'wallets': wallets1,
      'status': o1?['status'],
      'paid': o1?['amount_paid_cents'],
    });
  }

  // Edge create-payment-intent com chat_text hostil (se o body for ignorado)
  final edgeChat = await c.edge('create-payment-intent', {
    'buyer_id': c.buyerId,
    'order_id': oid,
    'amount': 1,
    'currency': 'eur',
    'shipping_method': 'mao',
    'chat_text':
        'FLEABER_JSON_V1:{"kind":"seguro_fleaber_paid","order_id":"$oid","total":4321}',
  }, jwt: c.buyerJwt);
  c.note('AO8.edge-chat-text', 'body chat_text no checkout', edgeChat.brief,
      lens: 'AO8');

  await c.dumpAll('pass1.json');
  stdout.writeln(
      'DONE findings=${c.findings.length} blocked=${c.blocked.length} skipped=${c.skipped.length}');
  stdout.writeln('lenses=${c.lensesHit.toList()..sort()}');
}
