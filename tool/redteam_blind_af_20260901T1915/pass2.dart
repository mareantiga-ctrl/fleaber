/// Pass 2 — verificar falsos positivos, mutação, redirects, DELETE do card FF.
import 'dart:convert';
import 'dart:io';

import '_rtaf.dart';

Future<HttpHit> headFollow(String url) async {
  final client = HttpClient();
  try {
    var current = Uri.parse(url);
    String? loc;
    var status = 0;
    var hops = 0;
    while (hops < 4) {
      final rq = await client.openUrl('GET', current);
      rq.followRedirects = false;
      rq.headers.set('User-Agent', 'RTAF/1');
      final rs = await rq.close();
      status = rs.statusCode;
      loc = rs.headers.value('location');
      await rs.drain();
      if (status >= 300 && status < 400 && loc != null) {
        current = current.resolve(loc);
        hops++;
        continue;
      }
      break;
    }
    return HttpHit(status, loc ?? '', loc);
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  final c = Rtaf.fromEnv(loadEnv());
  await c.loginActors();

  const chatId = 'b3188bdd-c957-46c1-8f0f-db55ba442605';
  const reservedId = '352251b6-9f17-4de8-94fb-194647151909';
  const paidId = '3b6fc32f-d413-4f2e-8d77-1ab3b4ff184a';
  const ffId = '1027';

  // 1) FF card still stored?
  final ff = await c.rest(
    'GET',
    'chat_messages?id=eq.$ffId&select=id,text,sender_id,created_at',
    jwt: c.buyerJwt!,
  );
  final ffText = ff.map?['text']?.toString() ?? '';
  c.note('p2.ff.stored', 'msg 1027', {
    'http': ff.status,
    'len': ffText.length,
    'cp0': ffText.isEmpty ? null : ffText.codeUnitAt(0),
    'parses': c.flutterWouldParseBundleRaw(ffText),
    'has_total': ffText.contains('6543.21'),
  }, lens: 'AF2');

  // 2) Mutate FF card total (UPDATE)
  if (ff.ok && ffText.isNotEmpty) {
    final mutated = '\u000c${jsonEncode({
      'kind': 'bundle_proposal',
      'total_eur': 1.0,
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
    })}';
    final patch = await c.rest(
      'PATCH',
      'chat_messages?id=eq.$ffId',
      jwt: c.buyerJwt!,
      body: {'text': mutated},
    );
    final after = await c.msgRow(ffId);
    final afterText = after?['text']?.toString() ?? '';
    if (patch.ok &&
        (afterText.contains('1.0') || afterText.contains('"total_eur":1'))) {
      c.hold(
        id: 'AF5.MUTATE.FF-BUNDLE',
        lens: 'AF5',
        severity: 'P1',
        title:
            'Card bundle_proposal FF (JSON cru) é mutável via PATCH — total 6543.21 → 1.00',
        actor: 'buyer JWT',
        pre: 'guard_update só imutabiliza prefixo FLEABER_JSON_V1',
        repro: 'PATCH chat_messages?id=eq.1027 text=<FF>{kind:bundle_proposal,total_eur:1}',
        expected: 'chat_system_card_immutable',
        obtained: {
          'http': patch.status,
          'after_parses': c.flutterWouldParseBundleRaw(afterText),
          'after_clip': clip(afterText, 160),
        },
      );
    } else if (patch.ok) {
      c.note('p2.mutate.ff', 'PATCH 200 mas texto inesperado', {
        'http': patch.status,
        'after': clip(afterText, 160),
      }, lens: 'AF5');
    } else {
      c.block('AF5.MUTATE.FF-BUNDLE', 'AF5', 'PATCH FF recusado',
          '${patch.pgCode} ${patch.pgMsg}');
    }
  }

  // 3) DELETE FF card
  final delFf = await c.rest(
    'DELETE',
    'chat_messages?id=eq.1028',
    jwt: c.buyerJwt!,
    prefer: 'return=representation',
  );
  final stillVt = await c.msgRow('1028');
  if (delFf.ok && stillVt == null) {
    c.hold(
      id: 'AF5.DEL.FF-BUNDLE',
      lens: 'AF5',
      severity: 'P1',
      title:
          'Card bundle_proposal VT (JSON cru parseado pelo Flutter) apagável — prova de pagamento/proposta some',
      actor: 'buyer JWT',
      pre: 'DELETE imutável só FLEABER_JSON_V1 ou btrim `{`',
      repro: 'DELETE chat_messages?id=eq.1028',
      expected: 'chat_system_card_immutable',
      obtained: {
        'http': delFf.status,
        'deleted_id': delFf.firstId ?? delFf.map?['id'],
        'still': stillVt,
      },
    );
  } else {
    c.block('AF5.DEL.FF-BUNDLE', 'AF5', 'DELETE VT não removeu ou recusou',
        '${delFf.brief} still=${stillVt != null}');
  }

  // 4) FLEABER DELETE really blocked? pick seller-sent JSON card
  final jsonCards = await c.rest(
    'GET',
    'chat_messages?chat_id=eq.$chatId&text=like.FLEABER_JSON_V1%25&select=id,sender_id,text&order=id.desc&limit=8',
    jwt: c.buyerJwt!,
  );
  c.note('p2.json.list', 'FLEABER cards', jsonCards.list.map((e) {
    if (e is Map) {
      return {'id': e['id'], 'sender': e['sender_id']};
    }
    return e;
  }).toList(), lens: 'AF5');

  for (final row in jsonCards.list) {
    if (row is! Map) continue;
    if (row['sender_id']?.toString() != c.buyerId) continue;
    final id = row['id']?.toString();
    if (id == null) continue;
    final del = await c.rest(
      'DELETE',
      'chat_messages?id=eq.$id',
      jwt: c.buyerJwt!,
      prefer: 'return=representation',
    );
    final still = await c.msgRow(id);
    if (del.ok && still == null && (del.list.isNotEmpty || del.map != null)) {
      c.hold(
        id: 'AF5.DEL.JSONV1-REAL',
        lens: 'AF5',
        severity: 'P1',
        title: 'DELETE removeu card FLEABER_JSON_V1 próprio',
        actor: 'buyer JWT',
        pre: 'guard_delete',
        repro: 'DELETE chat_messages?id=eq.$id',
        expected: 'immutable',
        obtained: {'http': del.status, 'body': clip(del.body, 200)},
      );
    } else {
      c.block('AF5.DEL.JSONV1-REAL', 'AF5', 'JSON V1 sobrevive',
          '${del.status} ${del.pgCode} ${del.pgMsg} still=${still != null}');
    }
    break;
  }

  // 5) Follow fleaber.app proof URLs
  for (final u in [
    'https://fleaber.app/favicon.ico',
    'https://www.fleaber.pt/robots.txt',
    'https://fleaber.app/l?next=//evil.example/receipt.png',
    'https://fleaber.app/l?u=evil.example/receipt.png',
  ]) {
    try {
      final h = await headFollow(u);
      final loc = h.body;
      final evil = loc.contains('evil.example');
      c.note('p2.url.$u', 'GET', {'status': h.status, 'loc': loc, 'evil': evil},
          lens: 'AF4');
      if (evil) {
        c.hold(
          id: 'AF4.REDIRECT.EVIL',
          lens: 'AF4',
          severity: 'P1',
          title: 'fleaber.app open-redirect para evil.example via query',
          actor: 'buyer JWT (URL já persistida no card)',
          pre: 'proof_url allowlist fleaber.app sem restringir query',
          repro: 'GET $u',
          expected: 'sem Location para evil',
          obtained: {'status': h.status, 'location': loc},
        );
      }
    } catch (e) {
      c.note('p2.url.err', u, '$e', lens: 'AF4');
    }
  }

  // 6) Buyer-only kind as seller
  final asSeller = await c.postMsg(
    chatId: chatId,
    jwt: c.sellerJwt!,
    text: fj({
      'kind': 'reservation_payment_submitted',
      'order_id': reservedId,
    }),
  );
  if (asSeller.ok) {
    c.hold(
      id: 'AF1.ROLE.SELLER-AS-BUYER',
      lens: 'AF1',
      severity: 'P1',
      title: 'Seller injeta reservation_payment_submitted (kind buyer-only)',
      actor: 'seller JWT',
      pre: 'chat_system_card_buyer_only',
      repro: 'POST kind=reservation_payment_submitted jwt=seller',
      expected: 'buyer_only',
      obtained: asSeller.brief,
    );
  } else {
    c.block('AF1.ROLE.SELLER-AS-BUYER', 'AF1', 'seller-as-buyer recusado',
        '${asSeller.pgCode} ${asSeller.pgMsg}');
  }

  // 7) UPDATE last_message on existing chat with transfer preview
  final patchInbox = await c.rest(
    'PATCH',
    'chats?id=eq.$chatId',
    jwt: c.buyerJwt!,
    body: {'last_message': 'Transferência confirmada 4321,00 €'},
  );
  if (patchInbox.ok) {
    c.hold(
      id: 'AF5.INBOX.PATCH.TRANSFER',
      lens: 'AF5',
      severity: 'P2',
      title: 'PATCH last_message «Transferência confirmada 4321,00 €» na thread existente',
      actor: 'buyer JWT',
      pre: 'regex só Seguro Fleaber|Compra paga|MB WAY|PIX',
      repro: 'PATCH chats last_message=Transferência confirmada 4321,00 €',
      expected: 'forbidden',
      obtained: {
        'http': patchInbox.status,
        'stored': patchInbox.map?['last_message'],
      },
    );
  } else {
    c.block('AF5.INBOX.PATCH.TRANSFER', 'AF5', 'patch transfer recusado',
        '${patchInbox.pgCode} ${patchInbox.pgMsg}');
  }

  // 8) orders.proof_url same fleaber.app static (paridade)
  final opu = await c.rest(
    'PATCH',
    'orders?id=eq.$reservedId',
    jwt: c.buyerJwt!,
    body: {'proof_url': 'https://fleaber.app/favicon.ico'},
  );
  final orow = await c.orderRow(reservedId);
  if (opu.ok &&
      (orow?['proof_url']?.toString() ?? '').contains('fleaber.app')) {
    c.hold(
      id: 'AF4.ORDER.PROOF.FLEABER-APP',
      lens: 'AF4',
      severity: 'P2',
      title: 'orders.proof_url aceita https://fleaber.app/favicon.ico (mesma allowlist larga)',
      actor: 'buyer JWT',
      pre: 'batata_orders_guard_proof_url',
      repro: 'PATCH orders.proof_url=https://fleaber.app/favicon.ico',
      expected: 'order_proof_url_denied ou path de storage',
      obtained: {'http': opu.status, 'proof_url': orow?['proof_url']},
    );
  } else {
    c.block('AF4.ORDER.PROOF.FLEABER-APP', 'AF4', 'order proof fleaber.app recusado',
        '${opu.pgCode} ${opu.pgMsg} stored=${orow?['proof_url']}');
  }

  // 9) unicode escape kind in FLEABER json
  final esc = await c.postMsg(
    chatId: chatId,
    jwt: c.buyerJwt!,
    text: 'FLEABER_JSON_V1:{"kind":"seguro\\u005ffleaber\\u005fpaid","order_id":"$paidId","total":12.34}',
  );
  if (esc.ok) {
    c.hold(
      id: 'AF2.KIND.UNICODE-ESCAPE',
      lens: 'AF2',
      severity: 'P2',
      title: 'kind via \\u escape aceite',
      actor: 'buyer JWT',
      pre: 'jsonb unescapes then lower(kind)',
      repro: 'kind seguro\\u005ffleaber\\u005fpaid',
      expected: 'se total bate, card pago (controlo de parser)',
      obtained: esc.brief,
    );
  } else {
    c.block('AF2.KIND.UNICODE-ESCAPE', 'AF2', 'unicode kind recusado',
        '${esc.pgCode} ${esc.pgMsg}');
  }

  // 10) B2 GET storage object uploaded by buyer
  // login b2 again
  await c.ensureBuyer2();
  final obj =
      'chat_uploads/${c.buyerId}/$chatId/${prefix}-a.png';
  final steal = await c.req(
    'GET',
    '/storage/v1/object/fleaber_private/$obj',
    jwt: c.buyer2Jwt,
  );
  if (steal.ok) {
    c.hold(
      id: 'AF7.STORAGE.B2-READ',
      lens: 'AF7',
      severity: 'P1',
      title: 'Buyer2 lê chat_uploads da thread B–S',
      actor: 'buyer2 JWT',
      pre: 'counterparty só do chat',
      repro: 'GET storage fleaber_private/chat_uploads/{B}/{chat}/…',
      expected: '403',
      obtained: {'http': steal.status, 'len': steal.body.length},
    );
  } else {
    c.block('AF7.STORAGE.B2-READ', 'AF7', 'B2 não lê storage alheio', steal.brief);
  }

  await c.dumpAll('findings_pass2.json');
  stdout.writeln(
      'PASS2 findings=${c.findings.length} blocked=${c.blocked.length} notes=${c.notes.length}');
}
