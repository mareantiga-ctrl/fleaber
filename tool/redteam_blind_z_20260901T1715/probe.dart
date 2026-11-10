// ignore_for_file: avoid_print
/// REDTEAM BLIND Z — chat / provas / UI pós-fecho W+VWX
/// dart run tool/redteam_blind_z_20260901T1715/probe.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

const prefix = 'RTZ-20260901T1715-';

late String url;
late String anon;
late String svc;
late Map<String, String> BH, SH, B2H, SVC, ANON, E2E;

final findings = <Map<String, dynamic>>[];
final closed = <Map<String, dynamic>>[];
final notes = <String>[];

void finding({
  required String id,
  required String sev,
  required String lens,
  required String actor,
  required String title,
  required String repro,
  required String expected,
  required Object? obtained,
  String? impact,
}) {
  final m = {
    'id': id,
    'sev': sev,
    'lens': lens,
    'actor': actor,
    'title': title,
    'repro': repro,
    'expected': expected,
    'obtained': obtained,
    if (impact != null) 'impact': impact,
  };
  findings.add(m);
  print('FINDING $sev $id · $title');
}

void close(String id, String msg, [Object? extra]) {
  closed.add({'id': id, 'msg': msg, 'extra': extra});
  print('CLOSED $id · $msg');
}

void note(String s) {
  notes.add(s);
  print('NOTE $s');
}

Future<Map<String, dynamic>> req(
  String method,
  String path, {
  Map<String, String>? h,
  Object? body,
  Map<String, String>? extraHeaders,
}) async {
  final headers = Map<String, String>.from(h ?? SVC);
  if (extraHeaders != null) headers.addAll(extraHeaders);
  final u = path.startsWith('http') ? path : '$url$path';
  final http.Response r;
  final encoded = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'POST':
      r = await http.post(Uri.parse(u), headers: headers, body: encoded);
      break;
    case 'PATCH':
      r = await http.patch(Uri.parse(u), headers: headers, body: encoded);
      break;
    case 'DELETE':
      r = await http.delete(Uri.parse(u), headers: headers);
      break;
    case 'PUT':
      r = await http.put(Uri.parse(u), headers: headers, body: encoded);
      break;
    default:
      r = await http.get(Uri.parse(u), headers: headers);
  }
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'raw': r.body, 'headers': r.headers};
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

String jsonCard(String kind, [Map<String, dynamic>? extra]) {
  return 'FLEABER_JSON_V1:${jsonEncode({'kind': kind, ...?extra})}';
}

Future<Map<String, dynamic>> postMsg(
  Map<String, String> h,
  String chatId,
  String text, {
  String? senderId,
  bool? isReservation,
  String? createdAt,
  int? id,
}) {
  return req('POST', '/rest/v1/chat_messages', h: h, body: {
    'chat_id': chatId,
    if (senderId != null) 'sender_id': senderId,
    'text': text,
    if (isReservation != null) 'is_reservation': isReservation,
    if (createdAt != null) 'created_at': createdAt,
    if (id != null) 'id': id,
  });
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT not staging');
    exit(2);
  }
  anon = envRequire(e, 'SUPABASE_ANON_KEY');
  svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final crashSecret = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);

  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  String? b2Tok;
  String? b2Id;
  try {
    b2Tok = await sb.signIn(
      email: 'demo_bot_01@staging.fleaber.bot',
      password: 'FleaberBotSim_Staging_2026!',
    );
    b2Id = await sb.userIdForAccessToken(b2Tok);
  } catch (err) {
    note('demo_bot_01 login fail: $err — creating admin user');
    final email = '${prefix.toLowerCase()}b2@staging.fleaber.bot';
    b2Id = await sb.createAdminUser(
      email: email,
      password: 'RTZ-Blind-Z-2026!',
      userMetadata: {'full_name': '${prefix}b2'},
    );
    await req('POST', '/rest/v1/profiles', h: {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation,resolution=merge-duplicates',
    }, body: {
      'id': b2Id,
      'full_name': '${prefix}b2',
    });
    b2Tok = await sb.signIn(email: email, password: 'RTZ-Blind-Z-2026!');
  }

  Map<String, String> h(String tok) => {
        'apikey': anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  BH = h(buyerTok);
  SH = h(sellerTok);
  B2H = h(b2Tok!);
  SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  ANON = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  E2E = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    if (crashSecret.length >= 16) 'x-fleaber-e2e-secret': crashSecret,
  };

  note('buyer=$buyerId seller=$sellerId b2=$b2Id');

  // ---- fixture: Stripe TEST captured order ----
  final paid = await req(
    'POST',
    '/functions/v1/sec-fase2-e2e-oversell',
    h: E2E,
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'probe': 'setup_paid_order',
      'initial_qty': 1,
      'shipping_method': 'mao',
    },
  );
  var oid = '';
  if (paid['body'] is Map) {
    final m = Map<String, dynamic>.from(paid['body'] as Map);
    oid = '${m['order_id'] ?? m['id'] ?? ''}'.trim();
  }
  if (oid.isEmpty) oid = idOf(paid['body']) ?? '';
  if (oid.isEmpty) {
    stderr.writeln('ABORT no paid order ${paid['http']} ${paid['raw']}');
    exit(3);
  }
  final orow = firstMap((await req(
    'GET',
    '/rest/v1/orders?id=eq.$oid&select=id,status,amount_paid_cents,price_total,stripe_payment_intent_id,stripe_refund_id,buyer_id,seller_id,proof_url,product_id,payment_method,shipping_method',
  ))['body']);
  note('paid order=$oid status=${orow?['status']} paid_cents=${orow?['amount_paid_cents']} pi=${orow?['stripe_payment_intent_id']}');

  // dedicated fixture chat (do not delete production-like threads)
  final chatIns = await req('POST', '/rest/v1/chats', h: SVC, body: {
    'user_a': buyerId,
    'user_b': sellerId,
    'last_message': '${prefix}seed',
  });
  final chatId = idOf(chatIns['body']);
  if (chatId == null) {
    stderr.writeln('ABORT no chat ${chatIns['raw']}');
    exit(3);
  }
  note('fixture chat=$chatId');

  // unpaid reservation order (fixture) for operational cards that need order_id
  final prodId = '${orow?['product_id'] ?? ''}'.trim();
  final unpaidIns = await req('POST', '/rest/v1/orders', h: SVC, body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'status': 'reservado',
    'payment_method': 'pagamento direto',
    'shipping_method': 'mao',
    'price_total': 12.34,
    if (prodId.isNotEmpty) 'product_id': prodId,
    'is_reservation': true,
  });
  final unpaidId = idOf(unpaidIns['body']);
  note('unpaid reservation=${unpaidId ?? unpaidIns['http']} ${unpaidId == null ? unpaidIns['raw'] : ''}');

  // server receipt fixture (service_role)
  final paidCents = (orow?['amount_paid_cents'] as num?)?.toInt() ?? 0;
  final totalStr = (paidCents / 100.0).toStringAsFixed(2);
  final svcReceipt = await postMsg(
    SVC,
    chatId,
    jsonCard('seguro_fleaber_paid', {
      'order_id': oid,
      'total': totalStr,
      'label': '${prefix}svc-receipt',
    }),
    senderId: buyerId,
  );
  final svcReceiptId = idOf(svcReceipt['body']);
  note('svc receipt msg=$svcReceiptId http=${svcReceipt['http']}');

  // ============================================================
  // Z2 — immutability variants (NOT exact DELETE JSON / created_at 2020)
  // ============================================================

  // Z2.1 DELETE chats CASCADE vs JSON receipt
  final cascadeChat = await req('POST', '/rest/v1/chats', h: SVC, body: {
    'user_a': buyerId,
    'user_b': sellerId,
    'last_message': '${prefix}cascade',
  });
  final cascadeChatId = idOf(cascadeChat['body']);
  String? cascadeMsgId;
  if (cascadeChatId != null) {
    final m = await postMsg(
      SVC,
      cascadeChatId,
      jsonCard('seguro_fleaber_paid', {
        'order_id': oid,
        'total': totalStr,
        'label': '${prefix}cascade-receipt',
      }),
      senderId: buyerId,
    );
    cascadeMsgId = idOf(m['body']);
    final delChat = await req(
      'DELETE',
      '/rest/v1/chats?id=eq.$cascadeChatId',
      h: BH,
    );
    final stillMsg = cascadeMsgId == null
        ? null
        : await req('GET', '/rest/v1/chat_messages?id=eq.$cascadeMsgId');
    final stillChat = await req('GET', '/rest/v1/chats?id=eq.$cascadeChatId');
    final msgGone = stillMsg != null &&
        stillMsg['body'] is List &&
        (stillMsg['body'] as List).isEmpty;
    final chatGone = stillChat['body'] is List &&
        (stillChat['body'] as List).isEmpty;
    if (delChat['http'] == 200 || delChat['http'] == 204) {
      if (msgGone) {
        finding(
          id: 'Z2-CASCADE-DELETE-CHAT-JSON',
          sev: 'P0',
          lens: 'Z2',
          actor: 'buyer JWT',
          title:
              'DELETE chats apaga recibo JSON (CASCADE) — DELETE em chat_messages está bloqueado',
          repro:
              'POST chats + service_role INSERT FLEABER_JSON_V1 seguro_fleaber_paid; DELETE chats?id=eq.X (buyer)',
          expected:
              'chat e/ou recibo JSON imutáveis (mesmo contrato que DELETE chat_messages)',
          obtained: {
            'del_chat_http': delChat['http'],
            'chat_gone': chatGone,
            'msg_id': cascadeMsgId,
            'msg_gone': msgGone,
          },
          impact: 'Apagar prova de pagamento no servidor sem passar no trigger de DELETE da mensagem.',
        );
      } else if (chatGone && !msgGone) {
        finding(
          id: 'Z2-DELETE-CHAT-ORPHAN-MSG',
          sev: 'P2',
          lens: 'Z2',
          actor: 'buyer JWT',
          title: 'DELETE chats remove a thread; recibo JSON fica órfão',
          repro: 'DELETE chats?id=eq.X (buyer) após INSERT JSON',
          expected: 'recusar DELETE de chat com cards de sistema, ou cascata consistente',
          obtained: {
            'del_http': delChat['http'],
            'msg_id': cascadeMsgId,
            'msg_gone': msgGone,
          },
        );
      } else {
        close('Z2.cascade', 'DELETE chat recusado ou recibo sobrevive', {
          'del': delChat['http'],
          'chat_gone': chatGone,
          'msg_gone': msgGone,
        });
      }
    } else {
      close('Z2.cascade', 'DELETE chats recusado ${delChat['http']} ${delChat['raw']}');
    }
  }

  // Z2.2 PATCH JSON via other columns / UPSERT
  if (svcReceiptId != null) {
    final upsert = await req('POST', '/rest/v1/chat_messages', h: BH, extraHeaders: {
      'Prefer': 'resolution=merge-duplicates,return=representation',
    }, body: {
      'id': int.tryParse(svcReceiptId) ?? svcReceiptId,
      'text': jsonCard('seguro_fleaber_paid', {
        'order_id': oid,
        'total': totalStr,
        'label': 'MUTATED-UPSERT',
      }),
      'chat_id': chatId,
      'sender_id': buyerId,
    });
    final afterUp = firstMap((await req(
      'GET',
      '/rest/v1/chat_messages?id=eq.$svcReceiptId&select=id,text',
    ))['body']);
    final txt = afterUp?['text']?.toString() ?? '';
    if (txt.contains('MUTATED-UPSERT')) {
      finding(
        id: 'Z2-UPSERT-JSON-MUTATE',
        sev: 'P0',
        lens: 'Z2',
        actor: 'buyer JWT',
        title: 'UPSERT PostgREST altera card JSON imutável',
        repro: 'POST chat_messages Prefer:resolution=merge-duplicates id=recibo',
        expected: 'chat_system_card_immutable',
        obtained: {'http': upsert['http'], 'text': txt},
      );
    } else {
      close('Z2.upsert', 'UPSERT não mutou JSON ${upsert['http']}');
    }

    final patchRes = await req(
      'PATCH',
      '/rest/v1/chat_messages?id=eq.$svcReceiptId',
      h: BH,
      body: {'is_reservation': true, 'is_read': false},
    );
    note('Z2.patch_flags_own_or_svc json http=${patchRes['http']} ${patchRes['raw']}');

    // bulk delete by chat_id (JSON rows)
    final bulk = await req(
      'DELETE',
      '/rest/v1/chat_messages?chat_id=eq.$chatId&text=like.*FLEABER_JSON_V1*',
      h: BH,
    );
    final still = firstMap((await req(
      'GET',
      '/rest/v1/chat_messages?id=eq.$svcReceiptId&select=id,text',
    ))['body']);
    if (still == null) {
      finding(
        id: 'Z2-BULK-DELETE-JSON-FILTER',
        sev: 'P0',
        lens: 'Z2',
        actor: 'buyer JWT',
        title: 'DELETE filtrado por chat_id apaga JSON',
        repro: 'DELETE chat_messages?chat_id=eq.X&text=like.*FLEABER_JSON_V1*',
        expected: 'chat_system_card_immutable',
        obtained: {'http': bulk['http'], 'still': still},
      );
    } else {
      close('Z2.bulk_del', 'bulk DELETE JSON bloqueado ${bulk['http']}');
    }
  }

  // Z2.3 mutate own plain then... prefix upgrade; DELETE own JSON we inserted
  final buyerPlain = await postMsg(BH, chatId, '${prefix}hello-plain');
  final plainId = idOf(buyerPlain['body']);
  if (plainId != null) {
    final toJson = await req(
      'PATCH',
      '/rest/v1/chat_messages?id=eq.$plainId',
      h: BH,
      body: {
        'text': jsonCard('order_dispute_opened', {'order_id': oid}),
      },
    );
    note('Z2.plain_to_json http=${toJson['http']}');
    if ((toJson['http'] as int) < 300) {
      final del = await req(
        'DELETE',
        '/rest/v1/chat_messages?id=eq.$plainId',
        h: BH,
      );
      final still = await req('GET', '/rest/v1/chat_messages?id=eq.$plainId');
      final gone = still['body'] is List && (still['body'] as List).isEmpty;
      if (gone) {
        finding(
          id: 'Z2-UPGRADE-THEN-DELETE',
          sev: 'P1',
          lens: 'Z2',
          actor: 'buyer JWT',
          title: 'PATCH plain→JSON e DELETE do card (se DELETE passar)',
          repro: 'PATCH text=FLEABER_JSON_V1; DELETE',
          expected: 'upgrade validado; DELETE JSON recusado',
          obtained: {'patch': toJson['http'], 'del': del['http'], 'gone': gone},
        );
      } else {
        close('Z2.upgrade_del', 'upgrade ok, DELETE JSON bloqueado ${del['http']}');
      }
    }
    // leftover plain delete (hygiene of fixture)
    await req('DELETE', '/rest/v1/chat_messages?id=eq.$plainId', h: BH);
  }

  // Z2.4 GraphQL
  final gql = await req('POST', '/graphql/v1', h: BH, body: {
    'query':
        'mutation { deleteFromchat_messagesCollection(filter: { id: { eq: ${svcReceiptId ?? 0} } }) { records { id } } }',
  });
  note('Z2.graphql http=${gql['http']} ${gql['raw'].toString().substring(0, gql['raw'].toString().length.clamp(0, 400))}');

  // ============================================================
  // Z1 — other kinds / fields lying about value
  // ============================================================

  if (unpaidId != null) {
    final directLie = await postMsg(
      SH,
      chatId,
      jsonCard('order_direct_payment_details', {
        'order_id': unpaidId,
        'amount_eur': 1.00,
        'mb_way': '910000000',
        'iban': 'PT50000000000000000000000',
      }),
    );
    final stored = firstMap(directLie['body']);
    if ((directLie['http'] as int) < 300) {
      finding(
        id: 'Z1-DIRECT-PAY-AMOUNT-LIE',
        sev: 'P1',
        lens: 'Z1',
        actor: 'seller JWT',
        title:
            'Card order_direct_payment_details aceita amount_eur=1.00 sem cruzar preço da encomenda (12.34)',
        repro:
            'POST chat_messages FLEABER_JSON_V1 kind=order_direct_payment_details amount_eur=1 order reservado 12.34',
        expected: 'total alinhado à BD (mesmo contrato que seguro_fleaber_paid)',
        obtained: {
          'http': directLie['http'],
          'msg_id': idOf(directLie['body']),
          'text': stored?['text'],
        },
        impact:
            'UI Flutter mostra «Valor a transferir» a partir do JSON (não da BD). Comprador pode transferir o valor mentido.',
      );
    } else {
      close('Z1.direct_amount', 'direct payment amount rejected ${directLie['http']} ${directLie['raw']}');
    }
  }

  final offerOut = await postMsg(
    SH,
    chatId,
    jsonCard('price_offer_outcome', {
      'order_id': oid,
      'outcome': 'accepted',
      'amount': 0.01,
      'offer_id': '00000000-0000-0000-0000-000000000001',
    }),
  );
  if ((offerOut['http'] as int) < 300) {
    finding(
      id: 'Z1-PRICE-OFFER-OUTCOME-FAKE',
      sev: 'P1',
      lens: 'Z1',
      actor: 'seller JWT',
      title:
          'price_offer_outcome accepted amount=0.01 sem oferta na BD — Flutter pinta «Proposta aceite — 0,01 €»',
      repro:
          'POST kind=price_offer_outcome outcome=accepted amount=0.01 offer_id fantasma',
      expected: 'exigir product_offers.status=accepted e amount da BD',
      obtained: {'http': offerOut['http'], 'id': idOf(offerOut['body'])},
    );
  } else {
    close('Z1.offer_outcome', 'blocked ${offerOut['http']} ${offerOut['raw']}');
  }

  // bundle_proposal WITHOUT FLEABER prefix (Flutter parses raw `{`)
  final rawBundle = jsonEncode({
    'kind': 'bundle_proposal',
    'total_eur': 8888,
    'discount_eur': 0,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'request_mode': 'discount',
    'product_ids': ['00000000-0000-0000-0000-000000000002'],
  });
  final rawIns = await postMsg(BH, chatId, rawBundle);
  if ((rawIns['http'] as int) < 300) {
    finding(
      id: 'Z1-BUNDLE-RAW-JSON-NO-PREFIX',
      sev: 'P1',
      lens: 'Z1',
      actor: 'buyer JWT',
      title:
          'Mensagem `{kind:bundle_proposal,total_eur:8888}` sem prefixo FLEABER_JSON_V1 — trigger não valida; Flutter parseia e mostra o total',
      repro:
          'POST chat_messages text={"kind":"bundle_proposal","total_eur":8888,...} (sem FLEABER_JSON_V1)',
      expected:
          'ou recusar kind operacional em JSON cru, ou o Flutter só pintar FLEABER_JSON_V1',
      obtained: {'http': rawIns['http'], 'id': idOf(rawIns['body'])},
      impact:
          'tryParseBundleProposalChatPayload aceita text.trim().startsWith("{"). Card usa payload.total_eur se não houver bundle_id.',
    );
  } else {
    close('Z1.raw_bundle', 'raw JSON blocked ${rawIns['http']} ${rawIns['raw']}');
  }

  // bundle_proposal FLEABER without bundle_id (gap: total only checked if bundle_id set)
  final ghostBundle = await postMsg(
    BH,
    chatId,
    jsonCard('bundle_proposal', {
      'total_eur': 6543.21,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'request_mode': 'discount',
    }),
  );
  if ((ghostBundle['http'] as int) < 300) {
    finding(
      id: 'Z1-BUNDLE-NO-ID-TOTAL-FREE',
      sev: 'P1',
      lens: 'Z1',
      actor: 'buyer JWT',
      title:
          'bundle_proposal FLEABER_JSON_V1 sem bundle_id: total_eur=6543.21 aceite (validação só corre se bundle_id presente)',
      repro: 'POST kind=bundle_proposal total_eur=6543.21 sem bundle_id',
      expected: 'exigir bundle_id real e total da BD, ou recusar o kind',
      obtained: {'http': ghostBundle['http'], 'id': idOf(ghostBundle['body'])},
    );
  } else {
    close('Z1.bundle_no_id', 'blocked ${ghostBundle['http']} ${ghostBundle['raw']}');
  }

  // seguro extra field display_total vs total (must match cents to insert)
  final displayLie = await postMsg(
    BH,
    chatId,
    jsonCard('seguro_fleaber_paid', {
      'order_id': oid,
      'total': totalStr,
      'display_total': 43210,
      'amount_eur': 43210,
      'label': 'display-lie',
    }),
  );
  if ((displayLie['http'] as int) < 300) {
    close(
      'Z1.display_extra',
      'INSERT ok (total BD match); extra keys persist — UI Flutter só lê `total` (não é mentira de valor)',
      idOf(displayLie['body']),
    );
  } else {
    close('Z1.display_extra_block', '${displayLie['http']} ${displayLie['raw']}');
  }

  // ============================================================
  // Z4 — URLs / provas (NOT exact proof_url INSERT evil on paid)
  // ============================================================

  final imgHttp = await postMsg(
    BH,
    chatId,
    jsonCard('chat_image', {
      'url': 'https://evil.example/rtz-phishing.png',
    }),
  );
  if ((imgHttp['http'] as int) < 300) {
    finding(
      id: 'Z4-CHAT-IMAGE-ARBITRARY-HTTPS',
      sev: 'P2',
      lens: 'Z4',
      actor: 'buyer JWT',
      title:
          'chat_image URL https://evil.example aceite (guard só bloqueia javascript:/data:/protocol-relative)',
      repro: 'POST kind=chat_image url=https://evil.example/rtz-phishing.png',
      expected: 'allowlist storage fleaber_private / domínio próprio',
      obtained: {'http': imgHttp['http'], 'id': idOf(imgHttp['body'])},
    );
  } else {
    close('Z4.chat_image_https', 'blocked ${imgHttp['http']} ${imgHttp['raw']}');
  }

  final imgJs = await postMsg(
    BH,
    chatId,
    jsonCard('chat_image', {'url': 'JAVASCRIPT:alert(1)'}),
  );
  // lower() should catch
  if ((imgJs['http'] as int) < 300) {
    finding(
      id: 'Z4-CHAT-IMAGE-JS-CASE',
      sev: 'P1',
      lens: 'Z4',
      actor: 'buyer JWT',
      title: 'chat_image javascript: em maiúsculas persistiu',
      repro: 'POST kind=chat_image url=JAVASCRIPT:alert(1)',
      expected: 'chat_system_card_url_denied',
      obtained: imgJs['body'],
    );
  } else {
    close('Z4.chat_image_js', 'blocked ${imgJs['http']}');
  }

  final imgPathTrav = await postMsg(
    BH,
    chatId,
    jsonCard('chat_image', {
      'path': 'chat_uploads/../order_proofs/$buyerId/$oid/secret.png',
    }),
  );
  note('Z4.path_trav http=${imgPathTrav['http']} id=${idOf(imgPathTrav['body'])}');
  if ((imgPathTrav['http'] as int) < 300) {
    finding(
      id: 'Z4-CHAT-IMAGE-PATH-TRAVERSAL-STORED',
      sev: 'P2',
      lens: 'Z4',
      actor: 'buyer JWT',
      title:
          'chat_image.path com chat_uploads/../order_proofs/… persistido (Flutter resolveChatImageUrl captura o path e pede signed URL)',
      repro:
          'POST kind=chat_image path=chat_uploads/../order_proofs/{buyer}/{order}/secret.png',
      expected: 'normalizar/recusar path fora de chat_uploads/{uid}/{chat_id}/',
      obtained: {'http': imgPathTrav['http'], 'id': idOf(imgPathTrav['body'])},
      impact:
          'Se createSignedUrl + storage resolverem `..`, pode assinar provas de outro prefixo. Prova de persistência aqui; efeito storage abaixo.',
    );
  }

  if (unpaidId != null) {
    final fakeProof = await postMsg(
      BH,
      chatId,
      jsonCard('reservation_payment_submitted', {
        'order_id': unpaidId,
        'notes': 'paguei 9999€ RTZ',
        'proof_url': 'javascript:alert(document.cookie)',
      }),
    );
    if ((fakeProof['http'] as int) < 300) {
      finding(
        id: 'Z4-PAYMENT-SUBMITTED-JS-PROOF',
        sev: 'P1',
        lens: 'Z4',
        actor: 'buyer JWT',
        title:
            'reservation_payment_submitted.proof_url=javascript: persistido — não passa pelo guard de chat_image nem de orders.proof_url',
        repro:
            'POST kind=reservation_payment_submitted proof_url=javascript:alert(document.cookie) order reservado',
        expected: 'mesmo denylist que chat_image / orders.proof_url',
        obtained: {'http': fakeProof['http'], 'id': idOf(fakeProof['body'])},
        impact:
            'Flutter _buildReservationPaymentSubmittedCard usa proof_url no CachedNetworkImage e no dialog, sem allowlist.',
      );
    } else {
      close('Z4.pay_js_proof', 'blocked ${fakeProof['http']} ${fakeProof['raw']}');
    }

    final evilImg = await postMsg(
      BH,
      chatId,
      jsonCard('reservation_payment_submitted', {
        'order_id': unpaidId,
        'proof_url': 'https://evil.example/fake-mbway-receipt.png',
      }),
    );
    if ((evilImg['http'] as int) < 300) {
      finding(
        id: 'Z4-PAYMENT-SUBMITTED-EXTERNAL-PROOF',
        sev: 'P1',
        lens: 'Z4',
        actor: 'buyer JWT',
        title:
            'Comprovativo MB WAY no card JSON aponta para https://evil.example (não é orders.proof_url)',
        repro:
            'POST kind=reservation_payment_submitted proof_url=https://evil.example/fake-mbway-receipt.png',
        expected: 'URL só fleaber_private/order_proofs do pedido',
        obtained: {'http': evilImg['http'], 'id': idOf(evilImg['body'])},
      );
    } else {
      close('Z4.pay_ext_proof', 'blocked ${evilImg['http']} ${evilImg['raw']}');
    }
  }

  // proof_url on UNPAID then leave it; also homograph on PAID
  if (unpaidId != null) {
    final puUnpaid = await req(
      'PATCH',
      '/rest/v1/orders?id=eq.$unpaidId',
      h: BH,
      body: {'proof_url': 'https://evil.example/unpaid-receipt.png'},
    );
    final urow = firstMap((await req(
      'GET',
      '/rest/v1/orders?id=eq.$unpaidId&select=id,status,proof_url,amount_paid_cents',
    ))['body']);
    if ((puUnpaid['http'] as int) < 300 &&
        (urow?['proof_url']?.toString() ?? '').contains('evil.example')) {
      finding(
        id: 'Z4-PROOF-URL-UNPAID-EXTERNAL',
        sev: 'P2',
        lens: 'Z4',
        actor: 'buyer JWT',
        title:
            'Pedido reservado (não pago) aceita proof_url externo — o trigger só restringe domínio quando v_paid',
        repro: 'PATCH orders.proof_url=https://evil.example/… status=reservado',
        expected: 'allowlist sempre, ou null até pagamento',
        obtained: {'http': puUnpaid['http'], 'row': urow},
        impact:
            'Se o pedido passar a pago sem UPDATE de proof_url, o URL externo sobrevive no pedido capturado.',
      );
    } else {
      close('Z4.unpaid_proof', '${puUnpaid['http']} stored=${urow?['proof_url']}');
    }
  }

  final homo = await req(
    'PATCH',
    '/rest/v1/orders?id=eq.$oid',
    h: BH,
    body: {
      'proof_url':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co.evil.example/storage/v1/object/public/x.png',
    },
  );
  final paidAfter = firstMap((await req(
    'GET',
    '/rest/v1/orders?id=eq.$oid&select=proof_url',
  ))['body']);
  final storedPu = paidAfter?['proof_url']?.toString() ?? '';
  if ((homo['http'] as int) < 300 && storedPu.contains('evil.example')) {
    finding(
      id: 'Z4-PROOF-URL-SUFFIX-HOMOGRAPH',
      sev: 'P1',
      lens: 'Z4',
      actor: 'buyer JWT',
      title:
          'proof_url pago aceita host supabase.co.evil.example (LIKE prefixo não âncora o host)',
      repro:
          'PATCH orders.proof_url=https://fxdknzrqjenzqcvnwqqq.supabase.co.evil.example/storage/…',
      expected: 'parse URI host ∈ {….supabase.co, fleaber.app, fleaber.pt}',
      obtained: {'http': homo['http'], 'proof_url': storedPu},
    );
  } else {
    close('Z4.homograph', '${homo['http']} stored=$storedPu ${homo['raw']}');
  }

  // fleaber.app open-looking path
  final fleaberApp = await req(
    'PATCH',
    '/rest/v1/orders?id=eq.$oid',
    h: SH,
    body: {'proof_url': 'https://fleaber.app/redirect?u=https://evil.example/x'},
  );
  note('Z4.fleaber_app_query http=${fleaberApp['http']} ${fleaberApp['raw']}');
  // trigger blocks ?https://  — this uses ?u=https:// which is `[?&][^#]*https?://`
  if ((fleaberApp['http'] as int) < 300) {
    finding(
      id: 'Z4-PROOF-URL-FLEABER-QUERY-REDIRECT',
      sev: 'P2',
      lens: 'Z4',
      actor: 'seller JWT',
      title: 'proof_url https://fleaber.app/redirect?u=https://evil passou',
      repro: 'PATCH proof_url=https://fleaber.app/redirect?u=https://evil.example/x',
      expected: 'query com URL nested recusada',
      obtained: fleaberApp['body'],
    );
  } else {
    close('Z4.fleaber_query', 'blocked ${fleaberApp['http']}');
  }

  // dispute replies UPDATE vs INSERT-only trigger
  final dispIns = await req('POST', '/rest/v1/order_disputes', h: SVC, body: {
    'order_id': oid,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'status': 'aberta',
    'reason': '${prefix}fixture',
  });
  final disputeId = idOf(dispIns['body']);
  note('Z4.dispute fixture=$disputeId http=${dispIns['http']}');
  if (disputeId != null) {
    final reply = await req('POST', '/rest/v1/order_dispute_replies', h: BH, body: {
      'dispute_id': disputeId,
      'author_id': buyerId,
      'body': '${prefix}ok',
      'proof_photos': [
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/x'
      ],
    });
    final replyId = idOf(reply['body']);
    note('Z4.reply http=${reply['http']} id=$replyId ${reply['raw']}');
    if (replyId != null) {
      final patchPhotos = await req(
        'PATCH',
        '/rest/v1/order_dispute_replies?id=eq.$replyId',
        h: BH,
        body: {
          'proof_photos': ['javascript:alert(1)', 'https://evil.example/x.png'],
        },
      );
      final rrow = firstMap((await req(
        'GET',
        '/rest/v1/order_dispute_replies?id=eq.$replyId&select=id,proof_photos',
      ))['body']);
      final photos = '${rrow?['proof_photos']}';
      if ((patchPhotos['http'] as int) < 300 &&
          (photos.contains('javascript') || photos.contains('evil.example'))) {
        finding(
          id: 'Z4-DISPUTE-REPLY-UPDATE-PHOTOS',
          sev: 'P1',
          lens: 'Z4',
          actor: 'buyer JWT',
          title:
              'order_dispute_replies.proof_photos: trigger só no INSERT — PATCH grava javascript:/URL externa',
          repro:
              'INSERT reply com URL storage; PATCH proof_photos=[javascript:alert(1), https://evil.example/x.png]',
          expected: 'mesmo guard no UPDATE',
          obtained: {'http': patchPhotos['http'], 'photos': rrow?['proof_photos']},
        );
      } else {
        close('Z4.reply_update', '${patchPhotos['http']} photos=$photos ${patchPhotos['raw']}');
      }
    }

    final replyEvilIns = await req(
      'POST',
      '/rest/v1/order_dispute_replies',
      h: BH,
      body: {
        'dispute_id': disputeId,
        'author_id': buyerId,
        'body': '${prefix}evil-ins',
        'proof_photos': ['https://evil.example/disp.png'],
      },
    );
    if ((replyEvilIns['http'] as int) < 300) {
      finding(
        id: 'Z4-DISPUTE-REPLY-INSERT-EXTERNAL',
        sev: 'P1',
        lens: 'Z4',
        actor: 'buyer JWT',
        title: 'INSERT reply proof_photos URL externa (esperava deny)',
        repro: 'POST order_dispute_replies proof_photos=[https://evil.example/disp.png]',
        expected: 'dispute_proof_url_denied',
        obtained: replyEvilIns['body'],
      );
    } else {
      close('Z4.reply_ins_evil', 'blocked ${replyEvilIns['http']}');
    }
  }

  // storage: B2 list / sign victim chat_uploads
  final listB2 = await req(
    'GET',
    '/storage/v1/object/list/fleaber_private?prefix=chat_uploads/$buyerId',
    h: B2H,
  );
  note('Z4.b2_list_chat http=${listB2['http']} ${listB2['raw'].toString().substring(0, (listB2['raw'] as String).length.clamp(0, 300))}');

  final signB2 = await req(
    'POST',
    '/storage/v1/object/sign/fleaber_private/chat_uploads/$buyerId/$chatId/nope.png',
    h: B2H,
    body: {'expiresIn': 60},
  );
  note('Z4.b2_sign http=${signB2['http']} ${signB2['raw']}');
  if ((signB2['http'] as int) < 300) {
    finding(
      id: 'Z4-B2-SIGN-OTHER-CHAT-UPLOAD',
      sev: 'P1',
      lens: 'Z4',
      actor: 'buyer2 JWT',
      title: 'B2 cria signed URL de chat_uploads do buyer1',
      repro:
          'POST /storage/v1/object/sign/fleaber_private/chat_uploads/{b1}/{chat}/nope.png',
      expected: 'RLS recusa',
      obtained: signB2['body'],
    );
  } else {
    close('Z4.b2_sign', 'blocked ${signB2['http']}');
  }

  // upload overwrite same path
  final png = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);
  final stPath = 'order_proofs/$buyerId/$oid/${prefix}overwrite.png';
  final up1 = await http.post(
    Uri.parse('$url/storage/v1/object/fleaber_private/$stPath'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
      'Content-Type': 'image/png',
      'x-upsert': 'false',
    },
    body: png,
  );
  note('Z4.upload1 ${up1.statusCode} ${up1.body}');
  final up2 = await http.post(
    Uri.parse('$url/storage/v1/object/fleaber_private/$stPath'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
      'Content-Type': 'image/png',
      'x-upsert': 'true',
    },
    body: png,
  );
  note('Z4.upload_upsert ${up2.statusCode} ${up2.body}');
  if (up1.statusCode < 300 && up2.statusCode < 300) {
    finding(
      id: 'Z4-STORAGE-UPSERT-PROOF',
      sev: 'P2',
      lens: 'Z4',
      actor: 'buyer JWT',
      title:
          'x-upsert=true substitui o objecto order_proofs no mesmo path (URL de prova imutável, conteúdo mutável)',
      repro:
          'POST storage fleaber_private/order_proofs/{uid}/{order}/RTZ-overwrite.png com x-upsert true',
      expected: 'provas imutáveis após pagamento (sem upsert)',
      obtained: {'up1': up1.statusCode, 'upsert': up2.statusCode},
    );
  } else {
    close('Z4.upsert_storage', 'up1=${up1.statusCode} up2=${up2.statusCode}');
  }

  // ============================================================
  // Z5 — operational cards without BD
  // ============================================================

  final dispCard = await postMsg(
    BH,
    chatId,
    jsonCard('order_dispute_opened', {
      'order_id': oid,
      'reason': 'RTZ-fake-dispute-card',
    }),
  );
  final dispExists = firstMap((await req(
    'GET',
    '/rest/v1/order_disputes?order_id=eq.$oid&select=id,status&limit=3',
  ))['body']);
  if ((dispCard['http'] as int) < 300) {
    finding(
      id: 'Z5-DISPUTE-CARD-WITHOUT-ROW',
      sev: 'P1',
      lens: 'Z5',
      actor: 'buyer JWT',
      title:
          'Card order_dispute_opened inserido; o kind não exige linha em order_disputes (fixture à parte se existir)',
      repro: 'POST kind=order_dispute_opened order_id=pago',
      expected: 'exigir disputa aberta na BD',
      obtained: {
        'http': dispCard['http'],
        'msg': idOf(dispCard['body']),
        'dispute_row_sample': dispExists,
      },
    );
  } else {
    close('Z5.dispute_card', '${dispCard['http']} ${dispCard['raw']}');
  }

  final reviewCard = await postMsg(
    BH,
    chatId,
    jsonCard('order_review_submitted', {
      'order_id': oid,
      'rating': 1,
      'comment': 'RTZ-fake-review',
    }),
  );
  if ((reviewCard['http'] as int) < 300) {
    finding(
      id: 'Z5-REVIEW-CARD-WITHOUT-REVIEW',
      sev: 'P1',
      lens: 'Z5',
      actor: 'buyer JWT',
      title: 'order_review_submitted sem row em reviews',
      repro: 'POST kind=order_review_submitted order pago (sem insert reviews)',
      expected: 'exigir review.order_id existente',
      obtained: {'http': reviewCard['http'], 'id': idOf(reviewCard['body'])},
    );
  } else {
    close('Z5.review_card', '${reviewCard['http']} ${reviewCard['raw']}');
  }

  final cancelSeller = await postMsg(
    SH,
    chatId,
    jsonCard('reservation_cancelled_by_seller', {'order_id': oid}),
  );
  final stNow = firstMap((await req(
    'GET',
    '/rest/v1/orders?id=eq.$oid&select=status',
  ))['body']);
  if ((cancelSeller['http'] as int) < 300 &&
      '${stNow?['status']}' != 'cancelado') {
    finding(
      id: 'Z5-SELLER-CANCEL-CARD-ON-PAID',
      sev: 'P1',
      lens: 'Z5',
      actor: 'seller JWT',
      title:
          'reservation_cancelled_by_seller no pedido Stripe capturado (status≠cancelado)',
      repro: 'POST kind=reservation_cancelled_by_seller order_id=pago',
      expected: 'status_mismatch / só se BD cancelado',
      obtained: {'http': cancelSeller['http'], 'order_status': stNow?['status']},
    );
  } else {
    close('Z5.seller_cancel', '${cancelSeller['http']} ${cancelSeller['raw']} st=${stNow?['status']}');
  }

  if (unpaidId != null) {
    final acc = await postMsg(
      SH,
      chatId,
      jsonCard('reservation_accepted', {
        'order_id': unpaidId,
        'expires_at': '2018-01-01T00:00:00.000Z',
      }),
    );
    if ((acc['http'] as int) < 300) {
      finding(
        id: 'Z3-RESERVATION-ACCEPTED-EXPIRES-BACKDATE',
        sev: 'P1',
        lens: 'Z3',
        actor: 'seller JWT',
        title:
            'reservation_accepted.expires_at=2018-01-01 aceite — Flutter mostra o prazo do JSON, created_at da mensagem é now()',
        repro:
            'POST kind=reservation_accepted expires_at=2018-01-01 (não é created_at da mensagem)',
        expected: 'expires_at da BD / servidor, não do cliente',
        obtained: {'http': acc['http'], 'id': idOf(acc['body'])},
      );
    } else {
      close('Z3.expires_at', '${acc['http']} ${acc['raw']}');
    }

    final reqOut = await postMsg(
      SH,
      chatId,
      jsonCard('reservation_request_outcome', {
        'order_id': unpaidId,
        'outcome': 'accepted',
      }),
    );
    if ((reqOut['http'] as int) < 300) {
      finding(
        id: 'Z5-RESERVATION-OUTCOME-NO-STATE',
        sev: 'P1',
        lens: 'Z5',
        actor: 'seller JWT',
        title:
            'reservation_request_outcome accepted sem verificar estado/oferta na BD',
        repro: 'POST kind=reservation_request_outcome outcome=accepted',
        expected: 'alinhar a orders.status / reservation row',
        obtained: {'http': reqOut['http'], 'id': idOf(reqOut['body'])},
      );
    } else {
      close('Z5.req_outcome', '${reqOut['http']} ${reqOut['raw']}');
    }
  }

  final shipLie = await postMsg(
    SH,
    chatId,
    jsonCard('reservation_order_shipped', {'order_id': oid}),
  );
  if ((shipLie['http'] as int) < 300 && '${orow?['status']}' == 'pago') {
    finding(
      id: 'Z5-SHIPPED-CARD-ON-PAGO',
      sev: 'P1',
      lens: 'Z5',
      actor: 'seller JWT',
      title: 'reservation_order_shipped em pedido ainda pago (não enviado)',
      repro: 'POST kind=reservation_order_shipped status=pago',
      expected: 'chat_system_card_status_mismatch',
      obtained: {'http': shipLie['http'], 'status': orow?['status']},
    );
  } else {
    close('Z5.shipped_pago', '${shipLie['http']} ${shipLie['raw']}');
  }

  final doneLie = await postMsg(
    BH,
    chatId,
    jsonCard('reservation_order_completed', {'order_id': oid}),
  );
  if ((doneLie['http'] as int) < 300) {
    finding(
      id: 'Z5-COMPLETED-CARD-ON-PAGO',
      sev: 'P1',
      lens: 'Z5',
      actor: 'buyer JWT',
      title: 'reservation_order_completed em pedido não concluído',
      repro: 'POST kind=reservation_order_completed status≠concluido',
      expected: 'status_mismatch',
      obtained: doneLie['body'],
    );
  } else {
    close('Z5.completed', '${doneLie['http']}');
  }

  // ============================================================
  // Z6 — inbox / last_message
  // ============================================================
  final inbox = await req(
    'PATCH',
    '/rest/v1/chats?id=eq.$chatId',
    h: BH,
    body: {
      'last_message': 'Compra paga através do Seguro Fleaber (9999.00 €)',
      'last_message_time': '2010-01-01T00:00:00Z',
    },
  );
  final crow = firstMap((await req(
    'GET',
    '/rest/v1/chats?id=eq.$chatId&select=id,last_message,last_message_time',
  ))['body']);
  if ((inbox['http'] as int) < 300 &&
      (crow?['last_message']?.toString() ?? '').contains('9999')) {
    finding(
      id: 'Z6-INBOX-LAST-MESSAGE-FORGE',
      sev: 'P2',
      lens: 'Z6',
      actor: 'buyer JWT',
      title:
          'Participante PATCH chats.last_message + last_message_time=2010 — inbox mente valor e cronologia',
      repro:
          'PATCH chats last_message="Compra paga… (9999.00 €)" last_message_time=2010-01-01',
      expected: 'last_message derivado do INSERT de mensagens / servidor',
      obtained: crow,
    );
  } else {
    close('Z6.inbox', '${inbox['http']} ${crow}');
  }

  // ============================================================
  // Z3 — chronology besides created_at
  // ============================================================
  final backMsg = await postMsg(
    BH,
    chatId,
    '${prefix}chrono-plain',
    createdAt: '2015-06-01T00:00:00Z',
  );
  final bmap = firstMap(backMsg['body']);
  final gotCreated = bmap?['created_at']?.toString() ?? '';
  if ((backMsg['http'] as int) < 300 && gotCreated.startsWith('2015')) {
    finding(
      id: 'Z3-CREATED-AT-PLAIN-BACKDATE',
      sev: 'P1',
      lens: 'Z3',
      actor: 'buyer JWT',
      title: 'created_at=2015 persistiu em mensagem plain (esperava now())',
      repro: 'POST chat_messages created_at=2015-06-01 text=plain',
      expected: 'NEW.created_at := now()',
      obtained: bmap,
    );
  } else {
    close('Z3.created_plain', 'forced now() or fail · stored=$gotCreated http=${backMsg['http']}');
  }

  if (plainId == null && bmap != null) {
    final pid2 = idOf(backMsg['body']);
    if (pid2 != null) {
      final pCreated = await req(
        'PATCH',
        '/rest/v1/chat_messages?id=eq.$pid2',
        h: BH,
        body: {'created_at': '2012-01-01T00:00:00Z'},
      );
      final after = firstMap((await req(
        'GET',
        '/rest/v1/chat_messages?id=eq.$pid2&select=id,created_at,text',
      ))['body']);
      if ((after?['created_at']?.toString() ?? '').startsWith('2012')) {
        finding(
          id: 'Z3-PATCH-CREATED-AT-PLAIN',
          sev: 'P1',
          lens: 'Z3',
          actor: 'buyer JWT',
          title: 'PATCH created_at em mensagem própria plain reescreveu cronologia',
          repro: 'PATCH chat_messages created_at=2012-01-01',
          expected: 'NEW.created_at := OLD.created_at',
          obtained: after,
        );
      } else {
        close('Z3.patch_created', '${pCreated['http']} stored=${after?['created_at']}');
      }
    }
  }

  // ============================================================
  // Z7 — 2nd actor
  // ============================================================
  final b2read = await req(
    'GET',
    '/rest/v1/chat_messages?chat_id=eq.$chatId&select=id,text,sender_id&limit=5',
    h: B2H,
  );
  final b2n = b2read['body'] is List ? (b2read['body'] as List).length : -1;
  if ((b2read['http'] as int) < 300 && b2n > 0) {
    finding(
      id: 'Z7-B2-READ-THREAD',
      sev: 'P1',
      lens: 'Z7',
      actor: 'buyer2 JWT',
      title: 'B2 lê chat_messages da thread B1/S1',
      repro: 'GET chat_messages?chat_id=eq.$chatId',
      expected: '0 rows / 401',
      obtained: {'http': b2read['http'], 'n': b2n},
    );
  } else {
    close('Z7.b2_read', 'n=$b2n http=${b2read['http']}');
  }

  final b2ins = await postMsg(B2H, chatId, '${prefix}b2-intrusion');
  if ((b2ins['http'] as int) < 300) {
    finding(
      id: 'Z7-B2-INSERT-THREAD',
      sev: 'P1',
      lens: 'Z7',
      actor: 'buyer2 JWT',
      title: 'B2 INSERT na thread alheia',
      repro: 'POST chat_messages chat_id=thread B1/S1',
      expected: 'RLS',
      obtained: b2ins['body'],
    );
  } else {
    close('Z7.b2_ins', '${b2ins['http']}');
  }

  final b2inbox = await req(
    'PATCH',
    '/rest/v1/chats?id=eq.$chatId',
    h: B2H,
    body: {'last_message': 'B2 hijack inbox'},
  );
  if ((b2inbox['http'] as int) < 300) {
    final chk = firstMap((await req(
      'GET',
      '/rest/v1/chats?id=eq.$chatId&select=last_message',
    ))['body']);
    if ((chk?['last_message']?.toString() ?? '').contains('B2 hijack')) {
      finding(
        id: 'Z7-B2-PATCH-INBOX',
        sev: 'P1',
        lens: 'Z7',
        actor: 'buyer2 JWT',
        title: 'B2 PATCH last_message da thread alheia',
        repro: 'PATCH chats?id=eq.thread_alheia',
        expected: 'RLS',
        obtained: chk,
      );
    } else {
      close('Z7.b2_inbox_empty', 'http 2xx mas 0 rows affected');
    }
  } else {
    close('Z7.b2_inbox', '${b2inbox['http']}');
  }

  final anonRead = await req(
    'GET',
    '/rest/v1/chat_messages?chat_id=eq.$chatId&select=id&limit=3',
    h: ANON,
  );
  final an = anonRead['body'] is List ? (anonRead['body'] as List).length : -1;
  if ((anonRead['http'] as int) < 300 && an > 0) {
    finding(
      id: 'Z7-ANON-READ-MSGS',
      sev: 'P1',
      lens: 'Z7',
      actor: 'anon',
      title: 'anon lê chat_messages',
      repro: 'GET Authorization=anon',
      expected: '0',
      obtained: {'n': an},
    );
  } else {
    close('Z7.anon', 'n=$an http=${anonRead['http']}');
  }

  // ============================================================
  // Z8 — composition: chat lie + Edge
  // ============================================================
  final refund = await req(
    'POST',
    '/functions/v1/refund-order',
    h: BH,
    body: {'order_id': oid},
  );
  final afterRef = firstMap((await req(
    'GET',
    '/rest/v1/orders?id=eq.$oid&select=id,status,stripe_refund_id,amount_paid_cents',
  ))['body']);
  note('Z8.refund-order http=${refund['http']} ${refund['raw']} after=$afterRef');
  // Buyer calling refund-order on captured paid order might be legitimate product
  // or might be blocked. Document either way. If it refunds because of chat cards,
  // that's P0. We did insert fake cancel/dispute cards — check if Edge used them.
  final refundOk = (refund['http'] as int) < 300 &&
      (refund['body'] is Map &&
          (refund['body'] as Map)['ok'] == true);
  if (refundOk && '${afterRef?['status']}' == 'cancelado') {
    finding(
      id: 'Z8-REFUND-AFTER-FAKE-CARDS',
      sev: 'P0',
      lens: 'Z8',
      actor: 'buyer JWT',
      title:
          'refund-order succedeu após cards forjados (dispute/cancel) — verificar se Edge obedeceu ao chat',
      repro: 'INSERT cards Z5 + POST /functions/v1/refund-order {order_id}',
      expected: 'Edge ignora chat; refund só por regra de produto (buyer refund em pago pode ser feature)',
      obtained: {'http': refund['http'], 'body': refund['body'], 'order': afterRef},
      impact:
          'Se o produto permite refund em pago, NÃO é composição chat→caixa (anotar como feature). Se o Edge leu as mensagens, é P0.',
    );
  } else {
    close('Z8.refund', 'Edge não refundou via chat ${refund['http']}');
  }

  // capture / confirm payment RPCs that might trust chat
  for (final fn in [
    'batata_seller_confirm_direct_payment',
    'batata_confirm_direct_payment',
    'batata_mark_order_paid_from_chat',
    'confirm_mbway_payment',
  ]) {
    final r = await req('POST', '/rest/v1/rpc/$fn', h: SH, body: {
      'p_order_id': unpaidId ?? oid,
      'order_id': unpaidId ?? oid,
    });
    note('Z8.rpc $fn http=${r['http']} ${r['raw'].toString().substring(0, (r['raw'] as String).length.clamp(0, 240))}');
    if ((r['http'] as int) < 300 &&
        r['body'] != null &&
        r['body'] != false &&
        '${r['body']}' != 'null') {
      final uAfter = unpaidId == null
          ? null
          : firstMap((await req(
              'GET',
              '/rest/v1/orders?id=eq.$unpaidId&select=id,status,amount_paid_cents',
            ))['body']);
      if (uAfter != null &&
          (uAfter['status'] == 'pago' ||
              ((uAfter['amount_paid_cents'] as num?) ?? 0) > 0)) {
        finding(
          id: 'Z8-RPC-PAID-FROM-CHAT-$fn',
          sev: 'P0',
          lens: 'Z8',
          actor: 'seller JWT',
          title: 'RPC $fn passou reserva a pago sem captura Stripe',
          repro: 'POST rpc/$fn após cards de pagamento forjados',
          expected: 'não marcar pago sem prova servidor',
          obtained: {'rpc': r['body'], 'order': uAfter},
        );
      }
    }
  }

  // prefix / kind bypass leftovers
  final bom = await postMsg(
    BH,
    chatId,
    '\uFEFF${jsonCard('seguro_fleaber_paid', {
      'order_id': oid,
      'total': '4321',
    })}',
  );
  note('Z1.bom_prefix http=${bom['http']} ${bom['raw']}');
  if ((bom['http'] as int) < 300) {
    // Flutter startsWith FLEABER won't match BOM, so it would be a text bubble —
    // and forged_seguro_plain also wouldn't match. Hygiene unless UI parses BOM.
    finding(
      id: 'Z2-BOM-PREFIX-JSON',
      sev: 'P3',
      lens: 'Z2',
      actor: 'buyer JWT',
      title: 'BOM + FLEABER_JSON_V1 inserido (trigger não vê o prefixo)',
      repro: 'POST text=\\uFEFFFLEABER_JSON_V1:{"kind":"seguro_fleaber_paid","total":"4321"}',
      expected: 'opcional: recusar prefixos ofuscados',
      obtained: {'http': bom['http'], 'id': idOf(bom['body'])},
    );
  } else {
    close('Z1.bom', '${bom['http']} ${bom['raw']}');
  }

  final serverOnly = await postMsg(
    BH,
    chatId,
    jsonCard('order_paid', {'order_id': oid, 'total': '9999'}),
  );
  close('Z1.order_paid_jwt', '${serverOnly['http']} ${serverOnly['raw']}');

  // write artifacts
  final dir = Directory('tool/redteam_blind_z_20260901T1715');
  final out = {
    'prefix': prefix,
    'order_id': oid,
    'chat_id': chatId,
    'unpaid_id': unpaidId,
    'buyer': buyerId,
    'seller': sellerId,
    'b2': b2Id,
    'svc_receipt_id': svcReceiptId,
    'paid_cents': paidCents,
    'findings': findings,
    'closed': closed,
    'notes': notes,
  };
  File('${dir.path}/probe_result.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print('--- findings=${findings.length} closed=${closed.length} ---');
  for (final f in findings) {
    print('  ${f['sev']} ${f['id']}');
  }
}
