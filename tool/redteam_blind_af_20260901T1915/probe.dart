/// RED TEAM CEGO AF — chat/provas/UI pós-ABACAD. Staging only. Não corrige.
import 'dart:convert';
import 'dart:io';

import '_rtaf.dart';

Future<void> main() async {
  final c = Rtaf.fromEnv(loadEnv());
  Directory(outDir()).createSync(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();

  final productId = await c.createProduct();
  if (productId == null) {
    stderr.writeln('no product');
    exit(4);
  }
  final chatId = await c.ensureChat(productId: productId);
  if (chatId == null) {
    stderr.writeln('no chat');
    exit(4);
  }

  final exp = DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String();
  final reservedId = await c.insertOrder(
    productId: productId,
    status: 'reservado',
    price: 12.34,
    expiresAt: exp,
  );
  final paidId = await c.insertOrder(
    productId: productId,
    status: 'pago',
    price: 12.34,
    paidCents: 1234,
    pi: 'pi_rtaf_${stamp}_paid',
    expiresAt: exp,
  );
  final unpaidId = await c.insertOrder(
    productId: productId,
    status: 'reserva_pendente',
    price: 12.34,
  );
  final offerId = await c.insertOffer(productId: productId, amount: 9.5);

  c.note('fixture', 'ids', {
    'product': productId,
    'chat': chatId,
    'reserved': reservedId,
    'paid': paidId,
    'unpaid': unpaidId,
    'offer': offerId,
    'buyer': c.buyerId,
    'seller': c.sellerId,
    'buyer2': c.buyer2Id,
  });

  // =====================================================================
  // AF2 — prefix / encoding (NEW: not NBSP, not raw `{`, not BOM exact)
  // =====================================================================
  final bundleJson = jsonEncode({
    'kind': 'bundle_proposal',
    'total_eur': 6543.21,
    'seller_id': c.sellerId,
    'buyer_id': c.buyerId,
    'product_ids': [productId],
    'subtotal_eur': 6543.21,
    'discount_pct': 0,
    'discount_eur': 0,
    'request_mode': 'discount',
  });

  final encodingCases = <String, String>{
    'ff': '\u000c$bundleJson',
    'vt': '\u000b$bundleJson',
    'ogham': '\u1680$bundleJson',
    'ls': '\u2028$bundleJson',
    'ps': '\u2029$bundleJson',
    'zwsp': '\u200b$bundleJson',
    'zwnj': '\u200c$bundleJson',
    'soft_hyphen': '\u00ad$bundleJson',
    'word_joiner': '\u2060$bundleJson',
    'rtl': '\u202e$bundleJson',
    'fullwidth_brace': '｛${bundleJson.substring(1)}',
    'json_array': '[$bundleJson]',
  };

  for (final e in encodingCases.entries) {
    final hit = await c.postMsg(chatId: chatId, text: e.value, jwt: c.buyerJwt!);
    final stored = hit.ok ? (hit.map?['text']?.toString() ?? e.value) : '';
    final flutterParses = c.flutterWouldParseBundleRaw(stored.isEmpty ? e.value : stored);
    if (hit.ok && flutterParses) {
      c.hold(
        id: 'AF2.ENC.${e.key}',
        lens: 'AF2',
        severity: 'P1',
        title:
            'JSON cru bundle_proposal prefixado com ${e.key} passa o trigger e o Flutter parseia o card (total_eur=6543.21 sem bundle_id)',
        actor: 'buyer JWT',
        pre:
            'tryParseBundleProposalChatPayload faz trim()+jsonDecode se começa por `{`; strip SQL não cobre FF/VT/Ogham/LS/PS',
        repro: 'POST chat_messages text=<${e.key}>{"kind":"bundle_proposal","total_eur":6543.21,...}',
        expected: 'chat_system_card_prefix_required',
        obtained: {'http': hit.status, 'id': hit.firstId, 'flutter_parses': true},
        evidence: {'variant': e.key, 'stored_prefix_cp': stored.isEmpty ? null : stored.codeUnitAt(0)},
      );
    } else if (hit.ok) {
      c.note('AF2.ENC.${e.key}.insert', 'inseriu mas Flutter trim não parseia',
          {'http': hit.status, 'id': hit.firstId},
          lens: 'AF2');
      // AF5: apagar este card se não for FLEABER_JSON_V1
      if (hit.firstId != null) {
        final del = await c.rest(
          'DELETE',
          'chat_messages?id=eq.${hit.firstId}',
          jwt: c.buyerJwt!,
          prefer: 'return=representation',
        );
        if (del.ok) {
          c.hold(
            id: 'AF5.DEL.${e.key}',
            lens: 'AF5',
            severity: 'P2',
            title:
                'Mensagem JSON cru ${e.key} é apagável — DELETE só imutabiliza FLEABER_JSON_V1 e btrim `{`',
            actor: 'buyer JWT',
            pre: 'trg_batata_chat_messages_guard_delete',
            repro: 'DELETE chat_messages?id=eq.${hit.firstId}',
            expected: 'chat_system_card_immutable',
            obtained: {'http': del.status, 'gone': del.ok},
          );
        } else {
          c.block('AF5.DEL.${e.key}', 'AF5', 'DELETE ${e.key} recusado', del.brief);
        }
      }
    } else {
      c.block('AF2.ENC.${e.key}', 'AF2', 'encoding ${e.key} recusado',
          '${hit.status} ${hit.pgCode} ${hit.pgMsg}');
    }
  }

  // Case / nested prefix that Flutter still parseia
  final prefixTwists = <String, String>{
    'lower_prefix': 'fleaber_json_v1:$bundleJson',
    'mixed_prefix': 'Fleaber_Json_V1:$bundleJson',
    'double_colon': 'FLEABER_JSON_V1::$bundleJson',
    'zwsp_in_prefix': 'FLEABER_JSON_V1\u200b:$bundleJson',
    'nbsp_in_prefix': 'FLEABER\u00a0JSON_V1:$bundleJson',
    'prefix_then_ff_json': 'FLEABER_JSON_V1:\u000c$bundleJson',
  };
  for (final e in prefixTwists.entries) {
    final hit = await c.postMsg(chatId: chatId, text: e.value, jwt: c.buyerJwt!);
    final stored = hit.map?['text']?.toString() ?? '';
    final flutterParses = stored.startsWith('FLEABER_JSON_V1:')
        ? true
        : c.flutterWouldParseBundleRaw(stored);
    if (hit.ok && (flutterParses || stored.contains('6543.21'))) {
      if (stored.startsWith('FLEABER_JSON_V1:') && e.key == 'prefix_then_ff_json') {
        // jsonb may have accepted FF as whitespace? Unlikely. If stored, check parse.
        try {
          jsonDecode(stored.substring('FLEABER_JSON_V1:'.length).trim());
          c.hold(
            id: 'AF2.PRE.${e.key}',
            lens: 'AF2',
            severity: 'P1',
            title: 'Prefixo FLEABER_JSON_V1 + ${e.key} aceite com total fantasma',
            actor: 'buyer JWT',
            pre: 'assert_json_card exige prefixo exacto e jsonb',
            repro: 'POST ${e.key}',
            expected: 'recusa',
            obtained: {'http': hit.status, 'id': hit.firstId, 'text': clip(stored, 120)},
          );
        } catch (_) {
          c.note('AF2.PRE.${e.key}', 'inseriu prefixo mas JSON inválido no cliente', hit.brief,
              lens: 'AF2');
        }
      } else if (!stored.startsWith('FLEABER_JSON_V1:') &&
          c.flutterWouldParseBundleRaw(stored)) {
        c.hold(
          id: 'AF2.PRE.${e.key}',
          lens: 'AF2',
          severity: 'P1',
          title: 'Twist de prefixo ${e.key} inserido e parseado como bundle',
          actor: 'buyer JWT',
          pre: 'prefixo exacto FLEABER_JSON_V1',
          repro: 'POST ${e.key}',
          expected: 'recusa ou texto plano',
          obtained: {'http': hit.status, 'id': hit.firstId},
        );
      } else {
        c.note('AF2.PRE.${e.key}', 'inseriu sem card Flutter', hit.brief, lens: 'AF2');
      }
    } else if (hit.ok) {
      c.note('AF2.PRE.${e.key}', 'inseriu texto não-card', hit.brief, lens: 'AF2');
    } else {
      c.block('AF2.PRE.${e.key}', 'AF2', e.key, '${hit.pgCode} ${hit.pgMsg}');
    }
  }

  // =====================================================================
  // AF1 — cards vs BD (NEW outcomes / kinds / fields)
  // =====================================================================
  if (reservedId != null) {
    // omit outcome → Flutter treats as recusou
    final omit = await c.postMsg(
      chatId: chatId,
      jwt: c.sellerJwt!,
      text: fj({
        'kind': 'reservation_request_outcome',
        'order_id': reservedId,
      }),
    );
    if (omit.ok) {
      final o = await c.orderRow(reservedId);
      c.hold(
        id: 'AF1.RES.OUTCOME-OMIT',
        lens: 'AF1',
        severity: 'P1',
        title:
            'reservation_request_outcome sem outcome num pedido reservado — Flutter mostra «recusou» (accepted==false) mas a BD continua reservado',
        actor: 'seller JWT',
        pre: 'trigger só cruza BD se outcome=accepted|rejected; Flutter: accepted = outcome==accepted',
        repro:
            'POST FLEABER_JSON_V1 kind=reservation_request_outcome order_id=<reservado> (sem outcome)',
        expected: 'recusa ou card alinhado ao status reservado',
        obtained: {
          'http': omit.status,
          'msg': omit.firstId,
          'order_status': o?['status'],
          'flutter': 'O vendedor recusou o pedido de reserva.',
        },
      );
    } else {
      c.block('AF1.RES.OUTCOME-OMIT', 'AF1', 'omit outcome recusado',
          '${omit.pgCode} ${omit.pgMsg}');
    }

    final expired = await c.postMsg(
      chatId: chatId,
      jwt: c.sellerJwt!,
      text: fj({
        'kind': 'reservation_request_outcome',
        'order_id': reservedId,
        'outcome': 'expired',
      }),
    );
    if (expired.ok) {
      c.hold(
        id: 'AF1.RES.OUTCOME-EXPIRED',
        lens: 'AF1',
        severity: 'P1',
        title:
            'reservation_request_outcome outcome=expired em reservado — card «recusou», BD reservado',
        actor: 'seller JWT',
        pre: 'sem check para outcome∉{accepted,rejected}',
        repro: 'POST outcome=expired order reservado',
        expected: 'recusa',
        obtained: {'http': expired.status, 'msg': expired.firstId},
      );
    } else {
      c.block('AF1.RES.OUTCOME-EXPIRED', 'AF1', 'expired recusado',
          '${expired.pgCode} ${expired.pgMsg}');
    }
  }

  if (paidId != null) {
    final acc = await c.postMsg(
      chatId: chatId,
      jwt: c.sellerJwt!,
      text: fj({
        'kind': 'reservation_accepted',
        'order_id': paidId,
        'expires_at': exp,
      }),
    );
    if (acc.ok) {
      final o = await c.orderRow(paidId);
      c.hold(
        id: 'AF1.RES.ACCEPTED-PAID',
        lens: 'AF1',
        severity: 'P1',
        title:
            'reservation_accepted aceite num pedido já pago — card «Tens até … para pagar» sem cruzar status',
        actor: 'seller JWT',
        pre: 'assert só compara expires_at se reservation_expires_at ≠ null; não exige status reservado',
        repro: 'POST kind=reservation_accepted order pago expires_at=BD',
        expected: 'chat_system_card_status_mismatch',
        obtained: {
          'http': acc.status,
          'msg': acc.firstId,
          'status': o?['status'],
          'paid_cents': o?['amount_paid_cents'],
        },
      );
    } else {
      c.block('AF1.RES.ACCEPTED-PAID', 'AF1', 'accepted-on-paid recusado',
          '${acc.pgCode} ${acc.pgMsg}');
    }

    // cancel outcome display field — not validated
    final cancelDisplay = await c.postMsg(
      chatId: chatId,
      jwt: c.sellerJwt!,
      text: fj({
        'kind': 'cancel_request_outcome',
        'order_id': paidId,
        'outcome': 'updated',
        'display':
            'Cancelamento aceite — reembolso de 4321,00 € processado na hora.',
      }),
    );
    if (cancelDisplay.ok) {
      final o = await c.orderRow(paidId);
      c.hold(
        id: 'AF1.CANCEL.DISPLAY',
        lens: 'AF1',
        severity: 'P1',
        title:
            'cancel_request_outcome.display livre — card mostra reembolso 4321 € com pedido ainda pago',
        actor: 'seller JWT',
        pre:
            'trigger só valida outcome accepted/rejected; Flutter _buildCancelOutcomeFromPayload usa payload.display cru',
        repro:
            'POST kind=cancel_request_outcome outcome=updated display=«reembolso 4321 €» order pago',
        expected: 'recusa ou display ignorado',
        obtained: {
          'http': cancelDisplay.status,
          'msg': cancelDisplay.firstId,
          'status': o?['status'],
          'refund': o?['stripe_refund_id'],
          'flutter_line':
              'Cancelamento aceite — reembolso de 4321,00 € processado na hora.',
        },
      );
    } else {
      c.block('AF1.CANCEL.DISPLAY', 'AF1', 'display recusado',
          '${cancelDisplay.pgCode} ${cancelDisplay.pgMsg}');
    }

    // seguro label integer euros / EUR (regex exige decimal + €)
    final pixLabel = await c.postMsg(
      chatId: chatId,
      jwt: c.buyerJwt!,
      text: fj({
        'kind': 'seguro_fleaber_paid',
        'order_id': paidId,
        'total': 12.34,
        'label': 'PIX 4321 €',
      }),
    );
    if (pixLabel.ok) {
      c.hold(
        id: 'AF1.SEGURO.LABEL-INT',
        lens: 'AF1',
        severity: 'P2',
        title:
            'seguro_fleaber_paid label «PIX 4321 €» (inteiro) aceite — regex do label exige decimal; Flutter concatena o label no card de pago',
        actor: 'buyer JWT',
        pre: "label ~ '(Seguro|PIX|MB WAY|Compra paga).*\\d+[,.]\\d+\\s*€'",
        repro: 'POST seguro_fleaber_paid total=12.34 label=«PIX 4321 €»',
        expected: 'chat_system_card_label_mismatch',
        obtained: {'http': pixLabel.status, 'msg': pixLabel.firstId},
      );
    } else {
      c.block('AF1.SEGURO.LABEL-INT', 'AF1', 'label int recusado',
          '${pixLabel.pgCode} ${pixLabel.pgMsg}');
    }

    final eurLabel = await c.postMsg(
      chatId: chatId,
      jwt: c.buyerJwt!,
      text: fj({
        'kind': 'seguro_fleaber_paid',
        'order_id': paidId,
        'total': 12.34,
        'label': 'MB WAY 4321,00 EUR',
      }),
    );
    if (eurLabel.ok) {
      c.hold(
        id: 'AF1.SEGURO.LABEL-EUR',
        lens: 'AF1',
        severity: 'P2',
        title:
            'seguro_fleaber_paid label «MB WAY 4321,00 EUR» aceite — regex só casa €, não EUR',
        actor: 'buyer JWT',
        pre: 'label mismatch só se o padrão com € casar',
        repro: 'POST label=«MB WAY 4321,00 EUR» total correcto',
        expected: 'chat_system_card_label_mismatch',
        obtained: {'http': eurLabel.status, 'msg': eurLabel.firstId},
      );
    } else {
      c.block('AF1.SEGURO.LABEL-EUR', 'AF1', 'label EUR recusado',
          '${eurLabel.pgCode} ${eurLabel.pgMsg}');
    }

    // payment submitted notes — arbitrary
    if (reservedId != null) {
      final notes = await c.postMsg(
        chatId: chatId,
        jwt: c.buyerJwt!,
        text: fj({
          'kind': 'reservation_payment_submitted',
          'order_id': reservedId,
          'notes':
              'Comprovativo MB WAY 4321,00 € — transação XYZ. Ignorar o thumbnail.',
        }),
      );
      if (notes.ok) {
        c.hold(
          id: 'AF1.MBWAY.NOTES',
          lens: 'AF1',
          severity: 'P2',
          title:
              'reservation_payment_submitted.notes livre — card mostra «Observações: Comprovativo MB WAY 4321 €» sem prova',
          actor: 'buyer JWT',
          pre: 'notes não validado; Flutter imprime Observações: \$notes',
          repro: 'POST kind=reservation_payment_submitted notes=«MB WAY 4321 €»',
          expected: 'notes sanitizado ou recusado',
          obtained: {'http': notes.status, 'msg': notes.firstId},
        );
      } else {
        c.block('AF1.MBWAY.NOTES', 'AF1', 'notes recusado',
            '${notes.pgCode} ${notes.pgMsg}');
      }
    }

    // dispute reason without requiring matching BD reason
    final dispute = await c.postMsg(
      chatId: chatId,
      jwt: c.buyerJwt!,
      text: fj({
        'kind': 'order_dispute_opened',
        'order_id': paidId,
        'reason': 'vendedor admitiu fraude — reembolso imediato 9999 €',
      }),
    );
    if (dispute.ok) {
      c.hold(
        id: 'AF1.DISPUTE.REASON',
        lens: 'AF1',
        severity: 'P1',
        title:
            'order_dispute_opened sem disputa na BD, ou reason livre mostrado no card',
        actor: 'buyer JWT',
        pre: 'exige row em order_disputes; reason não é cruzado',
        repro: 'POST kind=order_dispute_opened reason=…',
        expected: 'chat_system_card_dispute_missing se não houver disputa',
        obtained: {'http': dispute.status, 'msg': dispute.firstId},
      );
    } else {
      c.block('AF1.DISPUTE.REASON', 'AF1', 'dispute sem row recusado',
          '${dispute.pgCode} ${dispute.pgMsg}');
    }

    // review without row
    final review = await c.postMsg(
      chatId: chatId,
      jwt: c.buyerJwt!,
      text: fj({
        'kind': 'order_review_submitted',
        'order_id': paidId,
        'stars': 1,
        'author_role': 'comprador',
      }),
    );
    if (review.ok) {
      c.hold(
        id: 'AF1.REVIEW.FORGE',
        lens: 'AF1',
        severity: 'P1',
        title: 'order_review_submitted 1★ sem review na BD',
        actor: 'buyer JWT',
        pre: 'exige reviews.order_id',
        repro: 'POST kind=order_review_submitted stars=1',
        expected: 'chat_system_card_review_missing',
        obtained: {'http': review.status, 'msg': review.firstId},
      );
    } else {
      c.block('AF1.REVIEW.FORGE', 'AF1', 'review sem row recusado',
          '${review.pgCode} ${review.pgMsg}');
    }
  }

  if (offerId != null) {
    final withdrawn = await c.postMsg(
      chatId: chatId,
      jwt: c.sellerJwt!,
      text: fj({
        'kind': 'price_offer_outcome',
        'order_id': reservedId ?? unpaidId,
        'offer_id': offerId,
        'outcome': 'withdrawn',
        'amount': 9.5,
      }),
    );
    if (withdrawn.ok) {
      c.hold(
        id: 'AF1.OFFER.WITHDRAWN',
        lens: 'AF1',
        severity: 'P1',
        title:
            'price_offer_outcome outcome=withdrawn com oferta pending — Flutter mostra «Proposta recusada.» (accepted==false)',
        actor: 'seller JWT',
        pre:
            'trigger só valida accepted/rejected; PriceOfferOutcomeChatCard: else → recusada',
        repro: 'POST price_offer_outcome outcome=withdrawn offer pending amount=BD',
        expected: 'chat_system_card_offer_status_mismatch',
        obtained: {'http': withdrawn.status, 'msg': withdrawn.firstId},
      );
    } else {
      c.block('AF1.OFFER.WITHDRAWN', 'AF1', 'withdrawn recusado',
          '${withdrawn.pgCode} ${withdrawn.pgMsg}');
    }

    final omitOffer = await c.postMsg(
      chatId: chatId,
      jwt: c.sellerJwt!,
      text: fj({
        'kind': 'price_offer_outcome',
        'order_id': reservedId ?? unpaidId,
        'offer_id': offerId,
        'amount': 9.5,
      }),
    );
    if (omitOffer.ok) {
      c.hold(
        id: 'AF1.OFFER.OUTCOME-OMIT',
        lens: 'AF1',
        severity: 'P1',
        title:
            'price_offer_outcome sem outcome + oferta pending — card «Proposta recusada.»',
        actor: 'seller JWT',
        pre: 'mesmo buraco que withdrawn, variante omit',
        repro: 'POST price_offer_outcome sem outcome',
        expected: 'recusa',
        obtained: {'http': omitOffer.status, 'msg': omitOffer.firstId},
      );
    } else {
      c.block('AF1.OFFER.OUTCOME-OMIT', 'AF1', 'omit offer outcome recusado',
          '${omitOffer.pgCode} ${omitOffer.pgMsg}');
    }
  }

  // =====================================================================
  // AF4 — URLs / provas (NEW vs javascript, vs URL-em-URL, vs public avatars)
  // =====================================================================
  if (reservedId != null) {
    final urlCases = <String, String>{
      'fleaber_app_static': 'https://fleaber.app/favicon.ico',
      'fleaber_pt_static': 'https://www.fleaber.pt/robots.txt',
      'crlf_embedded':
          'https://fleaber.app/x%0d%0aLocation:%20https://evil.example/receipt.png',
      'query_proto_rel': 'https://fleaber.app/l?next=//evil.example/receipt.png',
      'query_bare_host': 'https://fleaber.app/l?u=evil.example/receipt.png',
      'fragment_at': 'https://fleaber.app/x#@evil.example/receipt.png',
      'private_traversal':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/../public/avatars/x.png',
      'private_pct_dots':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/%2e%2e/public/avatars/x.png',
      'vbscript': 'vbscript:msgbox(1)',
      'blob': 'blob:https://evil.example/abc',
      'file': 'file:///etc/passwd',
      'backslash_host':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co\\storage/v1/object/fleaber_private/x',
    };
    for (final e in urlCases.entries) {
      final hit = await c.postMsg(
        chatId: chatId,
        jwt: c.buyerJwt!,
        text: fj({
          'kind': 'reservation_payment_submitted',
          'order_id': reservedId,
          'proof_url': e.value,
        }),
      );
      if (hit.ok) {
        c.hold(
          id: 'AF4.PROOF.${e.key}',
          lens: 'AF4',
          severity: e.key.startsWith('fleaber') || e.key.contains('query')
              ? 'P1'
              : 'P2',
          title:
              'reservation_payment_submitted.proof_url=${e.key} aceite — Flutter abre no Image.network/dialog',
          actor: 'buyer JWT',
          pre: 'allowlist fleaber.app / fleaber_private; nested https e public bloqueados',
          repro: 'POST proof_url=${e.value}',
          expected: 'chat_system_card_url_denied',
          obtained: {'http': hit.status, 'msg': hit.firstId, 'url': e.value},
        );
      } else {
        c.block('AF4.PROOF.${e.key}', 'AF4', e.key,
            '${hit.pgCode} ${hit.pgMsg}');
      }
    }

    // chat_image public bucket URL (path still own chat_uploads)
    final imgPub = await c.postMsg(
      chatId: chatId,
      jwt: c.buyerJwt!,
      text: fj({
        'kind': 'chat_image',
        'path': 'chat_uploads/${c.buyerId}/$chatId/ghost.png',
        'url':
            'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/avatars/x.png',
      }),
    );
    if (imgPub.ok) {
      c.hold(
        id: 'AF4.IMG.PUBLIC',
        lens: 'AF4',
        severity: 'P2',
        title:
            'chat_image.url em bucket public aceite — allowlist só casa supabase.co/storage/, sem negar /object/public/',
        actor: 'buyer JWT',
        pre: 'chat_image url check ≠ proof_url (sem denylist public)',
        repro:
            'POST chat_image path=chat_uploads/{me}/{chat}/x url=…/object/public/avatars/x.png',
        expected: 'chat_system_card_url_denied',
        obtained: {'http': imgPub.status, 'msg': imgPub.firstId},
      );
    } else {
      c.block('AF4.IMG.PUBLIC', 'AF4', 'chat_image public recusado',
          '${imgPub.pgCode} ${imgPub.pgMsg}');
    }
  }

  // =====================================================================
  // AF3 — cronologia
  // =====================================================================
  final past = DateTime.now()
      .toUtc()
      .subtract(const Duration(seconds: 90))
      .toIso8601String();
  final future = DateTime.now()
      .toUtc()
      .add(const Duration(hours: 3))
      .toIso8601String();
  final backChat = await c.rest('POST', 'chats', jwt: c.buyerJwt!, body: {
    'user_a': c.buyerId,
    'user_b': c.sellerId,
    'product_id': productId,
    'last_message': '$prefix ping',
    'last_message_time': past,
  });
  if (backChat.ok) {
    final storedT = backChat.map?['last_message_time']?.toString() ?? '';
    final drifted = DateTime.tryParse(storedT);
    final now = DateTime.now().toUtc();
    if (drifted != null && now.difference(drifted).inSeconds >= 60) {
      c.hold(
        id: 'AF3.INBOX.BACKDATE-90S',
        lens: 'AF3',
        severity: 'P3',
        title: 'last_message_time −90s sobrevive (janela de 2 minutos)',
        actor: 'buyer JWT',
        pre: 'clamp só se < now()-2min ou > now()+5min',
        repro: 'POST chats last_message_time=now-90s',
        expected: 'forçar now()',
        obtained: {'http': backChat.status, 'stored': storedT},
      );
    } else {
      c.block('AF3.INBOX.BACKDATE-90S', 'AF3', '90s clamped ou agora', storedT);
    }
    if (backChat.firstId != null) c.createdChatIds.add(backChat.firstId!);
  } else {
    c.block('AF3.INBOX.BACKDATE-90S', 'AF3', 'POST chat backdate recusado',
        backChat.brief);
  }

  final fut = await c.rest(
    'PATCH',
    'chats?id=eq.$chatId',
    jwt: c.buyerJwt!,
    body: {'last_message_time': future},
  );
  if (fut.ok) {
    final storedT = fut.map?['last_message_time']?.toString() ?? '';
    final drifted = DateTime.tryParse(storedT);
    if (drifted != null &&
        drifted.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 6)))) {
      c.hold(
        id: 'AF3.INBOX.FUTURE',
        lens: 'AF3',
        severity: 'P3',
        title: 'last_message_time +3h persistido',
        actor: 'buyer JWT',
        pre: 'clamp > now()+5min',
        repro: 'PATCH chats last_message_time=now+3h',
        expected: 'now()',
        obtained: storedT,
      );
    } else {
      c.block('AF3.INBOX.FUTURE', 'AF3', 'future clamped', storedT);
    }
  } else {
    c.block('AF3.INBOX.FUTURE', 'AF3', 'PATCH time recusado', fut.brief);
  }

  // created_at backdate on a plain message
  final plain = await c.postMsg(
    chatId: chatId,
    jwt: c.buyerJwt!,
    text: '$prefix plain chrono',
  );
  if (plain.ok && plain.firstId != null) {
    final oldAt = '2020-01-01T00:00:00Z';
    final patchAt = await c.rest(
      'PATCH',
      'chat_messages?id=eq.${plain.firstId}',
      jwt: c.buyerJwt!,
      body: {'created_at': oldAt},
    );
    final after = await c.msgRow(plain.firstId!);
    final got = after?['created_at']?.toString() ?? '';
    if (got.startsWith('2020')) {
      c.hold(
        id: 'AF3.MSG.CREATED-AT',
        lens: 'AF3',
        severity: 'P2',
        title: 'PATCH created_at de mensagem própria para 2020',
        actor: 'buyer JWT',
        pre: 'guard_update força NEW.created_at := OLD.created_at',
        repro: 'PATCH chat_messages created_at=2020-01-01',
        expected: 'created_at imutável',
        obtained: {'http': patchAt.status, 'created_at': got},
      );
    } else {
      c.block('AF3.MSG.CREATED-AT', 'AF3', 'created_at imutável', got);
    }
  }

  // =====================================================================
  // AF5 — inbox preview (NEW vs regex Seguro/MB WAY/PIX + €)
  // =====================================================================
  final inboxCases = <String, String>{
    'mbway_nbsp': 'MB\u00a0WAY 4321,00 € confirmado',
    'mbway_nospace_euro': 'MB WAY 4321,00€',
    'mbway_concat': 'MBWAY 4321,00 €',
    'transfer': 'Transferência confirmada 4321,00 €',
    'pagamento_eur': 'Pagamento recebido 4321,00 EUR',
    'compra_sem_seguro': 'Compra paga 99,00 €',
  };
  for (final e in inboxCases.entries) {
    final ins = await c.rest('POST', 'chats', jwt: c.buyerJwt!, body: {
      'user_a': c.buyerId,
      'user_b': c.sellerId,
      'product_id': productId,
      'last_message': e.value,
    });
    if (ins.ok) {
      final stored = ins.map?['last_message']?.toString();
      c.hold(
        id: 'AF5.INBOX.INSERT.${e.key}',
        lens: 'AF5',
        severity: 'P2',
        title: 'Inbox INSERT last_message «${e.key}» aceite — preview falso na lista',
        actor: 'buyer JWT',
        pre:
            "batata_chat_is_forged_inbox_preview = '(Seguro Fleaber|Compra paga|MB WAY|PIX).*(\\d+[,.]?\\d*\\s*€|€\\s*\\d+)'",
        repro: 'POST chats last_message=${e.value}',
        expected: 'chat_inbox_preview_forbidden',
        obtained: {
          'http': ins.status,
          'id': ins.firstId,
          'stored': stored,
        },
      );
      if (ins.firstId != null) c.createdChatIds.add(ins.firstId!);
    } else {
      c.block('AF5.INBOX.INSERT.${e.key}', 'AF5', e.key,
          '${ins.pgCode} ${ins.pgMsg}');
    }
  }

  final patchInbox = await c.rest(
    'PATCH',
    'chats?id=eq.$chatId',
    jwt: c.buyerJwt!,
    body: {'last_message': 'MB WAY 12€ — pago'},
  );
  if (patchInbox.ok) {
    c.hold(
      id: 'AF5.INBOX.PATCH.NOSPACE',
      lens: 'AF5',
      severity: 'P2',
      title: 'PATCH last_message «MB WAY 12€» (sem espaço antes de €) aceite',
      actor: 'buyer JWT',
      pre: 'regex exige \\s*€ com dígito; 12€ pode falhar o ramo com espaço',
      repro: 'PATCH chats last_message=«MB WAY 12€ — pago»',
      expected: 'chat_inbox_preview_forbidden',
      obtained: {
        'http': patchInbox.status,
        'stored': patchInbox.map?['last_message'],
      },
    );
  } else {
    c.block('AF5.INBOX.PATCH.NOSPACE', 'AF5', 'patch nospaces recusado',
        '${patchInbox.pgCode} ${patchInbox.pgMsg}');
  }

  // DELETE FLEABER card (control — should block)
  if (c.createdMsgIds.isNotEmpty) {
    // find a FLEABER one
    final listed = await c.rest(
      'GET',
      'chat_messages?chat_id=eq.$chatId&text=like.FLEABER_JSON_V1%25&select=id,text&limit=3',
      jwt: c.buyerJwt!,
    );
    final fid = listed.map?['id']?.toString();
    if (fid != null) {
      final del = await c.rest(
        'DELETE',
        'chat_messages?id=eq.$fid',
        jwt: c.buyerJwt!,
      );
      if (del.ok) {
        c.hold(
          id: 'AF5.DEL.JSONV1',
          lens: 'AF5',
          severity: 'P1',
          title: 'DELETE de card FLEABER_JSON_V1 permitido',
          actor: 'buyer JWT',
          pre: 'guard_delete',
          repro: 'DELETE chat_messages FLEABER_JSON_V1',
          expected: 'chat_system_card_immutable',
          obtained: del.brief,
        );
      } else {
        c.block('AF5.DEL.JSONV1', 'AF5', 'JSON V1 imutável',
            '${del.pgCode} ${del.pgMsg}');
      }
    }
  }

  // =====================================================================
  // AF6 — storage upsert / overwrite / signed
  // =====================================================================
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );
  final objPath =
      'chat_uploads/${c.buyerId}/$chatId/${prefix}-a.png';
  final up1 = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$objPath',
    jwt: c.buyerJwt,
    rawBytes: png,
    rawContentType: 'image/png',
  );
  c.note('AF6.UP1', 'upload 1', up1.brief, lens: 'AF6');
  final up2 = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$objPath',
    jwt: c.buyerJwt,
    rawBytes: png,
    rawContentType: 'image/png',
    extra: {'x-upsert': 'true'},
  );
  if (up2.ok) {
    c.hold(
      id: 'AF6.UPSERT',
      lens: 'AF6',
      severity: 'P2',
      title:
          'x-upsert=true sobre chat_uploads próprio — pode substituir comprovativo no mesmo path',
      actor: 'buyer JWT',
      pre: 'policy UPDATE em fleaber_private dropada para order_proofs; chat_uploads?',
      repro: 'POST storage object same path x-upsert=true',
      expected: '409 / RLS deny',
      obtained: {'http': up2.status, 'body': clip(up2.body, 160)},
    );
  } else {
    c.block('AF6.UPSERT', 'AF6', 'upsert recusado', up2.brief);
  }

  final otherProof =
      'order_proofs/${c.sellerId}/00000000-0000-0000-0000-000000000001/${prefix}.png';
  final upOther = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$otherProof',
    jwt: c.buyerJwt,
    rawBytes: png,
    rawContentType: 'image/png',
  );
  if (upOther.ok) {
    c.hold(
      id: 'AF6.UPLOAD.OTHER-PREFIX',
      lens: 'AF6',
      severity: 'P1',
      title: 'Buyer faz upload para order_proofs/{seller}/…',
      actor: 'buyer JWT',
      pre: 'storage RLS insert own prefix',
      repro: 'POST storage order_proofs/{sellerId}/…',
      expected: 'RLS deny',
      obtained: upOther.brief,
    );
  } else {
    c.block('AF6.UPLOAD.OTHER-PREFIX', 'AF6', 'upload pasta alheia recusado',
        upOther.brief);
  }

  final signOther = await c.req(
    'POST',
    '/storage/v1/object/sign/fleaber_private/order_proofs/${c.sellerId}/x.png',
    jwt: c.buyerJwt,
    body: {'expiresIn': 60},
  );
  if (signOther.ok) {
    c.hold(
      id: 'AF6.SIGN.OTHER',
      lens: 'AF6',
      severity: 'P1',
      title: 'Buyer obtém signed URL de path order_proofs de outro uid',
      actor: 'buyer JWT',
      pre: 'sign deve exigir SELECT no objecto',
      repro: 'POST /object/sign/fleaber_private/order_proofs/{seller}/x.png',
      expected: 'deny',
      obtained: signOther.brief,
    );
  } else {
    c.block('AF6.SIGN.OTHER', 'AF6', 'sign alheio recusado', signOther.brief);
  }

  // =====================================================================
  // AF7 — cross-user
  // =====================================================================
  if (c.buyer2Jwt != null && reservedId != null) {
    final b2msg = await c.postMsg(
      chatId: chatId,
      jwt: c.buyer2Jwt!,
      text: fj({
        'kind': 'reservation_payment_submitted',
        'order_id': reservedId,
      }),
    );
    if (b2msg.ok) {
      c.hold(
        id: 'AF7.B2.THREAD',
        lens: 'AF7',
        severity: 'P1',
        title: 'Buyer2 injeta card na thread B–S',
        actor: 'buyer2 JWT',
        pre: 'insert exige participante',
        repro: 'POST chat_messages chat_id=B-S jwt=B2',
        expected: 'not participant / RLS',
        obtained: b2msg.brief,
      );
    } else {
      c.block('AF7.B2.THREAD', 'AF7', 'B2 fora da thread recusado',
          '${b2msg.pgCode} ${b2msg.pgMsg}');
    }

    final b2read = await c.rest(
      'GET',
      'chat_messages?chat_id=eq.$chatId&select=id,text&limit=3',
      jwt: c.buyer2Jwt!,
    );
    if (b2read.ok && b2read.list.isNotEmpty) {
      c.hold(
        id: 'AF7.B2.READ',
        lens: 'AF7',
        severity: 'P1',
        title: 'Buyer2 lê mensagens da thread B–S',
        actor: 'buyer2 JWT',
        pre: 'SELECT participantes',
        repro: 'GET chat_messages?chat_id=eq.B-S',
        expected: 'vazio / RLS',
        obtained: {'http': b2read.status, 'n': b2read.list.length},
      );
    } else {
      c.block('AF7.B2.READ', 'AF7', 'B2 não lê thread alheia',
          '${b2read.status} n=${b2read.list.length}');
    }

    if (reservedId != null) {
      final xurl =
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/order_proofs/${c.buyer2Id}/$reservedId/x.png';
      final xproof = await c.postMsg(
        chatId: chatId,
        jwt: c.buyerJwt!,
        text: fj({
          'kind': 'reservation_payment_submitted',
          'order_id': reservedId,
          'proof_url': xurl,
        }),
      );
      if (xproof.ok) {
        c.hold(
          id: 'AF7.PROOF.OTHER-UID-PATH',
          lens: 'AF7',
          severity: 'P2',
          title:
              'proof_url allowlist aceita path order_proofs/{outro_uid}/… — não amarra ao buyer/order',
          actor: 'buyer JWT',
          pre: 'allowlist prefixo fleaber_private sem checar uid/order',
          repro: 'POST proof_url=…/order_proofs/{buyer2}/{order}/x.png',
          expected: 'url denied ou path tem de ser deste pedido',
          obtained: {'http': xproof.status, 'msg': xproof.firstId},
        );
      } else {
        c.block('AF7.PROOF.OTHER-UID-PATH', 'AF7', 'path outro uid recusado',
            '${xproof.pgCode} ${xproof.pgMsg}');
      }
    }
  }

  // =====================================================================
  // AF8 — Edge vs chat (controlo)
  // =====================================================================
  if (unpaidId != null) {
    final edge = await c.edge('create-payment-intent', {
      'order_id': unpaidId,
      'amount': 1,
    }, jwt: c.buyerJwt);
    c.note('AF8.EDGE.PI', 'create-payment-intent amount=1 vs order', edge.brief,
        lens: 'AF8');
    final chatPaid = await c.postMsg(
      chatId: chatId,
      jwt: c.buyerJwt!,
      text: fj({
        'kind': 'seguro_fleaber_paid',
        'order_id': unpaidId,
        'total': 12.34,
      }),
    );
    if (chatPaid.ok) {
      c.hold(
        id: 'AF8.CHAT.PAID-UNPAID',
        lens: 'AF8',
        severity: 'P1',
        title: 'seguro_fleaber_paid inserido em pedido não pago (Edge não captura)',
        actor: 'buyer JWT',
        pre: 'v_needs_paid + captured',
        repro: 'POST seguro_fleaber_paid order reserva_pendente',
        expected: 'chat_system_card_order_not_paid',
        obtained: {'http': chatPaid.status, 'edge': edge.status},
      );
    } else {
      c.block(
        'AF8.CHAT.PAID-UNPAID',
        'AF8',
        'chat recusa pago em unpaid (Edge ${edge.status})',
        '${chatPaid.pgCode} ${chatPaid.pgMsg}',
      );
    }
  }

  await c.dumpAll('findings.json');
  stdout.writeln(
      'DONE findings=${c.findings.length} blocked=${c.blocked.length} notes=${c.notes.length}');
}
