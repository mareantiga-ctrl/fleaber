/// REDTEAM_BLIND_AO pass2 — confirmar mutação real, demotar 200 vazio, variantes extra.
import 'dart:convert';
import 'dart:io';
import '_rtao.dart';

Future<void> main() async {
  final c = Rtao.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  const chatId = 'ac2902d3-a3ca-4f82-b7de-2532db9cafba';
  const oid = '2a975658-318c-4482-9ea5-25e37e37f42a';
  const msgRefund = '1200';
  const msgWiseNotes = '1206';
  const msgPing = '1229';
  const msgImage = '1238';
  const msgSeguroEscape = '1227';

  Future<Map<String, dynamic>?> getMsg(String id) async {
    final h = await c.rest(
      'GET',
      'chat_messages?id=eq.$id&select=id,text,created_at,sender_id',
      service: true,
    );
    return h.map;
  }

  Future<Map<String, dynamic>?> getChat() async {
    final h = await c.rest(
      'GET',
      'chats?id=eq.$chatId&select=id,last_message,last_message_time,user_a,user_b',
      service: true,
    );
    return h.map;
  }

  final refund = await getMsg(msgRefund);
  final refundText = refund?['text']?.toString() ?? '';
  c.note('p2.refund-stored', 'msg 1200 text', refundText, lens: 'AO1');
  if (refundText.contains('Refund 50 EUR')) {
    c.hold(
      id: 'AO1.display-refund-persisted',
      lens: 'AO1',
      severity: 'P2',
      title: 'Card cancel com display Refund 50 EUR persistido; Flutter mostra display',
      actor: 'seller JWT',
      pre: 'assert só bloqueia Reembolso/PayPal/…; Flutter _buildCancelOutcomeFromPayload usa display',
      repro: 'POST cancel_request_outcome display=Refund 50 EUR processed; GET id=1200',
      expected: 'chat_system_card_display_forbidden',
      obtained: refundText,
      evidence: {'id': msgRefund, 'order': oid},
    );
  }

  final notes = await getMsg(msgWiseNotes);
  final notesText = notes?['text']?.toString() ?? '';
  c.note('p2.notes-stored', 'wise notes text', notesText, lens: 'AO1');
  if (notesText.contains('Wise 50')) {
    c.hold(
      id: 'AO1.notes-wise-persisted',
      lens: 'AO1',
      severity: 'P2',
      title: 'Comprovativo notes Wise 50€ persistido; Flutter mostra Observações',
      actor: 'buyer JWT',
      pre: 'payment_lie_text não inclui Wise/Revolut/Apple Pay',
      repro: 'POST reservation_payment_submitted notes=Wise 50€ já caiu',
      expected: 'notes_forbidden',
      obtained: notesText,
      evidence: {'id': msgWiseNotes},
    );
  }

  final img = await getMsg(msgImage);
  final imgText = img?['text']?.toString() ?? '';
  c.note('p2.image-stored', 'chat_image text', imgText, lens: 'AO4');
  if (imgText.contains('object/public/')) {
    c.hold(
      id: 'AO4.chat-image-public-persisted',
      lens: 'AO4',
      severity: 'P2',
      title: 'chat_image url=storage public persistida (allowlist storage/% não restringe bucket)',
      actor: 'buyer JWT',
      pre: 'assert url like supabase.co/storage/% ; Flutter usa url http',
      repro: 'POST chat_image path=chat_uploads/{uid}/x url=.../object/public/avatars/x.png',
      expected: 'url_denied (só fleaber_private)',
      obtained: imgText,
      evidence: {'id': msgImage},
    );
  }

  final ping = await getMsg(msgPing);
  final created = ping?['created_at']?.toString() ?? '';
  c.note('p2.created-at', 'PATCH 200 mas created_at', created, lens: 'AO3');
  if (created.startsWith('2020')) {
    c.hold(
      id: 'AO3.backdate-real',
      lens: 'AO3',
      severity: 'P2',
      title: 'created_at ficou 2020',
      actor: 'buyer JWT',
      pre: 'pass1 PATCH 200',
      repro: 'GET chat_messages 1229',
      expected: '2026',
      obtained: created,
    );
  } else {
    c.block('AO3.patch-silent-200', 'AO3',
        'PATCH created_at 200 sem mutar (ainda $created)', ping);
  }

  final chat = await getChat();
  c.note('p2.inbox', 'last_message actual', chat?['last_message'], lens: 'AO5');
  final lm = chat?['last_message']?.toString() ?? '';
  if (lm.contains('Wise') ||
      lm.contains('Revolut') ||
      lm.contains('MB WAY') ||
      lm.contains('Recebi') ||
      lm.contains('Pagamento') ||
      lm.contains('Transfer')) {
    c.hold(
      id: 'AO5.inbox-lie-persisted',
      lens: 'AO5',
      severity: 'P2',
      title: 'Inbox last_message mentiroso persistido (regex só pega PayPal/PIX/€ depois de keyword)',
      actor: 'buyer JWT',
      pre: 'PayPal 50€ bloqueado; Wise/Revolut/MB WAY aprovado/Pagamento recebido passam',
      repro: 'PATCH chats last_message; GET chats',
      expected: 'chat_inbox_preview_forbidden',
      obtained: lm,
    );
  }

  // B2 200 [] — confirmar que last_message NÃO é "rtao b2"
  if (lm == 'rtao b2') {
    c.hold(
      id: 'AO7.b2-inbox-mutated',
      lens: 'AO7',
      severity: 'P2',
      title: 'B2 alterou last_message do chat B1-S1',
      actor: 'buyer2 JWT',
      pre: 'pass1 200 []',
      repro: 'GET chats',
      expected: 'não rtao b2',
      obtained: lm,
    );
  } else {
    c.block('AO7.b2-patch-empty', 'AO7',
        'B2 PATCH 200 [] sem mutar last_message=$lm', chat);
  }

  final esc = await getMsg(msgSeguroEscape);
  c.note('p2.seguro-escape', 'kind stored', esc?['text'], lens: 'AO2');
  // kind unicode-escape em encomenda JÁ paga = card legítimo, não forge

  // Signed URL formato correcto /storage/v1/object/sign/
  const ownProof =
      'order_proofs/bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96/$oid/RTAO-20260902T1005-own.png';
  final sign = await c.storageSign(ownProof, jwt: c.buyerJwt!);
  final signedRel = sign.map?['signedURL']?.toString() ??
      sign.map?['signedUrl']?.toString() ??
      '';
  final signedAbs = signedRel.startsWith('http')
      ? signedRel
      : '${c.url}/storage/v1$signedRel';
  c.note('p2.signed-abs', 'URL', signedAbs, lens: 'AO4');
  if (signedRel.isNotEmpty) {
    final hit = await c.msg(
      chatId,
      fj({
        'kind': 'reservation_payment_submitted',
        'order_id': oid,
        'proof_url': signedAbs,
      }),
      jwt: c.buyerJwt!,
      sender: c.buyerId,
    );
    if (hit.ok) {
      c.block('AO4.signed-correct-accepted', 'AO4',
          'signed /storage/v1/object/sign aceite (AHAM)', hit);
    } else {
      c.note('AO4.signed-correct', 'ainda denied?', hit.brief, lens: 'AO4');
    }
  }

  // Cf DENTRO da keyword (strip no texto inteiro antes do json)
  final zwj = await c.msg(
    chatId,
    fj({
      'kind': 'cancel_request_outcome',
      'order_id': oid,
      'outcome': 'rejected',
      'display': 'Re\u200Bembolso 50 EUR processado',
    }),
    jwt: c.sellerJwt!,
    sender: c.sellerId,
  );
  if (zwj.ok) {
    c.hold(
      id: 'AO2.zwj-inside-keyword',
      lens: 'AO2',
      severity: 'P2',
      title: 'ZWSP dentro de Reembolso no display sobreviveu ao strip+regex',
      actor: 'seller JWT',
      pre: 'strip Cf no texto cru antes do jsonb; se remover ZWSP vira Reembolso e deveria 400',
      repro: 'display=Re+U+200B+embolso 50 EUR',
      expected: 'display_forbidden após strip',
      obtained: zwj.brief,
    );
  } else {
    c.block('AO2.zwj-inside-keyword', 'AO2', 'ZWSP intra-keyword stripped→blocked',
        zwj);
  }

  // DELETE da bolha JSON com NBSP prefix (não começa por FLEABER exacto)
  final nbspBubbles = await c.rest(
    'GET',
    'chat_messages?chat_id=eq.$chatId&sender_id=eq.${c.sellerId}&select=id,text&order=id.desc&limit=20',
    jwt: c.sellerJwt,
  );
  String? nbspId;
  for (final row in nbspBubbles.list) {
    if (row is! Map) continue;
    final t = '${row['text']}';
    if (t.contains('\u00A0FLEABER_JSON_V1:') ||
        t.startsWith('\u00A0') ||
        t.contains('\u2003FLEABER_JSON_V1:')) {
      nbspId = '${row['id']}';
      break;
    }
  }
  if (nbspId != null) {
    final del = await c.rest(
      'DELETE',
      'chat_messages?id=eq.$nbspId',
      jwt: c.sellerJwt,
    );
    if (del.ok) {
      final still = await getMsg(nbspId);
      if (still == null) {
        c.hold(
          id: 'AO5.delete-nbsp-prefix-bubble',
          lens: 'AO5',
          severity: 'P3',
          title: 'DELETE removeu bolha com NBSP+FLEABER_JSON_V1 (imutabilidade só prefixo exacto)',
          actor: 'seller JWT',
          pre: 'guard_delete like FLEABER_JSON_V1:% ou btrim {%',
          repro: 'DELETE id de text=U+00A0+FLEABER_JSON_V1:…',
          expected: 'chat_system_card_immutable',
          obtained: del.brief,
          evidence: {'id': nbspId},
        );
      } else {
        c.block('AO5.delete-nbsp-prefix-bubble', 'AO5', 'DELETE 200 mas linha ficou',
            still);
      }
    } else {
      c.block('AO5.delete-nbsp-prefix-bubble', 'AO5', 'DELETE bloqueado', del);
    }
  } else {
    c.skip('AO5.delete-nbsp', 'AO5', 'não encontrei bolha NBSP', nbspBubbles.brief);
  }

  // Cf-in-notes
  final notesZw = await c.msg(
    chatId,
    fj({
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'Re\u200Bembolso 4321 € já enviado',
    }),
    jwt: c.buyerJwt!,
    sender: c.buyerId,
  );
  if (notesZw.ok) {
    c.hold(
      id: 'AO2.zwj-notes',
      lens: 'AO2',
      severity: 'P2',
      title: 'ZWSP intra notes Reembolso passou',
      actor: 'buyer JWT',
      pre: 'strip no texto cru',
      repro: 'notes=Re+ZWSP+embolso 4321 €',
      expected: 'notes_forbidden',
      obtained: notesZw.brief,
    );
  } else {
    c.block('AO2.zwj-notes', 'AO2', 'ZWSP notes bloqueado', notesZw);
  }

  // Restaurar inbox (não deixar mentira no chat lab)
  final restore = await c.patchChat(
    chatId,
    {'last_message': 'RTAO cleanup'},
    jwt: c.buyerJwt,
  );
  c.note('p2.restore-inbox', 'last_message reset', restore.brief, lens: 'AO5');

  final o = await c.orderRow(oid);
  c.note('p2.books', 'order ainda pago', {
    'status': o?['status'],
    'paid': o?['amount_paid_cents'],
    'refund': o?['stripe_refund_id'],
  }, lens: 'AO8');

  await c.dumpAll('pass2.json');
  stdout.writeln(
      'PASS2 findings=${c.findings.length} blocked=${c.blocked.length}');
}
