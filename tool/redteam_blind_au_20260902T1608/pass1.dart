/// RED TEAM CEGO AU pass1 — variantes NOVAS pós-ANAS (não AO/AI exact).
/// Klarna/Sofort/iDEAL/cartão, homoglyphs novos, sign outro bucket,
/// inbox emoji €, created_at PATCH, kind homoglyph.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '_rtau.dart';

final png = Uint8List.fromList(base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
));

Future<void> main() async {
  final c = Rtau.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  final chatId = await c.ensureChat();
  if (chatId == null) {
    stderr.writeln('no chat');
    exit(4);
  }
  c.note('actors', 'ids', {
    'buyer': c.buyerId,
    'seller': c.sellerId,
    'buyer2': c.buyer2Id,
    'chat': chatId,
  });

  final paid = await c.payToPago(lens: 'AU8');
  final reserved = await c.insertReserved();
  c.note('fixture.ids', 'paid/reserved', {
    'paid': paid?.oid,
    'reserved': reserved?.oid,
    'paid_pi': paid?.pi,
  });

  double? totalEur;
  if (paid != null) {
    final cents = numOf((await c.orderRow(paid.oid))?['amount_paid_cents']);
    totalEur = cents == null ? 12.0 : cents / 100.0;
  }

  // =========================================================================
  // AU1 — Cards vs BD: rails novos (Klarna/Sofort/iDEAL/cartão)
  // =========================================================================
  if (reserved != null) {
    for (final e in <String, String>{
      'klarna-notes': 'Klarna 50€ confirmado',
      'sofort-notes': 'Sofort 18,50 EUR aprovado',
      'ideal-notes': 'iDEAL 18.50€ feito',
      'cartao-notes': 'Pago com cartão 18.50€',
      'googlepay-notes': 'Google Pay 18.50€ caiu',
      'alipay-notes': 'Alipay 18.50€ recebido',
      'twint-notes': 'Twint 18.50€ processado',
      'multibanco-notes': 'Multibanco 18.50€ aprovado',
    }.entries) {
      await c.expectDenied(
        id: 'AU1.notes.${e.key}',
        lens: 'AU1',
        title: 'reservation_payment_submitted notes=${e.value}',
        hit: await c.msg(
          chatId,
          fj({
            'kind': 'reservation_payment_submitted',
            'order_id': reserved.oid,
            'notes': e.value,
          }),
          jwt: c.buyerJwt!,
          sender: c.buyerId,
        ),
        actor: 'buyer JWT',
        pre: 'denylist ANAS sem Klarna/Sofort/iDEAL/cartão/Google Pay',
        repro: 'POST notes=${e.value}',
        severityIfOpen: 'P2',
        evidence: {'notes': e.value},
      );
    }

    await c.expectDenied(
      id: 'AU1.cancel.klarna-display',
      lens: 'AU1',
      title: 'cancel_request_outcome display Klarna',
      hit: await c.msg(
        chatId,
        fj({
          'kind': 'cancel_request_outcome',
          'order_id': reserved.oid,
          'outcome': 'rejected',
          'display': 'Klarna 99€ confirmado',
        }),
        jwt: c.sellerJwt!,
        sender: c.sellerId,
      ),
      actor: 'seller JWT',
      pre: 'display só corre payment_lie_text (sem Klarna)',
      repro: 'POST cancel_request_outcome display=Klarna 99€ confirmado',
      severityIfOpen: 'P2',
    );
  }

  if (paid != null && totalEur != null) {
    for (final e in <String, String>{
      'klarna': 'Klarna',
      'klarna-amt': 'Klarna ${totalEur.toStringAsFixed(2)}€',
      'klarna-lie-amt': 'Klarna 999.00€',
      'sofort': 'Sofort',
      'ideal': 'iDEAL',
      'cartao': 'Cartão',
      'google-pay': 'Google Pay',
      'samsung-pay': 'Samsung Pay',
      'alipay': 'Alipay',
      'giropay': 'Giropay',
      'bancontact': 'Bancontact',
      'twint': 'Twint',
      'multibanco': 'Multibanco',
    }.entries) {
      await c.expectDenied(
        id: 'AU1.seguro.label.${e.key}',
        lens: 'AU1',
        title: 'seguro_fleaber_paid label=${e.value}',
        hit: await c.msg(
          chatId,
          fj({
            'kind': 'seguro_fleaber_paid',
            'order_id': paid.oid,
            'total': totalEur,
            'label': e.value,
          }),
          jwt: c.buyerJwt!,
          sender: c.buyerId,
        ),
        actor: 'buyer JWT',
        pre: 'order pago Stripe TEST; ANAS label denylist sem estes rails',
        repro: 'POST seguro_fleaber_paid label=${e.value} total=BD',
        severityIfOpen: 'P2',
        evidence: {'label': e.value, 'total': totalEur},
      );
    }
  }

  // =========================================================================
  // AU2 — Prefixo / encoding / homoglyphs NOVOS (não cirílico еаорс already)
  // =========================================================================
  if (paid != null && totalEur != null) {
    const dze = '\u0455'; // ѕ cyrillic dze — NÃO está no translate ANAS (só с U+0441)
    const greekO = '\u03BF'; // ο
    const fullS = '\uFF53'; // ｓ
    const smallCapS = '\u1D1A'; // ᴚ no; use ꜱ U+A731
    const latinLongS = '\u017F'; // ſ
    const greekKappa = '\u039A'; // Κ

    for (final e in <String, String>{
      'cyr-dze-kind': '${dze}eguro_fleaber_paid',
      'greek-o-kind': 'segur${greekO}_fleaber_paid',
      'fullwidth-s-kind': '${fullS}eguro_fleaber_paid',
      'smallcap-s-kind': '\uA731eguro_fleaber_paid',
      'long-s-kind': '${latinLongS}eguro_fleaber_paid',
      'ascii-s-kind': '\u0073eguro_fleaber_paid', // pedido AU; não é homoglyph real
    }.entries) {
      await c.expectDenied(
        id: 'AU2.kind.${e.key}',
        lens: 'AU2',
        title: 'kind homoglyph ${e.key}',
        hit: await c.msg(
          chatId,
          fj({
            'kind': e.value,
            'order_id': paid.oid,
            'total': totalEur,
            'label': 'Pago',
          }),
          jwt: c.buyerJwt!,
          sender: c.buyerId,
        ),
        actor: 'buyer JWT',
        pre: 'allowlist kind exact after lower(trim)',
        repro: 'POST kind=${e.value}',
        severityIfOpen: 'P2',
      );
    }

    if (reserved != null) {
      await c.expectDenied(
        id: 'AU2.notes.fullwidth-klarna',
        lens: 'AU2',
        title: 'notes Ｋlarna fullwidth + 50€',
        hit: await c.msg(
          chatId,
          fj({
            'kind': 'reservation_payment_submitted',
            'order_id': reserved.oid,
            'notes': '\uFF2Blarna 50€ confirmado',
          }),
          jwt: c.buyerJwt!,
          sender: c.buyerId,
        ),
        actor: 'buyer JWT',
        pre: 'normalize_lie lower+cyrillic; fullwidth K não mapeado',
        repro: 'POST notes=U+FF2B larna 50€ confirmado',
        severityIfOpen: 'P2',
      );
      await c.expectDenied(
        id: 'AU2.notes.greek-kappa-klarna',
        lens: 'AU2',
        title: 'notes Κlarna (Greek kappa)',
        hit: await c.msg(
          chatId,
          fj({
            'kind': 'reservation_payment_submitted',
            'order_id': reserved.oid,
            'notes': '${greekKappa}larna 50€ confirmado',
          }),
          jwt: c.buyerJwt!,
          sender: c.buyerId,
        ),
        actor: 'buyer JWT',
        pre: 'Greek kappa não está no translate ANAS',
        repro: 'POST notes=Κlarna 50€ confirmado',
        severityIfOpen: 'P2',
      );
    }

    await c.expectDenied(
      id: 'AU2.seguro.label.greek-klarna',
      lens: 'AU2',
      title: 'seguro label Κlarna',
      hit: await c.msg(
        chatId,
        fj({
          'kind': 'seguro_fleaber_paid',
          'order_id': paid.oid,
          'total': totalEur,
          'label': '${greekKappa}larna',
        }),
        jwt: c.buyerJwt!,
        sender: c.buyerId,
      ),
      actor: 'buyer JWT',
      pre: 'label denylist sem Klarna; homoglyph Greek',
      repro: 'POST label=Κlarna',
      severityIfOpen: 'P2',
    );

    // Hangul filler / Braille blank prefix (não NBSP/Zs da lista AO)
    const hangulFiller = '\u3164';
    const brailleBlank = '\u2800';
    const choseong = '\u115F';
    final ghost = jsonEncode({
      'kind': 'seguro_fleaber_paid',
      'order_id': paid.oid,
      'total': totalEur,
      'label': 'Klarna',
    });
    for (final e in <String, String>{
      'hangul-filler': '$hangulFiller' 'FLEABER_JSON_V1:$ghost',
      'braille-blank': '$brailleBlank' 'FLEABER_JSON_V1:$ghost',
      'choseong-filler': '$choseong' 'FLEABER_JSON_V1:$ghost',
    }.entries) {
      await c.expectDenied(
        id: 'AU2.prefix.${e.key}',
        lens: 'AU2',
        title: 'prefix ${e.key} + FLEABER_JSON_V1',
        hit: await c.msg(
          chatId,
          e.value,
          jwt: c.buyerJwt!,
          sender: c.buyerId,
        ),
        actor: 'buyer JWT',
        pre: 'assert exige startsWith FLEABER; strip_unicode_ws sem Hangul/Braille',
        repro: 'POST text=U+xxxx + FLEABER_JSON_V1:seguro…',
        severityIfOpen: 'P3',
      );
    }
  }

  // =========================================================================
  // AU3 — Cronologia: created_at INSERT/PATCH (não last_message_time AO)
  // =========================================================================
  final backdated = await c.msg(
    chatId,
    'RTAU ping backdate',
    jwt: c.buyerJwt!,
    sender: c.buyerId,
    createdAt: '2020-01-01T00:00:00Z',
  );
  if (backdated.ok) {
    final row = await c.getMsg(backdated.firstId!);
    final ts = row?['created_at']?.toString() ?? '';
    final is2020 = ts.startsWith('2020');
    if (is2020) {
      c.hold(
        id: 'AU3.msg.insert-created-at-2020',
        lens: 'AU3',
        severity: 'P3',
        title: 'INSERT chat_messages created_at=2020 persistiu',
        actor: 'buyer JWT',
        pre: 'guard_update sela created_at no UPDATE; INSERT pode aceitar',
        repro: 'POST chat_messages created_at=2020-01-01T00:00:00Z',
        expected: 'created_at ≈ now()',
        obtained: ts,
        evidence: {'id': backdated.firstId, 'created_at': ts},
      );
    } else {
      c.block('AU3.msg.insert-created-at-2020', 'AU3',
          'INSERT created_at clamped', ts);
    }
  } else {
    c.block('AU3.msg.insert-created-at-2020', 'AU3', 'INSERT created_at denied',
        backdated);
  }

  if (backdated.firstId != null) {
    final patchAt = await c.patchMsg(
      backdated.firstId!,
      {'created_at': '2019-06-01T00:00:00Z'},
      jwt: c.buyerJwt,
    );
    final after = await c.getMsg(backdated.firstId!);
    final ts = after?['created_at']?.toString() ?? '';
    if (ts.startsWith('2019')) {
      c.hold(
        id: 'AU3.msg.patch-created-at-2019',
        lens: 'AU3',
        severity: 'P2',
        title: 'PATCH created_at=2019 persistiu',
        actor: 'buyer JWT',
        pre: 'guard_update NEW.created_at := OLD.created_at',
        repro: 'PATCH chat_messages created_at=2019-06-01',
        expected: 'created_at inalterado',
        obtained: ts,
      );
    } else {
      c.block(
        'AU3.msg.patch-created-at-2019',
        'AU3',
        'PATCH created_at não colou (${patchAt.status}) $ts',
        patchAt,
      );
    }
  }

  // =========================================================================
  // AU4 — URLs / provas: sign outro bucket; path no query; authenticated
  // =========================================================================
  final imgPath = 'chat_uploads/${c.buyerId}/$chatId/rtau.png';
  final putOwn = await c.storagePut(imgPath, png, jwt: c.buyerJwt!);
  c.note('AU4.put-own', 'upload chat_uploads', putOwn.brief, lens: 'AU4');
  final signOwn = await c.storageSign(imgPath, jwt: c.buyerJwt!);
  c.note('AU4.sign-own', 'sign own', signOwn.brief, lens: 'AU4');

  final avatarsPut = await c.req(
    'POST',
    '/storage/v1/object/avatars/${Uri.encodeFull('rtau-$stamp.png')}',
    jwt: c.buyerJwt,
    bytes: png,
    contentType: 'image/png',
  );
  c.note('AU4.put-avatars', 'upload avatars', avatarsPut.brief, lens: 'AU4');
  final avatarsSign = await c.storageSignOther(
    'avatars',
    'rtau-$stamp.png',
    jwt: c.buyerJwt!,
  );
  c.note('AU4.sign-avatars', 'sign avatars', avatarsSign.brief, lens: 'AU4');

  String? signedAvatarsUrl;
  final am = avatarsSign.map;
  if (am != null) {
    final u = (am['signedURL'] ?? am['signedUrl'] ?? am['url'])?.toString();
    if (u != null && u.isNotEmpty) {
      signedAvatarsUrl = u.startsWith('http') ? u : '${c.url}$u';
    }
  }

  if (signedAvatarsUrl != null) {
    final decoy =
        '$signedAvatarsUrl${signedAvatarsUrl.contains('?') ? '&' : '?'}p=$imgPath';
    await c.expectDenied(
      id: 'AU4.image.sign-avatars-path-query',
      lens: 'AU4',
      title: 'chat_image url=sign/avatars + path no query',
      hit: await c.msg(
        chatId,
        fj({
          'kind': 'chat_image',
          'path': imgPath,
          'url': decoy,
        }),
        jwt: c.buyerJwt!,
        sender: c.buyerId,
      ),
      actor: 'buyer JWT',
      pre: 'ANAS: sign/ qualquer bucket se path ⊂ url',
      repro: 'POST chat_image url=sign/avatars/…?p=chat_uploads/{uid}/…',
      severityIfOpen: 'P2',
      evidence: {'url': decoy},
    );
  }

  await c.expectDenied(
    id: 'AU4.image.sign-other-bucket-no-query',
    lens: 'AU4',
    title: 'chat_image url=sign/avatars sem path no url',
    hit: await c.msg(
      chatId,
      fj({
        'kind': 'chat_image',
        'path': imgPath,
        'url':
            'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/avatars/rtau.png?token=x',
      }),
      jwt: c.buyerJwt!,
      sender: c.buyerId,
    ),
    actor: 'buyer JWT',
    pre: 'path não está na url; url não é chat_uploads/sender',
    repro: 'POST chat_image url=…/object/sign/avatars/rtau.png',
    severityIfOpen: 'P2',
  );

  await c.expectDenied(
    id: 'AU4.image.authenticated-avatars',
    lens: 'AU4',
    title: 'chat_image url=object/authenticated/avatars',
    hit: await c.msg(
      chatId,
      fj({
        'kind': 'chat_image',
        'path': imgPath,
        'url':
            'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/authenticated/avatars/rtau.png?p=$imgPath',
      }),
      jwt: c.buyerJwt!,
      sender: c.buyerId,
    ),
    actor: 'buyer JWT',
    pre: 'ANAS permite authenticated/% sem restringir bucket',
    repro: 'POST authenticated/avatars + path no query',
    severityIfOpen: 'P2',
  );

  // UI legado: bolha de imagem a partir de URL http .png (não FLEABER_JSON)
  final legacyImg = await c.msg(
    chatId,
    'https://example.com/recibo-klarna-50eur.png',
    jwt: c.buyerJwt!,
    sender: c.buyerId,
  );
  if (legacyImg.ok) {
    c.hold(
      id: 'AU4.legacy-http-png-bubble',
      lens: 'AU4',
      severity: 'P3',
      title: 'texto http .png persiste (UI promove a bolha de imagem)',
      actor: 'buyer JWT',
      pre: '_chatImageUrlFromMessage: legado http + extensão imagem',
      repro: 'POST text=https://example.com/recibo-klarna-50eur.png',
      expected: 'texto simples ou 4xx se prova falsa',
      obtained: legacyImg.brief,
      evidence: {'id': legacyImg.firstId},
    );
  } else {
    c.block('AU4.legacy-http-png-bubble', 'AU4', 'http png denied', legacyImg);
  }

  if (reserved != null) {
    await c.expectDenied(
      id: 'AU4.proof.sign-other-bucket',
      lens: 'AU4',
      title: 'proof_url sign/avatars',
      hit: await c.msg(
        chatId,
        fj({
          'kind': 'reservation_payment_submitted',
          'order_id': reserved.oid,
          'proof_url':
              'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/avatars/rtau.png?token=x',
        }),
        jwt: c.buyerJwt!,
        sender: c.buyerId,
      ),
      actor: 'buyer JWT',
      pre: 'proof_url allowlist só fleaber_private',
      repro: 'POST proof_url=sign/avatars/…',
      severityIfOpen: 'P2',
    );
    await c.expectDenied(
      id: 'AU4.proof.authenticated-private',
      lens: 'AU4',
      title: 'proof_url object/authenticated/fleaber_private',
      hit: await c.msg(
        chatId,
        fj({
          'kind': 'reservation_payment_submitted',
          'order_id': reserved.oid,
          'proof_url':
              'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/authenticated/fleaber_private/order_proofs/${c.buyerId}/x.png',
        }),
        jwt: c.buyerJwt!,
        sender: c.buyerId,
      ),
      actor: 'buyer JWT',
      pre: 'allowlist sign/fleaber_private ou object/fleaber_private — sem authenticated',
      repro: 'POST proof_url=…/object/authenticated/fleaber_private/…',
      severityIfOpen: 'P3',
    );
  }

  // =========================================================================
  // AU5 — Inbox / delete: rails novos, emoji €, filler prefix DELETE
  // =========================================================================
  final inboxBefore = await c.rest(
    'GET',
    'chats?id=eq.$chatId&select=id,last_message,last_message_time',
    service: true,
  );
  final inboxBeforeText = inboxBefore.map?['last_message']?.toString();
  c.note('AU5.inbox.before', 'last_message', inboxBeforeText, lens: 'AU5');

  for (final e in <String, String>{
    'klarna-confirmado': 'Klarna confirmado',
    'sofort-feito': 'Sofort feito',
    'ideal-caiu': 'iDEAL caiu',
    'cartao-aprovado': 'cartão aprovado',
    'googlepay-ok': 'Google Pay processado',
    'recebi-emoji': 'Recebi \u{1F4B6}',
    'pagamento-moneybag': 'Pagamento \u{1F4B0}',
    'euro-emoji-only': 'Recebi \u{1F4B3}',
  }.entries) {
    final hit = await c.patchChat(
      chatId,
      {'last_message': e.value},
      jwt: c.buyerJwt,
    );
    final after = await c.rest(
      'GET',
      'chats?id=eq.$chatId&select=id,last_message',
      service: true,
    );
    final stored = after.map?['last_message']?.toString();
    if (hit.ok && stored == e.value) {
      c.hold(
        id: 'AU5.inbox.${e.key}',
        lens: 'AU5',
        severity: 'P2',
        title: 'Inbox last_message persistiu: ${e.value}',
        actor: 'buyer JWT',
        pre: 'inbox denylist sem Klarna; emoji 💶 ≠ €',
        repro: 'PATCH chats last_message=${e.value}; GET chats',
        expected: '4xx ou last_message inalterado',
        obtained: stored,
        evidence: {'patch': hit.brief, 'stored': stored},
      );
    } else {
      c.block(
        'AU5.inbox.${e.key}',
        'AU5',
        'inbox ${e.key} blocked/unchanged (${hit.status}) stored=$stored',
        hit,
      );
    }
  }

  // DELETE de card com Hangul filler prefix (não NBSP)
  if (paid != null && totalEur != null) {
    const hangulFiller = '\u3164';
    final filled =
        '$hangulFiller' 'FLEABER_JSON_V1:${jsonEncode({
          'kind': 'chat_image',
          'path': imgPath,
          'url': 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$imgPath',
        })}';
    final ins = await c.msg(
      chatId,
      filled,
      jwt: c.buyerJwt!,
      sender: c.buyerId,
    );
    c.note('AU5.hangul-insert', 'hangul+JSON insert', ins.brief, lens: 'AU5');
    if (ins.ok && ins.firstId != null) {
      final del = await c.rest(
        'DELETE',
        'chat_messages?id=eq.${ins.firstId}',
        jwt: c.buyerJwt,
        prefer: 'return=representation',
      );
      if (del.ok && (del.list.isNotEmpty || del.body.contains(ins.firstId!))) {
        c.hold(
          id: 'AU5.delete.hangul-filler-json',
          lens: 'AU5',
          severity: 'P3',
          title: 'DELETE removeu bolha Hangul-filler+FLEABER_JSON_V1',
          actor: 'buyer JWT',
          pre: 'guard_delete só NBSP/Zs + prefixo exacto',
          repro: 'POST U+3164+FLEABER_JSON_V1:… ; DELETE id',
          expected: '42501 chat_system_card_immutable',
          obtained: del.brief,
        );
      } else {
        c.block('AU5.delete.hangul-filler-json', 'AU5', 'DELETE blocked', del);
      }
    } else {
      c.block('AU5.hangul-insert', 'AU5', 'Hangul+JSON insert denied', ins);
    }
  }

  // =========================================================================
  // AU6 — Storage upsert / cross-user signed URL
  // =========================================================================
  if (c.buyer2Id != null && c.buyer2Jwt != null) {
    final b2Path = 'chat_uploads/${c.buyer2Id}/$chatId/stolen.png';
    final upsertAlien = await c.storagePut(
      'chat_uploads/${c.buyer2Id}/$chatId/stolen.png',
      png,
      jwt: c.buyerJwt!,
      upsert: true,
    );
    if (upsertAlien.ok) {
      c.hold(
        id: 'AU6.upsert.other-user-prefix',
        lens: 'AU6',
        severity: 'P1',
        title: 'buyer fez PUT no prefixo chat_uploads de B2',
        actor: 'buyer JWT',
        pre: 'storage policy path = auth.uid()',
        repro: 'POST /storage/v1/object/fleaber_private/chat_uploads/{b2}/…',
        expected: '4xx',
        obtained: upsertAlien.brief,
        evidence: {'path': b2Path},
      );
    } else {
      c.block('AU6.upsert.other-user-prefix', 'AU6', 'PUT pasta B2 denied',
          upsertAlien);
    }

    final signAlien = await c.storageSign(
      'chat_uploads/${c.buyerId}/$chatId/rtau.png',
      jwt: c.buyer2Jwt!,
    );
    if (signAlien.ok) {
      c.hold(
        id: 'AU6.sign.cross-user',
        lens: 'AU6',
        severity: 'P2',
        title: 'B2 assinou path chat_uploads do buyer',
        actor: 'buyer2 JWT',
        pre: 'sign só dono ou participante do chat',
        repro: 'POST /object/sign/fleaber_private/chat_uploads/{buyer}/…',
        expected: '4xx',
        obtained: signAlien.brief,
      );
    } else {
      c.block('AU6.sign.cross-user', 'AU6', 'B2 sign path buyer denied',
          signAlien);
    }
  }

  // =========================================================================
  // AU7 — Cross-user B2 thread / proofs
  // =========================================================================
  if (c.buyer2Jwt != null) {
    final readAlien = await c.rest(
      'GET',
      'chat_messages?chat_id=eq.$chatId&select=id,text,sender_id&limit=5',
      jwt: c.buyer2Jwt,
    );
    final leaked = readAlien.ok && readAlien.list.isNotEmpty;
    if (leaked) {
      c.hold(
        id: 'AU7.b2.read-thread',
        lens: 'AU7',
        severity: 'P1',
        title: 'B2 leu mensagens do chat B1-S1',
        actor: 'buyer2 JWT',
        pre: 'RLS chat_messages só participantes',
        repro: 'GET chat_messages?chat_id=eq.{chat B1-S1}',
        expected: '200 []',
        obtained: '${readAlien.status} n=${readAlien.list.length}',
      );
    } else {
      c.block('AU7.b2.read-thread', 'AU7', 'B2 GET thread vazio/denied',
          readAlien);
    }

    final insAlien = await c.msg(
      chatId,
      'RTAU b2 inject',
      jwt: c.buyer2Jwt!,
      sender: c.buyer2Id,
    );
    if (insAlien.ok) {
      c.hold(
        id: 'AU7.b2.insert-thread',
        lens: 'AU7',
        severity: 'P1',
        title: 'B2 inseriu mensagem no chat B1-S1',
        actor: 'buyer2 JWT',
        pre: 'não participante',
        repro: 'POST chat_messages chat_id=B1-S1 sender=B2',
        expected: '4xx',
        obtained: insAlien.brief,
      );
    } else {
      c.block('AU7.b2.insert-thread', 'AU7', 'B2 INSERT denied', insAlien);
    }

    await c.expectDenied(
      id: 'AU7.b2.patch-inbox',
      lens: 'AU7',
      title: 'B2 PATCH last_message do chat alheio',
      hit: await c.patchChat(
        chatId,
        {'last_message': 'Klarna 50€'},
        jwt: c.buyer2Jwt,
      ),
      actor: 'buyer2 JWT',
      pre: 'RLS chats update só participantes',
      repro: 'PATCH chats last_message como B2',
      severityIfOpen: 'P1',
    );
  }

  // =========================================================================
  // AU8 — Edge vs chat: mentira UI sem mint (controlo)
  // =========================================================================
  if (reserved != null) {
    await c.expectDenied(
      id: 'AU8.seguro-unpaid',
      lens: 'AU8',
      title: 'seguro_fleaber_paid em order não capturada',
      hit: await c.msg(
        chatId,
        fj({
          'kind': 'seguro_fleaber_paid',
          'order_id': reserved.oid,
          'total': 18.5,
        }),
        jwt: c.buyerJwt!,
        sender: c.buyerId,
      ),
      actor: 'buyer JWT',
      pre: 'order reservada sem PI/amount_paid',
      repro: 'POST seguro_fleaber_paid order_id=reservada',
      severityIfOpen: 'P1',
    );
  }

  if (paid != null) {
    final mint = await c.rest(
      'PATCH',
      'orders?id=eq.${paid.oid}',
      jwt: c.buyerJwt,
      body: {
        'payment_method': 'Klarna',
        'amount_paid_cents': 1,
      },
    );
    final row = await c.orderRow(paid.oid);
    final pm = row?['payment_method']?.toString();
    final cents = row?['amount_paid_cents'];
    if (pm == 'Klarna' || (cents is num && cents == 1)) {
      c.hold(
        id: 'AU8.order.patch-klarna',
        lens: 'AU8',
        severity: 'P0',
        title: 'buyer PATCH payment_method/amount_paid colou',
        actor: 'buyer JWT',
        pre: 'campos financeiros imutáveis',
        repro: 'PATCH orders payment_method=Klarna amount_paid_cents=1',
        expected: '403 / inalterado',
        obtained: {'patch': mint.brief, 'pm': pm, 'cents': cents},
      );
    } else {
      c.block('AU8.order.patch-klarna', 'AU8',
          'PATCH financeiro não colou ${mint.status} pm=$pm cents=$cents', mint);
    }
  }

  await c.dumpAll('pass1.json');
  stdout.writeln(
    'DONE findings=${c.findings.length} blocked=${c.blocked.length} lenses=${c.lensesHit.toList()..sort()}',
  );
}
