// ignore_for_file: avoid_print
/// REDTEAM_BLIND_AI_CHAT_POS_AEAFAG_v1 — probe staging only. NÃO CORRIGIR.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

const prefix = 'RTAI-20260902T0728';

typedef Hit = ({int http, dynamic body, String raw, String? id});

final findings = <Map<String, dynamic>>[];
final blocked = <Map<String, dynamic>>[];

void noteOpen({
  required String id,
  required String lens,
  required String sev,
  required String title,
  required String pre,
  required String repro,
  required Object evidence,
  String flutter = '',
}) {
  findings.add({
    'id': id,
    'open': true,
    'lens': lens,
    'sev': sev,
    'title': title,
    'pre': pre,
    'repro': repro,
    'flutter': flutter,
    'evidence': evidence,
  });
  print('OPEN $sev $id  $title');
}

void noteBlocked({
  required String id,
  required String lens,
  required String title,
  required Object evidence,
}) {
  blocked.add({
    'id': id,
    'open': false,
    'lens': lens,
    'title': title,
    'evidence': evidence,
  });
  print('BLOCK $id  $title');
}

Future<Hit> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
  List<int>? bytes,
]) async {
  late http.Response r;
  if (bytes != null) {
    r = await http.post(Uri.parse(u), headers: h, body: bytes);
  } else if (method == 'POST') {
    r = await http.post(
      Uri.parse(u),
      headers: h,
      body: body == null ? null : jsonEncode(body),
    );
  } else if (method == 'PATCH') {
    r = await http.patch(
      Uri.parse(u),
      headers: h,
      body: body == null ? null : jsonEncode(body),
    );
  } else if (method == 'DELETE') {
    r = await http.delete(Uri.parse(u), headers: h);
  } else {
    r = await http.get(Uri.parse(u), headers: h);
  }
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  String? id;
  if (p is List && p.isNotEmpty && p.first is Map) {
    id = '${(p.first as Map)['id']}'.trim();
  } else if (p is Map && p['id'] != null) {
    id = '${p['id']}'.trim();
  }
  return (http: r.statusCode, body: p, raw: r.body, id: id);
}

String? msgOf(Hit h) {
  final b = h.body;
  if (b is Map) return '${b['message'] ?? b['code'] ?? h.raw}';
  return h.raw.length > 240 ? h.raw.substring(0, 240) : h.raw;
}

String fj(Map<String, dynamic> m) => 'FLEABER_JSON_V1:${jsonEncode(m)}';

Map<String, dynamic>? firstMap(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
  return null;
}

bool stored(Hit h) => h.http >= 200 && h.http < 300 && h.id != null;

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: wrong project');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');

  Map<String, String> H(String tok) => {
        'apikey': anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  final BH = H(buyerTok);
  final SH = H(sellerTok);
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final E2E = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    if ((e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim().length >= 16)
      'x-fleaber-e2e-secret':
          (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim(),
  };

  // --- buyer2 ---
  final b2email = '${prefix.toLowerCase()}-b2@fleaber.test';
  const b2pass = 'Rtai0728b2!xK9';
  await req('POST', '$url/auth/v1/admin/users', SVC, {
    'email': b2email,
    'password': b2pass,
    'email_confirm': true,
  });
  final b2tok = await sb.signIn(email: b2email, password: b2pass);
  final b2me = await req('GET', '$url/auth/v1/user', {
    'apikey': anon,
    'Authorization': 'Bearer $b2tok',
  });
  final buyer2Id = firstMap(b2me.body)?['id']?.toString() ?? '';
  final B2H = H(b2tok);
  if (buyer2Id.isNotEmpty) {
    await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyer2Id', SVC, {
      'full_name': '$prefix-B2',
      'handle': 'rtai0728b2',
      'hub_published': false,
      'is_live': false,
    });
  }

  // --- fixtures ---
  final chat = await req('POST', '$url/rest/v1/chats', SVC, {
    'user_a': buyerId,
    'user_b': sellerId,
  });
  final chatId = chat.id;
  if (chatId == null) {
    stderr.writeln('ABORT no chat ${chat.raw}');
    exit(2);
  }

  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': '$prefix-sku',
    'price': 40.0,
    'quantity': 8,
    'list_on_marketplace': true,
    'is_sold': false,
    'available_for_live': true,
    'description': prefix,
    'image_urls': <String>[],
  });
  final productId = prod.id;
  if (productId == null) {
    stderr.writeln('ABORT no product ${prod.raw}');
    exit(2);
  }

  final decoy = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': '$prefix-decoy-999',
    'price': 999.0,
    'quantity': 1,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final decoyId = decoy.id;

  Future<String?> mkOrder({
    required String status,
    double price = 40.0,
    String payment = 'Pagamento na app',
    String shipping = 'entrega em mão',
    int? paidCents,
    String? pi,
    String? refund,
    String? expires,
  }) async {
    final o = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': productId,
      'price_total': price,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': payment,
      'shipping_method': shipping,
    });
    final id = o.id;
    if (id == null) {
      print('WARN order insert ${o.http} ${msgOf(o)}');
      return null;
    }
    final patch = <String, dynamic>{'status': status, 'price_total': price};
    if (paidCents != null) patch['amount_paid_cents'] = paidCents;
    if (pi != null) patch['stripe_payment_intent_id'] = pi;
    if (refund != null) patch['stripe_refund_id'] = refund;
    if (expires != null) patch['reservation_expires_at'] = expires;
    await req('PATCH', '$url/rest/v1/orders?id=eq.$id', SVC, patch);
    return id;
  }

  String? paidId;
  final e2e = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'probe': 'setup_paid_order',
      'initial_qty': 2,
      'shipping_method': 'mao',
    },
  );
  final e2b = e2e.body;
  if (e2b is Map) {
    paidId = '${e2b['order_id'] ?? ''}'.trim();
    if (paidId.isEmpty && e2b['order'] is Map) {
      paidId = '${(e2b['order'] as Map)['id']}'.trim();
    }
  }
  paidId = (paidId == null || paidId.isEmpty)
      ? await mkOrder(
          status: 'pago',
          paidCents: 1234,
          pi: 'pi_${prefix}_fixture',
        )
      : paidId;

  final reservedId = await mkOrder(
    status: 'reservado',
    expires: DateTime.now().toUtc().add(const Duration(days: 5)).toIso8601String(),
  );
  final pendingId = await mkOrder(status: 'reserva_pendente');
  final cancelledId = await mkOrder(
    status: 'cancelado',
    paidCents: 1234,
    pi: 'pi_${prefix}_cancel',
    refund: 're_${prefix}_cancel',
  );
  final mbwayId = await mkOrder(
    status: 'reservado',
    payment: 'MB WAY',
    shipping: 'ctt',
  );

  print('FIX chat=$chatId paid=$paidId reserved=$reservedId '
      'pending=$pendingId cancelled=$cancelledId mbway=$mbwayId b2=$buyer2Id');

  Future<Hit> postMsg(Map<String, String> h, String text, {String? cid}) {
    return req('POST', '$url/rest/v1/chat_messages', h, {
      'chat_id': cid ?? chatId,
      'text': text,
    });
  }

  Future<Map<String, dynamic>?> readMsg(String id) async {
    final h = await req(
      'GET',
      '$url/rest/v1/chat_messages?id=eq.$id&select=id,chat_id,sender_id,text,created_at',
      BH,
    );
    return firstMap(h.body);
  }

  // =====================================================================
  // AI2 — prefix / encoding  (NOT FF/VT/Ogham/LS/PS)
  // =====================================================================
  const zwsp = '\u200b';
  const zwnj = '\u200c';
  const zwj = '\u200d';
  const wj = '\u2060';
  const rlo = '\u202e';
  const lri = '\u2066';
  const shy = '\u00ad';
  const mvs = '\u180e';
  const alm = '\u061c';
  final ghostJson =
      '{"kind":"bundle_proposal","total_eur":6543.21,"title":"$prefix"}';

  final prefixBattery = <String, String>{
    'zwsp_before_json': '$zwsp$ghostJson',
    'zwnj_before_json': '$zwnj$ghostJson',
    'zwj_before_json': '$zwj$ghostJson',
    'wj_before_json': '$wj$ghostJson',
    'rlo_before_json': '$rlo$ghostJson',
    'lri_before_json': '$lri$ghostJson',
    'shy_before_json': '$shy$ghostJson',
    'mvs_before_json': '$mvs$ghostJson',
    'alm_before_json': '$alm$ghostJson',
    'zwsp_before_prefix': '${zwsp}FLEABER_JSON_V1:$ghostJson',
    'wj_before_prefix': '${wj}FLEABER_JSON_V1:$ghostJson',
    'rlo_before_prefix': '${rlo}FLEABER_JSON_V1:$ghostJson',
    'lower_prefix': 'fleaber_json_v1:$ghostJson',
    'mixed_prefix': 'Fleaber_JSON_V1:$ghostJson',
    'shy_in_prefix': 'FLEABER${shy}_JSON_V1:$ghostJson',
    'double_colon_space': 'FLEABER_JSON_V1 :$ghostJson',
    'jsonc_comment': 'FLEABER_JSON_V1:/*x*/$ghostJson',
    'kind_dup_last_seguro': paidId == null
        ? ''
        : 'FLEABER_JSON_V1:{"kind":"chat_image","kind":"seguro_fleaber_paid","order_id":"$paidId","total":12.34,"path":"chat_uploads/$buyerId/$chatId/x.png"}',
  };

  for (final e in prefixBattery.entries) {
    if (e.value.isEmpty) continue;
    final h = await postMsg(BH, e.value);
    if (stored(h)) {
      final row = await readMsg(h.id!);
      final text = row?['text']?.toString() ?? '';
      noteOpen(
        id: 'AI2-${e.key}',
        lens: 'AI2',
        sev: text.contains('6543.21') || text.contains('seguro_fleaber_paid')
            ? 'P2'
            : 'P3',
        title: 'Prefix/encoding ${e.key} aceite (assert saltado ou JSON cru)',
        pre: 'strip_unicode_ws + like FLEABER_JSON_V1:%',
        repro: 'POST chat_messages text=<${e.key}>',
        evidence: {
          'http': h.http,
          'id': h.id,
          'stored_prefix': text.length > 40 ? text.substring(0, 40) : text,
          'len': text.length,
        },
        flutter:
            'Cliente só parseia startsWith(FLEABER_JSON_V1:). Variantes com ZWSP à frente não viram card, mas DELETE/PATCH podem aplicar-se; JSON cru pode aparecer como bolha.',
      );
    } else {
      noteBlocked(
        id: 'AI2-${e.key}',
        lens: 'AI2',
        title: 'prefix ${e.key} bloqueado',
        evidence: {'http': h.http, 'msg': msgOf(h)},
      );
    }
  }

  // DELETE of a ZWSP-prefixed stored message (if any)
  final zwspHit = findings.where((f) => f['id'] == 'AI2-zwsp_before_prefix');
  if (zwspHit.isNotEmpty) {
    final mid = (zwspHit.first['evidence'] as Map)['id']?.toString();
    if (mid != null) {
      final d = await req(
        'DELETE',
        '$url/rest/v1/chat_messages?id=eq.$mid',
        BH,
      );
      final still = await req(
        'GET',
        '$url/rest/v1/chat_messages?id=eq.$mid&select=id',
        BH,
      );
      final gone = still.http == 200 &&
          (still.body is List && (still.body as List).isEmpty);
      if (d.http < 300 && gone) {
        noteOpen(
          id: 'AI5-delete-zwsp-prefix',
          lens: 'AI5',
          sev: 'P2',
          title: 'DELETE removeu mensagem com ZWSP+FLEABER_JSON_V1 (imutabilidade só prefixo exacto)',
          pre: 'guard_delete like FLEABER_JSON_V1:% ou btrim {%',
          repro: 'POST text=U+200B+FLEABER_JSON_V1:{...} ; DELETE id',
          evidence: {'http': d.http, 'gone': gone, 'id': mid},
        );
      } else {
        noteBlocked(
          id: 'AI5-delete-zwsp-prefix',
          lens: 'AI5',
          title: 'DELETE ZWSP-prefix bloqueado ou linha ficou',
          evidence: {'http': d.http, 'gone': gone},
        );
      }
    }
  }

  // =====================================================================
  // AI1 — cards vs BD  (novos campos / kinds Flutter lê)
  // =====================================================================
  if (paidId != null) {
    // cancel rejected + lying display on PAID (não é outcome=updated, não é AF-P1-04)
    final cancelDisp = await postMsg(
      SH,
      fj({
        'kind': 'cancel_request_outcome',
        'order_id': paidId,
        'outcome': 'rejected',
        'display': 'Compra cancelada — Reembolso 4321 EUR processado na hora.',
        'v': 1,
      }),
    );
    if (stored(cancelDisp)) {
      noteOpen(
        id: 'AI1-cancel-rejected-display-lie',
        lens: 'AI1',
        sev: 'P2',
        title:
            'cancel_request_outcome rejected no pedido PAGO aceita display de reembolso falso',
        pre: 'assert não valida campo display; só outcome ∈ {accepted,rejected}',
        repro:
            'POST FLEABER_JSON_V1 kind=cancel_request_outcome outcome=rejected display="Reembolso 4321 EUR" order_id=<pago>',
        evidence: {'http': cancelDisp.http, 'id': cancelDisp.id, 'order': paidId},
        flutter:
            '_buildCancelOutcomeFromPayload usa payload.display verbatim.',
      );
    } else {
      noteBlocked(
        id: 'AI1-cancel-rejected-display-lie',
        lens: 'AI1',
        title: 'display mentiroso em cancel rejected bloqueado',
        evidence: {'http': cancelDisp.http, 'msg': msgOf(cancelDisp)},
      );
    }

    if (cancelledId != null) {
      final accDisp = await postMsg(
        SH,
        fj({
          'kind': 'cancel_request_outcome',
          'order_id': cancelledId,
          'outcome': 'accepted',
          'display': 'Reembolso 4321 EUR confirmado (PIX).',
          'v': 1,
        }),
      );
      if (stored(accDisp)) {
        noteOpen(
          id: 'AI1-cancel-accepted-display-lie',
          lens: 'AI1',
          sev: 'P2',
          title:
              'cancel accepted real + display mentirosa (4321 EUR) — SQL não cruza display',
          pre: 'outcome accepted exige cancelado/refund; display livre',
          repro:
              'POST cancel_request_outcome accepted display="Reembolso 4321 EUR" order_id=<cancelado>',
          evidence: {'http': accDisp.http, 'id': accDisp.id},
          flutter: '_buildCancelOutcomeFromPayload mostra display.',
        );
      } else {
        noteBlocked(
          id: 'AI1-cancel-accepted-display-lie',
          lens: 'AI1',
          title: 'display mentiroso em cancel accepted bloqueado',
          evidence: {'http': accDisp.http, 'msg': msgOf(accDisp)},
        );
      }
    }

    // seguro label sem dígitos ASCII
    final paidRow = await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$paidId&select=id,amount_paid_cents,status,price_total',
      SVC,
    );
    final paidMap = firstMap(paidRow.body);
    final cents = int.tryParse('${paidMap?['amount_paid_cents'] ?? 0}') ?? 0;
    final total = (cents / 100.0);
    final totalStr = total.toStringAsFixed(2);

    final labNoDigit = await postMsg(
      BH,
      fj({
        'kind': 'seguro_fleaber_paid',
        'order_id': paidId,
        'total': total,
        'label': 'PIX confirmado — pagamento recebido via MB WAY',
      }),
    );
    if (stored(labNoDigit)) {
      noteOpen(
        id: 'AI1-seguro-label-no-ascii-digits',
        lens: 'AI1',
        sev: 'P2',
        title:
            'seguro_fleaber_paid com total BD-ok e label PIX/MB WAY sem dígitos ASCII',
        pre: 'label mismatch só se v_label ~ \\d AND keywords',
        repro:
            'POST seguro_fleaber_paid total=<paid> label="PIX confirmado — pagamento recebido via MB WAY"',
        evidence: {
          'http': labNoDigit.http,
          'id': labNoDigit.id,
          'total': total,
          'cents': cents,
        },
        flutter:
            '_buildSeguroFleaberPaidCard concatena label na linha Seguro Fleaber.',
      );
    } else {
      noteBlocked(
        id: 'AI1-seguro-label-no-ascii-digits',
        lens: 'AI1',
        title: 'label PIX sem dígitos bloqueado',
        evidence: {'http': labNoDigit.http, 'msg': msgOf(labNoDigit)},
      );
    }

    final labFw = await postMsg(
      BH,
      fj({
        'kind': 'seguro_fleaber_paid',
        'order_id': paidId,
        'total': total,
        'label': 'PIX ４３２１ €',
      }),
    );
    if (stored(labFw)) {
      noteOpen(
        id: 'AI1-seguro-label-fullwidth-digits',
        lens: 'AI1',
        sev: 'P2',
        title: 'label PIX com dígitos fullwidth ４３２１ passa (\\d ASCII-only)',
        pre: 'v_label ~ \'\\d\' não casa U+FF10..FF19',
        repro: 'POST seguro_fleaber_paid label="PIX ４３２１ €" total=<paid>',
        evidence: {'http': labFw.http, 'id': labFw.id, 'total': totalStr},
        flutter: 'label entra no secondaryLine do card pago.',
      );
    } else {
      noteBlocked(
        id: 'AI1-seguro-label-fullwidth-digits',
        lens: 'AI1',
        title: 'label fullwidth bloqueado',
        evidence: {'http': labFw.http, 'msg': msgOf(labFw)},
      );
    }

    // review card extra author_role / comment without matching table extras
    final revIns = await req('POST', '$url/rest/v1/reviews', BH, {
      'target_id': sellerId,
      'buyer_id': buyerId,
      'stars': 5,
      'comment': '$prefix review',
      'target_type': 'seller',
      'author_role': 'comprador',
      'order_id': paidId,
    });
    if (stored(revIns) || revIns.http < 300) {
      final revCard = await postMsg(
        BH,
        fj({
          'kind': 'order_review_submitted',
          'order_id': paidId,
          'stars': 5,
          'author_role': 'comprador',
          'comment': '1 estrela — artigo falso',
        }),
      );
      if (stored(revCard)) {
        noteOpen(
          id: 'AI1-review-comment-unchecked',
          lens: 'AI1',
          sev: 'P3',
          title:
              'order_review_submitted aceita comment mentiroso (SQL só cruza stars)',
          pre: 'assert stars vs reviews; comment/author_role livres',
          repro:
              'POST order_review_submitted stars=<BD 5> comment="1 estrela — artigo falso"',
          evidence: {'http': revCard.http, 'id': revCard.id},
          flutter:
              '_buildOrderReviewSubmittedCard ignora comment; só stars. Risco baixo salvo inbox.',
        );
      } else {
        noteBlocked(
          id: 'AI1-review-comment-unchecked',
          lens: 'AI1',
          title: 'review comment extra bloqueado',
          evidence: {'http': revCard.http, 'msg': msgOf(revCard)},
        );
      }
    }

    // dispute fake reason if we can insert dispute
    final disp = await req('POST', '$url/rest/v1/order_disputes', BH, {
      'order_id': paidId,
      'buyer_id': buyerId,
      'reason': 'nao_recebido',
      'description': '$prefix',
      'status': 'aberta',
      'current_turn': 'vendedor',
    });
    if (stored(disp) || disp.http < 300) {
      final dcard = await postMsg(
        BH,
        fj({
          'kind': 'order_dispute_opened',
          'order_id': paidId,
          'reason': 'Vendedor confessou fraude 9999 EUR — saldo bloqueado',
        }),
      );
      if (stored(dcard)) {
        noteOpen(
          id: 'AI1-dispute-reason-unchecked',
          lens: 'AI1',
          sev: 'P2',
          title:
              'order_dispute_opened com disputa real aceita reason inventada no payload',
          pre: 'assert só exists(order_disputes); reason livre',
          repro:
              'POST order_dispute_opened reason="Vendedor confessou fraude 9999 EUR"',
          evidence: {'http': dcard.http, 'id': dcard.id},
          flutter:
              '_buildOrderDisputeOpenedCard usa payload.reason se order_id vazio; com order_id carrega thread BD. Campo ainda fica na mensagem.',
        );
      } else {
        noteBlocked(
          id: 'AI1-dispute-reason-unchecked',
          lens: 'AI1',
          title: 'dispute reason extra bloqueado',
          evidence: {'http': dcard.http, 'msg': msgOf(dcard)},
        );
      }
    } else {
      print('INFO dispute insert ${disp.http} ${msgOf(disp)}');
    }

    // reminder kinds Flutter renders but allowlist denies
    for (final kind in [
      'reservation_reminder',
      'reservation_payment_check_reminder',
      'reservation_shipping_reminder',
      'raffle_prize_awarded',
    ]) {
      final h = await postMsg(
        BH,
        fj({'kind': kind, 'order_id': paidId}),
      );
      if (stored(h)) {
        noteOpen(
          id: 'AI1-kind-$kind',
          lens: 'AI1',
          sev: 'P2',
          title: 'kind $kind (Flutter card) aceite sem cruzar tabela',
          pre: 'allowlist assert_json_card',
          repro: 'POST FLEABER_JSON_V1 kind=$kind',
          evidence: {'http': h.http, 'id': h.id},
        );
      } else {
        noteBlocked(
          id: 'AI1-kind-$kind',
          lens: 'AI1',
          title: 'kind $kind denied (Flutter ainda tenta injectar)',
          evidence: {'http': h.http, 'msg': msgOf(h)},
        );
      }
    }
  }

  if (reservedId != null) {
    final notesBattery = <String, String>{
      'reembolso_amount': 'Reembolso 4321 € já enviado',
      'aprovado_amount': 'Pagamento aprovado 4321 €',
      'euros_word': 'MB WAY 4321 euros',
      'transferencia_no_accent': 'Transferencia 4321 EUR',
      'fullwidth': 'MB WAY ４３２１ €',
      'mbway_no_amount': 'MB WAY confirmado pelo banco',
      'iban_lie': 'IBAN recebido 4321 EUR',
    };
    for (final e in notesBattery.entries) {
      final h = await postMsg(
        BH,
        fj({
          'kind': 'reservation_payment_submitted',
          'order_id': reservedId,
          'notes': e.value,
        }),
      );
      if (stored(h)) {
        noteOpen(
          id: 'AI1-notes-${e.key}',
          lens: 'AI1',
          sev: 'P2',
          title: 'notes de prova mentem (${e.key}) — payment_lie_text furou',
          pre: 'batata_chat_payment_lie_text em notes',
          repro:
              'POST reservation_payment_submitted notes="${e.value}" order_id=<reservado>',
          evidence: {'http': h.http, 'id': h.id, 'notes': e.value},
          flutter:
              '_buildReservationPaymentSubmittedCard mostra Observações + notes.',
        );
      } else {
        noteBlocked(
          id: 'AI1-notes-${e.key}',
          lens: 'AI1',
          title: 'notes ${e.key} bloqueado',
          evidence: {'http': h.http, 'msg': msgOf(h)},
        );
      }
    }

    // fake cancel_request on reserved (no cancel table)
    final cr = await postMsg(
      BH,
      fj({
        'kind': 'cancel_request',
        'order_id': reservedId,
        'reason': 'Quero reembolso 9999 EUR agora',
      }),
    );
    if (stored(cr)) {
      noteOpen(
        id: 'AI1-cancel-request-no-table',
        lens: 'AI1',
        sev: 'P3',
        title:
            'cancel_request mintável sem linha de cancelamento (só order_id + buyer)',
        pre: 'needs_order; sem tabela cancel_requests',
        repro: 'POST cancel_request order_id=<reservado>',
        evidence: {'http': cr.http, 'id': cr.id},
        flutter: 'Card de pedido de cancelamento + CTAs vendedor.',
      );
    } else {
      noteBlocked(
        id: 'AI1-cancel-request-no-table',
        lens: 'AI1',
        title: 'cancel_request sem tabela bloqueado',
        evidence: {'http': cr.http, 'msg': msgOf(cr)},
      );
    }
  }

  // bundle product_ids lie
  final bun = await req('POST', '$url/rest/v1/product_bundles', SH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'chat_id': chatId,
    'status': 'pending',
    'total_eur': 40.0,
    'product_ids': [productId],
  });
  final bundleId = bun.id;
  print('INFO bundle ${bun.http} id=$bundleId ${msgOf(bun)}');
  if (bundleId != null && decoyId != null) {
    final bcard = await postMsg(
      SH,
      fj({
        'kind': 'bundle_proposal',
        'bundle_id': bundleId,
        'total_eur': 40.0,
        'product_ids': [decoyId],
        'title': 'Conjunto 999 €',
      }),
    );
    if (stored(bcard)) {
      noteOpen(
        id: 'AI1-bundle-product-ids-lie',
        lens: 'AI1',
        sev: 'P2',
        title:
            'bundle_proposal total=BD mas product_ids de artigo 999 € decoy',
        pre: 'assert só bundle_id + total_eur',
        repro:
            'POST bundle_proposal bundle_id=<real> total_eur=<BD> product_ids=[decoy 999€]',
        evidence: {
          'http': bcard.http,
          'id': bcard.id,
          'bundle': bundleId,
          'decoy': decoyId,
        },
        flutter:
            'BundleProposalChatCard lista products a partir de payload.product_ids.',
      );
    } else {
      noteBlocked(
        id: 'AI1-bundle-product-ids-lie',
        lens: 'AI1',
        title: 'bundle product_ids lie bloqueado',
        evidence: {'http': bcard.http, 'msg': msgOf(bcard)},
      );
    }
  }

  // offer — outcome card amount from payload (must match BD); extra headline fields
  final offer = await req('POST', '$url/rest/v1/product_offers', BH, {
    'product_id': productId,
    'chat_id': chatId,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 12.0,
    'offered_by': 'buyer',
    'status': 'pending',
  });
  print('INFO offer ${offer.http} ${offer.id} ${msgOf(offer)}');
  if (offer.id != null) {
    final oc = await postMsg(
      BH,
      fj({
        'kind': 'price_offer',
        'order_id': paidId ?? pendingId,
        'offer_id': offer.id,
        'amount': 12.0,
        'offered_by': 'seller',
        'buyer_id': sellerId,
        'seller_id': buyerId,
      }),
    );
    if (stored(oc)) {
      noteOpen(
        id: 'AI1-price-offer-role-swap',
        lens: 'AI1',
        sev: 'P2',
        title:
            'price_offer amount=BD mas offered_by/buyer_id/seller_id trocados no payload',
        pre: 'assert amount+status; papéis do JSON livres',
        repro:
            'POST price_offer offer_id=<pending> amount=BD offered_by=seller buyer_id=<seller>',
        evidence: {'http': oc.http, 'id': oc.id, 'offer': offer.id},
        flutter:
            'PriceOfferChatCard usa payload.offered_by / buyer_id / seller_id para headline e CTAs (não só BD).',
      );
    } else {
      noteBlocked(
        id: 'AI1-price-offer-role-swap',
        lens: 'AI1',
        title: 'price_offer role swap bloqueado',
        evidence: {'http': oc.http, 'msg': msgOf(oc)},
      );
    }
  }

  if (mbwayId != null) {
    final det = await postMsg(
      SH,
      fj({
        'kind': 'order_direct_payment_details',
        'order_id': mbwayId,
        'amount_eur': 40.0,
        'mb_way': '969999999',
        'iban': 'PT50000000000000000000000',
      }),
    );
    if (stored(det)) {
      noteOpen(
        id: 'AI1-direct-pay-extra-fields',
        lens: 'AI1',
        sev: 'P3',
        title:
            'order_direct_payment_details aceita mb_way/iban no JSON (UI busca RPC, payload fica na BD)',
        pre: 'assert só amount_eur vs price_total',
        repro:
            'POST order_direct_payment_details amount_eur=<total> mb_way=969999999',
        evidence: {'http': det.http, 'id': det.id},
        flutter:
            'Card não pinta IBAN do payload; botão chama RPC. Campo na mensagem ainda injectável.',
      );
    } else {
      noteBlocked(
        id: 'AI1-direct-pay-extra-fields',
        lens: 'AI1',
        title: 'direct payment extra fields bloqueado',
        evidence: {'http': det.http, 'msg': msgOf(det)},
      );
    }
  }

  // =====================================================================
  // AI4 — URLs / provas
  // =====================================================================
  if (reservedId != null) {
    final urlBattery = <String, String>{
      'path_traversal':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/../public/x.png',
      'pct_2e2e':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/%2e%2e/%2e%2e/object/public/x.png',
      'sign_path':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/order_proofs/$buyerId/$reservedId/x.png',
      'public_prefix_trick':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/order_proofs/x?redirect=https:%2f%2fevil.test',
      'fragment_js':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/x.png#javascript:alert(1)',
      'backslash':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/..\\..\\public\\x.png',
      'other_user_path':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/order_proofs/$buyer2Id/$reservedId/stolen.png',
      'zwsp_in_host':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/$zwsp/x.png',
    };
    for (final e in urlBattery.entries) {
      final h = await postMsg(
        BH,
        fj({
          'kind': 'reservation_payment_submitted',
          'order_id': reservedId,
          'proof_url': e.value,
        }),
      );
      if (stored(h)) {
        noteOpen(
          id: 'AI4-proof-${e.key}',
          lens: 'AI4',
          sev: e.key == 'other_user_path' ||
                  e.key.contains('traversal') ||
                  e.key == 'pct_2e2e'
              ? 'P2'
              : 'P2',
          title: 'proof_url ${e.key} aceite no prefixo fleaber_private',
          pre: 'like …/object/fleaber_private/%',
          repro: 'POST reservation_payment_submitted proof_url=<${e.key}>',
          evidence: {'http': h.http, 'id': h.id, 'url': e.value},
          flutter:
              'BatataCachedNetworkImage(imageUrl: proofUrl) — URL crua, sem re-sign.',
        );
      } else {
        noteBlocked(
          id: 'AI4-proof-${e.key}',
          lens: 'AI4',
          title: 'proof_url ${e.key} bloqueado',
          evidence: {'http': h.http, 'msg': msgOf(h)},
        );
      }
    }

    // happy-path signed URL (regressão funcional)
    final upPath =
        'order_proofs/$buyerId/$reservedId/${DateTime.now().millisecondsSinceEpoch}_rtai.png';
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xde, 0x00, 0x00, 0x00,
      0x0c, 0x49, 0x44, 0x41, 0x54, 0x08, 0xd7, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
      0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xfe, 0xd4, 0xef, 0x00, 0x00,
      0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
    ]);
    final up = await req(
      'POST',
      '$url/storage/v1/object/fleaber_private/$upPath',
      {
        'apikey': anon,
        'Authorization': 'Bearer $buyerTok',
        'Content-Type': 'image/png',
        'x-upsert': 'true',
      },
      null,
      png,
    );
    print('INFO storage upload ${up.http} ${up.raw.length > 120 ? up.raw.substring(0, 120) : up.raw}');
    final signed = await req(
      'POST',
      '$url/storage/v1/object/sign/fleaber_private/$upPath',
      BH,
      {'expiresIn': 3600},
    );
    String? signedUrl;
    final sm = firstMap(signed.body);
    if (sm != null) {
      final s = sm['signedURL']?.toString() ?? sm['signedUrl']?.toString() ?? '';
      if (s.startsWith('http')) {
        signedUrl = s;
      } else if (s.isNotEmpty) {
        signedUrl = '$url$s';
      }
    }
    if (signedUrl != null) {
      final hp = await postMsg(
        BH,
        fj({
          'kind': 'reservation_payment_submitted',
          'order_id': reservedId,
          'proof_url': signedUrl,
        }),
      );
      if (stored(hp)) {
        noteBlocked(
          id: 'AI8-signed-proof-happy',
          lens: 'AI8',
          title: 'URL assinada (fluxo app) aceite — happy path OK',
          evidence: {'http': hp.http, 'id': hp.id},
        );
      } else {
        noteOpen(
          id: 'AI8-signed-proof-happy-blocked',
          lens: 'AI8',
          sev: 'P2',
          title:
              'URL assinada do upload real BLOQUEADA — like exige /object/fleaber_private/ não /object/sign/',
          pre: 'proof_url like …/object/fleaber_private/%',
          repro:
              'upload order_proofs → createSignedUrl → POST reservation_payment_submitted proof_url=<signed>',
          evidence: {
            'http': hp.http,
            'msg': msgOf(hp),
            'signed_prefix': signedUrl.substring(0, signedUrl.length.clamp(0, 90)),
          },
          flutter:
              'FleaberPrivateStorage.uploadOrderProof devolve signed URL; o cliente manda-a no card.',
        );
      }
    }
  }

  // chat_image url → public bucket
  final imgPub = await postMsg(
    BH,
    fj({
      'kind': 'chat_image',
      'path': 'chat_uploads/$buyerId/$chatId/ghost.png',
      'url':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/product-images/evil.png',
    }),
  );
  if (stored(imgPub)) {
    noteOpen(
      id: 'AI4-chat-image-public-url',
      lens: 'AI4',
      sev: 'P3',
      title:
          'chat_image aceita url de bucket public (path obrigatório; Flutter prefere path)',
      pre: 'chat_image url like supabase storage/%',
      repro:
          'POST chat_image path=chat_uploads/{uid}/{chat}/x url=…/object/public/…',
      evidence: {'http': imgPub.http, 'id': imgPub.id},
      flutter:
          '_chatImageUrlFromMessage devolve path se começa chat_uploads/; url pública fica de reserva.',
    );
  } else {
    noteBlocked(
      id: 'AI4-chat-image-public-url',
      lens: 'AI4',
      title: 'chat_image public url bloqueado',
      evidence: {'http': imgPub.http, 'msg': msgOf(imgPub)},
    );
  }

  // raw HTTP image (legado Flutter)
  final rawImg = await postMsg(BH, 'https://example.com/rtai-fake-proof.png');
  if (stored(rawImg)) {
    noteOpen(
      id: 'AI4-raw-http-image-ext',
      lens: 'AI4',
      sev: 'P2',
      title:
          'Mensagem HTTP crua .png aceite — Flutter trata como imagem de prova',
      pre: 'assert_json_card early-return se não FLEABER_JSON_V1 e não {',
      repro: 'POST chat_messages text=https://example.com/rtai-fake-proof.png',
      evidence: {'http': rawImg.http, 'id': rawImg.id},
      flutter:
          '_chatImageUrlFromMessage: http + extensão imagem → bolha de imagem.',
    );
  } else {
    noteBlocked(
      id: 'AI4-raw-http-image-ext',
      lens: 'AI4',
      title: 'raw http image bloqueado',
      evidence: {'http': rawImg.http, 'msg': msgOf(rawImg)},
    );
  }

  final rawProofPath = await postMsg(
    BH,
    'https://evil.test/cdn/order_proofs/stolen.jpg',
  );
  if (stored(rawProofPath)) {
    noteOpen(
      id: 'AI4-raw-http-order-proofs-path',
      lens: 'AI4',
      sev: 'P2',
      title:
          'URL crua com "order_proofs" no path aceite (parser legado Flutter)',
      pre: 'texto http sem prefixo JSON',
      repro: 'POST text=https://evil.test/cdn/order_proofs/stolen.jpg',
      evidence: {'http': rawProofPath.http, 'id': rawProofPath.id},
      flutter: 'path.contains(order_proofs) ⇒ trata como imagem.',
    );
  } else {
    noteBlocked(
      id: 'AI4-raw-http-order-proofs-path',
      lens: 'AI4',
      title: 'raw order_proofs url bloqueado',
      evidence: {'http': rawProofPath.http, 'msg': msgOf(rawProofPath)},
    );
  }

  // =====================================================================
  // AI3 / AI5 — inbox + cronologia
  // =====================================================================
  final inboxBattery = <String, String>{
    'reembolso': 'Reembolso 4321 €',
    'euros_word': 'MB WAY 50 euros',
    'transferencia': 'Transferencia 50€',
    'paypal': 'PayPal 50€',
    'bizum': 'Bizum 50€',
    'fullwidth_pix': 'ＰＩＸ 50€',
    'confirmado_fw': 'confirmado ４３２１ €',
    'recebi': 'Recebi 50€',
  };
  for (final e in inboxBattery.entries) {
    final h = await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
      'last_message': e.value,
      'last_message_time': DateTime.now().toUtc().toIso8601String(),
    });
    if (h.http < 300) {
      noteOpen(
        id: 'AI5-inbox-${e.key}',
        lens: 'AI5',
        sev: 'P2',
        title: 'Inbox last_message="${e.value}" aceite (regex furou)',
        pre: 'batata_chat_is_forged_inbox_preview = payment_lie_text',
        repro: 'PATCH chats last_message="${e.value}"',
        evidence: {'http': h.http, 'preview': e.value},
      );
    } else {
      noteBlocked(
        id: 'AI5-inbox-${e.key}',
        lens: 'AI5',
        title: 'inbox ${e.key} bloqueado',
        evidence: {'http': h.http, 'msg': msgOf(h)},
      );
    }
  }

  final past29 = DateTime.now()
      .toUtc()
      .subtract(const Duration(seconds: 29))
      .toIso8601String();
  final past31 = DateTime.now()
      .toUtc()
      .subtract(const Duration(seconds: 31))
      .toIso8601String();
  final year2020 = '2020-01-01T00:00:00Z';

  final t29 = await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
    'last_message_time': past29,
  });
  final t31 = await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
    'last_message_time': past31,
  });
  final t2020 = await req('PATCH', '$url/rest/v1/chats?id=eq.$chatId', BH, {
    'last_message_time': year2020,
  });
  final chatAfter = await req(
    'GET',
    '$url/rest/v1/chats?id=eq.$chatId&select=id,last_message,last_message_time',
    BH,
  );
  final ca = firstMap(chatAfter.body);
  print('INFO time 29http=${t29.http} 31http=${t31.http} 2020http=${t2020.http} stored=${ca?['last_message_time']}');

  if (t2020.http < 300) {
    final storedT = DateTime.tryParse('${ca?['last_message_time'] ?? ''}');
    final clamped = storedT != null &&
        storedT.isAfter(DateTime.now().toUtc().subtract(const Duration(minutes: 2)));
    if (!clamped) {
      noteOpen(
        id: 'AI3-inbox-time-2020',
        lens: 'AI3',
        sev: 'P2',
        title: 'last_message_time=2020 persistiu (clamp 30s falhou)',
        pre: 'chats_guard_update clamp 30s / +5min',
        repro: 'PATCH chats last_message_time=2020-01-01',
        evidence: {'stored': ca?['last_message_time']},
      );
    } else {
      noteBlocked(
        id: 'AI3-inbox-time-2020',
        lens: 'AI3',
        title: 'last_message_time 2020 clamped a now()',
        evidence: {'stored': ca?['last_message_time']},
      );
    }
  }

  final backdateMsg = await req('POST', '$url/rest/v1/chat_messages', BH, {
    'chat_id': chatId,
    'text': '$prefix backdate',
    'created_at': year2020,
  });
  if (stored(backdateMsg)) {
    final row = await readMsg(backdateMsg.id!);
    final ca2 = row?['created_at']?.toString() ?? '';
    if (ca2.startsWith('2020')) {
      noteOpen(
        id: 'AI3-msg-created-at-2020',
        lens: 'AI3',
        sev: 'P2',
        title: 'INSERT chat_messages created_at=2020 persistiu',
        pre: 'guard_insert NEW.created_at := now()',
        repro: 'POST chat_messages created_at=2020-01-01',
        evidence: {'id': backdateMsg.id, 'created_at': ca2},
      );
    } else {
      noteBlocked(
        id: 'AI3-msg-created-at-2020',
        lens: 'AI3',
        title: 'created_at INSERT forçado a now()',
        evidence: {'created_at': ca2},
      );
    }
  }

  // PATCH created_at on own plain message
  if (stored(backdateMsg)) {
    final p = await req(
      'PATCH',
      '$url/rest/v1/chat_messages?id=eq.${backdateMsg.id}',
      BH,
      {'created_at': year2020},
    );
    final row = await readMsg(backdateMsg.id!);
    final ca2 = row?['created_at']?.toString() ?? '';
    if (p.http < 300 && ca2.startsWith('2020')) {
      noteOpen(
        id: 'AI3-patch-created-at',
        lens: 'AI3',
        sev: 'P2',
        title: 'PATCH created_at=2020 em mensagem própria',
        pre: 'guard_update NEW.created_at := OLD.created_at',
        repro: 'PATCH chat_messages created_at=2020',
        evidence: {'http': p.http, 'created_at': ca2},
      );
    } else {
      noteBlocked(
        id: 'AI3-patch-created-at',
        lens: 'AI3',
        title: 'PATCH created_at imutável',
        evidence: {'http': p.http, 'created_at': ca2},
      );
    }
  }

  // =====================================================================
  // AI6 storage upsert / AI7 cross-user
  // =====================================================================
  if (buyer2Id.isNotEmpty) {
    final b2chat = await req('POST', '$url/rest/v1/chat_messages', B2H, {
      'chat_id': chatId,
      'text': '$prefix b2 inject',
    });
    if (stored(b2chat)) {
      noteOpen(
        id: 'AI7-b2-write-thread',
        lens: 'AI7',
        sev: 'P1',
        title: 'buyer2 escreveu na thread B–S alheia',
        pre: 'RLS chat_messages insert participant',
        repro: 'POST chat_messages chat_id=<B-S> jwt=B2',
        evidence: {'http': b2chat.http, 'id': b2chat.id},
      );
    } else {
      noteBlocked(
        id: 'AI7-b2-write-thread',
        lens: 'AI7',
        title: 'B2 write thread alheia bloqueado',
        evidence: {'http': b2chat.http, 'msg': msgOf(b2chat)},
      );
    }

    final b2read = await req(
      'GET',
      '$url/rest/v1/chat_messages?chat_id=eq.$chatId&select=id,text&limit=3',
      B2H,
    );
    final n = b2read.body is List ? (b2read.body as List).length : -1;
    if (b2read.http < 300 && n > 0) {
      noteOpen(
        id: 'AI7-b2-read-thread',
        lens: 'AI7',
        sev: 'P1',
        title: 'buyer2 leu mensagens da thread B–S',
        pre: 'RLS select participant',
        repro: 'GET chat_messages?chat_id=eq.<B-S> jwt=B2',
        evidence: {'http': b2read.http, 'n': n},
      );
    } else {
      noteBlocked(
        id: 'AI7-b2-read-thread',
        lens: 'AI7',
        title: 'B2 read thread alheia vazio/negado',
        evidence: {'http': b2read.http, 'n': n, 'msg': msgOf(b2read)},
      );
    }

    // overwrite storage of buyer path as B2
    if (reservedId != null) {
      final stealPath =
          'order_proofs/$buyerId/$reservedId/rtai_overwrite.png';
      final up2 = await req(
        'POST',
        '$url/storage/v1/object/fleaber_private/$stealPath',
        {
          'apikey': anon,
          'Authorization': 'Bearer $b2tok',
          'Content-Type': 'image/png',
          'x-upsert': 'true',
        },
        null,
        Uint8List.fromList([0x00, 0x01, 0x02]),
      );
      if (up2.http < 300) {
        noteOpen(
          id: 'AI6-b2-upsert-buyer-proof',
          lens: 'AI6',
          sev: 'P1',
          title: 'B2 fez upsert no path order_proofs/{buyer}/{order}/…',
          pre: 'storage insert/update own path',
          repro:
              'POST storage fleaber_private/order_proofs/{buyerId}/{orderId}/x x-upsert jwt=B2',
          evidence: {'http': up2.http, 'raw': up2.raw.length > 160 ? up2.raw.substring(0, 160) : up2.raw},
        );
      } else {
        noteBlocked(
          id: 'AI6-b2-upsert-buyer-proof',
          lens: 'AI6',
          title: 'B2 upsert path do buyer bloqueado',
          evidence: {'http': up2.http, 'msg': msgOf(up2)},
        );
      }
    }
  }

  // =====================================================================
  // AI8 — kinds server-only / edge
  // =====================================================================
  if (paidId != null) {
    final so = await postMsg(
      BH,
      fj({
        'kind': 'marketplace_bag_paid',
        'order_id': paidId,
        'total': 12.34,
      }),
    );
    if (stored(so)) {
      noteOpen(
        id: 'AI8-server-only-bag-paid',
        lens: 'AI8',
        sev: 'P1',
        title: 'kind marketplace_bag_paid mintável por JWT buyer',
        pre: 'chat_system_card_server_only',
        repro: 'POST marketplace_bag_paid jwt=buyer',
        evidence: {'http': so.http, 'id': so.id},
      );
    } else {
      noteBlocked(
        id: 'AI8-server-only-bag-paid',
        lens: 'AI8',
        title: 'marketplace_bag_paid server-only OK',
        evidence: {'http': so.http, 'msg': msgOf(so)},
      );
    }
  }

  // PATCH FLEABER card text (immutability)
  final fleaberIds = findings
      .where((f) => f['open'] == true && (f['evidence'] as Map)['id'] != null)
      .map((f) => (f['evidence'] as Map)['id']?.toString())
      .whereType<String>()
      .toList();
  if (fleaberIds.isNotEmpty) {
    final target = fleaberIds.first;
    final row = await readMsg(target);
    final txt = row?['text']?.toString() ?? '';
    if (txt.startsWith('FLEABER_JSON_V1:')) {
      final p = await req(
        'PATCH',
        '$url/rest/v1/chat_messages?id=eq.$target',
        BH,
        {'text': '$txt "mutated"'},
      );
      if (p.http < 300) {
        noteOpen(
          id: 'AI5-patch-fleaber-card',
          lens: 'AI5',
          sev: 'P1',
          title: 'PATCH alterou card FLEABER_JSON_V1',
          pre: 'guard_update immutable prefix',
          repro: 'PATCH chat_messages text=… jwt=sender',
          evidence: {'http': p.http, 'id': target},
        );
      } else {
        noteBlocked(
          id: 'AI5-patch-fleaber-card',
          lens: 'AI5',
          title: 'PATCH FLEABER_JSON_V1 bloqueado',
          evidence: {'http': p.http, 'msg': msgOf(p)},
        );
      }
      final d = await req(
        'DELETE',
        '$url/rest/v1/chat_messages?id=eq.$target',
        BH,
      );
      if (d.http < 300) {
        noteOpen(
          id: 'AI5-delete-fleaber-card',
          lens: 'AI5',
          sev: 'P1',
          title: 'DELETE removeu card FLEABER_JSON_V1',
          pre: 'guard_delete',
          repro: 'DELETE chat_messages id=<FLEABER card>',
          evidence: {'http': d.http, 'id': target},
        );
      } else {
        noteBlocked(
          id: 'AI5-delete-fleaber-card',
          lens: 'AI5',
          title: 'DELETE FLEABER_JSON_V1 bloqueado',
          evidence: {'http': d.http, 'msg': msgOf(d)},
        );
      }
    }
  }

  final out = {
    'auditor': 'REDTEAM_BLIND_AI_CHAT_POS_AEAFAG_v1',
    'prefix': prefix,
    'chat_id': chatId,
    'paid_id': paidId,
    'reserved_id': reservedId,
    'buyer2': buyer2Id,
    'open': findings,
    'blocked': blocked,
    'open_count': findings.length,
    'blocked_count': blocked.length,
  };
  final dir = Directory('tool/redteam_blind_ai_20260902T0728');
  await dir.create(recursive: true);
  final f = File('tool/redteam_blind_ai_20260902T0728/findings.json');
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('WROTE ${f.path} open=${findings.length} blocked=${blocked.length}');
}
