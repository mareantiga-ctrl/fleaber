// ignore_for_file: avoid_print
/// REDTEAM BLIND AC — pós YZAA chat. dart run tool/redteam_blind_ac_20260901T1825/probe.dart
/// Não corrige. Staging only.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../live_ops_staging_client.dart';

const prefix = 'RTAC-20260901T1825';
const tinyPng = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
  Map<String, String>? extra,
]) async {
  final headers = {...h, if (extra != null) ...extra};
  final encoded = body == null
      ? null
      : body is String
          ? body
          : jsonEncode(body);
  late http.Response r;
  final uri = Uri.parse(u);
  switch (method) {
    case 'POST':
      r = await http.post(uri, headers: headers, body: encoded);
      break;
    case 'PATCH':
      r = await http.patch(uri, headers: headers, body: encoded);
      break;
    case 'PUT':
      r = await http.put(uri, headers: headers, body: encoded);
      break;
    case 'DELETE':
      r = await http.delete(uri, headers: headers, body: encoded);
      break;
    default:
      r = await http.get(uri, headers: headers);
  }
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body.length > 800 ? '${r.body.substring(0, 800)}…' : r.body;
  }
  return {'http': r.statusCode, 'body': p, 'raw_len': r.body.length};
}

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    final s = '${(body.first as Map)['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  if (body is Map && body['id'] != null) {
    final s = '${body['id']}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  return null;
}

Map<String, dynamic>? firstMap(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
  return null;
}

bool denied(Map<String, dynamic> r) => (r['http'] as int) >= 400;
bool persisted(Map<String, dynamic> r) =>
    (r['http'] as int) >= 200 && (r['http'] as int) < 300 && idOf(r['body']) != null;

String fj(Map<String, dynamic> m) => 'FLEABER_JSON_V1:${jsonEncode(m)}';

String brief(Map<String, dynamic> r) {
  final b = r['body'];
  String s;
  if (b is Map) {
    s = '${b['message'] ?? b['hint'] ?? b['code'] ?? b['error'] ?? b}';
  } else {
    s = '$b';
  }
  if (s.length > 240) s = '${s.substring(0, 240)}…';
  return 'http=${r['http']} $s';
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: wrong project');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final buyer2Id = (e['LIVE_OPS_TEST_BUYER2_ID'] ?? '').trim();
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  String? buyer2Tok;
  if (buyer2Id.isNotEmpty &&
      (e['LIVE_OPS_TEST_BUYER2_EMAIL'] ?? '').trim().isNotEmpty) {
    buyer2Tok = await sb.signIn(
      email: envRequire(e, 'LIVE_OPS_TEST_BUYER2_EMAIL'),
      password: envRequire(e, 'LIVE_OPS_TEST_BUYER2_PASSWORD'),
    );
  }

  Map<String, String> h(String tok) => {
        'apikey': anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  final BH = h(buyerTok);
  final SH = h(sellerTok);
  final B2H = buyer2Tok == null ? null : h(buyer2Tok);
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final ANON = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
  };

  final findings = <Map<String, dynamic>>[];
  final checks = <Map<String, dynamic>>[];

  void check(String id, String lens, {required bool open, String? detail}) {
    checks.add({'id': id, 'lens': lens, 'open': open, 'detail': detail});
    print('${open ? 'OPEN' : 'HOLD'} $id [$lens] ${detail ?? ''}');
  }

  void finding({
    required String id,
    required String sev,
    required String lens,
    required String actor,
    required String title,
    required String repro,
    required String impact,
    required Object proof,
  }) {
    findings.add({
      'id': id,
      'sev': sev,
      'lens': lens,
      'actor': actor,
      'title': title,
      'repro': repro,
      'impact': impact,
      'proof': proof,
    });
    print('FINDING $sev $id [$lens] $title');
  }

  Future<Map<String, dynamic>> postMsg(
    Map<String, String> hdr, {
    required String chatId,
    required String text,
    String? receiverId,
  }) {
    return req('POST', '$url/rest/v1/chat_messages', hdr, {
      'chat_id': chatId,
      'text': text,
      if (receiverId != null) 'receiver_id': receiverId,
    });
  }

  // ---- fixtures (service_role) ----
  final p1 = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': '$prefix-A',
    'price': 12.34,
    'quantity': 4,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final p2 = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': '$prefix-B',
    'price': 8.00,
    'quantity': 4,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final pid = idOf(p1['body']);
  final pidB = idOf(p2['body']);
  if (pid == null) {
    stderr.writeln('ABORT fixture product: ${brief(p1)}');
    exit(3);
  }

  final chatR = await req('POST', '$url/rest/v1/chats', SVC, {
    'user_a': buyerId,
    'user_b': sellerId,
    'product_id': pid,
    'last_message': '$prefix hello',
  });
  final chatId = idOf(chatR['body']);
  if (chatId == null) {
    stderr.writeln('ABORT fixture chat: ${brief(chatR)}');
    exit(3);
  }

  final exp = DateTime.now().toUtc().add(const Duration(days: 5)).toIso8601String();
  final hold = await req('POST', '$url/rest/v1/orders', SVC, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'status': 'reservado',
    'price_total': 12.34,
    'quantity': 1,
    'is_reservation': true,
    'reservation_expires_at': exp,
    'payment_method': 'mbway',
  });
  final holdOid = idOf(hold['body']);

  final paid = await req('POST', '$url/rest/v1/orders', SVC, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'status': 'pago',
    'price_total': 12.34,
    'quantity': 1,
    'amount_paid_cents': 1234,
    'stripe_payment_intent_id': 'pi_test_$prefix',
    'payment_method': 'stripe',
  });
  var paidOid = idOf(paid['body']);
  if (paidOid == null) {
    // fallback: promote hold via service_role
    if (holdOid != null) {
      await req('PATCH', '$url/rest/v1/orders?id=eq.$holdOid', SVC, {
        'status': 'pago',
        'amount_paid_cents': 1234,
        'stripe_payment_intent_id': 'pi_test_$prefix',
      });
      paidOid = holdOid;
    }
  }
  if (paidOid == null) {
    stderr.writeln('ABORT fixture paid order: ${brief(paid)} ${brief(hold)}');
    exit(3);
  }

  // reserved-only order if paid reused hold
  String? resOid = holdOid;
  if (resOid == null || resOid == paidOid) {
    final hold2 = await req('POST', '$url/rest/v1/orders', SVC, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'status': 'reservado',
      'price_total': 12.34,
      'quantity': 1,
      'is_reservation': true,
      'reservation_expires_at': exp,
      'payment_method': 'mbway',
    });
    resOid = idOf(hold2['body']);
  }

  final offerR = await req('POST', '$url/rest/v1/product_offers', SVC, {
    'product_id': pid,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 9.50,
    'status': 'pending',
    'offered_by': 'buyer',
  });
  final offerId = idOf(offerR['body']);

  String? bundleId;
  if (pidB != null) {
    final bun = await req('POST', '$url/rest/v1/product_bundles', SVC, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_ids': [pid, pidB],
      'chat_id': chatId,
      'status': 'cancelled',
      'total_eur': 18.00,
    });
    bundleId = idOf(bun['body']);
    if (bundleId == null) {
      final bun2 = await req('POST', '$url/rest/v1/product_bundles', SVC, {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_ids': [pid, pidB],
        'chat_id': chatId,
      });
      bundleId = idOf(bun2['body']);
      if (bundleId != null) {
        await req('PATCH', '$url/rest/v1/product_bundles?id=eq.$bundleId', SVC, {
          'status': 'cancelled',
          'total_eur': 18.00,
        });
      }
    }
  }

  await req('POST', '$url/rest/v1/reviews', SVC, {
    'order_id': paidOid,
    'reviewer_id': buyerId,
    'reviewee_id': sellerId,
    'rating': 5,
    'comment': '$prefix genuine',
  });

  print('FIXTURE chat=$chatId hold=$resOid paid=$paidOid offer=$offerId bundle=$bundleId');

  // =====================================================================
  // AC2 — prefix / encoding (NEW vs raw `{` exact)
  // =====================================================================
  final wsVariants = <String, String>{
    'nbsp': '\u00a0',
    'nel': '\u0085',
    'emquad': '\u2003',
    'nnbsp': '\u202f',
    'ideo': '\u3000',
    'zwsp': '\u200b',
    'zwnj': '\u200c',
    'bom_nbsp': '\uFEFF\u00a0',
  };
  final rawBundle = jsonEncode({
    'kind': 'bundle_proposal',
    'bundle_id': bundleId,
    'total_eur': 6543.21,
    'discount_eur': 0,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_ids': [pid, pidB],
  });

  String? nbspMsgId;
  for (final e in wsVariants.entries) {
    final text = '${e.value}$rawBundle';
    final r = await postMsg(BH, chatId: chatId, text: text, receiverId: sellerId);
    final ok = persisted(r);
    check('AC2-ws-${e.key}', 'AC2', open: ok, detail: brief(r));
    if (ok && (e.key == 'nbsp' || e.key == 'ideo' || e.key == 'emquad')) {
      nbspMsgId ??= idOf(r['body']);
      finding(
        id: 'AC2-WS-${e.key.toUpperCase()}-BUNDLE-RAW',
        sev: 'P1',
        lens: 'AC2',
        actor: 'buyer',
        title:
            'JSON cru bundle_proposal prefixado com whitespace Unicode (${e.key}) passa o trigger (btrim não corta) e o Flutter trim()+parse ainda pinta o card',
        repro:
            'POST chat_messages text=<U+${e.key}>{"kind":"bundle_proposal","total_eur":6543.21,...} sem FLEABER_JSON_V1',
        impact:
            'SQL trata como texto livre; tryParseBundleProposalChatPayload faz trim() (corta NBSP/ideo/emquad) e mostra total_eur do JSON. Em conjunto histórico o card usa payload, não a BD.',
        proof: {'http': r['http'], 'id': idOf(r['body']), 'ws': e.key},
      );
    }
  }

  // prefix whitespace / nested / homoglyph colon
  final enc = <String, String>{
    'lead_space_prefix': ' FLEABER_JSON_V1:${jsonEncode({'kind': 'chat_image', 'path': 'chat_uploads/$buyerId/$chatId/x.png'})}',
    'nbsp_prefix': '\u00a0FLEABER_JSON_V1:${jsonEncode({'kind': 'chat_image', 'path': 'chat_uploads/$buyerId/$chatId/x.png'})}',
    'fullwidth_colon': 'FLEABER_JSON_V1：${jsonEncode({'kind': 'chat_image', 'path': 'chat_uploads/$buyerId/$chatId/x.png'})}',
    'nl_after_prefix': 'FLEABER_JSON_V1:\n${jsonEncode({'kind': 'chat_image', 'path': 'chat_uploads/$buyerId/$chatId/x.png'})}',
    'tab_after_prefix': 'FLEABER_JSON_V1:\t${jsonEncode({'kind': 'chat_image', 'path': 'chat_uploads/$buyerId/$chatId/x.png'})}',
    'double_prefix': 'FLEABER_JSON_V1:FLEABER_JSON_V1:${jsonEncode({'kind': 'chat_image', 'path': 'chat_uploads/$buyerId/$chatId/x.png'})}',
    'lower_prefix': 'fleaber_json_v1:${jsonEncode({'kind': 'chat_image', 'path': 'chat_uploads/$buyerId/$chatId/x.png'})}',
    'array_json': jsonEncode([
      {'kind': 'bundle_proposal', 'total_eur': 6543.21}
    ]),
  };
  for (final e in enc.entries) {
    final r = await postMsg(BH, chatId: chatId, text: e.value, receiverId: sellerId);
    check('AC2-enc-${e.key}', 'AC2',
        open: persisted(r) && e.key != 'array_json' && e.key != 'lower_prefix',
        detail: brief(r));
  }

  // =====================================================================
  // AC1 — cards vs BD (kinds that don't cross-check status/amount)
  // =====================================================================
  if (resOid != null) {
    final declined = await postMsg(SH, chatId: chatId, text: fj({
      'kind': 'reservation_request_outcome',
      'order_id': resOid,
      'outcome': 'rejected',
    }), receiverId: buyerId);
    final open = persisted(declined);
    check('AC1-outcome-rejected-while-reservado', 'AC1',
        open: open, detail: brief(declined));
    if (open) {
      finding(
        id: 'AC1-RES-OUTCOME-REJECTED-LIE',
        sev: 'P1',
        lens: 'AC1',
        actor: 'seller',
        title:
            'Card reservation_request_outcome=rejected inserido com encomenda ainda reservado — UI diz recusou, BD não mudou',
        repro:
            'POST FLEABER_JSON_V1 kind=reservation_request_outcome outcome=rejected order_id=<reservado> (seller)',
        impact:
            'assert_json_card só cruza status quando outcome=accepted. Flutter pinta «O vendedor recusou o pedido de reserva.» sem ler orders.status.',
        proof: {'http': declined['http'], 'id': idOf(declined['body']), 'order': resOid},
      );
    }

    final accWrong = await postMsg(SH, chatId: chatId, text: fj({
      'kind': 'reservation_request_outcome',
      'order_id': resOid,
      'outcome': 'accepted',
    }), receiverId: buyerId);
    check('AC1-outcome-accepted-reservado', 'AC1',
        open: persisted(accWrong), detail: brief(accWrong));
  }

  if (offerId != null) {
    final fakeOffer = await postMsg(BH, chatId: chatId, text: fj({
      'kind': 'price_offer',
      'order_id': paidOid,
      'amount': 9999.0,
      'offered_by': 'buyer',
      'buyer_id': buyerId,
      'seller_id': sellerId,
    }), receiverId: sellerId);
    final open = persisted(fakeOffer);
    check('AC1-price-offer-no-offer-id', 'AC1', open: open, detail: brief(fakeOffer));
    if (open) {
      finding(
        id: 'AC1-PRICE-OFFER-ORPHAN-AMOUNT',
        sev: 'P1',
        lens: 'AC1',
        actor: 'buyer',
        title:
            'price_offer FLEABER_JSON_V1 sem offer_id e amount=9999 aceite — card usa payload.amount (offer_id null ⇒ resolved=true)',
        repro:
            'POST FLEABER_JSON_V1 kind=price_offer order_id=<pago> amount=9999 (sem offer_id)',
        impact:
            'Trigger não exige offer_id nem cruza product_offers. PriceOfferChatCard mostra 9999 € como proposta já resolvida.',
        proof: {'http': fakeOffer['http'], 'id': idOf(fakeOffer['body'])},
      );
    }

    final outAcc = await postMsg(SH, chatId: chatId, text: fj({
      'kind': 'price_offer_outcome',
      'order_id': paidOid,
      'offer_id': offerId,
      'amount': 9.50,
      'outcome': 'accepted',
    }), receiverId: buyerId);
    final open2 = persisted(outAcc);
    check('AC1-price-offer-outcome-accepted-while-pending', 'AC1',
        open: open2, detail: brief(outAcc));
    if (open2) {
      finding(
        id: 'AC1-PRICE-OFFER-OUTCOME-STATUS-LIE',
        sev: 'P1',
        lens: 'AC1',
        actor: 'seller',
        title:
            'price_offer_outcome=accepted com amount correcto mas offer.status ainda pending — UI diz proposta aceite',
        repro:
            'POST FLEABER_JSON_V1 kind=price_offer_outcome outcome=accepted offer_id=<pending> amount=BD',
        impact:
            'Trigger valida amount vs product_offers, não status. PriceOfferOutcomeChatCard pinta «Proposta aceite — o comprador pode concluir a compra».',
        proof: {'http': outAcc['http'], 'id': idOf(outAcc['body']), 'offer': offerId},
      );
    }
  }

  final fakeStars = await postMsg(BH, chatId: chatId, text: fj({
    'kind': 'order_review_submitted',
    'order_id': paidOid,
    'author_role': 'comprador',
    'stars': 1,
  }), receiverId: sellerId);
  final starsOpen = persisted(fakeStars);
  check('AC1-review-stars-payload', 'AC1', open: starsOpen, detail: brief(fakeStars));
  if (starsOpen) {
    finding(
      id: 'AC1-REVIEW-STARS-PAYLOAD',
      sev: 'P2',
      lens: 'AC1',
      actor: 'buyer',
      title:
          'order_review_submitted exige que exista review na BD mas stars/author_role vêm do JSON — card pode mostrar 1★ com review real 5★',
      repro:
          'POST FLEABER_JSON_V1 kind=order_review_submitted order_id=<com review 5★> stars=1',
      impact:
          'Flutter _buildOrderReviewSubmittedCard usa payload.stars, não reviews.rating.',
      proof: {'http': fakeStars['http'], 'id': idOf(fakeStars['body'])},
    );
  }

  final dupSeguro = await postMsg(BH, chatId: chatId, text: fj({
    'kind': 'seguro_fleaber_paid',
    'order_id': paidOid,
    'total': 12.34,
    'label': 'PIX confirmado 4321 €',
  }), receiverId: sellerId);
  check('AC1-seguro-label-extra', 'AC1',
      open: persisted(dupSeguro), detail: brief(dupSeguro));
  if (persisted(dupSeguro)) {
    finding(
      id: 'AC1-SEGURO-LABEL-INJECT',
      sev: 'P2',
      lens: 'AC1',
      actor: 'buyer',
      title:
          'Segundo card seguro_fleaber_paid com total correcto + label livre — UI concatena «· PIX confirmado 4321 €»',
      repro:
          'POST FLEABER_JSON_V1 kind=seguro_fleaber_paid total=<paid_cents/100> label=«PIX confirmado 4321 €»',
      impact:
          'total é cruzado; label não. Card «Compra paga através do Seguro Fleaber · 12,34 € · PIX confirmado 4321 €».',
      proof: {'http': dupSeguro['http'], 'id': idOf(dupSeguro['body'])},
    );
  }

  if (resOid != null) {
    final cancelOut = await postMsg(SH, chatId: chatId, text: fj({
      'kind': 'cancel_request_outcome',
      'order_id': resOid,
      'outcome': 'rejected',
    }), receiverId: buyerId);
    check('AC1-cancel-outcome-rejected', 'AC1',
        open: persisted(cancelOut), detail: brief(cancelOut));
  }

  // kinds Flutter still paints but SQL should deny (control)
  for (final kind in [
    'reservation_reminder',
    'auto_feedback_generated',
    'raffle_prize_awarded',
    'order_paid',
  ]) {
    final r = await postMsg(BH, chatId: chatId, text: fj({
      'kind': kind,
      'order_id': paidOid,
      'total': 12.34,
    }), receiverId: sellerId);
    check('AC1-denied-$kind', 'AC1', open: persisted(r), detail: brief(r));
  }

  // =====================================================================
  // AC4 — URLs (NEW vs javascript: exact)
  // =====================================================================
  if (resOid != null) {
    final urlVars = <String, String>{
      'nested_app': 'https://fleaber.app/https://evil.example/receipt.png',
      'query_https': 'https://www.fleaber.pt/?next=https://evil.example/x',
      'hash_https': 'https://fleaber.app/#https://evil.example/x',
      'userinfo': 'https://fleaber.app@evil.example/x.png',
      'subdomain': 'https://fleaber.app.evil.example/x.png',
      'vbscript': 'vbscript:msgbox(1)',
      'file': 'file:///etc/passwd',
      'mailto': 'mailto:x@evil.example',
      'storage_public':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/avatars/x.png',
      'tab_nested': 'https://fleaber.app/\thttps://evil.example/x',
    };
    for (final e in urlVars.entries) {
      final r = await postMsg(BH, chatId: chatId, text: fj({
        'kind': 'reservation_payment_submitted',
        'order_id': resOid,
        'proof_url': e.value,
        'notes': '$prefix ${e.key}',
      }), receiverId: sellerId);
      final ok = persisted(r);
      check('AC4-proof-${e.key}', 'AC4', open: ok, detail: brief(r));
      if (ok) {
        finding(
          id: 'AC4-PROOF-${e.key.toUpperCase()}',
          sev: (e.key == 'nested_app' || e.key == 'query_https' || e.key == 'hash_https')
              ? 'P1'
              : 'P2',
          lens: 'AC4',
          actor: 'buyer',
          title:
              'reservation_payment_submitted proof_url=${e.key} aceite (allowlist chat mais frouxa que orders_guard)',
          repro:
              'POST FLEABER_JSON_V1 kind=reservation_payment_submitted proof_url=${e.value}',
          impact:
              'Chat só bloqueia javascript/data/protocol-relative/newline + prefixo de host. Não tem os checks de URL-em-URL do batata_orders_guard_proof_url. Flutter abre proof_url no Image.network sem segundo filtro.',
          proof: {'http': r['http'], 'id': idOf(r['body']), 'url': e.value},
        );
      }
    }

    // orders.proof_url same nested URL (control vs chat)
    final ordNested = await req('PATCH', '$url/rest/v1/orders?id=eq.$resOid', BH, {
      'proof_url': 'https://fleaber.app/https://evil.example/receipt.png',
    });
    check('AC4-order-proof-nested-app', 'AC4',
        open: !denied(ordNested), detail: brief(ordNested));
  }

  // chat_image: url allowlisted but different object vs path
  final imgMismatch = await postMsg(BH, chatId: chatId, text: fj({
    'kind': 'chat_image',
    'path': 'chat_uploads/$buyerId/$chatId/cover.png',
    'url':
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/order_proofs/$sellerId/secret.png',
  }), receiverId: sellerId);
  check('AC4-chat-image-url-mismatch', 'AC4',
      open: persisted(imgMismatch), detail: brief(imgMismatch));

  final imgPct = await postMsg(BH, chatId: chatId, text: fj({
    'kind': 'chat_image',
    'path': 'chat_uploads/$buyerId/%2e%2e/order_proofs/x.png',
  }), receiverId: sellerId);
  check('AC4-chat-image-pct-dotdot', 'AC4',
      open: persisted(imgPct), detail: brief(imgPct));

  // =====================================================================
  // AC3 — cronologia
  // =====================================================================
  final future = DateTime.now().toUtc().add(const Duration(days: 400)).toIso8601String();
  final past = '2015-01-01T00:00:00Z';
  final timeFuture = await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
    'last_message_time': future,
  });
  var timeAfter = await req(
    'GET',
    '$url/rest/v1/chats?id=eq.$chatId&select=id,last_message_time,last_message',
    BH,
  );
  final storedTime = firstMap(timeAfter['body'])?['last_message_time']?.toString() ?? '';
  final futureHeld = !denied(timeFuture) && storedTime.startsWith('20') && storedTime.compareTo(DateTime.now().toUtc().add(const Duration(days: 2)).toIso8601String()) > 0;
  check('AC3-inbox-time-future', 'AC3', open: futureHeld, detail: 'stored=$storedTime ${brief(timeFuture)}');
  if (futureHeld) {
    finding(
      id: 'AC3-INBOX-TIME-FUTURE',
      sev: 'P2',
      lens: 'AC3',
      actor: 'buyer',
      title: 'chats.last_message_time no futuro aceite — guard só clampa datas < now-2min',
      repro: 'PATCH chats last_message_time=+400d',
      impact: 'Inbox ordenada por last_message_time: thread sobe ao topo eterno.',
      proof: {'stored': storedTime, 'http': timeFuture['http']},
    );
  }

  final timePast = await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
    'last_message_time': past,
  });
  timeAfter = await req(
    'GET',
    '$url/rest/v1/chats?id=eq.$chatId&select=last_message_time',
    BH,
  );
  final storedPast = firstMap(timeAfter['body'])?['last_message_time']?.toString() ?? '';
  check('AC3-inbox-time-past-clamped', 'AC3',
      open: storedPast.startsWith('2015'), detail: 'stored=$storedPast ${brief(timePast)}');

  final createdAtPatch = await req(
    'PATCH',
    '$url/rest/v1/chat_messages?chat_id=eq.$chatId&select=id,created_at&limit=1',
    BH,
    {'created_at': past},
  );
  check('AC3-msg-created-at-patch', 'AC3',
      open: !denied(createdAtPatch), detail: brief(createdAtPatch));

  // INSERT chat with forged time (guard is UPDATE-only)
  final insChat = await req('POST', '$url/rest/v1/chats', BH, {
    'user_a': buyerId,
    'user_b': sellerId,
    'product_id': pid,
    'last_message': 'Seguro Fleaber 999,00 €',
    'last_message_time': past,
  });
  check('AC3-chat-insert-backdate+forge', 'AC3',
      open: persisted(insChat), detail: brief(insChat));
  final insChatId = idOf(insChat['body']);
  if (persisted(insChat)) {
    final row = firstMap(insChat['body']);
    finding(
      id: 'AC5-INBOX-INSERT-FORGE',
      sev: 'P1',
      lens: 'AC5',
      actor: 'buyer',
      title:
          'INSERT chats.last_message «Seguro Fleaber 999,00 €» aceite — trigger só corre em UPDATE',
      repro:
          'POST chats user_a/b last_message="Seguro Fleaber 999,00 €" last_message_time=2015',
      impact:
          'Inbox mostra preview de recibo forjado sem mensagem JSON. batata_chats_guard_update não se aplica a INSERT.',
      proof: {
        'http': insChat['http'],
        'id': insChatId,
        'last_message': row?['last_message'],
        'last_message_time': row?['last_message_time'],
      },
    );
  }

  // =====================================================================
  // AC5 — inbox UPDATE bypass + delete
  // =====================================================================
  final inboxBypass = <String, String>{
    'mbway': 'MB WAY 99,00 €',
    'seguro_int': 'Seguro Fleaber 12 €',
    'compra_int': 'Compra paga 12 €',
    'eur_word': 'Seguro Fleaber 99,00 EUR',
    'pix': 'PIX 4321,00 €',
  };
  for (final e in inboxBypass.entries) {
    final r = await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
      'last_message': e.value,
    });
    final ok = !denied(r);
    check('AC5-inbox-bypass-${e.key}', 'AC5', open: ok, detail: brief(r));
    if (ok && (e.key == 'mbway' || e.key == 'seguro_int')) {
      finding(
        id: 'AC5-INBOX-REGEX-BYPASS-${e.key.toUpperCase()}',
        sev: 'P2',
        lens: 'AC5',
        actor: 'buyer',
        title: 'last_message «${e.value}» passa o regex (Seguro Fleaber|Compra paga)+decimal+€',
        repro: 'PATCH chats last_message="${e.value}"',
        impact: 'Preview de inbox enganador sem disparar chat_inbox_preview_forbidden.',
        proof: {'http': r['http'], 'text': e.value},
      );
    }
  }

  // DELETE JSON card
  final jsonMsg = await postMsg(BH, chatId: chatId, text: fj({
    'kind': 'reservation_request',
    'order_id': paidOid,
  }), receiverId: sellerId);
  final jsonId = idOf(jsonMsg['body']);
  if (jsonId != null) {
    final del = await req('DELETE', '$url/rest/v1/chat_messages?id=eq.$jsonId', BH);
    check('AC5-delete-json-card', 'AC5', open: !denied(del), detail: brief(del));
  } else {
    check('AC5-delete-json-card', 'AC5', open: false, detail: 'insert failed ${brief(jsonMsg)}');
  }

  if (nbspMsgId != null) {
    final delPlain = await req('DELETE', '$url/rest/v1/chat_messages?id=eq.$nbspMsgId', BH);
    final gone = await req(
      'GET',
      '$url/rest/v1/chat_messages?id=eq.$nbspMsgId&select=id',
      BH,
    );
    final vanished = (gone['body'] is List && (gone['body'] as List).isEmpty) ||
        !denied(delPlain);
    check('AC5-delete-nbsp-raw-json', 'AC5',
        open: vanished && !denied(delPlain), detail: brief(delPlain));
    if (!denied(delPlain)) {
      finding(
        id: 'AC5-DELETE-UNICODE-RAW-CARD',
        sev: 'P1',
        lens: 'AC5',
        actor: 'buyer',
        title:
            'Card bundle_proposal via NBSP+JSON cru é apagável — DELETE só protege prefixo FLEABER_JSON_V1',
        repro: 'POST NBSP+{"kind":"bundle_proposal"...}; DELETE chat_messages?id=',
        impact: 'Prova visual forjada e depois apagada; imutabilidade não cobre o bypass de encoding.',
        proof: {'delete_http': delPlain['http'], 'id': nbspMsgId},
      );
    }
  }

  // GraphQL delete
  if (jsonId != null) {
    final gql = await req('POST', '$url/graphql/v1', BH, {
      'query':
          'mutation { deleteFromchat_messagesCollection(filter: { id: { eq: $jsonId } }) { records { id } } }',
    });
    check('AC5-graphql-delete', 'AC5',
        open: !denied(gql) && '${gql['body']}'.contains('"$jsonId"'),
        detail: brief(gql));
  }

  // =====================================================================
  // AC6 — storage
  // =====================================================================
  final png = base64Decode(tinyPng);
  final proofPath = 'order_proofs/$buyerId/$paidOid/${prefix}-a.png';
  final up1 = await http.post(
    Uri.parse('$url/storage/v1/object/fleaber_private/$proofPath'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
      'Content-Type': 'image/png',
      'x-upsert': 'false',
    },
    body: png,
  );
  check('AC6-upload-insert', 'AC6',
      open: up1.statusCode >= 400, detail: 'http=${up1.statusCode} ${up1.body}');

  final up2 = await http.post(
    Uri.parse('$url/storage/v1/object/fleaber_private/$proofPath'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
      'Content-Type': 'image/png',
      'x-upsert': 'true',
    },
    body: Uint8List.fromList([...png, 0x00]),
  );
  check('AC6-upsert-xtrue', 'AC6',
      open: up2.statusCode < 400, detail: 'http=${up2.statusCode} ${up2.body}');
  if (up2.statusCode < 400) {
    finding(
      id: 'AC6-STORAGE-XUPSERT',
      sev: 'P1',
      lens: 'AC6',
      actor: 'buyer',
      title: 'x-upsert=true ainda substitui order_proofs no mesmo path após drop da policy UPDATE',
      repro:
          'POST storage fleaber_private/order_proofs/{uid}/{order}/file.png header x-upsert:true',
      impact:
          'URL de comprovativo imutável, bytes mutáveis. Vendedor reabre o mesmo link e vê outro ficheiro.',
      proof: {'http': up2.statusCode, 'path': proofPath, 'body': up2.body},
    );
  }

  final put = await http.put(
    Uri.parse('$url/storage/v1/object/fleaber_private/$proofPath'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
      'Content-Type': 'image/png',
    },
    body: png,
  );
  check('AC6-put', 'AC6', open: put.statusCode < 400, detail: 'http=${put.statusCode}');

  final copy = await req('POST', '$url/storage/v1/object/copy', BH, {
    'bucketId': 'fleaber_private',
    'sourceKey': proofPath,
    'destinationKey': 'order_proofs/$buyerId/$paidOid/${prefix}-copy.png',
  });
  check('AC6-copy', 'AC6', open: !denied(copy), detail: brief(copy));

  final move = await req('POST', '$url/storage/v1/object/move', BH, {
    'bucketId': 'fleaber_private',
    'sourceKey': proofPath,
    'destinationKey': 'order_proofs/$sellerId/$paidOid/${prefix}-moved.png',
  });
  check('AC6-move-other-uid', 'AC6', open: !denied(move), detail: brief(move));

  // =====================================================================
  // AC7 — cross-user
  // =====================================================================
  if (B2H != null) {
    final read = await req(
      'GET',
      '$url/rest/v1/chat_messages?chat_id=eq.$chatId&select=id,text&limit=3',
      B2H,
    );
    final rows = read['body'];
    final leaked = rows is List && rows.isNotEmpty;
    check('AC7-b2-read-messages', 'AC7', open: leaked, detail: brief(read));
    if (leaked) {
      finding(
        id: 'AC7-B2-READ-THREAD',
        sev: 'P0',
        lens: 'AC7',
        actor: 'buyer2',
        title: 'B2 lê chat_messages da thread B1/S1',
        repro: 'GET chat_messages?chat_id=eq.<thread alheia>',
        impact: 'Confidencialidade do chat quebrada.',
        proof: {'http': read['http'], 'n': (rows as List).length},
      );
    }

    final write = await postMsg(B2H, chatId: chatId, text: '$prefix b2 inject', receiverId: sellerId);
    check('AC7-b2-write-thread', 'AC7', open: persisted(write), detail: brief(write));

    final sign = await req(
      'POST',
      '$url/storage/v1/object/sign/fleaber_private/$proofPath',
      B2H,
      {'expiresIn': 60},
    );
    check('AC7-b2-sign-proof', 'AC7', open: !denied(sign), detail: brief(sign));
    if (!denied(sign)) {
      finding(
        id: 'AC7-B2-SIGN-PROOF',
        sev: 'P1',
        lens: 'AC7',
        actor: 'buyer2',
        title: 'B2 cria signed URL de order_proofs do buyer1',
        repro: 'POST /storage/v1/object/sign/fleaber_private/order_proofs/{b1}/{order}/…',
        impact: 'Comprovativo MB WAY / Stripe visível a terceiro.',
        proof: {'http': sign['http']},
      );
    }

    final list = await req('POST', '$url/storage/v1/object/list/fleaber_private', B2H, {
      'prefix': 'order_proofs/$buyerId',
      'limit': 5,
    });
    check('AC7-b2-list-proofs', 'AC7',
        open: !denied(list) && '${list['body']}'.contains(prefix),
        detail: brief(list));
  } else {
    check('AC7-b2-read-messages', 'AC7', open: false, detail: 'no buyer2');
  }

  final anonRead = await req(
    'GET',
    '$url/rest/v1/chat_messages?chat_id=eq.$chatId&select=id&limit=1',
    ANON,
  );
  check('AC7-anon-read', 'AC7',
      open: !denied(anonRead) && anonRead['body'] is List && (anonRead['body'] as List).isNotEmpty,
      detail: brief(anonRead));

  // =====================================================================
  // AC8 — Edge vs chat (control)
  // =====================================================================
  final edge = await sb.invokeEdge('create-payment-intent', {
    'order_id': paidOid,
    'amount': 1,
  }, accessToken: buyerTok);
  check('AC8-edge-amount-1-on-paid', 'AC8',
      open: edge.statusCode < 400, detail: 'http=${edge.statusCode} ${edge.body.length > 200 ? edge.body.substring(0, 200) : edge.body}');

  // =====================================================================
  // extras: UPDATE json via merge, RPC
  // =====================================================================
  final upsertMsg = await req(
    'POST',
    '$url/rest/v1/chat_messages',
    BH,
    {
      'id': jsonId,
      'text': fj({'kind': 'seguro_fleaber_paid', 'order_id': paidOid, 'total': 1}),
    },
    {'Prefer': 'resolution=merge-duplicates,return=representation'},
  );
  check('AC2-upsert-json-row', 'AC2',
      open: !denied(upsertMsg), detail: brief(upsertMsg));

  final out = {
    'auditor': 'REDTEAM_BLIND_AC_POS_YZAA_v1',
    'prefix': prefix,
    'fixture': {
      'chatId': chatId,
      'paidOid': paidOid,
      'resOid': resOid,
      'offerId': offerId,
      'bundleId': bundleId,
      'productId': pid,
    },
    'checks': checks,
    'findings': findings,
    'open_count': findings.length,
  };
  final outFile = File('tool/redteam_blind_ac_20260901T1825/probe_result.json');
  outFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print('WROTE ${outFile.path} findings=${findings.length} checks=${checks.length}');
}
