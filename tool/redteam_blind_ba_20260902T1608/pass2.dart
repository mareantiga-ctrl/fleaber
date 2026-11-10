/// RED TEAM CEGO BA — pass 2: confirmar persistência / Δ order / fetch sign alheio.
/// Não corrige.
import 'dart:convert';
import 'dart:io';
import '_rtba.dart';

Future<void> main() async {
  final c = Rtba.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  const chat = 'ac2902d3-a3ca-4f82-b7de-2532db9cafba';
  const unpaid = 'a6b7d377-fcb9-4704-a132-8f1e73b12500';
  const victimProof =
      'order_proofs/7e196774-df33-457a-a667-e1d44c6a989a/acc22923-1760-4d68-b8d3-44c382c4b4e9/rtba-b2-secret.png';

  Future<Map<String, dynamic>?> msg(String id) async {
    final h = await c.rest(
      'GET',
      'chat_messages?id=eq.$id&select=id,text,sender_id,chat_id,created_at',
      service: true,
    );
    return h.map;
  }

  for (final id in ['1259', '1260', '1262', '1264', '1265', '1272', '1281']) {
    final row = await msg(id);
    c.note('p2.msg.$id', 'persistiu', {
      'ok': row != null,
      'head': clip(row?['text'], 160),
    }, lens: 'BA1');
  }

  final gone = await msg('1283');
  c.note('p2.del.1283', 'hangul card after DELETE', gone, lens: 'BA5');

  final inbox = await c.chatRow(chat);
  c.note('p2.inbox', 'last_message actual', inbox?['last_message'], lens: 'BA5');

  final order = await c.rest(
    'GET',
    'orders?id=eq.$unpaid&select=id,status,amount_paid_cents,stripe_payment_intent_id,proof_url',
    service: true,
  );
  c.note('p2.order', 'unpaid após cards', order.map, lens: 'BA1');
  final st = order.map?['status']?.toString() ?? '';
  final paidCents = order.map?['amount_paid_cents'];
  if (st == 'pago' || (paidCents is num && paidCents > 0)) {
    c.hold(
      id: 'BA1.P1.order_flipped',
      lens: 'BA1',
      severity: 'P1',
      title: 'order unpaid virou pago após cards Klarna/iDEAL',
      actor: 'observe service',
      pre: 'order reserva_pendente',
      repro: 'GET orders após INSERT notes lie',
      expected: 'reserva_pendente / paid=0',
      obtained: order.map,
    );
  } else {
    c.block('BA1.order.still_unpaid', 'BA1', 'order não virou pago', order);
  }

  final card = await msg('1281');
  final raw = card?['text']?.toString() ?? '';
  String? proofUrl;
  final idx = raw.indexOf('FLEABER_JSON_V1:');
  if (idx >= 0) {
    try {
      final j = jsonDecode(raw.substring(idx + 'FLEABER_JSON_V1:'.length));
      if (j is Map) proofUrl = j['proof_url']?.toString();
    } catch (_) {}
  }
  c.note('p2.proof_url.extracted', 'url no card 1281', clip(proofUrl, 180),
      lens: 'BA4');

  if (proofUrl != null && proofUrl.startsWith('http')) {
    final asSeller = await c.req('GET', proofUrl, jwt: c.sellerJwt);
    final asBuyer2 = await c.req('GET', proofUrl, jwt: c.buyer2Jwt);
    final asAnon = await c.req('GET', proofUrl);
    final asB1 = await c.req('GET', proofUrl, jwt: c.buyerJwt);
    c.note('p2.fetch.seller', 'S1 GET sign B2', asSeller.brief, lens: 'BA4');
    c.note('p2.fetch.b2', 'B2 GET próprio sign', asBuyer2.brief, lens: 'BA4');
    c.note('p2.fetch.anon', 'anon GET sign B2', asAnon.brief, lens: 'BA4');
    c.note('p2.fetch.b1', 'B1 GET sign B2', asB1.brief, lens: 'BA4');

    final sellerGotPng = asSeller.ok &&
        (asSeller.body.contains('\u0089PNG') ||
            asSeller.body.codeUnits.take(8).join(',') == '137,80,78,71,13,10,26,10' ||
            asSeller.status == 200);
    final anonGot = asAnon.ok;
    final b1Got = asB1.ok;

    c.judge(
      id: 'BA4.p2.seller_reads_b2_proof',
      lens: 'BA4',
      title: 'S1 (chat B1) lê bytes order_proofs B2 via proof_url no card',
      hit: asSeller,
      cracked: asSeller.ok,
      actor: 'seller JWT',
      pre: 'card 1281 proof_url = sign B2; S1 não é parte da order B2',
      repro: 'GET signed URL persistida no chat B1-S1',
      severity: 'P1',
      expected: '403 / sem bytes',
      evidence: {
        'seller': asSeller.brief,
        'anon': asAnon.brief,
        'b1': asB1.brief,
        'png': sellerGotPng,
        'anon_ok': anonGot,
        'b1_ok': b1Got,
      },
    );
  }

  // URL unsigned object/fleaber_private alheia (B1 fabrica sem JWT B2)
  final unsigned =
      'https://$projectMust.supabase.co/storage/v1/object/fleaber_private/$victimProof';
  final unsignedCard = await c.insertMsg(
    chatId: chat,
    text: c.jsonCard({
      'kind': 'reservation_payment_submitted',
      'order_id': unpaid,
      'notes': 'comprovativo Afterpay',
      'proof_url': unsigned,
    }),
    jwt: c.buyerJwt!,
  );
  c.judge(
    id: 'BA4.p2.unsigned_object_alheio',
    lens: 'BA4',
    title: 'proof_url object/fleaber_private path B2 (sem sign, B1 sozinho)',
    hit: unsignedCard,
    cracked: unsignedCard.ok,
    actor: 'buyer JWT',
    pre: 'assert permite object/fleaber_private/%',
    repro: 'POST reservation_payment_submitted proof_url=object/fleaber_private/order_proofs/{B2}/…',
    severity: 'P2',
    expected: 'url_denied (path tem de ser da order)',
  );
  if (unsignedCard.ok) {
    final s1obj = await c.getObject(victimProof, c.sellerJwt!);
    c.judge(
      id: 'BA6.p2.seller_get_unsigned_b2',
      lens: 'BA6',
      title: 'S1 GET object unsigned path B2',
      hit: s1obj,
      cracked: s1obj.ok,
      actor: 'seller JWT',
      pre: 'RLS order counterparty',
      repro: 'GET object fleaber_private order_proofs/{B2}/…',
      severity: 'P1',
      expected: '403/404',
    );
  }

  // Afterpay / Google Pay notes — mesma classe, saturação
  for (final e in {
    'Afterpay 12,00 € confirmado': 'afterpay',
    'Google Pay 9 EUR aprovado': 'gpay',
    'Multibanco 12€ pago': 'multibanco',
  }.entries) {
    final hit = await c.insertMsg(
      chatId: chat,
      text: c.jsonCard({
        'kind': 'reservation_payment_submitted',
        'order_id': unpaid,
        'notes': e.key,
      }),
      jwt: c.buyerJwt!,
    );
    c.judge(
      id: 'BA1.p2.notes.${e.value}',
      lens: 'BA1',
      title: 'notes ${e.key}',
      hit: hit,
      cracked: hit.ok,
      actor: 'buyer JWT',
      pre: 'mesma classe denylist gap',
      repro: 'POST notes=${e.key}',
      severity: 'P2',
      expected: 'notes_forbidden',
    );
  }

  await c.dumpAll('pass2.json');
  stdout.writeln(
    'PASS2 done findings=${c.findings.length} blocked=${c.blocked.length}',
  );
}
